import assert from "node:assert/strict";
import test from "node:test";
import { coordinate, daysFromCivil } from "../src/exact.js";
import { CoordinateLaw, GREGORIAN_LAW, coordinateLaw } from "../src/coordinate-law.js";
import {
  coordinateEntryPlaceholder,
  coordinatePickerLadder,
  formatCoordinateEntry,
  parseCoordinateEntry
} from "../src/coordinate-entry.js";
import { ChronologEngine } from "../src/engine.js";
import { FIXED_RADIAL_CYCLES, resolveRadialCycle } from "../src/radial.js";
import { ViewSession } from "../src/session.js";
import { createStructuralDocument } from "./helpers/sample-document.js";
import { findByClass, renderWithStubDom } from "./helpers/render-dom.js";

// Owner ruling: "Hard No. Epochs, true epochs no faking." Task 2 makes an
// era-qualified year ("3E 433", "44 BCE") typeable in the placement field;
// Task 1 makes sure a calendar with no now-mapping draws no Now line.
//
// Eras are FRAMES STAPLED TOGETHER (src/era-chain.js), not a level of the
// declaration -- a mid-wave model pivot. An era-qualified coordinate's YEAR
// position is written bare ("433") or qualified with the era frame's own key
// ("3E 433"); choosing an era is choosing which FRAME to place on, which
// happens before this field, so the field never stores an "era" level at all.
//
// Every era fixture below is a succession chain of frame records, the same
// shape test/era-display.test.js uses (copied here, not imported, so this
// file stands alone). No law is ever constructed at module scope: a bad
// fixture must fail the one test that uses it, not abort the whole suite.

const PLAIN_GREGORIAN_LADDER = Object.freeze({
  kind: "gregorian",
  levels: Object.freeze([
    Object.freeze({ name: "year" }),
    Object.freeze({ name: "month", within: "year", transition: "gregorian.months" }),
    Object.freeze({ name: "day", within: "month", transition: "gregorian.days" }),
    Object.freeze({ name: "hour", within: "day", radix: "24" }),
    Object.freeze({ name: "minute", within: "hour", radix: "60" }),
    Object.freeze({ name: "second", within: "minute", radix: "60" })
  ])
});

// BCE descending and open below, CE ascending and open above -- the mission's
// own Gregorian-with-eras example, exercising a suffix affix.
const BCE_CE_CHAIN = Object.freeze([
  Object.freeze({ id: "era:bce", era: Object.freeze({
    key: "BCE", name: "Before Common Era", direction: "descending", firstYear: "1", years: "open", affix: "suffix"
  }) }),
  Object.freeze({ id: "era:ce", era: Object.freeze({
    key: "CE", name: "Common Era", direction: "ascending", firstYear: "1", years: "open", affix: "suffix",
    anchor: { year: "1", properYear: "1" }
  }) })
]);

// A uniform 365-day year (no month, no Gregorian family) with a true era
// chain: Merethic open below, three bounded eras, Fourth Era open above --
// the mission's other example, exercising a prefix affix on a non-Gregorian
// ladder. Ranges pinned against test/era-table.test.js's own numbers (1E: 1..2920,
// 2E: 2921..3816, 3E: 3817..4249, 4E: 4250..open).
const TAMRIEL_LADDER = Object.freeze({
  kind: "nested",
  baseLevel: "day",
  levels: Object.freeze([
    Object.freeze({ name: "year" }),
    Object.freeze({ name: "day", within: "year", radix: "365" }),
    Object.freeze({ name: "hour", within: "day", radix: "24" })
  ])
});

