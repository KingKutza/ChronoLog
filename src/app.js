import { ChronologEngine } from "./engine.js";
import { coordinateLawError, displayLaw, invalidateCoordinateLaws } from "./coordinate-law.js";
import { CommandHistory, createEmptyWorkspaceDocument, validateDocument } from "./model.js";
import { calendarFrames } from "./projections.js";
import { ViewSession, sanitizeSessionParameters } from "./session.js";
import { JournalStore, parseDocument } from "./store.js";
import { THEME_PRESETS } from "./visual-language.js";
import { createTransactions } from "./ui/transactions.js";
import { SESSION_STORAGE_KEY, createWorkspace } from "./ui/workspace.js";
import { createDock } from "./ui/dock.js";
import { createInspector } from "./ui/inspector.js";
import { createRoster } from "./ui/roster.js";
import { createFramesPanel } from "./ui/frames-panel.js";
import { applyTheme, createToolbar, storedTheme } from "./ui/toolbar.js";
import { createDragController } from "./ui/drag.js";
import { createTodoCapture } from "./ui/todo-capture.js";
import { createCalendarSyncPanel } from "./ui/calendar-sync-panel.js";

// The bootstrap: construct the document/session/store/history, wire every
// UI module onto the shared `app` object (the live document/engine/session/
// history/store plus a small bag of transient view state), and kick the
// first render. Every module receives `app` explicitly and reads its
// current fields at call time — `app.chronolog`/`app.engine`/`app.history`
// are reassigned whenever the workspace document is replaced, so nothing
// here (or in the modules) may cache them in a closure.
const byId = (id) => document.getElementById(id);
const projection = byId("projection");
const minimap = byId("minimap");
const toastNode = byId("toast");
const lensControls = byId("lens-controls");
const dockDom = {
  root: byId("app"),
  dock: byId("dock"),
  resize: byId("dock-resize"),
  rail: byId("dock-rail"),
  viewport: byId("dock-viewport"),
  strip: byId("dock-strip")
};
function workspaceTarget() {
  return {
    api: "/api",
    filename: "chronolog.chronolog"
  };
}

const WORKSPACE_TARGET = workspaceTarget();
const LOCAL_WORKSPACE_TARGET = /^https?:$/.test(location.protocol) ? WORKSPACE_TARGET : {};
const WORKSPACE_DOCUMENT_URL = `${WORKSPACE_TARGET.api}/document`;

function storedSession() {
  try {
    return JSON.parse(localStorage.getItem(SESSION_STORAGE_KEY) || "{}");
  } catch {
    return {};
  }
}

applyTheme({ ...THEME_PRESETS.paper, ...storedTheme() });

const app = {};
app.chronolog = createEmptyWorkspaceDocument();
app.engine = new ChronologEngine(app.chronolog);
// Re-index the engine against a document mid-transaction. The series convergence
// invariant (src/ui/transactions.js -> convergeSeries) has to compare a just-mutated
// occurrence against what its series projects, and stale indices would answer for
// the document as it was before the edit. Reuses the one engine rather than building
// a throwaway, because the post-change render path calls setDocument again anyway.
app.refreshEngine = (documentValue) => {
  invalidateCoordinateLaws(documentValue || app.chronolog);
  app.engine.setDocument(documentValue || app.chronolog);
  return app.engine;
};
const initialFrame = calendarFrames(app.chronolog)[0]?.id || "";
app.session = new ViewSession({
  activeFrame: initialFrame,
  projection: "calendar",
  scale: 1,
  radialMode: "spiral",
  ...storedSession(),
  ...sanitizeSessionParameters(new URLSearchParams(location.search), app.chronolog)
});
app.viewScroll = new Map();
app.pendingIntimateRebase = null;
app.pendingIntimateZoom = null;
app.intimateScrollGuard = 0;
app.documentLoading = true;
app.framesReturnTarget = null;
app.reportedLawError = null;

let toastTimer = null;
function toast(message, error = false) {
  clearTimeout(toastTimer);
  toastNode.textContent = message;
  toastNode.classList.toggle("error", error);
  toastNode.classList.add("show");
  toastTimer = setTimeout(() => toastNode.classList.remove("show"), 3600);
}
app.toast = toast;

app.store = new JournalStore({
  // The save state is a colour-only indicator, so the message never becomes
  // text in the chrome — it stays on `title` and `aria-label`, which is where a
  // hover and a screen reader look for it.
  onStatus(status) {
    const node = byId("save-status");
    node.dataset.state = status.state;
    node.title = status.message;
    node.setAttribute("aria-label", `Save status: ${status.message}`);
  },
  // Another window's records just landed in this document. There is no
  // download/reload decision to make any more — the merge already happened at
  // record level, so the engine just needs rebuilding around the new state.
  onRebase(missed) {
    invalidateCoordinateLaws(app.chronolog);
    app.engine.setDocument(app.chronolog);
    reconcileSession();
    app.scheduleRender();
    if (missed.length) app.toast(`Merged ${missed.length} edit${missed.length === 1 ? "" : "s"} from another window.`);
  }
});
app.store.attach(app.chronolog, WORKSPACE_TARGET);

