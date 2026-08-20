import assert from "node:assert/strict";
import test from "node:test";
import { ChronologEngine } from "../src/engine.js";
import { coordinateLaw } from "../src/coordinate-law.js";
import { Rational, coordinate } from "../src/exact.js";
import { importICS } from "../src/ics.js";
import {
  CommandHistory,
  addEvent,
  addFrame,
  addPattern,
  addRelation,
  durationMagnitude,
  frameEnd,
  objectEnd,
  putStaple,
  removeStaple,
  seriesEnd,
  validateDocument
} from "../src/model.js";
import {
  STAPLE_KINDS,
  effectiveObjectStaples,
  isFuzzyStaple,
  resolveObjectExtent,
  stapleKindScopes,
  stapleSpreadDays,
  staplesForSeries
} from "../src/staples.js";
import { createTransactions } from "../src/ui/transactions.js";
import { explainFactWeight } from "../src/visual-language.js";
import {
  buildStapleInput,
  createInspector,
  extentReadoutModel,
  stapleKindOptions,
  stapleRowModel,
  weightReadoutModel
} from "../src/ui/inspector.js";
import { createStructuralDocument } from "./helpers/sample-document.js";

// Owner's 8.20 field report: the shipped card kept a separate Start
// date/time GUI alongside the staples section, treating "start" as special --
// "if I enter an anchor at point end, 17:00 and a durration of 180m No event
// appears and I get an error that start time is null. This is bad because it
// treats the Start time as special, when no staple should be special." This
// file exercises the general replacement: the staple list IS the placement
// interface, one row per connection (the implicit default-start staple first,
// then every authored one), each with a single variable-precision coordinate
// field, driven under `src/coordinate-entry.js`'s law-governed parser rather
// than a date/time pair. Items 5 (weight visibility) and 8 ("Visible in"
// removal) share the same card and are exercised alongside it.
//
// Where the DOM is too thin to drive `innerHTML`/`FormData` flows (this
// codebase's own established limit -- see test/frame-creation.test.js and
// `resolveSubmittedEventColor`'s own tests), the DECISIONS the editor makes
// are pulled out as plain exported functions and driven directly here. A
// small stub-DOM harness (copied from test/dock-card-refresh.test.js's
// pattern, extended with just enough of `HTMLFormElement`/`FormData` to
// submit a real form) covers the handful of things that only make sense as
// rendered structure and the owner's bug end to end.

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

function appFor(chronolog) {
  const changes = [];
  const app = { chronolog, history: new CommandHistory(chronolog, (change) => changes.push(change)) };
  Object.assign(app, createTransactions(app));
  return { app, changes };
}

// A plain, non-recurring event on a calendar frame -- the "object" scope's
// minimal fixture. 30-minute duration, placed by the implicit attachment
// relation (the migration: an attachment IS the default start staple).
function documentWithEvent() {
  const document = createStructuralDocument();
  addFrame(document, { id: "calendar:test", title: "Test calendar", traits: ["set", "calendar"], basis: "frame:wall-time" });
  const event = addEvent(document, {
    id: "event:test",
    traits: ["event"],
    magnitudes: { duration: durationMagnitude("30", "minute") },
    payload: { title: "Test event" }
  });
  addRelation(document, {
    id: "relation:test-placed",
    type: "attachment",
    event: event.id,
    frame: "calendar:test",
    role: "placed",
    coordinate: civil(2026, 1, 5, 9, 0, 0)
  });
  return { document, event };
}

// The template event plus its ics-rrule pattern -- the exact shape
// `findRecurrencePattern` (src/ui/inspector.js) looks for, and the "series"
// scope's minimal fixture.
function documentWithSeries() {
  const { document, event } = documentWithEvent();
  const pattern = addPattern(document, {
    id: "pattern:test",
    kind: "ics-rrule",
    appliesTo: ["calendar:test"],
    frame: "calendar:test",
    templateEvent: event.id,
    templateRelation: "relation:test-placed",
    rrule: { FREQ: "WEEKLY" }
  });
  return { document, event, pattern };
}

// ---------------------------------------------------------------------------
// The registry-driven dropdown
// ---------------------------------------------------------------------------

test("stapleKindOptions is STAPLE_KINDS itself, filtered by scope -- never a hand-written list, and correspondence never appears on this card", () => {
  const seriesKinds = Object.keys(STAPLE_KINDS).filter((kind) => kind !== "correspondence" && stapleKindScopes(kind).includes("series"));
  const objectKinds = Object.keys(STAPLE_KINDS).filter((kind) => kind !== "correspondence" && stapleKindScopes(kind).includes("object"));
  assert.deepEqual(stapleKindOptions("series").map(([value]) => value).sort(), seriesKinds.sort());
  assert.deepEqual(stapleKindOptions("object").map(([value]) => value).sort(), objectKinds.sort());
  // Series-only kinds (partitioning/phase) must never be offered on a bare,
  // non-recurring event -- there is no series body to place them on.
  assert.ok(!stapleKindOptions("object").some(([value]) => value === "end"));
  assert.ok(!stapleKindOptions("object").some(([value]) => value === "inflection"));
  assert.ok(!stapleKindOptions("object").some(([value]) => value === "phase"));
  // `correspondence` (frame-to-frame) is not an object/series staple at all --
  // excluded explicitly rather than relying on its own scope set happening
  // to miss both.
  assert.ok(!stapleKindOptions("object").some(([value]) => value === "correspondence"));
  assert.ok(!stapleKindOptions("series").some(([value]) => value === "correspondence"));
  // Every option's label comes straight from the registry, not a restatement.
  for (const [value, label] of stapleKindOptions("series")) assert.equal(label, STAPLE_KINDS[value].label);
});

// ---------------------------------------------------------------------------
// buildStapleInput -- the staple row's own decision, pulled out of the DOM
// ---------------------------------------------------------------------------

test("buildStapleInput rejects a kind that cannot connect this scope to the chosen far end", () => {
  assert.throws(
    () => buildStapleInput({
      scope: "object", targetId: "event:x", kind: "end",
      farScope: "frame", farId: "calendar:test", coordinateText: "2026-01-01", law: coordinateLaw(createStructuralDocument(), "frame:wall-time")
    }),
    /cannot connect an event/
  );
});

test("buildStapleInput requires a coordinate for a frame connection, and a name for a custom point", () => {
  const law = coordinateLaw(createStructuralDocument(), "frame:wall-time");
  assert.throws(
    () => buildStapleInput({ scope: "object", targetId: "event:x", kind: "anchor", nearPoint: "start", farScope: "frame", farId: "frame:wall-time", law }),
    /needs a coordinate/
  );
  assert.throws(
    () => buildStapleInput({
      scope: "object", targetId: "event:x", kind: "anchor", nearPoint: "__custom__", nearPointName: "",
      farScope: "frame", farId: "frame:wall-time", coordinateText: "2026-01-01", law
    }),
    /Name this point/
  );
});

