// THE HANDLE IS EVERY TILE'S, AND THE MENU HAS DEPTH (ISSUES 9.2, six reports).
//
// Don: the hover handle on ALL tiles, "even if all is 1"; the only way to close
// the last tab is the handle's right-click, so left-click opens the same menu
// and the revealed handle carries a close mark; the triple-dot menu is huge, so
// the content-swap slots in as a sub-item whose sections come from the content
// registry; the Hidden-lenses drop overflows because a menu row's hint is not
// flexible; the projection drop's reading forces every lens chip to its initial.
//
// Every claim below is asked of the surface as rendered: a handle is found by
// what it IS (the `Draggable<String>` carrying the tile's id that `tileGrab`
// wraps), never by a key someone might rename; the menu's sections are checked
// against the content registry after a kind nobody shipped is registered, so
// the claim "the registry, never a written list" is executable.
//
// THE CONTRACT this file names (words, not symbols): the handle menu carries ONE
// row for changing what this box shows, worded as ISSUES offers it -- "Show
// here…" or "Change this to…" -- never "Swap", which already means trading
// places; opening it shows a section per content family, the family being the
// registry kind's prefix before its colon (`lens`, `card`, `bar`, `minimap`,
// and whatever registers next). `stage.stripStays` is the settings key that
// keeps a stack's strip when it thins to one tab (shipped off). Whether a
// nested row is a field on the record `MenuRow` or a second class is the
// implementer's; what is pinned is the menu a person opens.

import 'package:chronolog/cards/card_factory.dart';
import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/lens/view_tile.dart' show Surface;
import 'package:chronolog/session/lens_catalog.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/content.dart';
import 'package:chronolog/stage/stage_widget.dart' show closeMark;
import 'package:chronolog/stage/tile.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../edit/harness.dart';

const Size _surface = Size(1600, 1000);

TileSpec _body(String id, String type, String klass, String title) => TileSpec(
  id: id,
  type: type,
  klass: klass,
  title: title,
  build: (context) => SizedBox.expand(key: ValueKey('body-$id')),
);

typedef StageBench = ({Chrome chrome, Editor editor, CardFactory factory});

/// The shipped stage over [document], the contents registered exactly as boot
/// registers them. [alone] stands ONE view tile and nothing else -- no bars, no
/// minimap -- which is the "even if all is 1" case.
Future<StageBench> pumpStage(
  WidgetTester tester, {
  Document? document,
  bool alone = false,
  Iterable<TileContent> extra = const [],
}) async {
  tester.view.physicalSize = _surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final bench = (await tester.runAsync(
    () => openEditor(document ?? createEmptyWorkspaceDocument()),
  ))!;
  addTearDown(() => closeEditor(bench));
  final settings = chronologSettings();
  final views = ViewBook();
  final stage = Stage(tunable: settings.tunable, onLens: views.setLens);
  final factory = CardFactory(bench.editor, settings, stage);
  final chrome = Chrome(
    settings: settings,
    stage: stage,
    views: views,
    editor: bench.editor,
    viewTile: (id) => _body(id, 'view', 'lens', 'View'),
  );
  final Surface surface = (
    editor: bench.editor,
    settings: settings,
    views: views,
    stage: stage,
    objectCard: factory.objectCard,
    frameCard: factory.frameCard,
    settingsCard: factory.settingsCard,
  );
  registerShippedContents(factory: factory, surface: surface);
  for (final content in extra) {
    registerTileContent(content);
  }
  if (alone) {
    stage.open(_body('view:1', 'view', 'lens', 'View'));
  } else {
    installDefaultStage(chrome, minimap: (id) => _body(id, 'minimap', 'field', 'Minimap'));
  }
  await tester.pumpWidget(MaterialApp(home: ChronoSurface(chrome: chrome)));
  await tester.pump();
  return (chrome: chrome, editor: bench.editor, factory: factory);
}

/// The grips on the surface carrying THIS tile's id -- the handle is what you
/// drag a tile by, so a handle IS a `Draggable<String>` of the tile's id.
int gripsOf(WidgetTester tester, String id) => find
    .byWidgetPredicate((widget) => widget is Draggable<String> && widget.data == id)
    .evaluate()
    .length;

