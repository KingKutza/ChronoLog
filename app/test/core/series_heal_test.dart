// The convergence invariant: the spec.
//
// Owner ruling (8.19): "Any time that overriding event matches the pattern, the
// event is removed and the projection reasserts. The series of events leading up
// to the heal are irrelevant." So nothing below simulates a user journey. Each
// case puts the document into a STATE and asks the invariant what it thinks --
// which is the whole claim: a no-op close, an edit reverted by hand, and a
// delete-then-recreate are the same case because only the state is examined.
//
// Generative by ruling. The properties quantify over random override/occurrence
// pairs -- random slot, random title, random duration spelling, random authored
// coordinate depth, random group membership -- and over MUTATIONS of a pair that
// heals, each of which must refuse and name its own field. The cases labelled
// RULED ANCHOR are the worked examples the rulings state, or a regression the
// owner reported in those words.
//
// THE PROJECTION GENERATOR IS INJECTED, and here it is the test's own: the
// projection engine is a separate wave, so this file drives the seam exactly as
// the engine will -- one window in, one fact out. That is deliberate rather than
// a stand-in for something missing: it is what proves the module's own logic is
// the thing under test, and it reads the pattern and its template out of the
// live document on every call, so editing the series changes what it projects
// with no edit to the projector.

import 'dart:math';

import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/eras.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/ops.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/series_heal.dart';
import 'package:chronolog/core/staples.dart';
import 'package:chronolog/core/validate.dart';
import 'package:test/test.dart';

import '../helpers/staple_world.dart';

const int specSeed = 20260827;
const int iterations = 120;

T _pick<T>(Random random, List<T> items) => items[random.nextInt(items.length)];

const String frameId = 'calendar:work';
const String groupFrameId = 'frame:group-work';
const String patternId = 'pattern:standing';
const String templateId = 'event:template';
const String templateRelationId = 'relation:template';

typedef Slot = ({String key, Json coordinate, Rational day});

/// A weekly standing series, its template, and the generator that projects it.
///
/// Built by hand rather than imported from ICS: `src/ics.js` is not ported, so
/// the fields a materialized occurrence carries are stated here instead of read
/// out of an importer this build does not have. Stated, not implied.
class Series {
  Series({bool withGroup = false, String title = 'Standing meeting', String duration = '3600'}) {
    final world = World();
    var next = world.document;
    if (withGroup) {
      next = next.put(
        'frames',
        groupFrameId,
        const Frame(id: groupFrameId, title: 'Work', traits: ['set', 'group']),
      );
    }
    next = next.put(
      'events',
      templateId,
      Event(
        id: templateId,
        traits: const ['event'],
        magnitudes: {'duration': durationMagnitude(duration)},
        payload: {'title': title, 'description': 'weekly', 'location': 'Room 1'},
      ),
    );
    next = next.put(
      'relations',
      templateRelationId,
      Relation(
        id: templateRelationId,
        type: 'staple',
        extra: {
          'kind': 'anchor',
          'role': 'placed',
          'ends': [
            ObjectEnd(templateId, point: 'start').toJson(),
            FrameEnd(frameId, position: Position.coordinate(slots.first.coordinate)).toJson(),
          ],
        },
      ),
    );
    next = next.put(
      'patterns',
      patternId,
      const Pattern(
        id: patternId,
        language: 'ics',
        extra: {
          'kind': 'ics-rrule',
          'rrule': {'FREQ': 'WEEKLY'},
          'templateEvent': templateId,
          'frame': frameId,
        },
      ),
    );
    if (withGroup) {
      next = next.put(
        'relations',
        'relation:template-group',
        Relation(
          id: 'relation:template-group',
          type: 'staple',
          extra: {
            'role': 'placed',
            'ends': [
              ObjectEnd(templateId, point: 'start').toJson(),
              StapleEnd.frame(groupFrameId).toJson(),
            ],
          },
        ),
      );
    }
    document = next;
  }

  /// The occurrences the rule alone describes: 09:00 every seventh day.
  static final List<Slot> slots = [
    for (final day in [5, 12, 19, 26])
      (
        key: '2026-01-${day.toString().padLeft(2, '0')}T09:00',
        coordinate: civil(2026, 1, day, 9, 0),
        day: gregorianLaw.toDays(Coordinate.fromJson(civil(2026, 1, day, 9, 0))),
      ),
  ];

  late Document document;
  int _minted = 0;

