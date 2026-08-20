import assert from "node:assert/strict";
import test from "node:test";
import { Rational, coordinate } from "../src/exact.js";
import {
  CoordinateLaw,
  GREGORIAN_DECLARATION,
  GREGORIAN_LAW,
  GREGORY,
  civilCoordinateToDays,
  coordinateLaw,
  coordinateLawError,
  daysToCivilCoordinate,
  durationMagnitudeDays,
  invalidateCoordinateLaws,
  lawForCalendar,
  registeredCalendars,
  registeredTransitions
} from "../src/coordinate-law.js";
import { ChronologEngine } from "../src/engine.js";
import {
  CommandHistory,
  coordinateToDays,
  createEmptyWorkspaceDocument,
  daysToCoordinate,
  durationMagnitude
} from "../src/model.js";
import { buildCoordinateStructure, editableCoordinateStructure } from "../src/calendar-structure.js";
import { minimapLabelTicks } from "../src/minimap.js";
import { ViewSession } from "../src/session.js";
import { createTransactions } from "../src/ui/transactions.js";
import { findByClass, renderWithStubDom } from "./helpers/render-dom.js";

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

test("the transition registry resolves the declaration's transition strings, and refuses the ones nothing implements", () => {
  // These strings were written into `frame:wall-time` from the beginning and
  // resolved to NOTHING: the conversion branched on `kind: "gregorian"` and
  // never read them. They are entries now.
  assert.deepEqual(registeredTransitions(), [
    "gregorian.days", "gregorian.daysInYear", "gregorian.months"
  ]);

  assert.throws(() => new CoordinateLaw({
    kind: "gregorian",
    levels: [{ name: "year" }, { name: "month", within: "year", transition: "julian.months" }]
  }, { frameId: "frame:invented" }), (error) => {
    // The author is told what is wrong and what the alternatives are. Silence
    // here is what let a dead ladder look alive.
    assert.match(error.message, /Frame frame:invented/);
    assert.match(error.message, /julian\.months/);
    assert.match(error.message, /nothing implements/);
    assert.match(error.message, /gregorian\.months/);
    return true;
  });

  // A ladder the family cannot execute is equally an error, not a guess.
  assert.throws(() => new CoordinateLaw({
    kind: "gregorian",
    levels: [{ name: "year" }, { name: "day", within: "year", transition: "gregorian.days" }]
  }), /cannot execute the level ladder/);
});

test("CLDR calendar scales are ordinary registry entries, and an unregistered one is refused rather than computed as Gregorian", () => {
  // Gregorian is the first entry, not a privileged branch. Adding Hebrew or
  // Islamic later is a registration, and this is the seam that proves it.
  assert.deepEqual(registeredCalendars(), [GREGORY]);
  assert.equal(lawForCalendar("gregory").hoursPerDay().toJSON(), "24");
  // RFC 7529's own text is inconsistent about GREGORY vs GREGORIAN, so both
  // resolve; nothing else does.
  assert.equal(lawForCalendar("GREGORIAN"), lawForCalendar("gregory"));
  assert.equal(lawForCalendar("HEBREW"), null);
  assert.equal(lawForCalendar(""), null);
  assert.equal(GREGORIAN_LAW.calendarScale(), GREGORY);
});

test("the registered Gregorian conversion is exact in both directions and keeps a bare date bare", () => {
  const noon = civilCoordinateToDays(civil(2026, 8, 20, 12, 0, 0));
  assert.equal(noon.sub(noon.floor()).toJSON(), "1/2");
  assert.deepEqual(daysToCivilCoordinate(noon), civil(2026, 8, 20, 12, 0, 0));
  // Midnight carries no time levels: the shape every stored document has.
  assert.deepEqual(
    daysToCivilCoordinate(civilCoordinateToDays(coordinate([
      { level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "20" }
    ]))),
    coordinate([
      { level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "20" }
    ])
  );
});

test("a Gregorian month is exactly 146097/4800 days, not the float that was carried in the minimap", () => {
  assert.equal(GREGORIAN_LAW.meanMonthDays().toJSON(), "48699/1600");
  assert.equal(GREGORIAN_LAW.meanMonthDays().toNumber(), 30.436875);
  assert.equal(GREGORIAN_LAW.meanUnitDays("year").toJSON(), "146097/400");
  assert.equal(GREGORIAN_LAW.unitDays("month"), null, "a month has no constant length and must not pretend to");
  assert.equal(GREGORIAN_LAW.unitDays("day").toJSON(), "1");
  assert.equal(GREGORIAN_LAW.unitDays("hour").toJSON(), "1/24");
  assert.equal(GREGORIAN_LAW.unitDays("minute").toJSON(), "1/1440");
  assert.equal(GREGORIAN_LAW.unitDays("second").toJSON(), "1/86400");
  assert.equal(GREGORIAN_LAW.daysPerWeek().toJSON(), "7");
});

