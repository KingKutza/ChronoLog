import assert from "node:assert/strict";
import test from "node:test";
import {
  buildCoordinateStructure,
  buildFixedCalendarStructure,
  coordinateStructureSummary,
  editableCoordinateStructure,
  parseNameList,
  transitionChoices,
  validateNameList
} from "../src/calendar-structure.js";
import { coordinateLaw, invalidateCoordinateLaws } from "../src/coordinate-law.js";
import { frameAuthoringCapabilities } from "../src/frame-edit.js";
import { createEmptyWorkspaceDocument } from "../src/model.js";

// The owner's second field report, both halves:
//
//   "When I go into wall time there is no section to definecalendar structure,
//    which is weird as that is the frame defining the inherited calendar
//    structure. and when I go into my personal calendar using Wall Time as a
//    basis to override the list of week day names, with
//    Mon,Tue,Batman,Thu,Fri,Sat,Sun I get an error telling me I have to define
//    the same number of days, which is weird as I did define the same number of
//    days."
//
// The form itself is built with innerHTML, which the stub-DOM harness does not
// parse, so these pin the DOM-free contract the form is a thin shell over.

test("Wall Time can author its own calendar structure", () => {
  // `frame:wall-time` carries traits ["line", "temporal", "gregorian"], so its
  // authoring kind is "line". The structure section used to be gated on
  // "calendar", which withheld it from the one frame every other calendar
  // inherits its structure from.
  assert.equal(frameAuthoringCapabilities("line", ["line", "temporal", "gregorian"]).calendarStructure, true);
  assert.equal(frameAuthoringCapabilities("measure", ["measure"]).calendarStructure, true);
  assert.equal(frameAuthoringCapabilities("cycle").calendarStructure, true);
  // A group owns no coordinate, so it authors no structure.
  assert.equal(frameAuthoringCapabilities("group").calendarStructure, false);
  assert.equal(frameAuthoringCapabilities("importance").calendarStructure, false);
});

test("the structure editor round-trips Wall Time's own declaration without changing it", () => {
  const document = createEmptyWorkspaceDocument("Round trip");
  const law = coordinateLaw(document, "frame:wall-time");
  const rows = editableCoordinateStructure(law);

  assert.deepEqual(rows.levels.map((level) => level.name), [
    "year", "month", "day", "hour", "minute", "second", "subsecond"
  ]);
  assert.equal(rows.levels.find((level) => level.name === "hour").count, "24");
  assert.equal(rows.levels.find((level) => level.name === "month").transition, "gregorian.months");
  assert.match(rows.levels.find((level) => level.name === "month").names, /^January, February/);
  // The weekday cycle is offered as a cycle, which is the whole point.
  assert.deepEqual(rows.cycles.map((cycle) => cycle.name), ["weekday"]);
  assert.equal(rows.cycles[0].length, "7");
  assert.equal(rows.cycles[0].phase, "4");

  const rebuilt = buildCoordinateStructure({ ...rows, previous: document.frames["frame:wall-time"].coordinate });
  assert.deepEqual(
    coordinateLaw({ frames: { rebuilt: { id: "rebuilt", traits: ["gregorian"], coordinate: rebuilt } } }, "rebuilt").levelNames(),
    law.levelNames()
  );
  assert.equal(rebuilt.cycles[0].names.length, 7);
  assert.match(coordinateStructureSummary(rebuilt), /One year = 146097\/400 days/);

  // Every registered transition is offered, plus the fixed-count option.
  assert.deepEqual(transitionChoices().map((choice) => choice.value), [
    "", "gregorian.days", "gregorian.daysInYear", "gregorian.months"
  ]);
});

test("a seven-name weekday list is accepted, because a week is a cycle and not a level", () => {
  const document = createEmptyWorkspaceDocument("Batman");
  const rows = editableCoordinateStructure(coordinateLaw(document, "frame:wall-time"));
  rows.cycles[0].names = "Mon,Tue,Batman,Thu,Fri,Sat,Sun";

  const built = buildCoordinateStructure({ ...rows, previous: document.frames["frame:wall-time"].coordinate });
  assert.deepEqual(built.cycles[0].names, ["Mon", "Tue", "Batman", "Thu", "Fri", "Sat", "Sun"]);

  document.frames["frame:wall-time"].coordinate = built;
  invalidateCoordinateLaws(document);
  const law = coordinateLaw(document, "frame:wall-time");
  assert.deepEqual(law.weekdayNames(), ["Mon", "Tue", "Batman", "Thu", "Fri", "Sat", "Sun"]);
  // Day 5 sits at cycle index (5 + 4) mod 7 = 2, the position the author renamed.
  assert.equal(law.weekdayLabel(5), "Batman");
  assert.equal(law.weekdayLabel(3), "Mon", "the phase is data, so the rest of the list stays put");

  // Whitespace and a trailing comma are the author's typing, not an error.
  assert.deepEqual(
    buildCoordinateStructure({
      ...rows,
      cycles: [{ ...rows.cycles[0], names: " Mon , Tue , Batman , Thu , Fri , Sat , Sun , " }],
      previous: document.frames["frame:wall-time"].coordinate
    }).cycles[0].names,
    ["Mon", "Tue", "Batman", "Thu", "Fri", "Sat", "Sun"]
  );
});

