// The stage, drawn: the layout tree as widgets.
//
// One recursive walk, one divider service, one tab strip. Bars, the minimap,
// lenses and cards all arrive here as tiles; nothing below asks what type a
// tile is, and there is no floating layer to ask about. Motion is
// transform-only and retargets rather than queueing.
//
// WHAT YOU DRAG IS VISIBLE (ruled 2026-08-28). Every tile wears a permanent
// handle: a strip carrying one tab per tile in its stack, each with its own
// label and its own close, the strip itself the thing you drag and the surface
// you right-click. A bar, which has no thickness to spare, wears the same
// handle as a grip at its leading end. The hover-reveal box is gone -- an
// affordance you have to discover by hovering is not an affordance.
//
// A BAR IS A TILE LIKE ANY OTHER. Its content thickness is what it takes when
// it is first placed and the LEAST it will ever take; above that it is dragged,
// tabbed, dropped on, zoomed and persisted exactly like a lens. What the
// placement rules keep out of the chrome is the DEFAULT landing, never a
// deliberate one: the arrangement is the user's, and nothing here prevents one.
//
// THE DELIVERABLE IS CONTROL (Don, 2026-08-28): "I can't configure them cleanly
// to a good size or move my main lens to take some of the space back over."
// Hence a seam that tracks the pointer with no ladder, a double-click that
// resets one seam, a zoom that gives one tile the stage and hands the
// arrangement back untouched, and a swap that trades two tiles without
// disturbing a single size.

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../chrome/controls.dart';
import '../chrome/menus.dart';
import '../core/exact.dart';
import '../core/math.dart';
import '../lens/theme.dart';
import 'layout_tree.dart';

/// Stage geometry, as named settings.
const Map<String, String> stageTunableDefaults = {
  'stage.divider': '4',
  // The hand's target is wider than the painted line, so a seam is easy to
  // catch without drawing a bar of chrome to catch it with.
  'stage.dividerHit': '11',
  'stage.strip': '22',
  // The grip a bar wears instead of a strip: its leading end, costing the bar
  // no thickness at all.
  'stage.grip': '12',
  // A bar's least thickness across its container's axis: its height in a
  // column, its width in the rarer row. A floor, never a fixed size.
  'stage.barWidth': '240',
  // What the shipped preset gives a bar before that floor raises it: small, so
  // a bar arrives at its own content thickness and grows only when dragged.
  'stage.barShare': '1/64',
  'stage.minimapWidth': '1/5',
  'stage.edgeZone': '0.28',
  'stage.nudge': '1/64',
  'stage.splitRatio': '1/2',
  'stage.maxTabs': '6',
  'stage.dropWash': '0.16',
  // A zoomed tile keeps the chrome with it: the bars are how you get back.
  'stage.zoomKeepsBars': 'true',
};

/// A FORMULA setting: read against a bound `ratio` rather than on its own, so
/// it is not arithmetic the settings layer can evaluate and does not belong
/// with the tunables. The shipped value is the identity -- a divider tracks the
/// pointer and lands where it was let go. Snap rungs are opt-in and authored
/// here (`floor(ratio * 4 + 1/2) / 4` for quarters), not a shipped ladder with
/// a gate beside it (ruled 2026-08-28).
const Map<String, String> stageTextDefaults = {'stage.snapTo': 'ratio'};

