// The stage: a tiling window manager over the layout tree.
//
// Everything is a tile -- lenses, editor cards, the minimap and the three bars
// are all TileSpecs, and `type` is content. There is no dock, no floating, no
// overlap, and no tile kind has a special path.

import 'package:flutter/widgets.dart';

import 'dart:convert';

import '../core/exact.dart';
import '../lens/tunables.dart';
import '../session/lens_catalog.dart';
import '../session/settings.dart';
import '../session/view_state.dart';
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

  /// THE SAME TILE, SAYING WHAT IT IS NOW (ISSUES 9.1). A title that claims
  /// something which can change is a reading, not a fact minted once: the one
  /// seam where the claim changes restates it through here rather than leaving
  /// every strip and window drawing the name the tile was born with.
  TileSpec named(String title) => TileSpec(
    id: id,
    type: type,
    klass: klass,
    title: title,
    build: build,
    onClose: onClose,
  );
}

/// A NAMED SUBTREE, AND WHAT ITS VIEW LEAVES WERE LOOKING THROUGH (ISSUES 9.2,
/// Don: "named views live where persistent layouts live"; "presets and boards
/// are one record kind").
///
/// ONE record kind, two uses. A preset is a named subtree whose leaves are any
/// tiles; a board is one whose leaves are projection tiles. So a saved view is
/// not a second thing -- it is this record with one leaf, which is why a board
/// lays out like any preset and a preset carries a board.
///
/// [views] is what each view leaf SAID, by tile id, and it is
/// [ViewState.said] rather than a serializer of its own: lens, projection
/// expression, columns in order with their own expressions, the lens's own
/// keys, and never the focus. Where the eye was looking is not what was said.
class StagePreset {
  StagePreset(this.root, {Map<String, Map<String, Object?>>? views}) : views = views ?? const {};

  final LayoutNode root;
  final Map<String, Map<String, Object?>> views;

  Map<String, Object?> toJson() => {
    'root': root.toJson(),
    if (views.isNotEmpty) 'views': views,
  };

  /// A layout file's preset entry. The bare-node shape a file written before
  /// views were named still reads: a record says so with its own `root` key,
  /// and anything else IS the node. Nothing on the load path rewrites the file.
  static StagePreset? fromJson(Object? source, {Rational? barShare}) {
    final record = source is Map && source['root'] != null;
    final node = normalizeLayout(
      nodeFromJson(record ? source['root'] : source),
      barShare: barShare,
    );
    if (node == null) return null;
    final said = record ? source['views'] : null;
    return StagePreset(node, views: {
      if (said is Map)
        for (final entry in said.entries)
          if (entry.value is Map) '${entry.key}': Map<String, Object?>.from(entry.value as Map),
    });
  }
}

class Stage extends ChangeNotifier {
  Stage({List<PlacementRule>? rules, this.tunable, this.settings, this.onLens, this.root})
    : written = rules ?? defaultPlacementRules {
    settings?.addListener(_placementSaid);
  }

  LayoutNode? root;

  /// WHERE A TILE LANDS, AND WHERE THAT IS WRITTEN (ISSUES 9.1, Don's ruling on
  /// placement home): "file wins; settings edits file. App hot loads file."
  ///
  /// THE LAYOUT FILE IS THE HOME. This list is that file's placement section,
  /// read back by `applyJson` when the file is loaded or changes on disk, and
  /// written out by `toJson` every time the stage moves. Nothing else is a
  /// rival source: the `stage.placement` setting is a READ/WRITE VIEW of this
  /// section -- writing the key edits the file, and a file that changes says so
  /// through the key -- so the same rules can be authored by either road and
  /// the two cannot disagree. The shipped value is the parsed authored source.
  List<PlacementRule> written;

  /// Where a tile lands, right now.
  List<PlacementRule> get rules => written;

  final Tunable? tunable;

  /// The settings store, for the one key that is a view of the layout file.
  /// Absent, the stage still places by the file and simply has no second road
  /// to it -- which is what every test that hands no settings is asking for.
  final Settings? settings;

  /// The file's placement section, as the text the setting shows: the CANONICAL
  /// form, so a terse authored list read in comes back out saying every term it
  /// actually placed by.
  String get placementSource => jsonEncode([for (final rule in written) rule.toJson()]);

  bool _syncing = false;

  /// The setting was written -- by the settings card, or by hand in the settings
  /// file. It is a view of the layout file's section, so writing it EDITS THAT
  /// SECTION, and the stage notifies, which is what saves the layout.
  void _placementSaid() {
    final store = settings;
    if (store == null || _syncing) return;
    final said = store.text('stage.placement').trim();
    if (said == placementSource) return;
    final parsed = rulesFromSource(said);
    _syncing = true;
    // A list that will not read leaves the file standing and the key says what
    // the file says: a half-read rule list would place tiles by a rule nobody
    // wrote, and a key silently disagreeing with the file is the drift this
    // whole arrangement exists to prevent.
    if (parsed.isNotEmpty) written = parsed;
    store.setText('stage.placement', placementSource);
    _syncing = false;
    if (parsed.isNotEmpty) notifyListeners();
  }

