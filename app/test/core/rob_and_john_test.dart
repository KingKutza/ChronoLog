// LEXICON.md's Rob-and-John scenario, followed BEAT BY BEAT -- the integration
// acceptance of the whole series stack rather than one more unit test. Every
// beat runs the real modules end to end: the document is built with
// `records.dart` and `document.dart`, projected by `ProjectionEngine`, and
// healed by `SeriesHeal` wired to that same engine's unsuppressed projection.
//
// EXAMPLE-BASED ON PURPOSE, and the one file in this suite that is. The
// generative doctrine (Don, 2026-08-27: "we should never be testing for a
// specific case, we should be testing for a general case") allows exactly this
// exception, because THIS IS A STORY and its order is the specification: a rule
// that reigns, a life event, a staple at the inflection point, and what the
// projection says afterwards. No property quantified over random worlds can
// state "six years later John has a kid". The general cases the beats touch are
// each pinned generatively elsewhere -- projection_test.dart, series_heal_test
// .dart, staples_test.dart -- and what is only checkable here is that they
// COMPOSE into the scenario the model exists for.
//
// The scenario, in the owner's own words (LEXICON.md):
//
// "Rob says 'let's do Monday meetings -- you always get in early on Mondays.'
// John adds a Monday meeting, 6:15 to 6:30, repeat every Monday, skip holidays
// (events on frame xyz), run indefinite (projected up to 2 years into the
// future; default settable in settings). Six years later John has a kid,
// doesn't get in till 8:00, and after some conversation they move to a Thursday
// lunch meeting. At that decision they place a staple at the inflection point
// defining an end to the initial series rule, then either define a new rule
// post-staple or a new series, on preference."
//
// What it pins, restated as the beats below test them: a series is an identity
// whose rules are segments partitioned by staples; holiday exclusion is a live
// reference to another frame's events, not a baked list; the rule's extent
// (indefinite) and the projection horizon (bounded, settable) are different
// things; and the inflection staple records where life changed the schedule --
// without destroying the series' identity, and without there being only one way
// to author the same outcome.
//
// WHERE A JAVASCRIPT BEAT ASSERTED THROUGH THE OLD ENGINE'S SHAPES it is
// re-expressed against the Dart API without weakening the claim, and where one
// pinned behaviour a ruling has since killed it is adapted and marked `// RULED:`
// with the ruling named.

import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/eras.dart' show firstMatch;
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/series_heal.dart';
import 'package:chronolog/core/staples.dart';
import 'package:chronolog/core/validate.dart';
import 'package:test/test.dart';

import '../helpers/staple_world.dart' show civil;

const String workFrameId = 'calendar:work';
const String holidayFrameId = 'frame:holidays';
const String patternId = 'pattern:rob-and-john';
const String templateEventId = 'event:monday-check-in';
const String templateRelationId = 'relation:monday-check-in';
const String lunchPatternId = 'pattern:thursday-lunch';

/// A bare date, at day precision -- the window bounds the story speaks in.
Json date(int year, [int month = 1, int day = 1]) => civil(year, month, day);

/// The two durations the story names: John's original 6:15-6:30, and the
/// Thursday lunch's "a different duration".
final Rational fifteenMinutes = Rational.fromInt(15, 1440);
final Rational oneHour = Rational.fromInt(1, 24);

// The inflection instant six years on (2032-01-05, still a Monday -- 313 weeks
// preserves the weekday) and the Thursday lunch base three days later, computed
// exactly rather than eyeballed, per the file-wide no-string-dates discipline.

final Rational mondayBase =
    Rational(daysFromCivil(BigInt.from(2026), 1, 5)) +
    Rational.fromInt(6, 24) +
    Rational.fromInt(15, 1440);

final Rational inflectionDays = mondayBase + Rational(BigInt.from(313 * 7));

final Rational thursdayDays =
    Rational(inflectionDays.floor() + BigInt.from(3)) + Rational.fromInt(12, 24);

