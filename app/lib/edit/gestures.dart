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
  ///
  /// WRITTEN AS A STAPLE (Don, ruled 2026-09-01: break the compatibility). The
  /// placement record is gone and the staple IS the placement: the object's
  /// START identified with a point on the frame. It says `start` out loud,
  /// because a silent object end now means the WHOLE of it -- a different claim
  /// -- and it wears the registered `anchor` kind, which is what tells a
  /// placement from an `end` staple carrying a completion instant on the same
  /// sheet.
  Relation placement(String objectId, String frameId, Rational days, String role) => Relation(
    id: createId('relation'),
    type: 'staple',
    extra: {
      'kind': 'anchor',
      'role': role,
      'ends': [
        ObjectEnd(objectId, point: startPoint).toJson(),
        FrameEnd(
          frameId,
          position: Position.coordinate(engine.daysCoordinate(frameId, days)),
        ).toJson(),
      ],
    },
  );

  /// An object in a group -- a state frame included, which is what makes state a
  /// frame rather than a property.
  ///
  /// WRITTEN AS A STAPLE (Don, ruled 2026-09-01: there is no membership, only
  /// staples). The sentence is unchanged and so is every reader: a frame end
  /// naming no point says "in this frame, nothing about where", which is the
  /// whole of what the `membership` record said. Old records keep loading and
  /// keep meaning exactly this -- `stapledMemberships` is the one reading both
  /// spellings go through -- so nothing is migrated and no file changes shape.
  Relation membership(String objectId, String groupId) => Relation(
    id: createId('relation'),
    type: 'staple',
    extra: {
      'ends': [ObjectEnd(objectId).toJson(), StapleEnd.frame(groupId).toJson()],
    },
  );

  /// Drag-create: an object under THAT frame's law, its duration the drag's own
  /// span. A zero-duration kind takes none however far the drag went; a kind
  /// that carries duration and was given no span takes the shipped default.
  ///
  /// [stapledTo] is the OBJECT the create was said ON (ISSUES 9.1: right-click
  /// an event, "New todo here", and here means THE EVENT). The new object's
  /// start point is said to be the same point as that object's start, in the one
  /// staple vocabulary and inside the same transaction -- one act, one undo
  /// entry -- so the sentence records what the pointer was over rather than the
  /// coordinate it happened to be at.
  String createAt(
    String frameId,
    Rational startDays,
    Rational? endDays, {
    String kind = 'event',
    String? stapledTo,
  }) {
    final definition = objectKinds[normalizeObjectKind(kind)]!;
    final other = endDays ?? startDays;
    final from = startDays <= other ? startDays : other;
    var to = startDays <= other ? other : startDays;
    if (!definition.zeroDuration && to == from) to = from + setting('edit.newSpanDays');
    final event = newObject(kind, spanDays: to - from);
    transaction('Create ${definition.label}', (current) {
      var next = current.put('events', event.id, event);
      final rides = stapledTo != null && next.events.containsKey(stapledTo);
      // NO COMPANION PLACEMENT (ISSUES 9.1). A staple saying this object's start
      // IS that object's start has already said where this object is, and the
      // substrate reads it there; writing a frame coordinate beside it would bake
      // in a position that goes stale the moment the far end is re-said, while
      // the staple rides. The frame placement is what an object said on EMPTY
      // SPACE gets, because there the pointer's coordinate is the whole sentence.
      if (!rides) {
        final relation = placement(event.id, frameId, from, definition.relationRole);
        return next.put('relations', relation.id, relation);
      }
      return putStaple(
        next,
        kind: anchorStapleKind,
        ends: [
          ObjectEnd(event.id, point: 'start'),
          ObjectEnd(stapledTo, point: 'start'),
        ],
      ).document;
    });
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
        _timed(sayingInstant(placement, engine.daysCoordinate(frame, toDays)), timed),
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
      sayingInstant(
        sayingObject(fact.relation.copyWith(id: createId('relation')), eventId),
        at == null ? fact.relation.coordinate : engine.daysCoordinate(frame, at),
      ).withField('provenance', {'kind': 'explicit', 'replaces': fact.virtualId}),
      timed,
    );
    var next = document.put('events', eventId, event).put('relations', placement.id, placement);
    final template = document.patterns[fact.pattern]?.templateEvent;
    for (final source
        in template == null ? const <Relation>[] : eventRelations(document, template)) {
      if (!(document.frames[source.frame]?.traits.contains('group') ?? false)) continue;
      final copy = sayingObject(source.copyWith(id: createId('relation')), eventId);
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
  ///
  /// WRITTEN AS A STAPLE (Don, ruled 2026-09-01). Both ends name objects and
  /// both are SILENT -- "all of this is all of that" -- which is the affiliation
  /// sentence with no group side and no arrow. The identification is symmetric
  /// and reads the same from either end; what the tree reads as held-by is the
  /// AUTHORED ORDER, which is the one ruled carrier of direction.
  Document withContains(Document current, String parentId, String childId, bool contained) {
    final existing = firstMatch(
      current.relations.values,
      (relation) =>
          firstMatch(
            stapledContainments(relation),
            (edge) => edge.parent == parentId && edge.child == childId,
          ) !=
          null,
    );
    if (contained == (existing != null) || parentId == childId) return current;
    if (existing != null) return removeStaple(current, existing.id);
    return putStaple(
      current,
      id: createId('relation'),
      ends: [ObjectEnd(childId), ObjectEnd(parentId)],
    ).document;
  }

  void setContains(String parentId, String childId, bool contained) => transaction(
    contained ? 'Contain object' : 'Release object',
    (current) => withContains(current, parentId, childId, contained),
  );

  // --- Saying one sentence over a selection ----------------------------------

  /// STAPLE EACH OF THESE TO THAT: N two-ended staples (Don, ISSUES 9.2).
  ///
  /// "Every selected start is that end, graph distance 1 from the target and the
  /// selected objects NOT connected to one another." Each object gets its own
  /// record, so the only thing the selection shares is what it was stapled to --
  /// which is what a person who selected many and said one thing meant.
  ///
  /// ONE TRANSACTION, ONE UNDO ENTRY. A mass edit that undid a row at a time
  /// would make the selection a thing the history has to be replayed to see.
  void stapleEach(Iterable<String> objects, StapleEnd far, {String point = startPoint}) =>
      transaction('Staple each', (current) {
        var next = current;
        for (final objectId in objects) {
          next = putStaple(
            next,
            id: createId('relation'),
            kind: anchorStapleKind,
            ends: [ObjectEnd(objectId, point: point), far],
          ).document;
        }
        return next;
      });

  /// STAPLE ALL OF THESE TOGETHER TO THAT: ONE staple with N+1 ends.
  ///
  /// "n points are one point" said at its full width -- the metal does exactly
  /// this and nothing about it is a special case of the two-ended form. Graph
  /// distance 0: the selected objects are all one point WITH the target, which
  /// is the whole difference from [stapleEach] and the reason the alternate
  /// gesture exists at all.
  void stapleAsOne(Iterable<String> objects, StapleEnd far, {String point = startPoint}) =>
      transaction(
        'Staple all as one',
        (current) => putStaple(
          current,
          id: createId('relation'),
          kind: anchorStapleKind,
          ends: [for (final objectId in objects) ObjectEnd(objectId, point: point), far],
        ).document,
      );
}
