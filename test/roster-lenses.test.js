import assert from "node:assert/strict";
import test from "node:test";
import { CommandHistory, addEvent, addRelation, createId, durationMagnitude } from "../src/model.js";
import { rosterEntries } from "../src/object-kinds.js";
import { DEFAULT_LENS_ORDER, ViewSession } from "../src/session.js";
import { toggleTodoCompletion } from "../src/ui/roster.js";
import { createTransactions } from "../src/ui/transactions.js";
import { createSampleDocument, createStructuralDocument } from "./helpers/sample-document.js";
import { renderProjection } from "../src/projections.js";
import { ChronologEngine } from "../src/engine.js";
import { FIXED_RADIAL_CYCLES, resolveRadialCycle } from "../src/radial.js";
import { daysFromCivil } from "../src/exact.js";

// createTransactions(app) only reaches into app.chronolog/app.history/app.session,
// so toggleTodoCompletion's undo/redo bundle is exercised without a DOM -- same
// harness shape as test/op-capture.test.js.
function transactionHarness(document, activeFrame = "") {
  const changes = [];
  const app = { chronolog: document, session: new ViewSession({ activeFrame }) };
  app.history = new CommandHistory(document, (change) => changes.push(change));
  Object.assign(app, createTransactions(app));
  return { app, changes };
}

function documentWithFloats() {
  const document = createStructuralDocument();
  const calendar = Object.values(document.frames).find((frame) => frame.traits?.includes("gregorian"));
  const place = (traits, title, day = null) => {
    const event = addEvent(document, {
      traits,
      magnitudes: { duration: durationMagnitude("0") },
      payload: { title }
    });
    if (day !== null) {
      addRelation(document, {
        type: "placement",
        event: event.id,
        frame: calendar.id,
        coordinate: {
          levels: [
            { level: "year", value: "2026" },
            { level: "month", value: "8" },
            { level: "day", value: String(day) }
          ]
        }
      });
    }
    return event.id;
  };
  place(["event", "task", "todo"], "Water the plants", 18);
  place(["event", "task", "todo"], "Book the hall", 20);
  const unanchored = place(["event", "task", "todo"], "Someday idea");
  place(["event", "note"], "Rules of thumb", 19);
  place(["event"], "Design review", 18);
  return { document, unanchored };
}

test("a roster lists only its own kind", () => {
  const { document } = documentWithFloats();
  const todos = rosterEntries(document, "todo").map((entry) => entry.title);
  const notes = rosterEntries(document, "note").map((entry) => entry.title);
  assert.deepEqual(todos, ["Book the hall", "Someday idea", "Water the plants"]);
  assert.deepEqual(notes, ["Rules of thumb"]);
  // The plain Event belongs to neither roster.
  assert.ok(!todos.includes("Design review") && !notes.includes("Design review"));
});

// A float exists before it has been scheduled, so the roster has to be able to say
// "no staple yet" instead of inventing a date for it.
test("a roster reports an unanchored float honestly rather than inventing a date", () => {
  const { document } = documentWithFloats();
  const entries = rosterEntries(document, "todo");
  const someday = entries.find((entry) => entry.title === "Someday idea");
  assert.equal(someday.anchored, false);
  assert.equal(someday.coordinate, null);
  const anchored = entries.find((entry) => entry.title === "Water the plants");
  assert.equal(anchored.anchored, true);
  assert.ok(anchored.coordinate, "an anchored float carries the coordinate it is stapled at");
  assert.ok(anchored.frame, "and the frame it is stapled to");
});

