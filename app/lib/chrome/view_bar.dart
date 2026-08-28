// The view bar: which lens the focused view tile is, and what it looks through.
//
// A tile IS a lens -- the zoom auto-swap is dead -- so pressing a lens swaps
// THIS tile's lens rather than opening another one. Hold shift to get a second
// view instead. Hidden lenses collect in one drop that restores and switches in
// the same press, so a lens is never hidden somewhere you cannot reach it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../lens/theme.dart';
import '../session/lens_catalog.dart';
import 'controls.dart';
import 'menus.dart';
import 'projection_control.dart';

/// Opens another view tile, on [lensId] when one is named. Ids count up so the
/// layout file stays readable by hand.
String openViewTile(Chrome chrome, {String? lensId}) {
  var number = 1;
  while (chrome.stage.tiles.containsKey('view:$number')) {
    number += 1;
  }
  final id = 'view:$number';
  if (lensId != null) chrome.views.of(id).lensId = lensId;
  final make = chrome.viewTile;
  if (make != null) chrome.stage.open(make(id));
  return id;
}

class ViewBar extends StatelessWidget {
  const ViewBar({super.key});

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.of(context);
    return ListenableBuilder(
      listenable: chrome.pulse,
      builder: (context, _) {
        final tile = chrome.stage.focusedViewTile;
        final current = tile == null ? null : chrome.views.of(tile).lensId;
        final visible = chrome.views.visibleLenses;
        final hidden = [
          for (final id in lensCatalog.keys)
            if (!visible.contains(id)) id,
        ];
        return barShell(
          context,
          [
            for (final id in visible) _lens(context, id, id == current, tile),
            if (hidden.isNotEmpty)
              barItem(
                'Hidden lenses',
                ChronoMenu(
                  label: 'Hidden lenses',
                  glyph: '⋯',
                  rows: [
                    for (final id in hidden)
                      menuRow(lensCatalog[id]!.title, () {
                        chrome.views.setHidden(id, false);
                        if (tile != null) chrome.stage.swapLens(tile, id);
                      }, hint: lensCatalog[id]!.description),
                  ],
                ),
              ),
            barAction(
              context,
              'New view',
              glyph: '＋',
              hint: 'Open another view tile',
              onTap: () => openViewTile(chrome, lensId: current),
            ),
          ],
          trailing: [barItem('Projection', const ProjectionControl())],
        );
      },
    );
  }
}

/// A lens, in both forms: its name while the bar has room for ten of them, its
/// initial when it has not. The narrow form is the same control, not a
/// different one.
BarItem _lens(BuildContext c, String lensId, bool active, String? tile) {
  final chrome = ChromeScope.of(c);
  final theme = ChronoTheme.of(c);
  final spec = lensCatalog[lensId]!;
  Widget chip(String text) => controlChip(
    c,
    active: active,
    hint: spec.description,
    // Shift is the "and keep the one I have" modifier, everywhere.
    onTap: () => HardwareKeyboard.instance.isShiftPressed || tile == null
        ? openViewTile(chrome, lensId: lensId)
        : chrome.stage.swapLens(tile, lensId),
    child: Text(text, style: bodyStyle(c, color: active ? theme.ink : theme.strong)),
  );
  return (label: spec.title, full: chip(spec.title), compact: chip(spec.title.substring(0, 1)));
}
