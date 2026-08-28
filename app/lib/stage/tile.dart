// The stage: a tiling window manager over the layout tree.
//
// Everything is a tile -- lenses, editor cards, the minimap and the three bars
// are all TileSpecs, and `type` is content. There is no dock, no floating, no
// overlap, and no tile kind has a special path.

import 'package:flutter/widgets.dart';

import '../core/exact.dart';
import '../lens/tunables.dart';
import 'layout_tree.dart';
import 'placement_rules.dart';

class TileSpec {
  const TileSpec({
    required this.id,
    required this.type,
    required this.klass,
    required this.title,
    required this.build,
    this.onClose,
  });

  /// `view` | `card` | `minimap` | `bar`, then the kind within that.
  final String id, type, klass, title;
  final Widget Function(BuildContext) build;
  final VoidCallback? onClose;
}

class Stage extends ChangeNotifier {
  Stage({this.rules = defaultPlacementRules, this.tunable, this.onLens, this.root});

  LayoutNode? root;
  List<PlacementRule> rules;
  final Tunable? tunable;

  /// Told which view tile now shows which lens; the view book records it.
  final void Function(String viewTileId, String lensId)? onLens;

  final Map<String, TileSpec> tiles = {};
  final Map<String, LayoutNode> presets = {};

  /// The tile filling the stage on its own, and the pruned tree that shows it.
  /// The real [root] is never touched, so un-zooming restores the exact
  /// arrangement rather than a rebuilt approximation.
  String? zoomedId;
  LayoutNode? _zoomed;

  /// What the stage draws: the zoom when one is on, the arrangement otherwise.
  LayoutNode? get displayRoot => _zoomed ?? root;

  /// Open order, oldest first: what `tabWithNewest` reads.
  final List<String> openOrder = [];

  String? focusedId, _lastView;

  Listenable get listenable => this;

  List<TileLeaf> get leaves => leavesOf(root);

  Rational _setting(String key, Rational fallback) => tunable?.call(key) ?? fallback;

  /// Idempotent by id: opening a tile already on the stage re-arms its builder
  /// and focuses it rather than placing a second copy.
  void open(TileSpec spec) {
    final placed = findNode(root, spec.id) != null;
    tiles[spec.id] = spec;
    if (!placed) {
      final leaf = TileLeaf(spec.id, type: spec.type, klass: spec.klass, title: spec.title);
      root = root == null ? leaf : _place(leaf);
      openOrder
        ..remove(spec.id)
        ..add(spec.id);
    }
    focus(spec.id);
  }

  LayoutNode _place(TileLeaf leaf) {
    final half = Rational.fromInt(1, 2);
    // A tile that is not chrome lands in THE STAGE REGION: never inside the
    // chrome, never splitting a bar (ruled 2026-08-28).
    final target = leaf.type == 'bar'
        ? focusedId
        : stageRegion(root, prefer: [focusedId, focusedViewTile]);
    final placement = evaluatePlacement(
      rules,
      tile: leaf,
      root: root,
      focusedId: target,
      openOrder: openOrder,
      bindings: {
        'stageMaxTabs': _setting('stage.maxTabs', Rational.fromInt(6)),
        'stageSplitRatio': _setting('stage.splitRatio', half),
      },
    );
    if (placement == null) return insertSplit(root, leaf, target, 'row', half);
    if (placement.action == 'tabWithNewest') return insertTab(root, leaf, placement.targetId!);
    final into = placement.action == 'into'
        ? containerNamed(root, placement.container ?? '')
        : null;
    if (into != null) {
      into.children.add(leaf);
      into.ratios = [];
      normalize(into);
      return root!;
    }
    return insertSplit(
      root,
      leaf,
      placement.targetId,
      placement.axis,
      placement.ratio,
      before: placement.before,
    );
  }

  /// No confirmation, ever: closing is undone by opening again.
  void close(String id) {
    final spec = tiles.remove(id);
    openOrder.remove(id);
    root = removeNode(root, id);
    spec?.onClose?.call();
    // Focus lands back in the STAGE REGION, never on a bar: chrome is not
    // somewhere a tile can be worked in, so it is not somewhere focus rests.
    if (focusedId == id) {
      focusedId =
          stageRegion(root, prefer: [_lastView, focusedViewTile]) ?? edgeLeaf(root, true)?.id;
    }
    if (_lastView == id) _lastView = null;
    notifyListeners();
  }

