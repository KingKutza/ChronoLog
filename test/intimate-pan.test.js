import assert from "node:assert/strict";
import test from "node:test";
import {
  INTIMATE_COLUMN_PIXELS_FALLBACK,
  INTIMATE_WHEEL_NOTCH,
  intimatePanStep,
  intimateWheelStep,
  scrollSlack,
  wheelHorizontalDelta
} from "../src/intimate-pan.js";

const WIDE = { startScrollLeft: 0, startScrollTop: 400, maxScrollLeft: 0, columnPixels: 120 };
const NARROW = { startScrollLeft: 50, startScrollTop: 400, maxScrollLeft: 300, columnPixels: 120 };

test("both axes come out of one gesture rather than being chosen against each other", () => {
  const step = intimatePanStep({ ...NARROW, dx: -60, dy: -90 });
  assert.equal(step.scrollLeft, 110, "horizontal motion moves the rail");
  assert.equal(step.scrollTop, 490, "and vertical motion moves at the same time");
  assert.equal(step.dayShift, 0, "with slack to spare, nothing becomes window movement");
});

test("horizontal motion the rail cannot absorb becomes whole-day window movement", () => {
  // The wide-window case: `1fr` day columns mean there is no horizontal overflow
  // at all, so scrollLeft can never move and the whole gesture has to be time.
  assert.equal(intimatePanStep({ ...WIDE, dx: -60 }).dayShift, 0, "under one column is not yet a day");
  assert.equal(intimatePanStep({ ...WIDE, dx: -130 }).dayShift, 1);
  assert.equal(intimatePanStep({ ...WIDE, dx: -260 }).dayShift, 2);
  assert.equal(intimatePanStep({ ...WIDE, dx: 130 }).dayShift, -1, "dragging the other way goes back in time");
  for (const dx of [-600, -130, 0, 260]) {
    assert.equal(intimatePanStep({ ...WIDE, dx }).scrollLeft, 0, "a rail with no slack never scrolls");
  }
});

test("the narrow window spends its slack first and only then moves the window", () => {
  const inside = intimatePanStep({ ...NARROW, dx: -200 });
  assert.equal(inside.scrollLeft, 250);
  assert.equal(inside.dayShift, 0);

  const atEdge = intimatePanStep({ ...NARROW, dx: -250 });
  assert.equal(atEdge.scrollLeft, 300, "the rail pins at its edge");
  assert.equal(atEdge.dayShift, 0, "reaching the edge is not itself a day");

  const past = intimatePanStep({ ...NARROW, dx: -400 });
  assert.equal(past.scrollLeft, 300);
  assert.equal(past.dayShift, 1, "150px beyond the edge is one column");

  const backwards = intimatePanStep({ ...NARROW, dx: 200 });
  assert.equal(backwards.scrollLeft, 0);
  assert.equal(backwards.dayShift, -1);
});

test("day steps are reported as a delta so a re-render cannot page twice", () => {
  // The gesture reports cumulative dx every move, so the caller applies only
  // what it has not applied yet.
  let applied = 0;
  const path = [-130, -260, -400, -260, -130, 0];
  const committed = [];
  for (const dx of path) {
    const step = intimatePanStep({ ...WIDE, dx, appliedDays: applied });
    if (step.dayDelta) committed.push(step.dayDelta);
    applied = step.dayShift;
  }
  assert.deepEqual(committed, [1, 1, 1, -1, -1, -1]);
  assert.equal(applied, 0, "a gesture returned to its origin leaves the window where it began");
  assert.equal(committed.reduce((sum, value) => sum + value, 0), 0, "and every step is reversible");
});

test("a pan never scrolls outside the rail", () => {
  const top = intimatePanStep({ ...NARROW, dy: 5000, maxScrollTop: 900 });
  assert.equal(top.scrollTop, 0);
  const bottom = intimatePanStep({ ...NARROW, dy: -5000, maxScrollTop: 900 });
  assert.equal(bottom.scrollTop, 900);
  // With no measurement available the vertical axis is left to the browser's own
  // clamping rather than being pinned to a guess.
  assert.equal(intimatePanStep({ ...NARROW, dy: -5000 }).scrollTop, 5400);
});

test("degenerate measurements fall back instead of dividing by zero", () => {
  const step = intimatePanStep({ dx: -240, columnPixels: 0, maxScrollLeft: 0 });
  assert.equal(step.dayShift, Math.trunc(240 / INTIMATE_COLUMN_PIXELS_FALLBACK));
  assert.equal(intimatePanStep({}).dayShift, 0);
  assert.equal(intimatePanStep({}).scrollLeft, 0);
});

test("the wheel carries its sub-notch remainder so slow trackpad motion still counts", () => {
  let carried = 0;
  let total = 0;
  // Six nudges of a third of a notch each: two full notches, nothing rounded away.
  for (let nudge = 0; nudge < 6; nudge += 1) {
    const step = intimateWheelStep({ carried, delta: INTIMATE_WHEEL_NOTCH / 3 });
    carried = step.carried;
    total += step.dayShift;
  }
  assert.equal(total, 2);
  assert.ok(Math.abs(carried) < INTIMATE_WHEEL_NOTCH);

  assert.equal(intimateWheelStep({ carried: 0, delta: INTIMATE_WHEEL_NOTCH }).dayShift, 1);
  assert.equal(intimateWheelStep({ carried: 0, delta: -INTIMATE_WHEEL_NOTCH }).dayShift, -1);
  assert.equal(intimateWheelStep({ carried: 0, delta: 10 }).dayShift, 0);
});

test("horizontal wheel intent reads deltaX, or deltaY when shift is held", () => {
  assert.equal(wheelHorizontalDelta({ deltaX: -40, deltaY: 200 }), -40, "a trackpad reports the axis directly");
  assert.equal(wheelHorizontalDelta({ deltaX: 0, deltaY: 120 }), 0, "a plain vertical wheel is not horizontal intent");
  assert.equal(wheelHorizontalDelta({ deltaX: 0, deltaY: 120, shiftKey: true }), 120, "shift+wheel means horizontal");
  assert.equal(wheelHorizontalDelta({}), 0);
});

test("native scrolling keeps the gesture while the surface still has room", () => {
  assert.equal(scrollSlack(0, 300, 40), 300, "pushing forward from the start has the whole rail");
  assert.equal(scrollSlack(300, 300, 40), 0, "pinned at the end, forward motion has nowhere to go");
  assert.equal(scrollSlack(300, 300, -40), 300, "but backward motion still does");
  assert.equal(scrollSlack(0, 0, 40), 0, "a surface with no overflow never has room");
  assert.equal(scrollSlack(0, 300, 0), 0);
});
