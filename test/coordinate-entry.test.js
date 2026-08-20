import assert from "node:assert/strict";
import test from "node:test";
import { coordinate } from "../src/exact.js";
import { CoordinateLaw, GREGORIAN_LAW } from "../src/coordinate-law.js";
import {
  coordinateEntryDepth,
  coordinateEntryPlaceholder,
  coordinatePickerLadder,
  formatCoordinateEntry,
  parseCoordinateEntry
} from "../src/coordinate-entry.js";

// A custom, non-Gregorian nested ladder: fixed 8/8/8 radices, authored level
// and value names, no transitions and no family at all. Mirrors the shape of
// fixtures/skyland-coordinate-mapping.chronolog.json's own custom timeline
// (`age > archipelago > sky-day`), but adds authored value names on one level
// so name resolution against a NON-Gregorian vocabulary is exercised too.
const SKYLAND_SEASON_NAMES = Object.freeze([
  "Ashfall", "Ashen", "Waking", "Bloom", "Highsun", "Ember", "Harvest", "Hollow"
]);

const SKYLAND_LAW = new CoordinateLaw({
  kind: "nested",
  levels: [
    { name: "epoch" },
    { name: "season", within: "epoch", radix: "8", names: SKYLAND_SEASON_NAMES },
    { name: "pulse", within: "season", radix: "8" },
    { name: "beat", within: "pulse", radix: "8" }
  ]
}, { frameId: "line:skyland-test" });

function levels(coordinateValue) {
  return coordinateValue.levels.map((entry) => entry.level);
}

function value(coordinateValue, name) {
  return coordinateValue.levels.find((entry) => entry.level === name)?.value;
}

// --- Depth-by-depth parsing under GREGORIAN_LAW -----------------------------

test("each precision depth parses to a partial coordinate with exactly the levels typed, landing on the exact instant", () => {
  const cases = [
    ["2026", coordinate([{ level: "year", value: "2026" }])],
    ["2026 8 20", coordinate([{ level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "20" }])],
    ["2026 8 20 17:00", coordinate([
      { level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "20" },
      { level: "hour", value: "17" }, { level: "minute", value: "0" }
    ])],
    ["2026 8 20 17:00:30.250", coordinate([
      { level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "20" },
      { level: "hour", value: "17" }, { level: "minute", value: "0" }, { level: "second", value: "30" },
      { level: "subsecond", value: "0.250" }
    ])]
  ];
  const depths = ["year", "day", "minute", "subsecond"];

  cases.forEach(([text, expected], index) => {
    const { coordinate: parsed, depth } = parseCoordinateEntry(text, GREGORIAN_LAW);
    assert.deepEqual(parsed, expected, text);
    assert.equal(depth, depths[index], text);
    assert.equal(
      GREGORIAN_LAW.toDays(parsed).compare(GREGORIAN_LAW.toDays(expected)),
      0,
      `${text} must land on the exact same instant as its manually built equivalent`
    );
  });

  // The minute-precision entry is exactly noon plus five hours -- pin the
  // actual day-ordinal arithmetic, not just agreement with itself.
  const minute = parseCoordinateEntry("2026 8 20 17:00", GREGORIAN_LAW).coordinate;
  const days = GREGORIAN_LAW.toDays(minute);
  assert.equal(days.sub(days.floor()).toJSON(), "17/24");
});

// --- Separator tolerance -----------------------------------------------------

test("several spellings of one instant parse to the identical coordinate", () => {
  const spellings = [
    "2026-08-20 17:00:30.250",
    "2026/08/20 17:00:30.250",
    "2026 08 20 17 00 30 250",
    "2026,08,20,17,00,30,250",
    "2026.08.20.17.00.30.250",
    "2026-08-20 17:00:30,250"
  ];
  const [first, ...rest] = spellings.map((text) => parseCoordinateEntry(text, GREGORIAN_LAW).coordinate);
  for (const other of rest) assert.deepEqual(other, first);
});

// --- Authored names ----------------------------------------------------------

