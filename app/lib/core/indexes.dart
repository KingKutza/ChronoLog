// Pure Dart. Nothing under lib/core/ may import Flutter or a third-party
// package.
//
// ONE PASS. The JavaScript walked `document.relations` in FOUR separate loops
// and built a dozen maps beside them; every one of those maps answers a question
// about the same records, so they are built together here, once. Overscale
// doctrine is the reason the indexes exist at all -- `resolveObjectExtent` runs
// once per object inside fact indexing and recurses through connection chains, so
// "every staple touching this id" has to be O(1) -- and it is also the reason one
// pass matters: a document-wide scan per index, per reindex, per edit is the
// difference between usable and unusable at 500 calendars.
//
// MEMOIZED ENDS. `Relation.ends` re-parses its JSON on every access, so the
// substrate would pay for the parse once per lookup on every derivation that
// reads a connection. [Indexes.endsOf] is the one parse, and every index below
// and every consumer above reads through it.
//
// ONE MEMBERSHIP POOL (R5, ruling: frames are groups). The JavaScript maintained
// two parallel membership indexes -- six maps and eight accessors -- so that
// "group" could mean one thing to the document and another to display. Under the
// ruling that duality is bookkeeping with nothing left to keep: there is one
// pool, no trait gate decides who may have members, and handling is a group
// property a projection interprets. `isOrdinaryGroup`/`isDisplayGroup` have no
// counterpart here.
//
// THE FOUR ROUTES stay distinct because the ruling names them distinctly:
// PLACEMENT is an attachment relation, MEMBERSHIP is a membership relation
// (closed transitively, here), and the two STAPLE routes are read off the staple
// index. Attachment is therefore NOT folded into the membership pool -- it is its
// own route, and folding it in would make every event a member of every calendar
// it sits on and cost a second traversal to undo.

import 'records.dart';
import 'staples.dart';

/// Why a member is in a group.
///
/// RETAINED, never collapsed to a boolean: an inspector has to be able to say
/// "because you wrote this relation" or "because it is inside that group, via
/// this one", and a membership that cannot explain itself is a membership nobody
/// can correct. `kind` is `authored` (a membership relation), `query` (a
/// selector leaf), or `nested` (inherited through `via`).
typedef Provenance = ({String kind, String? relation, String? group, String? via});

List<String> _names(Object? value) => [
  for (final item in value is List ? value : const [])
    if (item is String) item,
];

/// Every index the projection engine reads, built whole from one document.
///
/// Rebuilt rather than patched. The engine is TOLD what changed (see
/// `ProjectionEngine.applyChange`), and what that precision buys is the
/// RECURRENCE caches and the resolved laws -- the expensive derivations. This
/// pass is one walk over the relation map, so rebuilding it is cheaper than
/// proving a patch correct, and a patch that is subtly wrong is a document that
/// quietly disagrees with itself.
class Indexes {
  Indexes(this.document) {
    for (final relation in document.relations.values) {
      switch (relation.type) {
        case 'attachment':
          _attachment(relation);
        case 'staple':
          for (final end in endsOf(relation)) {
            (_staples[end.id] ??= []).add(relation);
          }
        case 'contains':
          if (relation.parent case final String parent) {
            if (relation.child case final String child) {
              (_children[parent] ??= <String>{}).add(child);
              (_parents[child] ??= <String>{}).add(parent);
            }
          }
        case 'membership':
          // An authored edge that says it is not a membership is not a refusal
          // and not a second exclusion mechanism (R2) -- it is simply not an
          // edge. Filtering is authored as NOT in the projection now.
          if (relation.extra['include'] == false || relation.extra['mode'] == 'exclude') break;
          if (relation.group case final String group) {
            if (relation.member case final String member) {
              _edge(group, member, (
                kind: 'authored',
                relation: relation.id,
                group: group,
                via: null,
              ));
            }
          }
      }
    }
    for (final pattern in document.patterns.values) {
      if (pattern.extra['enabled'] == false) continue;
      final applies = _names(pattern.extra['appliesTo']);
      if (applies.isEmpty) {
        _everywhere.add(pattern);
        continue;
      }
      for (final frameId in applies) {
        (_patterns[frameId] ??= []).add(pattern);
      }
    }
    _selectors();
    // The same total, deterministic order the staple substrate tie-breaks on,
    // applied once here rather than per lookup. It is by relation id and is NOT
    // authoring order: what a tie-break needs is an order identical across
    // reload, journal replay and every window looking at one document.
    for (final bucket in _staples.values) {
      bucket.sort((left, right) => left.id.compareTo(right.id));
    }
  }

