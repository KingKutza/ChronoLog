// THE RULE LADDER, as properties rather than as a table of expected rungs.
//
// The ruling (8.28, extended 8.31) is a set of laws, not a list of numbers: one
// function of pixels-per-unit running BOTH ways, two tiers at every rung, the
// major a whole number of minors, and no zoom at which the surface stops
// subdividing or starts drawing one flat tone. So the specs sweep the scale over
// many orders of magnitude, and over ladders that are not ours, and assert the
// laws at every point.

import 'dart:math';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/lens/ladder.dart';
import 'package:chronolog/lens/painters/intimate.dart';
import 'package:test/test.dart';

import '../core/corpus.dart';

/// THE SHIPPED LADDER, read from what ships. A hand-copied table here would go
/// stale the first time an increment is authored -- and did: the copy stopped at
/// one minute while the shipped ladder reaches five seconds, so the rungs Don
/// named at the fine end were never being asked about at all.
List<Rational> shippedSteps() => ladderSteps(
  (key) => Rational.parse(intimateTunableDefaults[key]!),
  'intimate.ruleLadder.',
  'intimate.ruleLadderCount',
);

/// The two target spacings, from the ladder's own shipped defaults rather than
/// from numbers written down here: the rung a lens lands on is a function of
/// these, so a spec that invents its own is not asking about the shipped rest
/// state at all.
double shippedTarget(String key) => ladderPixels(null, key);

/// The scales a surface is actually asked to rule at, from a unit a fraction of
/// a pixel wide to one many screens tall, plus seeded points between.
List<double> scales(Random random) => [
  for (var power = -3; power <= 6; power += 1) pow(4, power).toDouble(),
  for (var index = 0; index < 24; index += 1) 0.05 + random.nextDouble() * 4000,
];

