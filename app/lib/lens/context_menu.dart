// The right-click surface, everywhere.
//
// ISSUES 8.26: right-clicking the projection got the browser's own menu, and
// right-clicking an event got nothing at all. The button was unowned. Here it is
// owned once -- the same menu class the bars use (`chrome/menus.dart`), so
// placement, dismissal, mutual exclusion and z-order are properties of the menu
// rather than of the site that raised it.
//
// A row that cannot act STAYS VISIBLE and carries its reason: a menu that hides
// what it will not do teaches nothing.

import 'package:flutter/widgets.dart';

import '../chrome/menus.dart';
import '../core/exact.dart';
import '../core/object_kinds.dart';
import '../edit/editor.dart';
import 'lens_painter.dart';
import 'view_tile.dart';

/// The rows for one point on a lens: what is under the cursor, then what this
/// place affords, then what the tile itself affords.
///
/// WHAT IS UNDER THE CURSOR ARRIVES IN WHATEVER FORM THE SURFACE HAS IT: a
/// painted lens carries a [MarkHit], a roster row or a graph node carries an id.
/// The rows are the same either way, because OPEN IS NOT A PER-LENS FEATURE --
/// every mark on every lens has a path back to its record's card (ruled
/// 2026-08-31).
List<MenuRow> viewMenuRows(
  ViewTileController tile, {
  MarkHit? hit,
  String? objectId,
  String? frameId,
  Rational? at,
}) {
  final frame = tile.primaryFrame, stage = tile.stage;
  final openObject = tile.objectCard, openFrame = tile.frameCard;
  final nothing = frame == null ? 'nothing projected' : null;
  final object = objectId ?? hit?.fact.event.id;
  return [
    if (frameId != null)
      menuRow(
        'Open',
        openFrame == null ? null : () => stage.open(openFrame(frameId)),
        hint: openFrame == null ? 'no card surface' : null,
      ),
    if (frameId == null && object != null) ...[
      menuRow(
        'Open',
        openObject == null
            ? null
            : () {
                tile.select(hit?.identity ?? object);
                tile.openObject(object);
              },
        hint: openObject == null ? 'no card surface' : null,
      ),
      // Undoable, so there is no confirmation to answer.
      menuRow('Delete', () => tile.editor.deleteObject(object), hint: 'undoable'),
      menuRow(
        'Mark done',
        () => tile.editor.toggleState(object, doneStateFrameId, frame: frame),
      ),
      if (hit != null) menuRow('Move to\u2026', null, hint: 'drag the mark'),
    ],
    for (final entry in objectKinds.entries)
      menuRow(
        'New ${entry.value.label.toLowerCase()} here',
        at == null || frame == null ? null : () => tile.createHere(entry.key, at),
        hint: nothing,
      ),
    menuRow('Paste', null, hint: 'nothing copied'),
    menuRow(
      'Frame\u2026',
      frame == null || openFrame == null ? null : () => stage.open(openFrame(frame)),
      hint: nothing,
    ),
    menuRow('Split right', () => stage.split(tile.tileId, 'row')),
    menuRow('Split down', () => stage.split(tile.tileId, 'column')),
    menuRow('Close tile', () => stage.close(tile.tileId)),
  ];
}

/// Raises the app's own menu at a global point. Every lens surface calls this
/// and no lens surface builds its own.
Future<void> showViewContextMenu(
  BuildContext context,
  Offset screen,
  ViewTileController tile, {
  MarkHit? hit,
  String? objectId,
  String? frameId,
  Rational? at,
}) => showChronoMenu(
  context,
  screen,
  viewMenuRows(tile, hit: hit, objectId: objectId, frameId: frameId, at: at),
);