  String _id(String prefix) => '$prefix:mat${(++_minted).toString().padLeft(3, '0')}';

  /// The generator. Reads the pattern, its template and its second, independent
  /// bound (an end staple) out of [source] on every call, so nothing here
  /// remembers a projection it has already made.
  UnsuppressedProjector projectorFor(Document source) => (window) {
    final pattern = source.patterns[patternId];
    final template = source.events[templateId];
    final placement = source.relations[templateRelationId];
    if (pattern == null || template == null || placement == null) return null;
    if (window.frame != frameId) return null;
    final slot = firstMatch(
      slots,
      (slot) => stableVirtualId(patternId, slot.key) == window.virtualId,
    );
    if (slot == null) return null;
    if (slot.day < window.start || slot.day > window.end) return null;
    // An end staple is a SECOND bound intersected with the rule at projection
    // time -- the rule itself is never rewritten -- so a retired slot projects
    // nothing, exactly as the engine's own generator would report it.
    final until = Staples(source)
        .stapleDays(seriesEndStaple(source, patternId) ?? const Relation(id: '', type: ''));
    if (until != null && slot.day > until) return null;
    final eventId = 'projected:${slot.key}';
    return (
      virtualId: window.virtualId,
      event: template.copyWith(id: eventId, traits: [...template.traits, 'generated']),
      relation: placement.copyWith(
        id: 'projected-relation:${slot.key}',
        extra: {
          ...placement.extra,
          'ends': [
            ObjectEnd(eventId, point: 'start').toJson(),
            FrameEnd(frameId, position: Position.coordinate(slot.coordinate)).toJson(),
          ],
          'provenance': {'kind': 'generated', 'replaces': window.virtualId},
        },
      ),
    );
  };

  SeriesHeal healFor(Document source) => SeriesHeal(source, project: projectorFor(source));

  SeriesHeal get heal => healFor(document);

  /// What the JavaScript's `prepareMaterialization` builds: a clone of the
  /// projected occurrence with fresh ids, "generated" stripped, explicit
  /// provenance, the template's group attachments copied, and a suppressing
  /// override pointing at it.
  ({String event, String relation, String override, List<String> groups}) materialize(
    Slot slot, {
    Json? coordinate,
  }) {
    final virtualId = stableVirtualId(patternId, slot.key);
    final fact = projectorFor(document)((
      frame: frameId,
      start: slot.day - Rational.one,
      end: slot.day + Rational.one,
      virtualId: virtualId,
    ))!;
    final eventId = _id('event'), relationId = _id('relation'), overrideId = _id('override');
    document = document.put(
      'events',
      eventId,
      fact.event.copyWith(
        id: eventId,
        traits: [
          for (final trait in fact.event.traits)
            if (trait != 'generated') trait,
        ],
        extra: {
          ...fact.event.extra,
          'provenance': {'kind': 'explicit', 'replaces': virtualId, 'pattern': patternId},
        },
      ),
    );
    document = document.put(
      'relations',
      relationId,
      fact.relation.copyWith(
        id: relationId,
        extra: {
          ...fact.relation.extra,
          'ends': [
            ObjectEnd(eventId, point: 'start').toJson(),
            FrameEnd(
              frameId,
              position: Position.coordinate(coordinate ?? slot.coordinate),
            ).toJson(),
          ],
          'provenance': {'kind': 'explicit', 'replaces': virtualId},
        },
      ),
    );
    document = document.put(
      'overrides',
      overrideId,
      Override(id: overrideId, virtualId: virtualId, suppress: true, replacements: [eventId]),
    );
    final groups = <String>[];
    for (final relation in templateGroupAttachments(document, templateId)) {
      final id = _id('relation');
      document = document.put(
        'relations',
        id,
        // The template's own group affiliation, copied onto the occurrence: the
        // object end is re-said, every other term stands.
        relation.copyWith(
          id: id,
          extra: {
            ...relation.extra,
            'ends': [
              for (final end in relation.ends)
                end is ObjectEnd ? ObjectEnd(eventId, point: end.point).toJson() : end.toJson(),
            ],
          },
        ),
      );
      groups.add(id);
    }
    return (event: eventId, relation: relationId, override: overrideId, groups: groups);
  }

  Override override(String id) => document.overrides[id]!;

  HealDecision decide(String overrideId) => heal.overrideHealDecision(override(overrideId));

