// The Tree: a GRAPH, drawn whole.
//
// The properties are the rulings: multi-parent and cyclic containment render
// (they are legal data, and a strict tree would pass judgment on them), both
// ends of a staple are reachable from either end, apparent magnitude falls off
// monotonically by graph distance, what the budget cut is counted rather than
// dropped, and a drag onto a node authors exactly one containment relation.

import 'dart:math';

import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/lens/capacity.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/lens/tree/graph_layout.dart';
import 'package:chronolog/lens/tree/tree_lens.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/lens/tunables.dart';
import 'package:chronolog/session/settings.dart';
import 'package:chronolog/lens/view_tile.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/corpus.dart';
import '../../edit/harness.dart';
import '../../helpers/projection_scene.dart';

/// A world with placements, memberships, containment (including a CYCLE) and a
/// staple, seeded so a failure names the document that produced it.
Scene tangle(int seed) {
  final random = Random(seed);
  final world = Scene()..calendar('calendar:a');
  final objects = [
    for (var index = 0; index < 8; index += 1)
      world.object(title: 'Object $index', duration: '${30 + random.nextInt(90)}'),
  ];
  for (final (index, id) in objects.indexed) {
    world.place('calendar:a', civil(2026, 8, 10 + index, 9), event: id);
  }
  world.group('group:a', objects.take(4).toList());
  world.group('group:b', objects.skip(2).take(3).toList());
  void contains(String parent, String child) {
    final id = world.mint('relation');
    world.document = world.document.put(
      'relations',
      id,
      Relation(id: id, type: 'contains', extra: {'parent': parent, 'child': child}),
    );
  }

  // A cycle and a second parent: both legal, both drawn as what they are.
  contains(objects[0], objects[1]);
  contains(objects[1], objects[2]);
  contains(objects[2], objects[0]);
  contains(objects[3], objects[1]);
  world.staple(ends: [StapleEnd.object(objects[4]), StapleEnd.object(objects[5])]);
  return world;
}

Graph graphOver(Document document, {int reach = 3, int budget = 200}) =>
    buildGraph(ProjectionEngine(document), roots: ['calendar:a'], reach: reach, budget: budget);

/// The controller a hosted lens is handed, with nothing but the seams the Tree
/// actually uses. Uncounted test support.
class FakeTile implements ViewTileController {
  FakeTile(this.editor);

  @override
  final Editor editor;
  @override
  final Stage stage = Stage();
  @override
  final Settings settings = chronologSettings();
  @override
  CardOpener? get objectCard => null;
  @override
  CardOpener? get frameCard => null;
  @override
  String get tileId => 'tile:tree';
  @override
  String get lensId => 'tree';
  @override
  String? get primaryFrame => 'calendar:a';
  @override
  Tunable get tunable => settings.tunable;
  @override
  Projection get projection => Projection.of(const ['calendar:a']);
  @override
  Set<String> get selection => const {};
  @override
  Map<String, Object?> get view => const {};
  @override
  Rational get focusDays => Rational.zero;
  @override
  void project(String frameId) {}

  @override
  void noSuchMethod(Invocation invocation) {}
}

