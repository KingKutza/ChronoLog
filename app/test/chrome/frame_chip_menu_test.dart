// A FRAME'S VERBS ARE WHERE THE FRAME IS NAMED (ISSUES 9.2, Don).
//
// "I don't see an expression field when I right-click on a frame in the context
// bar." Verified in ISSUES: the Expression field lives in the view bar's
// Projection drop, and the frame's name in the chrome has no right-click at all
// -- and, as read for this file, the context bar names no frame today at all
// (`context_bar.dart` renders the lens's declared controls and the steps); the
// one place a bar NAMES a projected frame is the Projection drop's own reading
// on the view bar. Don's instinct is the ruling: "the moment you are looking at
// a frame is the moment its verbs should be at hand."
//
// THE CONTRACT this file names: right-click on a frame WHEREVER the chrome names
// it -- the projection reading on the view bar, the frame's name in the open
// projection drop, a frame chip anywhere -- opens ONE set of rows for THAT
// frame, the same rows the projection drop offers it:
//
//   in / NOT / off  -- the three-state of the frame on this view's projection
//                      (ISSUES 9.2: "each frame row in the drop is three-state
//                      -- in / NOT / off -- and writes the expression"), the
//                      NOT written through `view.negated`, the row that names
//                      it saying "not";
//   open its card   -- the row says "open" and names the frame;
//   its settings    -- the same `settingsRows` every surface's menu carries,
//                      named for the frame;
//   the expression  -- a row that reaches the one-math Expression field over
//                      the view's projection.
//
// One menu source: `List<MenuRow> frameMenu(BuildContext context, ViewState
// view, String frameId)` in `lib/chrome/`, wired as the `onMenu` of every chip
// and link that names a frame -- never a second list per surface. The words are
// asserted by regular expression on what a person reads, never by exact label,
// so the wording is the implementer's. The frame's title is generated from the
// seed so nothing here is a golden string; set CHRONOLOG_SEED to reproduce.
//
// UNWRITTEN, needing a ruling: what a right-click on a reading that joins
// SEVERAL frames ("A or B or C") should offer -- rows per frame, or the drop
// itself. This file projects one frame and asks nothing about the joined case.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/records.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import '../stage/handle_menu_test.dart' show StageBench, pumpStage;

/// The run's seed: `CHRONOLOG_SEED` when set, else the clock; every reason
/// below names it.
final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

/// A title that is its own identifier in the one math (letters only), so the
/// projection reading shows the title itself rather than a slug of it.
String randomTitle(Random random) {
  const letters = 'abcdefghijklmnopqrstuvwxyz';
  return 'F${[for (var i = 0; i < 6; i += 1) letters[random.nextInt(letters.length)]].join()}';
}

/// The stage over a document holding one calendar frame titled [title], with
/// that frame projected on view:1 so the chrome names it.
Future<(StageBench, String)> pumpProjecting(WidgetTester tester, String title) async {
  const id = 'frame:under-test';
  final document = createEmptyWorkspaceDocument().put(
    'frames',
    id,
    Frame(
      id: id,
      title: title,
      traits: const ['set', 'calendar'],
      extra: const {'basis': 'frame:wall-time'},
    ),
  );
  final bench = await pumpStage(tester, document: document);
  final view = bench.chrome.views.of('view:1');
  view.selection.toggle(id);
  bench.chrome.views.touch();
  await tester.pumpAndSettle();
  return (bench, id);
}

