// Falloff math for floats: where an object LIVES on the days axis (its home,
// the range its own connections span) and how strongly it should register when
// viewed from some distance away from that home. Pure over
// `{document, engine}` and exact throughout -- the lens layer consumes this;
// nothing here touches projection, rendering, or the session.

import { Rational, ZERO } from "./exact.js";
import { effectiveObjectStaples, frameEndDays } from "./staples.js";

/**
 * The exact-Rational day range spanned by an object's staples' resolved frame
 * coordinates -- its implicit placement staple included, because that IS a
 * staple under the connection model (src/staples.js's effectiveObjectStaples).
 * A single resolvable staple gives a zero-width home; a many-valued or
 * object-far end contributes nothing (its instant is not one coordinate);
 * an object with nothing resolvable has no home at all, and `null` is that
 * honest answer -- never a fabricated date.
 *
 * Returns `{startDays, endDays}` (both Rational, startDays <= endDays) or null.
 */
export function objectHome(chronologDocument, engine, objectId) {
  let start = null;
  let end = null;
  for (const row of effectiveObjectStaples(chronologDocument, objectId, engine)) {
    const days = frameEndDays(engine, row.far);
    if (days === null) continue;
    if (start === null || days.compare(start) < 0) start = days;
    if (end === null || days.compare(end) > 0) end = days;
  }
  return start === null ? null : { startDays: start, endDays: end };
}

/**
 * Exact distance in days from a home range to an instant: zero anywhere inside
 * the range (an object is at full presence throughout its own home), the gap
 * to the nearer edge outside it. A null home has no distance to report.
 */
export function distanceFromHome(home, days) {
  if (!home) return null;
  const at = Rational.parse(days);
  if (at.compare(home.startDays) < 0) return home.startDays.sub(at);
  if (at.compare(home.endDays) > 0) return at.sub(home.endDays);
  return ZERO;
}

// The one falloff parameter: HALF_DISTANCE_DAYS days from home, apparent
// magnitude is half the base weight. The curve is the simple smooth reciprocal
//
//   apparent = base * 1 / (1 + distance / halfDistanceDays)
//
// -- monotone decreasing in distance, exactly `base` at distance zero, never
// reaching zero (a float lapses from prominence, it never lapses from truth).
// Chosen over an exponential half-life for its exactness: every value is one
// rational multiply, no transcendental approximation to round.
export const DEFAULT_HALF_DISTANCE_DAYS = "7";

/**
 * The apparent magnitude of `baseWeight` seen from `distanceDays` away.
 *
 * All three inputs parse through Rational (numbers, strings, Rationals), the
 * result IS a Rational -- callers that feed the display-weight machinery call
 * `.toNumber()` at their own boundary. Negative distance is read as its
 * magnitude (distance is a gap, not a direction), and a non-positive
 * `halfDistanceDays` is refused: a falloff that halves at zero distance is a
 * division by zero wearing a parameter.
 */
export function apparentMagnitude(baseWeight, distanceDays, { halfDistanceDays = DEFAULT_HALF_DISTANCE_DAYS } = {}) {
  const base = Rational.parse(baseWeight);
  const distance = Rational.parse(distanceDays).abs();
  const half = Rational.parse(halfDistanceDays);
  if (half.compare(0) <= 0) throw new RangeError("halfDistanceDays must be positive");
  return base.mul(half).div(half.add(distance));
}
