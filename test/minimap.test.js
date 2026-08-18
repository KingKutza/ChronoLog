import assert from "node:assert/strict";
import test from "node:test";
import { Rational, daysFromCivil } from "../src/exact.js";
import {
  MINIMAP_BUCKETS,
  MINIMAP_GRID_ROWS,
  MINIMAP_MAGNITUDE_LADDER,
  minimapColumnDots,
  minimapDotGrid,
  minimapEventMagnitude,
  minimapLabelGranularity,
  minimapLabelText,
  minimapLabelTicks,
  minimapMagnitudeCeiling
} from "../src/minimap.js";

const DAY_2026_08_18 = new Rational(daysFromCivil(2026n, 8n, 18n));

function field(entries, size = MINIMAP_BUCKETS) {
  const magnitudes = new Float64Array(size);
  const counts = new Uint16Array(size);
  for (const [column, magnitude, count] of entries) {
    magnitudes[column] = magnitude;
    counts[column] = count ?? Math.ceil(magnitude);
  }
  return { magnitudes, counts };
}

test("minimap magnitude uses a fixed event, staple, duration, and importance scale", () => {
  assert.equal(minimapEventMagnitude(), 1);
  assert.equal(minimapEventMagnitude({ durationDays: 2, stapleCount: 2 }), 5);
  assert.equal(minimapEventMagnitude({ durationDays: 2, stapleCount: 2, importance: "important" }), 8);
  assert.equal(minimapEventMagnitude({ durationDays: 2, stapleCount: 2, importance: "landmark" }), 12.5);
});

test("the field is one baseline row plus 24 activity rows at 288 buckets", () => {
  assert.equal(MINIMAP_GRID_ROWS, 25);
  assert.equal(MINIMAP_BUCKETS, 288);
  // The rebuild's two headline numbers: rows inside the asked-for 21-31 band,
  // and a dot count well past three times the old 11x140 field.
  assert.ok(MINIMAP_GRID_ROWS >= 21 && MINIMAP_GRID_ROWS <= 31);
  assert.ok(MINIMAP_BUCKETS * MINIMAP_GRID_ROWS >= 3 * 140 * 11);

  const { magnitudes, counts } = field([]);
  const grid = minimapDotGrid(magnitudes, { counts });
  assert.equal(grid.rows, 25);
  assert.equal(grid.columns, 288);
  assert.equal(grid.baseline, 24);
  assert.equal(grid.capacity, 24);
  assert.equal(grid.capacity % 12, 0, "24 activity rows keep quarter and third bands on real rows");
  assert.equal(grid.cells.length, grid.rows * grid.columns);
});

test("every column keeps a baseline dot so the field always reads as a time axis", () => {
  const { magnitudes, counts } = field([[5, 4, 2]]);
  const grid = minimapDotGrid(magnitudes, { counts });
  for (let column = 0; column < grid.columns; column += 1) {
    assert.equal(grid.cells[grid.baseline * grid.columns + column], 1);
  }
  // An empty bucket is the baseline and nothing else.
  assert.equal(grid.columnDots[6], 0);
  assert.equal(grid.cells[(grid.baseline - 1) * grid.columns + 6], 0);
});

test("activity grows upward from the baseline and never spills into a neighbour", () => {
  // An explicit ceiling keeps this column short of saturation, so the top of the
  // growth is somewhere the test can actually look at.
  const { magnitudes, counts } = field([[100, 6, 3]]);
  const grid = minimapDotGrid(magnitudes, { counts, ceiling: 24 });
  const dots = grid.columnDots[100];
  assert.equal(dots, 6);
  assert.ok(dots < grid.capacity);
  for (let step = 1; step <= dots; step += 1) {
    assert.equal(grid.cells[(grid.baseline - step) * grid.columns + 100], 1, `row ${step} above baseline is lit`);
  }
  assert.equal(grid.cells[(grid.baseline - dots - 1) * grid.columns + 100], 0, "growth stops at the column's height");
  // The old field bled a full column's overflow sideways, which smeared one busy
  // day across its neighbours. Neighbours now stay exactly as empty as they are.
  assert.equal(grid.columnDots[99], 0);
  assert.equal(grid.columnDots[101], 0);
});