// Stage B1: a check control on the roster row marks a ToDo done by writing the
// same "completed" relation the inspector's Completed date field writes, and
// undo restores the exact prior state.
test("marking a ToDo done writes the inspector's completed relation shape; undo clears it exactly", () => {
  const document = createSampleDocument();
  const todoId = createId("event");
  addEvent(document, {
    id: todoId,
    traits: ["event", "task", "todo"],
    magnitudes: { duration: durationMagnitude("0") },
    payload: { title: "Renew the parking permit" }
  });
  const scheduledCoordinate = {
    levels: [{ level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "15" }]
  };
  addRelation(document, {
    id: "relation:renew-permit-observed",
    type: "attachment",
    event: todoId,
    frame: "calendar:personal",
    role: "observed",
    coordinate: scheduledCoordinate
  });

  const before = rosterEntries(document, "todo").find((entry) => entry.id === todoId);
  assert.equal(before.completed, false, "not completed yet");
  assert.equal(before.completedAt, null);

  const { app } = transactionHarness(document, "calendar:personal");
  toggleTodoCompletion(app, todoId);

  const completedRelation = Object.values(app.chronolog.relations).find(
    (relation) => relation.type === "attachment" && relation.event === todoId && relation.role === "completed"
  );
  assert.ok(completedRelation, "checking the box adds a temporal attachment relation with role completed");
  assert.equal(completedRelation.frame, "calendar:personal", "it lands on the same calendar frame as the ToDo's own placement");
  assert.ok(
    completedRelation.coordinate.levels.some((level) => level.level === "year"),
    "coordinate is the levels shape daysToCivilCoordinate/the inspector's Completed field both produce"
  );

  const afterComplete = rosterEntries(app.chronolog, "todo").find((entry) => entry.id === todoId);
  assert.equal(afterComplete.completed, true);
  assert.deepEqual(afterComplete.completedAt, completedRelation.coordinate);
  // The ToDo's own placement is untouched -- completed-at is a separate fact,
  // never a stand-in for where the object is stapled.
  assert.deepEqual(afterComplete.coordinate, scheduledCoordinate);
  // Still one of the roster's entries -- marking done never deletes, hides, or
  // lapses it (ROADMAP #9's staple/decay model is unsettled and stays that way).
  assert.ok(rosterEntries(app.chronolog, "todo").some((entry) => entry.id === todoId));

  assert.equal(app.history.undo(), true);
  const afterUndo = rosterEntries(app.chronolog, "todo").find((entry) => entry.id === todoId);
  assert.equal(afterUndo.completed, false, "undo restores the exact prior state");
  assert.equal(afterUndo.completedAt, null);
  assert.ok(
    !Object.values(app.chronolog.relations).some((relation) => relation.role === "completed" && relation.event === todoId),
    "the completed relation itself is gone, not just hidden"
  );
});

// Unchecking is the same fact removed the same way, and it is itself undoable
// (checking, then unchecking, then undoing the uncheck restores completion).
test("unchecking a completed ToDo clears the relation, and that step undoes too", () => {
  const document = createSampleDocument();
  const todoId = createId("event");
  addEvent(document, {
    id: todoId,
    traits: ["event", "task", "todo"],
    magnitudes: { duration: durationMagnitude("0") },
    payload: { title: "File the report" }
  });
  addRelation(document, {
    id: "relation:file-report-observed",
    type: "attachment",
    event: todoId,
    frame: "calendar:personal",
    role: "observed",
    coordinate: { levels: [{ level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "1" }] }
  });

  const { app } = transactionHarness(document, "calendar:personal");
  toggleTodoCompletion(app, todoId); // check
  assert.equal(rosterEntries(app.chronolog, "todo").find((entry) => entry.id === todoId).completed, true);

  toggleTodoCompletion(app, todoId); // uncheck
  const afterUncheck = rosterEntries(app.chronolog, "todo").find((entry) => entry.id === todoId);
  assert.equal(afterUncheck.completed, false);
  assert.equal(afterUncheck.completedAt, null);

  assert.equal(app.history.undo(), true); // undo the uncheck
  const afterUndoUncheck = rosterEntries(app.chronolog, "todo").find((entry) => entry.id === todoId);
  assert.equal(afterUndoUncheck.completed, true, "undoing the uncheck restores completion");

  assert.equal(app.history.redo(), true); // redo the uncheck
  const afterRedoUncheck = rosterEntries(app.chronolog, "todo").find((entry) => entry.id === todoId);
  assert.equal(afterRedoUncheck.completed, false, "redo re-applies the uncheck");
});

