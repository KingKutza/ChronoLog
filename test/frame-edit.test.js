import test from "node:test";
import assert from "node:assert/strict";
import { additiveFrameTraits, frameAuthoringCapabilities, preservedFrameSchema } from "../src/frame-edit.js";
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
    ], smallestUnitDays: "1", epochDays: "0", periodFrame: "measure:human-time", totalDays: "512"
  });
});

test("fixed calendar editor rejects ambiguous hierarchy input and leaves non-fixed schemas alone", () => {
  assert.throws(() => buildFixedCalendarStructure({
    units: [{ name: "year" }, { name: "month", perParent: "8.5" }]
  }), /positive whole number/);
  // A count refusal states BOTH numbers and names the unit. The old wording
  // ("must contain exactly one name for each month") told an author their list
  // was wrong without ever showing them what it was measured against.
  assert.throws(() => buildFixedCalendarStructure({
    units: [{ name: "year" }, { name: "month", perParent: "8", labels: "one, two" }]
  }), /month names needs 8 names, one for each month; 2 were given\./);
  assert.equal(editableFixedCalendarStructure({ coordinate: { kind: "nested", levels: [{ name: "moon" }] } }), null);
});

test("fixed calendar editor does not offer to overwrite an advanced period", () => {
  const fixed = buildFixedCalendarStructure({ units: [{ name: "year" }, { name: "month", perParent: "8" }] });
  assert.equal(editableFixedCalendarStructure({
    coordinate: fixed.coordinate,
    period: { frame: "calendar:moon", value: { eventSeries: "new-moon" } }
  }), null);
});

test("frame authoring exposes temporal controls only to temporal capabilities", () => {
  assert.deepEqual(frameAuthoringCapabilities("group"), {
    basis: false, calendarStructure: false, fixedCalendar: false, observedBoundaries: false, coordinate: false, periodData: false
  });
  assert.deepEqual(frameAuthoringCapabilities("importance"), {
    basis: false, calendarStructure: false, fixedCalendar: false, observedBoundaries: false, coordinate: false, periodData: false
  });
  assert.deepEqual(frameAuthoringCapabilities("calendar"), {
    basis: true, calendarStructure: true, fixedCalendar: true, observedBoundaries: true, coordinate: true, periodData: true
  });
  assert.equal(frameAuthoringCapabilities("cycle").observedBoundaries, true);
  assert.equal(frameAuthoringCapabilities("line").coordinate, true);
  // Structure authoring follows the coordinate capability, not the "calendar"
  // kind: `frame:wall-time` is a LINE and is also the frame every derived
  // calendar inherits its structure from.
  assert.equal(frameAuthoringCapabilities("line").calendarStructure, true);
  assert.equal(frameAuthoringCapabilities("line").fixedCalendar, true);
  assert.equal(frameAuthoringCapabilities("group", ["set", "group", "cycle"]).observedBoundaries, true);
});