test("names and the weekday cycle come from the declaration, and a declaration that omits them inherits the registered ones", () => {
  assert.equal(GREGORIAN_LAW.monthNames()[0], "January");
  assert.equal(GREGORIAN_LAW.weekdayNames().length, 7);
  // Day zero is 1970-01-01, a Thursday: the phase the shipped
  // `floorMod(day + 4, 7)` derivation encoded as a literal.
  assert.equal(GREGORIAN_LAW.weekdayLabel(0), "Thursday");
  assert.equal(GREGORIAN_LAW.cycleIndex("weekday", 0), 4);
  assert.equal(GREGORIAN_LAW.weekdayLabel(3), "Sunday");

  const authored = new CoordinateLaw({
    ...GREGORIAN_DECLARATION,
    cycles: [{ name: "weekday", radix: "7", offset: "4", names: ["Sun", "Mon", "Tue", "Batman", "Thu", "Fri", "Sat"] }]
  });
  // Day 6 sits at cycle index (6 + 4) mod 7 = 3, the position the author renamed.
  assert.equal(authored.weekdayLabel(6), "Batman", "an authored name is used verbatim, never normalized away");
  assert.equal(authored.weekdayLabel(0), "Thu");

  // A frame that authored no names at all still reads: meaning is inherited
  // from the registered calendar, never invented.
  const bare = new CoordinateLaw({ kind: "gregorian" });
  assert.equal(bare.monthNames()[7], "August");
});

// ---------------------------------------------------------------------------
// THE ACCEPTANCE TEST for ROADMAP #6's prerequisite stage.
//
// Owner's field report: "I just swaped both Wall Time and Human time magnitude
// to Hour:Day:23, in the advanced frame data, applied and uppon inspection there
// still appears to be 24 hours in a day, the frame time definitions are thus
// broken."
//
// So: set hours-per-day to 23 on the frame and everything must move with it.
// This half of the test pins the arithmetic every surface consumes; the
// surface-level assertions live alongside their own renderers.
// ---------------------------------------------------------------------------

function twentyThreeHourDocument() {
  const document = createEmptyWorkspaceDocument("Twenty-three");
  for (const frameId of ["frame:wall-time", "measure:human-time"]) {
    const levels = document.frames[frameId].coordinate.levels;
    levels.find((level) => level.name === "hour").radix = "23";
  }
  return document;
}

test("declaring 23 hours in a day changes what an hour is worth everywhere the law is asked", () => {
  const document = twentyThreeHourDocument();
  const wall = coordinateLaw(document, "frame:wall-time");
  const measure = coordinateLaw(document, "measure:human-time");

  assert.equal(wall.hoursPerDay().toJSON(), "23");
  assert.equal(wall.unitDays("hour").toJSON(), "1/23");
  // The sub-hour ladder follows: minutes and seconds are subdivisions of THIS
  // hour, so a 23-hour day has 1380 minutes and 82800 seconds.
  assert.equal(wall.minutesPerDay().toJSON(), "1380");
  assert.equal(wall.secondsPerDay().toJSON(), "82800");
  assert.equal(wall.minutesPerHour().toJSON(), "60", "the radices below the hour are untouched");
  assert.equal(measure.hoursPerDay().toJSON(), "23");

  // Duration magnitudes: an event authored as one hour is now 1/23 of a day,
  // and the fixed {hour:"1/24"} factor table that used to answer this is gone.
  assert.equal(durationMagnitudeDays(durationMagnitude("1", "hour"), document).toJSON(), "1/23");
  assert.equal(durationMagnitudeDays(durationMagnitude("90", "minute"), document).toJSON(), "3/46");
  // A week is still seven days: the day is the base unit and the edit was below it.
  assert.equal(durationMagnitudeDays(durationMagnitude("2", "week"), document).toJSON(), "14");

  // Coordinate conversion: noon-by-the-clock is hour 12 of 23, which is no
  // longer the middle of the day, and the round trip is still exact.
  const twelve = coordinateToDays(document, "frame:wall-time", civil(2026, 8, 20, 12, 0, 0));
  assert.equal(twelve.sub(twelve.floor()).toJSON(), "12/23");
  assert.deepEqual(daysToCoordinate(document, "frame:wall-time", twelve), civil(2026, 8, 20, 12, 0, 0));

  // The date ladder above the base unit is untouched, so dates still land where
  // they always did -- and the series' rules stay ICS-expressible.
  assert.equal(
    coordinateToDays(document, "frame:wall-time", civil(2026, 8, 20)).toJSON(),
    civilCoordinateToDays(civil(2026, 8, 20)).toJSON()
  );
  assert.equal(wall.calendarScale(), GREGORY);
});

