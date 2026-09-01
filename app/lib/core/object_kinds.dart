// Object kinds, state, containment, and the roster.
//
// ONE OBJECT CLASS. An event, a ToDo and a note are the same record differing
// only by traits -- there is no todo type, no note type, and no list machinery.
// [objectKinds] is an authoring catalog (what a new one is called, what role its
// placement takes, whether it is an instant), never a type system.
//
// ENUM IS THE ENEMY, twice over. The kind catalog is a Map so a fourth kind is a
// row; the STATE vocabulary is not a catalog at all. "Done" is a frame the user
// authors, being in that state IS membership in that frame, and the whole
// vocabulary of states is whichever state frames the document happens to hold.
// Nothing below can enumerate the states, which is the point.
//
// THE SEAM TO THE ENGINE. The JavaScript read four engine indexes
// (`containsByParent`, `parentsByChild`, `staplesByObject`, group memberships)
// and hung two memos off the engine's generation. [ObjectFacts] is that seam: it
// takes those four as injected accessors, defaults each to a document scan, and
// owns the memos itself -- so ONE INSTANCE IS ONE GENERATION, and the engine's
// reindex is a new instance rather than a memo it has to remember to clear. It is
// deliberately the same shape [Staples] uses, so there is one seam idiom.
//
// Reading a staple's ends -- which point an end touches, which end is the other
// one -- belongs to the staple substrate and is read from it here, so "the
// default point is start" is stated in exactly one place.

import 'coordinate_law.dart';
import 'document.dart';
import 'eras.dart';
import 'records.dart';
import 'staples.dart';

/// What authoring needs to know about one kind of object: what to call it, what
/// to call a new one, the [traits] that MAKE it that kind (membership in that
/// list is the whole definition -- nothing stores a kind field), the role its
/// placement relation takes (a ToDo's is `observed`, because a task on a calendar
/// records what happened), and whether it is an instant.
class ObjectKind {
  const ObjectKind(this.label, this.newTitle, this.traits, this.relationRole, this.zeroDuration);

  final String label, newTitle, relationRole;
  final List<String> traits;
  final bool zeroDuration;
}

/// A CATALOG, not a type system: a fourth kind is a row. What makes the row
/// legitimate is that nothing below branches on which key it is.
const Map<String, ObjectKind> objectKinds = {
  'event': ObjectKind('Event', 'New event', ['event'], 'placed', false),
  'todo': ObjectKind('ToDo', 'New ToDo', ['event', 'task', 'todo'], 'observed', true),
  'note': ObjectKind('Note', 'New note', ['event', 'note'], 'placed', true),
};

/// The traits the catalog OWNS. Every other trait on an object is the author's
/// and survives a kind change untouched -- which is why changing kind is not a
/// trait replacement.
const Set<String> controlledTraits = {'event', 'task', 'todo', 'note'};

String normalizeObjectKind(Object? value) =>
    objectKinds.containsKey(value) ? value as String : 'event';

String objectKindForEvent(Event? event) {
  final traits = event?.traits ?? const <String>[];
  if (traits.contains('task') || traits.contains('todo')) return 'todo';
  if (traits.contains('note')) return 'note';
  return 'event';
}

List<String> traitsForObjectKind(Iterable<String>? existing, Object? kind) => {
  ...objectKinds[normalizeObjectKind(kind)]!.traits,
  for (final trait in existing ?? const <String>[])
    if (!controlledTraits.contains(trait)) trait,
}.toList();

// --- State frames -----------------------------------------------------------

/// A state frame is a GROUP frame carrying the `state` trait on top -- the same
/// additive shape an importance frame uses. Both traits are required, so a
/// pattern-state frame (`['state', 'generated']`) is never mistaken for one.
const List<String> stateFrameTraits = ['set', 'group', 'state'];

/// The one deterministic state frame the substrate itself ever names, so every
/// path -- toggle, inspector, ICS import -- converges on ONE Done rather than
/// each minting its own. It is minted lazily by the first completion and NEVER
/// seeded into an empty document.
const String doneStateFrameId = 'frame:state-done';
const String doneStateTitle = 'Done';

