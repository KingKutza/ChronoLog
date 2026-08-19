import test from "node:test";
import assert from "node:assert/strict";
import { createSampleDocument, createStructuralDocument } from "./helpers/sample-document.js";
import { ChronologEngine } from "../src/engine.js";
import { coordinate } from "../src/exact.js";
import {
  addEvent,
  addFrame,
  addPattern,
  addRelation,
  durationMagnitude,
  durationMagnitudeDays,
  suppressVirtual,
  validateDocument
} from "../src/model.js";

function date(year, month = "1", day = "1") {
  return coordinate([
    { level: "year", value: String(year) },
    { level: "month", value: String(month) },
    { level: "day", value: String(day) }
  ]);
}

test("duration magnitudes convert human units to exact days", () => {
  assert.equal(durationMagnitudeDays(durationMagnitude("2", "week")).toJSON(), "14");
  assert.equal(durationMagnitudeDays(durationMagnitude("90", "minute")).toJSON(), "1/16");
  assert.equal(durationMagnitudeDays({
    frame: "measure:human-time",
    value: coordinate([
      { level: "day", value: "1" },
      { level: "hour", value: "12" },
      { level: "minute", value: "30" }
    ])
  }).toJSON(), "73/48");
  assert.equal(durationMagnitudeDays(null).toJSON(), "0");
});

// The melt stage reconciled two forked duration-in-days helpers
// (model.js's durationMagnitudeDays, which used to throw on a malformed level
// and could return a negative total, and engine.js's private eventDurationDays,
// which tolerated malformed input and clamped negatives to zero) onto one
// behavior: tolerant and clamped, because callers -- overlap/lookback windows,
// a drag span, a duration shown in a form -- all want 0 rather than a thrown
// error or a negative span, and the owner's own ~169 MB of imported ICS makes
// malformed magnitudes plausible rather than hypothetical. These two tests pin
// that reconciled behavior so it cannot regress back to either fork.
test("a malformed duration magnitude yields zero rather than throwing", () => {
  const malformed = {
    frame: "measure:human-time",
    value: coordinate([{ level: "hour", value: "not-a-number" }])
  };
  assert.doesNotThrow(() => durationMagnitudeDays(malformed));
  assert.equal(durationMagnitudeDays(malformed).toJSON(), "0");
});

test("a negative-summing duration magnitude clamps to zero rather than going negative", () => {
  const negative = {
    frame: "measure:human-time",
    value: coordinate([
      { level: "day", value: "1" },
      { level: "hour", value: "-36" }
    ])
  };
  assert.equal(durationMagnitudeDays(negative).compare(0), 0);
});

test("generated pattern state and cycle facts exist at remote dates", () => {
  const engine = new ChronologEngine(createSampleDocument({ includeEvents: false }));
  for (const year of ["1026", "3026", "100002026", "-99997974"]) {
    const state = engine.queryState({
      frame: "calendar:generated",
      coordinate: date(year)
    });
    const facts = engine.queryFacts({
      frame: "calendar:generated",
      start: date(year),
      end: date(year, "2", "1")
    });
    assert.equal(state.errors.length, 0);
    assert.ok(state.values["pattern:marker"]);
    assert.ok(facts.facts.length >= 3);
    assert.equal(facts.errors.length, 0);
  }
});

test("virtual facts are suppressed and replaced without materializing a series", () => {
  const document = createSampleDocument({ includeEvents: false });
  const engine = new ChronologEngine(document);
  const query = {
    frame: "calendar:generated",
    start: date("3026"),
    end: date("3026", "2", "1")
  };
  const first = engine.queryFacts(query);
  const target = first.facts[0];
  suppressVirtual(document, target.virtualId);
  assert.equal(engine.queryFacts(query).facts.some((fact) => fact.virtualId === target.virtualId), false);
  assert.equal(Object.keys(document.events).length, 0);
});