test("a calendar inherits an edited ladder through its basis without restating it", () => {
  const document = twentyThreeHourDocument();
  document.frames["calendar:personal"] = {
    id: "calendar:personal",
    title: "Personal",
    traits: ["set", "calendar"],
    basis: "frame:wall-time"
  };
  // This is the relationship the owner named: "that is the frame defining the
  // inherited calendar structure."
  assert.equal(coordinateLaw(document, "calendar:personal").hoursPerDay().toJSON(), "23");
  assert.equal(
    coordinateToDays(document, "calendar:personal", civil(2026, 8, 20, 12, 0, 0)).toJSON(),
    coordinateToDays(document, "frame:wall-time", civil(2026, 8, 20, 12, 0, 0)).toJSON()
  );
});

test("an applied ladder edit is live: the memoized law is dropped when the declaration changes", () => {
  const document = createEmptyWorkspaceDocument("Live");
  assert.equal(coordinateLaw(document, "frame:wall-time").hoursPerDay().toJSON(), "24");

  // The shape an edit actually arrives in: `Object.assign` over the frame record
  // with a freshly parsed coordinate object.
  document.frames["frame:wall-time"] = {
    ...document.frames["frame:wall-time"],
    coordinate: JSON.parse(JSON.stringify({
      ...document.frames["frame:wall-time"].coordinate,
      levels: document.frames["frame:wall-time"].coordinate.levels.map((level) =>
        level.name === "hour" ? { ...level, radix: "23" } : level)
    }))
  };
  assert.equal(
    coordinateLaw(document, "frame:wall-time").hoursPerDay().toJSON(),
    "23",
    "a replaced declaration is noticed by identity, with no explicit invalidation at all"
  );

  // And an in-place mutation -- the shape an undo/replay can produce -- is
  // covered by the explicit invalidation the edit path calls.
  document.frames["frame:wall-time"].coordinate.levels
    .find((level) => level.name === "hour").radix = "10";
  invalidateCoordinateLaws(document);
  assert.equal(coordinateLaw(document, "frame:wall-time").hoursPerDay().toJSON(), "10");
});

test("the frame editor's apply path makes a ladder edit live, undoable, and journaled", () => {
  // The owner's report is an editor that ACCEPTED the edit and then ignored it.
  // This drives the same transaction the frame form submits -- one
  // `executeRecordChange` over the `frames` map -- rather than the form itself,
  // which is built with innerHTML the stub-DOM harness cannot parse.
  const document = createEmptyWorkspaceDocument("Apply");
  const changes = [];
  const app = { chronolog: document, history: new CommandHistory(document, (change) => changes.push(change)) };
  Object.assign(app, createTransactions(app));

  const rows = editableCoordinateStructure(coordinateLaw(document, "frame:wall-time"));
  rows.levels.find((level) => level.name === "hour").count = "23";
  const edited = buildCoordinateStructure({ ...rows, previous: document.frames["frame:wall-time"].coordinate });

  app.executeRecordChange("Edit frame", "frames", "frame:wall-time", (documentValue) => {
    Object.assign(documentValue.frames["frame:wall-time"], { coordinate: edited });
  });

  const engine = new ChronologEngine(document);
  assert.equal(coordinateLaw(document, "frame:wall-time").hoursPerDay().toJSON(), "23");
  // The engine, not just the model helper: this is the path every occurrence,
  // staple and projection query goes through.
  const twelve = engine.coordinateDays("frame:wall-time", civil(2026, 8, 20, 12, 0, 0));
  assert.equal(twelve.sub(twelve.floor()).toJSON(), "12/23");
  assert.deepEqual(engine.daysCoordinate("frame:wall-time", twelve), civil(2026, 8, 20, 12, 0, 0));

  // One undoable entry that actually undoes, and a journal op naming the record.
  assert.equal(app.history.undoStack.length, 1);
  assert.ok(changes.at(-1).ops.some((op) => op.map === "frames" && op.id === "frame:wall-time"));
  assert.equal(app.history.undo(), true);
  assert.equal(coordinateLaw(document, "frame:wall-time").hoursPerDay().toJSON(), "24");
  assert.equal(app.history.redo(), true);
  assert.equal(coordinateLaw(document, "frame:wall-time").hoursPerDay().toJSON(), "23");
});

