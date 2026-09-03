// TREE IS A LOCAL GRAPH, LAID OUT BY SIMULATION (ISSUES 9.2, Don: "Tree should
// behave more like the local graph in Obsidian").
//
// Consistent with the standing ruling that the Obsidian model is the GUI target,
// and the right instrument for what Tree shows: the stapled pile IS a graph, and
// Tree draws it as rings of hops -- a ring per distance, mates spaced evenly by
// id -- which says nothing about which ring-mates are stapled to each other.
// Obsidian's local graph is a force-directed neighbourhood: the object you are
// on at the centre, its neighbours placed by simulation, a depth control, node
// size and colour carrying meaning, hover lighting a node's own edges, drag to
// reposition, pan and zoom over the field.
//
// THE CONTRACT, as the signature it should have (does not exist yet):
//
//   // lib/lens/tree/graph_layout.dart, beside radialLayout
//   Map<String, Offset> forceLayout(
//     Graph graph,
//     Offset centre, {
//     required Tunable? read,                 // every number a setting: tree.edgeLength,
//                                             // tree.repulsion, tree.settleSteps ... never a literal
//     Map<String, Offset> pinned = const {},  // where the hand holds a node: honoured exactly
//   });
//
// Properties, all of which hold for any reasonable simulation and none of
// which hold for the ring layout:
//
//   1. STAPLES PULL. A cluster of mutually stapled objects draws as a cluster:
//      every member sits nearer to every other member than to any object of a
//      different cluster at the same hop. Rings space by id, so clusters
//      interleave -- that is the lie about structure the report names.
//   2. THE HAND WINS. A pinned node is exactly where it was put: a drag moves
//      the node under the pointer, whatever the springs would prefer.
//   3. THE CENTRE IS WHAT YOU ARE ON. The root (hop zero) sits at the centre.
//   4. THE SAME GRAPH DRAWS THE SAME WAY. No wall-clock seed: two layouts of one
//      graph are identical, so a lens reopened is the lens closed.
//
// NOT ASSERTED, because each waits on a ruling or a seam that does not exist:
// whether a dragged node PINS after release (an authored position, a real
// record) or springs back; whether the centre follows selection across every
// lens; and node SIZE from the display-weight derivation (`weightOf` reads a
// Fact, and a graph node is an id -- the Fact-free reading is the implementer's
// seam). Drag itself is not asserted at widget level: today a drag on a node
// authors containment on drop, and which chord carries which verb is unruled.
//
// Generative: seeded cluster sizes and seeded, unordered ids -- so the ring
// layout cannot pass by placing id-adjacent nodes side by side.

import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/lens/tree/graph_layout.dart';
import 'package:chronolog/lens/tunables.dart';
import 'package:flutter_test/flutter_test.dart';

final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

String seeded(String message) => '$message  (set CHRONOLOG_SEED=$runSeed to reproduce)';

final Tunable read = chronologSettings().tunable;

const Offset centre = Offset(480, 360);

GraphNode node(String id, int distance) => (id: id, map: 'events', label: id, distance: distance);

/// A root with two cliques hanging off it, every member of each at hop one. Ids
/// are random hex so id order says nothing about cluster membership.
({Graph graph, List<String> a, List<String> b}) barbell(Random random) {
  String fresh() => 'n:${random.nextInt(1 << 30).toRadixString(16)}';
  // Three or four a side: enough that a ring cannot keep them together by luck,
  // few enough that a settled clique's diameter stays under its distance to
  // the other clique.
  final a = [for (var i = 0; i < 3 + random.nextInt(2); i += 1) fresh()];
  final b = [for (var i = 0; i < 3 + random.nextInt(2); i += 1) fresh()];
  final edges = <GraphEdge>[
    for (final id in [...a, ...b]) (from: 'root', to: id, kind: stapleEdge),
    for (final cluster in [a, b])
      for (var i = 0; i < cluster.length; i += 1)
        for (var j = i + 1; j < cluster.length; j += 1)
          (from: cluster[i], to: cluster[j], kind: stapleEdge),
  ];
  final nodes = [node('root', 0), for (final id in [...a, ...b]) node(id, 1)]..shuffle(random);
  return (graph: (nodes: nodes, edges: edges, hidden: 0), a: a, b: b);
}

double gap(Map<String, Offset> places, String from, String to) => (places[from]! - places[to]!).distance;

void main() {
  // ignore: avoid_print
  print('FORCE LAYOUT RUN SEED: $runSeed  (set CHRONOLOG_SEED=$runSeed to reproduce)');

  test('staples pull: a clique of stapled objects draws as a cluster, apart from the other clique', () {
    final random = Random(runSeed);
    var checked = 0;
    for (var index = 0; index < 8; index += 1) {
      final made = barbell(random);
      final places = forceLayout(made.graph, centre, read: read);
      for (final (mine, theirs) in [(made.a, made.b), (made.b, made.a)]) {
        for (final one in mine) {
          for (final mate in mine) {
            if (mate == one) continue;
            for (final stranger in theirs) {
              expect(
                gap(places, one, mate),
                lessThan(gap(places, one, stranger)),
                reason: seeded(
                  'ISSUES 9.2: $one is stapled to $mate and not to $stranger, yet sits farther from '
                  'its mate (${gap(places, one, mate).toStringAsFixed(1)}px) than from the stranger '
                  '(${gap(places, one, stranger).toStringAsFixed(1)}px). The layout placed hop-one '
                  'nodes by id, not by what they are stapled to.',
                ),
              );
            }
          }
        }
      }
      checked += 1;
    }
    expect(checked, greaterThan(0), reason: seeded('at least one graph was asked'));
  });

  test('the hand wins: a pinned node is exactly where it was put', () {
    final random = Random(runSeed + 1);
    final made = barbell(random);
    final pinned = {
      made.a.first: centre + Offset(random.nextDouble() * 400 - 200, random.nextDouble() * 300 - 150),
      made.b.first: centre + Offset(random.nextDouble() * 400 - 200, random.nextDouble() * 300 - 150),
    };
    final places = forceLayout(made.graph, centre, read: read, pinned: pinned);
    for (final entry in pinned.entries) {
      expect(
        places[entry.key],
        equals(entry.value),
        reason: seeded('${entry.key} was pinned at ${entry.value} and the simulation moved it to ${places[entry.key]}'),
      );
    }
    expect(places.length, made.graph.nodes.length, reason: seeded('every node is placed, pinned or not'));
  });

  test('the centre is what you are on: the root sits at the centre', () {
    final random = Random(runSeed + 2);
    final made = barbell(random);
    final places = forceLayout(made.graph, centre, read: read);
    expect(
      (places['root']! - centre).distance,
      lessThan(1e-6),
      reason: seeded('the hop-zero node is the object the eye is on, and it is the centre of the field'),
    );
  });

  test('the same graph draws the same way twice', () {
    final random = Random(runSeed + 3);
    final made = barbell(random);
    final once = forceLayout(made.graph, centre, read: read);
    final again = forceLayout(made.graph, centre, read: read);
    expect(again, equals(once), reason: seeded('a layout that depends on the clock is a lens that never reopens the same'));
  });
}
