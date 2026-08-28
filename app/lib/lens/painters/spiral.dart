// SPIRAL: one ring outward per cycle, on a track whose two ENDS ARE FLAT CUTS
// colinear with the vertical ray.
//
// The track and the marks are opposite treatments and must stay that way. The
// ribbon is a filled polygon offset along each sample's own RADIUS, because no
// stroke cap lands flush on a spiral's tilted tangent; an event is a
// CONSTANT-RADIUS ARC at its midpoint radius, whose endpoints therefore sit
// exactly on their own rays and whose ROUND CAP is the point-in-time sigil
// rather than a defect. Swapping the two is the regression the geometry
// substrate exists to prevent.
//
// Everything else -- the cycle, the guide ladder, lanes, labels, capacity, the
// now marker -- is [CurvePainter], shared with Radial. What a spiral IS, is the
// answer to "what radius does this progress sit at": one that grows.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/exact.dart';
import '../../core/projection.dart';
import '../color.dart';
import '../lens_painter.dart';
import '../radial/geometry.dart';
import 'radial.dart';

class SpiralPainter extends CurvePainter {
  SpiralPainter(LensScene scene)
    : super(
        scene,
        'spiral',
        past: scene.number('inward', 'radial.inward').round().toInt(),
        future: scene.number('outward', 'radial.outward').round().toInt(),
      );

  @override
  String get innerKey => 'spiral.innerRadius';

  late final double spacing = math.min(
    scene.dim('spiral.spacingMax'),
    (outer - inner) / math.max(1, cycle.turns),
  );

  /// The whole point of the lens: radius grows with progress, so a year of
  /// cycles reads outward as one continuous track.
  @override
  double radiusOf(int band, double progress) => inner + progress * cycle.turns * spacing;

  @override
  double get bandWidth =>
      math.max(spacing * scene.dim('curve.laneShare'), scene.px('radial.ribbonWidth'));

  /// One track, so no ring packing.
  @override
  List<double> bandRadii(int count) => const [];

  /// The ribbon twice: the track's own body, then a hairline core along its
  /// centre so the spiral still reads where the body is crowded with marks.
  @override
  void paintTrack(Canvas canvas, ColorCascade cascade, List<Band> data) {
    for (final (half, alpha) in [
      (bandWidth / 2, scene.dim('curve.bandOpacity')),
      (scene.px('mark.stroke') / 2, scene.dim('curve.coreOpacity')),
    ]) {
      canvas.drawPath(
        spiralRibbon(
          centre,
          inner: inner,
          spacing: spacing,
          turns: cycle.turns,
          samples: cycle.turns * scene.many('spiral.samplesPerTurn'),
          halfWidth: half,
        ),
        Paint()..color = scene.theme.strong.withValues(alpha: alpha),
      );
    }
  }

  /// One track, so one band. Grouping is Radial's question, not this lens's.
  @override
  List<Band> bandsOf(List<Fact> facts) => facts.isEmpty ? const [] : [(title: '', facts: facts)];

  /// On a spiral the RADIUS is the unambiguous coordinate and the angle is the
  /// one that repeats, so a point reads its day from how far out it sits.
  @override
  Rational? unproject(Offset at) {
    final reach = cycle.turns * spacing;
    if (cycle.period <= Rational.zero || reach <= 0) return null;
    final progress = ((at - centre).distance - inner) / reach;
    if (progress < 0 || progress > 1) return null;
    return cycle.start + (cycle.end - cycle.start) * Rational.parse('$progress');
  }
}
