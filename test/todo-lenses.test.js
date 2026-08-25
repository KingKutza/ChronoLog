// The ToDo lens layer: two catalog lenses (List, Board) that independently
// project the same data, the quick-capture grammar, the grouping math, and
// the cross-lens state/falloff stamps the seven time lenses carry. The
// Spiral/Radial precedent governs throughout: no shared section model, only
// the data layer.
import assert from "node:assert/strict";
import test from "node:test";
import { CommandHistory, addEvent, addRelation, durationMagnitude } from "../src/model.js";
import { DEFAULT_LENS_ORDER, LENS_CATALOG, ViewSession, normalizeLensWorkspace } from "../src/session.js";
import { LIST_GROUPINGS, listSections, normalizeListGrouping } from "../src/list.js";
import { BOARD_GROUPINGS, boardColumns, normalizeBoardGrouping } from "../src/board.js";
import { parseQuickTodo, quickDateDays } from "../src/ui/todo-capture.js";
import { createTransactions } from "../src/ui/transactions.js";
import { ChronologEngine } from "../src/engine.js";
import { Rational, civilFromDays, daysFromCivil, nowDays } from "../src/exact.js";
import { createStructuralDocument } from "./helpers/sample-document.js";
import { findByClass, renderWithStubDom } from "./helpers/render-dom.js";

const SEVEN = ["intimate", "tactical", "strategic", "wall", "lines", "spiral", "radial"];

function civil(day, month = 8, year = 2026) {
  return {
    levels: [
      { level: "year", value: String(year) },
      { level: "month", value: String(month) },
      { level: "day", value: String(day) }
    ]
  };
}

// A calendar the engine can query (attachment relations against a frame
// carrying the "calendar" trait), plus a group, an importance frame, and the
// Done state frame in the ruled shape.
function todoDocument() {
  const document = createStructuralDocument();
  document.frames["calendar:personal"] = {
    id: "calendar:personal", title: "Personal", traits: ["set", "calendar"], basis: "frame:wall-time", codec: { kind: "ics" }
  };
  document.frames["calendar:work"] = {
    id: "calendar:work", title: "Work", traits: ["set", "calendar"], basis: "frame:wall-time", codec: { kind: "ics" }
  };
  document.frames["group:home"] = { id: "group:home", title: "Home", traits: ["set", "group"] };
  document.frames["frame:important"] = {
    id: "frame:important", title: "Important", traits: ["set", "group", "importance"], display: { importance: "important" }
  };
  document.frames["frame:state-done"] = { id: "frame:state-done", title: "Done", traits: ["set", "group", "state"] };
  return document;
}

function addTodo(document, id, title, { frame = "calendar:personal", coordinate = civil(18), payload = {} } = {}) {
  addEvent(document, {
    id,
    traits: ["event", "task", "todo"],
    magnitudes: { duration: durationMagnitude("0") },
    payload: { title, ...payload }
  });
  if (frame) {
    addRelation(document, {
      type: "attachment", role: "observed", event: id, frame, coordinate
    });
  }
  return id;
}

// ---------------------------------------------------------------------------
// Catalog and session
// ---------------------------------------------------------------------------

test("List and Board are two independent catalog entries with their own projections", () => {
  assert.equal(LENS_CATALOG.list.title, "List");
  assert.equal(LENS_CATALOG.list.projection, "list");
  assert.equal(LENS_CATALOG.board.title, "Board");
  assert.equal(LENS_CATALOG.board.projection, "board");
  // Owner-voiced one-liners, not capability jargon.
  assert.match(LENS_CATALOG.list.description, /Capture fast/i);
  assert.match(LENS_CATALOG.board.description, /Columns are the grouping/i);
  assert.deepEqual(DEFAULT_LENS_ORDER.slice(-2), ["list", "board"], "the pair joins at the catalog's end");
  assert.equal(DEFAULT_LENS_ORDER.length, 9);
});

