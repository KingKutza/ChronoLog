import assert from "node:assert/strict";
import test from "node:test";
import { ChronologEngine } from "../src/engine.js";
import { Rational, coordinate } from "../src/exact.js";
import { GREGORIAN_DECLARATION, coordinateLaw } from "../src/coordinate-law.js";
import {
  addEvent,
  addPattern,
  addRelation,
  createId,
  durationMagnitude,
  frameEnd,
  objectEnd,
  putStaple,
  selectorEnd,
  seriesEnd,
  spanEnd,
  validateDocument,
  voidEnd
} from "../src/model.js";
import { compactDocument } from "../src/store.js";
import {
  describeCorrespondence,
  endPosition,
  endScope,
  endScopePair,
  frameCorrespondences,
  frameEndDays,
  frameEndMatches,
  STAPLE_KINDS,
  stapleEnds,
  stapleKindScopes,
  stapleReferencesId,
  stapleTouchesAny,
  withRemappedEnds
} from "../src/staples.js";
import { createStructuralDocument } from "./helpers/sample-document.js";

// `createStructuralDocument` is a bare canvas -- the structural frames and
// nothing else -- so every test here authors exactly the calendar, events and
// series it needs. Two events, because a connection needs two things.
function workspace() {
  const document = createStructuralDocument();
  document.frames["calendar:personal"] = {
    id: "calendar:personal",
    title: "Personal",
    traits: ["set", "calendar"],
    basis: "frame:wall-time"
  };
  const first = addEvent(document, {
    id: "event:first",
    traits: ["event"],
    magnitudes: { duration: durationMagnitude("60", "minute") },
    payload: { title: "First" }
  });
  const firstRelation = addRelation(document, {
    id: "relation:first-placed",
    type: "attachment",
    event: first.id,
    frame: "calendar:personal",
    role: "placed",
    coordinate: wallAt(2026, 8, 20, 9)
  });
  const second = addEvent(document, {
    id: "event:second",
    traits: ["event"],
    magnitudes: { duration: durationMagnitude("30", "minute") },
    payload: { title: "Second" }
  });
  return { document, first, second, firstRelation };
}

function withSeries(document, templateEvent, templateRelation) {
  return addPattern(document, {
    id: "pattern:weekly",
    title: "Weekly",
    language: "chronolog-formula/1",
    kind: "ics-rrule",
    appliesTo: ["calendar:personal"],
    frame: "calendar:personal",
    templateEvent,
    templateRelation,
    rrule: { FREQ: "WEEKLY", INTERVAL: "1" },
    source: "export fn state(ctx) = {};\nexport fn facts(ctx) = [];",
    exports: { state: "state", facts: "facts" }
  });
}

// The Jeremy Bearimy frame: a line that is not monotonic against wall time and
// visits the same wall-time regions more than once. Its own coordinate ladder is
// its own -- strokes and steps, not years and months -- which is the whole point
// of each end carrying its own law: a Bearimy coordinate is meaningless read as
// a date, and a date is meaningless read as a stroke.
function addBearimyFrame(document) {
  document.frames["frame:bearimy"] = {
    id: "frame:bearimy",
    title: "Jeremy Bearimy",
    traits: ["line", "temporal", "nonlinear"],
    coordinate: {
      kind: "nested",
      levels: [
        { name: "stroke" },
        { name: "step", within: "stroke", radix: "8" }
      ]
    }
  };
  return document.frames["frame:bearimy"];
}

function bearimyAt(stroke, step = 0) {
  return coordinate([
    { level: "stroke", value: String(stroke) },
    { level: "step", value: String(step) }
  ]);
}

function wallAt(year, month, day, hour = 0, minute = 0) {
  return coordinate([
    { level: "year", value: String(year) },
    { level: "month", value: String(month) },
    { level: "day", value: String(day) },
    { level: "hour", value: String(hour) },
    { level: "minute", value: String(minute) }
  ]);
}

function correspond(document, bearimyCoordinate, wallCoordinate) {
  return putStaple(document, {
    id: createId("relation"),
    kind: "correspondence",
    ends: [
      frameEnd("frame:bearimy", bearimyCoordinate),
      frameEnd("frame:wall-time", wallCoordinate)
    ]
  });
}

// ---------------------------------------------------------------------------
// The edge itself
// ---------------------------------------------------------------------------

