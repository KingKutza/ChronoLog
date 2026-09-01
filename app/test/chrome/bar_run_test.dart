// THE BAR'S HYSTERESIS IS A MEASUREMENT, NOT A MEMORY (ISSUES 9.1).
//
//   "The lens/selector bar went to first letters with plenty of room, and only
//   expanding and recontracting the tile fixed it."
//
// `BarRun` keeps `_wide` -- the width the FULL run needed when it was last laid
// out -- and while compact it comes back to full labels only when the room
// exceeds it. But the full form is never laid out while compact and the value
// was never invalidated when the items changed, so a bar that measured wide
// once carried that threshold forever: room enough for today's run, never
// enough for the ghost of a wider one.
//
// The claim below is width-independent and does not name a private field: HOW
// THE BAR ARRIVED AT A SET OF CONTROLS CANNOT CHANGE WHAT IT DRAWS. A bar shown
// three lenses reads the same whether it opened with three or was narrowed down
// to three from ten. Seeded, over a sweep of widths and of subsets, so the
// claim is about the class and not about one lucky number.

import 'dart:math';

import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/session/lens_catalog.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TileSpec _body(String id, String type, String klass, String title) => TileSpec(
  id: id,
  type: type,
  klass: klass,
  title: title,
  build: (context) => SizedBox.expand(key: ValueKey('body-$id')),
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

/// What the view bar is DRAWING for each lens it still shows: its whole title,
/// its initial, or nothing at all (folded away). Read off the rendered bar
/// rather than off any state the bar keeps.
Map<String, String> _drawn(Iterable<String> lenses) {
  final read = <String, String>{};
  for (final id in lenses) {
    final title = lensCatalog[id]!.title;
    read[id] = find.text(title).evaluate().isNotEmpty
        ? 'full'
        : (find.text(title.substring(0, 1)).evaluate().isNotEmpty ? 'initial' : 'folded');
  }
  return read;
}

Future<Chrome> _pump(WidgetTester tester, double width, {Set<String> hidden = const {}}) async {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1;
  final chrome = _chrome();
  for (final id in hidden) {
    chrome.views.setHidden(id, true);
  }
  // A FRESH TREE, deliberately: Flutter reuses an element whose widget matches,
  // so pumping one surface over another would hand the new bar the OLD bar's
  // measurement -- which is the very state this light is about, arriving by the
  // back door and hiding the defect from itself.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(home: ChronoSurface(chrome: chrome)));
  await tester.pumpAndSettle();
  return chrome;
}

void main() {
  testWidgets('how the bar arrived at its controls cannot change what it draws', (tester) async {
    addTearDown(tester.view.reset);
    // Seeded: the generator picks the widths and the surviving lens sets, so
    // the claim is not pinned to one arrangement anybody chose by eye.
    final seed = Random(90126);
    final lenses = lensCatalog.keys.toList();
    var proved = 0;
    for (var trial = 0; trial < 8; trial++) {
      final width = 260.0 + seed.nextInt(9) * 90;
      final keep = 1 + seed.nextInt(lenses.length - 1);
      final hidden = lenses.sublist(keep).toSet();

      // The road that never measured a wider run: born with these lenses.
      final direct = await _pump(tester, width, hidden: hidden);
      final born = _drawn(direct.views.visibleLenses);

      // The road through a wider run: born with all of them, narrowed here.
      final arrived = await _pump(tester, width);
      final wide = _drawn(arrived.views.visibleLenses);
      for (final id in hidden) {
        arrived.views.setHidden(id, true);
      }
      await tester.pumpAndSettle();
      final narrowed = _drawn(arrived.views.visibleLenses);

      expect(
        narrowed,
        born,
        reason:
            'ISSUES (9.1): the bar "went to first letters with plenty of room, and only '
            'expanding and recontracting the tile fixed it". At ${width.toStringAsFixed(0)}px '
            'with $keep lenses the bar reads $narrowed when it was narrowed down to them '
            'and $born when it opened with them — a hysteresis threshold measured off a run '
            'that no longer exists.',
      );
      // The trial only proves something where the wide run WAS compact: that is
      // the state the stale threshold was remembered in.
      if (wide.values.any((form) => form != 'full')) proved += 1;
    }
    expect(
      proved,
      greaterThan(0),
      reason: 'no seeded width ever compacted the bar, so nothing here was exercised',
    );
  });

  testWidgets('a bar still compacts, and still folds, when the room really is gone', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    // The guard on the other side: invalidating the measurement must not turn
    // the narrowing off. Every lens visible in a sliver of a window is either
    // narrowed to its initial or reachable in the fold -- never merely clipped.
    final chrome = await _pump(tester, 240);
    final drawn = _drawn(chrome.views.visibleLenses);
    expect(
      drawn.values.any((form) => form != 'full'),
      isTrue,
      reason: 'at 240px the whole run cannot fit, so something must narrow or fold',
    );
    expect(tester.takeException(), isNull, reason: 'and nothing overflowed saying so');
  });
}
