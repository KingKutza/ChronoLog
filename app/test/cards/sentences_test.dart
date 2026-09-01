// THE SENTENCES REGION (ISSUES 9.1, Don's screenshot walk and the re-frame
// entries beside it).
//
// "There is no + to add a sentence. Nor is there a sentence here." — so the
// region is a run of sentences, each one a run of terms, and a + starts one.
// "No way to move an event incorrectly authored on one frame to another ... I
// think this is a sentences error." — so re-pointing the placement's frame end
// re-frames the object, and the coordinate comes along translated, or the
// re-saying is refused in words and nothing moves. "The Holds/Held-by picker
// pair should not be here" — so containment reads as a sentence like anything
// else and no second widget authors it. And the picker's one hardcoded verb
// dies: what a sentence says is a word the author picked.

import 'dart:math';

import 'package:chronolog/cards/sentence_rows.dart';
import 'package:chronolog/cards/sentences.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/staples.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import 'harness.dart';
import 'object_harness.dart';

/// A world with two calendar frames counting in the same standard clock, and
/// one object placed on the first. Two frames that share a basis is exactly the
/// case a coordinate CAN be carried across; the third frame below is the case
/// it cannot.
({Document document, String here, String there, String stranded, String object}) world({
  required String hour,
  required String minute,
}) {
  const here = 'frame:here', there = 'frame:there', stranded = 'frame:stranded';
  var document = createEmptyWorkspaceDocument(now: DateTime.utc(2026, 9, 1));
  for (final id in [here, there]) {
    document = document.put(
      'frames',
      id,
      Frame(
        id: id,
        title: id == here ? 'Here' : 'There',
        traits: const ['set', 'calendar'],
        extra: const {'basis': 'frame:wall-time'},
      ),
    );
  }
  // A frame whose own declaration cannot be resolved: it counts in a frame the
  // document does not hold, so nothing can say where a point of it is -- which
  // is exactly the case a coordinate cannot be carried into.
  document = document.put(
    'frames',
    stranded,
    const Frame(
      id: stranded,
      title: 'Stranded',
      traits: ['set', 'calendar'],
      extra: {'basis': 'frame:nothing-wears-this'},
    ),
  );
  document = document.put(
    'events',
    'event:one',
    const Event(id: 'event:one', traits: ['event'], payload: {'title': 'Lunch'}),
  );
  document = document.put(
    'relations',
    'relation:one',
    Relation(
      id: 'relation:one',
      type: 'staple',
      extra: {
        'kind': 'anchor',
        'role': 'placed',
        'ends': [
          ObjectEnd('event:one', point: 'start').toJson(),
          FrameEnd(here, position: Position.coordinate({
          'levels': [
            {'level': 'year', 'value': '2026'},
            {'level': 'month', 'value': '9'},
            {'level': 'day', 'value': '1'},
            {'level': 'hour', 'value': hour},
            {'level': 'minute', 'value': minute},
          ],
        })).toJson(),
        ],
      },
    ),
  );
  return (document: document, here: here, there: there, stranded: stranded, object: 'event:one');
}

Relation placementOf(CardBench bench, String objectId) =>
    bench.editor.engine.indexes.placementOf(objectId)!;

