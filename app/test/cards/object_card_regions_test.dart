// THE TWO-REGION OBJECT CARD (ISSUES 8.31, "New event/Object card, RULED
// redesign"; SENTENCES.md "The header" and "The staple sentence").
//
// What stands: "the dropdown on the noun — click *EVENT* to switch object kind
// — is good and stays." What fails: "everything below it is a dense mess that
// leaves the eye no natural path."
//
// The ruled shape, verbatim: "the card is TWO regions of authored sentences,
// nothing else. Top, properties: *EVENT* $name *DESCRIPTION* $description *+* —
// start with the basics (name, description, color) and add properties at will
// via the +. A horizontal rule, then staples, with its own *+*." And: "Frame
// connection is PART of the staple, not a separate control — membership is a
// staple; the standalone frame section dies." And: "Typing a frame name that
// does not exist offers to instantiate it, opening a second card to set that
// frame up." And: "Buttons: Delete always; when changes exist, Save / Apply /
// Discard." And: "The same card works for todos and notes — one editor class
// over properties + staples, not one per kind."
//
// Every case below asks the card as it is rendered, through the same CardHost a
// tile gives it.

import 'package:chronolog/cards/object_card.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/object_kinds.dart';
import 'package:chronolog/core/records.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import 'object_harness.dart';

/// One placed object on the workspace's own calendar frame: the smallest world a
/// card has anything to say about.
({Document document, String frame, String object}) placed() {
  var document = createEmptyWorkspaceDocument(now: DateTime.utc(2026, 8, 31));
  const frame = 'frame:wall-time';
  document = document.put(
    'events',
    'event:lunch',
    Event(id: 'event:lunch', traits: const ['event'], payload: const {'title': 'Lunch'}),
  );
  document = document.put(
    'relations',
    'relation:lunch',
    Relation(
      id: 'relation:lunch',
      type: 'staple',
      extra: {
        'kind': 'anchor',
        'role': 'placed',
        'ends': [
          ObjectEnd('event:lunch', point: 'start').toJson(),
          FrameEnd(frame, position: Position.coordinate({
          'levels': [
            {'level': 'year', 'value': '2026'},
            {'level': 'month', 'value': '8'},
            {'level': 'day', 'value': '31'},
            {'level': 'hour', 'value': '11'},
            {'level': 'minute', 'value': '30'},
          ],
        })).toJson(),
        ],
      },
    ),
  );
  return (document: document, frame: frame, object: 'event:lunch');
}

Future<void> pumpObject(WidgetTester tester, CardBench bench, String id) => pumpHosted(
  tester,
  bench,
  ObjectCard(
    request: (klass: 'object', id: id, kind: null, frameId: null, startDays: null, endDays: null),
  ),
  id: id,
  shell: true,
);

