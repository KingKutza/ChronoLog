import assert from "node:assert/strict";
import test from "node:test";
import { createDock } from "../src/ui/dock.js";
import { createInspector } from "../src/ui/inspector.js";
import { createRoster } from "../src/ui/roster.js";
import { ViewSession } from "../src/session.js";
import { ChronologEngine } from "../src/engine.js";
import { renderMinimap, renderProjection } from "../src/projections.js";
import { addEvent, addRelation, durationMagnitude } from "../src/model.js";
import { createWorkspace } from "../src/ui/workspace.js";
import { daysFromCivil } from "../src/exact.js";
import { createStructuralDocument } from "./helpers/sample-document.js";

// Item #7 (8.19 field report): "When I add a frame by import while the frames
// dock is open it dose not add the frame as a selectable card there." The
// diagnosis: card refresh used to be a hand-maintained list of per-card calls
// in src/ui/workspace.js's render() -- one line for the roster cards, no line
// for the Frames browser, nothing to stop the next card author from forgetting
// one too. The fix makes registering a card's reactivity the same act as
// opening it: `openDockCard({ ..., refresh })` (src/ui/dock.js), walked in
// full by one `refreshDockCards()` the render loop calls once. These tests
// exercise that mechanism directly (this file), its wiring into the render
// loop (workspace.js), its wiring out of the generic Inspector opener
// (inspector.js), and one real production card (roster.js) living the whole
// scenario end to end: a record added to the document elsewhere becomes
// visible in an already-open card without the user closing and reopening it.

// Same minimal stub-DOM shape as test/dock-dom.test.js -- "good enough to run
// dock.js's real card lifecycle", nothing more.
function createStubDom() {
  const listeners = new Map();

  class StubElement {
    constructor(tag = "div") {
      this.tagName = tag.toUpperCase();
      this.children = [];
      this.parentElement = null;
      this.dataset = {};
      this.style = { values: new Map(), setProperty(name, value) { this.values.set(name, value); }, getPropertyValue(name) { return this.values.get(name) ?? ""; } };
      this.attributes = new Map();
      this.handlers = new Map();
      this.hidden = false;
      this.inert = false;
      this.textContent = "";
      this.className = "";
      this.rect = { left: 0, top: 0, width: 900, height: 600 };
    }
    append(...nodes) {
      for (const node of nodes) {
        if (node.parentElement) node.parentElement.children = node.parentElement.children.filter((child) => child !== node);
        node.parentElement = this;
        this.children.push(node);
      }
    }
    replaceChildren(...nodes) {
      for (const child of this.children) child.parentElement = null;
      this.children = [];
      this.append(...nodes);
    }
    remove() {
      if (!this.parentElement) return;
      this.parentElement.children = this.parentElement.children.filter((child) => child !== this);
      this.parentElement = null;
    }
    setAttribute(name, value) { this.attributes.set(name, String(value)); }
    getAttribute(name) { return this.attributes.get(name) ?? null; }
    addEventListener(type, handler) {
      if (!this.handlers.has(type)) this.handlers.set(type, []);
      this.handlers.get(type).push(handler);
    }
    dispatch(type, event = {}) {
      for (const handler of this.handlers.get(type) || []) handler({ preventDefault() {}, ...event });
    }
    getBoundingClientRect() { return this.rect; }
    descendants() { return this.children.flatMap((child) => [child, ...child.descendants()]); }
    matches(selector) { return String(this.className).split(/\s+/).includes(selector.replace(".", "")); }
    closest(selector) { let node = this; while (node) { if (node.matches(selector)) return node; node = node.parentElement; } return null; }
    querySelectorAll(selector) { const wanted = selector.replace(".", ""); return this.descendants().filter((node) => String(node.className).split(/\s+/).includes(wanted)); }
  }

  const root = new StubElement("main");
  const workspace = new StubElement("div");
  const dock = new StubElement("section");
  const resize = new StubElement("div");
  const rail = new StubElement("div");
  const viewport = new StubElement("div");
  const strip = new StubElement("div");
  root.append(workspace);
  workspace.append(dock);
  dock.append(resize, rail, viewport);
  viewport.append(strip);

  const elementsById = new Map();
  const documentStub = { createElement: (tag) => new StubElement(tag), getElementById: (id) => elementsById.get(id) || null };
  const windowStub = { addEventListener(type, handler) { if (!listeners.has(type)) listeners.set(type, []); listeners.get(type).push(handler); } };
  return { root, workspace, dock, resize, rail, viewport, strip, documentStub, windowStub, StubElement };
}

