// The stage layout, as a tree. Everything is a tile: lenses, editor cards, the
// minimap and the three bars are leaves of ONE structure, and no tile kind has
// a special path here. Inner nodes are containers with a mode -- `split`
// (axis + ratios), `tabs` (active), `dwindle` (ratio; golden-spiral tiling is
// dwindle at 0.618). No floating, no overlap: every arrangement is total.
//
// Modes and axes are strings, not enums: an unfamiliar mode is data a later
// stage may learn to lay out, never a crash.

import '../core/exact.dart';

// Container ids are MINTED, never derived from the tile that caused them: a
// tile that is moved twice would otherwise name two live containers the same,
// and every lookup here is by id. Reading a tree advances the counter past what
// the file already used, so a loaded layout and a fresh insert cannot collide.
int _minted = 0;

String mintContainerId(String kind) => '$kind:${_minted++}';

void _noteId(String id) {
  final digits = RegExp(r':(\d+)$').firstMatch(id);
  final seen = digits == null ? -1 : int.parse(digits[1]!);
  if (seen >= _minted) _minted = seen + 1;
}

sealed class LayoutNode {
  LayoutNode(this.id);

  final String id;

  Map<String, Object?> toJson();
}

/// A tile: `type` (view | card | minimap | bar) and `klass` (its kind).
class TileLeaf extends LayoutNode {
  TileLeaf(super.id, {required this.type, required this.klass, this.title = ''});

  final String type, klass;
  String title;

  @override
  Map<String, Object?> toJson() => {'id': id, 'type': type, 'class': klass, 'title': title};
}

class Branch extends LayoutNode {
  Branch(
    super.id, {
    required this.mode,
    this.axis = 'row',
    List<LayoutNode>? children,
    List<Rational>? ratios,
    this.active = 0,
    Rational? ratio,
    this.name,
  }) : children = children ?? [],
       ratios = ratios ?? [],
       ratio = ratio ?? Rational.fromInt(1, 2) {
    normalize(this);
  }

  /// `split` | `tabs` | `dwindle`, and `row` | `column` (a dwindle alternates
  /// from this first cut).
  String mode, axis;

  final List<LayoutNode> children;
  List<Rational> ratios;
  int active;
  Rational ratio;

  /// An addressable container, so a placement rule may aim `into` it.
  String? name;

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'mode': mode,
    'axis': axis,
    'active': active,
    'ratio': ratio.toJson(),
    if (name != null) 'name': name,
    'ratios': [for (final value in ratios) value.toJson()],
    'children': [for (final child in children) child.toJson()],
  };
}

/// Ratios always match the child count and always sum to one.
void normalize(Branch branch) {
  final count = branch.children.length;
  branch.active = count == 0 ? 0 : branch.active.clamp(0, count - 1);
  var total = Rational.zero;
  if (branch.ratios.length == count) {
    for (final value in branch.ratios) {
      if (value > Rational.zero) total += value;
    }
  }
  branch.ratios = total <= Rational.zero
      ? List.filled(count, count == 0 ? Rational.zero : Rational.fromInt(1, count))
      : [for (final v in branch.ratios) (v > Rational.zero ? v : Rational.zero) / total];
}

/// The first node the test accepts, depth first.
LayoutNode? findWhere(LayoutNode? root, bool Function(LayoutNode) test) {
  if (root == null) return null;
  if (test(root)) return root;
  if (root is! Branch) return null;
  for (final child in root.children) {
    final found = findWhere(child, test);
    if (found != null) return found;
  }
  return null;
}

LayoutNode? findNode(LayoutNode? root, String id) => findWhere(root, (node) => node.id == id);

Branch? containerNamed(LayoutNode? root, String name) =>
    findWhere(root, (node) => node is Branch && node.name == name) as Branch?;

Branch? parentOf(LayoutNode? root, String id) =>
    findWhere(root, (node) => node is Branch && node.children.any((c) => c.id == id)) as Branch?;

List<TileLeaf> leavesOf(LayoutNode? root) => switch (root) {
  null => const [],
  TileLeaf leaf => [leaf],
  Branch branch => [for (final child in branch.children) ...leavesOf(child)],
};

/// The leaf a move lands on: the first or last of a container, with tabs
/// answering for their active child.
TileLeaf? edgeLeaf(LayoutNode? node, bool last) => switch (node) {
  null => null,
  TileLeaf leaf => leaf,
  Branch b when b.children.isEmpty => null,
  Branch b when b.mode == 'tabs' => edgeLeaf(b.children[b.active], last),
  Branch b => edgeLeaf(last ? b.children.last : b.children.first, last),
};

