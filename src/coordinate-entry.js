// The event card's placement field: ONE variable-precision coordinate entry,
// never separate date/time inputs. Owner's ruling: "a single field ... that
// allows for a variable precision entry, eg. Type month day year hour minute
// second millisecond, or pull a picker that lets you zoom it in."
//
// Precision typed IS coordinate depth -- a coordinate whose `levels` array
// stops early, the same partial shape the rest of the model already reads.
// Depth is never fuzziness: no uncertainty/spread data is produced, inferred,
// or implied anywhere in this module. Meaning is authored elsewhere.
//
// Every level name, order, radix, value-name list, and 0-vs-1-based numbering
// comes from the governing frame's own `CoordinateLaw` (src/coordinate-law.js).
// Nothing here hardcodes 12 months, 24 hours, or 60 minutes, and nothing here
// imports `daysFromCivil`/`civilFromDays` -- a custom calendar's field parses
// and formats in ITS OWN units, through the law it was handed.
//
// DOM-free and pure: this module only parses text, formats text, and describes
// picker data. The widget that renders it is a different slice's job.

import { Rational, coordinate } from "./exact.js";
import { transitionDefinition } from "./coordinate-law.js";

// Every separator a human actually types between coordinate values. Runs
// collapse; which specific character was used carries no positional meaning,
// so "2026-08-20" and "2026 8 20" and "2026.08.20" tokenize identically. The
// one place a "." behaves specially is not the separator regex at all -- it is
// the fact that the TRAILING continuous-tail level (see `isContinuousTail`)
// always reinterprets its raw digits as a fraction of its parent unit,
// regardless of which separator preceded them. That is what makes
// "17:00:30.250" and "17 00 30 250" mean the same thing.
const SEPARATORS = /[\s\-/.,:]+/;

// The low bound for a level's legal values. A level whose family default is
// "1" counts from 1 (Gregorian month, day); everything else -- including every
// below-base level and every level in a family-less custom law -- counts from
// 0. This is a rule about the DEFAULT, never a hardcoded per-name list, so a
// custom calendar's own family (if it ever declares one) is read the same way.
function levelBase(law, name) {
  return law.family?.defaults?.[name] === "1" ? 1n : 0n;
}

// The trailing level with no radix and no transition -- the ladder's
// continuous tail (Gregorian's `subsecond`). Only this level may ever carry a
// fractional value, and only when it is the LAST declared level: a "trailing"
// level that declared neither is, by the law's own construction rule, the
// unique level whose count cannot be determined.
function isContinuousTail(law, index) {
  const level = law.levels[index];
  return index === law.levels.length - 1 && !level.radix && !level.transition;
}

// How many children a bounded level actually has, given the coarser values
// already typed/fixed above it (`parts`, keyed by level name to BigInt --
// exactly the shape a transition's own `childrenIn` expects, e.g.
// `parts.year`/`parts.month` for "how many days in this month"). Null when the
// level is unbounded (root, continuous tail) and no count exists to check
// against or enumerate.
function childCount(law, level, parts) {
  if (level.radix) return level.radix.n;
  if (level.transition) return BigInt(transitionDefinition(level.transition).childrenIn(parts));
  return null;
}

// The law's own level order, in the author's own names, for the one refusal
// message every parse failure shares. The continuous tail is left out of the
// enumeration: it is never typed as a standalone position, only ever attached
// as a fraction of the level before it.
function guidanceLevelNames(law) {
  const names = law.levels.map((level) => level.name);
  const trimmed = names.length > 1 && isContinuousTail(law, law.levels.length - 1) ? names.slice(0, -1) : names;
  if (!law.hasEras()) return trimmed;
  // The era and year levels are typed as ONE position, not two: an era key
  // alone names no year, and a bare number alone does not say which era it
  // counts in, so the guidance must say so rather than list them separately.
  // The era is the FRAME, not a level, so there is one year position -- which
  // may be written bare ("433") or qualified with this era's own key ("3E 433").
  const key = law.eraKey();
  const [year, ...rest] = trimmed;
  return [`${year} (e.g. "${key} 1" or "1")`, ...rest];
}

function entryHelpMessage(law) {
  const names = guidanceLevelNames(law);
  if (!names.length) return "This frame declares no coordinate levels to enter.";
  if (names.length === 1) return `Enter ${names[0]} — as deep as you mean.`;
  return `Enter ${names[0]}, then ${names.slice(1).join(", ")} — as deep as you mean.`;
}

