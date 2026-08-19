import assert from "node:assert/strict";
import test from "node:test";
import { ChronologEngine } from "../src/engine.js";
import { coordinate, daysFromCivil, Rational } from "../src/exact.js";
import { importICS } from "../src/ics.js";
import {
  addEvent,
  addFrame,
  addRelation,
  durationMagnitude,
  durationMagnitudeDays,
  putStaple,
  setSeriesEndStaple,
  validateDocument
} from "../src/model.js";
import { resolveObjectExtent } from "../src/staples.js";
import { createStructuralDocument } from "./helpers/sample-document.js";

// LEXICON.md's staple anchoring: "We should be able to place a staple --
// start, end, midpoint, etc. -- and a magnitude; or two or three staples and
// calculate magnitude. Also a fuzzy staple, e.g. 'about 5ish,' would be good
// too." This exercises `src/staples.js`'s `resolveObjectExtent` as wired into
// `src/engine.js`'s `indexedExplicitFacts` -- the end-anchored work shift the
// owner asked for, entering a friend's irregular schedule for D&D planning.

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

function withCalendar(document) {
  addFrame(document, { id: "calendar:work", title: "Work", traits: ["set", "calendar"], basis: "frame:wall-time" });
  return document;
}

function addShift(document, { duration = "8", unit = "hour", placedAt = civil(2026, 8, 10, 9, 0, 0) } = {}) {
  const event = addEvent(document, {
    traits: ["event"],
    magnitudes: { duration: durationMagnitude(duration, unit) },
    payload: { title: "Shift" }
  });
  const relation = addRelation(document, {
    type: "attachment",
    event: event.id,
    frame: "calendar:work",
    role: "placed",
    coordinate: placedAt
  });
  return { event, relation };
}

function factFor(engine, eventId, { start = date(2026, 8, 1), end = date(2026, 8, 20) } = {}) {
  return engine.queryFacts({ frame: "calendar:work", start, end, limit: 50 })
    .facts.find((fact) => fact.event.id === eventId);
}

// --- An end-anchored work shift --------------------------------------------

test("an end anchor plus the object's own magnitude places the shift, and moving the end moves the start", () => {
  const document = withCalendar(createStructuralDocument());
  const { event } = addShift(document, { duration: "8", unit: "hour" });
  const staple = putStaple(document, {
    object: event.id,
    kind: "anchor",
    role: "end",
    frame: "calendar:work",
    coordinate: civil(2026, 8, 10, 17, 0, 0)
  });
  assert.equal(validateDocument(document).valid, true);

  let engine = new ChronologEngine(document);
  let fact = factFor(engine, event.id);
  assert.equal(fact.extent.source, "anchor+magnitude");
  assert.deepEqual(
    fact.coordinate,
    engine.daysCoordinate("calendar:work", engine.coordinateDays("calendar:work", civil(2026, 8, 10, 9, 0, 0))),
    "8 hours back from a 17:00 end anchor is 09:00"
  );

  // Move the end staple. The magnitude (8 hours) is preserved -- the start
  // moves with it -- rather than the start staying put and the magnitude
  // being refit.
  putStaple(document, { id: staple.id, object: event.id, kind: "anchor", role: "end", frame: "calendar:work", coordinate: civil(2026, 8, 10, 18, 0, 0) });
  engine = new ChronologEngine(document);
  fact = factFor(engine, event.id);
  assert.deepEqual(
    fact.coordinate,
    engine.daysCoordinate("calendar:work", engine.coordinateDays("calendar:work", civil(2026, 8, 10, 10, 0, 0))),
    "the end moved an hour later, so the (preserved) 8-hour magnitude now starts an hour later too"
  );
});

// --- Two anchors derive the magnitude --------------------------------------