final Json inflectionCoordinate = Json.from(daysToCivilCoordinate(inflectionDays).toJson());

final Json thursdayCoordinate = Json.from(daysToCivilCoordinate(thursdayDays).toJson());

/// The rule that follows the inflection staple: a different weekday AND a
/// different time of day AND a different duration.
Json thursdayRule() => {
  'rrule': const {'FREQ': 'WEEKLY'},
  'coordinate': thursdayCoordinate,
  'frame': workFrameId,
  'magnitude': durationMagnitude('1', 'hour').toJson(),
};

/// John's Monday 6:15-6:30 standing meeting, indefinite (no COUNT, no UNTIL),
/// plus a separate frame the meeting will be told to skip.
///
/// Built by hand rather than through a real ICS import: `src/ics.js` is not
/// ported, so the fields the importer would give each record are STATED here
/// instead of read out of an importer this build does not have -- the ICS the
/// JavaScript fed itself was `DTSTART:20260105T061500Z`, `RRULE:FREQ=WEEKLY`,
/// `DURATION:PT15M`, `SUMMARY:Monday check-in`, and those are the values below.
class World {
  World() {
    _document = createEmptyWorkspaceDocument(now: DateTime.utc(2026))
        .put(
          'frames',
          workFrameId,
          const Frame(
            id: workFrameId,
            title: 'Work calendar',
            traits: ['set', 'calendar'],
            extra: {'basis': 'frame:wall-time'},
          ),
        )
        .put(
          'frames',
          holidayFrameId,
          const Frame(
            id: holidayFrameId,
            title: 'Holidays',
            traits: ['set', 'calendar'],
            extra: {'basis': 'frame:wall-time'},
          ),
        )
        .put(
          'events',
          templateEventId,
          Event(
            id: templateEventId,
            traits: const ['event'],
            magnitudes: {'duration': durationMagnitude('15', 'minute')},
            payload: const {'title': 'Monday check-in'},
          ),
        )
        .put(
          'relations',
          templateRelationId,
          Relation(
            id: templateRelationId,
            type: 'attachment',
            extra: {
              'event': templateEventId,
              'frame': workFrameId,
              'role': 'template',
              'coordinate': civil(2026, 1, 5, 6, 15),
            },
          ),
        )
        .put(
          'patterns',
          patternId,
          const Pattern(
            id: patternId,
            language: 'chronolog-ics/1',
            extra: {
              'kind': 'ics-rrule',
              'rrule': {'FREQ': 'WEEKLY'},
              'templateEvent': templateEventId,
              'templateRelation': templateRelationId,
              'frame': workFrameId,
              'appliesTo': [workFrameId],
            },
          ),
        );
  }

  late Document _document;
  ProjectionEngine? _engine;
  int _minted = 0;

  Document get document => _document;

  /// Every edit drops the engine. A FRESH ENGINE PER DOCUMENT STATE,
  /// deliberately: this file is about what the projection says given the
  /// document's current state, never about a recurrence cache surviving an edit
  /// (that trap has its own regression in projection_test.dart).
  set document(Document next) {
    _document = next;
    _engine = null;
  }

  ProjectionEngine get engine => _engine ??= ProjectionEngine(_document);

  Pattern get pattern => _document.patterns[patternId]!;

  Json get rrule => obj(pattern.extra['rrule']) ?? const {};

  String _id(String prefix) => '$prefix:mat${(++_minted).toString().padLeft(3, '0')}';

  /// The VIRTUAL facts a query over this window comes to -- the occurrences the
  /// series projects, as the document currently stands.
  List<Fact> occurrences({Json? start, Json? end}) => [
    for (final fact
        in engine
            .queryFacts(
              Projection.of(const [workFrameId]),
              start: start ?? date(2020),
              end: end ?? date(2040),
              limit: 5000,
            )
            .facts)
      if (fact.kind == 'virtual') fact,
  ];