test("an authored month name and an unambiguous prefix resolve; an ambiguous prefix throws", () => {
  const byFullName = parseCoordinateEntry("2026 march 4", GREGORIAN_LAW).coordinate;
  assert.equal(value(byFullName, "month"), "3");

  const byPrefix = parseCoordinateEntry("2026 Aug 20", GREGORIAN_LAW).coordinate;
  assert.equal(value(byPrefix, "month"), "8");

  // Too short to attempt prefix resolution at all (< 3 characters).
  assert.throws(() => parseCoordinateEntry("2026 Ju 4", GREGORIAN_LAW), Error);

  // A custom law's own ambiguous prefix: "Ash" matches both "Ashfall" and
  // "Ashen". This must be refused even though neither name is Gregorian.
  assert.throws(() => parseCoordinateEntry("1 Ash", SKYLAND_LAW), Error);
  const unambiguous = parseCoordinateEntry("1 Waking", SKYLAND_LAW).coordinate;
  assert.equal(value(unambiguous, "season"), "2");
});

// --- Round trip ---------------------------------------------------------------

test("format then parse round-trips at day, minute, and subsecond depth", () => {
  const dayCoordinate = coordinate([
    { level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "20" }
  ]);
  assert.equal(formatCoordinateEntry(dayCoordinate, GREGORIAN_LAW), "2026-08-20");
  assert.deepEqual(parseCoordinateEntry(formatCoordinateEntry(dayCoordinate, GREGORIAN_LAW), GREGORIAN_LAW).coordinate, dayCoordinate);

  const minuteCoordinate = coordinate([
    { level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "20" },
    { level: "hour", value: "17" }, { level: "minute", value: "0" }
  ]);
  assert.equal(formatCoordinateEntry(minuteCoordinate, GREGORIAN_LAW), "2026-08-20 17:00");
  assert.deepEqual(parseCoordinateEntry(formatCoordinateEntry(minuteCoordinate, GREGORIAN_LAW), GREGORIAN_LAW).coordinate, minuteCoordinate);

  const subsecondCoordinate = coordinate([
    { level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "20" },
    { level: "hour", value: "17" }, { level: "minute", value: "0" }, { level: "second", value: "30" },
    { level: "subsecond", value: "0.25" }
  ]);
  const roundTripped = parseCoordinateEntry(formatCoordinateEntry(subsecondCoordinate, GREGORIAN_LAW), GREGORIAN_LAW).coordinate;
  assert.deepEqual(roundTripped, subsecondCoordinate);

  // A negative (proleptic) year round-trips through its sign.
  const bceYear = coordinate([{ level: "year", value: "-5" }]);
  assert.equal(formatCoordinateEntry(bceYear, GREGORIAN_LAW), "-5");
  assert.deepEqual(parseCoordinateEntry(formatCoordinateEntry(bceYear, GREGORIAN_LAW), GREGORIAN_LAW).coordinate, bceYear);
});

// --- Range refusal, transition-driven ----------------------------------------

test("2026-02-30 is refused and 2024-02-29 parses, driven by the transition's own childrenIn rule", () => {
  assert.throws(() => parseCoordinateEntry("2026-02-30", GREGORIAN_LAW), Error);
  const leapDay = parseCoordinateEntry("2024-02-29", GREGORIAN_LAW).coordinate;
  assert.equal(value(leapDay, "day"), "29");

  // Month itself is range-checked too: month 13 does not exist.
  assert.throws(() => parseCoordinateEntry("2026-13-01", GREGORIAN_LAW), Error);
  // A below-base level is range-checked against its own radix.
  assert.throws(() => parseCoordinateEntry("2026-01-01 24:00", GREGORIAN_LAW), Error);
});