  HealPlan plan([HealScope scope = HealScope.everything]) => heal.planSeriesHeal(scope);
}

/// One unchanged materialization, the state after "open an occurrence and change
/// nothing".
({Series series, String event, String relation, String override, List<String> groups}) fixture({
  bool withGroup = false,
  int slot = 1,
}) {
  final series = Series(withGroup: withGroup);
  final parts = series.materialize(Series.slots[slot]);
  return (
    series: series,
    event: parts.event,
    relation: parts.relation,
    override: parts.override,
    groups: parts.groups,
  );
}

/// A single-field deviation, its own name, and the refusal class it must land
/// in. A false heal destroys authored data, so every projected field gets its
/// own row: these are the rows that stop this module eating real edits.
typedef Deviation = ({
  String field,
  String reason,
  bool needsGroup,
  void Function(Series, String) apply,
});

Relation _placementOf(Series series, String eventId) =>
    firstMatch(series.document.relations.values, (relation) => isPlacement(relation, eventId))!;

/// Re-say one term of a placement. The coordinate lives on the FRAME END now
/// (ruled 2026-09-01), so writing a top-level `coordinate` would edit a field
/// nothing reads and the deviation under test would never happen.
void _editPlacement(Series series, String eventId, String key, Object? value) {
  final placement = _placementOf(series, eventId);
  final said = key == 'coordinate'
      ? placement.withField('ends', [
          for (final end in placement.ends)
            end is FrameEnd
                ? FrameEnd(
                    end.frame,
                    position: Position.coordinate(value! as Json),
                    extra: end.extra,
                  ).toJson()
                : end.toJson(),
        ])
      : placement.withField(key, value);
  series.document = series.document.put('relations', placement.id, said);
}

void _editEvent(Series series, String eventId, Event Function(Event) edit) {
  series.document = series.document.put('events', eventId, edit(series.document.events[eventId]!));
}

const String _content = 'event content deviates from the projection';
const String _relations = 'relations deviate from the projection';

/// The two records the roster's done toggle writes, keyed by the occurrence they
/// are written against -- so several occurrences can each carry their own.
String membershipId(String eventId) => 'relation:done-membership/$eventId';

String endStapleId(String eventId) => 'relation:done-staple/$eventId';

final List<Deviation> deviations = [
  (
    field: 'title',
    reason: _content,
    needsGroup: false,
    apply: (series, id) => _editEvent(
      series,
      id,
      (event) => event.copyWith(payload: {...event.payload!, 'title': 'Standing meeting (moved)'}),
    ),
  ),
  (
    field: 'description',
    reason: _content,
    needsGroup: false,
    apply: (series, id) => _editEvent(
      series,
      id,
      (event) => event.copyWith(payload: {...event.payload!, 'description': 'just this one'}),
    ),
  ),
  (
    field: 'location',
    reason: _content,
    needsGroup: false,
    apply: (series, id) => _editEvent(
      series,
      id,
      (event) => event.copyWith(payload: {...event.payload!, 'location': 'Room 3'}),
    ),
  ),
  (
    field: 'duration',
    reason: _content,
    needsGroup: false,
    // Longer by a quarter hour, whatever the series says: a deviation relative
    // to the projection rather than a value that might happen to match it.
    apply: (series, id) => _editEvent(series, id, (event) {
      final now = Rational.parse(event.duration!.coordinate.value('second'));
      return event.copyWith(
        magnitudes: {'duration': durationMagnitude('${now + Rational.fromInt(900)}')},
      );
    }),
  ),
  (
    field: 'traits',
    reason: _content,
    needsGroup: false,
    apply: (series, id) =>
        _editEvent(series, id, (event) => event.copyWith(traits: [...event.traits, 'important'])),
  ),
  (
    field: 'display colour',
    reason: _content,
    needsGroup: false,
    apply: (series, id) =>
        _editEvent(series, id, (event) => event.withField('display', {'color': '#ff0000'})),
  ),
  (
    field: 'coordinate',
    reason: _relations,
    needsGroup: false,
    // Moved WITHIN the window, so the projection is still found and the
    // difference is the instant itself -- not a slot that projects nothing.
    apply: (series, id) => _editPlacement(series, id, 'coordinate', {
      'levels': [
        for (final level in _placementOf(series, id).coordinate!['levels'] as List)
          if (level is Map)
            {'level': level['level'], 'value': level['level'] == 'hour' ? '14' : level['value']},
      ],
    }),
  ),
  (
    field: 'role',
    reason: _relations,
    needsGroup: false,
    apply: (series, id) => _editPlacement(series, id, 'role', 'observed'),
  ),
  (
    field: 'placement parameters',
    reason: _relations,
    needsGroup: false,
    apply: (series, id) => _editPlacement(series, id, 'parameters', {'dateOnly': true}),
  ),
  // The roster's done toggle writes exactly these two records against one
  // occurrence. Completing one occurrence of a series is authored data and must
  // never be healed away -- and each of the two blocks the heal on its own.
  (
    field: 'state membership',
    reason: _relations,
    needsGroup: false,
    apply: (series, id) {
      series.document = series.document
          .put(
            'frames',
            'frame:state-done',
            const Frame(id: 'frame:state-done', title: 'Done', traits: ['set', 'group', 'state']),
          )
          .put(
            'relations',
            membershipId(id),
            Relation(
              id: membershipId(id),
              // AFFILIATION (ruled 2026-09-01): the object's whole on the state
              // sheet, said as a staple whose frame end names no point.
              type: 'staple',
              extra: {
                'ends': [
                  ObjectEnd(id).toJson(),
                  StapleEnd.frame('frame:state-done').toJson(),
                ],
              },
            ),
          );
    },
  ),
  (
    field: 'completion end staple',
    reason: _relations,
    needsGroup: false,
    apply: (series, id) {
      final placement = _placementOf(series, id);
      series.document = putStaple(
        series.document,
        id: endStapleId(id),
        kind: 'end',
        ends: [
          StapleEnd.object(id, point: 'end'),
          StapleEnd.frame(frameId, position: Position.coordinate(placement.coordinate!)),
        ],
      ).document;
    },
  ),
  (
    field: 'group membership dropped for this instance',
    reason: _relations,
    needsGroup: true,
    apply: (series, id) {
      final copied = firstMatch(
        series.document.relations.values,
        (relation) => relation.event == id && relation.frame == groupFrameId,
      )!;
      series.document = series.document.remove('relations', copied.id);
    },
  ),
];

