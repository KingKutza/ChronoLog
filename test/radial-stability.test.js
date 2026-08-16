import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { ViewSession } from "../src/session.js";
import {
  FIXED_RADIAL_CYCLES,
  cyclePeriodHint,
  normalizeRadialGuideValues,
  radialGuideSettings,
  radialRenderState,
  resolveRadialCycle,
  radialCycleWindow
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
