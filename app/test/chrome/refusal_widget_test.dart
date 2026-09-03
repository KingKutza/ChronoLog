// A REFUSAL IS A THING YOU CAN TOUCH (ISSUES 9.2, Don).
//
// "Double-clicking an error message should copy it to the clipboard; right now
// I have no way to interact with them." Lens-top refusals were painted text
// with no hit region; card refusals were plain Texts. One class: every refusal
// is one widget with the same verbs -- click selects, double-click copies (text
// plus source), right-click offers Copy / Copy all / Dismiss; hover shows the
// full text when a banner truncated it. "Red light: every refusal surface in
// the registry answers a double-click with a clipboard write of its own text."
//
// The clipboard is `Clipboard` from flutter/services (no plugin), reached
// through the platform channel, so the spec listens on that channel. The card
// half landed; the LENS-TOP half is still painted text, and the second case is
// the light for it.

import 'dart:math';

import 'package:chronolog/app.dart';
import 'package:chronolog/cards/card_chrome.dart';
import 'package:chronolog/cards/object_card.dart';
import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/lens/view_tile.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:chronolog/store/document_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../cards/harness.dart';
import '../cards/object_harness.dart';
import '../core/corpus.dart';
import '../store/harness.dart';

/// Every text handed to the platform clipboard while the case ran.
List<String> listenToClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied.add('${(call.arguments as Map)['text']}');
    }
    return null;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return copied;
}

Future<void> doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump(kDoubleTapMinTime);
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump();
  await tester.pumpAndSettle();
}

/// Words a refusal might carry, seeded, so the clipboard is checked against text
/// the case invented rather than a sentence someone might rephrase.
String sentence(Random random) => [
  for (var index = 0; index < 4 + random.nextInt(9); index += 1)
    ['frame', 'names', 'no', 'level', 'the', 'law', 'declares', 'refused', 'here'][random.nextInt(9)],
].join(' ');

void main() {
  for (final seed in seeds(3)) {
    testWidgets('a refusal answers a double-click with a clipboard write of its text and source '
        '(seed $seed)', (tester) async {
      final random = Random(seed);
      final text = sentence(random);
      final source = 'Frame ${random.nextInt(100)}';
      final copied = listenToClipboard(tester);
      await pumpCard(tester, cardChrome(null), Refusal(text: text, source: source));
      await doubleTap(tester, find.byType(Refusal));
      expect(copied, hasLength(1), reason: 'ISSUES 9.2: a double-click is one clipboard write');
      expect(copied.single, contains(text), reason: 'the refusal\'s own text');
      expect(copied.single, contains(source), reason: 'with what it is about');
    });
  }

  testWidgets('a card\'s refusal note is the one class', (tester) async {
    // "All 14 `cardNote(refusal: true)` sites across 8 card files became
    // interactive through one call." A card asked to open a record that is not
    // in the document refuses -- and that refusal is a Refusal.
    final bench = (await tester.runAsync(() => openCards(createEmptyWorkspaceDocument())))!;
    await pumpHosted(
      tester,
      bench,
      const ObjectCard(
        request: (klass: 'object', id: 'event:gone', kind: null, frameId: null, startDays: null, endDays: null),
      ),
      id: 'event:gone',
      shell: true,
    );
    expect(
      find.byType(Refusal),
      findsWidgets,
      reason: 'ISSUES 9.2: a card refusal is the one interactive class, never a plain Text',
    );
  });

  testWidgets('a lens-top refusal is the one class too, and copies on a double-click', (
    tester,
  ) async {
    // "Still open: the LENS-TOP refusals are painted text (`paintRefusals` in
    // `lens_painter.dart`, `statedRefusal` in `view_tile.dart`) and are not yet
    // covered." A view tile over a frame whose declaration cannot be resolved
    // shows a stated refusal; it is a Refusal, and it copies.
    registerShippedLenses();
    final copied = listenToClipboard(tester);
    final store = DocumentStore(
      dataRoot: 'memory',
      files: MemoryFiles(),
      scheduler: ManualScheduler(),
      establish: () => createEmptyWorkspaceDocument().put(
        'frames',
        'frame:stranded',
        const Frame(
          id: 'frame:stranded',
          title: 'Stranded',
          traits: ['set', 'calendar'],
          extra: {'basis': 'frame:nothing-wears-this'},
        ),
      ),
    );
    await tester.runAsync(store.load);
    final settings = chronologSettings();
    final editor = Editor(store, settings: settings.tunable);
    final views = ViewBook()..defaultFrames = ['frame:stranded'];
    views.of('view:1').lensId = 'intimate';
    final stage = Stage(tunable: settings.tunable, onLens: views.setLens);
    final tile = ViewTile(
      tileId: 'view:1',
      surface: (
        editor: editor,
        settings: settings,
        views: views,
        stage: stage,
        objectCard: null,
        frameCard: null,
        settingsCard: null,
      ),
    );
    stage.open(TileSpec(id: 'view:1', type: 'view', klass: 'lens', title: 'View', build: (_) => tile));
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: themeDataFor(shipped['paper']!),
        home: Scaffold(
          body: ChromeScope(
            chrome: Chrome(settings: settings, stage: stage, views: views, editor: editor),
            child: SizedBox(width: 1000, height: 600, child: tile),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final refusal = find.byType(Refusal);
    expect(
      refusal,
      findsWidgets,
      reason:
          'ISSUES 9.2: the lens-top refusal is painted text with no hit region. Every refusal '
          'surface is the one class.',
    );
    await doubleTap(tester, refusal.first);
    expect(copied, isNotEmpty, reason: 'and it copies its own text on a double-click');
  });
}
