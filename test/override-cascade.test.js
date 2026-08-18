import assert from "node:assert/strict";
import test from "node:test";
import {
  CommandHistory,
  addEvent,
  overridePatternId,
  removeOverridesForPatterns,
  stableVirtualId,
  validateDocument,
  virtualPatternId
} from "../src/model.js";
import { importICS } from "../src/ics.js";
import { compactDocument, parseDocument } from "../src/store.js";
import { createTransactions } from "../src/ui/transactions.js";
import { createStructuralDocument } from "./helpers/sample-document.js";

// A document with one imported repeating series, a hand-authored suppression of
// one occurrence, and a replacement override — the shape the owner's real
// document was in when deleting a series orphaned six of these. The series comes
// from real ICS import rather than being hand-built, so every record carries
// exactly the fields the app gives it.
function documentWithSeries() {
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
    "END:VEVENT",
    "END:VCALENDAR",
    ""
  ].join("\r\n");
  const imported = importICS(source, document, { label: "Calendar" });
  const frame = document.frames[imported.frames[0]];
  const pattern = Object.values(document.patterns).find((item) => item.kind === "ics-rrule");
  const moved = addEvent(document, { payload: { title: "Standing meeting (moved)" } });

  // A plain suppression carries no replacement, so filtering `replacements` can
  // never clean it up. This is the record that orphaned.
  document.overrides["override:skipped"] = {
    id: "override:skipped",
    virtual: stableVirtualId(pattern.id, "2026-01-12T09:00:00"),
    suppress: true,
    replacements: []
  };
  document.overrides["override:moved"] = {
    id: "override:moved",
    virtual: stableVirtualId(pattern.id, "2026-01-19T09:00:00"),
    suppress: true,
    replacements: [moved.id]
  };
  return {
    document,
    frame,
    patternId: pattern.id,
    templateId: pattern.templateEvent,
    movedId: moved.id
  };
}

const BOTH_OVERRIDES = ["override:moved", "override:skipped"];

function transactionsFor(document) {
  const app = { chronolog: document };
  app.history = new CommandHistory(document, () => {});
  Object.assign(app, createTransactions(app));
  return app;
}

function overrideIds(document) {
  return Object.keys(document.overrides).sort();
}

test("a virtual id's pattern is derived one way everywhere", () => {
  const virtual = stableVirtualId("pattern:standing", "2026-01-12T09:00:00");
  assert.equal(virtualPatternId(virtual), "pattern:standing");
  assert.equal(overridePatternId({ virtual }), "pattern:standing");
  // The occurrence key is percent-encoded, so the last slash is always the
  // boundary — even when the key itself contained one.
  assert.equal(virtualPatternId(stableVirtualId("pattern:x", "a/b")), "pattern:x");
  assert.equal(virtualPatternId(""), "");
  assert.equal(virtualPatternId(undefined), "");
  assert.equal(overridePatternId({}), "");
});

test("the document that would not load: orphaned overrides fail validation", () => {
  const { document, patternId } = documentWithSeries();
  assert.equal(validateDocument(document).valid, true);
  // Exactly what a non-cascading pattern delete used to leave behind.
  delete document.patterns[patternId];
  const validation = validateDocument(document);
  assert.equal(validation.valid, false);
  assert.equal(
    validation.errors.filter((error) => /references a missing virtual pattern/.test(error)).length,
    2,
    "each orphan is its own error, which is how six of them filled a toast"
  );
});

test("repair-on-load sweeps orphans, reports them, and lets the document open", () => {
  const { document, patternId } = documentWithSeries();
  delete document.patterns[patternId];
  const text = JSON.stringify(document);

  const repairs = [];
  const loaded = parseDocument(text, repairs);
  assert.deepEqual(overrideIds(loaded), [], "the unreachable overrides are gone");
  assert.equal(validateDocument(loaded).valid, true, "and the document opens");
  assert.equal(repairs.length, 1);
  assert.equal(repairs[0].kind, "orphaned-virtual-overrides");
  assert.equal(repairs[0].count, 2);
  assert.match(repairs[0].message, /repeating series/);

  // The report is optional: the existing single-argument call still works.
  assert.equal(validateDocument(parseDocument(text)).valid, true);
});

test("a healthy document is not touched and reports no repairs", () => {
  const { document } = documentWithSeries();
  const repairs = [];
  const loaded = parseDocument(JSON.stringify(document), repairs);
  assert.deepEqual(repairs, []);
  assert.deepEqual(overrideIds(loaded), BOTH_OVERRIDES);
});

test("validateDocument itself stays strict — the repair lives in the parse path", () => {
  const { document, patternId } = documentWithSeries();
  delete document.patterns[patternId];
  // Validation must still reject this in memory; only compaction repairs it.
  assert.equal(validateDocument(document).valid, false);
  compactDocument(document);
  assert.equal(validateDocument(document).valid, true);
});

test("a repair never leaks into serialized output", () => {
  const { document, patternId } = documentWithSeries();
  delete document.patterns[patternId];
  const report = {};
  compactDocument(document, report);
  assert.equal(report.repairs.length, 1);
  assert.doesNotMatch(JSON.stringify(document), /repairs|orphaned-virtual-overrides/);
});

