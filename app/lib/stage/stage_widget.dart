// The stage, drawn: the layout tree as widgets.
//
// One recursive walk, one divider service, one tab strip. Bars, the minimap,
// lenses and cards all arrive here as tiles; nothing below asks what type a
// tile is, and there is no floating layer to ask about. Motion is
// transform-only and retargets rather than queueing.
//
// A STACK WEARS A STRIP; A LONE WINDOW WEARS NOTHING AT ALL (ISSUES 9.1, Don:
// "Single tabs have been replaced with a nontab title in the same place,
// defeating the purpose of removing them. The point was that the bar disappeared
// on a single tab"). Two tiles or more is a stack, and a stack's strip is one
// tab per tile with its own label and its own close, the strip itself the thing
// you drag and the surface you right-click. One tile is a WINDOW: no bar, no
// name, no grip -- nothing rests, and the tile spends no thickness on chrome.
// Its drag point is the triple dot the pointer REVEALS at its left edge, centred
// in y, with the same verbs behind it (drag, drop, right-click menu). This
// retires the standing "every tile names itself", which is Don's own ruling:
// the name in that place was the defect being reported.
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
import '../chrome/keyboard.dart';
import '../chrome/menus.dart';
import '../core/exact.dart';
import '../core/math.dart';
import '../lens/theme.dart';
import 'layout_tree.dart';
import 'placement_rules.dart';

