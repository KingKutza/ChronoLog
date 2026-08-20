import { Rational, coordinate } from "./exact.js";
import { CoordinateLaw, assertTransition, registeredTransitions, transitionDefinition } from "./coordinate-law.js";

const FIXED_SCHEMA = "chronolog/fixed-calendar/1";
const UNIT_NAME = /^[a-z][a-z0-9-]*$/i;

function positiveWhole(value, label) {
  const parsed = Rational.parse(value);
  if (parsed.compare(0) <= 0 || parsed.d !== 1n) {
    throw new TypeError(`${label} must be a positive whole number.`);
  }
  return parsed;
}

function positiveExact(value, label) {
  const parsed = Rational.parse(value);
  if (parsed.compare(0) <= 0) throw new TypeError(`${label} must be greater than zero.`);
  return parsed;
}

// --- Authored name lists ----------------------------------------------------
//
// The ONE parser and the ONE count check for every comma-separated list of
// authored names in the program. Both exist because of a field report: entering
// the seven weekday names "Mon,Tue,Batman,Thu,Fri,Sat,Sun" was rejected with
// "you have to define the same number of days" -- a message that blamed the
// author for a count the author had got right, because the only names field
// available belonged to the DAY-WITHIN-MONTH level and therefore demanded one
// name per day of the month.
//
// Two rules follow from that, and they are the reason these are functions rather
// than inline expressions:
//
//   1. A list is checked against the count ITS OWN MEANING requires -- never a
//      neighbouring count that happens to sit nearby in the schema. Seven
//      weekday names belong to a seven-long CYCLE (see `buildCoordinateStructure`
//      below), not to a level whose parent holds twenty-eight to thirty-one of
//      them, and a level whose count VARIES cannot be named one-by-one at all.
//   2. A refusal states both counts and names the offending entry. An author
//      cannot correct a mismatch that is never shown to them.
export function parseNameList(text) {
  if (Array.isArray(text)) return text.map((name) => String(name).trim()).filter(Boolean);
  return String(text ?? "").split(",").map((name) => name.trim()).filter(Boolean);
}

export function validateNameList(names, required, subject, unit = subject) {
  if (!names.length) return names;
  if (required === null || required === undefined) {
    throw new TypeError(
      `${subject} varies in number, so its members cannot be named one at a time.`
      + ` Name a repeating cycle instead (a seven-name week is a cycle, not a level).`
    );
  }
  const count = Number(required);
  if (names.length !== count) {
    throw new TypeError(
      `${subject} needs ${count} name${count === 1 ? "" : "s"}, one for each ${unit};`
      + ` ${names.length} ${names.length === 1 ? "was" : "were"} given.`
    );
  }
  const seen = new Set();
  for (const name of names) {
    const key = name.toLowerCase();
    if (seen.has(key)) throw new TypeError(`${subject} repeats the name "${name}"; each must be distinct.`);
    seen.add(key);
  }
  return names;
}

/**
 * Turn an ordinary, fixed-radix calendar into the existing generic nested
 * coordinate representation.  The period is the exact duration of one
 * top-level unit in the selected base measure (normally Earth days).
 */
export function buildFixedCalendarStructure({ units, smallestUnitDays = "1", epochDays = "0", periodFrame = "measure:human-time" }) {
  if (!Array.isArray(units) || units.length < 2) {
    throw new TypeError("A fixed calendar needs at least a top-level unit and one smaller unit.");
  }
  const normalized = units.map((unit, index) => {
    const name = String(unit?.name || "").trim();
    if (!UNIT_NAME.test(name)) throw new TypeError(`Unit ${index + 1} needs a simple name (letters, numbers, or hyphens).`);
    const perParent = index ? positiveWhole(unit.perParent, `${name} per parent`) : null;
    const labels = validateNameList(
      parseNameList(unit?.labels),
      perParent ? Number(perParent.n) : null,
      `${name} names`,
      name
    );
    return { name, perParent, labels };
  });
  if (new Set(normalized.map((unit) => unit.name.toLowerCase())).size !== normalized.length) {
    throw new TypeError("Each calendar unit needs a distinct name.");
  }
  const baseDays = positiveExact(smallestUnitDays, "Smallest unit length");
  const epoch = Rational.parse(epochDays);
  const total = normalized.slice(1).reduce((value, unit) => value.mul(unit.perParent), baseDays);
  return {
    coordinate: {
      kind: "nested",
      fixed: {
        schema: FIXED_SCHEMA,
        smallestUnitDays: baseDays.toJSON(),
        epochDays: epoch.toJSON(),
        units: normalized.map((unit) => ({
          name: unit.name,
          ...(unit.perParent ? { perParent: unit.perParent.toJSON() } : {}),
          ...(unit.labels.length ? { labels: unit.labels } : {})
        }))
      },
      levels: normalized.map((unit, index) => ({
        name: unit.name,
        ...(index ? { within: normalized[index - 1].name, radix: unit.perParent.toJSON(), ...(unit.labels.length ? { names: unit.labels } : {}) } : {})
      }))
    },
    period: {
      frame: periodFrame,
      value: coordinate([{ level: "day", value: total.toJSON() }])
    },
    totalDays: total.toJSON()
  };
}