test("a staple carries exactly two ends, and neither end is privileged over the other", () => {
  const { document, first } = workspace();
  const eventId = first.id;
  const staple = putStaple(document, {
    id: createId("relation"),
    kind: "anchor",
    ends: [objectEnd(eventId, "end"), frameEnd("calendar:personal", wallAt(2026, 8, 20, 17))]
  });
  assert.equal(validateDocument(document).valid, true);
  const ends = stapleEnds(staple);
  assert.equal(ends.length, 2);
  assert.deepEqual(ends.map(endScope).sort(), ["frame", "object"]);
  // Reachable from either thing it joins: a connection is as much the frame's
  // record as the object's, which is what every cascade sweep relies on.
  assert.equal(stapleReferencesId(staple, eventId), true);
  assert.equal(stapleReferencesId(staple, "calendar:personal"), true);
  assert.equal(stapleTouchesAny(staple, new Set(["calendar:personal"])), true);
});

test("authoring the ends in the other order describes the identical connection", () => {
  const { document, first } = workspace();
  const eventId = first.id;
  const at = wallAt(2026, 8, 20, 17);
  const forward = putStaple(document, {
    id: createId("relation"),
    kind: "anchor",
    ends: [objectEnd(eventId, "end"), frameEnd("frame:wall-time", at)]
  });
  const reversed = putStaple(document, {
    id: createId("relation"),
    kind: "anchor",
    ends: [frameEnd("frame:wall-time", at), objectEnd(eventId, "end")]
  });
  assert.equal(endScopePair(...stapleEnds(forward).map(endScope)),
    endScopePair(...stapleEnds(reversed).map(endScope)));
  const engine = new ChronologEngine(document);
  // Direction is not stored, so the instant each names is the same instant.
  const forwardDays = frameEndDays(engine, stapleEnds(forward).find((end) => end.frame));
  const reversedDays = frameEndDays(engine, stapleEnds(reversed).find((end) => end.frame));
  assert.equal(forwardDays.compare(reversedDays), 0);
});

test("a staple with one end, three ends, or both ends on one object is refused", () => {
  const { document, first, second } = workspace();
  const eventId = first.id;
  const otherId = second.id;
  const at = wallAt(2026, 8, 20);

  const lonely = putStaple(document, {
    id: createId("relation"),
    kind: "anchor",
    ends: [objectEnd(eventId, "start")]
  });
  assert.match(validateDocument(document).errors.join("\n"), /must connect exactly two things/);
  delete document.relations[lonely.id];

  const crowded = putStaple(document, {
    id: createId("relation"),
    kind: "anchor",
    ends: [objectEnd(eventId, "start"), frameEnd("frame:wall-time", at), objectEnd(otherId, "end")]
  });
  assert.match(validateDocument(document).errors.join("\n"), /must connect exactly two things/);
  delete document.relations[crowded.id];

  // An object's own start-to-end span is its duration magnitude, not a
  // connection -- so stapling an object to itself says nothing.
  putStaple(document, {
    id: createId("relation"),
    kind: "anchor",
    ends: [objectEnd(eventId, "start"), objectEnd(eventId, "end")]
  });
  assert.match(validateDocument(document).errors.join("\n"), /connects one object to itself/);
});

test("a kind is defined by the end-scope PAIR it may join, and refuses any other", () => {
  const { document, first, firstRelation } = workspace();
  const eventId = first.id;
  const patternId = withSeries(document, first.id, firstRelation.id).id;

  // A rule segment is cut at an instant, so an `end` staple reaches a frame and
  // nothing else: connecting a series to an object is not a defined thing.
  assert.deepEqual([...STAPLE_KINDS.end.connects], ["frame+series"]);
  assert.deepEqual([...STAPLE_KINDS.correspondence.connects], ["frame+frame"]);
  assert.equal(STAPLE_KINDS.anchor.connects.includes("object+object"), true);

  putStaple(document, {
    id: createId("relation"),
    kind: "end",
    ends: [seriesEnd(patternId), objectEnd(eventId, "start")]
  });
  assert.match(validateDocument(document).errors.join("\n"), /cannot connect object to series/);
});

test("stapleKindScopes derives a kind's scopes from its connects, so no surface hand-writes a list", () => {
  assert.deepEqual(stapleKindScopes("correspondence"), ["frame"]);
  assert.deepEqual(stapleKindScopes("end"), ["frame", "series"]);
  assert.deepEqual(stapleKindScopes("anchor"), ["frame", "object", "series"]);
  assert.deepEqual(stapleKindScopes("not-a-kind"), []);
});

// ---------------------------------------------------------------------------
// Migration: the flat shape restated, never reinterpreted
// ---------------------------------------------------------------------------