  /// An occurrence's own duration, read through the real stack rather than off
  /// the record: the following rule's magnitude overrides the template's for its
  /// own segment, and that override is what the split in beat 4 reads.
  Rational durationOf(Fact fact) => engine.eventDurationDays(fact.event);

  /// "skip holidays (events on frame xyz)" -- authored ONCE, and never touched
  /// again, which is what makes the exclusion live rather than baked.
  void skipHolidays() {
    document = _document.put(
      'patterns',
      patternId,
      pattern.withField('exclude', {
        'frames': const [holidayFrameId],
      }),
    );
  }

  String addHoliday(int year, int month, int day, [String title = 'Holiday']) {
    final eventId = _id('event'), relationId = _id('relation');
    document = _document
        .put(
          'events',
          eventId,
          Event(
            id: eventId,
            traits: const ['event', 'holiday'],
            magnitudes: {'duration': durationMagnitude('1', 'day')},
            payload: {'title': title},
          ),
        )
        .put(
          'relations',
          relationId,
          Relation(
            id: relationId,
            type: 'attachment',
            extra: {
              'event': eventId,
              'frame': holidayFrameId,
              'role': 'placed',
              'coordinate': date(year, month, day),
            },
          ),
        );
    return eventId;
  }

  Relation staple({String? kind, required List<StapleEnd> ends, Json extra = const {}}) {
    final placed = putStaple(_document, id: _id('relation'), kind: kind, ends: ends, extra: extra);
    document = placed.document;
    return placed.staple;
  }

  /// The inflection staple: it ends the reigning rule and carries the one that
  /// follows, on the same series.
  Relation inflect({Json? at, Json? rule}) => staple(
    kind: 'inflection',
    ends: [
      const StapleEnd.series(patternId),
      StapleEnd.frame(workFrameId, position: Position.coordinate(at ?? inflectionCoordinate)),
    ],
    extra: {
      'payload': {'rule': rule ?? thursdayRule()},
    },
  );

  /// A SECOND, independently authored series for the Thursday lunch -- the "or a
  /// new series, on preference" branch.
  String addThursdaySeries() {
    const eventId = 'event:thursday-lunch';
    const relationId = 'relation:thursday-lunch';
    document = _document
        .put(
          'events',
          eventId,
          Event(
            id: eventId,
            traits: const ['event'],
            magnitudes: {'duration': durationMagnitude('1', 'hour')},
            payload: const {'title': 'Thursday lunch'},
          ),
        )
        .put(
          'relations',
          relationId,
          Relation(
            id: relationId,
            type: 'attachment',
            extra: {
              'event': eventId,
              'frame': workFrameId,
              'role': 'template',
              'coordinate': thursdayCoordinate,
            },
          ),
        )
        .put(
          'patterns',
          lunchPatternId,
          const Pattern(
            id: lunchPatternId,
            language: 'chronolog-ics/1',
            extra: {
              'kind': 'ics-rrule',
              'rrule': {'FREQ': 'WEEKLY'},
              'templateEvent': eventId,
              'templateRelation': relationId,
              'frame': workFrameId,
              'appliesTo': [workFrameId],
            },
          ),
        );
    return lunchPatternId;
  }

  void movePlacement(String relationId, Json coordinate) {
    document = _document.put(
      'relations',
      relationId,
      _document.relations[relationId]!.withField('coordinate', coordinate),
    );
  }

  String addFollower(String title, String minutes) {
    final eventId = _id('event');
    document = _document.put(
      'events',
      eventId,
      Event(
        id: eventId,
        traits: const ['event'],
        magnitudes: {'duration': durationMagnitude(minutes, 'minute')},
        payload: {'title': title},
      ),
    );
    return eventId;
  }

  Extent extentOf(String objectId) => engine.staples.resolveObjectExtent(objectId);