// An authored name resolves by case-insensitive exact match first, then by
// unambiguous prefix (three characters or more -- shorter is never attempted,
// so "Ju" is refused rather than guessed at). Two or more names sharing a
// prefix is refused, never guessed: the caller gets -1 for "no resolution",
// identically whether the token matched nothing or matched more than one name.
function resolveAuthoredName(token, names) {
  const lower = token.toLowerCase();
  const exact = names.findIndex((name) => name.toLowerCase() === lower);
  if (exact >= 0) return exact;
  if (token.length < 3) return -1;
  const matches = [];
  names.forEach((name, index) => {
    if (name.toLowerCase().startsWith(lower)) matches.push(index);
  });
  return matches.length === 1 ? matches[0] : -1;
}

// The value already fixed at `name` in a coordinate, or null when the level
// was never typed -- distinct from `levelValue`'s fallback-on-absence contract
// in src/exact.js, because a picker rung and a depth scan both need to tell
// "fixed at zero" apart from "not fixed at all".
function fixedValue(coordinateValue, name) {
  const entry = coordinateValue?.levels?.find((part) => part.level === name);
  return entry ? entry.value : null;
}

/**
 * Text typed coarse-to-fine, in the law's own level order, to a partial
 * coordinate plus the deepest level actually typed. Throws (never guesses) on
 * anything the law cannot resolve: empty input, more values than the law has
 * levels, a token that is neither a whole number nor an authored name, an
 * ambiguous name prefix, or a value outside a level's declared range.
 */
export function parseCoordinateEntry(text, law) {
  const fail = () => { throw new Error(entryHelpMessage(law)); };

  const trimmed = String(text ?? "").trim();
  if (!trimmed) fail();

  let sign = 1n;
  let body = trimmed;
  let hadSign = false;
  if (body[0] === "+" || body[0] === "-") {
    sign = body[0] === "-" ? -1n : 1n;
    body = body.slice(1);
    hadSign = true;
  }

  const tokens = body.split(SEPARATORS).filter(Boolean);
  if (!tokens.length) fail();
  // An era-qualified year spends TWO tokens on the one year level ("3E 433"),
  // so the token budget allows one extra token when this law has eras -- the
  // per-level walk below still refuses anything that does not actually
  // resolve, this is only the outer bound on how many tokens can ever apply.
  if (tokens.length > law.levels.length + (law.hasEras() ? 1 : 0)) fail();

  const parts = {};
  const entries = [];
  let depth = null;

  // TWO CURSORS, because an era-qualified year spends two tokens on one level.
  // Walking a single index over both would slide every level below the year one
  // position out of step -- the day would be read as the hour.
  let levelIndex = 0;
  for (let index = 0; index < tokens.length; index += 1, levelIndex += 1) {
    if (levelIndex >= law.levels.length) fail();
    const level = law.levels[levelIndex];

    // An era frame's year may be written bare ("433") or QUALIFIED with the
    // era's own key ("3E 433"). The frame already fixes which era is meant, so
    // a qualifier is a redundant confirmation rather than a selector: one that
    // names a different era is refused outright instead of silently retargeting
    // a coordinate onto a frame the caller did not ask for.
    if (law.hasEras() && level.name === law.yearLevel) {
      const joined = `${tokens[index]} ${tokens[index + 1] ?? ""}`.trim();
      const qualified = law.parseYear(joined);
      if (qualified) {
        if (hadSign) fail(); // an era-qualified year already states its own direction.
        if (qualified.era !== law.eraKey()) fail();
        // The stored coordinate keeps the LOCAL year the author typed (433,
        // never 4249) but a transition BELOW this level (Gregorian's leap
        // February) resolves against the PROPER year -- "45 BCE" is proper
        // year -44 and IS a leap year though neither two-digit form is
        // divisible by 4 -- so `parts` carries the proper one downward while
        // `entries` keeps the local one. The table's own bounds check is what
        // refuses a year this era does not have.
        let properYear;
        try {
          properYear = law.eraTable.toProperYear(law.eraKey(), qualified.year);
        } catch {
          fail();
        }
        entries.push({ level: level.name, value: qualified.year });
        parts[level.name] = properYear;
        depth = level.name;
        index += 1;
        continue;
      }
    }

    const token = tokens[index];

    if (isContinuousTail(law, levelIndex)) {
      if (!/^\d+$/.test(token)) fail();
      entries.push({ level: level.name, value: `0.${token}` });
      depth = level.name;
      continue;
    }

    let value;
    if (/^\d+$/.test(token)) {
      value = BigInt(token);
      if (levelIndex === 0) value *= sign;
    } else if (level.names && /^[A-Za-z]+$/.test(token)) {
      const found = resolveAuthoredName(token, level.names);
      if (found < 0) fail();
      value = levelBase(law, level.name) + BigInt(found);
    } else {
      fail();
    }

    const count = childCount(law, level, parts);
    if (count !== null) {
      const base = levelBase(law, level.name);
      if (value < base || value >= base + count) fail();
    }

    // A bare year on an era law still has to be a year this era HAS, and the
    // level below it still needs the PROPER year for its own count -- same
    // rule as the era-qualified branch above, so a leap 29th resolves
    // correctly whether or not the era was spelled out.
    if (law.hasEras() && level.name === law.yearLevel) {
      let properYear;
      try {
        properYear = law.eraTable.toProperYear(law.eraKey(), value.toString());
      } catch {
        fail();
      }
      parts[level.name] = properYear;
    } else {
      parts[level.name] = value;
    }
    entries.push({ level: level.name, value: value.toString() });
    depth = level.name;
  }

  return { coordinate: coordinate(entries), depth };
}

