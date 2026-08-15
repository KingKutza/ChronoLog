import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { ViewSession } from "../src/session.js";
import {
  FIXED_RADIAL_CYCLES,
  fixedCycleDays,
  radialGuideSettings,
  radialRenderState,
  resolveRadialCycle
} from "../src/radial.js";

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

test("document cycles are offered only when their period is fixed and positive", () => {
  for (const reproduction of fixture.documentCycles) {
    const period = fixedCycleDays({ value: { levels: reproduction.levels } });
    assert.equal(Boolean(period), reproduction.supported, reproduction.title);
  }
  for (const cycle of FIXED_RADIAL_CYCLES.filter((item) => ["fixed:month", "fixed:quarter", "fixed:year"].includes(item.id))) {
    assert.match(cycle.title, /fixed mean/);
  }
  assert.equal(fixedCycleDays({ value: { levels: [{ level: "day", value: "invalid" }] } }), null);
});

test("a missing active cycle resolves together with the period used by navigation", () => {
  const resolved = resolveRadialCycle(FIXED_RADIAL_CYCLES, fixture.missingSelection.activeCycle);
  assert.equal(resolved.id, fixture.missingSelection.expected);
  assert.equal(resolved.period.toJSON(), FIXED_RADIAL_CYCLES[0].days);
});

test("empty, ordinary, and truncated Radial datasets have explicit deterministic states", () => {
  for (const reproduction of fixture.datasets) {
    assert.equal(radialRenderState(reproduction.factCount, reproduction.truncated), reproduction.state);
  }
});
