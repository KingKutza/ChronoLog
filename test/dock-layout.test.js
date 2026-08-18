import assert from "node:assert/strict";
import test from "node:test";
import {
  DOCK_SIDES,
  DOCK_SNAP_TOLERANCE,
  DOCK_WIDTH_MAX,
  DOCK_WIDTH_MIN,
  DOCK_WIDTH_SNAPS,
  appendCard,
  cardTranslatePercent,
  clampDockWidth,
  dockPagerState,
  dockPixelWidth,
  dockWidthFromDrag,
  normalizeDockSide,
  pagerIsMoving,
  reconcileCardOrder,
  removeCard,
  requestPage,
  requestPageTo,
  settlePage,
  snapDockWidth,
  swapCards
} from "../src/dock-layout.js";

test("DOCK_SIDES is frozen and lists right before left", () => {
  assert.deepEqual(DOCK_SIDES, ["right", "left"]);
  assert.ok(Object.isFrozen(DOCK_SIDES));
});

test("normalizeDockSide only recognizes the literal string left, defaulting everything else to right", () => {
  assert.equal(normalizeDockSide("left"), "left");
  assert.equal(normalizeDockSide("right"), "right");
  assert.equal(normalizeDockSide("LEFT"), "right", "not a case-insensitive match");
  assert.equal(normalizeDockSide(undefined), "right");
  assert.equal(normalizeDockSide(null), "right");
  assert.equal(normalizeDockSide(0), "right");
});

test("clampDockWidth stays inside [MIN, MAX] and garbage falls back to a third", () => {
  assert.equal(clampDockWidth(0.02), DOCK_WIDTH_MIN, "below the floor clamps up");
  assert.equal(clampDockWidth(0.9), DOCK_WIDTH_MAX, "above the ceiling clamps down");
  assert.equal(clampDockWidth(0.4), 0.4, "a value already inside the band is untouched");
  assert.equal(clampDockWidth(DOCK_WIDTH_MIN), DOCK_WIDTH_MIN, "the floor itself is valid");
  assert.equal(clampDockWidth(DOCK_WIDTH_MAX), DOCK_WIDTH_MAX, "the ceiling itself is valid");
  for (const garbage of [NaN, Infinity, -Infinity, undefined, "not a number", {}]) {
    assert.equal(clampDockWidth(garbage), 1 / 3, `garbage ${String(garbage)} falls back to the default width`);
  }
  // null coerces through Number() to 0, which is finite, so it clamps like any
  // other too-small value rather than being treated as unusable input.
  assert.equal(clampDockWidth(null), DOCK_WIDTH_MIN);
});

test("snapDockWidth pulls a width within tolerance onto its snap point and leaves the rest alone", () => {
  for (const snap of DOCK_WIDTH_SNAPS) {
    assert.equal(snapDockWidth(snap), snap, "a value already on a snap point stays there");
    assert.equal(snapDockWidth(snap + DOCK_SNAP_TOLERANCE / 2), snap, "just inside tolerance snaps");
    assert.equal(snapDockWidth(snap - DOCK_SNAP_TOLERANCE / 2), snap, "from the other side too");
  }
  // 1/4 and 1/3 are about 0.0833 apart, comfortably outside 2 * tolerance, so a
  // point roughly midway between them should snap to neither.
  const between = (1 / 4 + 1 / 3) / 2;
  assert.equal(snapDockWidth(between), clampDockWidth(between), "far from every snap, the value is untouched");
  // A custom tolerance is honoured explicitly.
  assert.equal(snapDockWidth(0.3, 0.05), 1 / 3, "a looser tolerance can pull in a farther value");
  assert.equal(snapDockWidth(0.3, 0), clampDockWidth(0.3), "zero tolerance never snaps unless exact");
});

test("snapDockWidth breaks an exact midpoint tie toward the smaller snap, deterministically", () => {
  const midpoint = (DOCK_WIDTH_SNAPS[0] + DOCK_WIDTH_SNAPS[1]) / 2;
  const distance = midpoint - DOCK_WIDTH_SNAPS[0];
  assert.equal(snapDockWidth(midpoint, distance), DOCK_WIDTH_SNAPS[0], "the smaller snap wins the exact midpoint");
  // Repeated calls with the same ambiguous input must agree with each other.
  const results = new Set();
  for (let i = 0; i < 5; i += 1) results.add(snapDockWidth(midpoint, distance));
  assert.equal(results.size, 1, "the tie-break is stable across repeated calls");
});

