// The surface, assembled: the settings every area declares, the shipped stage
// preset, and the widget that hosts them.
//
// The shipped preset is the ratified arrangement -- the chrome stack (document,
// view and context bars) on the left third of a top row, the minimap filling
// the right two thirds, the main row below -- expressed as an ordinary layout
// tree. It is a preset, not a special case: every tile in it can be split,
// tabbed, moved or closed like any other.

import 'package:flutter/material.dart';

import '../cards/card_chrome.dart';
import '../cards/card_factory.dart';
import '../cards/document_card.dart';
import '../core/exact.dart';
import '../edit/editor.dart';
import '../lens/gestures.dart';
import '../lens/painters/intimate.dart';
import '../lens/painters/month_grid.dart';
import '../lens/painters/radial.dart';
import '../lens/theme.dart';
import '../lens/todo/row.dart';
import '../lens/tree/tree_lens.dart';
import '../lens/tunables.dart';
import '../lens/minimap/minimap_tile.dart';
import '../lens/view_tile.dart';
import '../session/lens_catalog.dart';
import '../session/settings.dart';
import '../stage/content.dart';
import '../stage/layout_tree.dart';
import '../stage/stage_widget.dart';
import '../stage/tile.dart';
import 'context_bar.dart';
import 'controls.dart';
import 'document_bar.dart';
import 'keyboard.dart';
import 'view_bar.dart';

/// EVERY area's shipped defaults, composed, and nothing else composes them.
///
/// A key that reaches no map here is a REFUSAL naming the key rather than a
/// silently substituted zero, so this list being complete is what makes "no
/// literals in lenses or chrome" true rather than aspirational. `test/app`
/// asserts it against every key any file in `lib/` actually reads.
Settings chronologSettings() => Settings(
  defaults: const [
    lensTunableDefaults,
    sessionTunableDefaults,
    stageTunableDefaults,
    chromeTunableDefaults,
    editTunableDefaults,
    pointerTunableDefaults,
    intimateTunableDefaults,
    gridTunableDefaults,
    todoTunableDefaults,
    curveTunableDefaults,
    treeTunableDefaults,
    cardTunableDefaults,
    frameCardTunableDefaults,
  ],
  texts: const [chromeKeyDefaults, chromeTextDefaults, stageTextDefaults, frameCardTextDefaults],
);

const List<(String, String, String)> _bars = [
  ('bar:document', 'documentBar', 'Document'),
  ('bar:view', 'viewBar', 'View'),
  ('bar:context', 'contextBar', 'Context'),
];

/// One bar's spec, minted the same way wherever it is asked for.
TileSpec _barSpec(String id, String klass, String title) => TileSpec(
  id: id,
  type: 'bar',
  klass: klass,
  title: title,
  build: (context) => switch (klass) {
    'documentBar' => const DocumentBar(),
    'viewBar' => const ViewBar(),
    _ => const ContextBar(),
  },
);

/// THE SHIPPED REGISTRATION (the one ancestor, ruled 2026-09-01): every content
/// the app can show — the three bars, every catalog lens, the minimap, every
/// card class and every settings sub-card — lands in [tileContents] here, and
/// the connectivity law is checked against exactly this registry. A content
/// that ships without registering is invisible to the law, so nothing ships
/// without registering.
void registerShippedContents({required CardFactory factory, required Surface surface}) {
  for (final (_, klass, title) in _bars) {
    registerTileContent(DoorContent('bar:$klass', title, (id) => _barSpec(id, klass, title)));
  }
  for (final lensId in lensCatalog.keys) {
    registerTileContent(LensContent(lensId, surface));
  }
  registerTileContent(MinimapContent(surface));
  for (final content in factory.contents()) {
    registerTileContent(content);
  }
}

/// Registers the chrome tiles and lays the shipped preset out, saving it under
/// `default` so a rearranged stage can come back to it.
void installDefaultStage(Chrome chrome, {TileSpec Function(String id)? minimap}) {
  final stage = chrome.stage;
  for (final (id, klass, title) in _bars) {
    stage.tiles[id] = _barSpec(id, klass, title);
  }
  if (minimap != null) stage.tiles['minimap:main'] = minimap('minimap:main');
  if (chrome.viewTile != null) stage.tiles['view:1'] = chrome.viewTile!('view:1');
  final minimapWidth = chrome.settings.value('stage.minimapWidth');
  // A bar's share is small on purpose: its own content thickness raises it, so
  // a bar ARRIVES at the size it needs and grows only when someone drags it.
  final bar = chrome.settings.value('stage.barShare');
  stage.root = Branch(
    'root',
    mode: 'split',
    axis: 'column',
    ratios: [bar, bar, Rational.one - bar * Rational.fromInt(3), bar],
    children: [
      TileLeaf('bar:document', type: 'bar', klass: 'documentBar', title: 'Document'),
      TileLeaf('bar:view', type: 'bar', klass: 'viewBar', title: 'View'),
      Branch(
        'stage',
        mode: 'split',
        axis: 'row',
        name: 'stage',
        ratios: [Rational.one - minimapWidth, minimapWidth],
        children: [
          TileLeaf('view:1', type: 'view', klass: 'lens', title: 'View'),
          TileLeaf('minimap:main', type: 'minimap', klass: 'field', title: 'Minimap'),
        ],
      ),
      TileLeaf('bar:context', type: 'bar', klass: 'contextBar', title: 'Context'),
    ],
  );
  stage.openOrder
    ..clear()
    ..addAll(stage.tiles.keys);
  stage.savePreset('default');
  if (findNode(stage.root, 'view:1') != null) stage.focus('view:1');
}

/// The whole surface: the scope every bar reads, the one keyboard map, and the
/// tiling stage.
class ChronoSurface extends StatelessWidget {
  const ChronoSurface({super.key, required this.chrome, this.theme, this.cards});

  final Chrome chrome;
  final ChronoTheme? theme;

  /// The card layer, hosted ABOVE EVERY TILE rather than around each card, so
  /// any tile can open or focus another record's card from where it sits. A
  /// card's own host overrides this one with what that card is editing.
  final CardFactory? cards;

  @override
  Widget build(BuildContext context) {
    final palette = theme ?? ChronoTheme.of(context);
    // THE STAGE PAINTS ITS OWN GROUND. There is no Scaffold under this, so a
    // transparent surface is the host window's black -- which is what showed
    // through every seam in the first look.
    final stage = ChromeKeyboard(
      child: Material(color: palette.ground, child: const StageView()),
    );
    return Theme(
      // ONE THEME BUILDER. A bare ThemeData here carried the palette and let
      // Material answer for everything else, so tooltips, splashes and text
      // selection came up in the framework's blue under a hand-authored
      // palette. `themeDataFor` is the one place a ChronoTheme becomes a
      // ThemeData, and this is one of its two callers.
      data: themeDataFor(palette),
      child: ChromeScope(
        chrome: chrome,
        child: cards == null
            ? stage
            : CardHost(
                factory: cards!,
                request: const (
                  klass: '',
                  id: null,
                  kind: null,
                  frameId: null,
                  startDays: null,
                  endDays: null,
                ),
                tileId: '',
                child: stage,
              ),
      ),
    );
  }
}
