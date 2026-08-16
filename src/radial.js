import { Rational, civilFromDays, daysFromCivil } from "./exact.js";
import { eventCycleWindow, resolveEventCycle } from "./event-cycle.js";

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
  { id: "fixed:week", title: "Week", days: "7" }
]);

export function cyclePeriodHint(magnitude) {
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

function addGregorianMonths(civil, count) {
  const index = civil.year * 12n + civil.month - 1n + BigInt(count);
  return { year: index / 12n, month: index % 12n + 1n };
}

/**
 * Resolve the interval that Radial is allowed to draw.  A period expressed in
 * fixed day/week/hour levels is always safe.  A Gregorian month is variable,
 * but its two adjacent boundaries are fully described by the current schema,
 * so it can be resolved around the current focus without pretending that a
 * month has a mean number of days.  Formula- and event-defined cycles remain
 * intentionally unsupported until the schema exposes their boundaries.
 */
export function resolveRadialCycle(options, activeCycle, focus = null) {
  const choice = options.find((cycle) => cycle.id === activeCycle) || options[0] || null;
  if (!choice) return null;
  const fixed = cyclePeriodHint(choice.period || { value: choice.value?.levels })
    || (choice.days ? positiveRadialCycle(choice.days) : null);
  if (fixed) return { id: choice.id, period: fixed, dynamic: false, unsupported: false };

  if (choice.period?.kind === "event-defined" && focus !== null) {
    const resolved = resolveEventCycle(choice.period, focus);
    if (resolved.resolved) return { id: choice.id, ...resolved, dynamic: true, eventDefined: true, unsupported: false };
    return { id: choice.id, period: null, dynamic: false, unsupported: true, error: resolved.error };
  }

  const levels = choice.period?.value?.levels || choice.value?.levels;
  const monthCount = Array.isArray(levels) && levels.length === 1 && levels[0]?.level === "month"
    ? Number(levels[0].value)
    : 0;
  if (focus && Number.isInteger(monthCount) && monthCount > 0 && monthCount <= 24) {
    try {
      const civil = civilFromDays(Rational.parse(focus).floor());
      const startMonth = { year: civil.year, month: civil.month };
      const endMonth = addGregorianMonths(startMonth, monthCount);
      const start = new Rational(daysFromCivil(startMonth.year, startMonth.month, 1n));
      const end = new Rational(daysFromCivil(endMonth.year, endMonth.month, 1n));
      return {
        id: choice.id, period: end.sub(start), start, end,
        anchor: startMonth, monthCount, dynamic: true, unsupported: false
      };
    } catch {
      // Fall through to the explicit unsupported state.
    }
  }
  return { id: choice.id, period: null, dynamic: false, unsupported: true };
}

/** Return exact calendar boundaries for the visible dynamic spiral window. */
export function radialCycleWindow(resolution, past = 0, future = 0) {
  if (resolution?.eventDefined) {
    const window = eventCycleWindow({ kind: "event-defined", frame: resolution.frame, boundaries: resolution.boundaries.map((boundary) => ({ ...boundary, at: boundary.at.toJSON() })) }, resolution.start, past, future);
    return window.resolved ? { start: window.windowStart, end: window.windowEnd } : null;
  }
  if (!resolution?.dynamic || !resolution.anchor || !Number.isInteger(resolution.monthCount)) return null;
  try {
    const before = Math.max(0, Math.floor(Number(past)));
    const after = Math.max(0, Math.floor(Number(future)));
    const startMonth = addGregorianMonths(resolution.anchor, -resolution.monthCount * before);
    const endMonth = addGregorianMonths(resolution.anchor, resolution.monthCount * (after + 1));
    return {
      start: new Rational(daysFromCivil(startMonth.year, startMonth.month, 1n)),
      end: new Rational(daysFromCivil(endMonth.year, endMonth.month, 1n))
    };
  } catch {
    return null;
  }
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

// Persist the user's choice where possible. Only reduce an explicit major
// interval when its tick count makes that interval impossible to render.
export function normalizeRadialGuideValues(settings) {
  const requestedDivisions = Math.floor(Number(settings.radialDivisions));
  const radialDivisions = Number.isFinite(requestedDivisions)
    ? Math.max(0, Math.min(64, requestedDivisions))
    : 0;
  const requestedMajor = Math.floor(Number(settings.radialMajorEvery));
  let radialMajorEvery = Number.isFinite(requestedMajor)
    ? Math.max(0, Math.min(64, requestedMajor))
    : 0;
  const guide = radialGuideSettings({ ...settings, radialDivisions, radialMajorEvery });
  if (radialMajorEvery > guide.divisions) radialMajorEvery = guide.divisions;
  return { radialDivisions, radialMajorEvery };
}

export function radialRenderState(factCount, truncated) {
  if (truncated) return "dense";
  return factCount > 0 ? "ordinary" : "empty";
}
