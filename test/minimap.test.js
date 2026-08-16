import assert from "node:assert/strict";
import test from "node:test";
import { sampleIndexedRanges } from "../src/minimap.js";

test("bounded minimap samples retain both past and future activity", () => {
  const entries = Array.from({ length: 5000 }, (_, day) => ({ day }));
  const sample = sampleIndexedRanges([{ entries, start: 0, end: entries.length }], 5);
  assert.deepEqual(sample.map((entry) => entry.day), [0, 1249, 2499, 3749, 4999]);
});

test("minimap sampling preserves complete small ranges and selected bounds", () => {
  const first = Array.from({ length: 5 }, (_, day) => ({ source: "first", day }));
  const second = Array.from({ length: 5 }, (_, day) => ({ source: "second", day }));
  assert.deepEqual(
    sampleIndexedRanges([
      { entries: first, start: 1, end: 4 },
      { entries: second, start: 2, end: 5 }
    ], 10),
    [...first.slice(1, 4), ...second.slice(2, 5)]
  );
});