/// Directional focus: climb to the first ancestor cut along the wanted axis
/// that has a sibling that way, then descend to its nearest edge leaf.
String? directionalNeighbor(LayoutNode? root, String fromId, String direction) {
  final wanted = direction == 'left' || direction == 'right' ? 'row' : 'column';
  final forward = direction == 'right' || direction == 'down';
  var childId = fromId;
  for (var parent = parentOf(root, childId); parent != null;) {
    if (parent.mode != 'tabs' && parent.axis == wanted) {
      final index = parent.children.indexWhere((child) => child.id == childId);
      final next = forward ? index + 1 : index - 1;
      if (index >= 0 && next >= 0 && next < parent.children.length) {
        return edgeLeaf(parent.children[next], !forward)?.id;
      }
    }
    childId = parent.id;
    parent = parentOf(root, childId);
  }
  return null;
}

/// Removes a node and collapses whatever that empties: a container left with
/// one child becomes that child, and one left with none leaves too.
LayoutNode? removeNode(LayoutNode? root, String id) {
  if (root == null || root.id == id) return null;
  if (root is! Branch) return root;
  final kept = <LayoutNode>[], ratios = <Rational>[];
  for (final (index, child) in root.children.indexed) {
    final next = removeNode(child, id);
    if (next == null) continue;
    kept.add(next);
    ratios.add(root.ratios[index]);
  }
  if (kept.length < 2) return kept.isEmpty ? null : kept.first;
  root.children
    ..clear()
    ..addAll(kept);
  root.ratios = ratios;
  normalize(root);
  return root;
}

/// Puts [leaf] beside [targetId] along [axis]; [before] puts it first.
LayoutNode insertSplit(
  LayoutNode? root,
  TileLeaf leaf,
  String? targetId,
  String axis,
  Rational ratio, {
  bool before = false,
}) {
  final aimed = findNode(root, targetId ?? '') ?? root;
  if (aimed == null) return leaf;
  var target = aimed;
  // A TAB PAGE IS ONE TILE (ISSUES 9.2, Don killed the accidental nested
  // split). An ordinary split aimed at a tabbed leaf cuts BESIDE THE WHOLE
  // STACK, never inside whichever page happened to be showing: the stack is
  // the box, and what a box holds is changed by swapping, not by growing a
  // second tree inside one of its pages. Climbing every tabs ancestor is what
  // makes a stack inside a stack behave the same way.
  for (var above = parentOf(root, target.id); above != null && above.mode == 'tabs'; ) {
    target = above;
    above = parentOf(root, target.id);
  }
  final parent = parentOf(root, target.id);
  final split = Branch(
    mintContainerId('split'),
    mode: 'split',
    axis: axis,
    children: before ? [leaf, target] : [target, leaf],
    ratios: before ? [ratio, Rational.one - ratio] : [Rational.one - ratio, ratio],
  );
  if (parent == null) return split;
  parent.children[parent.children.indexOf(target)] = split;
  return root!;
}

/// Tabs [leaf] under [targetId]: joins an existing tab container, or makes one.
LayoutNode insertTab(LayoutNode? root, TileLeaf leaf, String targetId) {
  final target = findNode(root, targetId);
  if (root == null || target == null) return leaf;
  final parent = parentOf(root, targetId);
  if (parent != null && parent.mode == 'tabs') {
    parent.active = parent.children.indexOf(target) + 1;
    parent.children.insert(parent.active, leaf);
    parent.ratios = [];
    normalize(parent);
    return root;
  }
  final tabs = Branch(mintContainerId('tabs'), mode: 'tabs', children: [target, leaf], active: 1);
  if (parent == null) return tabs;
  parent.children[parent.children.indexOf(target)] = tabs;
  return root;
}

/// How many tabs sit in the container holding [targetId], counting the tile
/// itself when it is not already tabbed.
/// The tab stack [targetId] sits in, or null when it is not tabbed. What an
/// overflow splits: a sibling BESIDE the stack, never a second tile inside
/// whichever page happened to be showing.
String? tabContainerOf(LayoutNode? root, String targetId) {
  final parent = parentOf(root, targetId);
  return parent != null && parent.mode == 'tabs' ? parent.id : null;
}

int tabsAt(LayoutNode? root, String targetId) {
  final parent = parentOf(root, targetId);
  return parent != null && parent.mode == 'tabs' ? parent.children.length : 1;
}