/** Return editable fixed-radix values only when the schema is unambiguously ours. */
export function editableFixedCalendarStructure(frame = {}) {
  const fixed = frame.coordinate?.fixed;
  if (fixed?.schema !== FIXED_SCHEMA || !Array.isArray(fixed.units)) return null;
  try {
    const rebuilt = buildFixedCalendarStructure({
      units: fixed.units.map((unit) => ({ ...unit, labels: unit.labels?.join(", ") || "" })),
      smallestUnitDays: fixed.smallestUnitDays,
      periodFrame: frame.period?.frame || "measure:human-time"
    });
    // A fixed coordinate can still be paired with an event-defined or other
    // advanced period. Do not silently replace that structure merely because
    // its coordinate happens to be editable by this small form.
    if (frame.period && JSON.stringify(frame.period) !== JSON.stringify(rebuilt.period)) return null;
    return {
      units: rebuilt.coordinate.fixed.units.map((unit) => ({
        ...unit,
        ...(Object.hasOwn(unit, "labels") ? { labels: unit.labels.join(", ") } : {})
      })),
      smallestUnitDays: rebuilt.coordinate.fixed.smallestUnitDays,
      epochDays: rebuilt.coordinate.fixed.epochDays,
      periodFrame: frame.period?.frame || "measure:human-time",
      totalDays: rebuilt.totalDays
    };
  } catch {
    return null;
  }
}

// --- The coordinate declaration, as editable rows ---------------------------
//
// This is the surface the owner found missing: "When I go into wall time there
// is no section to definecalendar structure, which is weird as that is the frame
// defining the inherited calendar structure." It edits the DECLARATION the
// coordinate engine actually executes -- levels, radices, transitions, names,
// and cycles -- rather than a builder's summary of one, which is why an edit
// made here takes effect at all.
//
// Deliberately DOM-free so the whole contract is testable: the repo's stub-DOM
// harness does not parse innerHTML, so anything that only exists inside a form's
// markup cannot be pinned by a test.

export const COUNT_VARIES = "varies";

/** The rows a form should show for a law, whether authored here or inherited. */
export function editableCoordinateStructure(law) {
  if (!(law instanceof CoordinateLaw)) return null;
  return {
    kind: law.kind,
    levels: law.levels.map((level, index) => ({
      name: level.name,
      within: level.within,
      count: level.radix ? level.radix.toJSON() : "",
      transition: level.transition || (index && !level.radix ? COUNT_VARIES : ""),
      names: (level.names || law.namesFor(level.name) || []).join(", ")
    })),
    cycles: law.cycles().map((cycle) => ({
      name: cycle.name,
      length: cycle.radix.toJSON(),
      phase: String(cycle.offset),
      names: (cycle.names || []).join(", ")
    }))
  };
}

/** Every transition an author may pick, with the wording the form shows. */
export function transitionChoices() {
  return [
    { value: "", label: "Fixed count" },
    ...registeredTransitions().map((name) => ({
      value: name,
      label: `${name} (${transitionDefinition(name).summary})`
    }))
  ];
}

// How many children a level's edge yields, for validating a names list against
// it: an exact count for a radix, null for a transition whose count varies (and
// a names list against one of those is refused, with the reason).
function requiredNameCount(row) {
  if (row.transition) {
    const definition = transitionDefinition(row.transition);
    return definition.meanChildren.d === 1n ? Number(definition.meanChildren.n) : null;
  }
  return row.count === "" || row.count === undefined ? null : Number(positiveWhole(row.count, `${row.name} count`).n);
}

/**
 * Build a coordinate declaration from edited rows. Throws with the author's own
 * words on anything unresolvable, and validates the result by CONSTRUCTING THE
 * LAW: an unknown transition, a mixed calendar family, or a ladder no family can
 * execute is refused here rather than discovered at render time.
 *
 * `previous` carries forward a builder-written `fixed` block only while the
 * edited levels still match it exactly. Once they diverge the block is a stale
 * summary of a structure that no longer exists, and keeping it would make the
 * label projection disagree with the law.
 */
