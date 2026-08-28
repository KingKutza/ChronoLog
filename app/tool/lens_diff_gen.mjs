// Differential harness for the lens substrate, JavaScript side. Generates random
// ranges, cycles, geometry parameters and line clusters from a fixed seed, runs
// every probe through the shipped `src/minimap.js`, `src/radial.js` and
// `src/lines.js`, and writes each answer as an exact string to stdout as one JSON
// document. `app/tool/lens_diff_check.dart` replays the same cases through
// `lib/lens/` and compares.
//
// Nothing here is a test of the JavaScript. It is the ORACLE: any disagreement is
// either a port defect or a deliberate, documented deviation.
//
// THE RULED DIVERGENCE CLASSES, generated deliberately and marked `divergent`:
//
//   L1 -- the CYCLE CATALOG. The JavaScript ships a hardcoded `FIXED_RADIAL_CYCLES`
//         of one, five and seven days; the port derives the offered cycles from
//         the governing law's own base unit and declared cycles, so a world with a
//         five-day week gets a five-day week and nobody typed a 7. Cases that
//         resolve a MISSING id -- where the JavaScript falls back to its catalog's
//         first entry -- are counted, not compared. Cases naming a real period are
//         compared in full, because that path is identical.
//
//   L2 -- MINIMAP MAGNITUDE WEIGHT. The JavaScript multiplies by a three-value
//         importance table (1 / 1.6 / 2.5); the port multiplies by the COMPOSED
//         display weight, one math everywhere. The arithmetic shape
//         `(1 + staples + duration) * weight` is identical and IS compared, with
//         the JavaScript's own multiplier supplied as the weight.
//
//   L3 -- THE DOT FIELD. `minimapDotGrid`, `minimapColumnDots`, `minimapRowOrder`
//         and `minimapColumnReach` have no counterpart: the minimap is a particle
//         waveform now, not a dot matrix. They are not generated at all. The
//         SCALE they served -- the ladder and the busy-end quantile -- rides and is
//         compared.
//
// Run, from app/:
//
//   dart run tool/lens_diff_check.dart
//
// which shells out to node itself. To keep the cases for inspection, redirect
// into app/build/ (already ignored):
//
//   node tool/lens_diff_gen.mjs > build/lens-diff-cases.json
//   dart run tool/lens_diff_check.dart build/lens-diff-cases.json

import { Rational, daysFromCivil } from "../../src/exact.js";
import {
  minimapEventMagnitude,
  minimapLabelGranularity,
  minimapLabelText,
  minimapLabelTicks,
  minimapMagnitudeCeiling,
  MINIMAP_MAGNITUDE_LADDER
} from "../../src/minimap.js";
import {
  arcPath,
  cyclePeriodHint,
  polar,
  radialCycleWindow,
  resolveRadialCycle,
  spiralRibbonPath
} from "../../src/radial.js";
import { aggregateLinePoints, lineProgress } from "../../src/lines.js";

const SEED = 20260827;

