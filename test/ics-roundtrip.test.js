import test from "node:test";
import assert from "node:assert/strict";
import { createCelestialDocument } from "../src/celestial.js";
import { ChronologEngine } from "../src/engine.js";
import { civilCoordinateToDays, coordinate, daysFromCivil } from "../src/exact.js";
import { escapeICSText, exportICS, importICS, parseICSTree, unescapeICSText } from "../src/ics.js";
import { addEvent, addRelation, durationMagnitude } from "../src/model.js";

const NOW = new Date(Date.UTC(2026, 7, 7, 12, 0, 0));

function date(year, month = "1", day = "1") {
  return coordinate([
    { level: "year", value: String(year) },
    { level: "month", value: String(month) },
    { level: "day", value: String(day) }
  ]);
}

function vcalendar(lines) {
  return [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Test//EN",
    ...lines,
    "END:VCALENDAR",
    ""
  ].join("\r\n");
}

function importCalendar(lines) {
  const document = createCelestialDocument();
  const result = importICS(vcalendar(lines), document, { label: "Roundtrip" });
  return { document, result };
}

test("unescapeICSText decodes escapes in a single pass and inverts escapeICSText", () => {
  assert.equal(unescapeICSText("C:\\\\new folder"), "C:\\new folder");
  for (const text of ["C:\\new folder", "line\nbreak", "semi;colon, comma", "tail\\", "\\n kept \\\\n"]) {
    assert.equal(unescapeICSText(escapeICSText(text)), text);
  }
  const { document } = importCalendar([
    "BEGIN:VEVENT",
    "UID:desc@example.test",
    "DTSTART:20260806T090000Z",
    "SUMMARY:Files",
    "DESCRIPTION:C:\\\\new folder",
    "END:VEVENT"
  ]);
  const event = Object.values(document.events).find((item) => item.payload.uid === "desc@example.test");
  assert.equal(event.payload.description, "C:\\new folder");
});

test("EXDATE export preserves params, value typing, and multiplicity", () => {
  const { document, result } = importCalendar([
    "BEGIN:VEVENT",
    "UID:ex@example.test",
    "DTSTART;TZID=Test/Zone:20260806T090000",
    "RRULE:FREQ=DAILY;COUNT=5",
    "EXDATE;TZID=Test/Zone:20260808T090000",
    "EXDATE;VALUE=DATE:20260809",
    "SUMMARY:Recurring",
    "END:VEVENT"
  ]);
  const engine = new ChronologEngine(document);
  const facts = engine.queryFacts({ frame: result.frames[0], start: date(2026, 8, 1), end: date(2026, 8, 12) });
  const mine = facts.facts.filter((fact) => fact.event.payload.uid === "ex@example.test");
  assert.equal(mine.length, 3);
  const output = exportICS(document, { frame: result.frames[0], now: NOW });
  assert.ok(output.includes("EXDATE;TZID=Test/Zone:20260808T090000"));
  assert.ok(output.includes("EXDATE;VALUE=DATE:20260809"));
  assert.equal((output.match(/EXDATE/g) || []).length, 2);
  assert.doesNotThrow(() => parseICSTree(output));
});

test("VTODO round-trips DTSTART, DTSTAMP, and COMPLETED distinctly", () => {
  const { document, result } = importCalendar([
    "BEGIN:VTODO",
    "UID:todo@example.test",
    "SUMMARY:Started task",
    "DTSTART:20260805T120000Z",
    "DTSTAMP:20260807T010000Z",
    "COMPLETED:20260806T230000Z",
    "END:VTODO"
  ]);
  const task = Object.values(document.events).find((event) => event.traits.includes("task"));
  const roles = Object.values(document.relations)
    .filter((relation) => relation.event === task.id)
    .map((relation) => relation.role)
    .sort();
  assert.deepEqual(roles, ["completed", "observed"]);
  const output = exportICS(document, { frame: result.frames[0], now: NOW });
  assert.match(output, /DTSTART:20260805T120000Z/);
  assert.match(output, /DTSTAMP:20260807T010000Z/);
  assert.match(output, /COMPLETED:20260806T230000Z/);
  assert.equal((output.match(/BEGIN:VTODO/g) || []).length, 1);
});

