import test from "node:test";
import assert from "node:assert/strict";
import { buildFixedCalendarStructure } from "../src/calendar-structure.js";
import { fixedCalendarParts, fixedDayLabel, fixedMonthWindow } from "../src/calendar-projection.js";

function skyland() {
  const built = buildFixedCalendarStructure({
    units: [
      { name: "year" },
      { name: "month", perParent: "8", labels: "Frost, Rain, Bloom, Sun, Heat, Harvest, Leaf, Snow" },
      { name: "week", perParent: "8" },
      { name: "day", perParent: "8", labels: "First, Second, Third, Fourth, Fifth, Sixth, Seventh, Eighth" }
    ],
    smallestUnitDays: "1",
    epochDays: "100"
  });
  return { id: "calendar:skyland", traits: ["set", "calendar"], ...built };
}

test("Skyland fixed projection renders named 8 × 8 × 8 units from its explicit epoch", () => {
  const frame = skyland();
  assert.equal(frame.coordinate.fixed.epochDays, "100");
  assert.equal(frame.period.value.levels[0].value, "512");
  assert.deepEqual(fixedCalendarParts(frame, "100").parts.map((part) => part.label || part.value.toString()), ["1", "Frost", "1", "First"]);
  assert.deepEqual(fixedCalendarParts(frame, "163").parts.map((part) => part.label || part.value.toString()), ["1", "Frost", "8", "Eighth"]);
  assert.deepEqual(fixedCalendarParts(frame, "164").parts.map((part) => part.label || part.value.toString()), ["1", "Rain", "1", "First"]);
  assert.match(fixedDayLabel(frame, "164"), /First.*week 1.*Rain/);
});

test("Skyland month windows use authored 64-day months, not Gregorian month lengths", () => {
  const frame = skyland();
  const months = fixedMonthWindow(frame, "164", 3);
  assert.equal(months.length, 3);
  assert.deepEqual(months.map((month) => month.span.toString()), ["64", "64", "64"]);
  assert.deepEqual(months.map((month) => month.start.toString()), ["100", "164", "228"]);
});
