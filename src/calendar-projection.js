import { Rational, floorDiv, floorMod } from "./exact.js";

// Read-only projection helpers for the deliberately small, regular-calendar
// schema.  They do not make an arbitrary coordinate law look regular: callers
// get null for anything not explicitly authored with that schema.
const FIXED_SCHEMA = "chronolog/fixed-calendar/1";

export function fixedCalendarDefinition(frame) {
  const fixed = frame?.coordinate?.fixed;
  if (fixed?.schema !== FIXED_SCHEMA || !Array.isArray(fixed.units) || fixed.units.length < 2) return null;
  try {
    const smallestUnitDays = Rational.parse(fixed.smallestUnitDays);
    if (smallestUnitDays.compare(0) <= 0) return null;
    const radices = fixed.units.slice(1).map((unit) => {
      const radix = Rational.parse(unit.perParent);
      if (radix.compare(0) <= 0 || radix.d !== 1n) throw new TypeError("invalid radix");
      return radix.n;
    });
    const spans = new Array(fixed.units.length);
    let span = 1n;
    for (let index = fixed.units.length - 1; index >= 0; index -= 1) {
      spans[index] = span;
      if (index) span *= radices[index - 1];
    }
    return {
      units: fixed.units,
      smallestUnitDays,
      epochDays: Rational.parse(fixed.epochDays || "0"),
      radices,
      spans
    };
  } catch {
    return null;
  }
}

export function fixedCalendarParts(frame, earthDays) {
  const definition = fixedCalendarDefinition(frame);
  if (!definition) return null;
  const smallestOrdinal = Rational.parse(earthDays).sub(definition.epochDays)
    .div(definition.smallestUnitDays).floor();
  const parts = definition.units.map((unit, index) => {
    const value = index === 0
      ? floorDiv(smallestOrdinal, definition.spans[index]) + 1n
      : floorMod(floorDiv(smallestOrdinal, definition.spans[index]), definition.radices[index - 1]) + 1n;
    const labels = Array.isArray(unit.labels) ? unit.labels : [];
    const label = labels[Number(value - 1n)] || null;
    return { name: unit.name, value, label };
  });
  return { definition, smallestOrdinal, parts };
}

export function fixedDayLabel(frame, earthDays, compact = false) {
  const projected = fixedCalendarParts(frame, earthDays);
  if (!projected) return null;
  const { parts } = projected;
  const leaf = parts.at(-1);
  const parent = parts.at(-2);
  const major = parts.length > 2 ? parts[1] : null;
  const leafText = leaf.label || `${leaf.name} ${leaf.value}`;
  if (compact) return leafText;
  const parentText = parent ? `${parent.name} ${parent.value}` : "";
  const majorText = major ? major.label || `${major.name} ${major.value}` : "";
  return [leafText, parentText, majorText].filter(Boolean).join(" · ");
}

export function fixedMonthWindow(frame, earthDays, count) {
  const projected = fixedCalendarParts(frame, earthDays);
  if (!projected || projected.parts.length < 3 || projected.definition.smallestUnitDays.compare(1) !== 0) return null;
  const monthIndex = 1;
  const span = projected.definition.spans[monthIndex];
  const current = floorDiv(projected.smallestOrdinal, span);
  const amount = Math.max(1, Math.floor(Number(count) || 1));
  const first = current - BigInt(Math.floor(amount / 2));
  return Array.from({ length: amount }, (_, offset) => {
    const ordinal = first + BigInt(offset);
    const start = projected.definition.epochDays.add(new Rational(ordinal * span));
    return { start: start.floor(), span, ordinal };
  });
}
