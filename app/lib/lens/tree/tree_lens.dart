// TREE: the connection graph whole -- objects and frames as nodes; contains,
// staples, membership and placement as edges (ISSUES 8.26, candidate ruled in).
//
// The first lens whose substrate is CONNECTEDNESS rather than time, which makes
// it two things at once: the surface where a staple is visible and navigable
// from BOTH ends by construction, and the missing authoring surface for
// containment -- drag one node onto another and the drop authors `contains`.
//
// SHAPE IS NOT JUDGED. It renders a graph: multi-parent and cycles draw as what
// they are. EDGE VOCABULARY IS STROKE, not colour, so a grayscale display loses
// nothing. Apparent magnitude falls off by GRAPH DISTANCE from the selection --
// the same falloff, a different metric -- which is the overscale mechanism.

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/exact.dart';
import '../../core/falloff.dart';
import '../../core/projection.dart';
import '../../edit/gestures.dart';
import '../capacity.dart';
import '../color.dart';
import '../context_menu.dart';
import '../gestures.dart';
import '../marks.dart';
import '../painters/radial.dart';
import '../radial/geometry.dart';
import '../theme.dart';
import '../tunables.dart';
import '../view_tile.dart';
import 'graph_layout.dart';

/// Every number the Tree draws with.
const Map<String, String> treeTunableDefaults = {
  'tree.importantAt': '2',
  'tree.landmarkAt': '4',
  'tree.nodeSize': '18',
  'tree.ringStep': '120',
  'tree.ringTurn': '0.6',
  'tree.halfDistance': '2',
  'tree.edgeWidth': '1.4',
  'tree.labelGap': '14',
  'tree.hitPad': '10',
  // A RING EARNS RADIUS FROM ITS OCCUPANCY (ISSUES 9.1): the narrowest two
  // ring-mates may sit, as a share of one ring step. Raise it and a crowded
  // ring pushes further out; drop it to zero and the ring is the old fixed
  // `distance * step` again.
  'tree.ringSpacing': '3/4',
  // LABELS ARE MEASURED MARKS. One thins when its own presence falls below this
  // -- far labels drop first, by the same graph-distance falloff that thins the
  // nodes -- or when its measured box, padded by this much, lands on a label
  // already placed. What the pass cuts is a COUNT, never a silence.
  'tree.labelFloor': '0.34',
  'tree.labelPad': '3',
  // The pointer vocabulary, on a lens whose content exceeds its viewport
  // (ISSUES 9.1, "Tree has no way to pan around"). A wheel notch pans this
  // many pixels; ctrl+wheel scales the ring step between these bounds.
  'tree.wheelPan': '90',
  'tree.zoomMin': '1/8',
  'tree.zoomMax': '8',
};

Rational treeSetting(Tunable? read, String key) {
  if (read != null) return read(key);
  final value = shippedSetting(treeTunableDefaults, key);
  return value is Rational ? value : Rational.zero;
}

double treePixels(Tunable? read, String key) => treeSetting(read, key).toDouble();

/// The dash each connection type is drawn with. STROKE CARRIES THE MEANING:
/// contains is unbroken, a staple is dashed as a staple always is, membership
/// is dotted, a placement is the long-short of an attachment. An empty list is
/// a solid line.
const Map<String, List<String>> edgeDashes = {
  containsEdge: [],
  stapleEdge: ['mark.dashOn', 'mark.dashOff'],
  membershipEdge: ['mark.dotOn', 'mark.dotOff'],
  placementEdge: ['lines.stapleDashOn', 'lines.stapleDashOff'],
};

class TreePainter extends CustomPainter {
  TreePainter({
    required this.graph,
    required this.places,
    required this.theme,
    required this.engine,
    required this.read,
    this.selected,
    this.dragFrom,
    this.dragAt,
    this.origin = Offset.zero,
  });

  final Graph graph;
  final Map<String, Offset> places;

  /// Where the graph's own coordinates sit on this canvas: the view pan. The
  /// places are the LAYOUT's and never move; the surface does.
  final Offset origin;
  final ChronoTheme theme;
  final ProjectionEngine engine;
  final Tunable? read;
  final String? selected, dragFrom;
  final Offset? dragAt;

  /// How present a node at this graph distance is. Monotone decreasing, and it
  /// never reaches zero: a far connection lapses from prominence, never from
  /// truth.
  double presence(int distance) => falloffOpacity(
    falloffBucket(
      apparentMagnitude(
        Rational.one,
        Rational.fromInt(distance),
        halfDistance: treeSetting(read, 'tree.halfDistance'),
      ),
      read,
    ),
    read,
  );

