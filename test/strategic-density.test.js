import test from "node:test";
import assert from "node:assert/strict";
import { aggregateStrategicDays, stableStrategicFacts } from "../src/strategic-density.js";

function fact(id, day) {
  return { event: { id }, day: String(day) };
}

test("dense Strategic aggregation keeps every day represented with stable per-day facts", () => {
  const plan = aggregateStrategicDays({
    start: 10,
    end: 13,
    perDayLimit: 2,
    queryDay(day, _after, limit) {
      assert.equal(limit, 2);
      const values = {
        10: [fact("b", 10), fact("a", 10)],
        11: [fact("late", 11)],
        12: [fact("d", 12), fact("c", 12)]
      }[day.toString()] || [];
      return { facts: values, truncated: day === 10n || day === 12n, errors: [] };
    }
  });
  assert.deepEqual(plan.days.map((entry) => entry.day), ["10", "11", "12"]);
  assert.deepEqual(plan.days.map((entry) => entry.facts.map((item) => item.event.id)), [
    ["a", "b"], ["late"], ["c", "d"]
  ]);
  assert.deepEqual(plan.days.map((entry) => [entry.truncated, entry.shown, entry.minimum]), [
    [true, 2, 3], [false, 1, 1], [true, 2, 3]
  ]);
});

test("stable Strategic sorting has a deterministic tie-breaker beyond day", () => {
  assert.deepEqual(stableStrategicFacts([fact("z", "4"), fact("a", "4"), fact("m", "3")])
    .map((item) => item.event.id), ["m", "a", "z"]);
});
