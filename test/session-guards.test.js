import test from "node:test";
import assert from "node:assert/strict";
import {
  minimapDragFocus,
  minimapDragState,
  sanitizeSessionParameters
} from "../src/session.js";

const documentValue = {
  frames: {
    "calendar:main": { id: "calendar:main", traits: ["set", "calendar"] },
    "cycle:lunar": { id: "cycle:lunar", traits: ["set", "cycle"] }
  }
};

test("malformed or out-of-range scale parameters never reach the session", () => {
  assert.deepEqual(sanitizeSessionParameters(new URLSearchParams("scale=foo"), documentValue), {});
  assert.deepEqual(sanitizeSessionParameters(new URLSearchParams("scale=Infinity"), documentValue), {});
  assert.deepEqual(sanitizeSessionParameters(new URLSearchParams("scale=NaN"), documentValue), {});
  assert.deepEqual(sanitizeSessionParameters(new URLSearchParams("scale=9"), documentValue), { scale: 2 });
  assert.deepEqual(sanitizeSessionParameters(new URLSearchParams("scale=-3"), documentValue), { scale: 0 });
  assert.deepEqual(sanitizeSessionParameters(new URLSearchParams("scale=1.5"), documentValue), { scale: 1.5 });
});

test("frame, projection, and radial parameters are honored only when legal", () => {
  assert.deepEqual(sanitizeSessionParameters(new URLSearchParams("frame=typo"), documentValue), {});
  assert.deepEqual(
    sanitizeSessionParameters(new URLSearchParams("frame=calendar:main"), documentValue),
    { activeFrame: "calendar:main", primeFrame: "calendar:main" }
  );
  assert.deepEqual(sanitizeSessionParameters(new URLSearchParams("projection=bogus"), documentValue), {});
  assert.deepEqual(
    sanitizeSessionParameters(new URLSearchParams("projection=lines"), documentValue),
    { projection: "lines" }
  );
  assert.deepEqual(sanitizeSessionParameters(new URLSearchParams("radial=bogus"), documentValue), {});
  assert.deepEqual(
    sanitizeSessionParameters(new URLSearchParams("radial=concentric"), documentValue),
    { radialMode: "concentric" }
  );
  assert.deepEqual(
    sanitizeSessionParameters(new URLSearchParams("frame=calendar:main&scale=0.25&projection=wall&radial=spiral"), documentValue),
    { activeFrame: "calendar:main", primeFrame: "calendar:main", projection: "wall", scale: 0.25, radialMode: "spiral" }
  );
});

test("grabbing the minimap thumb keeps focus put and drags like a scrollbar", () => {
  const drag = minimapDragState({ start: "0", end: "100", focus: "50", visibleSpan: 20, fraction: 0.55 });
  assert.equal(drag.focus.toNumber(), 50);
  assert.ok(Math.abs(drag.grabOffset - 0.05) < 1e-12);
  const moved = minimapDragFocus(drag, 0.65);
  assert.ok(Math.abs(moved.toNumber() - 60) < 1e-9);
  const held = minimapDragFocus(drag, 0.65);
  assert.equal(held.compare(moved), 0);
});

test("pressing the minimap track jumps focus and clamps to the frozen strip", () => {
  const drag = minimapDragState({ start: "0", end: "100", focus: "50", visibleSpan: 20, fraction: 0.9 });
  assert.equal(drag.grabOffset, 0);
  assert.ok(Math.abs(drag.focus.toNumber() - 90) < 1e-9);
  assert.equal(minimapDragFocus(drag, 4).toNumber(), 100);
  assert.equal(minimapDragFocus(drag, -1).toNumber(), 0);
});

test("a degenerate frozen strip never divides by zero", () => {
  const drag = minimapDragState({ start: "10", end: "10", focus: "10", visibleSpan: 0, fraction: 0.5 });
  assert.equal(minimapDragFocus(drag, 0.75).toNumber(), 10);
});