  /// A node's ink: the record's OWN authored colour, or neutral ink. Nothing
  /// here infers a colour from a trait, a title or an id.
  Color inkOf(String id, String map) {
    final extra = map == 'frames'
        ? engine.document.frames[id]?.extra
        : engine.document.events[id]?.extra;
    return authoredColorOf(extra) ?? theme.neutral;
  }

  /// How many labels the last paint could not resolve. Read by nothing but the
  /// paint that produced it; kept so the count can be stated on the surface.
  int thinnedLabels = 0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    _paintGraph(canvas, size);
    canvas.restore();
  }

  void _paintGraph(Canvas canvas, Size size) {
    final width = treePixels(read, 'tree.edgeWidth');
    final node = treePixels(read, 'tree.nodeSize');
    final distances = {for (final entry in graph.nodes) entry.id: entry.distance};
    for (final edge in graph.edges) {
      final from = places[edge.from], to = places[edge.to];
      if (from == null || to == null) continue;
      final far = (distances[edge.from] ?? 0) > (distances[edge.to] ?? 0)
          ? distances[edge.from]!
          : distances[edge.to]!;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = edge.kind == containsEdge ? width * 2 : width
        ..color = theme.strong.withValues(alpha: presence(far));
      final dash = edgeDashes[edge.kind] ?? const [];
      if (dash.isEmpty) {
        canvas.drawLine(from, to, paint);
      } else {
        dashLine(canvas, from, to, paint, pixels(read, dash.first), pixels(read, dash.last));
      }
    }
    if (dragFrom != null && dragAt != null && places[dragFrom] != null) {
      dashLine(
        canvas,
        places[dragFrom]!,
        dragAt!,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 2
          ..color = theme.accent,
        pixels(read, 'mark.dashOn'),
        pixels(read, 'mark.dashOff'),
      );
    }
    for (final entry in graph.nodes) {
      final at = places[entry.id];
      if (at == null) continue;
      final alpha = presence(entry.distance);
      final bounds = Rect.fromCenter(center: at, width: node, height: node);
      // A frame is a square and an object a disc: structural role in the shape,
      // so the two never depend on colour to be told apart.
      final shape = sigilPath(entry.map == 'frames' ? 'note' : 'point', bounds);
      canvas.drawPath(shape, Paint()..color = theme.paper);
      canvas.drawPath(
        shape,
        Paint()
          ..style = entry.map == 'frames' ? PaintingStyle.stroke : PaintingStyle.fill
          ..strokeWidth = width * 2
          ..color = inkOf(entry.id, entry.map).withValues(alpha: alpha),
      );
      if (entry.id == selected) {
        canvas.drawPath(
          shape,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = pixels(read, 'selection.ring')
            ..color = theme.ink.withValues(alpha: pixels(read, 'selection.ringOpacity')),
        );
      }
    }
    _paintLabels(canvas);
    final unsaid = graph.hidden + thinnedLabels;
    if (unsaid > 0) {
      // ONE COUNT FOR EVERYTHING THIS SURFACE COULD NOT SAY: what the budget cut
      // from the graph and what the label pass thinned are both "there is more
      // here", and a cut label is a count rather than a silence (ISSUES 9.1).
      paintHaloed(
        canvas,
        '$unsaid+',
        Offset(pixels(read, 'lane.gap') - origin.dx, pixels(read, 'lane.gap') - origin.dy),
        theme: theme,
        rightAligned: false,
        read: read,
      );
    }
  }

  /// LABELS ARE MARKS WITH MEASURED BOXES (ISSUES 9.1). They resolve nearest
  /// first -- the same graph-distance falloff that thins the nodes -- and one
  /// that will not fit, or has faded past the floor, is THINNED and counted. Far
  /// labels drop first by construction, because the pass runs in distance order.
  void _paintLabels(Canvas canvas) {
    final gap = treePixels(read, 'tree.labelGap');
    final pad = treePixels(read, 'tree.labelPad');
    final floor = treePixels(read, 'tree.labelFloor');
    final ordered = [...graph.nodes]
      ..sort((a, b) => a.distance != b.distance
          ? a.distance.compareTo(b.distance)
          : a.id.compareTo(b.id));
    final placed = <Rect>[];
    thinnedLabels = 0;
    for (final entry in ordered) {
      final at = places[entry.id];
      if (at == null || entry.label.isEmpty) continue;
      final alpha = presence(entry.distance);
      if (alpha < floor) {
        thinnedLabels += 1;
        continue;
      }
      final box = haloedLabelBox(entry.label, at + Offset(0, gap), theme: theme, read: read);
      final claim = box.inflate(pad);
      if (placed.any(claim.overlaps)) {
        thinnedLabels += 1;
        continue;
      }
      placed.add(claim);
      paintHaloed(
        canvas,
        entry.label,
        at + Offset(0, gap),
        theme: theme,
        rightAligned: false,
        read: read,
        opacity: alpha,
      );
    }
  }

  @override
  bool shouldRepaint(covariant TreePainter old) =>
      old.graph != graph ||
      old.selected != selected ||
      old.dragAt != dragAt ||
      old.origin != origin ||
      old.places.length != places.length;
}

