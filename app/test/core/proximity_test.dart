// PROXIMITY IS A BOUND VALUE, NOT A KNOB.
//
// The lens side wants near things loud and far things quiet, and the standing
// law says every tunable is a settings key whose value is a one-math expression
// -- so what the engine owes is not a proximity FEATURE but one more name a
// weight formula may read: signed days from the instant the projector is looking
// from to the object's home. Positive ahead, negative behind, zero while the
// object is happening. "Next Tuesday" and "last Tuesday" are different claims
// about attention, and a formula that cannot tell them apart has to be written
// twice.
//
// The property: the binding is arithmetic and nothing else. A formula that never
// names it is unaffected, one that does reads the signed gap, and the sign is the
// direction of time.

import 'dart:math';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/falloff.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/weight.dart';
import 'package:test/test.dart';

import '../helpers/projection_scene.dart';
import 'corpus.dart';

const String frameId = 'calendar:a';

Rational civilDays(int year, int month, int day) =>
    Rational(daysFromCivil(BigInt.from(year), month, day));

void main() {
  test('the name a formula reads is stated once, for every caller', () {
    expect(proximityVariable, isNotEmpty);
    expect(proximityVariable, isNot(weightVariable));
  });

  for (final seed in seeds(5)) {
    final random = Random(seed);
    final gap = 1 + random.nextInt(20);

    test('signed distance is the gap WITH its direction (seed $seed)', () {
      final home = (start: Rational.zero, end: Rational.zero);
      final ahead = signedDistanceFromHome(home, -Rational.fromInt(gap));
      final behind = signedDistanceFromHome(home, Rational.fromInt(gap));
      expect(ahead, Rational.fromInt(gap), reason: 'home is ahead of the instant: positive');
      expect(behind, -Rational.fromInt(gap), reason: 'home is behind it: negative');
      expect(signedDistanceFromHome(home, Rational.zero), Rational.zero);
      // The unsigned gap the falloff step reads is this one's magnitude, always,
      // so the two can never disagree about where home is.
      for (final at in [-Rational.fromInt(gap), Rational.zero, Rational.fromInt(gap)]) {
        expect(signedDistanceFromHome(home, at)!.abs(), distanceFromHome(home, at));
      }
      expect(signedDistanceFromHome(null, Rational.zero), isNull);
    });

    test('a formula naming proximity reads the signed gap; one that does not is '
        'unaffected (seed $seed)', () {
      final day = 1 + random.nextInt(8);
      final scene = Scene()..calendar(frameId);
      // Zero-width on purpose: a home with breadth is zero-distance THROUGHOUT
      // itself, so before and after are measured from different edges and the
      // symmetry below would be testing the object's duration, not the sign.
      final object = scene.object(title: 'Standing', duration: '0');
      scene.place(frameId, civil(2026, 9, day, 0), event: object);
      // The frame's own authored math names proximity. Meaning is authored: the
      // engine supplies the value and decides nothing about what it means.
      scene.document = scene.document.put(
        'frames',
        frameId,
        scene.document.frames[frameId]!.withField('display', {
          // Kept gentle on purpose: a ring that would drive the weight negative
          // is refused as a broken knob, and this test is about the BINDING.
          'weight': 'w + $proximityVariable / 100',
        }),
      );

      final engine = ProjectionEngine(scene.document);
      final projection = Projection.of(const [frameId]);
      final start = civilDays(2026, 9, day);
      final fact = engine
          .queryFacts(projection, start: start, end: start + Rational.one)
          .facts
          .single;

      // Looked at from `gap` days before the object: home is ahead, so positive.
      final early = engine.weightOf(fact, projection, at: start - Rational.fromInt(gap));
      // And from `gap` days after it: behind, so negative, and by the same size.
      final late = engine.weightOf(fact, projection, at: start + Rational.fromInt(gap));
      Rational ring(WeightDerivation derivation) =>
          derivation.rings.firstWhere((step) => step.id == frameId).weight;
      expect(
        ring(early) - Rational.one,
        -(ring(late) - Rational.one),
        reason:
            'the two readings differ only in the SIGN of the gap, which is the whole '
            'claim: before and after are not the same distance said twice.',
      );
      expect(ring(early), greaterThan(ring(late)));
    });

    test('a formula that never names proximity is untouched by it (seed $seed)', () {
      final probe = Rational.fromInt(1 + random.nextInt(5));
      expect(
        applyWeightFormula('w * 2', probe, environment: {proximityVariable: Rational.fromInt(gap)}),
        applyWeightFormula('w * 2', probe),
      );
      // And `w` is this function's own contract: an environment cannot redefine
      // it out from under a formula.
      expect(
        applyWeightFormula('w', probe, environment: {weightVariable: Rational.zero}),
        probe,
      );
    });
  }
}
