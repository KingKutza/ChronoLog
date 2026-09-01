// Polar geometry for Radial and Spiral: hard-won, and carrying its own
// regression guards.
//
// AN EVENT MARK IS A CONSTANT-RADIUS ARC AT ITS MIDPOINT RADIUS, never a path
// that follows the spiral. On a circle the tangent at any point is exactly
// perpendicular to that point's radius, so the arc's endpoints already sit
// exactly on the radial rays of its start and stop angle, and a ROUND cap there
// is the sigil rather than a bug: it is a point-in-time indicator.
//
// THE TRACK IS THE OPPOSITE CASE and must terminate FLUSH on the ray it starts
// and stops on. No stroke cap can do that: a cap cuts perpendicular to its own
// tangent, and a spiral's tangent mixes angular and radial travel, so round,
// butt and square all land NEAR the ray and none on it. So the ribbon is a
// filled polygon offset along each sample's RADIUS instead. Turns is a whole
// number, so progress zero and progress one are the same ray, and the segment
// joining the two boundary points is colinear with it by construction -- an
// exact flat terminus, not an approximation of one.
//
// Swapping those two treatments is the exact regression this file exists to
// prevent.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme.dart';
import '../tunables.dart';

/// Screen convention: zero is the +x axis and the angle increases clockwise,
/// which puts `-pi/2` straight up. Every radial-family lens shares it.
Offset polar(Offset centre, double radius, double angle) =>
    Offset(centre.dx + math.cos(angle) * radius, centre.dy + math.sin(angle) * radius);

/// The ray a cycle starts and stops on.
const double startRay = -math.pi / 2;

/// One circular arc. Its endpoints are exactly on the rays of [from] and [to].
Path arcPath(Offset centre, double radius, double from, double to) {
  final rect = Rect.fromCircle(center: centre, radius: radius);
  final start = polar(centre, radius, from);
  return Path()
    ..moveTo(start.dx, start.dy)
    ..arcTo(rect, from, to - from, false);
}

/// The spiral track's closed outline: offset along each sample's own radius, so
/// both termini are flat cuts colinear with the start ray.
///
/// [turns] must be whole. A fractional turn ends somewhere that is not the ray,
/// and the flat cut stops being a cut and becomes a slice.
Path spiralRibbon(
  Offset centre, {
  required double inner,
  required double spacing,
  required int turns,
  required int samples,
  required double halfWidth,
}) {
  final outer = <Offset>[], within = <Offset>[];
  for (var index = 0; index <= samples; index += 1) {
    final progress = index / samples;
    final angle = startRay + progress * turns * math.pi * 2;
    final radius = inner + progress * turns * spacing;
    outer.add(polar(centre, radius + halfWidth, angle));
    within.add(polar(centre, math.max(0, radius - halfWidth), angle));
  }
  final path = Path()..moveTo(outer.first.dx, outer.first.dy);
  for (final point in outer.skip(1)) {
    path.lineTo(point.dx, point.dy);
  }
  for (final point in within.reversed) {
    path.lineTo(point.dx, point.dy);
  }
  return path..close();
}

/// Where one instant sits on a multi-turn spiral: the angle around and the
/// radius outward, from a progress fraction over the whole window.
({double angle, double radius}) spiralAt(
  double progress, {
  required double inner,
  required double spacing,
  required int turns,
}) =>
    (angle: startRay + progress * turns * math.pi * 2, radius: inner + progress * turns * spacing);

/// The ring radii of a stack of bands packed inward from the outer edge, so a
/// document with more groups than rings thins rather than overflows.
List<double> ringRadii(int count, {required double outer, required double inner}) {
  if (count < 1) return const [];
  final step = count == 1 ? 0.0 : (outer - inner) / (count - 1);
  return [for (var index = 0; index < count; index += 1) outer - step * index];
}

/// One guide mark: how strong it is, and whether it names a boundary of the
/// base unit. Four weights, which is the ring's whole legibility design.
typedef GuideTick = ({double angle, bool major, bool boundary, bool noon});

