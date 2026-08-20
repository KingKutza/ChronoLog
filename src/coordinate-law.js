import {
  Rational,
  civilFromDays,
  coordinate,
  daysFromCivil,
  daysInMonth,
  floorDiv,
  floorMod,
  isLeapYear,
  levelValue
} from "./exact.js";
import { EraTable } from "./eras.js";

// The one coordinate-arithmetic engine. Every unit relationship in ChronoLog --
// how many hours are in a day, how long a month is, how a nested coordinate
// becomes a day ordinal, what a duration magnitude is worth -- is computed here
// from the governing frame's own `coordinate` declaration.
//
// Before this module the declaration was decoration: the engine dispatched on
// `kind: "gregorian"` straight into hardcoded civil functions, the `transition`
// strings ("gregorian.months") resolved to nothing at all, and roughly fifty
// call sites carried 24 / 1440 / 86400 / 30.436875 as literals. Setting
// hours-per-day to 23 on a frame therefore changed nothing anywhere, which is
// the bug this module exists to make impossible: an editor that accepts an edit
// and ignores it is worse than one that refuses it.
//
// Two hard rules govern everything below.
//
//   * An unresolvable declaration is an ERROR SURFACED TO THE AUTHOR, never a
//     silent fallback. A transition string nothing implements, a radix that is
//     not a positive whole number, a level nesting inside a level that does not
//     exist -- each throws with the frame and the offending name in the message,
//     because a coordinate law that quietly means something other than what is
//     written is unauditable.
//   * All coordinate arithmetic is exact (`Rational`, BigInt). Pixels and
//     layout may be floats; unit law may not.

// --- The transition registry ------------------------------------------------
//
// A `transition` on a level says "the number of these inside their parent is not
// a constant; ask this rule". It is the counterpart of `radix`, which says the
// count IS a constant. A level declares exactly one of the two (the root
// declares neither, and a trailing level may declare neither -- that is the
// unbounded fractional tail, e.g. `subsecond`).
//
// Each entry belongs to a FAMILY. A family owns the closed-form conversion for
// the whole-unit part of a ladder, because that arithmetic cannot be derived
// from per-level counts alone without iterating from the epoch: proleptic
// Gregorian needs its 400-year era formula, and a future family will need its
// own. So the registry resolves a transition NAME to a family plus that
// transition's own count rule, and the family resolves a LADDER of them to days.
//
// This is what "the exact.js civil functions become the registered Gregorian
// entries, not a bypass" means concretely: `daysFromCivil`/`civilFromDays` are
// reached only through `GREGORIAN_FAMILY` below, which is reached only through
// a transition string written in a frame's declaration.
// A family is also a CALENDAR SCALE in the CLDR sense, and that identity is what
// crosses the ICS boundary: RFC 7529 lets a recurrence rule name the calendar it
// counts in (`RSCALE=HEBREW`), and the identifiers it uses are CLDR calendar
// names. So Gregorian is not privileged here -- it is simply the first entry, and
// Hebrew, Islamic, Indian and the rest are ordinary additional entries, each one
// a `registerCalendarFamily` call plus its transitions. Nothing else in the
// program needs to change to gain one.
//
// A calendar nothing has registered is REFUSED HONESTLY rather than computed as
// though it were Gregorian: `lawForCalendar` returns null, and the caller's job
// is to preserve the author's rule verbatim and say it cannot be projected.
const TRANSITIONS = new Map();
const FAMILIES = new Map();
const CALENDARS = new Map();

// A family receives the LADDER it is asked to execute -- the ordered level
// descriptors above the base, root first -- rather than only a signature string,
// because a family may need the levels' own radices to do its arithmetic at all.
// `calendar: null` means "this family is not a CLDR calendar scale": it can
// execute a ladder but names no standard calendar, so `calendarScale()` reports
// null and the ICS boundary converts or refuses rather than claiming a scale.
export function registerCalendarFamily(definition) {
  const name = String(definition?.name || "");
  if (!name) throw new TypeError("A calendar family needs a name.");
  for (const required of ["supports", "toWholeUnits", "fromWholeUnits"]) {
    if (typeof definition[required] !== "function") {
      throw new TypeError(`Calendar family ${name} must implement ${required}.`);
    }
  }
  const family = Object.freeze({ defaults: {}, aliases: [], calendar: name, ...definition });
  FAMILIES.set(name, family);
  for (const id of family.calendar === null ? [] : [family.calendar, ...family.aliases]) {
    CALENDARS.set(String(id).toLowerCase(), family);
  }
  return family;
}

// Every CLDR calendar scale this build can actually count in, lowercase.
export function registeredCalendars() {
  return [...new Set([...CALENDARS.values()].map((family) => family.calendar))].sort();
}

export function calendarFamily(calendarId) {
  return CALENDARS.get(String(calendarId || "").toLowerCase()) || null;
}

// The law a CLDR calendar scale name resolves to, or null when nothing
// implements that calendar. Memoized because the ICS boundary asks per rule.
const CALENDAR_LAWS = new Map();

export function lawForCalendar(calendarId) {
  const family = calendarFamily(calendarId);
  if (!family || !family.declaration) return null;
  const key = family.calendar;
  if (!CALENDAR_LAWS.has(key)) {
    CALENDAR_LAWS.set(key, new CoordinateLaw(family.declaration, { frameId: `calendar:${key}`, positional: true }));
  }
  return CALENDAR_LAWS.get(key);
}

export function registerTransition(name, definition) {
  const key = String(name || "");
  if (!key) throw new TypeError("A transition needs a name.");
  const family = FAMILIES.get(String(definition?.family || ""));
  if (!family) throw new TypeError(`Transition ${key} names an unregistered calendar family.`);
  const meanChildren = Rational.parse(definition.meanChildren);
  if (meanChildren.compare(0) <= 0) throw new TypeError(`Transition ${key} needs a positive mean child count.`);
  TRANSITIONS.set(key, Object.freeze({
    name: key,
    family,
    meanChildren,
    // How many children this parent actually has, for a specific parent. Used
    // by the authoring surface to describe a variable level honestly ("28-31")
    // and available to any consumer that needs a real count rather than a mean.
    childrenIn: definition.childrenIn || (() => meanChildren.n),
    summary: definition.summary || key
  }));
  return TRANSITIONS.get(key);
}

export function transitionDefinition(name) {
  return TRANSITIONS.get(String(name)) || null;
}

export function registeredTransitions() {
  return [...TRANSITIONS.keys()].sort();
}

// The one refusal message for a transition string nothing implements, shared by
// declaration normalization and by the authoring surface -- so an author sees
// the same sentence whether the bad name arrived by hand-edited JSON or by a
// form field, and the list of alternatives is never two lists.
export function assertTransition(name, subject) {
  if (TRANSITIONS.has(String(name))) return TRANSITIONS.get(String(name));
  throw new TypeError(
    `${subject} uses the transition "${name}", which nothing implements.`
    + ` Known transitions: ${registeredTransitions().join(", ") || "(none)"}.`
  );
}

