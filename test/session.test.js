import test from "node:test";
import assert from "node:assert/strict";
import { Rational } from "../src/exact.js";
import {
  INTIMATE_HOUR_PIXELS_MAX,
  INTIMATE_HOUR_PIXELS_MIN,
  LENS_VIEW_DEFAULTS,
  ViewSession,
  factMatchesSelection
} from "../src/session.js";

test("shared focus remains constant between projections by default", () => {
  const session = new ViewSession({ focusDays: "12345/2", projection: "calendar" });
  session.setProjection("radial");
  assert.equal(session.currentFocus().toJSON(), "12345/2");
  session.setProjection("lines");
  assert.equal(session.currentFocus().toJSON(), "12345/2");
});

test("projection-local focus is an explicit opt-in", () => {
  const session = new ViewSession({ focusDays: "10", projection: "calendar" });
  session.toggleShared(false);
  session.move(2);
  session.setProjection("radial");
  session.move(5);
  session.setProjection("calendar");
  assert.equal(session.currentFocus().toJSON(), "12");
  session.setProjection("radial");
  assert.equal(session.currentFocus().toJSON(), "17");
});

test("intimate movement rolls exactly through midnight and radial defaults to three turns", () => {
  const session = new ViewSession({
    focusDays: new Rational(23n, 24n),
    radialPast: 1,
    radialFuture: 1
  });
  session.move(new Rational(1n, 12n));
  assert.equal(session.currentFocus().toJSON(), "25/24");
  assert.equal(session.radialPast + session.radialFuture + 1, 3);
});

test("seven explicit lenses retain their own useful window sizes", () => {
  const session = new ViewSession({
    intimateBack: 2,
    intimateForward: 4,
    tacticalRows: 4,
    tacticalColumns: 5,
    strategicMonths: 12,
    wallMonths: 6,
    linesDays: 14
  });
  session.setLens("intimate");
  assert.equal(session.currentLens(), "intimate");
  assert.equal(session.visibleSpan(), 7);
  session.setLens("tactical");
  assert.equal(session.visibleSpan(), 20);
  session.setLens("strategic");
  assert.equal(session.visibleSpan(), 365.25);
  session.setLens("wall");
  assert.equal(session.visibleSpan(), 182.625);
  session.setLens("lines");
  assert.equal(session.visibleSpan(), 14);
  session.setLens("spiral");
  assert.equal(session.currentLens(), "spiral");
  session.setLens("radial");
  assert.equal(session.currentLens(), "radial");
});

test("each lens can restore its canonical view without moving focus", () => {
  const session = new ViewSession({
    focusDays: "123",
    intimateBack: 0,
    intimateForward: 0,
    intimateStartHour: 0,
    intimateEndHour: 24,
    tacticalRows: 1,
    tacticalColumns: 1,
    strategicMonths: 2
  });
  session.setLens("intimate");
  assert.equal(session.resetLensView(), true);
  assert.equal(session.intimateBack, 2);
  assert.equal(session.intimateForward, 7);
  assert.equal(session.intimateStartHour, 4);
  assert.equal(session.intimateEndHour, 20);
  assert.equal(session.currentFocus().toJSON(), "123");
  session.setLens("tactical");
  session.resetLensView();
  assert.equal(session.tacticalRows, 5);
  assert.equal(session.tacticalColumns, 7);
  session.setLens("strategic");
  session.resetLensView();
  assert.equal(session.strategicMonths, 9);
  assert.equal(LENS_VIEW_DEFAULTS.intimate.intimateHourPixels, 42);
});

test("radial guide settings survive a view-session round trip", () => {
  const original = new ViewSession({ radialDivisions: 30, radialMajorEvery: 7, radialMarks: "day-night" });
  const restored = new ViewSession(original.toJSON());
  assert.equal(restored.radialDivisions, 30);
  assert.equal(restored.radialMajorEvery, 7);
  assert.equal(restored.radialMarks, "day-night");
});

test("radial automatic values persist as auto and explicit major marks normalize only when ticks make them invalid", () => {
  const automatic = new ViewSession({ radialDivisions: 0, radialMajorEvery: 0 });
  const restoredAutomatic = new ViewSession(automatic.toJSON());
  assert.equal(restoredAutomatic.radialDivisions, 0);
  assert.equal(restoredAutomatic.radialMajorEvery, 0);

  const explicit = new ViewSession({ radialDivisions: 64, radialMajorEvery: 32 });
  const restoredExplicit = new ViewSession(explicit.toJSON());
  assert.equal(restoredExplicit.radialDivisions, 64);
  assert.equal(restoredExplicit.radialMajorEvery, 32);

  const constrained = new ViewSession({ radialDivisions: 4, radialMajorEvery: 32 });
  assert.equal(constrained.radialDivisions, 4);
  assert.equal(constrained.radialMajorEvery, 4);
});

test("the leading frame is canonical and survives a view-session round trip", () => {
  const session = new ViewSession({ activeFrame: "calendar:first", primeFrame: "calendar:legacy" });
  session.setLeadingFrame("calendar:second");
  const saved = session.toJSON();
  const restored = new ViewSession(saved);
  assert.equal(restored.activeFrame, "calendar:second");
  assert.equal(saved.activeFrame, "calendar:second");
  assert.equal("primeFrame" in saved, false);
  assert.equal("primeFrame" in restored, false);
});

