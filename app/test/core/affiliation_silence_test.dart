// AN AFFILIATION IS NOT A FAILED POSITION (ISSUES 9.2, three reports, one class).
//
// Don's rulings today: whole<->whole between objects says "this is connected to
// that"; whole<->frame says "in this frame, nothing about where". Neither is a
// claim on a point, so neither can FAIL to resolve one. Yet the extent
// derivation reported every whole-ended staple as an "unresolved" contest --
// the ultra-long extent note, and the lens-top banner about the email note.
//
//   An object whose connections are ALL affiliations has zero contests, no
//   refusal anywhere the projection reports, and is simply unpositioned.
//
// Generative: random numbers of group affiliations and object affiliations.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
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
  print('AFFILIATION SILENCE RUN SEED: $runSeed  (set CHRONOLOG_SEED=$runSeed to reproduce)');
  final random = Random(runSeed);

  test('an object connected only by wholes has no contests and no refusal', () {
    final scene = Scene()..calendar(frameId);
    final groups = 1 + random.nextInt(4), partners = 1 + random.nextInt(4);
    final note = scene.object(title: 'Email from Reggie', duration: '0');
    for (var i = 0; i < groups; i += 1) {
      final group = 'group:$i';
      scene.frame(group, const ['set', 'group']);
      scene.staple(kind: 'anchor', ends: [ObjectEnd(note), StapleEnd.frame(group)]);
    }
    for (var i = 0; i < partners; i += 1) {
      final partner = scene.object(title: 'Todo $i', duration: '0');
      scene.place(frameId, at(1 + random.nextInt(20), 9), event: partner);
      scene.staple(kind: 'anchor', ends: [ObjectEnd(note), ObjectEnd(partner)]);
    }
    final engine = ProjectionEngine(scene.document);
    final extent = engine.staples.resolveObjectExtent(note);
    expect(
      extent.unresolved,
      isEmpty,
      reason:
          'ISSUES 9.2: a whole-ended staple claims no point, so it cannot be an unresolved '
          'claim. Found: ${extent.unresolved.map((c) => c.reason).toList()}',
    );
    expect(extent.overdetermined, isEmpty);
    expect(extent.startDays, isNull, reason: 'affiliations position nothing -- by design');
    expect(
      engine.staples.stapledPlacements.refusals[note],
      isNull,
      reason: 'ISSUES 9.2: an unpositioned-by-design object is not a refusal for the lens top',
    );
    final projected = engine.queryFacts(
      Projection.of([frameId, for (var i = 0; i < groups; i += 1) 'group:$i']),
      start: Rational.fromInt(-1000000),
      end: Rational.fromInt(1000000),
    );
    expect(
      projected.errors.where((error) => error.source == note),
      isEmpty,
      reason: 'ISSUES 9.2: nothing the projection reports may name an affiliation-only object',
    );
  });
}
