// The connection graph itself, and where its nodes sit.
//
// A GRAPH, NEVER A TREE (ISSUES 8.26). Multi-parent and cyclic containment are
// legal data; rendering them as a strict tree passes judgment on a shape the
// author is allowed to have. The walk is breadth-first with a visited set, so a
// cycle terminates instead of being refused.
//
// EVERY CONNECTION TYPE IS AN EDGE, and the type is the edge's vocabulary:
// contains, staple, membership, placement. A shared placement is a real edge --
// "connection is not inclusion" (Don, 2026-08-27) -- which is why both ends of
// every staple appear from either side by construction.
//
// OVERSCALE IS THE SAME MECHANISM AS EVERYWHERE, with a different metric:
// apparent magnitude falls off by GRAPH DISTANCE from the selection, and the
// budget cuts the far ring first. Whole-graph is the pile.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/projection.dart';
import '../../core/records.dart';

// The edge vocabulary and the whole-graph accessor live in the model, under the
// name the model reserved for them; this file is the LAYOUT.
export '../../core/projection.dart'
    show GraphEdge, containsEdge, membershipEdge, placementEdge, stapleEdge;

/// One node: the record it is, which map it lives in, and how many hops from the
/// selection it was reached in.
typedef GraphNode = ({String id, String map, String label, int distance});

/// What one walk found. `hidden` is a LOWER BOUND on what the budget cut.
typedef Graph = ({List<GraphNode> nodes, List<GraphEdge> edges, int hidden});

/// The neighbourhood of [roots], out to [reach] hops and no further than
/// [budget] nodes. What did not fit is counted, never silently dropped.
Graph buildGraph(
  ProjectionEngine engine, {
  required Iterable<String> roots,
  required int reach,
  required int budget,
}) {
  final distance = <String, int>{};
  final nodes = <GraphNode>[];
  final edges = <GraphEdge>{};
  var frontier = [
    for (final id in roots.toSet().toList()..sort())
      if (engine.document.frames.containsKey(id) || engine.document.events.containsKey(id)) id,
  ];
  var hidden = 0;
  for (final id in frontier) {
    distance[id] = 0;
  }
  for (var hop = 0; hop <= reach && frontier.isNotEmpty; hop += 1) {
    final next = <String>[];
    for (final id in frontier) {
      if (nodes.length >= budget) {
        hidden += 1;
        continue;
      }
      nodes.add((id: id, map: _mapOf(engine, id), label: _labelOf(engine, id), distance: hop));
      if (hop == reach) continue;
      for (final edge in engine.connectionsOf(id)) {
        edges.add(edge);
        final far = edge.from == id ? edge.to : edge.from;
        if (distance.containsKey(far)) continue;
        distance[far] = hop + 1;
        next.add(far);
      }
    }
    frontier = next..sort();
  }
  final drawn = {for (final node in nodes) node.id};
  return (
    nodes: nodes,
    edges: [
      for (final edge in edges)
        if (drawn.contains(edge.from) && drawn.contains(edge.to)) edge,
    ]..sort((a, b) => '${a.kind}${a.from}${a.to}'.compareTo('${b.kind}${b.from}${b.to}')),
    hidden: hidden,
  );
}

String _mapOf(ProjectionEngine engine, String id) =>
    engine.document.frames.containsKey(id) ? 'frames' : 'events';

String _labelOf(ProjectionEngine engine, String id) {
  final frame = engine.document.frames[id];
  if (frame != null) return frame.title ?? id;
  final title = '${obj(engine.document.events[id]?.payload)?['title'] ?? ''}'.trim();
  return title.isEmpty ? id : title;
}

/// A ring per hop, deterministic by id: the selection at the centre, its
/// neighbours around it, theirs further out. No random seed and no iteration
/// count, so the same graph draws the same way every time it is opened.
///
/// [turn] offsets each ring so a chain of single children does not draw as one
/// straight spoke of coincident labels.
Map<String, Offset> radialLayout(
  Graph graph,
  Offset centre, {
  required double step,
  required double turn,
}) {
  final rings = <int, List<GraphNode>>{};
  for (final node in graph.nodes) {
    (rings[node.distance] ??= []).add(node);
  }
  final places = <String, Offset>{};
  for (final entry in rings.entries) {
    final ring = entry.value..sort((a, b) => a.id.compareTo(b.id));
    final radius = entry.key * step;
    for (final (index, node) in ring.indexed) {
      final angle = -math.pi / 2 + entry.key * turn + index / ring.length * math.pi * 2;
      places[node.id] = ring.length == 1 && entry.key == 0
          ? centre
          : centre + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
    }
  }
  return places;
}