void main() {
  group('every end is a term you can say again', () {
    // RE-FRAMING IS RE-POINTING THE PLACEMENT'S FRAME END, and the instant
    // comes along. Generated over instants rather than asserted at one, so what
    // is proved is the property and not a remembered time.
    for (final seed in seeds(4)) {
      test('re-saying the frame end re-frames the object and carries the instant (seed $seed)', () async {
        final random = Random(seed);
        final made = world(
          hour: '${random.nextInt(24)}',
          minute: '${random.nextInt(60)}',
        );
        final bench = await openCards(made.document);
        final engine = bench.editor.engine;
        final before = placementOf(bench, made.object);
        final wasDays = engine.coordinateDays(made.here, before.coordinate);

        // What the card's own term does, through the one seam it does it by --
        // called rather than re-implemented (ruled 2026-09-01: the frame lives
        // on an END, so hand-writing a top-level field would edit nothing).
        final frameEnd = connectionEnds(before).singleWhere((end) => end.map == 'frames');
        expect(
          bench.editor.resay(before.id, slot: frameEnd.slot, becomes: made.there),
          isTrue,
          reason: bench.editor.refusals.join(' '),
        );

        final after = placementOf(bench, made.object);
        expect(after.frame, made.there, reason: 'the object did not change frames');
        expect(
          bench.editor.engine.coordinateDays(made.there, after.coordinate),
          wasDays,
          reason:
              'ISSUES (9.1): "the coordinate must come along translated (or refuse in '
              'words when no correspondence can carry it)" — the instant moved.',
        );
      });
    }

    testWidgets('the placement\'s frame end is offered as a term, and it re-frames', (tester) async {
      final made = world(hour: '11', minute: '30');
      final bench = await openCards(made.document);
      await pumpHosted(
        tester,
        bench,
        StapleEditor(objectId: made.object),
        id: made.object,
      );
      // The far end reads as what the frame is CALLED, and it carries a way to
      // say it again -- a term you can read but not re-say is display.
      expect(find.text('Here'), findsWidgets, reason: 'the placement names its frame');
      final again = find.bySemanticsLabel('Say Here again');
      expect(
        again,
        findsWidgets,
        reason:
            'ISSUES (9.1): "a sentence that shows a connection but not all of its ends '
            'as authored terms is display, not authoring".',
      );
      await tester.tap(again.first, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.enterText(fieldHinted('Connect to a frame or an object').first, 'There');
      await tester.pumpAndSettle();
      await tapText(tester, '▤ There');
      expect(
        placementOf(bench, made.object).frame,
        made.there,
        reason: 'saying the frame end again did not re-frame the object',
      );
    });

    testWidgets('where nothing carries the instant, the re-saying refuses in words', (tester) async {
      final made = world(hour: '9', minute: '15');
      final bench = await openCards(made.document);
      final before = placementOf(bench, made.object);
      await pumpHosted(
        tester,
        bench,
        StapleEditor(objectId: made.object),
        id: made.object,
      );
      await tester.tap(find.bySemanticsLabel('Say Here again').first, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.enterText(fieldHinted('Connect to a frame or an object').first, 'Stranded');
      await tester.pumpAndSettle();
      await tapText(tester, '▤ Stranded');
      expect(
        placementOf(bench, made.object).frame,
        before.frame,
        reason: 'a re-saying nothing can carry must move nothing',
      );
      expect(
        find.textContaining('Nothing carries this instant'),
        findsOneWidget,
        reason:
            'ISSUES (9.1): "coordinate translated or a worded refusal" — it moved '
            'nothing and said nothing either.',
      );
    });
  });

  group('the verb is authored, not a species', () {
    test('the offers are what the document says, then what the substrate reads', () async {
      final made = world(hour: '8', minute: '0');
      var document = made.document;
      // A word this document uses that the substrate registers nothing for.
      document = putStaple(
        document,
        kind: 'rehearses',
        ends: [const ObjectEnd('event:one', point: 'start'), StapleEnd.frame(made.there)],
      ).document;
      final bench = await openCards(document);
      final offers = verbOffers(bench.editor.document);
      // The workspace's own words come first. `anchor` is among them now
      // (ruled 2026-09-01: a placement is an anchoring staple, so every
      // document that places anything uses that word), which is what makes this
      // a claim about ORDER rather than about one word.
      expect(
        offers.indexOf('rehearses'),
        lessThan(offers.indexOf(stapleKinds.keys.firstWhere((kind) => kind != 'anchor'))),
        reason: 'what the workspace says comes before what only the substrate knows',
      );
      for (final registered in stapleKinds.keys) {
        expect(offers, contains(registered), reason: 'every registered word is still offered');
      }
      expect(offers.toSet().length, offers.length, reason: 'a word is offered once');
    });

    test('a word nothing registers is legal, and what it costs is said', () {
      expect(
        verbSays('rehearses'),
        contains('moves nothing'),
        reason:
            'ISSUES (8.31, staple is metal): verbs carry zero engine meaning. An '
            'unregistered word is legal and the cost is stated rather than silent.',
      );
      for (final registered in stapleKinds.entries) {
        expect(verbSays(registered.key), contains(registered.value.label));
      }
    });

    testWidgets('a new sentence is written with the word the row is wearing', (tester) async {
      final made = world(hour: '13', minute: '45');
      final bench = await openCards(made.document);
      await pumpHosted(
        tester,
        bench,
        StapleEditor(objectId: made.object),
        id: made.object,
      );
      final before = bench.editor.document.relations.length;
      // The far term of the new sentence writes it; nothing else has to be
      // touched, and the word it uses is the one the row already says.
      final wearing = verbOffers(bench.editor.document).first;
      await tester.enterText(fieldHinted('Connect to a frame or an object').last, 'There');
      await tester.pumpAndSettle();
      await tapText(tester, '▤ There');
      // The placement is a staple too now, so the new sentence is the one that
      // was not there before.
      final made2 = bench.editor.document.relations.values
          .where((row) => row.isStaple && !isPlacement(row))
          .toList();
      expect(bench.editor.document.relations.length, before + 1);
      expect(
        made2.single.kind,
        wearing,
        reason:
            'ISSUES (9.1): "the picker\'s one hardcoded \'anchor\' verb dies — the verb '
            'is authored".',
      );
    });
  });

  group('containment is a sentence, not a pair of pickers', () {
    testWidgets('the Holds / Held-by widgets are gone and the relation reads as a sentence', (
      tester,
    ) async {
      final made = world(hour: '10', minute: '0');
      var document = made.document;
      document = document.put(
        'events',
        'event:two',
        const Event(id: 'event:two', traits: ['event'], payload: {'title': 'Prep'}),
      );
      final bench = await openCards(document);
      bench.editor.setContains(made.object, 'event:two', true);
      await pumpHosted(
        tester,
        bench,
        StapleEditor(objectId: made.object),
        id: made.object,
      );
      for (final gone in const ['Holds', 'Held by', 'Hold another object']) {
        expect(
          find.text(gone),
          findsNothing,
          reason:
              'ISSUES (9.1): the picker pair "should not be here, it is not a part of '
              'the design" — "$gone" still is.',
        );
      }
      // And what replaces it is the sentence: the held object is named, in the
      // one region, and it can be unsaid there.
      expect(find.text('Prep'), findsWidgets, reason: 'what this holds is not said anywhere');
      expect(find.text('holds'), findsOneWidget, reason: 'the sentence wears its own word');
    });

    test('every relation naming the object is one sentence in the region', () async {
      final made = world(hour: '7', minute: '5');
      var document = made.document;
      document = document.put(
        'events',
        'event:two',
        const Event(id: 'event:two', traits: ['event'], payload: {'title': 'Prep'}),
      );
      final bench = await openCards(document);
      bench.editor.setContains(made.object, 'event:two', true);
      bench.editor.setContains('event:two', made.object, true);
      final said = objectSentences(bench.editor, made.object);
      // The placement, the thing it holds and the thing holding it: three
      // sentences, no relation hidden and none said twice.
      expect(said.where((row) => !row.belonging), hasLength(1));
      expect(said.where((row) => row.verb == 'holds'), hasLength(1));
      expect(said.where((row) => row.verb == 'is held by'), hasLength(1));
      // ONE SOURCE (ISSUES 9.1): every sentence comes off the substrate's own
      // list, so the card never walks the document a second time -- and a card
      // reading a second list is what would let one of them go stale.
      expect(
        said.length,
        bench.editor.staples.effectiveObjectStaples(made.object).length,
        reason: 'the card said something the substrate did not, or dropped one it did',
      );
      for (final row in said) {
        expect(row.row.relation != null || row.row.staple != null, isTrue,
            reason: 'a sentence with no record behind it');
        expect(row.belonging, !row.row.positions, reason: 'belonging is what carries no position');
      }
    });

    // WHICH WORD A BELONGING SENTENCE WEARS follows from the record, not from a
    // walk that already knew the answer: one containment read from the parent
    // says "holds" and the same record read from the child says "is held by".
    test('a belonging verb is derived from the record that spells it', () async {
      final made = world(hour: '6', minute: '30');
      var document = made.document;
      document = document.put(
        'events',
        'event:two',
        const Event(id: 'event:two', traits: ['event'], payload: {'title': 'Prep'}),
      );
      final bench = await openCards(document);
      bench.editor.setContains(made.object, 'event:two', true);
      final held = bench.editor.document.relations.values.firstWhere(
        (row) => stapledContainments(row).isNotEmpty,
      );
      expect(belongingVerb(held, made.object), 'holds');
      expect(belongingVerb(held, 'event:two'), 'is held by');
      // Both sides of the same record, and the far end read from each.
      final mine = objectSentences(bench.editor, made.object)
          .where((row) => row.belonging)
          .single;
      final theirs = objectSentences(bench.editor, 'event:two')
          .where((row) => row.belonging)
          .single;
      expect(mine.row.staple?.id, theirs.row.staple?.id, reason: 'one record, two readings');
      expect(mine.row.far?.id, 'event:two');
      expect(theirs.row.far?.id, made.object);
      // A WORD nobody has phrasing for says itself rather than nothing (ruled
      // 2026-09-01: the record kind is always `staple`, so the word that can be
      // unheard-of is the staple's own verb).
      const strange = Relation(id: 'r', type: 'staple', extra: {'kind': 'unheard-of'});
      expect(belongingVerb(strange, made.object), 'unheard-of');
    });
  });

  group('the readouts say what they mean', () {
    testWidgets('the extent reads as sentences rather than fields joined by dots', (tester) async {
      final made = world(hour: '11', minute: '30');
      final bench = await openCards(made.document);
      await pumpHosted(
        tester,
        bench,
        StapleEditor(objectId: made.object),
        id: made.object,
      );
      expect(
        find.textContaining('This starts at'),
        findsOneWidget,
        reason:
            'ISSUES (9.1): "a reading surface nobody can read is not reading out" — the '
            'extent is still a run of fields.',
      );
      expect(find.textContaining(' · '), findsNothing, reason: 'dots are not a sentence');
    });
  });
}
