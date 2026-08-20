import { Rational } from "./exact.js";

// True eras.
//
// Owner ruling: "Hard No. Epochs, true epochs no faking" -- rejecting any
// linearization of eras onto a continuous year axis. So an era is NOT a display
// label pasted over a proleptic year: it is a level of the coordinate itself,
// and the era table is executed law. An era-qualified coordinate stores the ERA
// and the year WITHIN that era ("3E", 433) and never the linearized year (4249).
//
// The distinction is load-bearing in two places. Storage: a record that kept
// 4249 and a label would silently re-anchor every date the moment an era's span
// were corrected, because the label is derived and the number is not. Numbering
// direction: an era may count DOWN (higher number = older), which no single
// continuous axis can express at all -- 2500 BCE is older than 44 BCE, while
// 44 CE is newer than 1 CE, and a linearized year cannot hold both conventions
// at once. Descending numbering is therefore first-class here, not a rendering
// trick applied to negative numbers.
//
// This module is pure and document-free: it converts between an era-qualified
// year and a PROPER YEAR (the integer index the frame's own year ladder counts
// in), parses and formats era-qualified text, and refuses a table it cannot
// resolve. Turning a proper year into days is the coordinate law's job
// (src/coordinate-law.js), because that depends on how long a year is -- which
// is the year ladder's business, not the era table's.

const ERA_NAME = /^[^\s,;][^,;]*$/;

// Which end of an era's span may be open, per direction. An era with no `years`
// is OPEN, and only one end of the whole table can be open in each direction:
//
//   * A DESCENDING open era counts upward as it goes back ("2500 ME" is older
//     than "1 ME"), so its newest year abuts the era after it and its oldest is
//     unbounded. It can only be the FIRST entry.
//   * An ASCENDING open era counts upward as it goes forward, so its first year
//     abuts the era before it and its last is unbounded. It can only be the
//     LAST entry.
//
// An ascending era open at the bottom would have to start at negative infinity,
// and a descending era open at the top would have to count down from infinity.
// Both are refused rather than clamped to something invented.
export const ERA_DIRECTIONS = Object.freeze(["ascending", "descending"]);

function wholeBigInt(value, label) {
  const text = String(value ?? "").trim();
  if (!/^[+-]?\d+$/.test(text)) throw new TypeError(`${label} must be a whole number.`);
  return BigInt(text);
}

function positiveBigInt(value, label) {
  const parsed = wholeBigInt(value, label);
  if (parsed <= 0n) throw new TypeError(`${label} must be greater than zero.`);
  return parsed;
}

function normalizeEntry(entry, index) {
  const name = String(entry?.name ?? "").trim();
  if (!name || !ERA_NAME.test(name)) {
    throw new TypeError(`Era ${index + 1} needs a name (no commas or semicolons).`);
  }
  // The KEY is the era's stored identity -- what a coordinate's era level
  // actually holds ("3E"), as short and stable as a record needs. `name` is the
  // human label and may be rewritten without touching a single stored
  // coordinate. `abbrev` is accepted as a spelling of the same field.
  const key = String(entry?.key ?? entry?.abbrev ?? entry?.abbreviation ?? "").trim() || name;
  if (!ERA_NAME.test(key)) throw new TypeError(`The "${name}" era's key cannot contain a comma or semicolon.`);
  // A purely numeric key or name would make "12 34" unreadable -- there would be
  // no way to tell the era from the year. Refusing it here is what lets `parse`
  // treat the numeric token as the year with nothing left to guess.
  for (const token of [name, key]) {
    if (/^\d+$/.test(token)) {
      throw new TypeError(`An era cannot be called "${token}"; a number alone cannot be told apart from a year.`);
    }
  }
  const direction = String(entry?.direction ?? "ascending");
  if (!ERA_DIRECTIONS.includes(direction)) {
    throw new TypeError(`The "${name}" era's numbering must be ascending or descending, not "${direction}".`);
  }
  // An era with no length is OPEN. Absent, empty, and the explicit word "open"
  // all say so; the explicit spelling is what a hand-authored table reaches for,
  // and reading it as a length would be a silent misparse.
  const declaredYears = entry?.years === undefined || entry?.years === null ? "" : String(entry.years).trim();
  const open = declaredYears === "" || declaredYears.toLowerCase() === "open";
  const years = open ? null : positiveBigInt(declaredYears, `The "${name}" era's length`);
  // Which number an era's years START at. Authored rather than assumed: an era
  // that counts its first year as 0 is a convention, not an error.
  const firstYear = wholeBigInt(entry?.firstYear ?? "1", `The "${name}" era's first year`);
  const affix = String(entry?.affix ?? "prefix");
  if (!["prefix", "suffix"].includes(affix)) {
    throw new TypeError(`The "${name}" era's label must sit before or after its year, not "${affix}".`);
  }
  const ordinal = entry?.ordinal === undefined || entry?.ordinal === null || String(entry.ordinal).trim() === ""
    ? null
    : wholeBigInt(entry.ordinal, `The "${name}" era's ordinal`);
  return { name, key, abbrev: key, direction, years, open, firstYear, affix, ordinal };
}