test("a legacy flat staple migrates into a connection naming the identical instant, and validates", () => {
  const { document, first } = workspace();
  const eventId = first.id;
  const at = wallAt(2026, 8, 20, 17);
  const legacyId = createId("relation");
  const offset = { frame: "measure:human-time", value: coordinate([{ level: "minute", value: "45" }]) };
  document.relations[legacyId] = {
    id: legacyId,
    type: "staple",
    kind: "anchor",
    object: eventId,
    role: "shift handover",
    frame: "frame:wall-time",
    coordinate: at,
    parameters: { dateOnly: true },
    payload: { offset }
  };

  const engine = new ChronologEngine(document);
  const before = engine.coordinateDays("frame:wall-time", at);

  compactDocument(document);
  const migrated = document.relations[legacyId];

  assert.equal(validateDocument(document).valid, true);
  assert.equal(migrated.object, undefined);
  assert.equal(migrated.role, undefined);
  assert.equal(migrated.frame, undefined);
  assert.equal(migrated.coordinate, undefined);
  assert.equal(migrated.parameters, undefined);
  // The payload held nothing but the offset, so it goes with it rather than
  // lingering as an empty object.
  assert.equal(migrated.payload, undefined);

  const ends = stapleEnds(migrated);
  const near = ends.find((end) => end.object);
  const far = ends.find((end) => end.frame);
  assert.equal(near.object, eventId);
  assert.equal(near.point, "shift handover");
  assert.deepEqual(near.offset, offset);
  assert.deepEqual(far.coordinate, at);
  assert.deepEqual(far.parameters, { dateOnly: true });

  const after = frameEndDays(new ChronologEngine(document), far);
  assert.equal(after.compare(before), 0);
});

test("a legacy series staple migrates to a series end, and a role-less object staple defaults to its start", () => {
  const { document, first, firstRelation } = workspace();
  const eventId = first.id;
  const patternId = withSeries(document, first.id, firstRelation.id).id;
  const at = wallAt(2026, 8, 20);

  const objectStapleId = createId("relation");
  document.relations[objectStapleId] = {
    id: objectStapleId,
    type: "staple",
    kind: "anchor",
    object: eventId,
    frame: "frame:wall-time",
    coordinate: at
  };
  const seriesStapleId = createId("relation");
  document.relations[seriesStapleId] = {
    id: seriesStapleId,
    type: "staple",
    kind: "end",
    series: patternId,
    frame: "frame:wall-time",
    coordinate: at
  };
  compactDocument(document);
  const series = stapleEnds(document.relations[seriesStapleId]).find((end) => end.series);
  assert.equal(series.series, patternId);
  const near = stapleEnds(document.relations[objectStapleId]).find((end) => end.object);
  assert.equal(near.point, "start");
  assert.equal(validateDocument(document).valid, true);
});

test("migration is idempotent: a document this build saved compacts to itself", () => {
  const { document, first } = workspace();
  putStaple(document, {
    id: createId("relation"),
    kind: "anchor",
    ends: [objectEnd(first.id, "end"), frameEnd("frame:wall-time", wallAt(2026, 8, 20, 17))]
  });
  const once = JSON.stringify(compactDocument(document));
  const twice = JSON.stringify(compactDocument(JSON.parse(once)));
  assert.equal(twice, once);
  const report = [];
  compactDocument(JSON.parse(once), report);
  assert.equal(report.some((entry) => entry.kind === "staple-connections"), false);
});

test("migration reports what it restated, so a load can say so without the load failing", () => {
  const { document, first } = workspace();
  const legacyId = createId("relation");
  document.relations[legacyId] = {
    id: legacyId,
    type: "staple",
    kind: "anchor",
    object: first.id,
    role: "end",
    frame: "frame:wall-time",
    coordinate: wallAt(2026, 8, 20, 17)
  };
  const report = [];
  compactDocument(document, report);
  const entry = report.find((item) => item.kind === "staple-connections");
  assert.equal(entry.count, 1);
});

// ---------------------------------------------------------------------------
// Frame to frame: the Jeremy Bearimy correspondence
// ---------------------------------------------------------------------------