// --- The Gregorian family ---------------------------------------------------
//
// 400 Gregorian years span exactly 146097 days, which is where every exact mean
// below comes from: 146097/400 days per year, 146097/4800 per month (the value
// the minimap used to carry as the float literal 30.436875).
const GREGORIAN_ERA_DAYS = new Rational(146097n);
const MEAN_GREGORIAN_YEAR = GREGORIAN_ERA_DAYS.div(400);
const MEAN_GREGORIAN_MONTH = GREGORIAN_ERA_DAYS.div(4800);

// The ladders this family knows how to execute, keyed by the ordered transition
// names below the root. A declaration whose ladder is not listed here is an
// authoring error rather than a guess: "year then month then day" and "year then
// day-of-year" are different calendars, and inventing a conversion for a shape
// nobody wrote is exactly the class of silent wrongness this module removes.
const GREGORIAN_LADDERS = new Map([
  ["", {
    toWholeUnits: (parts) => daysFromCivil(parts.get(0), 1n, 1n),
    fromWholeUnits: (days) => [["year", civilFromDays(days).year]]
  }],
  ["gregorian.months", {
    toWholeUnits: (parts) => daysFromCivil(parts.get(0), parts.get(1), 1n),
    fromWholeUnits: (days) => {
      const civil = civilFromDays(days);
      return [["year", civil.year], ["month", civil.month]];
    }
  }],
  ["gregorian.months+gregorian.days", {
    toWholeUnits: (parts) => daysFromCivil(parts.get(0), parts.get(1), parts.get(2)),
    fromWholeUnits: (days) => {
      const civil = civilFromDays(days);
      return [["year", civil.year], ["month", civil.month], ["day", civil.day]];
    }
  }],
  ["gregorian.daysInYear", {
    toWholeUnits: (parts) => daysFromCivil(parts.get(0), 1n, 1n) + parts.get(1) - 1n,
    fromWholeUnits: (days) => {
      const civil = civilFromDays(days);
      return [["year", civil.year], ["day", days - daysFromCivil(civil.year, 1n, 1n) + 1n]];
    }
  }]
]);

// --- The registered standard Gregorian declaration ---------------------------
//
// The names and the weekday cycle live HERE, in the declaration, rather than as
// private arrays in the minimap and the projections: that is what makes them
// editable at all (the owner's report: "when I go into my personal calendar
// using Wall Time as a basis to override the list of week day names ... I get an
// error"). A frame whose declaration omits them inherits these, so a document
// authored before they existed reads exactly as it always did.
//
// A weekday is deliberately NOT a ladder level. It does not nest inside a month
// -- seven days repeat across month and year boundaries without regard for
// either -- so it is a CYCLE: a fixed-length repetition over the base unit with
// its own names and its own phase. Modelling it as a level is what forced the
// authoring surface to demand one name per day of the month, which is the count
// error the owner hit while entering seven weekday names.
export const STANDARD_MONTH_NAMES = Object.freeze([
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December"
]);

export const STANDARD_WEEKDAY_NAMES = Object.freeze([
  "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
]);

export const GREGORIAN_DECLARATION = Object.freeze({
  kind: "gregorian",
  levels: Object.freeze([
    Object.freeze({ name: "year" }),
    Object.freeze({ name: "month", within: "year", transition: "gregorian.months", names: STANDARD_MONTH_NAMES }),
    Object.freeze({ name: "day", within: "month", transition: "gregorian.days" }),
    Object.freeze({ name: "hour", within: "day", radix: "24" }),
    Object.freeze({ name: "minute", within: "hour", radix: "60" }),
    Object.freeze({ name: "second", within: "minute", radix: "60" }),
    Object.freeze({ name: "subsecond", within: "second" })
  ]),
  // `offset` is the cycle index of day zero (1970-01-01, a Thursday), which is
  // where the shipped `floorMod(day + 4, 7)` weekday derivation came from.
  cycles: Object.freeze([
    Object.freeze({ name: "weekday", radix: "7", offset: "4", names: STANDARD_WEEKDAY_NAMES })
  ])
});

export const GREGORY = "gregory";

export const GREGORIAN_FAMILY = registerCalendarFamily({
  name: "gregorian",
  // CLDR spells the proleptic Gregorian calendar `gregory`. RFC 7529's own text
  // and examples are not consistent about whether an RSCALE names it `GREGORY`
  // or `GREGORIAN`, so both are accepted on the way in; on the way out the
  // question never arises, because Gregorian is RSCALE's default and a rule that
  // counts in it omits the parameter entirely.
  calendar: GREGORY,
  aliases: ["gregorian"],
  // The canonical ladder this calendar scale counts in, which is what an
  // `RSCALE` naming it resolves to.
  declaration: GREGORIAN_DECLARATION,
  // A bare year/month/day coordinate with no time levels means midnight on that
  // date, and an absent year means the day-zero epoch year -- the defaults the
  // shipped civil conversion has always used.
  defaults: { year: "1970", month: "1", day: "1" },
  signature(ladder) {
    return ladder.slice(1).map((level) => level.transition || "").join("+");
  },
  supports(ladder) {
    return GREGORIAN_LADDERS.has(this.signature(ladder));
  },
  toWholeUnits(ladder, parts) {
    return GREGORIAN_LADDERS.get(this.signature(ladder)).toWholeUnits(parts);
  },
  fromWholeUnits(ladder, days) {
    return GREGORIAN_LADDERS.get(this.signature(ladder)).fromWholeUnits(days);
  }
});

// The uniform positional family: any ladder whose levels above the base all
// count a CONSTANT number of children. This is what a wholly invented calendar
// needs -- 12 months of 30 days in a 360-day year, or Tamriel's fixed year --
// and it is registered rather than special-cased, so such a calendar converts
// through the same seam Gregorian does.
//
// It names no CLDR calendar scale, so a series counting in it is not
// ICS-expressible as a rule (AGENTS.md's ICS contract) even though its dates
// resolve to exact day ordinals.
//
// Root values are 1-based, matching the family defaults every other level uses,
// and may be zero or negative: a descending era (Merethic, BCE) resolves to
// proper years at or below zero, and `floorDiv`/`floorMod` carry that through
// exactly rather than truncating toward zero.
export const UNIFORM_FAMILY = registerCalendarFamily({
  name: "uniform",
  calendar: null,
  defaults: { },
  // Whole units of the base level spanned by one unit of each ladder level.
  spans(ladder) {
    const spans = new Array(ladder.length);
    let span = 1n;
    for (let index = ladder.length - 1; index >= 0; index -= 1) {
      spans[index] = span;
      if (index > 0) span *= ladder[index].radix.n;
    }
    return spans;
  },
  supports(ladder) {
    return ladder.length > 0
      && ladder.slice(1).every((level) => level.radix && !level.transition && level.radix.d === 1n);
  },
  toWholeUnits(ladder, parts) {
    const spans = this.spans(ladder);
    let total = 0n;
    for (const [index] of ladder.entries()) {
      total += (parts.get(index) - 1n) * spans[index];
    }
    return total;
  },
  fromWholeUnits(ladder, wholeUnits) {
    const spans = this.spans(ladder);
    let remainder = BigInt(wholeUnits);
    const values = [];
    for (const [index, level] of ladder.entries()) {
      const amount = floorDiv(remainder, spans[index]);
      remainder -= amount * spans[index];
      values.push([level.name, amount + 1n]);
    }
    return values;
  }
});