const TAMRIEL_CHAIN = Object.freeze([
  Object.freeze({ id: "era:me", era: Object.freeze({
    key: "ME", name: "Merethic Era", direction: "descending", firstYear: "1", years: "open"
  }) }),
  Object.freeze({ id: "era:1e", era: Object.freeze({
    key: "1E", name: "First Era", direction: "ascending", firstYear: "1", years: "2920",
    anchor: { year: "1", properYear: "1" }
  }) }),
  Object.freeze({ id: "era:2e", era: Object.freeze({
    key: "2E", name: "Second Era", direction: "ascending", firstYear: "1", years: "896"
  }) }),
  Object.freeze({ id: "era:3e", era: Object.freeze({
    key: "3E", name: "Third Era", direction: "ascending", firstYear: "1", years: "433"
  }) }),
  Object.freeze({ id: "era:4e", era: Object.freeze({
    key: "4E", name: "Fourth Era", direction: "ascending", firstYear: "1", years: "open"
  }) })
]);

// A calendar spanning eras is a GROUP frame over the chain (src/era-chain.js);
// each era is its own frame inheriting the ladder from `basis`, and the
// boundary between consecutive eras is a `succession` staple whose `end`/
// `start` roles carry the whole of its meaning. Called from inside a test
// body only -- never at module scope -- so a fixture that fails to resolve
// fails one test, not the whole file's import.
function chainLaw(entries, ladder, eraId) {
  const frames = {
    "frame:chain-calendar": {
      id: "frame:chain-calendar",
      title: "Chain calendar",
      traits: ["line", "temporal", "calendar", "group"],
      coordinate: ladder
    }
  };
  const relations = {};
  for (const entry of entries) {
    frames[entry.id] = {
      id: entry.id,
      title: entry.era.name,
      traits: ["line", "temporal", "era"],
      basis: "frame:chain-calendar",
      era: entry.era
    };
  }
  for (const [index, entry] of entries.slice(0, -1).entries()) {
    relations[`succession:${entry.id}`] = {
      id: `succession:${entry.id}`,
      type: "staple",
      kind: "succession",
      ends: [
        { frame: entry.id, role: "end" },
        { frame: entries[index + 1].id, role: "start" }
      ]
    };
  }
  return coordinateLaw({ frames, relations }, eraId);
}

function value(coordinateValue, name) {
  return coordinateValue.levels.find((entry) => entry.level === name)?.value;
}

// --- Era-qualified year parses and round-trips ------------------------------

test("an era-qualified year parses through a chain-era law and round-trips through formatCoordinateEntry", () => {
  const thirdEra = chainLaw(TAMRIEL_CHAIN, TAMRIEL_LADDER, "era:3e");

  const { coordinate: parsed, depth } = parseCoordinateEntry("3E 433-308 20", thirdEra);
  // The coordinate carries a PLAIN year -- there is no "era" level any more,
  // the frame itself is the era.
  assert.deepEqual(parsed.levels.map((entry) => entry.level), ["year", "day", "hour"]);
  assert.equal(value(parsed, "year"), "433");
  assert.equal(value(parsed, "day"), "308");
  assert.equal(value(parsed, "hour"), "20");
  assert.equal(depth, "hour");
  assert.equal(thirdEra.formatYear(parsed), "3E 433");

  const formatted = formatCoordinateEntry(parsed, thirdEra);
  assert.equal(formatted, "3E 433-308 20", "the era-qualified year formats back to the exact text typed");
  assert.deepEqual(parseCoordinateEntry(formatted, thirdEra).coordinate, parsed);

  // Depth stops exactly at the year itself, same as any other level: typing
  // only "3E 433" yields a coordinate at year precision.
  const yearOnly = parseCoordinateEntry("3E 433", thirdEra);
  assert.equal(yearOnly.depth, "year");
  assert.equal(formatCoordinateEntry(yearOnly.coordinate, thirdEra), "3E 433");

  // A bare number, with no era qualifier at all, is equally legal: the frame
  // already fixes which era is meant.
  assert.deepEqual(parseCoordinateEntry("433-308 20", thirdEra).coordinate, parsed);
});