function mulberry32(seed) {
  return function next() {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const rnd = mulberry32(SEED);
const int = (bound) => Math.floor(rnd() * bound);
const pick = (items) => items[int(items.length)];
const fixed = (value) => (Number.isFinite(value) ? value.toFixed(6) : String(value));

// --- The label ladder --------------------------------------------------------

const LEVELS = ["hour", "day", "month", "quarter"];
const LENSES = ["intimate", "tactical", "lines", "wall", "strategic", "spiral", "radial", "nope"];

const labelCases = [];
for (let index = 0; index < 320; index += 1) {
  const year = 1800 + int(400);
  const start = new Rational(daysFromCivil(BigInt(year), 1 + int(12), 1 + int(28)))
    .add(Rational.parse(String(int(24))).div(Rational.parse("24")));
  const span = pick([1, 2, 5, 12, 31, 50, 90, 175, 456, 800, 2740, 9000]);
  const end = start.add(Rational.parse(String(span)));
  const level = pick(LEVELS);
  const ticks = minimapLabelTicks(start.toJSON(), end.toJSON(), level, 0);
  labelCases.push({
    start: start.toJSON(),
    end: end.toJSON(),
    level,
    ticks: ticks.map((tick) => [tick.days.toJSON(), tick.format, tick.text])
  });
}

const textCases = [];
for (let index = 0; index < 240; index += 1) {
  const year = 1600 + int(600);
  const days = new Rational(daysFromCivil(BigInt(year), 1 + int(12), 1 + int(28)))
    .add(Rational.parse(String(int(1439))).div(Rational.parse("1440")));
  const format = pick(LEVELS);
  textCases.push({ days: days.toJSON(), format, text: minimapLabelText(days.toJSON(), format) });
}

const granularityCases = LENSES.map((lens) => [lens, minimapLabelGranularity(lens)]);

// --- The magnitude scale -----------------------------------------------------

const IMPORTANCE = { standard: 1, important: 1.6, landmark: 2.5 };

const magnitudeCases = [];
for (let index = 0; index < 200; index += 1) {
  // Rounded before it is used, so the emitted decimal IS the number the
  // JavaScript multiplied -- otherwise the harness would be comparing two
  // different inputs and calling it a disagreement.
  const durationDays = Math.round((int(40) / (1 + int(8))) * 1000) / 1000;
  const stapleCount = int(9);
  const importance = pick(Object.keys(IMPORTANCE));
  magnitudeCases.push({
    durationDays: String(durationDays),
    stapleCount,
    weight: String(IMPORTANCE[importance]),
    magnitude: fixed(minimapEventMagnitude({ durationDays, stapleCount, importance }))
  });
}

const ceilingCases = [];
for (let index = 0; index < 200; index += 1) {
  const magnitudes = [];
  for (let bin = 0; bin < 1 + int(60); bin += 1) {
    magnitudes.push(rnd() < 0.35 ? 0 : Math.round(rnd() * 400 * 100) / 100);
  }
  ceilingCases.push({
    magnitudes: magnitudes.map(fixed),
    ceiling: fixed(minimapMagnitudeCeiling(magnitudes))
  });
}

// --- Cycle resolution --------------------------------------------------------

const CYCLE_LEVELS = ["day", "hour", "minute", "second", "week", "month", "year"];

const hintCases = [];
for (let index = 0; index < 200; index += 1) {
  const levels = [];
  for (let part = 0; part < 1 + int(3); part += 1) {
    levels.push({
      level: pick(CYCLE_LEVELS),
      value: rnd() < 0.1 ? "not a number" : String(1 + int(30))
    });
  }
  const magnitude = { value: { levels } };
  const hint = cyclePeriodHint(magnitude, null);
  hintCases.push({ magnitude, hint: hint === null ? null : hint.toJSON() });
}

const monthCases = [];
for (let index = 0; index < 200; index += 1) {
  const months = int(28);
  const year = 1900 + int(200);
  const focus = new Rational(daysFromCivil(BigInt(year), 1 + int(12), 1 + int(28)));
  const option = {
    id: "cycle:month",
    period: { value: { levels: [{ level: "month", value: String(months) }] } }
  };
  const resolved = resolveRadialCycle([option], "cycle:month", focus.toJSON(), null);
  const past = int(3);
  const future = int(3);
  const window = radialCycleWindow(resolved, past, future);
  monthCases.push({
    months,
    focus: focus.toJSON(),
    past,
    future,
    unsupported: Boolean(resolved?.unsupported),
    period: resolved?.period ? resolved.period.toJSON() : null,
    start: resolved?.start ? resolved.start.toJSON() : null,
    end: resolved?.end ? resolved.end.toJSON() : null,
    window: window ? [window.start.toJSON(), window.end.toJSON()] : null
  });
}

// L1: the missing-id fallback, generated and marked so the check counts it
// without comparing it.
const missingIdCases = [];
for (let index = 0; index < 20; index += 1) {
  const resolved = resolveRadialCycle([], "cycle:nobody", null, null);
  missingIdCases.push({ divergent: "L1", resolved: resolved === null ? null : resolved.id });
}

// --- Polar geometry ----------------------------------------------------------

const polarCases = [];
for (let index = 0; index < 240; index += 1) {
  const cx = Math.round(rnd() * 900);
  const cy = Math.round(rnd() * 720);
  const radius = Math.round(rnd() * 400 * 100) / 100;
  const angle = (rnd() * 8 - 4);
  const [x, y] = polar(cx, cy, radius, angle);
  // Full precision on the inputs: emitting a rounded angle and then comparing
  // an answer computed from the unrounded one would be a harness bug wearing a
  // disagreement's clothes.
  polarCases.push({
    cx, cy,
    radius: String(radius),
    angle: String(angle),
    x: fixed(x),
    y: fixed(y)
  });
}

function parseArc(d) {
  const move = /^M ([\d.-]+) ([\d.-]+)/.exec(d);
  const arc = /A [\d.-]+ [\d.-]+ 0 \d 1 ([\d.-]+) ([\d.-]+)/.exec(d);
  return [Number(move[1]), Number(move[2]), Number(arc[1]), Number(arc[2])];
}

const arcCases = [];
for (let index = 0; index < 200; index += 1) {
  const cx = Math.round(rnd() * 900);
  const cy = Math.round(rnd() * 720);
  const radius = 20 + Math.round(rnd() * 380 * 100) / 100;
  const from = rnd() * 6 - 3;
  const to = from + rnd() * 6;
  const [x1, y1, x2, y2] = parseArc(arcPath(cx, cy, radius, from, to));
  arcCases.push({
    cx, cy,
    radius: String(radius),
    from: String(from),
    to: String(to),
    ends: [x1, y1, x2, y2].map((value) => value.toFixed(2))
  });
}

function ribbonPoints(d) {
  const points = [];
  for (const match of d.matchAll(/[ML]([\d.-]+) ([\d.-]+)/g)) {
    points.push([Number(match[1]), Number(match[2])]);
  }
  return points;
}

const ribbonCases = [];
for (let index = 0; index < 120; index += 1) {
  const cx = Math.round(rnd() * 900);
  const cy = Math.round(rnd() * 720);
  const inner = 20 + Math.round(rnd() * 100 * 100) / 100;
  const spacing = 5 + Math.round(rnd() * 90 * 100) / 100;
  const turns = 1 + int(5);
  const samples = 60 + int(300);
  const halfWidth = Math.round(rnd() * 30 * 100) / 100;
  const points = ribbonPoints(spiralRibbonPath(cx, cy, inner, spacing, turns, samples, halfWidth));
  ribbonCases.push({
    cx, cy,
    inner: fixed(inner),
    spacing: fixed(spacing),
    turns,
    samples,
    halfWidth: fixed(halfWidth),
    count: points.length,
    outerStart: points[0].map((value) => value.toFixed(2)),
    innerStart: points[points.length - 1].map((value) => value.toFixed(2))
  });
}

// --- Lines -------------------------------------------------------------------

const progressCases = [];
for (let index = 0; index < 200; index += 1) {
  const start = Rational.parse(String(int(2000)));
  const end = start.add(Rational.parse(String(int(400))));
  const day = start.add(Rational.parse(String(int(400))));
  const progress = lineProgress(day.toJSON(), start.toJSON(), end.toJSON());
  progressCases.push({
    day: day.toJSON(),
    start: start.toJSON(),
    end: end.toJSON(),
    progress: progress === null ? null : fixed(progress)
  });
}

const fanCases = [];
for (let index = 0; index < 160; index += 1) {
  const points = [];
  let x = rnd();
  for (let count = 0; count < 1 + int(9); count += 1) {
    if (rnd() < 0.6) x += rnd() * 0.004;
    else x += rnd() * 0.2;
    points.push({ id: `p${int(1000)}-${count}`, eventId: `event:${int(6)}`, x });
  }
  const fanned = aggregateLinePoints(points);
  fanCases.push({
    points: points.map((point) => [point.id, point.eventId, fixed(point.x)]),
    fanned: fanned.map((point) => [point.id, fixed(point.offset), point.clusterSize])
  });
}

process.stdout.write(
  JSON.stringify(
    {
      seed: SEED,
      ladder: MINIMAP_MAGNITUDE_LADDER.map((rung) => fixed(rung)),
      granularity: granularityCases,
      labels: labelCases,
      text: textCases,
      magnitude: magnitudeCases,
      ceiling: ceilingCases,
      hints: hintCases,
      months: monthCases,
      missingId: missingIdCases,
      polar: polarCases,
      arcs: arcCases,
      ribbons: ribbonCases,
      progress: progressCases,
      fans: fanCases
    },
    null,
    0
  )
);