bool isStateFrame(Frame? frame) =>
    frame != null && frame.traits.contains('group') && frame.traits.contains('state');

/// Create-if-missing. An existing frame comes back UNTOUCHED and the document
/// unchanged: the user may have retitled or recolored it, and that authorship
/// must survive every later toggle.
({Document document, Frame frame}) ensureStateFrame(
  Document document, {
  String id = doneStateFrameId,
  String title = doneStateTitle,
}) {
  final existing = document.frames[id];
  if (existing != null) return (document: document, frame: existing);
  final frame = Frame(id: id, title: title, traits: stateFrameTraits);
  return (document: document.put('frames', id, frame), frame: frame);
}

// --- What the derivations answer with ---------------------------------------

/// The instant an object reached a terminal state: a frame, a position under
/// that frame's law, and the staple that states it. `parameters` is whatever time
/// typing the end carried (`{utc: true}`), so ICS export can restate it.
typedef StateInstant = ({String frame, Coordinate coordinate, Json? parameters, Relation staple});

/// One state this object is affiliated with. `at` is a fact about the OBJECT,
/// not about any one state, so every affiliation of an object reports the same
/// one -- and null is a legal answer, because membership with no instant stated
/// is a legal shape.
typedef StateAffiliation = ({String frame, String title, Relation membership, StateInstant? at});

typedef ContainsSummary = ({int direct, int total, int open, int done, bool cyclic});

/// One roster row. A null [coordinate] IS "this one has no staple yet" -- the
/// JavaScript carried a separate `anchored` flag saying exactly that, and a
/// second statement of one fact can only ever disagree with it. `completed`
/// never requires `completedAt`: membership with no instant is legal.
typedef RosterEntry = ({
  String id,
  String title,
  Coordinate? coordinate,
  String? frame,
  bool completed,
  Coordinate? completedAt,
});

/// A relation-graph accessor: every id related to this one, in a stable order.
typedef RelatedIds = List<String> Function(String id);

class _Visit {
  _Visit(this.id, this.children);
  final String? id;
  final List<String> children;
  int index = 0;
}

/// Every derivation about an object, over one document generation.
class ObjectFacts {
  ObjectFacts(
    this.document, {
    this.indexedChildren,
    this.indexedParents,
    this.indexedGroups,
    this.indexedStaples,
  });

  final Document document;

  /// The engine's own indexes, when there is an engine. Each one is optional and
  /// each falls back to a document scan, so every derivation here is answerable
  /// with nothing but a document -- which is what makes them testable without a
  /// projection engine and correct before one is built.
  final RelatedIds? indexedChildren, indexedParents, indexedGroups;
  final StaplesOf? indexedStaples;

  final Map<String, ContainsSummary> _summaries = {};
  Set<String>? _done;

  /// The scan behind the containment seams (ruled 2026-09-01). Containment is a
  /// staple whose ends are all silent objects, and authored ORDER is the one
  /// carrier of held-by: reading it from one side gives what this holds, from
  /// the other what holds it.
  List<String> _held(String id, {required bool held}) {
    final found = <String>{};
    for (final relation in document.relations.values) {
      for (final edge in stapledContainments(relation)) {
        if (held && edge.parent == id) found.add(edge.child);
        if (!held && edge.child == id) found.add(edge.parent);
      }
    }
    return found.toList()..sort();
  }

  /// The scan behind the affiliation seam: a staple whose frame end names no
  /// point. Which end is a FRAME is what makes the group side.
  List<String> _affiliated(String id) {
    final found = <String>{};
    for (final relation in document.relations.values) {
      for (final edge in stapledAffiliations(relation)) {
        if (edge.object == id) found.add(edge.frame);
      }
    }
    return found.toList()..sort();
  }

  List<String> children(String id) => indexedChildren?.call(id) ?? _held(id, held: true);

