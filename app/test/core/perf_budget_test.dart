// USABLE AT 500 CALENDARS (ISSUES 9.2, Strategic lag and the unusable minimap).
//
// After importing US Holidays and Work: "Strategic lags when opening", "minimap
// drag is so slow as to be unusable", "leaving Strategic is also a wait".
// Verified: one full projection query PER DAY per paint, run synchronously in
// the pointer handler. The rule:
//
//   Paint budgets are settings. A seeded document of 5,000 events, 200 series
//   and 50 frames paints Strategic within `perf.paintMillis`, and a lens paint
//   asks the engine for its window ONCE, bucketing afterwards.
//
// Generative: seeded placements and rules, fresh each run.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/lens/painters/strategic.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/staple_world.dart';
import '../lens/painters/grid_scene.dart';

final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

void main() {
  // ignore: avoid_print
  print('PERF BUDGET RUN SEED: $runSeed  (set CHRONOLOG_SEED=$runSeed to reproduce)');
  final random = Random(runSeed);

  test('Strategic first paint over a massive calendar stays within the settings budget', () {
    final settings = chronologSettings();
    final budget = settings.expressionOf('perf.paintMillis');
    if (budget.isEmpty) {
      fail(
        'ISSUES 9.2: no `perf.paintMillis` setting exists. Performance budgets are settings '
        'keys like every other tunable; add it (and `perf.frameMillis`), then this test times '
        'the paint against it.',
      );
    }
    final world = World();
    for (var i = 0; i < 5000; i += 1) {
      world.object(
        duration: '${15 + random.nextInt(90)}',
        placedAt: civil(2026, 1 + random.nextInt(12), 1 + random.nextInt(28), random.nextInt(24)),
      );
    }
    for (var i = 0; i < 200; i += 1) {
      world.pattern(
        rrule: {'FREQ': random.nextBool() ? 'WEEKLY' : 'DAILY'},
        templateAt: civil(2026, 1 + random.nextInt(12), 1 + random.nextInt(28), 9),
      );
    }
    for (var i = 0; i < 50; i += 1) {
      world.document = world.document.put(
        'frames',
        'group:$i',
        world.document.frames.values.first.copyWith(id: 'group:$i', title: 'Group $i'),
      );
    }
    final lens = sceneOf(
      world.document,
      const ['calendar:work'],
      size: const Size(1600, 1000),
      focus: civilDays(2026, 6, 15),
    );
    final painter = StrategicPainter(lens);
    final watch = Stopwatch()..start();
    render(painter, const Size(1600, 1000));
    watch.stop();
    expect(
      watch.elapsedMilliseconds,
      lessThanOrEqualTo(settings.value('perf.paintMillis').toDouble()),
      reason:
          'ISSUES 9.2: Strategic asked the engine once per DAY of the season. One windowed '
          'query per paint, bucketed by day afterwards.',
    );
  });
}