test("a correspondence connects two frames, each end a coordinate under its OWN law", () => {
  const { document } = workspace();
  addBearimyFrame(document);
  const dot = bearimyAt(4, 2);
  const staple = correspond(document, dot, wallAt(2026, 8, 18));
  assert.equal(validateDocument(document).valid, true);

  const engine = new ChronologEngine(document);
  const ends = stapleEnds(staple);
  const bearimyLaw = coordinateLaw(document, "frame:bearimy");
  const wallLaw = coordinateLaw(document, "frame:wall-time");

  // Two different laws, and neither coordinate is readable through the other.
  // BOTH are positional: a uniform custom ladder is fully computable from its
  // own radices under bottom-up composition, so the Bearimy frame has a real
  // axis of its own. What it does NOT have is any relation to Earth days --
  // its atom is a pen stroke, which no standard unit shares -- and that is the
  // property that keeps the two ends unreadable through each other.
  assert.equal(bearimyLaw.positional, true);
  assert.equal(bearimyLaw.sharesStandardAtom(), false);
  assert.equal(bearimyLaw.mapsToClock(), false, "a curve of handwriting has no now");
  assert.equal(wallLaw.positional, true);
  assert.equal(wallLaw.mapsToClock(), true);
  assert.deepEqual(bearimyLaw.levelNames(), ["stroke", "step"]);

  const bearimyEnd = ends.find((end) => end.frame === "frame:bearimy");
  const wallEnd = ends.find((end) => end.frame === "frame:wall-time");
  // A non-positional law counts in its OWN base units, so the Bearimy end
  // resolves through the Bearimy ladder and nothing else. Derived from the law
  // rather than written as a literal: the assertion is that the two ends are
  // read under two different laws, not what one ladder's arithmetic happens to
  // come to.
  assert.equal(frameEndDays(engine, bearimyEnd).compare(bearimyLaw.toDays(dot)), 0);
  assert.notEqual(frameEndDays(engine, bearimyEnd).compare(wallLaw.toDays(wallAt(2026, 8, 18))), 0);
  assert.equal(
    frameEndDays(engine, wallEnd).compare(engine.coordinateDays("frame:wall-time", wallAt(2026, 8, 18))),
    0
  );
});

test("one Bearimy point corresponds to many disjoint wall-time points, and every one survives", () => {
  const { document } = workspace();
  addBearimyFrame(document);
  const dot = bearimyAt(4, 2);
  // The dot over the i: every Tuesday, AND July. Disjoint, many-valued, and
  // authored as separate touch points rather than as a range.
  const tuesdays = [wallAt(2026, 8, 4), wallAt(2026, 8, 11), wallAt(2026, 8, 18), wallAt(2026, 8, 25)];
  for (const tuesday of tuesdays) correspond(document, dot, tuesday);
  const july = correspond(document, dot, wallAt(2026, 7, 1));
  assert.equal(validateDocument(document).valid, true);

  const engine = new ChronologEngine(document);
  const entries = frameCorrespondences(document, "frame:bearimy", "frame:wall-time", engine);
  assert.equal(entries.length, 5);
  // Nothing is collapsed, deduplicated, or reduced to one mapped position: the
  // whole set is the answer, because an average of five true answers is a sixth
  // answer nobody authored.
  const targets = entries.map((entry) => frameEndDays(engine, entry.to).toJSON());
  assert.equal(new Set(targets).size, 5);
  assert.equal(entries.some((entry) => entry.staple.id === july.id), true);
  // Every entry is oriented from the frame that was asked about.
  assert.equal(entries.every((entry) => entry.from.frame === "frame:bearimy"), true);
});

test("enumeration is not sorted into monotone order: a correspondence makes no monotonicity claim", () => {
  const { document } = workspace();
  addBearimyFrame(document);
  // Deliberately non-monotonic: later strokes reach earlier wall time.
  correspond(document, bearimyAt(1, 0), wallAt(2026, 9, 1));
  correspond(document, bearimyAt(2, 0), wallAt(2026, 7, 1));
  correspond(document, bearimyAt(3, 0), wallAt(2026, 8, 1));
  assert.equal(validateDocument(document).valid, true);

  const engine = new ChronologEngine(document);
  const entries = frameCorrespondences(document, "frame:bearimy", "frame:wall-time", engine);
  assert.equal(entries.length, 3);
  const sourceDays = entries.map((entry) => frameEndDays(engine, entry.from));
  const targetDays = entries.map((entry) => frameEndDays(engine, entry.to));
  // The order is the substrate's stable relation-id order, so it is not the
  // chronological order of either side. Asserting that at least one side is out
  // of ascending order is what proves nothing sorted them.
  const ascending = (values) => values.every((value, index) => index === 0 || value.compare(values[index - 1]) >= 0);
  assert.equal(ascending(sourceDays) && ascending(targetDays), false);
});

test("a Bearimy stretch with no correspondence corresponds to nothing, and nothing is interpolated for it", () => {
  const { document } = workspace();
  addBearimyFrame(document);
  correspond(document, bearimyAt(1, 0), wallAt(2026, 7, 1));
  correspond(document, bearimyAt(6, 0), wallAt(2026, 9, 1));
  const engine = new ChronologEngine(document);

  const entries = frameCorrespondences(document, "frame:bearimy", "frame:wall-time", engine);
  const gap = frameEndDays(engine, frameEnd("frame:bearimy", bearimyAt(3, 4)));
  // "Sometimes never": the stretch between the two authored points has no
  // correspondence at all, and the two neighbours are not licence to invent one.
  const atGap = entries.filter((entry) => frameEndDays(engine, entry.from).compare(gap) === 0);
  assert.deepEqual(atGap, []);
  assert.equal(entries.length, 2);
});