  final Document document;

  final Map<String, List<StapleEnd>> _ends = {};
  final Map<String, Relation?> _placement = {};
  final Map<String, List<Relation>> _attachments = {}, _staples = {};
  final Map<String, Set<String>> _framesOf = {}, _children = {}, _parents = {};
  final Map<String, String> _calendarOf = {};
  final Map<String, Map<String, List<Provenance>>> _direct = {};
  final Map<String, Set<String>> _directGroups = {};
  final List<Pattern> _everywhere = [];
  final Map<String, List<Pattern>> _patterns = {};
  final Map<String, Set<String>> _closures = {}, _objects = {};

  /// A group that (transitively) contains itself, reported ONCE. Broken here
  /// rather than unioned forever, and never thrown: the loop is authored data
  /// and the author is the only one who can resolve it.
  final Map<String, String> cycles = {};

  /// This staple's two ends, parsed exactly once per document generation.
  List<StapleEnd> endsOf(Relation relation) => _ends[relation.id] ??= relation.ends;

  void _attachment(Relation relation) {
    final event = relation.event;
    if (event == null) return;
    // "Seen, and it has none" is recorded distinctly from "not seen": an object
    // placed purely by a connection has a coordinate-less attachment, and
    // reading that miss as "unplaced" makes it look like it sits nowhere. The
    // first coordinate-carrying attachment wins and is not overwritten.
    if (isPlacement(relation)) {
      _placement[event] ??= relation;
    } else {
      _placement.putIfAbsent(event, () => null);
    }
    final frame = relation.frame;
    if (frame == null) return;
    (_attachments[frame] ??= []).add(relation);
    (_framesOf[event] ??= <String>{}).add(frame);
    if (document.frames[frame]?.traits.contains('calendar') ?? false) {
      _calendarOf.putIfAbsent(event, () => frame);
    }
  }

  void _edge(String group, String member, Provenance because) {
    final inGroup = _direct[group] ??= {};
    (inGroup[member] ??= []).add(because);
    (_directGroups[member] ??= <String>{}).add(group);
  }

  /// THE QUERY SELECTOR AS LEAF PREDICATES (R6). The JavaScript's `ids` /
  /// `traitsAll` / `traitsAny` / `groups` matcher was a second, parallel,
  /// non-composable membership mechanism beside the authored edges. It is a LEAF
  /// now: the test runs here, once per generation, and lands in the same one pool
  /// authored edges land in, so the algebra above has exactly one substrate to
  /// read. The three negation refusals die with it -- `excludeGroups` and
  /// `notGroups` are inert data, because NOT is authored in the expression.
  ///
  /// DEVIATION, with the reason: a selector naming no ids and no traits selects
  /// NOTHING here. The JavaScript's loop had no guard and so matched every event
  /// and every frame in the document, which made `query: {groups: [...]}` -- a
  /// statement purely about nesting -- silently claim every record as a member.
  /// That is a defect, not a ruling: an empty test is not a claim about
  /// everything.
  void _selectors() {
    for (final frame in document.frames.values) {
      final query = obj(frame.extra['query']);
      if (query == null) continue;
      final because = (kind: 'query', relation: null, group: frame.id, via: null);
      for (final nested in _names(query['groups'])) {
        _edge(frame.id, nested, because);
      }
      final wanted = query['ids'] is List ? _names(query['ids']).toSet() : null;
      final all = _names(query['traitsAll']), any = _names(query['traitsAny']);
      if (wanted == null && all.isEmpty && any.isEmpty) continue;
      for (final (id, traits) in [
        for (final event in document.events.values) (event.id, event.traits),
        for (final other in document.frames.values) (other.id, other.traits),
      ]) {
        if (wanted != null && !wanted.contains(id)) continue;
        if (all.any((trait) => !traits.contains(trait))) continue;
        if (any.isNotEmpty && !any.any(traits.contains)) continue;
        _edge(frame.id, id, because);
      }
    }
  }

