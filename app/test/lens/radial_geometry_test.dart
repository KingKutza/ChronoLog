// THE GEOMETRY STANDS ON ITS OWN: no oracle, no node, no shipped JavaScript.
//
// This file replaces the geometry half of the lens differential harness. That
// harness shelled out to `node tool/lens_diff_gen.mjs`, asked the legacy
// `src/*.js` what `polar`, `arcPath` and `spiralRibbon` ought to answer, and
// called any disagreement a port defect. The JavaScript is dead and node is a
// dependency, so the comparison is gone. What it was standing in for is the
// mathematics of the three subjects, and mathematics needs no oracle: a point
// at radius r is r from the centre, an arc's length is its radius times its
// sweep, a ribbon offset along each ray is two half-widths wide on that ray.
// Those are asserted here directly, over seeded random cases, and a red light
// prints the seed that produced it.
//
// Two regimes of tolerance, and which one applies is which side of the engine
// the number came from:
//
//   * `roundoff` -- a value computed in Dart doubles from coordinates the
//     generator keeps under ten thousand pixels. Double arithmetic on such
//     magnitudes rounds at the twelfth decimal; a billionth of a pixel is three
//     orders above that noise and infinitely below anything drawable.
//   * `engine` and `chordShortfall` -- a value read BACK from a `Path` through
//     its metrics. Skia keeps path geometry in single precision, represents an
//     arc as conic sections, and MEASURES a curve by flattening it to chords of
//     a half-pixel sagitta and summing them. A point it hands back is where it
//     should be to a hundredth of a pixel (`engine`); a length it hands back is
//     a chord sum, which is never longer than its arc and falls short of it by
//     a fixed fraction of a pixel per radian swept (`chordShortfall`), and a
//     point read at a fraction of that length is displaced along the arc by the
//     same accumulated shortfall. Both numbers were measured over thousands of
//     random arcs and each constant's own comment says what was seen.
//
// The vertices of the ribbon are OBSERVED, not assumed. `dart:ui` exposes no
// vertex list, so the closed polyline is walked through its own contour
// metric: the tangent of a polyline is constant along a segment and jumps at a
// vertex, so every jump names a corner, and the corner is pinned as the
// intersection of the two segment lines on either side of the jump. A step too
// coarse to see a segment reads as a LOW count, which is red -- the walk cannot
// hide a defect by missing one.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:chronolog/lens/radial/geometry.dart';
import 'package:flutter_test/flutter_test.dart';

final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

/// Every failure names the seed, so a red light is a reproducible one.
String seeded(String message) => '$message  (set CHRONOLOG_SEED=$runSeed to reproduce)';

/// Double rounding on coordinates under ten thousand pixels: see the header.
const double roundoff = 1e-9;

/// Single precision through the path engine: a hundredth of a pixel. Measured
/// over thousands of random arcs, an endpoint read back from a contour sits
/// within two thousandths of a pixel of `polar`; this is five times that.
const double engine = 1e-2;

/// How far a LENGTH read back from a contour may fall short of the true arc,
/// per radian swept. The engine measures a curve by flattening it to chords of
/// at most a half-pixel sagitta and summing them, and a chord is shorter than
/// its arc by about a third of the sagitta per radian -- so the shortfall is a
/// fixed fraction of a pixel per radian, independent of the radius, and always
/// SHORT, never long. Measured over thousands of random arcs the worst was
/// 0.22 px per radian; a quarter pixel covers it, and over the fullest turn
/// asked stays well under two pixels. The same shortfall, accumulated, is how
/// far a point read at a fraction of the length is displaced along the arc.
const double chordShortfall = 1 / 4;

/// How many random cases each property is asked over. Enough that a property
/// false on a region of the domain is found; few enough that the ribbon walk,
/// which touches every fraction of a pixel of a long outline, stays cheap.
const int polarCases = 200, arcCases = 60, ribbonCases = 8;

/// The generator keeps every magnitude where the `roundoff` justification is
/// true: a centre anywhere on a very large screen, a radius up to a thousand
/// pixels, an angle within a few turns of zero.
double between(math.Random random, double low, double high) =>
    low + random.nextDouble() * (high - low);

