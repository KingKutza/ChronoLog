import assert from "node:assert/strict";
import test from "node:test";
import { ChronologEngine } from "../src/engine.js";
import { coordinate, formatCivil } from "../src/exact.js";
import { exportICS, importICS } from "../src/ics.js";
import {
  applyRecurrenceEnd,
  normalizeRecurrenceCount,
  recurrenceEndMode,
  recurrenceUntilDate,
  recurrenceUntilForCoordinate,
  recurrenceUntilForDate,
  truncateRecurrenceAt
} from "../src/recurrence-end.js";
import { createStructuralDocument } from "./helpers/sample-document.js";

const UID = "rule@example.test";

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

function series(rrule, dtstart = "20260105T090000Z") {
  const source = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Test//EN",
    "BEGIN:VEVENT",
    `UID:${UID}`,
    `DTSTART:${dtstart}`,
    `RRULE:${rrule}`,
    "SUMMARY:Rule",
    "END:VEVENT",
    "END:VCALENDAR",
    ""
  ].join("\r\n");
  const document = createStructuralDocument();
  const result = importICS(source, document, { label: "Rules" });
  return { document, frame: result.frames[0] };
}

function occurrences({ document, frame }) {
  return new ChronologEngine(document)
    .queryFacts({ frame, start: date(2026), end: date(2028) })
    .facts
    .filter((fact) => fact.kind === "virtual" && fact.event.payload.uid === UID)
    .map((fact) => formatCivil(fact.coordinate));
}

function rulePattern(document) {
  return Object.values(document.patterns).find((pattern) => pattern.kind === "ics-rrule");
}

test("a rule reports how it ends", () => {
  assert.equal(recurrenceEndMode({ FREQ: "WEEKLY" }), "never");
  assert.equal(recurrenceEndMode({ FREQ: "WEEKLY", COUNT: "8" }), "count");
  assert.equal(recurrenceEndMode({ FREQ: "WEEKLY", UNTIL: "20261231" }), "until");
  assert.equal(recurrenceEndMode({}), "never");
  assert.equal(recurrenceEndMode(), "never");
  // A blank COUNT is not an end condition.
  assert.equal(recurrenceEndMode({ COUNT: "" }), "never");
});

test("COUNT and UNTIL are mutually exclusive, whichever way the mode changes", () => {
  const counted = applyRecurrenceEnd({ FREQ: "WEEKLY", UNTIL: "20261231" }, { mode: "count", count: "6" });
  assert.deepEqual(counted, { FREQ: "WEEKLY", COUNT: "6" });

  const dated = applyRecurrenceEnd({ FREQ: "WEEKLY", COUNT: "6" }, { mode: "until", until: "2026-12-31" });
  assert.deepEqual(dated, { FREQ: "WEEKLY", UNTIL: "20261231T235959" });

  const never = applyRecurrenceEnd({ FREQ: "WEEKLY", COUNT: "6" }, { mode: "never" });
  assert.deepEqual(never, { FREQ: "WEEKLY" });

  // Other rule parts are preserved untouched.
  const kept = applyRecurrenceEnd({ FREQ: "WEEKLY", BYDAY: "MO,WE", INTERVAL: "2" }, { mode: "count", count: "3" });
  assert.deepEqual(kept, { FREQ: "WEEKLY", BYDAY: "MO,WE", INTERVAL: "2", COUNT: "3" });
});

test("an unusable end value falls back to never rather than inventing one", () => {
  assert.deepEqual(applyRecurrenceEnd({ FREQ: "DAILY" }, { mode: "until", until: "" }), { FREQ: "DAILY" });
  assert.deepEqual(applyRecurrenceEnd({ FREQ: "DAILY" }, { mode: "until", until: "not a date" }), { FREQ: "DAILY" });
  assert.deepEqual(applyRecurrenceEnd({ FREQ: "DAILY" }, { mode: "nonsense" }), { FREQ: "DAILY" });
  // An already-compact value passes through instead of being re-derived.
  assert.deepEqual(
    applyRecurrenceEnd({ FREQ: "DAILY" }, { mode: "until", until: "20270115T120000" }),
    { FREQ: "DAILY", UNTIL: "20270115T120000" }
  );
});

test("counts are clamped into the range the engine will accept", () => {
  assert.equal(normalizeRecurrenceCount("6"), 6);
  assert.equal(normalizeRecurrenceCount(0), 1);
  assert.equal(normalizeRecurrenceCount(-4), 1);
  assert.equal(normalizeRecurrenceCount(99999), 10000);
  assert.equal(normalizeRecurrenceCount(""), 1);
  assert.equal(normalizeRecurrenceCount("3.7"), 3);
});

test("an UNTIL date round-trips back into a date input", () => {
  assert.equal(recurrenceUntilDate("20261231T235959"), "2026-12-31");
  assert.equal(recurrenceUntilDate("20261231"), "2026-12-31");
  assert.equal(recurrenceUntilDate(""), "");
  assert.equal(recurrenceUntilDate(undefined), "");
  assert.equal(recurrenceUntilDate(recurrenceUntilForDate("2027-03-09")), "2027-03-09");
});