test("a frame with no correspondences enumerates empty rather than reaching for a neighbour", () => {
  const { document } = workspace();
  addBearimyFrame(document);
  const engine = new ChronologEngine(document);
  assert.deepEqual(frameCorrespondences(document, "frame:bearimy", "frame:wall-time", engine), []);
  assert.deepEqual(frameCorrespondences(document, "frame:wall-time", null, engine), []);
  assert.deepEqual(frameCorrespondences(document, null, null, engine), []);
});

test("a nonlinear frame may correspond to ITSELF at two different points -- a line crossing its own path", () => {
  const { document } = workspace();
  addBearimyFrame(document);
  const crossing = putStaple(document, {
    id: createId("relation"),
    kind: "correspondence",
    ends: [
      frameEnd("frame:bearimy", bearimyAt(2, 0)),
      frameEnd("frame:bearimy", bearimyAt(5, 0))
    ]
  });
  assert.equal(validateDocument(document).valid, true);

  const engine = new ChronologEngine(document);
  // Enumerated from BOTH of its own ends, because either point is a legitimate
  // place to ask the question from.
  const entries = frameCorrespondences(document, "frame:bearimy", "frame:bearimy", engine);
  assert.equal(entries.length, 2);
  assert.equal(new Set(entries.map((entry) => frameEndDays(engine, entry.from).toJSON())).size, 2);

  // The degenerate case says nothing and is refused.
  putStaple(document, {
    id: createId("relation"),
    kind: "correspondence",
    ends: [frameEnd("frame:bearimy", bearimyAt(7, 0)), frameEnd("frame:bearimy", bearimyAt(7, 0))]
  });
  assert.match(validateDocument(document).errors.join("\n"), /connects one point to itself/);
  assert.ok(crossing.id);
});

test("deleting a frame takes its correspondences with it, so no coordinate survives in a space that is gone", () => {
  const { document } = workspace();
  addBearimyFrame(document);
  const staple = correspond(document, bearimyAt(4, 2), wallAt(2026, 8, 18));
  assert.equal(validateDocument(document).valid, true);

  // The cascade's own predicate: both ends count, so the connection is reachable
  // from the frame being removed.
  assert.equal(stapleTouchesAny(staple, new Set(["frame:bearimy"])), true);
  delete document.frames["frame:bearimy"];
  assert.equal(validateDocument(document).valid, false);
  delete document.relations[staple.id];
  assert.equal(validateDocument(document).valid, true);
});

// ---------------------------------------------------------------------------
// Positions: one point is only one of four things an end can name
// ---------------------------------------------------------------------------

test("an end may name a CYCLE position rather than a coordinate: 'Tuesdays' is not one instant", () => {
  const { document } = workspace();
  addBearimyFrame(document);
  const staple = putStaple(document, {
    id: createId("relation"),
    kind: "correspondence",
    ends: [
      frameEnd("frame:bearimy", bearimyAt(4, 2)),
      selectorEnd("frame:wall-time", { cycle: "weekday", value: "Tuesday" })
    ]
  });
  assert.equal(validateDocument(document).valid, true);

  const engine = new ChronologEngine(document);
  const to = stapleEnds(staple).find((end) => end.frame === "frame:wall-time");
  assert.equal(endPosition(to).form, "selector");
  // A selector is many-valued, so asking it for ONE instant must refuse rather
  // than pick an arbitrary Tuesday and call it the answer.
  assert.equal(frameEndDays(engine, to), null);

  const law = coordinateLaw(document, "frame:wall-time");
  // Membership is the question it can answer. 2026-08-18 is a Tuesday;
  // 2026-08-19 is not.
  const tuesday = engine.coordinateDays("frame:wall-time", wallAt(2026, 8, 18));
  const wednesday = engine.coordinateDays("frame:wall-time", wallAt(2026, 8, 19));
  assert.equal(law.weekdayLabel(tuesday), "Tuesday");
  assert.equal(frameEndMatches(law, to, tuesday), true);
  assert.equal(frameEndMatches(law, to, wednesday), false);
});

test("a cycle selector means what THIS frame's declaration says, not the registered names", () => {
  const { document } = workspace();
  document.frames["frame:renamed"] = {
    id: "frame:renamed",
    title: "Renamed week",
    traits: ["line", "temporal", "gregorian"],
    coordinate: {
      ...GREGORIAN_DECLARATION,
      cycles: [{ name: "weekday", radix: "7", offset: "4", names: ["Sun", "Mon", "Batman", "Wed", "Thu", "Fri", "Sat"] }]
    }
  };
  const law = coordinateLaw(document, "frame:renamed");
  const end = selectorEnd("frame:renamed", { cycle: "weekday", value: "Batman" });
  const engine = new ChronologEngine(document);
  const tuesday = engine.coordinateDays("frame:renamed", wallAt(2026, 8, 18));
  assert.equal(law.weekdayLabel(tuesday), "Batman");
  assert.equal(frameEndMatches(law, end, tuesday), true);
  // The registered name for that position is not what this frame declared, so it
  // must not match here.
  assert.equal(frameEndMatches(law, selectorEnd("frame:renamed", { cycle: "weekday", value: "Tuesday" }), tuesday), false);
});