test("one event may attach repeatedly and shared frames compose by reference", () => {
  const document = createStructuralDocument();
  const branchA = addFrame(document, { title: "Branch A", traits: ["line", "timeline"], basis: "frame:wall-time" });
  const branchB = addFrame(document, { title: "Branch B", traits: ["line", "timeline"], basis: "frame:wall-time" });
  const shared = addFrame(document, { title: "Shared history", traits: ["line", "segment"], basis: "frame:wall-time" });
  addRelation(document, { type: "composition", parent: branchA.id, child: shared.id, role: "shared" });
  addRelation(document, { type: "composition", parent: branchB.id, child: shared.id, role: "shared" });
  const event = addEvent(document, {
    traits: ["event", "terminator"],
    magnitudes: { duration: durationMagnitude("0") },
    payload: { title: "Boundary" }
  });
  addRelation(document, { type: "attachment", event: event.id, frame: branchA.id, role: "boundary", coordinate: date("2030") });
  addRelation(document, { type: "attachment", event: event.id, frame: branchA.id, role: "placed", coordinate: date("2031") });
  assert.equal(validateDocument(document).valid, true);
});

test("overlap queries retain a multi-day event after its start day", () => {
  const document = createSampleDocument({ includeEvents: false, includePattern: false });
  const event = addEvent(document, {
    traits: ["event"],
    magnitudes: { duration: durationMagnitude("9", "day") },
    payload: { title: "PTO" }
  });
  addRelation(document, {
    type: "attachment",
    event: event.id,
    frame: "calendar:personal",
    role: "placed",
    coordinate: date("2026", "8", "1")
  });
  const engine = new ChronologEngine(document);
  const window = {
    frame: "calendar:personal",
    start: date("2026", "8", "5"),
    end: date("2026", "8", "6")
  };
  assert.equal(engine.queryFacts(window).facts.length, 0);
  assert.deepEqual(
    engine.queryFacts({ ...window, includeOverlaps: true }).facts.map((fact) => fact.event.payload.title),
    ["PTO"]
  );
  assert.equal(engine.queryFacts({
    ...window,
    start: date("2026", "8", "10"),
    end: date("2026", "8", "11"),
    includeOverlaps: true
  }).facts.length, 0);
});

test("task and terminator traits enforce zero duration and retrospective calendar roles", () => {
  const document = createSampleDocument({ includeEvents: false, includePattern: false });
  const task = addEvent(document, {
    traits: ["event", "task"],
    magnitudes: { duration: durationMagnitude("1", "hour") },
    payload: { title: "Invalid prospective task" }
  });
  addRelation(document, {
    type: "attachment",
    event: task.id,
    frame: "calendar:personal",
    role: "placed",
    coordinate: date("2030")
  });
  const errors = validateDocument(document).errors.join("\n");
  assert.match(errors, /zero duration/);
  assert.match(errors, /retrospective/);
});

test("frame coordinate laws execute in the same formula runtime", () => {
  const document = createStructuralDocument();
  const law = addPattern(document, {
    title: "Hooperbun conversion",
    source: `
      export fn toDays(ctx) = num(ctx.value.levels[0].value) * 2;
      export fn fromDays(ctx) = {
        levels: [{ level: "hooperbun", value: num(ctx.days) / 2 }]
      };
      export fn state(ctx) = {};
      export fn facts(ctx) = [];
    `,
    exports: { state: "state", facts: "facts" }
  });
  const frame = addFrame(document, {
    title: "Hooper time",
    traits: ["line", "temporal"],
    coordinate: { kind: "nested", levels: [{ name: "hooperbun" }] },
    law: { pattern: law.id, toDays: "toDays", fromDays: "fromDays" }
  });
  const engine = new ChronologEngine(document);
  const value = coordinate([{ level: "hooperbun", value: "3.125" }]);
  assert.equal(engine.coordinateDays(frame.id, value).toJSON(), "25/4");
  assert.deepEqual(
    engine.daysCoordinate(frame.id, "25/4"),
    coordinate([{ level: "hooperbun", value: "25/8" }])
  );
});
