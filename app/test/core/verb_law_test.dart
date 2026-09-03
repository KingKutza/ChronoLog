// THE VERB CARRIES ZERO ENGINE MEANING (ISSUES 8.31, SENTENCES.md round five,
// Don's ruling).
//
// "Verb can not be logic, if it is open. It either has a definition in One Math
// or it doesn't... if it has a definition or not per verb then it is an enum,
// you can not have one verb mean something and another not without having a
// mapping and we already agreed to no mapping."
//
// The surviving position, from the same entry: ONE definition all verbs share --
// a staple binds the points it pierces; the solver reads the formula, never the
// verb; the verb is an authored word on the claim, data like colour (include,
// sort, style by it; meaning beyond binding is authored in projections). What
// looked like verb-meaning is FORMULA SHAPE, readable off the terms: which ends
// are objects and which frames, which point of the object is named, whether the
// far end carries a coordinate. "The stapleKinds registry dies as semantics (its
// flags re-derive from shape or die); the contract carries wording and styling
// only, zero meaning."
//
// Today the registry is live and it SELECTS: `isPlacement` asks
// `stapleKind(kind)?.anchors`, so a placement spelled with any word but
// `anchor` never reaches `_direct` and the object draws nowhere; the extent
// derivation and the connection rows ask the same flag; `seriesSegments` asks
// `partitions`, and `seriesEndStaple` and `objectEndStaple` compare the word to
// the literal `'end'`. Four sites where a word chooses a derivation.
//
// THE LAW THIS FILE STATES, and it is a law, not a refactor:
//
//   Two staples identical in every term -- the same ends, the same points, the
//   same coordinates, the same order -- derive identically whatever word is
//   written on them. Registered words, retired words, and words nobody has
//   ever typed are all one case. In particular no symbol in `lib/core` may read
//   `Relation.kind` to choose what a staple does; `stapleKinds`, `StapleKind`
//   and `stapleKind()` have no reader in the engine. What the cards keep is
//   wording: which words the dropdowns offer and how they are labelled.
//
// Deliberately NOT stated here, because it is Don's open residue in the same
// entry: WHICH reading an end-point staple gets (does an instant identified with
// an object's `end` relocate the extent, or only say when it finished). The
// tests below assert only that the two spellings AGREE, which is true under
// either answer and false today.
//
// Generative: seeded coordinates, seeded durations, and the words drawn from a
// pool of registered, retired and invented verbs, four per seed.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/object_kinds.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/staples.dart';
import 'package:test/test.dart';

import '../helpers/projection_scene.dart';

final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

String seeded(String message) => '$message  (set CHRONOLOG_SEED=$runSeed to reproduce)';

const String frameId = 'calendar:a';

/// Whole days on the shared axis for a civil date, the unit every fact's `day` counts in.
Rational civilDays(int year, int month, int day) => Rational(daysFromCivil(BigInt.from(year), month, day));

/// The words. The first six are what the registry knows; the rest are words a
/// person would actually write on a staple, none of them registered anywhere.
const List<String> verbs = [
  'anchor',
  'end',
  'phase',
  'correspondence',
  'inflection',
  'succession',
  'is placed on',
  'abuts',
  'was observed at',
  'dances with',
  'ᚱᚢᚾᛖ',
  'glorps',
];

/// Four words per seed, always including `anchor` and `end` -- the two the
/// engine currently treats differently -- so every seed exercises the tell.
List<String> wordsFor(Random random) {
  final rest = [for (final verb in verbs.skip(2)) verb]..shuffle(random);
  return ['anchor', 'end', ...rest.take(2)];
}

/// One reading of a document's facts on the calendar: object at day.
Set<String> factsOf(Document document) => {
  for (final fact in ProjectionEngine(document).explicitFacts(frameId))
    '${fact.event.id}@${fact.day}',
};

String extentOf(Document document, String objectId) {
  final extent = Staples(document).resolveObjectExtent(objectId);
  return '${extent.startDays}..${extent.endDays}';
}

