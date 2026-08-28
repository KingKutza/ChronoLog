// The warp: N staples = warp, Lines draws it.
//
// The properties that matter are about what Lines REFUSES. A companion of
// another coordinate space with no authored staple has no place on this axis and
// must draw nothing while saying why; with two staples it is pinned exactly at
// both and stretched between them, and nothing outside the pinned span may be
// answered for at all.

import 'dart:math';
import 'dart:ui' as ui;

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/lens/lens_painter.dart';
import 'package:chronolog/lens/painters/lines.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/corpus.dart';
import '../../helpers/projection_scene.dart';

const Size surface = Size(1200, 620);

LensScene sceneOver(
  Document document,
  List<String> frames, {
  Map<String, Object?> view = const {},
}) {
  final engine = ProjectionEngine(document);
  final focus = Rational(daysFromCivil(BigInt.from(2026), 8, 18));
  return LensScene(
    engine: engine,
    projection: Projection.of(frames),
    law: engine.lawOf(frames.first),
    focusDays: focus,
    view: {'days': 60, ...view},
    theme: shipped['paper']!,
    nowDays: focus,
    size: surface,
  );
}

List<Pin> pinsFrom(List<(int, int)> pairs) => [
  for (final (from, to) in pairs)
    (from: Rational.fromInt(from), to: Rational.fromInt(to), eventId: null),
]..sort((a, b) => a.from.compareTo(b.from));

/// A world of two frames in DIFFERENT coordinate spaces, with objects on each.
/// `staples` correspondence staples relate them, or none do.
Scene twoSpaces(int seed, {int staples = 0}) {
  final random = Random(seed);
  final world = Scene()..calendar('calendar:a');
  world.frame('frame:other', const ['set', 'calendar'], {'coordinate': inventedLaw});
  for (var index = 0; index < 6; index += 1) {
    world.place('calendar:a', civil(2026, 8, 10 + random.nextInt(16), 9), title: 'Here $index');
    world.place('frame:other', stroke(2 + index, random.nextInt(8)), title: 'There $index');
  }
  for (var index = 0; index < staples; index += 1) {
    world.staple(
      kind: 'correspondence',
      ends: [
        StapleEnd.frame(
          'calendar:a',
          position: Position.coordinate(civil(2026, 8, 12 + index * 4)),
        ),
        StapleEnd.frame('frame:other', position: Position.coordinate(stroke(2 + index * 5))),
      ],
    );
  }
  return world;
}

LinesPainter painted(LensScene scene) {
  final painter = LinesPainter(scene);
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), surface);
  recorder.endRecording().dispose();
  return painter;
}

void main() {
  test('a pin is exact and the stretch between two pins is linear', () {
    for (final seed in seeds(8)) {
      final random = Random(seed);
      // Distinct pinned points, arbitrary images: a correspondence may fold,
      // and the property has to hold when it does.
      var from = 0;
      final pins = pinsFrom([
        for (var index = 0; index < 2 + random.nextInt(4); index += 1)
          (from += 1 + random.nextInt(5), random.nextInt(40)),
      ]);
      for (final pin in pins) {
        expect(warp(pins, pin.from), pin.to, reason: 'seed $seed');
      }
      for (var index = 0; index + 1 < pins.length; index += 1) {
        final (before, after) = (pins[index], pins[index + 1]);
        final middle = (before.from + after.from) / Rational.fromInt(2);
        final image = warp(pins, middle);
        expect(image, isNotNull);
        expect(
          image! * Rational.fromInt(2),
          before.to + after.to,
          reason: 'the midpoint of a stretch is the midpoint of its image',
        );
      }
    }
  });

  test('outside the pinned span the warp answers nothing', () {
    final pins = pinsFrom([(10, 100), (20, 140)]);
    expect(warp(pins, Rational.fromInt(9)), isNull);
    expect(warp(pins, Rational.fromInt(21)), isNull);
    expect(warp(pins.take(1).toList(), Rational.fromInt(15)), isNull);
    expect(warp(const [], Rational.fromInt(15)), isNull);
  });

  test('one staple pins a point and does not license a line', () {
    final pins = pinsFrom([(10, 100)]);
    expect(warp(pins, Rational.fromInt(10)), Rational.fromInt(100));
    expect(warp(pins, Rational.fromInt(11)), isNull);
  });

  test('a folded correspondence stays folded rather than averaging', () {
    final pins = pinsFrom([(10, 100), (20, 40)]);
    final image = warp(pins, Rational.fromInt(15));
    expect(image, Rational.fromInt(70));
    expect(image! < pins.first.to, isTrue, reason: 'the mapping runs backwards, and is drawn so');
  });

  test('an unrelated companion draws no point and says why', () {
    for (final seed in seeds(3)) {
      final world = twoSpaces(seed);
      final painter = painted(sceneOver(world.document, ['calendar:a', 'frame:other']));
      for (final hit in painter.hits) {
        expect(
          hit.fact.relation.frame,
          isNot('frame:other'),
          reason: 'no authored staple relates it to the prime',
        );
      }
      expect(
        painter.refusals.any((refusal) => refusal.message.contains('staple')),
        isTrue,
        reason: 'the refusal is stated, not swallowed',
      );
    }
  });

  test('two staples are a warp, and the companion is drawn through them', () {
    final world = twoSpaces(specSeed, staples: 2);
    final engine = ProjectionEngine(world.document);
    final pins = warpPins(engine, 'frame:other', 'calendar:a', const {});
    expect(pins.length, greaterThanOrEqualTo(2));
    final painter = painted(sceneOver(world.document, ['calendar:a', 'frame:other']));
    final companion = painter.hits.where((hit) => hit.fact.relation.frame == 'frame:other');
    expect(companion, isNotEmpty, reason: 'the authored correspondence places it');
    for (final hit in companion) {
      expect(warp(pins, hit.fact.day), isNotNull, reason: 'every drawn point is inside the pins');
    }
  });

  test('the prime axis reads a point back exactly where it drew it', () {
    final world = twoSpaces(specSeed);
    final painter = painted(sceneOver(world.document, ['calendar:a']));
    for (var step = 1; step < 8; step += 1) {
      final days = painter.start + (painter.end - painter.start) * Rational.fromInt(step, 8);
      final at = painter.project(days);
      expect(at, isNotNull);
      final back = painter.unproject(at!);
      expect((back! - days).abs() < Rational.fromInt(1, 1000), isTrue);
    }
  });
}