test("a suffix-affix era ('44 BCE') parses as readily as a prefix one ('3E 433')", () => {
  const bce = chainLaw(BCE_CE_CHAIN, PLAIN_GREGORIAN_LADDER, "era:bce");
  const ce = chainLaw(BCE_CE_CHAIN, PLAIN_GREGORIAN_LADDER, "era:ce");

  const { coordinate: parsedBce, depth } = parseCoordinateEntry("44 BCE 3 15", bce);
  assert.deepEqual(parsedBce.levels.map((entry) => entry.level), ["year", "month", "day"]);
  assert.equal(value(parsedBce, "year"), "44");
  assert.equal(depth, "day");
  assert.equal(bce.formatYear(parsedBce), "44 BCE");
  assert.match(formatCoordinateEntry(parsedBce, bce), /^44 BCE/);

  // The reader may write the number first, too.
  assert.deepEqual(parseCoordinateEntry("44 BCE 3 15", bce).coordinate, parseCoordinateEntry("BCE 44 3 15", bce).coordinate);

  // "44 CE 3 15", parsed under the CE frame's own law, is a different instant.
  const parsedCe = parseCoordinateEntry("44 CE 3 15", ce).coordinate;
  assert.notEqual(bce.toDays(parsedBce).compare(ce.toDays(parsedCe)), 0, "44 BCE and 44 CE are not the same instant");
});

test("a qualifier naming a different era is refused, never silently retargeted onto another frame", () => {
  const thirdEra = chainLaw(TAMRIEL_CHAIN, TAMRIEL_LADDER, "era:3e");
  // "4E 5" is a real position -- in a DIFFERENT era. This field types a
  // position on its own frame's law, not a frame picker, so it refuses
  // rather than silently retargeting the coordinate.
  assert.throws(() => parseCoordinateEntry("4E 5 1", thirdEra), Error);
  // And a year past this era's own 433-year extent is refused too.
  assert.throws(() => parseCoordinateEntry("3E 434 1", thirdEra), Error);
});

test("text naming an unknown era is refused with the law's own help message, never silently read as a number", () => {
  const thirdEra = chainLaw(TAMRIEL_CHAIN, TAMRIEL_LADDER, "era:3e");
  assert.throws(() => parseCoordinateEntry("9Z 12", thirdEra), /year/);
});

test("a February 29 under an era resolves against the PROPER year's leap status, not the number typed within the era", () => {
  const bce = chainLaw(BCE_CE_CHAIN, PLAIN_GREGORIAN_LADDER, "era:bce");
  // 44 BCE is proper year -43 (not divisible by 4): not a leap year.
  assert.throws(() => parseCoordinateEntry("44 BCE 2 29", bce), Error);
  // 45 BCE is proper year -44 (divisible by 4): IS a leap year, though
  // neither two-digit local year looks like one.
  const leap = parseCoordinateEntry("45 BCE 2 29", bce).coordinate;
  assert.equal(value(leap, "day"), "29");

  // The picker ladder resolves the very same rule: the day rung's own option
  // count differs between the two years, driven by the PROPER year even
  // though only the LOCAL one is ever stored or chosen.
  const commonYear = coordinate([{ level: "year", value: "44" }, { level: "month", value: "2" }]);
  const leapYear = coordinate([{ level: "year", value: "45" }, { level: "month", value: "2" }]);
  const commonDay = coordinatePickerLadder(bce, commonYear).find((rung) => rung.level === "day");
  const leapDay = coordinatePickerLadder(bce, leapYear).find((rung) => rung.level === "day");
  assert.equal(commonDay.options.length, 28);
  assert.equal(leapDay.options.length, 29);
});

