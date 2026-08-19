import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { ViewSession } from "../src/session.js";
import {
  FIXED_RADIAL_CYCLES,
  arcPath,
  cyclePeriodHint,
  normalizeRadialGuideValues,
  polar,
  radialGuideSettings,
  radialRenderState,
  resolveRadialCycle,
  radialCycleWindow,
  spiralRibbonPath
} from "../src/radial.js";
import { daysFromCivil } from "../src/exact.js";

const fixture = JSON.parse(await readFile("fixtures/radial-stability.json", "utf8"));

test("persisted invalid Radial periods recover to a positive deterministic window", () => {
  for (const reproduction of fixture.persistedCycles) {
    const session = new ViewSession({ projection: "radial", radialCycle: reproduction.value });
    assert.ok(session.radialCycle.compare(0) > 0, reproduction.failure);
    const window = session.window();
    assert.ok(window.start.compare(window.end) < 0, reproduction.failure);
  }
});

test("Radial guide geometry stays finite and bounded for corrupted view values", () => {
  const guide = radialGuideSettings({
    radialCycle: "0",
    radialDivisions: Number.POSITIVE_INFINITY,
    radialMajorEvery: Number.NaN,
    radialMarks: "auto"
  });
  assert.ok(Number.isFinite(guide.cycleDays));
  assert.ok(guide.cycleDays > 0);
  assert.ok(guide.divisions >= 1 && guide.divisions <= 64);
  assert.ok(guide.majorEvery >= 1 && guide.majorEvery <= guide.divisions);
});

test("Radial guide values retain Auto and explicit major marks until a changed tick count invalidates them", () => {
  assert.deepEqual(
    normalizeRadialGuideValues({ radialCycle: "7", radialDivisions: 0, radialMajorEvery: 0 }),
    { radialDivisions: 0, radialMajorEvery: 0 }
  );
  assert.deepEqual(
    normalizeRadialGuideValues({ radialCycle: "7", radialDivisions: 64, radialMajorEvery: 32 }),
    { radialDivisions: 64, radialMajorEvery: 32 }
  );
  assert.deepEqual(
    normalizeRadialGuideValues({ radialCycle: "7", radialDivisions: 4, radialMajorEvery: 32 }),
    { radialDivisions: 4, radialMajorEvery: 4 }
  );
  assert.deepEqual(
    normalizeRadialGuideValues({ radialCycle: "7", radialDivisions: 999, radialMajorEvery: 999 }),
    { radialDivisions: 64, radialMajorEvery: 64 }
  );
});

test("document cycles preserve positive period hints without defining variable cycles as fixed", () => {
  for (const reproduction of fixture.documentCycles) {
    const period = cyclePeriodHint({ value: { levels: reproduction.levels } });
    assert.equal(Boolean(period), reproduction.supported, reproduction.title);
  }
  assert.deepEqual(FIXED_RADIAL_CYCLES.map((item) => item.id), ["fixed:day", "fixed:work-week", "fixed:week"]);
  assert.equal(cyclePeriodHint({ value: { levels: [{ level: "day", value: "invalid" }] } }), null);
});

test("a missing active cycle resolves together with the period used by navigation", () => {
  const resolved = resolveRadialCycle(FIXED_RADIAL_CYCLES, fixture.missingSelection.activeCycle);
  assert.equal(resolved.id, fixture.missingSelection.expected);
  assert.equal(resolved.period.toJSON(), FIXED_RADIAL_CYCLES[0].days);
});

test("Gregorian month cycles resolve their actual bounded interval without a mean-day approximation", () => {
  for (const reproduction of fixture.variableCycles) {
    const resolved = resolveRadialCycle([reproduction.cycle], reproduction.cycle.id, daysFromCivil(...reproduction.focus));
    assert.equal(resolved.dynamic, true, reproduction.title);
    assert.equal(resolved.period.toJSON(), reproduction.days, reproduction.title);
    assert.equal(resolved.start.toJSON(), daysFromCivil(reproduction.focus[0], reproduction.focus[1], 1n).toString(), reproduction.title);
    const window = radialCycleWindow(resolved, 1, 1);
    assert.equal(window.start.toJSON(), reproduction.windowStart, reproduction.title);
    assert.equal(window.end.toJSON(), reproduction.windowEnd, reproduction.title);
  }
});

