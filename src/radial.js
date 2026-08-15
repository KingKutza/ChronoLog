import { Rational } from "./exact.js";

const FIXED_LEVEL_DAYS = {
  week: "7",
  day: "1",
  hour: "1/24",
  minute: "1/1440",
  second: "1/86400"
};

export const FIXED_RADIAL_CYCLES = Object.freeze([
  { id: "fixed:day", title: "Day", days: "1" },
  { id: "fixed:work-week", title: "Work week", days: "5" },
  { id: "fixed:week", title: "Week", days: "7" },
  { id: "fixed:month", title: "Month (fixed mean · 30.436875 days)", days: "243495/8000" },
  { id: "fixed:quarter", title: "Quarter (fixed mean · 91.310625 days)", days: "146097/1600" },
  { id: "fixed:year", title: "Year (fixed mean · 365.2425 days)", days: "146097/400" }
]);

export function fixedCycleDays(magnitude) {
  const levels = magnitude?.value?.levels;
  if (!Array.isArray(levels) || levels.length === 0) return null;
  let total = Rational.parse(0);
  try {
    for (const part of levels) {
      const factor = FIXED_LEVEL_DAYS[part.level];
      if (factor === undefined) return null;
      total = total.add(Rational.parse(part.value).mul(factor));
    }
  } catch {
    return null;
  }
  return total.compare(0) > 0 ? total : null;
}

export function resolveRadialCycle(options, activeCycle) {
  const choice = options.find((cycle) => cycle.id === activeCycle) || options[0] || null;
  return choice ? { id: choice.id, period: positiveRadialCycle(choice.days) } : null;
}

export function positiveRadialCycle(value, fallback = "29.530588853") {
  try {
    const cycle = Rational.parse(value);
    if (cycle.compare(0) > 0) return cycle;
  } catch {
    // A persisted view value must not prevent the application from opening.
  }
  return Rational.parse(fallback);
}

export function radialGuideSettings(session) {
  const cycleDays = positiveRadialCycle(session.radialCycle).toNumber();
  const requestedDivisions = Math.floor(Number(session.radialDivisions));
  const divisions = Number.isFinite(requestedDivisions) && requestedDivisions > 0
    ? Math.min(64, requestedDivisions)
    : cycleDays >= 5 ? Math.max(1, Math.min(64, Math.round(cycleDays))) : 24;
  const requestedMajor = Math.floor(Number(session.radialMajorEvery));
  const majorEvery = Number.isFinite(requestedMajor) && requestedMajor > 0
    ? Math.min(divisions, requestedMajor)
    : cycleDays >= 20 ? Math.min(divisions, 7)
    : cycleDays >= 5 ? 1 : Math.max(1, Math.round(divisions / 4));
  const dayNight = session.radialMarks === "day-night"
    || (session.radialMarks === "auto" && (cycleDays <= 2 || cycleDays >= 20));
  return { cycleDays, divisions, majorEvery, dayNight };
}

export function radialRenderState(factCount, truncated) {
  if (truncated) return "dense";
  return factCount > 0 ? "ordinary" : "empty";
}