function dockHarness() {
  const stub = createStubDom();
  const previous = { document: globalThis.document, window: globalThis.window, requestAnimationFrame: globalThis.requestAnimationFrame };
  globalThis.document = stub.documentStub;
  globalThis.window = stub.windowStub;
  globalThis.requestAnimationFrame = (fn) => fn(0);
  const app = { session: new ViewSession({}), scheduleRender() {}, renders: 0 };
  const restore = () => Object.assign(globalThis, previous);
  const dock = createDock(app, { root: stub.root, dock: stub.dock, resize: stub.resize, rail: stub.rail, viewport: stub.viewport, strip: stub.strip });
  return { ...stub, app, dock, restore };
}

test("a card opened without a refresh handler is never touched by refreshDockCards", () => {
  const h = dockHarness();
  try {
    let liveCalls = 0;
    h.dock.openDockCard({ id: "live", title: "Live", body: new h.StubElement("div"), refresh: () => { liveCalls += 1; } });
    // No `refresh` at all -- if refreshDockCards ever called something here it
    // would have to call a function, and there isn't one to call. Opting out is
    // simply never registering, not a flag to check.
    h.dock.openDockCard({ id: "static", title: "Static", body: new h.StubElement("div") });
    h.dock.refreshDockCards();
    h.dock.refreshDockCards();
    assert.equal(liveCalls, 2, "the registered card was asked once per call");
  } finally {
    h.restore();
  }
});

test("refreshDockCards invokes every registered card's handler exactly once per call", () => {
  const h = dockHarness();
  try {
    const counts = { a: 0, b: 0, c: 0 };
    for (const id of ["a", "b", "c"]) {
      h.dock.openDockCard({ id, title: id, body: new h.StubElement("div"), refresh: () => { counts[id] += 1; } });
    }
    h.dock.refreshDockCards();
    assert.deepEqual(counts, { a: 1, b: 1, c: 1 });
    h.dock.refreshDockCards();
    assert.deepEqual(counts, { a: 2, b: 2, c: 2 }, "a second call reaches every card again, not just the newest one");
  } finally {
    h.restore();
  }
});

// The safety constraint: a card holding an in-progress edit is allowed to
// decline its own rebuild. The mechanism does not know or care why -- it just
// calls the handler and lets the handler decide, which is what lets the
// Frames browser's embedded frame editor and the object editor's provisional
// draft each make their own call (see src/ui/frames-panel.js's
// `refreshObjectBrowser` and the object editor's decision not to register a
// handler at all, described in the report).
test("a card's own handler may decline to rebuild itself while its input is in progress, and resumes once it is not", () => {
  const h = dockHarness();
  try {
    const store = { items: ["first"] };
    const input = { value: "unsaved text", focused: true };
    const list = new h.StubElement("div");
    const body = new h.StubElement("div");
    body.append(list);
    let paints = 0;
    const refresh = () => {
      if (input.focused) return; // declines while the user is mid-keystroke
      paints += 1;
      list.replaceChildren(...store.items.map((item) => { const row = new h.StubElement("span"); row.textContent = item; return row; }));
    };
    h.dock.openDockCard({ id: "panel:example", title: "Example", body, refresh });

    store.items.push("second"); // a record added elsewhere, e.g. an import
    h.dock.refreshDockCards();
    assert.equal(paints, 0, "declined while the input is focused");
    assert.deepEqual(list.children.map((n) => n.textContent), [], "and nothing was rebuilt out from under the input");

    input.focused = false; // the user moved on
    h.dock.refreshDockCards();
    assert.equal(paints, 1);
    assert.deepEqual(list.children.map((n) => n.textContent), ["first", "second"], "the deferred change is picked up on the next refresh");
    assert.equal(input.value, "unsaved text", "the unrelated input was never touched by any of this");
  } finally {
    h.restore();
  }
});

// The owner's exact case, generalized to the mechanism rather than one card:
// a record is added to the shared document by something other than the open
// card (an import, a sync pull, another card's edit), and the open card shows
// it without being closed and reopened. Before this fix there was no
// `refreshDockCards` to call this handler at all -- a card with no bespoke
// line hand-written into workspace.js's render() simply never ran again until
// its next open.
test("the owner's exact case: a record added to the document elsewhere appears in an open card without reopening it", () => {
  const h = dockHarness();
  try {
    const documentStore = { frames: [{ id: "calendar:existing", title: "Existing calendar" }] };
    const list = new h.StubElement("div");
    const paintRows = () => list.replaceChildren(...documentStore.frames.map((frame) => {
      const row = new h.StubElement("button");
      row.textContent = frame.title;
      row.dataset.frameId = frame.id;
      return row;
    }));
    paintRows();
    h.dock.openDockCard({ id: "panel:frames-browser", title: "Frames", body: list, refresh: paintRows });
    assert.equal(list.children.length, 1);

    // "Import a calendar" -- a frame lands in the document from somewhere that
    // is not this card at all.
    documentStore.frames.push({ id: "calendar:imported", title: "Imported calendar" });

    // This is exactly what the render loop now does once per render.
    h.dock.refreshDockCards();

    assert.equal(list.children.length, 2, "the imported frame is a row without the card being closed and reopened");
    assert.ok(list.children.some((row) => row.dataset.frameId === "calendar:imported"));
  } finally {
    h.restore();
  }
});

