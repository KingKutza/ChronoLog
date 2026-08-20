import assert from "node:assert/strict";
import test from "node:test";
import { ChronologEngine } from "../src/engine.js";
import { Rational, coordinate, daysFromCivil } from "../src/exact.js";
import {
  exportICS,
  importICS,
  parseICSTree,
  property
} from "../src/ics.js";
import {
  addEvent,
  addRelation,
  durationMagnitude,
  frameEnd,
  objectEnd,
  putStaple,
  seriesEnd,
  seriesEndStaple,
  setSeriesEndStaple,
  validateDocument
} from "../src/model.js";
import {
  frameEndOf,
  objectEndsOf,
  resolveObjectExtent,
  seriesSegments,
  stapleSpreadDays,
  staplesForObject
} from "../src/staples.js";
import { createSampleDocument, createStructuralDocument } from "./helpers/sample-document.js";

// The lead's ruled ICS contract for the staple substrate (LEXICON's staple
// anchoring / Rob-and-John scenario, ROADMAP #4):
//
//   (a) segment 0 exports exactly as today -- one VEVENT, UNTIL derived at
//       serialization from any partitioning staple, never stored in the rule.
//   (b) a following segment (a rule change part-way through a series) exports
//       as a SIBLING VEVENT, carrying X-CHRONOLOG-SERIES/-SEGMENT-INDEX so a
//       ChronoLog re-import rejoins the identity, while any other calendar
//       just sees the real meetings.
//   (c) anchors/magnitudes/spreads are ChronoLog-native: the DERIVED extent
//       exports as ordinary DTSTART/DTEND, and the authored intent rides
//       along as X-CHRONOLOG-ANCHOR / X-CHRONOLOG-SPREAD so a ChronoLog
//       re-import reconstructs it losslessly.
//   (d) import only ever reconstructs staples from those X-properties --
//       never inferred from a title, category, or duration.
//   (e) COUNT and a partitioning staple together truncate COUNT rather than
//       emit the RFC-5545-illegal COUNT+UNTIL combination.
//
// Every comparison here that touches a coordinate goes through exact Rational
// days (`civilCoordinateToDays`/`engine.coordinateDays`), matching this
// module's own documented hazard: ICS writes month "01" where a hand-authored
// coordinate writes "1".

const NOW = new Date(Date.UTC(2026, 7, 19, 12, 0, 0));

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

function paramValue(prop, name) {
  return prop?.params?.find((item) => item.name === name)?.values?.[0] || null;
}

function findVEVENTs(icsText) {
  const tree = parseICSTree(icsText);
  return tree.components[0].components.filter((item) => item.name === "VEVENT");
}

// A real recurring series, imported from ICS exactly the way the sibling
// series-staple.test.js builds its fixtures -- every record carries exactly
// the fields the app gives it, which is what makes the digit-padding hazard
// this file guards against a real risk rather than a hand-waved one.
function weeklySeries({ until, count } = {}) {
  const document = createStructuralDocument();
  const rrule = until ? `FREQ=WEEKLY;UNTIL=${until}`
    : count ? `FREQ=WEEKLY;COUNT=${count}`
    : "FREQ=WEEKLY";
  const source = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Test//EN",
    "BEGIN:VEVENT",
    "UID:standing@example.test",
    "DTSTART:20260105T090000Z",
    `RRULE:${rrule}`,
    "SUMMARY:Standing meeting",
    "DURATION:PT30M",
    "END:VEVENT",
    "END:VCALENDAR",
    ""
  ].join("\r\n");
  const imported = importICS(source, document, { label: "Calendar" });
  const frame = document.frames[imported.frames[0]];
  const pattern = Object.values(document.patterns).find((item) => item.kind === "ics-rrule");
  return { document, frame, pattern };
}

