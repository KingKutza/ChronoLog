import assert from "node:assert/strict";
import test from "node:test";
import { CommandHistory, addEvent, addRelation, createId, durationMagnitude, validateDocument } from "../src/model.js";
import { rosterEntries } from "../src/object-kinds.js";
import { DEFAULT_LENS_ORDER, ViewSession } from "../src/session.js";
import { toggleTodoCompletion } from "../src/ui/roster.js";
import { createTransactions } from "../src/ui/transactions.js";
import { createSampleDocument, createStructuralDocument } from "./helpers/sample-document.js";
import { findByClass, renderWithStubDom } from "./helpers/render-dom.js";
import { ChronologEngine } from "../src/engine.js";
import { FIXED_RADIAL_CYCLES, polar, resolveRadialCycle } from "../src/radial.js";
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

function doneMembershipOf(documentValue, todoId) {
  return Object.values(documentValue.relations).find(
    (relation) => relation.type === "membership" && relation.group === "frame:state-done" && relation.member === todoId
  );
}

function completionStapleOf(documentValue, todoId) {
  return Object.values(documentValue.relations).find(
    (relation) => relation.type === "staple"
      && relation.kind === "end"
      && relation.ends?.some((end) => end.object === todoId && end.point === "end")
  );
}

// The roster's check control marks a ToDo done through the ruled shape: done is
// membership in the Done state frame, the instant is an end staple -- "the end
// of this todo abuts" the moment it finished. Same records the inspector's
// Completed field writes, and undo restores the exact prior state.
test("marking a ToDo done writes the Done-state membership and end staple; undo clears both exactly", () => {
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

  const membership = doneMembershipOf(app.chronolog, todoId);
  assert.ok(membership, "checking the box writes membership in the Done state frame -- state is a frame, not a property");
  const staple = completionStapleOf(app.chronolog, todoId);
  assert.ok(staple, "and the instant is an end staple on the object's own end point");
  const frameEnd = staple.ends.find((end) => end.frame);
  assert.equal(frameEnd.frame, "calendar:personal", "it lands on the same calendar frame as the ToDo's own placement");
  assert.ok(
    frameEnd.coordinate.levels.some((level) => level.level === "year"),
    "coordinate is the levels shape the inspector's Completed field produces"
  );

  const afterComplete = rosterEntries(app.chronolog, "todo").find((entry) => entry.id === todoId);
  assert.equal(afterComplete.completed, true);
  assert.deepEqual(afterComplete.completedAt, frameEnd.coordinate);
  // The ToDo's own placement is untouched -- completed-at is a separate fact,
  // never a stand-in for where the object is stapled.
  assert.deepEqual(afterComplete.coordinate, scheduledCoordinate);
  // Still one of the roster's entries -- marking done never deletes, hides, or
  // lapses it (ROADMAP #2's staple/decay model is unsettled and stays that way).
  assert.ok(rosterEntries(app.chronolog, "todo").some((entry) => entry.id === todoId));

  assert.equal(app.history.undo(), true);
  const afterUndo = rosterEntries(app.chronolog, "todo").find((entry) => entry.id === todoId);
  assert.equal(afterUndo.completed, false, "undo restores the exact prior state");
  assert.equal(afterUndo.completedAt, null);
  assert.ok(!doneMembershipOf(app.chronolog, todoId), "the membership itself is gone, not just hidden");
  assert.ok(!completionStapleOf(app.chronolog, todoId), "and so is the end staple");
});

// Unchecking is the same two facts removed the same way, and it is itself
// undoable (checking, then unchecking, then undoing the uncheck restores both).
test("unchecking a completed ToDo clears membership and staple, and that step undoes too", () => {
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
  assert.ok(!completionStapleOf(app.chronolog, todoId), "leaving the state takes the instant with it");

  assert.equal(app.history.undo(), true); // undo the uncheck
  const afterUndoUncheck = rosterEntries(app.chronolog, "todo").find((entry) => entry.id === todoId);
  assert.equal(afterUndoUncheck.completed, true, "undoing the uncheck restores completion");

  assert.equal(app.history.redo(), true); // redo the uncheck
  const afterRedoUncheck = rosterEntries(app.chronolog, "todo").find((entry) => entry.id === todoId);
  assert.equal(afterRedoUncheck.completed, false, "redo re-applies the uncheck");
});