Offset anyCentre(math.Random random) =>
    Offset(between(random, -2000, 2000), between(random, -2000, 2000));

double anyRadius(math.Random random) => between(random, 1, 1000);

double anyAngle(math.Random random) => between(random, -4 * math.pi, 4 * math.pi);

/// Angles compare through atan2 of the difference, never by raw subtraction: a
/// wrap at pi is not a disagreement.
double normalize(double angle) => math.atan2(math.sin(angle), math.cos(angle));

double angleOf(Offset point, Offset centre) =>
    math.atan2(point.dy - centre.dy, point.dx - centre.dx);

double cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

/// The corners of one closed polyline contour, in path order, starting at the
/// contour's own start point. [step] must be shorter than the shortest segment
/// and [turn] smaller than the smallest real change of direction; both are
/// derived by the caller from the construction under test.
List<Offset> cornersOf(PathMetric metric, {required double step, required double turn}) {
  final corners = <Offset>[];
  var previous = metric.getTangentForOffset(0);
  expect(previous, isNotNull, reason: seeded('the contour has a start'));
  corners.add(previous!.position);
  for (var at = step; at < metric.length; at += step) {
    final current = metric.getTangentForOffset(at);
    expect(current, isNotNull, reason: seeded('the contour has a point at $at of ${metric.length}'));
    final bend = normalize(current!.angle - previous!.angle).abs();
    if (bend > turn) {
      // The corner is where the two segment lines meet: p0 + s*t0 = p1 + u*t1.
      final denominator = cross(previous.vector, current.vector);
      final s = cross(current.position - previous.position, current.vector) / denominator;
      corners.add(previous.position + previous.vector * s);
    }
    previous = current;
  }
  return corners;
}