// A float with no staple yet can still be marked done -- completion is
// independent of the staple/decay question ROADMAP #9 leaves open, so this
// falls back to the active frame rather than inventing a staple to hang it on.
test("marking an unstapled ToDo done falls back to the active frame and invents no staple", () => {
  const document = createStructuralDocument();
  document.frames["calendar:personal"] = {
    id: "calendar:personal",
    title: "Personal",
    traits: ["set", "calendar"],
    basis: "frame:wall-time",
    codec: { kind: "ics" }
  };
  const todoId = createId("event");
  addEvent(document, {
    id: todoId,
    traits: ["event", "task", "todo"],
    magnitudes: { duration: durationMagnitude("0") },
    payload: { title: "Someday idea" }
  });

  const { app } = transactionHarness(document, "calendar:personal");
  toggleTodoCompletion(app, todoId);

  const entry = rosterEntries(app.chronolog, "todo").find((item) => item.id === todoId);
  assert.equal(entry.completed, true);
  assert.equal(entry.anchored, false, "completing an unstapled float does not invent a staple for it");
  const completedRelation = Object.values(app.chronolog.relations).find(
    (relation) => relation.role === "completed" && relation.event === todoId
  );
  assert.equal(completedRelation.frame, "calendar:personal", "falls back to the session's active frame");
});

test("a roster is stable and total on an empty or malformed document", () => {
  assert.deepEqual(rosterEntries(createStructuralDocument(), "todo"), []);
  assert.deepEqual(rosterEntries({}, "note"), []);
  assert.deepEqual(rosterEntries(undefined, "todo"), []);
  // An unknown kind falls back to events rather than throwing.
  assert.deepEqual(rosterEntries(createStructuralDocument(), "nonesuch"), []);
});

// The number keys used to index a hard-coded catalogue order. With a lens hidden
// or reordered, 4 could land on something that was not the fourth button — or on a
// hidden lens, where setLens refused and the key silently did nothing.
test("the number keys follow the visible bar order, not the catalogue", () => {
  const session = new ViewSession({});
  assert.deepEqual(session.availableLenses(), [...DEFAULT_LENS_ORDER]);

  // Hide Tactical: everything after it shifts up one position.
  session.configureLenses({
    enabledLenses: DEFAULT_LENS_ORDER.filter((lens) => lens !== "tactical")
  });
  const visible = session.availableLenses();
  assert.ok(!visible.includes("tactical"));
  assert.equal(visible[1], "strategic", "the second key now reaches the second visible lens");

  // Reordering changes what each key means, in the order the user actually sees.
  session.configureLenses({ lensOrder: ["wall", "lines", "intimate", "strategic", "spiral", "radial"] });
  assert.equal(session.availableLenses()[0], "wall");
});

test("hiding a lens keeps it reachable and never loses its settings", () => {
  const session = new ViewSession({ strategicMonths: 11, radialLabels: false });
  session.configureLenses({ enabledLenses: ["intimate", "tactical"] });

  // It is off the bar but still in the order, which is what the drop lists.
  assert.ok(!session.enabledLenses.includes("strategic"));
  assert.ok(session.lensOrder.includes("strategic"), "a hidden lens stays in the order, so the drop can offer it");
  assert.equal(session.strategicMonths, 11, "and keeps its own window setting");
  assert.equal(session.radialLabels, false);

  // Restoring it from the drop is exactly re-enabling it.
  session.configureLenses({ enabledLenses: [...session.enabledLenses, "strategic"] });
  session.setLens("strategic");
  assert.equal(session.currentLens(), "strategic");
  assert.equal(session.strategicMonths, 11);
});

