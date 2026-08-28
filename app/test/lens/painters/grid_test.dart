// Properties of the four grid lenses, over seeded random documents and over
// laws that are not ours: an 8x8x8 calendar, a 23-hour day, a ladder of pen
// strokes with no clock at all.
//
// Nothing here pins a count. Every claim is a property a ruling states.

import 'dart:math';
import 'dart:ui';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/lens/capacity.dart';
import 'package:chronolog/lens/lens_painter.dart';
import 'package:chronolog/lens/painters/intimate.dart';
import 'package:chronolog/lens/painters/month_grid.dart';
import 'package:chronolog/lens/painters/strategic.dart';
import 'package:chronolog/lens/painters/tactical.dart';
import 'package:chronolog/lens/painters/wall.dart';
import 'package:chronolog/session/lens_catalog.dart';
import 'package:chronolog/lens/view_tile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/corpus.dart';
import '../../helpers/projection_scene.dart';
import 'grid_scene.dart';

const Size surface = Size(960, 720);

/// A calendar with randomly placed objects around the focus, some of them ToDos,
/// some of them multi-day, from a named seed.
Scene randomWorld(int seed, {int count = 40, int? hoursPerDay}) {
  final random = Random(seed);
  final world = Scene()..calendar('calendar:a', hoursPerDay: hoursPerDay);
  world.group('frame:work', const []);
  for (var index = 0; index < count; index += 1) {
    final object = world.object(title: 'Object $index', duration: '${15 + random.nextInt(600)}');
    if (random.nextBool()) {
      world.document = world.document.put(
        'events',
        object,
        world.document.events[object]!.copyWith(traits: const ['event', 'task', 'todo']),
      );
    }
    world.place(
      'calendar:a',
      civil(2026, 7 + random.nextInt(3), 1 + random.nextInt(28), random.nextInt(24)),
      event: object,
    );
    if (random.nextBool()) world.join('frame:work', object);
  }
  return world;
}

List<DayGridPainter Function(LensScene)> get gridLenses => [
  TacticalPainter.new,
  StrategicPainter.new,
  WallPainter.new,
];

