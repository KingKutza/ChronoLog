import assert from "node:assert/strict";
import test from "node:test";
import { Rational, coordinate, nowDays } from "../src/exact.js";
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
  addEvent,
  addRelation,
  clone,
  coordinateToDays,
  createEmptyWorkspaceDocument,
  daysToCoordinate,
  durationMagnitude
} from "../src/model.js";
import { exportICS } from "../src/ics.js";
import { buildCoordinateStructure, editableCoordinateStructure } from "../src/calendar-structure.js";
import { minimapLabelTicks } from "../src/minimap.js";
import { ViewSession } from "../src/session.js";
import { createInspector } from "../src/ui/inspector.js";
import { toggleTodoCompletion } from "../src/ui/roster.js";
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

  // A frame that authored no ladder at all still reads: the registered ladder is
  // substituted for it, so it genuinely HAS months and inherits their names.
  const inherited = coordinateLaw({
    frames: { "line:bare": { id: "line:bare", traits: ["line", "gregorian"] } }
  }, "line:bare");
  assert.equal(inherited.monthNames()[7], "August");
  assert.equal(inherited.hasWeekdays(), true);

  // But a declaration that names levels and has no month among them declares no
  // months, and says so rather than claiming January through December. Inheriting
  // the standard is right for a law that counts in the registered calendar and
  // merely left a level unnamed; it is a fabrication for a law with no months.
  const monthless = new CoordinateLaw({
    kind: "nested",
    levels: [{ name: "day" }, { name: "hour", within: "day", radix: "24" }]
  });
  assert.equal(monthless.monthNames(), null);
  assert.equal(monthless.hasMonths(), false);
  assert.equal(monthless.weekdayNames(), null, "a world with no week has no weekday names");
  assert.equal(monthless.hasWeekdays(), false);
  assert.equal(monthless.weekdayLabel(0), null);
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

  // Owner ruling: "I did not change the lenght of an hour I changed the length
  // of a day. Day is defined as a number of hours, which are themselves a number
  // of minutes, ect." Units compose FROM BELOW, so a radix is a statement about
  // the length of the unit ABOVE it.
  assert.equal(wall.hoursPerDay().toJSON(), "23");
  assert.equal(wall.unitDays("hour").toJSON(), "1/24", "the hour is untouched -- it was not the thing edited");
  assert.equal(wall.unitDays("day").toJSON(), "23/24", "the DAY is now twenty-three standard hours long");
  // Everything below the hour is likewise untouched, and the per-day counts fall
  // out of the shortened day rather than out of fattened parts.
  assert.equal(wall.unitDays("minute").toJSON(), "1/1440");
  assert.equal(wall.minutesPerDay().toJSON(), "1380");
  assert.equal(wall.secondsPerDay().toJSON(), "82800");
  assert.equal(wall.minutesPerHour().toJSON(), "60");
  assert.equal(measure.hoursPerDay().toJSON(), "23");

  // Duration magnitudes agree: an hour is a standard hour and 180 minutes are
  // 180 standard minutes whatever the day radix says, while "1 day" is now the
  // shortened thing.
  assert.equal(durationMagnitudeDays(durationMagnitude("1", "hour"), document).toJSON(), "1/24");
  assert.equal(durationMagnitudeDays(durationMagnitude("180", "minute"), document).toJSON(), "1/8");
  assert.equal(durationMagnitudeDays(durationMagnitude("1", "day"), document).toJSON(), "23/24");
  // A week is seven of THIS law's days, because a week is composed of them.
  assert.equal(durationMagnitudeDays(durationMagnitude("2", "week"), document).toJSON(), "14");

  // Conversion: twelve o'clock is twelve STANDARD hours after this day began,
  // and the day itself is twenty-three standard hours long. Both are stated as
  // differences, because the absolute position of any given day now drifts.
  const midnight = coordinateToDays(document, "frame:wall-time", civil(2026, 8, 20, 0, 0, 0));
  const twelve = coordinateToDays(document, "frame:wall-time", civil(2026, 8, 20, 12, 0, 0));
  const nextMidnight = coordinateToDays(document, "frame:wall-time", civil(2026, 8, 21, 0, 0, 0));
  assert.equal(twelve.sub(midnight).toJSON(), "1/2", "twelve hours in is twelve standard hours in");
  assert.equal(nextMidnight.sub(midnight).toJSON(), "23/24", "successive day boundaries are 23 standard hours apart");
  assert.deepEqual(daysToCoordinate(document, "frame:wall-time", twelve), civil(2026, 8, 20, 12, 0, 0));

  // MIDNIGHT DRIFT: because the day is the shortened unit, this frame's day
  // sequence slides against the standard calendar. Day N of the frame sits at
  // N * 23/24 standard days, so a date is a position in the FRAME's own day
  // sequence and not the standard date of the same spelling.
  const civilDay = civilCoordinateToDays(civil(2026, 8, 20));
  assert.equal(midnight.toJSON(), civilDay.mul(Rational.parse("23/24")).toJSON());
  assert.notEqual(midnight.toJSON(), civilDay.toJSON(), "an edited day length necessarily drifts");
  // The DATE ladder is still Gregorian, so the rule stays ICS-expressible even
  // though the instants it names are not standard instants.
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
  // Twelve hours in is twelve STANDARD hours in, and the day it sits in is
  // twenty-three standard hours long -- both stated as differences, because
  // under bottom-up composition the absolute position of a given day drifts.
  const midnight = engine.coordinateDays("frame:wall-time", civil(2026, 8, 20, 0, 0, 0));
  const twelve = engine.coordinateDays("frame:wall-time", civil(2026, 8, 20, 12, 0, 0));
  assert.equal(twelve.sub(midnight).toJSON(), "1/2");
  assert.equal(
    engine.coordinateDays("frame:wall-time", civil(2026, 8, 21, 0, 0, 0)).sub(midnight).toJSON(),
    "23/24"
  );
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

