import test from "node:test";
import assert from "node:assert/strict";
import { createCelestialDocument } from "../src/celestial.js";
import { ChronologEngine } from "../src/engine.js";
import { daysFromCivil, daysToCivilCoordinate, Rational } from "../src/exact.js";
import { importICS } from "../src/ics.js";

function calendar(count, recurring = false) {
  const lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "X-WR-CALNAME:Performance"];
  for (let index = 0; index < count; index += 1) {
    const day = String(index % 28 + 1).padStart(2, "0");
    lines.push(
      "BEGIN:VEVENT",
      `UID:performance-${index}`,
      `DTSTART:202608${day}T090000`,
      `DTEND:202608${day}T100000`,
      `SUMMARY:Event ${index}`
    );
    if (recurring === true) lines.push("RRULE:FREQ=DAILY;COUNT=30");
    else if (recurring === "open") lines.push("RRULE:FREQ=DAILY");
    lines.push("END:VEVENT");
  }
  lines.push("END:VCALENDAR");
  return lines.join("\r\n");
}

function date(year, month, day) {
  return daysToCivilCoordinate(new Rational(daysFromCivil(BigInt(year), BigInt(month), BigInt(day))));
}

test("fact queries use frame and event indexes and honor a UI result bound", () => {
  const document = createCelestialDocument();
  const imported = importICS(calendar(1000), document);
  const engine = new ChronologEngine(document);
  const frame = imported.frames[0];
  assert.equal(engine.relationsByFrame.get(frame).length, 1000);
  assert.equal(engine.eventGroupFrame(imported.events[0]), null);
  const result = engine.queryFacts({
    frame,
    start: date(2026, 8, 1),
    end: date(2026, 9, 1),
    limit: 75
  });
  assert.equal(result.facts.length, 75);
  assert.equal(result.truncated, true);
  assert.equal(engine.explicitFactsByFrame.get(frame).length, 1000);
});

test("dense recurrence expansion stops at the render limit", () => {
  const document = createCelestialDocument();
  const imported = importICS(calendar(80, true), document);
  const engine = new ChronologEngine(document);
  const result = engine.queryFacts({
    frame: imported.frames[0],
    start: date(2026, 8, 1),
    end: date(2026, 9, 1),
    limit: 120
  });
  assert.equal(result.facts.length, 120);
  assert.equal(result.truncated, true);
});

test("open-ended recurrence windows are cached for adjacent UI queries", () => {
  const document = createCelestialDocument();
  const imported = importICS(calendar(20, "open"), document);
  const engine = new ChronologEngine(document);
  engine.queryFacts({
    frame: imported.frames[0],
    start: date(2026, 8, 1),
    end: date(2026, 8, 21),
    limit: 100
  });
  const cachedBefore = engine.recurrenceWindows.size;
  assert.ok(cachedBefore > 0);
  engine.queryFacts({
    frame: imported.frames[0],
    start: date(2026, 8, 2),
    end: date(2026, 8, 22),
    limit: 100
  });
  const cachedAfter = engine.recurrenceWindows.size;
  assert.equal(cachedAfter, cachedBefore);
});

test("lightweight explicit edits can rebuild indexes without discarding recurrence caches", () => {
  const document = createCelestialDocument();
  const imported = importICS(calendar(20, "open"), document);
  const engine = new ChronologEngine(document);
  engine.queryFacts({
    frame: imported.frames[0],
    start: date(2026, 8, 1),
    end: date(2026, 8, 21),
    limit: 100
  });
  const cache = engine.recurrenceWindows;
  const cachedFacts = engine.recurrenceWindowFacts;
  engine.setDocument(document, { preserveRecurrence: true });
  assert.equal(engine.recurrenceWindows, cache);
  assert.equal(engine.recurrenceWindowFacts, cachedFacts);
  assert.equal(engine.explicitFactsByFrame.size, 0);
});

test("sustained navigation keeps generated recurrence caches within hard bounds", () => {
  const document = createCelestialDocument();
  const imported = importICS(calendar(200, "open"), document);
  const engine = new ChronologEngine(document);
  for (let offset = 0; offset < 180 * 31; offset += 31) {
    engine.queryFacts({
      frame: imported.frames[0],
      start: date(2026, 8, 1 + offset),
      end: date(2026, 8, 43 + offset),
      limit: 600
    });
  }
  assert.ok(engine.recurrenceWindows.size <= 256);
  assert.ok(engine.recurrenceWindowFacts <= 16_000);
});