test("hiding the lens in view moves to one that is still visible", () => {
  const session = new ViewSession({});
  session.setLens("radial");
  assert.equal(session.currentLens(), "radial");
  session.configureLenses({ enabledLenses: ["intimate", "tactical"] });
  // A workspace whose current lens just became unreachable must not be left
  // projecting something with no way back to it.
  assert.ok(session.enabledLenses.includes(session.currentLens()));
});

test("dock geometry and lens visibility both survive a session round trip", () => {
  const session = new ViewSession({});
  session.configureLenses({ enabledLenses: ["intimate", "wall"], lensOrder: ["wall", "intimate"] });
  const restored = new ViewSession(session.toJSON());
  assert.deepEqual(restored.availableLenses(), ["wall", "intimate"]);
  assert.ok(restored.lensOrder.includes("radial"), "a hidden lens is still remembered");
});

// There is no DOM-execution harness in this repo beyond the stub pattern
// test/dock-dom.test.js established -- this is that same shape, sized down to
// exactly what src/projections.js touches while building Intimate day columns
// and radial-family SVG (createElement/createElementNS, style, dataset,
// classList, append/replaceChildren). It is real enough to run renderProjection
// end to end and inspect the actual elements it produces, so these are
// behavioral checks against rendered output, not against the implementation's
// source text.
function createRenderStubDom() {
  class StubElement {
    constructor(tag) {
      this.tagName = String(tag).toUpperCase();
      this.className = "";
      this.textContent = "";
      this.dataset = {};
      this.children = [];
      this.parentElement = null;
      this.attributes = new Map();
      this.clientHeight = 900;
      const node = this;
      this.style = {
        setProperty(name, value) { this[name] = String(value); },
        getPropertyValue(name) { return this[name] ?? ""; }
      };
      this.classList = {
        add(cls) { node.className = node.className ? `${node.className} ${cls}` : cls; }
      };
    }

    append(...nodes) {
      for (const n of nodes) { n.parentElement = this; this.children.push(n); }
    }

    replaceChildren(...nodes) {
      this.children = [];
      this.append(...nodes);
    }

    setAttribute(name, value) {
      this.attributes.set(name, String(value));
      // svgElement() sets the SVG "class" attribute via setAttribute rather
      // than the className property real HTML elements get from element()
      // -- mirror it the way a real DOM keeps className and the class
      // attribute in sync, so classList.add (used for sigil classes) and
      // this attribute-set class both land in the one place findByClass reads.
      if (name === "class") this.className = String(value);
    }

    getAttribute(name) { return this.attributes.get(name) ?? null; }

    descendants() {
      return this.children.flatMap((child) => [child, ...child.descendants()]);
    }
  }
  const documentStub = {
    createElement: (tag) => new StubElement(tag),
    createElementNS: (_ns, tag) => new StubElement(tag)
  };
  return { StubElement, documentStub };
}

// Runs renderProjection with the document/window globals stubbed for exactly
// the duration of the call, and always restores them -- a leaked stub
// `document` would corrupt every test that runs after this one in the same
// process.
function renderWithStubDom(context) {
  const { StubElement, documentStub } = createRenderStubDom();
  const previousDocument = globalThis.document;
  globalThis.document = documentStub;
  const target = new StubElement("div");
  try {
    renderProjection(target, context);
    return target;
  } finally {
    globalThis.document = previousDocument;
  }
}

function findByClass(root, className) {
  return root.descendants().filter((node) => String(node.className).split(/\s+/).includes(className));
}

// A day column's rendered "timed" rail is a continuous multi-day window (it
// carries several buffer days either side of the visible day for scroll
// continuity), so a class-only search can pick up floats from neighbouring
// days too. Matching on the title text a button's own <strong> child carries
// isolates the one button a test actually means.
function floatWithTitle(target, title) {
  return findByClass(target, "float-event").filter(
    (node) => node.children.some((child) => child.textContent?.includes(title))
  );
}

