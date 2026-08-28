// Radial and Spiral, as lenses rather than as geometry.
//
// The geometry spec next door guards the shapes; this guards the LENS: that the
// angle mapping is a bijection over the drawn window (so a wheel notch can spin
// it), that a cycle is either an exact positive period or a stated refusal and
// never a quiet zero, and that the drawn field obeys the one capacity budget.
//
// Properties over seeded worlds, never pinned counts.

import 'dart:math';
import 'dart:ui' as ui;

import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/lens/capacity.dart';
import 'package:chronolog/lens/lens_painter.dart';
import 'package:chronolog/lens/painters/radial.dart';
import 'package:chronolog/lens/painters/spiral.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/corpus.dart';
import '../../helpers/projection_scene.dart';

const double tolerance = 1e-6;
const Size surface = Size(900, 700);

LensScene sceneOver(
  Document document,
  List<String> frames, {
  Map<String, Object?> view = const {},
  Rational? focus,
}) {
  final engine = ProjectionEngine(document);
  final at = focus ?? Rational(daysFromCivil(BigInt.from(2026), 8, 18));
  return LensScene(
    engine: engine,
    projection: Projection.of(frames),
    law: engine.lawOf(frames.first),
    focusDays: at,
    view: view,
    theme: shipped['paper']!,
    nowDays: at,
    size: surface,
  );
}

/// A world with a calendar, a group and a scatter of placed objects, seeded so a
/// failure names the document that produced it.
Scene worldFor(int seed, {int? hoursPerDay}) {
  final random = Random(seed);
  final world = Scene()..calendar('calendar:a', hoursPerDay: hoursPerDay);
  final members = <String>[];
  for (var index = 0; index < 12; index += 1) {
    final day = 10 + random.nextInt(18);
    final id = world.object(title: 'Object $index', duration: '${15 + random.nextInt(180)}');
    world.place('calendar:a', civil(2026, 8, day, random.nextInt(hoursPerDay ?? 24)), event: id);
    if (random.nextBool()) members.add(id);
  }
  world.group('group:a', members);
  return world;
}

void paintOn(CustomPainter painter) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), surface);
  recorder.endRecording().dispose();
}

void main() {
  test('the angle mapping is a bijection over the drawn window', () {
    for (final seed in seeds(6)) {
      final world = worldFor(seed, hoursPerDay: seed.isEven ? null : 23);
      for (final painter in [
        RadialPainter(sceneOver(world.document, ['calendar:a', 'group:a'])),
        SpiralPainter(sceneOver(world.document, ['calendar:a'], view: {'inward': 1, 'outward': 2})),
      ]) {
        final curve = painter;
        for (var step = 0; step < 8; step += 1) {
          final angle = startRayOf(curve) + step / 8 * curve.cycle.turns * pi * 2;
          expect(
            curve.daysToAngle(curve.angleToDays(angle)),
            closeTo(angle, 1e-9),
            reason: 'seed $seed',
          );
        }
      }
    }
  });

  test('a cycle is an exact positive period or a stated refusal, never neither', () {
    for (final seed in seeds(6)) {
      final world = worldFor(seed, hoursPerDay: seed.isEven ? null : 23);
      final span = cycleFor(sceneOver(world.document, ['calendar:a']));
      expect(
        span.refusal != null || (span.period > Rational.zero && span.end > span.start),
        isTrue,
        reason: 'seed $seed',
      );
      if (span.refusal != null) expect(span.period, Rational.zero);
    }
  });

  test('the drawn field never exceeds the one capacity budget', () {
    for (final seed in seeds(4)) {
      final world = worldFor(seed);
      for (final painter in [
        RadialPainter(sceneOver(world.document, ['calendar:a', 'group:a'])),
        SpiralPainter(sceneOver(world.document, ['calendar:a'])),
      ]) {
        paintOn(painter);
        final curve = painter;
        final budget = capacityOf(
          pi * 2 * curve.outer * curve.cycle.turns,
          curve.outer - curve.inner,
          null,
        );
        expect(painter.hits.length, lessThanOrEqualTo(budget.marks), reason: 'seed $seed');
      }
    }
  });

  test('a mark hit is the ribbon the eye sees, not the box around a half circle', () {
    final world = worldFor(specSeed);
    final painter = RadialPainter(sceneOver(world.document, ['calendar:a']));
    paintOn(painter);
    for (final hit in painter.hits) {
      expect(hit.shape, isNotNull);
      // The band hugs its own radius: nothing in it reaches the centre.
      expect(hit.bounds.contains(painter.centre), isFalse);
    }
  });

  testWidgets('both lenses paint a first-run document without inventing a now', (tester) async {
    final document = createEmptyWorkspaceDocument(now: DateTime.utc(2026, 8, 27));
    final frames = document.frames.keys.toList();
    for (final painter in [
      RadialPainter(sceneOver(document, frames)),
      SpiralPainter(sceneOver(document, frames)),
    ]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox.fromSize(
            size: surface,
            child: CustomPaint(painter: painter),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });
}

/// The ray both lenses start and stop on, read off the painter rather than
/// restated: the spec asserts the bijection, not the convention.
double startRayOf(CurvePainter painter) => painter.daysToAngle(painter.cycle.start);
