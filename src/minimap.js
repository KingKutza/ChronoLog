import { Rational, civilFromDays, daysFromCivil, floorDiv, floorMod } from "./exact.js";

// Minimap magnitude, dot-field geometry, and label granularity. No DOM code
// lives here, so the whole visual contract is testable; `renderMinimap` in
// projections.js is the only consumer and does nothing but draw what these
// functions decide.
//
// Rows: 25, read as one always-lit baseline row plus 24 activity rows. 24 is
// the reason for the choice — it divides by 2, 3, 4, 6, 8 and 12, so quarter,
// third and half guide bands land exactly on rows instead of between them, and
// an odd total keeps a true middle row for the field's visual centre. Against
// the previous 11 rows that is 2.27x the rows; paired with 288 buckets it is
// 4.7x the dots of the old 11x140 field, at slightly under half the old dot
// diameter.
export const MINIMAP_GRID_ROWS = 25;

// 288 buckets across the field. The minimap range is a fixed multiple of the
// lens's visible span, so bucket width follows the lens automatically: roughly
// four hours in Intimate, fifteen hours in Tactical, a day and a half in Wall,
// five days in Strategic. Every one of those is finer than the granularity the
// lens itself renders, which is what lets a busy bucket and a free bucket
// differ at a glance in every lens.
export const MINIMAP_BUCKETS = 288;

const IMPORTANCE_MULTIPLIER = Object.freeze({
  standard: 1,
  important: 1.6,
  landmark: 2.5
});

export function minimapEventMagnitude({ durationDays = 0, stapleCount = 0, importance = "standard" } = {}) {
  const duration = Math.max(0, Number(durationDays) || 0);
  const staples = Math.max(0, Math.floor(Number(stapleCount) || 0));
  const multiplier = IMPORTANCE_MULTIPLIER[importance] || IMPORTANCE_MULTIPLIER.standard;
  return (1 + staples + duration) * multiplier;
}

// The scale ladder. A dot field that renormalized to its own maximum on every
// pan would shimmer, and a single landmark event would flatten everything else;
// a scale fixed for all time cannot serve both an empty document and a hundred
// thousand events. So the ceiling is snapped to a coarse ladder: it changes
// only when the field's busy end crosses a rung, and between rungs the mapping
// is exactly position-independent.
export const MINIMAP_MAGNITUDE_LADDER = Object.freeze([
  1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024
]);

// The rung is chosen from the field's busy end rather than its maximum, so one
// exceptional bucket cannot squash the rest of the field. Buckets at or above
// the rung saturate, which is deliberate: saturation is what makes "busy" read
// instantly.
export const MINIMAP_BUSY_QUANTILE = 0.9;

export function minimapMagnitudeCeiling(magnitudes, quantile = MINIMAP_BUSY_QUANTILE) {
  const occupied = [];
  for (const value of magnitudes) {
    const magnitude = Math.max(0, Number(value) || 0);
    if (magnitude > 0) occupied.push(magnitude);
  }
  if (!occupied.length) return MINIMAP_MAGNITUDE_LADDER[0];
  occupied.sort((left, right) => left - right);
  const fraction = Math.max(0, Math.min(1, Number(quantile)));
  const index = Math.min(occupied.length - 1, Math.floor(fraction * occupied.length));
  const busy = occupied[index];
  return MINIMAP_MAGNITUDE_LADDER.find((rung) => rung >= busy)
    || MINIMAP_MAGNITUDE_LADDER[MINIMAP_MAGNITUDE_LADDER.length - 1];
}

// One column's dot height. Two guarantees compose here:
//
//   * every object in the bucket contributes at least one dot, up to the
//     field's capacity — that is the `count` floor, and it is why a bucket can
//     never look empty while holding objects;
//   * magnitude lifts the column further, so a long, repeatedly stapled or
//     important object is several dots rather than one.
//
// Above capacity the column clamps. Nothing spills sideways: the old field bled
// a full column's overflow into its neighbours, which smeared a single busy day
// across a week and destroyed exactly the contrast the field exists to show.
export function minimapColumnDots(magnitude, count, options = {}) {
  const capacity = Math.max(1, Math.floor(Number(options.capacity) || 1));
  const dotsPerMagnitude = Math.max(0, Number(options.dotsPerMagnitude) || 0);
  const scaled = Math.ceil(Math.max(0, Number(magnitude) || 0) * dotsPerMagnitude);
  const objects = Math.max(0, Math.floor(Number(count) || 0));
  return Math.min(capacity, Math.max(objects, scaled));
}