test("two anchors derive the magnitude; the object's own duration is ignored for placement", () => {
  const document = withCalendar(createStructuralDocument());
  // The object's OWN duration says 2 hours -- deliberately wrong, to prove it
  // is ignored once two anchors fully determine the extent.
  const { event } = addShift(document, { duration: "2", unit: "hour" });
  putStaple(document, { object: event.id, kind: "anchor", role: "start", frame: "calendar:work", coordinate: civil(2026, 8, 10, 9, 0, 0) });
  putStaple(document, { object: event.id, kind: "anchor", role: "end", frame: "calendar:work", coordinate: civil(2026, 8, 10, 17, 30, 0) });
  assert.equal(validateDocument(document).valid, true);

  const engine = new ChronologEngine(document);
  const fact = factFor(engine, event.id);
  assert.equal(fact.extent.source, "anchors");
  assert.equal(fact.extent.derivedMagnitude, true);
  const expectedMagnitude = Rational.parse(17.5 - 9);
  assert.equal(fact.extent.magnitudeDays.compare(expectedMagnitude.div(24)), 0, "8.5 hours, derived, not the object's stored 2");
  assert.deepEqual(fact.coordinate, engine.daysCoordinate("calendar:work", engine.coordinateDays("calendar:work", civil(2026, 8, 10, 9, 0, 0))));
});

// --- Three anchors: the third is overdetermined, never averaged in --------

test("three anchors: the two highest-precedence roles win; the third is reported overdetermined and never averaged in", () => {
  const document = withCalendar(createStructuralDocument());
  const { event } = addShift(document);
  putStaple(document, { object: event.id, kind: "anchor", role: "start", frame: "calendar:work", coordinate: civil(2026, 8, 10, 9, 0, 0) });
  putStaple(document, { object: event.id, kind: "anchor", role: "end", frame: "calendar:work", coordinate: civil(2026, 8, 10, 17, 0, 0) });
  // A midpoint that does NOT agree with the start/end pair's own midpoint
  // (13:00) -- if it were averaged in, the resolved extent would shift.
  const midpoint = putStaple(document, { object: event.id, kind: "anchor", role: "midpoint", frame: "calendar:work", coordinate: civil(2026, 8, 10, 15, 0, 0) });

  const engine = new ChronologEngine(document);
  const extent = resolveObjectExtent(document, engine, event.id);
  assert.equal(extent.startDays.compare(engine.coordinateDays("calendar:work", civil(2026, 8, 10, 9, 0, 0))), 0, "start/end win, unmoved by the midpoint");
  assert.equal(extent.endDays.compare(engine.coordinateDays("calendar:work", civil(2026, 8, 10, 17, 0, 0))), 0);
  assert.ok(extent.overdetermined.some((item) => item.staple.id === midpoint.id), "the midpoint is reported, not silently dropped");
});

// --- Fuzzy staples: spread survives and two fuzzy anchors' spreads add ----

test("a fuzzy staple's spread reaches the fact, and two fuzzy anchors' spreads add", () => {
  const document = withCalendar(createStructuralDocument());
  const { event } = addShift(document);
  putStaple(document, {
    object: event.id, kind: "anchor", role: "start", frame: "calendar:work", coordinate: civil(2026, 8, 10, 9, 0, 0),
    spread: { before: durationMagnitude("10", "minute"), after: durationMagnitude("5", "minute") }
  });
  putStaple(document, {
    object: event.id, kind: "anchor", role: "end", frame: "calendar:work", coordinate: civil(2026, 8, 10, 17, 0, 0),
    spread: { before: durationMagnitude("15", "minute"), after: durationMagnitude("20", "minute") }
  });
  assert.equal(validateDocument(document).valid, true);

  const engine = new ChronologEngine(document);
  const fact = factFor(engine, event.id);
  assert.ok(fact.extent.spread, "the spread reaches the fact");
  const expectedBefore = durationMagnitudeDays(durationMagnitude("10", "minute")).add(durationMagnitudeDays(durationMagnitude("15", "minute")));
  const expectedAfter = durationMagnitudeDays(durationMagnitude("5", "minute")).add(durationMagnitudeDays(durationMagnitude("20", "minute")));
  assert.equal(fact.extent.spread.start.before.compare(expectedBefore), 0, "uncertainties add, they do not cancel");
  assert.equal(fact.extent.spread.start.after.compare(expectedAfter), 0);
  assert.equal(fact.extent.spread.end.before.compare(expectedBefore), 0, "the same derived spread applies to both ends");
});