export function buildCoordinateStructure({ levels = [], cycles = [], kind = "nested", previous = null } = {}) {
  const rows = levels
    .map((row) => ({
      name: String(row?.name || "").trim(),
      count: row?.count === undefined || row?.count === null ? "" : String(row.count).trim(),
      transition: row?.transition === COUNT_VARIES ? "" : String(row?.transition || "").trim(),
      names: parseNameList(row?.names)
    }))
    .filter((row) => row.name || row.count || row.transition || row.names.length);
  if (!rows.length) throw new TypeError("A coordinate declaration needs at least one level.");
  const built = [];
  for (const [index, row] of rows.entries()) {
    if (!UNIT_NAME.test(row.name)) {
      throw new TypeError(`Level ${index + 1} needs a simple name (letters, numbers, or hyphens).`);
    }
    if (built.some((level) => level.name.toLowerCase() === row.name.toLowerCase())) {
      throw new TypeError(`Level "${row.name}" is declared twice.`);
    }
    if (index && row.transition && row.count) {
      throw new TypeError(`Level "${row.name}" has both a count and a transition; it takes one or the other.`);
    }
    // An unimplemented transition is refused before its names are counted:
    // otherwise the author is told their name list is the wrong length when the
    // real problem is that nothing can count the level at all.
    if (index && row.transition) assertTransition(row.transition, `Level "${row.name}"`);
    validateNameList(row.names, index === 0 ? null : requiredNameCount(row), `${row.name} names`, row.name);
    built.push({
      name: row.name,
      ...(index ? { within: rows[index - 1].name } : {}),
      ...(index && row.transition ? { transition: row.transition } : {}),
      ...(index && !row.transition && row.count
        ? { radix: positiveWhole(row.count, `${row.name} count`).toJSON() }
        : {}),
      ...(row.names.length ? { names: row.names } : {})
    });
  }
  const builtCycles = cycles
    .map((row) => ({
      name: String(row?.name || "").trim(),
      length: String(row?.length ?? "").trim(),
      phase: String(row?.phase ?? "0").trim() || "0",
      names: parseNameList(row?.names)
    }))
    .filter((row) => row.name || row.length || row.names.length)
    .map((row) => {
      if (!UNIT_NAME.test(row.name)) throw new TypeError(`A cycle needs a simple name (letters, numbers, or hyphens).`);
      const radix = positiveWhole(row.length, `The "${row.name}" cycle length`);
      validateNameList(row.names, Number(radix.n), `The "${row.name}" cycle`, row.name);
      if (!/^[+-]?\d+$/.test(row.phase)) {
        throw new TypeError(`The "${row.name}" cycle phase must be a whole number of units.`);
      }
      return {
        name: row.name,
        radix: radix.toJSON(),
        offset: row.phase,
        ...(row.names.length ? { names: row.names } : {})
      };
    });
  // Anything else the previous declaration carried survives untouched: this grid
  // knows about levels, cycles and the builder block, and a key it has never
  // heard of is data it has no business deleting.
  const declaration = {
    ...(previous || {}),
    kind,
    levels: built
  };
  if (builtCycles.length) declaration.cycles = builtCycles;
  else delete declaration.cycles;
  const fixed = previous?.fixed;
  if (fixed && matchesFixedBlock(fixed, built)) declaration.fixed = fixed;
  else delete declaration.fixed;
  // The law is the arbiter: if it cannot be constructed, the declaration is not
  // authorable, and the author gets the law's own message rather than a render
  // that silently means something else.
  new CoordinateLaw(declaration);
  return declaration;
}

function matchesFixedBlock(fixed, built) {
  const units = Array.isArray(fixed.units) ? fixed.units : [];
  if (units.length !== built.length) return false;
  return units.every((unit, index) => unit.name === built[index].name
    && (index === 0 || String(unit.perParent) === String(built[index].radix)));
}

/** A one-line, author-facing summary of what a declaration adds up to. */
export function coordinateStructureSummary(declaration) {
  const law = new CoordinateLaw(declaration);
  const root = law.levels[0];
  if (!root) return "No levels declared.";
  const rootDays = law.meanUnitDays(root.name);
  const parts = law.levels.slice(1).map((level) => {
    const per = level.radix
      ? level.radix.toJSON()
      : transitionDefinition(level.transition || "")?.summary || "varies";
    return `${per} ${level.name} per ${level.within}`;
  });
  const total = rootDays ? `One ${root.name} = ${rootDays.toJSON()} days (${rootDays.toDecimal(6)}).` : `One ${root.name} has no fixed length.`;
  return [total, ...parts].join(" ");
}
