import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { eventBoundarySeries, eventCycleWindow, resolveEventCycle, stepEventCycle } from "../src/event-cycle.js";
import { resolveRadialCycle, radialCycleWindow } from "../src/radial.js";
import { createDocument, validateDocument } from "../src/model.js";

const fixture = JSON.parse(await readFile(new URL("../fixtures/irregular-event-cycle.json", import.meta.url), "utf8"));

test("observed irregular boundaries resolve the containing cycle exactly, never by an average", () => {
  const result = resolveEventCycle(fixture.period, "30");
  assert.equal(result.resolved, true);
  assert.equal(result.start.toDecimal(2), "29.31");
  assert.equal(result.end.toDecimal(2), "58.92");
  assert.equal(result.period.toDecimal(2), "29.61");
  assert.notEqual(result.period.toDecimal(9), "29.530588853");
});

test("event-defined cycles support deterministic reverse traversal within their authored finite window", () => {
  const backwards = stepEventCycle(fixture.period, "60", -1);
  assert.equal(backwards.resolved, true);
  assert.equal(backwards.start.toDecimal(2), "29.31");
  assert.equal(stepEventCycle(fixture.period, "1", -1).resolved, false);
  const window = eventCycleWindow(fixture.period, "60", 1, 1);
  assert.equal(window.windowStart.toDecimal(2), "29.31");
  assert.equal(window.windowEnd.toDecimal(2), "117.87");
});

test("Radial can use an authored event cycle and refuses to extrapolate it", () => {
  const resolved = resolveRadialCycle([{ id: "cycle:observed-lunar", period: fixture.period }], "cycle:observed-lunar", "60");
  assert.equal(resolved.unsupported, false);
  assert.equal(resolved.eventDefined, true);
  assert.equal(resolved.period.toDecimal(2), "29.11");
  const window = radialCycleWindow(resolved, 1, 1);
  assert.equal(window.start.toDecimal(2), "29.31");
  assert.equal(window.end.toDecimal(2), "117.87");
});

test("ambiguous or unordered event boundaries are rejected", () => {
  const bad = structuredClone(fixture.period);
  bad.boundaries[2].at = bad.boundaries[1].at;
  assert.equal(eventBoundarySeries(bad).valid, false);
  assert.match(eventBoundarySeries(bad).error, /strictly ordered/);
  assert.equal(resolveEventCycle(fixture.period, "999").resolved, false);
});

test("documents validate boundary frame, observed events, and ordered exact event cycles", () => {
  const document = createDocument();
  document.frames["measure:earth-days"] = { id: "measure:earth-days", traits: ["measure"] };
  document.frames["cycle:moon"] = { id: "cycle:moon", traits: ["cycle"], period: fixture.period };
  for (const boundary of fixture.period.boundaries) {
    document.events[boundary.event] = { id: boundary.event, traits: ["event"], magnitudes: { duration: { frame: "measure:earth-days", value: { levels: [] } } } };
  }
  assert.equal(validateDocument(document).valid, true);
  document.frames["cycle:moon"].period.boundaries[1].at = "0";
  assert.match(validateDocument(document).errors.join("\n"), /strictly ordered/);
});
