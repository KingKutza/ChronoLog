import assert from "node:assert/strict";
import test from "node:test";
import { ChronologEngine } from "../src/engine.js";
import { Rational, coordinate, daysFromCivil, formatCivil } from "../src/exact.js";
import { daysToCivilCoordinate } from "../src/coordinate-law.js";
import { importICS } from "../src/ics.js";
import {
  addEvent,
  addFrame,
  addPattern,
  addRelation,
  createId,
  durationMagnitude,
  durationMagnitudeDays,
  putStaple,
  removeStaple,
  validateDocument
} from "../src/model.js";
import { applySeriesHeal, overrideHealDecision, planSeriesHeal } from "../src/series-heal.js";
import { createStructuralDocument } from "./helpers/sample-document.js";

// LEXICON.md's Rob-and-John scenario, followed beat by beat -- this is the
// acceptance case for the whole staple substrate (src/staples.js), not one
// more unit test:
//
// "Rob says 'let's do Monday meetings -- you always get in early on
// Mondays.' John adds a Monday meeting, 6:15 to 6:30, repeat every Monday,
// skip holidays (events on frame xyz), run indefinite (projected up to 2
// years into the future; default settable in settings). Six years later
// John has a kid, doesn't get in till 8:00, and after some conversation they
// move to a Thursday lunch meeting. At that decision they place a staple at
// the inflection point defining an end to the initial series rule, then
// either define a new rule post-staple or a new series, on preference."
//
// What it pins, restated as the beats below test them: a series is an
// identity whose rules are segments partitioned by staples; holiday
// exclusion is a live reference to another frame's events, not a baked
// list; the rule's extent (indefinite) and the projection horizon (bounded,
// settable) are different things; and the inflection staple records where
// life changed the schedule -- without destroying the series' identity, and
// without there being only one way to author the same outcome.

function civil(year, month, day, hour = 0, minute = 0, second = 0) {
  return coordinate([
    { level: "year", value: String(year) },
    { level: "month", value: String(month) },
    { level: "day", value: String(day) },
    { level: "hour", value: String(hour) },
    { level: "minute", value: String(minute) },
    { level: "second", value: String(second) }
  ]);
}

function date(year, month = "1", day = "1") {
  return coordinate([
    { level: "year", value: String(year) },
    { level: "month", value: String(month) },
    { level: "day", value: String(day) }
  ]);
}

// John's Monday 6:15-6:30 standing meeting, indefinite (no COUNT, no UNTIL),
// plus a separate frame the meeting will be told to skip -- built through
// real ICS import, as the sibling series-* test files do, so every record
// carries exactly the fields the app itself would give it.
function buildWorld() {
  const document = createStructuralDocument();
  const source = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Test//EN",
    "BEGIN:VEVENT",
    "UID:rob-and-john@example.test",
    "DTSTART:20260105T061500Z",
    "RRULE:FREQ=WEEKLY",
    "SUMMARY:Monday check-in",
    "DURATION:PT15M",
    "END:VEVENT",
    "END:VCALENDAR",
    ""
  ].join("\r\n");
  const imported = importICS(source, document, { label: "Work calendar" });
  const frame = document.frames[imported.frames[0]];
  const pattern = Object.values(document.patterns).find((item) => item.kind === "ics-rrule");
  const holidays = addFrame(document, {
    id: "frame:holidays",
    title: "Holidays",
    traits: ["set", "calendar"],
    basis: "frame:wall-time"
  });
  return { document, frame, pattern, holidays };
}

function addHoliday(document, holidays, year, month, day, title = "Holiday") {
  const event = addEvent(document, {
    traits: ["event", "holiday"],
    magnitudes: { duration: durationMagnitude("1", "day") },
    payload: { title }
  });
  addRelation(document, {
    type: "attachment",
    event: event.id,
    frame: holidays.id,
    role: "placed",
    coordinate: date(year, month, day)
  });
  return event;
}

// A fresh engine per query, deliberately: this file is about what the
// projection says given the document's current state, not about the
// recurrence cache (that trap gets its own dedicated regression in
// test/staple-anchoring.test.js).
function occurrences(document, frame, { start = date(2020), end = date(2040) } = {}) {
  return new ChronologEngine(document)
    .queryFacts({ frame: frame.id, start, end, limit: 5000 })
    .facts.filter((fact) => fact.kind === "virtual");
}

function times(facts) {
  return facts.map((fact) => formatCivil(fact.coordinate, true));
}

