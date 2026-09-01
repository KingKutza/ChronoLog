// THE SILENT-EMPTY CLASS (ISSUES 9.1, the third defect in Don's morning report).
//
// "A generator handed a stated rule that produces nothing because its own record
// is malformed must refuse in words (refusals notify), never return an empty list
// the card contradicts."
//
// `series_starvation_test.dart` holds the field report itself -- the pattern that
// says "repeats daily, ends never" and draws one day. This file holds the CLASS
// around it, both halves:
//
//   THE READ HEALS. The pattern's template placement is DERIVED from its template
//   event, so a record minted without `templateRelation`, or carrying a stale or
//   wrong one, projects anyway and no byte of Don's document has to be rewritten.
//
//   WHAT CANNOT PRODUCE SAYS SO. When the record really has nothing to repeat
//   from -- no template event, or a template that sits on no frame -- the query
//   comes back with a sentence naming why, never an empty list.
//
// Generative by ruling: the shapes quantify over seeded days and intervals, and
// nothing here counts occurrences.

import 'dart:math';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:test/test.dart';

import '../helpers/projection_scene.dart';
import 'corpus.dart';

const String frameId = 'calendar:a';

Rational days(int year, int month, int day) =>
    Rational(daysFromCivil(BigInt.from(year), month, day));

/// A pattern carrying whatever the caller says about its template, and nothing
/// else assumed -- so each shape below is exactly one defect.
String pattern(
  Scene scene, {
  required String? templateEvent,
  required String? templateRelation,
  int interval = 1,
}) {
  final id = scene.mint('pattern');
  scene.document = scene.document.put(
    'patterns',
    id,
    Pattern(
      id: id,
      language: 'chronolog-ics/1',
      extra: {
        'kind': 'ics-rrule',
        'templateEvent': ?templateEvent,
        'templateRelation': ?templateRelation,
        'frame': frameId,
        'appliesTo': [frameId],
        'rrule': {'FREQ': 'DAILY', 'INTERVAL': '$interval'},
      },
    ),
  );
  return id;
}

QueryResult over(Scene scene, int day) {
  final engine = ProjectionEngine(scene.document);
  final start = days(2026, 9, day);
  return engine.queryFacts(
    Projection.of(const [frameId]),
    start: start,
    end: start + Rational.fromInt(30),
  );
}

void main() {
  for (final seed in seeds(5)) {
    final random = Random(seed);
    final day = 1 + random.nextInt(20);
    final interval = 1 + random.nextInt(3);

    // --- The read heals ------------------------------------------------------

    for (final (said, stored) in [
      ('absent', null),
      ('stale — it names a relation that is gone', 'relation:vanished'),
    ]) {
      test('a templateRelation that is $said still projects, unrewritten (seed $seed)', () {
        final scene = Scene()..calendar(frameId);
        final template = scene.object(title: 'Standing', duration: '45');
        scene.place(frameId, civil(2026, 9, day, 9), event: template);
        final before = scene.document;
        pattern(
          scene,
          templateEvent: template,
          templateRelation: stored,
          interval: interval,
        );

        final result = over(scene, day);
        expect(
          result.facts.length,
          greaterThan(1),
          reason:
              'ISSUES (9.1): the placement is derivable from the template event, so '
              'the stored relation id being $said cannot starve the generator.',
        );
        expect(
          result.errors,
          isEmpty,
          reason: 'nothing is wrong with this series once the read derives',
        );
        // The heal is in the READ: every record the world arrived with is
        // untouched, which is what makes Don's own document heal on load.
        for (final entry in before.relations.entries) {
          expect(scene.document.relations[entry.key], entry.value);
        }
      });
    }

    test('a templateRelation naming another object\'s placement is overruled (seed $seed)', () {
      final scene = Scene()..calendar(frameId);
      final template = scene.object(title: 'Standing', duration: '45');
      scene.place(frameId, civil(2026, 9, day, 9), event: template);
      final other = scene.object(title: 'Someone else');
      final wrong = scene.place(frameId, civil(2026, 9, day, 14), event: other);
      pattern(scene, templateEvent: template, templateRelation: wrong, interval: interval);

      final result = over(scene, day);
      final generated = result.facts.where((fact) => fact.virtualId.isNotEmpty);
      expect(generated, isNotEmpty);
      for (final fact in generated) {
        expect(
          fact.event.payload?['title'],
          'Standing',
          reason:
              'ISSUES (9.1): the pattern names its template EVENT, so a stored '
              'relation belonging to another object is wrong data, not an instruction.',
        );
      }
    });

    // --- What cannot produce says so ----------------------------------------

    test('a repeat whose template sits on no frame refuses in words (seed $seed)', () {
      final scene = Scene()..calendar(frameId);
      final template = scene.object(title: 'Standing');
      pattern(scene, templateEvent: template, templateRelation: null, interval: interval);

      final result = over(scene, day);
      expect(
        result.errors,
        isNotEmpty,
        reason:
            'ISSUES (9.1): a stated rule that produces nothing because its own record '
            'is malformed must refuse in words, never answer with silence.',
      );
      expect(result.errors.single.message, contains('Standing'));
      expect(result.errors.single.message, contains('no frame'));
    });

    test('a repeat naming no template event at all refuses in words (seed $seed)', () {
      final scene = Scene()..calendar(frameId);
      scene.place(frameId, civil(2026, 9, day, 9));
      pattern(scene, templateEvent: null, templateRelation: null, interval: interval);

      final result = over(scene, day);
      expect(result.errors, isNotEmpty);
      expect(result.errors.single.message, contains('nothing to repeat'));
    });

    test('the COUNT-bounded fast path refuses in the same words (seed $seed)', () {
      final scene = Scene()..calendar(frameId);
      final template = scene.object(title: 'Standing');
      final id = pattern(scene, templateEvent: template, templateRelation: null);
      // A bounded rule takes the whole-series cache instead of the window walk;
      // it had its own silent empty, and it says the same sentence now.
      scene.document = scene.document.put(
        'patterns',
        id,
        scene.document.patterns[id]!.withField('rrule', {'FREQ': 'DAILY', 'COUNT': '5'}),
      );

      final result = over(scene, day);
      expect(result.errors, isNotEmpty);
      expect(result.errors.single.message, contains('no frame'));
    });

    test('a generator this build cannot read says so (seed $seed)', () {
      final scene = Scene()..calendar(frameId);
      final template = scene.object(title: 'Standing');
      scene.place(frameId, civil(2026, 9, day, 9), event: template);
      final id = pattern(scene, templateEvent: template, templateRelation: null);
      scene.document = scene.document.put(
        'patterns',
        id,
        scene.document.patterns[id]!.withField('kind', 'topology-replication'),
      );

      final result = over(scene, day);
      expect(
        result.errors.single.message,
        contains('topology-replication'),
        reason:
            'ISSUES (9.1): an unfamiliar language is DATA and is never refused as '
            'invalid — but a record whose whole purpose is to generate, generating '
            'nothing in silence, is the same defect the starved series was.',
      );
      // Data, not a refusal: the record is untouched and still loads.
      expect(scene.document.patterns[id]!.kind, 'topology-replication');
    });

    test('a healthy series says nothing at all (seed $seed)', () {
      final scene = Scene()..calendar(frameId);
      scene.series(frameId, const {'FREQ': 'DAILY'}, at: civil(2026, 9, day, 9));
      final result = over(scene, day);
      expect(result.facts.length, greaterThan(1));
      expect(result.errors, isEmpty, reason: 'a refusal is news, and there is no news here');
    });
  }
}
