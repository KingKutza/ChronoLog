// A RING EARNS RADIUS FROM ITS OCCUPANCY (ISSUES 9.1, Don's morning test).
//
// "The issue of overlap needs fixed in the tree view, especially as it will get
// busier and busier… I can see this getting worse with more than a dozen items."
// Today a hop's radius is FIXED (`distance * step`), so a ring's room never
// grows with what it holds: forty children of one root pack shoulder to
// shoulder while three float far apart. Overscale is the law — usable at 500 or
// improperly built for 3 — and the layout must space by content, not by count.
//
// The property: however many nodes share a ring, no two of them land closer
// than half a step. Quantified over seeded occupancies, never a pinned count.

import 'dart:math';

import 'package:chronolog/lens/tree/graph_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/corpus.dart';

Graph fanOf(int children) => (
  nodes: [
    (id: 'root', map: 'events', label: 'root', distance: 0),
    for (var i = 0; i < children; i++)
      (id: 'child:$i', map: 'events', label: 'child $i', distance: 1),
  ],
  edges: const <GraphEdge>[],
  hidden: 0,
);

void main() {
  for (final seed in seeds(5)) {
    test('no two ring-mates land closer than half a step (seed $seed)', () {
      final random = Random(seed);
      // Enough ring-mates that a fixed radius provably crowds them: the claim
      // is about occupancy at scale, and it must hold for ANY count after the
      // ring learns to earn its room.
      final children = 16 + random.nextInt(25);
      const step = 120.0;
      final places = radialLayout(fanOf(children), Offset.zero, step: step, turn: 0.35);
      var closest = double.infinity;
      for (var a = 0; a < children; a++) {
        for (var b = a + 1; b < children; b++) {
          final gap = (places['child:$a']! - places['child:$b']!).distance;
          if (gap < closest) closest = gap;
        }
      }
      expect(
        closest,
        greaterThanOrEqualTo(step / 2),
        reason:
            'ISSUES (9.1): $children ring-mates land ${closest.toStringAsFixed(1)}px apart '
            'on a fixed radius — the ring never earned room from its occupancy, and the '
            'lines and labels riding these positions overlap exactly as reported.',
      );
    });
  }
}
