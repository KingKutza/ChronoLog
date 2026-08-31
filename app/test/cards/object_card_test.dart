// The object card, the staple editor, the typeahead and the weight explainer:
// the spec.
//
// Properties over seeded generation, never pinned counts. Every case here
// restates a RULING or a field report in its own terms -- the steering rule,
// both-ends visibility, the overscale window, reversibility without a dialog --
// and reads the model's own answer rather than a number written down here.

import 'package:chronolog/cards/card_chrome.dart';
import 'package:chronolog/cards/connection_picker.dart';
import 'package:chronolog/cards/object_card.dart';
import 'package:chronolog/cards/staple_editor.dart';
import 'package:chronolog/cards/weight_explainer.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/object_kinds.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/staples.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import 'harness.dart';
import 'object_harness.dart';

/// Two objects on one frame, and the frame's own law. The smallest world in
/// which a connection has two ends worth navigating.
({Document document, String frame, String a, String b}) pair() {
  var document = createEmptyWorkspaceDocument(now: DateTime.utc(2026, 8, 27));
  const frame = 'frame:wall-time';
  for (final (id, title) in const [('event:a', 'Upstream'), ('event:b', 'Downstream')]) {
    document = document.put(
      'events',
      id,
      Event(id: id, traits: const ['event'], payload: {'title': title}),
    );
  }
  return (document: document, frame: frame, a: 'event:a', b: 'event:b');
}

