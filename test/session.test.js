import test from "node:test";
import assert from "node:assert/strict";
import { Rational } from "../src/exact.js";
import {
  INTIMATE_HOUR_PIXELS_MAX,
  INTIMATE_HOUR_PIXELS_MIN,
  ViewSession
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