/// A hand move: pull the tile out, then drop it on a target edge or centre.
LayoutNode? moveNode(LayoutNode? root, String id, String targetId, String zone, Rational ratio) {
  final leaf = findNode(root, id);
  if (leaf is! TileLeaf || id == targetId) return root;
  final pruned = removeNode(root, id);
  if (pruned == null || findNode(pruned, targetId) == null) return pruned ?? leaf;
  if (zone == 'center') return insertTab(pruned, leaf, targetId);
  // INTO THE INNER TREE (ISSUES 9.2, Don's ruling on the named subtree): "plain
  // drag targets the app layer; alt-drag drops INTO a container's inner tree".
  // Every edge zone lands the leaf BESIDE the container on the stage; this one
  // lands it among the container's own children, so a board is one box from
  // outside and a tree inside. A LEAF has no inner tree to join, so `into` on
  // one is a tab under it -- the nearest thing to "inside this box" a leaf has.
  if (zone == 'into') {
    final target = findNode(pruned, targetId);
    if (target is! Branch) return insertTab(pruned, leaf, targetId);
    target.children.add(leaf);
    target.ratios = [];
    normalize(target);
    return pruned;
  }
  final axis = zone == 'left' || zone == 'right' ? 'row' : 'column';
  return insertSplit(pruned, leaf, targetId, axis, ratio, before: zone == 'left' || zone == 'up');
}

/// Moves the boundary after child [index], leaving the other children alone.
/// [settle] is the authored snap function -- identity by default, so a drag
/// tracks the pointer and lands where it was let go rather than on a ladder of
/// shipped stop points (ruled 2026-08-28).
void setRatio(Branch branch, int index, Rational value, [Rational Function(Rational)? settle]) {
  final count = branch.children.length;
  if (index < 0 || index + 1 >= count) return;
  final least = Rational.one / Rational.fromInt(16 * count);
  final ratios = branch.ratios.toList();
  final wanted = settle == null ? value : settle(value);
  var moving = wanted - ratios[index];
  if (moving > Rational.zero) {
    // GROWING TAKES FROM THE FAR SIDE, in order, each neighbour down to its
    // floor before the next gives anything. A boundary that could only trade
    // with the tile beside it is a tile that can never be made bigger than its
    // neighbour's share -- which is exactly "I can't configure them cleanly to
    // a good size" (Don, 2026-08-28).
    var taken = Rational.zero;
    for (var other = index + 1; other < count && moving > Rational.zero; other++) {
      final spare = ratios[other] - least;
      if (spare <= Rational.zero) continue;
      final take = spare < moving ? spare : moving;
      ratios[other] -= take;
      taken += take;
      moving -= take;
    }
    ratios[index] += taken;
  } else {
    // Shrinking hands the room to the tile the boundary is moving toward.
    final spare = ratios[index] - least;
    final give = spare <= Rational.zero ? Rational.zero : (spare < -moving ? spare : -moving);
    ratios[index] -= give;
    ratios[index + 1] += give;
  }
  branch.ratios = ratios;
}

/// Puts the child at [from] at [to] within its own container: what dropping a
/// tab back onto its own strip does.
void reorderChild(Branch branch, int from, int to) {
  final count = branch.children.length;
  if (from < 0 || from >= count || to < 0 || to >= count || from == to) return;
  final child = branch.children.removeAt(from);
  final ratios = branch.ratios.toList();
  final ratio = ratios.removeAt(from);
  branch.children.insert(to, child);
  ratios.insert(to, ratio);
  branch.ratios = ratios;
  branch.active = to;
  normalize(branch);
}

/// Every container between [id] and the root, nearest first.
List<Branch> ancestorsOf(LayoutNode? root, String id) {
  final chain = <Branch>[];
  for (var parent = parentOf(root, id); parent != null; parent = parentOf(root, parent.id)) {
    chain.add(parent);
  }
  return chain;
}

/// THE STAGE REGION: where a tile that is not chrome belongs. Bars are chrome
/// pinned to an edge, so a new view never lands among them and never splits one
/// (ruled 2026-08-28); [prefer] wins when it is itself a stage tile.
String? stageRegion(LayoutNode? root, {List<String?> prefer = const [], String? avoid}) {
  bool stage(TileLeaf leaf) =>
      leaf.type != 'bar' && leaf.id != avoid && !amongChrome(root, leaf.id);
  final leaves = leavesOf(root);
  for (final wanted in prefer) {
    final leaf = leaves.where((leaf) => leaf.id == wanted).firstOrNull;
    if (leaf != null && stage(leaf)) return leaf.id;
  }
  final open = leaves.where(stage).toList();
  // Where the work is: a view tile before anything else, and never the chrome.
  return (open.where((leaf) => leaf.type == 'view').lastOrNull ?? open.lastOrNull)?.id;
}