  List<String> parents(String id) => indexedParents?.call(id) ?? _held(id, held: false);

  List<String> groups(String id) => indexedGroups?.call(id) ?? _affiliated(id);

  List<Relation> staples(String id) => indexedStaples?.call(id) ?? staplesFor(document, object: id);

  /// Authored done-memberships as ONE set, built once per generation rather than
  /// once per descendant: a project summary at overscale asks about hundreds of
  /// children, and a per-child relation scan would be quadratic.
  Set<String> doneMembers() => _done ??= {
    for (final relation in document.relations.values)
      for (final edge in stapledAffiliations(relation))
        if (edge.frame == doneStateFrameId) edge.object,
  };

  // --- The completion instant ------------------------------------------------

  /// THE COMPLETION INSTANT IS A STAPLE, AND IT IS TERMINAL: the registered
  /// `end` kind, the object's own `end` point, the other end a position under
  /// some frame's law. Backdating is nothing but that position. Null is a legal
  /// answer.
  Relation? objectEndStaple(String objectId) {
    for (final staple in staples(objectId)) {
      if (staple.kind != 'end') continue;
      if (_instant(staple, objectId) != null) return staple;
    }
    return null;
  }

  /// The frame end an end staple carries, in the `{frame, coordinate}` shape
  /// every consumer of "when" already reads. Null unless this really is a
  /// terminal end staple: the object's own `end` point at one end, a coordinate
  /// under some frame's law at the other.
  StateInstant? _instant(Relation? staple, String objectId) {
    if (staple == null) return null;
    final index = staple.endIndexOf(objectId);
    final near = index < 0 ? null : staple.ends[index];
    if (near is! ObjectEnd || endPoint(near) != 'end') return null;
    // N-ARY: the completion instant may be identified with several sheets at
    // once, and any one of them spells it. The first in authored order that
    // carries a coordinate is the one this reads -- never "the staple has more
    // than two ends so it says nothing".
    final coordinates = [
      for (final end in staple.othersThan(index))
        if (end is FrameEnd)
          if (end.position?.coordinate != null) end,
    ];
    if (coordinates.isEmpty) return null;
    final far = coordinates.first;
    final coordinate = far.position!.coordinate;
    if (coordinate == null) return null;
    return (
      frame: far.frame,
      coordinate: coordinate,
      parameters: obj(far.extra['parameters']),
      staple: staple,
    );
  }

  /// Every state this object is affiliated with, in stable frame-id order. The
  /// ONE derivation the roster, the inspector, ICS export and the contains
  /// summary all read, so "is this done, and when" has exactly one answer.
  List<StateAffiliation> stateAffiliations(String objectId) {
    if (objectId.isEmpty) return const [];
    final at = _instant(objectEndStaple(objectId), objectId);
    final entries = <StateAffiliation>[];
    for (final relation in document.relations.values) {
      // BOTH SPELLINGS OF ONE SENTENCE (ruled 2026-09-01). A `membership` record
      // and a staple whose frame end names no point say the same thing, so the
      // state grammar reads them the same way -- otherwise a Done written by
      // this build and a Done written by an older one would be different facts.
      final groups = relation.type == 'membership'
          ? [if (relation.member == objectId) ?relation.group]
          : [
              for (final edge in stapledAffiliations(relation))
                if (edge.object == objectId) edge.frame,
            ];
      for (final group in groups) {
        final frame = document.frames[group];
        if (!isStateFrame(frame)) continue;
        entries.add((frame: group, title: frame!.title ?? group, membership: relation, at: at));
      }
    }
    return entries..sort((left, right) => left.frame.compareTo(right.frame));
  }

  StateAffiliation? doneAffiliation(String objectId) =>
      firstMatch(stateAffiliations(objectId), (entry) => entry.frame == doneStateFrameId);

  // --- Containment -----------------------------------------------------------