test("segment 0 exports exactly as today: an unstapled series' rule text is untouched, and no X-CHRONOLOG properties appear", () => {
  const { document, frame } = weeklySeries();
  const engine = new ChronologEngine(document);
  const output = exportICS(document, { frame: frame.id, engine, now: NOW });
  assert.equal(findVEVENTs(output).length, 1, "no sibling VEVENTs for an un-partitioned series");
  assert.match(output, /RRULE:FREQ=WEEKLY\r\n/, "the rule's own text is untouched -- no UNTIL invented");
  assert.doesNotMatch(output, /X-CHRONOLOG/, "no staple annotations exist to export");
});

test("an end-staple's UNTIL is derived at export time and never stored in the rule", () => {
  const { document, frame, pattern } = weeklySeries();
  setSeriesEndStaple(document, pattern.id, frame.id, civil(2026, 1, 19, 9, 0, 0));
  const staple = seriesEndStaple(document, pattern.id);
  const engine = new ChronologEngine(document);
  const output = exportICS(document, { frame: frame.id, engine, now: NOW });
  assert.equal(findVEVENTs(output).length, 1, "an end-staple (no following rule) stays one VEVENT");
  assert.match(output, /RRULE:FREQ=WEEKLY;UNTIL=20260119T090000/);
  assert.doesNotMatch(output, new RegExp(staple.id), "the staple's own record id never appears in the exported text");
  // Untouched: the staple never gets written back onto the pattern's own rule.
  assert.equal(pattern.rrule.UNTIL, undefined);
});

test("export's staple-vs-rule comparison is exact-numeric: a bare-digit staple wins over a later, zero-padded rule UNTIL", () => {
  const { document, frame, pattern } = weeklySeries({ until: "20260301T000000" });
  // Authored with bare digits, as the editor's own date/time inputs naturally
  // produce -- the named hazard: ICS writes month "01", this writes "1".
  setSeriesEndStaple(document, pattern.id, frame.id, coordinate([
    { level: "year", value: "2026" },
    { level: "month", value: "1" },
    { level: "day", value: "19" },
    { level: "hour", value: "9" },
    { level: "minute", value: "0" },
    { level: "second", value: "0" }
  ]));
  const engine = new ChronologEngine(document);
  const output = exportICS(document, { frame: frame.id, engine, now: NOW });
  assert.match(
    output,
    /RRULE:FREQ=WEEKLY;UNTIL=20260119T090000/,
    "the bare-digit staple (earlier) wins over the rule's own later, zero-padded UNTIL"
  );
  assert.doesNotThrow(() => parseICSTree(output));
});

test("COUNT plus a partitioning staple truncates COUNT instead of emitting the illegal COUNT+UNTIL combination", () => {
  const { document, frame, pattern } = weeklySeries({ count: 10 });
  // Mondays 2026-01-05, -12, -19, -26, ...; the staple lands on the third.
  setSeriesEndStaple(document, pattern.id, frame.id, civil(2026, 1, 19, 9, 0, 0));
  const engine = new ChronologEngine(document);
  const output = exportICS(document, { frame: frame.id, engine, now: NOW });
  assert.match(output, /RRULE:FREQ=WEEKLY;COUNT=3\r\n/, "COUNT is truncated to what the staple actually leaves standing");
  assert.doesNotMatch(output, /UNTIL/, "COUNT and UNTIL never appear together -- RFC 5545 forbids it");
  assert.doesNotThrow(() => parseICSTree(output));
  // The truncated rule really does describe the surviving projection.
  const facts = engine.queryFacts({
    frame: frame.id,
    start: civil(2026, 1, 1),
    end: civil(2026, 3, 1),
    applyOverrides: false
  }).facts.filter((fact) => fact.kind === "virtual");
  assert.equal(facts.length, 3);
});