test("the session reaches, names, and round-trips both ToDo lenses", () => {
  const session = new ViewSession({});
  session.setLens("list");
  assert.equal(session.projection, "list");
  assert.equal(session.currentLens(), "list");
  assert.ok(Number.isFinite(session.visibleSpan()), "a roster lens still reports one finite span");
  session.setLens("board");
  assert.equal(session.currentLens(), "board");
  session.listGrouping = "frame";
  session.boardGrouping = "container";
  const restored = new ViewSession(session.toJSON());
  assert.equal(restored.projection, "board");
  assert.equal(restored.currentLens(), "board");
  assert.equal(restored.listGrouping, "frame", "the grouping choice survives the round trip");
  assert.equal(restored.boardGrouping, "container");
  // An unknown grouping normalizes rather than poisoning the view.
  assert.equal(new ViewSession({ listGrouping: "bogus" }).listGrouping, "state");
  assert.equal(normalizeListGrouping("nonesuch"), "state");
  assert.equal(normalizeBoardGrouping("nonesuch"), "state");
  assert.deepEqual([...LIST_GROUPINGS], ["state", "importance", "container", "frame"]);
  assert.deepEqual([...BOARD_GROUPINGS], ["state", "importance", "container", "frame"]);
});

test("a persisted seven-lens workspace gains the ToDo lenses VISIBLE; a deliberately hidden lens stays hidden", () => {
  // The pre-ToDo persisted shape: seven lenses, wall hidden by the user.
  const persisted = { lensOrder: [...SEVEN], enabledLenses: SEVEN.filter((lens) => lens !== "wall") };
  const session = new ViewSession(persisted);
  assert.ok(session.lensOrder.includes("list") && session.lensOrder.includes("board"), "appended to the order");
  assert.ok(session.enabledLenses.includes("list") && session.enabledLenses.includes("board"),
    "a genuinely new lens is visible to existing users, not born hidden");
  assert.ok(!session.enabledLenses.includes("wall"), "the user's own hiding of wall is untouched");

  // Once the order knows them, hiding one is an ordinary user choice that
  // survives every later restore.
  session.configureLenses({ enabledLenses: session.enabledLenses.filter((lens) => lens !== "board") });
  const restored = new ViewSession(session.toJSON());
  assert.ok(!restored.enabledLenses.includes("board"), "known-but-hidden keeps current behavior");
  assert.ok(restored.lensOrder.includes("board"), "and stays reachable from the drop");

  // Live reconfiguration never migrates -- only the persisted path does.
  const live = normalizeLensWorkspace({ lensOrder: [...SEVEN], enabledLenses: ["lines"] });
  assert.deepEqual(live.enabledLenses, ["lines"]);
});

// ---------------------------------------------------------------------------
// The quick-capture grammar (provisional, pending Don's delimiter vocabulary)
// ---------------------------------------------------------------------------

test("parseQuickTodo: #group and @date tokens and the > note split, order-free, none required", () => {
  assert.deepEqual(parseQuickTodo("Call the vet #home @tomorrow > ask about shots"),
    { title: "Call the vet", group: "home", date: "tomorrow", note: "ask about shots" });
  assert.deepEqual(parseQuickTodo("#home Call the vet"),
    { title: "Call the vet", group: "home", date: "", note: "" });
  assert.deepEqual(parseQuickTodo("Water the plants"),
    { title: "Water the plants", group: "", date: "", note: "" });
  // First token of each kind wins; a second reads as title text.
  assert.deepEqual(parseQuickTodo("#a #b thing"), { title: "#b thing", group: "a", date: "", note: "" });
  // A note can itself contain the delimiter.
  assert.equal(parseQuickTodo("t > a > b").note, "a > b");
  // No title, no todo -- a bare token line creates nothing.
  assert.equal(parseQuickTodo("#home"), null);
  assert.equal(parseQuickTodo("   "), null);
  assert.equal(parseQuickTodo(""), null);
});