/// A right-click at the centre of [target].
Future<void> rightClick(WidgetTester tester, Finder target) async {
  final gesture = await tester.startGesture(
    tester.getCenter(target),
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

/// The words a frame's menu must carry, by what a person reads.
Map<String, RegExp> frameRowWords(String title) => {
  'NOT (the three-state: in / NOT / off)': RegExp(r'\bnot\b', caseSensitive: false),
  'open its card': RegExp('\\bopen\\b.*$title|$title.*\\bopen\\b', caseSensitive: false),
  'its settings, named for the frame': RegExp(
    '$title.*\\bsettings\\b|\\bsettings\\b.*$title',
    caseSensitive: false,
  ),
  'the expression field': RegExp(r'\bexpression\b', caseSensitive: false),
};

/// How many widgets already say each word BEFORE the right-click. The open
/// drop's own row draws a "not" link of its own, and a menu that adds nothing
/// must not pass on the strength of what was already there.
Map<String, int> countRowWords(String title) => {
  for (final entry in frameRowWords(title).entries)
    entry.key: find.textContaining(entry.value).evaluate().length,
};

/// Every word gained at least one widget: the right-click ADDED the rows.
void expectFrameRows(String title, String where, Map<String, int> before) {
  for (final entry in frameRowWords(title).entries) {
    expect(
      find.textContaining(entry.value).evaluate().length,
      greaterThan(before[entry.key] ?? 0),
      reason:
          'seed $runSeed: ISSUES 9.2 -- right-click on "$title" $where offered no row for '
          '${entry.key}. The frame\'s verbs live where the frame is named.',
    );
  }
}

void main() {
  testWidgets('right-click on the frame the view bar names opens that frame\'s verbs', (
    tester,
  ) async {
    final title = randomTitle(Random(runSeed));
    final (bench, _) = await pumpProjecting(tester, title);
    final named = find.descendant(of: find.byType(BarRun), matching: find.text(title));
    expect(
      named,
      findsWidgets,
      reason: 'seed $runSeed: a bar names the projected frame "$title" (the projection reading)',
    );
    final before = countRowWords(title);
    await rightClick(tester, named.first);
    expectFrameRows(title, 'in the view bar\'s projection reading', before);
    // The one row that opens a settings card is a door, not a dead label.
    expect(bench.chrome.views.of('view:1').selection.isSelected('frame:under-test'), isTrue);
  });

  testWidgets('the frame\'s name inside the open projection drop right-clicks to the same rows', (
    tester,
  ) async {
    final title = randomTitle(Random(runSeed + 1));
    final (_, _) = await pumpProjecting(tester, title);
    final reading = find.descendant(of: find.byType(BarRun), matching: find.text(title));
    expect(reading, findsWidgets, reason: 'seed $runSeed: the reading names "$title"');
    await tester.tap(reading.first);
    await tester.pumpAndSettle();
    // Open, the drop shows the frame's own row; its name there is the chip.
    final inDrop = find.text(title);
    expect(
      inDrop,
      findsAtLeastNWidgets(2),
      reason: 'seed $runSeed: the open drop lists "$title" as a row beside the reading',
    );
    final before = countRowWords(title);
    await rightClick(tester, inDrop.last);
    expectFrameRows(title, 'on its row in the open projection drop', before);
  });

  testWidgets('the NOT row writes the projection: the frame is negated, and the reading says so', (
    tester,
  ) async {
    // "the 8.26 ruling ('filters authored as NOT') has the algebra and no hand."
    // The hand is the row; what it writes is the view's own `negated` set, and
    // the reading on the bar restates it -- the same thing in math.
    final title = randomTitle(Random(runSeed + 2));
    final (bench, id) = await pumpProjecting(tester, title);
    final view = bench.chrome.views.of('view:1');
    expect(view.negated, isNot(contains(id)), reason: 'in, not NOT, to start');
    final named = find.descendant(of: find.byType(BarRun), matching: find.text(title));
    expect(named, findsWidgets, reason: 'seed $runSeed: the bar names "$title"');
    final notWord = RegExp(r'\bnot\b', caseSensitive: false);
    final already = find.textContaining(notWord).evaluate().length;
    await rightClick(tester, named.first);
    final notRow = find.textContaining(notWord);
    expect(
      notRow.evaluate().length,
      greaterThan(already),
      reason: 'seed $runSeed: ISSUES 9.2 -- no NOT row on the frame\'s right-click',
    );
    // The row the right-click added is the newest one on the surface.
    await tester.tap(notRow.last);
    await tester.pumpAndSettle();
    expect(
      view.negated,
      contains(id),
      reason: 'seed $runSeed: the NOT row did not negate "$title" on this view\'s projection',
    );
    expect(
      find.descendant(
        of: find.byType(BarRun),
        matching: find.textContaining(RegExp('not\\s+$title', caseSensitive: false)),
      ),
      findsWidgets,
      reason: 'seed $runSeed: the reading on the bar restates the NOT in the one math',
    );
  });
}