test("a law with no eras parses and formats byte-identically to before", () => {
  // Pin 1: the registered Gregorian standard.
  const gregorianText = "2026-08-20 17:00:30";
  const gregorianParsed = parseCoordinateEntry(gregorianText, GREGORIAN_LAW).coordinate;
  assert.equal(formatCoordinateEntry(gregorianParsed, GREGORIAN_LAW), gregorianText);
  assert.deepEqual(
    gregorianParsed,
    coordinate([
      { level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "20" },
      { level: "hour", value: "17" }, { level: "minute", value: "0" }, { level: "second", value: "30" }
    ])
  );
  assert.equal(coordinateEntryPlaceholder(GREGORIAN_LAW), "year-month-day hour:minute:second:subsecond");

  // Pin 2: a fully custom, non-Gregorian, eras-free law -- constructed inside
  // this test body, never at module scope.
  const skyland = new CoordinateLaw({
    kind: "nested",
    levels: [
      { name: "epoch" },
      { name: "season", within: "epoch", radix: "8" },
      { name: "pulse", within: "season", radix: "8" }
    ]
  }, { frameId: "line:skyland-era-entry-test" });
  assert.equal(skyland.hasEras(), false);
  const skylandParsed = parseCoordinateEntry("3 5 2", skyland).coordinate;
  assert.equal(formatCoordinateEntry(skylandParsed, skyland), "3 5:2");
  assert.equal(coordinateEntryPlaceholder(skyland), "epoch season:pulse");
});

test("the placeholder advertises the year position honestly under an era law", () => {
  const thirdEra = chainLaw(TAMRIEL_CHAIN, TAMRIEL_LADDER, "era:3e");
  assert.equal(coordinateEntryPlaceholder(thirdEra), "[3E] year-day hour");

  const bce = chainLaw(BCE_CE_CHAIN, PLAIN_GREGORIAN_LADDER, "era:bce");
  assert.equal(coordinateEntryPlaceholder(bce), "[BCE] year-month-day hour:minute:second");
});

// --- The picker ladder: eras are frames, not a level ------------------------

test("the picker ladder offers no era rung of its own -- the law exposes no era level to enumerate", () => {
  const thirdEra = chainLaw(TAMRIEL_CHAIN, TAMRIEL_LADDER, "era:3e");
  const ladder = coordinatePickerLadder(thirdEra, coordinate([]));
  // The root rung is the plain "year" level, unbounded like any root -- there
  // is no separate era rung above it enumerating the chain's keys.
  assert.deepEqual(ladder.map((rung) => rung.level), ["year"]);
  assert.equal(ladder[0].bounded, false);
  assert.deepEqual(ladder[0].options, []);
});

// --- Now-line: mapsToClock() false suppresses the marker entirely ----------
//
// Owner's field note: "no artificial Now line on a calendar with no
// now-mapping." Rendered against the shared stub-DOM harness, not asserted
// from source text: a suppressed marker must leave no element at all, not a
// hidden one or a stray label.

// A Gregorian-shaped ladder (so month/weekday names still resolve through the
// registered standard -- renderIntimate's day headers need a weekday label
// regardless of the Now-line question this fixture exists to test) with an
// authored `clock` flag toggling only the one thing under test.
const CLOCK_TEST_DECLARATION = Object.freeze({
  kind: "gregorian",
  levels: Object.freeze([
    Object.freeze({ name: "year" }),
    Object.freeze({ name: "month", within: "year", transition: "gregorian.months" }),
    Object.freeze({ name: "day", within: "month", transition: "gregorian.days" }),
    Object.freeze({ name: "hour", within: "day", radix: "24" })
  ])
});

function todayOrdinal() {
  const now = new Date();
  return daysFromCivil(BigInt(now.getFullYear()), BigInt(now.getMonth() + 1), BigInt(now.getDate()));
}

function activeGregorianFrameId(document) {
  return Object.values(document.frames).find((frame) => frame.traits?.includes("gregorian")).id;
}

