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
import '../tunables.dart';
import 'tree_lens.dart';

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

/// The narrowest gap two ring-mates may sit at, as a share of one ring step.
/// A default, not a law: the Tree passes `tree.ringSpacing` and this is what
/// answers for a caller that has no settings to hand (the same shape as
/// `defaultHalfDistanceDays` in `core/falloff.dart`).
const double defaultRingSpacing = 3 / 4;

/// A RING EARNS ITS RADIUS FROM ITS OCCUPANCY (ISSUES 9.1, Don: "the issue of
/// overlap needs fixed in the tree view... I can see this getting worse with
/// more than a dozen items").
///
/// A ring per hop, deterministic by id: the selection at the centre, its
/// neighbours around it, theirs further out. No random seed and no iteration
/// count, so the same graph draws the same way every time it is opened.
///
/// The radius is NOT `distance * step` any more. That gave a ring the same room
/// whatever it held, so forty children packed shoulder to shoulder while three
/// floated far apart -- and the lines and labels riding those positions overlap
/// exactly as reported. A ring of `n` mates spaced evenly at radius `r` puts
/// adjacent mates `2 * r * sin(pi / n)` apart, so the radius that keeps a stated
/// gap is that equation solved for `r`. Overscale is the reason: usable at 500
/// or improperly built for 3.
///
/// Rings stay in order and stay a step apart whatever their occupancies do, so a
/// crowded inner ring pushes the sparse ring outside it rather than swallowing
/// it.
///
/// [turn] offsets each ring so a chain of single children does not draw as one
/// straight spoke of coincident labels.
Map<String, Offset> radialLayout(
  Graph graph,
  Offset centre, {
  required double step,
  required double turn,
  double spacing = defaultRingSpacing,
}) {
  final rings = <int, List<GraphNode>>{};
  for (final node in graph.nodes) {
    (rings[node.distance] ??= []).add(node);
  }
  final places = <String, Offset>{};
  final gap = step * spacing;
  // Hops in order, so each ring can be held outside the one within it.
  final hops = rings.keys.toList()..sort();
  var inner = -step;
  for (final hop in hops) {
    final ring = rings[hop]!..sort((a, b) => a.id.compareTo(b.id));
    // What this ring's own occupancy asks for. One node asks for nothing: it
    // has no ring-mate to be crowded by.
    final earned = ring.length < 2 ? 0.0 : gap / (2 * math.sin(math.pi / ring.length));
    final radius = math.max(math.max(hop * step, inner + step), earned);
    inner = radius;
    for (final (index, node) in ring.indexed) {
      final angle = -math.pi / 2 + hop * turn + index / ring.length * math.pi * 2;
      places[node.id] = radius <= 0
          ? centre
          : centre + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
    }
  }
  return places;
}

/// THE LOCAL GRAPH, LAID OUT BY SIMULATION (ISSUES 9.2, Don: "Tree should behave
/// more like the local graph in Obsidian").
///
/// [radialLayout] spaces ring-mates BY ID, which is a statement about the
/// alphabet and not about the pile: two objects stapled to each other land on
/// opposite sides of their ring while strangers sit shoulder to shoulder, and
/// the picture then reads as structure that is not there. A simulation says the
/// one thing the graph actually knows -- STAPLES PULL, and everything else
/// pushes -- so a cluster draws as a cluster because it is one.
///
/// Fruchterman-Reingold, which is that sentence as arithmetic: every pair
/// repels by `k^2 / d`, every edge attracts by `d^2 / k`, and a cooling cap on
/// each step's travel settles the field. A stapled pair therefore rests where
/// the two balance -- at `k`, the authored edge length -- and an unstapled pair
/// has nothing pulling it back, so it goes as far as the rest of the field
/// allows. That is the whole property the report asks for.
///
/// THE SAME GRAPH DRAWS THE SAME WAY. There is no clock and no random seed: the
/// starting positions are [radialLayout]'s, which are a function of the ids, and
/// every pass runs over sorted ids. A lens reopened is the lens closed.
///
/// THE HAND WINS. A node in [pinned] is placed exactly where it was put and
/// never moved -- a drag is an instruction, not a suggestion -- and the hop-zero
/// node is held at [centre], because the centre is what you are on.
Map<String, Offset> forceLayout(
  Graph graph,
  Offset centre, {
  required Tunable? read,
  Map<String, Offset> pinned = const {},
}) {
  final ids = [for (final node in graph.nodes) node.id]..sort();
  final held = <String>{
    for (final node in graph.nodes)
      if (node.distance == 0) node.id,
    ...pinned.keys,
  };
  final places = radialLayout(
    graph,
    centre,
    step: treePixels(read, 'tree.ringStep'),
    turn: treePixels(read, 'tree.ringTurn'),
    spacing: treePixels(read, 'tree.ringSpacing'),
  );
  for (final node in graph.nodes) {
    places[node.id] ??= centre;
    if (node.distance == 0) places[node.id] = centre;
  }
  places.addAll(pinned);
  final k = treePixels(read, 'tree.edgeLength');
  final steps = treeSetting(read, 'tree.settleSteps').round().toInt();
  final cool = treePixels(read, 'tree.settleCool');
  if (k <= 0 || steps < 1 || ids.length < 2) return places;
  // A pair exactly on top of another has no direction to push in, so the field
  // needs one: the id order, which is the same order every time.
  Offset apart(String from, String to, int rank) {
    final delta = places[from]! - places[to]!;
    if (delta.distance > 1e-9) return delta;
    final angle = rank * math.pi * 2 / ids.length;
    return Offset(math.cos(angle), math.sin(angle)) * 1e-6;
  }

  final edges = [
    for (final edge in graph.edges)
      if (places.containsKey(edge.from) && places.containsKey(edge.to)) edge,
  ];
  var travel = k;
  for (var pass = 0; pass < steps; pass += 1) {
    final push = {for (final id in ids) id: Offset.zero};
    for (var one = 0; one < ids.length; one += 1) {
      for (var two = one + 1; two < ids.length; two += 1) {
        final delta = apart(ids[one], ids[two], one);
        final gap = delta.distance;
        final force = delta / gap * (k * k / gap);
        push[ids[one]] = push[ids[one]]! + force;
        push[ids[two]] = push[ids[two]]! - force;
      }
    }
    for (final edge in edges) {
      final delta = apart(edge.from, edge.to, 0);
      final gap = delta.distance;
      final force = delta / gap * (gap * gap / k);
      push[edge.from] = push[edge.from]! - force;
      push[edge.to] = push[edge.to]! + force;
    }
    for (final id in ids) {
      if (held.contains(id)) continue;
      final force = push[id]!;
      final size = force.distance;
      if (size <= 0) continue;
      places[id] = places[id]! + force / size * math.min(size, travel);
    }
    travel *= cool;
  }
  return places;
}