// Stage B3 (8.19 field report, owner item 2): "Left Alignment on TODOs
// appears broken, I see one show half width without another event to push to
// half width." The Intimate float branch shrank every float to
// `max(22, 42 - lane*6)%` unconditionally -- even at lane 0 with laneCount 1,
// i.e. with no other float anywhere near it in time. The fix reuses the same
// real-collision signal (item.laneCount) the non-float branch already uses,
// so a float with nothing to collide with claims the full column.
// engine.queryFacts (what actually drives Intimate/Radial rendering) only
// reads "attachment" relations -- documentWithFloats() above places
// "placement" relations, which rosterEntries() reads directly by coordinate
// regardless of type, but the engine does not. A frame with the "calendar"
// trait is also required (frame:wall-time -- the bare gregorian line -- is
// not itself queryable); this mirrors createSampleDocument's calendar:personal.
function intimateFloatDocument() {
  const document = createStructuralDocument();
  document.frames["calendar:personal"] = {
    id: "calendar:personal",
    title: "Personal",
    traits: ["set", "calendar"],
    basis: "frame:wall-time",
    codec: { kind: "ics" }
  };
  const calendar = document.frames["calendar:personal"];
  const place = (title, day, hour = 9) => {
    const event = addEvent(document, {
      traits: ["event", "task", "todo"],
      magnitudes: { duration: durationMagnitude("0") },
      payload: { title }
    });
    addRelation(document, {
      type: "attachment",
      role: "placed",
      event: event.id,
      frame: calendar.id,
      coordinate: {
        levels: [
          { level: "year", value: "2026" },
          { level: "month", value: "8" },
          { level: "day", value: String(day) },
          { level: "hour", value: String(hour) }
        ]
      }
    });
    return event.id;
  };
  // A lone float, nothing else scheduled anywhere near it in time.
  place("Renew the parking permit", 18);
  // Two floats stacked at the exact same hour on another day -- a genuine
  // overlap, the only thing allowed to narrow a float.
  place("Call the vet", 20);
  place("Pick up the dry cleaning", 20);
  return { document, calendar };
}

function renderIntimateFor(document, calendar, focusDay) {
  const session = new ViewSession({
    projection: "calendar",
    scale: 0,
    activeFrame: calendar.id,
    intimateBack: 0,
    intimateForward: 0,
    focusDays: focusDay.toString()
  });
  const context = { document, engine: new ChronologEngine(document), session };
  return renderWithStubDom(context);
}

test("Stage B3: a lone float with no colliding neighbour claims the full column, not a shrunk half-width", () => {
  const { document, calendar } = intimateFloatDocument();
  // Aug 19 focus with the default bufferDays=3 rail spans Aug16-22, so this
  // single render already carries both the lone float (Aug 18) and the
  // colliding pair (Aug 20) -- the point of the buffered rail is that they
  // all live in one continuous column, which is exactly why matching by
  // class alone is not enough and floatWithTitle exists.
  const target = renderIntimateFor(document, calendar, daysFromCivil(2026n, 8n, 19n));
  const floats = floatWithTitle(target, "Renew the parking permit");
  assert.equal(floats.length, 1, "the lone float renders exactly once");
  const [button] = floats;
  assert.equal(button.style.right, "0%", "right-edge anchoring is preserved (ROADMAP #9)");
  assert.equal(button.style.width, "calc(100% - 3px)", "absent a real collision, a float takes the full column width");
});