test("createInspector's openInspector threads a refresh handler straight to app.openDockCard", () => {
  const calls = [];
  const app = { openDockCard: (options) => calls.push(options), dockIsOpen: () => true };
  const inspector = createInspector(app);
  const body = {};
  const refresh = () => {};
  inspector.openInspector("Frames", body, "frames-browser", null, refresh);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].id, "panel:frames-browser");
  assert.equal(calls[0].body, body);
  assert.equal(calls[0].refresh, refresh, "the exact handler the caller supplied reaches the dock, unwrapped");
});

test("openInspector's refresh defaults to null, so a caller that never asks to stay live never gets called", () => {
  const calls = [];
  const app = { openDockCard: (options) => calls.push(options), dockIsOpen: () => true };
  const inspector = createInspector(app);
  inspector.openInspector("Event", {}, "object", "event:1");
  assert.equal(calls[0].refresh, null);
});

// A real production card, end to end: roster.js's own registered refresh
// handler (wired in by this fix) re-renders from `app.chronolog` -- the same
// object an ICS import mutates -- so a ToDo added after the card opened shows
// up the moment the mechanism calls the handler, not only if the card is
// closed and reopened. `app.openInspector` here stands in for the real
// inspector.js + dock.js pairing (already proven above); this test's job is
// roster.js's own contribution: a working, real handler.
test("a ToDo added to the document elsewhere shows up in an already-open roster card via its registered refresh", () => {
  const previousDocument = globalThis.document;
  class MiniNode {
    constructor(tag) {
      this.tagName = String(tag || "div").toUpperCase();
      this.attrs = new Map();
      this.children = [];
      this.parentElement = null;
      this.handlers = new Map();
      this.textContent = "";
    }
    get className() { return this.attrs.get("class") || ""; }
    set className(value) { this.attrs.set("class", value); }
    get dataset() {
      const data = {};
      for (const [key, value] of this.attrs) {
        if (!key.startsWith("data-")) continue;
        data[key.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = value;
      }
      return data;
    }
    setAttribute(name, value) { this.attrs.set(name, String(value)); }
    getAttribute(name) { return this.attrs.has(name) ? this.attrs.get(name) : null; }
    addEventListener(type, handler) { if (!this.handlers.has(type)) this.handlers.set(type, []); this.handlers.get(type).push(handler); }
    append(...nodes) { for (const node of nodes) { node.parentElement = this; this.children.push(node); } }
    replaceChildren(...nodes) { this.children = []; this.append(...nodes); }
    descendants() { return this.children.flatMap((child) => [child, ...child.descendants()]); }
    matchesSimple(selector) {
      const attrMatch = /^\[([a-zA-Z0-9_-]+)(?:="([^"]*)")?\]$/.exec(selector);
      if (attrMatch) {
        const [, name, value] = attrMatch;
        if (!this.attrs.has(name)) return false;
        return value === undefined || this.attrs.get(name) === value;
      }
      return false;
    }
    querySelector(selector) { return this.descendants().find((node) => node.matchesSimple(selector)) || null; }
    querySelectorAll(selector) { return this.descendants().filter((node) => node.matchesSimple(selector)); }
    get innerHTML() { return this._html || ""; }
    set innerHTML(value) {
      this._html = value;
      this.children = parseFragment(value);
      for (const child of this.children) child.parentElement = this;
    }
  }

  const VOID_TAGS = new Set(["input", "br", "img", "hr"]);
  function unescapeHTML(value) {
    return String(value).replace(/&quot;/g, '"').replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
  }
  function parseFragment(html) {
    const root = new MiniNode("root");
    const stack = [root];
    const tagRe = /<\/([a-zA-Z][a-zA-Z0-9-]*)>|<([a-zA-Z][a-zA-Z0-9-]*)([^>]*)>|([^<]+)/g;
    let match;
    while ((match = tagRe.exec(html))) {
      const [, closeTag, openTag, rawAttrs, text] = match;
      if (closeTag) {
        for (let i = stack.length - 1; i > 0; i--) {
          if (stack[i].tagName === closeTag.toUpperCase()) { stack.length = i; break; }
        }
      } else if (openTag) {
        const selfClose = /\/\s*$/.test(rawAttrs || "");
        const node = new MiniNode(openTag);
        const attrRe = /([a-zA-Z_:][-a-zA-Z0-9_:.]*)(?:\s*=\s*"([^"]*)")?/g;
        let attrMatch;
        while ((attrMatch = attrRe.exec((rawAttrs || "").replace(/\/\s*$/, "")))) {
          node.attrs.set(attrMatch[1], attrMatch[2] !== undefined ? unescapeHTML(attrMatch[2]) : "");
        }
        stack[stack.length - 1].append(node);
        if (!VOID_TAGS.has(openTag.toLowerCase()) && !selfClose) stack.push(node);
      } else if (text !== undefined && text.trim().length) {
        const t = new MiniNode("#text");
        t.textContent = unescapeHTML(text);
        stack[stack.length - 1].append(t);
      }
    }
    return root.children;
  }
  function textOf(node) {
    return node.descendants().filter((n) => n.tagName === "#TEXT").map((n) => n.textContent).join("");
  }

  globalThis.document = { createElement: (tag) => new MiniNode(tag) };
  try {
    const chronolog = createStructuralDocument();
    let cardBody = null;
    let capturedRefresh = null;
    const app = {
      chronolog,
      dockCardBody: () => cardBody,
      closeDockCard: () => {},
      createEventAt: () => {},
      openEventInspector: () => {},
      openInspector: (title, body, panel, key, refresh) => {
        cardBody = new MiniNode("div");
        cardBody.append(body);
        capturedRefresh = refresh;
      }
    };
    const roster = createRoster(app);
    roster.openRoster("todo");
    assert.equal(typeof capturedRefresh, "function", "the roster registered a refresh handler when it opened");
    assert.ok(!textOf(cardBody).includes("Freshly imported todo"));

    // Something other than this card adds a ToDo -- exactly what an ICS import
    // or another open editor does.
    const added = addEvent(chronolog, { traits: ["event", "task", "todo"], magnitudes: { duration: durationMagnitude("0") }, payload: { title: "Freshly imported todo" } });
    addRelation(chronolog, { type: "attachment", event: added.id, frame: "frame:wall-time", role: "observed", coordinate: { levels: [{ level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "19" }] } });

    capturedRefresh();

    assert.ok(textOf(cardBody).includes("Freshly imported todo"), "the card reflects the change without being closed and reopened");
  } finally {
    globalThis.document = previousDocument;
  }
});

