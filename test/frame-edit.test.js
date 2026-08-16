import test from "node:test";
import assert from "node:assert/strict";
import { additiveFrameTraits, preservedFrameSchema } from "../src/frame-edit.js";
import { buildFixedCalendarStructure, editableFixedCalendarStructure } from "../src/calendar-structure.js";

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

test("fixed calendar editor writes an exact Skyland hierarchy and round-trips it", () => {
  const built = buildFixedCalendarStructure({
    units: [
      { name: "year" }, { name: "month", perParent: "8", labels: "Frost, Rain, Bloom, Sun, Heat, Harvest, Leaf, Snow" },
      { name: "week", perParent: "8" }, { name: "day", perParent: "8", labels: "First, Second, Third, Fourth, Fifth, Sixth, Seventh, Eighth" }
    ],
    smallestUnitDays: "1"
  });
  assert.equal(built.totalDays, "512");
  assert.deepEqual(built.coordinate.levels, [
    { name: "year" }, { name: "month", within: "year", radix: "8", names: ["Frost", "Rain", "Bloom", "Sun", "Heat", "Harvest", "Leaf", "Snow"] },
    { name: "week", within: "month", radix: "8" }, { name: "day", within: "week", radix: "8", names: ["First", "Second", "Third", "Fourth", "Fifth", "Sixth", "Seventh", "Eighth"] }
  ]);
  assert.deepEqual(editableFixedCalendarStructure(built), {
    units: [
      { name: "year" }, { name: "month", perParent: "8", labels: "Frost, Rain, Bloom, Sun, Heat, Harvest, Leaf, Snow" },
      { name: "week", perParent: "8" }, { name: "day", perParent: "8", labels: "First, Second, Third, Fourth, Fifth, Sixth, Seventh, Eighth" }
    ], smallestUnitDays: "1", periodFrame: "measure:human-time", totalDays: "512"
  });
});

test("fixed calendar editor rejects ambiguous hierarchy input and leaves non-fixed schemas alone", () => {
  assert.throws(() => buildFixedCalendarStructure({
    units: [{ name: "year" }, { name: "month", perParent: "8.5" }]
  }), /positive whole number/);
  assert.throws(() => buildFixedCalendarStructure({
    units: [{ name: "year" }, { name: "month", perParent: "8", labels: "one, two" }]
  }), /exactly one name/);
  assert.equal(editableFixedCalendarStructure({ coordinate: { kind: "nested", levels: [{ name: "moon" }] } }), null);
});

test("fixed calendar editor does not offer to overwrite an advanced period", () => {
  const fixed = buildFixedCalendarStructure({ units: [{ name: "year" }, { name: "month", perParent: "8" }] });
  assert.equal(editableFixedCalendarStructure({
    coordinate: fixed.coordinate,
    period: { frame: "calendar:moon", value: { eventSeries: "new-moon" } }
  }), null);
});