  void focus(String id) {
    if (findNode(root, id) == null) return;
    focusedId = id;
    if (tiles[id]?.type == 'view') _lastView = id;
    // Reveal it: every tab container above the tile shows the branch it is in.
    var childId = id;
    for (var parent = parentOf(root, childId); parent != null;) {
      if (parent.mode == 'tabs') {
        parent.active = parent.children.indexWhere((child) => child.id == childId);
      }
      childId = parent.id;
      parent = parentOf(root, childId);
    }
    notifyListeners();
  }

  /// The view tile the bars and the minimap describe.
  String? get focusedViewTile {
    if (tiles[focusedId]?.type == 'view') return focusedId;
    if (_lastView != null && findNode(root, _lastView!) != null) return _lastView;
    return leaves.where((leaf) => leaf.type == 'view').map((leaf) => leaf.id).lastOrNull;
  }

  /// Re-cuts the container holding [id] along [axis], pulling the tile out of a
  /// tab stack when it is in one. This is untab as much as it is split.
  void split(String id, String axis) {
    final parent = parentOf(root, id);
    final leaf = findNode(root, id);
    if (parent == null || leaf is! TileLeaf) return;
    if (parent.mode != 'tabs') {
      parent.mode = 'split';
      parent.axis = axis;
    } else {
      final sibling = edgeLeaf(parent.children.firstWhere((c) => c.id != id), true)?.id;
      root = removeNode(root, id);
      root = insertSplit(root, leaf, sibling, axis, Rational.fromInt(1, 2));
    }
    notifyListeners();
  }

  void tabUnder(String id, String targetId) => move(id, targetId, 'center');

  /// Puts the tile on that side of where it sits: out of a tab stack when it is
  /// in one, and against the neighbour that way when it is not. The strip menu
  /// offers the same verb a drag onto that edge does.
  void splitToward(String id, String direction) {
    final leaf = findNode(root, id);
    final parent = parentOf(root, id);
    if (leaf is! TileLeaf || parent == null) return;
    final axis = direction == 'left' || direction == 'right' ? 'row' : 'column';
    final before = direction == 'left' || direction == 'up';
    final sibling = parent.mode == 'tabs'
        ? edgeLeaf(parent.children.firstWhere((child) => child.id != id), true)?.id
        : directionalNeighbor(root, id, direction);
    if (sibling == null) {
      parent.mode = 'split';
      parent.axis = axis;
      notifyListeners();
      return;
    }
    root = removeNode(root, id);
    root = insertSplit(
      root,
      leaf,
      sibling,
      axis,
      _setting('stage.splitRatio', Rational.fromInt(1, 2)),
      before: before,
    );
    focus(id);
  }

  /// Everything but this tile and the chrome. Undone by opening them again;
  /// nothing here asks.
  void closeOthers(String id) {
    for (final leaf in leaves.toList()) {
      if (leaf.id != id && leaf.type != 'bar') close(leaf.id);
    }
  }

  void move(String id, String targetId, String zone) {
    root = moveNode(root, id, targetId, zone, _setting('stage.splitRatio', Rational.fromInt(1, 2)));
    notifyListeners();
  }

  /// Moves focus to the nearest tile in a direction.
  bool focusDirection(String direction) {
    final id = focusedId == null ? null : directionalNeighbor(root, focusedId!, direction);
    if (id == null) return false;
    focus(id);
    return true;
  }

  /// Moves the FOCUSED TILE that way, landing it on the neighbour's near edge.
  bool moveDirection(String direction) {
    const opposite = {'left': 'right', 'right': 'left', 'up': 'down', 'down': 'up'};
    final from = focusedId;
    final id = from == null ? null : directionalNeighbor(root, from, direction);
    if (from == null || id == null) return false;
    move(from, id, opposite[direction]!);
    focus(from);
    return true;
  }

  void swapLens(String viewTileId, String lensId) {
    if (tiles[viewTileId]?.type != 'view') return;
    onLens?.call(viewTileId, lensId);
    notifyListeners();
  }

  /// Something the tree owns changed in place (a divider ratio, a tab order).
  void touch() => notifyListeners();

