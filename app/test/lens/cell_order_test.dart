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

import 'dart:ui';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/object_kinds.dart';
import 'package:chronolog/lens/display_weight.dart';
import 'package:chronolog/lens/painters/month_grid.dart';
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

  // PIPS GROUP BY SIGIL, CLOCK ORDER WITHIN THE GROUP, ROWS NOT A COLUMN
  // (ISSUES 9.2, Don's ruling on the pips).
  //
  // "Grouped by sigil. They are already a sigil with no label, so keep them that
  // way — just put the diamonds with the diamonds and the circles with the
  // circles, and fill the space a bit better by making rows, not just one
  // vertical column." So the grouping key is the MARK ITSELF: a pip's sigil is
  // already derived from what the object is, so grouping by it groups by that
  // without the cell inventing a category. Two consequences the entry states:
  // the sort is by sigil identity and clock order holds INSIDE a group (weight
  // still admits, per the 9.1 ruling above), and the flow is a WRAPPED GRID
  // rather than a column. Labels stay off. The order BETWEEN groups is not
  // ruled and is not asserted.
  //
  // The sigil is read through `markSpecFor`, the painter's own derivation, so
  // this asserts grouping by what the cell draws and never by a trait string.
  // Kinds alternate by the hour by construction, so a clock-ordered flow is
  // guaranteed to interleave sigils and cannot pass by accident.
  for (final seed in seeds(5)) {
    testWidgets('a cell of pips puts each sigil together, in clock order within (seed $seed)', (
      tester,
    ) async {
      final random = Random(seed);
      final scene = Scene()..calendar(frameId);
      final day = 4 + random.nextInt(20);
      final kinds = ['event', 'todo', 'note'];
      final firstHour = 5 + random.nextInt(4);
      final count = 9 + random.nextInt(4);
      for (var index = 0; index < count; index += 1) {
        final kind = kinds[index % kinds.length];
        final placement = scene.place(
          frameId,
          civil(2026, 9, day, firstHour + index),
          title: '$kind at ${firstHour + index}',
        );
        final object = scene.document.relations[placement]!.event!;
        scene.document = scene.document.put(
          'events',
          object,
          scene.document.events[object]!.copyWith(traits: objectKinds[kind]!.traits),
        );
      }

      // Narrow enough that no cell has room for a name: every mark is a pip.
      final lens = sceneOf(
        scene.document,
        const [frameId],
        focus: civilDays(2026, 9, day),
        now: civilDays(2026, 9, day),
        size: const Size(300, 720),
      );
      final painter = TacticalPainter(lens);
      expect(painter.cellWidth, lessThan(lens.px('grid.nameAt')));
      render(painter, lens.size);

      final drawn = [
        for (final hit in painter.hits)
          if (hit.fact.day >= civilDays(2026, 9, day) &&
              hit.fact.day < civilDays(2026, 9, day) + Rational.one)
            hit,
      ];
      expect(drawn.length, greaterThan(kinds.length), reason: 'the cell drew the seeded pips');
      final sigils = [
        for (final hit in drawn)
          markSpecFor(
            lens,
            painter.law,
            hit.fact,
            factDisplayWeight(lens, hit.fact, keyPrefix: 'tactical'),
            const Color(0xFF000000),
          ).sigil,
      ];
      expect(sigils.toSet().length, greaterThan(1), reason: 'the premise: more than one sigil in the cell');

      // Every sigil is ONE contiguous run.
      var runs = 1;
      for (var index = 1; index < sigils.length; index += 1) {
        if (sigils[index] != sigils[index - 1]) runs += 1;
      }
      expect(
        runs,
        sigils.toSet().length,
        reason:
            'ISSUES (9.2, pips): the diamonds are not with the diamonds. Draw order by sigil: '
            '$sigils — ${sigils.toSet().length} sigils drawn in $runs runs.',
      );

      // Inside a run the clock runs forward (the sheet's authored draw order).
      for (var index = 1; index < drawn.length; index += 1) {
        if (sigils[index] != sigils[index - 1]) continue;
        expect(
          drawn[index].fact.day.compareTo(drawn[index - 1].fact.day) * painter.drawOrder,
          greaterThanOrEqualTo(0),
          reason: 'ISSUES (9.2, pips): within the ${sigils[index]} group the clock ran backwards',
        );
      }

      // Rows, not a column: the pips flow across the cell.
      expect(
        drawn.map((hit) => hit.bounds.left).toSet().length,
        greaterThan(1),
        reason: 'ISSUES (9.2, pips): every pip sits at one x — a vertical column, not rows',
      );
      // And no label: a pip's footprint is a pip, never a chip row.
      final pip = lens.px('grid.pipSize');
      for (final hit in drawn) {
        expect(hit.bounds.width, closeTo(pip, 1e-9), reason: 'a pip shows no name and claims no row');
      }
    });
  }
}
