import assert from "node:assert/strict";
import test from "node:test";
import { coordinate } from "../src/exact.js";
import { EraTable } from "../src/eras.js";
import { CoordinateLaw, GREGORIAN_DECLARATION, coordinateLaw, invalidateCoordinateLaws } from "../src/coordinate-law.js";
import { civilCoordinateToDays } from "../src/coordinate-law.js";

// Owner ruling: "Hard No. Epochs, true epochs no faking." An era is a level of
// the coordinate, not a label over a linearized year, and an era may count DOWN.
// These pin both, plus the two fenceposts that make the difference visible: BCE's
// missing year zero, and a descending era's oldest year being its highest number.

// --- The two example laws from the mission ---------------------------------

// Gregorian with eras: BCE descending and open below, CE ascending and open
// above. Year 0 does not exist -- 1 BCE and 1 CE are adjacent.
const BCE_CE_DECLARATION = Object.freeze({
  kind: "gregorian",
  levels: Object.freeze([
    Object.freeze({ name: "era" }),
    Object.freeze({ name: "year", within: "era" }),
    Object.freeze({ name: "month", within: "year", transition: "gregorian.months" }),
    Object.freeze({ name: "day", within: "month", transition: "gregorian.days" }),
    Object.freeze({ name: "hour", within: "day", radix: "24" }),
    Object.freeze({ name: "minute", within: "hour", radix: "60" }),
    Object.freeze({ name: "second", within: "minute", radix: "60" })
  ]),
  eras: Object.freeze({
    anchor: { era: "Common Era", year: "1", properYear: "1" },
    entries: Object.freeze([
      Object.freeze({ name: "Before Common Era", abbrev: "BCE", direction: "descending", affix: "suffix" }),
      Object.freeze({ name: "Common Era", abbrev: "CE", direction: "ascending", affix: "suffix" })
    ])
  })
});

// Tamriel: a uniform 365-day year (12 months of 30 days plus a 5-day span is
// not modelled here -- this is the era ladder's fixture, and the year ladder is
// deliberately the simplest uniform one that exercises it), with a true era
// table: Merethic descending and open below, then three bounded eras, then a
// fourth open above.
const TAMRIEL_DECLARATION = Object.freeze({
  kind: "nested",
  origin: { days: "0" },
  // A uniform ladder has no transition to infer a day from, so it says which of
  // its own levels IS the day.
  baseLevel: "day",
  levels: Object.freeze([
    Object.freeze({ name: "era" }),
    Object.freeze({ name: "year", within: "era" }),
    Object.freeze({ name: "day", within: "year", radix: "365" }),
    Object.freeze({ name: "hour", within: "day", radix: "24" })
  ]),
  eras: Object.freeze({
    anchor: { era: "First Era", year: "1", properYear: "1" },
    entries: Object.freeze([
      Object.freeze({ name: "Merethic Era", abbrev: "ME", direction: "descending" }),
      Object.freeze({ name: "First Era", abbrev: "1E", direction: "ascending", years: "2920" }),
      Object.freeze({ name: "Second Era", abbrev: "2E", direction: "ascending", years: "896" }),
      Object.freeze({ name: "Third Era", abbrev: "3E", direction: "ascending", years: "433" }),
      Object.freeze({ name: "Fourth Era", abbrev: "4E", direction: "ascending" })
    ])
  })
});

function lawFor(declaration, id = "calendar:test") {
  return coordinateLaw({
    frames: { [id]: { id, traits: declaration.kind === "gregorian" ? ["line", "gregorian"] : ["set", "calendar"], coordinate: declaration } }
  }, id);
}

function eraCoordinate(era, year, rest = []) {
  return coordinate([
    { level: "era", value: era },
    { level: "year", value: String(year) },
    ...rest
  ]);
}

// --- The era table itself --------------------------------------------------