test("a segmented series exports sibling VEVENTs with stable X-CHRONOLOG-SERIES linkage, and re-export of an unchanged document is byte-identical", () => {
  const { document, frame, pattern } = weeklySeries();
  // Rob-and-John: Monday 09:00 meetings end 2026-01-19; a Thursday lunch rule
  // begins after it, at an independently authored time of its own.
  const inflection = putStaple(document, {
    kind: "inflection",
    ends: [seriesEnd(pattern.id), frameEnd(frame.id, civil(2026, 1, 19, 9, 0, 0))],
    payload: {
      rule: {
        rrule: { FREQ: "WEEKLY" },
        coordinate: civil(2026, 1, 22, 12, 0, 0),
        frame: frame.id
      }
    }
  });
  const engine = new ChronologEngine(document);
  const first = exportICS(document, { frame: frame.id, engine, now: NOW });
  assert.equal(validateDocument(document).valid, true);

  const vevents = findVEVENTs(first);
  assert.equal(vevents.length, 2, "segment 0 plus one sibling for the following rule");
  const base = vevents[0];
  const sibling = vevents[1];
  const baseUid = property(base, "UID").value;

  assert.equal(property(sibling, "X-CHRONOLOG-SERIES").value, baseUid);
  assert.equal(property(sibling, "X-CHRONOLOG-SEGMENT-INDEX").value, "1");
  assert.notEqual(property(sibling, "UID").value, baseUid, "the sibling has its own, distinct UID");
  assert.match(property(sibling, "DTSTART").value, /^20260122T120000/);
  assert.match(property(sibling, "RRULE").value, /FREQ=WEEKLY/);

  const inflectionProp = property(sibling, "X-CHRONOLOG-INFLECTION");
  assert.ok(inflectionProp, "the partitioning staple's own coordinate rides along, independent of the sibling's DTSTART");
  assert.equal(paramValue(inflectionProp, "FRAME"), frame.id);
  assert.match(inflectionProp.value, /^20260119T090000/);

  // Segment 0 itself stopped at the inflection point, not left running forever
  // (which would double-book against the sibling's own occurrences).
  assert.match(property(base, "RRULE").value, /UNTIL=20260119T090000/);

  // A re-export of the exact same document, same clock, is byte-identical --
  // no random ids, or every sync would churn.
  const second = exportICS(document, { frame: frame.id, engine: new ChronologEngine(document), now: NOW });
  assert.equal(first, second);

  // And a re-import of ChronoLog's own export rejoins the two VEVENTs into one
  // series identity: one pattern, two segments, no spurious extra event for
  // the sibling.
  const reimported = createStructuralDocument();
  importICS(first, reimported, { label: "Reimport" });
  assert.equal(validateDocument(reimported).valid, true, "the reconstructed staple resolves against a real frame, not a stale foreign one");
  assert.equal(Object.keys(reimported.events).length, 1, "the sibling reconstructs a staple, not a second event");
  const reimportedPattern = Object.values(reimported.patterns).find((item) => item.kind === "ics-rrule");
  assert.ok(reimportedPattern);
  const reimportedEngine = new ChronologEngine(reimported);
  const segments = seriesSegments(reimportedEngine, reimportedPattern);
  assert.equal(segments.length, 2, "the inflection staple reconstructs a second segment");
  assert.equal(segments[0].untilDays.compare(new Rational(daysFromCivil(2026n, 1n, 19n)).add(Rational.parse(9).div(24))), 0);
  assert.equal(segments[1].rrule.FREQ, "WEEKLY");
  const expectedSiblingBase = new Rational(daysFromCivil(2026n, 1n, 22n)).add(Rational.parse(12).div(24));
  assert.equal(
    reimportedEngine.coordinateDays(segments[1].frame, segments[1].baseCoordinate).compare(expectedSiblingBase),
    0
  );

  assert.equal(document.relations[inflection.id].kind, "inflection", "the original staple is untouched by export");
});