test("Intimate vertical zoom clamps at usable extremes and survives restoration", () => {
  const session = new ViewSession({ intimateHourPixels: 56 });
  session.setIntimateHourPixels(1);
  assert.equal(session.intimateHourPixels, INTIMATE_HOUR_PIXELS_MIN);
  session.setIntimateHourPixels(1000);
  assert.equal(session.intimateHourPixels, INTIMATE_HOUR_PIXELS_MAX);
  session.setIntimateHourPixels(42.5);
  const restored = new ViewSession(session.toJSON());
  assert.equal(restored.intimateHourPixels, 42.5);
});

// A single click on the stage selects; a double click opens the editor. These are
// the identity rules that decide what the selected mark lands on.
test("selection matches one occurrence, not every occurrence of its series", () => {
  const explicit = { type: "event", id: "event:one" };
  assert.equal(factMatchesSelection(explicit, { event: { id: "event:one" } }), true);
  assert.equal(factMatchesSelection(explicit, { event: { id: "event:two" } }), false);

  // Two generated occurrences of one weekly series share an event id. Matching on
  // the event alone would light up the whole series when the user picked one week.
  const occurrence = { type: "event", id: "event:series", virtualId: "pattern:p/2026-01-12" };
  assert.equal(
    factMatchesSelection(occurrence, { event: { id: "event:series" }, virtualId: "pattern:p/2026-01-12" }),
    true
  );
  assert.equal(
    factMatchesSelection(occurrence, { event: { id: "event:series" }, virtualId: "pattern:p/2026-01-19" }),
    false,
    "a different week of the same series is not the selected object"
  );
  // A materialized instance is not the generated occurrence it replaced.
  assert.equal(factMatchesSelection(occurrence, { event: { id: "event:series" } }), false);
});

test("an absent or foreign selection never marks anything", () => {
  assert.equal(factMatchesSelection(null, { event: { id: "event:one" } }), false);
  assert.equal(factMatchesSelection({ type: "frame", id: "frame:a" }, { event: { id: "frame:a" } }), false);
  assert.equal(factMatchesSelection({ type: "event", id: "event:one" }, {}), false);
  assert.equal(factMatchesSelection({ type: "event", id: "event:one" }, null), false);
});

test("dock geometry is view state and survives a session round trip", () => {
  const session = new ViewSession({ dockSide: "left", dockWidth: 0.5, dockOrder: ["object:a", "panel:frames-browser"] });
  const restored = new ViewSession(session.toJSON());
  assert.equal(restored.dockSide, "left");
  assert.equal(restored.dockWidth, 0.5);
  assert.deepEqual(restored.dockOrder, ["object:a", "panel:frames-browser"]);
  // Garbage degrades to the documented defaults rather than throwing.
  const fallback = new ViewSession({ dockSide: "sideways", dockWidth: "wide" });
  assert.equal(fallback.dockSide, "right");
  assert.equal(fallback.dockWidth, 1 / 3);
});

// A lens projects a leading frame and optional companions (AGENTS.md's frame
// model, point 4). The Frame drop needs to check several frames at once
// while `activeFrame` keeps meaning "the leading one" for every renderer
// that only knows about a single frame.
test("selectedFrames puts the leading frame first, then its companions", () => {
  const session = new ViewSession({ activeFrame: "calendar:personal" });
  assert.deepEqual(session.selectedFrames(), ["calendar:personal"], "no companions yet");
  session.setFrameSelection(["calendar:personal", "calendar:work", "calendar:family"]);
  assert.equal(session.activeFrame, "calendar:personal", "the already-leading frame stays leading");
  assert.deepEqual(session.selectedFrames(), ["calendar:personal", "calendar:work", "calendar:family"]);
});

test("setFrameSelection only reassigns the leading frame when it drops out of the selection", () => {
  const session = new ViewSession({ activeFrame: "calendar:personal" });
  session.setFrameSelection(["calendar:work", "calendar:family"]);
  assert.equal(session.activeFrame, "calendar:work", "the first offered id becomes leading");
  assert.deepEqual(session.companionFrames, ["calendar:family"]);
  // An empty selection is refused outright — a frame drop with nothing
  // checked is a trap, not a valid state.
  session.setFrameSelection([]);
  assert.equal(session.activeFrame, "calendar:work", "unchanged");
});

test("setLeadingFrame keeps the promoted frame out of its own companion list", () => {
  const session = new ViewSession({ activeFrame: "calendar:personal" });
  session.setFrameSelection(["calendar:personal", "calendar:work"]);
  session.setLeadingFrame("calendar:work");
  assert.equal(session.activeFrame, "calendar:work");
  assert.deepEqual(session.companionFrames, [], "the new leader is not also listed as its own companion");
});

test("pruneFrameSelection drops companions, and reassigns the leader, when a frame no longer exists", () => {
  const session = new ViewSession({ activeFrame: "calendar:personal" });
  session.setFrameSelection(["calendar:personal", "calendar:work", "calendar:family"]);
  session.pruneFrameSelection(["calendar:work", "calendar:family"]);
  assert.equal(session.activeFrame, "calendar:work", "the deleted leader is replaced by a surviving companion");
  assert.deepEqual(session.companionFrames, ["calendar:family"]);
});

test("companion frames survive a session round trip and never include the leading frame twice", () => {
  const session = new ViewSession({ activeFrame: "calendar:personal", companionFrames: ["calendar:work", "calendar:personal"] });
  assert.deepEqual(session.companionFrames, ["calendar:work"], "the leading frame is not duplicated into its own companions");
  const restored = new ViewSession(session.toJSON());
  assert.equal(restored.activeFrame, "calendar:personal");
  assert.deepEqual(restored.companionFrames, ["calendar:work"]);
});