// The dot field: one column per bucket, growing upward from an always-lit
// baseline row. Bottom-anchored growth (rather than the old centre-out growth)
// spends all 24 activity rows on one comparable height instead of 12 mirrored
// pairs, which is what makes adjacent columns comparable at a glance.
export function minimapDotGrid(magnitudes, options = {}) {
  const columns = magnitudes.length;
  const rows = Math.max(3, Math.floor(Number(options.rows) || MINIMAP_GRID_ROWS));
  const baseline = rows - 1;
  const capacity = rows - 1;
  const counts = options.counts || [];
  const ceiling = Math.max(
    MINIMAP_MAGNITUDE_LADDER[0],
    Number(options.ceiling) || minimapMagnitudeCeiling(magnitudes, options.quantile)
  );
  const dotsPerMagnitude = capacity / ceiling;
  const cells = new Uint8Array(columns * rows);
  const columnDots = new Uint8Array(columns);
  for (let column = 0; column < columns; column += 1) {
    cells[baseline * columns + column] = 1;
    const dots = minimapColumnDots(magnitudes[column], counts[column], { capacity, dotsPerMagnitude });
    columnDots[column] = dots;
    for (let step = 1; step <= dots; step += 1) cells[(baseline - step) * columns + column] = 1;
  }
  return { cells, columns, rows, baseline, capacity, ceiling, dotsPerMagnitude, columnDots };
}

const MONTH_ABBREVIATIONS = Object.freeze([
  "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
]);

// The finest label level each lens may use. A lens never labels more finely
// than this, and the ladder below coarsens from here until the labels fit:
//
//   intimate  hour     never a year at any stride — the range is ~50 days
//   tactical  day      the day is Tactical's own unit
//   lines     day      same window family as Tactical
//   wall      month    months are the unit; the range crosses a year
//   strategic quarter  quarters are the unit at a 9-18 month window
//   spiral    month    a cycle multiple lands anywhere, so month is the finest
//   radial    month    level that stays honest across an arbitrary cycle
export const MINIMAP_LABEL_GRANULARITY = Object.freeze({
  intimate: "hour",
  tactical: "day",
  lines: "day",
  wall: "month",
  strategic: "quarter",
  spiral: "month",
  radial: "month"
});

export function minimapLabelGranularity(lens) {
  return MINIMAP_LABEL_GRANULARITY[lens] || "day";
}

// Each level's stride ladder. The text format follows the stride actually
// chosen, not the level asked for, so a lens tells the truth about what its
// labels mark: Intimate reads "Aug 18 12:00" when its window is narrow enough
// for half-day boundaries to fit and "Aug 18" when it is not, and never grows a
// year at either end because its ladder stops at week strides.
//
// The one place the level overrides the stride is `quarter`: its ladder is made
// of month strides, but every rung lands on a quarter boundary, so Strategic
// reads "Q1-26 Q2-26" whether it steps by one quarter or by five years.
const LABEL_LADDERS = Object.freeze({
  hour: Object.freeze([
    ["hour", 1], ["hour", 2], ["hour", 3], ["hour", 4], ["hour", 6], ["hour", 8], ["hour", 12],
    ["day", 1], ["day", 2], ["day", 7]
  ]),
  day: Object.freeze([
    ["day", 1], ["day", 2], ["day", 3], ["day", 7], ["day", 14], ["month", 1], ["month", 3]
  ]),
  month: Object.freeze([
    ["month", 1], ["month", 2], ["month", 3], ["month", 6], ["month", 12], ["month", 24]
  ]),
  quarter: Object.freeze([
    ["month", 3], ["month", 6], ["month", 12], ["month", 24], ["month", 60]
  ])
});

// How many labels of each format fit across the field. Shorter text packs
// tighter, so the budget is per format rather than one number: "Q1-26" is five
// characters and "Aug 18 12:00" is twelve.
const LABEL_BUDGET = Object.freeze({ hour: 12, day: 16, month: 14, quarter: 18 });

const STRIDE_DAYS = Object.freeze({ hour: 1 / 24, day: 1, month: 30.436875 });

// The format a stride produces. Only `quarter` outranks its own stride unit.
function strideFormat(unit, level) {
  if (level === "quarter" && unit === "month") return "quarter";
  return unit;
}