test("Intimate draws no Now marker at all under a law with no now-mapping, though the same focus day draws one under a clock-mapping law", () => {
  const document = createStructuralDocument();
  const activeFrame = activeGregorianFrameId(document);
  const focus = todayOrdinal();

  const render = (law) => {
    const session = new ViewSession({
      projection: "calendar", scale: 0, activeFrame,
      intimateBack: 0, intimateForward: 0,
      focusDays: focus.toString()
    });
    session.setCoordinateLaw(law);
    return renderWithStubDom({ document, engine: new ChronologEngine(document), session });
  };

  const noClockLaw = new CoordinateLaw({ ...CLOCK_TEST_DECLARATION, clock: false }, { frameId: "test:no-clock" });
  assert.equal(noClockLaw.mapsToClock(), false);
  const suppressed = render(noClockLaw);
  assert.equal(findByClass(suppressed, "intimate-now").length, 0, "no marker, not a hidden one");

  const clockLaw = new CoordinateLaw(CLOCK_TEST_DECLARATION, { frameId: "test:clock" });
  assert.equal(clockLaw.mapsToClock(), true);
  const drawn = render(clockLaw);
  assert.equal(findByClass(drawn, "intimate-now").length, 1, "the same focus day DOES draw one when the law maps to the clock");
});

test("Radial draws no Now line under a law with no now-mapping, though the same cycle draws one under a clock-mapping law", () => {
  const document = createStructuralDocument();
  const activeFrame = activeGregorianFrameId(document);
  const focus = todayOrdinal();

  const render = (law) => {
    const session = new ViewSession({
      projection: "radial", radialMode: "concentric", activeFrame,
      activeCycle: "fixed:week", focusDays: focus.toString()
    });
    session.setCoordinateLaw(law);
    session.radialResolution = resolveRadialCycle(FIXED_RADIAL_CYCLES, session.activeCycle, session.currentFocus());
    return renderWithStubDom({ document, engine: new ChronologEngine(document), session });
  };

  const noClockLaw = new CoordinateLaw({ ...CLOCK_TEST_DECLARATION, clock: false }, { frameId: "test:no-clock-radial" });
  const suppressed = render(noClockLaw);
  assert.equal(findByClass(suppressed, "radial-now-line").length, 0);

  const clockLaw = new CoordinateLaw(CLOCK_TEST_DECLARATION, { frameId: "test:clock-radial" });
  const drawn = render(clockLaw);
  assert.equal(findByClass(drawn, "radial-now-line").length, 1, "the week containing today draws its Now line under a clock-mapping law");
});

// The inspector's own date fields, audited against the frames model. Its two
// gates are `law.hasEras()` (which withholds a native `<input type="date">`,
// since one can only ever hold a plain civil year) and `formatCoordinateEntry`
// (which renders the era-qualified year instead). Both are exercised here
// through an era FRAME's law rather than a declaration, because frame identity
// is what carries the era now.
test("an era frame's law drives the inspector's withhold-and-qualify gates", () => {
  const law = chainLaw(TAMRIEL_CHAIN, TAMRIEL_LADDER, "era:3e");
  assert.equal(law.hasEras(), true, "the gate that disables the native date input");
  assert.equal(law.eraKey(), "3E");

  // What the editor shows in place of a civil date: era-qualified, and readable
  // straight back by the same field. Asserted on the year rather than the whole
  // coordinate, so this stays true of whatever ladder the era inherits.
  const value = coordinate([{ level: "year", value: "433" }]);
  const text = formatCoordinateEntry(value, law);
  assert.match(text, /^3E 433/);
  const reparsed = parseCoordinateEntry(text, law).coordinate;
  assert.equal(reparsed.levels.find((level) => level.level === "year").value, "433");
  assert.equal(law.formatYear(reparsed), "3E 433");

  // A frame with no eras keeps the plain civil path untouched.
  const plain = coordinateLaw(
    { frames: { "line:plain": { id: "line:plain", traits: ["line", "gregorian"] } } },
    "line:plain"
  );
  assert.equal(plain.hasEras(), false);
  assert.equal(formatCoordinateEntry(coordinate([
    { level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "20" }
  ]), plain), "2026-08-20");
});
