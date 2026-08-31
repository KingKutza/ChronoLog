// THE MINIMAP HAS TO READ AS A WAVE.
//
// Don, on the first build: "the minimap dust effect looks more like dirt than a
// waveform." The ruling it missed is "an almost animated waveform in dust or
// glitter", and a ruling about how something LOOKS can only be checked by
// looking, so this writes the two shapes the tile actually ships in -- the
// narrow column beside a lens, and a wide band under one -- to goldens.
//
// The field underneath is seeded and hand-built rather than random: a busy
// stretch, one long span, a quiet fortnight and a scattering, which is the shape
// that shows whether the curve is a curve and whether the dust follows it.

import 'dart:math';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/lens/law_context.dart';
import 'package:chronolog/lens/minimap/field.dart';
import 'package:chronolog/lens/minimap/labels.dart';
import 'package:chronolog/lens/minimap/painter.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/corpus.dart';
import '../../helpers/projection_scene.dart';

final Rational august = Rational(daysFromCivil(BigInt.from(2026), 8, 18));

/// A document with somewhere to look at and somewhere to look away from.
Scene busyWorld() {
  final random = Random(specSeed);
  final world = Scene()..calendar('calendar:a');
  // A busy week: several events a day, at hours the seed picks.
  for (var day = 8; day < 15; day += 1) {
    for (var index = 0; index < 2 + random.nextInt(4); index += 1) {
      world.place(
        'calendar:a',
        civil(2026, 8, day, 7 + random.nextInt(12)),
        title: 'Aug $day #$index',
      );
    }
  }
  // One long span across the busy end, then a quiet fortnight, then a scattering.
  world.place(
    'calendar:a',
    civil(2026, 8, 12),
    event: world.object(title: 'Trip', duration: '4', unit: 'day'),
  );
  for (final day in [1, 3, 4, 30]) {
    world.place('calendar:a', civil(2026, 8, day, 9), title: 'Aug $day');
  }
  for (final day in [4, 5, 11]) {
    world.place('calendar:a', civil(2026, 9, day, 14), title: 'Sep $day');
  }
  return world;
}

MinimapPainter wavePainter({String lens = 'tactical', double clock = 9.5}) =>
    painterOver(busyWorld(), (_) {}, clock, lens: lens);

/// Four events in a rough cluster with a quiet fortnight either side: the shape
/// Don was looking at when he asked why he could not simply count them.
MinimapPainter clusterPainter({double clock = 9.5}) => painterOver(
  Scene()..calendar('calendar:a'),
  (world) {
    for (final (day, hour) in [(17, 9), (17, 14), (18, 11), (19, 16)]) {
      world.place('calendar:a', civil(2026, 8, day, hour), title: 'Aug $day at $hour');
    }
  },
  clock,
);

/// TWO EVENTS A DAY, EVERY DAY: a real, sparse calendar -- the document Don
/// opened on 8/31 and got "dots" from. Every neighbourhood here is countable, so
/// this is exactly the shape the old regime drew with no dust at all and a
/// dimmed envelope: a dot matrix.
MinimapPainter sparsePainter({double clock = 9.5}) => painterOver(
  Scene()..calendar('calendar:a'),
  (world) {
    for (var day = 1; day <= 30; day += 1) {
      world.place('calendar:a', civil(2026, 8, day, 9), title: 'Aug $day, morning');
      world.place('calendar:a', civil(2026, 8, day, 15), title: 'Aug $day, afternoon');
    }
  },
  clock,
);

/// One painter over a world the caller fills: the two sparse shapes differ by
/// their facts and nothing else.
MinimapPainter painterOver(
  Scene world,
  void Function(Scene) fill,
  double clock, {
  String lens = 'tactical',
}) {
  fill(world);
  final engine = ProjectionEngine(world.document);
  final span = Rational.fromInt(14);
  final range = slideRange(null, august, span, null);
  return MinimapPainter(
    field: accumulate(engine, Projection.of(['calendar:a']), range, null),
    law: LawContext(engine.lawOf('calendar:a')),
    theme: shipped['paper']!,
    focusDays: august,
    spanDays: span,
    nowDays: august + Rational(BigInt.from(3), BigInt.from(4)),
    granularity: granularityFor(lens),
    clock: clock,
  );
}