// Owner's ruling made concrete: "Type month day year hour minute second
// millisecond" -- precision typed IS coordinate depth, and depth is never
// fuzziness. A bare date on ANY kind resolves to midnight of that day (the
// law's own default-filling for levels below what was typed), never an
// inferred end-of-day -- that would be a kind-specific business rule sitting
// inside the one generic coordinate field, contradicting "every row is the
// same shape".
test("a bare-date coordinate resolves to midnight of that day -- precision typed is depth, never an inferred end-of-day", () => {
  const law = coordinateLaw(createStructuralDocument(), "frame:wall-time");
  const input = buildStapleInput({
    scope: "object", targetId: "event:x", kind: "anchor", nearPoint: "start",
    farScope: "frame", farId: "frame:wall-time", coordinateText: "2026-01-19", law
  });
  const engine = new ChronologEngine(createStructuralDocument());
  assert.equal(
    engine.coordinateDays("frame:wall-time", input.ends[1].coordinate)
      .compare(engine.coordinateDays("frame:wall-time", civil(2026, 1, 19, 0, 0, 0))),
    0
  );
});

// An explicit clock time on purpose: this asserts that what was typed is what is
// stored. The bare-date case is a question about how a SEGMENT CLOSES, not about
// what the field records, and it is covered where the projection is checked.
test("an end staple authored through buildStapleInput connects the series to a frame at the exact typed instant", () => {
  const { document, pattern } = documentWithSeries();
  const law = coordinateLaw(document, "calendar:test");
  const input = buildStapleInput({
    scope: "series", targetId: pattern.id, kind: "end",
    farScope: "frame", farId: "calendar:test", coordinateText: "2026-01-19 23:59:59", law
  });
  assert.equal(input.kind, "end");
  assert.deepEqual(input.ends[0], seriesEnd(pattern.id));
  assert.equal(input.ends[1].frame, "calendar:test");
  putStaple(document, { ...input, id: "relation:end-under-test" });
  assert.equal(validateDocument(document).valid, true);
  const engine = new ChronologEngine(document);
  assert.equal(
    engine.coordinateDays("calendar:test", document.relations["relation:end-under-test"].ends[1].coordinate)
      .compare(engine.coordinateDays("calendar:test", civil(2026, 1, 19, 23, 59, 59))),
    0
  );
});

test("a named point pairs with an offset magnitude; start/end/midpoint never do", () => {
  const { document } = documentWithEvent();
  const law = coordinateLaw(document, "calendar:test");
  const named = buildStapleInput({
    scope: "object", targetId: "event:x", kind: "anchor",
    nearPoint: "__custom__", nearPointName: "shift handover", nearOffsetAmount: "45", nearOffsetUnit: "minute",
    farScope: "frame", farId: "calendar:test", coordinateText: "2026-01-19 17:00", law
  });
  assert.equal(named.ends[0].point, "shift handover");
  assert.ok(named.ends[0].offset, "the offset magnitude is paired with the named point");

  const start = buildStapleInput({
    scope: "object", targetId: "event:x", kind: "anchor", nearPoint: "start",
    nearOffsetAmount: "45", nearOffsetUnit: "minute",
    farScope: "frame", farId: "calendar:test", coordinateText: "2026-01-19 17:00", law
  });
  assert.equal(start.ends[0].offset, undefined, "an offset typed for a fixed point is not stored -- its meaning is not defined");
});

// ---------------------------------------------------------------------------
// One list row's display fields -- one coordinate text, never a date/time pair
// ---------------------------------------------------------------------------

test("stapleRowModel represents the implicit placement row as one row among others, with a single coordinate field", () => {
  const { document, event } = documentWithEvent();
  const rows = effectiveObjectStaples(document, event.id);
  assert.equal(rows.length, 1);
  const model = stapleRowModel(rows[0], document);
  assert.equal(model.implicit, true);
  assert.equal(model.nearPoint, "start");
  assert.equal(model.farScope, "frame");
  assert.equal(model.farId, "calendar:test");
  assert.equal(model.coordinateText, "2026-01-05 09:00:00");
  assert.equal(model.fuzzy, false);
  assert.equal(Object.prototype.hasOwnProperty.call(model, "date"), false, "no separate date field");
  assert.equal(Object.prototype.hasOwnProperty.call(model, "time"), false, "no separate time field");
});

test("stapleRowModel reports the registry label, near/far, single coordinate text, and fuzzy marker for an authored row", () => {
  const { document, event } = documentWithEvent();
  const law = coordinateLaw(document, "calendar:test");
  putStaple(document, {
    id: "relation:plain-anchor",
    kind: "anchor",
    ends: [objectEnd(event.id, "start"), frameEnd("calendar:test", civil(2026, 2, 1, 9, 30, 0))]
  });
  const plainRow = effectiveObjectStaples(document, event.id).find((row) => row.staple?.id === "relation:plain-anchor");
  const plainModel = stapleRowModel(plainRow, document);
  assert.equal(plainModel.implicit, false);
  assert.equal(plainModel.kindLabel, STAPLE_KINDS.anchor.label);
  assert.equal(plainModel.nearPoint, "start");
  assert.equal(plainModel.farLabel, "Test calendar");
  assert.equal(plainModel.coordinateText, "2026-02-01 09:30:00");
  assert.equal(plainModel.fuzzy, false);

  const fuzzy = putStaple(document, buildStapleInput({
    scope: "object", targetId: event.id, kind: "anchor", nearPoint: "end",
    farScope: "frame", farId: "calendar:test", coordinateText: "2026-02-02", law,
    fuzzy: true, spreadBeforeAmount: "10", spreadAfterAmount: "10"
  }));
  const fuzzyRow = effectiveObjectStaples(document, event.id).find((row) => row.staple?.id === fuzzy.id);
  const fuzzyModel = stapleRowModel(fuzzyRow, document);
  assert.equal(fuzzyModel.fuzzy, true);
  assert.equal(fuzzyModel.coordinateText, "2026-02-02", "depth reflects exactly what was typed -- a bare date stays a bare date");
});

// ---------------------------------------------------------------------------
// Adding/removing a staple: one journalled, undoable, record-level change
// ---------------------------------------------------------------------------

