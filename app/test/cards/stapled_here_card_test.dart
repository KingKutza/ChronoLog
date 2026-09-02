// THE FRAME CARD'S "STAPLED HERE" ROW SHOWS THE WHOLE PILE (ISSUES 9.2, Don).
//
// "The frame for PTP shows nothing stapled here when there are two events. And
// frames with a lot of events are overflowing rather than showing staples.
// Perhaps a list of stapled items by type."
//
// The pure claim -- a neighbourhood query on the graph, grouped by the catalog --
// is in `test/core/stapled_here_test.dart`. This file asks the CARD as rendered:
// two objects stapled to the group PTP read under "Stapled here"; an era's
// predecessor frame reads there; a frame holding more members than the window
// says its true count and offers a door to the whole list rather than the
// dead-end "+N more."; and a frame holding hundreds reads as counts by kind with
// a way in, without the card standing up hundreds of rows. "If it is not usable
// at 500 calendars it is improperly built for 3."
//
// The door's WORDING is not pinned. What is pinned: the count is on the card,
// the truncation note is not, and one tap from the row opens a tile.

import 'dart:math';

import 'package:chronolog/cards/frame_card.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/object_kinds.dart';
import 'package:chronolog/core/records.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import '../helpers/projection_scene.dart';
import '../helpers/staple_world.dart' as staple_world;
import 'object_harness.dart';

/// The row itself: the nearest `cardRow` around the label, so "under Stapled
/// here" is a place on the card and not a guess about wording elsewhere.
Finder stapledHereRow() =>
    find.ancestor(of: find.text('Stapled here'), matching: find.byType(LayoutBuilder)).first;

Finder inRow(Finder matching) => find.descendant(of: stapledHereRow(), matching: matching);

Future<void> pumpFrame(WidgetTester tester, CardBench bench, String frameId) => pumpHosted(
  tester,
  bench,
  FrameCard(frameId: frameId),
  klass: 'frame',
  id: frameId,
  shell: true,
);

void main() {
  testWidgets('two objects stapled to a group read under "Stapled here"', (tester) async {
    // Don's PTP: a group, two members, "nothing stapled here". The staple landed;
    // the surface that should prove it looked at the placement index.
    final scene = Scene()..group('frame:ptp', const []);
    final first = scene.object(title: 'Reggie follow-up');
    final second = scene.object(title: 'Ledger reconcile');
    scene.join('frame:ptp', first);
    // The second is said as an anchor to the frame with no coordinate: a staple
    // to the group by another word, still a staple to the group.
    scene.staple(
      kind: 'anchor',
      ends: [ObjectEnd(second, point: 'start'), StapleEnd.frame('frame:ptp')],
    );
    final bench = await openCards(scene.document);
    await pumpFrame(tester, bench, 'frame:ptp');
    expect(
      inRow(find.text('Nothing is stapled here yet.')),
      findsNothing,
      reason:
          'ISSUES 9.2: two objects are stapled to PTP and the row says nothing is -- it asked '
          '`framesOf`, the PLACEMENT index, and a staple to a group carries no coordinate.',
    );
    for (final title in const ['Reggie follow-up', 'Ledger reconcile']) {
      expect(inRow(find.text(title)), findsOneWidget, reason: '$title is stapled here');
    }
  });

  testWidgets('a frame stapled to a frame reads under "Stapled here"', (tester) async {
    // Eras are frames stapled together. The successor's card names its
    // predecessor, or the region cannot show an era's own neighbours.
    final world = staple_world.World();
    world.era('era:first', key: '1E', name: 'The Dawn Era', years: '300');
    world.era('era:second', key: '2E', name: 'The Second Era', after: 'era:first');
    final bench = await openCards(world.document);
    await pumpFrame(tester, bench, 'era:second');
    expect(
      inRow(find.text('The Dawn Era')),
      findsOneWidget,
      reason:
          'ISSUES 9.2: `_stapledHere` iterates `document.events` alone; the succession staple '
          'joining these two frames is invisible to it.',
    );
  });

  for (final seed in seeds(3)) {
    testWidgets('more members than the window: the true count is on the card, the truncation '
        'note is not, and a door opens the whole list (seed $seed)', (tester) async {
      final random = Random(seed);
      final window = chronologSettings().value('card.searchWindow').round().toInt();
      final count = window + 1 + random.nextInt(window * 2);
      final scene = Scene()..group('frame:ptp', const []);
      for (var index = 0; index < count; index += 1) {
        scene.join('frame:ptp', scene.object(title: 'Member $index'));
      }
      final full = await openCards(scene.document);
      await pumpFrame(tester, full, 'frame:ptp');

      expect(
        inRow(find.textContaining(RegExp(r'\+\d+ more'))),
        findsNothing,
        reason: 'ISSUES 9.2: "+N more." is a dead end -- no way to reach the rest.',
      );
      expect(
        inRow(find.textContaining('$count')),
        findsWidgets,
        reason: 'the group says its TRUE total, however few it lists',
      );
      // A door: one tap inside the row opens a tile that was not open before --
      // and not a MEMBER's own card, which every listed name already opens and
      // which is not a way into the rest.
      final tilesBefore = full.factory.stage.tiles.keys.toSet();
      final memberCards = {
        for (final id in scene.document.events.keys) 'card:object:$id',
      };
      final doors = inRow(find.byType(InkWell));
      expect(doors, findsWidgets, reason: 'the row offers a way into the whole list');
      var opened = false;
      for (final element in doors.evaluate()) {
        await tester.tap(find.byElementPredicate((it) => it == element), warnIfMissed: false);
        await tester.pumpAndSettle();
        final newTiles = full.factory.stage.tiles.keys.toSet().difference(tilesBefore);
        if (newTiles.difference(memberCards).isNotEmpty) {
          opened = true;
          break;
        }
      }
      expect(
        opened,
        isTrue,
        reason:
            'ISSUES 9.2: "each group ... shows its own window with a door to the full list -- '
            'the All frames door is the pattern already on this card". Nothing in the row '
            'opened a tile.',
      );
    });
  }

  testWidgets('a frame holding hundreds reads as counts by kind with a way in, and the card '
      'does not stand up hundreds of rows', (tester) async {
    final random = Random(specSeed);
    final scene = Scene()..group('frame:ptp', const []);
    final counts = <String, int>{};
    const members = 600;
    for (var index = 0; index < members; index += 1) {
      final kind = objectKinds.keys.elementAt(random.nextInt(objectKinds.length));
      final id = scene.object(title: 'Member $index');
      scene.document = scene.document.put(
        'events',
        id,
        scene.document.events[id]!.copyWith(traits: objectKinds[kind]!.traits),
      );
      scene.join('frame:ptp', id);
      counts[kind] = (counts[kind] ?? 0) + 1;
    }
    final bench = await openCards(scene.document);
    final window = bench.settings.value('card.searchWindow').round().toInt();
    await pumpFrame(tester, bench, 'frame:ptp');
    expect(tester.takeException(), isNull);

    for (final entry in counts.entries) {
      expect(
        inRow(find.textContaining('${entry.value}')),
        findsWidgets,
        reason:
            'ISSUES 9.2: "a frame holding five hundred objects reads as counts by kind with a '
            'way in, never as a truncation" -- the ${entry.key} count ${entry.value} is not on '
            'the card.',
      );
    }
    final listed = inRow(find.textContaining('Member ')).evaluate().length;
    expect(
      listed,
      lessThanOrEqualTo(window * objectKinds.length),
      reason: 'each kind lists at most one window; the rest is a count and a door',
    );
    expect(listed, greaterThan(0), reason: 'and each kind shows a window into itself');
  });
}
