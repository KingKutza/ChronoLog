import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { lineFramePlan, lineProgress, linesRenderState } from "../src/lines.js";

const fixture = JSON.parse(await readFile("fixtures/lines-baseline.json", "utf8"));

test("Lines resolves the active terrestrial frame and explicitly selected calendar companions", () => {
  const plan = lineFramePlan(fixture.document, "calendar:terrestrial");
  assert.equal(plan.supported, true);
  assert.equal(plan.leading.title, "Terrestrial");
  assert.deepEqual(plan.companions.map((frame) => frame.title), ["Companion"]);
  assert.deepEqual(plan.unsupportedCompanions, ["frame:unsupported", "calendar:missing"]);
});

test("Lines does not infer companions when none are selected", () => {
  const documentValue = structuredClone(fixture.document);
  delete documentValue.frames["calendar:terrestrial"].display;
  const plan = lineFramePlan(documentValue, "calendar:terrestrial");
  assert.deepEqual(plan.companions, []);
});

test("Lines reports unsupported leading data without dereferencing a missing frame", () => {
  for (const frame of ["frame:unsupported", "calendar:missing"]) {
    const plan = lineFramePlan(fixture.document, frame);
    assert.equal(plan.supported, false);
    assert.deepEqual(plan.companions, []);
  }
});

test("Lines has distinct deterministic loading, unsupported, error, empty, ordinary, and dense states", () => {
  for (const reproduction of fixture.states) {
    assert.equal(linesRenderState(reproduction.input), reproduction.expected, reproduction.name);
  }
});

test("terrestrial, companion, and shared mapped events receive deterministic window positions", () => {
  for (const fact of fixture.facts) {
    assert.equal(lineProgress(fact.day, fixture.window.start, fixture.window.end), fact.progress);
  }
  const shared = fixture.facts.filter((fact) => fact.event === "event:shared");
  assert.equal(shared.length, 2);
  assert.equal(shared[0].progress, shared[1].progress);
  assert.equal(lineProgress("10", "10", "10"), null);
});