test("an end may name a LEVEL position: July is every July, by the frame's own level names", () => {
  const { document } = workspace();
  addBearimyFrame(document);
  putStaple(document, {
    id: createId("relation"),
    kind: "correspondence",
    ends: [
      frameEnd("frame:bearimy", bearimyAt(4, 2)),
      selectorEnd("frame:wall-time", { level: "month", value: "July" })
    ]
  });
  assert.equal(validateDocument(document).valid, true);
  const law = coordinateLaw(document, "frame:wall-time");
  const engine = new ChronologEngine(document);
  const end = selectorEnd("frame:wall-time", { level: "month", value: "July" });
  assert.equal(frameEndMatches(law, end, engine.coordinateDays("frame:wall-time", wallAt(2026, 7, 4))), true);
  assert.equal(frameEndMatches(law, end, engine.coordinateDays("frame:wall-time", wallAt(2027, 7, 30))), true);
  assert.equal(frameEndMatches(law, end, engine.coordinateDays("frame:wall-time", wallAt(2026, 8, 4))), false);
  // The numeric spelling of the same level position agrees with the named one.
  const numeric = selectorEnd("frame:wall-time", { level: "month", value: "7" });
  assert.equal(frameEndMatches(law, numeric, engine.coordinateDays("frame:wall-time", wallAt(2026, 7, 4))), true);
});

test("a selector naming a cycle or level the frame never declared is refused, not silently matched forever", () => {
  const { document } = workspace();
  addBearimyFrame(document);
  // The Bearimy frame declares strokes and steps, and no cycles at all.
  putStaple(document, {
    id: createId("relation"),
    kind: "correspondence",
    ends: [
      selectorEnd("frame:bearimy", { cycle: "weekday", value: "Tuesday" }),
      frameEnd("frame:wall-time", wallAt(2026, 8, 18))
    ]
  });
  assert.match(validateDocument(document).errors.join("\n"), /does not declare/);
});

test("an end declares exactly one position: none is incomplete, two is two claims in one record", () => {
  const { document } = workspace();
  addBearimyFrame(document);
  const bare = putStaple(document, {
    id: createId("relation"),
    kind: "correspondence",
    ends: [{ frame: "frame:bearimy" }, frameEnd("frame:wall-time", wallAt(2026, 8, 18))]
  });
  assert.match(validateDocument(document).errors.join("\n"), /needs a position/);
  delete document.relations[bare.id];

  putStaple(document, {
    id: createId("relation"),
    kind: "correspondence",
    ends: [
      { frame: "frame:bearimy", coordinate: bearimyAt(4, 2), selector: { level: "step", value: "2" } },
      frameEnd("frame:wall-time", wallAt(2026, 8, 18))
    ]
  });
  assert.match(validateDocument(document).errors.join("\n"), /exactly one position/);
});

test("'sometimes never' is authored as a VOID end, which is a different claim from an absent staple", () => {
  const { document } = workspace();
  addBearimyFrame(document);
  // A stretch of the Bearimy that corresponds to nothing in wall time. Both
  // things are still named -- this stretch, and wall time -- so it stays an edge
  // rather than becoming a one-ended staple.
  const staple = putStaple(document, {
    id: createId("relation"),
    kind: "correspondence",
    ends: [
      spanEnd("frame:bearimy", bearimyAt(2, 0), bearimyAt(5, 0)),
      voidEnd("frame:wall-time")
    ]
  });
  assert.equal(validateDocument(document).valid, true);

  const engine = new ChronologEngine(document);
  const ends = stapleEnds(staple);
  const span = ends.find((end) => end.span);
  const nothing = ends.find((end) => end.void);
  assert.equal(endPosition(span).form, "span");
  assert.equal(endPosition(nothing).form, "void");

  const bearimyLaw = coordinateLaw(document, "frame:bearimy");
  const wallLaw = coordinateLaw(document, "frame:wall-time");
  // The span is a region and matches by containment; the void matches nothing,
  // which is the whole content of the claim.
  const inside = bearimyLaw.toDays(bearimyAt(3, 4));
  const outside = bearimyLaw.toDays(bearimyAt(6, 0));
  assert.equal(frameEndMatches(bearimyLaw, span, inside), true);
  assert.equal(frameEndMatches(bearimyLaw, span, outside), false);
  assert.equal(frameEndMatches(wallLaw, nothing, Rational.parse(0)), false);
  assert.equal(frameEndDays(engine, nothing), null);
  assert.equal(frameEndDays(engine, span), null);

  // An authored void is enumerated -- it is a statement in the correspondence,
  // not a hole in it.
  const described = describeCorrespondence(document, "frame:bearimy", "frame:wall-time", engine);
  assert.equal(described.voids, 1);
  assert.equal(described.points, 0);
  assert.equal(described.cardinality, "empty");
});

