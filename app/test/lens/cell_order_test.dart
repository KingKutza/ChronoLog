// WEIGHT ADMITS, THE CLOCK ORDERS (ISSUES 9.1, Don's morning test).
//
// "On Tactical the meetings are out of order… it is just lacking order." The
// day-cell painter ranks a cell's facts by display weight to decide which chips
// survive the capacity budget — and then draws them in that same ranking. The
// rule this file states: within one day cell, whatever the budget admitted is
// DRAWN in time order. The budget decides who fits; the clock decides where
// they stand.
//
// Generative: seeded hours and a seeded boosted meeting, never a pinned list.
// The painter's own hit list is built during paint in draw order, so the claim
// reads geometry the program itself keeps, not pixels.

import 'dart:math';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/lens/painters/tactical.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import '../helpers/projection_scene.dart';
import 'painters/grid_scene.dart';

const String frameId = 'calendar:a';

void main() {
  for (final seed in seeds(5)) {
    testWidgets('a day cell draws its admitted facts in time order (seed $seed)', (tester) async {
      final random = Random(seed);
      final scene = Scene()..calendar(frameId);
      // A handful of meetings on one day, at distinct seeded hours…
      final count = 3 + random.nextInt(3);
      final hours = <int>[];
      while (hours.length < count) {
        final hour = 6 + random.nextInt(12);
        if (!hours.contains(hour)) hours.add(hour);
      }
      final day = 4 + random.nextInt(20);
      for (final hour in hours) {
        scene.place(frameId, civil(2026, 9, day, hour), title: 'Meeting at $hour');
      }
      // …one of the LATER ones boosted hard, the way a group boost really does.
      final latest = hours.reduce(max);
      final boosted = scene.place(frameId, civil(2026, 9, day, latest, 30), title: 'Boosted');
      final boostedEvent = '${scene.document.relations[boosted]!.event}';
      scene.group('frame:loud', [boostedEvent], weight: 'w * 9');

      final lens = sceneOf(
        scene.document,
        const [frameId],
        focus: civilDays(2026, 9, day),
        now: civilDays(2026, 9, day),
      );
      final painter = TacticalPainter(lens);
      render(painter, lens.size);

      final drawn = [
        for (final hit in painter.hits)
          if (hit.fact.day >= civilDays(2026, 9, day) &&
              hit.fact.day < civilDays(2026, 9, day) + Rational.one)
            hit.fact.day,
      ];
      expect(drawn.length, greaterThan(2), reason: 'the cell drew the seeded meetings');
      final sorted = [...drawn]..sort();
      expect(
        drawn,
        sorted,
        reason:
            'ISSUES (9.1): the cell draws in weight order — the boosted meeting jumps '
            'the queue — where the admitted chips must stand in time order.',
      );
    });
  }
}