registerTransition("gregorian.months", {
  family: "gregorian",
  meanChildren: "12",
  childrenIn: () => 12n,
  summary: "12 months"
});

registerTransition("gregorian.days", {
  family: "gregorian",
  meanChildren: MEAN_GREGORIAN_MONTH,
  childrenIn: (parts) => BigInt(daysInMonth(parts.year ?? 1970n, parts.month ?? 1n)),
  summary: "28-31 days"
});

registerTransition("gregorian.daysInYear", {
  family: "gregorian",
  meanChildren: MEAN_GREGORIAN_YEAR,
  childrenIn: (parts) => isLeapYear(parts.year ?? 1970n) ? 366n : 365n,
  summary: "365 or 366 days"
});

// The unit relationships a partial declaration inherits. A calendar that omits
// the `hour` level entirely is not asserting that hours do not exist; it simply
// has not authored them, and a display that needs an hour rail gets the
// registered standard rather than a crash. Anything the declaration DOES author
// always wins.
const STANDARD_UNIT_DAYS = Object.freeze({
  week: Rational.parse("7"),
  day: Rational.parse("1"),
  hour: Rational.parse("1/24"),
  minute: Rational.parse("1/1440"),
  second: Rational.parse("1/86400")
});

// --- Declaration normalization ----------------------------------------------

function positiveWholeRadix(value, frameLabel, levelName) {
  let parsed;
  try {
    parsed = Rational.parse(value);
  } catch {
    throw new TypeError(`${frameLabel}: level "${levelName}" has a radix that is not a number (${value}).`);
  }
  if (parsed.compare(0) <= 0 || parsed.d !== 1n) {
    throw new TypeError(`${frameLabel}: level "${levelName}" needs a positive whole radix, not ${value}.`);
  }
  return parsed;
}

function normalizeNames(names) {
  if (!Array.isArray(names)) return null;
  const cleaned = names.map((name) => String(name).trim()).filter(Boolean);
  return cleaned.length ? Object.freeze(cleaned) : null;
}

function normalizeLevels(declaration, frameLabel) {
  const declared = Array.isArray(declaration?.levels) ? declaration.levels : [];
  const levels = [];
  const seen = new Map();
  for (const [index, entry] of declared.entries()) {
    const name = String(entry?.name || "").trim();
    if (!name) throw new TypeError(`${frameLabel}: level ${index + 1} has no name.`);
    if (seen.has(name)) throw new TypeError(`${frameLabel}: level "${name}" is declared twice.`);
    const within = index === 0 ? null : String(entry?.within || declared[index - 1]?.name || "").trim() || null;
    if (index > 0 && !seen.has(within)) {
      throw new TypeError(`${frameLabel}: level "${name}" nests inside "${within || "(nothing)"}", which is not a level above it.`);
    }
    const transitionName = entry?.transition ? String(entry.transition) : null;
    if (transitionName) assertTransition(transitionName, `${frameLabel}: level "${name}"`);
    if (transitionName && entry?.radix !== undefined && entry.radix !== null && entry.radix !== "") {
      throw new TypeError(`${frameLabel}: level "${name}" declares both a radix and a transition; a level has one or the other.`);
    }
    const level = Object.freeze({
      name,
      within,
      radix: transitionName || entry?.radix === undefined || entry?.radix === null || entry?.radix === ""
        ? null
        : positiveWholeRadix(entry.radix, frameLabel, name),
      transition: transitionName,
      names: normalizeNames(entry?.names) || normalizeNames(entry?.labels)
    });
    levels.push(level);
    seen.set(name, level);
  }
  return { levels: Object.freeze(levels), byName: seen };
}

function normalizeCycles(declaration, frameLabel) {
  const declared = Array.isArray(declaration?.cycles) ? declaration.cycles : [];
  const cycles = new Map();
  for (const entry of declared) {
    const name = String(entry?.name || "").trim();
    if (!name) throw new TypeError(`${frameLabel}: a cycle has no name.`);
    const radix = positiveWholeRadix(entry?.radix, frameLabel, name);
    const names = normalizeNames(entry?.names);
    if (names && names.length !== Number(radix.n)) {
      throw new TypeError(
        `${frameLabel}: the "${name}" cycle repeats every ${radix.n} but ${names.length} name${names.length === 1 ? " was" : "s were"} given.`
      );
    }
    cycles.set(name, Object.freeze({
      name,
      radix,
      offset: entry?.offset === undefined ? 0n : BigInt(entry.offset),
      names
    }));
  }
  return cycles;
}

// --- CoordinateLaw ----------------------------------------------------------

