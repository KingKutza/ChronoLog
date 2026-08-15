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

test("Frames button toggles its browser panel with accessible state and preserves panel closing controls", async () => {
  const [html, app] = await Promise.all([
    readFile("pocket-instrument.html", "utf8"),
    readFile("src/app.js", "utf8")
  ]);
  assert.match(html, /id="new-frame"[^>]*aria-controls="inspector"[^>]*aria-expanded="false"/);
  const framesButton = sourceSlice(app, 'byId("new-frame").addEventListener', 'byId("new-pattern")');
  assert.match(framesButton, /inspector\.dataset\.panel === "frames-browser"/);
  assert.match(framesButton, /closeInspector\(\)/);
  assert.match(framesButton, /openObjectBrowser\("frame"\)/);
  const browser = sourceSlice(app, "function openObjectBrowser", "function openStapleSuggestions");
  assert.match(browser, /"frames-browser"/);
  assert.match(browser, /aria-expanded", "true"/);
  assert.match(browser, /search\.focus\(\)/);
  const refresh = sourceSlice(app, "function refreshFramesPanel", "function openStapleSuggestions");
  assert.match(refresh, /dataset\.panel === "frames-browser"/);
  assert.doesNotMatch(app, /dataset\.objectBrowser/);
  const dismiss = sourceSlice(app, "function dismissInspector", "function resolveProvisionalDraft");
  assert.match(dismiss, /aria-expanded", "false"/);
  assert.match(dismiss, /new-frame"\)\.focus\(\)/);
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
  const browser = sourceSlice(app, "function openObjectBrowser", "function openStapleSuggestions");
  const viewCard = sourceSlice(app, "function frameViewCard", "function openObjectBrowser");
  assert.match(browser, /Current lens/);
  assert.match(viewCard, /Shown with/);
  assert.match(viewCard, /Include calendars and lines/);
  assert.match(viewCard, /Automatic/);
  assert.match(viewCard, /Strategic: promote/);
  assert.doesNotMatch(viewCard, /Layer mode/);
});

test("empty drag creates an interval, shift-drag pans, and untouched drafts are discarded", async () => {
  const app = await readFile("src/app.js", "utf8");
  assert.match(app, /pan: event\.shiftKey/);
  assert.match(app, /createEventAt\(drag\.start, end\)/);
  assert.match(app, /Discard empty draft/);
  assert.match(app, /provisionalEvent\.form\?\.requestSubmit/);
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
  assert.match(app, /ticks \(0 auto\)/);
  assert.match(app, /bold every \(0 auto\)/);
  assert.match(projections, /dataset\.radialState/);
  assert.match(projections, /radial-empty-ring/);
  assert.match(projections, /Dense window · showing the first 350 events/);
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
  assert.match(projections, /Math\.ceil\(visibleHours \/ 48\)/);
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
  assert.match(projections, /minimap-density-layer/);
  assert.match(projections, /minimap-now-line/);
  assert.match(projections, /radial-now-line/);
  assert.match(css, /left: calc\(33\.333% \+ 6px\)/);
  assert.match(html, /class="chronolog-mark"/);
  assert.match(html, /id="theme-settings"/);
});
