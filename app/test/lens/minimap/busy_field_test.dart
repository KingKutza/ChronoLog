// THE MINIMAP MAPS BUSYNESS, AND BUSYNESS IS AUTHORED (ISSUES 9.2, two reports).
//
// "The important zone is filling the minimap; the goal for the minimap was to
// map busyness, and the event in question is anti-busy." And, found on the
// way: the field reads AUTHORED facts only, so no series occurrence contributes
// -- every recurring meeting is invisible to the minimap. The rules:
//
//   The field accumulates the same windowed projection the lenses read,
//   virtual occurrences included. Busyness is a frame/object handling composed
//   through the rings like weight (`b * 0` on a zone bundle by default), and
//   the minimap's per-fact formula is a settings key, not a literal.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/core/projection.dart';
import 'package:chronolog/lens/minimap/field.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/staple_world.dart';
import '../painters/grid_scene.dart';

final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

void main() {
  // ignore: avoid_print
  print('BUSY FIELD RUN SEED: $runSeed  (set CHRONOLOG_SEED=$runSeed to reproduce)');
  final random = Random(runSeed);

  test('series occurrences contribute to the field', () {
    final world = World();
    final startDay = 1 + random.nextInt(10);
    world.pattern(rrule: const {'FREQ': 'DAILY'}, templateAt: civil(2026, 9, startDay, 9));
    final engine = ProjectionEngine(world.document);
    final range = (start: civilDays(2026, 9, startDay), end: civilDays(2026, 9, startDay + 14));
    final field = accumulate(engine, Projection.of(const ['calendar:work']), range, allTunables);
    final busyBins = field.magnitudes.where((magnitude) => magnitude > 0).length;
    expect(
      busyBins,
      greaterThanOrEqualTo(10),
      reason:
          'ISSUES 9.2: a daily series over two weeks lit $busyBins bin(s). `accumulate` reads '
          '`explicitFacts` -- authored facts only -- so every occurrence is invisible. Read the '
          'windowed projection the lenses read.',
    );
  });

  test('busyness is an authored handling composed through the rings', () {
    // WORK ITEM (ISSUES 9.2): the per-fact magnitude is the literal
    // `(1 + staples + duration) * weight` in field.dart, and no `display.busy`
    // handling exists on frames or objects. When it does, this test authors
    // `b * 0` on a frame, places a heavy multi-day member in it, and asserts the
    // member adds nothing to any bin -- while the same member outside the frame
    // does; and `minimap.busy` is the settings key the default formula lives in.
    fail(
      'ISSUES 9.2: busyness is a literal formula and no frame can say "anti-busy". Make '
      '`display.busy` a ring-composed handling and `minimap.busy` a settings key, then '
      'assert a `b * 0` frame contributes nothing here.',
    );
  });
}
