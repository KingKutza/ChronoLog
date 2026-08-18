import { levelValue } from "./exact.js";

// How an RRULE stops: never, after a number of occurrences (COUNT), or on a
// date (UNTIL). No DOM code lives here so the whole contract is testable.
//
// RFC 5545 forbids COUNT and UNTIL in the same rule, and the editor used to
// offer only COUNT — so "ends after" could only be an integer and a series that
// ends on a date was unreachable from the UI, even though `engine.js` has always
// honoured UNTIL and `ics.js` round-trips it verbatim.
//
// UNTIL values are compared against an occurrence's own ordinal, inclusively:
// engine.js drops an occurrence when `day > until`. Everything below therefore
// puts UNTIL *at or after* the last instant meant to survive, never before it.

const COUNT_MINIMUM = 1;
const COUNT_MAXIMUM = 10000;

export function recurrenceEndMode(rrule = {}) {
  const count = rrule?.COUNT;
  if (count !== undefined && String(count).trim() !== "") return "count";
  if (rrule?.UNTIL) return "until";
  return "never";
}

function padYear(text) {
  const negative = String(text).startsWith("-");
  const digits = String(text).replace(/^[+-]/, "").padStart(4, "0");
  return `${negative ? "-" : ""}${digits}`;
}

function pad(value) {
  return String(value).padStart(2, "0");
}

// The calendar date an UNTIL falls on, for putting back into a date input.
export function recurrenceUntilDate(until) {
  const match = /^([+-]?\d{4,})(\d{2})(\d{2})/.exec(String(until || "").trim());
  return match ? `${match[1]}-${match[2]}-${match[3]}` : "";
}

// "Ends on this date" means through the whole of that day, whatever time of day
// the occurrences fall at — so the value is the last second of the date, not its
// midnight. A midnight UNTIL would silently drop a 09:00 series' final
// occurrence, which is the kind of off-by-one a user reads as a bug.
export function recurrenceUntilForDate(dateText) {
  const match = /^([+-]?\d+)-(\d{1,2})-(\d{1,2})$/.exec(String(dateText || "").trim());
  if (!match) return "";
  return `${padYear(match[1])}${pad(match[2])}${pad(match[3])}T235959`;
}

// "Stop repeating here" caps the series at one specific occurrence, inclusively,
// so the value has to be that occurrence's own instant. A date-only series has no
// time of day and gets the plain date form, which keeps the value type matching
// the series the way RFC 5545 expects.
export function recurrenceUntilForCoordinate(value) {
  const year = padYear(levelValue(value, "year", "1970"));
  const month = pad(levelValue(value, "month", "1"));
  const day = pad(levelValue(value, "day", "1"));
  const hour = Number(levelValue(value, "hour", "0"));
  const minute = Number(levelValue(value, "minute", "0"));
  const second = Number(levelValue(value, "second", "0"));
  if (!hour && !minute && !second) return `${year}${month}${day}`;
  return `${year}${month}${day}T${pad(hour)}${pad(minute)}${pad(second)}`;
}

export function normalizeRecurrenceCount(value) {
  const count = Math.floor(Number(String(value ?? "").trim()));
  if (!Number.isFinite(count)) return COUNT_MINIMUM;
  return Math.max(COUNT_MINIMUM, Math.min(COUNT_MAXIMUM, count));
}

// Returns a new rule rather than mutating, and always leaves exactly one of
// COUNT/UNTIL set — an unreachable combination is worse than a rejected one.
export function applyRecurrenceEnd(rrule = {}, input = {}) {
  const next = { ...rrule };
  delete next.COUNT;
  delete next.UNTIL;
  const mode = input.mode === "count" || input.mode === "until" ? input.mode : "never";
  if (mode === "count") {
    next.COUNT = String(normalizeRecurrenceCount(input.count));
  } else if (mode === "until") {
    const until = String(input.until || "").trim();
    // A mode the user chose but left blank falls back to "never" rather than
    // inventing a date.
    const value = /^[+-]?\d{4,}\d{2}\d{2}/.test(until) ? until : recurrenceUntilForDate(until);
    if (value) next.UNTIL = value;
  }
  return next;
}

// Truncate a series so `coordinate` is its last occurrence. Deliberately
// inclusive: the occurrence you are looking at when you ask the series to stop
// is the one you can see, and losing it would make the action feel like a
// deletion rather than an ending.
export function truncateRecurrenceAt(rrule = {}, coordinate) {
  return applyRecurrenceEnd(rrule, { mode: "until", until: recurrenceUntilForCoordinate(coordinate) });
}
