// ONE LANE PACKER (ruled 2026-08-19, item 2).
//
// Lanes key on TEMPORAL OVERLAP ONLY. Never on which frame supplied a fact,
// never on whether it is a float, never on a display layer -- two things that do
// not overlap in time share a lane, and two that do never can. The web build ran
// three copies of this algorithm (Intimate, Spiral, Radial) and one of them
// quietly consulted the display layer; there is one copy now, and it has nothing
// else to consult.
//
// Intimate, Spiral and Radial all pack through this. A lens decides what a lane
// LOOKS like; it does not decide what a lane IS.

import '../core/exact.dart';

/// A half-open span on whatever axis the caller is packing: days for a rail,
/// angle for a ring. A zero-width span still occupies its instant.
typedef Span = ({Rational start, Rational end});

/// The lane each span lands in, in the caller's own order, plus how many lanes
/// the packing needed. NO CAP: the radial lenses' hard five-lane ceiling crammed
/// the sixth concurrent object into the shortest lane regardless of overlap.
/// Apparent-magnitude falloff thins a field; an integer never does.
typedef Packing = ({List<int> lanes, int count});

Packing packLanes(List<Span> spans) {
  final order = [for (var index = 0; index < spans.length; index += 1) index]
    ..sort((a, b) {
      final byStart = spans[a].start.compareTo(spans[b].start);
      return byStart != 0 ? byStart : a.compareTo(b);
    });
  final lanes = List.filled(spans.length, 0);
  final ends = <Rational>[];
  for (final index in order) {
    final span = spans[index];
    // A zero-width span still holds its instant, so `<=` would let two
    // simultaneous marks share a lane and draw on top of each other.
    var lane = ends.indexWhere((end) => end <= span.start && end < span.end);
    if (span.end <= span.start) lane = ends.indexWhere((end) => end <= span.start);
    if (lane < 0) {
      lane = ends.length;
      ends.add(span.end);
    } else {
      ends[lane] = span.end > ends[lane] ? span.end : ends[lane];
    }
    lanes[index] = lane;
  }
  return (lanes: lanes, count: ends.length);
}

/// The lane geometry a surface of [extent] gives [count] lanes: each lane's
/// offset and width, gap included. Right-anchored marginalia asks for the LAST
/// lanes of this same packing rather than a narrower rail of its own -- "float
/// right-anchored is not a licence to narrow one."
List<({double offset, double size})> laneBands(
  double extent,
  int count, {
  required double gap,
  required double minimum,
}) {
  final lanes = count < 1 ? 1 : count;
  final available = extent - gap * (lanes - 1);
  final size = available / lanes;
  final width = size < minimum ? minimum : size;
  return [
    for (var index = 0; index < lanes; index += 1) (offset: index * (width + gap), size: width),
  ];
}
