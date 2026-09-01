// Validation. Refuse before store: a record whose claim cannot be honoured is
// not a valid record, and reporting it as one defers a certain failure to
// whichever render first asks.
//
// WHAT IS NOT HERE, and why.
//
// Shape checks are gone: "must be an object", "requires traits", "must be an
// object map" are all unrepresentable in records.dart's types, so the ~90 lines
// that checked them have no counterpart rather than a port.
//
// ~30 hand-written variations of "references a missing X" are gone too, melted
// into one table -- [_refs] -- read by one loop. A new reference is a row.
//
// THREE NEGATION REFUSALS DIE. `query.excludeGroups`/`notGroups` on a frame and
// `include: false`/`mode: "exclude"` on a membership used to be errors.
// Projection is boolean algebra and a filter is authored as NOT, so negation is
// the mechanism, not a fault. Nothing below refuses it.
//
// THE STAPLE KIND GATE DIES. A staple is two ends in order; direction is the
// order. There is no registry of which scopes a kind may join, because that
// typing is exactly what the directional-not-typed ruling replaced.
//
// THE FOUR TIME-TRAVEL TAXONOMY VALIDATORS DIE AS WRITTEN. `shared-segment`,
// `termination`, `displacement` and `coordinate-mapping` records stay perfectly
// legal data -- they parse, they round-trip, they are never refused -- they are
// simply not checked against a hardcoded shape. Time travel is re-founded on the
// one math, and hardcoding four shapes would preclude the rest.
//
// A refusal is a MESSAGE. Nothing here throws on data.

import 'document.dart';
import 'event_cycle.dart';
import 'records.dart';
import 'staples.dart' show isPlacement;

/// One reference: which pointer it is, which record maps a legal target may
/// live in, and the ids the record claims. Yielding a list means a field, a pair
/// of fields, and a whole collection are all one row.
typedef _Ref = (String, List<String>, Iterable<String?> Function(Object));

/// Reference integrity, once. The JavaScript hand-wrote ~30 variations of
/// "references a missing X"; this is the table they collapse to, read by one
/// loop, and a new reference is one row. Keyed by record map, or by
/// `relations:<type>`. An UNKNOWN relation type simply has no row -- which is
/// exactly what makes it legal data rather than a refusal.
final Map<String, List<_Ref>> _refs = {
  'frames': [
    ('basis', _frames, (r) => [(r as Frame).basis]),
    ('coordinate definition', _frames, (r) => [(r as Frame).coordinateDefinition]),
    ('law pattern', _patterns, (r) => [_lawPattern(r as Frame)]),
    ('boundary frame', _frames, (r) => [_boundaryFrame(r as Frame)]),
    ('boundary event', _events, (r) => _boundaryEvents(r as Frame)),
  ],
  'events': [('magnitude frame', _frames, (r) => (r as Event).magnitudes.values.map(_mf))],
  'patterns': [
    ('template event', _events, (r) => [_ics(r, (p) => p.templateEvent)]),
  ],
  'overrides': [
    ('virtual pattern', _patterns, (r) => [overridePatternId(r as Override)]),
    ('replacement event', _events, (r) => (r as Override).replacements),
  ],
  // NO ROW FOR A CONNECTION (ruled 2026-09-01). The four record kinds each had
  // rows naming their own fields; a connection is a staple now and names what it
  // names at its ENDS, which `_staple` already checks one end at a time and by
  // position -- so a row here would report the same fault a second time. A
  // record still spelled `attachment`, `membership` or `contains` matches
  // nothing at all, which is exactly what an unknown type has always done and
  // exactly what "nothing reads them" has to mean here too.
};

const List<String> _frames = ['frames'];
const List<String> _events = ['events'];
const List<String> _patterns = ['patterns'];

String? _mf(Magnitude magnitude) => magnitude.frame;

/// A frame's `period` block, only when it is the event-defined kind. Every other
/// period shape makes no reference claim of this sort and so has no row.
Json? _eventDefinedPeriod(Frame frame) {
  final period = obj(frame.extra['period']);
  return period?['kind'] == 'event-defined' ? period : null;
}

