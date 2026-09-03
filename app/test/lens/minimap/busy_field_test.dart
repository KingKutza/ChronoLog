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
//
// Don: "I don't know specifically how to fix that in a code / data-model way
// that is consistent across all cases." The consistent way is the one weight
// already takes: `display.busy` is a one-math term over `b`, the incoming
// busyness, composed ring by ring exactly as `display.weight` is over `w`, so an
// Out-of-Office frame authors `b * 0` and every member inherits it by the same
// walk that gives it its colour and weight. "No special case anywhere:
// 'anti-busy' is a formula somebody wrote on a frame, and the minimap reads the
// graph." The key `minimap.busy` holds the shipped per-fact formula.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
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
    // A heavy multi-day member of a frame that says `b * 0` adds nothing to any
    // bin; the same member outside that frame lights the bins it spans. And the
    // per-fact formula lives in a settings key, never in the painter.
    final settings = chronologSettings();
    expect(
      settings.expressionOf('minimap.busy'),
      isNotEmpty,
      reason:
          'ISSUES 9.2: the per-fact magnitude is the literal `(1 + staples + duration) * weight` '
          'in field.dart. Lens numbers are settings: `minimap.busy` holds the shipped formula.',
    );
    final days = 3 + random.nextInt(4);
    final startDay = 5 + random.nextInt(10);
    World build({required bool antiBusy}) {
      final world = World();
      world.document = world.document.put(
        'frames',
        'group:ooo',
        const Frame(
          id: 'group:ooo',
          title: 'Out of office',
          traits: ['set', 'group'],
          extra: {
            'display': {'busy': 'b * 0', 'zone': true},
          },
        ),
      );
      final member = world.object(
        duration: '${days * 24 * 60}',
        placedAt: civil(2026, 9, startDay, 0),
      );
      if (antiBusy) {
        world.staple(ends: [ObjectEnd(member), StapleEnd.frame('group:ooo')]);
      }
      return world;
    }

    final range = (start: civilDays(2026, 9, 1), end: civilDays(2026, 9, 30));
    MinimapField fieldOf(World world) => accumulate(
      ProjectionEngine(world.document),
      Projection.of(const ['calendar:work']),
      range,
      settings.tunable,
    );
    final plain = fieldOf(build(antiBusy: false));
    expect(
      plain.magnitudes.any((magnitude) => magnitude > 0),
      isTrue,
      reason: 'a $days-day member outside the frame lights the bins it spans',
    );
    final quiet = fieldOf(build(antiBusy: true));
    expect(
      quiet.magnitudes.every((magnitude) => magnitude == 0),
      isTrue,
      reason:
          'ISSUES 9.2: the same member inside a frame that says `b * 0` still lit '
          '${quiet.magnitudes.where((m) => m > 0).length} bin(s). "The important zone is filling '
          'the minimap" -- busyness is a ring-composed handling, and this frame says none.',
    );
  });
}