test("ChronoLog to ICS to ChronoLog round-trip reproduces an anchor and its spread exactly", () => {
  const document = createSampleDocument({ includeEvents: false, includePattern: false });
  const shift = addEvent(document, {
    traits: ["event"],
    magnitudes: { duration: durationMagnitude("7", "hour") },
    payload: { title: "Night shift" }
  });
  addRelation(document, {
    type: "attachment",
    event: shift.id,
    frame: "calendar:personal",
    role: "placed",
    // A placeholder placement; the end anchor below is what actually decides
    // where this event sits once it exists.
    coordinate: civil(2026, 3, 2, 22, 0, 0)
  });
  putStaple(document, {
    kind: "anchor",
    ends: [objectEnd(shift.id, "end"), frameEnd("calendar:personal", civil(2026, 3, 3, 5, 0, 0))],
    spread: {
      before: { frame: "measure:human-time", value: { levels: [{ level: "hour", value: "1" }] } },
      after: { frame: "measure:human-time", value: { levels: [{ level: "minute", value: "30" }] } }
    }
  });
  const engine = new ChronologEngine(document);
  const output = exportICS(document, { frame: "calendar:personal", engine, now: NOW });

  const [vevent] = findVEVENTs(output);
  // The DERIVED extent exports as ordinary DTSTART/DTEND -- an end-anchored
  // shift must not export as a broken event to any other calendar.
  assert.match(property(vevent, "DTSTART").value, /^20260302T220000/);
  assert.match(property(vevent, "DTEND").value, /^20260303T050000/);

  const anchorProp = property(vevent, "X-CHRONOLOG-ANCHOR");
  assert.ok(anchorProp);
  assert.equal(paramValue(anchorProp, "ROLE"), "end");
  assert.match(anchorProp.value, /^20260303T050000/);
  const spreadProp = property(vevent, "X-CHRONOLOG-SPREAD");
  assert.ok(spreadProp);
  assert.equal(paramValue(spreadProp, "ID"), paramValue(anchorProp, "ID"));
  assert.equal(paramValue(spreadProp, "BEFORE"), "1/24");
  assert.equal(paramValue(spreadProp, "AFTER"), "1/48");

  const reimported = createSampleDocument({ includeEvents: false, includePattern: false });
  importICS(output, reimported, { label: "Reimport" });
  assert.equal(validateDocument(reimported).valid, true);
  const reimportedEvent = Object.values(reimported.events).find((item) => item.payload.title === "Night shift");
  assert.ok(reimportedEvent);
  const staples = staplesForObject(reimported, reimportedEvent.id);
  assert.equal(staples.length, 1, "exactly the one authored anchor comes back, nothing invented");
  const reimportedObjectEnd = objectEndsOf(staples[0]).find((end) => end.object === reimportedEvent.id);
  assert.equal(reimportedObjectEnd?.point, "end");
  assert.ok(staples[0].spread, "the fuzziness comes back too");

  const reimportedEngine = new ChronologEngine(reimported);
  const originalDays = engine.coordinateDays("calendar:personal", civil(2026, 3, 3, 5, 0, 0));
  const reimportedFar = frameEndOf(staples[0]);
  const reimportedDays = reimportedEngine.coordinateDays(reimportedFar.frame, reimportedFar.coordinate);
  assert.equal(reimportedDays.compare(originalDays), 0, "the exact instant round-trips, not merely a similar one");

  const reimportedSpread = stapleSpreadDays(staples[0]);
  assert.ok(reimportedSpread);
  assert.equal(reimportedSpread.before.compare(Rational.parse(1).div(24)), 0, "the exact BEFORE fuzziness round-trips");
  assert.equal(reimportedSpread.after.compare(Rational.parse(1).div(48)), 0, "the exact AFTER fuzziness round-trips");
});

test("a foreign ICS calendar (no X-CHRONOLOG properties) imports with no staples invented", () => {
  const source = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Other Vendor//EN",
    "BEGIN:VEVENT",
    "UID:plain@example.test",
    "DTSTART:20260806T090000Z",
    "DTEND:20260806T170000Z",
    "SUMMARY:An ordinary all-day-feeling shift",
    "END:VEVENT",
    "BEGIN:VEVENT",
    "UID:standing@example.test",
    "DTSTART:20260105T090000Z",
    "RRULE:FREQ=WEEKLY",
    "SUMMARY:Standing meeting",
    "END:VEVENT",
    "END:VCALENDAR",
    ""
  ].join("\r\n");
  const document = createStructuralDocument();
  importICS(source, document, { label: "Foreign" });
  const staples = Object.values(document.relations).filter((relation) => relation.type === "staple");
  assert.deepEqual(staples, [], "meaning is authored, never inferred -- a plain import invents nothing");
  assert.equal(validateDocument(document).valid, true);
});

