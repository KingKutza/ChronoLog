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

import 'package:flutter/widgets.dart';

import '../../core/exact.dart';
import '../../core/falloff.dart';
import '../../core/projection.dart';
import '../../edit/gestures.dart';
import '../capacity.dart';
import '../color.dart';
import '../context_menu.dart';
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
  });

  final Graph graph;
  final Map<String, Offset> places;
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

  @override
  void paint(Canvas canvas, Size size) {
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
      paintHaloed(
        canvas,
        entry.label,
        at + Offset(0, treePixels(read, 'tree.labelGap')),
        theme: theme,
        rightAligned: false,
        read: read,
      );
    }
    if (graph.hidden > 0) {
      paintHaloed(
        canvas,
        '${graph.hidden}+',
        Offset(pixels(read, 'lane.gap'), pixels(read, 'lane.gap')),
        theme: theme,
        rightAligned: false,
        read: read,
      );
    }
  }

  @override
  bool shouldRepaint(covariant TreePainter old) =>
      old.graph != graph ||
      old.selected != selected ||
      old.dragAt != dragAt ||
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

  Tunable? get _read => widget.tile.tunable;

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
          step: treePixels(_read, 'tree.ringStep'),
          turn: treePixels(_read, 'tree.ringTurn'),
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
          onPointerDown: (event) => _pointer = event.localPosition,
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
            onSecondaryTapUp: (details) =>
                showViewContextMenu(context, details.globalPosition, widget.tile),
            onPanStart: (details) => setState(() {
              _dragFrom = _nodeAt(_pointer ?? details.localPosition);
              _dragAt = details.localPosition;
            }),
            onPanUpdate: (details) => setState(() => _dragAt = details.localPosition),
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