export class CoordinateLaw {
  // `declaration` is a frame's `coordinate` object. `frameId` only ever appears
  // in error messages, so an ad-hoc declaration (a form previewing an unsaved
  // edit) constructs fine without one.
  //
  // `positional` says whether this declaration names POSITIONS on a timeline
  // (a calendar: year/month/day resolve to a day ordinal through a family) or
  // MAGNITUDES (a measure frame: the base level's value already IS a count of
  // days). It defaults to "positional if a family can execute the ladder", and
  // `coordinateLaw` passes it explicitly so a measure frame keeps reading its
  // own base level rather than being reinterpreted as a date.
  constructor(declaration = null, { frameId = null, positional = undefined } = {}) {
    const frameLabel = frameId ? `Frame ${frameId}` : "This coordinate declaration";
    this.frameId = frameId;
    this.declaration = declaration || null;
    this.kind = String(declaration?.kind || "nested");
    const { levels, byName } = normalizeLevels(declaration, frameLabel);
    this.levels = levels;
    this._byName = byName;
    this._cycles = normalizeCycles(declaration, frameLabel);
    this._unitDays = new Map();
    this._unitAtoms = new Map();

    // THE ATOM: the finest declared unit, the one everything else is composed
    // from. Its own absolute length is the one thing composition cannot supply,
    // so it comes from the registered standard for a unit of that name (a second
    // is 1/86400 of a standard day wherever it appears) or is authored outright
    // with `atomDays`.
    //
    // This is also the shared denominator for cross-frame comparison: two laws
    // relate absolutely exactly insofar as they share an atom, whether directly
    // or through basis inheritance. Two frames with no shared atom have no
    // automatic absolute relation at all -- that is what connection staples are
    // for, and inventing one would be the same fabrication as an invented origin.
    const finest = levels.length ? levels[levels.length - 1] : null;
    // A continuous tail is not a unit of its own; the finest FIXED unit is the
    // level above it.
    this.atomLevel = finest && !finest.radix && !finest.transition && levels.length > 1
      ? levels[levels.length - 2].name
      : finest?.name || null;
    const authoredAtomDays = declaration?.atomDays
      ?? declaration?.baseUnitDays
      ?? declaration?.fixed?.smallestUnitDays;
    if (authoredAtomDays !== undefined && authoredAtomDays !== null) {
      this.atomDays = Rational.parse(authoredAtomDays);
    } else if (this.atomLevel && STANDARD_UNIT_DAYS[this.atomLevel]) {
      this.atomDays = STANDARD_UNIT_DAYS[this.atomLevel];
    } else {
      this.atomDays = Rational.parse(1);
    }
    if (this.atomDays.compare(0) <= 0) {
      throw new TypeError(`${frameLabel}: the smallest unit must be longer than zero days.`);
    }

    // The BASE LEVEL is the level the family's whole-unit arithmetic COUNTS IN --
    // the "day" of this ladder. It is no longer "one standard day": under
    // bottom-up composition its length is whatever its own radices make it, so a
    // frame declaring 23 hours in a day has a base unit of 23 standard hours and
    // its day sequence DRIFTS against the standard calendar. That drift is the
    // ruling, not a defect: successive day boundaries fall 23 standard hours
    // apart because the day is the thing that was shortened.
    //
    // A `fixed` block's finest level is its base. Otherwise the base is the
    // deepest level reached by a transition, because a transition counts whole
    // base units. A UNIFORM ladder has no transition to infer from, so such a
    // calendar states `baseLevel` outright, and that statement outranks every
    // inference here.
    const fixed = declaration?.fixed;
    const deepestTransition = [...levels].reverse().find((level) => level.transition) || null;
    const declaredBase = declaration?.baseLevel ? String(declaration.baseLevel) : null;
    if (declaredBase && !byName.has(declaredBase)) {
      throw new TypeError(
        `${frameLabel}: the base unit is declared as "${declaredBase}", which is not one of its levels`
        + ` (${levels.map((level) => level.name).join(", ") || "none"}).`
      );
    }
    this.baseLevel = declaredBase
      || (fixed && levels.length ? levels[levels.length - 1].name : null)
      || deepestTransition?.name
      || levels[0]?.name
      || "day";
    this.epochDays = Rational.parse(fixed?.epochDays ?? "0");

    const baseIndex = levels.findIndex((level) => level.name === this.baseLevel);
    this.aboveLadder = baseIndex < 0 ? Object.freeze([]) : Object.freeze(levels.slice(0, baseIndex + 1));
    this.belowLadder = baseIndex < 0 ? Object.freeze([]) : Object.freeze(levels.slice(baseIndex + 1));

    // The ERA TABLE sits above the year level and renumbers it. Its level is the
    // declaration's root, and the level directly below it is the one whose
    // numbering restarts per era -- so an era-qualified coordinate carries BOTH
    // ("3E", 433) and the ladder underneath is unchanged. The era level is
    // deliberately NOT part of the family's ladder: the table converts
    // (era, year) to the PROPER YEAR the ladder already counts in, and the family
    // takes it from there. That composition is what keeps eras first-class
    // instead of a label over a linearized year.
    if (declaration?.eras) {
      if (levels.length < 2) {
        throw new TypeError(`${frameLabel}: an era table needs an era level and a year level beneath it.`);
      }
      try {
        this.eraTable = new EraTable(declaration.eras);
      } catch (error) {
        throw new TypeError(`${frameLabel}: ${error.message}`);
      }
      this.eraLevel = levels[0].name;
      this.yearLevel = levels[1].name;
      if (levels[0].radix || levels[0].transition) {
        throw new TypeError(
          `${frameLabel}: level "${this.eraLevel}" is governed by the era table, so it takes no count or transition.`
        );
      }
      if (this.eraLevel === this.baseLevel) {
        throw new TypeError(`${frameLabel}: the era level cannot also be the base unit.`);
      }
    } else {
      this.eraTable = null;
      this.eraLevel = null;
      this.yearLevel = null;
    }

    // What the family actually executes: the above-base ladder minus the era
    // level, whose job the table has already done.
    this.familyLadder = this.eraTable ? Object.freeze(this.aboveLadder.slice(1)) : this.aboveLadder;

    // Every transition above the base must belong to one family: half a
    // Gregorian ladder spliced onto half of something else is not a calendar.
    const families = new Set(this.familyLadder
      .filter((level) => level.transition)
      .map((level) => TRANSITIONS.get(level.transition).family.name));
    if (families.size > 1) {
      throw new TypeError(`${frameLabel}: levels mix the ${[...families].join(" and ")} calendar families.`);
    }
    // A ladder with no transitions at all is uniform: constant counts the whole
    // way down. It only becomes POSITIONAL when the author says where it starts
    // (`origin.days`) or hands it an era table, because without an origin there
    // is no statement of which day the calendar's first unit begins on, and
    // inventing one would place every date in the document by guess.
    const origin = declaration?.origin;
    let family = families.size ? FAMILIES.get([...families][0]) : null;
    // An era table renumbers YEARS; it says nothing about which day the calendar
    // starts on, so it never substitutes for an origin. Anchoring at day zero by
    // default would place every date in the document by an invented convention.
    if (!family && this.familyLadder.length && UNIFORM_FAMILY.supports(this.familyLadder) && origin) {
      family = UNIFORM_FAMILY;
    }
    if (family && !family.supports(this.familyLadder)) {
      throw new TypeError(
        `${frameLabel}: the ${family.name} family cannot execute the level ladder `
        + `${this.familyLadder.map((level) => level.name).join(" > ")}.`
      );
    }
    if (origin !== undefined && origin !== null) {
      this.originDays = Rational.parse(origin?.days ?? origin);
      // `fixed.epochDays` and `origin.days` are two statements of the same fact —
      // where this calendar's counting begins. Carrying both would silently add
      // them together, so one of them has to go rather than be reconciled here.
      if (!this.epochDays.isZero()) {
        throw new TypeError(
          `${frameLabel}: the declaration states its starting day twice, as a fixed-calendar epoch`
          + ` and as an origin. Keep one.`
        );
      }
    } else {
      this.originDays = Rational.parse(0);
    }
    // An era table is itself a statement that these coordinates are positions,
    // not magnitudes -- there is no such thing as a duration of "3E 433".
    const declaredPositional = positional === undefined
      ? Boolean(family)
      : Boolean((positional || this.eraTable || origin) && family);
    this.positional = declaredPositional;
    this.family = this.positional ? family : null;
    if (this.eraTable && !this.family) {
      throw new TypeError(
        `${frameLabel}: an era table needs a year ladder its family can execute; `
        + `declare an origin day for a uniform ladder, or use a registered transition.`
      );
    }
    // Retained even when this law is not positional, so an authoring surface can
    // still describe a measure frame's variable levels ("365 or 366 days").
    this.declaredFamily = family;
  }

  // --- Structure --------------------------------------------------------