// ---------------------------------------------------------------------------
// Wave 8.20 Wave B: Wave A's residue class. `civilCoordinateToDays`/
// `daysToCivilCoordinate` are the registered-standard boundary -- the name is
// the assertion "standard Gregorian, deliberately". A call site that builds a
// coordinate with them and then stores it against, or resolves it against, a
// frame whose law is NOT the registered standard silently means the wrong
// instant once that frame's own law is edited. The rule: a coordinate stored
// in, or resolved against, a document frame must be built under THAT frame's
// own law (`coordinateLaw(document, frame)`), never the standard boundary --
// the standard boundary is reserved for the host clock, RFC 5545's wire, and
// an explicit "go to this calendar date" entry.
//
// Each test below drives the actual fixed function (not a re-derivation of
// its logic) against a frame whose law is edited exactly the owner's way
// (`twentyThreeHourDocument`, Hour:Day:23), and proves the stored/queried
// coordinate resolves back through the frame's OWN law to the exact day it
// started from.
// ---------------------------------------------------------------------------

function personalFrameOn(document) {
  document.frames["calendar:personal"] = {
    id: "calendar:personal",
    title: "Personal",
    traits: ["set", "calendar"],
    basis: "frame:wall-time"
  };
  return document.frames["calendar:personal"];
}

test("wave 8.20 residue: under the registered standard, a frame's own law resolves a day exactly as the civil boundary it replaces", () => {
  // Every fixed call site now reads `coordinateLaw(document, frame).fromDays`
  // where it used to read `daysToCivilCoordinate` outright. For an ordinary
  // (unedited) document this must be a no-op -- proved once here, generically,
  // rather than once per call site.
  const document = createEmptyWorkspaceDocument("Standard");
  personalFrameOn(document);
  const probe = civilCoordinateToDays(civil(2026, 3, 15, 13, 45, 30));
  assert.deepEqual(coordinateLaw(document, "calendar:personal").fromDays(probe), daysToCivilCoordinate(probe));
});