test("adding a staple of each registered kind is one journalled, undoable change, and undo removes it", () => {
  for (const kindName of Object.keys(STAPLE_KINDS)) {
    // A kind that ONLY connects frame to frame is never authored on this card,
    // which edits an object's or a series' own staples. Derived from the
    // registry rather than named, so a new frame-to-frame kind needs no edit
    // here -- `succession` (era boundaries) is the second such kind.
    if (STAPLE_KINDS[kindName].connects.every((pair) => pair === "frame+frame")) continue;
    const definition = STAPLE_KINDS[kindName];
    const scope = stapleKindScopes(kindName).includes("object") ? "object" : "series";
    const fixture = scope === "series" ? documentWithSeries() : documentWithEvent();
    const { document } = fixture;
    const targetId = scope === "series" ? fixture.pattern.id : fixture.event.id;
    const law = coordinateLaw(document, "calendar:test");
    const { app, changes } = appFor(document);
    const input = buildStapleInput({
      scope,
      targetId,
      kind: kindName,
      nearPoint: definition.anchors ? "start" : undefined,
      farScope: "frame",
      farId: "calendar:test",
      coordinateText: "2026-02-01 09:00",
      law
    });
    const stapleId = "relation:staple-under-test";

    changes.length = 0;
    if (scope === "series") {
      app.executePatternChange(`Add ${kindName} staple`, targetId, (documentValue) => putStaple(documentValue, { ...input, id: stapleId }));
    } else {
      app.executeEventChange(`Add ${kindName} staple`, targetId, (documentValue) => putStaple(documentValue, { ...input, id: stapleId }));
    }
    assert.ok(document.relations[stapleId], `${kindName}: the staple record exists`);
    assert.equal(document.relations[stapleId].kind, kindName);
    assert.equal(changes.length, 1, `${kindName}: exactly one journalled change`);
    assert.ok(
      changes[0].ops.some((op) => op.op === "put" && op.map === "relations" && op.id === stapleId),
      `${kindName}: journals as a record-level relations put`
    );
    assert.equal(validateDocument(document).valid, true, `${kindName}: the document stays valid`);

    app.history.undo();
    assert.equal(document.relations[stapleId], undefined, `${kindName}: undo removes it`);
    app.history.redo();
    assert.ok(document.relations[stapleId], `${kindName}: redo restores it`);
  }
});

test("deleting an event deletes its own object staples in the same undoable transaction, and undo restores both together", () => {
  const { document, event } = documentWithEvent();
  const staple = putStaple(document, {
    kind: "anchor", ends: [objectEnd(event.id, "start"), frameEnd("calendar:test", civil(2026, 2, 1, 9, 0, 0))]
  });
  const { app } = appFor(document);

  // Mirrors src/ui/inspector.js's real Delete handler: the event's own
  // ordinary relations (its placement) are swept explicitly; its staples are
  // not -- that is the cascade under test.
  app.executeEventChange("Delete event", event.id, (documentValue) => {
    delete documentValue.events[event.id];
    for (const relation of Object.values(documentValue.relations)) {
      if (relation.event === event.id) delete documentValue.relations[relation.id];
    }
  });
  assert.equal(document.events[event.id], undefined);
  assert.equal(document.relations[staple.id], undefined, "its object staple went with it, not left as a dangling pointer");
  assert.equal(validateDocument(document).valid, true);

  app.history.undo();
  assert.ok(document.events[event.id], "the event comes back");
  assert.ok(document.relations[staple.id], "and its staple comes back with it, in the same undo step");
});

test("removing a staple is one journalled, undoable change", () => {
  const { document, event } = documentWithEvent();
  const staple = putStaple(document, {
    kind: "anchor", ends: [objectEnd(event.id, "start"), frameEnd("calendar:test", civil(2026, 2, 1, 9, 0, 0))]
  });
  const { app, changes } = appFor(document);

  changes.length = 0;
  app.executeEventChange("Remove staple", event.id, (documentValue) => removeStaple(documentValue, staple.id));
  assert.equal(document.relations[staple.id], undefined);
  assert.equal(changes.length, 1);
  assert.ok(changes[0].ops.some((op) => op.op === "del" && op.map === "relations" && op.id === staple.id));

  app.history.undo();
  assert.ok(document.relations[staple.id], "undo restores the removed staple");
  assert.deepEqual(document.relations[staple.id].kind, "anchor");
});

test("an end staple added through the general staples flow cuts a series projection exactly like the bespoke field used to", () => {
  const document = createStructuralDocument();
  const source = [
    "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Test//EN", "BEGIN:VEVENT",
    "UID:standing@example.test", "DTSTART:20260105T090000Z", "RRULE:FREQ=WEEKLY",
    "SUMMARY:Standing meeting", "DURATION:PT30M", "END:VEVENT", "END:VCALENDAR", ""
  ].join("\r\n");
  const imported = importICS(source, document, { label: "Calendar" });
  const frame = document.frames[imported.frames[0]];
  const pattern = Object.values(document.patterns).find((item) => item.kind === "ics-rrule");
  const { app, changes } = appFor(document);
  const law = coordinateLaw(document, frame.id);

  // A BARE DATE, typed the way a user types one. Nothing here is kind-special:
  // day precision names a DAY, so the segment closes at the end of it and the
  // 19th's own occurrence survives the cut.
  const input = buildStapleInput({
    scope: "series", targetId: pattern.id, kind: "end",
    farScope: "frame", farId: frame.id, coordinateText: "2026-01-19", law
  });
  changes.length = 0;
  app.executePatternChange("Add staple", pattern.id, (documentValue) => putStaple(documentValue, input));
  assert.equal(changes.length, 1);

  const engine = new ChronologEngine(document);
  const facts = engine.queryFacts({
    frame: frame.id,
    start: civil(2026, 1, 1),
    end: civil(2026, 3, 1),
    limit: 200
  }).facts.filter((fact) => fact.kind === "virtual");
  const dates = facts.map((fact) => `${fact.coordinate.levels.find((l) => l.level === "day").value}`);
  assert.deepEqual(dates, ["5", "12", "19"], "the staple's own occurrence survives; nothing after it projects");

  app.history.undo();
  assert.equal(staplesForSeries(document, pattern.id).length, 0, "undo removes the staple entirely");
});

// ---------------------------------------------------------------------------
// Fuzzy staples: asymmetric before/after spread, never inferred from depth
// ---------------------------------------------------------------------------

test("a fuzzy staple round-trips its asymmetric before/after spread", () => {
  const { document, event } = documentWithEvent();
  const law = coordinateLaw(document, "calendar:test");
  const input = buildStapleInput({
    scope: "object", targetId: event.id, kind: "anchor", nearPoint: "start",
    farScope: "frame", farId: "calendar:test", coordinateText: "2026-02-01 17:00", law,
    fuzzy: true, spreadBeforeAmount: "15", spreadBeforeUnit: "minute", spreadAfterAmount: "30", spreadAfterUnit: "minute"
  });
  const staple = putStaple(document, input);
  assert.ok(isFuzzyStaple(staple));
  const spread = stapleSpreadDays(staple);
  assert.equal(spread.before.compare(Rational.parse(15).div(1440)), 0);
  assert.equal(spread.after.compare(Rational.parse(30).div(1440)), 0);
  assert.notEqual(spread.before.compare(spread.after), 0, "asymmetric on purpose -- never a single +/-");
});

test("a staple with no spread amounts entered is not reported as fuzzy", () => {
  const { document, event } = documentWithEvent();
  const law = coordinateLaw(document, "calendar:test");
  const staple = putStaple(document, buildStapleInput({
    scope: "object", targetId: event.id, kind: "anchor", nearPoint: "start",
    farScope: "frame", farId: "calendar:test", coordinateText: "2026-02-01", law, fuzzy: true
  }));
  assert.equal(isFuzzyStaple(staple), false);
});

