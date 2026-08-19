import assert from "node:assert/strict";
import test from "node:test";
import { ChronologEngine, seriesEffectiveUntilDays } from "../src/engine.js";
import { Rational, coordinate, daysFromCivil, formatCivil } from "../src/exact.js";
import { importICS } from "../src/ics.js";
import {
  CommandHistory,
  clearSeriesEndStaple,
  seriesEndStaple,
  setSeriesEndStaple,
  validateDocument
} from "../src/model.js";
import { createTransactions } from "../src/ui/transactions.js";
import { createStructuralDocument } from "./helpers/sample-document.js";

// LEXICON.md's staple anchoring / Rob-and-John scenario: "the goal is to be
// able to staple a series at the beginning, the end, or any other arbitrary
// point ... ending a series is an end-staple, not a command". This file
// exercises exactly the end-staple slice of that (ROADMAP #4's first stage):
// a series' own rule extent (COUNT/UNTIL) is untouched data; the staple is a
// separate authored record; the projection is their intersection; removing
// the staple restores the projection for free. Start/midpoint/other-named
// anchors, staple-derived magnitudes, fuzzy staples, and constraint bounds
// are later stages of the same roadmap item and are not built here.
//
// The series comes from real ICS import, as the sibling series-* test files
// already do, so every record carries exactly the fields the app gives it --
// which matters most here, because the risk this mechanism can most easily
// have is comparing two representations of the same instant and calling them
// different (ICS writes month "01"; the generator writes "1").

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

function occurrences(document, frame, { start = date(2026), end = date(2026, "3", "1") } = {}) {
  return new ChronologEngine(document)
    .queryFacts({ frame: frame.id, start, end, limit: 200 })
    .facts.filter((fact) => fact.kind === "virtual")
    .map((fact) => formatCivil(fact.coordinate, true));
}

function transactionsFor(document) {
  const changes = [];
  const app = { chronolog: document, changes };
  app.history = new CommandHistory(document, (change) => changes.push(change));
  Object.assign(app, createTransactions(app));
  return app;
}

test("an end-staple stops the projection at its exact coordinate; occurrences before it survive", () => {
  const { document, frame, pattern } = weeklySeries();
  const before = occurrences(document, frame);
  assert.deepEqual(before.slice(0, 4), [
    "2026-01-05 09:00:00", "2026-01-12 09:00:00", "2026-01-19 09:00:00", "2026-01-26 09:00:00"
  ]);

  setSeriesEndStaple(document, pattern.id, frame.id, civil(2026, 1, 19, 9, 0, 0));
  assert.deepEqual(occurrences(document, frame), [
    "2026-01-05 09:00:00", "2026-01-12 09:00:00", "2026-01-19 09:00:00"
  ], "the staple's own occurrence survives; nothing after it projects");
  assert.equal(validateDocument(document).valid, true);
});

test("removing the staple resumes the full projection", () => {
  const { document, frame, pattern } = weeklySeries();
  const before = occurrences(document, frame);

  setSeriesEndStaple(document, pattern.id, frame.id, civil(2026, 1, 19, 9, 0, 0));
  assert.notDeepEqual(occurrences(document, frame), before, "the staple really cut the projection");

  clearSeriesEndStaple(document, pattern.id);
  assert.deepEqual(occurrences(document, frame), before, "the full projection is back, unconditionally");
});

test("the effective stop is the earlier of the rule's own UNTIL and an end-staple", () => {
  // The rule's own extent (2026-01-12) is earlier than the staple (01-19): the
  // rule wins, exactly as it would with no staple at all.
  const early = weeklySeries({ until: "20260112T235959" });
  setSeriesEndStaple(early.document, early.pattern.id, early.frame.id, civil(2026, 1, 19, 9, 0, 0));
  assert.deepEqual(occurrences(early.document, early.frame), [
    "2026-01-05 09:00:00", "2026-01-12 09:00:00"
  ], "the rule's own, earlier UNTIL is still honoured");

  // The rule's own extent runs well past the staple: the staple is now the
  // binding constraint.
  const late = weeklySeries({ until: "20260301T000000" });
  setSeriesEndStaple(late.document, late.pattern.id, late.frame.id, civil(2026, 1, 19, 9, 0, 0));
  assert.deepEqual(occurrences(late.document, late.frame), [
    "2026-01-05 09:00:00", "2026-01-12 09:00:00", "2026-01-19 09:00:00"
  ], "the earlier of the two -- the staple -- wins");
});