/// Whether [id] sits inside a container the layout file calls `chrome`.
bool amongChrome(LayoutNode? root, String id) =>
    ancestorsOf(root, id).any((branch) => branch.name == 'chrome');

/// A layout read from disk, made legal. The stale shape is REPAIRED rather than
/// refused (which would lose the arrangement) or reset (which would lose more):
/// a tile that split the chrome column is pulled out to the stage region, and
/// the chrome column itself -- a shape the shipped preset no longer makes, and
/// why Don's bars came back as one tall empty box -- is dissolved, its bars
/// re-anchored across the top at [barShare] each. Nothing is dropped.
LayoutNode? normalizeLayout(LayoutNode? root, {Rational? barShare}) {
  var tree = root;
  final share = barShare ?? Rational.fromInt(1, 64);
  for (final leaf in leavesOf(tree)) {
    if (leaf.type == 'bar' || !amongChrome(tree, leaf.id)) continue;
    final home = stageRegion(tree, avoid: leaf.id);
    tree = removeNode(tree, leaf.id);
    if (tree == null) return leaf;
    tree = insertSplit(
      tree,
      leaf,
      home != null && findNode(tree, home) != null ? home : null,
      'row',
      Rational.fromInt(1, 2),
      before: true,
    );
  }
  for (var guard = 0; guard < 8; guard++) {
    final chrome = findWhere(tree, (node) => node is Branch && node.name == 'chrome') as Branch?;
    if (chrome == null) break;
    final bars = leavesOf(chrome);
    tree = removeNode(tree, chrome.id);
    for (final bar in bars.reversed) {
      tree = tree == null ? bar : insertSplit(tree, bar, null, 'column', share, before: true);
    }
  }
  return tree;
}

/// Exchanges two leaves where they stand. Sizes belong to the containers, so a
/// swap moves the tiles and touches no ratio.
LayoutNode? swapLeaves(LayoutNode? root, String a, String b) {
  final left = findNode(root, a), right = findNode(root, b);
  if (left is! TileLeaf || right is! TileLeaf || a == b) return root;
  final over = parentOf(root, a), under = parentOf(root, b);
  if (over == null || under == null) return root;
  // Both places are read BEFORE either is written: two tiles in one container
  // would otherwise overwrite each other's slot.
  final here = over.children.indexWhere((child) => child.id == a);
  final there = under.children.indexWhere((child) => child.id == b);
  over.children[here] = right;
  under.children[there] = left;
  return root;
}

/// Everything but [keep] and, when [bars] is true, the chrome: what a ZOOM
/// shows. The tree it is built from is untouched, so toggling back restores the
/// arrangement exactly.
LayoutNode? zoomedTo(LayoutNode? root, String keep, {bool bars = true}) {
  var tree = nodeFromJson(root?.toJson());
  for (final leaf in leavesOf(tree)) {
    if (leaf.id == keep || (bars && leaf.type == 'bar')) continue;
    tree = removeNode(tree, leaf.id);
  }
  return findNode(tree, keep) == null ? null : tree;
}

LayoutNode? nodeFromJson(Object? source) {
  if (source is! Map) return null;
  final id = '${source['id'] ?? ''}';
  if (id.isEmpty) return null;
  _noteId(id);
  if (source['mode'] == null) {
    return TileLeaf(
      id,
      type: '${source['type'] ?? 'view'}',
      klass: '${source['class'] ?? ''}',
      title: '${source['title'] ?? ''}',
    );
  }
  final children = [
    for (final child in source['children'] is List ? source['children'] as List : const [])
      ?nodeFromJson(child),
  ];
  if (children.length < 2) return children.firstOrNull;
  return Branch(
    id,
    mode: '${source['mode']}',
    axis: '${source['axis'] ?? 'row'}',
    name: source['name'] == null ? null : '${source['name']}',
    children: children,
    ratios: [
      if (source['ratios'] is List)
        for (final value in source['ratios'] as List) rationalOr(value, Rational.zero),
    ],
    active: source['active'] is int ? source['active'] as int : 0,
    ratio: rationalOr(source['ratio'], Rational.fromInt(1, 2)),
  );
}

/// A number the file wrote, or the fallback: a malformed ratio costs its own
/// value and nothing else.
Rational rationalOr(Object? source, Rational fallback) {
  try {
    return Rational.parse('${source ?? ''}');
  } on FormatException {
    return fallback;
  }
}