void main() {
  test('every drawn edge joins two drawn nodes, and a cycle terminates', () {
    for (final seed in seeds(6)) {
      final graph = graphOver(tangle(seed).document);
      final drawn = {for (final node in graph.nodes) node.id};
      expect(drawn.length, graph.nodes.length, reason: 'a node is drawn once');
      for (final edge in graph.edges) {
        expect(drawn.contains(edge.from) && drawn.contains(edge.to), isTrue, reason: 'seed $seed');
      }
      expect(
        graph.edges.any((edge) => edge.kind == containsEdge),
        isTrue,
        reason: 'containment is an edge, cycle included',
      );
    }
  });

  test('a staple is reachable from BOTH of its ends', () {
    final world = tangle(specSeed);
    final engine = ProjectionEngine(world.document);
    final staple = world.document.relations.values.firstWhere((row) => row.type == 'staple');
    final ends = engine.indexes.endsOf(staple).map((end) => end.id).toList();
    for (final end in ends) {
      final edges = engine.connectionsOf(end).where((edge) => edge.kind == stapleEdge);
      expect(
        edges.any((edge) => ends.contains(edge.to) || ends.contains(edge.from)),
        isTrue,
        reason: 'the connection is visible from $end',
      );
    }
  });

  test('apparent magnitude falls off monotonically by graph distance', () {
    final painter = TreePainter(
      graph: graphOver(tangle(specSeed).document),
      places: const {},
      theme: shipped['paper']!,
      engine: ProjectionEngine(tangle(specSeed).document),
      read: null,
    );
    var previous = double.infinity;
    for (var distance = 0; distance < 8; distance += 1) {
      final presence = painter.presence(distance);
      expect(presence, lessThanOrEqualTo(previous));
      expect(presence, greaterThan(0), reason: 'it lapses from prominence, never from truth');
      previous = presence;
    }
  });

  test('what the budget cuts is counted, never silently dropped', () {
    final graph = graphOver(tangle(specSeed).document, budget: 4);
    expect(graph.nodes.length, lessThanOrEqualTo(4));
    expect(graph.hidden, greaterThan(0));
  });

  test('the layout is deterministic and puts each ring at its own distance', () {
    final graph = graphOver(tangle(specSeed).document);
    const centre = Offset(400, 300);
    final first = radialLayout(graph, centre, step: 100, turn: 0.6);
    final again = radialLayout(graph, centre, step: 100, turn: 0.6);
    expect(first, again);
    for (final node in graph.nodes) {
      expect(
        (first[node.id]! - centre).distance,
        closeTo(node.distance * 100, 1),
        reason: 'ring ${node.distance}',
      );
    }
  });

  testWidgets(
    'a drag from one node onto another authors exactly one containment',
    timeout: const Timeout(Duration(seconds: 45)),
    (tester) async {
      // The store is real file I/O, which a widget test's fake clock never
      // completes: it has to run on the real one.
      final bench = (await tester.runAsync(
        () => openEditor(tangle(specSeed).document, label: 'tree'),
      ))!;
      addTearDown(() => tester.runAsync(() => closeEditor(bench)));
      final tile = FakeTile(bench.editor);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: TreeLens(tile: tile),
        ),
      );
      expect(tester.takeException(), isNull);
      // The graph and its layout are pure and deterministic, so the spec derives
      // the same two node positions the surface drew rather than reaching inside.
      final size = tester.getSize(find.byType(TreeLens));
      final graph = buildGraph(
        bench.editor.engine,
        roots: const ['calendar:a'],
        reach: treeSetting(null, 'tree.reach').round().toInt(),
        budget: capacityOf(size.width, size.height, null).marks,
      );
      final places = radialLayout(
        graph,
        size.center(Offset.zero),
        step: treePixels(null, 'tree.ringStep'),
        turn: treePixels(null, 'tree.ringTurn'),
      );
      final held = {
        for (final row in bench.editor.document.relations.values)
          if (row.type == 'contains') '${row.parent} ${row.child}',
      };
      final events = graph.nodes.where((node) => node.map == 'events').toList();
      final movable = [
        for (final source in events)
          for (final target in events)
            if (source.id != target.id && !held.contains('${target.id} ${source.id}'))
              [source, target],
      ].first;
      final before = held.length;
      final origin = tester.getTopLeft(find.byType(TreeLens));
      await tester.timedDragFrom(
        origin + places[movable.first.id]!,
        places[movable.last.id]! - places[movable.first.id]!,
        const Duration(milliseconds: 200),
      );
      await tester.pump(const Duration(milliseconds: 50));
      final after = bench.editor.document.relations.values
          .where((row) => row.type == 'contains')
          .length;
      expect(after, before + 1, reason: 'one relation, and one only');
    },
  );
}
