// A PLACEMENT NAMES THE PLACEMENT POINT (ISSUES 9.2, Don's double render).
//
// Field report, proven from the live journal: an END anchor -- object end
// `point: end`, far end a Wall Time coordinate -- was indexed as a second
// PLACEMENT beside the start, and the projection built one fact per relation,
// so the same event drew twice on every lens that projects Wall Time. The rule:
//
//   A placement is a staple that names the object's PLACEMENT POINT at a frame
//   coordinate. An anchor on any other point is an anchor for the extent
//   derivation and never a second placement. The projection yields ONE fact
//   per object per frame; a second placement-shaped record is a contest in
//   words, never a second mark.
//
// Generative: random start day, random span, random end hour.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/staples.dart';
import 'package:test/test.dart';

import '../helpers/projection_scene.dart';

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
  print('PLACEMENT POINT RUN SEED: $runSeed  (set CHRONOLOG_SEED=$runSeed to reproduce)');
  final random = Random(runSeed);

  test('an anchor on the END is not a placement, and the object draws once', () {
    final scene = Scene()..calendar(frameId);
    final startDay = 1 + random.nextInt(18), span = 1 + random.nextInt(6);
    final id = scene.object(title: 'Span', duration: '60');
    scene.place(frameId, at(startDay, 9), event: id);
    final endAnchor = scene.staple(
      kind: 'anchor',
      ends: [
        ObjectEnd(id, point: 'end'),
        FrameEnd(frameId, position: Position.coordinate(at(startDay + span, 17))),
      ],
    );
    expect(
      isPlacement(endAnchor, id),
      isFalse,
      reason:
          'ISSUES 9.2: `isPlacement` must read WHICH point the near end names. An anchor '
          'on `end` positions the extent; it is not where the object is placed.',
    );
    final engine = ProjectionEngine(scene.document);
    final own = engine.explicitFacts(frameId).where((fact) => fact.event.id == id).toList();
    expect(
      own,
      hasLength(1),
      reason:
          'ISSUES 9.2: one object, one frame, ONE fact. Two relations naming the same '
          'object on the same sheet are one extent, not two marks (found ${own.length}).',
    );
  });

  test('two resolving anchors derive the magnitude between them (guard)', () {
    final scene = Scene()..calendar(frameId);
    final startDay = 1 + random.nextInt(18), span = 1 + random.nextInt(6);
    final id = scene.object(title: 'Span', duration: '60');
    scene.place(frameId, at(startDay, 9), event: id);
    scene.staple(
      kind: 'anchor',
      ends: [
        ObjectEnd(id, point: 'end'),
        FrameEnd(frameId, position: Position.coordinate(at(startDay + span, 9))),
      ],
    );
    final extent = ProjectionEngine(scene.document).staples.resolveObjectExtent(id);
    expect(extent.startDays, isNotNull);
    expect(extent.endDays, isNotNull);
    expect(
      extent.endDays! - extent.startDays!,
      equals(Rational.fromInt(span)),
      reason: 'a start placement and an end anchor separate the extent by exactly their distance',
    );
  });
}
