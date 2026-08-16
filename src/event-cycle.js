import { Rational } from "./exact.js";

// Event-defined cycles deliberately contain occurrences rather than a mean
// duration.  `at` is an exact coordinate in `period.frame`; a boundary may
// also name the observed event that established that coordinate.  The finite
// series is the authority: there is no extrapolation before its first or
// after its last boundary.
function malformed(message) {
  return { valid: false, error: message, boundaries: [] };
}

export function eventBoundarySeries(period) {
  if (period?.kind !== "event-defined") return malformed("not an event-defined period");
  if (typeof period.frame !== "string" || !period.frame) return malformed("event-defined period needs a boundary frame");
  if (!Array.isArray(period.boundaries) || period.boundaries.length < 2) {
    return malformed("event-defined period needs at least two explicit boundaries");
  }
  const ids = new Set();
  const boundaries = [];
  for (const [index, source] of period.boundaries.entries()) {
    const id = String(source?.id || "").trim();
    if (!id) return malformed(`boundary ${index + 1} needs an id`);
    if (ids.has(id)) return malformed(`boundary ids must be unique (${id})`);
    ids.add(id);
    try {
      const at = Rational.parse(source?.at);
      if (boundaries.length && at.compare(boundaries.at(-1).at) <= 0) {
        return malformed("event-defined boundaries must be strictly ordered and unambiguous");
      }
      boundaries.push({ id, at, ...(typeof source.event === "string" ? { event: source.event } : {}) });
    } catch {
      return malformed(`boundary ${id} needs an exact finite coordinate`);
    }
  }
  return { valid: true, frame: period.frame, boundaries };
}

/** Resolve the one authored interval containing focus, using [start, end). */
export function resolveEventCycle(period, focus) {
  const series = eventBoundarySeries(period);
  if (!series.valid) return { ...series, resolved: false };
  let at;
  try { at = Rational.parse(focus); } catch { return { ...series, resolved: false, error: "focus must be an exact coordinate" }; }
  let index = -1;
  for (let cursor = 0; cursor < series.boundaries.length - 1; cursor += 1) {
    const start = series.boundaries[cursor].at;
    const end = series.boundaries[cursor + 1].at;
    if (at.compare(start) >= 0 && at.compare(end) < 0) { index = cursor; break; }
  }
  if (index < 0) return { ...series, resolved: false, error: "focus is outside the authored boundary window" };
  const boundary = series.boundaries[index];
  const nextBoundary = series.boundaries[index + 1];
  return { ...series, resolved: true, index, boundary, nextBoundary, start: boundary.at, end: nextBoundary.at, period: nextBoundary.at.sub(boundary.at) };
}

/** Move by authored intervals.  Reverse traversal never infers a predecessor. */
export function stepEventCycle(period, focus, direction = 1) {
  const current = resolveEventCycle(period, focus);
  if (!current.resolved) return current;
  const delta = Number(direction);
  if (!Number.isInteger(delta) || delta === 0) return { ...current, resolved: false, error: "cycle step must be a non-zero whole number" };
  const index = current.index + delta;
  if (index < 0 || index >= current.boundaries.length - 1) {
    return { ...current, resolved: false, error: "requested cycle is outside the authored boundary window" };
  }
  const boundary = current.boundaries[index];
  const nextBoundary = current.boundaries[index + 1];
  return { ...current, resolved: true, index, boundary, nextBoundary, start: boundary.at, end: nextBoundary.at, period: nextBoundary.at.sub(boundary.at) };
}

/** A finite radial/spiral window made only from authored adjacent intervals. */
export function eventCycleWindow(period, focus, past = 0, future = 0) {
  const current = resolveEventCycle(period, focus);
  if (!current.resolved) return current;
  const before = Math.max(0, Math.floor(Number(past) || 0));
  const after = Math.max(0, Math.floor(Number(future) || 0));
  const first = current.index - before;
  const last = current.index + after + 1;
  if (first < 0 || last >= current.boundaries.length) {
    return { ...current, resolved: false, error: "requested window exceeds authored boundaries" };
  }
  return { ...current, windowStart: current.boundaries[first].at, windowEnd: current.boundaries[last].at, firstIndex: first, lastIndex: last - 1 };
}