/// A BLANK frame names nothing, so it makes no reference claim: the invariant
/// below reports "needs a boundary frame" and this row stays silent, rather than
/// both of them reporting the one fault.
String? _boundaryFrame(Frame frame) {
  final named = str(_eventDefinedPeriod(frame)?['frame']) ?? '';
  return named.trim().isEmpty ? null : named;
}

/// A boundary MAY name the observed event that established its coordinate; one
/// that does not makes no claim, and one that does must be able to keep it.
Iterable<String?> _boundaryEvents(Frame frame) {
  final rows = _eventDefinedPeriod(frame)?['boundaries'];
  return rows is! List ? const [] : [for (final row in rows) str(obj(row)?['event'])];
}

String? _lawPattern(Frame frame) => str(obj(frame.extra['law'])?['pattern']);
String? _ics(Object record, String? Function(Pattern) field) =>
    (record as Pattern).kind == 'ics-rrule' ? field(record) : null;

const Map<String, String> _relationLabels = {};

String _label(Object record) => switch (record) {
  Frame() => 'Frame',
  Event() => 'Event',
  Pattern() => 'Pattern',
  Override() => 'Override',
  Relation(:final type) when type.isEmpty => 'Relation',
  Relation(:final type) => _relationLabels[type] ?? type[0].toUpperCase() + type.substring(1),
  _ => 'Record',
};

String _scope(StapleEnd end) => switch (end) {
  FrameEnd() => 'frame',
  ObjectEnd() => 'object',
  SeriesEnd() => 'series',
};

/// Every refusal this document earns, as messages. `valid` is the absence of
/// any, which is what a load gate reads.
({bool valid, List<String> errors}) validateDocument(Document document) {
  final errors = <String>[];
  if (document.schema != schemaVersion) {
    final named = document.schema.isEmpty ? '(missing)' : document.schema;
    errors.add('Unsupported schema: $named');
  }
  for (final map in const ['frames', 'events', 'patterns', 'relations', 'overrides']) {
    for (final entry in document.records(map).entries) {
      final record = entry.value!;
      final name = _label(record);
      if ((record as DocumentRecord).id != entry.key) {
        errors.add('$name map key ${entry.key} does not match its id');
      }
      final rows = _refs[record is Relation ? 'relations:${record.type}' : map] ?? const <_Ref>[];
      for (final (label, maps, ids) in rows) {
        for (final id in ids(record)) {
          final found = id == null || maps.any((map) => document.records(map).containsKey(id));
          if (found) continue;
          errors.add('$name ${entry.key} references a missing $label');
        }
      }
      _invariants(document, record, entry.key, errors);
    }
  }
  return (valid: errors.isEmpty, errors: errors);
}

void _invariants(Document document, Object record, String id, List<String> errors) {
  switch (record) {
    case Event():
      // Every object carries an intrinsic duration; a zero one is a fact, its
      // absence is a record that cannot answer how long it lasts.
      if (record.duration == null) {
        errors.add('Event $id requires an intrinsic duration');
      }
      final instant = record.traits.contains('task') || record.traits.contains('terminator');
      if (instant && !isZeroDuration(record)) {
        errors.add('Event $id must have zero duration for its task/terminator trait');
      }
    case Frame():
      if (record.coordinateDefinition == id) {
        errors.add('Frame $id cannot define coordinates through itself');
      }
      // An event-defined period is checked by THE SAME parser the resolver
      // reads, so "is this boundary series well formed" has one implementation:
      // at least two boundaries, unique ids, strictly increasing exact
      // coordinates. Refuse before store -- a document whose boundaries only
      // fail at query time is not a valid document.
      final period = _eventDefinedPeriod(record);
      if (period != null) {
        final refusal = eventBoundarySeries(period).refusal;
        if (refusal != null) {
          errors.add('Frame $id event-defined period: $refusal');
        }
      }
    case Pattern():
      if ((record.language ?? '').isEmpty) {
        errors.add('Pattern $id lacks a language');
      }
    case Relation():
      _relation(document, record, id, errors);
  }
}