test("an object-to-object connection round-trips through export and reimport, and a foreign reader sees the correct resolved extent", () => {
  const document = createSampleDocument({ includeEvents: false, includePattern: false });
  const shift = addEvent(document, {
    traits: ["event"],
    magnitudes: { duration: durationMagnitude("7", "hour") },
    payload: { title: "Shift" }
  });
  addRelation(document, {
    type: "attachment",
    event: shift.id,
    frame: "calendar:personal",
    role: "placed",
    coordinate: civil(2026, 3, 2, 22, 0, 0)
  });
  const handoff = addEvent(document, {
    traits: ["event"],
    magnitudes: { duration: durationMagnitude("30", "minute") },
    payload: { title: "Handoff meeting" }
  });
  addRelation(document, {
    type: "attachment",
    event: handoff.id,
    frame: "calendar:personal",
    role: "placed",
    // A placeholder placement, chosen consistent with what the connection
    // below implies -- exactly as the shift's own placement above is chosen
    // consistent with its own end anchor. Both objects independently name a
    // point (LEXICON's staple axiom), and a staple that connects two
    // independently authored points to DIFFERENT instants would be a
    // contradiction no different from two frame anchors disagreeing; this
    // fixture is the connection actually holding, not a coincidence the
    // substrate requires.
    coordinate: civil(2026, 3, 3, 5, 0, 0)
  });
  putStaple(document, {
    kind: "anchor",
    // ICS has no property for "this event's start IS that event's end" --
    // this is exactly that connection, expressed as two object ends.
    ends: [objectEnd(handoff.id, "start"), objectEnd(shift.id, "end")]
  });
  const engine = new ChronologEngine(document);
  const output = exportICS(document, { frame: "calendar:personal", engine, now: NOW });

  const [shiftVevent, handoffVevent] = findVEVENTs(output);
  // The derived extent exports as ordinary DTSTART/DTEND -- a foreign reader
  // with no idea what X-CHRONOLOG-ANCHOR means still sees the correct times.
  assert.match(property(shiftVevent, "DTEND").value, /^20260303T050000/);
  assert.match(property(handoffVevent, "DTSTART").value, /^20260303T050000/);
  assert.match(property(handoffVevent, "DTEND").value, /^20260303T053000/);

  const anchorProp = property(handoffVevent, "X-CHRONOLOG-ANCHOR");
  assert.ok(anchorProp, "the connection's intent rides along on the same property, not a second one");
  assert.equal(paramValue(anchorProp, "ROLE"), "start");
  assert.equal(paramValue(anchorProp, "TO-POINT"), "end");
  assert.equal(paramValue(anchorProp, "TO-UID"), property(shiftVevent, "UID").value);
  assert.match(
    anchorProp.value,
    /^20260303T050000/,
    "the property VALUE is the connection's resolved instant, correct even if TO-UID/TO-POINT are ignored"
  );

  const reimported = createSampleDocument({ includeEvents: false, includePattern: false });
  importICS(output, reimported, { label: "Reimport" });
  assert.equal(validateDocument(reimported).valid, true);
  const reimportedShift = Object.values(reimported.events).find((item) => item.payload.title === "Shift");
  const reimportedHandoff = Object.values(reimported.events).find((item) => item.payload.title === "Handoff meeting");
  assert.ok(reimportedShift && reimportedHandoff);

  const reimportedStaples = staplesForObject(reimported, reimportedHandoff.id);
  assert.equal(reimportedStaples.length, 1, "the connection reconstructs as one staple, not a frame fallback");
  const ends = objectEndsOf(reimportedStaples[0]);
  assert.equal(ends.length, 2, "both ends are object ends -- an object-to-object connection was rebuilt");
  assert.equal(ends.find((end) => end.object === reimportedHandoff.id)?.point, "start");
  assert.equal(ends.find((end) => end.object === reimportedShift.id)?.point, "end");

  const reimportedEngine = new ChronologEngine(reimported);
  const reimportedExtent = resolveObjectExtent(reimported, reimportedEngine, reimportedHandoff.id);
  assert.equal(
    reimportedExtent.startDays.compare(engine.coordinateDays("calendar:personal", civil(2026, 3, 3, 5, 0, 0))),
    0,
    "the reconstructed connection resolves to the same instant the original export computed"
  );
});

