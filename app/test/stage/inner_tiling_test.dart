// A TAB PAGE IS ONE TILE; THE AUTHORED CONTAINER IS THE FEATURE (ISSUES 9.2).
//
// Don killed the accidental nested split ("a tab page is one tile; change what
// a box holds by swapping") and then ruled the deliberate form: a board is a
// NAMED SUBTREE with its own inner tree, entered by alt-drag, never by an
// ordinary split landing inside a tab page. "Plain drag targets the app layer;
// alt-drag (a settings key) drops INTO a container's inner tree; the drop
// preview outlines which."
//
// THE CONTRACT this file names (data, not new symbols): a board is a `Branch`
// whose `mode` is `board`, carrying a `name` so a placement rule may aim at it
// -- one more mode string beside `split` / `tabs` / `dwindle`, never a class of
// its own. The drop zone `into` on the tree's one move function lands a leaf
// INSIDE that branch; every edge zone lands BESIDE it on the stage, as today.
// Which modifier arms `into` is the binding `pointer.dropInto`, a text setting
// like every other pointer chord.

import 'package:chronolog/chrome/shell.dart';
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
    // "A board is a NAMED SUBTREE: one tile from outside (the WM's box), an
    // inner layout tree of column tiles inside, with its own presets." A plain
    // drop beside it lands on the stage; a drop INTO it joins the inner tree.
    final half = Rational.fromInt(1, 2);
    final board = Branch(
      'board:ai',
      mode: 'board',
      name: 'AI board',
      children: [leaf('column:open'), leaf('column:done')],
    );
    LayoutNode? root = Branch(
      'root',
      mode: 'split',
      axis: 'row',
      children: [leaf('view:lens'), board, leaf('view:spare')],
    );
    // Plain drop on the board's edge: BESIDE it, on the app layer.
    final beside = moveNode(root, 'view:spare', 'board:ai', 'left', half);
    expect(
      parentOf(beside, 'view:spare')?.id,
      isNot(equals('board:ai')),
      reason: 'a plain drag targets the app layer, never the inner tree',
    );
    expect(
      containerNamed(beside, 'AI board')?.children.map((child) => child.id),
      equals(['column:open', 'column:done']),
      reason: 'the board\'s inner tree is untouched by a drop beside it',
    );
    // The modifier drop: INTO the inner tree.
    final inside = moveNode(root, 'view:spare', 'board:ai', 'into', half);
    expect(
      parentOf(inside, 'view:spare')?.id,
      equals('board:ai'),
      reason:
          'ISSUES 9.2: no drop distinguishes "into the inner tree" from "onto the stage". The '
          '`into` zone lands the leaf INSIDE the named subtree.',
    );
    expect(
      containerNamed(inside, 'AI board')?.children.map((child) => child.id),
      containsAll(['column:open', 'column:done', 'view:spare']),
      reason: 'the board now holds three tiles inside its one box',
    );
    expect(containerNamed(inside, 'AI board')?.mode, equals('board'), reason: 'and is still a board');
    // The tree that holds it still reads and writes as JSON, board and all.
    final again = nodeFromJson(inside!.toJson());
    expect(containerNamed(again, 'AI board')?.mode, equals('board'));
    expect(
      chronologSettings().text('pointer.dropInto'),
      isNotEmpty,
      reason: 'ISSUES 9.2: which modifier drops INTO a container is a settings key, like every chord',
    );
  });
}