// ---------------------------------------------------------------------------
// Set-level claims: derived from the staples, never stored beside them
// ---------------------------------------------------------------------------

test("cardinality, monotonicity and coverage are DERIVED from the set, so they cannot contradict it", () => {
  const { document } = workspace();
  addBearimyFrame(document);
  const dot = bearimyAt(4, 2);
  correspond(document, dot, wallAt(2026, 8, 4));
  correspond(document, dot, wallAt(2026, 8, 11));
  correspond(document, dot, wallAt(2026, 7, 1));
  const engine = new ChronologEngine(document);

  const described = describeCorrespondence(document, "frame:bearimy", "frame:wall-time", engine);
  assert.equal(described.points, 3);
  // One Bearimy point, three wall-time points: one-to-many, read off the set.
  assert.equal(described.cardinality, "one-to-many");
  // Three targets for one source is not an ordering, so monotonicity is not
  // decidable -- null, never a confident `true`.
  assert.equal(described.monotonic, null);
  assert.equal(described.voids, 0);

  // No record anywhere stores any of this: the claim lives in exactly one place,
  // which is the staples themselves.
  for (const relation of Object.values(document.relations)) {
    assert.equal(relation.cardinality, undefined);
    assert.equal(relation.monotonic, undefined);
    assert.equal(relation.coverage, undefined);
  }
});

test("a genuinely non-monotonic set reports monotonic false, and a rising one reports true", () => {
  const { document } = workspace();
  addBearimyFrame(document);
  correspond(document, bearimyAt(1, 0), wallAt(2026, 9, 1));
  correspond(document, bearimyAt(2, 0), wallAt(2026, 7, 1));
  correspond(document, bearimyAt(3, 0), wallAt(2026, 8, 1));
  let engine = new ChronologEngine(document);
  assert.equal(describeCorrespondence(document, "frame:bearimy", "frame:wall-time", engine).monotonic, false);

  const rising = workspace().document;
  addBearimyFrame(rising);
  correspond(rising, bearimyAt(1, 0), wallAt(2026, 7, 1));
  correspond(rising, bearimyAt(2, 0), wallAt(2026, 8, 1));
  correspond(rising, bearimyAt(3, 0), wallAt(2026, 9, 1));
  engine = new ChronologEngine(rising);
  assert.equal(describeCorrespondence(rising, "frame:bearimy", "frame:wall-time", engine).monotonic, true);
});

test("a set carrying a many-valued position cannot be called monotone at all", () => {
  const { document } = workspace();
  addBearimyFrame(document);
  correspond(document, bearimyAt(1, 0), wallAt(2026, 7, 1));
  putStaple(document, {
    id: createId("relation"),
    kind: "correspondence",
    ends: [
      frameEnd("frame:bearimy", bearimyAt(4, 2)),
      selectorEnd("frame:wall-time", { cycle: "weekday", value: "Tuesday" })
    ]
  });
  const engine = new ChronologEngine(document);
  const described = describeCorrespondence(document, "frame:bearimy", "frame:wall-time", engine);
  assert.equal(described.manyValued, 1);
  assert.equal(described.monotonic, null, "a selector has no single position to be monotone against");
  assert.equal(described.count, 2, "and it is still enumerated -- refusing to order it is not refusing to carry it");
});

// ---------------------------------------------------------------------------
// Authored precision survives into the fact
// ---------------------------------------------------------------------------

