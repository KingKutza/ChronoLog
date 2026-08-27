// Pure Dart. Nothing under lib/core/ may import Flutter or a third-party
// package.
//
// Where an object LIVES on the days axis (its home -- the range its own
// connections span) and how strongly it registers when viewed from some
// distance away. Exact throughout: every value here is one rational multiply,
// with no transcendental to approximate and nothing to round.
//
// Ruled generalization (JC-8, Don 2026-08-27, ruling 10): falloff is not a
// special case wired into one lens. It is the CLOSING STEP of the weight
// chain -- "apparent-magnitude falloff as the projector's own closing step,"
// applied multiplicatively after the frame-formula fold. `weight.dart`'s
// `composeWeight` is where that happens; this file is the math it calls.

import 'exact.dart';

/// A closed range on the shared days axis, `start <= end`.
typedef DayExtent = ({Rational start, Rational end});

/// Resolves one staple far end to the day range it occupies, or null when it
/// does not resolve to a coordinate at all.
///
/// THE SEAM: staples are not this file's business. The caller -- the staple
/// substrate, which owns `effectiveObjectStaples` and frame-coordinate
/// resolution -- hands in the far-end ids and this resolver. A many-valued
/// far end, or one that lands on another object rather than a coordinate,
/// resolves to null: its instant is not one coordinate, so it contributes
/// nothing rather than a fabricated one.
typedef ExtentResolver = DayExtent? Function(String farEndId);

/// The day range an object's resolvable staples span -- its implicit
/// placement staple included, because that IS a staple under the connection
/// model. A single resolvable staple gives a zero-width home; an object with
/// nothing resolvable has NO home, and null is that honest answer rather than
/// a fabricated date.
DayExtent? objectHome(Iterable<String> farEndIds, ExtentResolver resolve) {
  Rational? start;
  Rational? end;
  for (final id in farEndIds) {
    final extent = resolve(id);
    if (extent == null) continue;
    if (start == null || extent.start < start) start = extent.start;
    if (end == null || extent.end > end) end = extent.end;
  }
  return start == null ? null : (start: start, end: end!);
}

/// Exact distance in days from a home to an instant: zero anywhere inside the
/// range -- an object is at full presence throughout its own home -- and the
/// gap to the nearer edge outside it. A null home has no distance to report.
Rational? distanceFromHome(DayExtent? home, Rational days) {
  if (home == null) return null;
  if (days < home.start) return home.start - days;
  if (days > home.end) return days - home.end;
  return Rational.zero;
}

/// The one falloff parameter: this many days from home, apparent magnitude is
/// half the base. Seven days is a default, not a law -- a projector may name
/// its own.
final Rational defaultHalfDistanceDays = Rational.fromInt(7);

/// The apparent magnitude of [base] seen from [distance] away:
///
///   apparent = base * half / (half + distance)
///
/// Monotone decreasing in distance, exactly [base] at distance zero, and for
/// a positive base never reaching zero -- a float lapses from prominence, it
/// never lapses from truth. Negative distance reads as its magnitude
/// (distance is a gap, not a direction), and a non-positive half-distance is
/// refused: a falloff that halves at zero distance is a division by zero
/// wearing a parameter.
Rational apparentMagnitude(Rational base, Rational distance, {Rational? halfDistance}) {
  final half = halfDistance ?? defaultHalfDistanceDays;
  if (half <= Rational.zero) {
    throw RangeError('Falloff half-distance must be positive');
  }
  return base * half / (half + distance.abs());
}
