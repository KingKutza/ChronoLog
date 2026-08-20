import assert from "node:assert/strict";
import test from "node:test";
import { ChronologEngine } from "../src/engine.js";
import { Rational, daysFromCivil } from "../src/exact.js";
import { daysToCivilCoordinate } from "../src/coordinate-law.js";
import { importICS } from "../src/ics.js";
import { CommandHistory, createId, seriesEndStaple, setSeriesEndStaple, validateDocument } from "../src/model.js";
import { createTransactions } from "../src/ui/transactions.js";
import { createStructuralDocument } from "./helpers/sample-document.js";

// Stage F's wiring, as opposed to Stage F's invariant (test/series-heal.test.js
// covers the invariant itself). What is pinned here is that the convergence step
// actually runs inside the ordinary transaction helpers, that its removals ride the
// journal, and that undo brings an occurrence and its override back together.
//
// These tests deliberately drive the transaction layer rather than the DOM. The
// editor's form is built with `innerHTML`, which the repo's stub-DOM harness does
// not parse, and the behaviour worth guaranteeing is a document contract anyway:
// "closing an occurrence you did not change leaves no trace" is a claim about ops
// and records, not about buttons.

function seriesDocument() {
  const chronologDocument = createStructuralDocument();
  const source = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Test//EN",
    "BEGIN:VEVENT",
    "UID:standing@example.test",
    "DTSTART:20260105T090000Z",
    "RRULE:FREQ=WEEKLY",
    "SUMMARY:Standing meeting",
    "DURATION:PT1H",
    "END:VEVENT",
    "END:VCALENDAR",
    ""
  ].join("\r\n");
  const imported = importICS(source, chronologDocument, { label: "Calendar" });
  const frame = chronologDocument.frames[imported.frames[0]];
  const pattern = Object.values(chronologDocument.patterns).find((item) => item.kind === "ics-rrule");
  return { document: chronologDocument, frame, pattern };
}

function appFor(chronologDocument) {
  const changes = [];
  const app = { chronolog: chronologDocument, changes };
  app.engine = new ChronologEngine(chronologDocument);
  app.refreshEngine = (documentValue) => {
    app.engine.setDocument(documentValue || app.chronolog);
    return app.engine;
  };
  app.history = new CommandHistory(chronologDocument, (change) => changes.push(change));
  Object.assign(app, createTransactions(app));
  return app;
}

function occurrenceFacts(app, frame) {
  return app.refreshEngine(app.chronolog).queryFacts({
    frame: frame.id,
    start: daysToCivilCoordinate(daysFromCivil(2026n, 1n, 1n).toString()),
    end: daysToCivilCoordinate(daysFromCivil(2026n, 2n, 15n).toString()),
    limit: 80,
    applyOverrides: false
  }).facts;
}

// The document state the editor produces when the user asks for occurrence mode.
// Mirrors src/ui/inspector.js's prepareMaterialization/applyMaterialization.
function materializeOccurrence(app, fact, pattern) {
  const chronologDocument = app.chronolog;
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
  app.history.executeDelta("Edit one occurrence", (documentValue) => {
    documentValue.events[event.id] = event;
    documentValue.relations[relation.id] = relation;
    documentValue.overrides[override.id] = override;
  }, (documentValue) => {
    delete documentValue.overrides[override.id];
    delete documentValue.relations[relation.id];
    delete documentValue.events[event.id];
  }, {});
  return { event, relation, override };
}

function census(chronologDocument) {
  return {
    events: Object.keys(chronologDocument.events).sort(),
    relations: Object.keys(chronologDocument.relations).sort(),
    overrides: Object.keys(chronologDocument.overrides).sort(),
    patterns: Object.keys(chronologDocument.patterns).sort()
  };
}

// ROADMAP #5, and the owner's ruling that a no-op must leave nothing behind.
test("asking for occurrence mode and then closing without changes leaves zero document delta", () => {
  const { document: chronologDocument, frame, pattern } = seriesDocument();
  const app = appFor(chronologDocument);
  const before = census(chronologDocument);

  const { event } = materializeOccurrence(app, occurrenceFacts(app, frame)[1], pattern);
  assert.notDeepEqual(census(chronologDocument), before, "the materialization really happened");

  // This is what closing the card does.
  assert.equal(app.convergeSeriesOccurrence(event.id), true, "closing converges it");
  assert.deepEqual(census(chronologDocument), before, "and the document is exactly as it started");
  assert.equal(validateDocument(chronologDocument).valid, true);
});

