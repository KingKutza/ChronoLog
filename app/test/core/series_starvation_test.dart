// A SERIES NEVER STARVES IN SILENCE (ISSUES 9.1, Don's morning test).
//
// The field report, proven from the live journal: a pattern minted before the
// 8.31-evening fix carries templateEvent, frame, appliesTo and the rrule but no
// templateRelation, and the generator's first line returns NOTHING for it,
// silently — while the card round-trips the rrule and reads "repeats daily,
// ends never". The generalized rule this file states:
//
//   A pattern whose rrule says "repeat" either PROJECTS its occurrences or
//   REFUSES IN WORDS. An empty answer with no stated reason is the defect,
//   whatever field the record is missing — the placement is derivable from
//   templateEvent (`placementOf`), so "minted without templateRelation" must
//   not be a reachable silent state.
//
// Generative by ruling: the shape quantifies over seeded start days and
// intervals, never a pinned date or a pinned count.

import 'dart:math';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:test/test.dart';

import '../helpers/projection_scene.dart';
import 'corpus.dart';

const String frameId = 'calendar:a';

Rational civilDays(int year, int month, int day) =>
    Rational(daysFromCivil(BigInt.from(year), month, day));

/// Don's exact journal shape (seq 70): everything BUT templateRelation.
Scene starvedWorld(Random random, {required int interval, required Json at}) {
  final scene = Scene()..calendar(frameId);
  final template = scene.object(title: 'Standing', duration: '45');
  scene.place(frameId, at, event: template);
  final id = scene.mint('pattern');
  scene.document = scene.document.put(
    'patterns',
    id,
    Pattern(
      id: id,
      language: 'chronolog-ics/1',
      extra: {
        'kind': 'ics-rrule',
        'templateEvent': template,
        'frame': frameId,
        'appliesTo': [frameId],
        'rrule': {'FREQ': 'DAILY', 'INTERVAL': '$interval'},
      },
    ),
  );
  return scene;
}

void main() {
  for (final seed in seeds(5)) {
    test('a repeat with no templateRelation projects or refuses — never silence (seed $seed)', () {
      final random = Random(seed);
      final day = 1 + random.nextInt(25);
      final interval = 1 + random.nextInt(3);
      final scene = starvedWorld(random, interval: interval, at: civil(2026, 9, day, 9));
      final engine = ProjectionEngine(scene.document);
      final start = civilDays(2026, 9, day);
      final result = engine.queryFacts(
        Projection.of(const [frameId]),
        start: start,
        end: start + Rational.fromInt(30),
      );
      // More than the template's own single placement, or a reason in words.
      // Today: exactly one fact and no error — the silent starvation the
      // tracker names.
      expect(
        result.facts.length > 1 || result.errors.isNotEmpty,
        isTrue,
        reason:
            'ISSUES (9.1): the pattern says "every $interval day(s), ends never" and the '
            'window holds ${result.facts.length} fact(s) with ${result.errors.length} stated '
            'error(s) — a rule stored over a starved generator, said by nobody.',
      );
    });

    test('a healthy series still projects (seed $seed)', () {
      final random = Random(seed);
      final day = 1 + random.nextInt(25);
      final scene = Scene()..calendar(frameId);
      scene.series(frameId, const {'FREQ': 'DAILY'}, at: civil(2026, 9, day, 9));
      final engine = ProjectionEngine(scene.document);
      final start = civilDays(2026, 9, day);
      final result = engine.queryFacts(
        Projection.of(const [frameId]),
        start: start,
        end: start + Rational.fromInt(30),
      );
      expect(result.facts.length, greaterThan(1), reason: 'the generator itself is not in question');
    });
  }
}