// The inflection instant six years on (2032-01-05, still a Monday -- 313
// weeks preserves the weekday) and the Thursday lunch base three days later,
// computed exactly rather than eyeballed, per the file-wide no-string-dates
// discipline.
function sixYearsOnInflection() {
  const mondayBase = new Rational(daysFromCivil(2026n, 1n, 5n))
    .add(Rational.parse(6).div(24))
    .add(Rational.parse(15).div(1440));
  const inflectionDays = mondayBase.add(new Rational(313n * 7n));
  const thursdayDays = new Rational(inflectionDays.floor() + 3n).add(Rational.parse(12).div(24));
  return {
    inflectionDays,
    thursdayDays,
    inflectionCoordinate: daysToCivilCoordinate(inflectionDays),
    thursdayCoordinate: daysToCivilCoordinate(thursdayDays)
  };
}

// --- Beat 1: a Monday standing meeting, indefinite -------------------------

test("Rob-and-John beat 1: a Monday 6:15-6:30 weekly series, indefinite", () => {
  const { document, frame, pattern } = buildWorld();
  assert.equal(pattern.rrule.FREQ, "WEEKLY");
  assert.equal(pattern.rrule.COUNT, undefined, "no COUNT -- indefinite");
  assert.equal(pattern.rrule.UNTIL, undefined, "no UNTIL -- indefinite");
  const facts = occurrences(document, frame, { start: date(2026), end: date(2026, 3, 1) });
  assert.deepEqual(times(facts).slice(0, 4), [
    "2026-01-05 06:15:00", "2026-01-12 06:15:00", "2026-01-19 06:15:00", "2026-01-26 06:15:00"
  ]);
  assert.equal(validateDocument(document).valid, true);
});

// --- Beat 2: holidays are a live reference, not a baked list ---------------

test("Rob-and-John beat 2: holiday exclusion is a live reference to another frame's events", () => {
  const { document, frame, pattern, holidays } = buildWorld();
  // 2026-01-19 is one of the series' own Mondays.
  addHoliday(document, holidays, 2026, 1, 19, "Made-up holiday");
  pattern.exclude = { frames: [holidays.id] };

  const withOneHoliday = times(occurrences(document, frame, { start: date(2026), end: date(2026, 2, 1) }));
  assert.ok(!withOneHoliday.includes("2026-01-19 06:15:00"), "the holiday Monday does not project");
  assert.deepEqual(withOneHoliday, [
    "2026-01-05 06:15:00", "2026-01-12 06:15:00", "2026-01-26 06:15:00"
  ], "every other Monday in the window is untouched");

  // Add a SECOND holiday with NO EDIT TO THE SERIES -- that is what makes the
  // exclusion live rather than baked. `pattern` and `pattern.exclude` are not
  // touched again below.
  addHoliday(document, holidays, 2026, 2, 2, "A second made-up holiday");
  const withTwoHolidays = times(occurrences(document, frame, { start: date(2026), end: date(2026, 2, 10) }));
  assert.ok(!withTwoHolidays.includes("2026-02-02 06:15:00"), "the newly-added holiday's Monday stops projecting");
  assert.deepEqual(withTwoHolidays, [
    "2026-01-05 06:15:00", "2026-01-12 06:15:00", "2026-01-26 06:15:00", "2026-02-09 06:15:00"
  ]);
  assert.equal(validateDocument(document).valid, true);
});

// --- Beat 3: rule extent vs. projection horizon are different things -------

test("Rob-and-John beat 3: the rule's extent (indefinite) and the projection horizon (bounded) are different things", () => {
  const { document, frame, pattern } = buildWorld();
  assert.equal(pattern.rrule.COUNT, undefined);
  assert.equal(pattern.rrule.UNTIL, undefined);

  // A ~2-year horizon (the scenario's own default) returns a bounded set...
  const twoYearHorizon = occurrences(document, frame, { start: date(2026), end: date(2028) });
  assert.ok(twoYearHorizon.length > 0 && twoYearHorizon.length < 120);

  // ...while a wider query against the very same, still-indefinite rule
  // returns strictly more -- the rule never stopped; only the query bound did.
  const sixYearHorizon = occurrences(document, frame, { start: date(2026), end: date(2032) });
  assert.ok(sixYearHorizon.length > twoYearHorizon.length, "a wider horizon sees further into the same indefinite rule");
  assert.deepEqual(times(sixYearHorizon).slice(0, twoYearHorizon.length), times(twoYearHorizon), "the shared prefix agrees exactly");
});

// --- Beat 4: the inflection staple, single identity ------------------------

