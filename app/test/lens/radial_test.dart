// Radial and Spiral geometry, and what a cycle is allowed to resolve to.
//
// The two geometry properties here are the regression guards the web build
// earned the hard way: an arc's endpoints sit exactly on their own rays, and a
// ribbon's two ends are flat cuts colinear with the ray it starts and stops on.
// Swapping those treatments is the bug; these are what catch the swap.

import 'dart:math';

import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/lens/radial/cycles.dart';
import 'package:chronolog/lens/radial/geometry.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/projection_scene.dart';

/// Angles compare through atan2 of the difference, never by raw subtraction: a
/// wrap at pi is not a disagreement.
double normalize(double angle) => atan2(sin(angle), cos(angle));

double angleOf(Offset point, Offset centre) => atan2(point.dy - centre.dy, point.dx - centre.dx);

const double tolerance = 1e-3;

List<Offset> pointsOf(Path path, {double step = 1}) {
  final points = <Offset>[];
  for (final metric in path.computeMetrics()) {
    for (var at = 0.0; at <= metric.length; at += step) {
      points.add(metric.getTangentForOffset(at)!.position);
    }
    points.add(metric.getTangentForOffset(metric.length)!.position);
  }
  return points;
}

void main() {
  const centre = Offset(450, 360);

  group('arc geometry', () {
    test("an arc's endpoints sit exactly on the rays of its own start and stop", () {
      for (final (radius, from, to) in [
        (60.0, -pi / 2, 0.0),
        (278.0, 0.0, pi),
        (150.0, pi / 4, 1.9 * pi),
        (326.0, -3.0, 3.0),
      ]) {
        final path = arcPath(centre, radius, from, to);
        final drawn = pointsOf(path);
        expect(normalize(angleOf(drawn.first, centre) - from).abs(), lessThan(tolerance));
        expect(normalize(angleOf(drawn.last, centre) - to).abs(), lessThan(tolerance));
        for (final point in drawn) {
          expect((point - centre).distance, closeTo(radius, tolerance * radius));
        }
      }
    });

    test("a circle's tangent is exactly perpendicular to its own radius", () {
      const epsilon = 1e-5;
      for (final angle in [0.0, pi / 6, pi / 2, 2.3, -1.1, pi]) {
        final here = polar(centre, 200, angle), next = polar(centre, 200, angle + epsilon);
        final tangent = (next - here) / (next - here).distance;
        final radial = Offset(cos(angle), sin(angle));
        expect((tangent.dx * radial.dx + tangent.dy * radial.dy).abs(), lessThan(tolerance));
      }
    });
  });

  group('the spiral ribbon', () {
    test('both ends are flat cuts colinear with the start ray', () {
      for (final (inner, spacing, turns, samples, halfWidth) in [
        (82.0, 78.0, 1, 180, 17.0),
        (82.0, 42.0, 3, 360, 30.6),
        (60.0, 20.0, 2, 240, 0.7),
      ]) {
        final path = spiralRibbon(
          centre,
          inner: inner,
          spacing: spacing,
          turns: turns,
          samples: samples,
          halfWidth: halfWidth,
        );
        // The outline runs out along the outer edge and back along the inner
        // one, so its closing segment joins the two radii of the start ray -- a
        // segment exactly 2*halfWidth long, and colinear with that ray by
        // construction rather than by a cap's approximation.
        final metric = path.computeMetrics().first;
        final outerStart = metric.getTangentForOffset(0)!.position;
        final innerStart = metric.getTangentForOffset(metric.length - halfWidth * 2)!.position;
        for (final terminus in [outerStart, innerStart]) {
          expect(normalize(angleOf(terminus, centre) - startRay).abs(), lessThan(tolerance));
        }
        expect((outerStart - centre).distance, closeTo(inner + halfWidth, tolerance));
        expect((innerStart - centre).distance, closeTo(max(0, inner - halfWidth), tolerance));
        // The far end is a flat cut too: the outline's outermost point is the
        // outer edge's terminus, and it sits on the same ray. A multi-turn
        // spiral crosses that ray at every whole turn, which is why this asks
        // about the extreme radii rather than about every point on the ray.
        final sampled = pointsOf(path, step: 1 / 2);
        final outermost = sampled.reduce(
          (a, b) => (a - centre).distance >= (b - centre).distance ? a : b,
        );
        expect((outermost - centre).distance, closeTo(inner + turns * spacing + halfWidth, 1 / 2));
        // The sample nearest the terminus, so the bound is the half-pixel walk
        // subtended at that radius rather than the geometry's own error.
        final subtended = 1 / 2 / (inner + turns * spacing);
        expect(
          normalize(angleOf(outermost, centre) - startRay).abs(),
          lessThan(tolerance + subtended),
        );
      }
    });

    test('a whole turn returns to its own ray', () {
      for (final turns in [1, 2, 5]) {
        final at = spiralAt(1, inner: 50, spacing: 20, turns: turns);
        expect(normalize(at.angle - startRay).abs(), lessThan(tolerance));
        expect(at.radius, closeTo(50 + turns * 20, tolerance));
      }
    });

    test('rings pack inward from the outer edge and never invert', () {
      for (final count in [1, 2, 7, 40]) {
        final radii = ringRadii(count, outer: 278, inner: 58);
        expect(radii.length, count);
        expect(radii.first, closeTo(278, tolerance));
        for (var index = 1; index < radii.length; index += 1) {
          expect(radii[index], lessThan(radii[index - 1]));
          expect(radii[index], greaterThanOrEqualTo(58 - tolerance));
        }
      }
    });
  });

  group('guide ticks', () {
    test('divisions come from the law: a 23-hour day gets 23 ticks', () {
      final world = Scene();
      world.calendar('calendar:short', hoursPerDay: 23);
      final law = CoordinateLaw.parse(
        obj(world.document.frames['calendar:short']!.extra['coordinate']),
        frameId: 'calendar:short',
      );
      final guide = guideSettings(law, law.baseDays);
      expect(guide.divisions, 23);
      expect(
        guideTicks(
          divisions: guide.divisions,
          majorEvery: guide.majorEvery,
          unitsPerCycle: 1,
        ).length,
        23,
      );
    });

    test('a major mark never outruns the divisions it marks', () {
      for (final divisions in [1, 4, 23, 64, 999]) {
        final guide = guideSettings(
          gregorianLaw,
          Rational.fromInt(7),
          divisions: divisions,
          majorEvery: 999,
        );
        expect(guide.divisions, lessThanOrEqualTo(64));
        expect(guide.majorEvery, lessThanOrEqualTo(guide.divisions));
        expect(guide.majorEvery, greaterThanOrEqualTo(1));
      }
    });
  });

  group('cycle resolution', () {
    test('the law offers its own cycles, never a hardcoded seven', () {
      final world = Scene();
      world.calendar('calendar:a');
      final law = CoordinateLaw.parse(gregorianDeclarationJson, frameId: 'calendar:a');
      final options = lawCycles(law);
      expect(options.first.days, law.baseDays);
      expect(options.map((option) => option.title), contains('weekday'));
      for (final option in options) {
        expect(option.days! > Rational.zero, isTrue);
      }
    });

    test('a fixed period resolves exactly; a month resolves at its own boundaries', () {
      final options = <CycleOption>[
        (
          id: 'cycle:week',
          title: 'Week',
          period: const {
            'value': {
              'levels': [
                {'level': 'week', 'value': '2'},
              ],
            },
          },
          days: null,
        ),
        (
          id: 'cycle:month',
          title: 'Month',
          period: const {
            'value': {
              'levels': [
                {'level': 'month', 'value': '1'},
              ],
            },
          },
          days: null,
        ),
      ];
      final week = resolveCycle(options, 'cycle:week', law: gregorianLaw);
      expect(week.unsupported, isFalse);
      expect(week.period, Rational.fromInt(14));

      final february = Rational(daysFromCivil(BigInt.from(2026), 2, 16));
      final month = resolveCycle(options, 'cycle:month', law: gregorianLaw, focus: february);
      expect(month.unsupported, isFalse);
      expect(month.dynamic, isTrue);
      expect(month.period, Rational.fromInt(28));
      expect(month.start, Rational(daysFromCivil(BigInt.from(2026), 2, 1)));

      final leap = Rational(daysFromCivil(BigInt.from(2024), 2, 16));
      expect(
        resolveCycle(options, 'cycle:month', law: gregorianLaw, focus: leap).period,
        Rational.fromInt(29),
      );
    });

    test('a cycle it cannot resolve exactly refuses, in its own sentence', () {
      final refusals = <CycleOption>[
        (id: 'a', title: 'Formula', period: const {'kind': 'formula'}, days: null),
        (
          id: 'b',
          title: 'Zero months',
          period: const {
            'value': {
              'levels': [
                {'level': 'month', 'value': '0'},
              ],
            },
          },
          days: null,
        ),
        (id: 'c', title: 'Nothing', period: null, days: null),
      ];
      for (final option in refusals) {
        final resolved = resolveCycle(
          [option],
          option.id,
          law: gregorianLaw,
          focus: Rational.fromInt(20000),
        );
        expect(resolved.id, option.id, reason: option.title);
        expect(resolved.unsupported, isTrue, reason: option.title);
        expect(resolved.period, isNull, reason: option.title);
        expect(resolved.refusal, isNotEmpty, reason: option.title);
      }
    });

    test('an event-defined cycle resolves against its authored series, never past it', () {
      const period = {
        'kind': 'event-defined',
        'frame': 'calendar:a',
        'boundaries': [
          {'id': 'b1', 'at': '100'},
          {'id': 'b2', 'at': '129'},
          {'id': 'b3', 'at': '159'},
        ],
      };
      final option = (id: 'cycle:moon', title: 'Moon', period: period, days: null);
      final inside = resolveCycle(
        [option],
        'cycle:moon',
        law: gregorianLaw,
        focus: Rational.fromInt(110),
      );
      expect(inside.unsupported, isFalse);
      expect(inside.period, Rational.fromInt(29));
      final outside = resolveCycle(
        [option],
        'cycle:moon',
        law: gregorianLaw,
        focus: Rational.fromInt(400),
      );
      expect(outside.unsupported, isTrue);
      expect(outside.refusal, contains('outside'));
    });

    test('a period with an inexact level is null, never a mean', () {
      Json magnitude(String level, String value) => {
        'value': {
          'levels': [
            {'level': level, 'value': value},
          ],
        },
      };
      expect(cyclePeriodHint(magnitude('week', '2'), gregorianLaw), Rational.fromInt(14));
      expect(cyclePeriodHint(magnitude('month', '1'), gregorianLaw), isNull);
      expect(cyclePeriodHint(magnitude('day', 'not a number'), gregorianLaw), isNull);
      expect(cyclePeriodHint(null, gregorianLaw), isNull);
    });
  });
}