test("the Intimate rail, its hour labels and the minimap all count the frame's own hours", () => {
  // The rendered half of the acceptance test: the owner's "uppon inspection
  // there still appears to be 24 hours in a day" was an inspection of the
  // STAGE, so the stage is what this checks.
  const document = twentyThreeHourDocument();
  document.frames["calendar:personal"] = {
    id: "calendar:personal",
    title: "Personal",
    traits: ["set", "calendar"],
    basis: "frame:wall-time"
  };
  const session = new ViewSession({
    projection: "calendar",
    scale: 0,
    activeFrame: "calendar:personal",
    intimateBack: 0,
    intimateForward: 0,
    focusDays: String(GREGORIAN_LAW.toDays(civil(2026, 8, 20)))
  });
  session.setCoordinateLaw(coordinateLaw(document, "calendar:personal"));
  assert.equal(session.hoursPerDay().toJSON(), "23");
  // The intimate window clamps to this frame's hours: a 4..20 window is still
  // inside a 23-hour day, but the end bound may never exceed it.
  assert.ok(session.intimateEndHour <= 23);

  const target = renderWithStubDom({ document, engine: new ChronologEngine(document), session });
  const scroll = findByClass(target, "intimate-scroll")[0];
  assert.ok(scroll, "the Intimate rail rendered");
  // The rail publishes the hours-per-day the pointer layer must agree with,
  // and its buffer is counted in those same hours.
  assert.equal(scroll.dataset.hoursPerDay, "23");
  assert.equal(Number(scroll.dataset.bufferHours) % 23, 0, "the buffer is a whole number of this frame's days");
  const column = findByClass(target, "intimate-day-column")[0];
  assert.equal(Number(column.dataset.timelineHours) % 23, 0, "the rail is a whole number of this frame's days");
  // One hour label per rail hour, and the rail is a whole number of 23-hour days.
  const labels = findByClass(target, "intimate-hour-label");
  assert.equal(labels.length, Number(column.dataset.timelineHours));
  assert.equal(labels.length % 23, 0);

  // The minimap's hour stride is this frame's hour, not 1/24 of a day.
  const law = coordinateLaw(document, "calendar:personal");
  const start = GREGORIAN_LAW.toDays(civil(2026, 8, 20));
  const ticks = minimapLabelTicks(start, start.add(1), "hour", 64, law);
  const strides = new Set(ticks.slice(1).map((tick, index) => tick.days.sub(ticks[index].days).toJSON()));
  assert.ok(strides.size >= 1);
  for (const stride of strides) {
    assert.equal(
      Rational.parse(stride).mul(23).d, 1n,
      "every hour stride is a whole number of 23rds of a day"
    );
  }
});

test("an unresolvable declaration is reported to the author rather than swallowed by the render", () => {
  const document = createEmptyWorkspaceDocument("Broken");
  assert.equal(coordinateLawError(document, "frame:wall-time"), null);
  document.frames["frame:wall-time"].coordinate = {
    kind: "gregorian",
    levels: [{ name: "year" }, { name: "month", within: "year", transition: "gregorian.months" },
      { name: "day", within: "month", transition: "gregorian.days" },
      { name: "hour", within: "day", radix: "0" }]
  };
  invalidateCoordinateLaws(document);
  assert.match(coordinateLawError(document, "frame:wall-time"), /positive whole radix/);
});

test("a measure frame keeps reading its own base level rather than being reinterpreted as a date", () => {
  // `measure:human-time` carries a full year/day/hour ladder because it measures
  // magnitudes, not positions. Asking it to convert a coordinate must not treat
  // "day 5" as the fifth day of 1970.
  const document = createEmptyWorkspaceDocument("Measure");
  const measure = coordinateLaw(document, "measure:human-time");
  assert.equal(measure.positional, false);
  assert.equal(coordinateToDays(document, "measure:human-time", coordinate([{ level: "day", value: "5" }])).toJSON(), "5");
  assert.deepEqual(
    daysToCoordinate(document, "measure:human-time", Rational.parse("25/4")),
    coordinate([{ level: "day", value: "25/4" }])
  );
  // Its declared radices still govern magnitudes, which is the half that matters.
  assert.equal(measure.unitDays("hour").toJSON(), "1/24");
});

test("a duration magnitude with no governing law falls back to the registered standard, and a malformed one is tolerated", () => {
  assert.equal(durationMagnitudeDays(durationMagnitude("90", "minute")).toJSON(), "1/16");
  assert.equal(durationMagnitudeDays(null).toJSON(), "0");
  assert.equal(durationMagnitudeDays({ frame: "measure:human-time", value: { levels: [{ level: "day", value: "nope" }] } }).toJSON(), "0");
  // A level this law never declared is skipped, not guessed at.
  assert.equal(
    durationMagnitudeDays({ frame: "measure:human-time", value: { levels: [{ level: "fortnight", value: "3" }] } }).toJSON(),
    "0"
  );
});