  /// What the inspector's `prepareMaterialization` builds: a clone of the
  /// projected occurrence with fresh ids, "generated" stripped, explicit
  /// provenance, and a suppressing override pointing at it.
  ({String event, String relation, String override}) materialize(Fact fact) {
    final eventId = _id('event'), relationId = _id('relation'), overrideId = _id('override');
    document = _document
        .put(
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
              'provenance': {
                'kind': 'explicit',
                'replaces': fact.virtualId,
                'pattern': fact.pattern,
                'originalCoordinate': fact.relation.coordinate,
              },
            },
          ),
        )
        .put(
          'relations',
          relationId,
          fact.relation.copyWith(
            id: relationId,
            extra: {
              ...fact.relation.extra,
              'event': eventId,
              'provenance': {'kind': 'explicit', 'replaces': fact.virtualId},
            },
          ),
        )
        .put(
          'overrides',
          overrideId,
          Override(
            id: overrideId,
            virtualId: fact.virtualId,
            suppress: true,
            replacements: [eventId],
          ),
        );
    return (event: eventId, relation: relationId, override: overrideId);
  }

  /// THE CONVERGENCE INVARIANT, WIRED TO THE REAL ENGINE.
  ///
  /// `series_heal.dart` documents exactly this wiring for integration -- "it is
  /// `queryFacts` over the window with overrides not applied, picking the fact
  /// whose virtual id matches" -- so the generator that reasserts IS the one that
  /// heals and the two cannot drift.
  SeriesHeal get heal {
    final live = engine;
    return SeriesHeal(
      _document,
      staples: live.staples,
      project: (window) {
        final found = firstMatch(
          live
              .queryFacts(
                Projection.of([window.frame]),
                start: window.start,
                end: window.end,
                applyOverrides: false,
              )
              .facts,
          (fact) => fact.virtualId == window.virtualId,
        );
        return found == null
            ? null
            : (virtualId: found.virtualId, event: found.event, relation: found.relation);
      },
    );
  }

  HealDecision decide(String overrideId) =>
      heal.overrideHealDecision(_document.overrides[overrideId]!);
}

/// Every occurrence's civil instant, as text. DISPLAY ONLY: every comparison
/// with teeth below is made in exact days.
List<String> times(List<Fact> facts) => [
  for (final fact in facts) formatCivil(Coordinate.fromJson(fact.coordinate), includeTime: true),
];

List<String> daysOf(List<Fact> facts) => [for (final fact in facts) fact.day.toJson()];