test("coordinate entry depth never sets a spread; the fuzzy checkbox is the only thing that does", () => {
  const { document, event } = documentWithEvent();
  const law = coordinateLaw(document, "calendar:test");
  for (const text of ["2026", "2026-02-01", "2026-02-01 17:00:30"]) {
    const input = buildStapleInput({
      scope: "object", targetId: event.id, kind: "anchor", nearPoint: "start",
      farScope: "frame", farId: "calendar:test", coordinateText: text, law
    });
    assert.equal(input.spread, undefined, `entry depth "${text}" must not imply fuzziness`);
  }
});

// ---------------------------------------------------------------------------
// Variable precision, through the editor's own parse path, at three depths
// ---------------------------------------------------------------------------

test("variable precision at three depths, through the editor's own parse path, each lands on the exact instant", () => {
  const { document, event } = documentWithEvent();
  const law = coordinateLaw(document, "calendar:test");
  const engine = new ChronologEngine(document);
  const cases = [
    ["2026", civil(2026, 1, 1, 0, 0, 0)],
    ["2026 8 20", civil(2026, 8, 20, 0, 0, 0)],
    ["2026 8 20 17:00", civil(2026, 8, 20, 17, 0, 0)]
  ];
  for (const [text, expected] of cases) {
    const input = buildStapleInput({
      scope: "object", targetId: event.id, kind: "anchor", nearPoint: "start",
      farScope: "frame", farId: "calendar:test", coordinateText: text, law
    });
    assert.equal(
      engine.coordinateDays("calendar:test", input.ends[1].coordinate).compare(engine.coordinateDays("calendar:test", expected)),
      0,
      `"${text}" lands on the exact instant`
    );
  }
});

// ---------------------------------------------------------------------------
// The derived-extent readout, including `unresolved`
// ---------------------------------------------------------------------------

test("the derived-extent readout reports an end-anchored event's start, and names an overdetermined anchor", () => {
  const { document, event } = documentWithEvent();

  // Explicit ids, not the substrate's own random `createId` ones: the whole
  // point of this test is which of two same-role anchors the stable order
  // picks, and a random id would make that pass or fail by chance.
  putStaple(document, {
    id: "relation:end-anchor-1",
    kind: "anchor", ends: [objectEnd(event.id, "end"), frameEnd("calendar:test", civil(2026, 1, 5, 17, 0, 0))]
  });
  const before = extentReadoutModel(resolveObjectExtent(document, new ChronologEngine(document), event.id));
  assert.equal(before.source, "anchor+magnitude");
  assert.equal(before.derivedMagnitude, false);
  assert.equal(before.end, "2026-01-05 17:00:00");
  // 30-minute duration (documentWithEvent's fixture), end-anchored -> starts
  // half an hour earlier, not at the object's own unrelated placement.
  assert.equal(before.start, "2026-01-05 16:30:00");
  assert.deepEqual(before.overdetermined, []);
  assert.deepEqual(before.unresolved, []);

  // A second "end" anchor cannot also be believed -- it is retained, named,
  // and reported, never silently averaged in.
  putStaple(document, {
    id: "relation:end-anchor-2",
    kind: "anchor", ends: [objectEnd(event.id, "end"), frameEnd("calendar:test", civil(2026, 1, 6, 12, 0, 0))]
  });
  const after = extentReadoutModel(resolveObjectExtent(document, new ChronologEngine(document), event.id));
  assert.equal(after.start, before.start, "placement is unchanged -- the extra anchor is not used");
  assert.equal(after.overdetermined.length, 1);
  assert.equal(after.overdetermined[0].kind, "anchor");
  assert.equal(after.overdetermined[0].kindLabel, STAPLE_KINDS.anchor.label);
  assert.equal(after.overdetermined[0].role, "end");
  assert.match(after.overdetermined[0].reason, /already anchors this point/);
});

test("a zero-staple object reports an unresolved-free honest placement, not a fabricated extent", () => {
  const document = createStructuralDocument();
  const event = addEvent(document, {
    id: "event:floating",
    traits: ["event", "task", "todo"],
    magnitudes: { duration: durationMagnitude("0") },
    payload: { title: "Floating todo" }
  });
  const engine = new ChronologEngine(document);
  const model = extentReadoutModel(resolveObjectExtent(document, engine, event.id));
  assert.equal(model.source, "unstapled");
  assert.equal(model.start, null);
  assert.equal(model.end, null);
  assert.deepEqual(model.unresolved, []);
});

test("a connection whose other end has no resolvable position is surfaced as unresolved, never averaged or hidden", () => {
  const document = createStructuralDocument();
  addFrame(document, { id: "calendar:test", title: "Test calendar", traits: ["set", "calendar"], basis: "frame:wall-time" });
  const floating = addEvent(document, {
    id: "event:floating", traits: ["event"], magnitudes: { duration: durationMagnitude("0") }, payload: { title: "Floating" }
  });
  const dependent = addEvent(document, {
    id: "event:dependent", traits: ["event"], magnitudes: { duration: durationMagnitude("1", "hour") }, payload: { title: "Dependent" }
  });
  putStaple(document, {
    kind: "anchor",
    ends: [objectEnd(dependent.id, "start"), objectEnd(floating.id, "end")]
  });
  const engine = new ChronologEngine(document);
  const model = extentReadoutModel(resolveObjectExtent(document, engine, dependent.id));
  assert.equal(model.start, null);
  assert.equal(model.unresolved.length, 1);
  assert.equal(model.unresolved[0].kind, "anchor");
  assert.match(model.unresolved[0].reason, /no resolvable position/);
});

// ---------------------------------------------------------------------------
// An object-to-object row: the other half the owner said was missing
// ---------------------------------------------------------------------------

test("an object-to-object row authored through the editor produces a valid two-object-end staple, and the downstream event resolves at the upstream event's chosen point", () => {
  const document = createStructuralDocument();
  addFrame(document, { id: "calendar:test", title: "Test calendar", traits: ["set", "calendar"], basis: "frame:wall-time" });
  const upstream = addEvent(document, {
    id: "event:upstream", traits: ["event"],
    magnitudes: { duration: durationMagnitude("2", "hour") },
    payload: { title: "Upstream" }
  });
  addRelation(document, { type: "attachment", event: upstream.id, frame: "calendar:test", role: "placed", coordinate: civil(2026, 4, 1, 8, 0, 0) });

  const downstream = addEvent(document, {
    id: "event:downstream", traits: ["event"],
    magnitudes: { duration: durationMagnitude("30", "minute") },
    payload: { title: "Downstream" }
  });
  addRelation(document, { type: "attachment", event: downstream.id, frame: "calendar:test", role: "placed" });

  const input = buildStapleInput({
    scope: "object", targetId: downstream.id, kind: "anchor", nearPoint: "start",
    farScope: "object", farId: upstream.id, farPoint: "end"
  });
  assert.deepEqual(input.ends[0], objectEnd(downstream.id, "start"));
  assert.deepEqual(input.ends[1], objectEnd(upstream.id, "end"));

  putStaple(document, { ...input, id: "relation:cross-object" });
  assert.equal(validateDocument(document).valid, true);

  const engine = new ChronologEngine(document);
  const upstreamExtent = resolveObjectExtent(document, engine, upstream.id);
  const downstreamExtent = resolveObjectExtent(document, engine, downstream.id);
  assert.equal(
    downstreamExtent.startDays.compare(upstreamExtent.endDays), 0,
    "the downstream event starts exactly at the upstream event's chosen (end) point"
  );
});