class StageView extends StatelessWidget {
  const StageView({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ChromeScope.of(context).stage.listenable,
    builder: (context, _) {
      final root = ChromeScope.of(context).stage.displayRoot;
      return root == null ? const SizedBox.expand() : _node(context, root);
    },
  );
}

Widget _node(BuildContext c, LayoutNode node) => switch (node) {
  TileLeaf leaf => _Tile(key: ValueKey(leaf.id), leaf: leaf),
  Branch b when b.mode == 'tabs' => _tabs(c, b),
  Branch b when b.mode == 'dwindle' => _dwindle(c, b, 0, b.axis),
  Branch b => _split(c, b),
};

Widget _flex(bool horizontal, List<Widget> parts) =>
    horizontal ? Row(children: parts) : Column(children: parts);

Widget _sized(bool horizontal, double extent, Widget child) =>
    SizedBox(width: horizontal ? extent : null, height: horizontal ? null : extent, child: child);

/// The LEAST a node may be given along an axis -- its content thickness. A bar
/// knows how thick it needs to be; every other tile takes what it is given.
double leastExtent(Chrome chrome, LayoutNode node, bool horizontal) {
  if (node is TileLeaf) {
    if (node.type != 'bar') return 0;
    return horizontal ? chrome.px('stage.barWidth') : chrome.px('chrome.barHeight');
  }
  if (node is! Branch || node.children.isEmpty) return 0;
  final along = node.mode == 'split' && (node.axis == 'row') == horizontal;
  var total = 0.0;
  for (final child in node.children) {
    final extent = leastExtent(chrome, child, horizontal);
    total = along ? total + extent : (extent > total ? extent : total);
  }
  return along ? total + chrome.px('stage.divider') * (node.children.length - 1) : total;
}

/// Ratios first, minimums second: every child takes its share, and a child
/// whose share falls under its content thickness is raised to it out of the
/// slack the others are carrying.
List<double> splitExtents(List<double> shares, List<double> least, double span) {
  final extents = [for (final share in shares) share * span];
  var owed = 0.0, slack = 0.0;
  for (final (index, extent) in extents.indexed) {
    if (extent < least[index]) {
      owed += least[index] - extent;
      extents[index] = least[index];
    } else {
      slack += extent - least[index];
    }
  }
  if (owed <= 0 || slack <= 0) return extents;
  for (final (index, extent) in extents.indexed) {
    final spare = extent - least[index];
    if (spare > 0) extents[index] = extent - owed * (spare / slack);
  }
  return extents;
}

Widget _split(BuildContext outer, Branch branch) {
  final horizontal = branch.axis == 'row';
  final chrome = ChromeScope.of(outer);
  final gap = chrome.px('stage.divider');
  final least = [for (final child in branch.children) leastExtent(chrome, child, horizontal)];
  return LayoutBuilder(
    builder: (c, box) {
      final raw = (horizontal ? box.maxWidth : box.maxHeight) - gap * (branch.children.length - 1);
      final span = raw < 0 ? 0.0 : raw;
      final extents = splitExtents(
        [for (final ratio in branch.ratios) ratio.toDouble()],
        least,
        span,
      );
      final parts = <Widget>[];
      for (final (index, child) in branch.children.indexed) {
        parts.add(_sized(horizontal, extents[index].clamp(0.0, span), _node(c, child)));
        if (index < branch.children.length - 1) {
          parts.add(
            _Divider(
              branch: branch,
              index: index,
              horizontal: horizontal,
              span: span,
              least: least,
            ),
          );
        }
      }
      return _flex(horizontal, parts);
    },
  );
}

/// Golden-spiral tiling: the first child takes its share, the rest dwindle on
/// the flipped axis. The tree stays flat; the alternation lives here.
Widget _dwindle(BuildContext outer, Branch branch, int from, String axis) {
  if (branch.children.length - from <= 1) return _node(outer, branch.children[from]);
  final horizontal = axis == 'row';
  final divider = ChromeScope.of(outer).px('stage.divider');
  return LayoutBuilder(
    builder: (c, box) {
      final span = (horizontal ? box.maxWidth : box.maxHeight) - divider;
      final head = span * branch.ratio.toDouble();
      return _flex(horizontal, [
        _sized(horizontal, head, _node(c, branch.children[from])),
        _sized(horizontal, divider, const SizedBox.shrink()),
        _sized(
          horizontal,
          span - head,
          _dwindle(c, branch, from + 1, horizontal ? 'column' : 'row'),
        ),
      ]);
    },
  );
}

/// The authored snap, or the identity. A refusal costs the snap and nothing
/// else -- the drag still lands where the pointer left it.
Rational Function(Rational) settleWith(Chrome chrome) {
  final source = chrome.settings.text('stage.snapTo');
  return (ratio) {
    try {
      final read = evaluateSource(source, Env(values: {'ratio': ratio}));
      return read is Rational && read > Rational.zero && read < Rational.one ? read : ratio;
    } on MathRefusal {
      return ratio;
    }
  };
}

/// ONE VISIBLE SEAM IS ONE DIVIDER (ruled 2026-08-28). Every divider on screen
/// registers here so a drag can gather the ones collinear and contiguous with
/// it -- however many containers meet along that line -- and move them together
/// for the whole gesture.
final Set<_DividerState> _liveDividers = {};

class _Divider extends StatefulWidget {
  const _Divider({
    required this.branch,
    required this.index,
    required this.horizontal,
    required this.span,
    required this.least,
  });