/// The Tree surface: its own graph gestures, because a graph's pointer
/// vocabulary is not the time surfaces' one (a drag here mints nothing and
/// authors a connection instead).
class TreeLens extends StatefulWidget {
  const TreeLens({super.key, required this.tile, this.roots = const []});

  final ViewTileController tile;

  /// What the graph is centred on. Empty means the projected primary frame.
  final List<String> roots;

  @override
  State<TreeLens> createState() => _TreeLensState();
}

class _TreeLensState extends State<TreeLens> {
  String? _selected, _dragFrom;
  Offset? _dragAt, _pointer;
  Graph _graph = (nodes: const [], edges: const [], hidden: 0);
  Map<String, Offset> _places = const {};

  /// THE VIEW, MOVED (ISSUES 9.1, "Tree has no way to pan around"). The ruled
  /// pointer vocabulary belongs to any lens whose content can exceed its
  /// viewport -- the roster carve-out was about MINTING, never about motion --
  /// so this surface answers the verbs the time lenses do: middle-drag and
  /// shift-drag pan, the wheel pans, ctrl+wheel zooms. Transform-only: the pan
  /// is an origin the painter translates by, and the layout never hears of it.
  Offset _view = Offset.zero;
  Offset? _panFrom;
  Offset _panWas = Offset.zero;
  double _zoom = 1;
  final Notches _wheel = Notches(), _zoomWheel = Notches();

  Tunable? get _read => widget.tile.tunable;

  /// A point on the canvas, in the graph's own coordinates. Every hit test and
  /// every authored drag asks through here, so the pan cannot make the pointer
  /// and the picture disagree.
  Offset _inGraph(Offset at) => at - _view;

  double _tile(String key) => widget.tile.settings.value(key).toDouble();

  /// The selection is the centre: falloff by graph distance measures from what
  /// the eye is on. Failing a selection, the graph is rooted on EVERY frame the
  /// projection names -- the projection is the population here as it is
  /// everywhere, not the primary frame alone.
  List<String> get _roots => [
    if (_selected case final String id) id,
    ...widget.roots,
    ...widget.tile.projection.frames,
  ];

  String? _nodeAt(Offset at) {
    final reach = (treePixels(_read, 'tree.nodeSize') + treePixels(_read, 'tree.hitPad')) / 2;
    for (final node in _graph.nodes.reversed) {
      final place = _places[node.id];
      if (place != null && (place - at).distance <= reach) return node.id;
    }
    return null;
  }

  void _open(String id) {
    final node = _graph.nodes.where((entry) => entry.id == id).firstOrNull;
    final open = node?.map == 'frames' ? widget.tile.frameCard : widget.tile.objectCard;
    if (open != null) widget.tile.stage.open(open(id));
  }

  /// A DROP AUTHORS CONTAINMENT: the node released onto holds the node dragged.
  /// One relation, undoable like every other edit, no confirmation.
  /// This lens's own declared control, not a bare setting: the context bar
  /// moves it and the graph follows.
  int get _reach => switch (widget.tile.view['reach']) {
    final Rational written => written.round().toInt(),
    _ => treeSetting(_read, 'tree.reach').round().toInt(),
  };

  /// THE ONE POINTER TABLE, asked here too. A graph is not a time surface, so
  /// it never mints -- the table already says that, `timeSurface: false`
  /// answering `select` -- but pan is pan on every surface holding more content
  /// than window.
  void _down(PointerDownEvent event) {
    _pointer = _inGraph(event.localPosition);
    final keys = HardwareKeyboard.instance;
    final verb = pointerVerb(
      buttons: event.buttons,
      shift: keys.isShiftPressed,
      alt: keys.isAltPressed,
      control: keys.isControlPressed,
      onMark: false,
      timeSurface: false,
      bindings: widget.tile.settings.binding,
    );
    if (verb != 'pan') return;
    _panFrom = event.localPosition;
    _panWas = _view;
  }

  void _drag(PointerMoveEvent event) {
    final from = _panFrom;
    if (from == null) return;
    setState(() => _view = _panWas + (event.localPosition - from));
  }