test("an occurrence that was genuinely edited survives closing, exactly once", () => {
  const { document: chronologDocument, frame, pattern } = seriesDocument();
  const app = appFor(chronologDocument);
  const { event } = materializeOccurrence(app, occurrenceFacts(app, frame)[1], pattern);

  app.executeEventChange("Edit event", event.id, (documentValue) => {
    documentValue.events[event.id].payload.title = "Standing meeting (moved)";
  });
  assert.ok(chronologDocument.events[event.id], "the edit survived its own transaction's convergence check");

  assert.equal(app.convergeSeriesOccurrence(event.id), false, "closing does not retire a real deviation");
  assert.ok(chronologDocument.events[event.id], "the authored occurrence is still there");
  const materialized = Object.values(chronologDocument.overrides)
    .filter((override) => override.suppress && override.replacements?.length);
  assert.equal(materialized.length, 1, "exactly one materialized instance, not two");
});

// The heal is state-based, so undoing an edit back to the series' own values makes
// the occurrence converge on the very next touch — "the series of events leading up
// to the heal are irrelevant".
test("editing an occurrence and then editing it back retires it", () => {
  const { document: chronologDocument, frame, pattern } = seriesDocument();
  const app = appFor(chronologDocument);
  const baseline = census(chronologDocument);
  const { event } = materializeOccurrence(app, occurrenceFacts(app, frame)[1], pattern);

  app.executeEventChange("Edit event", event.id, (documentValue) => {
    documentValue.events[event.id].payload.title = "Temporarily different";
  });
  assert.ok(chronologDocument.events[event.id]);

  // Put the title back by hand. The convergence step inside this very transaction
  // notices the occurrence now matches and retires it.
  app.executeEventChange("Edit event", event.id, (documentValue) => {
    documentValue.events[event.id].payload.title = "Standing meeting";
  });
  assert.equal(chronologDocument.events[event.id], undefined, "it healed inside the edit that restored it");
  assert.deepEqual(census(chronologDocument), baseline, "leaving the document as the series alone describes it");
});

test("the heal rides the journal, so another window sees the same removals", () => {
  const { document: chronologDocument, frame, pattern } = seriesDocument();
  const app = appFor(chronologDocument);
  const { event, relation, override } = materializeOccurrence(app, occurrenceFacts(app, frame)[1], pattern);

  app.changes.length = 0;
  app.convergeSeriesOccurrence(event.id);
  assert.equal(app.changes.length, 1, "one journalled change");
  const deletions = app.changes[0].ops
    .filter((op) => op.op === "del" && op.map !== "meta")
    .map((op) => `${op.map}/${op.id}`)
    .sort();
  assert.deepEqual(deletions, [
    `events/${event.id}`,
    `overrides/${override.id}`,
    `relations/${relation.id}`
  ].sort(), "the event, its relation and the override are all journalled as removed");
});

test("undo restores a healed occurrence and its override together", () => {
  const { document: chronologDocument, frame, pattern } = seriesDocument();
  const app = appFor(chronologDocument);
  const { event, override } = materializeOccurrence(app, occurrenceFacts(app, frame)[1], pattern);
  const materialized = census(chronologDocument);

  app.convergeSeriesOccurrence(event.id);
  assert.equal(chronologDocument.events[event.id], undefined);

  app.history.undo();
  assert.deepEqual(census(chronologDocument), materialized, "both come back, in one step");
  assert.ok(chronologDocument.overrides[override.id], "the override is not restored without its event");
  assert.ok(chronologDocument.events[event.id], "nor the event without its override");
  assert.equal(validateDocument(chronologDocument).valid, true);

  app.history.redo();
  assert.equal(chronologDocument.events[event.id], undefined, "redo retires it again");
  assert.equal(chronologDocument.overrides[override.id], undefined);
});