test("dockWidthFromDrag grows toward the workspace interior on both sides", () => {
  const workspaceWidth = 1000;
  // Right dock: moving the pointer left (away from the right edge, into the
  // workspace) should widen the dock.
  const rightNear = dockWidthFromDrag({ side: "right", pointerX: 900, workspaceWidth });
  const rightFar = dockWidthFromDrag({ side: "right", pointerX: 500, workspaceWidth });
  assert.ok(rightFar > rightNear, "dragging further into the workspace widens a right dock");
  assert.equal(rightNear, (0 + 1000 - 900) / 1000);
  assert.equal(rightFar, (0 + 1000 - 500) / 1000);

  // Left dock: moving the pointer right (into the workspace) should widen it.
  const leftNear = dockWidthFromDrag({ side: "left", pointerX: 100, workspaceWidth });
  const leftFar = dockWidthFromDrag({ side: "left", pointerX: 500, workspaceWidth });
  assert.ok(leftFar > leftNear, "dragging further into the workspace widens a left dock");
  assert.equal(leftNear, (100 - 0) / 1000);
  assert.equal(leftFar, (500 - 0) / 1000);

  // workspaceLeft offsets both sides equivalently.
  const offsetRight = dockWidthFromDrag({ side: "right", pointerX: 1400, workspaceLeft: 200, workspaceWidth: 1000 });
  assert.equal(offsetRight, (200 + 1000 - 1400) / 1000);
});

test("dockWidthFromDrag falls back to the default width instead of dividing by zero", () => {
  assert.equal(dockWidthFromDrag({ side: "right", pointerX: 100, workspaceWidth: 0 }), 1 / 3);
  assert.equal(dockWidthFromDrag({ side: "right", pointerX: 100, workspaceWidth: -50 }), 1 / 3);
  assert.equal(dockWidthFromDrag({}), 1 / 3);
});

test("dockPixelWidth rounds the clamped fraction into whole workspace pixels", () => {
  assert.equal(dockPixelWidth(1 / 3, 900), 300);
  assert.equal(dockPixelWidth(0.02, 900), Math.round(DOCK_WIDTH_MIN * 900), "clamps before scaling");
  assert.equal(dockPixelWidth(1 / 3, -100), 0, "a negative workspace floors at zero");
  assert.equal(dockPixelWidth(1 / 3, undefined), 0);
});

test("requestPage retargets rather than queues: three quick +1 requests land three cards ahead with one target", () => {
  let state = dockPagerState(0, null);
  state = requestPage(state, 1, 6);
  assert.deepEqual(state, { index: 0, target: 1 });
  state = requestPage(state, 1, 6);
  assert.deepEqual(state, { index: 0, target: 2 });
  state = requestPage(state, 1, 6);
  // The index never moved — only the single pending target advanced — which is
  // exactly what keeps rapid cycling from stacking up separate animations.
  assert.deepEqual(state, { index: 0, target: 3 });
});

test("requestPage wraps around the card count in both directions", () => {
  const atEnd = dockPagerState(5, null);
  assert.deepEqual(requestPage(atEnd, 1, 6), { index: 5, target: 0 }, "past the last card wraps to the first");
  const atStart = dockPagerState(0, null);
  assert.deepEqual(requestPage(atStart, -1, 6), { index: 0, target: 5 }, "before the first card wraps to the last");
  // Wrapping also applies while a target is already pending: this accumulates
  // from the pending target (5), wraps 5 + 1 to 0, and since that equals the
  // settled index, the result is a fully resting state.
  const midFlight = dockPagerState(0, 5);
  assert.deepEqual(requestPage(midFlight, 1, 6), { index: 0, target: null });
});

test("requestPage with a nonpositive count resets to a resting state", () => {
  assert.deepEqual(requestPage(dockPagerState(3, 4), 1, 0), { index: 0, target: null });
  assert.deepEqual(requestPage(dockPagerState(3, 4), 1, -2), { index: 0, target: null });
});

test("requestPageTo jumps straight to an absolute index and wraps out-of-range requests", () => {
  const state = dockPagerState(2, null);
  assert.deepEqual(requestPageTo(state, 5, 6), { index: 2, target: 5 });
  assert.deepEqual(requestPageTo(state, 9, 6), { index: 2, target: 3 }, "9 wraps to 3 (9 mod 6)");
  assert.deepEqual(requestPageTo(state, -1, 6), { index: 2, target: 5 }, "negative requests wrap backward");
});

test("requestPageTo targeting the current index produces no animation", () => {
  const state = dockPagerState(2, null);
  assert.deepEqual(requestPageTo(state, 2, 6), { index: 2, target: null });
  // Also true when arriving at the current index by wrapping.
  assert.deepEqual(requestPageTo(state, 8, 6), { index: 2, target: null });
});