// ---------------------------------------------------------------------------
// The weight readout
// ---------------------------------------------------------------------------

test("the weight readout lists contributing groups in application order with correct before-to-after values", () => {
  const { document, event } = documentWithEvent();
  addFrame(document, { id: "group:a", title: "Group A", traits: ["set", "group"], display: { weight: "w * 2", weightOrder: 0 } });
  addFrame(document, { id: "group:b", title: "Group B", traits: ["set", "group"], display: { weight: "w + 1", weightOrder: 1 } });
  addRelation(document, { type: "attachment", event: event.id, frame: "group:a", role: "member" });
  addRelation(document, { type: "attachment", event: event.id, frame: "group:b", role: "member" });
  const engine = new ChronologEngine(document);

  const model = weightReadoutModel(explainFactWeight({ document, engine }, { event }));
  assert.equal(model.base, 1);
  assert.equal(model.baseVerdict, "standard");
  assert.deepEqual(model.rows.map((row) => row.title), ["Group A", "Test calendar", "Group B"],
    "application order, not authored/iteration order");
  assert.deepEqual(model.rows.map((row) => row.formula), ["w * 2", "w", "w + 1"]);
  assert.equal(model.rows[0].from, 1);
  assert.equal(model.rows[0].to, 2);
  assert.equal(model.rows[1].from, 2, "the second row's 'before' is the first row's 'after'");
  assert.equal(model.rows[1].to, 2, "no authored weight on the calendar frame -- identity, not a no-op that vanishes from the list");
  assert.equal(model.rows[2].from, 2);
  assert.equal(model.rows[2].to, 3);
  assert.equal(model.final, 3);
  assert.equal(model.verdict, "important");
});

// ---------------------------------------------------------------------------
// The rendered card: no start-date/start-time control, "Visible in" gone
// ---------------------------------------------------------------------------

// A minimal but real-enough stub DOM: `innerHTML` actually parses into a tree
// (copied from test/dock-card-refresh.test.js's `MiniNode`), extended with
// just enough of `HTMLFormElement`'s surface (`.elements`, settable
// `.value`/`.checked`, `#id`/`.closest` lookups, `classList.toggle`) to open
// the real event editor and submit it for real. `dispatch(type, {target})`
// (test/dock-dom.test.js's own established pattern) is how a delegated
// listener on an ancestor is driven, since this stub does not bubble events.
function createFormDom() {
  const VOID_TAGS = new Set(["input", "br", "img", "hr"]);
  function unescapeHTML(value) {
    return String(value).replace(/&quot;/g, '"').replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
  }

  class MiniNode {
    constructor(tag) {
      this.tagName = String(tag || "div").toUpperCase();
      this.attrs = new Map();
      this.children = [];
      this.parentElement = null;
      this.handlers = new Map();
      this.textContent = "";
      this._value = undefined;
      this._checked = undefined;
      this.hidden = false;
    }
    get className() { return this.attrs.get("class") || ""; }
    set className(value) { this.attrs.set("class", value); }
    get classList() {
      const node = this;
      return {
        toggle(cls, force) {
          const has = String(node.className || "").split(/\s+/).includes(cls);
          const want = force === undefined ? !has : force;
          const parts = new Set(String(node.className || "").split(/\s+/).filter(Boolean));
          if (want) parts.add(cls); else parts.delete(cls);
          node.className = [...parts].join(" ");
        }
      };
    }
    get dataset() {
      const data = {};
      for (const [key, value] of this.attrs) {
        if (!key.startsWith("data-")) continue;
        data[key.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = value;
      }
      return data;
    }
    get type() { return this.attrs.get("type") || ""; }
    get value() {
      if (this._value !== undefined) return this._value;
      if (this.tagName === "SELECT") {
        const options = this.children.filter((c) => c.tagName === "OPTION");
        const selected = options.find((o) => o.attrs.get("selected") !== undefined);
        return (selected || options[0])?.attrs.get("value") ?? "";
      }
      if (this.tagName === "TEXTAREA") {
        return this.descendants().filter((n) => n.tagName === "#TEXT").map((n) => n.textContent).join("");
      }
      return this.attrs.get("value") ?? "";
    }
    set value(v) { this._value = String(v); }
    get checked() { return this._checked !== undefined ? this._checked : this.attrs.has("checked"); }
    set checked(v) { this._checked = Boolean(v); }
    get placeholder() { return this.attrs.get("placeholder") || ""; }
    set placeholder(v) { this.attrs.set("placeholder", String(v)); }
    get elements() {
      const map = {};
      for (const node of this.descendants()) {
        const name = node.attrs.get("name");
        if (name && !(name in map)) map[name] = node;
      }
      return map;
    }
    setAttribute(name, value) { this.attrs.set(name, String(value)); }
    getAttribute(name) { return this.attrs.has(name) ? this.attrs.get(name) : null; }
    addEventListener(type, handler) { if (!this.handlers.has(type)) this.handlers.set(type, []); this.handlers.get(type).push(handler); }
    dispatch(type, event = {}) { for (const handler of this.handlers.get(type) || []) handler({ preventDefault() {}, target: this, ...event }); }
    append(...nodes) { for (const node of nodes) { node.parentElement = this; this.children.push(node); } }
    replaceChildren(...nodes) { this.children = []; this.append(...nodes); }
    descendants() { return this.children.flatMap((child) => [child, ...child.descendants()]); }
    matchesSimple(selector) {
      const idMatch = /^#([a-zA-Z0-9_-]+)$/.exec(selector);
      if (idMatch) return this.attrs.get("id") === idMatch[1];
      const attrMatch = /^\[([a-zA-Z0-9_-]+)(?:="([^"]*)")?\]$/.exec(selector);
      if (attrMatch) {
        const [, name, attrValue] = attrMatch;
        if (!this.attrs.has(name)) return false;
        return attrValue === undefined || this.attrs.get(name) === attrValue;
      }
      return false;
    }
    closest(selector) {
      let node = this;
      while (node) { if (node.matchesSimple(selector)) return node; node = node.parentElement; }
      return null;
    }
    querySelector(selector) { return this.descendants().find((node) => node.matchesSimple(selector)) || null; }
    querySelectorAll(selector) { return this.descendants().filter((node) => node.matchesSimple(selector)); }
    get innerHTML() { return this._html || ""; }
    set innerHTML(value) {
      this._html = value;
      this.children = parseFragment(value);
      for (const child of this.children) child.parentElement = this;
    }
  }

  function parseFragment(html) {
    const root = new MiniNode("root");
    const stack = [root];
    const tagRe = /<\/([a-zA-Z][a-zA-Z0-9-]*)>|<([a-zA-Z][a-zA-Z0-9-]*)([^>]*)>|([^<]+)/g;
    let match;
    while ((match = tagRe.exec(html))) {
      const [, closeTag, openTag, rawAttrs, text] = match;
      if (closeTag) {
        for (let i = stack.length - 1; i > 0; i--) {
          if (stack[i].tagName === closeTag.toUpperCase()) { stack.length = i; break; }
        }
      } else if (openTag) {
        const selfClose = /\/\s*$/.test(rawAttrs || "");
        const node = new MiniNode(openTag);
        const attrRe = /([a-zA-Z_:][-a-zA-Z0-9_:.]*)(?:\s*=\s*"([^"]*)")?/g;
        let attrMatch;
        while ((attrMatch = attrRe.exec((rawAttrs || "").replace(/\/\s*$/, "")))) {
          node.attrs.set(attrMatch[1], attrMatch[2] !== undefined ? unescapeHTML(attrMatch[2]) : "");
        }
        stack[stack.length - 1].append(node);
        if (!VOID_TAGS.has(openTag.toLowerCase()) && !selfClose) stack.push(node);
      } else if (text !== undefined && text.trim().length) {
        const t = new MiniNode("#text");
        t.textContent = unescapeHTML(text);
        stack[stack.length - 1].append(t);
      }
    }
    return root.children;
  }

  class FakeFormData {
    constructor(form) { this.form = form; }
    get(name) {
      const el = this.form.elements[name];
      if (!el) return null;
      if (el.tagName === "INPUT" && el.type === "checkbox") return el.checked ? (el.value || "on") : null;
      return el.value ?? null;
    }
    getAll(name) {
      return this.form.querySelectorAll(`[name="${name}"]`)
        .filter((el) => el.tagName !== "INPUT" || el.type !== "checkbox" || el.checked)
        .map((el) => el.value);
    }
  }

  return { MiniNode, FakeFormData };
}