test("every object in a bucket is at least one dot, and magnitude lifts the column further", () => {
  // Nine objects in a bucket whose magnitude alone would only earn two dots.
  assert.equal(minimapColumnDots(2, 9, { capacity: 24, dotsPerMagnitude: 1 }), 9);
  // Magnitude wins when it exceeds the object floor: importance and duration are
  // what make one object several dots.
  assert.equal(minimapColumnDots(minimapEventMagnitude(), 1, { capacity: 24, dotsPerMagnitude: 4 }), 4);
  assert.equal(
    minimapColumnDots(minimapEventMagnitude({ importance: "landmark" }), 1, { capacity: 24, dotsPerMagnitude: 4 }),
    10,
    "a landmark outweighs a standard event at the same scale"
  );
  // Neither guarantee may exceed the field.
  assert.equal(minimapColumnDots(500, 400, { capacity: 24, dotsPerMagnitude: 4 }), 24);
  assert.equal(minimapColumnDots(0, 0, { capacity: 24, dotsPerMagnitude: 4 }), 0);
});

test("a busy bucket and a free bucket differ at a glance at every density", () => {
  // Each case is one lens's bucket width against a plausible document: a quiet
  // calendar, a working week, and a heavily imported one. The scale ladder has
  // to keep the busy/free gap wide in all three.
  for (const [label, busyMagnitude, busyCount] of [
    ["quiet", 3, 2],
    ["working", 12, 8],
    ["dense", 90, 60]
  ]) {
    const magnitudes = new Float64Array(MINIMAP_BUCKETS);
    const counts = new Uint16Array(MINIMAP_BUCKETS);
    for (let column = 0; column < MINIMAP_BUCKETS; column += 2) {
      magnitudes[column] = busyMagnitude;
      counts[column] = busyCount;
    }
    const grid = minimapDotGrid(magnitudes, { counts });
    const busy = grid.columnDots[0];
    const free = grid.columnDots[1];
    assert.equal(free, 0, `${label}: a free bucket stays empty above the baseline`);
    assert.ok(busy >= grid.capacity / 2, `${label}: a busy bucket fills at least half the field, got ${busy}`);
  }
});

test("the magnitude ceiling snaps to a coarse ladder so panning does not reshuffle the scale", () => {
  const rungs = new Set(MINIMAP_MAGNITUDE_LADDER);
  for (const busy of [1, 2.4, 5, 9, 30, 200]) {
    const magnitudes = new Float64Array(8).fill(busy);
    const ceiling = minimapMagnitudeCeiling(magnitudes);
    assert.ok(rungs.has(ceiling), `${busy} snaps to a ladder rung, got ${ceiling}`);
    assert.ok(ceiling >= busy);
  }
  // A small perturbation inside a rung leaves the scale alone.
  assert.equal(minimapMagnitudeCeiling(new Float64Array(8).fill(9)), minimapMagnitudeCeiling(new Float64Array(8).fill(11)));
  // An empty field still has a usable scale rather than dividing by zero.
  assert.equal(minimapMagnitudeCeiling(new Float64Array(8)), MINIMAP_MAGNITUDE_LADDER[0]);
});

test("at one scale, equal activity reads identically wherever it sits", () => {
  const left = field([[12, 4, 3]]);
  const right = field([[240, 4, 3]]);
  const options = { ceiling: 16 };
  const leftGrid = minimapDotGrid(left.magnitudes, { ...options, counts: left.counts });
  const rightGrid = minimapDotGrid(right.magnitudes, { ...options, counts: right.counts });
  assert.equal(leftGrid.columnDots[12], rightGrid.columnDots[240]);
  const lit = (grid) => [...grid.cells].filter(Boolean).length;
  assert.equal(lit(leftGrid), lit(rightGrid));
});