test("one anchor plus the bounded spans derives every era's range exactly", () => {
  const table = new EraTable(TAMRIEL_DECLARATION.eras);
  const ranges = Object.fromEntries(table.entries.map((entry) => [entry.abbrev, [entry.firstProper, entry.lastProper]]));
  assert.deepEqual(ranges["1E"], [1n, 2920n]);
  assert.deepEqual(ranges["2E"], [2921n, 3816n]);
  assert.deepEqual(ranges["3E"], [3817n, 4249n]);
  // Open above: the calendar has no last year, and says so rather than picking one.
  assert.deepEqual(ranges["4E"], [4250n, null]);
  // Open below, descending: its newest year abuts 1E 1, its oldest is unbounded.
  assert.deepEqual(ranges.ME, [null, 0n]);
});

test("a descending era's higher number is the older year", () => {
  const table = new EraTable(TAMRIEL_DECLARATION.eras);
  assert.equal(table.toProperYear("ME", "1"), 0n);
  assert.equal(table.toProperYear("ME", "2500"), -2499n);
  assert.ok(table.toProperYear("ME", "2500") < table.toProperYear("ME", "1"));
  // And the inverse recovers the number the author wrote, not its linearization.
  assert.deepEqual(
    { era: table.fromProperYear(-2499n).era, year: table.fromProperYear(-2499n).year },
    { era: "ME", year: 2500n }
  );
});

test("era ordering follows day order across the whole ladder", () => {
  const law = lawFor(TAMRIEL_DECLARATION);
  const days = (era, year) => law.toDays(eraCoordinate(era, year)).toNumber();
  // The mission's acceptance ordering, asserted as a chain.
  const chain = [
    ["ME", 2500], ["ME", 1], ["1E", 1], ["1E", 2920], ["2E", 1]
  ].map(([era, year]) => days(era, year));
  for (const [index, value] of chain.slice(1).entries()) {
    assert.ok(chain[index] < value, `${chain[index]} < ${value}`);
  }
  // Adjacent eras meet with no gap: 1E 2920 and 2E 1 are consecutive years.
  assert.equal(days("2E", 1) - days("1E", 2920), 365);
});

test("a Tamriel-law frame round-trips an era-qualified coordinate exactly", () => {
  const law = lawFor(TAMRIEL_DECLARATION);
  const written = eraCoordinate("Third Era", 433);
  const days = law.toDays(written);
  const back = law.fromDays(days);
  // The stored coordinate carries the ERA and the year WITHIN it -- 433, never
  // the linearized 4249.
  // The stored value is the era's KEY, so renaming "Third Era" never rewrites a record.
  assert.equal(back.levels.find((level) => level.level === "era").value, "3E");
  assert.equal(back.levels.find((level) => level.level === "year").value, "433");
  assert.equal(law.toDays(back).compare(days), 0);
  // And it renders the way it was written.
  assert.equal(law.formatYear(back), "3E 433");
  assert.equal(law.formatYearAtDays(days), "3E 433");
  // The abbreviation is accepted on the way in too.
  assert.equal(law.toDays(eraCoordinate("3E", 433)).compare(days), 0);
});

test("BCE crosses to CE with no year zero", () => {
  const law = lawFor(BCE_CE_DECLARATION, "line:history");
  const at = (era, year, month = 1, day = 1) => law.toDays(eraCoordinate(era, year, [
    { level: "month", value: String(month) },
    { level: "day", value: String(day) }
  ]));

  // 1 BCE is the year immediately before 1 CE: ADJACENT proper years, 0 and 1.
  // The gap between their January firsts is therefore exactly one year and not
  // two -- and that one year is 366 days, because proleptic year 0 is divisible
  // by 400 and so is a leap year. Asserting 366 rather than 365 is the point:
  // the fencepost is real, and getting it wrong by a year would show up here.
  const oneBce = at("BCE", 1);
  const oneCe = at("CE", 1);
  assert.ok(oneBce.compare(oneCe) < 0);
  assert.equal(oneCe.sub(oneBce).toJSON(), "366", "1 BCE runs straight into 1 CE with no year zero between them");
  const table = new EraTable(BCE_CE_DECLARATION.eras);
  assert.equal(table.toProperYear("BCE", "1") + 1n, table.toProperYear("CE", "1"));

  // 44 BCE resolves to proleptic year -43 -- the fencepost, asserted against the
  // registered standard conversion rather than restated as a literal.
  assert.equal(
    at("BCE", 44, 3, 15).toJSON(),
    civilCoordinateToDays(coordinate([
      { level: "year", value: "-43" }, { level: "month", value: "3" }, { level: "day", value: "15" }
    ])).toJSON()
  );

  // Round trip, both sides of the boundary, including the affix this era authored.
  for (const [era, year] of [["BCE", 44], ["BCE", 1], ["CE", 1], ["CE", 2026]]) {
    const days = at(era, year);
    const back = law.fromDays(days);
    assert.equal(back.levels.find((level) => level.level === "era").value, era);
    assert.equal(law.formatYear(back), `${year} ${era}`);
    assert.equal(law.toDays(back).compare(days), 0);
  }
});