test("refuses empty input, too many values, and non-numeric non-name tokens, naming the law's own level order", () => {
  assert.throws(() => parseCoordinateEntry("", GREGORIAN_LAW), /year, then month, day, hour, minute, second/);
  assert.throws(() => parseCoordinateEntry("   ", GREGORIAN_LAW), /year, then month, day, hour, minute, second/);
  assert.throws(() => parseCoordinateEntry("2026 8 20 17 0 0 0 0 0", GREGORIAN_LAW), Error);
  assert.throws(() => parseCoordinateEntry("2026 Xyz 20", GREGORIAN_LAW), Error);
});

// --- A fully custom, non-Gregorian law ---------------------------------------

test("a custom 8/8/8 law parses in its own level names and radices; Gregorian names and counts never leak in", () => {
  const { coordinate: parsed, depth } = parseCoordinateEntry("3 Bloom 5 2", SKYLAND_LAW);
  assert.deepEqual(levels(parsed), ["epoch", "season", "pulse", "beat"]);
  assert.equal(depth, "beat");
  assert.equal(value(parsed, "epoch"), "3");
  assert.equal(value(parsed, "season"), "3"); // "Bloom" is index 3, 0-based (no family on this law).
  assert.equal(value(parsed, "pulse"), "5");
  assert.equal(value(parsed, "beat"), "2");

  // A season value at the edge of its own radix (0..7) is fine; radix 8, not
  // Gregorian's 12.
  assert.doesNotThrow(() => parseCoordinateEntry("3 7", SKYLAND_LAW));
  assert.throws(() => parseCoordinateEntry("3 8", SKYLAND_LAW), Error);

  // This law's own names never resolve against Gregorian month names, and its
  // own vocabulary never leaks onto a level Gregorian declares.
  assert.equal(SKYLAND_LAW.namesFor("season")[3], "Bloom");
  assert.equal(SKYLAND_LAW.namesFor("month"), null);
  assert.equal(GREGORIAN_LAW.namesFor("season"), null);

  // Round trip and placeholder both speak this law's own units.
  const formatted = formatCoordinateEntry(parsed, SKYLAND_LAW);
  assert.deepEqual(parseCoordinateEntry(formatted, SKYLAND_LAW).coordinate, parsed);
  // No transition anywhere in this law means "epoch" (the root) is the only
  // above-base level; season/pulse/beat all divide down by radix below it.
  assert.equal(coordinateEntryPlaceholder(SKYLAND_LAW), "epoch season:pulse:beat");
});

// --- coordinateEntryDepth ------------------------------------------------------

test("coordinateEntryDepth reports the deepest law level present, or null for empty, ignoring levels the law does not declare", () => {
  assert.equal(coordinateEntryDepth(coordinate([]), GREGORIAN_LAW), null);
  assert.equal(
    coordinateEntryDepth(coordinate([{ level: "year", value: "2026" }, { level: "month", value: "8" }]), GREGORIAN_LAW),
    "month"
  );
  // A level this law never declared (e.g. an authored custom field) is invisible to depth.
  assert.equal(
    coordinateEntryDepth(coordinate([{ level: "year", value: "2026" }, { level: "sky-day", value: "9" }]), GREGORIAN_LAW),
    "year"
  );
});

// --- Placeholder ---------------------------------------------------------------

test("the placeholder is derived from the law's own declared levels", () => {
  assert.equal(coordinateEntryPlaceholder(GREGORIAN_LAW), "year-month-day hour:minute:second:subsecond");
  assert.equal(coordinateEntryPlaceholder(SKYLAND_LAW), "epoch season:pulse:beat");
});

// --- Picker ladder ---------------------------------------------------------------

