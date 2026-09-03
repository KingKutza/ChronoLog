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
///
/// A row carrying [rows] is a SUB-ITEM (ISSUES 9.2, Don: "there is already a
/// huge context menu on the triple dot -- our menu will have to slot neatly
/// into a sub-item on that one"). Depth is a property of a row rather than a
/// second row class, so every site that already builds rows can nest without
/// learning anything new, and every surface that renders rows renders depth.
class MenuRow {
  const MenuRow(this.label, {this.hint, this.onTap, this.active = false, this.rows = const []});

  final String label;
  final String? hint;
  final VoidCallback? onTap;
  final bool active;
  final List<MenuRow> rows;

  /// What a press on this row does: its own verb, or opening what it holds.
  bool get opens => rows.isNotEmpty;
}

MenuRow menuRow(
  String label,
  VoidCallback? onTap, {
  String? hint,
  bool active = false,
  List<MenuRow> rows = const [],
}) => MenuRow(label, hint: hint, onTap: onTap, active: active, rows: rows);

/// The mark a row wears to say it holds more. A sub-item is a door, and a door
/// that looks like a dead label is the thing this vocabulary exists to avoid.
const String submenuMark = '›';

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
    this.cap,
    this.onMenu,
  });

  /// The drop's own right-click. A drop whose glyph is a READING names
  /// something, and what it names has verbs of its own.
  final void Function(Offset at)? onMenu;

  final String label;
  final String? glyph;

  /// The widest this drop's glyph may draw, in pixels, for a glyph that is a
  /// READING rather than a mark: a value grows with the document and the bar it
  /// sits on does not. Absent, the glyph draws at whatever width it wants.
  final double? cap;

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

  Widget _capped(Widget child) => widget.cap == null
      ? child
      : ConstrainedBox(constraints: BoxConstraints(maxWidth: widget.cap!), child: child);

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
              for (final row in widget.rows)
                menuTile(
                  context,
                  row,
                  close: _controller.close,
                  onOpen: (at) => showChronoMenu(context, at, row.rows),
                ),
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
        onMenu: widget.onMenu,
        button: true,
        semantics: widget.name == null ? widget.label : null,
        child: _capped(
          Text(
            widget.glyph ?? widget.label,
            overflow: widget.cap == null ? null : TextOverflow.ellipsis,
            softWrap: widget.cap == null,
            style: (widget.glyph == null ? bodyStyle : dataStyle)(context),
          ),
        ),
      ),
    );
  }
}

/// One rendered row. [close] absent means the surrounding surface owns the tap.
Widget menuTile(
  BuildContext c,
  MenuRow row, {
  VoidCallback? close,
  void Function(Offset at)? onOpen,
}) {
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
        // FLEXIBLE, NOT FIXED (ISSUES 9.2: "the Hidden-lenses drop overflows
        // because a menu row's hint is not flexible"). A hint is a whole
        // sentence on some rows -- a lens's description -- and an unbounded
        // Text beside an Expanded label is a yellow bar the moment one is
        // longer than the room left over.
        if (row.hint != null)
          Flexible(child: Text(row.hint!, overflow: TextOverflow.ellipsis, style: labelStyle(c))),
        if (row.opens) Text(submenuMark, style: labelStyle(c)),
      ],
    ),
  );
  return close == null || (row.onTap == null && !row.opens)
      ? tile
      : Builder(
          builder: (c) => InkWell(
            onTap: () {
              close();
              if (row.opens && onOpen != null) {
                final box = c.findRenderObject() as RenderBox?;
                onOpen(
                  box == null
                      ? Offset.zero
                      : box.localToGlobal(box.size.bottomLeft(Offset.zero)),
                );
                return;
              }
              row.onTap?.call();
            },
            child: tile,
          ),
        );
}

/// A PANEL AT A POINT: the same surface, holding something that is not a list
/// of rows -- a field, a chooser. It is [showChronoMenu]'s own body rule said at
/// a point rather than under a chip, so placement, dismissal and z-order stay
/// properties of the menu and no site grows an overlay of its own.
Future<void> showChronoPanel(BuildContext context, Offset at, Widget child) {
  final chrome = ChromeScope.of(context);
  final theme = ChronoTheme.of(context);
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  return showMenu<void>(
    context: context,
    color: theme.surface,
    position: RelativeRect.fromRect(at & Size.zero, Offset.zero & overlay.size),
    items: [
      PopupMenuItem<void>(
        padding: EdgeInsets.all(chrome.px('chrome.pad')),
        enabled: false,
        // THE SCOPE COMES WITH IT. A panel is built inside the overlay, which
        // sits ABOVE the scope every control reads its numbers from -- so a
        // control that would find the chrome anywhere else finds nothing here.
        // The rows of a menu are built eagerly at the call site and never meet
        // this; a panel holds a live widget, so it carries the scope in.
        child: ChromeScope(
          chrome: chrome,
          child: SizedBox(width: chrome.px('chrome.menuWidth'), child: child),
        ),
      ),
    ],
  );
}

/// The owned right-click surface: the same rows, at a point. Every lens and
/// every tile uses this rather than letting a platform menu answer for it.
///
/// AN OPEN DROP STAYS OPEN. A right-click on a row INSIDE a drop is about that
/// row, and closing the drop out from under it leaves a menu describing
/// something the eye can no longer see. "A bar is ONE instrument" is a rule
/// about two DROPS, not about a drop and the right-click on its own contents.
Future<void> showChronoMenu(BuildContext context, Offset at, List<MenuRow> rows) {
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
          enabled: row.onTap != null || row.opens,
          // A SUB-ITEM OPENS ITS OWN PANEL at the point the parent stood, so
          // depth costs the surrounding menu nothing: the same one class draws
          // it, and dismissal, edge-flip and z-order stay the menu's own.
          onTap: row.opens ? () => showChronoMenu(context, at, row.rows) : row.onTap,
          child: SizedBox(width: chrome.px('chrome.menuWidth'), child: menuTile(context, row)),
        ),
    ],
  );
}