/// A pointer parked in the handle band down the tile's leading edge.
Future<TestGesture> hoverBand(WidgetTester tester, Chrome chrome, String id) async {
  final rect = tester.getRect(find.byKey(ValueKey('body-$id')));
  final band = chrome.px('stage.handleBand');
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(Offset(rect.left + band / 2, rect.center.dy));
  await tester.pumpAndSettle();
  return mouse;
}

Finder _grip(String id) =>
    find.byWidgetPredicate((widget) => widget is Draggable<String> && widget.data == id);

void main() {
  testWidgets('the Hidden-lenses drop never overflows its rows', (tester) async {
    final bench = await pumpStage(tester);
    final ids = lensCatalog.keys.toList();
    for (final id in ids.skip(1)) {
      bench.chrome.views.setHidden(id, true);
    }
    await tester.pump();
    final drop = find.text('⋯');
    expect(drop, findsWidgets, reason: 'the hidden-lenses drop is on the bar');
    await tester.tap(drop.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.takeException(),
      isNull,
      reason:
          'ISSUES 9.2: a menu row is Row[Expanded(label), Text(hint)] in a fixed box, the hint '
          'unbounded -- a long description overflows. The hint is Flexible; a long one wraps.',
    );
  });

  testWidgets('every tile has the hover handle, the sole tile included', (tester) async {
    // Don: "awesome, 100% love -- it should be for all tiles, not just those
    // without tabs", then "yes all tiles, even if all is 1 ... if for nothing
    // else than for the right-click context menu." Both gates in
    // `stage_widget.dart` -- `!tabbed` and `leaves.length > 1` -- go.
    final bench = await pumpStage(tester, alone: true);
    expect(bench.chrome.stage.leaves, hasLength(1), reason: 'one tile is all there is');
    final resting = gripsOf(tester, 'view:1');
    await hoverBand(tester, bench.chrome, 'view:1');
    expect(
      gripsOf(tester, 'view:1'),
      greaterThan(resting),
      reason:
          'ISSUES 9.2 (Don: "even if all is 1"): the sole tile revealed no handle on hover -- '
          '`leaves.length > 1` gates it. Its verbs (close, settings, the menu) are still wanted.',
    );
  });

  testWidgets('a tabbed tile reveals its handle over its own body too', (tester) async {
    // "The handle is EVERY tile's, tabbed or not; the tab in the strip is a
    // second grip, not a substitute."
    final bench = await pumpStage(tester);
    final stage = bench.chrome.stage;
    stage.tabUnder('minimap:main', 'view:1');
    stage.focus('view:1');
    await tester.pumpAndSettle();
    final resting = gripsOf(tester, 'view:1');
    await hoverBand(tester, bench.chrome, 'view:1');
    expect(
      gripsOf(tester, 'view:1'),
      greaterThan(resting),
      reason:
          'ISSUES 9.2: a tile in a stack got no body handle because "the strip above already '
          'carries its tab". The strip is a second grip, not a substitute.',
    );
  });

  testWidgets('left-click on the handle opens the same menu; the revealed handle carries a close '
      'mark', (tester) async {
    // "The only way to close the last tab in a tile is to right-click on the
    // triple dots." Ruled: (a) LEFT-click on the handle opens the menu the
    // right-click does; (b) the revealed handle carries the close mark beside
    // the grip; (c) a setting says whether a strip stays when a stack thins to
    // one tab, default off.
    final bench = await pumpStage(tester, alone: true);
    await hoverBand(tester, bench.chrome, 'view:1');
    expect(
      find.text(closeMark),
      findsWidgets,
      reason:
          'ISSUES 9.2: the revealed handle carries the close mark beside the grip, so the verb '
          'the hand wants most is one hover and one click away without a menu.',
    );
    final grip = _grip('view:1');
    expect(grip, findsWidgets, reason: 'the handle is out');
    await tester.tap(grip.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      find.text('Close'),
      findsWidgets,
      reason:
          'ISSUES 9.2: left-click on the handle opens the same menu the right-click does -- one '
          'grip, drag or click, no hidden button.',
    );
    expect(
      bench.chrome.settings.expressionOf('stage.stripStays'),
      isNotEmpty,
      reason:
          'ISSUES 9.2: whether the strip stays when a stack thins to one tab is a setting, '
          'default off (the no-resting-chrome ruling), on for people who want the ✕ visible.',
    );
  });

  testWidgets('the content door is a sub-item whose sections are the registry read by family', (
    tester,
  ) async {
    // "There is already a huge context menu on the triple dot -- our menu will
    // have to slot neatly into a sub-item on that one." And the swap menu is "a
    // SECTION PER CONTENT TYPE (lenses, cards, bars, minimap, settings -- the
    // `TileContent` registry's own families) ... Generative: the menu is the
    // registry read by family, never a written list." And the wording: "'Swap
    // with X' already means trade PLACES with another tile, so the content door
    // cannot also say 'swap' -- it says what it does to this box: 'Show here…' or
    // 'Change this to…'."
    final gizmo = DoorContent('gizmo:one', 'A gizmo', (id) => _body(id, 'gizmo', 'one', 'Gizmo'));
    final bench = await pumpStage(tester, extra: [gizmo]);
    final families = {for (final kind in tileContents.keys) kind.split(':').first};
    expect(families, contains('gizmo'), reason: 'the registry now holds a family nobody shipped');
    await hoverBand(tester, bench.chrome, 'view:1');
    final grip = _grip('view:1');
    expect(grip, findsWidgets);
    final gesture = await tester.startGesture(
      tester.getCenter(grip.first),
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    final door = find.textContaining(RegExp('Show here|Change this to', caseSensitive: false));
    expect(
      door,
      findsOneWidget,
      reason:
          'ISSUES 9.2: the content-swap must slot into the triple-dot menu as ONE sub-item that '
          'says what it does to this box -- never a second flat fan, never the word "swap".',
    );
    await tester.tap(door.first);
    await tester.pumpAndSettle();
    for (final family in families) {
      expect(
        find.textContaining(RegExp(family, caseSensitive: false)),
        findsWidgets,
        reason:
            'ISSUES 9.2: the sub-item has no "$family" section. Sections are the registry\'s '
            'families, so a kind registered a minute ago is a section with no code change.',
      );
    }
  });

  testWidgets('the projection reading is capped and the bar compacts the widest items first', (
    tester,
  ) async {
    // "We need some fixed width or overflow rule for the projecting-frame
    // drop-down so it does not force the lenses to first initials." Ruled: the
    // reading is capped by a settings-fed width (`chrome.readingWidth`), the bar
    // compacts the WIDEST items first and only as many as it takes. Red light:
    // ten projected frames of forty-character titles, every lens chip keeps its
    // full title at the shipped bar width.
    var document = createEmptyWorkspaceDocument();
    final ids = <String>[];
    for (var index = 0; index < 10; index += 1) {
      final id = 'frame:long-$index';
      ids.add(id);
      document = document.put(
        'frames',
        id,
        Frame(
          id: id,
          title: 'Frame number $index with a deliberately forty-char name',
          traits: const ['set', 'calendar'],
          extra: const {'basis': 'frame:wall-time'},
        ),
      );
    }
    final bench = await pumpStage(tester, document: document);
    final view = bench.chrome.views.of('view:1');
    for (final id in ids) {
      view.selection.toggle(id);
    }
    bench.chrome.views.touch();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'a long reading overflows nothing');
    for (final id in bench.chrome.views.visibleLenses) {
      final title = lensCatalog[id]!.title;
      expect(
        find.text(title),
        findsWidgets,
        reason:
            'ISSUES 9.2: ten projected frames of long titles collapsed the "$title" chip to its '
            'initial. The reading gives up everything it can before a chip loses its name.',
      );
    }
    expect(
      bench.chrome.settings.expressionOf('chrome.readingWidth'),
      isNotEmpty,
      reason: 'ISSUES 9.2: the cap on the reading is a settings key, never a literal in the bar',
    );
  });
}
