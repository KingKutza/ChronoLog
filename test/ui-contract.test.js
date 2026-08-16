import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

function cssBlock(css, selector) {
  const escaped = selector.replace(/[.#[\]"=-]/g, "\\$&").replace(/\n/g, "\\s*");
  const match = css.match(new RegExp(`(?:^|\\n)${escaped}\\s*\\{[^}]*\\}`));
  assert.ok(match, `expected a CSS block for ${selector}`);
  return match[0];
}

function sourceSlice(source, startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  assert.ok(start > -1, `expected source to contain ${startMarker}`);
  const end = endMarker ? source.indexOf(endMarker, start) : source.length;
  assert.ok(end > start, `expected ${endMarker} after ${startMarker}`);
  return source.slice(start, end);
}

test("application shell exposes seven explicit lenses with contextual window controls", async () => {
  const [html, css, app, projections] = await Promise.all([
    readFile("pocket-instrument.html", "utf8"),
    readFile("src/app.css", "utf8"),
    readFile("src/app.js", "utf8"),
    readFile("src/projections.js", "utf8")
  ]);
  assert.match(html, /id="lens-bar"/);
  assert.match(html, /id="lens-controls"/);
  for (const lens of ["intimate", "tactical", "strategic", "wall", "lines", "spiral", "radial"]) {
    assert.match(html, new RegExp(`data-lens="${lens}"`));
  }
  assert.match(html, /id="minimap"/);
  assert.match(cssBlock(css, "html,\nbody,\n#app"), /overflow: hidden/);
  const tactical = cssBlock(css, ".tactical-grid");
  assert.match(tactical, /var\(--columns, 7\)/);
  assert.match(tactical, /var\(--rows, 3\)/);
  const strategic = cssBlock(css, ".strategic-row");
  assert.match(strategic, /repeat\(31, minmax\(29px, 1fr\)\)/);
  assert.match(cssBlock(css, ".intimate-scroll"), /overflow: auto/);
  assert.match(app, /sharedFocus/);
  assert.match(app, /session\.projection === "radial"/);
  assert.match(app, /session\.setLens/);
  assert.match(app, /session\.tacticalRows/);
  assert.match(app, /session\.strategicMonths/);
  assert.match(projections, /radialPast/);
  assert.match(projections, /radial-event-arc/);
  assert.match(app, /SESSION_STORAGE_KEY/);
  assert.match(app, /localStorage\.setItem/);
});

test("event creation and dragging use the defined exact duration converter", async () => {
  const [app, model] = await Promise.all([
    readFile("src/app.js", "utf8"),
    readFile("src/model.js", "utf8")
  ]);
  assert.match(model, /export function durationMagnitudeDays/);
  assert.match(app, /durationMagnitudeDays\(event\?\.magnitudes\?\.duration\)/);
  assert.match(app, /durationMagnitudeDays\(chronolog\.events\[item\.dataset\.eventId\]/);
  assert.doesNotMatch(app, /\bmagnitudeDays\(/);
});

test("lens workspace uses a registry, persisted order, and a visible configuration entry point", async () => {
  const [html, app, session] = await Promise.all([
    readFile("pocket-instrument.html", "utf8"),
    readFile("src/app.js", "utf8"),
    readFile("src/session.js", "utf8")
  ]);
  assert.match(html, /id="lens-settings"/);
  assert.match(app, /function openLensWorkspace/);
  assert.match(app, /session\.configureLenses/);
  assert.match(session, /LENS_CATALOG/);
  assert.match(session, /availableLenses\(\)/);
});

test("save status remains a legible, accessible status badge", async () => {
  const [html, css, app] = await Promise.all([
    readFile("pocket-instrument.html", "utf8"),
    readFile("src/app.css", "utf8"),
    readFile("src/app.js", "utf8")
  ]);
  assert.match(html, /id="save-status"[^>]*role="status"/);
  assert.match(html, /id="save-status"[^>]*aria-live="polite"/);
  assert.match(html, /id="save-status"[^>]*aria-label="Save status"/);
  assert.match(html, /id="save-status"[^>]*title="Current save status"/);
  assert.match(html, /id="save-status"[^>]*>Saved<\/span>/);
  assert.doesNotMatch(css, /#save-status\s*\{[^}]*color:\s*transparent/);
  assert.doesNotMatch(css, /#save-status\s*\{[^}]*width:\s*19px/);
  const statusUpdate = sourceSlice(app, "onStatus(status)", "store.attach");
  assert.match(statusUpdate, /node\.dataset\.state = status\.state/);
  assert.match(statusUpdate, /node\.textContent = status\.message/);
});

test("workspace conflicts offer explicit download-or-reload recovery instead of last-write-wins", async () => {
  const [app, html, store] = await Promise.all([
    readFile("src/app.js", "utf8"),
    readFile("pocket-instrument.html", "utf8"),
    readFile("src/store.js", "utf8")
  ]);
  assert.match(html, /id="download-conflict"[^>]*disabled/);
  assert.match(html, /id="reload-latest"[^>]*disabled/);
  assert.match(app, /Downloaded your conflicting local copy/);
  assert.match(app, /store\.readRemote\(\)/);
  assert.match(store, /response\.status === 409/);
  assert.match(store, /local edits are safe/);
  assert.match(store, /"if-match"/);
});

test("primary toolbar exposes reversible history while document actions live in a named menu", async () => {
  const [html, css, app] = await Promise.all([
    readFile("pocket-instrument.html", "utf8"),
    readFile("src/app.css", "utf8"),
    readFile("src/app.js", "utf8")
  ]);
  const toolbar = sourceSlice(html, '<header id="hud"', '</header>');
  const documentMenu = sourceSlice(html, '<details id="document-menu">', '</details>');
  assert.match(toolbar, /class="history-controls" aria-label="Edit history"/);
  assert.match(toolbar, /id="undo"[^>]*title="Undo \(Ctrl\+Z\)"/);
  assert.match(toolbar, /id="redo"[^>]*title="Redo \(Ctrl\+Shift\+Z\)"/);
  assert.match(documentMenu, /<summary[^>]*>[\s\S]*responsive-label-long[^>]*>Document<\/span>[\s\S]*<\/summary>/);
  for (const id of ["open-document", "save-document", "save-as-document", "import-ics", "export-ics"]) {
    assert.match(documentMenu, new RegExp(`id="${id}"`));
  }
  assert.doesNotMatch(documentMenu, /id="undo"|id="redo"/);
  assert.match(css, /\.history-controls \{ display: inline-flex/);
  assert.match(app, /function confirmDocumentReplacement\(\)/);
  assert.match(app, /Unsaved changes in the current document are already recoverable/);
  assert.match(app, /function closeDocumentMenu\(\)/);
});

test("Intimate programmatic scrolling is guarded through the next animation frame", async () => {
  const app = await readFile("src/app.js", "utf8");
  assert.match(app, /let intimateScrollGuard = 0/);
  assert.match(app, /const scrollGuard = intimateProgrammaticScroll \? \+\+intimateScrollGuard : 0/);
  assert.match(app, /requestAnimationFrame\(\(\) => \{\s*if \(intimateScrollGuard === scrollGuard\) intimateScrollGuard = 0/);
  assert.match(app, /\|\| intimateScrollGuard\s*\|\| pendingIntimateRebase/);
});

test("Intimate rebases its finite rail synchronously and preserves one exact day of scroll", async () => {
  const [app, projections] = await Promise.all([
    readFile("src/app.js", "utf8"),
    readFile("src/projections.js", "utf8")
  ]);
  const rebase = sourceSlice(app, "function rebaseIntimateScroll", 'projection.addEventListener("scroll"');
  assert.match(rebase, /const dayPixels = hourPixels \* 24/);
  assert.match(rebase, /scroll\.scrollTop - direction \* dayPixels/);
  assert.match(rebase, /session\.move\(direction\)/);
  assert.match(rebase, /render\(\)/);
  assert.doesNotMatch(rebase, /scheduleRender\(\)/);
  assert.match(app, /rebaseIntimateScroll\(scroll, -1\)/);
  assert.match(app, /rebaseIntimateScroll\(scroll, 1\)/);
  assert.match(projections, /Math\.max\(3, Math\.ceil\(visibleHours \/ 24\) \+ 1\)/);
  assert.match(projections, /boundary \* 24 \* hourPixels/);
});

test("lens Options remains open when an option rerenders its controls", async () => {
  const app = await readFile("src/app.js", "utf8");
  assert.match(app, /const optionsWasOpen = previousLens === lens/);
  assert.match(app, /options\.open = optionsWasOpen/);
});

test("lens controls use an explicit accessible overflow menu instead of clipped horizontal controls", async () => {
  const [css, app] = await Promise.all([
    readFile("src/app.css", "utf8"),
    readFile("src/app.js", "utf8")
  ]);
  const updateControls = sourceSlice(app, "function updateLensControls", "function toast");
  assert.match(updateControls, /lens-control-overflow/);
  assert.match(updateControls, /primaryControlIndexes/);
  assert.match(updateControls, /lensControls\.append\(\.\.\.primaryControls, options, todayControl\)/);
  assert.match(cssBlock(css, "#lens-controls"), /overflow: visible/);
  assert.doesNotMatch(cssBlock(css, "#lens-controls"), /overflow-x: auto/);
  assert.match(cssBlock(css, ".lens-control-overflow > summary"), /cursor: pointer/);
  assert.match(css, /\.lens-readout\s*\{\s*min-width: 0;[\s\S]*?text-overflow: ellipsis/);
  const today = cssBlock(css, "#today");
  assert.doesNotMatch(today, /position: sticky/);
  assert.doesNotMatch(today, /margin-left: auto/);
  assert.match(today, /place-items: center/);
});

test("URL parameters pass through the sanitizer before reaching the session", async () => {
  const app = await readFile("src/app.js", "utf8");
  assert.match(app, /sanitizeSessionParameters\(new URLSearchParams\(location\.search\), chronolog\)/);
  assert.doesNotMatch(app, /Number\(initialParameters\.get\(/);
  assert.doesNotMatch(app, /activeFrame: initialParameters\.get\(/);
});

test("editing fields keep native text undo ahead of document undo", async () => {
  const app = await readFile("src/app.js", "utf8");
  const keydown = sourceSlice(app, 'window.addEventListener("keydown"', 'window.addEventListener("beforeunload"');
  const guard = keydown.indexOf("if (editing) return;");
  const undo = keydown.indexOf("history.undo()");
  assert.ok(guard > -1, "keydown handler must guard editing fields");
  assert.ok(undo > -1, "keydown handler must route document undo");
  assert.ok(guard < undo, "editing guard must run before the undo/redo branch");
});

test("history changes reconcile dangling inspector and frame state", async () => {
  const app = await readFile("src/app.js", "utf8");
  const historySource = sourceSlice(app, "function makeHistory", "function replaceDocument");
  assert.match(historySource, /reconcileSession\(\)/);
  const reconcile = sourceSlice(app, "function reconcileSession", "function context");
  assert.match(reconcile, /calendarFrames\(chronolog\)/);
  assert.match(reconcile, /closeInspector\(\)/);
});

test("an open Frames panel and every projection share the toolbar leading frame", async () => {
  const [app, projections] = await Promise.all([
    readFile("src/app.js", "utf8"),
    readFile("src/projections.js", "utf8")
  ]);
  const selection = sourceSlice(app, "function selectLeadingFrame", "function updateChrome");
  assert.match(selection, /session\.setLeadingFrame\(frameId\)/);
  assert.match(selection, /refreshFramesPanel\(\)/);
  assert.match(selection, /scheduleRender\(\)/);
  const toolbar = sourceSlice(app, 'byId("active-calendar").addEventListener', 'byId("shared-focus").addEventListener');
  assert.match(toolbar, /selectLeadingFrame\(event\.target\.value\)/);
  const viewCard = sourceSlice(app, "function frameViewCard", "function openObjectBrowser");
  assert.match(viewCard, /leadingSelect\.id = "frame-leading-select"/);
  assert.match(viewCard, /selectLeadingFrame\(leadingSelect\.value\)/);
  assert.match(viewCard, /const display = active\?\.display \|\| \{\}/);
  assert.match(viewCard, /const activeFrameId = session\.activeFrame/);
  assert.match(viewCard, /documentValue\.frames\[activeFrameId\]/);
  assert.match(viewCard, /target\.display = \{ \.\.\.\(target\.display \|\| \{\}\), overlays: \[\.\.\.overlays\] \}/);
  const refresh = sourceSlice(app, "function refreshFramesPanel", "function openStapleSuggestions");
  assert.match(refresh, /current\.replaceWith\(frameViewCard\(\)\)/);
  assert.doesNotMatch(app, /primeFrame/);
  assert.doesNotMatch(projections, /primeFrame/);
});

test("openInspector only accepts DOM nodes", async () => {
  const app = await readFile("src/app.js", "utf8");
  const inspectorSource = sourceSlice(app, "function openInspector", "function escapeHTML");
  assert.doesNotMatch(inspectorSource, /innerHTML/);
  assert.match(inspectorSource, /replaceChildren\(body\)/);
});

test("Frames triggers toggle one browser panel with accessible state and coherent focus return", async () => {
  const [html, app, css] = await Promise.all([
    readFile("pocket-instrument.html", "utf8"),
    readFile("src/app.js", "utf8"),
    readFile("src/app.css", "utf8")
  ]);
  assert.match(html, /id="new-frame"[^>]*aria-controls="inspector"[^>]*aria-expanded="false"/);
  assert.match(html, /id="manage-frames"[^>]*aria-controls="inspector"[^>]*aria-expanded="false"/);
  const framesToggle = sourceSlice(app, "function toggleFramesBrowser", 'byId("new-pattern")');
  assert.match(framesToggle, /inspector\.dataset\.panel === "frames-browser"/);
  assert.match(framesToggle, /closeInspector\(\)/);
  assert.match(framesToggle, /openObjectBrowser\("frame"\)/);
  assert.match(framesToggle, /toggleFramesBrowser\(returnTarget\)/);
  const dismissal = sourceSlice(app, "function dismissInspector", "function discardProvisionalDraft");
  assert.match(dismissal, /framesReturnTarget/);
  assert.match(dismissal, /document-menu/);
  const browser = sourceSlice(app, "function openObjectBrowser", "function openStapleSuggestions");
  assert.match(browser, /"frames-browser"/);
  assert.match(browser, /aria-expanded", "true"/);
  assert.match(browser, /search\.focus\(\{ preventScroll: true \}\)/);
  assert.doesNotMatch(browser, /scheduleRender\(\)/, "opening the drawer must not rerender or reset the projection");
  const inspector = cssBlock(css, "#inspector");
  assert.match(inspector, /position: absolute/);
  assert.match(inspector, /contain: layout paint/);
  assert.match(inspector, /will-change: transform/);
  const refresh = sourceSlice(app, "function refreshFramesPanel", "function openStapleSuggestions");
  assert.match(refresh, /dataset\.panel === "frames-browser"/);
  assert.doesNotMatch(app, /dataset\.objectBrowser/);
  const dismiss = sourceSlice(app, "function dismissInspector", "function resolveProvisionalDraft");
  assert.match(dismiss, /aria-expanded", "false"/);
  assert.match(dismiss, /returnTarget \|\| visibleToolbarTrigger \|\|/);
  const keydown = sourceSlice(app, 'window.addEventListener("keydown"', 'window.addEventListener("beforeunload"');
  assert.match(keydown, /event\.key === "Escape"/);
  assert.match(keydown, /closeInspector\(\)/);
});

test("pattern errors surface above chrome in every projection", async () => {
  const [css, projections] = await Promise.all([
    readFile("src/app.css", "utf8"),
    readFile("src/projections.js", "utf8")
  ]);
  const banner = cssBlock(css, ".projection-error");
  assert.match(banner, /z-index: 30/);
  assert.match(cssBlock(css, "#projection"), /position: relative/);
  const lines = sourceSlice(projections, "function renderLines", "function polar");
  assert.match(lines, /renderErrors\(target, \{ errors \}\)/);
});

test("navigation chrome never performs a second recurrence query", async () => {
  const projections = await readFile("src/projections.js", "utf8");
  const minimap = sourceSlice(projections, "export function renderMinimap", null);
  assert.doesNotMatch(minimap, /queryFacts\(/);
  assert.match(minimap, /indexedExplicitFacts/);
});

test("explicit rendered events carry drag placement data and reschedule through history", async () => {
  const [app, projections] = await Promise.all([
    readFile("src/app.js", "utf8"),
    readFile("src/projections.js", "utf8")
  ]);
  assert.match(projections, /dataset\.relationId/);
  assert.match(projections, /dataset\.factDay/);
  assert.match(app, /destinationForDrop/);
  assert.match(app, /history\.executeDelta\("Move event"/);
  assert.match(app, /const nextCoordinate = daysToCivilCoordinate\(destination\)/);
  assert.match(app, /relation\.coordinate = clone\(nextCoordinate\)/);
  assert.match(app, /"Move recurring occurrence",\s*\n\s*\(documentValue\) => applyMaterialization/);
  assert.match(app, /prepareMaterialization\(fact, nextCoordinate\)/);
  assert.match(app, /history\.executeDelta\(\s*\n\s*`Import/);
  assert.match(app, /intimate-day-column/);
  assert.match(app, /data-drop-start/);
});

test("ordinary event clicks are not captured as drags and active drags show a landing preview", async () => {
  const app = await readFile("src/app.js", "utf8");
  const pointerDown = sourceSlice(
    app,
    'projection.addEventListener("pointerdown", (event) => {',
    'projection.addEventListener("pointermove", (event) => {'
  );
  assert.doesNotMatch(pointerDown, /setPointerCapture/);
  const pointerMove = sourceSlice(
    app,
    'projection.addEventListener("pointermove", (event) => {',
    'projection.addEventListener("pointerup", (event) => {'
  );
  assert.match(pointerMove, /setPointerCapture/);
  assert.match(pointerMove, /queueDragPreview/);
  assert.match(app, /formatCivil\(daysToCivilCoordinate\(destination\), true\)/);
  assert.match(pointerDown, /if \(event\.shiftKey\) return/);
  assert.match(app, /!event\.shiftKey && event\.target\.closest/);
});

test("Intimate keeps included overlays out of base collision lanes and scrolls its guide with its grid", async () => {
  const [css, projections] = await Promise.all([
    readFile("src/app.css", "utf8"),
    readFile("src/projections.js", "utf8")
  ]);
  const intimate = sourceSlice(projections, "function renderIntimate", "function strategicPresentation");
  assert.match(intimate, /displayLayer !== "included"/);
  assert.match(intimate, /displayLayer === "included"/);
  assert.match(intimate, /included-event/);
  assert.match(intimate, /scroll\.append\(header, body\)/);
  assert.match(css, /\.intimate-header[^}]*position: sticky/s);
  assert.match(css, /\.intimate-all-day-lane/);
});

test("event creation and editing use scoped deltas and expose calendar-language fields", async () => {
  const app = await readFile("src/app.js", "utf8");
  const editor = sourceSlice(app, "function openEventInspector", "function frameForm");
  assert.match(editor, /executeEventChange\("Edit event"/);
  assert.match(editor, /executeEventChange\("Delete event"/);
  assert.doesNotMatch(editor, /history\.execute\(/);
  for (const label of ["Start date", "Start time", "Duration", "Units", "Calendar", "Repeats", "Ends after", "Location or meeting link", "Importance", "Visible in"]) {
    assert.match(editor, new RegExp(label));
  }
  assert.match(editor, /Create group/);
  assert.match(editor, /Weekdays \(Mon–Fri\)/);
  assert.match(editor, /const rrule = \{ \.\.\.\(existingPattern\?\.rrule \|\| \{\}\)/);
  assert.match(editor, /rrule\.BYDAY = "MO,TU,WE,TH,FR"/);
  const creator = sourceSlice(app, "function createEventAt", "let zoomWheel");
  assert.match(creator, /executeEventChange\("Create event"/);
  assert.doesNotMatch(app, /history\.execute\(/);
});

test("calendar lenses request overlaps, split duration spans, and radial keeps only unambiguous fixed cycles", async () => {
  const [app, projections, radial] = await Promise.all([
    readFile("src/app.js", "utf8"),
    readFile("src/projections.js", "utf8"),
    readFile("src/radial.js", "utf8")
  ]);
  assert.match(projections, /includeOverlaps: true/);
  assert.match(projections, /segmentStartMinute/);
  assert.match(projections, /segmentEndMinute/);
  for (const label of ["Day", "Work week", "Week"]) {
    assert.match(radial, new RegExp(`title: "${label.replace(/[()]/g, "\\$&")}`));
  }
  assert.match(app, /cyclePeriodHint\(frame\.period\)/);
  assert.match(app, /\(variable\)/);
});

test("lens rerenders preserve internal scroll and minimap range", async () => {
  const [app, projections] = await Promise.all([
    readFile("src/app.js", "utf8"),
    readFile("src/projections.js", "utf8")
  ]);
  assert.match(app, /viewScroll\.set/);
  for (const key of ["intimate", "strategic", "wall"]) {
    assert.match(projections, new RegExp(`dataset\\.scrollKey = "${key}"`));
  }
  const minimap = sourceSlice(projections, "export function renderMinimap", null);
  assert.match(minimap, /session\.minimapRange/);
  assert.match(minimap, /previous\.start/);
});

test("Lines uses the active leading calendar and explicitly selected companions", async () => {
  const projections = await readFile("src/projections.js", "utf8");
  const lines = sourceSlice(projections, "function renderSimpleLines", "function polar");
  assert.match(lines, /Prime/);
  assert.match(lines, /lineFramePlan\(context\.document, context\.session\.activeFrame\)/);
  assert.match(lines, /staple/);
  assert.match(lines, /Math\.sin\(Math\.PI \* p\)/);
  assert.match(lines, /dataset\.linesState/);
  assert.match(lines, /Loading timeline data/);
  assert.match(lines, /No events in this window/);
  assert.match(lines, /context\.session\.window\(\)/);
  assert.match(lines, /bindFact\(dot, fact\)/);
  assert.doesNotMatch(lines, /context\.document\s*=/);
});

test("workspace documents use a custom extension with autoload and attached autosave", async () => {
  const [html, app, store, server, ignore] = await Promise.all([
    readFile("pocket-instrument.html", "utf8"),
    readFile("src/app.js", "utf8"),
    readFile("src/store.js", "utf8"),
    readFile("tools/serve.js", "utf8"),
    readFile(".gitignore", "utf8")
  ]);
  assert.match(html, /accept="\.chronolog/);
  assert.match(ignore, /\*\.chronolog/);
  assert.match(app, /loadWorkspaceDocument/);
  assert.match(app, /remoteUrl: "\/api\/document"/);
  assert.match(store, /application\/x-chronolog/);
  assert.match(server, /request\.method === "PUT"/);
});

test("frame manager exposes contextual calendar inclusion, group visibility, strategic priority, and frame editing", async () => {
  const app = await readFile("src/app.js", "utf8");
  const manager = sourceSlice(app, "function frameForm(frame", "function openFrameInspector");
  for (const phrase of ["Frame type", "Strategic", "Promote to name", "Duplicate", "Remove"]) {
    assert.match(manager, new RegExp(phrase));
  }
  for (const phrase of ["Fixed calendar structure", "Use a regular unit hierarchy", "Smallest unit length in Earth days"]) {
    assert.match(manager, new RegExp(phrase));
  }
  assert.match(manager, /Epoch in Earth days/);
  const browser = sourceSlice(app, "function openObjectBrowser", "function openStapleSuggestions");
  const viewCard = sourceSlice(app, "function frameViewCard", "function openObjectBrowser");
  assert.match(browser, /Current lens/);
  assert.match(viewCard, /Shown with/);
  assert.match(viewCard, /Include calendars and lines/);
  assert.match(viewCard, /Automatic/);
  assert.match(viewCard, /Strategic: promote/);
  assert.doesNotMatch(viewCard, /Layer mode/);
});

test("empty drag creates an interval, shift-drag pans, and provisional drafts resolve transactionally", async () => {
  const app = await readFile("src/app.js", "utf8");
  assert.match(app, /pan: event\.shiftKey/);
  assert.match(app, /createEventAt\(drag\.start, end\)/);
  assert.match(app, /Discard provisional draft/);
  assert.match(app, /id="cancel-draft"/);
  assert.match(app, /function discardProvisionalDraft/);
  assert.match(app, /function commitProvisionalDraft/);
  const close = sourceSlice(app, "function closeInspector", "function dismissInspector");
  assert.match(close, /discardProvisionalDraft\(\)/);
  assert.doesNotMatch(close, /requestSubmit/);
  assert.match(app, /document\.addEventListener\("pointerdown"/);
  assert.match(app, /focusInspectorEditor\(eventId\)/);
  assert.match(app, /store\.beginDeferred/);
  assert.match(app, /store\.endDeferred/);
  assert.match(app, /calendar-panning/);
  assert.match(app, /cell-preview/);
});

test("radial uses whole-cycle scrolling, populated calendar-group bands, collision lanes, and labels", async () => {
  const [app, projections] = await Promise.all([
    readFile("src/app.js", "utf8"),
    readFile("src/projections.js", "utf8")
  ]);
  assert.match(app, /session\.radialCycle\.mul\(steps\)/);
  assert.doesNotMatch(app, /session\.radialCycle\.mul\(steps \/ 7\)/);
  assert.match(projections, /frameId.*groupId/s);
  assert.match(projections, /laneEnds/);
  assert.match(projections, /radialEventLabel/);
  assert.match(projections, /radialGuideSettings/);
  assert.match(projections, /radial-noon-tick/);
  assert.match(app, /radialGuideSelect\(\n        "ticks"/);
  assert.match(app, /radialGuideSelect\(\n        "major marks"/);
  assert.match(projections, /dataset\.radialState/);
  assert.match(projections, /radial-empty-ring/);
  assert.match(projections, /Dense window · showing the first 350 events/);
});

test("Strategic turns dense windows into stable day topology instead of a moving truncation warning", async () => {
  const [projections, css] = await Promise.all([
    readFile("src/projections.js", "utf8"),
    readFile("src/app.css", "utf8")
  ]);
  const strategic = sourceSlice(projections, "function queryStrategicFacts", "function factsByDay");
  assert.match(strategic, /aggregateStrategicDays/);
  assert.match(strategic, /truncated: false/);
  const render = sourceSlice(projections, "function renderStrategic", "function renderCalendar");
  assert.match(render, /strategic-density-notice/);
  assert.match(render, /strategic-density-count/);
  assert.match(render, /densityByDay/);
  assert.match(cssBlock(css, ".strategic-density-notice"), /position: sticky/);
});

test("Radial guide controls expose Auto, document the tick cap, and keep major marks independent until invalid", async () => {
  const [app, css] = await Promise.all([
    readFile("src/app.js", "utf8"),
    readFile("src/app.css", "utf8")
  ]);
  assert.match(app, /const radialGuideSelect =/);
  assert.match(app, /\["0", "Auto"\]/);
  assert.match(app, /Manual tick counts are limited to 64/);
  assert.match(app, /normalizeRadialGuideValues\(\{ \.\.\.session, radialDivisions: value \}\)/);
  assert.doesNotMatch(app, /Number\(input\.value\) \|\| value/);
  assert.match(css, /\.radial-guide-control/);
  assert.match(css, /max-width: 100%/);
});

test("interaction refinements expose continuous intimate scroll, tactical shift scroll, delete, and frame-owned importance", async () => {
  const [app, projections, engine] = await Promise.all([
    readFile("src/app.js", "utf8"),
    readFile("src/projections.js", "utf8"),
    readFile("src/engine.js", "utf8")
  ]);
  assert.match(projections, /dataset\.bufferHours = String\(Number\(bufferDays\) \* 24\)/);
  assert.match(app, /scroll\.scrollTop = createDrag\.startScrollTop - dy/);
  assert.match(projections, /intimate-midnight-marker/);
  assert.match(app, /session\.move\(event\.shiftKey \? steps : steps \* session\.tacticalColumns\)/);
  assert.match(app, /event\.key === "Delete" && session\.inspector\?\.type === "event"/);
  assert.match(app, /\["importance", "\+ Importance"\]/);
  assert.match(app, /Override group color/);
  assert.match(projections, /other\.start < item\.end && other\.end > item\.start/);
  assert.match(projections, /frame\.display\?\.radialMinDays/);
  assert.match(engine, /eventFrames\(eventId\)/);
});

test("Intimate zoom is anchored, accessible, persistent, and keeps multi-day hit geometry", async () => {
  const [app, projections, session] = await Promise.all([
    readFile("src/app.js", "utf8"),
    readFile("src/projections.js", "utf8"),
    readFile("src/session.js", "utf8")
  ]);
  assert.match(session, /intimateHourPixels: this\.intimateHourPixels/);
  assert.match(session, /INTIMATE_HOUR_PIXELS_MIN = 8/);
  assert.match(session, /INTIMATE_HOUR_PIXELS_MAX = 144/);
  assert.match(projections, /Math\.ceil\(visibleHours \/ 24\)/);
  assert.match(projections, /for \(let boundary = 1; boundary < railDays; boundary \+= 1\)/);
  assert.match(projections, /dataset\.timelineStart = \(day - bufferDays\)\.toString\(\)/);
  const zoom = sourceSlice(app, "function prepareIntimateZoom", "function adjustWindow");
  assert.match(zoom, /localHour/);
  assert.match(zoom, /scroll\.scrollTop \+ offset - headerPixels/);
  assert.match(zoom, /session\.setIntimateHourPixels\(value\)/);
  assert.match(app, /event\.clientY - scroll\.getBoundingClientRect\(\)\.top/);
  assert.match(app, /aria-label", "Zoom Intimate out"/);
  assert.match(app, /aria-label", "Zoom Intimate in"/);
  assert.match(app, /Center Intimate on today and now/);
  assert.match(app, /cell\.dataset\.timelineStart/);
  assert.match(app, /cell\.dataset\.timelineHours/);
});

test("continuous-time chrome and recurrence exceptions retain their governing context", async () => {
  const [html, app, css, projections] = await Promise.all([
    readFile("pocket-instrument.html", "utf8"),
    readFile("src/app.js", "utf8"),
    readFile("src/app.css", "utf8"),
    readFile("src/projections.js", "utf8")
  ]);
  assert.match(app, /originalCoordinate: clone\(fact\.relation\.coordinate\)/);
  assert.match(app, /chronolog\.frames\[relation\.frame\]\?\.traits\.includes\("group"\)/);
  assert.match(app, /Restore recurring occurrence/);
  assert.match(app, /animateRadialWheel/);
  assert.match(app, /name="frameLenses"/);
  assert.match(projections, /MINIMAP_FACT_LIMIT = 1200/);
  assert.match(projections, /MINIMAP_EXACT_MARK_LIMIT = 280/);
  assert.match(projections, /minimap-density-topology/);
  assert.match(projections, /minimap-exact-mark/);
  assert.match(projections, /Topology sampled from first/);
  assert.match(projections, /const kernel = \[0\.18, 0\.55, 1, 0\.55, 0\.18\]/);
  assert.match(css, /\.minimap-density-topology/);
  assert.match(css, /\.minimap-exact-mark/);
  assert.match(projections, /minimap-now-line/);
  assert.match(projections, /radial-now-line/);
  assert.match(cssBlock(css, "#minimap"), /left: calc\(var\(--workspace-control-edge\) \+ var\(--workspace-inner-half\)\)/);
  assert.match(html, /class="chronolog-mark"/);
  assert.match(html, /id="theme-settings"/);
});

test("Frames can author finite observed boundary calendars without raw JSON", async () => {
  const [app, css, fixture] = await Promise.all([
    readFile("src/app.js", "utf8"),
    readFile("src/app.css", "utf8"),
    readFile("fixtures/observed-boundary-calendar.json", "utf8")
  ]);
  const boundary = JSON.parse(fixture);
  assert.equal(boundary.boundaries.length, 3);
  assert.match(app, /Observed boundary series/);
  assert.match(app, /name="useObservedCalendar"/);
  assert.match(app, /data-add-observed-boundary/);
  assert.match(app, /data-import-observed-boundaries/);
  assert.match(app, /data-move-observed-up/);
  assert.match(app, /data-remove-observed-boundary/);
  assert.match(app, /validateEventDefinedBoundaryDraft/);
  assert.match(app, /strictly increasing order/);
  assert.match(app, /never averages, fills gaps, or extrapolates/);
  assert.match(app, /kind: "event-defined"/);
  assert.match(css, /\.observed-boundary-row/);
});

test("ChronoLog identity is an original, accessible topology mark rather than a clock glyph", async () => {
  const [html, css, svg, identity] = await Promise.all([
    readFile("pocket-instrument.html", "utf8"),
    readFile("src/app.css", "utf8"),
    readFile("assets/chronolog-mark.svg", "utf8"),
    readFile("docs/identity.md", "utf8")
  ]);
  assert.match(html, /rel="icon" href="\.\/assets\/chronolog-mark\.svg"/);
  assert.match(html, /aria-label="ChronoLog: a timeline instrument"/);
  assert.match(html, /chronolog-mark__frame--primary/);
  assert.match(html, /chronolog-mark__frame--secondary/);
  assert.match(html, /chronolog-mark__staple/);
  assert.match(html, /chronolog-mark__join/);
  assert.match(html, /<title id="chronolog-mark-title">Interlocking timeline frames joined by a staple<\/title>/);
  assert.match(cssBlock(css, ".chronolog-mark"), /color: var\(--ink\)/);
  assert.match(cssBlock(css, ".chronolog-mark__join"), /fill: var\(--accent\)/);
  assert.match(svg, /Two interlocking timeline frames joined by a central staple/);
  assert.match(svg, /<title id="title">ChronoLog mark<\/title>/);
  assert.match(identity, /original, repository-native SVG/);
  assert.match(identity, /not a clock face, calendar\s+page, or generic checkmark/);
});
