// THE CARD'S OWN CONTRACT (ISSUES 9.1, Don's morning test): three reports,
// three claims a pumped card can be asked about.
//
// "Clicking the x in the top left of a frame window does not close it" — the
// shell's fallback CardHost carries tileId '' and the factory builds bodies
// with the OUTER context, so the card's × calls `stage.close('')` and removes
// nothing. The claim: a card's close closes ITS OWN tile, whatever host
// topology it was built under.
//
// "I know I opened new frame and named and colored it… I don't see it in the
// frames drop" — the journal holds no `New frame` transaction: the draft died
// with the card, silently. The claim: a named draft never dies silently — the
// close verb writes it, exactly as the object card's `card.closeVerb` contract
// already promises.
//
// The screenshot walk: a disabled menu stamps its ONE refusal onto every row
// and drowns the labels. The claim: the refusal is the menu's one sentence.

import 'package:chronolog/cards/card_chrome.dart';
import 'package:chronolog/cards/card_factory.dart';
import 'package:chronolog/cards/frame_card.dart';
import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:chronolog/store/document_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../store/harness.dart';
import 'harness.dart';

typedef Bench = ({Editor editor, CardFactory factory, Chrome chrome});

Future<Bench> bench() async {
  final store = DocumentStore(
    dataRoot: 'memory',
    files: MemoryFiles(),
    scheduler: ManualScheduler(),
    establish: () => createEmptyWorkspaceDocument().put(
      'frames',
      'frame:work',
      const Frame(id: 'frame:work', title: 'Work', traits: ['set', 'calendar']),
    ),
  );
  await store.load();
  final settings = chronologSettings();
  final editor = Editor(store, settings: settings.tunable);
  final views = ViewBook();
  final stage = Stage(tunable: settings.tunable, onLens: views.setLens);
  final factory = CardFactory(editor, settings, stage, bodies: frameCardBodies);
  return (
    editor: editor,
    factory: factory,
    chrome: Chrome(settings: settings, stage: stage, views: views, editor: editor),
  );
}

const CardRequest _shellRequest = (
  klass: '',
  id: null,
  kind: null,
  frameId: null,
  startDays: null,
  endDays: null,
);

/// The exact topology the shell provides: the fallback host above, the card's
/// own spec built with the surrounding context — the shape the defect lives in.
Future<void> pumpSpec(WidgetTester tester, Bench probe, TileSpec spec) => pumpCard(
  tester,
  probe.chrome,
  CardHost(
    factory: probe.factory,
    request: _shellRequest,
    tileId: '',
    child: SizedBox(
      height: cardSurface.height,
      child: Builder(builder: (context) => spec.build(context)),
    ),
  ),
);

void main() {
  testWidgets('the frame card\'s × closes the frame card\'s own tile', (tester) async {
    final probe = await bench();
    final spec = probe.factory.frameCard('frame:work');
    probe.chrome.stage.open(spec);
    await pumpSpec(tester, probe, spec);
    expect(probe.chrome.stage.tiles.containsKey(spec.id), isTrue);
    await tester.tap(find.bySemanticsLabel('Close').first, warnIfMissed: false);
    await tester.pump();
    expect(
      probe.chrome.stage.tiles.containsKey(spec.id),
      isFalse,
      reason:
          'ISSUES (9.1): the × resolves the shell\'s fallback host (tileId "") and calls '
          'stage.close("") — the card stays. A card\'s close closes its OWN tile.',
    );
  });

  testWidgets('a named frame draft never dies silently', (tester) async {
    final probe = await bench();
    final spec = probe.factory.newFrameCard();
    probe.chrome.stage.open(spec);
    await pumpSpec(tester, probe, spec);
    await tester.enterText(fieldHinted('What this frame is called').first, 'Steves Project');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Close').first, warnIfMissed: false);
    await tester.pump();
    expect(
      probe.editor.document.frames.values.any((frame) => frame.title == 'Steves Project'),
      isTrue,
      reason:
          'ISSUES (9.1): Don named and colored a frame and the journal holds no New frame '
          'transaction — the draft died with the card. The close verb writes a named draft '
          '(card.closeVerb, the contract the object card already keeps), or refuses in words.',
    );
  });

  testWidgets('a disabled menu says its refusal ONCE, not per row', (tester) async {
    final probe = await bench();
    await pumpCard(
      tester,
      probe.chrome,
      Builder(
        builder: (context) => cardMenu(
          context,
          'a',
          const {'a': 'Alpha', 'b': 'Beta', 'c': 'Gamma'},
          null,
          hint: 'The implicit placement has no kind to change.',
        ),
      ),
    );
    await tester.tap(find.text('Alpha').first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('The implicit placement has no kind to change.'),
      findsOneWidget,
      reason:
          'ISSUES (9.1): the one refusal is stamped onto every row, drowning the labels '
          'and overflowing the menu width. A refusal is the MENU\'s one sentence.',
    );
  });
}
