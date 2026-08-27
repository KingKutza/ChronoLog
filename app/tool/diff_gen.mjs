// Differential harness, JavaScript side. Generates random declarations,
// coordinates and era tables from a fixed seed, runs them through the shipped
// src/coordinate-law.js and src/eras.js, and writes every answer as an exact
// string to stdout as one JSON document. app/tool/diff_check.dart replays the
// same cases through the Dart port and compares.
//
// Run, from app/:
//
//   dart run tool/diff_check.dart
//
// which shells out to node itself. To keep the cases for inspection, redirect
// into app/build/ (already ignored):
//
//   node tool/diff_gen.mjs > build/diff-cases.json
//   dart run tool/diff_check.dart build/diff-cases.json
//
// Nothing here is a test of the JavaScript. It is the oracle: any disagreement
// is either a port defect or a deliberate, documented deviation.

import { Rational, coordinate } from "../../src/exact.js";
import {
  CoordinateLaw,
  GREGORIAN_DECLARATION,
  registeredCalendars,
  registeredTransitions
} from "../../src/coordinate-law.js";
import { EraTable } from "../../src/eras.js";

const SEED = 20260827;

function mulberry32(seed) {
  return function next() {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const rnd = mulberry32(SEED);
const int = (bound) => Math.floor(rnd() * bound);
const pick = (items) => items[int(items.length)];

const ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";

function word(used) {
  for (;;) {
    let text = "";
    for (let index = 0, length = 3 + int(6); index < length; index += 1) {
      text += ALPHABET[int(ALPHABET.length)];
    }
    if (!used.has(text.toLowerCase())) {
      used.add(text.toLowerCase());
      return text;
    }
  }
}

const STANDARD = {
  week: Rational.parse("7"),
  day: Rational.parse("1"),
  hour: Rational.parse("1/24"),
  minute: Rational.parse("1/1440"),
  second: Rational.parse("1/86400")
};

// The melt under test: one `unitsPer(name, per)` replacing six named wrappers
// that each re-hardcoded their own fallback. Reimplemented here so the Dart
// port is compared against a stated rule rather than against six rules.
function meltUnitsPer(law, name, per) {
  const unit = law.unitDays(name) ?? law.meanUnitDays(name);
  const parent = per === undefined ? law.baseDays : (law.unitDays(per) ?? law.meanUnitDays(per));
  if (unit === null || unit.isZero() || parent === null || parent.isZero()) {
    const standardUnit = STANDARD[name];
    const standardParent = STANDARD[per ?? "day"];
    if (!standardUnit || !standardParent || standardUnit.isZero()) return Rational.parse("1");
    return standardParent.div(standardUnit);
  }
  return parent.div(unit);
}

const exact = (value) => (value === null || value === undefined ? null : value.toJSON());
const asPairs = (value) => value.levels.map((entry) => [entry.level, entry.value]);

function attempt(body) {
  try {
    return { ok: body() };
  } catch (error) {
    return { error: String(error?.message ?? error) };
  }
}

// --- Generators -------------------------------------------------------------

function randomLadder() {
  const depth = 2 + int(4);
  const used = new Set();
  const names = [];
  for (let index = 0; index < depth; index += 1) names.push(word(used));
  const radices = [1];
  for (let index = 1; index < depth; index += 1) radices.push(2 + int(39));
  const baseIndex = 1 + int(depth - 1);
  const origin = String(int(4001) - 2000);
  const atomDays = rnd() < 0.5 ? null : `1/${1 + int(100)}`;
  const declaration = {
    kind: "nested",
    origin: { days: origin },
    baseLevel: names[baseIndex],
    ...(atomDays === null ? {} : { atomDays }),
    levels: names.map((name, index) => ({
      name,
      ...(index > 0 ? { within: names[index - 1], radix: String(radices[index]) } : {})
    }))
  };
  return { names, radices, baseIndex, declaration };
}

function ladderCoordinate(ladder) {
  return coordinate(ladder.names.map((name, index) => ({
    level: name,
    value: String(
      index === 0
        ? int(2001) - 1000
        : index <= ladder.baseIndex
          ? 1 + int(ladder.radices[index])
          : int(ladder.radices[index])
    )
  })));
}

function civilLadder() {
  const hours = 1 + int(40);
  const minutes = 1 + int(90);
  const seconds = 1 + int(90);
  const tail = rnd() < 0.7;
  const signature = pick([
    "gregorian.months+gregorian.days",
    "gregorian.months",
    "gregorian.daysInYear",
    ""
  ]);
  const levels = [{ name: "year" }];
  if (signature === "gregorian.months+gregorian.days") {
    levels.push({ name: "month", within: "year", transition: "gregorian.months" });
    levels.push({ name: "day", within: "month", transition: "gregorian.days" });
  } else if (signature === "gregorian.months") {
    levels.push({ name: "month", within: "year", transition: "gregorian.months" });
  } else if (signature === "gregorian.daysInYear") {
    levels.push({ name: "day", within: "year", transition: "gregorian.daysInYear" });
  }
  const deepest = levels[levels.length - 1].name;
  levels.push({ name: "hour", within: deepest, radix: String(hours) });
  levels.push({ name: "minute", within: "hour", radix: String(minutes) });
  levels.push({ name: "second", within: "minute", radix: String(seconds) });
  if (tail) levels.push({ name: "subsecond", within: "second" });
  return { signature, hours, minutes, seconds, declaration: { kind: "gregorian", levels } };
}

function civilCoordinate(shape) {
  const parts = [{ level: "year", value: String(int(6000) - 3000) }];
  if (shape.signature.includes("gregorian.months")) {
    parts.push({ level: "month", value: String(1 + int(12)) });
  }
  if (shape.signature.includes("+gregorian.days")) {
    parts.push({ level: "day", value: String(1 + int(28)) });
  }
  if (shape.signature === "gregorian.daysInYear") {
    parts.push({ level: "day", value: String(1 + int(365)) });
  }
  parts.push({ level: "hour", value: String(int(shape.hours)) });
  parts.push({ level: "minute", value: String(int(shape.minutes)) });
  parts.push({ level: "second", value: String(int(shape.seconds)) });
  return coordinate(parts);
}

function brokenDeclaration() {
  const used = new Set();
  const first = word(used);
  const second = word(used);
  const absent = word(used);
  return pick([
    { levels: [{ name: first }, { name: first, within: first, radix: "2" }] },
    { levels: [{ name: first }, { name: second, within: absent, radix: "2" }] },
    { levels: [{ name: first }, { name: second, within: first, radix: "0" }] },
    { levels: [{ name: first }, { name: second, within: first, radix: `${1 + 2 * int(9)}/2` }] },
    { levels: [{ name: first }, { name: second, within: first, radix: absent }] },
    { levels: [{ name: first }, { name: "" }] },
    {
      levels: [
        { name: first },
        { name: second, within: first, radix: "7", transition: "gregorian.months" }
      ]
    },
    {
      kind: "gregorian",
      levels: [{ name: "year" }, { name: "month", within: "year", transition: `${absent}.months` }]
    },
    {
      kind: "gregorian",
      levels: [{ name: "year" }, { name: "day", within: "year", transition: "gregorian.days" }]
    },
    { levels: [{ name: first }, { name: second, within: first, radix: "3" }], baseLevel: absent },
    {
      levels: [{ name: first }, { name: second, within: first, radix: "3" }],
      origin: { days: "5" },
      fixed: { epochDays: String(1 + int(500)) }
    },
    { levels: [{ name: first }], atomDays: `-${1 + int(500)}` },
    {
      levels: [{ name: first }],
      cycles: [{ name: second, radix: String(2 + int(9)), names: [absent, first] }]
    },
    { levels: [{ name: first }], cycles: [{ name: "", radix: "7" }] },
    { levels: [{ name: first }], cycles: [{ name: second, radix: absent }] }
  ]);
}

function randomEraTable() {
  const count = 1 + int(5);
  const used = new Set();
  const entries = [];
  const descendingFirst = count > 1 && rnd() < 0.5;
  const openLast = rnd() < 0.5;
  for (let index = 0; index < count; index += 1) {
    const descending = index === 0 && descendingFirst;
    const open = descending ? rnd() < 0.5 : index === count - 1 && openLast;
    entries.push({
      name: `${word(used)} Era`,
      key: word(used),
      direction: descending ? "descending" : "ascending",
      firstYear: String(int(3)),
      years: open ? "open" : String(1 + int(3000)),
      ...(rnd() < 0.5 ? { affix: "suffix" } : {})
    });
  }
  const anchored = entries[int(count)];
  const firstYear = Number(anchored.firstYear);
  const span = anchored.years === "open" ? 20 : Number(anchored.years);
  return {
    anchor: {
      era: anchored.key,
      year: String(firstYear + int(span)),
      properYear: String(int(8001) - 4000)
    },
    entries
  };
}

function brokenEraTable() {
  const used = new Set();
  const first = word(used);
  const second = word(used);
  const anchor = { era: first, year: "1", properYear: "1" };
  return pick([
    { anchor, entries: [] },
    {
      anchor,
      entries: [
        { key: first, name: `${first} Era`, direction: "ascending", years: "10" },
        { key: second, name: `${second} Era`, direction: "ascending" },
        { key: `${second}x`, name: `${second}x Era`, direction: "ascending", years: "10" }
      ]
    },
    {
      anchor,
      entries: [
        { key: first, name: `${first} Era`, direction: "ascending", years: "10" },
        { key: second, name: `${second} Era`, direction: "descending" }
      ]
    },
    {
      anchor,
      entries: [
        { key: first, name: `${first} Era`, direction: "ascending", years: "10" },
        { key: first, name: `${second} Era`, direction: "ascending", years: "10" }
      ]
    },
    { anchor, entries: [{ key: first, name: `${first} Era`, direction: "ascending", years: "0" }] },
    {
      anchor,
      entries: [{ key: first, name: `${first} Era`, direction: "ascending", years: "12.5" }]
    },
    {
      anchor,
      entries: [{ key: String(1 + int(99)), name: `${first} Era`, direction: "ascending", years: "5" }]
    },
    {
      anchor,
      entries: [{ key: first, name: String(1 + int(99)), direction: "ascending", years: "5" }]
    },
    {
      anchor,
      entries: [{ key: first, name: `${first} Era`, direction: word(used), years: "5" }]
    },
    {
      anchor,
      entries: [{ key: first, name: `${first} Era`, direction: "ascending", years: "5", affix: word(used) }]
    },
    {
      anchor: { era: second, year: "1", properYear: "1" },
      entries: [{ key: first, name: `${first} Era`, direction: "ascending", years: "5" }]
    },
    {
      anchor: { era: first, year: "99", properYear: "1" },
      entries: [{ key: first, name: `${first} Era`, direction: "ascending", years: "5" }]
    },
    {
      anchor,
      entries: [
        { key: first, name: `${first} Era`, direction: "ascending", years: "10", ordinal: "0" },
        { key: second, name: `${second} Era`, direction: "ascending", years: "10" }
      ]
    },
    {
      anchor,
      entries: [
        { key: first, name: `${first} Era`, direction: "ascending", years: "10", ordinal: "2" },
        { key: second, name: `${second} Era`, direction: "ascending", years: "10", ordinal: "2" }
      ]
    },
    { anchor, entries: [{ name: "", direction: "ascending", years: "5" }] },
    {
      anchor,
      entries: [{ key: first, name: `${first}, Era`, direction: "ascending", years: "5" }]
    }
  ]);
}

// --- Probing ----------------------------------------------------------------

function probeLaw(declaration, frameId, positional, era, coordinates, ordinals) {
  const built = attempt(() => new CoordinateLaw(declaration, { frameId, positional, era }));
  if (built.error) return { refusal: built.error };
  const law = built.ok;
  const names = [...law.levelNames(), "week", "day", "hour", "minute", "second", "fortnight"];
  const perParent = [
    ["minute", "hour"],
    ["second", "minute"],
    [law.baseLevel, "week"],
    ["hour", "day"]
  ];
  return {
    atomLevel: law.atomLevel,
    atomDays: exact(law.atomDays),
    baseLevel: law.baseLevel,
    baseDays: exact(law.baseDays),
    baseAtoms: exact(law.baseAtoms),
    epochDays: exact(law.epochDays),
    originDays: exact(law.originDays),
    positional: law.positional,
    inheritsRegistered: law.inheritsRegistered,
    calendarScale: law.calendarScale(),
    mapsToClock: law.mapsToClock(),
    sharesStandardAtom: law.sharesStandardAtom(),
    hasEras: law.hasEras(),
    eraKey: law.eraKey() ?? null,
    levelNames: law.levelNames(),
    monthNames: law.monthNames(),
    weekdayNames: law.weekdayNames(),
    unitDays: Object.fromEntries(names.map((name) => [name, exact(law.unitDays(name))])),
    unitAtoms: Object.fromEntries(names.map((name) => [name, exact(law.unitAtoms(name))])),
    meanUnitDays: Object.fromEntries(names.map((name) => [name, exact(law.meanUnitDays(name))])),
    meanMonthDays: exact(law.meanMonthDays()),
    unitsPer: Object.fromEntries(
      names.map((name) => [name, exact(meltUnitsPer(law, name, undefined))])
    ),
    unitsPerParent: perParent.map(([name, per]) => [name, per, exact(meltUnitsPer(law, name, per))]),
    // The six wrappers the melt replaces, for a divergence report rather than a
    // pass/fail: their fallback policies differed from each other by accident.
    wrappers: {
      hoursPerDay: exact(law.hoursPerDay()),
      minutesPerDay: exact(law.minutesPerDay()),
      secondsPerDay: exact(law.secondsPerDay()),
      minutesPerHour: exact(law.minutesPerHour()),
      secondsPerMinute: exact(law.secondsPerMinute()),
      daysPerWeek: exact(law.daysPerWeek())
    },
    cycles: law.cycles().map((cycle) => cycle.name),
    cycleLabels: ordinals.map((days) => [
      days,
      law.weekdayLabel(days),
      law.cycleIndex("weekday", days)
    ]),
    toDays: coordinates.map((value) => {
      const answer = attempt(() => law.toDays(value));
      return {
        value: asPairs(value),
        days: answer.error ? null : exact(answer.ok),
        error: answer.error ?? null
      };
    }),
    fromDays: ordinals.map((days) => {
      const answer = attempt(() => law.fromDays(days));
      return {
        days,
        coordinate: answer.error ? null : asPairs(answer.ok),
        error: answer.error ?? null
      };
    }),
    formatYear: coordinates.map((value) => {
      const answer = attempt(() => law.formatYear(value));
      return { value: asPairs(value), text: answer.error ? null : answer.ok, error: answer.error ?? null };
    }),
    parseYear: coordinates.map((value) => {
      const text = attempt(() => law.formatYear(value));
      if (text.error) return { text: null, parsed: null };
      const parsed = law.parseYear(text.ok);
      return { text: text.ok, parsed: parsed ? [parsed.era, parsed.year] : null };
    }),
    magnitudeDays: coordinates.map((value) => [
      asPairs(value),
      exact(law.magnitudeDays({ value: { levels: value.levels } }))
    ])
  };
}

function probeEraTable(declaration) {
  const built = attempt(() => new EraTable(declaration));
  if (built.error) return { refusal: built.error };
  const table = built.ok;
  const probes = [];
  for (const entry of table.entries) {
    const span = entry.years === null ? 20 : Number(entry.years);
    for (let round = 0; round < 3; round += 1) {
      const year = (entry.firstYear + BigInt(int(span))).toString();
      const proper = attempt(() => table.toProperYear(entry.key, year));
      const text = attempt(() => table.format(entry.key, year));
      const back = proper.error ? { error: proper.error } : attempt(() => table.fromProperYear(proper.ok));
      probes.push({
        era: entry.key,
        year,
        proper: proper.error ? null : proper.ok.toString(),
        properError: proper.error ?? null,
        text: text.error ? null : text.ok,
        back: back.error ? null : [back.ok.key, back.ok.year.toString()],
        parsedPrefix: (() => {
          const parsed = table.parse(`${entry.key} ${year}`);
          return parsed ? [parsed.era, parsed.year] : null;
        })(),
        parsedSuffix: (() => {
          const parsed = table.parse(`${year} ${entry.key}`);
          return parsed ? [parsed.era, parsed.year] : null;
        })(),
        parsedName: (() => {
          const parsed = table.parse(`${entry.name} ${year}`);
          return parsed ? [parsed.era, parsed.year] : null;
        })(),
        parsedBare: (() => {
          const parsed = table.parse(`${entry.key}${year}`);
          return parsed ? [parsed.era, parsed.year] : null;
        })()
      });
    }
  }
  const outside = attempt(() => table.fromProperYear(BigInt(int(200001) - 100000)));
  return {
    entries: table.entries.map((entry) => ({
      key: entry.key,
      name: entry.name,
      direction: entry.direction,
      years: entry.years === null ? null : entry.years.toString(),
      firstYear: entry.firstYear.toString(),
      affix: entry.affix,
      firstProper: entry.firstProper === null ? null : entry.firstProper.toString(),
      lastProper: entry.lastProper === null ? null : entry.lastProper.toString()
    })),
    eraKeys: table.eraKeys(),
    eraNames: table.eraNames(),
    summary: table.summary(),
    declarationBack: table.toDeclaration(),
    outside: outside.error ? { error: outside.error } : { ok: [outside.ok.key, outside.ok.year.toString()] },
    probes
  };
}

// --- Case assembly ----------------------------------------------------------

const cases = [];

cases.push({
  kind: "registry",
  transitions: registeredTransitions(),
  calendars: registeredCalendars()
});

for (let index = 0; index < 400; index += 1) {
  const ladder = randomLadder();
  const coordinates = [];
  for (let round = 0; round < 3; round += 1) coordinates.push(ladderCoordinate(ladder));
  // A foreign coordinate, to pin the refusal, and a bare base-level count.
  coordinates.push(coordinate([
    { level: "year", value: "1973" },
    { level: "month", value: "3" },
    { level: "day", value: "15" }
  ]));
  const ordinals = [];
  for (let round = 0; round < 3; round += 1) {
    ordinals.push(Rational.parse(String(int(400001) - 200000)).mul(Rational.parse("1/97")).toJSON());
  }
  cases.push({
    kind: "law",
    frameId: `frame:uniform-${index}`,
    positional: pick([undefined, true, false]) ?? null,
    positionalGiven: undefined,
    declaration: ladder.declaration,
    coordinates: coordinates.map(asPairs),
    ordinals,
    probes: null
  });
}

for (let index = 0; index < 300; index += 1) {
  const shape = civilLadder();
  const coordinates = [];
  for (let round = 0; round < 3; round += 1) coordinates.push(civilCoordinate(shape));
  const ordinals = [];
  for (let round = 0; round < 3; round += 1) {
    ordinals.push(Rational.parse(String(int(2000001) - 1000000)).mul(Rational.parse("1/86400")).toJSON());
  }
  cases.push({
    kind: "law",
    frameId: `frame:civil-${index}`,
    positional: null,
    declaration: shape.declaration,
    coordinates: coordinates.map(asPairs),
    ordinals,
    probes: null
  });
}

cases.push({
  kind: "law",
  frameId: "gregorian",
  positional: null,
  declaration: GREGORIAN_DECLARATION,
  coordinates: [
    [["year", "2026"], ["month", "8"], ["day", "20"], ["hour", "12"], ["minute", "0"], ["second", "0"]],
    [["year", "1970"], ["month", "1"], ["day", "1"]],
    [["year", "-44"], ["month", "3"], ["day", "15"]]
  ],
  ordinals: ["0", "1/2", "-20000", "20000", "1/86400", "146097"],
  probes: null
});

// Declarations whose BASE LEVEL has no constant length (a Gregorian month or
// year), which is the only shape where the six named wrappers' fallback policies
// could diverge from the melt's single one. Generated deliberately, because the
// ordinary distribution never reaches it.
for (let index = 0; index < 200; index += 1) {
  const base = pick(["year", "month", "day", "hour"]);
  const declaration = {
    kind: "gregorian",
    baseLevel: base,
    levels: [
      { name: "year" },
      { name: "month", within: "year", transition: "gregorian.months" },
      { name: "day", within: "month", transition: "gregorian.days" },
      { name: "hour", within: "day", radix: String(1 + int(40)) },
      { name: "minute", within: "hour", radix: String(1 + int(90)) },
      { name: "second", within: "minute", radix: "60" },
      ...(rnd() < 0.5 ? [{ name: "subsecond", within: "second" }] : [])
    ]
  };
  cases.push({
    kind: "law",
    frameId: `frame:variable-base-${index}`,
    positional: null,
    declaration,
    coordinates: [
      [["year", String(int(4000) - 2000)], ["month", String(1 + int(12))], ["day", String(1 + int(28))]],
      [["year", "2026"], ["month", "8"], ["day", "20"], ["hour", "3"], ["minute", "4"]]
    ],
    ordinals: ["0", "1/3", String(int(40001) - 20000)],
    probes: null
  });
}

for (let index = 0; index < 300; index += 1) {
  cases.push({
    kind: "law",
    frameId: `frame:broken-${index}`,
    positional: null,
    declaration: brokenDeclaration(),
    coordinates: [],
    ordinals: [],
    probes: null
  });
}

for (let index = 0; index < 300; index += 1) {
  cases.push({ kind: "era-table", declaration: randomEraTable(), probes: null });
}

for (let index = 0; index < 200; index += 1) {
  cases.push({ kind: "era-table", declaration: brokenEraTable(), probes: null });
}

// Era laws: a real era table injected onto a real year ladder, exactly as the
// resolver will hand it over once the succession chain ships.
for (let index = 0; index < 200; index += 1) {
  const tableDeclaration = randomEraTable();
  const built = attempt(() => new EraTable(tableDeclaration));
  if (built.error) continue;
  const table = built.ok;
  const entry = table.entries[int(table.entries.length)];
  const gregorian = rnd() < 0.5;
  const declaration = gregorian
    ? GREGORIAN_DECLARATION
    : {
        kind: "nested",
        baseLevel: "day",
        origin: { days: "0" },
        levels: [
          { name: "year" },
          { name: "day", within: "year", radix: String(300 + int(200)) },
          { name: "hour", within: "day", radix: String(1 + int(40)) }
        ]
      };
  const span = entry.years === null ? 20 : Number(entry.years);
  const coordinates = [];
  for (let round = 0; round < 3; round += 1) {
    const year = (entry.firstYear + BigInt(int(span))).toString();
    coordinates.push(
      gregorian
        ? [["year", year], ["month", String(1 + int(12))], ["day", String(1 + int(28))]]
        : [["year", year], ["day", String(1 + int(200))]]
    );
  }
  // One year past this era's own extent, to pin the refusal.
  coordinates.push([["year", (entry.firstYear + BigInt(span)).toString()]]);
  const ordinals = [];
  for (let round = 0; round < 3; round += 1) {
    ordinals.push(String(int(2000001) - 1000000));
  }
  cases.push({
    kind: "era-law",
    frameId: `era:${entry.key}`,
    declaration,
    eraTable: tableDeclaration,
    eraKey: entry.key,
    countable: true,
    coordinates,
    ordinals,
    probes: null
  });
}

for (let index = 0; index < 100; index += 1) {
  const used = new Set();
  cases.push({
    kind: "era-law",
    frameId: `era:dawn-${index}`,
    declaration: GREGORIAN_DECLARATION,
    eraTable: null,
    eraKey: word(used),
    eraName: `${word(used)} Era`,
    countable: false,
    coordinates: [[["year", "2026"], ["month", "8"], ["day", "20"]]],
    ordinals: ["0", "12345"],
    probes: null
  });
}

// --- Run the oracle ---------------------------------------------------------

for (const item of cases) {
  if (item.kind === "law") {
    item.probes = probeLaw(
      item.declaration,
      item.frameId,
      item.positional === null ? undefined : item.positional,
      null,
      item.coordinates.map((pairs) =>
        coordinate(pairs.map(([level, value]) => ({ level, value })))),
      item.ordinals
    );
  } else if (item.kind === "era-table") {
    item.probes = probeEraTable(item.declaration);
  } else if (item.kind === "era-law") {
    let era = null;
    if (item.countable) {
      const table = new EraTable(item.eraTable);
      era = {
        countable: true,
        table,
        entry: table.entries.find((entry) => entry.key === item.eraKey)
      };
    } else {
      era = { countable: false, key: item.eraKey, name: item.eraName };
    }
    item.probes = probeLaw(
      item.declaration,
      item.frameId,
      undefined,
      era,
      item.coordinates.map((pairs) =>
        coordinate(pairs.map(([level, value]) => ({ level, value })))),
      item.ordinals
    );
  }
  delete item.positionalGiven;
}

process.stdout.write(JSON.stringify({ seed: SEED, cases }));
