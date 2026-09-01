// Properties of the four grid lenses, over seeded random documents and over
// laws that are not ours: an 8x8x8 calendar, a 23-hour day, a ladder of pen
// strokes with no clock at all.
//
// Nothing here pins a count. Every claim is a property a ruling states.

import 'dart:math';
import 'dart:ui';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/lens/capacity.dart';
import 'package:chronolog/lens/ladder.dart';
import 'package:chronolog/lens/law_context.dart';
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

  test('the rule ladder runs both ways and is TWO-TIER at every rung', () {
    // Don, 2026-08-28: "as I zoom in so that an hour or a minute fills the
    // screen, I don't get new more granular lines". Extended 8.31: every rung
    // pairs a major with a minor, and the major is a whole number of minors, so
    // the surface never reads as one flat tone. One function of pixels per hour,
    // run in BOTH directions, over a law that is not ours as well as one that is.
    final minorTarget = ladderPixels(allTunables, 'rule.minorSpacing');
    final majorTarget = ladderPixels(allTunables, 'rule.majorSpacing');
    for (final hours in [null, 23]) {
      for (final pixels in [1, 4, 12, 42, 160, 700, 4000, 90000]) {
        final scene = sceneOf(
          randomWorld(specSeed, count: 4, hoursPerDay: hours).document,
          const ['calendar:a'],
          view: {'hourPixels': pixels},
        );
        final painter = IntimatePainter(scene);
        render(painter, surface);
        final rung = painter.rung(pixels.toDouble());
        expect(
          rung.major > rung.minor,
          isTrue,
          reason: 'at $pixels px an hour the rung was flat',
        );
        expect(
          (rung.major % rung.minor).isZero,
          isTrue,
          reason: 'at $pixels px an hour ${rung.major} is not whole minors of ${rung.minor}',
        );
        for (final pair in [(rung.minor, minorTarget), (rung.major, majorTarget)]) {
          expect(
            pair.$1.toDouble() * pixels >= pair.$2 - 1e-9,
            isTrue,
            reason: 'at $pixels px an hour a tier sat '
                '${pair.$1.toDouble() * pixels}px apart, under ${pair.$2}',
          );
        }
      }
    }
  });

  test('a day grid pans in whole cells and promises nothing it cannot keep', () {
    // The 8.31 pan class, audited on the grid family: a cell is a whole day, so
    // the window cannot hold a third of one. Nothing is shown sliding, the
    // commit is the whole motion, and the gesture is not dead.
    final document = randomWorld(specSeed, count: 40).document;
    for (final build in [TacticalPainter.new, StrategicPainter.new, WallPainter.new]) {
      final painter = build(sceneOf(document, const ['calendar:a']));
      render(painter, surface);
      expect(painter.bleed, Offset.zero, reason: 'a grid previews nothing');
      for (final shift in [const Offset(0, -120), const Offset(0, 200)]) {
        final landing = painter.panLanding(shift);
        expect(landing.shown, Offset.zero);
        expect(landing.days.isZero, isFalse, reason: 'a pan of $shift moved nothing at all');
      }
    }
  });

  test('at rest the minors are the lens own increment and the majors the law hour', () {
    // Don, 8.31: "at rest: minors at the authored increment, e.g. the set 15m,
    // majors at the hour." Both sides derived and neither pinned -- the
    // increment is the grain this lens declares, the hour is the law's own.
    for (final hours in [null, 23]) {
      final scene = sceneOf(
        randomWorld(specSeed, count: 4, hoursPerDay: hours).document,
        const ['calendar:a'],
      );
      final painter = IntimatePainter(scene);
      render(painter, surface);
      final law = LawContext(scene.law);
      expect(painter.railRung.minor, law.daysOfMinute(scene.setting('intimate.grain')));
      expect(painter.railRung.major, law.daysOfMinute(law.minutesPerHour));
    }
  });

  test('a bleeding surface paints PAST its own edge, so a pan slides content in', () {
    // The other half of the 8.31 pan report: "when I drag, the white space moves
    // on the edge vs a drag preview of the new position." A transform can only
    // slide in pixels that exist, so the rail is drawn past the viewport by the
    // bleed -- and a mark that sits in that margin is drawn, hit-listed and
    // ready to arrive.
    const hourPixels = 60;
    final world = Scene()..calendar('calendar:a');
    // One hour past the bottom edge, which the bleed still covers.
    final past = (surface.height / 2 / hourPixels).ceil() + 1;
    world.place('calendar:a', civil(2026, 8, 18, past), title: 'Just below');
    final scene = sceneOf(
      world.document,
      const ['calendar:a'],
      view: {'hourPixels': hourPixels},
      size: surface,
    );
    final painter = IntimatePainter(scene);
    render(painter, surface);
    expect(painter.bleed.dy > 0, isTrue, reason: 'Intimate bleeds down its rail');
    expect(
      past * hourPixels < surface.height / 2 + painter.bleed.dy,
      isTrue,
      reason: 'the spec placed its mark outside the bled margin',
    );
    final below = painter.hits.where((hit) => hit.bounds.top > surface.height);
    expect(below, isNotEmpty, reason: 'nothing was painted past the edge to slide in');
  });

  test('a pan commits exactly the pixels it took: the repaint moves fidelity, never position', () {
    // Don, 2026-08-31: "I drag up and right, and then it snaps back to basically
    // the same position when I release." The painter answers with the focus
    // movement, what the eye may be shown, and WHICH PIXELS THE MOVEMENT TOOK;
    // the law is that the last two agree with the first -- painting again with
    // the committed focus puts the watched time exactly `taken` from where it
    // was, and whatever the commit did not take stays shown (ISSUES 9.1, the
    // Intimate ratchet: sideways this surface can only commit whole columns, so
    // the slide is continuous and the commit is stepped, and the remainder is
    // carried rather than dropped).
    final random = Random(specSeed);
    final document = randomWorld(specSeed, count: 40).document;
    var checked = 0;
    for (var index = 0; index < 16; index += 1) {
      final scene = sceneOf(document, const ['calendar:a']);
      final before = IntimatePainter(scene);
      render(before, surface);
      final shift = Offset(random.nextDouble() * 500 - 250, random.nextDouble() * 200 - 100);
      final landing = before.panLanding(shift);
      final watched = before.unproject(Offset(surface.width / 2, surface.height / 2));
      expect(watched, isNotNull);
      final was = before.projectAll(watched!);
      final after = IntimatePainter(scene.copyWith(focusDays: scene.focusDays + landing.days));
      render(after, surface);
      final now = after.projectAll(watched);
      expect(was, isNotEmpty);
      expect(now, isNotEmpty, reason: 'a pan of $shift lost the time it was panning');
      expect(
        now.any((point) => was.any((from) => (point - (from + landing.taken)).distance < 1)),
        isTrue,
        reason: 'a pan of $shift took ${landing.taken} and settled at '
            '${now.first - was.first}',
      );
      checked += 1;
    }
    expect(checked, 16);
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

  test('the whole block grabs, and the whole block is what a click means', () {
    // ISSUES 9.1, Don: "click on an event or todo and drag it, the event does
    // not move -- it drags to create a new event." The nine-pixel leading strip
    // that used to be the only grab region is gone: the common gesture gets the
    // common verb, a drag anywhere on a block moves it, and creating THROUGH an
    // occupied span is what wears alt (which the one pointer table already
    // answers). A mark that declares no grab is grabbed wherever it is hit.
    final scene = sceneOf(randomWorld(specSeed, count: 400).document, const ['calendar:a']);
    final painter = IntimatePainter(scene);
    render(painter, surface);
    final wide = painter.hits.where((hit) => hit.bounds.width > 40).toList();
    expect(wide, isNotEmpty);
    for (final hit in wide.take(4)) {
      expect(hit.grab, isNull, reason: 'no region of a block is closed to a drag');
      expect(
        painter.grabAt(hit.bounds.center),
        isNotNull,
        reason: 'the body moves it',
      );
      expect(
        hit.shape!.contains(hit.bounds.center),
        isTrue,
        reason: 'the body is what a click means',
      );
      expect(painter.markAt(hit.bounds.center), isNotNull);
    }
  });
}