test("requestPage landing back on the settled index clears the target instead of animating in place", () => {
  const state = dockPagerState(3, null);
  const forward = requestPage(state, 1, 6);
  assert.deepEqual(forward, { index: 3, target: 4 });
  const backward = requestPage(forward, -1, 6);
  assert.deepEqual(backward, { index: 3, target: null }, "the retarget cancels back to a no-op");
});

test("settlePage commits the pending target and clears it, or is a no-op at rest", () => {
  assert.deepEqual(settlePage(dockPagerState(1, 4)), { index: 4, target: null });
  assert.deepEqual(settlePage(dockPagerState(4, null)), { index: 4, target: null });
});

test("pagerIsMoving reflects whether a target is pending", () => {
  assert.equal(pagerIsMoving(dockPagerState(0, 1)), true);
  assert.equal(pagerIsMoving(dockPagerState(0, null)), false);
  assert.equal(pagerIsMoving(dockPagerState(0, 0)), true, "target 0 is still a pending target, distinct from null");
});

test("cardTranslatePercent offsets the strip by whole cards, or zero when there are none", () => {
  assert.equal(cardTranslatePercent(0, 5), 0);
  assert.equal(cardTranslatePercent(1, 5), -100);
  assert.equal(cardTranslatePercent(4, 5), -400);
  assert.equal(cardTranslatePercent(2, 0), 0, "no cards means nothing to translate");
});

test("appendCard is append-only: an existing id never moves, a new id lands last", () => {
  const order = ["a", "b", "c"];
  assert.deepEqual(appendCard(order, "b"), ["a", "b", "c"], "appending an id already present does not reorder it");
  assert.deepEqual(appendCard(order, "d"), ["a", "b", "c", "d"], "a new id is appended at the end");
  assert.deepEqual(order, ["a", "b", "c"], "the input array is never mutated");
});

test("removeCard drops exactly the named id and nothing else", () => {
  assert.deepEqual(removeCard(["a", "b", "c"], "b"), ["a", "c"]);
  assert.deepEqual(removeCard(["a", "b", "c"], "z"), ["a", "b", "c"], "removing an absent id is a harmless copy");
});

test("swapCards exchanges exactly two positions and leaves the rest untouched", () => {
  const order = ["a", "b", "c", "d"];
  assert.deepEqual(swapCards(order, "a", "c"), ["c", "b", "a", "d"]);
  assert.deepEqual(order, ["a", "b", "c", "d"], "the input array is never mutated");
});

test("swapCards is a no-op copy when an id is missing or the two ids are the same", () => {
  const order = ["a", "b", "c"];
  assert.deepEqual(swapCards(order, "a", "z"), ["a", "b", "c"], "missing target id: unchanged copy");
  assert.deepEqual(swapCards(order, "z", "a"), ["a", "b", "c"], "missing source id: unchanged copy");
  assert.deepEqual(swapCards(order, "a", "a"), ["a", "b", "c"], "swapping an id with itself: unchanged copy");
  const result = swapCards(order, "a", "z");
  assert.notEqual(result, order, "still a fresh array, not the same reference");
});

test("reconcileCardOrder preserves the user's arrangement, drops dead ids, and appends new ones at the end", () => {
  const order = ["c", "a", "b"];
  const live = ["a", "b", "c", "d"];
  assert.deepEqual(reconcileCardOrder(order, live), ["c", "a", "b", "d"]);
});

test("reconcileCardOrder drops ids that are no longer live, leaving no gap", () => {
  assert.deepEqual(reconcileCardOrder(["a", "b", "c"], ["a", "c"]), ["a", "c"]);
});

test("reconcileCardOrder de-duplicates both the recorded order and the live list", () => {
  assert.deepEqual(reconcileCardOrder(["a", "a", "b"], ["a", "b", "b", "c"]), ["a", "b", "c"]);
});

test("reconcileCardOrder never mutates its inputs", () => {
  const order = ["c", "a"];
  const live = ["a", "b", "c"];
  reconcileCardOrder(order, live);
  assert.deepEqual(order, ["c", "a"]);
  assert.deepEqual(live, ["a", "b", "c"]);
});

test("pure functions do not mutate the state objects passed to the pager API", () => {
  const state = dockPagerState(2, 4);
  const frozen = Object.freeze({ ...state });
  assert.doesNotThrow(() => requestPage(frozen, 1, 6));
  assert.doesNotThrow(() => requestPageTo(frozen, 0, 6));
  assert.doesNotThrow(() => settlePage(frozen));
  assert.doesNotThrow(() => pagerIsMoving(frozen));
  assert.deepEqual(frozen, { index: 2, target: 4 }, "the original state object is untouched");
});