void main() {
  // --- The heal fires -------------------------------------------------------

  group('an occurrence that says what its series says is retired', () {
    test('RULED ANCHOR: a materialization that changed nothing heals, and the '
        'projection reasserts', () {
      final parts = fixture();
      final series = parts.series;
      expect(series.decide(parts.override).healable, isTrue);
      final plan = series.plan();
      expect(plan.healed, 1);
      final healed = applySeriesHeal(series.document, plan);
      expect(healed.overrides[parts.override], isNull, reason: 'the override is gone');
      expect(healed.events[parts.event], isNull, reason: 'the materialized event is gone');
      expect(healed.relations[parts.relation], isNull, reason: 'its relation is gone');
      expect(validateDocument(healed).errors, isEmpty);
      // The projection reasserting is the point: with the override removed the
      // slot is described by the series alone once more.
      final slot = Series.slots[1];
      expect(
        series.projectorFor(healed)((
          frame: frameId,
          start: slot.day - Rational.one,
          end: slot.day + Rational.one,
          virtualId: stableVirtualId(patternId, slot.key),
        )),
        isNotNull,
      );
      // Idempotent: the second pass finds nothing left to heal.
      expect(series.healFor(healed).planSeriesHeal().healed, 0);
    });

    test('RULED ANCHOR: an occurrence edited away and moved back heals, even '
        'though the coordinate is written differently', () {
      final parts = fixture();
      final series = parts.series;
      // Move it: a genuine deviation.
      _editPlacement(series, parts.event, 'coordinate', civil(2026, 1, 14, 9, 0));
      expect(
        series.decide(parts.override).healable,
        isFalse,
        reason: 'while moved it stays overridden',
      );
      // Move it back by hand, in the OTHER textual form -- zero-padded, the way
      // an importer writes the same instant. A string comparison would call
      // these different; exact arithmetic does not.
      const padded = {
        'levels': [
          {'level': 'year', 'value': '2026'},
          {'level': 'month', 'value': '01'},
          {'level': 'day', 'value': '12'},
          {'level': 'hour', 'value': '09'},
          {'level': 'minute', 'value': '00'},
        ],
      };
      final projected = Series.slots[1].coordinate['levels'] as List;
      expect((projected[3] as Json)['value'], '9', reason: 'the projection writes a bare hour');
      _editPlacement(series, parts.event, 'coordinate', padded);
      final decision = series.decide(parts.override);
      expect(decision.healable, isTrue, reason: decision.reason);
    });

    test('RULED ANCHOR: a duration written 3600.0 still matches a projection of '
        '3600', () {
      for (final spelling in ['3600', '3600.0', '03600', '3600.000', '7200/2']) {
        final parts = fixture();
        _editEvent(
          parts.series,
          parts.event,
          (event) => event.copyWith(magnitudes: {'duration': durationMagnitude(spelling)}),
        );
        expect(
          parts.series.decide(parts.override).healable,
          isTrue,
          reason: 'exact equality, not string equality: "$spelling"',
        );
      }
    });

    test('RULED ANCHOR: deleting a materialization and recreating a matching one '
        'in the same place heals', () {
      final parts = fixture();
      final series = parts.series;
      series.document = series.document
          .remove('events', parts.event)
          .remove('relations', parts.relation)
          .remove('overrides', parts.override);
      final remade = series.materialize(Series.slots[1]);
      expect(remade.event, isNot(parts.event), reason: 'genuinely a different record');
      final decision = series.decide(remade.override);
      expect(decision.healable, isTrue, reason: decision.reason);
    });

    test('RULED ANCHOR: an occurrence carrying the template\'s group attachments '
        'heals with them, never orphaning one', () {
      final parts = fixture(withGroup: true);
      expect(parts.groups, hasLength(1));
      final decision = parts.series.decide(parts.override);
      expect(decision.healable, isTrue, reason: decision.reason);
      expect(decision.relationIds, contains(parts.groups.single));
      final healed = applySeriesHeal(parts.series.document, parts.series.plan());
      expect(healed.relations[parts.groups.single], isNull);
      expect(validateDocument(healed).errors, isEmpty);
    });

    test('an UNCHANGED random pair always heals, whatever the series says or '
        'which slot it sits on', () {
      final random = Random(specSeed);
      for (var round = 0; round < iterations; round += 1) {
        final series = Series(
          withGroup: random.nextBool(),
          title: 'Meeting ${random.nextInt(9999)}',
          duration: _pick(random, ['3600', '1800', '900', '86400', '0']),
        );
        final slot = Series.slots[random.nextInt(Series.slots.length)];
        // A coordinate spelled differently but numerically identical, at a
        // random padding width: the state the owner named as "moved back".
        final padding = 1 + random.nextInt(3);
        final respelled = <String, Object?>{
          'levels': [
            for (final level in slot.coordinate['levels'] as List)
              {
                'level': (level as Json)['level'],
                'value': (level['level'] == 'year')
                    ? level['value']
                    : '${level['value']}'.padLeft(padding, '0'),
              },
          ],
        };
        final parts = series.materialize(slot, coordinate: random.nextBool() ? respelled : null);
        final decision = series.decide(parts.override);
        expect(decision.healable, isTrue, reason: decision.reason);
        expect(decision.reason, 'matches the projection');
        expect(decision.eventIds, [parts.event]);
        expect(decision.relationIds, containsAll([parts.relation, ...parts.groups]));
      }
    });
  });

  // --- The heal refuses, field by field ------------------------------------

  group('every single-field deviation refuses, naming its field', () {
    for (final deviation in deviations) {
      test('RULED ANCHOR: a changed ${deviation.field} is authored data the heal '
          'must not destroy', () {
        final parts = fixture(withGroup: deviation.needsGroup);
        deviation.apply(parts.series, parts.event);
        final decision = parts.series.decide(parts.override);
        expect(decision.healable, isFalse, reason: '${deviation.field} is a deviation');
        expect(decision.reason, deviation.reason, reason: deviation.field);
        final plan = parts.series.plan();
        expect(plan.healed, 0, reason: 'and nothing is removed');
        expect(parts.series.document.events[parts.event], isNotNull);
        // A missed heal must be diagnosable rather than mysterious.
        final refusal = firstMatch(plan.refusals, (item) => item.override == parts.override);
        expect(refusal?.reason, deviation.reason);
      });
    }

    test('over random pairs, every single-field mutation refuses in its own '
        'named class', () {
      final random = Random(specSeed + 1);
      for (var round = 0; round < iterations; round += 1) {
        final deviation = _pick(random, deviations);
        final series = Series(
          withGroup: deviation.needsGroup || random.nextBool(),
          title: 'Meeting ${random.nextInt(9999)}',
          duration: _pick(random, ['3600', '1800', '900']),
        );
        final slot = Series.slots[random.nextInt(2) + 1];
        final parts = series.materialize(slot);
        expect(
          series.decide(parts.override).healable,
          isTrue,
          reason: 'healable before the change',
        );
        deviation.apply(series, parts.event);
        final decision = series.decide(parts.override);
        expect(decision.healable, isFalse, reason: deviation.field);
        expect(decision.reason, deviation.reason, reason: deviation.field);
        expect(series.plan().healed, 0);
      }
    });

    test('RULED ANCHOR: state affiliation blocks healing while present and '
        're-enables it when removed', () {
      final parts = fixture();
      final series = parts.series;
      expect(series.decide(parts.override).healable, isTrue);
      deviations.firstWhere((row) => row.field == 'state membership').apply(series, parts.event);
      deviations
          .firstWhere((row) => row.field == 'completion end staple')
          .apply(series, parts.event);
      final blocked = series.decide(parts.override);
      expect(blocked.healable, isFalse);
      expect(blocked.reason, _relations);
      series.document = series.document.remove('relations', membershipId(parts.event));
      expect(
        series.decide(parts.override).healable,
        isFalse,
        reason: 'the end staple blocks on its own too',
      );
      series.document = series.document.remove('relations', endStapleId(parts.event));
      // History-free: nothing about HOW the state was removed matters.
      expect(series.decide(parts.override).healable, isTrue);
    });
  });

  // --- Shapes the module must not touch ------------------------------------

  group('a shape this module did not build, it does not dismantle', () {
    test('RULED ANCHOR: a plain suppression with no replacement is never healed', () {
      final series = Series();
      const id = 'override:skip';
      series.document = series.document.put(
        'overrides',
        id,
        Override(
          id: id,
          virtualId: stableVirtualId(patternId, Series.slots[1].key),
          suppress: true,
        ),
      );
      final decision = series.decide(id);
      expect(decision.healable, isFalse);
      expect(decision.reason, 'override has 0 replacements, expected 1');
      expect(series.plan().healed, 0);
      expect(series.document.overrides[id], isNotNull, reason: 'the suppression survives');
    });

    test('a non-suppressing override, a missing replacement, and two '
        'replacements each refuse by their own shape', () {
      final parts = fixture();
      final series = parts.series;
      final override = series.override(parts.override);
      expect(
        series.heal.overrideHealDecision(override.copyWith(suppress: false)).reason,
        'override does not suppress its slot',
      );
      expect(
        series.heal.overrideHealDecision(override.copyWith(replacements: [])).reason,
        'override has 0 replacements, expected 1',
      );
      expect(
        series.heal
            .overrideHealDecision(override.copyWith(replacements: [parts.event, 'event:other']))
            .reason,
        'override has 2 replacements, expected 1',
      );
      expect(
        series.heal.overrideHealDecision(override.copyWith(replacements: ['event:ghost'])).reason,
        'replacement event is missing',
      );
      expect(
        series.heal.overrideHealDecision(override.copyWith(id: '')).reason,
        'not an override record',
      );
    });

    test('RULED ANCHOR: an end staple that retires the slot leaves the override '
        'in place -- the invariant refuses rather than destroys', () {
      final parts = fixture();
      final series = parts.series;
      expect(series.decide(parts.override).healable, isTrue);
      // A SECOND, independent bound intersected with the rule at projection
      // time: FREQ=WEEKLY is never rewritten.
      final cut = Series.slots[1].day - Rational.one;
      series.document = setSeriesEndStaple(
        series.document,
        patternId,
        frameId,
        gregorianLaw.fromDays(cut).toJson(),
      ).document;
      final decision = series.decide(parts.override);
      expect(decision.healable, isFalse);
      expect(decision.reason, 'the series projects nothing at this slot');
      expect(
        series.document.events[parts.event],
        isNotNull,
        reason: 'the authored event is untouched',
      );
      // Removing the staple resumes the projection; the override, unchanged this
      // whole time, is healable again purely because the state changed back.
      series.document = clearSeriesEndStaple(series.document, patternId);
      expect(series.decide(parts.override).healable, isTrue);
    });

    test('RULED ANCHOR: an override whose pattern is gone is left for the repair '
        'path, not healed', () {
      final parts = fixture();
      parts.series.document = parts.series.document.remove('patterns', patternId);
      final decision = parts.series.decide(parts.override);
      expect(decision.healable, isFalse);
      expect(decision.reason, 'the series projects nothing at this slot');
    });

    test('an occurrence moved clean off its window projects nothing rather than '
        'reporting a false match', () {
      final random = Random(specSeed + 2);
      for (var round = 0; round < iterations; round += 1) {
        final parts = fixture(slot: 1);
        final away = 2 + random.nextInt(5);
        _editPlacement(parts.series, parts.event, 'coordinate', civil(2026, 1, 12 + away, 9, 0));
        final decision = parts.series.decide(parts.override);
        expect(decision.healable, isFalse);
        expect(decision.reason, 'the series projects nothing at this slot');
      }
    });

    test('the projection for an overridden slot is reachable even though the '
        'override hides it', () {
      final parts = fixture();
      final projected = parts.series.heal.projectedOccurrence(
        parts.series.override(parts.override),
        parts.series.document.events[parts.event]!,
      );
      expect(projected, isNotNull);
      expect(projected!.virtualId, parts.series.override(parts.override).virtualId);
      // Anchored on the RESOLVED EXTENT, so an occurrence whose position comes
      // from a connection is found on the same rule as one placed outright.
      expect(projected.event.traits, contains('generated'));
    });
  });

  // --- Scope --------------------------------------------------------------

  group('scopes union rather than take priority', () {
    test('RULED ANCHOR: naming the event, the override, or the pattern each '
        'reaches the same heal, and naming something else reaches none', () {
      final parts = fixture();
      final series = parts.series;
      expect(series.plan(HealScope(eventIds: {parts.event})).healed, 1);
      expect(series.plan(HealScope(overrideIds: {parts.override})).healed, 1);
      expect(series.plan(const HealScope(patternIds: {patternId})).healed, 1);
      // The case treating the scopes as alternatives silently lost: an edit
      // scoped by EVENT id, whose convergeable occurrence is reachable only
      // through the pattern.
      expect(
        series.plan(HealScope(eventIds: {'event:unrelated'}, patternIds: {patternId})).healed,
        1,
      );
      expect(series.plan(const HealScope(eventIds: {'event:unrelated'})).healed, 0);
      expect(series.plan(const HealScope(overrideIds: {'override:nope'})).healed, 0);
      // An override id named outright outranks a widening: the caller knows.
      expect(
        series
            .plan(HealScope(overrideIds: const {'override:nope'}, eventIds: {parts.event}))
            .healed,
        0,
      );
    });

    test('the cheap pre-filter never misses a heal the real check would find', () {
      final random = Random(specSeed + 3);
      for (var round = 0; round < iterations; round += 1) {
        final series = Series(withGroup: random.nextBool());
        final wanted = <String>{};
        for (var count = 0; count < 1 + random.nextInt(3); count += 1) {
          final parts = series.materialize(Series.slots[count]);
          if (random.nextBool()) {
            _pick(
              random,
              deviations.where((row) => !row.needsGroup).toList(),
            ).apply(series, parts.event);
          } else {
            wanted.add(parts.override);
          }
        }
        final candidates = series.heal.healCandidateIds().toSet();
        final healed = {for (final decision in series.plan().heals) decision.override.id};
        expect(healed, wanted);
        expect(candidates, containsAll(healed), reason: 'a pre-filter that misses is a bug');
        // And an ordinary edit to an ordinary event matches nothing at all.
        expect(series.heal.healCandidateIds(const HealScope(eventIds: {'event:plain'})), isEmpty);
      }
    });
  });

  // --- Undo stays bundle-clean --------------------------------------------

  group('ops and inverse ops compose to identity', () {
    test('a plan then its revert is a document no-op, over random pairs', () {
      final random = Random(specSeed + 4);
      for (var round = 0; round < iterations; round += 1) {
        final series = Series(withGroup: random.nextBool());
        for (var count = 0; count < 1 + random.nextInt(3); count += 1) {
          series.materialize(Series.slots[count]);
        }
        final before = series.document;
        final plan = series.plan();
        expect(plan.healed, greaterThan(0));
        final healed = applySeriesHeal(before, plan);
        expect(healed, isNot(before), reason: 'the heal really happened');
        expect(revertSeriesHeal(healed, plan), before, reason: 'and it is exactly undone');
        // The same claim through the raw op lists, which is what the journal
        // replays: forward then inverse is the identity.
        expect(applyOps(applyOps(before, plan.ops), plan.inverseOps), before);
        expect(validateDocument(healed).errors, isEmpty);
        // The override leaves FIRST and comes back FIRST, so no state carries a
        // materialized event whose slot is no longer suppressed.
        expect(plan.ops.first.map, 'overrides');
        expect(plan.inverseOps.last.map, 'events');
      }
    });

    test('RULED ANCHOR: closing an unchanged occurrence leaves zero document '
        'delta', () {
      final series = Series();
      final baseline = series.document;
      final parts = series.materialize(Series.slots[1]);
      expect(series.document, isNot(baseline), reason: 'the materialization really happened');
      expect(series.document.events[parts.event], isNotNull);
      final healed = applySeriesHeal(series.document, series.plan());
      expect(healed, baseline, reason: 'and the document is exactly as it started');
      expect(validateDocument(healed).valid, isTrue);
    });

    test('RULED ANCHOR: an occurrence genuinely edited survives closing, exactly '
        'once, and editing it back retires it', () {
      final series = Series();
      final baseline = series.document;
      final parts = series.materialize(Series.slots[1]);
      _editEvent(
        series,
        parts.event,
        (event) => event.copyWith(payload: {...event.payload!, 'title': 'Temporarily different'}),
      );
      expect(series.plan().healed, 0, reason: 'closing does not retire a real deviation');
      expect(
        [
          for (final override in series.document.overrides.values)
            if (override.suppress && override.replacements.isNotEmpty) override.id,
        ],
        hasLength(1),
        reason: 'exactly one materialized instance, not two',
      );
      // Put the title back by hand. The invariant is state-based, so the very
      // next pass notices the occurrence matches and retires it.
      _editEvent(
        series,
        parts.event,
        (event) => event.copyWith(payload: {...event.payload!, 'title': 'Standing meeting'}),
      );
      final healed = applySeriesHeal(series.document, series.plan());
      expect(healed.events[parts.event], isNull, reason: 'it healed on the touch that restored it');
      expect(healed, baseline);
    });

    test('RULED ANCHOR: moving the series onto an exception\'s own values retires '
        'that exception', () {
      final series = Series();
      final parts = series.materialize(Series.slots[1]);
      _editEvent(
        series,
        parts.event,
        (event) => event.copyWith(payload: {...event.payload!, 'title': 'Renamed on this one'}),
      );
      expect(series.plan().healed, 0, reason: 'the exception exists and deviates');
      // Now move the SERIES onto the values the exception already had, by
      // editing its template. The projector reads the template live, so what the
      // series projects changes with no edit to the exception at all.
      _editEvent(
        series,
        templateId,
        (event) => event.copyWith(payload: {...event.payload!, 'title': 'Renamed on this one'}),
      );
      // Scoped by pattern, because the edit named the template EVENT and the
      // occurrence it converges is reachable only through the pattern.
      final plan = series.plan(const HealScope(patternIds: {patternId}));
      expect(plan.healed, 1);
      expect(applySeriesHeal(series.document, plan).events[parts.event], isNull);
    });
  });

  // --- Numeric spellings never decide anything ----------------------------

  test('a numeric spelling never affects any heal verdict, in a duration or a '
      'coordinate', () {
    final random = Random(specSeed + 5);
    for (var round = 0; round < iterations; round += 1) {
      final spellings = ['60', '60.0', '060', '60.000', '120/2'];
      final verdicts = <bool>{};
      final reasons = <String>{};
      for (final spelling in spellings) {
        final series = Series(duration: '60');
        final slot = Series.slots[1];
        final parts = series.materialize(slot);
        _editEvent(
          series,
          parts.event,
          (event) => event.copyWith(magnitudes: {'duration': durationMagnitude(spelling)}),
        );
        // And the same claim about a coordinate level, padded at random.
        final width = 1 + random.nextInt(4);
        _editPlacement(series, parts.event, 'coordinate', {
          'levels': [
            for (final level in slot.coordinate['levels'] as List)
              {
                'level': (level as Json)['level'],
                'value': level['level'] == 'year'
                    ? level['value']
                    : '${level['value']}'.padLeft(width, '0'),
              },
          ],
        });
        final decision = series.decide(parts.override);
        verdicts.add(decision.healable);
        reasons.add(decision.reason);
      }
      expect(verdicts, {true}, reason: 'every spelling of the same quantity heals');
      expect(reasons, {'matches the projection'});
    }
  });
}