void main() {
  // --- Beat 1: a Monday standing meeting, indefinite ------------------------

  test('Rob-and-John beat 1: a Monday 6:15-6:30 weekly series, indefinite', () {
    final world = World();
    expect(world.rrule['FREQ'], 'WEEKLY');
    expect(world.rrule['COUNT'], isNull, reason: 'no COUNT -- indefinite');
    expect(world.rrule['UNTIL'], isNull, reason: 'no UNTIL -- indefinite');
    final facts = world.occurrences(start: date(2026), end: date(2026, 3, 1));
    expect(times(facts).take(4).toList(), [
      '2026-01-05 06:15:00',
      '2026-01-12 06:15:00',
      '2026-01-19 06:15:00',
      '2026-01-26 06:15:00',
    ]);
    // 6:15 TO 6:30 -- the duration is the story's, read back through the stack
    // that will have to draw it.
    expect(world.durationOf(facts.first), fifteenMinutes);
    expect(validateDocument(world.document).valid, isTrue);
  });

  // --- Beat 2: holidays are a live reference, not a baked list --------------

  test('Rob-and-John beat 2: holiday exclusion is a live reference to another '
      "frame's events", () {
    final world = World();
    // 2026-01-19 is one of the series' own Mondays.
    world.addHoliday(2026, 1, 19, 'Made-up holiday');
    world.skipHolidays();

    final withOneHoliday = times(world.occurrences(start: date(2026), end: date(2026, 2, 1)));
    expect(
      withOneHoliday,
      isNot(contains('2026-01-19 06:15:00')),
      reason: 'the holiday Monday does not project',
    );
    expect(withOneHoliday, [
      '2026-01-05 06:15:00',
      '2026-01-12 06:15:00',
      '2026-01-26 06:15:00',
    ], reason: 'every other Monday in the window is untouched');

    // Add a SECOND holiday with NO EDIT TO THE SERIES -- that is what makes the
    // exclusion live rather than baked. Neither the pattern nor its `exclude` is
    // touched again below.
    world.addHoliday(2026, 2, 2, 'A second made-up holiday');
    final withTwoHolidays = times(world.occurrences(start: date(2026), end: date(2026, 2, 10)));
    expect(
      withTwoHolidays,
      isNot(contains('2026-02-02 06:15:00')),
      reason: "the newly-added holiday's Monday stops projecting",
    );
    expect(withTwoHolidays, [
      '2026-01-05 06:15:00',
      '2026-01-12 06:15:00',
      '2026-01-26 06:15:00',
      '2026-02-09 06:15:00',
    ]);
    expect(validateDocument(world.document).valid, isTrue);
  });

  // --- Beat 3: rule extent vs. projection horizon are different things ------

  test('Rob-and-John beat 3: the rule\'s extent (indefinite) and the projection '
      'horizon (bounded) are different things', () {
    final world = World();
    expect(world.rrule['COUNT'], isNull);
    expect(world.rrule['UNTIL'], isNull);

    // A ~2-year horizon (the scenario's own default) returns a bounded set...
    final twoYearHorizon = world.occurrences(start: date(2026), end: date(2028));
    expect(twoYearHorizon, isNotEmpty);
    expect(twoYearHorizon.length, lessThan(120));

    // ...while a wider query against the very same, still-indefinite rule
    // returns strictly more -- the rule never stopped; only the query bound did.
    final sixYearHorizon = world.occurrences(start: date(2026), end: date(2032));
    expect(
      sixYearHorizon.length,
      greaterThan(twoYearHorizon.length),
      reason: 'a wider horizon sees further into the same indefinite rule',
    );
    expect(
      daysOf(sixYearHorizon).take(twoYearHorizon.length).toList(),
      daysOf(twoYearHorizon),
      reason: 'the shared prefix agrees exactly',
    );
    // And the rule itself is untouched by either ask: the horizon is the
    // caller's derived budget, never a bound written onto the series.
    expect(world.rrule, {'FREQ': 'WEEKLY'});
  });

  // --- Beat 4: the inflection staple, single identity -----------------------

  test('Rob-and-John beat 4: an inflection staple partitions the series into '
      'Monday-then-Thursday, one identity throughout', () {
    final world = World();
    final staple = world.inflect();
    expect(validateDocument(world.document).valid, isTrue);

    final facts = world.occurrences(start: date(2020), end: date(2033));
    // Split by each occurrence's own duration rather than string-matching a
    // date: a Monday occurrence's duration is the original 15 minutes; a
    // Thursday lunch's is the new 1-hour magnitude the staple's following rule
    // carries (LEXICON.md: "a different duration").
    final before = [
      for (final fact in facts)
        if (world.durationOf(fact) == fifteenMinutes) fact,
    ];
    final after = [
      for (final fact in facts)
        if (world.durationOf(fact) == oneHour) fact,
    ];
    expect(
      before.length + after.length,
      facts.length,
      reason: 'every fact is one or the other -- no third shape appears',
    );

    // Mondays exist before the staple and STOP at it, inclusive of the staple's
    // own occurrence (the boundary convention: a partitioning staple closes its
    // segment inclusively).
    expect(
      before.length,
      greaterThan(100),
      reason: 'many Monday occurrences precede the inflection',
    );
    final lastMondayDays =
        Rational(daysFromCivil(BigInt.from(2032), 1, 5)) +
        Rational.fromInt(6, 24) +
        Rational.fromInt(15, 1440);
    expect(before.last.day, lastMondayDays, reason: "the last Monday IS the staple's own instant");
    expect(before.last.day, inflectionDays);
    for (final fact in before) {
      expect(fact.day <= inflectionDays, isTrue, reason: 'no Monday occurs after the staple');
    }

    // Thursday lunches exist after the staple and NOT before.
    expect(after, isNotEmpty, reason: 'at least one Thursday lunch projects');
    for (final fact in after) {
      expect(
        fact.day > inflectionDays,
        isTrue,
        reason: 'every Thursday lunch is strictly after the staple',
      );
    }

    // The whole thing is STILL ONE IDENTITY: every fact from both segments names
    // the same pattern, and virtual ids never collide across the boundary.
    // RULED: `fact.event.provenance.pattern` is `Fact.pattern` now -- a typed
    // field on the fact rather than a map dug out of the event's payload, and
    // documented as "ONE provenance for a whole series: every segment's facts
    // name the same pattern, because a rule change is not a new identity". The
    // claim is the same one, asserted where the engine now states it.
    for (final fact in facts) {
      expect(fact.pattern, patternId, reason: 'one identity across the rule change');
    }
    expect(
      {for (final fact in facts) fact.virtualId}.length,
      facts.length,
      reason: 'no two segments ever produce the same virtual id',
    );

    expect(staple.id, isNotEmpty, reason: 'the staple itself is a normal relation record');
    expect(staple.type, 'staple');

    // THE PRECISION-AWARE CLOSE, which is what a person authoring this staple
    // actually types: "at that decision" is a DAY, not an instant. A coordinate
    // at or above the base unit names a PERIOD and closes at that period's last
    // instant, so the 06:15 Monday ON the named date still projects -- a midnight
    // close would silently drop it, which is the off-by-one a user reads as a bug.
    final bare = World();
    bare.staple(
      kind: 'end',
      ends: [
        const StapleEnd.series(patternId),
        StapleEnd.frame(workFrameId, position: Position.coordinate(date(2032, 1, 5))),
      ],
    );
    final closed = bare.occurrences(start: date(2020), end: date(2033));
    expect(
      closed.last.day,
      inflectionDays,
      reason: 'a bare date closes at the last instant of its own day',
    );
    expect(closed.length, before.length, reason: 'the same last Monday, whichever precision');
  });

  // --- Beat 5: the same outcome, authored as a new series instead -----------

  test("Rob-and-John beat 5: 'a new rule, or a new series, on preference' render "
      'the identical occurrence set', () {
    final single = World();
    single.inflect();
    final singleIdentityTimes = times(single.occurrences(start: date(2020), end: date(2033)))
      ..sort();

    // The preference branch: an "end" staple with NO following rule (retiring
    // the original series outright) plus an independently authored second series
    // for the Thursday lunch.
    final split = World();
    split.staple(
      kind: 'end',
      ends: [
        const StapleEnd.series(patternId),
        StapleEnd.frame(workFrameId, position: Position.coordinate(inflectionCoordinate)),
      ],
    );
    split.addThursdaySeries();
    expect(validateDocument(split.document).valid, isTrue);
    final splitFacts = split.occurrences(start: date(2020), end: date(2033));
    final splitTimes = times(splitFacts)..sort();

    expect(
      splitTimes,
      singleIdentityTimes,
      reason: 'on preference -- a real choice, not two different behaviors',
    );

    // But the identity claim genuinely differs, which is the whole reason a
    // preference exists at all: the split version does NOT carry one pattern id.
    expect(
      {for (final fact in splitFacts) fact.pattern},
      {patternId, lunchPatternId},
      reason: 'the split authoring is genuinely two identities',
    );
    expect(
      {for (final fact in single.occurrences(start: date(2020), end: date(2033))) fact.pattern},
      {patternId},
      reason: 'and the single-identity authoring is genuinely one',
    );
  });

  // --- Beat 6: removing the inflection staple restores the original ---------

  test('Rob-and-John beat 6: removing the inflection staple restores the '
      'original indefinite Monday projection, unconditionally', () {
    final world = World();
    final before = times(world.occurrences(start: date(2020), end: date(2033)));

    final staple = world.inflect();
    expect(
      times(world.occurrences(start: date(2020), end: date(2033))),
      isNot(before),
      reason: 'the staple really changed the projection',
    );

    world.document = removeStaple(world.document, staple.id);
    expect(
      times(world.occurrences(start: date(2020), end: date(2033))),
      before,
      reason: 'the full original projection is back, unconditionally',
    );
    expect(validateDocument(world.document).valid, isTrue);

    // The same unconditional claim for the story's OTHER arbitrary-occurrence
    // staple: "stapling an arbitrary occurrence anchors the cycle's phase." It
    // replaces the generator's base for the whole series without rewriting the
    // template, which is exactly what makes removing it restore the original
    // phase for free.
    final phase = world.staple(
      kind: 'phase',
      ends: [
        const StapleEnd.series(patternId),
        StapleEnd.frame(workFrameId, position: Position.coordinate(civil(2026, 1, 7, 6, 15))),
      ],
    );
    final shifted = times(world.occurrences(start: date(2020), end: date(2033)));
    expect(shifted, isNot(before), reason: 'the phase staple moved the whole series');
    expect(
      world.document.relations[templateRelationId]!.coordinate,
      civil(2026, 1, 5, 6, 15),
      reason: 'and it moved it without rewriting the template',
    );
    world.document = removeStaple(world.document, phase.id);
    expect(times(world.occurrences(start: date(2020), end: date(2033))), before);
  });

  // --- Beat 7: the healing invariant holds across a rule change -------------

  test('Rob-and-John beat 7: the healing invariant holds across a rule change '
      '-- a materialized Thursday lunch heals like any occurrence', () {
    final world = World();
    world.inflect();

    final lunchFacts = [
      for (final fact in world.occurrences(start: date(2032), end: date(2033)))
        if (world.durationOf(fact) == oneHour) fact,
    ];
    expect(
      lunchFacts.length,
      greaterThanOrEqualTo(2),
      reason: 'the second segment projects several Thursday lunches',
    );
    final fact = lunchFacts[1];

    final parts = world.materialize(fact);
    final decision = world.decide(parts.override);
    expect(
      decision.healable,
      isTrue,
      reason: 'a no-op materialization in the SECOND segment heals too (${decision.reason})',
    );

    final plan = world.heal.planSeriesHeal();
    expect(plan.healed, 1);
    world.document = applySeriesHeal(world.document, plan);
    expect(world.document.overrides[parts.override], isNull);
    expect(world.document.events[parts.event], isNull);
    expect(world.document.relations[parts.relation], isNull);
    expect(validateDocument(world.document).errors, isEmpty);

    // The projection reasserts: the slot the override was hiding projects again.
    expect(
      [for (final item in world.occurrences(start: date(2032), end: date(2033))) item.virtualId],
      contains(fact.virtualId),
      reason: 'the healed Thursday lunch slot projects once more',
    );
    // Idempotent: the second pass finds nothing left to heal.
    expect(world.heal.planSeriesHeal().healed, 0);
  });

  // --- Beat 8: the healing invariant composes with connections --------------

  test('Rob-and-John beat 8: the healing invariant composes with connections -- '
      "moving a materialized occurrence's end back onto the pattern moves what "
      'is stapled to it', () {
    final world = World();
    final facts = world.occurrences(start: date(2026), end: date(2026, 2, 1));
    final fact = facts[1]; // 2026-01-12, 06:15-06:30

    final parts = world.materialize(fact);
    final trueStartDays =
        Rational(daysFromCivil(BigInt.from(2026), 1, 12)) +
        Rational.fromInt(6, 24) +
        Rational.fromInt(15, 1440);
    final durationDays = world.engine.eventDurationDays(world.document.events[parts.event]);
    expect(durationDays, fifteenMinutes);

    // Deviate the materialized occurrence 20 minutes later -- an authored edit,
    // not yet matching the series (the owner's own "edit then move back... it
    // does not matter" healing case, quoted in series_heal.dart).
    final deviatedStartDays = trueStartDays + Rational.fromInt(20, 1440);
    world.movePlacement(
      parts.relation,
      Json.from(daysToCivilCoordinate(deviatedStartDays).toJson()),
    );
    expect(
      world.decide(parts.override).healable,
      isFalse,
      reason: 'the deviation is not healable yet',
    );

    // A follower event is stapled to the materialized occurrence's end.
    final follower = world.addFollower('Follow-up chat', '10');
    world.staple(
      kind: 'anchor',
      ends: [
        StapleEnd.object(follower),
        StapleEnd.object(parts.event, point: 'end'),
      ],
    );
    expect(validateDocument(world.document).valid, isTrue);

    expect(
      world.extentOf(follower).startDays,
      deviatedStartDays + durationDays,
      reason: "the follower sits at the deviated occurrence's end",
    );

    // Move the occurrence back onto the pattern -- the owner's own healing
    // scenario. The follower has to follow, through the staple, before the heal
    // ever fires.
    world.movePlacement(parts.relation, Json.from(daysToCivilCoordinate(trueStartDays).toJson()));
    expect(
      world.extentOf(follower).startDays,
      trueStartDays + durationDays,
      reason:
          "moving the occurrence's end back onto the pattern moves the follower "
          'with it, through the staple',
    );

    // Back on the pattern the occurrence's own values match again -- but a
    // connection to it is authored content the pattern does not project, and
    // series_heal.dart counts anything the pattern does not project as
    // deviation. So the heal refuses while the follower is stapled to this
    // occurrence's end: healing it away would delete the very point the follower
    // is placed by, which is the asymmetry that module is built on -- a missed
    // heal leaves an extra record, a wrong one destroys authored data.
    final blockedDecision = world.decide(parts.override);
    expect(
      blockedDecision.healable,
      isFalse,
      reason: 'an occurrence something else is stapled to does not heal away underneath it',
    );
    expect(blockedDecision.reason, 'relations deviate from the projection');
    final blocked = world.heal.planSeriesHeal();
    expect(blocked.healed, 0);
    world.document = applySeriesHeal(world.document, blocked);
    expect(world.document.overrides[parts.override], isNotNull, reason: 'the override survives');
    expect(
      world.document.events[parts.event],
      isNotNull,
      reason: 'and so does the occurrence the follower needs',
    );
    expect(
      validateDocument(world.document).valid,
      isTrue,
      reason: 'no dangling connection is ever produced',
    );

    // The refusal is about the connection, not a permanent block: remove the
    // connection and the ordinary healing invariant reasserts unchanged.
    final connection = firstMatch(
      world.document.relations.values,
      (relation) => relation.isStaple && relation.ends.any((end) => end.id == follower),
    )!;
    world.document = removeStaple(world.document, connection.id);
    final freed = world.decide(parts.override);
    expect(freed.healable, isTrue, reason: 'with nothing stapled to it, the override heals again');
    final plan = world.heal.planSeriesHeal();
    expect(plan.healed, 1);
    world.document = applySeriesHeal(world.document, plan);
    expect(world.document.overrides[parts.override], isNull);
    expect(world.document.events[parts.event], isNull);
    expect(validateDocument(world.document).valid, isTrue);

    expect(
      [
        for (final item in world.occurrences(start: date(2026), end: date(2026, 2, 1)))
          item.virtualId,
      ],
      contains(fact.virtualId),
      reason: 'the healed slot projects again, unconditionally',
    );
    // The follower is now genuinely unplaced rather than pointing at a ghost.
    expect(world.extentOf(follower).startDays, isNull);
  });
}