  /// What an object contains: `direct` counts authored child edges' distinct
  /// children, `total` distinct descendants at any depth, `open`/`done` those
  /// descendants split by the done derivation.
  ///
  /// A DIAMOND is legal and counts once; a CYCLE is REPORTED with the loop
  /// broken at the revisit -- never thrown, never looped forever -- because
  /// containment passes no judgment on family-tree shape and this derivation has
  /// to survive whatever it admits. Memoized per generation so a lens can ask
  /// once per rendered row.
  ContainsSummary containsSummary(String objectId) {
    final cached = _summaries[objectId];
    if (cached != null) return cached;
    final direct = {...children(objectId)};
    final seen = <String>{};
    // An explicit on-path set, because `seen` alone cannot tell a diamond from a
    // loop; iterative, because recursion would overflow on the deep chains
    // validation deliberately allows.
    final path = <String>{objectId};
    final stack = [_Visit(null, direct.toList())];
    var cyclic = false;
    while (stack.isNotEmpty) {
      final top = stack.last;
      if (top.index >= top.children.length) {
        stack.removeLast();
        path.remove(top.id);
        continue;
      }
      final child = top.children[top.index++];
      if (path.contains(child)) {
        cyclic = true;
        continue;
      }
      if (!seen.add(child)) continue;
      path.add(child);
      stack.add(_Visit(child, children(child)));
    }
    final done = doneMembers();
    final closed = seen.where(done.contains).length;
    return _summaries[objectId] = (
      direct: direct.length,
      total: seen.length,
      open: seen.length - closed,
      done: closed,
      cyclic: cyclic,
    );
  }

  // --- The roster ------------------------------------------------------------

  /// Every object of one kind, with the position it is stapled at.
  ///
  /// Deliberately a FLAT roster, not the staple/decay model: showing every
  /// object of a kind invents no lifecycle rule that would later have to be
  /// unwound. A completed ToDo is still an entry -- completion is a fact about
  /// the object, never a reason to stop listing it.
  ///
  /// ONE relation sweep produces placements, done memberships and completion
  /// instants together, and seeds the done memo, so the whole roster costs what
  /// one object's derivation costs.
  List<RosterEntry> rosterEntries(Object? requestedKind) {
    final kind = normalizeObjectKind(requestedKind);
    final placements = <String, Relation>{};
    final done = <String>{};
    final instants = <String, (String, Coordinate)>{};
    for (final entry in document.relations.entries) {
      final relation = entry.value;
      var affiliated = false;
      for (final edge in stapledAffiliations(relation)) {
        if (edge.frame != doneStateFrameId) continue;
        done.add(edge.object);
        affiliated = true;
      }
      if (affiliated) continue;
      if (relation.isStaple && relation.kind == 'end') {
        for (final end in relation.ends) {
          if (end is! ObjectEnd) continue;
          final at = _instant(relation, end.object);
          if (at == null) continue;
          final current = instants[end.object];
          // First in the substrate's stable order (relation id), matching
          // objectEndStaple, so the roster and the inspector name one instant.
          if (current == null || entry.key.compareTo(current.$1) < 0) {
            instants[end.object] = (entry.key, at.coordinate);
          }
        }
        continue;
      }
      if (isPlacement(relation)) {
        placements.putIfAbsent(relation.event!, () => relation);
      }
    }
    _done ??= done;
    final rows = <RosterEntry>[];
    for (final event in document.events.values) {
      if (objectKindForEvent(event) != kind) continue;
      final title = str(event.payload?['title']) ?? '';
      final placed = placements[event.id]?.coordinate;
      rows.add((
        id: event.id,
        title: title.isEmpty ? '(untitled)' : title,
        coordinate: placed == null ? null : Coordinate.fromJson(placed),
        frame: placements[event.id]?.frame,
        completed: done.contains(event.id),
        completedAt: instants[event.id]?.$2,
      ));
    }
    return rows..sort(
      (left, right) => left.title.compareTo(right.title) == 0
          ? left.id.compareTo(right.id)
          : left.title.compareTo(right.title),
    );
  }
}
