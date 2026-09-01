// The one menu. Every bar drop and every right-click surface is this class, so
// edge-flip, dismissal, focus return and z-order are properties of the menu
// rather than of the site that opened it.
//
// A bar is ONE instrument: opening a menu closes whatever menu was open.

import 'package:flutter/material.dart';

import '../lens/theme.dart';
import 'controls.dart';

/// A row of a menu. A null [onTap] is a stated refusal, not a mystery: the row
/// stays visible and carries its reason.
typedef MenuRow = ({String label, String? hint, VoidCallback? onTap, bool active});

MenuRow menuRow(String label, VoidCallback? onTap, {String? hint, bool active = false}) =>
    (label: label, hint: hint, onTap: onTap, active: active);

MenuController? _open;

/// The Escape cascade's first rung: close whatever menu is open, and say
/// whether there was one.
bool closeOpenMenu() {
  if (_open?.isOpen != true) return false;
  _open!.close();
  return true;
}

class ChronoMenu extends StatefulWidget {
  const ChronoMenu({
    super.key,
    required this.label,
    this.rows = const [],
    this.glyph,
    this.name,
    this.body,
  });

  final String label;
  final String? glyph;

  /// The WORDS a drop wears beside its reading, for a control whose glyph is a
  /// VALUE rather than a mark: the reading answers "what", the name answers "of
  /// what". A drop whose glyph is already a mark needs no name beside it, and
  /// says nothing here.
  final String? name;
  final List<MenuRow> rows;

  /// A panel that is not a list of rows -- the projection control's frame rows,
  /// a lens's own options. It rides in the same panel, so placement, dismissal
  /// and mutual exclusion stay properties of the menu, not of the site.
  final Widget Function(BuildContext, VoidCallback close)? body;

  @override
  State<ChronoMenu> createState() => _ChronoMenuState();
}

class _ChronoMenuState extends State<ChronoMenu> {
  final MenuController _controller = MenuController();

  void _toggle() {
    if (_controller.isOpen) return _controller.close();
    if (_open != _controller) _open?.close();
    _open = _controller;
    _controller.open();
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.of(context);
    return MenuAnchor(
      controller: _controller,
      menuChildren: [
        SizedBox(
          width: chrome.px('chrome.menuWidth'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final row in widget.rows) menuTile(context, row, close: _controller.close),
              if (widget.body != null) widget.body!(context, _controller.close),
            ],
          ),
        ),
      ],
      child: controlChip(
        context,
        label: widget.name ?? '',
        hint: widget.label,
        onTap: _toggle,
        button: true,
        semantics: widget.name == null ? widget.label : null,
        child: Text(
          widget.glyph ?? widget.label,
          style: (widget.glyph == null ? bodyStyle : dataStyle)(context),
        ),
      ),
    );
  }
}

/// One rendered row. [close] absent means the surrounding surface owns the tap.
Widget menuTile(BuildContext c, MenuRow row, {VoidCallback? close}) {
  final chrome = ChromeScope.of(c);
  final theme = ChronoTheme.of(c);
  final tile = Container(
    height: chrome.px('chrome.rowHeight'),
    alignment: Alignment.centerLeft,
    padding: EdgeInsets.symmetric(horizontal: chrome.px('chrome.pad')),
    color: row.active ? theme.primary.withValues(alpha: 0.10) : null,
    child: Row(
      children: [
        Expanded(
          child: Text(
            row.label,
            overflow: TextOverflow.ellipsis,
            style: bodyStyle(c, color: row.onTap == null ? theme.hair : theme.ink),
          ),
        ),
        if (row.hint != null)
          Text(row.hint!, overflow: TextOverflow.ellipsis, style: labelStyle(c)),
      ],
    ),
  );
  return close == null || row.onTap == null
      ? tile
      : InkWell(
          onTap: () {
            close();
            row.onTap!();
          },
          child: tile,
        );
}

/// The owned right-click surface: the same rows, at a point. Every lens and
/// every tile uses this rather than letting a platform menu answer for it.
Future<void> showChronoMenu(BuildContext context, Offset at, List<MenuRow> rows) {
  _open?.close();
  final chrome = ChromeScope.of(context);
  final theme = ChronoTheme.of(context);
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  return showMenu<void>(
    context: context,
    color: theme.surface,
    position: RelativeRect.fromRect(at & Size.zero, Offset.zero & overlay.size),
    items: [
      for (final row in rows)
        PopupMenuItem<void>(
          padding: EdgeInsets.zero,
          height: chrome.px('chrome.rowHeight'),
          enabled: row.onTap != null,
          onTap: row.onTap,
          child: SizedBox(width: chrome.px('chrome.menuWidth'), child: menuTile(context, row)),
        ),
    ],
  );
}