/// Stage geometry, as named settings.
const Map<String, String> stageTunableDefaults = {
  // THE SEAM IS THE GROUND, AND THE GROUND IS THE TARGET. A divider is a
  // CHANNEL of the stage's own ground between two tiles, wide enough that the
  // hand catches it without aiming and that the arrangement reads as tiles laid
  // out rather than as one wall with lines ruled across it. The hairline sits
  // down the middle of it; the tiles either side are rounded and edged, so what
  // the eye reads as a fine seam is what the hand grabs.
  'stage.divider': '2 * 4',
  'stage.radius': '2 * 3',
  // The hand's target is wider than the painted line, so a seam is easy to
  // catch without drawing a bar of chrome to catch it with.
  'stage.dividerHit': '11',
  // A STACK'S strip. Tall enough to hold a hand's target: the close on a tab is
  // a thing you hit without aiming ("Bigger x on the tabs", Don 2026-08-31), and
  // a strip shorter than `chrome.hit` could not carry one.
  'stage.strip': '2 * 16',
  // A LONE WINDOW'S HANDLE, across the tile's leading edge: the target the hand
  // gets, with the mark (`stage.mark`) drawn in the middle of it. It costs the
  // tile nothing, because the handle rides over the body rather than taking a
  // strip off it.
  'stage.grip': '2 * 14',
  // The two marks the stage draws with -- the close on a tab and the handle on a
  // window -- at the size the MARK is drawn, inside the hand's target it sits in.
  'stage.mark': '2 * 9',
  // The air before a lone window's revealed handle, so the mark is not flush
  // against the tile's own edge.
  'stage.handleInset': '2 * 2',
  // WHERE THE POINTER FINDS THE HANDLE: a band down the tile's leading edge,
  // and nowhere else (ISSUES 9.1, Don's ruling on the reveal region). Wide
  // enough to hold the inset and the mark's own target with room to catch, so
  // the hand does not have to aim at the glyph to bring it out.
  'stage.handleBand': '2 * 18',
  // How solid a drag bar reads while the alignment chord is held: the channel
  // that is otherwise the stage's own ground, washed so every seam on the page
  // can be seen at once.
  'stage.seamWash': '0.22',
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
const Map<String, String> stageTextDefaults = {
  'stage.snapTo': 'ratio',
  // WHERE A NEW TILE LANDS, AUTHORED (ISSUES 9.1). The whole rule list, in the
  // form `PlacementRule.fromJson` already parsed and nothing ever fed it.
  'stage.placement': defaultPlacementSource,
};

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

/// IS THIS A STACK? "1 tab is not a tab it is just a window" (Don, 2026-08-31).
/// A tab strip is what tells two or more tiles apart, so one child is not a
/// stack, wears no strip, and renders as the plain window it is -- whether it
/// was born alone or was left alone when its neighbour closed.
bool isStack(LayoutNode? node) => node is Branch && node.mode == 'tabs' && node.children.length > 1;

Widget _node(BuildContext c, LayoutNode node) => switch (node) {
  TileLeaf leaf => _Tile(key: ValueKey(leaf.id), leaf: leaf),
  Branch b when b.mode == 'tabs' && b.children.length == 1 => _node(c, b.children.first),
  Branch b when b.mode == 'tabs' => _tabs(c, b),
  Branch b when b.mode == 'dwindle' => _dwindle(c, b, 0, b.axis),
  Branch b => _split(c, b),
};

Widget _flex(bool horizontal, List<Widget> parts) =>
    horizontal ? Row(children: parts) : Column(children: parts);

Widget _sized(bool horizontal, double extent, Widget child) =>
    SizedBox(width: horizontal ? extent : null, height: horizontal ? null : extent, child: child);

/// What a tile spends on its own frame across BOTH edges of an axis: the
/// hairline that draws its boundary. The standoff is the divider's channel and
/// belongs to the container, not to the tile.
double tileChrome(Chrome chrome) => chrome.px('chrome.hair') * 2;

/// The LEAST a node may be given along an axis -- its content thickness. A bar
/// knows how thick it needs to be; every other tile takes what it is given. A
/// bar's ask is its CONTENT's thickness plus its own frame, so widening the
/// inset never eats into the bar (ruled 2026-08-28).
double leastExtent(Chrome chrome, LayoutNode node, bool horizontal) {
  if (node is TileLeaf) {
    if (node.type != 'bar') return 0;
    return tileChrome(chrome) +
        (horizontal ? chrome.px('stage.barWidth') : chrome.px('chrome.barHeight'));
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

/// A DRAG BAR MOVES THE TWO WINDOWS IT SITS BETWEEN (ISSUES 9.1, Don's ruling
/// on dividers). Collinear dividers merging by PROXIMITY was the 8.28 default
/// and is vetoed: "the minimap's horizontal seam linked to the lens card's
/// horizontal seam and no dragging unstuck them". Alignment across the page is
/// still one gesture, but it is AUTHORED AND VISIBLE -- hold `keys.alignSeams`
/// and every drag bar on the stage paints, a drag carries its whole collinear
/// run, and a click locks or unlocks that run so it stays linked with the chord
/// let go. Nothing is ever inferred from how close two seams happen to be.
///
/// Every divider on screen registers here so the chord can find the run.
final Set<_DividerState> _liveDividers = {};

/// Is the alignment chord held? One handler for the whole stage rather than one
/// per divider, and one notifier every drag bar watches: the mode is a property
/// of the surface, not of whichever seam the pointer is near.
final ValueNotifier<bool> aligningSeams = ValueNotifier(false);

String _alignChord = '';

bool _readChord(KeyEvent event) {
  aligningSeams.value = chordHeld(_alignChord);
  // Never consumed: this reads a state, it does not answer a keystroke.
  return false;
}

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
    if (_liveDividers.isEmpty) HardwareKeyboard.instance.addHandler(_readChord);
    _liveDividers.add(this);
  }

  @override
  void dispose() {
    _liveDividers.remove(this);
    if (_liveDividers.isEmpty) {
      HardwareKeyboard.instance.removeHandler(_readChord);
      aligningSeams.value = false;
    }
    super.dispose();
  }

  /// This seam's name, which is what a lock is authored against: the container
  /// it cuts and which cut of it. Stable across rebuilds, saved with the layout.
  String get _seamId => '${widget.branch.id}:${widget.index}';

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

  /// WHAT THIS DRAG MOVES. By default: this seam, and therefore the two windows
  /// either side of it. The collinear run is gathered only when the alignment
  /// mode is on -- the chord held, or this seam locked into a run by someone who
  /// held it -- so a link is something you said and can see, never a coincidence
  /// of pixels.
  void _resolveSeam() {
    if (!aligningSeams.value && !ChromeScope.of(context).stage.seamLocked(_seamId)) {
      _seam = [this];
      return;
    }
    _seam = _collinear();
  }

  /// Collinear and contiguous: the same axis, the same pixel line, extents that
  /// touch. Grown transitively, so a run of three stacked seams is one seam.
  List<_DividerState> _collinear() {
    final mine = _rect;
    if (mine == null) return [this];
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
    return chosen;
  }

  /// The one verb of the alignment mode: this run is linked, or it is not. Off
  /// the chord a tap does nothing here -- a seam is for dragging, and a click
  /// that quietly re-plumbed the page is the defect being fixed.
  void _toggleLock() {
    if (!aligningSeams.value) return;
    ChromeScope.of(context).stage.toggleSeamLock(_seamId);
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
    _alignChord = chrome.settings.text('keys.alignSeams');
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
              onTap: _toggleLock,
              onDoubleTap: _reset,
              onHorizontalDragStart: _horizontal ? (_) => _resolveSeam() : null,
              onHorizontalDragUpdate: _horizontal ? (d) => _drag(d.delta.dx) : null,
              onHorizontalDragEnd: _horizontal ? (_) => _drag(0, settle: true) : null,
              onVerticalDragStart: _horizontal ? null : (_) => _resolveSeam(),
              onVerticalDragUpdate: _horizontal ? null : (d) => _drag(d.delta.dy),
              onVerticalDragEnd: _horizontal ? null : (d) => _drag(0, settle: true),
              child: Container(
                width: _horizontal ? hit : null,
                height: _horizontal ? null : hit,
                color: const Color(0x00000000),
                alignment: Alignment.center,
                // WHAT IS LINKED IS WHAT IS SHOWN. At rest a seam is the
                // hairline down the middle of its channel; under the chord the
                // whole channel washes, so every drag bar on the page can be
                // seen at once, and a LOCKED run wears the ink rather than the
                // hair -- the authored link, visible without holding anything.
                child: ValueListenableBuilder<bool>(
                  valueListenable: aligningSeams,
                  builder: (context, aligning, _) {
                    final locked = chrome.stage.seamLocked(_seamId);
                    return AnimatedContainer(
                      duration: chrome.motion,
                      curve: chrome.curve,
                      width: _horizontal ? (aligning ? painted : chrome.px('chrome.hair')) : null,
                      height: _horizontal ? null : (aligning ? painted : chrome.px('chrome.hair')),
                      color: locked
                          ? theme.primary
                          : (aligning
                                ? theme.ink.withValues(alpha: chrome.px('stage.seamWash'))
                                : theme.hair),
                    );
                  },
                ),
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
    // THE STAGE'S OWN MENU OPENS THE STAGE'S OWN SETTINGS (ISSUES 9.1, Don's
    // ruling on the settings surface). The handle is where the tile's verbs
    // live, so it is where the numbers behind them are reached from.
    ...settingsRows(c, 'stage', 'The stage'),
  ];
}

/// THE handle: what you drag a tile by and what you right-click on. A stack's
/// strip wears it across the top, a lone window's bar does the same, and a bar
/// wears it as a grip at its leading end.
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

/// The two marks the stage draws: the close on a tab, and the handle a window
/// or a bar is dragged by.
const String closeMark = '×', handleMark = '⋮';

/// A MARK THAT IS ITS OWN HIT TARGET. The glyph is laid out AT the target size
/// rather than sitting in a box beside one, so what the eye aims at and what the
/// pointer lands on are the same rectangle -- which is the whole of "Bigger x on
/// the tabs" (Don, 2026-08-31). Both sizes are settings, like every other number
/// the stage draws with.
Widget stageMark(BuildContext context, String glyph, {Color? color}) {
  final chrome = ChromeScope.of(context);
  final target = chrome.px('chrome.hit'), mark = chrome.px('stage.mark');
  return ConstrainedBox(
    constraints: BoxConstraints.tightFor(width: target, height: target),
    child: Text(
      glyph,
      textAlign: TextAlign.center,
      style: labelStyle(context, color: color).copyWith(
        fontSize: mark,
        // The line box IS the target, so the mark rides in the middle of it
        // rather than at the top of a box twice its height.
        height: mark <= 0 ? null : target / mark,
      ),
    ),
  );
}

/// The wash a handle or a tab takes while a drop hovers it.
class _Ground extends StatelessWidget {
  const _Ground({required this.washed, required this.child});

  final bool washed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.of(context);
    final theme = ChronoTheme.of(context);
    return AnimatedContainer(
      duration: chrome.motion,
      curve: chrome.curve,
      decoration: BoxDecoration(
        color: washed
            ? theme.ink.withValues(alpha: chrome.px('stage.dropWash'))
            : const Color(0x00000000),
        borderRadius: BorderRadius.circular(chrome.px('chrome.corner')),
      ),
      child: child,
    );
  }
}

/// A stage control: GHOST until the pointer is on it, then an ink wash on the
/// ratified curve, exactly like every other chip in the app. No border and no
/// ground at rest -- a mark, and the room around it to hit.
class _Control extends StatefulWidget {
  const _Control({required this.glyph, required this.semantics, this.onTap});

  final String glyph, semantics;
  final VoidCallback? onTap;

  @override
  State<_Control> createState() => _ControlState();
}

class _ControlState extends State<_Control> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.of(context);
    final theme = ChronoTheme.of(context);
    return Semantics(
      label: widget.semantics,
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _over = true),
        onExit: (_) => setState(() => _over = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // No confirmation, anywhere: reversibility over interruption.
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: chrome.motion,
            curve: chrome.curve,
            decoration: BoxDecoration(
              color: _over
                  ? theme.ink.withValues(alpha: chrome.px('chrome.hoverWash'))
                  : const Color(0x00000000),
              borderRadius: BorderRadius.circular(chrome.px('chrome.corner')),
            ),
            child: stageMark(context, widget.glyph, color: _over ? theme.ink : theme.strong),
          ),
        ),
      ),
    );
  }
}

