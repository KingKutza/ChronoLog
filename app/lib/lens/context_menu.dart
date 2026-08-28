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
List<MenuRow> viewMenuRows(ViewTileController tile, {MarkHit? hit, Rational? at}) {
  final frame = tile.primaryFrame, stage = tile.stage;
  final openObject = tile.objectCard, openFrame = tile.frameCard;
  final nothing = frame == null ? 'nothing projected' : null;
  return [
    if (hit != null) ...[
      menuRow(
        'Open',
        openObject == null
            ? null
            : () {
                tile.select(hit.identity);
                tile.openSelected();
              },
        hint: openObject == null ? 'no card surface' : null,
      ),
      // Undoable, so there is no confirmation to answer.
      menuRow('Delete', () => tile.editor.deleteObject(hit.fact.event.id), hint: 'undoable'),
      menuRow(
        'Mark done',
        () => tile.editor.toggleState(hit.fact.event.id, doneStateFrameId, frame: frame),
      ),
      menuRow('Move to…', null, hint: 'drag the mark'),
    ],
    for (final entry in objectKinds.entries)
      menuRow(
        'New ${entry.value.label.toLowerCase()} here',
        at == null || frame == null ? null : () => tile.createHere(entry.key, at),
        hint: nothing,
      ),
    menuRow('Paste', null, hint: 'nothing copied'),
    menuRow(
      'Frame…',
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
  Rational? at,
}) => showChronoMenu(context, screen, viewMenuRows(tile, hit: hit, at: at));
