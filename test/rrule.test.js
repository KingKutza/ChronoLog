import test from "node:test";
import assert from "node:assert/strict";
import { createStructuralDocument } from "./helpers/sample-document.js";
import { ChronologEngine } from "../src/engine.js";
import { coordinate, formatCivil } from "../src/exact.js";
import { importICS } from "../src/ics.js";

function date(year, month = "1", day = "1") {
  return coordinate([
    { level: "year", value: String(year) },
    { level: "month", value: String(month) },
    { level: "day", value: String(day) }
  ]);
}

function query(rrule, dtstart, { start = date(2026), end = date(2028) } = {}) {
  const source = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Test//EN",
    "BEGIN:VEVENT",
    "UID:rule@example.test",
    `DTSTART:${dtstart}`,
    `RRULE:${rrule}`,
    "SUMMARY:Rule",
    "END:VEVENT",
    "END:VCALENDAR",
    ""
  ].join("\r\n");
  const document = createStructuralDocument();
  const result = importICS(source, document, { label: "Rules" });
  const engine = new ChronologEngine(document);
  const output = engine.queryFacts({ frame: result.frames[0], start, end });
  const dates = output.facts
    .filter((fact) => fact.kind === "virtual" && fact.event.payload.uid === "rule@example.test")
    .map((fact) => formatCivil(fact.coordinate));
  return { output, dates, document, result };
}

test("WEEKLY honors COUNT", () => {
  const { dates } = query("FREQ=WEEKLY;COUNT=8", "20260105T090000Z");
  assert.equal(dates.length, 8);
  assert.equal(dates[0], "2026-01-05");
  assert.equal(dates.at(-1), "2026-02-23");
});

test("WEEKLY respects INTERVAL together with COUNT", () => {
  const { dates } = query("FREQ=WEEKLY;INTERVAL=2;COUNT=3", "20260105T090000Z");
  assert.deepEqual(dates, ["2026-01-05", "2026-01-19", "2026-02-02"]);
});

test("WEEKLY expands multiple BYDAY values with correct COUNT indexing", () => {
  const { dates } = query("FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=5", "20260105T090000Z");
  assert.deepEqual(dates, ["2026-01-05", "2026-01-07", "2026-01-09", "2026-01-12", "2026-01-14"]);
});

test("MONTHLY COUNT counts emitted occurrences, not cycles", () => {
  const { dates } = query("FREQ=MONTHLY;BYMONTHDAY=1,15;COUNT=4", "20260101T090000Z");
  assert.deepEqual(dates, ["2026-01-01", "2026-01-15", "2026-02-01", "2026-02-15"]);
  const long = query("FREQ=MONTHLY;BYMONTHDAY=31;COUNT=12", "20260131T090000Z");
  assert.equal(long.dates.length, 12);
  assert.equal(long.dates.at(-1), "2027-08-31");
});

test("COUNT applies from DTSTART even when the window starts later", () => {
  const { dates } = query("FREQ=DAILY;COUNT=5", "20260101T090000Z", {
    start: date(2026, 2, 1),
    end: date(2026, 3, 1)
  });
  assert.equal(dates.length, 0);
});

test("non-positive INTERVAL is rejected instead of looping", () => {
  for (const interval of ["0", "-1"]) {
    const { output, dates } = query(`FREQ=DAILY;INTERVAL=${interval};COUNT=5`, "20260101T090000Z");
    assert.equal(dates.length, 0);
    assert.ok(output.errors.some((error) => /INTERVAL/.test(error.message)));
  }
});

test("pathological COUNT values are rejected before they can lock the UI", () => {
  const { output, dates } = query("FREQ=DAILY;COUNT=999999999999", "20260101T090000Z");
  assert.equal(dates.length, 0);
  assert.ok(output.errors.some((error) => /safe limit/.test(error.message)));
});

test("windowed queries without COUNT fast-forward while keeping INTERVAL alignment", () => {
  const { dates } = query("FREQ=WEEKLY;INTERVAL=2", "20260105T090000Z", {
    start: date(2026, 2, 1),
    end: date(2026, 3, 1)
  });
  assert.deepEqual(dates, ["2026-02-02", "2026-02-16"]);
});

test("MONTHLY BYDAY supports ordinal and negative weekdays", () => {
  const second = query("FREQ=MONTHLY;BYDAY=2TU;COUNT=3", "20260113T090000Z");
  assert.deepEqual(second.dates, ["2026-01-13", "2026-02-10", "2026-03-10"]);
  const last = query("FREQ=MONTHLY;BYDAY=-1FR;COUNT=2", "20260130T090000Z");
  assert.deepEqual(last.dates, ["2026-01-30", "2026-02-27"]);
});

test("MONTHLY plain BYDAY matches every such weekday", () => {
  const { dates } = query("FREQ=MONTHLY;BYDAY=TU;COUNT=5", "20260106T090000Z");
  assert.deepEqual(dates, ["2026-01-06", "2026-01-13", "2026-01-20", "2026-01-27", "2026-02-03"]);
});

test("YEARLY expands multiple BYMONTH and BYMONTHDAY values", () => {
  const { dates } = query("FREQ=YEARLY;BYMONTH=3,9;BYMONTHDAY=1,15;COUNT=6", "20260301T090000Z");
  assert.deepEqual(dates, [
    "2026-03-01", "2026-03-15", "2026-09-01", "2026-09-15", "2027-03-01", "2027-03-15"
  ]);
});

test("unsupported FREQ values raise clear errors", () => {
  for (const freq of ["HOURLY", "MINUTELY", "SECONDLY", "BOGUS"]) {
    const { output, dates } = query(`FREQ=${freq};COUNT=3`, "20260101T090000Z");
    assert.equal(dates.length, 0);
    assert.ok(output.errors.some((error) => /Unsupported FREQ/.test(error.message)));
  }
});

// RFC 7529: RSCALE names the calendar a rule counts in. It is one more key
// inside the RRULE value text (`parseRRule` already splits it generically),
// so a rule naming the registered `gregory` scale resolves exactly as if
// RSCALE were absent, while a rule naming a calendar this build has not
// registered must be refused honestly -- never silently projected as though
// it counted in Gregorian.
test("RSCALE naming the registered Gregorian scale resolves exactly as FREQ alone", () => {
  const plain = query("FREQ=WEEKLY;COUNT=3", "20260105T090000Z");
  const scaled = query("RSCALE=GREGORIAN;FREQ=WEEKLY;COUNT=3", "20260105T090000Z");
  assert.deepEqual(scaled.dates, plain.dates);
  assert.deepEqual(scaled.dates, ["2026-01-05", "2026-01-12", "2026-01-19"]);
  const upperCase = query("RSCALE=GREGORY;FREQ=WEEKLY;COUNT=3", "20260105T090000Z");
  assert.deepEqual(upperCase.dates, plain.dates);
});

test("RSCALE naming an unregistered calendar preserves the rule and refuses projection", () => {
  const { dates, output, document, result } = query("RSCALE=HEBREW;FREQ=YEARLY;COUNT=3", "20260101T090000Z");
  assert.equal(dates.length, 0);
  assert.ok(output.errors.some((error) => /RSCALE=HEBREW/.test(error.message)));
  assert.ok(output.errors.some((error) => /cannot be projected/.test(error.message)));
  const pattern = Object.values(document.patterns).find((item) => item.id === result.patterns[0]);
  assert.equal(pattern.rrule.RSCALE, "HEBREW");
  assert.equal(pattern.rawRule.value, "RSCALE=HEBREW;FREQ=YEARLY;COUNT=3");
});
