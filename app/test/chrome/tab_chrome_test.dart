// TABS ON TILES (ISSUES 8.31, evening, Don live), as amended by ISSUES 9.1.
//
// Three of the four points are shape, not taste, and each one is a claim the
// rendered stage can be asked about:
//
//   "1 tab is not a tab it is just a window" -- a stack with ONE child renders as
//   a plain window with no tab strip; the strip exists only at two or more.
//
//   AMENDED (ISSUES 9.1): the lone window's triple dot does not REST there
//   either, and RULED (9.1) that the pointer finds it in a band down the tile's
//   LEADING EDGE -- hovering the middle of a lens reveals nothing -- while a
//   hand with no pointer long-presses anywhere in the tile for the same handle. "Single tabs have been replaced with a nontab title in the same
//   place, defeating the purpose of removing them... on a single tab the bar
//   DISAPPEARS entirely; the drag point is the triple dot as a HOVER element on
//   the tile's left edge, centered in y." The halves below that pinned a
//   permanent handle were the drift; the strip-at-two-or-more halves stand.
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

import 'package:chronolog/chrome/context_bar.dart';
import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/document_bar.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/chrome/view_bar.dart';
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

/// A tile's own rectangle: its body where the tile has one, the bar it is
/// otherwise. Derived, so nothing here has to know what the preset placed.
Finder tileFinder(String id) {
  final body = find.byKey(ValueKey('body-$id'));
  if (body.evaluate().isNotEmpty) return body;
  return find.byType(switch (id) {
    'bar:document' => DocumentBar,
    'bar:view' => ViewBar,
    _ => ContextBar,
  });
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
  });

  testWidgets('nothing at all rests on a lone window: not a name, not a mark', (tester) async {
    final chrome = await pumpStage(tester);
    expect(tabbedLeaves(chrome), 0, reason: 'every tile here is a window, not a tab');
    // Every tile's own title, from the stage's own record: none may be drawn
    // anywhere while every tile stands alone.
    for (final leaf in chrome.stage.leaves) {
      expect(
        find.text(chrome.stage.tiles[leaf.id]!.title),
        findsNothing,
        reason:
            'ISSUES (9.1): "single tabs have been replaced with a nontab title in the '
            'same place, defeating the purpose of removing them" -- ${leaf.id} still '
            'names itself at rest.',
      );
    }
    expect(
      find.text(handleGlyph),
      findsNothing,
      reason: 'ISSUES (9.1): the triple dot is a HOVER element -- nothing rests.',
    );
  });

  testWidgets('the pointer finds the handle in the leading band, and nowhere else', (
    tester,
  ) async {
    final chrome = await pumpStage(tester);
    final band = chrome.px('stage.handleBand');
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    // EVERY lone tile answers the same way, bars included: the claim is about
    // the class, not about whichever tile the preset happens to put where.
    for (final leaf in chrome.stage.leaves) {
      final body = tester.getRect(tileFinder(leaf.id));
      // The middle of the tile is the tile's own content and nothing else.
      await pointer.moveTo(body.center);
      await tester.pumpAndSettle();
      expect(
        find.text(handleGlyph),
        findsNothing,
        reason:
            'ISSUES (9.1, ruled): the reveal region is the LEFT-EDGE BAND -- hovering '
            'the middle of ${leaf.id} brought the handle out.',
      );
      await pointer.moveTo(Offset(body.left + band / 2, body.center.dy));
      await tester.pumpAndSettle();
      final mark = find.text(handleGlyph);
      expect(
        mark,
        findsOneWidget,
        reason:
            'ISSUES (9.1): the drag point is the triple dot as a hover element -- '
            '${leaf.id} showed none with the pointer in its leading band.',
      );
      final at = tester.getRect(mark);
      expect(
        at.left - body.left,
        lessThan(body.width / 4),
        reason: 'ISSUES (9.1): "on the tile\'s left edge"',
      );
      expect(
        (at.center.dy - body.center.dy).abs(),
        lessThan(at.height),
        reason: 'ISSUES (9.1): "centered in y"',
      );
      await pointer.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(find.text(handleGlyph), findsNothing, reason: 'and it leaves with the pointer');
    }
  });

  testWidgets('a long press anywhere in the tile brings out the same handle', (tester) async {
    final chrome = await pumpStage(tester);
    // RULED (9.1): a hand with no pointer has no hover to find the band with,
    // so the press is its hover -- held anywhere in the tile, answered by the
    // handle in the one place the handle ever lives.
    for (final leaf in chrome.stage.leaves) {
      final body = tester.getRect(tileFinder(leaf.id));
      await tester.longPressAt(body.center);
      await tester.pumpAndSettle();
      final mark = find.text(handleGlyph);
      expect(
        mark,
        findsOneWidget,
        reason:
            'ISSUES (9.1, ruled): long-press anywhere in the tile reveals the handle -- '
            '${leaf.id} answered a held press with nothing.',
      );
      final at = tester.getRect(mark);
      expect(at.left - body.left, lessThan(body.width / 4), reason: 'in the one place');
      expect((at.center.dy - body.center.dy).abs(), lessThan(at.height), reason: 'centred in y');
      // The next press puts it away: a touch surface has no "leave" but this.
      await tester.tapAt(body.center);
      await tester.pumpAndSettle();
      expect(find.text(handleGlyph), findsNothing, reason: 'and a press puts it away again');
    }
  });

  testWidgets('the revealed handle carries the same verbs the strip does', (tester) async {
    final chrome = await pumpStage(tester);
    final minimap = chrome.stage.leaves.firstWhere((leaf) => leaf.type == 'minimap');
    final band = chrome.px('stage.handleBand');
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    final body = tester.getRect(tileFinder(minimap.id));
    await pointer.moveTo(Offset(body.left + band / 2, body.center.dy));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.text(handleGlyph)),
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    for (final verb in const ['Zoom', 'Close']) {
      expect(
        find.textContaining(verb),
        findsWidgets,
        reason:
            'ISSUES (9.1): "same verbs behind it -- right-click menu, drag, drop" -- '
            '"$verb" was not offered on the revealed handle.',
      );
    }
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