void main() {
  // ignore: avoid_print
  print('RADIAL GEOMETRY RUN SEED: $runSeed  (set CHRONOLOG_SEED=$runSeed to reproduce)');

  group('polar', () {
    test('the point is exactly radius from the centre, for any centre, radius and angle', () {
      final random = math.Random(runSeed);
      var checked = 0;
      for (var index = 0; index < polarCases; index += 1) {
        final centre = anyCentre(random), radius = anyRadius(random), angle = anyAngle(random);
        final point = polar(centre, radius, angle);
        expect(
          (point - centre).distance,
          closeTo(radius, roundoff),
          reason: seeded('polar($centre, $radius, $angle) = $point is not $radius from the centre'),
        );
        checked += 1;
      }
      expect(checked, greaterThan(0), reason: seeded('at least one case was asked'));
    });

    test('zero is the +x axis, the start ray is straight up, and the angle grows clockwise', () {
      // The implementation's own convention, in its own words: "zero is the +x
      // axis and the angle increases clockwise, which puts -pi/2 straight up."
      // On a y-down screen clockwise from +x is DOWN, so a small positive angle
      // lowers the point.
      final random = math.Random(runSeed + 1);
      var checked = 0;
      for (var index = 0; index < polarCases; index += 1) {
        final centre = anyCentre(random), radius = anyRadius(random);
        final onAxis = polar(centre, radius, 0);
        expect(onAxis.dx, closeTo(centre.dx + radius, roundoff), reason: seeded('angle zero is +x'));
        expect(onAxis.dy, closeTo(centre.dy, roundoff), reason: seeded('angle zero has no rise'));
        final up = polar(centre, radius, startRay);
        expect(up.dx, closeTo(centre.dx, roundoff), reason: seeded('the start ray is vertical'));
        expect(up.dy, closeTo(centre.dy - radius, roundoff), reason: seeded('the start ray points UP'));
        // Anywhere in the first quarter turn is below the axis and right of centre.
        final small = between(random, 0, math.pi / 2);
        final turned = polar(centre, radius, small);
        expect(turned.dy, greaterThan(centre.dy), reason: seeded('a positive angle turns clockwise: down the screen'));
        expect(turned.dx, greaterThan(centre.dx), reason: seeded('and is still right of centre within the first quarter'));
        checked += 1;
      }
      expect(checked, greaterThan(0), reason: seeded('at least one case was asked'));
    });

    test('a full turn is the same point: the map is periodic in the angle', () {
      final random = math.Random(runSeed + 2);
      var checked = 0;
      for (var index = 0; index < polarCases; index += 1) {
        final centre = anyCentre(random), radius = anyRadius(random), angle = anyAngle(random);
        // One to three whole turns, either way round; never zero, which would
        // ask nothing.
        final turns = (1 + random.nextInt(3)) * (random.nextBool() ? 1 : -1);
        final once = polar(centre, radius, angle);
        final again = polar(centre, radius, angle + turns * 2 * math.pi);
        expect(
          (again - once).distance,
          closeTo(0, roundoff),
          reason: seeded('$turns whole turns moved the point from $once to $again'),
        );
        checked += 1;
      }
      expect(checked, greaterThan(0), reason: seeded('at least one case was asked'));
    });

    test('radius zero is the centre itself, exactly, whatever the angle', () {
      // cos and sin of anything finite times zero is zero, and adding zero to a
      // coordinate leaves it: this one is exact, not close.
      final random = math.Random(runSeed + 3);
      var checked = 0;
      for (var index = 0; index < polarCases; index += 1) {
        final centre = anyCentre(random), angle = anyAngle(random);
        expect(
          polar(centre, 0, angle),
          equals(centre),
          reason: seeded('polar($centre, 0, $angle) left the centre'),
        );
        checked += 1;
      }
      expect(checked, greaterThan(0), reason: seeded('at least one case was asked'));
    });

    test('a negative radius reflects through the centre', () {
      // The point at -r is the mirror of the point at r: the two average to the
      // centre, and the one at -r is the one at r half a turn on.
      final random = math.Random(runSeed + 4);
      var checked = 0;
      for (var index = 0; index < polarCases; index += 1) {
        final centre = anyCentre(random), radius = anyRadius(random), angle = anyAngle(random);
        final forward = polar(centre, radius, angle), back = polar(centre, -radius, angle);
        expect(
          ((forward + back) / 2 - centre).distance,
          closeTo(0, roundoff),
          reason: seeded('$forward and $back do not mirror through $centre'),
        );
        expect(
          (back - polar(centre, radius, angle + math.pi)).distance,
          closeTo(0, roundoff),
          reason: seeded('the reflected point is not the point half a turn on'),
        );
        checked += 1;
      }
      expect(checked, greaterThan(0), reason: seeded('at least one case was asked'));
    });
  });

  group('arcPath', () {
    /// A sweep strictly inside one turn, either direction, never zero. The
    /// engine treats a sweep of a full turn or more as a special case (an oval,
    /// or the sweep modulo a turn), and `arcPath` promises ONE circular arc, so
    /// one arc is the domain asked. A hundredth of a turn of margin keeps the
    /// generator off the boundary.
    double anySweep(math.Random random) {
      final magnitude = between(random, math.pi / 100, 2 * math.pi * 99 / 100);
      return random.nextBool() ? magnitude : -magnitude;
    }

    /// The one contour of an arc with a non-zero sweep.
    PathMetric theArc(Path path) {
      final metrics = path.computeMetrics().toList();
      expect(metrics, hasLength(1), reason: seeded('an arc is one contour, found ${metrics.length}'));
      return metrics.single;
    }

    test('both endpoints sit on the circle and coincide with polar at from and to', () {
      final random = math.Random(runSeed + 5);
      var checked = 0;
      for (var index = 0; index < arcCases; index += 1) {
        final centre = anyCentre(random), radius = anyRadius(random);
        final from = anyAngle(random), to = from + anySweep(random);
        final metric = theArc(arcPath(centre, radius, from, to));
        final start = metric.getTangentForOffset(0)!.position;
        final end = metric.getTangentForOffset(metric.length)!.position;
        for (final (point, angle, name) in [(start, from, 'start'), (end, to, 'end')]) {
          expect(
            (point - centre).distance,
            closeTo(radius, engine),
            reason: seeded('the $name of the arc is off the circle of radius $radius about $centre'),
          );
          expect(
            (point - polar(centre, radius, angle)).distance,
            closeTo(0, engine),
            reason: seeded('the $name of the arc is not polar($centre, $radius, $angle)'),
          );
        }
        checked += 1;
      }
      expect(checked, greaterThan(0), reason: seeded('at least one case was asked'));
    });

    test('the arc length is the radius times the swept angle', () {
      // Proportional to the sweep at a given radius, and the constant is the
      // radius: length = r * |sweep|. The bound is one-sided and per radian,
      // because that is the shape of the engine's error (see `chordShortfall`):
      // a chord sum never exceeds its arc, and falls short of it by a fixed
      // fraction of a pixel per radian, not by a fraction of the length -- a
      // relative bound would fail a tiny sweep for noise a long one absorbs.
      final random = math.Random(runSeed + 6);
      var checked = 0;
      for (var index = 0; index < arcCases; index += 1) {
        final centre = anyCentre(random), radius = anyRadius(random);
        final from = anyAngle(random), sweep = anySweep(random);
        final metric = theArc(arcPath(centre, radius, from, from + sweep));
        final arc = radius * sweep.abs();
        expect(
          metric.length,
          lessThanOrEqualTo(arc + engine),
          reason: seeded('an arc of radius $radius sweeping $sweep measured ${metric.length}, LONGER than $arc'),
        );
        expect(
          metric.length,
          greaterThanOrEqualTo(arc - chordShortfall * sweep.abs()),
          reason: seeded('an arc of radius $radius sweeping $sweep measured ${metric.length}, not $arc'),
        );
        checked += 1;
      }
      expect(checked, greaterThan(0), reason: seeded('at least one case was asked'));
    });

    test('a zero sweep is a degenerate path: no length, bounds collapsed to the start', () {
      // The engine may drop a zero-length contour from the metrics altogether,
      // so the claim is over the SUM of whatever contours there are.
      final random = math.Random(runSeed + 7);
      var checked = 0;
      for (var index = 0; index < arcCases; index += 1) {
        final centre = anyCentre(random), radius = anyRadius(random), from = anyAngle(random);
        final path = arcPath(centre, radius, from, from);
        final total = path.computeMetrics().fold(0.0, (sum, metric) => sum + metric.length);
        expect(total, closeTo(0, engine), reason: seeded('a zero sweep has length $total'));
        final bounds = path.getBounds(), start = polar(centre, radius, from);
        expect(bounds.width, closeTo(0, engine), reason: seeded('a zero sweep has width ${bounds.width}'));
        expect(bounds.height, closeTo(0, engine), reason: seeded('a zero sweep has height ${bounds.height}'));
        expect(
          (bounds.center - start).distance,
          closeTo(0, engine),
          reason: seeded('a zero sweep at $from sits at ${bounds.center}, not at its start $start'),
        );
        checked += 1;
      }
      expect(checked, greaterThan(0), reason: seeded('at least one case was asked'));
    });

    test('the sweep direction is honoured: the arc runs from `from` toward `to`, not the long way round', () {
      // Arc length along a circle is uniform in angle, so the point a fraction
      // t along the contour is the point at angle from + t*sweep. The wrong
      // direction puts the midpoint half a turn away -- an unambiguous tell --
      // and a handful of random fractions pin the whole parameterization.
      final random = math.Random(runSeed + 8);
      var checked = 0;
      for (var index = 0; index < arcCases; index += 1) {
        final centre = anyCentre(random), radius = anyRadius(random);
        final from = anyAngle(random), sweep = anySweep(random);
        final metric = theArc(arcPath(centre, radius, from, from + sweep));
        for (final fraction in [1 / 2, random.nextDouble(), random.nextDouble()]) {
          final along = metric.getTangentForOffset(metric.length * fraction)!.position;
          final expected = polar(centre, radius, from + sweep * fraction);
          final wrongWay = polar(centre, radius, from - (2 * math.pi - sweep.abs()) * sweep.sign * fraction);
          expect(
            (along - expected).distance,
            lessThan((along - wrongWay).distance),
            reason: seeded('an arc from $from sweeping $sweep ran the other way round the circle'),
          );
          // The point is ON the circle (the endpoint test says so to the engine
          // tolerance) but the chord-summed length places it a little early
          // along the arc: by at most the accumulated shortfall.
          expect(
            (along - expected).distance,
            lessThanOrEqualTo(chordShortfall * sweep.abs() + engine),
            reason: seeded('$fraction of the way along an arc from $from sweeping $sweep is not at angle ${from + sweep * fraction}'),
          );
          expect(
            (along - centre).distance,
            closeTo(radius, engine),
            reason: seeded('$fraction of the way along an arc of radius $radius the point has left the circle'),
          );
        }
        checked += 1;
      }
      expect(checked, greaterThan(0), reason: seeded('at least one case was asked'));
    });
  });

  group('spiralRibbon', () {
    /// One ribbon's parameters. The domain is where a ribbon is a ribbon:
    /// `inner` clears the half-width by a margin, because the implementation
    /// clamps the inner edge at the centre (`max(0, radius - halfWidth)`) and
    /// below that clamp the inner edge is not two half-widths inside the outer.
    /// `turns` is whole, as the function requires. `samples` is bounded against
    /// `turns` so the bend between consecutive chords stays far above the
    /// engine's single-precision noise in a tangent.
    ({Offset centre, double inner, double spacing, int turns, int samples, double halfWidth}) anyRibbon(
      math.Random random,
    ) {
      final halfWidth = between(random, 1, 12);
      final turns = 1 + random.nextInt(4);
      return (
        centre: anyCentre(random),
        inner: halfWidth + between(random, 20, 120),
        spacing: between(random, 1, 40),
        turns: turns,
        samples: turns * (24 + random.nextInt(137)),
        halfWidth: halfWidth,
      );
    }

    /// The ribbon's corners, as the walk observes them, plus the contour.
    ({PathMetric metric, List<Offset> corners}) observe(
      ({Offset centre, double inner, double spacing, int turns, int samples, double halfWidth}) ribbon,
    ) {
      final path = spiralRibbon(
        ribbon.centre,
        inner: ribbon.inner,
        spacing: ribbon.spacing,
        turns: ribbon.turns,
        samples: ribbon.samples,
        halfWidth: ribbon.halfWidth,
      );
      final metrics = path.computeMetrics().toList();
      expect(metrics, hasLength(1), reason: seeded('a ribbon is one outline, found ${metrics.length}'));
      // The bend between two consecutive chords is one sample's share of the
      // angle swept; the shortest segment is the shorter of a cut across the
      // ribbon and a chord at the innermost radius.
      final bend = 2 * math.pi * ribbon.turns / ribbon.samples;
      final shortest = math.min(2 * ribbon.halfWidth, (ribbon.inner - ribbon.halfWidth) * bend);
      return (
        metric: metrics.single,
        corners: cornersOf(metrics.single, step: shortest / 4, turn: bend / 4),
      );
    }

    test('the outline has two corners per sample ray: one outer, one inner', () {
      // The construction visits every progress index from 0 to `samples`
      // INCLUSIVE, so there are samples + 1 rays, and offsets each ray twice:
      // outward by the half-width and inward by it. Every one of those points
      // is a corner of the outline, and nothing else is.
      final random = math.Random(runSeed + 9);
      var checked = 0;
      for (var index = 0; index < ribbonCases; index += 1) {
        final ribbon = anyRibbon(random);
        final rays = ribbon.samples + 1;
        final seen = observe(ribbon);
        expect(
          seen.corners.length,
          equals(2 * rays),
          reason: seeded(
            'a ribbon of ${ribbon.samples} samples has $rays rays and so ${2 * rays} corners; '
            'the outline shows ${seen.corners.length}',
          ),
        );
        checked += 1;
      }
      expect(checked, greaterThan(0), reason: seeded('at least one case was asked'));
    });

    test('each outer corner is two half-widths farther out than its inner partner, on the same ray', () {
      // Path order is outer[0..S] then inner[S..0], so the partner of outer k
      // is corner 2S + 1 - k. Offset ALONG THE RAY is what makes the two cuts
      // flat, so the pair shares a ray as well as differing by the full width.
      final random = math.Random(runSeed + 10);
      var checked = 0;
      for (var index = 0; index < ribbonCases; index += 1) {
        final ribbon = anyRibbon(random);
        final seen = observe(ribbon);
        final rays = ribbon.samples + 1;
        expect(seen.corners.length, equals(2 * rays), reason: seeded('the corner count is the premise of the pairing'));
        // A position error of `engine` pixels at the innermost radius subtends
        // this much angle; farther out it subtends less.
        final angular = engine / (ribbon.inner - ribbon.halfWidth);
        for (var k = 0; k < rays; k += 1) {
          final outer = seen.corners[k], inner = seen.corners[2 * rays - 1 - k];
          expect(
            (outer - ribbon.centre).distance - (inner - ribbon.centre).distance,
            closeTo(2 * ribbon.halfWidth, engine),
            reason: seeded('ray $k of $ribbon: outer $outer and inner $inner are not two half-widths apart'),
          );
          expect(
            normalize(angleOf(outer, ribbon.centre) - angleOf(inner, ribbon.centre)).abs(),
            lessThan(angular),
            reason: seeded('ray $k of $ribbon: outer $outer and inner $inner are not on one ray'),
          );
        }
        checked += 1;
      }
      expect(checked, greaterThan(0), reason: seeded('at least one case was asked'));
    });

    test('the radius grows monotonically with progress, one turn of spacing per turn', () {
      // Progress k/S carries the radius from `inner` by k/S of `turns * spacing`
      // and the angle from the start ray by k/S of `turns` whole turns. Each
      // outer corner is that radius plus the half-width, on that ray.
      final random = math.Random(runSeed + 11);
      var checked = 0;
      for (var index = 0; index < ribbonCases; index += 1) {
        final ribbon = anyRibbon(random);
        final seen = observe(ribbon);
        final rays = ribbon.samples + 1;
        expect(seen.corners.length, equals(2 * rays), reason: seeded('the corner count is the premise of the walk'));
        final angular = engine / (ribbon.inner - ribbon.halfWidth);
        var previous = double.negativeInfinity;
        for (var k = 0; k < rays; k += 1) {
          final progress = k / ribbon.samples;
          final outer = seen.corners[k];
          final radius = (outer - ribbon.centre).distance;
          expect(radius, greaterThan(previous), reason: seeded('ray $k of $ribbon: the radius fell from $previous to $radius'));
          expect(
            radius,
            closeTo(ribbon.inner + ribbon.halfWidth + progress * ribbon.turns * ribbon.spacing, engine),
            reason: seeded('ray $k of $ribbon: the outer radius is not inner + halfWidth + progress * turns * spacing'),
          );
          expect(
            normalize(angleOf(outer, ribbon.centre) - (startRay + progress * ribbon.turns * 2 * math.pi)).abs(),
            lessThan(angular),
            reason: seeded('ray $k of $ribbon: the corner is not on the ray progress puts it on'),
          );
          previous = radius;
        }
        checked += 1;
      }
      expect(checked, greaterThan(0), reason: seeded('at least one case was asked'));
    });

    test('the outline closes, and both cuts lie flat on the start ray', () {
      // Closed as the engine sees it, and closed as the eye sees it: the last
      // point is the first. And because turns is whole, the far cut (outer S to
      // inner S) is on the same ray as the near cut (inner 0 back to outer 0):
      // the start ray, both of them.
      final random = math.Random(runSeed + 12);
      var checked = 0;
      for (var index = 0; index < ribbonCases; index += 1) {
        final ribbon = anyRibbon(random);
        final seen = observe(ribbon);
        final rays = ribbon.samples + 1;
        expect(seen.metric.isClosed, isTrue, reason: seeded('the ribbon outline is not a closed contour'));
        final first = seen.metric.getTangentForOffset(0)!.position;
        final last = seen.metric.getTangentForOffset(seen.metric.length)!.position;
        expect((last - first).distance, closeTo(0, engine), reason: seeded('the outline ends at $last, not back at $first'));
        expect(seen.corners.length, equals(2 * rays), reason: seeded('the corner count is the premise of naming the cuts'));
        final angular = engine / (ribbon.inner - ribbon.halfWidth);
        for (final (corner, name) in [
          (seen.corners[0], 'outer start'),
          (seen.corners[2 * rays - 1], 'inner start'),
          (seen.corners[rays - 1], 'outer far end'),
          (seen.corners[rays], 'inner far end'),
        ]) {
          expect(
            normalize(angleOf(corner, ribbon.centre) - startRay).abs(),
            lessThan(angular),
            reason: seeded('the $name corner $corner of $ribbon is off the start ray'),
          );
        }
        checked += 1;
      }
      expect(checked, greaterThan(0), reason: seeded('at least one case was asked'));
    });
  });

  // THE DOMAIN IS SAID, NEVER SILENT (ISSUES 9.3, from the geometry rewrite:
  // "FOUR DEFECTS IN `app/lib/lens/radial/geometry.dart`, found while asserting
  // its properties, none fixed").
  //
  // Each of the four is a place where the function accepts an argument it
  // cannot draw and answers with garbage instead of a refusal. The entry's own
  // framing is kept: each case is "a refusal, or a spelled behaviour" -- what
  // is asserted is that the silence ends. A throw of any kind is the refusal
  // branch; otherwise the spelled behaviour is checked.
  //
  //   (1) `turns`. The entry reads "documented whole and nothing enforcing it".
  //       STALE AS WRITTEN: `turns` is `int` in `spiralRibbon` and `spiralAt`
  //       and at every call site (`past + future + 1`), so a fraction cannot be
  //       expressed. What the type does NOT enforce is the sign: zero turns
  //       collapses both edges onto the start ray (a zero-area sliver) and a
  //       negative count winds the radius inward through the centre. The
  //       contract: a turn count below one is refused.
  //   (2) `samples == 0` divides by zero (`index / samples`) and every vertex is
  //       NaN. REFUSAL ONLY, and the reason is what the first draft of this test
  //       found: the engine DROPS non-finite geometry, so a NaN outline measures
  //       as no contour with finite empty bounds -- exactly what an authored
  //       "draws nothing" would measure as. The two cannot be told apart from
  //       outside, so the silence can only end as a refusal. (A negative count
  //       already throws, by accident of `outer.first` on an empty list; the
  //       contract makes it deliberate and includes zero.)
  //   (3) `arcPath` promises "one circular arc" with no stated domain, and the
  //       engine special-cases a sweep at or past a full turn (an oval, or the
  //       sweep modulo a turn). The contract: a sweep of a full turn or more is
  //       refused, or draws the whole circle -- a closed path of length 2*pi*r
  //       -- which is the only "one circular arc" such a sweep can mean.
  //   (4) The inner radius clamps at zero, so a ribbon whose half-width exceeds
  //       its inner radius is silently pinched to the centre and is not two
  //       half-widths wide there. REFUSAL ONLY: the entry's alternative ("spell
  //       what it draws there") is a documentation act a test cannot tell from
  //       today's silence, and the corner walk's own step derivation goes
  //       negative below the clamp -- there is no ribbon to observe.
  //
  // Seeded like everything above; every reason names the seed.
  group('the domain is said, never silent (ISSUES 9.3)', () {
    /// Runs [call]; the thrown object if it refused, else null.
    Object? refusalOf(void Function() call) {
      try {
        call();
        return null;
      } on Object catch (thrown) {
        return thrown;
      }
    }

    test('(1) a turn count below one is refused: nothing winds zero times or inward', () {
      final random = math.Random(runSeed + 13);
      var checked = 0;
      for (var index = 0; index < ribbonCases; index += 1) {
        final halfWidth = between(random, 1, 12);
        final turns = -random.nextInt(4); // 0, -1, -2, -3
        final refusal = refusalOf(
          () => spiralRibbon(
            anyCentre(random),
            inner: halfWidth + between(random, 20, 120),
            spacing: between(random, 1, 40),
            turns: turns,
            samples: 24 + random.nextInt(137),
            halfWidth: halfWidth,
          ),
        );
        expect(
          refusal,
          isNotNull,
          reason: seeded(
            'ISSUES 9.3 (1): spiralRibbon accepted turns = $turns and drew something. A ribbon '
            'winds a whole POSITIVE number of turns; below one there is no ribbon, and the flat '
            'cut it exists to guard is either the whole figure or a reflection through the centre.',
          ),
        );
        checked += 1;
      }
      expect(checked, greaterThan(0), reason: seeded('at least one case was asked'));
    });

    test('(2) a ribbon of no samples is refused: the NaN it would draw is indistinguishable from nothing', () {
      final random = math.Random(runSeed + 14);
      var checked = 0;
      for (var index = 0; index < ribbonCases; index += 1) {
        final halfWidth = between(random, 1, 12);
        final samples = -random.nextInt(3); // 0, -1, -2
        final refusal = refusalOf(
          () => spiralRibbon(
            anyCentre(random),
            inner: halfWidth + between(random, 20, 120),
            spacing: between(random, 1, 40),
            turns: 1 + random.nextInt(4),
            samples: samples,
            halfWidth: halfWidth,
          ),
        );
        expect(
          refusal,
          isNotNull,
          reason: seeded(
            'ISSUES 9.3 (2): spiralRibbon accepted samples = $samples. With no samples index / '
            'samples is NaN and every vertex is NaN; the engine drops the outline silently. '
            'A ribbon of no samples is refused.',
          ),
        );
        checked += 1;
      }
      expect(checked, greaterThan(0), reason: seeded('at least one case was asked'));
    });

    test('(3) a sweep of a full turn or more is refused or is the whole circle', () {
      final random = math.Random(runSeed + 15);
      var checked = 0;
      for (var index = 0; index < arcCases; index += 1) {
        final centre = anyCentre(random), radius = anyRadius(random), from = anyAngle(random);
        // Exactly a turn, and anything up to two: both signs.
        final magnitude = index % 4 == 0 ? 2 * math.pi : between(random, 2 * math.pi, 4 * math.pi);
        final sweep = random.nextBool() ? magnitude : -magnitude;
        Path? path;
        final refusal = refusalOf(() => path = arcPath(centre, radius, from, from + sweep));
        if (refusal != null) {
          checked += 1;
          continue;
        }
        final metrics = path!.computeMetrics().toList();
        final total = metrics.fold(0.0, (sum, metric) => sum + metric.length);
        final circle = 2 * math.pi * radius;
        expect(
          total,
          closeTo(circle, chordShortfall * 2 * math.pi + engine),
          reason: seeded(
            'ISSUES 9.3 (3): arcPath promised one circular arc; a sweep of $sweep at radius '
            '$radius measured $total px, not the whole circle ($circle). The engine drew the '
            'sweep modulo a turn, or an oval, and the signature said neither.',
          ),
        );
        for (final metric in metrics) {
          final start = metric.getTangentForOffset(0)!.position;
          final end = metric.getTangentForOffset(metric.length)!.position;
          expect(
            (end - start).distance,
            closeTo(0, engine),
            reason: seeded('a full turn closes: the arc ends at $end, not back at $start'),
          );
        }
        checked += 1;
      }
      expect(checked, greaterThan(0), reason: seeded('at least one case was asked'));
    });

    test('(4) a half-width wider than the inner radius is refused, never pinched to the centre', () {
      final random = math.Random(runSeed + 16);
      var checked = 0;
      for (var index = 0; index < ribbonCases; index += 1) {
        final inner = between(random, 5, 60);
        final halfWidth = inner + between(random, 0.5, 40);
        final refusal = refusalOf(
          () => spiralRibbon(
            anyCentre(random),
            inner: inner,
            spacing: between(random, 1, 40),
            turns: 1 + random.nextInt(4),
            samples: 24 + random.nextInt(137),
            halfWidth: halfWidth,
          ),
        );
        expect(
          refusal,
          isNotNull,
          reason: seeded(
            'ISSUES 9.3 (4): inner = $inner, halfWidth = $halfWidth: the inner edge is clamped '
            'at the centre and the ribbon is not two half-widths wide on its first rays. '
            'A ribbon that cannot be a ribbon is refused, not drawn thinner in silence.',
          ),
        );
        checked += 1;
      }
      expect(checked, greaterThan(0), reason: seeded('at least one case was asked'));
    });
  });
}