void main() {
  // ignore: avoid_print
  print('VERB LAW RUN SEED: $runSeed  (set CHRONOLOG_SEED=$runSeed to reproduce)');
  final random = Random(runSeed);

  test('a placement derives the same under any word: the shape places, the verb does not', () {
    final day = 1 + random.nextInt(28), hour = random.nextInt(24);
    final duration = '${15 + random.nextInt(300)}';
    final words = wordsFor(random);
    Document under(String word) {
      final scene = Scene()..calendar(frameId);
      final object = scene.object(title: 'Same shape', duration: duration);
      scene.staple(
        kind: word,
        ends: [
          ObjectEnd(object, point: 'start'),
          FrameEnd(frameId, position: Position.coordinate(civil(2026, 9, day, hour))),
        ],
      );
      return scene.document;
    }

    final reference = under(words.first);
    final objectId = reference.events.keys.single;
    expect(
      factsOf(reference),
      isNotEmpty,
      reason: seeded('the premise: the shape [object.start = frame coordinate] IS a placement'),
    );
    for (final word in words.skip(1)) {
      final document = under(word);
      expect(
        factsOf(document),
        equals(factsOf(reference)),
        reason: seeded(
          'ISSUES 8.31: the same staple spelled "$word" projects differently from '
          '"${words.first}". A word chose whether the object is placed -- that is the '
          'registry acting as semantics.',
        ),
      );
      expect(
        extentOf(document, objectId),
        equals(extentOf(reference, objectId)),
        reason: seeded('the extent derivation read the word "$word", not the shape'),
      );
    }
  });

  test('an end-point staple derives the same under any word -- whichever reading is ruled', () {
    final day = 1 + random.nextInt(28), hour = random.nextInt(24);
    final duration = '${15 + random.nextInt(300)}';
    final words = wordsFor(random);
    Document under(String word) {
      final scene = Scene()..calendar(frameId);
      final object = scene.object(title: 'Same shape', duration: duration);
      scene.staple(
        kind: word,
        ends: [
          ObjectEnd(object, point: 'end'),
          FrameEnd(frameId, position: Position.coordinate(civil(2026, 9, day, hour))),
        ],
      );
      return scene.document;
    }

    final reference = under(words.first);
    final objectId = reference.events.keys.single;
    for (final word in words.skip(1)) {
      final document = under(word);
      expect(
        extentOf(document, objectId),
        equals(extentOf(reference, objectId)),
        reason: seeded(
          'ISSUES 8.31: [object.end = frame coordinate] spelled "$word" resolves to a '
          'different extent than spelled "${words.first}". Whether an end instant relocates '
          'the extent is Don\'s open residue; that the WORD decides it is not open.',
        ),
      );
      expect(
        factsOf(document),
        equals(factsOf(reference)),
        reason: seeded('the projection read the word "$word", not the shape'),
      );
    }
  });

  test('a series cut derives the same under any word: the shape partitions, the verb does not', () {
    final cutDay = 5 + random.nextInt(20);
    final words = wordsFor(random);
    Document under(String word) {
      final scene = Scene()..calendar(frameId);
      final pattern = scene.series(frameId, const {'FREQ': 'DAILY'}, at: civil(2026, 9, 1, 9));
      scene.staple(
        kind: word,
        ends: [
          StapleEnd.series(pattern),
          StapleEnd.frame(frameId, position: Position.coordinate(civil(2026, 9, cutDay))),
        ],
      );
      return scene.document;
    }

    Set<String> occurrences(Document document) {
      final found = ProjectionEngine(document).queryFacts(
        Projection.of(const [frameId]),
        start: civilDays(2026, 9, 1),
        end: civilDays(2026, 10, 1),
      );
      return {for (final fact in found.facts) '${fact.day}'};
    }

    final reference = under(words.first);
    for (final word in words.skip(1)) {
      expect(
        occurrences(under(word)),
        equals(occurrences(reference)),
        reason: seeded(
          'ISSUES 8.31: [series = frame coordinate] spelled "$word" cuts the series '
          'differently from "${words.first}" (seriesSegments asks `partitions`, '
          'seriesEndStaple compares to the literal "end").',
        ),
      );
    }
  });

  test('a completion instant is found by its shape, not by the word "end"', () {
    final day = 1 + random.nextInt(28), hour = random.nextInt(24);
    final words = wordsFor(random);
    Document under(String word) {
      final scene = Scene()..calendar(frameId);
      final todo = scene.object(title: 'Same shape', duration: '30');
      scene.document = scene.document.put(
        'events',
        todo,
        scene.document.events[todo]!.copyWith(traits: objectKinds['todo']!.traits),
      );
      scene.place(frameId, civil(2026, 9, day, 9), event: todo);
      scene.frame(doneStateFrameId, stateFrameTraits);
      scene.join(doneStateFrameId, todo);
      scene.staple(
        kind: word,
        ends: [
          ObjectEnd(todo, point: 'end'),
          FrameEnd(frameId, position: Position.coordinate(civil(2026, 9, day, hour))),
        ],
      );
      return scene.document;
    }

    String instantOf(Document document) {
      final entry = ObjectFacts(document).rosterEntries('todo').single;
      return '${entry.completed}:${entry.completedAt?.toJson()}';
    }

    final reference = under(words.first);
    for (final word in words.skip(1)) {
      expect(
        instantOf(under(word)),
        equals(instantOf(reference)),
        reason: seeded(
          'ISSUES 8.31: the roster reads the completion instant off the word "end" '
          '(objectEndStaple, rosterEntries); spelled "$word" the same staple says nothing.',
        ),
      );
    }
  });
}
