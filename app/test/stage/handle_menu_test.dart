// THE HANDLE IS EVERY TILE'S, AND THE MENU HAS DEPTH (ISSUES 9.2, six reports).
//
// Don: the hover handle on ALL tiles, "even if all is 1"; the only way to close
// the last tab is the handle's right-click, so left-click opens the same menu
// and the revealed handle carries a close mark; the triple-dot menu is huge, so
// the content-swap slots in as a sub-item whose sections come from the content
// registry; the Hidden-lenses drop overflows because a menu row's hint is not
// flexible; the projection drop's reading forces every lens chip to its initial.

import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/session/lens_catalog.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/tile.dart';
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

Future<Chrome> pumpStage(WidgetTester tester) async {
  tester.view.physicalSize = _surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final bench = (await tester.runAsync(() => openEditor(createEmptyWorkspaceDocument())))!;
  addTearDown(() => closeEditor(bench));
  final settings = chronologSettings();
  final views = ViewBook();
  final stage = Stage(tunable: settings.tunable, onLens: views.setLens);
  final chrome = Chrome(
    settings: settings,
    stage: stage,
    views: views,
    editor: bench.editor,
    viewTile: (id) => _body(id, 'view', 'lens', 'View'),
  );
  installDefaultStage(chrome, minimap: (id) => _body(id, 'minimap', 'field', 'Minimap'));
  await tester.pumpWidget(MaterialApp(home: ChronoSurface(chrome: chrome)));
  await tester.pump();
  return chrome;
}

void main() {
  testWidgets('the Hidden-lenses drop never overflows its rows', (tester) async {
    final chrome = await pumpStage(tester);
    final ids = lensCatalog.keys.toList();
    for (final id in ids.skip(1)) {
      chrome.views.setHidden(id, true);
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

  test('every tile has the hover handle, the sole tile included', () {
    fail(
      'ISSUES 9.2 (Don: "yes all tiles, even if all is 1"): `handled = !tabbed && leaves.length > 1`. '
      'Both gates go; assert a tabbed tile and a sole tile each reveal the handle on hover.',
    );
  });

  test('left-click on the handle opens the same menu; the revealed handle carries a close mark', () {
    fail(
      'ISSUES 9.2: the last tab\'s only close is the handle\'s right-click or ctrl+w. Left-click '
      'opens the menu; a close mark rides beside the grip; `stage.stripStays` keeps the strip at one tab.',
    );
  });

  test('menu rows have children, and the content-swap sub-item is the registry read by family', () {
    fail(
      'ISSUES 9.2: `MenuRow` has no children; the swap menu must slot into the triple-dot menu '
      'as one sub-item with a section per content family from `TileContent` registrations, '
      'never a written list. Assert the families equal the registry\'s.',
    );
  });

  test('the projection reading is capped and the bar compacts the widest items first', () {
    fail(
      'ISSUES 9.2: ten projected frames of long titles collapse every lens chip to its initial. '
      'Cap the reading (`chrome.readingWidth`, middle ellipsis, "N frames" compact) and compact '
      'widest-first; assert every lens chip keeps its full title at the shipped bar width.',
    );
  });
}
