// A TAB PAGE IS ONE TILE; THE AUTHORED CONTAINER IS THE FEATURE (ISSUES 9.2).
//
// Don killed the accidental nested split ("a tab page is one tile; change what
// a box holds by swapping") and then ruled the deliberate form: a board is a
// NAMED SUBTREE with its own inner tree, entered by alt-drag, never by an
// ordinary split landing inside a tab page.

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/stage/layout_tree.dart';
import 'package:test/test.dart';

TileLeaf leaf(String id) => TileLeaf(id, type: 'view', klass: 'lens', title: id);

void main() {
  test('splitting a tabbed tile splits BESIDE the stack, never inside the page', () {
    var root = insertTab(leaf('a'), leaf('b'), 'a');
    root = insertSplit(root, leaf('c'), 'a', 'row', Rational.fromInt(1, 2), before: false);
    final stack = tabContainerOf(root, 'a');
    expect(stack, isNotNull, reason: 'a is still a tab');
    expect(
      parentOf(root, 'a')?.mode,
      equals('tabs'),
      reason:
          'ISSUES 9.2 (killed idea): an ordinary split on a tabbed leaf must not turn the '
          'tab PAGE into a split. The new tile goes beside the whole stack.',
    );
    expect(parentOf(root, stack!)?.mode, equals('split'), reason: 'the split holds the stack and c');
    expect(
      parentOf(root, 'c')?.id,
      equals(parentOf(root, stack)?.id),
      reason: 'c is the sibling of the stack',
    );
  });

  test('a named subtree is one box outside and a tree inside', () {
    // WORK ITEM (ISSUES 9.2, boards as named subtrees): no layout node kind is a
    // container-with-inner-tree today, and no drop zone distinguishes "into the
    // inner tree" (alt-drag) from "onto the stage". When the seam exists this
    // test builds a board of column tiles, drops a tile onto it with and without
    // the modifier, and asserts where each lands.
    fail(
      'ISSUES 9.2: no named-subtree node in the layout tree, no alt-drag inner drop. '
      'Build both; then assert the two drop targets here.',
    );
  });
}