test("Stage B3: two floats that genuinely overlap still lane side by side instead of both claiming full width", () => {
  const { document, calendar } = intimateFloatDocument();
  const target = renderIntimateFor(document, calendar, daysFromCivil(2026n, 8n, 19n));
  const vet = floatWithTitle(target, "Call the vet");
  const dryCleaning = floatWithTitle(target, "Pick up the dry cleaning");
  assert.equal(vet.length, 1);
  assert.equal(dryCleaning.length, 1);
  const widths = [vet[0].style.width, dryCleaning[0].style.width].sort();
  const rights = [vet[0].style.right, dryCleaning[0].style.right].sort();
  assert.deepEqual(widths, ["calc(50% - 3px)", "calc(50% - 3px)"], "a real collision still divides width by the true lane count");
  assert.deepEqual(rights, ["0%", "50%"], "and the lanes are laid out distinctly, right-anchored, not stacked on top of each other");
  // And the lone float on Aug 18, sharing this same rendered column, is
  // unaffected by a collision two days away.
  assert.equal(floatWithTitle(target, "Renew the parking permit")[0].style.width, "calc(100% - 3px)");
});

// Stage C (8.19 field report, owner item 6): "Spiral Still has rounded edges,
// at the ends of the spirals, where it should terminate along the vertical
// ray according to its start or stop date." The cap is now decided in exactly
// one place -- `.radial-event-arc { stroke-linecap: butt }` in app.css -- and
// the geometry proof that a butt cap on a circular arc lands exactly on the
// radial ray lives in src/radial.js's arcPath/polar tests.
//
// What this pins is the half of the contract that CSS cannot defend: the arc
// renderer must not set a cap of its own. An inline style or a presentation
// attribute here would outrank the stylesheet and make that rule a dead letter,
// and the risk is live rather than theoretical -- sibling paths in the very same
// renderer (the Lines lens, the radial guide rings) legitimately set
// "stroke-linecap": "round", so copying that pattern onto an event arc is a
// one-line regression that would restore the reported bug invisibly.
function radialArcDocument() {
  const document = createStructuralDocument();
  document.frames["calendar:personal"] = {
    id: "calendar:personal",
    title: "Personal",
    traits: ["set", "calendar"],
    basis: "frame:wall-time",
    codec: { kind: "ics" }
  };
  const calendar = document.frames["calendar:personal"];
  const event = addEvent(document, {
    traits: ["event"],
    magnitudes: { duration: durationMagnitude("60") },
    payload: { title: "Standup" }
  });
  addRelation(document, {
    type: "attachment",
    role: "placed",
    event: event.id,
    frame: calendar.id,
    coordinate: {
      levels: [
        { level: "year", value: "2026" }, { level: "month", value: "8" },
        { level: "day", value: "19" }, { level: "hour", value: "9" }
      ]
    }
  });
  return { document, calendar };
}

function renderRadialFamilyFor(document, calendar, radialMode) {
  const session = new ViewSession({
    projection: "radial",
    radialMode,
    activeFrame: calendar.id,
    activeCycle: "fixed:week",
    focusDays: daysFromCivil(2026n, 8n, 19n).toString()
  });
  session.radialResolution = resolveRadialCycle(FIXED_RADIAL_CYCLES, session.activeCycle, session.currentFocus());
  const context = { document, engine: new ChronologEngine(document), session };
  return renderWithStubDom(context);
}

for (const radialMode of ["concentric", "spiral"]) {
  test(`Stage C: a rendered ${radialMode === "spiral" ? "Spiral" : "Radial"} arc leaves its flush cap to the stylesheet and never re-rounds it`, () => {
    const { document, calendar } = radialArcDocument();
    const target = renderRadialFamilyFor(document, calendar, radialMode);
    const arcs = findByClass(target, "radial-event-arc");
    assert.ok(arcs.length > 0, "the event actually rendered an arc");
    for (const arc of arcs) {
      const style = arc.attributes.get("style") || "";
      const attribute = arc.attributes.get("stroke-linecap") || "";
      // A round or square cap extends the stroke past the arc's own exact
      // endpoint, which is the reported overshoot past the start/stop date.
      assert.doesNotMatch(style, /stroke-linecap/, "the renderer sets no inline cap, so app.css stays the single decision point");
      assert.ok(
        attribute === "" || attribute === "butt",
        `the renderer must not present a rounded cap attribute (got "${attribute}")`
      );
    }
  });
}