test("Rob-and-John beat 4: an inflection staple partitions the series into Monday-then-Thursday, one identity throughout", () => {
  const { document, frame, pattern } = buildWorld();
  const { inflectionDays, inflectionCoordinate, thursdayCoordinate } = sixYearsOnInflection();

  const staple = putStaple(document, {
    series: pattern.id,
    kind: "inflection",
    frame: frame.id,
    coordinate: inflectionCoordinate,
    payload: {
      rule: {
        rrule: { FREQ: "WEEKLY" },
        coordinate: thursdayCoordinate,
        frame: frame.id,
        magnitude: durationMagnitude("1", "hour")
      }
    }
  });
  assert.equal(validateDocument(document).valid, true);

  const facts = occurrences(document, frame, { start: date(2020), end: date(2033) });
  // Split by each occurrence's own duration rather than string-matching a
  // date: a Monday occurrence's duration is the original 15 minutes; a
  // Thursday lunch's is the new 1-hour magnitude the staple's following rule
  // carries (LEXICON.md: "a different duration").
  // occurrence's own duration is the original 15 minutes; a Thursday lunch's
  // is the new 1 hour magnitude the staple's following rule carries.
  const fifteenMinutes = durationMagnitude("15", "minute");
  const oneHour = durationMagnitude("1", "hour");
  const before = facts.filter((fact) => durationMagnitudeDays(fact.event.magnitudes.duration).compare(durationMagnitudeDays(fifteenMinutes)) === 0);
  const after = facts.filter((fact) => durationMagnitudeDays(fact.event.magnitudes.duration).compare(durationMagnitudeDays(oneHour)) === 0);
  assert.equal(before.length + after.length, facts.length, "every fact is one or the other -- no third shape appears");

  // Mondays exist before the staple and STOP at it, inclusive of the
  // staple's own occurrence (the boundary convention: a partitioning staple
  // closes its segment inclusively).
  assert.ok(before.length > 100, "many Monday occurrences precede the inflection");
  const lastMonday = before.at(-1);
  const lastMondayDays = new Rational(daysFromCivil(2032n, 1n, 5n))
    .add(Rational.parse(6).div(24)).add(Rational.parse(15).div(1440));
  assert.equal(Rational.parse(lastMonday.day).compare(lastMondayDays), 0, "the last Monday IS the staple's own instant");
  assert.equal(Rational.parse(lastMonday.day).compare(inflectionDays), 0);
  for (const fact of before) assert.ok(Rational.parse(fact.day).compare(inflectionDays) <= 0, "no Monday occurs after the staple");

  // Thursday lunches exist after the staple and NOT before.
  assert.ok(after.length > 0, "at least one Thursday lunch projects");
  for (const fact of after) assert.ok(Rational.parse(fact.day).compare(inflectionDays) > 0, "every Thursday lunch is strictly after the staple");

  // The whole thing is STILL ONE IDENTITY: every fact from both segments
  // carries the same pattern id in its provenance, and virtual ids never
  // collide across the segment boundary.
  for (const fact of facts) assert.equal(fact.event.provenance.pattern, pattern.id, "one identity across the rule change");
  const virtualIds = new Set(facts.map((fact) => fact.virtualId));
  assert.equal(virtualIds.size, facts.length, "no two segments ever produce the same virtual id");

  assert.ok(staple.id, "the staple itself is a normal relation record");
});

// --- Beat 5: the same outcome, authored as a new series instead -----------

test("Rob-and-John beat 5: 'a new rule, or a new series, on preference' render the identical occurrence set", () => {
  const single = buildWorld();
  const { inflectionCoordinate, thursdayCoordinate } = sixYearsOnInflection();
  putStaple(single.document, {
    series: single.pattern.id,
    kind: "inflection",
    frame: single.frame.id,
    coordinate: inflectionCoordinate,
    payload: {
      rule: {
        rrule: { FREQ: "WEEKLY" },
        coordinate: thursdayCoordinate,
        frame: single.frame.id,
        magnitude: durationMagnitude("1", "hour")
      }
    }
  });
  const singleIdentityTimes = times(occurrences(single.document, single.frame, { start: date(2020), end: date(2033) })).sort();

  // The preference branch: an "end" staple with NO following rule (retiring
  // the original series outright) plus an independently authored second
  // series for the Thursday lunch.
  const split = buildWorld();
  putStaple(split.document, {
    series: split.pattern.id,
    kind: "end",
    frame: split.frame.id,
    coordinate: inflectionCoordinate
  });
  const lunchEvent = addEvent(split.document, {
    traits: ["event"],
    magnitudes: { duration: durationMagnitude("1", "hour") },
    payload: { title: "Thursday lunch" }
  });
  const lunchRelation = addRelation(split.document, {
    type: "attachment",
    event: lunchEvent.id,
    frame: split.frame.id,
    role: "placed",
    coordinate: thursdayCoordinate
  });
  addPattern(split.document, {
    kind: "ics-rrule",
    appliesTo: [split.frame.id],
    frame: split.frame.id,
    templateEvent: lunchEvent.id,
    templateRelation: lunchRelation.id,
    rrule: { FREQ: "WEEKLY" },
    source: "export fn state(ctx) = {};\nexport fn facts(ctx) = [];",
    exports: { state: "state", facts: "facts" }
  });
  assert.equal(validateDocument(split.document).valid, true);
  const splitTimes = times(occurrences(split.document, split.frame, { start: date(2020), end: date(2033) })).sort();

  assert.deepEqual(splitTimes, singleIdentityTimes, "on preference -- a real choice, not two different behaviors");

  // But the identity claim genuinely differs, which is the whole reason a
  // preference exists at all: the split version does NOT carry one pattern id.
  const splitPatternIds = new Set(
    occurrences(split.document, split.frame, { start: date(2020), end: date(2033) })
      .map((fact) => fact.event.provenance.pattern)
  );
  assert.equal(splitPatternIds.size, 2, "the split authoring is genuinely two identities");
});

