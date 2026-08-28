// Properties of the layout tree over random insert / close / move sequences.
// Nothing here pins a count: the invariants are structural.

import 'dart:math';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/stage/layout_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart' show seeds, specSeed;

const List<String> _zones = ['left', 'right', 'up', 'down', 'center'];
final Rational _half = Rational.fromInt(1, 2);

TileLeaf _leaf(int index) =>
    TileLeaf('tile:$index', type: index.isEven ? 'view' : 'card', klass: 'k${index % 3}');

/// Every structural claim the tree makes, checked at once.
void _sound(LayoutNode? root) {
  if (root == null) return;
  final seen = <String>{};
  void walk(LayoutNode node) {
    expect(seen.add(node.id), isTrue, reason: 'duplicate id ${node.id}');
    expect(findNode(root, node.id), same(node), reason: '${node.id} is unreachable');
    if (node is! Branch) return;
    expect(node.children.length, greaterThan(1), reason: 'a container with one child survived');
    expect(node.ratios.length, node.children.length);
    var total = Rational.zero;
    for (final value in node.ratios) {
      expect(value > Rational.zero, isTrue);
      total += value;
    }
    expect(total, Rational.one, reason: 'ratios must sum to one');
    expect(node.active, inInclusiveRange(0, node.children.length - 1));
    node.children.forEach(walk);
  }

  walk(root);
}