test("signed and large years round-trip through the adapter", () => {
  const document = createCelestialDocument();
  const ides = addEvent(document, {
    traits: ["event"],
    magnitudes: { duration: durationMagnitude("3600", "second") },
    payload: { title: "Ides of March" }
  });
  addRelation(document, {
    type: "attachment",
    event: ides.id,
    frame: "calendar:personal",
    role: "placed",
    coordinate: date(-44, 3, 15)
  });
  const far = addEvent(document, {
    traits: ["event"],
    magnitudes: { duration: durationMagnitude("0") },
    payload: { title: "Deep future" }
  });
  addRelation(document, {
    type: "attachment",
    event: far.id,
    frame: "calendar:personal",
    role: "placed",
    coordinate: date(100002026, 8, 6)
  });
  const output = exportICS(document, { frame: "calendar:personal", now: NOW });
  assert.match(output, /DTSTART:-00440315T000000/);
  assert.match(output, /DTSTART:1000020260806T000000/);
  const back = createCelestialDocument();
  importICS(output, back, { label: "Back" });
  const backIdes = Object.values(back.events).find((event) => event.payload.title === "Ides of March");
  const backRelation = Object.values(back.relations).find(
    (relation) => relation.event === backIdes.id && relation.role === "placed"
  );
  assert.equal(civilCoordinateToDays(backRelation.coordinate).toJSON(), String(daysFromCivil(-44n, 3n, 15n)));
  const backFar = Object.values(back.events).find((event) => event.payload.title === "Deep future");
  const farRelation = Object.values(back.relations).find(
    (relation) => relation.event === backFar.id && relation.role === "placed"
  );
  assert.equal(
    civilCoordinateToDays(farRelation.coordinate).toJSON(),
    String(daysFromCivil(100002026n, 8n, 6n))
  );
});

test("calendar-level subcomponents besides VTIMEZONE survive export", () => {
  const { document, result } = importCalendar([
    "BEGIN:VJOURNAL",
    "UID:journal@example.test",
    "SUMMARY:Journal entry",
    "END:VJOURNAL",
    "BEGIN:X-CUSTOM-COMP",
    "X-FIELD:keep",
    "END:X-CUSTOM-COMP",
    "BEGIN:VEVENT",
    "UID:plain@example.test",
    "DTSTART:20260806T090000Z",
    "SUMMARY:Plain",
    "END:VEVENT"
  ]);
  const output = exportICS(document, { frame: result.frames[0], now: NOW });
  assert.match(output, /BEGIN:VJOURNAL/);
  assert.match(output, /X-FIELD:keep/);
  assert.equal((output.match(/BEGIN:VEVENT/g) || []).length, 1);
  assert.doesNotThrow(() => parseICSTree(output));
});

test("quoted parameter values are stripped on import and re-quoted only when needed", () => {
  const { document, result } = importCalendar([
    "BEGIN:VEVENT",
    "UID:quoted@example.test",
    'DTSTART;TZID="Test/Zone":20260806T090000',
    'ATTENDEE;CN="Doe, John":mailto:john@example.test',
    "SUMMARY:Quoted",
    "END:VEVENT"
  ]);
  const event = Object.values(document.events).find((item) => item.payload.uid === "quoted@example.test");
  const relation = Object.values(document.relations).find((item) => item.event === event.id);
  assert.equal(relation.parameters.timeZone, "Test/Zone");
  const output = exportICS(document, { frame: result.frames[0], now: NOW });
  assert.match(output, /DTSTART;TZID=Test\/Zone:20260806T090000/);
  assert.match(output, /ATTENDEE;CN="Doe, John":mailto:john@example.test/);
  assert.doesNotThrow(() => parseICSTree(output));
});

test("date-only RECURRENCE-ID suppresses the matching timed occurrence", () => {
  const { document, result } = importCalendar([
    "BEGIN:VEVENT",
    "UID:move@example.test",
    "DTSTART:20260806T090000Z",
    "RRULE:FREQ=DAILY;COUNT=5",
    "SUMMARY:Series",
    "END:VEVENT",
    "BEGIN:VEVENT",
    "UID:move@example.test",
    "RECURRENCE-ID;VALUE=DATE:20260808",
    "DTSTART:20260808T150000Z",
    "SUMMARY:Moved occurrence",
    "END:VEVENT"
  ]);
  const engine = new ChronologEngine(document);
  const facts = engine.queryFacts({ frame: result.frames[0], start: date(2026, 8, 1), end: date(2026, 8, 12) });
  const virtual = facts.facts.filter(
    (fact) => fact.kind === "virtual" && fact.event.payload.uid === "move@example.test"
  );
  assert.equal(virtual.length, 4);
  assert.ok(facts.facts.some(
    (fact) => fact.kind === "explicit" && fact.event.payload.title === "Moved occurrence"
  ));
  assert.equal(result.warnings.length, 0);
});