void main() {
  late CardBench bench;

  group('the kind registry steers rather than refusing', () {
    // The 8.26 field report: authoring "end (Ends here) at start of event"
    // between two objects fails, while "Anchors a point" works -- "nothing
    // steers you from a refused kind to the kind that can author the same
    // connection."
    const object = ObjectEnd('event:a', point: 'end');
    const other = ObjectEnd('event:b', point: 'start');
    const frame = FrameEnd('frame:wall-time');
    const series = SeriesEnd('pattern:one');

    test('every steer names a REGISTERED kind, and never the one already chosen', () {
      for (final kind in stapleKinds.keys) {
        for (final near in const [object, frame, series]) {
          for (final far in const [object, other, frame, series]) {
            final steer = steerStapleKind(kind, near, far);
            if (steer == null) continue;
            expect(stapleKinds, contains(steer.kind));
            expect(steer.kind, isNot(kind));
            // The reason is written in the registry's own labels, so it reads
            // as the vocabulary the picker shows.
            expect(steer.why, contains(stapleKinds[steer.kind]!.label));
          }
        }
      }
    });

    test('a steer is IDEMPOTENT: the kind it names needs no further steer', () {
      for (final kind in stapleKinds.keys) {
        final steer = steerStapleKind(kind, object, other);
        if (steer == null) continue;
        expect(steerStapleKind(steer.kind, object, other), isNull);
      }
    });

    test('"Ends here" between two objects steers to the kind that PLACES', () {
      final steer = steerStapleKind('end', object, other);
      expect(steer?.kind, 'anchor');
      expect(steer!.why, contains('does not place it'));
    });

    test('a kind whose derivation fits this pair is left alone', () {
      expect(steerStapleKind('anchor', object, frame), isNull);
      expect(steerStapleKind('end', series, frame), isNull);
      expect(steerStapleKind('correspondence', frame, frame), isNull);
    });

    test('an unregistered kind is not steered — it is not this rule\'s business', () {
      expect(steerStapleKind('constraint-bound', object, frame), isNull);
    });
  });

  group('overscale: the far-end typeahead never enumerates', () {
    test('an empty query lists nothing at all', () {
      final corpus = Corpus(specSeed).document(events: 40, frames: 12);
      final found = searchConnectables(corpus, '   ', window: 5, scan: 1000);
      expect(found.hits, isEmpty);
      expect(found.scanned, isFalse);
    });

    test('hits never exceed the window, and the remainder is a LOWER BOUND', () {
      final corpus = Corpus(specSeed + 1).document(events: 60, frames: 20);
      for (final window in const [1, 3, 12]) {
        final found = searchConnectables(corpus, 'Object', window: window, scan: 5000);
        expect(found.hits.length, lessThanOrEqualTo(window));
        final total = corpus.events.values
            .where((event) => '${event.payload?['title']}'.contains('Object'))
            .length;
        expect(found.hits.length + found.more, total);
      }
    });

    test('the scan is bounded, so a huge document costs the same look', () {
      final corpus = Corpus(specSeed + 2).document(events: 60, frames: 20);
      final tight = searchConnectables(corpus, 'Object', window: 100, scan: 3);
      expect(tight.hits.length + tight.more, lessThanOrEqualTo(3));
    });
  });

  group('a connection is visible and navigable from BOTH of its ends', () {
    testWidgets('a staple authored A to B appears in B\'s card as a link to A', (tester) async {
      final world = pair();
      bench = await openCards(world.document);
      bench.editor.transaction(
        'Connect',
        (d) => putStaple(
          d,
          kind: 'anchor',
          ends: [
            ObjectEnd(world.a, point: 'end'),
            ObjectEnd(world.b, point: 'start'),
          ],
        ).document,
      );
      // The substrate answers for the far side, which is the half the web build
      // never rendered.
      final staples = bench.editor.staples;
      final rows = staples.effectiveObjectStaples(world.b);
      expect(rows.map((row) => row.far?.id), contains(world.a));

      await pumpHosted(tester, bench, StapleEditor(objectId: world.b), id: world.b);
      final upstream = bench.editor.document.events[world.a]!.payload!['title'];
      expect(find.text('$upstream'), findsWidgets);
      await tapText(tester, '$upstream');
      // Following the link opens the far record's own card as a tile.
      expect(bench.factory.stage.tiles.keys, contains('card:object:${world.a}'));
    });
  });

  group('containment has an authoring path at last', () {
    testWidgets('holding an object writes exactly one contains relation', (tester) async {
      final world = pair();
      bench = await openCards(world.document);
      final before = bench.editor.document.relations.length;
      bench.editor.setContains(world.a, world.b, true);
      final relations = bench.editor.document.relations.values
          .where((relation) => relation.type == 'contains')
          .toList();
      expect(relations, hasLength(1));
      expect(bench.editor.document.relations.length, before + 1);
      // It passes no judgment: the reverse edge is legal data too.
      bench.editor.setContains(world.b, world.a, true);
      expect(
        bench.editor.document.relations.values.where((r) => r.type == 'contains'),
        hasLength(2),
      );
    });
  });

  // E1 (2026-08-28): "created events that receive no updates auto-save when
  // closed, rather than waiting till at least one value is set somewhere."
  group('a new object is a DRAFT until the first authored value', () {
    /// The "+" card: no id, no seed, nothing stated.
    /// [tag] keys the card, so a fresh one really is fresh: without it Flutter
    /// updates the element in place and the second card is the first one still.
    Future<void> pumpNew(WidgetTester tester, String kind, {String tag = ''}) => pumpHosted(
      tester,
      bench,
      ObjectCard(
        key: ValueKey('new:$kind:$tag'),
        request: (
          klass: 'newObject',
          id: null,
          kind: kind,
          frameId: null,
          startDays: null,
          endDays: null,
        ),
      ),
      klass: 'newObject',
      kind: kind,
      shell: true,
    );

    testWidgets('opening one writes nothing: no record, no undo entry, no journal line', (
      tester,
    ) async {
      bench = await openCards(createEmptyWorkspaceDocument(now: DateTime.utc(2026, 8, 27)));
      final before = bench.editor.document.toJson();
      for (final kind in objectKinds.keys) {
        await pumpNew(tester, kind, tag: kind);
        expect(bench.editor.document.events, isEmpty, reason: 'nothing minted for $kind');
        expect(bench.editor.canUndo, isFalse);
        expect(bench.editor.document.toJson(), before);
        // Nor is it dirty: a card holding a record has authored no edit to
        // leave unsaved.
        expect(find.byTooltip('Unsaved edits'), findsNothing, reason: 'clean for $kind');
      }
    });

    testWidgets('closing it with nothing set means nothing happened', (tester) async {
      bench = await openCards(createEmptyWorkspaceDocument(now: DateTime.utc(2026, 8, 27)));
      final before = bench.editor.document.toJson();
      await pumpNew(tester, 'todo');
      await pumpCard(tester, bench.chrome, const SizedBox.shrink());
      expect(bench.editor.document.events, isEmpty);
      expect(bench.editor.canUndo, isFalse);
      expect(bench.editor.document.toJson(), before, reason: 'every record as it was');
      expect(bench.editor.pending, isEmpty, reason: 'and the hold went with the card');
    });

    testWidgets('the first value mints the record AND the value as ONE undo entry', (tester) async {
      bench = await openCards(createEmptyWorkspaceDocument(now: DateTime.utc(2026, 8, 27)));
      await pumpNew(tester, 'todo');
      await tester.enterText(find.byType(CardField).first, 'Ring the bell');
      await tester.pump();
      // The same card again -- same key, same state, a fresh build. (The stage
      // rebuilds a tile off `Chrome.pulse`; this harness pumps the card bare.)
      await pumpNew(tester, 'todo');
      expect(find.byTooltip('Unsaved edits'), findsOneWidget, reason: 'dirty once authored');
      final minted = bench.editor.document.events.values.toList();
      expect(minted, hasLength(1));
      expect(minted.first.payload?['title'], 'Ring the bell');
      expect(objectKindForEvent(minted.first), 'todo');
      expect(bench.editor.history, hasLength(1), reason: 'one act, one entry');
      // Undoing takes the record with the value: they were never two edits.
      expect(bench.editor.undo(), isTrue);
      expect(bench.editor.document.events, isEmpty);
    });

    testWidgets('discarding a minted record removes it undoably, and nothing asks', (tester) async {
      bench = await openCards(createEmptyWorkspaceDocument(now: DateTime.utc(2026, 8, 27)));
      await pumpNew(tester, 'todo');
      await tester.enterText(find.byType(CardField).first, 'Named');
      await tester.pump();
      final minted = bench.editor.document.events.keys.single;
      await tapText(tester, 'Discard');
      expect(bench.editor.document.events, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      expect(bench.editor.undo(), isTrue);
      expect(bench.editor.document.events.keys, contains(minted));
    });

    testWidgets('two surfaces asking for a new object hold two independent drafts', (tester) async {
      bench = await openCards(createEmptyWorkspaceDocument(now: DateTime.utc(2026, 8, 27)));
      bench.factory.open(bench.factory.newObjectCard('event'));
      bench.factory.open(bench.factory.newObjectCard('event'));
      expect(bench.factory.stage.tiles, hasLength(2), reason: 'there is no id to dedupe on');
    });

    testWidgets('a seed that STATES A PLACEMENT is an authored value: it commits', (tester) async {
      final world = pair();
      bench = await openCards(world.document);
      await pumpHosted(
        tester,
        bench,
        ObjectCard(
          request: (
            klass: 'newObject',
            id: null,
            kind: 'event',
            frameId: world.frame,
            startDays: Rational.zero,
            endDays: null,
          ),
        ),
        klass: 'newObject',
        kind: 'event',
        shell: true,
      );
      expect(bench.editor.document.events, hasLength(3), reason: 'drag-create is unchanged');
      expect(bench.editor.history, hasLength(1));
    });

    /// One value of each authored kind, each on its own fresh card: whichever
    /// row an author reaches for first is the one that mints.
    testWidgets('any kind of first value mints exactly one record and one entry', (tester) async {
      final acts = <String, void Function(Editor editor, String id, String other)>{
        'title': (editor, id, _) => editor.transaction(
          'Name it',
          (d) => d.put(
            'events',
            id,
            d.events[id]!.copyWith(payload: {...?d.events[id]!.payload, 'title': 'Named'}),
          ),
        ),
        'placement': (editor, id, _) {
          final placed = editor.placement(id, 'frame:wall-time', Rational.zero, 'placed');
          editor.transaction('Place it', (d) => d.put('relations', placed.id, placed));
        },
        'membership': (editor, id, _) {
          final joined = editor.membership(id, 'frame:wall-time');
          editor.transaction('Group it', (d) => d.put('relations', joined.id, joined));
        },
        'staple': (editor, id, other) => editor.transaction(
          'Connect it',
          (d) => putStaple(
            d,
            kind: 'anchor',
            ends: [
              ObjectEnd(id, point: 'start'),
              ObjectEnd(other, point: 'end'),
            ],
          ).document,
        ),
        'state': (editor, id, _) => editor.toggleState(id, doneStateFrameId),
        'contains': (editor, id, other) => editor.setContains(id, other, true),
      };
      for (final entry in acts.entries) {
        final world = pair();
        bench = await openCards(world.document);
        final editor = bench.editor;
        await pumpNew(tester, 'todo', tag: entry.key);
        final held = editor.pending.keys.single;
        expect(editor.document.events.containsKey(held), isFalse, reason: entry.key);
        entry.value(editor, held, world.a);
        expect(editor.document.events, hasLength(3), reason: '${entry.key} minted it');
        expect(editor.history, hasLength(1), reason: '${entry.key} is one entry');
        expect(editor.pending, isEmpty, reason: '${entry.key} authored it for good');
        expect(editor.undo(), isTrue);
        expect(editor.document.events.containsKey(held), isFalse, reason: 'undone whole');
      }
    });

    testWidgets('an edit committed DURING A BUILD is announced without throwing', (tester) async {
      final world = pair();
      bench = await openCards(world.document);
      var once = true;
      await pumpCard(
        tester,
        bench.chrome,
        Builder(
          builder: (context) {
            if (once) {
              once = false;
              bench.editor.setContains(world.a, world.b, true);
            }
            return const SizedBox.shrink();
          },
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(bench.editor.history, hasLength(1));
    });
  });

  group('the card is reversible, and nothing ever asks twice', () {
    testWidgets('a zero-duration kind offers no duration row; an event does', (tester) async {
      final world = pair();
      bench = await openCards(world.document);
      for (final kind in objectKinds.keys) {
        final event = bench.editor.document.events[world.a]!;
        bench.editor.transaction(
          'kind',
          (d) => d.put(
            'events',
            world.a,
            event.copyWith(traits: traitsForObjectKind(event.traits, kind)),
          ),
        );
        await pumpHosted(
          tester,
          bench,
          ObjectCard(
            request: (
              klass: 'object',
              id: world.a,
              kind: null,
              frameId: null,
              startDays: null,
              endDays: null,
            ),
          ),
          id: world.a,
          shell: true,
        );
        // TWO REGIONS, NO FOLD (ISSUES 8.31): the properties are in the open,
        // so the duration row is either on the card or is not offered at all.
        expect(
          find.text('Duration'),
          objectKinds[kind]!.zeroDuration ? findsNothing : findsOneWidget,
          reason: 'duration row for $kind',
        );
      }
    });
  });

  group('the weight explainer shows exactly what the engine folded', () {
    testWidgets('every ring the derivation reports is on the card, in order', (tester) async {
      final world = pair();
      bench = await openCards(world.document);
      final editor = bench.editor;
      // Place it, then put it in a boosting group -- one ring the fold must
      // report and the card must name.
      final placement = editor.placement(world.a, world.frame, Rational.zero, 'placed');
      final group = Frame(
        id: 'frame:boost',
        title: 'Boost',
        traits: const ['set', 'group'],
        extra: const {
          'display': {'weight': 'w * 3'},
        },
      );
      final joined = editor.membership(world.a, group.id);
      editor.transaction(
        'place and group',
        (d) => d
            .put('relations', placement.id, placement)
            .put('frames', group.id, group)
            .put('relations', joined.id, joined),
      );

      final fact = factForObject(editor.engine, world.a);
      expect(fact, isNotNull);
      final explanation = editor.explainWeight(fact!, Projection.of([world.frame]));

      await pumpHosted(tester, bench, WeightRings(objectId: world.a), id: world.a);
      for (final ring in explanation.rows) {
        expect(
          find.textContaining(ring.title),
          findsWidgets,
          reason: 'ring ${ring.id} is named on the card',
        );
      }
      expect(find.textContaining(explanation.weight.toDecimal(3)), findsWidgets);
      // The group's own formula is shown, not a number with no provenance.
      expect(find.textContaining('w * 3'), findsWidgets);
    });

    testWidgets('an unplaced object says so instead of showing a weight', (tester) async {
      final world = pair();
      bench = await openCards(world.document);
      await pumpHosted(tester, bench, WeightRings(objectId: world.a), id: world.a);
      expect(find.textContaining('Nothing places this object yet'), findsOneWidget);
    });
  });
}