// The one anchor: "this era's year N is proper year P". Every other era's range
// derives from it plus the bounded spans, which is what keeps the table's
// arithmetic exact and its authoring honest -- the author states one alignment
// they actually know rather than a per-era offset table nobody can verify.
function normalizeAnchor(anchor, entries) {
  const eraName = String(anchor?.era ?? "").trim();
  const found = entries.find((entry) => entry.key === eraName || entry.name === eraName);
  if (!found) {
    throw new TypeError(
      `The era table's anchor names "${eraName || "(nothing)"}", which is not one of its eras`
      + ` (${entries.map((entry) => entry.name).join(", ") || "none declared"}).`
    );
  }
  return {
    era: found.key,
    // Whole, not positive: an era may number its years from 0, and the anchor is
    // checked against that era's own span rather than against a presumed 1.
    year: wholeBigInt(anchor?.year ?? "1", "The anchor's year"),
    properYear: wholeBigInt(anchor?.properYear ?? anchor?.year ?? "1", "The anchor's proper year")
  };
}

export class EraTable {
  constructor(declaration = {}) {
    const declared = Array.isArray(declaration?.entries) ? declaration.entries : [];
    if (!declared.length) throw new TypeError("An era table needs at least one era.");
    const entries = declared.map((entry, index) => normalizeEntry(entry, index));

    // An explicit `ordinal` on every era is authoritative over the order they
    // happen to be listed in. Declaring it on SOME of them is refused rather
    // than half-honoured: a table half-ordered by ordinal and half by position
    // has no single answer to which era comes first.
    const ordinals = entries.filter((entry) => entry.ordinal !== null);
    if (ordinals.length && ordinals.length !== entries.length) {
      throw new TypeError("Either every era declares an ordinal or none does; a partly-ordered table has no order.");
    }
    if (ordinals.length) {
      if (new Set(entries.map((entry) => entry.ordinal)).size !== entries.length) {
        throw new TypeError("Two eras share an ordinal; each must state its own place in the sequence.");
      }
      entries.sort((left, right) => (left.ordinal < right.ordinal ? -1 : left.ordinal > right.ordinal ? 1 : 0));
    }

    const names = new Set();
    for (const entry of entries) {
      for (const token of [entry.name, entry.key]) {
        const key = token.toLowerCase();
        if (names.has(key)) {
          throw new TypeError(`Two eras answer to "${token}"; each name and abbreviation must be distinct.`);
        }
        names.add(key);
      }
    }

    // Openness has to be legal before any range can be derived: an open era in
    // the middle leaves both of its neighbours unresolvable.
    for (const [index, entry] of entries.entries()) {
      if (!entry.open) continue;
      if (entry.direction === "descending" && index !== 0) {
        throw new TypeError(
          `The "${entry.name}" era counts down with no stated length, so it is the calendar's oldest era`
          + ` and must be listed first.`
        );
      }
      if (entry.direction === "ascending" && index !== entries.length - 1) {
        throw new TypeError(
          `The "${entry.name}" era counts up with no stated length, so it is the calendar's newest era`
          + ` and must be listed last.`
        );
      }
    }

    this.entries = entries;
    this.anchor = normalizeAnchor(declaration?.anchor, entries);
    this.affixDefault = "prefix";
    this._resolveRanges();
    Object.freeze(this.entries);
  }