  /// The file spoke: the key says what the file says.
  void _publishPlacement() {
    final store = settings;
    if (store == null || _syncing) return;
    if (store.text('stage.placement').trim() == placementSource) return;
    _syncing = true;
    store.setText('stage.placement', placementSource);
    _syncing = false;
  }

  @override
  void dispose() {
    settings?.removeListener(_placementSaid);
    heldHandle.dispose();
    super.dispose();
  }

  /// WHICH TILE IS HOLDING ITS HANDLE OUT. One notifier for the whole stage
  /// rather than one per tile: a press is how a hand with no pointer says "this
  /// one", a pointer can only be in one place, and a menu open on a handle
  /// holds it out while it stands. It lives on the STAGE and not beside it,
  /// because a handle held for a tile belongs to the arrangement that tile is
  /// in -- a notifier outliving its stage is state one stage hands the next.
  final ValueNotifier<String?> heldHandle = ValueNotifier(null);

  /// Told which view tile now shows which lens; the view book records it.
  final void Function(String viewTileId, String lensId)? onLens;

  final Map<String, TileSpec> tiles = {};
  final Map<String, StagePreset> presets = {};

  /// The tile filling the stage on its own. The real [root] is never touched,
  /// so un-zooming restores the exact arrangement rather than a rebuilt
  /// approximation.
  String? zoomedId;

  /// What the stage draws: the zoom when one is on, the arrangement otherwise.
  ///
  /// DERIVED ON EVERY READ, never a stored copy (ISSUES 9.2, Don's live break:
  /// "I get 'No tile named card:frames:one is open', and I cannot open another
  /// tile"). A pruned COPY was the defect: close mutated the real tree and
  /// never the copy, so the stage went on drawing a leaf whose tile was gone
  /// and every later open landed underneath, invisible. A zoom is a QUESTION
  /// asked of the live tree.
  LayoutNode? get displayRoot {
    final id = zoomedId;
    if (id == null || findNode(root, id) == null) return root;
    final keepBars = _setting('stage.zoomKeepsBars', Rational.one) > Rational.zero;
    return zoomedTo(root, id, bars: keepBars && tiles[id]?.type != 'bar') ?? root;
  }

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
      // THE ZOOM CLEARS (ISSUES 9.2, Don). The hand asked to SEE something; a
      // tile that landed in the tree behind a zoom was invisible, which reads
      // as the open having failed.
      zoomedId = null;
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
    if (tabActions.contains(placement.action)) return insertTab(root, leaf, placement.targetId!);
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
    // A zoom whose tile is gone clears itself: there is nothing left to fill
    // the stage with, and a name pointing at nothing is what broke.
    if (zoomedId == id) zoomedId = null;
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

  /// A VIEW TILE'S NAME IS ITS CURRENT LENS (ISSUES 9.1, Don: "when it switches
  /// lenses via the lens bar, the name of that window does not change"). The
  /// swap is the one seam where that name changes, so the swap restates it --
  /// what every strip and window draws is `tiles[id].title`, and a title left
  /// at the value it was constructed with is a claim about a thing that moved.
  void swapLens(String viewTileId, String lensId) {
    final spec = tiles[viewTileId];
    if (spec?.type != 'view') return;
    final named = lensCatalog[lensId]?.title;
    if (named != null && named != spec!.title) tiles[viewTileId] = spec.named(named);
    onLens?.call(viewTileId, lensId);
    notifyListeners();
  }

  /// SEAMS THAT MOVE TOGETHER, BECAUSE SOMEONE SAID SO (ISSUES 9.1, Don's
  /// ruling on dividers). A divider drags the two windows it sits between and
  /// nothing else; a seam named here carries its whole collinear run, and the
  /// only way into this set is the alignment chord, where the drag bars are
  /// visible while you say it.
  final Set<String> lockedSeams = {};

  bool seamLocked(String seam) => lockedSeams.contains(seam);

  void toggleSeamLock(String seam) {
    lockedSeams.contains(seam) ? lockedSeams.remove(seam) : lockedSeams.add(seam);
    notifyListeners();
  }

  /// Something the tree owns changed in place (a divider ratio, a tab order).
  void touch() => notifyListeners();

