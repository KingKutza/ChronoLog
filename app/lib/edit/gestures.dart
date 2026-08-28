// The write side of pointer gestures.
//
// Every coordinate written here is built under the law of the frame it is
// written ONTO -- never the registered standard, and never the primary's law for
// a companion frame's placement. That is the frame model, and it is the one rule
// these four verbs share.

import '../core/coordinate_law.dart';
import '../core/document.dart';
import '../core/eras.dart';
import '../core/exact.dart';
import '../core/object_kinds.dart';
import '../core/projection.dart';
import '../core/records.dart';
import '../core/staples.dart';
import 'editor.dart';

extension Gestures on Editor {
  /// A new object of [kind]: the catalog's traits, the payload a card fills in,
  /// and a duration in the measure frame's own seconds. Every create path builds
  /// its object here, so a fourth kind is a catalog row and nothing more.
  Event newObject(String kind, {String? title, Rational? spanDays, String note = ''}) {
    final definition = objectKinds[normalizeObjectKind(kind)]!;
    // The measure frame comes from the core's own duration factory rather than
    // being named again here: two spellings of one frame id could only disagree.
    final measure = durationMagnitude('0', 'second').frame!;
    final seconds = definition.zeroDuration || spanDays == null
        ? Rational.zero
        : spanDays * engine.lawOf(measure).unitsPer('second', 'day');
    return Event(
      id: createId('event'),
      traits: traitsForObjectKind(null, kind),
      magnitudes: {'duration': durationMagnitude(seconds.toJson(), 'second')},
      payload: {'title': title ?? definition.newTitle, 'description': note, 'location': ''},
    );
  }

  /// An object placed on a frame at a day, the coordinate built under THAT
  /// frame's own law. Every placement any surface writes is built here.
  Relation placement(String objectId, String frameId, Rational days, String role) => Relation(
    id: createId('relation'),
    type: 'attachment',
    extra: {
      'event': objectId,
      'frame': frameId,
      'role': role,
      'coordinate': engine.daysCoordinate(frameId, days),
    },
  );

  /// An object in a group -- a state frame included, which is what makes state a
  /// frame rather than a property.
  Relation membership(String objectId, String groupId) => Relation(
    id: createId('relation'),
    type: 'membership',
    extra: {'group': groupId, 'member': objectId},
  );

  /// Drag-create: an object under THAT frame's law, its duration the drag's own
  /// span. A zero-duration kind takes none however far the drag went; a kind
  /// that carries duration and was given no span takes the shipped default.
  String createAt(String frameId, Rational startDays, Rational? endDays, {String kind = 'event'}) {
    final definition = objectKinds[normalizeObjectKind(kind)]!;
    final other = endDays ?? startDays;
    final from = startDays <= other ? startDays : other;
    var to = startDays <= other ? other : startDays;
    if (!definition.zeroDuration && to == from) to = from + setting('edit.newSpanDays');
    final event = newObject(kind, spanDays: to - from);
    final relation = placement(event.id, frameId, from, definition.relationRole);
    transaction(
      'Create ${definition.label}',
      (current) => current.put('events', event.id, event).put('relations', relation.id, relation),
    );
    return event.id;
  }

  /// Drag-move.
  ///
  /// A generated occurrence materializes into an authored object first, its
  /// placement inheriting the relation's own frame. An occurrence that was
  /// already materialized and is dropped back within half a grain of where its
  /// series put it is RESTORED to the series instead: removing the event takes
  /// its placement and its suppressing override with it, and the projection
  /// reasserts on its own.
  ///
  /// Answers with the object now carrying the placement, or null when the drop
  /// restored the series or the placement had gone.
  String? moveFact(Fact fact, Rational toDays, {bool timed = false}) {
    final frame = fact.relation.frame;
    if (frame == null) return null;
    if (fact.virtualId.isNotEmpty) {
      final parts = materializeFact(fact, at: toDays, timed: timed);
      transaction('Move recurring occurrence', (_) => parts.document);
      return parts.event;
    }
    final placement = document.relations[fact.relation.id];
    if (placement == null) return null;
    final provenance = obj(fact.event.extra['provenance']);
    final home = obj(provenance?['originalCoordinate']);
    if (provenance?['replaces'] != null && home != null) {
      final was = engine.coordinateDays(frame, home);
      final grain = setting('edit.snapGrainMinutes');
      final half = grain / (Rational.fromInt(2) * engine.lawOf(frame).unitsPer('minute', 'day'));
      if ((was - toDays).abs() <= half) {
        transaction(
          'Restore recurring occurrence',
          (current) => current.remove('events', fact.event.id),
        );
        return null;
      }
    }
    transaction(
      'Move ${objectKinds[objectKindForEvent(fact.event)]!.label}',
      (current) => current.put(
        'relations',
        placement.id,
        _timed(placement.withField('coordinate', engine.daysCoordinate(frame, toDays)), timed),
      ),
    );
    return fact.event.id;
  }

