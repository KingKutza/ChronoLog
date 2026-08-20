import { Rational, civilFromDays, daysFromCivil } from "./exact.js";
import { CoordinateLaw, GREGORIAN_LAW, magnitudeLaw } from "./coordinate-law.js";
import { eventCycleWindow, resolveEventCycle } from "./event-cycle.js";

export const FIXED_RADIAL_CYCLES = Object.freeze([
  { id: "fixed:day", title: "Day", days: "1" },
  { id: "fixed:work-week", title: "Work week", days: "5" },
  { id: "fixed:week", title: "Week", days: "7" }
]);

// `governing` is the document a cycle's period is authored against (its own
// `magnitude.frame`, normally `measure:human-time`), a CoordinateLaw
// directly, or nothing -- resolving to the registered standard, exactly the
// FIXED_LEVEL_DAYS table this replaces ({week:"7", day:"1", hour:"1/24", ...}
// was a second, duplicate copy of the same factors src/exact.js used to
// carry). `magnitudeLaw` (coordinate-law.js) does the resolution.
//
// Radial's contract is stricter than a plain duration
// (`law.magnitudeDays`, which is tolerant and returns a mean-based 0/total):
// this must refuse to draw a cycle it cannot resolve EXACTLY. `law.unitDays`
// is null for precisely the levels whose length varies under this law (a
// Gregorian month) or that this law does not declare and has no standard
// fallback for, so checking each level's `unitDays` individually -- rather
// than delegating to `magnitudeDays` -- is what keeps a month-only magnitude
// unsupported here while still being a legitimate duration elsewhere.
export function cyclePeriodHint(magnitude, governing = null) {
  const levels = magnitude?.value?.levels;
  if (!Array.isArray(levels) || levels.length === 0) return null;
  const law = magnitudeLaw(magnitude, governing);
  let total = Rational.parse(0);
  try {
    for (const part of levels) {
      const factor = law.unitDays(part.level);
      if (factor === null) return null;
      total = total.add(Rational.parse(part.value).mul(factor));
    }
  } catch {
    return null;
  }
  return total.compare(0) > 0 ? total : null;
}