test("UTC RECURRENCE-ID or EXDATE against a TZID DTSTART returns warnings", () => {
  const { result } = importCalendar([
    "BEGIN:VEVENT",
    "UID:tzmix@example.test",
    "DTSTART;TZID=Test/Zone:20260806T090000",
    "RRULE:FREQ=DAILY;COUNT=5",
    "EXDATE:20260808T130000Z",
    "SUMMARY:Series",
    "END:VEVENT",
    "BEGIN:VEVENT",
    "UID:tzmix@example.test",
    "RECURRENCE-ID:20260808T130000Z",
    "DTSTART;TZID=Test/Zone:20260808T150000",
    "SUMMARY:Moved",
    "END:VEVENT"
  ]);
  assert.ok(result.warnings.some((warning) => warning.includes("EXDATE")));
  assert.ok(result.warnings.some((warning) => warning.includes("RECURRENCE-ID")));
});

test("cross-zone DTEND keeps the wall-clock duration but warns", () => {
  const { document, result } = importCalendar([
    "BEGIN:VEVENT",
    "UID:cross@example.test",
    "DTSTART;TZID=Test/Zone:20260806T090000",
    "DTEND:20260806T100000Z",
    "SUMMARY:Cross",
    "END:VEVENT"
  ]);
  assert.ok(result.warnings.some((warning) => warning.includes("DTEND")));
  const event = Object.values(document.events).find((item) => item.payload.uid === "cross@example.test");
  assert.equal(event.magnitudes.duration.value.levels[0].value, "3600");
});

test("fresh events gain a deterministic DTSTAMP from the injected clock", () => {
  const document = createCelestialDocument();
  const event = addEvent(document, {
    traits: ["event"],
    magnitudes: { duration: durationMagnitude("0") },
    payload: { title: "Native" }
  });
  addRelation(document, {
    type: "attachment",
    event: event.id,
    frame: "calendar:personal",
    role: "placed",
    coordinate: date(2026, 8, 6)
  });
  const output = exportICS(document, { frame: "calendar:personal", now: NOW });
  assert.match(output, /DTSTAMP:20260807T120000Z/);
});

test("exports serialize RRULE from the edited dict while preserving key order", () => {
  const { document, result } = importCalendar([
    "BEGIN:VEVENT",
    "UID:edit@example.test",
    "DTSTART:20260806T090000Z",
    "RRULE:FREQ=MONTHLY;BYMONTHDAY=15;COUNT=2",
    "SUMMARY:Editable",
    "END:VEVENT"
  ]);
  const untouched = exportICS(document, { frame: result.frames[0], now: NOW });
  assert.match(untouched, /RRULE:FREQ=MONTHLY;BYMONTHDAY=15;COUNT=2/);
  document.patterns[result.patterns[0]].rrule.COUNT = "5";
  const edited = exportICS(document, { frame: result.frames[0], now: NOW });
  assert.match(edited, /RRULE:FREQ=MONTHLY;BYMONTHDAY=15;COUNT=5/);
});

test("content lines without a colon round-trip verbatim", () => {
  const { document, result } = importCalendar([
    "X-CALENDAR-MALFORMED-MARKER",
    "BEGIN:VEVENT",
    "UID:broken@example.test",
    "DTSTART:20260806T090000Z",
    "SUMMARY:Broken line",
    "X-EVENT-MALFORMED-MARKER",
    "END:VEVENT"
  ]);
  const output = exportICS(document, { frame: result.frames[0], now: NOW });
  assert.ok(output.includes("\r\nX-CALENDAR-MALFORMED-MARKER\r\n"));
  assert.ok(output.includes("\r\nX-EVENT-MALFORMED-MARKER\r\n"));
  assert.ok(!output.includes("X-CALENDAR-MALFORMED-MARKER:"));
  assert.ok(!output.includes("X-EVENT-MALFORMED-MARKER:"));
});