// Builds the editor's own `app` object against a real engine and real
// undo/journalling (`createTransactions`), without opening any card -- the
// shared base for `openFormHarness` (below) and the quick-creation test,
// which needs `createEventAt` rather than an already-existing event.
function buildEditorApp(document, activeFrame = "calendar:test") {
  const { MiniNode, FakeFormData } = createFormDom();
  const previous = {
    document: globalThis.document,
    FormData: globalThis.FormData,
    requestAnimationFrame: globalThis.requestAnimationFrame,
    HTMLInputElement: globalThis.HTMLInputElement
  };
  globalThis.document = { createElement: (tag) => new MiniNode(tag) };
  globalThis.FormData = FakeFormData;
  globalThis.requestAnimationFrame = (fn) => fn(0);
  // `focusInspectorEditor` (a freshly-created draft's own focus call) checks
  // `instanceof HTMLInputElement`, which Node has no host definition for --
  // stand `MiniNode` in for it so a stub `<input>` satisfies the check the
  // way a real one would, rather than skipping the codepath entirely.
  globalThis.HTMLInputElement = MiniNode;
  const engine = new ChronologEngine(document);
  let cardBody = null;
  const app = {
    chronolog: document,
    engine,
    history: new CommandHistory(document, () => {}),
    session: {
      inspector: null,
      activeFrame,
      currentLens: () => "tactical",
      intimateGrain: 30,
      law: coordinateLaw(document, activeFrame)
    },
    openDockCard(options) { cardBody = options.body; },
    dockIsOpen: () => true,
    closeDockCard() {},
    dockCardBody: () => cardBody,
    toast(message) { app.lastToast = message; },
    store: { beginDeferred() {}, endDeferred() {} },
    refreshEngine(documentValue) { app.engine.setDocument(documentValue); return app.engine; }
  };
  Object.assign(app, createTransactions(app));
  const inspector = createInspector(app);
  const restore = () => Object.assign(globalThis, previous);
  return { app, inspector, getCardBody: () => cardBody, restore };
}

function openFormHarness(document, eventId) {
  const { app, inspector, getCardBody, restore } = buildEditorApp(document);
  inspector.openEventInspector(eventId);
  return { app, cardBody: getCardBody(), restore };
}

test("there is no start-date or start-time control in the card; the staple list is the only placement interface", () => {
  const { document, event } = documentWithEvent();
  event.display = { lenses: ["intimate", "tactical"] };
  const { cardBody, restore } = openFormHarness(document, event.id);
  try {
    assert.equal(cardBody.querySelector('[name="startDate"]'), null);
    assert.equal(cardBody.querySelector('[name="startTime"]'), null);
    assert.equal(cardBody.querySelector("[data-object-date-label]"), null);
    assert.equal(cardBody.querySelector("[data-object-time-label]"), null);
    assert.equal(cardBody.querySelector('[name="visibility"]'), null, "the 'Visible in' select is gone from the rendered card");
    // No date/time pair anywhere in the staple Add control either -- the
    // single coordinate field replaces it everywhere, not just on Start.
    assert.equal(cardBody.querySelector('[name="stapleDate"]'), null);
    assert.equal(cardBody.querySelector('[name="stapleTime"]'), null);
    assert.equal(cardBody.querySelector('[name="endStapleDate"]'), null);
    assert.equal(cardBody.querySelector('[name="endStapleTime"]'), null);
    assert.ok(cardBody.querySelector('[name="stapleCoordinate"]'), "the one coordinate field exists");

    const order = cardBody.descendants();
    const recurrenceIndex = order.indexOf(cardBody.querySelector("[data-recurrence-row]"));
    const staplesIndex = order.indexOf(cardBody.querySelector("[data-staples-section]"));
    const groupsIndex = order.indexOf(cardBody.querySelector("[data-groups-field]"));
    assert.ok(recurrenceIndex >= 0 && staplesIndex >= 0 && groupsIndex >= 0, "all three landmarks render");
    assert.ok(recurrenceIndex < staplesIndex, "staples section is below the recurrence rows");
    assert.ok(staplesIndex < groupsIndex, "staples section is above the Groups field");
  } finally {
    restore();
  }
});

test("saving through the editor leaves an event's already-authored display.lenses untouched", () => {
  const { document, event } = documentWithEvent();
  event.display = { lenses: ["intimate", "tactical"] };
  const { cardBody, restore } = openFormHarness(document, event.id);
  try {
    cardBody.dispatch("submit", {});
    assert.deepEqual(document.events[event.id].display.lenses, ["intimate", "tactical"],
      "existing authored data is not destroyed by a control that no longer exists");
  } finally {
    restore();
  }
});

test("the weight readout renders inside the card, near the color row, not as a control of its own", () => {
  const { document, event } = documentWithEvent();
  const { cardBody, restore } = openFormHarness(document, event.id);
  try {
    const readout = cardBody.querySelector("[data-weight-readout]");
    assert.ok(readout, "the weight readout renders");
    assert.equal(readout.querySelectorAll("input, select, textarea, button").length, 0, "read-only -- no inputs of its own");
  } finally {
    restore();
  }
});