test("era-qualified text parses from either side of the number", () => {
  const law = lawFor(TAMRIEL_DECLARATION);
  // Every spelling resolves to the era's KEY, which is what a coordinate stores.
  assert.deepEqual(law.parseYear("3E 433"), { era: "3E", year: "433" });
  assert.deepEqual(law.parseYear("ME 2500"), { era: "ME", year: "2500" });
  assert.deepEqual(law.parseYear("Third Era 433"), { era: "3E", year: "433" });
  // A reader who types the number first means the same date.
  assert.deepEqual(law.parseYear("433 3E"), { era: "3E", year: "433" });
  assert.deepEqual(law.parseYear("3E433"), { era: "3E", year: "433" });
  // Text naming no era at all is distinguishable from text naming an unknown one.
  assert.equal(law.parseYear("433"), null);
  assert.equal(law.parseYear("9Z 12"), null);

  const bce = lawFor(BCE_CE_DECLARATION, "line:history");
  assert.deepEqual(bce.parseYear("44 BCE"), { era: "BCE", year: "44" });
  assert.deepEqual(bce.parseYear("BCE 44"), { era: "BCE", year: "44" });
});

// --- Refusals: an era table that cannot be resolved is not stored ----------

test("an era table whose spans contradict its neighbours is refused", () => {
  const base = TAMRIEL_DECLARATION.eras;
  const withEntries = (entries) => () => new EraTable({ anchor: base.anchor, entries });

  // An open era in the middle leaves both neighbours unresolvable.
  assert.throws(withEntries([
    { name: "First Era", abbrev: "1E", direction: "ascending", years: "2920" },
    { name: "Second Era", abbrev: "2E", direction: "ascending" },
    { name: "Third Era", abbrev: "3E", direction: "ascending", years: "433" }
  ]), /counts up with no stated length.*must be listed last/s);

  // A descending open era anywhere but first is equally unresolvable.
  assert.throws(withEntries([
    { name: "First Era", abbrev: "1E", direction: "ascending", years: "2920" },
    { name: "Merethic Era", abbrev: "ME", direction: "descending" }
  ]), /counts down with no stated length.*must be listed first/s);

  // Two eras answering to the same token cannot be told apart on the way in.
  assert.throws(withEntries([
    { name: "First Era", abbrev: "1E", direction: "ascending", years: "10" },
    { name: "Later Era", abbrev: "1E", direction: "ascending", years: "10" }
  ]), /Two eras answer to "1E"/);

  // A span must be a positive whole number of years.
  assert.throws(withEntries([
    { name: "First Era", abbrev: "1E", direction: "ascending", years: "0" }
  ]), /must be greater than zero/);
  assert.throws(withEntries([
    { name: "First Era", abbrev: "1E", direction: "ascending", years: "12.5" }
  ]), /must be a whole number/);

  // The anchor has to name a real era, and sit inside it.
  assert.throws(() => new EraTable({
    anchor: { era: "Fifth Era", year: "1", properYear: "1" },
    entries: base.entries
  }), /is not one of its eras/);
  assert.throws(() => new EraTable({
    anchor: { era: "Third Era", year: "500", properYear: "1" },
    entries: base.entries
  }), /only 433 years long/);
  // A partly-ordered table has no order at all, and says so.
  assert.throws(withEntries([
    { name: "First Era", abbrev: "1E", direction: "ascending", years: "10", ordinal: "0" },
    { name: "Second Era", abbrev: "2E", direction: "ascending", years: "10" }
  ]), /Either every era declares an ordinal or none does/);

  // A year outside every declared era has no name, and is refused rather than
  // given an invented one.
  const closed = new EraTable({
    anchor: { era: "Only Era", year: "1", properYear: "1" },
    entries: [{ name: "Only Era", abbrev: "OE", direction: "ascending", years: "100" }]
  });
  assert.throws(() => closed.fromProperYear(200n), /falls outside every declared era/);
  assert.throws(() => closed.toProperYear("OE", "101"), /only 100 years long/);
  assert.throws(() => closed.toProperYear("OE", "0"), /numbers its years from 1/);
});