test("wave 8.20 residue: toggleTodoCompletion (src/ui/roster.js) resolves 'now' under the ToDo's own calendar frame", () => {
  const document = twentyThreeHourDocument();
  personalFrameOn(document);
  const todo = addEvent(document, {
    traits: ["event", "task", "todo"],
    magnitudes: { duration: durationMagnitude("0") },
    payload: { title: "Renew the parking permit" }
  });
  addRelation(document, {
    type: "attachment",
    event: todo.id,
    frame: "calendar:personal",
    role: "observed",
    coordinate: coordinateLaw(document, "calendar:personal").fromDays(Rational.parse("20000"))
  });

  const app = { chronolog: document, session: new ViewSession({ activeFrame: "calendar:personal" }) };
  app.history = new CommandHistory(document, () => {});
  Object.assign(app, createTransactions(app));

  // `nowDays()` is not injectable (it is the deliberate host-clock civil
  // boundary), so the live instant is bounded rather than pinned to a literal.
  const before = nowDays();
  toggleTodoCompletion(app, todo.id);
  const after = nowDays();

  const completed = Object.values(app.chronolog.relations).find(
    (relation) => relation.type === "attachment" && relation.event === todo.id && relation.role === "completed"
  );
  assert.ok(completed, "checking the box wrote a completed relation");
  assert.equal(completed.frame, "calendar:personal");
  const resolved = coordinateLaw(app.chronolog, "calendar:personal").toDays(completed.coordinate);
  // `fromDays` carries its continuous tail as a 12-place decimal (its own
  // documented `fractionPlaces` default), so a real-clock fraction that does
  // not divide evenly into a 23-radix hour loses at most ~1e-12 of a day on
  // the round trip -- an existing, unrelated precision bound of `fromDays`
  // itself, not this fix. `slack` is three orders of magnitude looser than
  // that truncation and five orders tighter than one wall-clock second, so it
  // cannot mask the bug this test exists to catch (which is minutes wide, not
  // microseconds).
  const slack = Rational.parse("1/1000000000");
  assert.ok(
    resolved.compare(before.sub(slack)) >= 0 && resolved.compare(after.add(slack)) <= 0,
    "the stored coordinate resolves back through the frame's OWN 23-hour law to the instant it was written at"
  );
  // The bug this replaces: `daysToCivilCoordinate(nowDays())` builds an "hour"
  // value out of 24, which this 23-hour frame's law would then divide by 23 on
  // the way back -- a different instant whenever the hour is not zero.
  const hourLevel = completed.coordinate.levels.find((level) => level.level === "hour");
  if (hourLevel && Number(hourLevel.value) > 0) {
    assert.notEqual(civilCoordinateToDays(completed.coordinate).compare(resolved), 0);
  }
});

// A minimal harness for `createInspector(app).createEventAt`: it needs
// `executeEventChange`/`store`/`toast`, but not the real undo journal or the
// object card's own DOM (built with innerHTML the stub-DOM harness cannot
// parse -- see the frame-editor test above for the same constraint). Each
// `executeEventChange` mutation is snapshotted immediately, so the write this
// test cares about survives even though `openEventInspector`'s later DOM/
// engine-dependent work (unreachable here, deliberately unstubbed) throws and
// triggers the same provisional-draft discard a real failed open would.
function createEventAtHarness(document, activeFrame) {
  const snapshots = [];
  const app = {
    chronolog: document,
    session: new ViewSession({ activeFrame }),
    store: { beginDeferred() {}, endDeferred() {} },
    toast() {},
    executeEventChange(label, eventId, mutate) {
      mutate(document);
      snapshots.push(clone(document.relations));
    }
  };
  return { inspector: createInspector(app), snapshots };
}

test("wave 8.20 residue: createEventAt (src/ui/inspector.js) resolves the drag-provided day under the active frame's own law", () => {
  const document = twentyThreeHourDocument();
  personalFrameOn(document);
  const { inspector, snapshots } = createEventAtHarness(document, "calendar:personal");

  // A day-fraction only this frame's own law can place correctly. Hour 5 is
  // five STANDARD hours into the frame's day (units compose from below), and
  // 20000 is not a boundary of the frame's own shortened day sequence, so
  // nothing but that law resolves this ordinal back to what it means.
  const startDay = Rational.parse("20000").add(Rational.parse("5/24"));
  inspector.createEventAt(startDay, startDay, "event");

  const created = Object.values(snapshots[0] || {}).find((relation) => relation.type === "attachment");
  assert.ok(created, "createEventAt wrote a placement relation before any later failure could discard it");
  assert.equal(created.frame, "calendar:personal");
  assert.equal(
    coordinateLaw(document, "calendar:personal").toDays(created.coordinate).compare(startDay), 0,
    "the stored coordinate resolves back through the frame's OWN 23-hour law to the exact day the drag handed in"
  );
});