/// The tick ladder around one cycle. [divisions] comes from the law -- a
/// 23-hour day gets 23 ticks -- and [unitsPerCycle] says how many base units the
/// cycle spans, which is what makes a boundary tick a boundary rather than an
/// arbitrary one.
List<GuideTick> guideTicks({
  required int divisions,
  required int majorEvery,
  required double unitsPerCycle,
  bool dayNight = false,
}) {
  final ticks = <GuideTick>[];
  final every = majorEvery < 1 ? 1 : majorEvery;
  for (var index = 0; index < divisions; index += 1) {
    final progress = index / divisions;
    final units = progress * unitsPerCycle;
    final fraction = units - units.floorToDouble();
    ticks.add((
      angle: startRay + progress * math.pi * 2,
      major: index % every == 0,
      boundary: fraction < 1 / divisions || fraction > 1 - 1 / divisions,
      noon: dayNight && (fraction - 1 / 2).abs() < 1 / (divisions * 2),
    ));
  }
  return ticks;
}

/// The four tick weights: plain, major, boundary, and both. A boundary of the
/// base unit reads in ink; everything else reads in the derived tones.
Paint guidePaint(GuideTick tick, ChronoTheme theme, Tunable? read) {
  final width = tick.noon
      ? pixels(read, 'radial.noonTick')
      : tick.major && tick.boundary
      ? pixels(read, 'radial.tickStrong')
      : tick.major
      ? pixels(read, 'radial.tickMajor')
      : pixels(read, 'radial.tickPlain');
  final color = tick.noon
      ? theme.secondary
      : tick.boundary
      ? theme.ink.withValues(
          alpha: tick.major ? pixels(read, 'zone.edge') * 3 / 2 : pixels(read, 'zone.fill') * 4 / 3,
        )
      : tick.major
      ? theme.strong
      : theme.hair;
  return Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..color = color;
}

/// Places labels around a ring, suppressing collisions rather than overlapping
/// them. Deduped by text, measured for real with a [TextPainter], and dropped
/// once the field is full: a label the eye cannot separate is worse than none.
///
/// The anchor flips on the left half so text always reads outward from the ring.
List<({String text, Offset at, bool rightAligned})> placeLabels(
  Iterable<({String text, double angle, double radius})> candidates,
  Offset centre,
  ChronoTheme theme, {
  required int budget,
  Tunable? read,
}) {
  final gapY = pixels(read, 'radial.labelGapY'), gapX = pixels(read, 'radial.labelGapX');
  final placed = <({String text, Offset at, bool rightAligned})>[];
  final seen = <String>{};
  for (final candidate in candidates) {
    if (placed.length >= budget) break;
    if (!seen.add(candidate.text)) continue;
    final at = polar(centre, candidate.radius, candidate.angle);
    final collides = placed.any(
      (other) => (other.at.dy - at.dy).abs() < gapY && (other.at.dx - at.dx).abs() < gapX,
    );
    if (collides) continue;
    placed.add((text: candidate.text, at: at, rightAligned: math.cos(candidate.angle) < 0));
  }
  return placed;
}

/// The box one haloed label would occupy, drawn at [at]. Measured, not guessed:
/// a label that collides is a label the surface must thin, and a collision test
/// against an assumed width is a test of nothing (ISSUES 9.1, Tree overlap).
Rect haloedLabelBox(String text, Offset at, {required ChronoTheme theme, Tunable? read}) {
  final size = pixels(read, 'minimap.labelSize');
  final painter = TextPainter(
    text: TextSpan(text: text, style: theme.data.copyWith(fontSize: size)),
    textDirection: TextDirection.ltr,
  )..layout();
  return Rect.fromLTWH(at.dx, at.dy - size / 2, painter.width, painter.height);
}

/// Draws one label twice -- a paper stroke, then the ink fill -- so it stays
/// readable over whatever arc it crosses. Flutter has no paint-order property;
/// the halo IS the second draw.
void paintHaloed(
  Canvas canvas,
  String text,
  Offset at, {
  required ChronoTheme theme,
  required bool rightAligned,
  Tunable? read,
  double opacity = 1,
}) {
  final size = pixels(read, 'minimap.labelSize');
  final halo = pixels(read, 'radial.labelHalo');
  for (final paint in [
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = halo
      ..color = theme.paper.withValues(alpha: opacity),
    Paint()..color = theme.ink.withValues(alpha: opacity),
  ]) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: theme.data.copyWith(fontSize: size, foreground: paint),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(rightAligned ? at.dx - painter.width : at.dx, at.dy - size / 2));
  }
}
