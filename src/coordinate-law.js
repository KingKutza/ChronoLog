import {
  Rational,
  civilFromDays,
  coordinate,
  daysFromCivil,
  daysInMonth,
  floorMod,
  isLeapYear,
  levelValue
} from "./exact.js";

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

export function registerCalendarFamily(definition) {
  const name = String(definition?.name || "");
  if (!name) throw new TypeError("A calendar family needs a name.");
  if (typeof definition.toWholeUnits !== "function" || typeof definition.fromWholeUnits !== "function") {
    throw new TypeError(`Calendar family ${name} must implement toWholeUnits and fromWholeUnits.`);
  }
  const family = Object.freeze({ defaults: {}, aliases: [], calendar: name, ...definition });
  FAMILIES.set(name, family);
  for (const id of [family.calendar, ...family.aliases]) {
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
  ladder(signature) {
    return GREGORIAN_LADDERS.get(signature) || null;
  },
  toWholeUnits(signature, parts) {
    return GREGORIAN_LADDERS.get(signature).toWholeUnits(parts);
  },
  fromWholeUnits(signature, days) {
    return GREGORIAN_LADDERS.get(signature).fromWholeUnits(days);
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

    // The BASE LEVEL is the level whose unit is one day of the base measure --
    // the unit every `days` number in ChronoLog counts. Everything above it is
    // measured by transitions (which count whole base units); everything below
    // it is measured by radix division.
    //
    // A `fixed` block names its own base explicitly: its finest level, scaled by
    // `smallestUnitDays`. Otherwise the base is the deepest level reached by a
    // transition, because a transition's whole point is that it counts days.
    // With neither, the root is the base -- a bare `day -> hour` ladder needs no
    // ceremony to mean what it says.
    const fixed = declaration?.fixed;
    const deepestTransition = [...levels].reverse().find((level) => level.transition) || null;
    if (fixed && levels.length) {
      this.baseLevel = levels[levels.length - 1].name;
      this.baseDays = Rational.parse(fixed.smallestUnitDays ?? "1");
      this.epochDays = Rational.parse(fixed.epochDays ?? "0");
    } else {
      this.baseLevel = deepestTransition?.name || levels[0]?.name || "day";
      this.baseDays = Rational.parse(1);
      this.epochDays = Rational.parse(0);
    }
    if (this.baseDays.compare(0) <= 0) {
      throw new TypeError(`${frameLabel}: the smallest unit must be longer than zero days.`);
    }

    const baseIndex = levels.findIndex((level) => level.name === this.baseLevel);
    this.aboveLadder = baseIndex < 0 ? Object.freeze([]) : Object.freeze(levels.slice(0, baseIndex + 1));
    this.belowLadder = baseIndex < 0 ? Object.freeze([]) : Object.freeze(levels.slice(baseIndex + 1));

    // Every transition above the base must belong to one family: half a
    // Gregorian ladder spliced onto half of something else is not a calendar.
    const families = new Set(this.aboveLadder
      .filter((level) => level.transition)
      .map((level) => TRANSITIONS.get(level.transition).family.name));
    if (families.size > 1) {
      throw new TypeError(`${frameLabel}: levels mix the ${[...families].join(" and ")} calendar families.`);
    }
    this.signature = this.aboveLadder.slice(1).map((level) => level.transition || "").join("+");
    const family = families.size ? FAMILIES.get([...families][0]) : null;
    if (family && !family.ladder(this.signature)) {
      throw new TypeError(
        `${frameLabel}: the ${family.name} family cannot execute the level ladder `
        + `${this.aboveLadder.map((level) => level.name).join(" > ")}.`
      );
    }
    this.positional = positional === undefined ? Boolean(family) : Boolean(positional && family);
    this.family = this.positional ? family : null;
    // Retained even when this law is not positional, so an authoring surface can
    // still describe a measure frame's variable levels ("365 or 366 days").
    this.declaredFamily = family;
  }

  // --- Structure --------------------------------------------------------

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

  monthNames() {
    const monthLevel = this.levels.find((level) => level.transition === "gregorian.months")
      || this.level("month");
    return (monthLevel && this.namesFor(monthLevel.name)) || STANDARD_MONTH_NAMES;
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

  // Below the base, a unit divides down from its parent; above the base, it
  // multiplies up from the child that nests in it. A level whose own edge is a
  // transition -- or that contains one -- has no constant length at all, and
  // says so by returning null rather than a mean masquerading as exact.
  _computeUnitDays(name) {
    if (name === this.baseLevel) return this.baseDays;
    const level = this.level(name);
    if (!level) {
      return STANDARD_UNIT_DAYS[name] ? STANDARD_UNIT_DAYS[name].mul(this.baseDays) : null;
    }
    if (level.transition) return null;
    if (this.belowLadder.some((entry) => entry.name === name)) {
      const parent = level.within ? this.unitDays(level.within) : null;
      // A below-base level with no radix (the ladder's `subsecond` tail) is its
      // parent subdivided continuously rather than into a fixed count: a value
      // of 0.25 there means a quarter of one parent unit. Radix 1, in other
      // words -- which is exactly how the shipped civil conversion treated
      // `subsecond`, as a fraction carried in seconds.
      return parent !== null ? parent.div(level.radix || 1) : null;
    }
    const child = this.levels.find((entry) => entry.within === name);
    if (!child || child.transition || !child.radix) return null;
    const childDays = this.unitDays(child.name);
    return childDays === null ? null : childDays.mul(child.radix);
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

  weekdayNames() {
    return this.cycleNames("weekday") || STANDARD_WEEKDAY_NAMES;
  }

  weekdayLabel(days) {
    return this.cycleLabel("weekday", days);
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
      for (const [index, level] of this.aboveLadder.entries()) {
        const fallback = this.family.defaults[level.name] ?? "1";
        parts.set(index, BigInt(levelValue(value, level.name, fallback)));
      }
      const whole = this.family.toWholeUnits(this.signature, parts);
      return new Rational(whole).mul(this.baseDays).add(this.epochDays).add(this._belowDays(value));
    }
    const raw = value?.levels?.find((entry) => entry.level === this.baseLevel)
      || value?.levels?.find((entry) => entry.level === "day");
    if (!raw) {
      throw new Error(`Frame ${this.frameId || "(anonymous)"} has no temporal coordinate law`);
    }
    return Rational.parse(raw.value).mul(this.baseDays).add(this.epochDays);
  }

  _belowDays(value) {
    let total = Rational.parse(0);
    for (const level of this.belowLadder) {
      const unit = this.unitDays(level.name);
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
    const baseUnits = value.sub(this.epochDays).div(this.baseDays);
    const whole = baseUnits.floor();
    let remainder = baseUnits.sub(whole).mul(this.baseDays);
    const levels = this.family.fromWholeUnits(this.signature, whole)
      .map(([level, amount]) => ({ level, value: amount }));
    const below = [];
    let significant = false;
    for (const [index, level] of this.belowLadder.entries()) {
      const unit = this.unitDays(level.name);
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
  if (declaration?.kind === "gregorian" || frame.traits?.includes("gregorian")) {
    // A gregorian frame with no authored ladder gets the registered one, which
    // is what the `gregorian` kind has always meant here.
    return { declaration: authored ? declaration : GREGORIAN_DECLARATION, frameId, positional: true };
  }
  if (frame.basis) return resolveDeclaration(documentValue, frame.basis, seen);
  return { declaration: declaration || null, frameId, positional: false };
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
