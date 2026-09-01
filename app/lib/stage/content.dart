// THE ONE ANCESTOR (Don, ruled 2026-09-01): "Keep tiles their own thing… you
// can keep your classes for cards and lenses and etc., as long as they all
// inherit from one ancestor and that ancestor is what our test checks graph
// connectivity against."
//
// A TILE is the box — the stage's unit, unchanged. A CONTENT is what fills a
// box: a lens, a card, a bar, the minimap, a settings sub-card. Every content
// class descends from [TileContent], every shipped content registers here, and
// the connectivity law ("from anywhere, reach anything") is checked against
// THIS registry — the universe is derived, never a hand list, so it grows to
// the full surface count on its own as contents register.
//
// This is also the melt of the four minting doors: what used to be
// CardFactory-or-viewTileSpec-or-minimapTileSpec-or-a-bar-switch is one
// question, "which content?", answered by one map.

import 'tile.dart';

/// One kind of thing a tile can hold.
abstract class TileContent {
  const TileContent();

  /// The registry key and graph node: `lens:lines`, `card:frame`,
  /// `bar:viewBar`, `minimap`, `card:settings:intimate`. Unique by
  /// construction — registering a kind twice replaces it, which is what a
  /// hot-reloaded registration wants.
  String get kind;

  /// What this content is called — a READING of what it is now, not a fact
  /// minted once (ISSUES 9.1: a view tile's name is its current lens).
  String get title;

  /// Mint the box's filling. The id is the tile's, chosen by whoever opens it,
  /// so opening the same content twice under one id stays idempotent through
  /// `Stage.open`.
  TileSpec spec(String id);
}

/// Every registered content, by kind. The graph test's universe IS this map's
/// values after the shipped registration runs — nothing else may enumerate
/// what the app can show.
final Map<String, TileContent> tileContents = {};

void registerTileContent(TileContent content) => tileContents[content.kind] = content;

/// A content whose spec is a closure — the adapter for contents that already
/// have a factory door and gain nothing from a class of their own.
class DoorContent extends TileContent {
  const DoorContent(this.kind, this.title, this._spec);

  @override
  final String kind;
  @override
  final String title;
  final TileSpec Function(String id) _spec;

  @override
  TileSpec spec(String id) => _spec(id);
}