// --- The hard regression: zero anchors resolve bit-identically ------------

test("REGRESSION GUARD: an event with no anchor staples resolves bit-identically to plain start-plus-duration placement", () => {
  const document = withCalendar(createStructuralDocument());
  const { event, relation } = addShift(document, { placedAt: civil(2026, 8, 10, 9, 0, 0) });
  assert.equal(validateDocument(document).valid, true);

  const engine = new ChronologEngine(document);
  const fact = factFor(engine, event.id);
  assert.equal(fact.extent.source, "placement", "no anchors -- the zero-anchor fallback");
  // Not merely equal in value -- the SAME coordinate object the relation
  // already carried, proving nothing was re-derived for the ordinary case.
  assert.equal(fact.coordinate, relation.coordinate, "identical object reference, not a re-derivation");
  assert.equal(fact.day, engine.coordinateDays(relation.frame, relation.coordinate).toJSON());
});

// --- Exactness: a bare-digit anchor against a zero-padded ICS import ------

test("a bare-digit anchor staple and a zero-padded ICS-imported event resolve to the exact same instant", () => {
  const document = createStructuralDocument();
  const source = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Test//EN",
    "BEGIN:VEVENT",
    "UID:shift@example.test",
    "DTSTART:20260819T090000Z",
    "DURATION:PT2H",
    "SUMMARY:Shift",
    "END:VEVENT",
    "END:VCALENDAR",
    ""
  ].join("\r\n");
  const imported = importICS(source, document, { label: "Work" });
  const eventId = imported.events[0];
  const relation = Object.values(document.relations).find(
    (item) => item.type === "attachment" && item.event === eventId
  );
  const before = new ChronologEngine(document);
  const originalStart = before.coordinateDays(relation.frame, relation.coordinate);

  // Anchor the SAME end instant (09:00 + 2h = 11:00) with bare-digit levels,
  // exactly the shape a hand-authored editor field would produce -- the
  // named risk being that ICS writes month "08" where this writes "8".
  putStaple(document, {
    object: eventId,
    kind: "anchor",
    role: "end",
    frame: relation.frame,
    coordinate: coordinate([
      { level: "year", value: "2026" },
      { level: "month", value: "8" },
      { level: "day", value: "19" },
      { level: "hour", value: "11" },
      { level: "minute", value: "0" },
      { level: "second", value: "0" }
    ])
  });
  const engine = new ChronologEngine(document);
  const extent = resolveObjectExtent(document, engine, eventId);
  assert.equal(
    extent.startDays.compare(originalStart), 0,
    "the bare-digit anchor's derived start and the zero-padded import's own start are the exact same instant"
  );
});

// --- The cache-invalidation trap --------------------------------------------