test("a coordinate on an era calendar must name its era", () => {
  const law = lawFor(TAMRIEL_DECLARATION);
  assert.throws(
    () => law.toDays(coordinate([{ level: "year", value: "433" }])),
    /numbers years within eras/
  );
  assert.throws(() => law.toDays(eraCoordinate("9Z", 1)), /is not one of this calendar's eras/);
});

test("an era table needs a year ladder its family can execute", () => {
  // No origin and no transitions: nothing says which day this calendar starts
  // on, so the era table has nothing to anchor against and says so.
  assert.throws(() => new CoordinateLaw({
    kind: "nested",
    baseLevel: "day",
    levels: [{ name: "era" }, { name: "year", within: "era" }, { name: "day", within: "year", radix: "365" }],
    eras: TAMRIEL_DECLARATION.eras
  }, { frameId: "frame:unanchored" }), /needs a year ladder its family can execute/);

  // The era level is governed by the table, so it takes no count of its own.
  assert.throws(() => new CoordinateLaw({
    ...TAMRIEL_DECLARATION,
    levels: [{ name: "era", radix: "4" }, ...TAMRIEL_DECLARATION.levels.slice(1)]
  }, { frameId: "frame:counted-era" }), /governed by the era table, so it takes no count/);
});

// --- The acceptance fixture's own declarative shape ------------------------
//
// fixtures/datasets/elder-scrolls.json authors its era table with `key`,
// `ordinal`, `firstYear` and the explicit string `"open"`. Each of those is a
// better statement than the shape this engine first assumed, so the engine reads
// them; this pins that it does, against the fixture's exact spelling.
test("the fixture's era spelling is read as authored: key, ordinal, firstYear, and an explicit open span", () => {
  const table = new EraTable({
    anchor: { era: "1E", year: "1", properYear: "1" },
    entries: [
      { key: "ME", ordinal: "0", name: "Merethic Era", direction: "descending", firstYear: "1", years: "open" },
      { key: "1E", ordinal: "1", name: "First Era", direction: "ascending", firstYear: "1", years: "2920" },
      { key: "2E", ordinal: "2", name: "Second Era", direction: "ascending", firstYear: "1", years: "896" },
      { key: "3E", ordinal: "3", name: "Third Era", direction: "ascending", firstYear: "1", years: "433" },
      { key: "4E", ordinal: "4", name: "Fourth Era", direction: "ascending", firstYear: "1", years: "open" }
    ]
  });
  assert.deepEqual(table.eraKeys(), ["ME", "1E", "2E", "3E", "4E"]);
  // `"open"` is an open span, not a length -- reading it as one would be a silent
  // misparse rather than a refusal.
  assert.equal(table.era("ME").years, null);
  assert.equal(table.era("4E").years, null);
  assert.equal(table.toProperYear("3E", "433"), 4249n);
  assert.equal(table.toProperYear("ME", "2500"), -2499n);

  // `ordinal` orders the table regardless of the order the entries are listed in.
  const shuffled = new EraTable({
    anchor: { era: "1E", year: "1", properYear: "1" },
    entries: [
      { key: "3E", ordinal: "3", name: "Third Era", direction: "ascending", years: "433" },
      { key: "ME", ordinal: "0", name: "Merethic Era", direction: "descending", years: "open" },
      { key: "4E", ordinal: "4", name: "Fourth Era", direction: "ascending", years: "open" },
      { key: "1E", ordinal: "1", name: "First Era", direction: "ascending", years: "2920" },
      { key: "2E", ordinal: "2", name: "Second Era", direction: "ascending", years: "896" }
    ]
  });
  assert.deepEqual(shuffled.eraKeys(), ["ME", "1E", "2E", "3E", "4E"]);
  assert.equal(shuffled.toProperYear("3E", "433"), 4249n);
});

test("an era's first year is authored, not assumed to be 1", () => {
  // A calendar whose era counts its opening year as 0 is a convention, and the
  // arithmetic has to measure from the number the author actually wrote.
  const table = new EraTable({
    anchor: { era: "ZE", year: "0", properYear: "0" },
    entries: [{ key: "ZE", name: "Zeroth Era", direction: "ascending", firstYear: "0", years: "100" }]
  });
  assert.equal(table.toProperYear("ZE", "0"), 0n);
  assert.equal(table.toProperYear("ZE", "99"), 99n);
  assert.equal(table.fromProperYear(0n).year, 0n);
  assert.throws(() => table.toProperYear("ZE", "100"), /only 100 years long/);
  assert.throws(() => table.toProperYear("ZE", "-1"), /numbers its years from 0/);
});

// --- Positionality is decided by the registry, never by a label ------------

test("an executable ladder is positional whatever its kind string says", () => {
  // Measured defect: an identical year > month > day declaration resolved
  // positional=false purely because its `kind` was spelled "nested", and
  // 2026-08-20 then read as day ordinal 20 -- off by fifty-six years, silently.
  // Positionality is a property of the LADDER and the REGISTRY.
  const declaration = {
    kind: "nested",
    levels: [
      { name: "year" },
      { name: "month", within: "year", transition: "gregorian.months", names: ["Frimaire", "Nivose", "Pluviose", "Ventose", "Germinal", "Floreal", "Prairial", "Messidor", "Thermidor", "Fructidor", "Vendemiaire", "Brumaire"] },
      { name: "day", within: "month", transition: "gregorian.days" }
    ]
  };
  const law = coordinateLaw({
    frames: { "calendar:renamed": { id: "calendar:renamed", traits: ["set", "calendar"], coordinate: declaration } }
  }, "calendar:renamed");

  assert.equal(law.positional, true, "the family can execute this ladder, so it is positional");
  const value = coordinate([
    { level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "20" }
  ]);
  assert.equal(law.toDays(value).compare(civilCoordinateToDays(value)), 0);
  assert.notEqual(law.toDays(value).toJSON(), "20");
  // Its own authored names still win over the registered ones.
  assert.equal(law.monthNames()[0], "Frimaire");
});

test("a measure frame stays a magnitude, because that is what the trait says it is", () => {
  // The one marker that survives is `measure`, and it is not a label for
  // arithmetic -- it says what the frame IS. Its levels are counts.
  const law = coordinateLaw({
    frames: {
      "measure:span": {
        id: "measure:span",
        traits: ["line", "measure", "duration"],
        coordinate: {
          kind: "nested",
          levels: [
            { name: "year" },
            { name: "day", within: "year", transition: "gregorian.daysInYear" },
            { name: "hour", within: "day", radix: "24" }
          ]
        }
      }
    }
  }, "measure:span");
  assert.equal(law.positional, false);
  assert.equal(law.toDays(coordinate([{ level: "day", value: "5" }])).toJSON(), "5");
});

test("a law with no family refuses a positional coordinate instead of reading it as a count", () => {
  // Measured defect: a {year, month, day} coordinate handed to a family-less law
  // whose base level happened to be `day` placed 1973-03-15 at day 15.
  const law = coordinateLaw({
    frames: {
      "measure:m": {
        id: "measure:m",
        traits: ["measure"],
        coordinate: { kind: "nested", levels: [{ name: "day" }, { name: "hour", within: "day", radix: "24" }] }
      }
    }
  }, "measure:m");
  assert.throws(() => law.toDays(coordinate([
    { level: "year", value: "1973" }, { level: "month", value: "3" }, { level: "day", value: "15" }
  ])), /declares no year, month level/);
  // A value made only of levels it does declare still reads as the count it is.
  assert.equal(law.toDays(coordinate([{ level: "day", value: "15" }])).toJSON(), "15");
});

// --- Documents without era tables are untouched ----------------------------

test("a law with no era table behaves exactly as before", () => {
  const law = new CoordinateLaw(GREGORIAN_DECLARATION, { frameId: "gregorian" });
  assert.equal(law.hasEras(), false);
  assert.deepEqual(law.eras(), []);
  assert.equal(law.parseYear("44 BCE"), null);
  // The plain proleptic year axis remains the default, and `formatYear` reports
  // the bare year rather than inventing an era for it.
  const value = coordinate([
    { level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "20" }
  ]);
  assert.equal(law.formatYear(value), "2026");
  assert.equal(law.toDays(value).compare(civilCoordinateToDays(value)), 0);
  assert.deepEqual(law.fromDays(law.toDays(value)), value);
});

test("only a positional law claims a place on the running clock", () => {
  assert.equal(new CoordinateLaw(GREGORIAN_DECLARATION).mapsToClock(), true);
  assert.equal(lawFor(TAMRIEL_DECLARATION).mapsToClock(), true, "an authored origin IS a mapping to real days");
  // A frame that says outright it has no now does not get one drawn on it.
  assert.equal(new CoordinateLaw({ ...TAMRIEL_DECLARATION, clock: false }).mapsToClock(), false);
  // A measure frame has no positions at all, so it has no now either.
  const measure = coordinateLaw({
    frames: { "measure:m": { id: "measure:m", traits: ["measure"], coordinate: { kind: "nested", levels: [{ name: "day" }, { name: "hour", within: "day", radix: "24" }] } } }
  }, "measure:m");
  assert.equal(measure.mapsToClock(), false);
});

test("a uniform ladder with an authored origin converts positionally, and is no CLDR calendar scale", () => {
  const law = lawFor(TAMRIEL_DECLARATION);
  assert.equal(law.positional, true);
  // No registered CLDR scale: a series counting in it is not ICS-expressible as
  // a rule, which is what the ICS contract asks this question for.
  assert.equal(law.calendarScale(), null);
  // Its own units, exactly: a 365-day year of 24-hour days.
  assert.equal(law.unitDays("year").toJSON(), "365");
  assert.equal(law.unitDays("day").toJSON(), "1");
  assert.equal(law.unitDays("hour").toJSON(), "1/24");
  // Day-in-year is 1-based and lands where it says.
  const first = law.toDays(eraCoordinate("1E", 1, [{ level: "day", value: "1" }]));
  const second = law.toDays(eraCoordinate("1E", 1, [{ level: "day", value: "2" }]));
  assert.equal(second.sub(first).toJSON(), "1");
  assert.equal(first.toJSON(), "0", "1E 1 day 1 sits on the authored origin day");
});

test("an era table survives the memoized-law cache the way any declaration does", () => {
  const id = "calendar:tamriel";
  const document = {
    frames: { [id]: { id, traits: ["set", "calendar"], coordinate: TAMRIEL_DECLARATION } }
  };
  assert.equal(coordinateLaw(document, id).formatYearAtDays(0), "1E 1");
  document.frames[id] = {
    ...document.frames[id],
    coordinate: {
      ...TAMRIEL_DECLARATION,
      eras: {
        anchor: TAMRIEL_DECLARATION.eras.anchor,
        entries: TAMRIEL_DECLARATION.eras.entries.map((entry) =>
          entry.abbrev === "1E" ? { ...entry, abbrev: "IE" } : entry)
      }
    }
  };
  invalidateCoordinateLaws(document);
  assert.equal(coordinateLaw(document, id).formatYearAtDays(0), "IE 1");
});
