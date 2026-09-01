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
          // Const, and it makes no difference now: the control OWNS ITS OWN
          // LISTENING (ISSUES 9.1). Handing an identical widget instance to
          // this ListenableBuilder every build is what froze the open drop --
          // Flutter skips a child it has already been given -- so the fix is
          // that no control reading live state may depend on a parent to
          // rebuild it.
          trailing: [barItem('Projection', const ProjectionControl())],
        );
      },
    );
  }
}

/// A lens, in both forms: its name while the bar has room for ten of them, its
/// initial when it has not. The narrow form is the same control, not a
/// different one.
///
/// HIDING IS A VERB ON THE CHIP (ISSUES 9.1, Don: "I can't find the setting to
/// hide some of them behind a button" / "no way to hide lenses behind the
/// button"). The Hidden-lenses drop was only ever the way BACK -- `setHidden(id,
/// true)` had no call site anywhere -- so the verb goes where the hand already
/// is, on the lens itself.
BarItem _lens(BuildContext c, String lensId, bool active, String? tile) {
  final chrome = ChromeScope.of(c);
  final theme = ChronoTheme.of(c);
  final spec = lensCatalog[lensId]!;
  Widget chip(String text) => controlChip(
    c,
    active: active,
    hint: spec.description,
    semantics: spec.title,
    // Shift is the "and keep the one I have" modifier, everywhere.
    onTap: () => HardwareKeyboard.instance.isShiftPressed || tile == null
        ? openViewTile(chrome, lensId: lensId)
        : chrome.stage.swapLens(tile, lensId),
    onMenu: (at) => showChronoMenu(c, at, lensChipMenu(c, lensId)),
    child: Text(text, style: bodyStyle(c, color: active ? theme.ink : theme.strong)),
  );
  return (label: spec.title, full: chip(spec.title), compact: chip(spec.title.substring(0, 1)));
}

/// A lens chip's own verbs. Hiding the LAST visible lens is refused in words:
/// a bar with no lens on it has no way back to one, and the drop that restores
/// hangs off the bar.
List<MenuRow> lensChipMenu(BuildContext c, String lensId) {
  final chrome = ChromeScope.of(c);
  final spec = lensCatalog[lensId]!;
  final visible = chrome.views.visibleLenses;
  final tile = chrome.stage.focusedViewTile;
  return [
    menuRow(
      visible.length > 1
          ? 'Hide ${spec.title}'
          : 'Hide ${spec.title} — it is the last lens on the bar, so nothing would bring it back',
      visible.length > 1 ? () => chrome.views.setHidden(lensId, true) : null,
      hint: visible.length > 1 ? 'Hidden lenses' : null,
    ),
    menuRow(
      'Open ${spec.title} in a new view',
      chrome.viewTile == null ? null : () => openViewTile(chrome, lensId: lensId),
    ),
    if (tile != null)
      menuRow('Show ${spec.title} here', () => chrome.stage.swapLens(tile, lensId)),
    ...settingsRows(c, lensId, spec.title),
  ];
}
