import assert from "node:assert/strict";
import test from "node:test";
import { minimapDotGrid, minimapEventMagnitude } from "../src/minimap.js";

test("minimap magnitude uses a fixed event, staple, duration, and importance scale", () => {
  assert.equal(minimapEventMagnitude(), 1);
  assert.equal(minimapEventMagnitude({ durationDays: 2, stapleCount: 2 }), 5);
  assert.equal(minimapEventMagnitude({ durationDays: 2, stapleCount: 2, importance: "important" }), 8);
  assert.equal(minimapEventMagnitude({ durationDays: 2, stapleCount: 2, importance: "landmark" }), 12.5);
});

test("dot field always lights its center and grows vertically before spilling sideways", () => {
  const magnitude = new Float32Array(9);
  magnitude[4] = 1;
  const ordinary = minimapDotGrid(magnitude, { rows: 5, dotsPerMagnitude: 2 });
  for (let column = 0; column < ordinary.columns; column += 1) {
    assert.equal(ordinary.cells[ordinary.center * ordinary.columns + column], 1);
  }
  assert.equal(ordinary.cells[(ordinary.center - 1) * ordinary.columns + 4], 1);
  assert.equal(ordinary.cells[(ordinary.center + 1) * ordinary.columns + 4], 1);
  assert.equal(ordinary.cells[(ordinary.center - 1) * ordinary.columns + 3], 0);

  magnitude[4] = 3;
  const dense = minimapDotGrid(magnitude, { rows: 5, dotsPerMagnitude: 2 });
  for (let row = 0; row < dense.rows; row += 1) assert.equal(dense.cells[row * dense.columns + 4], 1);
  assert.equal(dense.cells[(dense.center - 1) * dense.columns + 3], 1);
  assert.equal(dense.cells[(dense.center + 1) * dense.columns + 3], 1);
});

test("moving equal magnitude between dates never changes its apparent dot count", () => {
  const left = new Float32Array(12);
  const right = new Float32Array(12);
  left[2] = 2.5;
  right[9] = 2.5;
  const litCount = (grid) => [...grid.cells].filter(Boolean).length;
  assert.equal(litCount(minimapDotGrid(left)), litCount(minimapDotGrid(right)));
});