test("the picker ladder's day rung differs between a leap and a common February, and the root rung is unbounded with no options", () => {
  const empty = coordinatePickerLadder(GREGORIAN_LAW, coordinate([]));
  assert.equal(empty.length, 1);
  assert.equal(empty[0].level, "year");
  assert.equal(empty[0].bounded, false);
  assert.deepEqual(empty[0].options, []);
  assert.equal(empty[0].chosen, null);

  const commonFebruary = coordinate([{ level: "year", value: "2026" }, { level: "month", value: "2" }]);
  const leapFebruary = coordinate([{ level: "year", value: "2024" }, { level: "month", value: "2" }]);

  const commonLadder = coordinatePickerLadder(GREGORIAN_LAW, commonFebruary);
  const leapLadder = coordinatePickerLadder(GREGORIAN_LAW, leapFebruary);

  assert.deepEqual(commonLadder.map((rung) => rung.level), ["year", "month", "day"]);
  const commonDayRung = commonLadder.find((rung) => rung.level === "day");
  const leapDayRung = leapLadder.find((rung) => rung.level === "day");
  assert.equal(commonDayRung.bounded, true);
  assert.equal(commonDayRung.options.length, 28);
  assert.equal(leapDayRung.options.length, 29);
  assert.equal(commonDayRung.chosen, null);
  assert.equal(commonDayRung.options[0].value, "1");

  // A rung already fixed carries its chosen value, and the drilling stops
  // exactly where the caller's coordinate stops (day-precision input yields
  // rungs down to day plus the open hour rung, never further).
  const dayPrecision = coordinate([{ level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "20" }]);
  const ladder = coordinatePickerLadder(GREGORIAN_LAW, dayPrecision);
  assert.deepEqual(ladder.map((rung) => rung.level), ["year", "month", "day", "hour"]);
  assert.equal(ladder.find((rung) => rung.level === "day").chosen, "20");
  assert.equal(ladder.find((rung) => rung.level === "hour").chosen, null);
  assert.equal(ladder.find((rung) => rung.level === "hour").options.length, 24);

  // Overscale doctrine: an unbounded level never gets a materialized list, and
  // a bounded level's list is never longer than its own count.
  assert.equal(ladder.find((rung) => rung.level === "year").options.length, 0);
});

test("the month rung's options are named from the law's own authored names", () => {
  const ladder = coordinatePickerLadder(GREGORIAN_LAW, coordinate([{ level: "year", value: "2026" }]));
  const monthRung = ladder.find((rung) => rung.level === "month");
  assert.equal(monthRung.options.length, 12);
  assert.equal(monthRung.options[0].label, "January");
  assert.equal(monthRung.options[7].label, "August");
  assert.equal(monthRung.options[7].value, "8");
});

// --- Fuzziness never enters here -----------------------------------------------

test("depth never sets, implies, or returns any fuzziness or spread data", () => {
  const parsed = parseCoordinateEntry("2026 8 20", GREGORIAN_LAW);
  assert.deepEqual(Object.keys(parsed).sort(), ["coordinate", "depth"]);
  assert.deepEqual(Object.keys(parsed.coordinate).sort(), ["levels"]);
  for (const entry of parsed.coordinate.levels) {
    assert.deepEqual(Object.keys(entry).sort(), ["level", "value"]);
  }

  const ladder = coordinatePickerLadder(GREGORIAN_LAW, parsed.coordinate);
  for (const rung of ladder) {
    assert.deepEqual(Object.keys(rung).sort(), ["bounded", "chosen", "label", "level", "options"]);
    for (const option of rung.options) assert.deepEqual(Object.keys(option).sort(), ["label", "value"]);
  }
});

// --- Drilling the picker, rung by rung -----------------------------------------
//
// "or pull a picker that lets you zoom it in." The ladder is derived from the
// coordinate handed in, so DRILLING is just picking a value and asking again --
// there is no picker state to keep, which is why stopping at any depth costs
// nothing and cannot leave a half-open selection behind.

function pick(law, coordinateValue, level, optionValue) {
  return coordinate([
    ...coordinateValue.levels.filter((entry) => entry.level !== level),
    { level, value: optionValue }
  ]);
}

