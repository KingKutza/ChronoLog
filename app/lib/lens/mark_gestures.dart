// THE POINTER VOCABULARY FOR A MARK THAT IS A WIDGET.
//
// Don, 2026-08-31: "Clicking, and double clicking on an event don't open its
// card, also right clicking does not include an open card option. I see no clear
// way to open an events card back up." The ruled class is EVERY MARK ON EVERY
// LENS, so it cannot be a rule the painted surfaces keep and the roster surfaces
// each improvise: single click selects, double click opens the object's card,
// the secondary button raises the app's own menu with Open on it.
//
// A time lens reads that table in `view_tile.dart` because its marks are
// painted geometry. A ToDo row and a graph node are marks too -- they just have
// a widget instead of a Path -- so they wrap in THIS, and the vocabulary is
// stated once for both kinds of surface rather than wired per lens.

import 'package:flutter/widgets.dart';

import 'context_menu.dart';
import 'view_tile.dart';

class MarkGestures extends StatelessWidget {
  const MarkGestures({
    required this.tile,
    required this.child,
    this.objectId,
    this.frameId,
    super.key,
  });

  final ViewTileController tile;

  /// The object this mark names, where it names one.
  final String? objectId;

  /// The frame it names instead -- a graph node may be either, and Open opens
  /// whichever card the record actually has.
  final String? frameId;

  final Widget child;

  String? get _id => objectId ?? frameId;

  void _select() {
    final id = _id;
    if (id != null) tile.selectObject(id);
  }

  void _open() {
    final frame = frameId, object = objectId;
    final card = frame != null ? tile.frameCard : tile.objectCard;
    final id = frame ?? object;
    if (card == null || id == null) return;
    tile.stage.open(card(id));
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: _select,
    onDoubleTap: () {
      _select();
      _open();
    },
    onSecondaryTapUp: (details) => showViewContextMenu(
      context,
      details.globalPosition,
      tile,
      objectId: objectId,
      frameId: frameId,
    ),
    child: child,
  );
}