test("unbounded formula, event-defined, and invalid cycle selections remain explicit instead of borrowing a fixed period", () => {
  for (const reproduction of fixture.unsupportedCycles) {
    const resolved = resolveRadialCycle([reproduction.cycle], reproduction.cycle.id, daysFromCivil(2026n, 8n, 16n));
    assert.equal(resolved.id, reproduction.cycle.id, reproduction.title);
    assert.equal(resolved.unsupported, true, reproduction.title);
    assert.equal(resolved.period, null, reproduction.title);
  }
});

test("empty, ordinary, and truncated Radial datasets have explicit deterministic states", () => {
  for (const reproduction of fixture.datasets) {
    assert.equal(radialRenderState(reproduction.factCount, reproduction.truncated), reproduction.state);
  }
});

// Stage C (8.19 field report, owner item 6): "Spiral Still has rounded edges,
// at the ends of the spirals, where it should terminate along the vertical
// ray according to its start or stop date." arcPath (the Radial ring lens's
// per-event geometry) already computes exact endpoints -- this pins that the
// date-correctness half of the bug was never in the geometry. The visible cap
// (round/square bulging past the endpoint vs. butt sitting flush) is a
// rendering choice, proven separately below and pinned end to end against a
// rendered arc in test/roster-lenses.test.js.
test("arcPath's own endpoints already sit exactly on the radial ray of their start and stop angle", () => {
  const cx = 450;
  const cy = 360;
  const normalize = (angle) => Math.atan2(Math.sin(angle), Math.cos(angle));
  for (const { radius, start, end } of [
    { radius: 60, start: -Math.PI / 2, end: 0 },
    { radius: 278, start: 0, end: Math.PI },
    { radius: 150, start: Math.PI / 4, end: Math.PI * 1.9 },
    { radius: 326, start: -3, end: 3 }
  ]) {
    const d = arcPath(cx, cy, radius, start, end);
    const [, mx, my] = /^M ([\d.-]+) ([\d.-]+)/.exec(d);
    const [, ex, ey] = /A [\d.-]+ [\d.-]+ 0 \d 1 ([\d.-]+) ([\d.-]+)/.exec(d);
    const startAngleFromPath = Math.atan2(Number(my) - cy, Number(mx) - cx);
    const endAngleFromPath = Math.atan2(Number(ey) - cy, Number(ex) - cx);
    assert.ok(
      Math.abs(normalize(startAngleFromPath - start)) < 1e-3,
      `start endpoint at radius ${radius} must sit on the ${start} ray, not overshoot or undershoot it`
    );
    assert.ok(
      Math.abs(normalize(endAngleFromPath - end)) < 1e-3,
      `end endpoint at radius ${radius} must sit on the ${end} ray, not overshoot or undershoot it`
    );
  }
});

// The other half of the proof: on a circle, the tangent at any point is
// exactly perpendicular to that point's own radius. A stroke's `butt`
// linecap draws its flat edge perpendicular to the path's tangent direction
// at the endpoint -- so on a circular arc that flat edge is parallel to the
// radius, and passing through a point on the radius line through the center
// makes it colinear with the radial ray itself. `round` and `square` both
// extend the visible mark past this same endpoint along the tangent, which
// is the rounded-edge/overshoot bug the owner reported; only `butt` draws no
// such extension. This is what licenses the renderer to fix Stage C purely
// with a linecap choice rather than by changing arcPath's already-exact
// endpoint geometry.
test("a circle's tangent at any point is exactly perpendicular to that point's radius", () => {
  const cx = 450;
  const cy = 360;
  const radius = 200;
  const epsilon = 1e-5;
  for (const angle of [0, Math.PI / 6, Math.PI / 2, 2.3, -1.1, Math.PI]) {
    const [x0, y0] = polar(cx, cy, radius, angle);
    const [x1, y1] = polar(cx, cy, radius, angle + epsilon);
    const tangent = [x1 - x0, y1 - y0];
    const tangentLength = Math.hypot(...tangent);
    const radial = [Math.cos(angle), Math.sin(angle)];
    const cosineBetween = (tangent[0] * radial[0] + tangent[1] * radial[1]) / tangentLength;
    assert.ok(
      Math.abs(cosineBetween) < 1e-3,
      `the tangent at angle ${angle} must be perpendicular to the radius there (cos ${cosineBetween})`
    );
  }
});