  /// The transitive membership pool: the LEAST FIXED POINT of positive nesting.
  ///
  /// Positive nesting is monotonic over a finite graph, so repeatedly adding
  /// inherited members terminates at the least fixed point, and a self-edge
  /// becomes a no-op rather than a hang. Provenance travels: an inherited member
  /// records the group it came through, so the chain is explainable.
  late final Map<String, Map<String, List<Provenance>>> members = _close();

  Map<String, Map<String, List<Provenance>>> _close() {
    final closed = {
      for (final entry in _direct.entries)
        entry.key: {
          for (final row in entry.value.entries) row.key: [...row.value],
        },
    };
    var changed = true;
    while (changed) {
      changed = false;
      for (final group in closed.keys.toList()) {
        final inGroup = closed[group]!;
        for (final member in inGroup.keys.toList()) {
          for (final inherited in closed[member]?.keys ?? const <String>[]) {
            if (inGroup.containsKey(inherited)) continue;
            inGroup[inherited] = [(kind: 'nested', relation: null, group: group, via: member)];
            changed = true;
          }
        }
      }
    }
    for (final group in closed.keys) {
      if (closed[group]!.containsKey(group)) {
        cycles[group] =
            'Group $group contains itself; the cycle was broken here rather'
            ' than unioned forever.';
      }
    }
    return closed;
  }

  // --- What the engine asks -------------------------------------------------

  /// The object's placement relation, or null.
  ///
  /// A MISS IS THE ANSWER here, and provably so: this pass sees every attachment
  /// relation in the document, so an id it never saw has no attachment at all --
  /// which is exactly "no placement". The substrate's index-or-scan dual path
  /// therefore collapses to one arm with nothing lost.
  Relation? placementOf(String objectId) => _placement[objectId];

  List<Relation> staplesOf(String id) => _staples[id] ?? const [];

  List<Relation> attachmentsOf(String frameId) => _attachments[frameId] ?? const [];

  List<String> framesOf(String eventId) => [...?_framesOf[eventId]];

  String? calendarFrameOf(String eventId) => _calendarOf[eventId];

  List<String> childrenOf(String id) => [...?_children[id]]..sort();

  List<String> parentsOf(String id) => [...?_parents[id]]..sort();

  /// One authored hop upward: the groups this id is a direct member of. Distance
  /// in the connection graph is counted in hops, so the closure above cannot
  /// answer this -- it has already flattened them.
  List<String> directGroupsOf(String id) => [...?_directGroups[id]]..sort();

  /// Every pattern that projects onto this frame. A pattern naming no
  /// `appliesTo` applies everywhere, which is what an imported series does.
  List<Pattern> patternsFor(String frameId) => [..._everywhere, ...?_patterns[frameId]];

  /// The frames whose OWN placements populate this one: itself, plus every frame
  /// transitively inside it. This is the substrate the OR case of the algebra
  /// reads, and the reason a group needs no arithmetic of its own -- each member
  /// resolved under its own law, unioned, never re-resolved under the group's.
  Set<String> frameClosure(String frameId) => _closures[frameId] ??= {
    frameId,
    for (final id in members[frameId]?.keys ?? const <String>[])
      if (document.frames.containsKey(id)) id,
  };

  /// The objects transitively inside this frame by MEMBERSHIP. Their placements
  /// live on whatever frames they are attached to; membership is a connection
  /// route in its own right, so they populate this frame from wherever they sit.
  Set<String> memberObjects(String frameId) => _objects[frameId] ??= {
    for (final id in members[frameId]?.keys ?? const <String>[])
      if (document.events.containsKey(id)) id,
  };
}