function monthStarts(start, end, step) {
  const startCivil = civilFromDays(start.floor());
  const endCivil = civilFromDays(end.ceil());
  const stride = BigInt(step);
  const first = startCivil.year * 12n + startCivil.month - 1n;
  const last = endCivil.year * 12n + endCivil.month - 1n;
  // Anchor the stride to month zero so a given stride always lands on the same
  // boundaries no matter where the window sits — quarters stay on Jan/Apr/Jul/Oct.
  const anchored = first - floorMod(first, stride);
  const days = [];
  for (let index = anchored; index <= last; index += stride) {
    const year = floorDiv(index, 12n);
    const month = floorMod(index, 12n) + 1n;
    days.push(new Rational(daysFromCivil(year, month, 1n)));
  }
  return days;
}

function dayStarts(start, end, step) {
  const stride = BigInt(step);
  const first = start.floor();
  const last = end.ceil();
  const anchored = first - floorMod(first, stride);
  const days = [];
  for (let day = anchored; day <= last; day += stride) days.push(new Rational(day));
  return days;
}

function hourStarts(start, end, step) {
  const perDay = 24 / step;
  const first = start.floor();
  const last = end.ceil();
  const days = [];
  for (let day = first; day <= last; day += 1n) {
    for (let slot = 0; slot < perDay; slot += 1) {
      days.push(new Rational(day).add(Rational.parse(slot * step).div(24)));
    }
  }
  return days;
}

function strideTicks(start, end, unit, step) {
  const all = unit === "month"
    ? monthStarts(start, end, step)
    : unit === "hour"
      ? hourStarts(start, end, step)
      : dayStarts(start, end, step);
  return all.filter((value) => value.compare(start) >= 0 && value.compare(end) <= 0);
}

// Labels land on real boundaries, never at even fractions of the window:
// "Q1-26 Q2-26" has to sit where the quarters actually start or the label is
// decoration rather than a coordinate. The ladder is walked coarsest-fitting
// first; the analytic estimate skips rungs that cannot possibly fit so a wide
// range never materializes tens of thousands of boundaries to throw away.
export function minimapLabelTicks(startDays, endDays, level, maxLabels = 0) {
  const start = Rational.parse(startDays);
  const end = Rational.parse(endDays);
  if (end.compare(start) <= 0) return [];
  const ladder = LABEL_LADDERS[level] || LABEL_LADDERS.day;
  const rangeDays = end.sub(start).toNumber();
  const override = Math.floor(Number(maxLabels) || 0);
  let chosen = null;
  let ticks = [];
  for (const [unit, step] of ladder) {
    const format = strideFormat(unit, level);
    const limit = Math.max(2, override || LABEL_BUDGET[format] || 12);
    if (rangeDays / (STRIDE_DAYS[unit] * step) > limit * 2) continue;
    const candidate = strideTicks(start, end, unit, step);
    chosen = { format, limit };
    ticks = candidate;
    if (candidate.length <= limit) break;
  }
  if (!chosen) {
    const [unit, step] = ladder[ladder.length - 1];
    chosen = { format: strideFormat(unit, level), limit: Math.max(2, override || 12) };
    ticks = strideTicks(start, end, unit, step);
  }
  if (ticks.length > chosen.limit) {
    const stride = Math.ceil(ticks.length / chosen.limit);
    ticks = ticks.filter((_, index) => index % stride === 0);
  }
  return ticks.map((days) => ({ days, format: chosen.format, text: minimapLabelText(days, chosen.format) }));
}

export function minimapLabelText(days, granularity) {
  const value = Rational.parse(days);
  const whole = value.floor();
  const civil = civilFromDays(whole);
  const month = Number(civil.month);
  const year = ((Number(civil.year) % 100) + 100) % 100;
  const shortYear = String(year).padStart(2, "0");
  if (granularity === "quarter") return `Q${Math.floor((month - 1) / 3) + 1}-${shortYear}`;
  if (granularity === "month") return `${MONTH_ABBREVIATIONS[month - 1]} '${shortYear}`;
  if (granularity === "hour") {
    const minutes = Math.round(value.sub(new Rational(whole)).mul(1440).toNumber());
    const hour = String(Math.floor(minutes / 60) % 24).padStart(2, "0");
    const minute = String(minutes % 60).padStart(2, "0");
    return `${MONTH_ABBREVIATIONS[month - 1]} ${civil.day} ${hour}:${minute}`;
  }
  return `${MONTH_ABBREVIATIONS[month - 1]} ${civil.day}`;
}