// A float with no staple yet can still be marked done -- completion is
// independent of the staple/decay question ROADMAP #2 leaves open. The end
// staple's frame falls back to the active frame, and because the `end` kind
// never anchors, it must not invent a placement for the float. This first
// completion is also what mints the Done frame -- nothing seeds it -- and undo
// of that first toggle removes the minted frame again.
test("marking an unstapled ToDo done falls back to the active frame, mints the Done frame lazily, and anchors nothing", () => {
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
  assert.equal(document.frames["frame:state-done"], undefined, "an empty document holds no Done frame");

  const { app } = transactionHarness(document, "calendar:personal");
  toggleTodoCompletion(app, todoId);

  const doneFrame = app.chronolog.frames["frame:state-done"];
  assert.ok(doneFrame, "the first completion mints the deterministic Done frame");
  assert.equal(doneFrame.title, "Done");
  assert.ok(doneFrame.traits.includes("group") && doneFrame.traits.includes("state"));
  const entry = rosterEntries(app.chronolog, "todo").find((item) => item.id === todoId);
  assert.equal(entry.completed, true);
  assert.equal(entry.anchored, false, "the completion staple never anchors the float anywhere");
  const staple = completionStapleOf(app.chronolog, todoId);
  assert.equal(staple.ends.find((end) => end.frame).frame, "calendar:personal", "falls back to the session's active frame");
  assert.deepEqual(validateDocument(app.chronolog).errors, [], "the completed document is valid");

  assert.equal(app.history.undo(), true);
  assert.equal(app.chronolog.frames["frame:state-done"], undefined, "undo of the minting toggle removes the frame it minted");
  assert.deepEqual(validateDocument(app.chronolog).errors, [], "and leaves a valid document behind");
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

// The stub DOM this suite renders into lives in test/helpers/render-dom.js,
// shared with the coordinate-law acceptance test. A second copy of a DOM stub
// is a second set of silent divergences in what "the DOM does" means, so there
// is one.

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
  assert.equal(button.style.right, "0%", "right-edge anchoring is preserved (ROADMAP #2)");
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

// Stage C (8.19 field report, owner item 6) reported the TRACK's own rounded
// end caps: "Spiral Still has rounded edges, at the ends of the spirals,
// where it should terminate along the vertical ray according to its start
// or stop date." The prior wave's fix conflated two distinct classes: it
// gave the EVENT marks a flush `butt` cap (via `.radial-event-arc` in
// app.css) instead of the TRACK, which kept drawing its own rounded caps
// unchanged. Two 8.19 Part Three owner reports are the two halves of that
// swap surfacing: "Spiral still has rounded end caps" (the track was never
// actually fixed) and "Spiral Events lost rounded caps, and are not
// perpendicular to the radial lines they sit on" (the events wrongly lost
// theirs). The track's flat terminus is now handled as geometry
// (spiralRibbonPath in src/radial.js, pinned in test/radial-stability.test.js)
// and the event arc's round cap is restored here, along with the arc's own
// perpendicular-to-its-radius geometry (also pinned below) -- distinct
// claims, so a bug that swaps which class gets which treatment cannot pass
// a test that only checks "something is flat".
//
// What this test pins is the half of the contract that CSS cannot defend:
// the arc renderer must not set a cap of its own. An inline style or a
// presentation attribute here would outrank the stylesheet and make that
// rule a dead letter, and the risk is live rather than theoretical --
// sibling paths in the very same renderer (the Lines lens, the radial guide
// rings) legitimately set "stroke-linecap" as an attribute for their own
// reasons, so copying that pattern onto an event arc is a one-line
// regression that would silently override app.css's decision either way.
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
  test(`Stage C: a rendered ${radialMode === "spiral" ? "Spiral" : "Radial"} event arc leaves its round cap to the stylesheet and never flattens it`, () => {
    const { document, calendar } = radialArcDocument();
    const target = renderRadialFamilyFor(document, calendar, radialMode);
    const arcs = findByClass(target, "radial-event-arc");
    assert.ok(arcs.length > 0, "the event actually rendered an arc");
    for (const arc of arcs) {
      const style = arc.attributes.get("style") || "";
      const attribute = arc.attributes.get("stroke-linecap") || "";
      // A `butt` cap here would flatten the event mark's own sigil (a
      // point-in-time indicator, not a boundary) -- that is the track's
      // treatment, not an event's; see spiralRibbonPath's doc comment.
      assert.doesNotMatch(style, /stroke-linecap/, "the renderer sets no inline cap, so app.css stays the single decision point");
      assert.ok(
        attribute === "" || attribute === "round",
        `the renderer must not present a flush cap attribute that would override the round default (got "${attribute}")`
      );
    }
  });
}

// This is the other distinct claim in the same owner report: not just that
// the cap is round, but that the mark's own long axis -- the arc's path
// itself, independent of any cap -- sits perpendicular to the radius it
// occupies, rather than skewed along the spiral's own mixed radial+angular
// travel direction. A test that only checked the cap (above) would have
// missed this half entirely: the previous per-sample spiral event path had
// exactly the reported butt cap AND a tangent tilted away from perpendicular
// by the spiral's own pitch.
test("Stage C: a rendered Spiral event arc is a constant-radius arc, so its own long axis is exactly perpendicular to its own radius", () => {
  const { document, calendar } = radialArcDocument();
  const target = renderRadialFamilyFor(document, calendar, "spiral");
  const arcs = findByClass(target, "radial-event-arc");
  assert.ok(arcs.length > 0, "the event actually rendered an arc");
  const cx = 450;
  const cy = 360;
  for (const arc of arcs) {
    const d = arc.attributes.get("d");
    const match = /^M ([\d.-]+) ([\d.-]+) A ([\d.-]+) [\d.-]+ 0 \d 1 ([\d.-]+) ([\d.-]+)/.exec(d);
    assert.ok(match, `a Spiral event arc must be a single constant-radius A command, not a path sampled along the spiral's own growth (got "${d}")`);
    const [mx, my, r, ex, ey] = match.slice(1).map(Number);
    // Constant radius, not one end further out than the other the way the
    // spiral's own track (or the old per-sample event path) would be.
    assert.ok(Math.abs(Math.hypot(mx - cx, my - cy) - r) < 0.5, "the arc's start point must sit on its own declared radius");
    assert.ok(Math.abs(Math.hypot(ex - cx, ey - cy) - r) < 0.5, "the arc's end point must sit on the same radius as its start");
    // The numeric perpendicularity claim: estimate the tangent at the start
    // point by stepping a small angle further around that same circle (same
    // technique as radial-stability.test.js's circle-tangent proof, applied
    // here to the actually-rendered geometry rather than a synthetic input).
    // Epsilon must be large enough that the resulting displacement (r *
    // epsilon) dominates the +/-0.005 quantization noise `d`'s toFixed(2)
    // coordinates carry -- at 1e-4 that displacement is only ~0.02 units at
    // a ~200 radius, the same order as the rounding noise itself, which
    // manufactures a spurious few-percent "misalignment" out of thin air.
    // 1e-2 keeps the chord-vs-true-tangent bias (epsilon/2) an order of
    // magnitude below the old pitch-tilt bug's own ~0.12-0.15 cosine, so it
    // stays a tight, discriminating check rather than a loose one.
    const startAngle = Math.atan2(my - cy, mx - cx);
    const epsilon = 1e-2;
    const [nx, ny] = polar(cx, cy, r, startAngle + epsilon);
    const tangent = [nx - mx, ny - my];
    const tangentLength = Math.hypot(...tangent);
    const radial = [Math.cos(startAngle), Math.sin(startAngle)];
    const cosineBetween = (tangent[0] * radial[0] + tangent[1] * radial[1]) / tangentLength;
    assert.ok(
      Math.abs(cosineBetween) < 1e-2,
      `the event mark's long axis must be perpendicular to the radius it sits on, not tangent-misaligned to the spiral's pitch (cos ${cosineBetween})`
    );
  }
});