// The named risk: "ICS writes month '01' where the generator writes '1'". A
// string comparison between the rule's own (zero-padded) UNTIL and a staple
// coordinate authored by hand (bare digits, as the editor's own date/time
// inputs naturally produce) would silently disagree about whether they name
// the same instant.
test("comparing a staple against an ICS-derived UNTIL is exact-numeric, not textual", () => {
  const { document, frame, pattern } = weeklySeries({ until: "20260119T090000" });
  const engine = new ChronologEngine(document);
  setSeriesEndStaple(document, pattern.id, frame.id, coordinate([
    { level: "year", value: "2026" },
    { level: "month", value: "1" },
    { level: "day", value: "19" },
    { level: "hour", value: "9" },
    { level: "minute", value: "0" },
    { level: "second", value: "0" }
  ]));
  const untilDays = seriesEffectiveUntilDays(engine, pattern);
  const expected = new Rational(daysFromCivil(2026n, 1n, 19n)).add(Rational.parse(9).div(24));
  assert.equal(
    untilDays.compare(expected), 0,
    "the zero-padded ICS UNTIL and the bare-digit staple resolve to the exact same instant"
  );
  // A string-comparison bug would either exclude this boundary occurrence or
  // pick the wrong one of the two arbitrarily; exact comparison keeps it.
  assert.deepEqual(occurrences(document, frame), [
    "2026-01-05 09:00:00", "2026-01-12 09:00:00", "2026-01-19 09:00:00"
  ]);
});

test("a staple journals as a record-level op and undoes/redoes as one change", () => {
  const { document, frame, pattern } = weeklySeries();
  const app = transactionsFor(document);

  app.changes.length = 0;
  app.executePatternChange("Place end staple", pattern.id, (documentValue) => {
    setSeriesEndStaple(documentValue, pattern.id, frame.id, civil(2026, 1, 19, 9, 0, 0));
  });
  const staple = seriesEndStaple(document, pattern.id);
  assert.ok(staple, "the staple exists");
  assert.equal(app.changes.length, 1, "one journalled change");
  // `capturePatternBundle` always re-clones the pattern record on both sides
  // of the diff (so the bundle stays valid whether or not this particular
  // edit touched it), and an identity-based diff (`opsFromMaps`) therefore
  // always re-puts it alongside whatever else changed -- that redundant put
  // is pre-existing bundle behaviour, not something the staple introduces.
  // What matters here is that the staple's own put rides along as an
  // ordinary record-level relation op.
  const puts = app.changes[0].ops.filter((op) => op.op === "put" && op.map !== "meta");
  assert.ok(
    puts.some((op) => op.map === "relations" && op.id === staple.id),
    "the staple journals as a record-level put, like any other relation"
  );
  assert.equal(validateDocument(document).valid, true);

  app.history.undo();
  assert.equal(seriesEndStaple(document, pattern.id), null, "undo removes the staple");
  app.history.redo();
  assert.ok(seriesEndStaple(document, pattern.id), "redo restores it");

  app.changes.length = 0;
  app.executePatternChange("Remove end staple", pattern.id, (documentValue) => {
    clearSeriesEndStaple(documentValue, pattern.id);
  });
  assert.equal(seriesEndStaple(document, pattern.id), null, "removal took effect");
  const deletes = app.changes[0].ops.filter((op) => op.op === "del" && op.map !== "meta");
  assert.ok(
    deletes.some((op) => op.map === "relations" && op.id === staple.id),
    "removing the staple journals as a record-level delete"
  );

  app.history.undo();
  assert.ok(seriesEndStaple(document, pattern.id), "undo restores a removed staple");
});

// AGENTS.md's persistence contract: "deleting a pattern must delete its
// overrides ... in the same undoable transaction" -- a staple belongs to its
// series the same way, so it travels with pattern deletion through the same
// bundle helpers (src/ui/transactions.js), not a second mechanism.
test("deleting a pattern deletes its end-staple in the same undoable transaction, and undo restores both together", () => {
  const { document, frame, pattern } = weeklySeries();
  const app = transactionsFor(document);
  app.executePatternChange("Place end staple", pattern.id, (documentValue) => {
    setSeriesEndStaple(documentValue, pattern.id, frame.id, civil(2026, 1, 19, 9, 0, 0));
  });
  const staple = seriesEndStaple(document, pattern.id);
  assert.ok(staple);

  app.executePatternChange("Delete pattern", pattern.id, (documentValue) => {
    delete documentValue.patterns[pattern.id];
  });
  assert.equal(document.patterns[pattern.id], undefined, "the pattern is gone");
  assert.equal(document.relations[staple.id], undefined, "its staple went with it, not left as a dangling pointer");
  assert.equal(validateDocument(document).valid, true);

  app.history.undo();
  assert.ok(document.patterns[pattern.id], "the pattern comes back");
  assert.ok(document.relations[staple.id], "and its staple comes back with it, in the same undo step");
  assert.equal(validateDocument(document).valid, true);

  app.history.redo();
  assert.equal(document.patterns[pattern.id], undefined);
  assert.equal(document.relations[staple.id], undefined, "redo removes both again");
});
