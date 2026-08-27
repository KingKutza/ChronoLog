// The convergence invariant for series occurrences.
//
// Owner ruling (8.19): "the issue is not that a fork occurred, the issue is that
// it was not healed. If I no-op, if I edit then move back, if I delete then
// create a new instance in the same place -- it does not matter. Any time we
// have a pattern we save the pattern and project. Any time we have a deviation
// from the pattern, we override the instance with an event. Any time that
// overriding event matches the pattern, the event is removed and the projection
// reasserts. The series of events leading up to the heal are irrelevant."
//
// So this module is deliberately NOT flow control. It knows nothing about
// editors, dialogs, toggles, or what the user did on the way here. It answers
// one question about a STATE: does this materialized occurrence still say
// exactly what its series already says? If it does, the override and its
// materialized event are removed and the projection reasserts on its own.
//
// History-free by construction. A no-op close, an edit reverted by hand, and a
// delete-then-recreate-in-the-same-place are indistinguishable here, because
// only the resulting document is ever examined. That is the whole point:
// prevention (not materializing until an edit lands) is an optional
// optimization, healing is the law.
//
// Conservative on purpose, and ASYMMETRICALLY so. A false heal destroys authored
// data; a missed heal only leaves an extra record that will heal on the next
// touch. So anything the pattern does not project counts as deviation, and
// anything this module cannot positively confirm is treated as deviation.
//
// One trap worth naming, because it decides how comparison works. The owner
// requires "edit then move back" to heal. A hand-reverted value is NUMERICALLY
// equal but not necessarily textually equal -- a re-parsed coordinate can gain
// an explicit `minute: 0`, and a duration can come back as "60.0" where the
// projection says "60". Comparing serialized text would silently miss exactly
// the case he named, so every temporal quantity here is compared through exact
// arithmetic ([Rational], and the coordinate law's own resolution), never as a
// string. The record types' own structural equality carries the rest of the
// canonicalization the JavaScript had to perform by hand.

import 'dart:convert';

import 'coordinate_law.dart';
import 'document.dart';
import 'eras.dart';
import 'exact.dart';
import 'ops.dart';
import 'records.dart';
import 'staples.dart';

/// A window wide enough to contain the projected slot while the materialized
/// event still sits on it. It does not need to be generous: if the event has
/// been moved off its slot that IS a deviation, so failing to find the
/// projection inside a tight window is the correct answer rather than a limit.
final Rational healSlackDays = Rational.one;

/// A placeholder standing in for "this occurrence's own id". Materialized and
/// projected records necessarily carry different ids, so identity is normalized
/// away before comparison while every other field is compared.
const String _self = ' self';

/// One projected occurrence, as the patterns alone describe it: the virtual id
/// it answers to, the event the generator would mint, and the relation that
/// would place it. The minimum this module reads -- a projector may carry more.
typedef ProjectedFact = ({String virtualId, Event event, Relation relation});

/// The window a projection is asked for, in exact days on one frame's axis.
typedef ProjectionWindow = ({String frame, Rational start, Rational end, String virtualId});

/// THE INJECTED PROJECTOR SEAM.
///
/// The override suppresses this very slot, so what is wanted is the UNSUPPRESSED
/// projection: the fact the patterns would place at [ProjectionWindow.virtualId]
/// inside the window, with the overrides map ignored. Null when the series
/// projects nothing there.
///
/// Injected rather than implemented, so THE SAME GENERATOR THAT REASSERTS IS THE
/// ONE THAT HEALS and the two cannot drift. The projection engine wires this at
/// integration: it is `queryFacts` over the window with overrides not applied,
/// picking the fact whose virtual id matches.
typedef UnsuppressedProjector = ProjectedFact? Function(ProjectionWindow window);

/// Which overrides a heal pass even looks at.
///
/// The scopes UNION rather than taking priority over one another. That matters
/// for the real editing path: the inspector edits a series by editing its
/// template EVENT, so that transaction is scoped by event id, yet the
/// occurrences it can converge are reached only through the pattern. Treating
/// the scopes as alternatives silently lost exactly the case the owner
/// described -- moving a series onto the values one of its exceptions already
/// had, which must retire that exception.
class HealScope {
  const HealScope({this.overrideIds, this.eventIds, this.patternIds});

