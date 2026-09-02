// MINTING FROM A FRAME'S STAPLES REGION ARRIVES WITH THE STAPLE WRITTEN
// (ISSUES 9.2, Don).
//
// "If I have a frame editor open and I click new event or todo under 'stapled
// here', the new window that opens should contain a prewritten staple for the
// frame I am coming from."
//
// THIS REVERSES A PRIOR RULING, AND ONLY FOR THIS PATH. `frame_card.dart` carries
// the 9.1 ruling for its doors: "The blank cards open with their placement region
// EMPTY and waiting to be said -- coming from a frame does not staple anything to
// it, because the staple is the sentence and the sentence is authored." Don's 9.2
// ruling narrows it: a new object born out of the frame's own STAPLES REGION has
// exactly one thing said about it already, and the person just said it by
// choosing where to click. Minting from the DOORS row is unchanged and still
// arrives empty. Both halves are pinned here so the distinction cannot be lost
// again: the two affordances differ by WHERE they sit on the card, and this file
// finds them by place, never by wording.
//
// What arrives is a SENTENCE -- visible, editable, deletable like any other row,
// never a hidden default. It binds the whole of the new object to the frame and
// says nothing about where: Save writes exactly that one staple and no placement
// it was not given (today's `frameId` seed on a new-object request calls
// `createAt(frame, startDays ?? 0)` -- a placement at day zero nobody said).
// Discard writes nothing at all. One card class serves events, todos and notes,
// so this is one behaviour, asserted over every catalog kind.
//
// THE CONTRACT this file names: the frame card's "Stapled here" row offers one
// minting affordance per catalog kind, labelled as the doors are ("New event",
// "New todo", "New note" -- `New ${label.toLowerCase()}`); tapping one opens a
// `card:newObject:` tile whose card holds a draft staple `[ObjectEnd(new),
// StapleEnd.frame(origin)]` rendered as a `SentenceRow`. How the factory carries
// the origin is the implementer's (a `stapledTo` on `newObjectCard` is the
// natural spelling); what is pinned is the card as rendered and the document as
// written. Two consequences an implementer reading today's code would otherwise
// miss: the prewritten row's far end is a RE-SAYABLE TERM (today a kindless
// affiliation renders as a belonging row with `onSaid: null` and a refusal --
// "editable like any other sentence" forbids that here), and the seed COUNTS AS
// A CHANGE, so Save / Apply / Discard are on the card the moment it opens
// (`Draft.changed` is a document-identity check; a held pending record is not a
// change, a written staple is).

import 'package:chronolog/cards/frame_card.dart';
import 'package:chronolog/cards/sentence_rows.dart';
import 'package:chronolog/core/object_kinds.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/projection_scene.dart';
import 'harness.dart';
import 'object_harness.dart';

const String origin = 'frame:ptp';
const String originTitle = 'PTP';

/// A group frame with one member already, so the region is a region and not an
/// empty note.
Scene world() {
  final scene = Scene()..calendar('calendar:a');
  scene.frame(origin, const ['set', 'group']);
  scene.document = scene.document.put(
    'frames',
    origin,
    scene.document.frames[origin]!.copyWith(title: originTitle),
  );
  scene.join(origin, scene.object(title: 'Already here'));
  return scene;
}

Finder stapledHereRow() =>
    find.ancestor(of: find.text('Stapled here'), matching: find.byType(LayoutBuilder)).first;

Future<void> pumpFrame(WidgetTester tester, CardBench bench) => pumpHosted(
  tester,
  bench,
  const FrameCard(frameId: origin),
  klass: 'frame',
  id: origin,
  shell: true,
);

/// The minting affordance for [kind] INSIDE the row, or the one OUTSIDE it (the
/// doors). Same words, different place -- the place is the whole ruling.
Element mintingFor(String kind, {required bool inRow}) {
  final label = 'New ${objectKinds[kind]!.label.toLowerCase()}';
  final within = find.descendant(of: stapledHereRow(), matching: find.text(label)).evaluate().toSet();
  final all = find.text(label).evaluate();
  final chosen = all.where((element) => within.contains(element) == inRow).toList();
  expect(
    chosen,
    isNotEmpty,
    reason: inRow
        ? 'ISSUES 9.2: the "Stapled here" row offers no "$label" of its own -- the only one on '
              'the card is the doors\', which by the 9.1 ruling arrives empty.'
        : 'the doors row still offers "$label"',
  );
  return chosen.first;
}

/// Taps an affordance and renders the new-object tile it opened.
Future<TileSpec> openMinted(WidgetTester tester, CardBench bench, Element affordance) async {
  final before = bench.factory.stage.tiles.keys.toSet();
  await tester.ensureVisible(find.byElementPredicate((it) => it == affordance));
  await tester.pumpAndSettle();
  await tester.tap(find.byElementPredicate((it) => it == affordance), warnIfMissed: false);
  await tester.pumpAndSettle();
  final opened = bench.factory.stage.tiles.keys.toSet().difference(before);
  expect(opened, hasLength(1), reason: 'one tap opens one card');
  final spec = bench.factory.stage.tiles[opened.single]!;
  expect(spec.id, startsWith('card:newObject:'), reason: 'and it is a new-object card');
  await pumpCard(
    tester,
    bench.chrome,
    SizedBox(height: cardSurface.height, child: Builder(builder: spec.build)),
  );
  return spec;
}

