// Settling: what an edit produced, plus everything that could not survive it,
// plus the series convergence invariant -- all one document, so all one undo
// entry and one journal entry.
//
// Owner ruling (8.19): a fork is not the problem, an UNHEALED fork is. So the
// heal runs on every transaction and asks nothing about what the user did; it
// re-reads the state. And it is a PLAN first, so a settling that changes nothing
// pushes no undo entry.

import '../core/document.dart';
import '../core/ops.dart';
import '../core/records.dart';
import '../core/series_heal.dart';
import 'reach.dart';

/// What settling came to. [refusals] non-empty means the edit was NOT applied:
/// [document] is the untouched original and the words are the reference's own.
typedef Settlement = ({Document document, List<String> refusals, int healed});

/// The ids one edit put, deleted, or removed outright, per record map.
typedef Touched = ({Map<String, Set<String>> changed, Set<String> removed});

Touched touchedBy(Document before, Document after) {
  final changed = <String, Set<String>>{};
  final removed = <String>{};
  for (final op in opsFromMaps(mapSnapshot(before), mapSnapshot(after))) {
    (changed[op.map] ??= {}).add(op.id);
    if (op.op == 'del') removed.add(op.id);
  }
  return (changed: changed, removed: removed);
}

/// Which overrides this edit could have converged.
///
/// The diff alone is not enough and the JavaScript knew it: the inspector edits
/// a series by editing its TEMPLATE EVENT, and the occurrences such an edit
/// retires are reachable only through the pattern. So a changed event or
/// relation widens the scope to every pattern it is the template of.
HealScope healScope(Document document, Touched touched, HealScope? also) {
  final events = {...?touched.changed['events'], ...?also?.eventIds};
  final relations = touched.changed['relations'] ?? const <String>{};
  return HealScope(
    eventIds: events,
    patternIds: {
      ...?touched.changed['patterns'],
      ...?also?.patternIds,
      for (final pattern in document.patterns.values)
        // DERIVED, and only derived (ruled 2026-09-01): an edit to a connection
        // that places the template event moves the series, and the pattern
        // record is not consulted about which connection that is.
        if (events.contains(pattern.templateEvent) ||
            relations.any((id) => document.relations[id]?.event == pattern.templateEvent))
          pattern.id,
    },
  );
}

/// The one settling step. [projector] is asked for an engine over the CASCADED
/// document, and only once the cheap candidate scan has found something to heal
/// -- an ordinary edit to an ordinary object never pays for a rebuild.
Settlement settle(
  Document before,
  Document after, {
  required UnsuppressedProjector Function(Document) projector,
  HealScope? converge,
}) {
  final touched = touchedBy(before, after);
  var next = after;
  for (final (map, id) in unsupported(next, touched.removed)) {
    next = next.remove(map, id);
  }
  final refusals = dangling(next, touched.removed);
  if (refusals.isNotEmpty) return (document: before, refusals: refusals, healed: 0);
  final scope = healScope(next, touched, converge);
  // A projector that answers nothing is enough for the candidate pre-filter: it
  // reads overrides only, and reusing the core derivation is what keeps this
  // scan and the real check from disagreeing about what a candidate is.
  // An override this very edit AUTHORED has not converged back onto anything --
  // it has just been written, which is what "edit this occurrence" is. The heal
  // asks its question of overrides that already stood, so a materialization
  // survives the transaction that made it and is asked again on the next one and
  // on the card's close, where an unchanged occurrence retires.
  final candidates = [
    for (final id in SeriesHeal(next, project: (_) => null).healCandidateIds(scope))
      if (before.overrides.containsKey(id)) id,
  ];
  if (candidates.isEmpty) return (document: next, refusals: const [], healed: 0);
  final plan = SeriesHeal(
    next,
    project: projector(next),
  ).planSeriesHeal(HealScope(overrideIds: candidates.toSet()));
  return (document: applySeriesHeal(next, plan), refusals: const [], healed: plan.healed);
}

// --- Duplicating a frame ----------------------------------------------------

Object? _remap(Object? node, String from, String to) => switch (node) {
  String value => value == from ? to : value,
  Map<String, dynamic> map => {
    for (final entry in map.entries) entry.key: _remap(entry.value, from, to),
  },
  List<dynamic> list => [for (final item in list) _remap(item, from, to)],
  _ => node,
};

bool _mentions(Object? node, String id) => switch (node) {
  String value => value == id,
  Map<String, dynamic> map => map.values.any((value) => _mentions(value, id)),
  List<dynamic> list => list.any((value) => _mentions(value, id)),
  _ => false,
};

const Map<String, DocumentRecord Function(Json)> _clonable = {
  'relations': Relation.fromJson,
  'patterns': Pattern.fromJson,
};

/// A deep copy. Every reference to the original -- a placement's `frame`, a
/// staple END, a pattern's scope -- names the copy instead, which is the part
/// three field checks could never see.
Document duplicateFrame(Document document, String id) {
  final source = document.frames[id];
  if (source == null) return document;
  final copy = createId('frame');
  Json remap(Json json, String named) => Json.from(_remap(json, id, copy)! as Map)..['id'] = named;
  var next = document.put(
    'frames',
    copy,
    Frame.fromJson(remap(source.toJson(), copy)).copyWith(title: '${source.title ?? id} (copy)'),
  );
  for (final entry in _clonable.entries) {
    for (final record in document.records(entry.key).values) {
      final json = Json.from(jsonValue(record)! as Map);
      if (!_mentions(json, id)) continue;
      final made = createId(entry.key);
      next = next.put(entry.key, made, entry.value(remap(json, made)));
    }
  }
  return next;
}
