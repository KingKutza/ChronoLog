// The one reference graph an edit reads.
//
// Five hand-written bundle capture/restore pairs answered this question in the
// JavaScript, each with its own filters over the same relation map. There is one
// question and it is asked in one direction: WHICH RECORDS NAME THIS ID. Undo
// needs no bundle at all, because an immutable document's identity diff already
// reports exactly what an edit touched.

import '../core/document.dart';
import '../core/records.dart';

/// One record, addressed the way an op addresses it.
typedef RecordRef = (String map, String id);

/// The maps whose records are pure pointer: a relation, an override and a
/// pattern say nothing at all once what they name is gone. Events and frames are
/// CONTENT and are never removed by a cascade -- deleting a magnitude frame must
/// not delete the objects measured in it.
const List<String> connectiveMaps = ['relations', 'overrides', 'patterns'];

/// Every id this record names, whatever field or end spells it. The declared
/// graph, and the only place it is declared for edits.
Iterable<String> namedBy(Object? record) => switch (record) {
  Frame() => [
    ?record.basis,
    ?record.coordinateDefinition,
    ?str(obj(record.extra['law'])?['pattern']),
    ...?_period(record),
  ],
  Event() => [for (final magnitude in record.magnitudes.values) ?magnitude.frame],
  Pattern() => [?record.templateEvent, ?record.templateRelation],
  Override() => [overridePatternId(record), ...record.replacements],
  Relation() => [
    ?record.event,
    ?record.frame,
    ?record.parent,
    ?record.child,
    ?record.member,
    ?record.group,
    for (final end in record.ends) end.id,
  ],
  _ => const <String>[],
};

/// A frame's event-defined period names another frame and the observed events
/// that established its boundaries.
Iterable<String>? _period(Frame frame) {
  final period = obj(frame.extra['period']);
  if (period?['kind'] != 'event-defined') return null;
  final rows = period!['boundaries'];
  return [
    ?str(period['frame']),
    if (rows is List)
      for (final row in rows) ?str(obj(row)?['event']),
  ];
}

/// Every connective record that cannot survive the loss of [doomed], to a fixed
/// point: a frame's deletion takes the attachment that placed a series template,
/// which takes the pattern, which takes that pattern's overrides.
Set<RecordRef> unsupported(Document document, Set<String> doomed) {
  final gone = {...doomed};
  final removed = <RecordRef>{};
  for (var reached = true; reached;) {
    reached = false;
    for (final map in connectiveMaps) {
      for (final entry in document.records(map).entries) {
        if (gone.contains(entry.key)) continue;
        if (!namedBy(entry.value).any(gone.contains)) continue;
        gone.add(entry.key);
        removed.add((map, entry.key));
        reached = true;
      }
    }
  }
  return removed;
}

/// Content records still naming something doomed. A cascade may not delete
/// authored content to tidy a reference away, and it may not leave the pointer
/// dangling either, so the edit is refused in the reference's own words.
List<String> dangling(Document document, Set<String> doomed) => [
  for (final map in ['frames', 'events'])
    for (final entry in document.records(map).entries)
      for (final id in namedBy(entry.value))
        if (doomed.contains(id)) '${entry.key} still names $id, which this edit removes',
];