function makeHistory() {
  return new CommandHistory(app.chronolog, (change) => {
    // A committed change may have rewritten a frame's coordinate declaration,
    // and every memoized law derived from it is now a lie. Dropping the cache
    // before the engine re-indexes is what makes an applied ladder edit LIVE:
    // the owner's report was an editor that accepted "Hour:Day:23" and then
    // still drew 24 hours, because nothing downstream was told to look again.
    invalidateCoordinateLaws(app.chronolog);
    if (change.frameOnly) app.engine.refreshFrame(change.frameOnly);
    else if (!change.viewOnly) app.engine.setDocument(app.chronolog, { preserveRecurrence: change.preserveRecurrence });
    reconcileSession();
    // Every committed change reports the records it touched. The store throws
    // if a change arrives without ops, which is the assertion that keeps new
    // mutation paths from quietly bypassing the journal.
    app.store.collect(change.label, change.ops);
    app.scheduleRender();
    if (change.historyLimited) {
      app.toast("Change applied, but this large operation was not kept in undo history.");
    }
  });
}

app.history = makeHistory();

function replaceDocument(next, storageTarget = {}) {
  app.clearProvisionalDraft();
  invalidateCoordinateLaws(app.chronolog);
  app.chronolog = next;
  app.engine = new ChronologEngine(app.chronolog);
  app.history = makeHistory();
  app.store.attach(app.chronolog, storageTarget);
  // Opening a different document is the one moment every card is meaningless at
  // once: each one edits a record from the document being replaced. This is the
  // user's own explicit act, not a stage interaction, so emptying the dock here
  // does not violate the never-close-on-stage rule.
  app.closeAllDockCards();
  reconcileSession();
  app.scheduleRender();
}
app.replaceDocument = replaceDocument;

function reconcileSession() {
  const leadingFrame = app.chronolog.frames[app.session.activeFrame]
    ? app.session.activeFrame
    : calendarFrames(app.chronolog)[0]?.id || "";
  app.session.setLeadingFrame(leadingFrame);
  // The primary frame owns the coordinate law for display (src/frame-selection.js),
  // so reassigning the primary or editing its declaration re-derives every view
  // bound that depends on it. An unresolvable declaration is reported rather
  // than swallowed -- an unknown transition string must reach the author.
  app.session.setCoordinateLaw(displayLaw(app.chronolog, app.session));
  const lawError = leadingFrame ? coordinateLawError(app.chronolog, leadingFrame) : null;
  if (lawError && lawError !== app.reportedLawError) app.toast(lawError, true);
  app.reportedLawError = lawError;
  // One-time bridge off a document that still carries the retired
  // frames[leading].display.overlays field (see session.js's
  // seedOverlaysOnce) — a no-op once the session has its own companions,
  // including "the user cleared them all."
  app.session.seedOverlaysOnce(app.chronolog);
  app.reconcileRadialCycle();
  const open = app.session.inspector;
  if (!open?.id) return;
  const pool = open.type === "event"
    ? app.chronolog.events
    : open.type === "frame"
      ? app.chronolog.frames
      : app.chronolog.patterns;
  if (!pool[open.id]) app.closeInspector();
}

Object.assign(app, createTransactions(app));
Object.assign(app, createWorkspace(app, { projection, minimap }));
// The dock is wired before every module that opens a card into it, because those
// modules call `app.openDockCard` at construction-time-plus-one and read it off
// the shared object rather than capturing it.
Object.assign(app, createDock(app, dockDom));
Object.assign(app, createInspector(app));
Object.assign(app, createRoster(app));
Object.assign(app, createFramesPanel(app));
Object.assign(app, createToolbar(app, { projection, lensControls, LOCAL_WORKSPACE_TARGET }));
Object.assign(app, createDragController(app, { projection, minimap }));
// The ToDo lenses' capture/toggle delegation -- listeners live here, not in
// the renderers, so a re-render never orphans a handler.
createTodoCapture(app, { projection });
createCalendarSyncPanel(app);

async function loadWorkspaceDocument() {
  app.store.status("loading", "Loading workspace document…");
  try {
    const response = await fetch(WORKSPACE_DOCUMENT_URL, { cache: "no-store" });
    if (response.status === 404) {
      // A data directory with no snapshot cannot be journaled onto, and the
      // server has no idea what an empty chronolog document looks like — that
      // is domain knowledge it deliberately lacks. So this window establishes
      // the first snapshot before any op is appended.
      app.store.attach(app.chronolog, WORKSPACE_TARGET);
      await app.store.uploadSnapshot();
      app.toast("No workspace document found; started a new chronolog.chronolog file.");
      return;
    }
    if (!response.ok) throw new Error(await response.text() || `Open returned ${response.status}`);
    const loadedName = response.headers.get("x-chronolog-file") || "chronolog.chronolog";
    // The server already replayed its journal, so this body is the current
    // materialized document and the sequence number it corresponds to.
    const repairs = [];
    replaceDocument(parseDocument(await response.text(), repairs), {
      ...WORKSPACE_TARGET,
      seq: Number(response.headers.get("x-chronolog-seq") || 0)
    });
    // A repair is a warning, never a failure: the document opened. Say what was
    // swept rather than letting it happen silently.
    if (repairs.length) app.toast(repairs.map((repair) => repair.message).join(" · "));
    else app.toast(`Auto-loaded ${loadedName}`);
  } catch (error) {
    app.store.attach(app.chronolog, LOCAL_WORKSPACE_TARGET);
    app.toast(`Workspace autoload unavailable: ${error.message}`, true);
  } finally {
    app.documentLoading = false;
  }
}

app.render();
await loadWorkspaceDocument();
const validation = validateDocument(app.chronolog);
if (!validation.valid) app.toast(validation.errors.join(" · "), true);
app.render();