  /// ZOOM: the focused tile fills the stage, and toggling back restores the
  /// exact tree it came from. The chrome rides along unless a setting says not.
  void toggleZoom(String id) {
    if (zoomedId == id) {
      zoomedId = null;
      _zoomed = null;
    } else if (findNode(root, id) != null) {
      final keepBars = _setting('stage.zoomKeepsBars', Rational.one) > Rational.zero;
      final tree = zoomedTo(root, id, bars: keepBars && tiles[id]?.type != 'bar');
      if (tree == null) return;
      zoomedId = id;
      _zoomed = tree;
      focusedId = id;
    }
    notifyListeners();
  }

  /// SWAP: two tiles change places and neither container changes size.
  void swap(String id, String targetId) {
    root = swapLeaves(root, id, targetId);
    if (zoomedId != null) toggleZoom(zoomedId!);
    focus(id);
  }

  /// Every container back to equal shares. A tile dragged down to nothing is
  /// undone by this rather than by hunting for the seam again.
  void evenRatios() {
    void even(LayoutNode? node) {
      if (node is! Branch) return;
      node.ratios = [];
      normalize(node);
      for (final child in node.children) {
        even(child);
      }
    }

    even(root);
    notifyListeners();
  }

  /// A preset IS a saved tree. Applying one re-hosts the live tiles: a leaf
  /// naming a live tile keeps it, a leaf naming nothing adopts an unplaced tile
  /// of the same type and class or leaves, and a live tile the preset never
  /// names is re-placed by the rules.
  void applyPreset(String name) {
    final source = presets[name];
    if (source == null) return;
    var next = nodeFromJson(source.toJson());
    final unplaced = tiles.keys.toSet();
    for (final leaf in leavesOf(next)) {
      if (unplaced.remove(leaf.id)) continue;
      final adopted = unplaced.firstWhere(
        (id) => tiles[id]!.type == leaf.type && tiles[id]!.klass == leaf.klass,
        orElse: () => '',
      );
      next = adopted.isEmpty
          ? removeNode(next, leaf.id)
          : _swapIn(next, leaf.id, TileLeaf(adopted, type: leaf.type, klass: leaf.klass));
      unplaced.remove(adopted);
    }
    root = next;
    for (final id in openOrder.where(unplaced.contains).toList()) {
      final spec = tiles[id]!;
      final leaf = TileLeaf(id, type: spec.type, klass: spec.klass, title: spec.title);
      root = root == null ? leaf : _place(leaf);
    }
    focusedId = stageRegion(root) ?? edgeLeaf(root, false)?.id;
    notifyListeners();
  }

  void savePreset(String name) {
    if (root != null) presets[name] = nodeFromJson(root!.toJson())!;
    notifyListeners();
  }

  LayoutNode? _swapIn(LayoutNode? tree, String id, TileLeaf node) {
    if (tree == null || tree.id == id) return node;
    final parent = parentOf(tree, id);
    if (parent == null) return tree;
    parent.children[parent.children.indexWhere((child) => child.id == id)] = node;
    return tree;
  }

  Map<String, Object?> toJson() => {
    if (root != null) 'root': root!.toJson(),
    if (zoomedId != null) 'zoomed': zoomedId,
    'rules': [for (final rule in rules) rule.toJson()],
    'presets': {for (final entry in presets.entries) entry.key: entry.value.toJson()},
  };

  /// Reads a layout file. A tree naming tiles nothing has opened is kept as
  /// written -- the tiles arrive as they open, and an unknown leaf renders as a
  /// stated gap rather than being silently pruned.
  void applyJson(Map<String, Object?> source) {
    // A STALE LAYOUT IS REPAIRED, never refused and never reset: the view that
    // split the opening bar is pulled back out to the stage region.
    final share = _setting('stage.barShare', Rational.fromInt(1, 64));
    final tree = normalizeLayout(nodeFromJson(source['root']), barShare: share);
    if (tree != null) root = tree;
    final read = source['rules'];
    if (read is List) {
      final parsed = [for (final entry in read) ?PlacementRule.fromJson(entry)];
      if (parsed.isNotEmpty) rules = parsed;
    }
    if (source['presets'] is Map) {
      presets.clear();
      for (final entry in (source['presets'] as Map).entries) {
        if (normalizeLayout(nodeFromJson(entry.value), barShare: share) case final node?) {
          presets['${entry.key}'] = node;
        }
      }
    }
    focusedId ??= stageRegion(root) ?? edgeLeaf(root, false)?.id;
    final zoom = source['zoomed'];
    if (zoom is String && findNode(root, zoom) != null) toggleZoom(zoom);
    notifyListeners();
  }
}