  // The base unit's own length, COMPOSED from its radices rather than assumed to
  // be one standard day. Every consumer that used to read a hardcoded 1 here now
  // reads whatever the declaration actually adds up to.
  get baseDays() {
    return this.unitDays(this.baseLevel) ?? this.atomDays;
  }

  /** How many atoms one base unit spans -- the family's counting granularity. */
  get baseAtoms() {
    return this.unitAtoms(this.baseLevel) ?? Rational.parse(1);
  }

  level(name) {
    return this._byName.get(String(name)) || null;
  }

  has(name) {
    return this._byName.has(String(name));
  }

  levelNames() {
    return this.levels.map((level) => level.name);
  }

  // Authored names for a level's values, one per unit within its parent
  // (January..December), or null when nothing names them.
  //
  // The registered standard is inherited ONLY by a law that actually counts in
  // that registered calendar. A custom calendar whose second level happens to be
  // spelled "month" is not the Gregorian month and must not be handed twelve
  // Gregorian names -- an authoring surface would then show twelve names against
  // a radix of eight and refuse the author's own structure.
  namesFor(name) {
    const level = this.level(name);
    if (level?.names) return level.names;
    if (!this.declaredFamily) return null;
    const standard = GREGORIAN_DECLARATION.levels.find((entry) => entry.name === String(name));
    return standard?.names || null;
  }

  // The names of this law's month-scale level, or NULL when it has no such
  // concept at all.
  //
  // The distinction matters and used to be lost: a frame declaring no month
  // level and no calendar family was told it had January through December.
  // Inheriting the standard is right for a law that COUNTS in the registered
  // calendar and simply left a level unnamed; it is a fabrication for a law that
  // has no months. A caller that draws a month grid must therefore handle null by
  // not drawing one.
  monthNames() {
    const monthLevel = this.levels.find((level) => level.transition === "gregorian.months")
      || this.level("month");
    const authored = monthLevel && this.namesFor(monthLevel.name);
    if (authored) return authored;
    if (monthLevel && this.declaredFamily) return STANDARD_MONTH_NAMES;
    return this.declaredFamily && !this.levels.length ? STANDARD_MONTH_NAMES : null;
  }

  hasMonths() {
    return this.monthNames() !== null;
  }

  // The CLDR calendar scale this law's DATE ladder counts in, or null when it
  // counts in no registered calendar at all.
  //
  // This is the question the ICS boundary asks: RFC 7529's RSCALE governs the
  // date ladder a recurrence rule counts in, and nothing below the base unit --
  // so a frame that redefines its hours still counts dates in `gregory` and its
  // rules stay spec-expressible, while a frame with a `fixed` block or a formula
  // law counts in no registered calendar and its rules must export as concrete
  // projections instead of as a rule ICS would misread.
  calendarScale() {
    return this.family?.calendar || null;
  }

  // --- Unit magnitudes --------------------------------------------------

  // Exact days per one unit of `name`, or null for a level whose length varies
  // (a Gregorian month). `meanUnitDays` answers for those.
  unitDays(name) {
    const key = String(name);
    if (this._unitDays.has(key)) return this._unitDays.get(key);
    const value = this._computeUnitDays(key);
    this._unitDays.set(key, value);
    return value;
  }

  // UNITS ARE DEFINED BY COMPOSITION FROM BELOW.
  //
  // Owner ruling: "that is wrong, I did not change the lenght of an hour I
  // changed the length of a day. Day is defined as a number of hours, which are
  // themselves a number of minutes, ect."
  //
  // So the finest declared unit is the ATOM, and every level's length is the
  // product of the radices beneath it. A radix says how many children fill one
  // parent, which makes it a statement about the PARENT's length: editing
  // hour-within-day to 23 makes the DAY twenty-three standard hours long and
  // leaves the hour untouched. Anchoring the other way round -- holding the day
  // fixed and fattening its hours -- is the inversion this replaces.
  //
  // A level containing a transition has no constant length and says so by
  // returning null rather than a mean masquerading as exact.
  _computeUnitAtoms(name) {
    const level = this.level(name);
    if (!level) return STANDARD_UNIT_DAYS[name] ? STANDARD_UNIT_DAYS[name].div(this.atomDays) : null;
    if (name === this.atomLevel) return Rational.parse(1);
    // A level's OWN edge (radix or transition) says how many of IT fit in its
    // parent, so it describes the PARENT's length and says nothing about its own.
    // Only the child's edge does that. Reading a level's own transition here is
    // what made `day` -- which carries `gregorian.days`, "how many days in a
    // month" -- look like a unit of no fixed length.
    const child = this.levels.find((entry) => entry.within === name);
    if (!child) return Rational.parse(1);
    if (child.transition) return null;
    const childAtoms = this.unitAtoms(child.name);
    // A level with no radix beneath it (the ladder's continuous `subsecond`
    // tail) subdivides its parent continuously rather than into a fixed count,
    // so it contributes a factor of one: a value of 0.25 there means a quarter
    // of one parent unit, which is how the shipped civil conversion has always
    // treated it.
    return childAtoms === null ? null : childAtoms.mul(child.radix || 1);
  }

  /** How many atoms one unit of `name` spans, or null when it varies. */
  unitAtoms(name) {
    const key = String(name);
    if (this._unitAtoms.has(key)) return this._unitAtoms.get(key);
    const value = this._computeUnitAtoms(key);
    this._unitAtoms.set(key, value);
    return value;
  }

  _computeUnitDays(name) {
    const atoms = this.unitAtoms(name);
    return atoms === null ? null : atoms.mul(this.atomDays);
  }

  // Exact mean days per unit, defined for every level: a variable level's mean
  // comes from its transition's registered mean child count, so a Gregorian
  // month is exactly 146097/4800 days rather than the float 30.436875.
  meanUnitDays(name) {
    const exact = this.unitDays(name);
    if (exact !== null) return exact;
    const level = this.level(name);
    if (!level) return null;
    const child = this.levels.find((entry) => entry.within === level.name);
    if (!child) return null;
    const childMean = this.meanUnitDays(child.name);
    if (childMean === null) return null;
    const transition = child.transition ? TRANSITIONS.get(child.transition) : null;
    const perParent = transition ? transition.meanChildren : child.radix;
    return perParent ? childMean.mul(perParent) : null;
  }

  // How many units of `name` fit in one base unit -- "how many minutes in a
  // day". This is the accessor that replaced the 1440s.
  unitsPerDay(name) {
    const unit = this.unitDays(name) ?? this.meanUnitDays(name);
    if (unit === null || unit.isZero()) return null;
    return this.baseDays.div(unit);
  }

  // Named conveniences for the units the display surfaces actually reason
  // about. Each resolves through the declaration and falls back to the
  // registered standard for a level this calendar never authored.
  hoursPerDay() {
    return this.unitsPerDay("hour") ?? Rational.parse("24");
  }

  minutesPerDay() {
    return this.unitsPerDay("minute") ?? Rational.parse("1440");
  }

  secondsPerDay() {
    return this.unitsPerDay("second") ?? Rational.parse("86400");
  }