// A bounded level's own digit width -- the digit length of its own count
// (12 for a Gregorian month, 31 for a 31-day month, 24 for an hour) -- so
// `formatCoordinateEntry` zero-pads to what THIS law's own level actually
// spans, never to a hardcoded width of two.
function padded(value, count) {
  const negative = value < 0n;
  const digits = (negative ? -value : value).toString().padStart(count.toString().length, "0");
  return negative ? `-${digits}` : digits;
}

// The continuous tail's stored value is a fraction of its parent unit
// (0 <= value < 1, e.g. "0.25" for a quarter second). Formatting strips the
// leading "0." so the digits it prints are exactly the digits `parseCoordinateEntry`
// would reattach a "0." to on the way back in.
function tailDigits(rawValue) {
  const value = Rational.parse(rawValue);
  if (value.compare(0) < 0 || value.compare(1) >= 0) {
    throw new RangeError(`A trailing fractional coordinate value must be between 0 and 1 (got ${rawValue}).`);
  }
  const decimal = value.toDecimal(18);
  const dot = decimal.indexOf(".");
  return dot === -1 ? "0" : decimal.slice(dot + 1);
}

/**
 * The deepest law level actually present in a coordinate, in the law's own
 * order -- or null for an empty coordinate. A level the law does not declare
 * is ignored, never mistaken for depth.
 */
export function coordinateEntryDepth(coordinateValue, law) {
  let deepest = null;
  for (const level of law.levels) {
    if (fixedValue(coordinateValue, level.name) !== null) deepest = level.name;
  }
  return deepest;
}

/**
 * The canonical text for a coordinate, at exactly its own depth. Always
 * numeric (authored names are never emitted, so the round trip through
 * `parseCoordinateEntry` is unambiguous): "-" between above-base levels, a
 * space before the first below-base level, ":" between below-base levels.
 */