test("quickDateDays resolves the small date vocabulary exactly, and refuses what it cannot read", () => {
  const today = daysFromCivil(2026n, 8n, 25n);
  assert.equal(quickDateDays("today", today).toJSON(), new Rational(today).toJSON());
  assert.equal(quickDateDays("tomorrow", today).toJSON(), new Rational(today + 1n).toJSON());
  assert.equal(quickDateDays("+3", today).toJSON(), new Rational(today + 3n).toJSON());
  assert.equal(quickDateDays("+10d", today).toJSON(), new Rational(today + 10n).toJSON());
  assert.equal(quickDateDays("2026-09-01", today).toJSON(), new Rational(daysFromCivil(2026n, 9n, 1n)).toJSON());
  assert.equal(quickDateDays("9/1", today).toJSON(), new Rational(daysFromCivil(2026n, 9n, 1n)).toJSON(),
    "a yearless date reads in the current civil year");
  assert.equal(quickDateDays("9/1/2027", today).toJSON(), new Rational(daysFromCivil(2027n, 9n, 1n)).toJSON());
  assert.equal(quickDateDays("someday", today), null, "an unreadable date is refused, never guessed");
  assert.equal(quickDateDays("", today), null);
});

test("createQuickTodo writes the same records the create menu's ToDo writes, plus the authored extras, in one undo", () => {
  const document = todoDocument();
  const changes = [];
  const app = { chronolog: document, session: new ViewSession({ activeFrame: "calendar:personal" }) };
  app.history = new CommandHistory(document, (change) => changes.push(change));
  Object.assign(app, createTransactions(app));

  const day = new Rational(daysFromCivil(2026n, 9n, 1n));
  const result = app.createQuickTodo({ title: "Book the hall", group: "Home", dateDays: day, note: "ask for the deposit" });
  assert.ok(result.id, "the todo was created");
  assert.equal(result.group, "group:home", "the #group token matched the group frame by title");
  assert.equal(result.unmatchedGroup, null);
  const event = app.chronolog.events[result.id];
  assert.deepEqual(event.traits, ["event", "task", "todo"], "the todo traits, same as the create menu");
  assert.equal(event.payload.title, "Book the hall");
  assert.equal(event.payload.description, "ask for the deposit");
  const placement = Object.values(app.chronolog.relations).find((relation) =>
    relation.type === "attachment" && relation.event === result.id);
  assert.equal(placement.role, "observed", "a todo's relation role is observed");
  assert.equal(placement.frame, "calendar:personal");
  assert.equal(placement.coordinate.levels.find((level) => level.level === "day").value, "1",
    "the @date token became the staple's coordinate under the frame's own law");
  const membership = Object.values(app.chronolog.relations).find((relation) =>
    relation.type === "membership" && relation.member === result.id);
  assert.equal(membership.group, "group:home");

  assert.equal(app.history.undo(), true);
  assert.equal(app.chronolog.events[result.id], undefined, "one undo removes the whole capture");
  assert.ok(!Object.values(app.chronolog.relations).some((relation) =>
    relation.event === result.id || relation.member === result.id));

  // An unmatched group is reported, never minted: meaning is authored.
  const framesBefore = Object.keys(app.chronolog.frames).length;
  const missed = app.createQuickTodo({ title: "Someday idea", group: "Nonesuch" });
  assert.equal(missed.unmatchedGroup, "Nonesuch");
  assert.equal(Object.keys(app.chronolog.frames).length, framesBefore, "no frame was created from a typo");
  // Title-only: no date, no group -- the observed relation lands at now.
  assert.ok(Object.values(app.chronolog.relations).some((relation) =>
    relation.type === "attachment" && relation.event === missed.id && relation.coordinate));
});

// ---------------------------------------------------------------------------
// Grouping and population (pure lens math)
// ---------------------------------------------------------------------------

function groupedDocument() {
  const document = todoDocument();
  addTodo(document, "event:water", "Water the plants", { coordinate: civil(18) });
  addTodo(document, "event:hall", "Book the hall", { frame: "calendar:work", coordinate: civil(20) });
  addTodo(document, "event:someday", "Someday idea", { frame: null });
  addTodo(document, "event:filed", "File the report", { coordinate: civil(19) });
  addRelation(document, { type: "membership", group: "frame:state-done", member: "event:filed", provenance: { kind: "explicit" } });
  addRelation(document, { type: "membership", group: "group:home", member: "event:water" });
  addRelation(document, { type: "membership", group: "frame:important", member: "event:hall" });
  // A container parent with one open and one done child.
  addEvent(document, { id: "event:party", traits: ["event"], magnitudes: { duration: durationMagnitude("0") }, payload: { title: "The party" } });
  addRelation(document, { type: "contains", parent: "event:party", child: "event:water" });
  addRelation(document, { type: "contains", parent: "event:party", child: "event:filed" });
  return document;
}

