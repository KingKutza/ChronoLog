import test from "node:test";
import assert from "node:assert/strict";
import { createStructuralDocument } from "./helpers/sample-document.js";
import { ChronologEngine } from "../src/engine.js";
import { coordinate } from "../src/exact.js";
import { exportICS, importICS, parseICSTree } from "../src/ics.js";
import { stapleEvents, validateDocument } from "../src/model.js";

const source = [
  "BEGIN:VCALENDAR",
  "VERSION:2.0",
  "PRODID:-//Test//EN",
  "X-UNUSUAL-CALENDAR:keep",
  "BEGIN:VTIMEZONE",
  "TZID:Test/Zone",
  "X-TZ-DETAIL:keep",
  "END:VTIMEZONE",
  "BEGIN:VEVENT",
  "UID:recurring@example.test",
  "DTSTART;TZID=Test/Zone:20260806T090000",
  "DTEND;TZID=Test/Zone:20260806T100000",
  "RRULE:FREQ=DAILY;COUNT=3",
  "SUMMARY:Daily\\, Test",
  "ATTENDEE;CN=Somebody:mailto:somebody@example.test",
  "BEGIN:VALARM",
  "ACTION:DISPLAY",
  "TRIGGER:-PT15M",
  "DESCRIPTION:Reminder",
  "END:VALARM",
  "X-UNKNOWN-EVENT:keep",
  "END:VEVENT",
  "BEGIN:VTODO",
  "UID:task@example.test",
  "SUMMARY:Retrospective task",
  "DTSTAMP:20260807T010000Z",
  "COMPLETED:20260806T230000Z",
  "END:VTODO",
  "END:VCALENDAR",
  ""
].join("\r\n");

function date(day) {
  return coordinate([
    { level: "year", value: "2026" },
    { level: "month", value: "8" },
    { level: "day", value: String(day) }
  ]);
}

test("ICS import keeps recurrence structural and task times distinct", () => {
  const document = createStructuralDocument();
  const result = importICS(source, document, { label: "Test" });
  const validation = validateDocument(document);
  assert.equal(validation.valid, true, validation.errors.join("\n"));
  assert.equal(result.events.length, 2);
  assert.equal(result.patterns.length, 1);
  const sourceId = document.frames[result.frames[0]].codec.source;
  const storedCalendar = document.foreign.ics.sources[sourceId].component;
  assert.equal(storedCalendar.components.some(
    (component) => ["VEVENT", "VTODO"].includes(component.name)
  ), false);
  assert.ok(result.events.every(
    (eventId) => ["VEVENT", "VTODO"].includes(document.events[eventId].foreign.ics.component.name)
  ));
  const task = Object.values(document.events).find((event) => event.traits.includes("task"));
  const roles = Object.values(document.relations)
    .filter((relation) => relation.event === task.id)
    .map((relation) => relation.role)
    .sort();
  assert.deepEqual(roles, ["completed", "observed"]);

  const engine = new ChronologEngine(document);
  const facts = engine.queryFacts({
    frame: result.frames[0],
    start: date(1),
    end: date(12)
  });
  const recurring = facts.facts.filter((fact) => fact.event.payload.uid === "recurring@example.test");
  assert.equal(recurring.length, 3);
});

test("ICS export preserves unknown data, timezone, alarm, attendee, and RRULE", () => {
  const document = createStructuralDocument();
  const result = importICS(source, document, { label: "Test" });
  const engine = new ChronologEngine(document);
  const output = exportICS(document, {
    frame: result.frames[0],
    start: date(1),
    end: date(12),
    engine
  });
  assert.match(output, /ATTENDEE;CN=Somebody:mailto:somebody@example\.test/);
  assert.match(output, /X-UNKNOWN-EVENT:keep/);
  assert.match(output, /X-TZ-DETAIL:keep/);
  assert.match(output, /BEGIN:VALARM/);
  assert.match(output, /RRULE:FREQ=DAILY;COUNT=3/);
  assert.equal((output.match(/BEGIN:VTODO/g) || []).length, 1);
  assert.match(output, /DTSTAMP:20260807T010000Z/);
  assert.match(output, /COMPLETED:20260806T230000Z/);
  assert.doesNotThrow(() => parseICSTree(output));
});

test("matching UIDs across imports only produce staple suggestions", () => {
  const document = createStructuralDocument();
  const first = importICS(source, document, { label: "First" });
  const second = importICS(source, document, { label: "Second" });
  assert.ok(second.suggestions.some((item) => item.uid === "recurring@example.test"));
  assert.notEqual(first.frames[0], second.frames[0]);
  const matching = Object.values(document.events).filter(
    (event) => event.payload?.uid === "recurring@example.test"
  );
  assert.equal(matching.length, 2);
  assert.notEqual(matching[0].id, matching[1].id);
  const canonical = stapleEvents(document, matching.map((event) => event.id));
  assert.equal(
    Object.values(document.events).filter(
      (event) => event.payload?.uid === "recurring@example.test"
    ).length,
    1
  );
  assert.ok(Object.values(document.relations).some((relation) => relation.event === canonical.id));
});