// --- Beat 6: removing the inflection staple restores the original ---------

test("Rob-and-John beat 6: removing the inflection staple restores the original indefinite Monday projection, unconditionally", () => {
  const { document, frame, pattern } = buildWorld();
  const before = times(occurrences(document, frame, { start: date(2020), end: date(2033) }));

  const { inflectionCoordinate, thursdayCoordinate } = sixYearsOnInflection();
  const staple = putStaple(document, {
    series: pattern.id,
    kind: "inflection",
    frame: frame.id,
    coordinate: inflectionCoordinate,
    payload: {
      rule: {
        rrule: { FREQ: "WEEKLY" },
        coordinate: thursdayCoordinate,
        frame: frame.id,
        magnitude: durationMagnitude("1", "hour")
      }
    }
  });
  assert.notDeepEqual(times(occurrences(document, frame, { start: date(2020), end: date(2033) })), before, "the staple really changed the projection");

  removeStaple(document, staple.id);
  assert.deepEqual(times(occurrences(document, frame, { start: date(2020), end: date(2033) })), before, "the full original projection is back, unconditionally");
  assert.equal(validateDocument(document).valid, true);
});

// --- Beat 7: the healing invariant holds across a rule change -------------

// Mirrors src/ui/inspector.js's prepareMaterialization, exactly as
// test/series-heal.test.js's own local helper does.
function materialize(document, fact, pattern) {
  const event = structuredClone(fact.event);
  event.id = createId("event");
  event.traits = (event.traits || []).filter((trait) => trait !== "generated");
  event.provenance = {
    kind: "explicit",
    replaces: fact.virtualId,
    pattern: pattern.id,
    originalCoordinate: structuredClone(fact.relation.coordinate)
  };
  const relation = structuredClone(fact.relation);
  relation.id = createId("relation");
  relation.event = event.id;
  relation.provenance = { kind: "explicit", replaces: fact.virtualId };
  const override = {
    id: createId("override"),
    virtual: fact.virtualId,
    suppress: true,
    replacements: [event.id]
  };
  document.events[event.id] = event;
  document.relations[relation.id] = relation;
  document.overrides[override.id] = override;
  return { event, relation, override };
}

test("Rob-and-John beat 7: the healing invariant holds across a rule change -- a materialized Thursday lunch heals like any occurrence", () => {
  const { document, frame, pattern } = buildWorld();
  const { inflectionCoordinate, thursdayCoordinate } = sixYearsOnInflection();
  putStaple(document, {
    series: pattern.id,
    kind: "inflection",
    frame: frame.id,
    coordinate: inflectionCoordinate,
    payload: {
      rule: {
        rrule: { FREQ: "WEEKLY" },
        coordinate: thursdayCoordinate,
        frame: frame.id,
        magnitude: durationMagnitude("1", "hour")
      }
    }
  });

  const engine = new ChronologEngine(document);
  const oneHour = durationMagnitude("1", "hour");
  const lunchFacts = engine.queryFacts({
    frame: frame.id, start: date(2032), end: date(2033), limit: 50, applyOverrides: false
  }).facts.filter((fact) =>
    fact.kind === "virtual"
    && durationMagnitudeDays(fact.event.magnitudes.duration).compare(durationMagnitudeDays(oneHour)) === 0);
  assert.ok(lunchFacts.length >= 2, "the second segment projects several Thursday lunches");
  const fact = lunchFacts[1];

  const { override, event } = materialize(document, fact, pattern);
  const decision = overrideHealDecision(document, engine, override);
  assert.equal(decision.healable, true, `a no-op materialization in the SECOND segment heals too (${decision.reason})`);

  const plan = planSeriesHeal(document, engine);
  assert.equal(plan.healed, 1);
  applySeriesHeal(document, plan);
  assert.equal(document.overrides[override.id], undefined);
  assert.equal(document.events[event.id], undefined);
  assert.equal(validateDocument(document).errors.length, 0);

  // The projection reasserts: the slot the override was hiding projects again.
  const restored = new ChronologEngine(document).queryFacts({
    frame: frame.id, start: date(2032), end: date(2033), limit: 50
  }).facts;
  assert.ok(restored.some((item) => item.virtualId === fact.virtualId), "the healed Thursday lunch slot projects once more");
});