  /// The whole document.
  static const HealScope everything = HealScope();

  /// Named outright, which outranks the other two: a caller that knows the
  /// override is not asking to be widened.
  final Set<String>? overrideIds;
  final Set<String>? eventIds, patternIds;
}

/// Whether one override has converged back onto its series, and WHY NOT when it
/// has not -- a decision rather than a bare boolean, so a missed heal is
/// diagnosable instead of mysterious.
class HealDecision {
  const HealDecision({
    required this.healable,
    required this.reason,
    required this.override,
    this.eventIds = const [],
    this.relationIds = const [],
  });

  final bool healable;
  final String reason;
  final Override override;

  /// What retiring this override removes with it. Empty on a refusal.
  final List<String> eventIds, relationIds;
}

/// Every override in scope that has converged, with the ops to retire them and
/// the inverse ops that put them back.
typedef HealPlan = ({
  List<HealDecision> heals,
  List<Op> ops,
  List<Op> inverseOps,
  List<({String override, String reason})> refusals,
  int healed,
});

/// Magnitudes are exact quantities, so they are compared NUMERICALLY: "60" and
/// "60.0" and "060" are the same duration and must not read as a deviation. An
/// unparseable value keeps its own text, which can only make the comparison
/// stricter -- the safe direction.
String _exactText(Object? value) {
  try {
    return Rational.parse('$value').toJson();
  } catch (_) {
    return 'raw:$value';
  }
}

/// "generated" is stripped by materialization, so it is not a difference between
/// a projected occurrence and its materialized twin.
List<String> normalizeTraits(Iterable<String> traits) =>
    ({...traits}..remove('generated')).toList()..sort();

Magnitude _normalizeMagnitude(Magnitude magnitude) {
  final levels = magnitude.value?['levels'];
  if (levels is! List) return magnitude;
  return magnitude.copyWith(
    value: {
      ...magnitude.value!,
      'levels': [
        for (final level in levels)
          if (level is Map) {'level': level['level'], 'value': _exactText(level['value'])},
      ],
    },
  );
}

/// An event reduced to its CONTENT: identity and bookkeeping normalized away,
/// traits deduped and sorted, every magnitude reduced to the exact quantity it
/// denotes. Two of these being equal is the whole event-content comparison,
/// because the record types compare structurally.
Event eventContent(Event event) => event.copyWith(
  id: '',
  traits: normalizeTraits(event.traits),
  magnitudes: {
    for (final entry in event.magnitudes.entries) entry.key: _normalizeMagnitude(entry.value),
  },
  extra: {...event.extra}..remove('provenance'),
);

/// Key-sorted JSON. Relations carry open, arbitrarily nested authored data, so
/// unlike an [Event] they have no value type to compare structurally: this is
/// the total order that lets two SETS of them be compared.
String _canonicalText(Object? value) => jsonEncode(_canonical(value));