  minutesPerHour() {
    const hour = this.unitDays("hour");
    const minute = this.unitDays("minute");
    return hour && minute && !minute.isZero() ? hour.div(minute) : Rational.parse("60");
  }

  secondsPerMinute() {
    const minute = this.unitDays("minute");
    const second = this.unitDays("second");
    return minute && second && !second.isZero() ? minute.div(second) : Rational.parse("60");
  }

  daysPerWeek() {
    const week = this.unitDays("week") ?? this.meanUnitDays("week");
    return week && !this.baseDays.isZero() ? week.div(this.baseDays) : Rational.parse("7");
  }

  // The mean length of the level a month-scale stride steps by. The minimap's
  // label ladder needs a stride in days for a variable unit; this is the exact
  // value it needs, per this frame's own law.
  meanMonthDays() {
    const monthLevel = this.levels.find((level) => level.transition === "gregorian.months")
      || this.level("month");
    return (monthLevel && this.meanUnitDays(monthLevel.name)) || MEAN_GREGORIAN_MONTH;
  }

  // --- Duration magnitudes ---------------------------------------------
  //
  // A magnitude is a bag of level counts ({hour: 2, minute: 30}). Its worth in
  // days is the sum of each count times that level's own unit length under THIS
  // law, which is what retires the fixed {week:"7", day:"1", hour:"1/24", ...}
  // factor table: a 23-hour day makes "2 hours" worth 2/23 of a day, and every
  // consumer of a duration has to agree about that or the same event is two
  // different lengths in two different lenses.
  //
  // Tolerant by contract: an unparseable magnitude yields zero rather than
  // throwing (~169 MB of imported ICS is plausibly dirty), a level this law
  // does not know is skipped, and a negative sum clamps to zero because every
  // caller treats a duration as a non-negative span.
  magnitudeDays(magnitude) {
    let total = Rational.parse(0);
    try {
      for (const part of magnitude?.value?.levels || []) {
        const unit = this.unitDays(part.level) ?? this.meanUnitDays(part.level);
        if (unit !== null) total = total.add(Rational.parse(part.value).mul(unit));
      }
    } catch {
      return Rational.parse(0);
    }
    return total.compare(0) > 0 ? total : Rational.parse(0);
  }

  // --- Cycles -----------------------------------------------------------

  cycle(name) {
    const declared = this._cycles.get(String(name));
    if (declared) return declared;
    // Same rule as `namesFor`: only a law that counts in the registered calendar
    // inherits its cycles. A law that does not has no week unless it says so.
    if (!this.declaredFamily) return null;
    const standard = GREGORIAN_DECLARATION.cycles.find((entry) => entry.name === String(name));
    if (!standard) return null;
    return {
      name: standard.name,
      radix: Rational.parse(standard.radix),
      offset: BigInt(standard.offset),
      names: standard.names
    };
  }

  cycleNames(name) {
    return this.cycle(name)?.names || null;
  }

  // Every cycle in force, authored ones first and the registered standard ones
  // this declaration never overrode after them. The authoring surface needs the
  // effective set, not just what happens to be written on this frame.
  cycles() {
    const effective = new Map();
    for (const standard of GREGORIAN_DECLARATION.cycles) {
      if (this.declaredFamily) effective.set(standard.name, this.cycle(standard.name));
    }
    for (const [name, cycle] of this._cycles) effective.set(name, cycle);
    return [...effective.values()];
  }

  // Which position in the cycle a given day ordinal falls on.
  cycleIndex(name, days) {
    const cycle = this.cycle(name);
    if (!cycle) return null;
    const ordinal = Rational.parse(days).sub(this.epochDays).div(this.baseDays).floor();
    return Number(floorMod(ordinal + cycle.offset, cycle.radix.n));
  }

  cycleLabel(name, days) {
    const cycle = this.cycle(name);
    if (!cycle) return null;
    const index = this.cycleIndex(name, days);
    return cycle.names?.[index] ?? `${cycle.name} ${index + 1}`;
  }

  // The weekday cycle's names, or NULL when this law declares no such cycle and
  // inherits no calendar that would. A world with no week has no weekday names,
  // and handing it seven Gregorian ones invents a fact.
  weekdayNames() {
    const authored = this.cycleNames("weekday");
    if (authored) return authored;
    return this.declaredFamily ? STANDARD_WEEKDAY_NAMES : null;
  }

  hasWeekdays() {
    return this.weekdayNames() !== null;
  }

  weekdayLabel(days) {
    return this.hasWeekdays() ? this.cycleLabel("weekday", days) : null;
  }

  // --- Eras -------------------------------------------------------------

  hasEras() {
    return this.eraTable !== null;
  }

  eras() {
    return this.eraTable ? this.eraTable.entries : [];
  }

  /**
   * How a year renders under this law: "3E 433" where the law has eras, and the
   * plain year otherwise. `value` is a coordinate, so this reads whichever
   * levels the law actually declares rather than assuming a `year` level exists.
   */
  formatYear(value) {
    if (!this.eraTable) {
      const level = this.familyLadder[0]?.name || this.levels[0]?.name;
      return level ? String(levelValue(value, level, "")) : "";
    }
    const era = value?.levels?.find((entry) => entry.level === this.eraLevel);
    if (!era) return "";
    return this.eraTable.format(era.value, levelValue(value, this.yearLevel, "1"));
  }

  /** The era-qualified year at a day ordinal, or the plain year without eras. */
  formatYearAtDays(days) {
    return this.formatYear(this.fromDays(days));
  }

  /** Era-qualified text ("3E 433", "44 BCE") to {era, year}, or null. */
  parseYear(text) {
    return this.eraTable ? this.eraTable.parse(text) : null;
  }

  /**
   * Does this law place its coordinates on the running clock at all?
   *
   * Only a positional law does: a non-positional law reads its base level as a
   * bare count with no statement of which day anything begins on, so "now" has
   * no position in it. An author may also say so outright with `clock: false` --
   * a calendar of a world with no relation to this one has no now, and drawing a
   * Now line on it invents a fact (the owner's field note: "no artificial Now
   * line on a calendar with no now-mapping").
   */
  mapsToClock() {
    return this.positional && this.declaration?.clock !== false;
  }

  // --- Conversion -------------------------------------------------------