// ---------------------------------------------------------------------------
// THE BUG DIES: an end anchor plus a duration places the event, no error
// ---------------------------------------------------------------------------

test("OWNER'S BUG, as a test: an end anchor at 17:00 plus a 180-minute duration places the event with no start coordinate typed, through the editor's own submit path", () => {
  const document = createStructuralDocument();
  addFrame(document, { id: "calendar:test", title: "Test calendar", traits: ["set", "calendar"], basis: "frame:wall-time" });
  const event = addEvent(document, {
    id: "event:end-anchored",
    traits: ["event"],
    magnitudes: { duration: durationMagnitude("180", "minute") },
    payload: { title: "End-anchored shift" }
  });
  // Bare frame membership -- no coordinate at all. This is exactly what the
  // owner's bug used to delete for lack of a typed start.
  addRelation(document, { id: "relation:membership", type: "attachment", event: event.id, frame: "calendar:test", role: "placed" });

  const law = coordinateLaw(document, "calendar:test");
  const input = buildStapleInput({
    scope: "object", targetId: event.id, kind: "anchor", nearPoint: "end",
    farScope: "frame", farId: "calendar:test", coordinateText: "2026-02-10 17:00", law
  });
  const { app } = appFor(document);
  app.executeEventChange("Add staple", event.id, (documentValue) => putStaple(documentValue, input));

  const engineBefore = new ChronologEngine(document);
  const expectedEnd = engineBefore.coordinateDays("calendar:test", civil(2026, 2, 10, 17, 0, 0));
  const expectedStart = expectedEnd.sub(Rational.parse(180).div(1440));

  // Drive the real editor's own submit path -- no start field exists to type
  // into, and Save must not throw "start time is null" or delete the
  // membership relation for lack of a coordinate.
  const { cardBody, app: editorApp, restore } = openFormHarness(document, event.id);
  try {
    cardBody.dispatch("submit", {});
    assert.equal(editorApp.lastToast, undefined, "no error toast -- the owner's exact bug is gone");
  } finally {
    restore();
  }

  assert.ok(document.relations["relation:membership"], "the frame membership survives with no coordinate typed");
  assert.equal(document.relations["relation:membership"].coordinate, undefined);

  const engineAfter = new ChronologEngine(document);
  const extent = resolveObjectExtent(document, engineAfter, event.id);
  assert.equal(extent.startDays.compare(expectedStart), 0, "exact Rational start, 3 hours before the 17:00 end anchor");
  assert.equal(extent.endDays.compare(expectedEnd), 0);

  const facts = engineAfter.queryFacts({
    frame: "calendar:test", start: civil(2026, 2, 1), end: civil(2026, 2, 20), limit: 50
  }).facts;
  const fact = facts.find((item) => item.event.id === event.id);
  assert.ok(fact, "the event is a real, visible fact on its calendar frame -- no error, no missing event");
  assert.equal(Rational.parse(fact.day).compare(expectedStart), 0);
});

// ---------------------------------------------------------------------------
// Quick creation stays quick: one row, nothing more
// ---------------------------------------------------------------------------

test("quick creation: one typed coordinate yields exactly one effective staple row", () => {
  const document = createStructuralDocument();
  addFrame(document, { id: "calendar:test", title: "Test calendar", traits: ["set", "calendar"], basis: "frame:wall-time" });
  const { app, inspector, restore } = buildEditorApp(document);
  try {
    inspector.createEventAt("10", "11");
    const eventId = Object.keys(document.events)[0];
    assert.ok(eventId, "the event was created");
    const rows = effectiveObjectStaples(document, eventId);
    assert.equal(rows.length, 1, "one row, no extra ceremony");
    assert.equal(rows[0].implicit, true);
  } finally {
    restore();
  }
  assert.equal(app.chronolog, document);
});

// ---------------------------------------------------------------------------
// Editing/removing the implicit placement row
// ---------------------------------------------------------------------------

test("editing the implicit placement row updates the attachment relation directly and mints no staple; removing it leaves the object placed by its remaining staples", () => {
  const { document, event } = documentWithEvent();
  const relationCountBefore = Object.keys(document.relations).length;
  const { cardBody, restore } = openFormHarness(document, event.id);
  try {
    const stapleListEl = cardBody.querySelector("[data-staple-list]");
    const implicitRow = stapleListEl.querySelector("[data-staple-row]");
    assert.equal(implicitRow.dataset.implicit, "true", "the implicit row renders first");

    const coordinateInput = implicitRow.querySelector("[data-row-coordinate]");
    coordinateInput.value = "2026-03-01 09:00";
    stapleListEl.dispatch("change", { target: coordinateInput });

    assert.equal(Object.keys(document.relations).length, relationCountBefore, "no staple record was minted");
    const editedRelation = document.relations["relation:test-placed"];
    const engine1 = new ChronologEngine(document);
    assert.equal(
      engine1.coordinateDays("calendar:test", editedRelation.coordinate)
        .compare(engine1.coordinateDays("calendar:test", civil(2026, 3, 1, 9, 0, 0))),
      0,
      "the attachment relation's own coordinate was patched"
    );

    // An explicit staple, authored directly (bypassing the Add control,
    // which is exercised elsewhere), so the object stays placed once the
    // implicit reading is removed.
    putStaple(document, {
      id: "relation:explicit-anchor",
      kind: "anchor",
      ends: [objectEnd(event.id, "start"), frameEnd("calendar:test", civil(2026, 3, 5, 8, 0, 0))]
    });

    const refreshedList = cardBody.querySelector("[data-staple-list]");
    const rows = refreshedList.querySelectorAll("[data-staple-row]");
    const implicitRowAfter = rows.find((row) => row.dataset.implicit === "true");
    const removeButton = implicitRowAfter.querySelector("[data-remove-staple]");
    refreshedList.dispatch("click", { target: removeButton });
  } finally {
    restore();
  }

  const relation = document.relations["relation:test-placed"];
  assert.equal(relation.coordinate, undefined, "the placement coordinate is gone");
  assert.equal(relation.parameters, undefined);
  assert.ok(document.relations[relation.id], "the attachment relation itself (frame membership) survives");
  const engine = new ChronologEngine(document);
  const extent = resolveObjectExtent(document, engine, event.id);
  assert.equal(extent.source, "anchor+magnitude", "placed by its remaining explicit staple now");
  assert.equal(
    extent.startDays.compare(engine.coordinateDays("calendar:test", civil(2026, 3, 5, 8, 0, 0))),
    0
  );
});

// ---------------------------------------------------------------------------
// The following rule (LEXICON's Rob-and-John, second half)
// ---------------------------------------------------------------------------
//
// "At that decision they place a staple at the inflection point defining an end
// to the initial series rule, then either define a new rule post-staple or a
// new series, on preference."
//
// The substrate has always been able to carry a following rule; the editor's
// job here is authoring it through the same single coordinate field the rest
// of the card uses -- "New rule starts" is one field, not a date/time pair
// either.