test("'ends on a date' covers the whole of that day, whatever time the series runs at", () => {
  // A midnight UNTIL would drop a 09:00 series' final occurrence. This is the
  // off-by-one a user reads as a bug, so the value is the day's last second.
  assert.equal(recurrenceUntilForDate("2026-12-31"), "20261231T235959");
  assert.equal(recurrenceUntilForDate("2026-1-5"), "20260105T235959");
  assert.equal(recurrenceUntilForDate("bad"), "");
});

// There is no longer a button that does this — ending a series will arrive as an
// end-staple on the series body, not an imperative command. The arithmetic stays
// because the "Ends on a date" control uses it and the staple model will too.
test("an inclusive UNTIL cap lands exactly on the occurrence it names", () => {
  // A timed occurrence needs its own instant, or an inclusive cap is impossible.
  assert.deepEqual(
    truncateRecurrenceAt({ FREQ: "WEEKLY", COUNT: "40" }, civil(2026, 10, 5, 9, 30)),
    { FREQ: "WEEKLY", UNTIL: "20261005T093000" }
  );
  // A date-only occurrence keeps the plain date form, matching its own value type.
  assert.deepEqual(
    truncateRecurrenceAt({ FREQ: "DAILY" }, civil(2026, 10, 5)),
    { FREQ: "DAILY", UNTIL: "20261005" }
  );
  assert.equal(recurrenceUntilForCoordinate(civil(2026, 1, 2, 0, 0, 7)), "20260102T000007");
});

// The point of an inclusive cap is that the occurrence in hand survives and the
// next one does not. That is a claim about the engine, so it is asserted against
// the engine rather than against the string.
test("an inclusive cap keeps the occurrence it names and drops every later one", () => {
  const context = series("FREQ=WEEKLY;COUNT=8");
  assert.equal(occurrences(context).length, 8);

  const pattern = rulePattern(context.document);
  pattern.rrule = truncateRecurrenceAt(pattern.rrule, civil(2026, 1, 19, 9, 0));
  assert.deepEqual(occurrences(context), ["2026-01-05", "2026-01-12", "2026-01-19"]);
  assert.equal(pattern.rrule.COUNT, undefined, "the old COUNT cannot survive alongside UNTIL");
});

test("'ends on a date' keeps occurrences on that date even though they run at 09:00", () => {
  const context = series(`FREQ=WEEKLY;UNTIL=${recurrenceUntilForDate("2026-01-19")}`);
  assert.deepEqual(occurrences(context), ["2026-01-05", "2026-01-12", "2026-01-19"]);
});

// This is the bug `recurrenceUntilForDate` exists to avoid: a midnight UNTIL on
// the date the user picked silently loses that date's own occurrence.
test("a midnight UNTIL on the chosen date would have dropped it", () => {
  const context = series("FREQ=WEEKLY;UNTIL=20260119");
  assert.deepEqual(occurrences(context), ["2026-01-05", "2026-01-12"]);
});

// A rule change that the engine honours but ICS export drops would be worse than
// no feature at all, because it would look right until the file left the app.
test("an UNTIL written by the editor survives an ICS export and re-import", () => {
  const { document, frame } = series("FREQ=WEEKLY;COUNT=8");
  const pattern = rulePattern(document);
  const rrule = applyRecurrenceEnd(pattern.rrule, { mode: "until", until: "2026-02-02" });
  pattern.rrule = rrule;
  pattern.rawRule = {
    ...pattern.rawRule,
    value: Object.entries(rrule).map(([key, value]) => `${key}=${value}`).join(";")
  };
  delete pattern.rawRule.raw;
  delete pattern.rawRule.verbatim;

  const text = String(exportICS(document, { frame }));
  assert.match(text, /RRULE:FREQ=WEEKLY;UNTIL=20260202T235959/);

  const reloaded = createStructuralDocument();
  importICS(text, reloaded, { label: "Round trip" });
  const reloadedRule = rulePattern(reloaded).rrule;
  assert.equal(reloadedRule.UNTIL, "20260202T235959");
  assert.equal(reloadedRule.COUNT, undefined);
});

test("switching a live series from COUNT to a date changes what the engine emits", () => {
  const context = series("FREQ=WEEKLY;COUNT=8");
  const pattern = rulePattern(context.document);
  pattern.rrule = applyRecurrenceEnd(pattern.rrule, { mode: "until", until: "2026-02-02" });
  assert.deepEqual(occurrences(context), ["2026-01-05", "2026-01-12", "2026-01-19", "2026-01-26", "2026-02-02"]);

  pattern.rrule = applyRecurrenceEnd(pattern.rrule, { mode: "count", count: "2" });
  assert.deepEqual(occurrences(context), ["2026-01-05", "2026-01-12"]);

  pattern.rrule = applyRecurrenceEnd(pattern.rrule, { mode: "never" });
  assert.ok(occurrences(context).length > 8, "an unbounded series runs past the old count");
});