test("deleting a pattern takes its overrides with it, and undo brings both back", () => {
  const { document, patternId, movedId } = documentWithSeries();
  const app = transactionsFor(document);

  app.executePatternChange("Delete pattern", patternId, (documentValue) => {
    delete documentValue.patterns[patternId];
  });

  assert.equal(document.patterns[patternId], undefined);
  assert.deepEqual(overrideIds(document), [], "no orphan survives the delete");
  assert.equal(validateDocument(document).valid, true, "the document stays loadable");
  // The replacement is a real event record and is not swept by a pattern delete.
  assert.ok(document.events[movedId], "an explicit replacement event stays");

  app.history.undo();
  assert.ok(document.patterns[patternId], "the series comes back");
  assert.deepEqual(overrideIds(document), BOTH_OVERRIDES, "with its exceptions");
  assert.equal(validateDocument(document).valid, true);

  app.history.redo();
  assert.equal(document.patterns[patternId], undefined);
  assert.deepEqual(overrideIds(document), [], "redo re-applies the cascade, not half of it");
  assert.equal(validateDocument(document).valid, true);
});

test("the cascade rides the journal, so another window sees the same deletions", () => {
  const { document, patternId } = documentWithSeries();
  const changes = [];
  const app = { chronolog: document };
  app.history = new CommandHistory(document, (change) => changes.push(change));
  Object.assign(app, createTransactions(app));

  app.executePatternChange("Delete pattern", patternId, (documentValue) => {
    delete documentValue.patterns[patternId];
  });

  const expected = [
    "overrides/override:moved",
    "overrides/override:skipped",
    `patterns/${patternId}`
  ].sort();
  const records = (change, kind) => change.ops
    .filter((op) => op.op === kind && op.map !== "meta")
    .map((op) => `${op.map}/${op.id}`)
    .sort();

  assert.equal(changes.length, 1);
  assert.deepEqual(
    records(changes[0], "del"),
    expected,
    "every removed record is journaled, not just the pattern"
  );

  // Undo is its own journal entry rather than a rewind, so the restoration has to
  // appear as real put ops or another window would never see the series return.
  app.history.undo();
  assert.equal(changes.length, 2);
  assert.deepEqual(
    records(changes[1], "put"),
    expected,
    "and undo puts all of them back together"
  );
});

test("deleting the template event cascades to the series' overrides too", () => {
  const { document, patternId, templateId } = documentWithSeries();
  const app = transactionsFor(document);

  app.executeEventChange("Delete event", templateId, (documentValue) => {
    delete documentValue.events[templateId];
    for (const [id, relation] of Object.entries(documentValue.relations)) {
      if (relation.event === templateId) delete documentValue.relations[id];
    }
    for (const [id, pattern] of Object.entries(documentValue.patterns)) {
      if (pattern.templateEvent === templateId) delete documentValue.patterns[id];
    }
  });

  assert.deepEqual(overrideIds(document), []);
  assert.equal(validateDocument(document).valid, true);

  app.history.undo();
  assert.ok(document.events[templateId]);
  assert.ok(document.patterns[patternId]);
  assert.deepEqual(overrideIds(document), BOTH_OVERRIDES);
  assert.equal(validateDocument(document).valid, true);
});

test("removing a frame cascades to the patterns it scoped and their overrides", () => {
  const { document, frame } = documentWithSeries();
  const app = transactionsFor(document);

  app.executeFrameChange("Remove frame", frame.id, (documentValue) => {
    delete documentValue.frames[frame.id];
    for (const [id, relation] of Object.entries(documentValue.relations)) {
      if (relation.frame === frame.id) delete documentValue.relations[id];
    }
    for (const [id, pattern] of Object.entries(documentValue.patterns)) {
      if (pattern.frame === frame.id || pattern.appliesTo?.includes(frame.id)) delete documentValue.patterns[id];
    }
  });

  assert.deepEqual(overrideIds(document), []);

  app.history.undo();
  assert.ok(document.frames[frame.id]);
  assert.deepEqual(overrideIds(document), BOTH_OVERRIDES);
  assert.equal(validateDocument(document).valid, true);
});

// Stage 0.5's "stop repeating here" caps a series with UNTIL and leaves the
// pattern in place, so no override can be orphaned by it. Overrides for
// occurrences beyond the cap stay: the pattern still exists, they are inert
// rather than dangling, and undoing the cap makes them meaningful again.
test("capping a series with UNTIL orphans nothing", () => {
  const { document, patternId } = documentWithSeries();
  const app = transactionsFor(document);

  app.executePatternChange("Stop repeating series", patternId, (documentValue) => {
    documentValue.patterns[patternId].rrule = { FREQ: "WEEKLY", UNTIL: "20260112T090000" };
  });

  assert.deepEqual(overrideIds(document), BOTH_OVERRIDES);
  assert.equal(validateDocument(document).valid, true);
  assert.equal(document.patterns[patternId].rrule.UNTIL, "20260112T090000");

  // And the capped document survives a round trip with nothing to repair.
  const repairs = [];
  assert.equal(validateDocument(parseDocument(JSON.stringify(document), repairs)).valid, true);
  assert.deepEqual(repairs, []);
});

test("the shared sweep only removes overrides belonging to the named patterns", () => {
  const { document, patternId } = documentWithSeries();
  document.patterns["pattern:other"] = { ...document.patterns[patternId], id: "pattern:other" };
  document.overrides["override:other"] = {
    id: "override:other",
    virtual: stableVirtualId("pattern:other", "2026-02-02T09:00:00"),
    suppress: true,
    replacements: []
  };

  assert.equal(removeOverridesForPatterns(document, [patternId]), 2);
  assert.deepEqual(overrideIds(document), ["override:other"], "an unrelated series is untouched");
  assert.equal(removeOverridesForPatterns(document, []), 0);
  assert.equal(removeOverridesForPatterns(document, new Set(["pattern:missing"])), 0);
});
