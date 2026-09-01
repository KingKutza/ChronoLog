// STAGE AND BAR RULINGS (ISSUES 9.1, Don's morning test), each a claim the
// rendered chrome can be asked about.
//
//   "Single tabs have been replaced with a nontab title in the same place,
//   defeating the purpose of removing them. The point was that the bar
//   disappeared on a single tab" — a lone window wears NO resting bar; its
//   drag point is a hover element, so at rest its title paints nowhere.
//
//   "If I am in a lens and there is a window to the right, and I would open a
//   new window: default to tabbing there" — placement prefers the right-hand
//   neighbor as a tab host over splitting again.
//
//   "When it switches lenses via the lens bar, the name of that window does
//   not change" — a view tile's name IS its current lens, read live, wherever
//   a name for it is drawn (its tab in a stack).
//
//   "I can't find the setting to hide some of them behind a button" — hiding a
//   lens is a verb on the lens chip itself; today only the restore half exists.

import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/session/lens_catalog.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/layout_tree.dart';
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

Future<Chrome> pumpStage(WidgetTester tester) async {
  tester.view.physicalSize = _surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // A real editor over a real store: the projection drop reads
  // `chrome.editor?.document.frames`, and a chrome with no document has no
  // frames to even list.
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
  testWidgets('a lone window wears no resting name bar at all', (tester) async {
    await pumpStage(tester);
    expect(
      find.text('Minimap'),
      findsNothing,
      reason:
          'ISSUES (9.1): the single tab was replaced with a nontab title in the same '
          'place, defeating the removal. The bar DISAPPEARS on a lone window; the drag '
          'point is a hover triple-dot on the left edge, centred in y — nothing rests.',
    );
  });

  test('a new tile tabs into the right-hand neighbor before splitting again', () {
    final settings = chronologSettings();
    final stage = Stage(tunable: settings.tunable)
      ..open(_body('a', 'view', 'lens', 'A'))
      ..open(_body('b', 'card', 'note', 'B'));
    // A is focused with B split to its right — Don's stated situation.
    stage.focus('a');
    stage.open(_body('c', 'card', 'editor', 'C'));
    final parent = parentOf(stage.root, 'c');
    expect(
      parent?.mode == 'tabs' && parent!.children.any((child) => child.id == 'b'),
      isTrue,
      reason:
          'ISSUES (9.1): "there is a window to the right… default to tabbing there" — '
          'C landed by ${parent?.mode ?? 'nowhere'} instead of tabbing with the '
          'right-hand neighbor B.',
    );
  });

  testWidgets('a stacked view tile\'s tab is named by its CURRENT lens', (tester) async {
    final chrome = await pumpStage(tester);
    final view = chrome.stage.leaves.firstWhere((leaf) => leaf.type == 'view');
    final minimap = chrome.stage.leaves.firstWhere((leaf) => leaf.type == 'minimap');
    chrome.stage.tabUnder(minimap.id, view.id);
    await tester.pumpAndSettle();
    final swapped = lensCatalog.keys.firstWhere((id) => id != chrome.views.of(view.id).lensId);
    chrome.stage.swapLens(view.id, swapped);
    await tester.pumpAndSettle();
    // The SPEC title is what every strip and window draws for this tile — the
    // lens bar's own chips carry the same words, so the claim reads the seam
    // the chrome reads rather than hunting text the bar also shows.
    expect(
      chrome.stage.tiles[view.id]!.title,
      lensCatalog[swapped]!.title,
      reason:
          'ISSUES (9.1): the window keeps the name it was born with — `viewTileSpec` '
          'bakes the title at construction and `swapLens` never restates it. A view '
          'tile\'s name IS its current lens, read at paint.',
    );
  });

  testWidgets('a lens chip offers Hide where the hand already is', (tester) async {
    await pumpStage(tester);
    final chip = find.text(lensCatalog.values.first.title).first;
    await tester.tap(chip, warnIfMissed: false, buttons: kSecondaryMouseButton);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('Hide'),
      findsWidgets,
      reason:
          'ISSUES (9.1): `setHidden(id, true)` has ZERO call sites — the Hidden-lenses '
          'drop restores, and nothing anywhere hides. The verb belongs on the chip.',
    );
  });

  testWidgets('the projection drop offers to make the frame it does not have', (tester) async {
    await pumpStage(tester);
    await tester.tap(find.text('Projection').first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('New frame'),
      findsWidgets,
      reason:
          'ISSUES (9.1): the frames drop has no button to author a frame — and the '
          'moment you discover the frame you want does not exist is exactly the moment '
          'you are looking at the list of frames.',
    );
  });

  testWidgets('the open projection drop is a live reading of the selection', (tester) async {
    final chrome = await pumpStage(tester);
    await tester.tap(find.text('Projection').first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    final tile = chrome.stage.focusedViewTile!;
    final view = chrome.views.of(tile);
    // Lead with the OTHER frame, live, while the drop stays open.
    final other = chrome.editor!.document.frames.keys
        .firstWhere((id) => !view.selection.isPrimary(id));
    view.selection
      ..toggle(other)
      ..setPrimary(other);
    chrome.views.touch();
    await tester.pump(const Duration(milliseconds: 300));
    // The lead mark must sit against the newly-led frame's row: in the flat
    // text order of the open drop, the mark PRECEDING that title is ◉.
    final texts = [
      for (final widget in tester.widgetList<Text>(find.byType(Text))) widget.data ?? '',
    ];
    final title = chrome.editor!.document.frames[other]!.title ?? other;
    var lead = '';
    for (final text in texts) {
      if (text == '◉' || text == '○') lead = text;
      if (text == title) break;
    }
    expect(
      lead,
      '◉',
      reason:
          'ISSUES (9.1): the checkboxes ripple but never check — `const '
          'ProjectionControl()` under the bar\'s ListenableBuilder is an identical '
          'widget every build, so nothing re-runs the control when views.touch() fires. '
          'The lens behind updates; the open list lies.',
    );
  });
}