  final Branch branch;
  final int index;
  final bool horizontal;

  /// The pixels the container has to divide: what turns a drag into a ratio.
  final double span;

  /// Each child's content thickness, so a double-click can put this one seam
  /// back to what the container would give it by default.
  final List<double> least;

  @override
  State<_Divider> createState() => _DividerState();
}

class _DividerState extends State<_Divider> {
  List<_DividerState> _seam = const [];

  @override
  void initState() {
    super.initState();
    _liveDividers.add(this);
  }

  @override
  void dispose() {
    _liveDividers.remove(this);
    super.dispose();
  }

  bool get _horizontal => widget.horizontal;

  Rect? get _rect {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _move(double pixels, {bool settle = false}) {
    if (!mounted || widget.span <= 0) return;
    final chrome = ChromeScope.of(context);
    setRatio(
      widget.branch,
      widget.index,
      widget.branch.ratios[widget.index] +
          Rational.parse((pixels / widget.span).toStringAsFixed(6)),
      settle ? settleWith(chrome) : null,
    );
    chrome.stage.touch();
  }

  /// One seam, back to the container's default: the near child's own content
  /// thickness where it has one, an even share of the pair where it does not.
  void _reset() {
    final index = widget.index;
    final pair = widget.branch.ratios[index] + widget.branch.ratios[index + 1];
    final least = widget.least[index];
    final wanted = least > 0 && widget.span > 0
        ? Rational.parse((least / widget.span).toStringAsFixed(6))
        : pair / Rational.fromInt(2);
    setRatio(widget.branch, index, wanted);
    ChromeScope.of(context).stage.touch();
  }

  /// Collinear and contiguous: the same axis, the same pixel line, extents that
  /// touch. Grown transitively, so a run of three stacked seams is one seam.
  void _resolveSeam() {
    final mine = _rect;
    if (mine == null) return;
    final tolerance = ChromeScope.of(context).px('stage.dividerHit');
    final pool = [
      for (final divider in _liveDividers)
        if (divider != this && divider._horizontal == _horizontal && divider._rect != null) divider,
    ];
    final chosen = <_DividerState>[this];
    final rects = <Rect>[mine];
    for (var grew = true; grew;) {
      grew = false;
      for (final divider in pool) {
        if (chosen.contains(divider)) continue;
        final rect = divider._rect!;
        if (!rects.any((held) => _touching(held, rect, _horizontal, tolerance))) continue;
        chosen.add(divider);
        rects.add(rect);
        grew = true;
      }
    }
    _seam = chosen;
  }

  void _drag(double pixels, {bool settle = false}) {
    for (final divider in _seam) {
      divider._move(pixels, settle: settle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.of(context);
    final theme = ChronoTheme.of(context);
    final painted = chrome.px('stage.divider');
    final line = _sized(_horizontal, chrome.px('chrome.hair'), ColoredBox(color: theme.hair));
    final nudge = chrome.settings.value('stage.nudge').toDouble();
    final back = _horizontal ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowUp;
    final on = _horizontal ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowDown;
    final hit = chrome.px('stage.dividerHit');
    return _sized(
      _horizontal,
      painted,
      Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey != back && event.logicalKey != on) return KeyEventResult.ignored;
          _seam = [this];
          _drag(event.logicalKey == back ? -nudge : nudge, settle: true);
          return KeyEventResult.handled;
        },
        child: MouseRegion(
          cursor: _horizontal ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
          child: OverflowBox(
            maxWidth: _horizontal ? hit : null,
            maxHeight: _horizontal ? null : hit,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: _reset,
              onHorizontalDragStart: _horizontal ? (_) => _resolveSeam() : null,
              onHorizontalDragUpdate: _horizontal ? (d) => _drag(d.delta.dx) : null,
              onHorizontalDragEnd: _horizontal ? (_) => _drag(0, settle: true) : null,
              onVerticalDragStart: _horizontal ? null : (_) => _resolveSeam(),
              onVerticalDragUpdate: _horizontal ? null : (d) => _drag(d.delta.dy),
              onVerticalDragEnd: _horizontal ? null : (_) => _drag(0, settle: true),
              child: Container(
                width: _horizontal ? hit : null,
                height: _horizontal ? null : hit,
                color: const Color(0x00000000),
                alignment: Alignment.center,
                child: line,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _touching(Rect a, Rect b, bool horizontal, double tolerance) => horizontal
    ? (a.center.dx - b.center.dx).abs() <= tolerance &&
          a.top <= b.bottom + tolerance &&
          b.top <= a.bottom + tolerance
    : (a.center.dy - b.center.dy).abs() <= tolerance &&
          a.left <= b.right + tolerance &&
          b.left <= a.right + tolerance;

Widget _tabs(BuildContext c, Branch branch) {
  final chrome = ChromeScope.of(c);
  final active = branch.active.clamp(0, branch.children.length - 1);
  final leaves = [for (final child in branch.children) ?edgeLeaf(child, false)];
  return Listener(
    onPointerSignal: (signal) {
      if (signal is! PointerScrollEvent || !HardwareKeyboard.instance.isControlPressed) return;
      final count = branch.children.length;
      final leaf = edgeLeaf(
        branch.children[(active + (signal.scrollDelta.dy > 0 ? 1 : count - 1)) % count],
        false,
      );
      if (leaf != null) chrome.stage.focus(leaf.id);
    },
    child: Column(
      children: [
        _Strip(leaves: leaves, activeId: leaves.isEmpty ? '' : leaves[active].id, branch: branch),
        Expanded(
          child: AnimatedSwitcher(
            duration: chrome.motion,
            switchInCurve: chrome.curve,
            switchOutCurve: chrome.curve,
            // Transform only: a tab arrives by sliding, never by resizing.
            transitionBuilder: (child, animation) => SlideTransition(
              position: Tween(begin: const Offset(0.03, 0), end: Offset.zero).animate(animation),
              child: child,
            ),
            child: KeyedSubtree(
              key: ValueKey(branch.children[active].id),
              child: _node(c, branch.children[active]),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The verbs a handle offers without a drag, with their chords, so what the
/// hand can do and what the keyboard can do are one list.
List<MenuRow> stripMenu(BuildContext c, TileLeaf leaf) {
  final chrome = ChromeScope.of(c);
  final stage = chrome.stage;
  final others = [
    for (final other in stage.leaves)
      if (other.id != leaf.id) other,
  ];
  String title(TileLeaf of) => stage.tiles[of.id]?.title ?? of.title;
  String chord(String way) =>
      chrome.settings.text('keys.move${way[0].toUpperCase()}${way.substring(1)}');
  return [
    menuRow(
      stage.zoomedId == leaf.id ? 'Unzoom' : 'Zoom',
      () => stage.toggleZoom(leaf.id),
      hint: chrome.settings.text('keys.zoomTile'),
      active: stage.zoomedId == leaf.id,
    ),
    for (final way in const ['left', 'right', 'up', 'down'])
      menuRow('Split $way', () => stage.splitToward(leaf.id, way), hint: chord(way)),
    for (final other in others)
      menuRow('Tab with ${title(other)}', () => stage.tabUnder(leaf.id, other.id)),
    for (final other in others)
      menuRow('Swap with ${title(other)}', () => stage.swap(leaf.id, other.id)),
    if (others.isEmpty) menuRow('Tab or swap with…  (no other tile is open)', null),
    menuRow('Reset sizes', stage.evenRatios),
    menuRow('Close', () => stage.close(leaf.id), hint: chrome.settings.text('keys.closeTile')),
    menuRow('Close others', others.isEmpty ? null : () => stage.closeOthers(leaf.id)),
  ];
}

/// THE handle: what you drag a tile by and what you right-click on. A strip
/// wears it across the top; a bar wears it as a grip at its leading end.
Widget tileGrab(BuildContext context, TileLeaf leaf, Widget child) {
  final chrome = ChromeScope.of(context);
  final theme = ChronoTheme.of(context);
  final title = chrome.stage.tiles[leaf.id]?.title ?? leaf.title;
  return MouseRegion(
    cursor: SystemMouseCursors.grab,
    child: GestureDetector(
      onTap: () => chrome.stage.focus(leaf.id),
      onDoubleTap: () => chrome.stage.toggleZoom(leaf.id),
      onSecondaryTapUp: (details) =>
          showChronoMenu(context, details.globalPosition, stripMenu(context, leaf)),
      child: Draggable<String>(
        data: leaf.id,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(
          color: theme.surface,
          child: Padding(
            padding: EdgeInsets.all(chrome.px('chrome.pad')),
            child: Text(title, style: labelStyle(context, color: theme.ink)),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: child),
        child: child,
      ),
    ),
  );
}

/// A drop onto a handle: SWAP under a modifier, reorder within the stack,
/// otherwise tab into it. One rule, wherever a handle is.
void dropOnHandle(BuildContext context, TileLeaf leaf, String from, {Branch? stack}) {
  final stage = ChromeScope.of(context).stage;
  final keys = HardwareKeyboard.instance;
  if (keys.isControlPressed || keys.isAltPressed) return stage.swap(from, leaf.id);
  final at = stack?.children.indexWhere((child) => edgeLeaf(child, false)?.id == from) ?? -1;
  if (stack != null && at >= 0) {
    reorderChild(stack, at, stack.children.indexWhere((c) => edgeLeaf(c, false)?.id == leaf.id));
    stage.focus(from);
    return;
  }
  stage.move(from, leaf.id, 'center');
}

/// The always-visible strip: one tab per tile in the stack, the active one
/// distinguished by INK rather than by colour, each with its own close, and the
/// whole strip the handle you drag the tile by.
class _Strip extends StatelessWidget {
  const _Strip({required this.leaves, required this.activeId, this.branch});

  final List<TileLeaf> leaves;
  final String activeId;
  final Branch? branch;

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.of(context);
    final theme = ChronoTheme.of(context);
    if (leaves.isEmpty) return const SizedBox.shrink();
    final active = leaves.where((leaf) => leaf.id == activeId).firstOrNull;
    return SizedBox(
      height: chrome.px('stage.strip'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.surface,
          border: Border(
            bottom: BorderSide(color: theme.hair, width: chrome.px('chrome.hair')),
          ),
        ),
        // THE WHOLE STRIP IS THE HANDLE, with the tabs riding on it at their
        // own width and CLIPPED rather than squeezed: a strip is a tile's own
        // width and a tile is any width, down to a sliver.
        child: tileGrab(
          context,
          active ?? leaves.first,
          ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: double.infinity,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [for (final leaf in leaves) _tab(context, leaf, leaf.id == activeId)],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, TileLeaf leaf, bool active) {
    final chrome = ChromeScope.of(context);
    final theme = ChronoTheme.of(context);
    final title = chrome.stage.tiles[leaf.id]?.title ?? leaf.title;
    final cap = chrome.settings.value('chrome.labelCap').round().toInt();
    final body = Container(
      padding: EdgeInsets.symmetric(horizontal: chrome.px('chrome.pad')),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: active ? theme.ink : const Color(0x00000000),
            width: chrome.px('chrome.focusRing'),
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title.length > cap ? '${title.substring(0, cap)}…' : title,
            style: labelStyle(context, color: active ? theme.ink : theme.strong),
          ),
          SizedBox(width: chrome.px('chrome.gap')),
          Semantics(
            label: 'Close $title',
            button: true,
            // No confirmation, anywhere: reversibility over interruption.
            child: InkWell(
              onTap: () => chrome.stage.close(leaf.id),
              child: Text('×', style: labelStyle(context, color: theme.strong)),
            ),
          ),
        ],
      ),
    );
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != leaf.id,
      onAcceptWithDetails: (details) => dropOnHandle(context, leaf, details.data, stack: branch),
      builder: (context, candidate, _) => tileGrab(
        context,
        leaf,
        candidate.isEmpty
            ? body
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.ink.withValues(alpha: chrome.px('stage.dropWash')),
                ),
                child: body,
              ),
      ),
    );
  }
}

/// A bar's handle: the same verbs, as a grip at its leading end, so chrome is
/// as movable as anything else without spending a strip's worth of thickness.
Widget _grip(BuildContext context, TileLeaf leaf) {
  final chrome = ChromeScope.of(context);
  final theme = ChronoTheme.of(context);
  return DragTarget<String>(
    onWillAcceptWithDetails: (details) => details.data != leaf.id,
    onAcceptWithDetails: (details) => dropOnHandle(context, leaf, details.data),
    builder: (context, candidate, _) => tileGrab(
      context,
      leaf,
      Container(
        width: chrome.px('stage.grip'),
        color: candidate.isEmpty
            ? theme.surface
            : theme.ink.withValues(alpha: chrome.px('stage.dropWash')),
        alignment: Alignment.center,
        child: Text('⋮', style: labelStyle(context, color: theme.strong)),
      ),
    ),
  );
}

class _Tile extends StatefulWidget {
  const _Tile({super.key, required this.leaf});

  final TileLeaf leaf;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  String? _zone;

  /// Which region a drop would land in: four edges split, the centre tabs.
  String _zoneAt(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return 'center';
    final local = box.globalToLocal(global);
    final edge = ChromeScope.of(context).px('stage.edgeZone');
    if (local.dx < box.size.width * edge) return 'left';
    if (local.dx > box.size.width * (1 - edge)) return 'right';
    if (local.dy < box.size.height * edge) return 'up';
    if (local.dy > box.size.height * (1 - edge)) return 'down';
    return 'center';
  }

  /// The live preview: an ink wash over the region the drop would take, with
  /// the resulting split drawn as its outline.
  Widget _preview(BuildContext context, String zone) {
    final chrome = ChromeScope.of(context);
    final theme = ChronoTheme.of(context);
    final (align, wide, tall) = switch (zone) {
      'left' => (Alignment.centerLeft, 0.5, 1.0),
      'right' => (Alignment.centerRight, 0.5, 1.0),
      'up' => (Alignment.topCenter, 1.0, 0.5),
      'down' => (Alignment.bottomCenter, 1.0, 0.5),
      _ => (Alignment.center, 1.0, 1.0),
    };
    return IgnorePointer(
      child: Align(
        alignment: align,
        child: FractionallySizedBox(
          widthFactor: wide,
          heightFactor: tall,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.ink.withValues(alpha: chrome.px('stage.dropWash')),
              border: Border.all(color: theme.ink, width: chrome.px('chrome.focusRing')),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.of(context);
    final theme = ChronoTheme.of(context);
    final id = widget.leaf.id;
    final focused = chrome.stage.focusedId == id;
    final tabbed = parentOf(chrome.stage.displayRoot, id)?.mode == 'tabs';
    final handled = !tabbed && chrome.stage.leaves.length > 1;
    final body =
        chrome.stage.tiles[id]?.build(context) ??
        Center(child: Text('No tile named $id is open.', style: labelStyle(context)));
    // EVERY TILE BODY SITS ON PAPER. A painter draws marks, not a ground;
    // without this the window's own black shows through the surface.
    final ground = ColoredBox(color: theme.paper, child: body);
    final stack = widget.leaf.type == 'bar'
        // A bar has no thickness to spend on a strip, so its handle rides at
        // its leading end instead. Same verbs, same drop, no lost height.
        ? Row(
            children: [
              if (handled) _grip(context, widget.leaf),
              Expanded(child: ground),
            ],
          )
        : Column(
            children: [
              if (handled) _Strip(leaves: [widget.leaf], activeId: id),
              Expanded(child: ground),
            ],
          );
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => chrome.stage.focus(id),
      child: DragTarget<String>(
        // Every tile receives a drop, bars included: what the placement rules
        // keep out of the chrome is the DEFAULT landing, never a deliberate one.
        onWillAcceptWithDetails: (details) => details.data != id,
        onMove: (details) {
          final zone = _zoneAt(details.offset);
          if (zone != _zone) setState(() => _zone = zone);
        },
        onLeave: (_) => setState(() => _zone = null),
        onAcceptWithDetails: (details) {
          final zone = _zone ?? 'center';
          setState(() => _zone = null);
          chrome.stage.move(details.data, id, zone);
        },
        builder: (context, candidate, _) => DecoratedBox(
          // Selection and focus are INK, never a colour.
          decoration: BoxDecoration(
            border: Border.all(
              color: focused ? theme.strong : const Color(0x00000000),
              width: chrome.px('chrome.focusRing'),
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(child: stack),
              if (candidate.isNotEmpty && _zone != null)
                Positioned.fill(child: _preview(context, _zone!)),
            ],
          ),
        ),
      ),
    );
  }
}