// CACHE INVALIDATION TRAP (found while integrating the substrate): a staple
// is stored as a `relations` record, and `src/ui/transactions.js`'s
// `executeRecordChange` defaults `preserveRecurrence` to `mapName !== "patterns"`
// -- true for the `relations` map, which is also where plain attachments and
// memberships live and CAN safely preserve the cache. A caller cannot tell a
// staple-carrying relations edit apart from an ordinary one by map name
// alone, so a staple placed through such a path would silently serve stale
// occurrences from `recurrenceWindows`/`recurrenceSeries` -- the staple
// would appear not to work. The fix lives in `ChronologEngine.setDocument`:
// it fingerprints the document's staple relations independently of whatever
// `preserveRecurrence` the caller asked for, and only honors the request
// when staples provably did not change. This test drives that fix directly
// through the engine (not through src/ui/transactions.js, which this worker
// does not own) -- exactly the shape a real edit path produces: the SAME
// document object mutated in place, then re-indexed with
// `preserveRecurrence: true`.
test("CACHE INVALIDATION TRAP: a staple placed while the recurrence cache claims to be preserved still changes the projection", () => {
  const document = createStructuralDocument();
  const source = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Test//EN",
    "BEGIN:VEVENT",
    "UID:standing@example.test",
    "DTSTART:20260105T090000Z",
    "RRULE:FREQ=WEEKLY",
    "SUMMARY:Standing meeting",
    "DURATION:PT30M",
    "END:VEVENT",
    "END:VCALENDAR",
    ""
  ].join("\r\n");
  const imported = importICS(source, document, { label: "Calendar" });
  const frame = imported.frames[0];
  const pattern = Object.values(document.patterns).find((item) => item.kind === "ics-rrule");

  const engine = new ChronologEngine(document);
  const window = { start: date(2026, 1, 1), end: date(2026, 3, 1), limit: 200 };
  const before = engine.queryFacts({ frame, ...window }).facts;
  assert.ok(engine.recurrenceWindows.size > 0, "the open-ended rule populated the windowed recurrence cache");
  assert.ok(before.length > 4, "several occurrences project before the staple");

  // Mutate the SAME document object in place -- exactly how a real edit path
  // works (src/ui/transactions.js always mutates `documentValue` directly) --
  // then re-index claiming the recurrence cache is preserved, exactly what
  // `executeRecordChange`'s default does for any non-"patterns" map record.
  setSeriesEndStaple(document, pattern.id, frame, civil(2026, 1, 19, 9, 0, 0));
  engine.setDocument(document, { preserveRecurrence: true });

  const after = engine.queryFacts({ frame, ...window }).facts;
  assert.deepEqual(
    after.map((fact) => fact.day),
    before.slice(0, 3).map((fact) => fact.day),
    "the staple's cut is honored even though the caller claimed the cache could be preserved"
  );
  assert.ok(after.length < before.length, "the series is genuinely shorter now, not served stale from the cache");
});

// The generalized rule, exercised directly: staples changing is what forces a
// fresh index, regardless of the caller's own belief about which map an edit
// touched -- and an edit that genuinely has nothing to do with staples still
// gets to keep its cache, so this is not "never trust preserveRecurrence",
// it is "trust it only once it is verified".
test("an ordinary relations-map edit with no staple change still gets to preserve the recurrence cache", () => {
  const document = createStructuralDocument();
  const source = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Test//EN",
    "BEGIN:VEVENT",
    "UID:standing@example.test",
    "DTSTART:20260105T090000Z",
    "RRULE:FREQ=WEEKLY",
    "SUMMARY:Standing meeting",
    "DURATION:PT30M",
    "END:VEVENT",
    "END:VCALENDAR",
    ""
  ].join("\r\n");
  const imported = importICS(source, document, { label: "Calendar" });
  const frame = imported.frames[0];
  const engine = new ChronologEngine(document);
  const window = { start: date(2026, 1, 1), end: date(2026, 3, 1), limit: 200 };
  engine.queryFacts({ frame, ...window });
  const cache = engine.recurrenceWindows;

  // An unrelated relations-map record -- an ordinary explicit event -- is
  // added; no staple anywhere is touched.
  const unrelated = addEvent(document, {
    traits: ["event"],
    magnitudes: { duration: durationMagnitude("0") },
    payload: { title: "Unrelated" }
  });
  addRelation(document, { type: "attachment", event: unrelated.id, frame, role: "placed", coordinate: date(2026, 6, 1) });
  engine.setDocument(document, { preserveRecurrence: true });
  assert.equal(engine.recurrenceWindows, cache, "the recurrence cache instance survives when staples did not change");
});