test("wave 8.20 residue: createEventAt is byte-identical to the old civil conversion under the registered standard", () => {
  const document = createEmptyWorkspaceDocument("Standard create");
  personalFrameOn(document);
  const { inspector, snapshots } = createEventAtHarness(document, "calendar:personal");

  const startDay = Rational.parse("20000").add(Rational.parse("5/24"));
  inspector.createEventAt(startDay, startDay, "event");

  const created = Object.values(snapshots[0] || {}).find((relation) => relation.type === "attachment");
  assert.ok(created);
  assert.deepEqual(created.coordinate, daysToCivilCoordinate(startDay));
});

test("wave 8.20 residue: the ICS export window (src/ui/calendar-sync-panel.js) is resolved under the exporting frame's own law", () => {
  // The owner's scenario, applied to an export window: `session.window()`
  // hands back universal day ordinals, and the fix resolves them with
  // `coordinateLaw(document, frame).fromDays` before handing them to
  // `exportICS`, which resolves them back with `coordinateLaw(...).toDays`
  // (src/ics.js). Half a day under the standard boundary (hour 12 of 24) is a
  // DIFFERENT absolute instant than half a day under this frame's real 23-hour
  // law (hour 12 of 23 is 12/23 of a day, not 1/2) -- so an event placed just
  // past the true half-day mark is wrongly swept into the export by the old
  // boundary, and correctly excluded by the fix.
  const document = twentyThreeHourDocument();
  const frame = personalFrameOn(document);
  const law = coordinateLaw(document, frame.id);
  const dayStart = GREGORIAN_LAW.toDays(civil(2026, 8, 20));

  const event = addEvent(document, {
    traits: ["event"],
    magnitudes: { duration: durationMagnitude("0") },
    payload: { title: "Just past the true half-day mark" }
  });
  addRelation(document, {
    type: "attachment",
    event: event.id,
    frame: frame.id,
    role: "placed",
    coordinate: law.fromDays(dayStart.add(Rational.parse("51/100")))
  });

  const windowStartFixed = law.fromDays(dayStart);
  const windowEndFixed = law.fromDays(dayStart.add(Rational.parse("1/2")));
  const fixedExport = exportICS(document, { frame: frame.id, start: windowStartFixed, end: windowEndFixed });
  assert.doesNotMatch(fixedExport, /Just past the true half-day mark/, "the fix excludes it: 51/100 is past the true half-day bound");

  // The bug, reproduced: the same window bounds built through the standard
  // boundary instead. `dayStart` itself is bare and survives (0 hours is 0
  // hours under any radix), but the fractional end does not.
  const windowStartBuggy = daysToCivilCoordinate(dayStart);
  const windowEndBuggy = daysToCivilCoordinate(dayStart.add(Rational.parse("1/2")));
  // Under bottom-up composition the divergence is larger and structural, not a
  // fraction-of-a-day rounding: this frame's DAY is shorter, so its whole day
  // sequence drifts against the standard calendar and a standard-boundary
  // coordinate names an entirely different instant. Both bounds move, so the
  // buggy window is a different interval altogether -- which is the point. The
  // assertion is that it IS different, not which way it lands, because "which
  // way" is a function of how far from the epoch the window sits.
  assert.notEqual(
    law.toDays(windowEndBuggy).compare(law.toDays(windowEndFixed)), 0,
    "a standard-boundary coordinate is not this frame's boundary once its day length is authored"
  );
  assert.notEqual(
    law.toDays(windowStartBuggy).compare(law.toDays(windowStartFixed)), 0,
    "the drift moves the start bound too, so the buggy window is a different interval"
  );
});
