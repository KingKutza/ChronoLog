import test from "node:test";
import assert from "node:assert/strict";
import { Rational } from "../src/exact.js";
import { ViewSession } from "../src/session.js";

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
