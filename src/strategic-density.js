import { Rational } from "./exact.js";

// Strategic is deliberately a topology view.  A very dense calendar should
// still show *where* activity exists instead of allowing the first busy week
// to consume the entire renderer's fact allowance.
export const STRATEGIC_DAY_FACT_LIMIT = 48;

export function stableStrategicFactKey(fact) {
  return [
    Rational.parse(fact.day).toJSON(),
    fact.event?.id || "",
    fact.virtualId || "",
    fact.relation?.id || ""
  ].join("\u0000");
}

export function stableStrategicFacts(facts) {
  return [...facts].sort((left, right) => stableStrategicFactKey(left).localeCompare(stableStrategicFactKey(right)));
}

// The callback is intentionally small and synchronous: the engine is already
// synchronous, and keeping the bucketing rule here makes it testable without
// a DOM.  `truncated` means the displayed count is a lower bound, not that a
// later date quietly vanished from the Strategic view.
export function aggregateStrategicDays({ start, end, queryDay, perDayLimit = STRATEGIC_DAY_FACT_LIMIT }) {
  const first = Rational.parse(start).floor();
  const after = Rational.parse(end).ceil();
  const days = [];
  const errors = [];
  for (let day = first; day < after; day += 1n) {
    const result = queryDay(day, day + 1n, perDayLimit);
    const facts = stableStrategicFacts(result.facts || []);
    days.push({
      day: day.toString(),
      facts,
      truncated: Boolean(result.truncated),
      shown: facts.length,
      minimum: facts.length + (result.truncated ? 1 : 0)
    });
    for (const error of result.errors || []) errors.push(error);
  }
  const uniqueErrors = [...new Map(errors.map((error) => [
    `${error.pattern || ""}\u0000${error.message || ""}`,
    error
  ])).values()];
  return { days, errors: uniqueErrors, perDayLimit };
}