// 8.19 Part Three: two owner reports turned out to be two halves of one
// conflated bug. "Spiral still has rounded end caps" -- the TRACK (this
// timeline's own spiral ribbon) never actually got the flat/flush treatment
// the prior wave's fix intended; it still drew as a stroked path with
// `stroke-linecap: round`. "Spiral Events lost rounded caps and are not
// perpendicular to the radial lines they sit on" -- the prior wave's fix
// landed on the EVENT marks instead (`.radial-event-arc` in app.css), which
// should have kept their round caps.
//
// This test pins the TRACK half only, deliberately apart from the event-arc
// tests in test/roster-lenses.test.js -- a test that only asserted "the
// track is flat" would not have caught the swap, since the event arcs were
// *also* flat. The two must be asserted as distinct claims so this class of
// bug (a cap/terminus decision shared between a track and a mark) cannot
// silently swap again.
test("spiralRibbonPath's own two ends are exact flat cuts colinear with the vertical ray, not a cap perpendicular to the spiral's own tilted tangent", () => {
  const cx = 450;
  const cy = 360;
  const normalize = (angle) => Math.atan2(Math.sin(angle), Math.cos(angle));
  const angleOf = ([x, y]) => Math.atan2(y - cy, x - cx);
  for (const { inner, spacing, turns, samples, halfWidth } of [
    { inner: 82, spacing: 78, turns: 1, samples: 180, halfWidth: 17 },
    { inner: 82, spacing: 42, turns: 3, samples: 360, halfWidth: 30.6 },
    { inner: 60, spacing: 20, turns: 2, samples: 240, halfWidth: 0.7 }
  ]) {
    const d = spiralRibbonPath(cx, cy, inner, spacing, turns, samples, halfWidth);
    const points = [...d.matchAll(/[ML]([\d.-]+) ([\d.-]+)/g)].map(([, x, y]) => [Number(x), Number(y)]);
    assert.equal(points.length, 2 * (samples + 1), "the polygon carries an outer and inner edge sample per progress step");
    const outerStart = points[0];
    const outerEnd = points[samples];
    const innerEnd = points[samples + 1];
    const innerStart = points[points.length - 1];
    // The load-bearing claim: at each terminus, the outer and inner edge
    // (offset radially, not tangent-normal) land on the exact same ray as
    // each other -- so the segment joining them (the polygon's actual end
    // edge) is colinear with that ray, by construction, regardless of the
    // spiral's pitch at that point.
    assert.ok(
      Math.abs(normalize(angleOf(outerStart) - angleOf(innerStart))) < 1e-3,
      "the start terminus's outer and inner edge must sit on the same ray"
    );
    assert.ok(
      Math.abs(normalize(angleOf(outerEnd) - angleOf(innerEnd))) < 1e-3,
      "the end terminus's outer and inner edge must sit on the same ray"
    );
    // And that shared ray is exactly the vertical ray both the start and
    // stop date sit on -- true because `turns` (radialPast + radialFuture +
    // 1, always floored by ViewSession) is always an integer, so progress 0
    // and progress 1 are the same angle modulo a whole number of turns.
    assert.ok(
      Math.abs(normalize(angleOf(outerStart) + Math.PI / 2)) < 1e-3,
      "the start terminus must sit on the vertical ray, the spiral's own start angle"
    );
    assert.ok(
      Math.abs(normalize(angleOf(outerEnd) + Math.PI / 2)) < 1e-3,
      "the end terminus must sit on the vertical ray too"
    );
  }
});