  /// The wheel, in the same vocabulary as every other surface: ctrl zooms, a
  /// plain notch pans down the surface, shift pans across it.
  void _signal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final keys = HardwareKeyboard.instance;
    final notch = _tile('pointer.wheelNotch');
    final sideways =
        keys.isShiftPressed || event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs();
    final raw = keys.isShiftPressed || event.scrollDelta.dx == 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (keys.isControlPressed) {
      final steps = _zoomWheel.take(raw * _tile('pointer.zoomDirection'), notch);
      if (steps == 0) return;
      // Wheel-up zooms IN, which on a graph is a WIDER ring step: the sign
      // convention is the pointer table's, read from the same setting the time
      // surfaces read (ISSUES 9.1, reversed zoom).
      final factor = _tile('pointer.zoomStep');
      var next = _zoom;
      for (var step = 0; step < steps.abs(); step += 1) {
        next = steps < 0 ? next * factor : next / factor;
      }
      final least = treePixels(_read, 'tree.zoomMin'), most = treePixels(_read, 'tree.zoomMax');
      return setState(() => _zoom = next < least ? least : (next > most ? most : next));
    }
    final steps = _wheel.take(raw, notch);
    if (steps == 0) return;
    final by = treePixels(_read, 'tree.wheelPan') * steps;
    setState(() => _view += sideways ? Offset(-by, 0) : Offset(0, -by));
  }

  void _drop() {
    final source = _dragFrom, target = _dragAt == null ? null : _nodeAt(_dragAt!);
    if (source != null && target != null && target != source) {
      widget.tile.editor.setContains(target, source, true);
    }
    setState(() {
      _dragFrom = null;
      _dragAt = null;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.tile.editor.changes,
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final budget = capacityOf(size.width, size.height, _read).marks;
        _graph = buildGraph(
          widget.tile.editor.engine,
          roots: _roots,
          reach: _reach,
          budget: budget,
        );
        _places = radialLayout(
          _graph,
          size.center(Offset.zero),
          step: treePixels(_read, 'tree.ringStep') * _zoom,
          turn: treePixels(_read, 'tree.ringTurn'),
          spacing: treePixels(_read, 'tree.ringSpacing'),
        );
        if (_graph.nodes.isEmpty) {
          return statedRefusal(
            context,
            'Nothing is projected, so there is no connection graph to draw.',
            _read,
          );
        }
        // The pointer's own DOWN position, not the pan's: a pan is recognised
        // only after the slop, by which point the pointer has left the node it
        // started on and a drag would author from nothing.
        return Listener(
          onPointerDown: _down,
          onPointerMove: _drag,
          onPointerUp: (_) => _panFrom = null,
          onPointerCancel: (_) => _panFrom = null,
          onPointerSignal: _signal,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              final hit = _pointer == null ? null : _nodeAt(_pointer!);
              _selected = hit == _selected ? null : hit;
            }),
            onDoubleTap: () {
              final hit = _pointer == null ? null : _nodeAt(_pointer!);
              if (hit != null) _open(hit);
            },
            // The menu is raised ON THE NODE under the pointer, so Open is
            // offered here exactly as it is on a painted mark (ruled 8.31).
            onSecondaryTapUp: (details) {
              final id = _nodeAt(_pointer ?? _inGraph(details.localPosition));
              final node = id == null
                  ? null
                  : _graph.nodes.where((entry) => entry.id == id).firstOrNull;
              showViewContextMenu(
                context,
                details.globalPosition,
                widget.tile,
                objectId: node != null && node.map != 'frames' ? id : null,
                frameId: node != null && node.map == 'frames' ? id : null,
              );
            },
            onPanStart: (details) => setState(() {
              if (_panFrom != null) return;
              _dragFrom = _nodeAt(_pointer ?? _inGraph(details.localPosition));
              _dragAt = _inGraph(details.localPosition);
            }),
            onPanUpdate: (details) => setState(
              () => _dragAt = _panFrom != null ? null : _inGraph(details.localPosition),
            ),
            onPanEnd: (_) => _drop(),
            onPanCancel: _drop,
            child: ColoredBox(
              color: ChronoTheme.of(context).paper,
              child: CustomPaint(
                size: size,
                painter: TreePainter(
                  graph: _graph,
                  places: _places,
                  theme: ChronoTheme.of(context),
                  engine: widget.tile.editor.engine,
                  read: _read,
                  selected: _selected,
                  dragFrom: _dragFrom,
                  dragAt: _dragAt,
                  origin: _view,
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// The catalog's builder for the Tree, registered with the curve family.
Widget treeLensBuilder(BuildContext context, ViewTileController tile) => TreeLens(tile: tile);
