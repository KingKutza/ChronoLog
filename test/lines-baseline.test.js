import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { aggregateLinePoints, lineFramePlan, lineProgress, lineTopologyPlan, lineUnitLabel, linesRenderState } from "../src/lines.js";

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

test("Lines fans coincident points in a stable ID order rather than hiding a cluster", () => {
  const points = aggregateLinePoints([
    { id: "z", eventId: "event:z", x: 0.5 },
    { id: "a", eventId: "event:a", x: 0.5 },
    { id: "near", eventId: "event:near", x: 0.504 }
  ]);
  assert.deepEqual(points.map((point) => point.id), ["a", "near", "z"]);
  assert.deepEqual(points.map((point) => point.offset), [-8, 0, 8]);
  assert.ok(points.every((point) => point.clusterSize === 3));
});

test("Lines calls an authored fixed calendar by its own units, never Gregorian by implication", () => {
  const frame = { coordinate: { fixed: { schema: "chronolog/fixed-calendar/1", units: [{ name: "turn" }, { name: "watch" }, { name: "beat" }] } } };
  assert.equal(lineUnitLabel(frame, "22000"), "turn / watch / beat");
  assert.equal(lineUnitLabel({ traits: ["line", "timeline"] }), "topological order (unmapped units)");
});

test("Lines derives colliding time-travel lanes only from explicit authored topology", async () => {
  const topology = JSON.parse(await readFile("fixtures/time-travel-taxonomy.chronolog.json", "utf8"));
  const plan = lineTopologyPlan(topology, "line:earth");
  assert.equal(plan.frames[0].id, "line:earth");
  assert.ok(plan.frames.some((frame) => frame.id === "line:fork"));
  assert.ok(plan.frames.some((frame) => frame.id === "line:traveler"));
  assert.ok(plan.links.some((relation) => relation.id === "segment:earth-traveler-shared"));
  assert.ok(plan.links.some((relation) => relation.id === "displacement:backward-earth"));
  assert.equal(plan.attachments.some((relation) => relation.event === "event:arrival" && relation.frame === "line:traveler"), true);
  assert.equal(lineFramePlan(topology, "line:earth").supported, true);
});