/// ONE SHAPE, ONE SWITCH POINT (ruled 2026-09-01). A record spelled with one of
/// the four retired kinds matches nothing here -- exactly as an unknown type
/// always has -- so it loads, validates clean and saves back byte for byte,
/// while nothing reads it. The invariants those kinds carried are stated of the
/// SENTENCE now, inside the staple check, because that is where the sentence is.
void _relation(Document document, Relation relation, String id, List<String> errors) {
  if (relation.isStaple) _staple(document, relation, id, errors);
}

/// The claims a connection cannot survive, whatever spelling reached it.
void _connection(Document document, Relation relation, String id, List<String> errors) {
  // Completion is a state-frame affiliation plus an optional end staple, so a
  // task on a calendar records what happened, never what is planned.
  final event = document.events[relation.event];
  final frame = document.frames[relation.frame];
  if (isPlacement(relation) &&
      event != null &&
      frame != null &&
      event.traits.contains('task') &&
      frame.traits.contains('calendar') &&
      relation.role != 'observed') {
    errors.add('Task placement $id must be retrospective');
  }
  // Containment passes no judgment: multi-parent and any depth are legal, and a
  // cycle is reported by the derivations that walk it, not refused here. The one
  // claim it cannot survive -- a thing holding itself -- needs no check of its
  // own now that containment IS a staple: "connects one object to itself" below
  // is the general form of exactly that fault, and stating it twice would report
  // one defect as two.
}

void _staple(Document document, Relation staple, String id, List<String> errors) {
  _connection(document, staple, id, errors);
  // N POINTS ARE ONE POINT, n >= 0. Zero ends is a staple that pierces pages
  // without identifying any of their points, one is a pin that gives a point
  // identity for other math to reference, and three is the sticky note stapled
  // to two calendars at once. So the COUNT is never an error. What is not data
  // is an `ends` field that is not a list of ends at all, or an end the document
  // cannot read -- both of which silently shrink what the author wrote.
  final ends = staple.ends;
  final declared = staple.extra['ends'];
  if (declared != null && declared is! List) {
    errors.add('Staple $id must carry its ends as a list');
  } else if (declared is List && declared.length != ends.length) {
    errors.add('Staple $id has an end that names nothing this document can reach');
  }
  for (final (index, end) in ends.indexed) {
    final label = 'Staple $id end ${index + 1}';
    if (!document.records(end.map).containsKey(end.id)) {
      errors.add('$label references a missing ${_scope(end)}');
    }
    if (end is ObjectEnd && (end.point?.trim().isEmpty ?? false)) {
      errors.add('$label point must be a non-empty name');
    }
  }
  // A TOP-LEVEL ROLE IS THE PLACEMENT'S OWN WORD (ruled 2026-09-01). It used to
  // be refused here, because `role` on a staple could only have been a touch
  // point written in the wrong place -- the touch point is an END's `point`, and
  // it still is. But a placement is a staple now, and `role` is what it has
  // always carried beside its coordinate (placed, observed, template), so the
  // refusal was refusing the one shape there is.

  // A frame may be stapled to ITSELF at two different positions: that is a
  // nonlinear line crossing its own path, which correspondence exists to carry.
  // Two ends at the same position say nothing, and an object or series stapled
  // to itself says nothing either -- an object's own start-to-end span is its
  // duration magnitude, not a connection.
  if (ends.length > 1 && ends.every((end) => end.id == ends.first.id)) {
    final first = ends.first;
    if (first is FrameEnd) {
      if (ends.every((end) => end is FrameEnd && end.position == first.position)) {
        errors.add('Staple $id connects one point to itself');
      }
    } else {
      errors.add('Staple $id connects one ${_scope(first)} to itself');
    }
  }
  if (ends.whereType<SeriesEnd>().length > 1) {
    errors.add('Staple $id connects two series, which is not defined');
  }
}