test("an inflection staple authored with a following rule carries that rule head", () => {
  const law = coordinateLaw(createStructuralDocument(), "frame:wall-time");
  const input = buildStapleInput({
    scope: "series", targetId: "pattern:test", kind: "inflection",
    farScope: "frame", farId: "frame:wall-time", coordinateText: "2032-03-01", law,
    ruleRepeat: "WEEKLY", ruleInterval: "1", ruleCoordinateText: "2032-03-04 12:00", ruleLaw: law,
    ruleDurationAmount: "45", ruleDurationUnit: "minute"
  });
  assert.equal(input.kind, "inflection");
  assert.equal(input.payload.rule.rrule.FREQ, "WEEKLY");
  assert.equal(input.payload.rule.rrule.INTERVAL, "1");
  // The following rule gets its OWN start, not the staple's instant -- the new
  // meeting is a Thursday lunch, not the old Monday 6:15.
  assert.ok(input.payload.rule.coordinate, "the rule head carries its own base coordinate");
  assert.equal(input.payload.rule.frame, "frame:wall-time");
  assert.equal(input.payload.rule.magnitude.value.levels[0].value, "45");
});

test("the weekdays preset expands to BYDAY in a following rule, as the main repeat control does", () => {
  const law = coordinateLaw(createStructuralDocument(), "frame:wall-time");
  const input = buildStapleInput({
    scope: "series", targetId: "pattern:test", kind: "inflection",
    farScope: "frame", farId: "frame:wall-time", coordinateText: "2032-03-01", law,
    ruleRepeat: "WEEKDAYS", ruleCoordinateText: "2032-03-04", ruleLaw: law
  });
  assert.equal(input.payload.rule.rrule.FREQ, "WEEKLY");
  assert.equal(input.payload.rule.rrule.BYDAY, "MO,TU,WE,TH,FR");
});

test("leaving the following rule blank makes the inflection staple simply end the series", () => {
  const law = coordinateLaw(createStructuralDocument(), "frame:wall-time");
  const input = buildStapleInput({
    scope: "series", targetId: "pattern:test", kind: "inflection",
    farScope: "frame", farId: "frame:wall-time", coordinateText: "2032-03-01", law, ruleRepeat: ""
  });
  assert.equal(input.payload?.rule, undefined, "no rule follows -- the other preference, authored by omission");
});

test("a kind that cannot carry a rule ignores the rule fields entirely", () => {
  // Registry-driven: `end` has carriesRule false, so rule fields submitted
  // against it are not quietly attached to a record whose kind would then fail
  // validation (src/model.js refuses payload.rule on a non-carriesRule kind).
  const law = coordinateLaw(createStructuralDocument(), "frame:wall-time");
  const input = buildStapleInput({
    scope: "series", targetId: "pattern:test", kind: "end",
    farScope: "frame", farId: "frame:wall-time", coordinateText: "2032-03-01", law,
    ruleRepeat: "WEEKLY", ruleCoordinateText: "2032-03-04"
  });
  assert.equal(input.payload?.rule, undefined);
});

test("a following rule authored through the editor really re-rules the series", () => {
  // The end-to-end closure: the editor's own decision function -> putStaple ->
  // the engine's segmented projection. A Monday series becomes Thursday lunches
  // after the staple, on ONE pattern identity, with no code path a user cannot
  // reach from the card.
  const document = createStructuralDocument();
  const source = [
    "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Test//EN",
    "BEGIN:VEVENT",
    "UID:mondays@example.test",
    "DTSTART:20260105T061500Z",
    "RRULE:FREQ=WEEKLY;BYDAY=MO",
    "SUMMARY:Monday meeting",
    "DURATION:PT15M",
    "END:VEVENT", "END:VCALENDAR", ""
  ].join("\r\n");
  const imported = importICS(source, document, { label: "Work" });
  const frame = document.frames[imported.frames[0]];
  const pattern = Object.values(document.patterns).find((item) => item.kind === "ics-rrule");
  const law = coordinateLaw(document, frame.id);

  const input = buildStapleInput({
    scope: "series",
    targetId: pattern.id,
    kind: "inflection",
    farScope: "frame",
    farId: frame.id,
    coordinateText: "2026-02-02 23:59",
    law,
    ruleRepeat: "WEEKLY",
    ruleInterval: "1",
    ruleCoordinateText: "2026-02-05 12:00",
    ruleLaw: law,
    ruleDurationAmount: "45",
    ruleDurationUnit: "minute"
  });
  putStaple(document, { ...input, id: "relation:inflection" });
  assert.equal(validateDocument(document).valid, true, "the authored record validates");

  const weekdayOf = (fact) => Number(
    new Rational(Rational.parse(fact.day).floor()).add(4).mod(7).toJSON()
  );
  const facts = new ChronologEngine(document).queryFacts({
    frame: frame.id,
    start: coordinate([{ level: "year", value: "2026" }, { level: "month", value: "1" }, { level: "day", value: "1" }]),
    end: coordinate([{ level: "year", value: "2026" }, { level: "month", value: "3" }, { level: "day", value: "15" }]),
    limit: 200
  }).facts.filter((fact) => fact.kind === "virtual");

  // The cut is the staple's own instant, resolved exactly -- never compared as
  // coordinate text, since the ICS-imported rule and the editor-authored staple
  // spell the same instant differently ("01" vs "1").
  const cut = new ChronologEngine(document).coordinateDays(frame.id, input.ends[1].coordinate);
  const before = facts.filter((fact) => Rational.parse(fact.day).compare(cut) <= 0);
  const after = facts.filter((fact) => Rational.parse(fact.day).compare(cut) > 0);

  assert.ok(before.length >= 4, "the original Monday rule projected before the staple");
  assert.ok(after.length >= 4, "a new rule projects after the staple");
  assert.deepEqual([...new Set(before.map(weekdayOf))], [1], "everything before the staple is a Monday");
  assert.deepEqual([...new Set(after.map(weekdayOf))], [4], "everything after it is a Thursday");
  // One identity, not two series (the whole point of the ruling).
  assert.deepEqual(
    [...new Set(facts.map((fact) => fact.event.provenance.pattern))],
    [pattern.id],
    "both segments are the same series"
  );

  // And removing it restores the original projection unconditionally.
  removeStaple(document, "relation:inflection");
  const restored = new ChronologEngine(document).queryFacts({
    frame: frame.id,
    start: coordinate([{ level: "year", value: "2026" }, { level: "month", value: "1" }, { level: "day", value: "1" }]),
    end: coordinate([{ level: "year", value: "2026" }, { level: "month", value: "3" }, { level: "day", value: "15" }]),
    limit: 200
  }).facts.filter((fact) => fact.kind === "virtual");
  assert.deepEqual([...new Set(restored.map(weekdayOf))], [1], "Mondays all the way again");
});