// The render loop itself: `render()` calls the one registry function exactly
// once, rather than a hand-maintained list of per-card calls (the class of bug
// this item fixes). This runs the real renderer against a minimal document, so
// it also proves render() still completes -- refreshDockCards is not added at
// the cost of the projection.
test("the render loop asks the dock's card-refresh registry exactly once per render", () => {
  class StubElement {
    constructor(tag) {
      this.tagName = String(tag).toUpperCase();
      this.className = "";
      this.textContent = "";
      this.dataset = {};
      this.children = [];
      this.parentElement = null;
      this.clientHeight = 900;
      const node = this;
      this.style = { setProperty(name, value) { this[name] = String(value); }, getPropertyValue(name) { return this[name] ?? ""; } };
      this.classList = { add(cls) { node.className = node.className ? `${node.className} ${cls}` : cls; } };
    }
    append(...nodes) { for (const n of nodes) { n.parentElement = this; this.children.push(n); } }
    replaceChildren(...nodes) { this.children = []; this.append(...nodes); }
    setAttribute() {}
    getAttribute() { return null; }
    querySelector() { return null; }
  }
  const documentStub = { createElement: (tag) => new StubElement(tag), createElementNS: (_ns, tag) => new StubElement(tag) };
  const previousDocument = globalThis.document;
  globalThis.document = documentStub;
  try {
    const chronolog = createStructuralDocument();
    chronolog.frames["calendar:personal"] = {
      id: "calendar:personal", title: "Personal", traits: ["set", "calendar"], basis: "frame:wall-time", codec: { kind: "ics" }
    };
    const session = new ViewSession({
      projection: "calendar",
      scale: 0,
      activeFrame: "calendar:personal",
      intimateBack: 0,
      intimateForward: 0,
      focusDays: daysFromCivil(2026n, 8n, 19n).toString()
    });
    const engine = new ChronologEngine(chronolog);
    let refreshCalls = 0;
    const app = {
      chronolog,
      engine,
      session,
      documentLoading: false,
      viewScroll: new Map(),
      pendingIntimateRebase: null,
      pendingIntimateZoom: null,
      intimateScrollGuard: 0,
      reconcileRadialCycle() {},
      updateCalendarSelect() {},
      updateChrome() {},
      updateLensControls() {},
      refreshDockCards() { refreshCalls += 1; }
    };
    const projection = new StubElement("div");
    const minimap = new StubElement("div");
    const workspace = createWorkspace(app, { projection, minimap });
    void renderMinimap;
    void renderProjection;

    workspace.render();
    assert.equal(refreshCalls, 1);
    workspace.render();
    assert.equal(refreshCalls, 2, "every render asks again, not just the first");
  } finally {
    globalThis.document = previousDocument;
  }
});