test("label granularity is declared per lens, and Intimate never shows a year", () => {
  assert.equal(minimapLabelGranularity("intimate"), "hour");
  assert.equal(minimapLabelGranularity("tactical"), "day");
  assert.equal(minimapLabelGranularity("strategic"), "quarter");
  assert.equal(minimapLabelGranularity("wall"), "month");
  assert.equal(minimapLabelGranularity("nonesuch"), "day", "an unregistered lens falls back to days");

  // Intimate's window is a handful of days; its ladder stops at week strides, so
  // no reachable stride can print a year.
  for (const span of [2, 5, 12, 50, 90]) {
    const ticks = minimapLabelTicks(DAY_2026_08_18, DAY_2026_08_18.add(span), "hour");
    assert.ok(ticks.length > 1, `a ${span} day range earns labels`);
    for (const tick of ticks) {
      assert.ok(["hour", "day"].includes(tick.format));
      assert.doesNotMatch(tick.text, /\d{4}|'\d\d/, `Intimate label "${tick.text}" carries no year`);
    }
  }
});

test("Strategic labels read as consecutive quarters on real quarter boundaries", () => {
  const start = DAY_2026_08_18.sub(685);
  const ticks = minimapLabelTicks(start, start.add(1370), "quarter");
  assert.ok(ticks.length >= 8);
  for (const tick of ticks) {
    assert.equal(tick.format, "quarter");
    assert.match(tick.text, /^Q[1-4]-\d\d$/);
    // A quarter label has to sit where the quarter actually starts.
    const civil = minimapLabelText(tick.days, "day");
    assert.match(civil, /^(Jan|Apr|Jul|Oct) 1$/, `${tick.text} lands on a quarter boundary, not ${civil}`);
  }
  const quarters = ticks.map((tick) => tick.text);
  assert.ok(quarters.includes("Q1-26") && quarters.includes("Q2-26"), `expected consecutive quarters, got ${quarters.join(" ")}`);
});

test("each remaining lens gets an honest, distinguishable label format", () => {
  const formatFor = (level, span) => {
    const ticks = minimapLabelTicks(DAY_2026_08_18, DAY_2026_08_18.add(span), level);
    return { format: ticks[0]?.format, count: ticks.length };
  };
  // Tactical and Lines mark days; Wall and the radial pair mark months, where a
  // year matters because the range crosses one.
  assert.equal(formatFor("day", 175).format, "day");
  assert.equal(formatFor("day", 70).format, "day");
  assert.equal(formatFor("month", 456).format, "month");
  assert.match(minimapLabelText(DAY_2026_08_18, "month"), /^Aug '26$/);
  assert.match(minimapLabelText(DAY_2026_08_18, "day"), /^Aug 18$/);
  assert.match(minimapLabelText(DAY_2026_08_18.add(Rational.parse(1).div(2)), "hour"), /^Aug 18 12:00$/);
  assert.match(minimapLabelText(DAY_2026_08_18, "quarter"), /^Q3-26$/);
});

test("label ticks stay inside the range, in order, and within a legible budget", () => {
  for (const [level, span] of [["hour", 50], ["day", 175], ["month", 456], ["quarter", 2740]]) {
    const start = DAY_2026_08_18;
    const end = start.add(span);
    const ticks = minimapLabelTicks(start, end, level);
    assert.ok(ticks.length >= 2, `${level} produced ${ticks.length} labels`);
    assert.ok(ticks.length <= 18, `${level} produced ${ticks.length} labels, too many to read`);
    let previous = null;
    for (const tick of ticks) {
      assert.ok(tick.days.compare(start) >= 0 && tick.days.compare(end) <= 0, `${tick.text} is inside the range`);
      if (previous) assert.ok(tick.days.compare(previous) > 0, "labels ascend");
      previous = tick.days;
    }
  }
  // A degenerate range asks for nothing rather than dividing by zero.
  assert.deepEqual(minimapLabelTicks(DAY_2026_08_18, DAY_2026_08_18, "day"), []);
});
