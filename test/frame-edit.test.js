import test from "node:test";
import assert from "node:assert/strict";
import { additiveFrameTraits, preservedFrameSchema } from "../src/frame-edit.js";

test("editing a leading frame preserves composable traits and untouched coordinate structure", () => {
  const previous = {
    traits: ["set", "calendar", "line", "cycle", "custom-law"],
    coordinate: { nesting: [{ level: "moon", children: [{ level: "phase" }] }] },
    period: { frame: "calendar:moon", value: { eventSeries: "new-moon" } }
  };
  assert.deepEqual(
    additiveFrameTraits("group", ["group"], previous.traits),
    ["set", "calendar", "line", "cycle", "custom-law", "group"]
  );
  assert.deepEqual(preservedFrameSchema(previous), {
    coordinate: previous.coordinate,
    period: previous.period
  });
});