test("authored coordinate depth reaches the fact, so a bare year is not indistinguishable from January 1st", () => {
  const { document } = workspace();
  // Two events on the same instant, authored at different depths: one says
  // "1973", the other says "1973-01-01 00:00".
  const vague = addEvent(document, {
    id: "event:vague",
    traits: ["event"],
    magnitudes: { duration: durationMagnitude("0") },
    payload: { title: "Sometime in 1973" }
  });
  addRelation(document, {
    id: "relation:vague",
    type: "attachment",
    event: vague.id,
    frame: "calendar:personal",
    role: "placed",
    coordinate: coordinate([{ level: "year", value: "1973" }])
  });
  const exact = addEvent(document, {
    id: "event:exact",
    traits: ["event"],
    magnitudes: { duration: durationMagnitude("0") },
    payload: { title: "New Year's Day 1973" }
  });
  addRelation(document, {
    id: "relation:exact",
    type: "attachment",
    event: exact.id,
    frame: "calendar:personal",
    role: "placed",
    coordinate: wallAt(1973, 1, 1, 0, 0)
  });
  assert.equal(validateDocument(document).valid, true);

  const engine = new ChronologEngine(document);
  const facts = engine.indexedExplicitFacts("calendar:personal");
  const vagueFact = facts.find((entry) => entry.fact.event.id === vague.id).fact;
  const exactFact = facts.find((entry) => entry.fact.event.id === exact.id).fact;

  // They resolve to the same instant -- the law supplies the missing levels --
  // which is exactly why the depth has to travel separately.
  assert.equal(Rational.parse(vagueFact.day).compare(Rational.parse(exactFact.day)), 0);
  assert.equal(vagueFact.precision, "year");
  assert.equal(exactFact.precision, "minute");
});

test("an anchored event's precision comes from the coordinate its own connection was authored at", () => {
  const { document, second } = workspace();
  addRelation(document, {
    id: "relation:second-member",
    type: "attachment",
    event: second.id,
    frame: "calendar:personal",
    role: "placed"
  });
  putStaple(document, {
    id: createId("relation"),
    kind: "anchor",
    ends: [objectEnd(second.id, "end"), frameEnd("calendar:personal", coordinate([
      { level: "year", value: "2026" },
      { level: "month", value: "8" },
      { level: "day", value: "20" },
      { level: "hour", value: "17" }
    ]))]
  });
  assert.equal(validateDocument(document).valid, true);
  const engine = new ChronologEngine(document);
  const fact = engine.indexedExplicitFacts("calendar:personal")
    .find((entry) => entry.fact.event.id === second.id).fact;
  assert.equal(fact.precision, "hour", "the depth the author stopped at, not the depth the law filled in");
});

test("remapping ends rewrites only the ids it was given, so a partial copy keeps its links to what was not copied", () => {
  const { document, first } = workspace();
  addBearimyFrame(document);
  const staple = correspond(document, bearimyAt(4, 2), wallAt(2026, 8, 18));
  const copied = withRemappedEnds(staple, new Map([["frame:bearimy", "frame:bearimy-copy"]]));
  const ends = stapleEnds(copied);
  assert.equal(ends.find((end) => end.frame === "frame:bearimy-copy") !== undefined, true);
  assert.equal(ends.find((end) => end.frame === "frame:wall-time") !== undefined, true);
  // The original is untouched: remapping produces a copy, so a duplicate cannot
  // reach back and repoint the record it was copied from.
  assert.equal(stapleReferencesId(staple, "frame:bearimy"), true);
  assert.equal(stapleReferencesId(staple, "frame:bearimy-copy"), false);
  // An object end remaps through the same one path, by whichever key it uses.
  const anchor = putStaple(document, {
    id: createId("relation"),
    kind: "anchor",
    ends: [objectEnd(first.id, "end"), frameEnd("calendar:personal", wallAt(2026, 8, 20, 17))]
  });
  const moved = withRemappedEnds(anchor, new Map([[first.id, "event:copy"]]));
  assert.equal(stapleEnds(moved).find((end) => end.object === "event:copy").point, "end");
});

test("the engine indexes a correspondence under both of its frames, so enumeration is O(1) per frame", () => {
  const { document } = workspace();
  addBearimyFrame(document);
  const staple = correspond(document, bearimyAt(4, 2), wallAt(2026, 8, 18));
  const engine = new ChronologEngine(document);
  assert.equal(engine.staplesByFrame.get("frame:bearimy").includes(staple), true);
  assert.equal(engine.staplesByFrame.get("frame:wall-time").includes(staple), true);
  // A correspondence is not an object or series staple and must not leak into
  // either index, or it would be scanned by every extent resolution.
  assert.equal(engine.staplesByObject.size, 0);
});

test("a correspondence never anchors an object's extent, so it cannot move anything on screen", () => {
  const { document } = workspace();
  addBearimyFrame(document);
  correspond(document, bearimyAt(4, 2), wallAt(2026, 8, 18));
  assert.equal(STAPLE_KINDS.correspondence.anchors, false);
  assert.equal(STAPLE_KINDS.correspondence.partitions, false);
  assert.equal(STAPLE_KINDS.correspondence.carriesRule, false);
  // Rendering nonlinear correspondence is a separate concern; carrying it is
  // this substrate's whole job, and carrying it must not disturb placement.
  const engine = new ChronologEngine(document);
  for (const eventId of Object.keys(document.events)) {
    const staples = engine.staplesByObject.get(eventId) || [];
    assert.equal(staples.length, 0);
  }
});