void main() {
  late CardBench bench;

  testWidgets('the noun dropdown stays: the kind is a click on the word', (tester) async {
    final world = placed();
    bench = await openCards(world.document);
    await pumpObject(tester, bench, world.object);
    // Every kind the catalog knows is offered, by its own label.
    await tapText(tester, objectKinds['event']!.label);
    for (final definition in objectKinds.values) {
      expect(find.text(definition.label), findsWidgets, reason: 'the noun offers every kind');
    }
    await tapText(tester, objectKinds['todo']!.label);
    expect(objectKindForEvent(bench.editor.document.events[world.object]), 'todo');
  });

  testWidgets('region one is the properties, in the open: name, description, color, location', (
    tester,
  ) async {
    final world = placed();
    bench = await openCards(world.document);
    await pumpObject(tester, bench, world.object);
    // No fold. "The card is TWO regions of authored sentences, nothing else."
    expect(
      find.textContaining('Everything else'),
      findsNothing,
      reason:
          'ISSUES (8.31): the ruled card is TWO REGIONS — properties, a rule, '
          'staples — and nothing else; the one fold hides the basics.',
    );
    for (final basic in const ['Description', 'Location']) {
      expect(
        find.text(basic),
        findsOneWidget,
        reason: 'ISSUES (8.31): "start with the basics" — $basic is behind the fold.',
      );
    }
    expect(
      find.textContaining(RegExp('Colou?r')),
      findsWidgets,
      reason: 'ISSUES (8.31): colour is one of the basics the properties region starts with.',
    );
  });

  testWidgets('the properties region carries a + that adds a property', (tester) async {
    final world = placed();
    bench = await openCards(world.document);
    await pumpObject(tester, bench, world.object);
    expect(
      find.text('+'),
      findsWidgets,
      reason:
          'ISSUES (8.31): "*EVENT* \$name *DESCRIPTION* \$description *+* … add '
          'properties at will via the +" — there is no + on the card.',
    );
  });

  testWidgets('the standalone frame section dies: a frame connection is a staple', (tester) async {
    final world = placed();
    bench = await openCards(world.document);
    await pumpObject(tester, bench, world.object);
    for (final section in const ['Frames', 'Groups']) {
      expect(
        find.text(section),
        findsNothing,
        reason:
            'ISSUES (8.31): "Frame connection is PART of the staple, not a separate '
            'control — membership is a staple; the standalone frame section dies." '
            'The card still draws a "$section" section of its own.',
      );
    }
    // And what replaces it is a sentence: the placement reads as one.
    // The frame's authored title, spelled the way the document spells it.
    expect(find.textContaining('Wall time'), findsWidgets, reason: 'the frame is named in a staple');
  });

  testWidgets('typing a frame name that does not exist offers to create it', (tester) async {
    final world = placed();
    bench = await openCards(world.document);
    await pumpObject(tester, bench, world.object);
    final far = fieldHinted('Connect to a frame or an object');
    expect(far, findsWidgets, reason: 'the staple names its far end through a find box');
    await tester.enterText(far.first, 'Rehearsals');
    await tester.pumpAndSettle();
    final offer = find.textContaining(RegExp('[Cc]reate'));
    expect(
      offer,
      findsWidgets,
      reason:
          'ISSUES (8.31): "Typing a frame name that does not exist offers to '
          'instantiate it, opening a second card to set that frame up" — the picker '
          'only reports that nothing is called that.',
    );
    await tester.tap(offer.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      bench.factory.stage.tiles.keys.where((id) => id.startsWith('card:frame:')),
      isNotEmpty,
      reason: 'the offer opens that frame\'s own card',
    );
  });

  testWidgets('Delete always; Save / Apply / Discard once changes exist', (tester) async {
    final world = placed();
    bench = await openCards(world.document);
    await pumpObject(tester, bench, world.object);
    expect(find.text('Delete'), findsOneWidget, reason: 'Delete is always offered');
    // Author a change, and the three change verbs appear.
    await tester.enterText(fieldHolding('Lunch').first, 'Lunch with Rob');
    await tester.pump();
    await pumpObject(tester, bench, world.object);
    for (final verb in const ['Save', 'Apply', 'Discard']) {
      expect(
        find.text(verb),
        findsOneWidget,
        reason:
            'ISSUES (8.31): "Buttons: Delete always; when changes exist, Save / '
            'Apply / Discard" — "$verb" is not on the card.',
      );
    }
  });

  testWidgets('one card class serves events, todos and notes', (tester) async {
    final world = placed();
    bench = await openCards(world.document);
    for (final kind in objectKinds.keys) {
      final event = bench.editor.document.events[world.object]!;
      bench.editor.transaction(
        'Change kind',
        (d) => d.put(
          'events',
          world.object,
          event.copyWith(traits: traitsForObjectKind(event.traits, kind)),
        ),
      );
      await pumpObject(tester, bench, world.object);
      expect(find.byType(ObjectCard), findsOneWidget, reason: 'one editor class for $kind');
      expect(tester.takeException(), isNull, reason: '$kind renders');
    }
  });

  testWidgets('closing the card keeps what was authored: the X saves by default', (tester) async {
    final world = placed();
    bench = await openCards(world.document);
    await pumpObject(tester, bench, world.object);
    await tester.enterText(fieldHolding('Lunch').first, 'Lunch with Rob');
    await tester.pump();
    // The card goes away, as the tile closing it does.
    await pumpCard(tester, bench.chrome, const SizedBox.shrink());
    expect(
      str(bench.editor.document.events[world.object]?.payload?['title']),
      'Lunch with Rob',
      reason:
          'ISSUES (8.31): "what the card\'s X does by default is a settings key '
          '(Don\'s instinct: save)".',
    );
  });
}