/// A LONE WINDOW'S HANDLE (ISSUES 9.1, Don): "on a single tab the bar
/// DISAPPEARS entirely; the drag point is the triple dot as a HOVER element on
/// the tile's left edge, centered in y. Same verbs behind it -- right-click
/// menu, drag, drop -- just no resting chrome."
///
/// So NOTHING RESTS: no bar, no name, no grip, and not one pixel of the tile's
/// thickness spent. It paints where the hand can learn ONE place -- the left
/// edge, centred in y -- and it carries the whole handle behind it: drag it to
/// move the tile, drop onto it to tab or swap, right-click it for the tile's
/// verbs.
///
/// TWO WAYS TO BRING IT OUT, one for each kind of hand (ruled 9.1). A POINTER
/// finds it by being in the band down the leading edge -- `stage.handleBand`
/// wide, the reveal region and nothing outside it. A HAND WITH NO POINTER
/// long-presses ANYWHERE in the tile, and what comes out is the same handle
/// doing the same things; the tile's own gesture surface arms that, because a
/// press is a property of the tile rather than of the band.
///
/// One handle for every lone tile, bars included. A bar used to wear a grip at
/// its leading end and a lens a bar across its top; they were the same verbs
/// drawn twice, and this is the one of them.
/// WHICH TILE IS HOLDING ITS HANDLE OUT, by press. One notifier for the whole
/// stage rather than one per tile: a press is how a hand with no pointer says
/// "this one", and a pointer can only be in one place, so a press elsewhere
/// putting the last one away is the same rule the hover already follows.
final ValueNotifier<String?> heldHandle = ValueNotifier(null);

