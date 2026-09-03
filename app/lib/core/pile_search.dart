// Pure Dart. Nothing under lib/core/ may import Flutter or a third-party
// package.
//
// ZERO-STAPLE OBJECTS AND ORPHANS ARE FINDABLE, AS A TERM IN THE ONE MATH
// (ISSUES 9.2, Don: "Is there a way to search for 0-staple objects, and/or
// orphans? (Same thing.)").
//
// The engine already knew -- `staples.dart` names `unstapled` as an extent
// source, distinct from `unresolved` -- and nothing surfaced either. This is
// not a panel and not a filter: "the stapled pile is a graph, project the
// graph", so an object with zero staples has DEGREE ZERO, and the honest form
// is a graph MEASURE the one math can compare. That gives the neighbouring
// questions out of the same grammar rather than as three features:
//
//   staples == 0                     the orphan, Don's question
//   unresolved > 0                   somebody said something that will not
//                                    resolve, which is not the same fact
//   staples > 0 and neighbours == 0  reachable from nothing else -- a component
//                                    of one, which a one-ended pin is
//
// No term is a keyword special-cased in a search path. Each is a NUMBER bound
// in the one math's [Env], exactly as `w` is bound for a weight formula, so
// `staples == 0 or a`, `not (staples == 0)` and `unresolved > 0 and not b` all
// parse and mean what the algebra says. One math, used everywhere.

import 'exact.dart';
import 'math.dart';
import 'projection.dart';
import 'records.dart';

/// What a pile search found: the ids listed, and how many more matched than the
/// window had room for. A budget bounds WORK, never DATA.
typedef PileHits = ({List<String> ids, int more});

/// The degree measures one object wears in the graph, bound by name.
///
/// The three are what make the three populations pairwise disjoint, which is
/// the whole of "keep them distinct" made executable:
///  * [staples] every staple record NAMING this object, however many ends it
///    has -- a one-ended pin counts, because somebody said it;
///  * [unresolved] of those, the ones with an end whose position cannot be read
///    under its frame's law, or that names a record the document does not hold;
///  * [neighbours] the distinct OTHER records those staples name and the
///    document HOLDS, position irrelevant: a staple to a frame whose law cannot
///    place it is still a staple to a real neighbour.
const String stapleCountName = 'staples';
const String unresolvedCountName = 'unresolved';
const String neighbourCountName = 'neighbours';

/// SEARCH THE PILE with an expression in the one math.
///
/// [source] is parsed by [parse] itself -- a malformed query is a [MathRefusal]
/// carrying its position, never a silent empty result. Per object the resolver
/// binds the three numbers above and every name in [bindings], which is true
/// when the object is stapled to the frame that binding names -- so a frame name
/// and a graph measure compose in one sentence.
///
/// [window] bounds the ids returned and never the count: `more` is what else
/// matched.
PileHits searchPile(
  ProjectionEngine engine,
  String source, {
  Map<String, String> bindings = const {},
  int? window,
}) {
  // ONCE, not per object. The parse is the same for five thousand objects and
  // an expression re-read per row is a scan pretending to be a query.
  final expression = parse(source);
  final document = engine.document;
  final indexes = engine.indexes;
  final matched = <String>[];
  for (final objectId in document.events.keys.toList()..sort()) {
    final staples = indexes.staplesOf(objectId);
    final neighbours = <String>{};
    var unresolved = 0;
    for (final staple in staples) {
      var broken = false;
      for (final end in indexes.endsOf(staple)) {
        if (end.id == objectId) continue;
        // Asked through the record map the end itself names, so a fourth end
        // form is reachable here without a branch of its own.
        if (!document.records(end.map).containsKey(end.id)) {
          broken = true;
          continue;
        }
        neighbours.add(end.id);
        // A position the frame's own law cannot read. An end that names NO
        // position said nothing about where and so has nothing to fail at:
        // "nobody said" and "somebody said something that will not resolve" are
        // different facts, and this is the line between them.
        if (end is FrameEnd &&
            end.position?.coordinate != null &&
            engine.staples.frameEndDays(end) == null) {
          broken = true;
        }
      }
      if (broken) unresolved += 1;
    }
    final env = Env(
      values: {
        stapleCountName: Rational.fromInt(staples.length),
        unresolvedCountName: Rational.fromInt(unresolved),
        neighbourCountName: Rational.fromInt(neighbours.length),
      },
      resolver: (name) {
        final frameId = bindings[name] ?? name;
        return document.frames.containsKey(frameId)
            ? indexes.stapledFrames(objectId).contains(frameId)
            : null;
      },
    );
    final value = evaluate(expression, env);
    if (value is! bool) {
      throw const MathRefusal('A pile search must come to a truth value, not a number');
    }
    if (value) matched.add(objectId);
  }
  final listed = window == null ? matched : matched.take(window).toList();
  return (ids: listed, more: matched.length - listed.length);
}
