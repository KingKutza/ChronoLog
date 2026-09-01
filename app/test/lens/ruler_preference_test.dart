// THE LENS HAS AN OPINION (ISSUES 9.1).
//
// "Intimate's major/minor ruler spacing is not nearly opinionated enough and is
// far too narrow: the lens should PREFER STRONGLY its associated rungs (the 1h /
// 15m pair its settings name), and by the time it snaps to a new major that
// major should be a named rung like 10m or 6h — never a 30m or 2h it holds no
// opinion about."
//
// Two properties, swept over orders of magnitude rather than pinned at a zoom:
// the pair it names holds over a band of zooms far wider than geometry alone
// would give it, and no tier it ever produces is a rung it holds no opinion
// about. Both numbers are settings, so both are read from what ships.

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/lens/ladder.dart';
import 'package:chronolog/lens/painters/intimate.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/projection_scene.dart';
import 'painters/grid_scene.dart';

const String frameId = 'calendar:a';

/// How finely the sweep samples pixels-per-hour. The band measured off a sample
/// can only under-report by one step, which is what the claim allows for below.
const double sampleStep = 1.01;

/// The scales a rail is really asked to rule at, finely enough that the band the
/// preference holds over can be measured rather than guessed.
Iterable<double> scales() sync* {
  for (var pixels = 0.5; pixels < 1e5; pixels *= sampleStep) {
    yield pixels;
  }
}

void main() {
  final world = Scene()..calendar(frameId);
  world.place(frameId, civil(2026, 9, 15, 9));
  final scene = sceneOf(world.document, const [frameId]);
  final painter = IntimatePainter(scene);
  render(painter, scene.size);

  test('no tier is ever a rung the lens holds no opinion about', () {
    // Don named these two by name: "never a 30m or 2h it holds no opinion
    // about". In the hours the ladder is asked in, that is a half and a two.
    final unopinionated = [Rational.fromInt(1, 2), Rational.fromInt(2)];
    for (final pixels in scales()) {
      final rung = painter.rung(pixels);
      for (final tier in [rung.major, rung.minor]) {
        expect(
          unopinionated.contains(tier),
          isFalse,
          reason:
              'ISSUES (9.1): at ${pixels.toStringAsFixed(1)}px an hour the ruler '
              'landed on $tier, a rung the lens holds no opinion about.',
        );
      }
    }
  });

  test('the named pair holds over a band the preference setting states', () {
    final major = scene.setting('intimate.preferMajor');
    final minor = scene.setting('intimate.preferMinor');
    final held = [
      for (final pixels in scales())
        if (painter.rung(pixels).major == major && painter.rung(pixels).minor == minor) pixels,
    ];
    expect(held, isNotEmpty, reason: 'the pair the lens names is reachable at all');
    // One sample step of slack, and no more: the first and last held sample sit
    // inside the real band by up to that much.
    final band = held.last / held.first * sampleStep;
    expect(
      band,
      greaterThanOrEqualTo(ladderPixels(scene.tunable, 'rule.preference')),
      reason:
          'ISSUES (9.1): the lens clings to $major / $minor over a band of only '
          '${band.toStringAsFixed(2)}x in pixels-per-hour, which is geometry '
          'deciding rather than the lens holding an opinion.',
    );
  });

  test('every tier the ruler lands on is still two-tier and whole', () {
    // The 8.28 law does not lapse because the lens gained an opinion.
    for (final pixels in scales()) {
      final rung = painter.rung(pixels);
      expect(rung.major > rung.minor, isTrue, reason: 'flat at $pixels');
      expect((rung.major % rung.minor).isZero, isTrue, reason: 'not whole minors at $pixels');
    }
  });
}
