// The surface, as rendered. These re-express the dock rulings as widget tests
// before the chrome that replaced the dock is trusted: no floating windows, no
// overlap, one stack, and no confirmation dialog anywhere.

import 'package:chronolog/chrome/context_bar.dart';
import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/document_bar.dart';
import 'package:chronolog/chrome/keyboard.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/chrome/view_bar.dart';
import 'package:chronolog/session/lens_catalog.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/layout_tree.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:chronolog/stage/stage_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const Size _surface = Size(1600, 1000);

TileSpec _body(String id, String type, String klass, String title) => TileSpec(
  id: id,
  type: type,
  klass: klass,
  title: title,
  build: (context) => ColoredBox(
    color: const Color(0x11000000),
    child: SizedBox.expand(key: ValueKey('body-$id')),
  ),
);

Chrome _chrome() {
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
  return chrome;
}

Future<Chrome> _pump(WidgetTester tester) async {
  tester.view.physicalSize = _surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final chrome = _chrome();
  await tester.pumpWidget(MaterialApp(home: ChronoSurface(chrome: chrome)));
  await tester.pump();
  return chrome;
}

void main() {
  testWidgets('the shipped preset pins each bar to its edge at its own thickness', (tester) async {
    final chrome = await _pump(tester);
    // A bar arrives at its own content thickness -- its shipped share is under
    // that, so the minimum is what it takes -- and it spends nothing on chrome
    // of its own: the grip that used to sit at its leading end is retired
    // (ISSUES 9.1), so a bar is its tile's whole width less its own hairline.
    final height = chrome.px('chrome.barHeight');
    final full = _surface.width - tileChrome(chrome);
    for (final bar in [DocumentBar, ViewBar, ContextBar]) {
      expect(tester.getSize(find.byType(bar)).width, closeTo(full, 2), reason: '$bar');
      expect(tester.getSize(find.byType(bar)).height, closeTo(height, 1), reason: '$bar');
    }
    final lens = tester.getRect(find.byKey(const ValueKey('body-view:1')));
    final minimap = tester.getRect(find.byKey(const ValueKey('body-minimap:main')));
    expect(minimap.left, greaterThan(lens.right - 1));
    expect(
      minimap.width / (minimap.width + lens.width),
      closeTo(chrome.px('stage.minimapWidth'), 0.02),
    );
  });

  testWidgets('every tile is a rectangle of the stage: none floats, none overlaps', (tester) async {
    final chrome = await _pump(tester);
    final stage = tester.getRect(find.byType(ChronoSurface));
    final rects = [
      for (final leaf in leavesOf(chrome.stage.root))
        tester.getRect(
          find.byKey(ValueKey('body-${leaf.id}')).evaluate().isEmpty
              ? find.byType(switch (leaf.klass) {
                  'documentBar' => DocumentBar,
                  'viewBar' => ViewBar,
                  _ => ContextBar,
                })
              : find.byKey(ValueKey('body-${leaf.id}')),
        ),
    ];
    expect(rects.length, greaterThan(1));
    for (final rect in rects) {
      expect(
        stage.contains(rect.topLeft) && stage.contains(rect.bottomRight - const Offset(1, 1)),
        isTrue,
        reason: 'a tile left the stage',
      );
    }
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        expect(rects[i].intersect(rects[j]).isEmpty, isTrue, reason: 'tiles overlap');
      }
    }
  });

  testWidgets('the view bar swaps the focused tile lens rather than opening another', (
    tester,
  ) async {
    final chrome = await _pump(tester);
    expect(chrome.views.of('view:1').lensId, 'intimate');
    await tester.ensureVisible(find.text('Tactical'));
    await tester.pump();
    await tester.tap(find.text('Tactical'));
    await tester.pump();
    expect(chrome.views.of('view:1').lensId, 'tactical');
    expect(leavesOf(chrome.stage.root).where((leaf) => leaf.type == 'view').length, 1);
  });

  testWidgets('the context bar renders the lens declaration, not a lens branch', (tester) async {
    final chrome = await _pump(tester);
    chrome.views.setLens('view:1', 'tactical');
    await tester.pump();
    expect(find.text('Rows'), findsOneWidget);
    expect(find.text('Days per row'), findsOneWidget);
    chrome.views.setLens('view:1', 'list');
    await tester.pump();
    expect(find.text('Rows'), findsNothing);
    expect(find.text('Group by'), findsOneWidget);
  });

  testWidgets('Today is disabled, with its reason, when no law maps onto the clock', (
    tester,
  ) async {
    await _pump(tester);
    expect(
      find.byTooltip('This frame has no now-mapping, so there is no today to centre on.'),
      findsOneWidget,
    );
  });

  testWidgets('closing a tile asks nothing', (tester) async {
    final chrome = await _pump(tester);
    chrome.stage.close('view:1');
    await tester.pump();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const ValueKey('body-view:1')), findsNothing);
    expect(find.text('No view tile is focused.'), findsOneWidget);
  });

  testWidgets('no bar overflows at any width, and nothing is merely clipped away', (tester) async {
    // The one bar layout, put under the whole range a window can be: full
    // labels, then compact forms, then a fold -- and never a RenderFlex.
    for (final width in const [200.0, 320.0, 520.0, 800.0, 1280.0, 2000.0, 3000.0]) {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final chrome = _chrome();
      await tester.pumpWidget(MaterialApp(home: ChronoSurface(chrome: chrome)));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'a bar overflowed at $width');
      final visible = chrome.views.visibleLenses;
      final shown = visible.where((id) => find.text(lensCatalog[id]!.title).evaluate().isNotEmpty);
      final folded = find.byTooltip('More controls').evaluate().isNotEmpty;
      final narrowed = visible.where(
        (id) => find.text(lensCatalog[id]!.title.substring(0, 1)).evaluate().isNotEmpty,
      );
      expect(
        shown.length == visible.length || folded || narrowed.isNotEmpty,
        isTrue,
        reason: 'at $width a lens was neither shown, narrowed, nor reachable in the fold',
      );
    }
  });

  testWidgets('a stage of lone windows draws no chrome of its own at all', (tester) async {
    final chrome = await _pump(tester);
    expect(chrome.stage.leaves.length, greaterThan(1));
    // ISSUES (9.1): "on a single tab the bar DISAPPEARS entirely". No name, no
    // mark, no strip -- the tiles' bodies are the whole of what is drawn, and
    // every pixel of every tile is its content. WHAT the pointer reveals in
    // their place is specified in test/chrome/tab_chrome_test.dart.
    expect(find.text('Minimap'), findsNothing);
    expect(find.text('⋮'), findsNothing, reason: 'nothing rests');
    // And the body proves it: the lens fills its tile with no strip taken off
    // the top, which is the whole point of retiring the bar.
    final tile = tester.getRect(find.byType(StageView));
    final lens = tester.getRect(find.byKey(const ValueKey('body-view:1')));
    final minimap = tester.getRect(find.byKey(const ValueKey('body-minimap:main')));
    expect(lens.height, closeTo(minimap.height, 1), reason: 'neither wears a bar the other lacks');
    expect(lens.height, lessThan(tile.height));
  });

  testWidgets('a divider drag resizes, with no ladder of stop points', (tester) async {
    await _pump(tester);
    final lens = tester.getRect(find.byKey(const ValueKey('body-view:1')));
    final minimap = tester.getRect(find.byKey(const ValueKey('body-minimap:main')));
    final seam = Offset((lens.right + minimap.left) / 2, lens.center.dy);
    await tester.dragFrom(seam, const Offset(-237, 0));
    // Past the double-tap window: the same seam also answers a double-click.
    await tester.pump(const Duration(milliseconds: 500));
    final moved = tester.getRect(find.byKey(const ValueKey('body-view:1')));
    // The seam follows the pointer for the whole gesture past the drag slop --
    // no ladder of stop points between where it started and where it landed.
    expect(lens.width - moved.width, greaterThan(200));
    expect(lens.width - moved.width, lessThanOrEqualTo(237));
  });

  testWidgets('a bar is a tile: its seam drags and its thickness is only a floor', (tester) async {
    final chrome = await _pump(tester);
    final bar = tester.getRect(find.byType(DocumentBar));
    expect(bar.height, closeTo(chrome.px('chrome.barHeight'), 1), reason: 'it arrives at content');
    await tester.dragFrom(Offset(bar.center.dx, bar.bottom + 2), const Offset(0, 200));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      tester.getRect(find.byType(DocumentBar)).height,
      greaterThan(bar.height + 100),
      reason: 'a bar resizes like any other tile: its thickness is only a floor',
    );
  });

  testWidgets('zoom gives one tile the stage and hands the arrangement back untouched', (
    tester,
  ) async {
    final chrome = await _pump(tester);
    final written = chrome.stage.root!.toJson();
    chrome.stage.toggleZoom('view:1');
    await tester.pump();
    expect(find.byKey(const ValueKey('body-minimap:main')), findsNothing);
    expect(find.byType(DocumentBar), findsOneWidget, reason: 'the chrome rides along');
    chrome.stage.toggleZoom('view:1');
    await tester.pump();
    expect(find.byKey(const ValueKey('body-minimap:main')), findsOneWidget);
    expect(chrome.stage.root!.toJson(), written);
  });

  testWidgets('a bare key never steals a keystroke from a field; a chord still fires', (
    tester,
  ) async {
    // Don, 2026-08-28: "I cannot type numbers in the names of events, like
    // '5-min test'". ONE guard at the dispatcher, not a condition per binding.
    final chrome = await _pump(tester);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    chrome.stage.open(
      TileSpec(
        id: 'card:name',
        type: 'card',
        klass: 'objectCard',
        title: 'Name',
        build: (context) => Material(child: TextField(controller: controller)),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(typingNow(), isTrue, reason: 'a field has the keystrokes');
    final lens = chrome.views.of('view:1').lensId;
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pump();
    expect(chrome.views.of('view:1').lensId, lens, reason: 'a digit typed a digit');
    // A chord cannot be typed into a field, so it still belongs to the surface.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(chrome.stage.tiles.containsKey('card:name'), isFalse, reason: 'ctrl+w still closed it');
  });

  testWidgets('view controls act on the focused view tile, never on the minimap', (tester) async {
    final chrome = await _pump(tester);
    chrome.stage.focus('minimap:main');
    await tester.pump();
    final before = chrome.views.focusOf('view:1');
    await tester.tap(find.byTooltip('Forward a window'));
    await tester.pump();
    expect(chrome.views.focusOf('view:1'), isNot(before), reason: 'the lens tile moved');
    expect(
      chrome.views.views.containsKey('minimap:main'),
      isFalse,
      reason: 'the minimap never becomes the target of a lens control',
    );
  });
}