Object? _canonical(Object? value) {
  if (value is List) return [for (final item in value) _canonical(item)];
  if (value is Map) {
    final keys = [for (final key in value.keys) '$key']..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  return value;
}

/// A relation reduced to its content, with identity and bookkeeping normalized
/// away and the coordinate reduced to the EXACT INSTANT it denotes rather than
/// the shape it happens to be written in.
///
/// `id` and `provenance` are dropped; any field whose value is the owning
/// event's id becomes [_self], which covers `event` on an attachment and
/// `member` on a membership without special-casing either. An instant that
/// cannot be resolved falls back to the written form, which can only make the
/// comparison stricter.
String relationSignature(Relation relation, String ownerId, Staples staples) {
  final content = <String, Object?>{'type': relation.type};
  for (final entry in relation.extra.entries) {
    if (entry.key == 'provenance' || entry.key == 'coordinate') continue;
    content[entry.key] = entry.value == ownerId ? _self : entry.value;
  }
  final coordinate = relation.coordinate;
  if (coordinate != null) {
    final frame = relation.frame;
    final days = frame == null ? null : staples.daysOf(frame, Coordinate.fromJson(coordinate));
    content['at'] = days?.toJson() ?? 'unresolved:${_canonicalText(coordinate)}';
  }
  return _canonicalText(content);
}

/// Every relation that names this object.
///
/// A staple names its things on its ENDS, so `relation.event` never sees one.
/// Including them here is what makes a connection count as CONTENT of the
/// occurrence it touches, and that is the conservative answer in both
/// directions: a staple authored on this occurrence alone is an occurrence-only
/// addition the pattern does not project, and a staple from another object onto
/// this occurrence's end is that object's placement. Either way the signature
/// comparison sees a difference the projection cannot account for and refuses --
/// a missed heal leaves an extra record, a wrong one destroys authored data and
/// leaves the survivor anchored to nothing.
List<Relation> relationsReferencing(Document document, String eventId) => [
  for (final relation in document.relations.values)
    if (relation.event == eventId ||
        relation.member == eventId ||
        (relation.isStaple && relation.ends.any((end) => end.id == eventId)))
      relation,
];

/// The group attachments materialization copies off the pattern's template:
/// attachment-typed relations on frames carrying the persisted `group` trait.
/// Mirrors what materialization itself filters on, so the two agree about what a
/// materialized occurrence is supposed to contain.
List<Relation> templateGroupAttachments(Document document, String? templateEventId) {
  if (templateEventId == null || templateEventId.isEmpty) return const [];
  return [
    for (final relation in document.relations.values)
      if (relation.type == 'attachment' && relation.event == templateEventId)
        if (document.frames[relation.frame]?.traits.contains('group') ?? false) relation,
  ];
}

/// The invariant, bound to one document and the generator that projects it.
class SeriesHeal {
  SeriesHeal(this.document, {required this.project, Staples? staples})
    : staples = staples ?? Staples(document);

  final Document document;

  /// The ONE placement derivation. Read rather than reimplemented, because an
  /// occurrence whose position is supplied by a connection carries no coordinate
  /// of its own -- and that is how a heal that moves an upstream event's end
  /// propagates through anything stapled to it: the extent is re-derived, never
  /// remembered.
  final Staples staples;

  final UnsuppressedProjector project;

  Extent? _extentOf(String objectId) {
    try {
      return staples.resolveObjectExtent(objectId);
    } catch (_) {
      return null;
    }
  }

  /// The projection for an overridden slot, as the patterns alone describe it.
  ///
  /// The window is anchored on the RESOLVED EXTENT of the materialized event,
  /// never on an attachment's own coordinate: reading the coordinate would find
  /// nothing for a connection-placed occurrence and report every such occurrence
  /// as deviating from a series it actually matches. If the event still sits on
  /// its slot the projection is found; if it has been moved away the projection
  /// is correctly not found, which reads as deviation.
  ProjectedFact? projectedOccurrence(Override override, Event replacement) {
    final patternId = virtualPatternId(override.virtualId);
    if (patternId.isEmpty || !document.patterns.containsKey(patternId)) return null;
    final attachment = firstMatch(
      relationsReferencing(document, replacement.id),
      (relation) => relation.type == 'attachment',
    );
    if (attachment == null) return null;
    final extent = _extentOf(replacement.id);
    final days = extent?.startDays;
    final frame = extent?.frame ?? attachment.frame;
    if (days == null || frame == null) return null;
    return project((
      frame: frame,
      start: days - healSlackDays,
      end: days + healSlackDays,
      virtualId: override.virtualId,
    ));
  }

  /// Does this override's materialized event still match what its series
  /// projects?
  ///
  /// Three gates in order: the SHAPE this module built (a suppressing override
  /// with exactly one replacement -- anything else is a shape it did not build
  /// and must not dismantle), the event's own CONTENT, and the whole RELATION
  /// SET around it, staples and copied template group attachments included.
  HealDecision overrideHealDecision(Override override) {
    HealDecision refuse(String reason) =>
        HealDecision(healable: false, reason: reason, override: override);
    if (override.id.isEmpty) return refuse('not an override record');
    if (!override.suppress) return refuse('override does not suppress its slot');
    final replacements = override.replacements;
    if (replacements.length != 1) {
      return refuse('override has ${replacements.length} replacements, expected 1');
    }
    final replacement = document.events[replacements.first];
    if (replacement == null) return refuse('replacement event is missing');

    final projected = projectedOccurrence(override, replacement);
    if (projected == null) return refuse('the series projects nothing at this slot');

    if (eventContent(replacement) != eventContent(projected.event)) {
      return refuse('event content deviates from the projection');
    }

    final templateEventId = document.patterns[virtualPatternId(override.virtualId)]?.templateEvent;
    final actual = relationsReferencing(document, replacement.id);
    final actualSignature = [
      for (final relation in actual) relationSignature(relation, replacement.id, staples),
    ]..sort();
    final expectedSignature = [
      relationSignature(projected.relation, projected.event.id, staples),
      for (final relation in templateGroupAttachments(document, templateEventId))
        relationSignature(relation, templateEventId!, staples),
    ]..sort();
    if (_canonicalText(actualSignature) != _canonicalText(expectedSignature)) {
      // The arm that catches an occurrence-only addition the pattern does not
      // project -- a state-frame membership written from the roster's done
      // toggle, its end staple carrying the completion instant, a group added to
      // just this instance -- and correctly refuses to heal it away. Removing
      // that addition re-enables the heal purely because the state changed back.
      return refuse('relations deviate from the projection');
    }

    return HealDecision(
      healable: true,
      reason: 'matches the projection',
      override: override,
      eventIds: [replacement.id],
      relationIds: [for (final relation in actual) relation.id],
    );
  }

  List<Override> _candidates(HealScope scope) {
    final overrides = document.overrides.values;
    final wanted = scope.overrideIds;
    if (wanted != null) {
      return [
        for (final override in overrides)
          if (wanted.contains(override.id)) override,
      ];
    }
    final events = scope.eventIds, patterns = scope.patternIds;
    if (events == null && patterns == null) return overrides.toList();
    return [
      for (final override in overrides)
        if ((events != null && override.replacements.any(events.contains)) ||
            (patterns != null && patterns.contains(virtualPatternId(override.virtualId))))
          override,
    ];
  }

  /// Overrides that COULD possibly heal in a scope -- a cheap pre-filter, so a
  /// caller can decide whether the real check (which needs a rebuilt projection)
  /// is worth paying for at all. An ordinary edit to an ordinary event matches
  /// nothing here and therefore costs nothing.
  List<String> healCandidateIds([HealScope scope = HealScope.everything]) => [
    for (final override in _candidates(scope))
      if (override.suppress && override.replacements.length == 1) override.id,
  ];

  /// Every override in scope that has converged back onto its series, with the
  /// ops to retire it.
  ///
  /// Ops are captured against the document AS IT STANDS NOW, so each inverse put
  /// carries the exact record that was removed -- the pre-mutation snapshot,
  /// which is what keeps undo bundle-clean and the journal complete.
  ///
  /// The override is removed FIRST, and its group's inverse puts it back first
  /// in turn, so the slot is never unsuppressed while its materialized twin is
  /// still in the document. The whole inverse list is then reversed, so a plan
  /// covering several overrides undoes them in reverse plan order.
  HealPlan planSeriesHeal([HealScope scope = HealScope.everything]) {
    final heals = <HealDecision>[];
    final ops = <Op>[], inverseOps = <Op>[];
    final refusals = <({String override, String reason})>[];
    for (final override in _candidates(scope)) {
      final decision = overrideHealDecision(override);
      if (!decision.healable) {
        refusals.add((override: override.id, reason: decision.reason));
        continue;
      }
      heals.add(decision);
      ops.add(delOp('overrides', override.id));
      for (final id in decision.relationIds) {
        ops.add(delOp('relations', id));
      }
      for (final id in decision.eventIds) {
        ops.add(delOp('events', id));
      }
      for (final id in decision.eventIds.reversed) {
        inverseOps.add(putOp('events', id, document.events[id]));
      }
      for (final id in decision.relationIds.reversed) {
        inverseOps.add(putOp('relations', id, document.relations[id]));
      }
      inverseOps.add(putOp('overrides', override.id, override));
    }
    return (
      heals: heals,
      ops: ops,
      inverseOps: inverseOps.reversed.toList(),
      refusals: refusals,
      healed: heals.length,
    );
  }
}

/// Apply a plan. The ops ARE the mutation here -- an immutable document has no
/// second in-place path that could disagree with the journal's account of it.
Document applySeriesHeal(Document document, HealPlan plan) => applyOps(document, plan.ops);

/// Restore everything a plan removed, from the snapshot its inverse ops carry.
Document revertSeriesHeal(Document document, HealPlan plan) => applyOps(document, plan.inverseOps);