/// The one staple row naming the origin frame, on the card as rendered.
Finder originSentence() => find.ancestor(
  of: find.descendant(of: find.byType(SentenceRow), matching: find.text(originTitle)),
  matching: find.byType(SentenceRow),
);

void main() {
  for (final kind in objectKinds.keys) {
    testWidgets('minting a $kind from the staples region opens a card with the staple to the '
        'frame already written, visible, editable and deletable', (tester) async {
      final bench = await openCards(world().document);
      await pumpFrame(tester, bench);
      await openMinted(tester, bench, mintingFor(kind, inRow: true));

      expect(
        originSentence(),
        findsOneWidget,
        reason:
            'ISSUES 9.2: "the new window that opens should contain a prewritten staple for the '
            'frame I am coming from." No sentence on the new $kind card names $originTitle.',
      );
      // Deletable: the row wears the same unsay every sentence wears.
      expect(
        find.descendant(of: originSentence(), matching: find.text('Unsay this')),
        findsOneWidget,
        reason: 'the prewritten staple is a sentence like any other, not a hidden default',
      );
      // Editable: the far end is a term you can say again -- tapping it opens
      // the find box every far end opens.
      await tester.tap(
        find.descendant(of: originSentence(), matching: find.text(originTitle)),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(
        fieldHinted('Connect to a frame or an object'),
        findsWidgets,
        reason: 'the far end of the prewritten staple can be re-said',
      );
    });

    testWidgets('Discard on a $kind minted from the staples region writes nothing at all', (
      tester,
    ) async {
      final bench = await openCards(world().document);
      final events = bench.editor.document.events.keys.toSet();
      final relations = bench.editor.document.relations.keys.toSet();
      await pumpFrame(tester, bench);
      await openMinted(tester, bench, mintingFor(kind, inRow: true));
      expect(find.text('Discard'), findsOneWidget, reason: 'a sentence is on the card: changes exist');
      await tapText(tester, 'Discard');
      expect(bench.editor.document.events.keys.toSet(), events, reason: 'no object was written');
      expect(
        bench.editor.document.relations.keys.toSet(),
        relations,
        reason: 'ISSUES 9.2: "Discard writes nothing" -- no staple survives the discard',
      );
    });

    testWidgets('Save on a $kind minted from the staples region writes exactly that one staple '
        'and no placement it was not given', (tester) async {
      final bench = await openCards(world().document);
      final events = bench.editor.document.events.keys.toSet();
      final relations = bench.editor.document.relations.keys.toSet();
      await pumpFrame(tester, bench);
      await openMinted(tester, bench, mintingFor(kind, inRow: true));
      await tapText(tester, 'Save');

      final newEvents = bench.editor.document.events.keys.toSet().difference(events);
      final newRelations = bench.editor.document.relations.keys.toSet().difference(relations);
      expect(newEvents, hasLength(1), reason: 'one $kind was minted');
      expect(
        newRelations,
        hasLength(1),
        reason:
            'ISSUES 9.2: Save writes the prewritten staple and nothing else -- not a second '
            'placement at day zero from the `frameId` seed, not nothing.',
      );
      final minted = newEvents.single;
      expect(objectKindForEvent(bench.editor.document.events[minted]), kind);
      final staple = bench.editor.document.relations[newRelations.single]!;
      expect(staple.isStaple, isTrue);
      expect(
        {for (final end in staple.ends) end.id},
        {minted, origin},
        reason: 'the staple binds the new object to the frame it came from',
      );
      expect(
        staple.coordinate,
        isNull,
        reason:
            'the region\'s own grammar says the object belongs to this frame and nothing '
            'about where -- no coordinate was said, so none is written',
      );
    });
  }

  testWidgets('the doors path is unchanged: a card minted from the doors opens with its '
      'staples region empty', (tester) async {
    // The 9.1 ruling, kept for the path it was made for. The doors are not the
    // frame's staples region: nothing was said about the frame by taking one.
    final bench = await openCards(world().document);
    final relations = bench.editor.document.relations.keys.toSet();
    await pumpFrame(tester, bench);
    await openMinted(tester, bench, mintingFor('event', inRow: false));
    expect(
      find.byType(SentenceRow),
      findsNothing,
      reason: 'ISSUES 9.1: "the blank cards open with their placement region EMPTY"',
    );
    expect(find.text('Unsay this'), findsNothing);
    expect(bench.editor.document.relations.keys.toSet(), relations, reason: 'nothing stapled');
  });
}