  /// The materialization record set: the occurrence as an authored object (its
  /// `generated` trait stripped, its provenance naming the slot it replaces and
  /// the coordinate it was born at), its placement under the SAME frame's law,
  /// the template's group attachments, and the override that suppresses the slot.
  ///
  /// Built without committing, so "edit this occurrence" and a drag-move share
  /// one derivation and one shape.
  ({Document document, String event}) materializeFact(
    Fact fact, {
    Rational? at,
    bool timed = false,
  }) {
    final frame = fact.relation.frame ?? '';
    final eventId = createId('event');
    final event = fact.event
        .copyWith(
          id: eventId,
          traits: [
            for (final trait in fact.event.traits)
              if (trait != 'generated') trait,
          ],
        )
        .withField('provenance', {
          'kind': 'explicit',
          'replaces': fact.virtualId,
          'pattern': fact.pattern,
          'originalCoordinate': fact.relation.coordinate,
        });
    final placement = _timed(
      fact.relation
          .copyWith(id: createId('relation'))
          .withField('event', eventId)
          .withField(
            'coordinate',
            at == null ? fact.relation.coordinate : engine.daysCoordinate(frame, at),
          )
          .withField('provenance', {'kind': 'explicit', 'replaces': fact.virtualId}),
      timed,
    );
    var next = document.put('events', eventId, event).put('relations', placement.id, placement);
    final template = document.patterns[fact.pattern]?.templateEvent;
    for (final source
        in template == null ? const <Relation>[] : eventRelations(document, template)) {
      if (!(document.frames[source.frame]?.traits.contains('group') ?? false)) continue;
      final copy = source.copyWith(id: createId('relation')).withField('event', eventId);
      next = next.put('relations', copy.id, copy);
    }
    final override = Override(
      id: createId('override'),
      virtualId: fact.virtualId,
      suppress: true,
      replacements: [eventId],
    );
    return (document: next.put('overrides', override.id, override), event: eventId);
  }

  /// A drop onto a timed surface states a time, so the placement can no longer
  /// claim to be date-only.
  Relation _timed(Relation relation, bool timed) => timed
      ? relation.withField('parameters', {...?obj(relation.extra['parameters']), 'dateOnly': false})
      : relation;

  /// Entering or leaving a state, as a DOCUMENT rather than as a commit.
  ///
  /// Composable on purpose: a card dragged from one state column to another
  /// leaves one state and enters another, and that is ONE act, so it must be
  /// one undo entry (ruled 2026-08-28). [toggleState] is this plus a label.
  ///
  /// The state frame is minted lazily by the first entry and NEVER seeded, so
  /// undoing the first completion removes the frame too. Leaving takes the
  /// instant with it: un-doing a done is a claim that it did not finish, so the
  /// staple that said when it finished cannot stand. ONE end staple per object
  /// -- a second state entered while an instant is already stated reuses it.
  Document withState(
    Document current,
    String objectId,
    String stateFrameId, {
    Coordinate? at,
    String title = doneStateTitle,
    String? frame,
  }) {
    if (!current.events.containsKey(objectId)) return current;
    final facts = ObjectFacts(current);
    final entered = firstMatch(
      facts.stateAffiliations(objectId),
      (entry) => entry.frame == stateFrameId,
    );
    if (entered != null) {
      var next = current.remove('relations', entered.membership.id);
      final staple = facts.objectEndStaple(objectId);
      return staple == null ? next : removeStaple(next, staple.id);
    }
    final joined = membership(objectId, stateFrameId);
    var next = ensureStateFrame(
      current,
      id: stateFrameId,
      title: title,
    ).document.put('relations', joined.id, joined);
    // The instant lands on the same frame the object is already placed on, so
    // both facts agree about where it lives. With no real frame to pin it to,
    // the membership alone is the honest record -- done, instant unstated,
    // which the ruling makes legal.
    final home =
        firstMatch(current.relations.values, (r) => isPlacement(r, objectId))?.frame ??
        (current.frames.containsKey(frame) ? frame : null);
    if (home != null && facts.objectEndStaple(objectId) == null) {
      next = putStaple(
        next,
        kind: 'end',
        ends: [
          ObjectEnd(objectId, point: 'end'),
          FrameEnd(
            home,
            position: Position.coordinate(
              at == null ? engine.daysCoordinate(home, nowDays()) : Json.from(at.toJson()),
            ),
          ),
        ],
      ).document;
    }
    return next;
  }

  /// Enter or leave a state: a membership and, entering, the terminal end staple
  /// that says when -- one bundle, one undo entry.
  void toggleState(
    String objectId,
    String stateFrameId, {
    Coordinate? at,
    String title = doneStateTitle,
    String? frame,
  }) {
    // A record still pending is one this very act authors, so it counts.
    if (!document.events.containsKey(objectId) && !pending.containsKey(objectId)) return;
    final leaving = firstMatch(
      ObjectFacts(document).stateAffiliations(objectId),
      (entry) => entry.frame == stateFrameId,
    );
    transaction(
      '${leaving == null ? 'Enter' : 'Leave'} state $title',
      (current) => withState(current, objectId, stateFrameId, at: at, title: title, frame: frame),
    );
  }

  /// Containment, which passes no judgment: any object may contain any other,
  /// multi-parent and cyclic shapes included. Only a thing containing itself is
  /// refused, because that says nothing.
  Document withContains(Document current, String parentId, String childId, bool contained) {
    final existing = firstMatch(
      current.relations.values,
      (relation) =>
          relation.type == 'contains' && relation.parent == parentId && relation.child == childId,
    );
    if (contained == (existing != null) || parentId == childId) return current;
    if (existing != null) return current.remove('relations', existing.id);
    final relation = Relation(
      id: createId('relation'),
      type: 'contains',
      extra: {'parent': parentId, 'child': childId},
    );
    return current.put('relations', relation.id, relation);
  }

  void setContains(String parentId, String childId, bool contained) => transaction(
    contained ? 'Contain object' : 'Release object',
    (current) => withContains(current, parentId, childId, contained),
  );
}
