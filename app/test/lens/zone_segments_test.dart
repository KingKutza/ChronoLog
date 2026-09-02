// EVERY SEGMENT OF A ZONE IS THE ZONE (ISSUES 9.2, two reports).
//
// "Double-click on the body of a spanning zone event in Intimate does nothing;
// I have to click the head on the first day." And: "if I can't see the start I
// have no way to know what it is." One early `return` -- written to skip the
// title on continuation days -- sat before the hit registration. The rule:
//
//   For every painted segment of a multi-day fact, a hit test inside that
//   segment finds the fact, and the segment names itself (the title is sticky
//   on every visible segment).
//
// Generative: a random span of days and a random start hour.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/lens/painters/intimate.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/projection_scene.dart';
import 'painters/grid_scene.dart';

final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

const String frameId = 'calendar:a';

Map<String, Object?> at(int day, int hour) => {
  'levels': [
    {'level': 'year', 'value': '2026'},
    {'level': 'month', 'value': '9'},
    {'level': 'day', 'value': '$day'},
    {'level': 'hour', 'value': '$hour'},
    {'level': 'minute', 'value': '0'},
  ],
};

void main() {
  // ignore: avoid_print
  print('ZONE SEGMENTS RUN SEED: $runSeed  (set CHRONOLOG_SEED=$runSeed to reproduce)');
  final random = Random(runSeed);

  test('a hit inside any day of a spanning zone finds the zone', () {
    final scene = Scene()..calendar(frameId);
    final spanDays = 3 + random.nextInt(3), startHour = 6 + random.nextInt(6);
    final id = scene.object(title: 'Conference', duration: '${spanDays * 24 * 60}');
    scene.document = scene.document.put(
      'events',
      id,
      scene.document.events[id]!.withField('display', const {'zone': true}),
    );
    scene.place(frameId, at(2, startHour), event: id);
    const size = Size(1400, 900);
    // Focus on the middle of the span, so the start day is a column to the left.
    final middle = civilDays(2026, 9, 3) + Rational.fromInt(1, 2);
    final lens = sceneOf(scene.document, const [frameId], size: size, focus: middle, now: middle);
    final painter = IntimatePainter(lens);
    render(painter, size);
    final columns = painter
        .projectAll(middle)
        .where((point) => point.dx >= 0 && point.dx < size.width)
        .toList();
    expect(columns, isNotEmpty, reason: 'the middle of the span is on screen');
    for (final column in columns) {
      final probe = column + const Offset(24, 6);
      final hit = painter.markAt(probe);
      expect(
        hit?.fact.event.id,
        equals(id),
        reason:
            'ISSUES 9.2: the continuation segment at $probe registered no hit -- the title guard '
            'returned before `hits.add`. Every segment of a fact is the fact.',
      );
    }
  });

  test('every visible segment of a band names itself', () {
    // WORK ITEM (ISSUES 9.2, sticky title): the painter draws the title on the
    // start segment only (`zoneTitled`). When the title is sticky, this test
    // reads the painted labels per column (the painter records what it wrote)
    // and asserts the title appears inside every visible segment's rect.
    fail(
      'ISSUES 9.2: a zone whose start is off-screen is an anonymous wash. Make the title '
      'sticky per visible segment and record painted labels so this asserts it.',
    );
  });
}