test("a names list is checked against the count its own meaning requires, and says both numbers when it is wrong", () => {
  // The generalized defect: a list was validated against a NEIGHBOURING count.
  // Naming the days inside a month cannot work at all -- a Gregorian month holds
  // 28 to 31 of them -- so the refusal has to say that instead of demanding a
  // number the author can never satisfy.
  const document = createEmptyWorkspaceDocument("Counts");
  const rows = editableCoordinateStructure(coordinateLaw(document, "frame:wall-time"));
  const dayRow = rows.levels.find((level) => level.name === "day");
  dayRow.names = "Mon,Tue,Batman,Thu,Fri,Sat,Sun";
  assert.throws(() => buildCoordinateStructure({ ...rows }), (error) => {
    assert.match(error.message, /varies in number/);
    assert.match(error.message, /cycle/);
    return true;
  });

  // A fixed count states both numbers and names the unit.
  assert.throws(
    () => validateNameList(["one", "two"], 8, "month names", "month"),
    /month names needs 8 names, one for each month; 2 were given\./
  );
  // A repeated name is accepted: distinctness is not authoring's job. What it
  // protected was lookup-by-name ("March" resolving to month 3 alone), and this
  // module has no such lookup -- an ambiguous name is refused at RESOLUTION,
  // not withheld from the author here.
  assert.deepEqual(validateNameList(["Mon", "mon"], 2, "weekday names", "weekday"), ["Mon", "mon"]);
  assert.deepEqual(parseNameList("a, ,b,,c , "), ["a", "b", "c"]);
  assert.deepEqual(parseNameList(["a", " b "]), ["a", "b"]);
  assert.deepEqual(parseNameList(undefined), []);
});

test("the structure editor refuses a declaration the coordinate engine cannot execute, before it is stored", () => {
  const document = createEmptyWorkspaceDocument("Refuse");
  const rows = editableCoordinateStructure(coordinateLaw(document, "frame:wall-time"));
  assert.throws(() => buildCoordinateStructure({
    ...rows,
    levels: rows.levels.map((level) => level.name === "month" ? { ...level, transition: "julian.months" } : level)
  }), /nothing implements/);

  assert.throws(() => buildCoordinateStructure({
    ...rows,
    levels: rows.levels.map((level) => level.name === "hour" ? { ...level, count: "0" } : level)
  }), /positive whole number/);

  assert.throws(() => buildCoordinateStructure({
    ...rows,
    cycles: [{ name: "weekday", length: "7", phase: "0", names: "Mon,Tue,Wed" }]
  }), /needs 7 names/);

  assert.throws(() => buildCoordinateStructure({
    ...rows,
    cycles: [{ name: "weekday", length: "7", phase: "half", names: "" }]
  }), /whole number of units/);
});

test("editing the structure grid drops a stale fixed-calendar summary but keeps a matching one", () => {
  const built = buildFixedCalendarStructure({
    units: [{ name: "year" }, { name: "month", perParent: "8" }, { name: "day", perParent: "8" }],
    smallestUnitDays: "1"
  });
  const rows = editableCoordinateStructure(
    coordinateLaw({ frames: { fixed: { id: "fixed", traits: ["set", "calendar"], coordinate: built.coordinate } } }, "fixed")
  );
  const unchanged = buildCoordinateStructure({ ...rows, previous: built.coordinate });
  assert.deepEqual(unchanged.fixed, built.coordinate.fixed, "an untouched hierarchy keeps its builder summary");

  const changed = buildCoordinateStructure({
    ...rows,
    levels: rows.levels.map((level) => level.name === "day" ? { ...level, count: "9" } : level),
    previous: built.coordinate
  });
  assert.equal(changed.fixed, undefined, "a summary that no longer describes the levels is dropped, not kept as a lie");
});

test("baseLevel and origin are authorable for a wholly invented, uniform ladder", () => {
  // A ladder with no registered transition anywhere in it has nothing to infer
  // a day from, so it states its own base level and starting day ordinal --
  // the two fields a uniform calendar (12 months of 30 days, say) needs to
  // become positional at all.
  const built = buildCoordinateStructure({
    levels: [{ name: "year" }, { name: "month", count: "12" }, { name: "day", count: "30" }],
    baseLevel: "day",
    origin: "0"
  });
  assert.equal(built.baseLevel, "day");
  assert.deepEqual(built.origin, { days: "0" });
  const law = coordinateLaw({ frames: { uniform: { id: "uniform", traits: ["set", "calendar"], coordinate: built } } }, "uniform");
  assert.equal(law.positional, true);
  assert.equal(law.baseLevel, "day");

  // Blank fields are omitted rather than stored empty, so a document that never
  // authors either stays byte-identical to one that still doesn't -- exactly
  // the rule the structure grid already applies to `fixed` and `cycles`.
  const rows = editableCoordinateStructure(law);
  assert.equal(rows.baseLevel, "day");
  assert.equal(rows.origin, "0");
  const withoutEither = buildCoordinateStructure({ levels: rows.levels, kind: rows.kind });
  assert.equal(Object.hasOwn(withoutEither, "baseLevel"), false);
  assert.equal(Object.hasOwn(withoutEither, "origin"), false);
});
