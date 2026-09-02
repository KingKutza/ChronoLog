// THE ZOOM IS DERIVED, NEVER A STORED COPY (ISSUES 9.2, Don's live break).
//
// "The Frame card took over both lower tiles, and when I closed it I get 'No
// tile named card:frames:one is open', and I cannot open another tile." Zoom
// kept a pruned COPY of the tree; close mutated the real tree and never the
// copy; every later open landed under the zoom, invisible. The rule:
//
//   displayRoot derives from root on every read. Closing the zoomed tile
//   restores the arrangement. Opening a tile while zoomed makes it visible
//   (Don: the zoom clears).

import 'package:chronolog/stage/layout_tree.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:flutter/widgets.dart';
import 'package:test/test.dart';

TileSpec spec(String id) => TileSpec(
  id: id,
  type: 'view',
  klass: 'lens',
  title: id,
  build: (context) => const SizedBox.shrink(),
);

Set<String> shown(Stage stage) => {for (final leaf in leavesOf(stage.displayRoot)) leaf.id};

void main() {
  test('closing the zoomed tile brings the arrangement back', () {
    final stage = Stage()
      ..open(spec('a'))
      ..open(spec('b'))
      ..open(spec('c'));
    stage.toggleZoom('a');
    expect(shown(stage), equals({'a'}), reason: 'zoomed: only the zoomed tile shows');
    stage.close('a');
    expect(stage.zoomedId, isNull, reason: 'ISSUES 9.2: a zoom whose tile is gone clears itself');
    expect(
      shown(stage),
      equals({'b', 'c'}),
      reason:
          'ISSUES 9.2: the stage kept drawing a stale copy holding the closed leaf '
          '("No tile named ... is open"). displayRoot must derive from root.',
    );
  });

  test('opening a tile while zoomed shows it', () {
    final stage = Stage()
      ..open(spec('a'))
      ..open(spec('b'));
    stage.toggleZoom('b');
    stage.open(spec('c'));
    expect(
      shown(stage),
      contains('c'),
      reason:
          'ISSUES 9.2 (Don: clear the zoom): a tile opened under a zoom landed in the real '
          'tree, invisible. The hand asked to see something; the zoom clears.',
    );
  });
}