export function formatCoordinateEntry(coordinateValue, law) {
  const depthName = coordinateEntryDepth(coordinateValue, law);
  if (!depthName) return "";

  const baseIndex = law.levels.findIndex((level) => level.name === law.baseLevel);
  const depthIndex = law.levels.findIndex((level) => level.name === depthName);
  const parts = {};
  let text = "";

  // The same "-" / " " / ":" placement rule, shared by the era-qualified
  // token and every ordinary one below, so the era case is not a second,
  // divergent copy of the punctuation rule.
  const place = (index, display) => {
    if (index === 0) text = display;
    else if (index <= baseIndex) text += `-${display}`;
    else if (index === baseIndex + 1) text += ` ${display}`;
    else text += `:${display}`;
  };

  for (let index = 0; index <= depthIndex; index += 1) {
    const level = law.levels[index];

    // The YEAR renders era-qualified ("3E 433") through the law's own affix.
    // The era itself is the frame, so it occupies no position of its own -- one
    // token in, one token out, which is what makes the round trip stable.
    if (law.hasEras() && level.name === law.yearLevel) {
      const raw = fixedValue(coordinateValue, level.name);
      if (raw === null) {
        throw new Error(`Coordinate is missing level "${level.name}" between the root and its own depth of "${depthName}".`);
      }
      place(index, law.formatYear(coordinateValue));
      // A level below (Gregorian's leap February) counts against the PROPER
      // year, not the local one just displayed -- same rule as the parse
      // side. An out-of-table year is already invalid stored data; leave
      // `parts` without one rather than compound that error.
      try {
        parts[level.name] = law.eraTable.toProperYear(law.eraKey(), raw);
      } catch { /* see comment above */ }
      continue;
    }

    const raw = fixedValue(coordinateValue, level.name);
    if (raw === null) {
      throw new Error(`Coordinate is missing level "${level.name}" between the root and its own depth of "${depthName}".`);
    }

    let display;
    if (isContinuousTail(law, index)) {
      display = tailDigits(raw);
    } else {
      const value = BigInt(raw);
      const count = childCount(law, level, parts);
      display = count === null ? value.toString() : padded(value, count);
      parts[level.name] = value;
    }

    place(index, display);
  }

  return text;
}

/**
 * The zoomable picker's data: one rung per law level from the root down to
 * (and including) the first level the coordinate has not yet fixed. Each rung
 * is `{ level, label, chosen, bounded, options }`; `options` is
 * `{ value, label }` bounded by the level's own radix or transition
 * (`childrenIn` given the coarser values already chosen, so a leap February
 * offers 29 days and a common one offers 28). The root and the continuous
 * tail have no determinable count: `bounded` is false and `options` is empty,
 * never a materialized guess.
 */
export function coordinatePickerLadder(law, coordinateValue) {
  const depthName = coordinateEntryDepth(coordinateValue, law);
  const depthIndex = depthName ? law.levels.findIndex((level) => level.name === depthName) : -1;
  const lastIndex = Math.min(depthIndex + 1, law.levels.length - 1);
  if (lastIndex < 0) return [];

  const parts = {};
  const rungs = [];

  for (let index = 0; index <= lastIndex; index += 1) {
    const level = law.levels[index];
    const chosen = fixedValue(coordinateValue, level.name);
    // Eras are FRAMES, not a level, so no rung enumerates them: choosing an era
    // is choosing which frame to place on, which happens before this ladder and
    // not inside it.
    const count = childCount(law, level, parts);
    const bounded = count !== null;
    const options = [];

    if (bounded) {
      const base = levelBase(law, level.name);
      const names = law.namesFor(level.name);
      for (let offset = 0n; offset < count; offset += 1n) {
        const value = (base + offset).toString();
        options.push({ value, label: names ? (names[Number(offset)] ?? value) : value });
      }
    }

    rungs.push({ level: level.name, label: level.name, chosen, bounded, options });

    if (chosen !== null && !isContinuousTail(law, index)) {
      try {
        // A transition below the year (Gregorian's leap-February day count)
        // resolves against the PROPER year, not the number typed within this
        // era -- "45 BCE" is proper year -44 and IS a leap year even though
        // neither two-digit form is divisible by 4. Every other level keeps
        // reading its raw chosen value.
        parts[level.name] = law.hasEras() && level.name === law.yearLevel
          ? law.eraTable.toProperYear(law.eraKey(), chosen)
          : BigInt(chosen);
      } catch {
        // A non-integer "chosen" on a bounded level cannot happen from this
        // module's own output; a caller handing in a malformed coordinate
        // simply gets no further children counted from it.
      }
    }
  }

  return rungs;
}

/**
 * The field's own placeholder/help text, e.g. "year-month-day hour:minute:second"
 * under `GREGORIAN_LAW` -- derived from the law's declared levels, so a custom
 * calendar's field advertises its own units rather than a Gregorian assumption.
 */
export function coordinateEntryPlaceholder(law) {
  const aboveNames = law.aboveLadder.map((level) => level.name);
  // Under an era law the year position may carry the era's own key, so the
  // placeholder advertises that rather than a bare number.
  const above = law.hasEras()
    ? [`[${law.eraKey()}] ${aboveNames[0]}`, ...aboveNames.slice(1)].join("-")
    : aboveNames.join("-");
  const below = law.belowLadder.map((level) => level.name).join(":");
  return below ? `${above} ${below}` : above;
}