  // Ranges in PROPER YEARS, derived from the single anchor outward. Each era's
  // `firstProper`/`lastProper` are ascending-order bounds regardless of which
  // way the era's own numbering runs; null means open at that end.
  _resolveRanges() {
    const entries = this.entries;
    // `anchor.era` is normalized to the era's KEY, so it is matched by key.
    const anchorIndex = entries.findIndex((entry) => entry.key === this.anchor.era);
    const anchored = entries[anchorIndex];

    this._assertYearInEra(anchored, this.anchor.year, "The anchor sits at");

    // The anchored era first. For a descending era its FIRST-NUMBERED year is
    // its newest, so the anchor pins the era's upper bound; for an ascending era
    // the first-numbered year is its oldest, pinning the lower bound. `firstYear`
    // is the number that first year actually carries, so the offset is measured
    // from it rather than from a presumed 1.
    const offset = this.anchor.year - anchored.firstYear;
    if (anchored.direction === "descending") {
      anchored.lastProper = this.anchor.properYear + offset;
      anchored.firstProper = anchored.years === null ? null : anchored.lastProper - anchored.years + 1n;
    } else {
      anchored.firstProper = this.anchor.properYear - offset;
      anchored.lastProper = anchored.years === null ? null : anchored.firstProper + anchored.years - 1n;
    }

    // Forward from the anchor: each era begins where the previous one ended.
    for (let index = anchorIndex + 1; index < entries.length; index += 1) {
      const previous = entries[index - 1];
      const entry = entries[index];
      if (previous.lastProper === null) {
        throw new TypeError(
          `"${previous.name}" has no stated length, so "${entry.name}" cannot know where it begins.`
        );
      }
      entry.firstProper = previous.lastProper + 1n;
      entry.lastProper = entry.years === null ? null : entry.firstProper + entry.years - 1n;
    }

    // Backward from the anchor: each era ends where the next one begins.
    for (let index = anchorIndex - 1; index >= 0; index -= 1) {
      const next = entries[index + 1];
      const entry = entries[index];
      if (next.firstProper === null) {
        throw new TypeError(
          `"${next.name}" has no stated beginning, so "${entry.name}" cannot know where it ends.`
        );
      }
      entry.lastProper = next.firstProper - 1n;
      entry.firstProper = entry.years === null ? null : entry.lastProper - entry.years + 1n;
    }

    // Contiguity and order, checked rather than assumed: a span that contradicts
    // its neighbours is refused here, before anything is stored.
    for (const [index, entry] of entries.entries()) {
      if (entry.firstProper !== null && entry.lastProper !== null && entry.firstProper > entry.lastProper) {
        throw new TypeError(`The "${entry.name}" era's length leaves it ending before it begins.`);
      }
      const previous = entries[index - 1];
      if (previous && previous.lastProper !== null && entry.firstProper !== null
        && previous.lastProper + 1n !== entry.firstProper) {
        throw new TypeError(
          `"${previous.name}" ends at proper year ${previous.lastProper} but "${entry.name}" begins at`
          + ` ${entry.firstProper}; eras must meet exactly, with no gap and no overlap.`
        );
      }
    }
  }

  era(token) {
    const wanted = String(token ?? "").trim().toLowerCase();
    if (!wanted) return null;
    return this.entries.find((entry) =>
      entry.key.toLowerCase() === wanted || entry.name.toLowerCase() === wanted) || null;
  }

  /** The stored identities, which is what a coordinate's era level holds. */
  eraKeys() {
    return this.entries.map((entry) => entry.key);
  }

  eraNames() {
    return this.entries.map((entry) => entry.name);
  }

  // The era a proper year falls in, or null when the year lies outside every
  // declared era -- a calendar closed at both ends genuinely has no year there,
  // and inventing one is what "no faking" forbids.
  eraAtProperYear(properYear) {
    const year = BigInt(properYear);
    return this.entries.find((entry) =>
      (entry.firstProper === null || year >= entry.firstProper)
      && (entry.lastProper === null || year <= entry.lastProper)) || null;
  }

  // (era, yearWithinEra) -> proper year. Descending eras count backwards from
  // their own newest year, which is where BCE's missing year zero comes from:
  // 1 BCE and 1 CE are adjacent proper years 0 and 1, so nothing has to
  // special-case a gap that was never there.
  _assertYearInEra(entry, year, prefix = "There is") {
    if (year < entry.firstYear) {
      throw new TypeError(
        `${prefix} year ${year} of "${entry.name}", which numbers its years from ${entry.firstYear}.`
      );
    }
    if (entry.years !== null && year > entry.firstYear + entry.years - 1n) {
      throw new TypeError(
        `${prefix} year ${year} of "${entry.name}", which is only ${entry.years} years long.`
      );
    }
  }

  toProperYear(eraToken, yearWithinEra) {
    const entry = this.era(eraToken);
    if (!entry) {
      throw new TypeError(
        `"${eraToken}" is not one of this calendar's eras (${this.eraKeys().join(", ")}).`
      );
    }
    const year = wholeBigInt(yearWithinEra, `A year in "${entry.name}"`);
    this._assertYearInEra(entry, year);
    const offset = year - entry.firstYear;
    return entry.direction === "descending"
      ? entry.lastProper - offset
      : entry.firstProper + offset;
  }