void main() {
  final minor = 22.0, major = 66.0;

  test('every rung has two tiers, and the major is a whole number of minors', () {
    final random = Random(specSeed);
    for (final unitPixels in scales(random)) {
      final rung = rungFor(
        unitPixels: unitPixels,
        minorTarget: minor,
        majorTarget: major,
        steps: shippedSteps(),
      );
      expect(rung.minor > Rational.zero, isTrue, reason: 'at $unitPixels the minor vanished');
      expect(
        rung.major > rung.minor,
        isTrue,
        reason: 'at $unitPixels the rung was flat: ${rung.major} over ${rung.minor}',
      );
      expect(
        (rung.major % rung.minor).isZero,
        isTrue,
        reason: 'at $unitPixels ${rung.major} is not whole minors of ${rung.minor}',
      );
    }
  });

  test('both tiers clear their target spacing at every scale', () {
    final random = Random(specSeed);
    for (final unitPixels in scales(random)) {
      final rung = rungFor(
        unitPixels: unitPixels,
        minorTarget: minor,
        majorTarget: major,
        steps: shippedSteps(),
      );
      expect(
        rung.minor.toDouble() * unitPixels >= minor - 1e-9,
        isTrue,
        reason: 'at $unitPixels the minors crowded to '
            '${rung.minor.toDouble() * unitPixels}px',
      );
      expect(
        rung.major.toDouble() * unitPixels >= major - 1e-9,
        isTrue,
        reason: 'at $unitPixels the majors crowded to '
            '${rung.major.toDouble() * unitPixels}px',
      );
    }
  });

  test('the ladder runs BOTH ways: finer as the scale grows, coarser as it shrinks', () {
    final steps = shippedSteps();
    Rational minorAt(double unitPixels) =>
        rungFor(unitPixels: unitPixels, minorTarget: minor, majorTarget: major, steps: steps).minor;
    // Monotone: more pixels per unit never asks for a coarser rung.
    var previous = minorAt(0.05);
    for (var unitPixels = 0.05; unitPixels < 100000; unitPixels *= 1.7) {
      final chosen = minorAt(unitPixels);
      expect(
        chosen <= previous,
        isTrue,
        reason: 'at $unitPixels the rung coarsened from $previous to $chosen',
      );
      previous = chosen;
    }
    // And it never stops in either direction: an hour filling many screens is
    // still subdivided, and a screen holding years is not ruled every hour.
    expect(minorAt(1e6) < shippedSteps().first, isTrue);
    expect(minorAt(1e-3) > shippedSteps().last, isTrue);
  });

  test('the ladder is the AUTHORED one: a calendar with its own increments keeps them', () {
    final random = Random(specSeed);
    for (var trial = 0; trial < 12; trial += 1) {
      // A ladder of nothing like ours: primes and sevenths, ascending.
      final steps = <Rational>[
        for (var index = 1; index <= 4 + random.nextInt(4); index += 1)
          Rational.fromInt(index * (1 + random.nextInt(5)), 7),
      ]..sort((a, b) => a.compareTo(b));
      for (final unitPixels in scales(random).take(12)) {
        final rung = rungFor(
          unitPixels: unitPixels,
          minorTarget: minor,
          majorTarget: major,
          steps: steps,
        );
        expect(rung.major > rung.minor, isTrue);
        expect((rung.major % rung.minor).isZero, isTrue);
        expect(rung.minor.toDouble() * unitPixels >= minor - 1e-9, isTrue);
      }
    }
  });

  test('the law supplies the rungs above its own base unit', () {
    // Zoomed out far enough that no sub-hour increment can serve, the rung comes
    // from the units the caller's law declares -- here a day of 8 hours and a
    // week of 5 of them -- and not from a doubling of ours.
    final day = Rational.fromInt(8), week = Rational.fromInt(40);
    final rung = rungFor(
      unitPixels: 3,
      minorTarget: minor,
      majorTarget: major,
      steps: shippedSteps(),
      extra: [day, week],
    );
    expect(rung.minor, day);
    expect(rung.major, week);
  });

  // THE RUNGS DON NAMED (ISSUES 8.28, extended 8.31): "at rest: minors at the
  // authored increment, e.g. the set 15m, majors at the hour; zoomed in: majors
  // 15m / minors 5m, majors 1m / minors 5s; zoomed out: majors at the week /
  // minors at the day". The resolution note claims "Don-stated rungs land exactly
  // at shipped defaults" -- which nothing was asking.
  //
  // Not at a pinned zoom: a named pair has to be REACHABLE, because which zoom
  // shows it is the surface's business and Don named none.
  test('every rung Don named is one the shipped ladder actually lands on', () {
    final steps = shippedSteps();
    final minorTarget = shippedTarget('rule.minorSpacing');
    final majorTarget = shippedTarget('rule.majorSpacing');
    final reached = <String>{};
    // A fine sweep over eight orders of magnitude of pixels-per-hour: every rung
    // the shipped ladder can produce at any zoom.
    for (var unitPixels = 0.01; unitPixels < 1e6; unitPixels *= 1.02) {
      final rung = rungFor(
        unitPixels: unitPixels,
        minorTarget: minorTarget,
        majorTarget: majorTarget,
        steps: steps,
      );
      reached.add('${rung.major}/${rung.minor}');
    }
    // Named in hours of the frame's own day, which is the unit the ladder is
    // asked in: an hour, a quarter, five minutes, a minute, five seconds.
    const named = <String, (int, int, int, int)>{
      'majors at the hour, minors at the quarter': (1, 1, 1, 4),
      'majors 15m, minors 5m': (1, 4, 1, 12),
      'majors 1m, minors 5s': (1, 60, 1, 720),
    };
    for (final entry in named.entries) {
      final (majorN, majorD, minorN, minorD) = entry.value;
      final want =
          '${Rational.fromInt(majorN, majorD)}/'
          '${Rational.fromInt(minorN, minorD)}';
      expect(
        reached,
        contains(want),
        reason:
            'ISSUES (8.28, extended 8.31): "${entry.key}" is a rung Don named, and no '
            'zoom on the shipped ladder produces it.',
      );
    }
  });

  test('a rule is major exactly where the major unit turns over', () {
    final rung = (major: Rational.fromInt(1), minor: Rational.fromInt(1, 4));
    var majors = 0;
    for (var index = 0; index < 24; index += 1) {
      final at = rung.minor * Rational.fromInt(index);
      if (isMajorRule(at, rung)) majors += 1;
    }
    // One in four, because the major is four minors: the delineation is the
    // arithmetic and not a decoration.
    expect(majors, 6);
  });
}