test("population is frame selection, never a filter: state affiliation projects through the state frame", () => {
  const document = groupedDocument();
  const engine = new ChronologEngine(document);
  // Only the personal calendar selected: its open todos and the unplaced one
  // render; the work todo does not; the done todo projects through its state
  // frame, which is not selected.
  const personalOnly = listSections(document, engine, { grouping: "state", selectedFrames: ["calendar:personal"] });
  const titles = personalOnly.sections.flatMap((section) => section.entries.map((entry) => entry.title));
  assert.ok(titles.includes("Water the plants"));
  assert.ok(titles.includes("Someday idea"), "the null-frame todo always renders -- an unfiled capture is never invisible");
  assert.ok(!titles.includes("Book the hall"), "a todo on an unselected calendar does not project");
  assert.ok(!titles.includes("File the report"), "a done todo projects through the Done frame, which is deselected");

  // Selecting the Done state frame is the visibility control.
  const withDone = listSections(document, engine, { grouping: "state", selectedFrames: ["calendar:personal", "frame:state-done"] });
  const doneSection = withDone.sections.find((section) => section.key === "frame:state-done");
  assert.ok(doneSection, "the Done section appears once the frame is selected");
  assert.deepEqual(doneSection.entries.map((entry) => entry.title), ["File the report"]);
  assert.equal(doneSection.entries[0].state, "done");
  assert.equal(withDone.sections[0].title, "Open", "the null section leads");
});

test("each grouping supplies honest sections; empty groups are never emitted", () => {
  const document = groupedDocument();
  const engine = new ChronologEngine(document);
  const selectedFrames = ["calendar:personal", "calendar:work", "frame:state-done"];

  const byImportance = listSections(document, engine, { grouping: "importance", selectedFrames });
  assert.deepEqual(byImportance.sections.map((section) => section.title).slice(0, 1), ["No importance"]);
  const important = byImportance.sections.find((section) => section.key === "frame:important");
  assert.deepEqual(important.entries.map((entry) => entry.title), ["Book the hall"]);

  const byContainer = listSections(document, engine, { grouping: "container", selectedFrames });
  const party = byContainer.sections.find((section) => section.key === "event:party");
  assert.deepEqual(party.entries.map((entry) => entry.title).sort(), ["File the report", "Water the plants"]);
  assert.equal(party.meta.open, 1, "the container section's meta is the contains summary");
  assert.equal(party.meta.done, 1);

  const byFrame = listSections(document, engine, { grouping: "frame", selectedFrames });
  assert.equal(byFrame.sections[0].title, "No frame", "unaffiliated todos get their honest null-frame section, first");
  assert.deepEqual(byFrame.sections[0].entries.map((entry) => entry.title), ["Someday idea"]);
  assert.ok(byFrame.sections.some((section) => section.key === "calendar:personal"));
  assert.ok(byFrame.sections.some((section) => section.key === "calendar:work"));

  // Empty groups absent: group:home holds no visible todo in a selection
  // that hides the personal calendar, so no grouping ever emits it empty.
  for (const grouping of ["state", "importance", "container", "frame"]) {
    for (const section of listSections(document, engine, { grouping, selectedFrames }).sections) {
      assert.ok(section.entries.length > 0, `${grouping}: no empty section renders`);
    }
  }
});

test("boardColumns projects the same data by its own rules and never emits an empty column", () => {
  const document = groupedDocument();
  const engine = new ChronologEngine(document);
  const plan = boardColumns(document, engine, {
    grouping: "state",
    selectedFrames: ["calendar:personal", "calendar:work", "frame:state-done"]
  });
  assert.equal(plan.columns[0].title, "Open", "the null column leads");
  assert.ok(plan.columns.some((column) => column.key === "frame:state-done"));
  for (const column of plan.columns) assert.ok(column.entries.length > 0, "no empty column, ever");
  // Deselect the Done frame: the column disappears with its population --
  // frame selection is the visibility control, not a filter knob.
  const withoutDone = boardColumns(document, engine, {
    grouping: "state",
    selectedFrames: ["calendar:personal", "calendar:work"]
  });
  assert.ok(!withoutDone.columns.some((column) => column.key === "frame:state-done"));
});

