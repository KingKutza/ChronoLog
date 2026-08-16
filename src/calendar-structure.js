import { Rational, coordinate } from "./exact.js";

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
    const labels = String(unit?.labels || "").split(",").map((label) => label.trim()).filter(Boolean);
    if (labels.length && (!perParent || labels.length !== Number(perParent.n))) {
      throw new TypeError(`${name} names must contain exactly one name for each ${name} in its parent.`);
    }
    if (new Set(labels.map((label) => label.toLowerCase())).size !== labels.length) {
      throw new TypeError(`${name} names must be distinct.`);
    }
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
