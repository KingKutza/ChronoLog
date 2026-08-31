// TABS ON TILES (ISSUES 8.31, evening, Don live).
//
// Three of the four points are shape, not taste, and each one is a claim the
// rendered stage can be asked about:
//
//   "1 tab is not a tab it is just a window" -- a stack with ONE child renders as
//   a plain window with no tab strip; the strip exists only at two or more, and
//   the lone window carries its triple-dot control instead.
//
//   "Bigger x on the tabs" -- the close target is a hit target, sized for
//   fingers-and-haste rather than pixel-hunting, and settings-keyed like every
//   other number the chrome draws with.
//
//   Right-click on a tab (and on the lone window's chrome) opens the context
//   menu with the tab verbs -- one menu source, not per-surface wiring.
//
// The fourth point ("just more aesthetic tabs") is the look pass's business and
// is not asserted here: a golden would pin taste, and taste is Don's.

import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/layout_tree.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Size _surface = Size(1600, 1000);

/// The close glyph the strip draws, and the handle glyph a bar wears. Read from
/// nowhere: they are the two marks the stage paints, and what this spec is about
/// is WHICH tiles wear them.
const String closeGlyph = '×', handleGlyph = '⋮';

TileSpec _body(String id, String type, String klass, String title) => TileSpec(
  id: id,
  type: type,
  klass: klass,
  title: title,
  build: (context) => SizedBox.expand(key: ValueKey('body-$id')),
);

Future<Chrome> pumpStage(WidgetTester tester) async {
  tester.view.physicalSize = _surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = chronologSettings();
  final views = ViewBook();
  final stage = Stage(tunable: settings.tunable, onLens: views.setLens);
  final chrome = Chrome(
    settings: settings,
    stage: stage,
    views: views,
    viewTile: (id) => _body(id, 'view', 'lens', 'View'),
  );
  installDefaultStage(chrome, minimap: (id) => _body(id, 'minimap', 'field', 'Minimap'));
  await tester.pumpWidget(MaterialApp(home: ChronoSurface(chrome: chrome)));
  await tester.pump();
  return chrome;
}

/// How many of the stage's leaves sit in a TAB STACK -- a `tabs` branch holding
/// two or more children. Derived from the tree, never counted by hand, so the
/// expectation follows whatever arrangement the preset ships.
int tabbedLeaves(Chrome chrome) {
  var found = 0;
  for (final leaf in chrome.stage.leaves) {
    final parent = parentOf(chrome.stage.displayRoot, leaf.id);
    if (parent?.mode == 'tabs' && parent!.children.length > 1) found += 1;
  }
  return found;
}

void main() {
  testWidgets('a stack with ONE child is just a window: no tab strip on it', (tester) async {
    final chrome = await pumpStage(tester);
    expect(chrome.stage.leaves.length, greaterThan(1), reason: 'the preset opened its tiles');
    expect(tabbedLeaves(chrome), 0, reason: 'the shipped preset stacks nothing');
    expect(
      find.text(closeGlyph),
      findsNWidgets(tabbedLeaves(chrome)),
      reason:
          'ISSUES (8.31, evening): "1 tab is not a tab it is just a window" — a lone '
          'tile wears a tab strip with its own close, and the strip is supposed to '
          'exist only at two or more.',
    );
    // And the lone window is not left with no handle at all: it carries the
    // triple-dot control every other lone tile does.
    expect(
      find.text(handleGlyph),
      findsNWidgets(chrome.stage.leaves.length - tabbedLeaves(chrome)),
      reason: 'every lone window carries its triple-dot control',
    );
  });

  testWidgets('two tiles in ONE stack do wear a tab strip, one close each', (tester) async {
    final chrome = await pumpStage(tester);
    final lens = chrome.stage.leaves.firstWhere((leaf) => leaf.type == 'view');
    final minimap = chrome.stage.leaves.firstWhere((leaf) => leaf.type == 'minimap');
    chrome.stage.tabUnder(minimap.id, lens.id);
    await tester.pumpAndSettle();
    expect(tabbedLeaves(chrome), 2, reason: 'the two are one stack now');
    expect(find.text(closeGlyph), findsNWidgets(2), reason: 'a tab each, a close each');
  });

  testWidgets('the tab close target is a hit target, not a glyph to hunt for', (tester) async {
    final chrome = await pumpStage(tester);
    final lens = chrome.stage.leaves.firstWhere((leaf) => leaf.type == 'view');
    final minimap = chrome.stage.leaves.firstWhere((leaf) => leaf.type == 'minimap');
    chrome.stage.tabUnder(minimap.id, lens.id);
    await tester.pumpAndSettle();
    // A comfortable target, in the app's OWN vocabulary: `chrome.rowHeight` is
    // the size the menus already give a thing meant to be hit without aiming.
    // Don named no pixel count -- "sized for fingers-and-haste, not
    // pixel-hunting" -- so the floor is the comfortable size already shipped
    // rather than a number invented here.
    final comfortable = chrome.px('chrome.rowHeight');
    for (final close in find.text(closeGlyph).evaluate()) {
      final box = tester.getRect(find.byWidget(close.widget));
      expect(
        box.shortestSide,
        greaterThanOrEqualTo(comfortable),
        reason:
            'ISSUES (8.31, evening): "Bigger x on the tabs" — the close target '
            'measures ${box.width.toStringAsFixed(1)}x${box.height.toStringAsFixed(1)}, '
            'under the comfortable ${comfortable.toStringAsFixed(0)} the chrome '
            'already ships for a hit target.',
      );
    }
  });

  testWidgets('right-click on a tab opens the tab verbs', (tester) async {
    final chrome = await pumpStage(tester);
    final lens = chrome.stage.leaves.firstWhere((leaf) => leaf.type == 'view');
    final minimap = chrome.stage.leaves.firstWhere((leaf) => leaf.type == 'minimap');
    chrome.stage.tabUnder(minimap.id, lens.id);
    await tester.pumpAndSettle();
    final tab = find.text('Minimap');
    expect(tab, findsWidgets, reason: 'the tab names its tile');
    final gesture = await tester.startGesture(
      tester.getCenter(tab.first),
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    // The verbs that already exist on keys and drags, in one menu: closing,
    // splitting out, zooming.
    for (final verb in const ['Zoom', 'Close']) {
      expect(
        find.textContaining(verb),
        findsWidgets,
        reason:
            'ISSUES (8.31, evening): right-click on a tab opens the context menu '
            'with the tab verbs — "$verb" was not offered.',
      );
    }
  });
}