// This walk and the `daysFromCivil` boundary lookups below it are the
// registered Gregorian ladder's OWN month-boundary arithmetic (the 400-year
// era formula), not something a generic positional conversion can derive
// from per-level counts. Generic positional conversion for a custom,
// non-Gregorian ladder (a frame authoring its own multi-level calendar with
// variable-length units) is explicitly out of scope for this wave -- see
// CoordinateLaw.toDays's own comment on the same limitation.
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
export function resolveRadialCycle(options, activeCycle, focus = null, governing = null) {
  const choice = options.find((cycle) => cycle.id === activeCycle) || options[0] || null;
  if (!choice) return null;
  const fixed = cyclePeriodHint(choice.period || { value: choice.value?.levels }, governing)
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
  // `session` is usually a live ViewSession (`session.law` always set), but
  // this also runs against a bare persisted-values object (see
  // normalizeRadialGuideValues below and this module's own tests) that
  // carries no law at all -- falls back to the registered standard rather
  // than throwing on `session.law.hoursPerDay`.
  const law = session?.law instanceof CoordinateLaw ? session.law : GREGORIAN_LAW;
  const hoursPerDay = Math.max(1, Math.min(64, Math.round(law.hoursPerDay().toNumber())));
  const cycleDays = positiveRadialCycle(session.radialCycle).toNumber();
  const requestedDivisions = Math.floor(Number(session.radialDivisions));
  const divisions = Number.isFinite(requestedDivisions) && requestedDivisions > 0
    ? Math.min(64, requestedDivisions)
    // One tick per hour when the cycle is about a day long, in THIS law's
    // hours -- a 23-hour day gets 23 ticks around the ring, not 24 with one
    // that marks nothing.
    : cycleDays >= 5 ? Math.max(1, Math.min(64, Math.round(cycleDays))) : hoursPerDay;
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

/**
 * Convert a center, radius, and angle (radians, 0 = +x axis, increasing
 * clockwise per the on-screen convention every radial-family lens uses) into
 * a Cartesian point. Shared by the ring/spiral tick, label, and arc geometry
 * in the renderer.
 */
export function polar(cx, cy, radius, angle) {
  return [cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius];
}

/**
 * The SVG path for one circular arc from startAngle to endAngle (the Radial
 * ring lens). The two endpoints already sit exactly on the radial rays of
 * startAngle/endAngle -- for a circle, the tangent at any point is exactly
 * perpendicular to that point's radius, so a `stroke-linecap: butt` cap
 * (perpendicular to the tangent) lands exactly along the radial ray, with no
 * angular overshoot or shortfall past the arc's true start/stop date. `round`
 * and `square` caps both bulge the rendered mark past this path's already-
 * exact endpoint along the tangent direction, which is the rounded-edge bug:
 * they make the arc visually extend past the date it actually ends on.
 * Whether the stroke actually terminates flush is therefore a linecap choice
 * the renderer makes, not something this path's geometry needs to change to
 * accommodate.
 */
export function arcPath(cx, cy, radius, startAngle, endAngle) {
  const [x1, y1] = polar(cx, cy, radius, startAngle);
  const [x2, y2] = polar(cx, cy, radius, endAngle);
  const large = endAngle - startAngle > Math.PI ? 1 : 0;
  return `M ${x1.toFixed(2)} ${y1.toFixed(2)} A ${radius.toFixed(2)} ${radius.toFixed(2)} 0 ${large} 1 ${x2.toFixed(2)} ${y2.toFixed(2)}`;
}

/**
 * The closed outline of the Spiral lens's own timeline ribbon (the track,
 * not an event) -- a filled polygon rather than a stroked open path, offset
 * by `halfWidth` along each sample's RADIUS instead of perpendicular to the
 * path's local tangent.
 *
 * A stroked path's cap can only ever cut perpendicular to its own tangent at
 * the endpoint; on a spiral that tangent is a mix of angular and radial
 * travel (the spiral's pitch), so no native `stroke-linecap` -- round, butt,
 * or square -- can land exactly on the vertical ray the track starts/stops
 * on, only near it. Radial offset sidesteps the tangent question entirely:
 * `turns` is always a non-negative integer (`ViewSession` floors
 * radialPast/radialFuture), so progress 0 and progress 1 land on the exact
 * same ray (-PI/2 mod 2*PI radians). The two boundary points at each end
 * therefore share that angle and differ only in radius, so the segment
 * directly joining them is, by construction, colinear with the ray -- an
 * exact flat terminus, not a rendering approximation of one.
 *
 * This is deliberately a different geometry strategy than an event mark's
 * own path (see `renderRadial`'s spiral event loop in projections.js, which
 * draws a constant-radius `arcPath` per event so its tangent is exactly
 * perpendicular to its own radius): the track is one continuous multi-turn
 * ribbon whose ends must read as flush cuts, while an event is a point-in-
 * time mark whose rounded ends are the desired sigil, not a bug. Conflating
 * the two into one cap decision is exactly the regression this fixes.
 */
export function spiralRibbonPath(cx, cy, inner, spacing, turns, samples, halfWidth) {
  const outerEdge = [];
  const innerEdge = [];
  for (let index = 0; index <= samples; index += 1) {
    const progress = index / samples;
    const angle = -Math.PI / 2 + progress * turns * Math.PI * 2;
    const radius = inner + progress * turns * spacing;
    outerEdge.push(polar(cx, cy, radius + halfWidth, angle));
    innerEdge.push(polar(cx, cy, Math.max(0, radius - halfWidth), angle));
  }
  let d = "";
  outerEdge.forEach(([x, y], index) => {
    d += `${index ? "L" : "M"}${x.toFixed(2)} ${y.toFixed(2)} `;
  });
  for (let index = innerEdge.length - 1; index >= 0; index -= 1) {
    const [x, y] = innerEdge[index];
    d += `L${x.toFixed(2)} ${y.toFixed(2)} `;
  }
  return `${d}Z`;
}