void main() {
  test('every registered grid lens is a lens the catalog declares', () {
    registerGridLenses();
    expect(lensPainters.keys, isNotEmpty);
    for (final id in lensPainters.keys) {
      expect(lensCatalog.containsKey(id), isTrue, reason: '$id is not in the catalog');
    }
  });

  test('a grid reads a day back exactly where it drew it', () {
    for (final seed in seeds(4)) {
      final scene = sceneOf(randomWorld(seed).document, const ['calendar:a']);
      for (final build in gridLenses) {
        final painter = build(scene);
        render(painter, surface);
        for (final row in painter.rows) {
          for (final day in row.days) {
            if (day == null) continue;
            final start = Rational(day) * painter.law.dayDays;
            final point = painter.project(start);
            expect(point, isNotNull);
            // A grid counts whole days, so the eye and the drop agree to one.
            expect(painter.unproject(point! + const Offset(1, 1)), start);
          }
        }
      }
    }
  });

  test('a grid never draws more marks than its cells hold', () {
    for (final seed in seeds(2)) {
      final scene = sceneOf(randomWorld(seed, count: 220).document, const ['calendar:a']);
      for (final build in gridLenses) {
        final painter = build(scene);
        render(painter, surface);
        final cells = painter.rows.fold<int>(
          0,
          (total, row) => total + row.days.where((day) => day != null).length,
        );
        final perCell = capacityOf(
          painter.cellWidth,
          surface.height / painter.rows.length,
          allTunables,
          widthKey: 'grid.chipWidth',
          heightKey: 'grid.chipHeight',
          depthKey: 'grid.chipDepth',
        );
        expect(painter.hits.length, lessThanOrEqualTo(cells * perCell.marks));
        for (final hit in painter.hits) {
          expect(hit.bounds.left, greaterThanOrEqualTo(0));
        }
      }
    }
  });

  test('a month sheet has one column per base unit the LAW says a month holds', () {
    final world = Scene()
      ..frame('frame:eight', const ['set', 'calendar'], const {'coordinate': eightLaw});
    world.place('frame:eight', const {
      'levels': [
        {'level': 'year', 'value': '12'},
        {'level': 'month', 'value': '3'},
        {'level': 'day', 'value': '9'},
      ],
    }, title: 'A day in Na');
    final scene = sceneOf(world.document, const ['frame:eight'], view: const {'months': 3});
    final strategic = StrategicPainter(scene);
    render(strategic, surface);
    expect(strategic.rows, isNotEmpty);
    for (final row in strategic.rows) {
      // Sixty-four, because the law says sixty-four -- never a 31 borrowed
      // from ours, and never a Gregorian month name.
      expect(row.days.length, 64);
      expect(row.label, isNot(contains('January')));
    }
  });

  test('a Gregorian sheet pads its short months rather than reflowing them', () {
    final scene = sceneOf(
      randomWorld(specSeed).document,
      const ['calendar:a'],
      view: const {'months': 3},
    );
    final strategic = StrategicPainter(scene);
    render(strategic, surface);
    final widths = {for (final row in strategic.rows) row.days.length};
    expect(widths.length, 1, reason: 'every row of a sheet has the same column count');
    final real = strategic.rows.map((row) => row.days.where((day) => day != null).length).toSet();
    expect(real.length, greaterThan(1), reason: 'short months pad rather than reflow');
  });

  test('a wall sheet leads with the authored first weekday and pads before it', () {
    final scene = sceneOf(
      randomWorld(specSeed).document,
      const ['calendar:a'],
      view: const {'months': 1},
    );
    final wall = WallPainter(scene);
    render(wall, surface);
    final names = scene.law.weekdayNames()!;
    expect(wall.headings.length, names.length);
    expect(wall.headings.first.cycle, scene.setting('wall.firstWeekday').round().toInt());
    final first = wall.rows.first.days;
    expect(first.length, names.length);
    // The lead pad is real absence: null cells, never day zero.
    expect(first.where((day) => day != null), isNotEmpty);
  });

  test('a law with no month level is refused in its own words, not invented', () {
    final world = Scene()
      ..frame('frame:strokes', const ['set', 'calendar'], const {'coordinate': inventedLaw});
    world.place('frame:strokes', stroke(4, 2), title: 'A stroke');
    final scene = sceneOf(world.document, const ['frame:strokes']);
    for (final build in [StrategicPainter.new, WallPainter.new]) {
      final painter = build(scene);
      render(painter, surface);
      expect(painter.refusals, isNotEmpty);
      expect(painter.rows, isEmpty);
    }
  });

  test('a law with no clock mapping paints, and marks no now', () {
    final world = Scene()
      ..frame('frame:strokes', const ['set', 'calendar'], const {'coordinate': inventedLaw});
    world.place('frame:strokes', stroke(4, 2), title: 'A stroke');
    final scene = sceneOf(world.document, const ['frame:strokes']);
    expect(scene.law.mapsToClock(), isFalse);
    final intimate = IntimatePainter(scene);
    render(intimate, surface);
    expect(intimate.nowAt, isNull);
  });

  test('Intimate reads a time back within one grain, on a 23-hour day too', () {
    for (final hours in [null, 23]) {
      final scene = sceneOf(randomWorld(specSeed, hoursPerDay: hours).document, const [
        'calendar:a',
      ]);
      final painter = IntimatePainter(scene);
      render(painter, surface);
      final grain = painter.law.daysOfMinute(scene.setting('intimate.grain'));
      for (var step = 0; step < 12; step += 1) {
        final at = scene.focusDays + painter.law.daysOfMinute(Rational.fromInt(step * 37));
        final point = painter.project(at)!;
        final back = painter.unproject(Offset(point.dx + 1, point.dy))!;
        expect((back - at).abs() <= grain, isTrue, reason: '$back vs $at');
      }
    }
  });

  test('Intimate paints N day columns, and reads a point in each one back', () {
    final scene = sceneOf(
      randomWorld(specSeed, count: 40).document,
      const ['calendar:a'],
      view: const {'back': 1, 'forward': 2},
    );
    final painter = IntimatePainter(scene);
    render(painter, surface);
    final rail = scene.px('intimate.rail');
    final width = (surface.width - rail) / 4;
    for (var column = 0; column < 4; column += 1) {
      final at = Offset(rail + width * (column + Rational.fromInt(1, 2).toDouble()), 300);
      final days = painter.unproject(at)!;
      final back = painter.projectAll(days);
      expect(back, isNotEmpty, reason: 'a point in a column names a time that column shows');
      expect(
        back.any((point) => (point.dx - (rail + width * column)).abs() < 2),
        isTrue,
        reason: 'the time reads back in the column the point was in',
      );
    }
  });

  test('one time, every position: an event shows in every column showing its time', () {
    // Don, 2026-08-28: "if I have it zoomed and scrolled so the same time is
    // visible in two spots, an event can only appear at one of those spots".
    // Zoomed out far enough, a column's window runs past a whole day, so
    // neighbouring columns overlap in time -- and the mark belongs to both.
    final world = Scene()..calendar('calendar:a');
    final object = world.object(title: 'Twice over', duration: '90');
    world.place('calendar:a', civil(2026, 8, 18, 9), event: object);
    final scene = sceneOf(
      world.document,
      const ['calendar:a'],
      view: const {'back': 1, 'forward': 1, 'hourPixels': 8},
    );
    final painter = IntimatePainter(scene);
    render(painter, surface);
    final places = [
      for (final hit in painter.hits)
        if (hit.fact.event.id == object) hit.bounds.left,
    ];
    expect(
      places.toSet().length,
      greaterThan(1),
      reason: 'the same fact is drawn in every column whose window holds it',
    );
    // Every drawn position hit-tests, and every one of them names the same fact.
    for (final hit in painter.hits.where((hit) => hit.fact.event.id == object)) {
      final found = painter.markAt(hit.bounds.centerLeft + const Offset(2, 0));
      expect(found, isNotNull, reason: 'a painted position is a position you can grab');
      expect(found!.fact.event.id, object);
    }
    final at = painter.unproject(painter.hits.first.bounds.centerLeft + const Offset(2, 0))!;
    expect(painter.projectAll(at).length, greaterThan(1), reason: 'one time, many positions');
  });

  test('the rule ladder runs both ways: rules stay near their target spacing', () {
    // Don, 2026-08-28: "as I zoom in so that an hour or a minute fills the
    // screen, I don't get new more granular lines". One function of pixels per
    // hour, run in BOTH directions.
    for (final hours in [null, 23]) {
      for (final pixels in [4, 12, 42, 160, 700, 4000]) {
        final scene = sceneOf(
          randomWorld(specSeed, count: 4, hoursPerDay: hours).document,
          const ['calendar:a'],
          view: {'hourPixels': pixels},
        );
        final painter = IntimatePainter(scene);
        render(painter, surface);
        final target = scene.px('intimate.ruleSpacing');
        final step = painter.ruleHours(pixels.toDouble());
        final spacing = step.toDouble() * pixels;
        expect(
          spacing >= target / 2 && spacing <= target * 2,
          isTrue,
          reason: 'at $pixels px an hour the rules sat $spacing apart, not near $target',
        );
      }
    }
  });

  test('Intimate orders every lane in time', () {
    final scene = sceneOf(randomWorld(specSeed, count: 90).document, const ['calendar:a']);
    final painter = IntimatePainter(scene);
    render(painter, surface);
    final byLane = <double, List<Rect>>{};
    for (final hit in painter.hits) {
      (byLane[hit.bounds.left] ??= []).add(hit.bounds);
    }
    expect(byLane, isNotEmpty);
    for (final lane in byLane.values) {
      final tops = [for (final box in lane) box.top]..sort();
      expect([for (final box in lane) box.top], tops);
    }
  });

  test('a mark is grabbed by its leading edge, so a create-drag passes through', () {
    final scene = sceneOf(randomWorld(specSeed, count: 400).document, const ['calendar:a']);
    final painter = IntimatePainter(scene);
    render(painter, surface);
    final wide = painter.hits.where((hit) => hit.bounds.width > 40).toList();
    expect(wide, isNotEmpty);
    for (final hit in wide.take(4)) {
      expect(
        hit.shape!.contains(hit.bounds.centerLeft + const Offset(2, 0)),
        isTrue,
        reason: 'the leading edge moves it',
      );
      expect(
        hit.shape!.contains(hit.bounds.center),
        isFalse,
        reason: 'the body creates through it',
      );
    }
  });
}