void main() {
  test('a random build stays sound and every live tile is reachable', () {
    for (final seed in seeds(24)) {
      final random = Random(seed);
      final live = <String>{};
      LayoutNode? root;
      for (var step = 0; step < 30; step++) {
        final leaves = leavesOf(root);
        final action = random.nextInt(10);
        if (root == null || action < 5) {
          final leaf = _leaf(step);
          final target = leaves.isEmpty ? null : leaves[random.nextInt(leaves.length)].id;
          root = root == null
              ? leaf
              : (random.nextBool() && target != null
                    ? insertTab(root, leaf, target)
                    : insertSplit(root, leaf, target, random.nextBool() ? 'row' : 'column', _half));
          live.add(leaf.id);
        } else if (action < 8 && leaves.length > 1) {
          final from = leaves[random.nextInt(leaves.length)].id;
          final onto = leaves[random.nextInt(leaves.length)].id;
          root = moveNode(root, from, onto, _zones[random.nextInt(_zones.length)], _half);
        } else if (leaves.isNotEmpty) {
          final gone = leaves[random.nextInt(leaves.length)].id;
          root = removeNode(root, gone);
          live.remove(gone);
        }
        _sound(root);
        expect(leavesOf(root).map((leaf) => leaf.id).toSet(), live);
      }
    }
  });

  test('a closed tile never leaves an empty or single-child container', () {
    var root = insertSplit(_leaf(0), _leaf(1), 'tile:0', 'row', _half);
    root = insertTab(root, _leaf(2), 'tile:1');
    final pruned = removeNode(root, 'tile:2');
    _sound(pruned);
    expect(findWhere(pruned, (node) => node is Branch && node.mode == 'tabs'), isNull);
  });

  test('a tree round-trips through JSON', () {
    final random = Random(specSeed);
    LayoutNode root = _leaf(0);
    for (var step = 1; step < 12; step++) {
      final leaves = leavesOf(root);
      root = random.nextBool()
          ? insertTab(root, _leaf(step), leaves[random.nextInt(leaves.length)].id)
          : insertSplit(
              root,
              _leaf(step),
              leaves[random.nextInt(leaves.length)].id,
              'column',
              _half,
            );
    }
    final written = root.toJson();
    expect(nodeFromJson(written)!.toJson(), written);
  });

  test('a divider move trades with its neighbour first and never starves anyone', () {
    for (final seed in seeds(12)) {
      final random = Random(seed);
      final branch = Branch('b', mode: 'split', children: [_leaf(0), _leaf(1), _leaf(2)]);
      setRatio(branch, 0, Rational.parse((random.nextDouble() * 2 - 0.5).toStringAsFixed(4)));
      for (final ratio in branch.ratios) {
        expect(ratio > Rational.zero, isTrue, reason: 'no tile is starved to nothing');
      }
      _sound(branch);
    }
  });

  test('growing past a neighbour keeps taking from the far side', () {
    // A boundary that could only trade with the tile beside it is a tile that
    // can never be made bigger than its neighbour's share (Don, 2026-08-28).
    final branch = Branch(
      'b',
      mode: 'split',
      children: [_leaf(0), _leaf(1), _leaf(2)],
      ratios: [Rational.fromInt(1, 20), Rational.fromInt(1, 20), Rational.fromInt(9, 10)],
    );
    setRatio(branch, 0, Rational.fromInt(1, 2));
    expect(branch.ratios[0] >= Rational.fromInt(2, 5), isTrue, reason: 'it actually grew');
    expect(branch.ratios[2] < Rational.fromInt(9, 10), isTrue, reason: 'the far side gave');
    _sound(branch);
  });

  test('with no authored snap a drag lands exactly where it was let go', () {
    final branch = Branch('b', mode: 'split', children: [_leaf(0), _leaf(1)]);
    final wanted = Rational.fromInt(37, 100);
    setRatio(branch, 0, wanted);
    expect(branch.ratios[0], wanted, reason: 'the shipped ladder of stop points is gone');
    setRatio(branch, 0, wanted, (ratio) => _half);
    expect(branch.ratios[0], _half, reason: 'an authored snap still settles the drag');
  });

  test('a stale chrome column is repaired, not refused and not reset', () {
    final chrome = Branch(
      'chrome',
      mode: 'split',
      axis: 'column',
      name: 'chrome',
      children: [
        TileLeaf('bar:document', type: 'bar', klass: 'documentBar'),
        TileLeaf('bar:view', type: 'bar', klass: 'viewBar'),
        TileLeaf('view:1', type: 'view', klass: 'lens'),
      ],
    );
    final root = normalizeLayout(
      Branch(
        'root',
        mode: 'split',
        axis: 'row',
        children: [
          chrome,
          TileLeaf('minimap:main', type: 'minimap', klass: 'field'),
        ],
      ),
    );
    for (final id in ['bar:document', 'bar:view', 'view:1', 'minimap:main']) {
      expect(findNode(root, id), isNotNull, reason: '$id is kept, not dropped');
    }
    expect(containerNamed(root, 'chrome'), isNull, reason: 'the chrome column is dissolved');
    expect(amongChrome(root, 'view:1'), isFalse, reason: 'the view left the chrome column');
  });

  test('a swap trades two tiles and touches no ratio', () {
    final root = insertSplit(_leaf(0), _leaf(1), 'tile:0', 'row', Rational.fromInt(1, 4));
    final before = (parentOf(root, 'tile:0') as Branch).ratios.toList();
    final swapped = swapLeaves(root, 'tile:0', 'tile:1') as Branch;
    expect(swapped.children.map((child) => child.id), ['tile:1', 'tile:0']);
    expect(swapped.ratios, before, reason: 'sizes belong to the container, not the tile');
  });

  test('a zoom keeps the chrome and hands the arrangement back untouched', () {
    final root = Branch(
      'root',
      mode: 'split',
      axis: 'column',
      children: [
        TileLeaf('bar:view', type: 'bar', klass: 'viewBar'),
        TileLeaf('view:1', type: 'view', klass: 'lens'),
        TileLeaf('minimap:main', type: 'minimap', klass: 'field'),
      ],
    );
    final written = root.toJson();
    final zoomed = zoomedTo(root, 'view:1');
    expect(leavesOf(zoomed).map((leaf) => leaf.id), ['bar:view', 'view:1']);
    expect(leavesOf(zoomedTo(root, 'view:1', bars: false)).map((l) => l.id), ['view:1']);
    expect(root.toJson(), written, reason: 'the arrangement a zoom came from is untouched');
  });

  test('a tab dropped on its own strip reorders rather than moving out', () {
    final branch = Branch('tabs', mode: 'tabs', children: [_leaf(0), _leaf(1), _leaf(2)]);
    reorderChild(branch, 2, 0);
    expect(branch.children.map((child) => child.id), ['tile:2', 'tile:0', 'tile:1']);
    expect(branch.active, 0);
    _sound(branch);
  });

  test('directional focus finds the neighbour on the axis it was cut on', () {
    final root = insertSplit(_leaf(0), _leaf(1), 'tile:0', 'row', _half);
    expect(directionalNeighbor(root, 'tile:0', 'right'), 'tile:1');
    expect(directionalNeighbor(root, 'tile:1', 'left'), 'tile:0');
    expect(directionalNeighbor(root, 'tile:0', 'down'), isNull);
  });
}