test("drilling the picker coarse to fine reveals exactly one new rung per choice, and stopping is always legal", () => {
  let current = coordinate([]);
  const seen = [];
  for (const [level, choice] of [["year", "2026"], ["month", "8"], ["day", "20"], ["hour", "17"]]) {
    const ladder = coordinatePickerLadder(GREGORIAN_LAW, current);
    const open = ladder.at(-1);
    assert.equal(open.level, level, "the open rung is always the next unfixed level");
    assert.equal(open.chosen, null, "the open rung is open");
    if (open.bounded) {
      assert.ok(open.options.some((option) => option.value === choice), "the choice is offered by the rung itself");
    }
    current = pick(GREGORIAN_LAW, current, level, choice);
    seen.push(level);
    // Every level chosen so far is fixed, and nothing deeper has appeared.
    const after = coordinatePickerLadder(GREGORIAN_LAW, current);
    assert.deepEqual(after.filter((rung) => rung.chosen !== null).map((rung) => rung.level), seen);
    assert.equal(after.length, seen.length + 1, "exactly one rung opens per choice");
    // Stopping here is a complete answer: the coordinate is valid at this depth
    // and resolves to an exact instant.
    assert.equal(coordinateEntryDepth(current, GREGORIAN_LAW), level);
    assert.ok(GREGORIAN_LAW.toDays(current) !== null);
  }
  assert.equal(formatCoordinateEntry(current, GREGORIAN_LAW), "2026-08-20 17");
});

test("re-picking a coarser rung re-derives the finer ones against the new choice", () => {
  const leapFebruary = coordinate([{ level: "year", value: "2024" }, { level: "month", value: "2" }]);
  assert.equal(coordinatePickerLadder(GREGORIAN_LAW, leapFebruary).at(-1).options.length, 29);
  // Change the year alone: the day rung's own count follows, because it is
  // derived from the choices above it rather than remembered.
  const commonFebruary = pick(GREGORIAN_LAW, leapFebruary, "year", "2026");
  assert.equal(coordinatePickerLadder(GREGORIAN_LAW, commonFebruary).at(-1).options.length, 28);
});

test("a custom law's picker offers ITS OWN rungs, counts and names, with no Gregorian leak", () => {
  const ladder = coordinatePickerLadder(SKYLAND_LAW, coordinate([{ level: "epoch", value: "3" }]));
  assert.deepEqual(ladder.map((rung) => rung.level), ["epoch", "season"]);

  const epoch = ladder[0];
  assert.equal(epoch.chosen, "3");
  assert.equal(epoch.bounded, false, "the root has no parent to be counted within");
  assert.deepEqual(epoch.options, []);

  const season = ladder[1];
  assert.equal(season.bounded, true);
  assert.equal(season.options.length, 8, "eight seasons, from this law's own radix");
  assert.deepEqual(season.options.map((option) => option.label), [...SKYLAND_SEASON_NAMES]);
  // The registered Gregorian names and counts must not appear anywhere.
  assert.equal(season.options.some((option) => option.label === "January"), false);
  assert.notEqual(season.options.length, 12);

  const deeper = coordinatePickerLadder(SKYLAND_LAW, coordinate([
    { level: "epoch", value: "3" },
    { level: "season", value: "2" },
    { level: "pulse", value: "5" }
  ]));
  assert.deepEqual(deeper.map((rung) => rung.level), ["epoch", "season", "pulse", "beat"]);
  assert.equal(deeper.at(-1).options.length, 8);
  assert.equal(deeper.at(-1).bounded, true);
});

test("the picker never materializes an option list for an unbounded rung, at any depth", () => {
  for (const law of [GREGORIAN_LAW, SKYLAND_LAW]) {
    for (const rung of coordinatePickerLadder(law, coordinate([]))) {
      if (!rung.bounded) assert.deepEqual(rung.options, []);
    }
  }
  // The continuous tail is unbounded too: subsecond subdivides its parent
  // without a fixed count, so there is nothing to enumerate.
  const full = coordinate([
    { level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "20" },
    { level: "hour", value: "17" }, { level: "minute", value: "30" }, { level: "second", value: "15" }
  ]);
  const tail = coordinatePickerLadder(GREGORIAN_LAW, full).at(-1);
  assert.equal(tail.level, "subsecond");
  assert.equal(tail.bounded, false);
  assert.deepEqual(tail.options, []);
});