test("sparse is the honest title-only predicate in the lens modules", () => {
  const document = todoDocument();
  addTodo(document, "event:bare", "Someday idea", { frame: null });
  addTodo(document, "event:described", "Call the vet", { frame: null, payload: { description: "ask about shots" } });
  const engine = new ChronologEngine(document);
  const sections = listSections(document, engine, { grouping: "state", selectedFrames: [] }).sections;
  const entries = new Map(sections.flatMap((section) => section.entries.map((entry) => [entry.id, entry])));
  assert.equal(entries.get("event:bare").state, "sparse");
  assert.equal(entries.get("event:described").state, null, "a description lifts sparse -- it is no longer title-only");
});

// ---------------------------------------------------------------------------
// Stub-DOM renders
// ---------------------------------------------------------------------------

function renderLens(document, session) {
  const context = { document, engine: new ChronologEngine(document), session };
  return renderWithStubDom(context);
}

test("the List lens renders sections, rows with state stamps, toggles, and the pinned capture input", () => {
  const document = groupedDocument();
  const session = new ViewSession({ projection: "list", activeFrame: "calendar:personal" });
  session.setFrameSelection(["calendar:personal", "frame:state-done"]);
  const target = renderLens(document, session);
  assert.equal(findByClass(target, "todo-quick-input").length, 1, "the quick-capture input is pinned at the top");
  const sections = findByClass(target, "todo-section");
  assert.ok(sections.length >= 2, "Open and Done sections rendered");
  for (const section of sections) {
    assert.ok(findByClass(section, "todo-row").length > 0, "no empty section renders");
  }
  const doneRow = findByClass(target, "todo-row").find((row) => row.dataset.todoState === "done");
  assert.ok(doneRow, "the done row carries its state stamp");
  const check = findByClass(doneRow, "todo-check")[0];
  assert.equal(check.checked, true);
  assert.equal(check.dataset.todoToggle, "event:filed", "the toggle names the object for the delegated write path");
  const open = findByClass(doneRow, "todo-open")[0];
  assert.equal(open.dataset.eventId, "event:filed", "rows open through the same event-id grammar as every lens");
});

test("the List lens's standard capture row renders its three fields once expanded -- never a dock card", () => {
  const document = todoDocument();
  const session = new ViewSession({ projection: "list", activeFrame: "calendar:personal" });
  session.todoCapture = { text: "Call the vet", expanded: true, group: "", date: "", note: "", focus: "group" };
  const target = renderLens(document, session);
  const fields = findByClass(target, "todo-capture-field");
  assert.equal(fields.length, 3, "group, date, and note fields");
  assert.equal(findByClass(target, "todo-quick-input")[0].value, "Call the vet", "mid-typing text survives a render");
});

test("the Board lens renders one column per non-empty group, horizontally scrollable, cards stamped", () => {
  const document = groupedDocument();
  const session = new ViewSession({ projection: "board", activeFrame: "calendar:personal" });
  session.setFrameSelection(["calendar:personal", "calendar:work", "frame:state-done"]);
  const target = renderLens(document, session);
  const columns = findByClass(target, "todo-column");
  assert.ok(columns.length >= 2);
  for (const column of columns) {
    assert.ok(findByClass(column, "todo-card").length > 0, "an empty group renders no column at all");
  }
  const doneCard = findByClass(target, "todo-card").find((card) => card.dataset.todoState === "done");
  assert.ok(doneCard, "the done card carries its state stamp");
  assert.equal(findByClass(target, "todo-quick-input").length, 1, "Board captures too");
});

// ---------------------------------------------------------------------------
// The seven time lenses: state stamps, falloff, spectrum
// ---------------------------------------------------------------------------