// Editing the series can converge an occurrence the edit never named: this is why
// convergence is scoped by pattern on a pattern change, not by event.
test("moving the series onto an exception's own values retires that exception", () => {
  const { document: chronologDocument, frame, pattern } = seriesDocument();
  const app = appFor(chronologDocument);
  const { event } = materializeOccurrence(app, occurrenceFacts(app, frame)[1], pattern);

  app.executeEventChange("Edit event", event.id, (documentValue) => {
    documentValue.events[event.id].payload.title = "Renamed on this one";
  });
  assert.ok(chronologDocument.events[event.id], "the exception exists and deviates");

  // Now rename the SERIES to the same thing, via the pattern's template event. The
  // exception no longer deviates, so it must not survive as a duplicate.
  app.executeEventChange("Edit series", pattern.templateEvent, (documentValue) => {
    documentValue.events[pattern.templateEvent].payload.title = "Renamed on this one";
  });
  assert.equal(
    chronologDocument.events[event.id],
    undefined,
    "the exception converged onto the series and was retired"
  );
  assert.equal(validateDocument(chronologDocument).valid, true);
});

// LEXICON's staple anchoring / Rob-and-John scenario, driven through the same
// transaction the series editor card actually uses: src/ui/inspector.js
// places/clears the staple inside the template event's own `executeEventChange`
// call, alongside the rest of the series edit, so it journals and undoes as
// one change -- not a second mechanism with its own bundle.
test("placing an end-staple through the series' own edit transaction stops the projection, journals as one change, and undoes cleanly", () => {
  const { document: chronologDocument, frame, pattern } = seriesDocument();
  const app = appFor(chronologDocument);
  const before = occurrenceFacts(app, frame).map((fact) => fact.day);
  assert.ok(before.length > 3, "the series projects several occurrences before the staple");

  const stapleDay = Rational.parse(before[2]);
  app.changes.length = 0;
  app.executeEventChange("Edit series", pattern.templateEvent, (documentValue) => {
    setSeriesEndStaple(documentValue, pattern.id, frame.id, daysToCivilCoordinate(stapleDay));
  });

  const staple = seriesEndStaple(chronologDocument, pattern.id);
  assert.ok(staple, "the staple exists");
  assert.equal(app.changes.length, 1, "one journalled change, not a separate transaction");
  // `captureEventBundle` always re-clones the template event and the series'
  // own pattern on both sides of the diff, so an identity-based diff
  // (`opsFromMaps`) re-puts them alongside whatever else changed -- that is
  // pre-existing bundle behaviour, not something the staple introduces. What
  // this pins is that the staple's own put rides along as an ordinary
  // record-level relation op, inside this one transaction.
  const puts = app.changes[0].ops.filter((op) => op.op === "put" && op.map !== "meta");
  assert.ok(
    puts.some((op) => op.map === "relations" && op.id === staple.id),
    "the staple journals as a record-level put"
  );

  const after = occurrenceFacts(app, frame).map((fact) => fact.day);
  assert.deepEqual(after, before.slice(0, 3), "the projection stops at the staple; earlier occurrences survive");

  app.history.undo();
  assert.equal(seriesEndStaple(chronologDocument, pattern.id), null, "undo removes the staple");
  assert.deepEqual(occurrenceFacts(app, frame).map((fact) => fact.day), before, "and the full projection is back");

  app.history.redo();
  assert.ok(seriesEndStaple(chronologDocument, pattern.id), "redo restores the staple");
  assert.deepEqual(occurrenceFacts(app, frame).map((fact) => fact.day), before.slice(0, 3));
});

test("an ordinary event edit is untouched by the convergence step", () => {
  const { document: chronologDocument } = seriesDocument();
  const app = appFor(chronologDocument);
  const plain = createId("event");
  app.executeEventChange("Create event", plain, (documentValue) => {
    documentValue.events[plain] = {
      id: plain,
      traits: ["event"],
      payload: { title: "Unrelated" },
      magnitudes: {}
    };
  });
  assert.ok(chronologDocument.events[plain], "a plain event is never a heal candidate");
  assert.equal(app.convergeSeriesOccurrence(plain), false, "and asking about it commits nothing");
});