  // Proper year -> {era, year}. The exact inverse of `toProperYear`, refusing
  // rather than clamping when the year is outside the calendar entirely.
  fromProperYear(properYear) {
    const year = BigInt(properYear);
    const entry = this.eraAtProperYear(year);
    if (!entry) {
      throw new RangeError(`Proper year ${year} falls outside every declared era of this calendar.`);
    }
    const within = entry.firstYear + (entry.direction === "descending"
      ? entry.lastProper - year
      : year - entry.firstProper);
    // `era` is the KEY, because that is what a coordinate stores: renaming an
    // era must never rewrite a record.
    return { era: entry.key, key: entry.key, name: entry.name, year: within, entry };
  }

  /** "3E 433", "ME 2500", "44 BCE" -- the affix each era authored for itself. */
  format(eraToken, yearWithinEra) {
    const entry = this.era(eraToken);
    if (!entry) throw new TypeError(`"${eraToken}" is not one of this calendar's eras.`);
    const year = String(yearWithinEra);
    return entry.affix === "suffix" ? `${year} ${entry.key}` : `${entry.key} ${year}`;
  }

  formatProperYear(properYear) {
    const resolved = this.fromProperYear(properYear);
    return this.format(resolved.era, resolved.year.toString());
  }

  /**
   * Text to {era, year}, accepting an era's name or its abbreviation on either
   * side of the number regardless of which affix that era formats with -- a
   * reader who types "433 3E" means the same date as "3E 433". Returns null
   * when no era token is present at all, so a caller can tell "this text names
   * no era" apart from "this text names an era I do not have".
   */
  parse(text) {
    const trimmed = String(text ?? "").trim();
    if (!trimmed) return null;
    const tokens = trimmed.split(/[\s,]+/).filter(Boolean);
    if (tokens.length >= 2) {
      // The YEAR is the numeric token; everything else is the era, joined back
      // up so a multi-word era name ("Third Era 433") resolves as readily as its
      // abbreviation. No era name may be purely numeric, so exactly one end of
      // the text can be the number and there is nothing to disambiguate.
      const [first, last] = [tokens[0], tokens[tokens.length - 1]];
      const leadingYear = /^\d+$/.test(first);
      const trailingYear = /^\d+$/.test(last);
      if (leadingYear === trailingYear) return null;
      const year = leadingYear ? first : last;
      const entry = this.era((leadingYear ? tokens.slice(1) : tokens.slice(0, -1)).join(" "));
      return entry ? { era: entry.key, year } : null;
    }
    // A bare "3E433" cannot be split by shape: an abbreviation may itself contain
    // digits, so "3E433" is only readable BY THE AUTHORED NAMES -- "3E" is an era
    // and "3E4" is not. Each era is tried as a literal prefix and suffix, and two
    // eras matching the same text is refused rather than resolved by precedence.
    const matches = [];
    const lower = trimmed.toLowerCase();
    for (const entry of this.entries) {
      for (const token of [entry.name, entry.key]) {
        const key = token.toLowerCase();
        if (lower.startsWith(key) && /^\d+$/.test(trimmed.slice(token.length))) {
          matches.push({ era: entry.key, year: trimmed.slice(token.length) });
        } else if (lower.endsWith(key) && /^\d+$/.test(trimmed.slice(0, -token.length))) {
          matches.push({ era: entry.key, year: trimmed.slice(0, -token.length) });
        }
      }
    }
    const distinct = new Set(matches.map((match) => `${match.era}/${match.year}`));
    return distinct.size === 1 ? matches[0] : null;
  }

  /** The rows an authoring surface edits, in the order they are declared. */
  toDeclaration() {
    return {
      anchor: {
        era: this.anchor.era,
        year: this.anchor.year.toString(),
        properYear: this.anchor.properYear.toString()
      },
      entries: this.entries.map((entry) => ({
        name: entry.name,
        key: entry.key,
        direction: entry.direction,
        ...(entry.years === null ? {} : { years: entry.years.toString() }),
        ...(entry.affix === "prefix" ? {} : { affix: entry.affix })
      }))
    };
  }

  /** Human-readable ranges, for a form's live preview. */
  summary() {
    return this.entries.map((entry) => {
      const first = entry.firstProper === null ? "open" : entry.firstProper.toString();
      const last = entry.lastProper === null ? "open" : entry.lastProper.toString();
      const length = entry.years === null ? "open-ended" : `${entry.years} years`;
      return `${entry.key}: ${length}, ${entry.direction}, proper years ${first}..${last}`;
    }).join(" · ");
  }
}

/** Exact years-per-era total, for a preview that wants one number. */
export function eraTableSpanYears(table) {
  let total = Rational.parse(0);
  for (const entry of table.entries) {
    if (entry.years === null) return null;
    total = total.add(Rational.parse(entry.years.toString()));
  }
  return total;
}