test("Intimate stamps data-todo-state and the falloff ramp on task sigils", () => {
  const document = todoDocument();
  const oldDay = daysFromCivil(2020n, 1n, 1n);
  // Long past its home and unresolved: fades to the floor bucket. It carries
  // a description so it is open, not sparse.
  addTodo(document, "event:overdue", "Renew the parking permit", {
    coordinate: civil(1, 1, 2020), payload: { description: "at the office" }
  });
  // Title-only: sparse. Same day, so it renders in the same window.
  addTodo(document, "event:bare", "Someday idea", { coordinate: civil(1, 1, 2020) });
  // Done: state grammar speaks, falloff never does.
  addTodo(document, "event:done", "File the report", { coordinate: civil(1, 1, 2020) });
  addRelation(document, { type: "membership", group: "frame:state-done", member: "event:done", provenance: { kind: "explicit" } });
  const session = new ViewSession({
    projection: "calendar", scale: 0, activeFrame: "calendar:personal",
    intimateBack: 0, intimateForward: 0, focusDays: oldDay.toString()
  });
  const target = renderLens(document, session);
  const floats = findByClass(target, "float-event");
  const byTitle = (title) => floats.find((node) => node.children.some((child) => child.textContent?.includes(title)));
  const overdue = byTitle("Renew the parking permit");
  assert.ok(overdue, "the lapsed todo still renders at its historical staple when scrolled to");
  assert.equal(overdue.dataset.todoFalloff, "3", "years past its home, it sits at the falloff floor");
  assert.equal(overdue.dataset.todoState, undefined, "open todos carry no state stamp");
  const bare = byTitle("Someday idea");
  assert.equal(bare.dataset.todoState, "sparse");
  const done = byTitle("File the report");
  assert.equal(done.dataset.todoState, "done");
  assert.equal(done.dataset.todoFalloff, undefined, "done never fades -- its state grammar already says what it is");
  assert.match(done.attributes.get("aria-label"), /, done: /, "the aria label composes the state");
});

test("Tactical chips carry the state stamp, and an open future todo washes the spectrum now→staple", () => {
  const document = todoDocument();
  const today = nowDays().floor();
  const ahead = civilFromDays(today + 3n);
  addTodo(document, "event:ahead", "Book the hall", {
    coordinate: civil(Number(ahead.day), Number(ahead.month), Number(ahead.year)),
    payload: { description: "call first" }
  });
  const doneCivil = civilFromDays(today);
  addTodo(document, "event:done", "File the report", {
    coordinate: civil(Number(doneCivil.day), Number(doneCivil.month), Number(doneCivil.year))
  });
  addRelation(document, { type: "membership", group: "frame:state-done", member: "event:done", provenance: { kind: "explicit" } });
  const session = new ViewSession({
    projection: "calendar", scale: 1, activeFrame: "calendar:personal", focusDays: new Rational(today).toJSON()
  });
  const target = renderLens(document, session);
  const doneChip = findByClass(target, "event-chip").find((chip) => chip.dataset.todoState === "done");
  assert.ok(doneChip, "the done todo's chip is stamped");
  const washed = findByClass(target, "todo-spectrum-day");
  assert.ok(washed.length >= 3, "the cells from now to the staple carry the spectrum wash");
  assert.ok(washed.every((cell) => cell.dataset.createDay !== undefined));
});

test("Wall pips carry the state stamp -- the modifier axis reaches every mark shape", () => {
  const document = todoDocument();
  addTodo(document, "event:done", "File the report", { coordinate: civil(19) });
  addRelation(document, { type: "membership", group: "frame:state-done", member: "event:done", provenance: { kind: "explicit" } });
  const session = new ViewSession({
    projection: "wall", activeFrame: "calendar:personal",
    focusDays: daysFromCivil(2026n, 8n, 19n).toString()
  });
  const target = renderLens(document, session);
  const pip = findByClass(target, "event-pip").find((node) => node.dataset.todoState === "done");
  assert.ok(pip, "the pip is stamped with the todo state");
  assert.equal(pip.dataset.sigil, "task", "the task glyph stays; state is a modifier axis");
});