/// Paints the whole test view at [size], so a golden is the tile and nothing
/// around it. The view is resized rather than the widget, because a 1280-wide
/// band does not fit the default 800x600 surface.
Future<void> pumpAt(WidgetTester tester, MinimapPainter painter, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: const ValueKey('minimap'),
        child: CustomPaint(painter: painter, size: Size.infinite),
      ),
    ),
  );
}

void main() {
  testWidgets('the narrow column reads as a wave', (tester) async {
    final painter = wavePainter();
    await pumpAt(tester, painter, const Size(96, 720));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('minimap')),
      matchesGoldenFile('goldens/minimap-column.png'),
    );
  });

  testWidgets('the wide band reads as a wave', (tester) async {
    final painter = wavePainter();
    await pumpAt(tester, painter, const Size(1280, 140));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('minimap')),
      matchesGoldenFile('goldens/minimap-band.png'),
    );
  });

  testWidgets('a quiet document is a flat line, not an empty tile', (tester) async {
    final world = Scene()..calendar('calendar:a');
    final engine = ProjectionEngine(world.document);
    final span = Rational.fromInt(14);
    final range = slideRange(null, august, span, null);
    final painter = MinimapPainter(
      field: accumulate(engine, Projection.of(['calendar:a']), range, null),
      law: LawContext(engine.lawOf('calendar:a')),
      theme: shipped['paper']!,
      focusDays: august,
      spanDays: span,
      nowDays: august,
      granularity: granularityFor('tactical'),
    );
    await pumpAt(tester, painter, const Size(96, 720));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('minimap')),
      matchesGoldenFile('goldens/minimap-quiet.png'),
    );
  });

  testWidgets('four events in a cluster are four countable motes', (tester) async {
    const size = Size(96, 720);
    final painter = clusterPainter();
    await pumpAt(tester, painter, size);
    expect(tester.takeException(), isNull);
    // THE COUNT IS ANCHORED: four facts, four marks, and not one mark that is
    // not a fact. That is the whole reason a countable regime exists (Don,
    // 2026-08-31: "if we were bothering to render countable dots why weren't we
    // anchoring their count to anything obvious").
    expect(painter.motesFor(size).length, 4);
    // And the wave is still underneath them: the dust does not stand aside for
    // a count (ruled 2026-08-31, "It was good now it is misrendering").
    expect(painter.grainsFor(size), isNotEmpty);
    await expectLater(
      find.byKey(const ValueKey('minimap')),
      matchesGoldenFile('goldens/minimap-cluster.png'),
    );
  });

  testWidgets('a sparse calendar is the WAVE, in dust, with its counts on it', (tester) async {
    const size = Size(96, 720);
    final painter = sparsePainter();
    await pumpAt(tester, painter, size);
    expect(tester.takeException(), isNull);
    final grains = painter.grainsFor(size);
    expect(
      grains,
      isNotEmpty,
      reason:
          'ISSUES (8.31, night): at one to three events a day every bin is countable, '
          'the dust used to be suppressed there and the envelope dimmed with it — '
          'which left "dots" where the ruled look is the dust wave.',
    );
    // The dust is a BAND, not a line: it stands off the axis, which is the wave
    // being visible at all.
    final axis = size.width / 2;
    final reach = grains.map((grain) => (grain.at.dx - axis).abs()).reduce(max);
    expect(
      reach,
      greaterThan(axis / 4),
      reason: 'the dust hugs the axis, so there is no wave to see',
    );
    // AND NOT A DOTTED LINE. Sixty facts across this stretch cannot be drawn as
    // sixty separable marks -- a mote is its own width of ink and they would
    // land closer together than that -- so at this zoom the facts ARE the wave,
    // and the count comes back when the view is zoomed in far enough to take it.
    final placed = [
      for (var bin = 0; bin < painter.field.bins; bin += 1) painter.field.presentAt(bin),
    ].fold(0, (sum, count) => sum + count);
    expect(placed, greaterThan(50), reason: 'the whole month is in the range');
    expect(
      painter.motesFor(size),
      isEmpty,
      reason:
          'ISSUES (8.31, night): "render countable dots only if their count is '
          'anchored to something obvious" — motes this close together are a dotted '
          'line, not a count.',
    );
    await expectLater(
      find.byKey(const ValueKey('minimap')),
      matchesGoldenFile('goldens/minimap-sparse.png'),
    );
  });

  testWidgets('busy or quiet, the tile is dust the whole way along', (tester) async {
    const size = Size(1280, 140);
    final painter = wavePainter();
    await pumpAt(tester, painter, size);
    expect(painter.grainsFor(size), isNotEmpty);
    // Both regimes are on this tile: a busy week and a quiet fortnight. The
    // motes belong to the quiet end alone; the dust belongs to all of it.
    expect(painter.motesFor(size), isNotEmpty);
  });

  test('NOTHING moves along time: only brightness and the width of the band do', () {
    const size = Size(96, 720);
    // Two instants far apart on a clock that never wraps, so if there were a
    // period this would straddle it.
    final early = wavePainter(clock: 0).grainsFor(size);
    final late = wavePainter(clock: 137.4).grainsFor(size);
    expect(early.length, late.length);
    expect(early, isNotEmpty);
    var twinkled = false;
    for (var index = 0; index < early.length; index += 1) {
      // Down the column IS time. Not one grain may have moved along it.
      expect(late[index].at.dy, early[index].at.dy, reason: 'grain $index travelled in time');
      if ((late[index].alpha - early[index].alpha).abs() > 1 / 100) twinkled = true;
    }
    expect(twinkled, isTrue, reason: 'nothing twinkled, so there is no motion at all');
  });

  test('the motion has no period: no two instants a cycle apart agree', () {
    const size = Size(96, 720);
    final base = wavePainter(clock: 0).grainsFor(size);
    // A whole base twinkle period later, and again much later: if the grains
    // shared one rate the field would be identical at both.
    for (final clock in [24.0, 48.0, 240.0]) {
      final now = wavePainter(clock: clock).grainsFor(size);
      final same = [
        for (var index = 0; index < base.length; index += 1)
          if ((now[index].alpha - base[index].alpha).abs() < 1 / 1000) index,
      ];
      expect(same.length, lessThan(base.length ~/ 2), reason: 'the field repeats at $clock s');
    }
  });

  testWidgets('a scrub holds the field still', (tester) async {
    const size = Size(96, 720);
    final moving = wavePainter(clock: 12);
    final held = MinimapPainter(
      field: moving.field,
      law: moving.law,
      theme: moving.theme,
      focusDays: moving.focusDays,
      spanDays: moving.spanDays,
      nowDays: moving.nowDays,
      granularity: moving.granularity,
      clock: 12,
      frozen: true,
    );
    await pumpAt(tester, held, size);
    expect(tester.takeException(), isNull);
    final grains = held.grainsFor(size);
    expect(grains, isNotEmpty);
    expect(grains.map((grain) => grain.alpha).toSet().length, lessThan(3));
  });

  testWidgets('time runs along the long side, and the scrub agrees with it', (tester) async {
    final tall = wavePainter();
    await pumpAt(tester, tall, const Size(96, 720));
    // Down the column IS forward in time, and across it is not time at all.
    expect(tall.unproject(Offset.zero), tall.field.range.start);
    expect(tall.unproject(const Offset(0, 720)) > tall.unproject(const Offset(0, 10)), isTrue);
    expect(tall.unproject(const Offset(96, 300)), tall.unproject(const Offset(0, 300)));
    // The eye and the drop cannot disagree: project undoes unproject.
    expect(tall.project(tall.unproject(const Offset(0, 300)))!, closeTo(300, 1));

    final wide = wavePainter();
    await pumpAt(tester, wide, const Size(1280, 140));
    expect(wide.unproject(const Offset(640, 0)), wide.unproject(const Offset(640, 70)));
    expect(wide.project(wide.unproject(const Offset(640, 0)))!, closeTo(640, 1));
  });
}