  // A nested coordinate to an exact day ordinal.
  //
  // With a family, the ladder above the base resolves in closed form and the
  // levels below add their own fractions -- so `hour` genuinely contributes
  // 1/23 of a day once the declaration says radix 23.
  //
  // Without a family there is no origin to count from, so the base level's value
  // IS the day count. That is what this has always done for `kind: "nested"`
  // frames and it stays that way; positional conversion for a fully custom
  // ladder is the next stage of ROADMAP #6, not something to guess at here.
  toDays(value) {
    if (this.family) {
      const parts = new Map();
      for (const [index, level] of this.familyLadder.entries()) {
        // The era table owns the year level's numbering, so that value is the
        // PROPER year it resolves to rather than whatever the coordinate stored.
        if (this.eraTable && level.name === this.yearLevel) {
          parts.set(index, this._properYear(value));
          continue;
        }
        const fallback = this.family.defaults[level.name] ?? "1";
        parts.set(index, BigInt(levelValue(value, level.name, fallback)));
      }
      // In ATOMS first, then out to standard days once: the whole-unit count is
      // in base units, each of which is `baseAtoms` atoms long, and the levels
      // below contribute their own atoms directly. Composing in the atom is what
      // makes a shortened day shorten the absolute span rather than compress the
      // hours inside it.
      const whole = this.family.toWholeUnits(this.familyLadder, parts);
      const atoms = new Rational(whole).mul(this.baseAtoms).add(this._belowAtoms(value));
      return atoms.mul(this.atomDays).add(this.epochDays).add(this.originDays);
    }
    // A value naming levels this law does not declare is NOT a value in this
    // law, and reading its base level as a bare count would answer a question
    // nobody asked: a {year, month, day} coordinate handed to a law with no
    // family placed 1973-03-15 at day 15, silently, because `day` happened to be
    // the base level. A magnitude of "15 days" and the fifteenth of March are not
    // the same number, so this refuses instead of reading.
    //
    // A law that declares no levels at all is a bare day axis and keeps the
    // permissive read: there is nothing there to contradict.
    if (this.levels.length) {
      const foreign = (value?.levels || [])
        .map((entry) => entry.level)
        .filter((level) => !this._byName.has(level));
      if (foreign.length) {
        throw new TypeError(
          `Frame ${this.frameId || "(anonymous)"} declares no ${foreign.join(", ")} level,`
          + ` so this coordinate is not a position in it (its levels are `
          + `${this.levelNames().join(", ")}).`
        );
      }
    }
    const raw = value?.levels?.find((entry) => entry.level === this.baseLevel)
      || value?.levels?.find((entry) => entry.level === "day");
    if (!raw) {
      throw new Error(`Frame ${this.frameId || "(anonymous)"} has no temporal coordinate law`);
    }
    return Rational.parse(raw.value).mul(this.baseDays).add(this.epochDays);
  }

  // The proper year an era-qualified coordinate names. The era is REQUIRED: a
  // year with no era on a calendar that has eras is genuinely ambiguous, and
  // defaulting it to "the era the anchor happens to sit in" would be exactly the
  // invented meaning this model refuses.
  _properYear(value) {
    const era = value?.levels?.find((entry) => entry.level === this.eraLevel);
    if (!era) {
      throw new TypeError(
        `This calendar numbers years within eras, so a coordinate needs one of `
        + `${this.eraTable.eraKeys().join(", ")} in its "${this.eraLevel}" level.`
      );
    }
    const year = levelValue(value, this.yearLevel, "1");
    return this.eraTable.toProperYear(era.value, year);
  }

  _belowAtoms(value) {
    let total = Rational.parse(0);
    for (const level of this.belowLadder) {
      const unit = this.unitAtoms(level.name);
      if (unit === null) continue;
      total = total.add(Rational.parse(levelValue(value, level.name, "0")).mul(unit));
    }
    return total;
  }

  // A day ordinal back to a nested coordinate. The levels below the base only
  // appear when at least one of them is non-zero, so midnight stays a bare
  // date -- the shape every existing consumer and every stored document expects.
  fromDays(days, fractionPlaces = 12) {
    const value = Rational.parse(days);
    if (!this.family) {
      return coordinate([{
        level: this.baseLevel,
        value: value.sub(this.epochDays).div(this.baseDays).toJSON()
      }]);
    }
    // Into ATOMS once, then decompose: whole base units first, then whatever
    // atoms are left spent down the below-base ladder.
    const atoms = value.sub(this.epochDays).sub(this.originDays).div(this.atomDays);
    const baseUnits = atoms.div(this.baseAtoms);
    const whole = baseUnits.floor();
    let remainder = atoms.sub(this.baseAtoms.mul(whole));
    const resolved = this.family.fromWholeUnits(this.familyLadder, whole);
    // The era table turns the proper year back into an era plus a year within
    // it, and BOTH land in the coordinate -- the round trip preserves what the
    // author wrote, not a linearized equivalent of it.
    const levels = this.eraTable
      ? (() => {
          const properYear = resolved.find(([name]) => name === this.yearLevel)?.[1];
          const era = this.eraTable.fromProperYear(properYear);
          return [
            { level: this.eraLevel, value: era.era },
            ...resolved.map(([level, amount]) =>
              level === this.yearLevel ? { level, value: era.year } : { level, value: amount })
          ];
        })()
      : resolved.map(([level, amount]) => ({ level, value: amount }));
    const below = [];
    let significant = false;
    for (const [index, level] of this.belowLadder.entries()) {
      const unit = this.unitAtoms(level.name);
      if (unit === null) continue;
      // The continuous tail carries whatever is left as a fraction of one of its
      // own units, and only appears at all when there is something left.
      if (index === this.belowLadder.length - 1 && !level.radix) {
        if (!remainder.isZero()) {
          below.push({ level: level.name, value: remainder.div(unit).toDecimal(fractionPlaces) });
          significant = true;
        }
        continue;
      }
      const amount = remainder.div(unit).floor();
      remainder = remainder.sub(unit.mul(amount));
      if (amount !== 0n) significant = true;
      below.push({ level: level.name, value: amount });
    }
    return coordinate(significant ? [...levels, ...below] : levels);
  }
}

// --- Resolution and caching -------------------------------------------------
//
// Overscale doctrine: the engine asks for a frame's law inside occurrence loops,
// so resolution has to be O(1) after the first call. The cache is keyed by
// document identity (a WeakMap, so a replaced document is collectable) and
// invalidated two ways: the resolved declaration's OBJECT IDENTITY is checked on
// every hit, and `invalidateCoordinateLaws` is called explicitly by the edit
// path. Identity alone would miss an in-place mutation; the explicit call alone
// would miss an undo that swaps whole records. Both together mean an applied
// coordinate edit is live on the next render, which is the failure the owner
// reported: "I swaped both Wall Time and Human time magnitude to Hour:Day:23 ...
// and uppon inspection there still appears to be 24 hours in a day".
let LAW_CACHE = new WeakMap();

export function invalidateCoordinateLaws(documentValue = null) {
  if (documentValue) LAW_CACHE.delete(documentValue);
  else LAW_CACHE = new WeakMap();
}