test("an unresolved TO-UID falls back to a frame anchor at the exported instant, rather than dropping the staple or fabricating a dangling object end", () => {
  const source = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Test//EN",
    "BEGIN:VEVENT",
    "UID:standalone@example.test",
    "DTSTART:20260302T220000Z",
    "DTEND:20260303T050000Z",
    "SUMMARY:Standalone",
    // TO-UID names an event that was never part of this calendar at all --
    // an export window that dropped the other half, or a hand-edited file.
    "X-CHRONOLOG-ANCHOR;ID=abc123;ROLE=end;TO-UID=missing@nowhere.test;TO-POINT=start:20260303T050000Z",
    "END:VEVENT",
    "END:VCALENDAR",
    ""
  ].join("\r\n");
  const document = createStructuralDocument();
  importICS(source, document, { label: "Reimport" });
  assert.equal(validateDocument(document).valid, true, "no dangling object end is ever fabricated");

  const event = Object.values(document.events).find((item) => item.payload.title === "Standalone");
  assert.ok(event);
  const staples = staplesForObject(document, event.id);
  assert.equal(staples.length, 1, "the connection is not silently dropped");
  const ends = objectEndsOf(staples[0]);
  assert.equal(ends.length, 1, "the unresolvable far end became a frame, not a second object end");
  assert.equal(ends[0].point, "end");

  const far = frameEndOf(staples[0]);
  assert.ok(far, "the fallback is a frame anchor -- correct in wall time, the connection itself is lost");
  const engine = new ChronologEngine(document);
  assert.equal(
    engine.coordinateDays(far.frame, far.coordinate).compare(engine.coordinateDays(far.frame, civil(2026, 3, 3, 5, 0, 0))),
    0,
    "the exported instant is preserved exactly, even though TO-UID could not resolve"
  );
});

test("a correspondence staple (frame-to-frame) never appears on any VEVENT, and export does not throw", () => {
  const document = createSampleDocument({ includeEvents: false, includePattern: false });
  const event = addEvent(document, {
    traits: ["event"],
    magnitudes: { duration: durationMagnitude("1", "hour") },
    payload: { title: "Ordinary meeting" }
  });
  addRelation(document, {
    type: "attachment",
    event: event.id,
    frame: "calendar:personal",
    role: "placed",
    coordinate: civil(2026, 4, 1, 9, 0, 0)
  });
  // Frame-to-frame, no object or series end at all -- not an event property,
  // and must not be written onto any VEVENT.
  const correspondence = putStaple(document, {
    kind: "correspondence",
    ends: [
      frameEnd("calendar:personal", civil(2026, 4, 1, 0, 0, 0)),
      frameEnd("frame:wall-time", civil(2026, 4, 1, 0, 0, 0))
    ]
  });
  assert.equal(validateDocument(document).valid, true);
  const engine = new ChronologEngine(document);
  let output;
  assert.doesNotThrow(() => {
    output = exportICS(document, { frame: "calendar:personal", engine, now: NOW });
  });
  assert.doesNotMatch(
    output,
    new RegExp(correspondence.id),
    "the correspondence staple's own record id never appears on any VEVENT"
  );
  assert.doesNotMatch(output, /X-CHRONOLOG-ANCHOR/, "a correspondence is not an anchor and must not export as one");
});