  /// ZOOM: the focused tile fills the stage, and toggling back restores the
  /// exact tree it came from. The chrome rides along unless a setting says not.
  void toggleZoom(String id) {
    if (zoomedId == id) {
      zoomedId = null;
    } else if (findNode(root, id) != null) {
      zoomedId = id;
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

  /// CHANGE WHAT THIS BOX SHOWS (ISSUES 9.2, Don: "'Swap with X' already means
  /// trade PLACES with another tile, so the content door cannot also say
  /// 'swap' -- it says what it does to this box"). The box does not move, does
  /// not resize and does not close: its filling is replaced, and the leaf
  /// restates what it now IS so every strip, menu and placement rule reads the
  /// new content rather than the one the tile was born with.
  void showHere(String tileId, TileSpec spec) {
    if (findNode(root, tileId) == null || spec.id != tileId) return;
    tiles[tileId] = spec;
    final leaf = TileLeaf(tileId, type: spec.type, klass: spec.klass, title: spec.title);
    final parent = parentOf(root, tileId);
    if (parent == null) {
      root = leaf;
    } else {
      parent.children[parent.children.indexWhere((child) => child.id == tileId)] = leaf;
    }
    focus(tileId);
  }

  /// A preset IS a saved tree. Applying one re-hosts the live tiles: a leaf
  /// naming a live tile keeps it, a leaf naming nothing adopts an unplaced tile
  /// of the same type and class or leaves, and a live tile the preset never
  /// names is re-placed by the rules.
  ///
  /// Hand it the view book and each view leaf comes back looking through what
  /// it was looking through -- onto whichever live tile took that leaf's place,
  /// which is not always the id the preset wrote.
  void applyPreset(String name, {ViewBook? views}) {
    final preset = presets[name];
    if (preset == null) return;
    var next = nodeFromJson(preset.root.toJson());
    // Which live tile ended up standing in each saved leaf's place.
    final stood = <String, String>{};
    final unplaced = tiles.keys.toSet();
    for (final leaf in leavesOf(next)) {
      if (unplaced.remove(leaf.id)) {
        stood[leaf.id] = leaf.id;
        continue;
      }
      final adopted = unplaced.firstWhere(
        (id) => tiles[id]!.type == leaf.type && tiles[id]!.klass == leaf.klass,
        orElse: () => '',
      );
      next = adopted.isEmpty
          ? removeNode(next, leaf.id)
          : _swapIn(next, leaf.id, TileLeaf(adopted, type: leaf.type, klass: leaf.klass));
      if (adopted.isNotEmpty) stood[leaf.id] = adopted;
      unplaced.remove(adopted);
    }
    root = next;
    for (final id in openOrder.where(unplaced.contains).toList()) {
      final spec = tiles[id]!;
      final leaf = TileLeaf(id, type: spec.type, klass: spec.klass, title: spec.title);
      root = root == null ? leaf : _place(leaf);
    }
    focusedId = stageRegion(root) ?? edgeLeaf(root, false)?.id;
    if (views != null) {
      for (final entry in stood.entries) {
        if (preset.views[entry.key] case final said?) views.showSaid(entry.value, said);
      }
    }
    notifyListeners();
  }

  /// Saves the arrangement, and -- when the book is handed in -- what every
  /// view leaf in it SAID. Without the book it is the arrangement alone, which
  /// is what it always was.
  void savePreset(String name, {ViewBook? views}) {
    final tree = root;
    if (tree == null) return;
    presets[name] = StagePreset(
      nodeFromJson(tree.toJson())!,
      views: {
        if (views != null)
          for (final leaf in leavesOf(tree))
            if (leaf.type == 'view' && views.views.containsKey(leaf.id))
              leaf.id: views.views[leaf.id]!.said,
      },
    );
    notifyListeners();
  }

  /// A NAMED VIEW: one tile's view state under a name, in the same map, as a
  /// one-leaf arrangement -- so applying it lays out and showing it does not.
  /// The leaf wears the live tile's own type and class, which is what lets a
  /// different view tile adopt it later.
  void saveView(String name, String tileId, ViewState state) {
    final spec = tiles[tileId];
    presets[name] = StagePreset(
      TileLeaf(
        tileId,
        type: spec?.type ?? 'view',
        klass: spec?.klass ?? 'lens',
        title: spec?.title ?? name,
      ),
      views: {tileId: state.said},
    );
    notifyListeners();
  }

  /// THIS TILE NOW SHOWS THAT NAMED VIEW, and its focus is left alone. The
  /// record's state for this very tile when it holds one, else the first view
  /// leaf's in the saved tree's own order -- deterministic, so showing a view
  /// twice shows the same view.
  void showView(String name, String tileId, ViewBook views) {
    final preset = presets[name];
    if (preset == null) return;
    final said =
        preset.views[tileId] ??
        [for (final leaf in leavesOf(preset.root)) ?preset.views[leaf.id]].firstOrNull;
    if (said == null) return;
    views.showSaid(tileId, said);
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
    if (lockedSeams.isNotEmpty) 'seams': lockedSeams.toList()..sort(),
    'rules': [for (final rule in written) rule.toJson()],
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
      if (parsed.isNotEmpty) written = parsed;
    }
    _publishPlacement();
    final seams = source['seams'];
    if (seams is List) {
      lockedSeams
        ..clear()
        ..addAll([for (final seam in seams) '$seam']);
    }
    if (source['presets'] is Map) {
      presets.clear();
      for (final entry in (source['presets'] as Map).entries) {
        if (StagePreset.fromJson(entry.value, barShare: share) case final preset?) {
          presets['${entry.key}'] = preset;
        }
      }
    }
    focusedId ??= stageRegion(root) ?? edgeLeaf(root, false)?.id;
    final zoom = source['zoomed'];
    if (zoom is String && findNode(root, zoom) != null) toggleZoom(zoom);
    notifyListeners();
  }
}