// The declaration a frame's coordinates are actually governed by: its own if it
// declares levels, otherwise whatever it defers to. This is the same chain the
// shipped conversion walked (`coordinateDefinition`, then the gregorian
// kind/trait, then `basis`), which is why a calendar with `basis:
// frame:wall-time` inherits wall time's law -- exactly what the owner means by
// "that is the frame defining the inherited calendar structure".
// The BASIS deliberately outranks a frame's own non-calendar declaration, which
// is the order the shipped conversion used and the order the owner's mental
// model needs: a calendar whose basis is Wall Time inherits Wall Time's law,
// including a radix edited there, without restating the ladder itself.
function resolveDeclaration(documentValue, frameId, seen) {
  if (seen.has(frameId)) throw new Error(`Coordinate definition cycle at ${frameId}`);
  seen.add(frameId);
  const frame = documentValue?.frames?.[frameId];
  if (!frame) throw new Error(`Unknown frame: ${frameId}`);
  if (frame.coordinateDefinition) return resolveDeclaration(documentValue, frame.coordinateDefinition, seen);
  const declaration = frame.coordinate;
  const authored = Array.isArray(declaration?.levels) && declaration.levels.length;
  // POSITIONALITY IS A PROPERTY OF THE LADDER AND THE REGISTRY, never of a kind
  // string or a trait. `positional: undefined` hands the decision to the
  // constructor, which asks whether a registered family can actually execute the
  // ladder -- so an identical year > month > day declaration resolves the same
  // way whether or not anyone remembered to write `kind: "gregorian"` on it.
  // Deciding by label instead placed 2026-08-20 at day ordinal 20, silently, for
  // any declaration that spelled its kind differently.
  //
  // The one semantic marker that survives is `measure`, and it is not a label
  // for arithmetic: it says what the frame IS. A measure frame's coordinate is a
  // MAGNITUDE -- "5 days" -- so its levels are counts and not positions, and no
  // family may reinterpret them as a date.
  const magnitude = frame.traits?.includes("measure") || frame.traits?.includes("duration");
  const positional = magnitude ? false : undefined;
  if (declaration?.kind === "gregorian" || frame.traits?.includes("gregorian")) {
    // A gregorian frame with no authored ladder gets the registered one, which
    // is what the `gregorian` kind has always meant here. The kind survives only
    // as this default-ladder shorthand, never as the positionality answer.
    return { declaration: authored ? declaration : GREGORIAN_DECLARATION, frameId, positional };
  }
  // An ERA TABLE or an authored ORIGIN is a frame stating that its own levels
  // name positions -- an era is not a magnitude, and an origin is precisely the
  // statement of which day the ladder starts on. Such a frame owns its
  // coordinates outright and does not defer to a basis for them.
  if (authored && (declaration.eras || declaration.origin)) {
    return { declaration, frameId, positional };
  }
  if (frame.basis) return resolveDeclaration(documentValue, frame.basis, seen);
  return { declaration: declaration || null, frameId, positional };
}

export function coordinateLaw(documentValue, frameId) {
  const resolved = resolveDeclaration(documentValue, frameId, new Set());
  let perDocument = LAW_CACHE.get(documentValue);
  if (!perDocument) {
    perDocument = new Map();
    LAW_CACHE.set(documentValue, perDocument);
  }
  const cached = perDocument.get(frameId);
  if (cached && cached.declaration === resolved.declaration) return cached.law;
  const law = new CoordinateLaw(resolved.declaration, {
    frameId: resolved.frameId,
    positional: resolved.positional
  });
  perDocument.set(frameId, { declaration: resolved.declaration, law });
  return law;
}

// The law that governs DISPLAY arithmetic for a render pass: the primary frame's
// (src/frame-selection.js -- the explicit primary marker owns axis, labels, and
// coordinate law; overlaid companions are drawn against it, never blended with
// it). Falls back to the registered standard when there is no primary yet or its
// declaration is unresolvable, because a broken frame must not blank the stage;
// `coordinateLawError` is how a surface asks what went wrong.
export function displayLaw(documentValue, session) {
  const frameId = session?.activeFrame || session?.frameSelection?.primary?.() || null;
  if (!frameId) return GREGORIAN_LAW;
  try {
    return coordinateLaw(documentValue, frameId);
  } catch {
    return GREGORIAN_LAW;
  }
}

// What is wrong with this frame's declaration, in the author's words, or null
// when it resolves. The frame editor shows this instead of letting an
// unresolvable law fail silently at render time.
export function coordinateLawError(documentValue, frameId) {
  try {
    coordinateLaw(documentValue, frameId);
    return null;
  } catch (error) {
    return error.message;
  }
}

// What is wrong with this COORDINATE under its frame's law, in the author's
// words, or null when it resolves.
//
// The refuse-before-store discipline extends to validation: a document whose era
// coordinates only fail at query time is not a valid document, and reporting it
// as one defers a certain failure to the worst possible moment. This is the seam
// `validateDocument` calls per attachment/staple coordinate; `coordinateLawError`
// is its per-frame sibling.
export function coordinateValueError(documentValue, frameId, value) {
  try {
    coordinateLaw(documentValue, frameId).toDays(value);
    return null;
  } catch (error) {
    return error.message;
  }
}

// The query path's counterpart to `displayLaw`'s catch: a single unresolvable
// frame must not take down a whole projection, for exactly the reason a broken
// frame must not blank the stage. Returns null instead of throwing, so a caller
// can skip the record and collect the reason rather than abort the query.
export function coordinateDaysOrNull(documentValue, frameId, value) {
  try {
    return coordinateLaw(documentValue, frameId).toDays(value);
  } catch {
    return null;
  }
}

export const GREGORIAN_LAW = new CoordinateLaw(GREGORIAN_DECLARATION, { frameId: "gregorian" });

// --- The standard boundary --------------------------------------------------
//
// RFC 5545 times, the host wall clock, and any other interface that speaks plain
// civil Gregorian convert HERE, through the registered entries, and nowhere
// else. Per the ICS ruling: ICS is an explicitly lossy boundary that always
// speaks standard civil Gregorian; an edited coordinate law never reinterprets
// an incoming ICS time, and a coordinate under a non-standard law is converted
// at the boundary rather than emitted as though its level values were Gregorian.
//
// These are named functions rather than inline `GREGORIAN_LAW` calls because the
// name is the assertion: a call site that reads `civilCoordinateToDays` is
// declaring "standard Gregorian, deliberately, not this document's law".
export function civilCoordinateToDays(value) {
  return GREGORIAN_LAW.toDays(value);
}

export function daysToCivilCoordinate(days, subsecondPlaces = 12) {
  return GREGORIAN_LAW.fromDays(days, subsecondPlaces);
}

// The one duration-in-days primitive, melted onto the law.
//
// `governing` may be a document (the magnitude's own `frame` names the law --
// normally `measure:human-time`), a CoordinateLaw, or nothing. A call site that
// has the document MUST pass it: the standard fallback exists for genuinely
// law-free contexts, not as a convenience, because a duration measured against
// the wrong law is the same class of silent wrongness this module removes.
export function durationMagnitudeDays(magnitude, governing = null) {
  return magnitudeLaw(magnitude, governing).magnitudeDays(magnitude);
}

export function magnitudeLaw(magnitude, governing = null) {
  if (governing instanceof CoordinateLaw) return governing;
  const frameId = magnitude?.frame;
  if (governing && frameId && governing.frames?.[frameId]) {
    try {
      return coordinateLaw(governing, frameId);
    } catch {
      return GREGORIAN_LAW;
    }
  }
  return GREGORIAN_LAW;
}

export { MEAN_GREGORIAN_MONTH, MEAN_GREGORIAN_YEAR };