class _Handle extends StatefulWidget {
  const _Handle({required this.leaf});

  final TileLeaf leaf;

  @override
  State<_Handle> createState() => _HandleState();
}

class _HandleState extends State<_Handle> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.of(context);
    final theme = ChronoTheme.of(context);
    final band = chrome.px('stage.handleBand');
    return Stack(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.only(left: chrome.px('stage.handleInset')),
            child: ValueListenableBuilder<String?>(
              valueListenable: heldHandle,
              builder: (context, held, _) {
                final shown = _over || held == widget.leaf.id;
                // UNREVEALED IT IS NOT THERE. Not drawn at zero opacity, not a
                // transparent target on the leading edge of every lens waiting
                // to eat the drags that start there: absent, which is what
                // "nothing rests" means. It arrives on the one curve, like
                // every other ground.
                return IgnorePointer(
                  ignoring: !shown,
                  child: AnimatedSwitcher(
                    duration: chrome.motion,
                    switchInCurve: chrome.curve,
                    switchOutCurve: chrome.curve,
                    child: !shown
                        ? const SizedBox.shrink()
                        : DragTarget<String>(
                            onWillAcceptWithDetails: (details) => details.data != widget.leaf.id,
                            onAcceptWithDetails: (details) =>
                                dropOnHandle(context, widget.leaf, details.data),
                            builder: (context, candidate, _) => tileGrab(
                              context,
                              widget.leaf,
                              _Ground(
                                washed: candidate.isNotEmpty,
                                child: SizedBox(
                                  width: chrome.px('stage.grip'),
                                  child: stageMark(context, handleMark, color: theme.strong),
                                ),
                              ),
                            ),
                          ),
                  ),
                );
              },
            ),
          ),
        ),
        // THE BAND, and only the band: hovering the middle of a lens reveals
        // nothing. It rides IN FRONT of the mark it reveals and behind
        // nothing else: the mark's own region is opaque to the mouse tracker,
        // so a band behind it would lose the pointer the moment it worked and
        // flicker forever. Translucent, so it takes no pointer event and the
        // tile's own content answers every press exactly as before.
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: band,
          child: MouseRegion(
            opaque: false,
            hitTestBehavior: HitTestBehavior.translucent,
            onEnter: (_) => setState(() => _over = true),
            onExit: (_) => setState(() => _over = false),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

/// A STACK'S strip: one tab per tile in it, each with its own close, and the
/// whole strip the handle the active tile is dragged by. It exists only where
/// there IS a stack -- two tiles or more.
///
/// THE STRIP IS CHROME AND THE ACTIVE TAB IS THE SHEET. Elevation carries the
/// reading: the strip is `surface`, like every other piece of chrome; the active
/// tab is the `paper` its body is drawn on, rounded into it and joined to it;
/// and an ink rule along its top says which one is in force. Colour says nothing
/// here -- colour is authored frame and group meaning alone.
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
    final corner = Radius.circular(chrome.px('chrome.corner'));
    final body = AnimatedContainer(
      duration: chrome.motion,
      curve: chrome.curve,
      padding: EdgeInsets.only(left: chrome.px('chrome.pad'), right: chrome.px('chrome.gap')),
      decoration: BoxDecoration(
        color: active ? theme.paper : const Color(0x00000000),
        borderRadius: BorderRadius.only(topLeft: corner, topRight: corner),
        border: Border(
          top: BorderSide(
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
          _Control(
            glyph: closeMark,
            semantics: 'Close $title',
            onTap: () => chrome.stage.close(leaf.id),
          ),
        ],
      ),
    );
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != leaf.id,
      onAcceptWithDetails: (details) => dropOnHandle(context, leaf, details.data, stack: branch),
      builder: (context, candidate, _) =>
          tileGrab(context, leaf, _Ground(washed: candidate.isNotEmpty, child: body)),
    );
  }
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
    // A TAB STRIP IS FOR A STACK. In one, the strip above already carries this
    // tile's tab; alone, it is a window -- and a window wears NO resting chrome
    // at all (ISSUES 9.1), only the handle the pointer reveals over its body.
    final tabbed = isStack(parentOf(chrome.stage.displayRoot, id));
    final handled = !tabbed && chrome.stage.leaves.length > 1;
    final body =
        chrome.stage.tiles[id]?.build(context) ??
        Center(child: Text('No tile named $id is open.', style: labelStyle(context)));
    // EVERY TILE BODY SITS ON PAPER. A painter draws marks, not a ground;
    // without this the window's own black shows through the surface.
    final ground = ColoredBox(color: theme.paper, child: body);
    final radius = BorderRadius.circular(chrome.px('stage.radius'));
    // THE PRESS IS THE TOUCH HAND'S HOVER (ruled 9.1): held anywhere in the
    // tile it brings out the same handle, in the same place, with the same
    // verbs. Putting it away is a Listener rather than a tap, because a press
    // that lands on a control belongs to that control and would never reach a
    // recognizer here -- and a press INSIDE the band is the hand reaching for
    // the handle it just asked for, so that one leaves it standing.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.localPosition.dx > chrome.px('stage.handleBand')) heldHandle.value = null;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (_) => chrome.stage.focus(id),
        onLongPress: handled ? () => heldHandle.value = id : null,
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
          builder: (context, candidate, _) => AnimatedContainer(
            duration: chrome.motion,
            curve: chrome.curve,
            // Selection and focus are INK, never a colour -- and at the SAME
            // weight as the resting hairline, so taking focus moves no pixel.
            decoration: BoxDecoration(
              color: theme.paper,
              borderRadius: radius,
              border: Border.all(
                color: focused ? theme.ink : theme.hair,
                width: chrome.px('chrome.hair'),
              ),
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                children: [
                  Positioned.fill(child: ground),
                  // The handle costs the body nothing: it rides OVER the tile
                  // rather than taking a strip off the top of it.
                  if (handled) Positioned.fill(child: _Handle(leaf: widget.leaf)),
                  if (candidate.isNotEmpty && _zone != null)
                    Positioned.fill(child: _preview(context, _zone!)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
