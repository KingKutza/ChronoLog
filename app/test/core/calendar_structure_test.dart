// Coordinate-structure and frame authoring.
//
// THE LAW IS THE ARBITER, so the central property is a biconditional over random
// ladders: whatever the grid accepts, a real [CoordinateLaw] built from the same
// rungs accepts too. The grid may refuse MORE (a name list whose count is wrong
// for its own meaning is an authoring fault the law never sees), and the test
// counts that it actually exercised all three outcomes rather than passing
// vacuously.
//
// The name-list properties are the "Mon,Tue,Batman" field report as a rule: a
// list is measured against the count ITS OWN MEANING requires -- a cycle's radix,
// a level's radix, or nothing at all when the count varies.

import 'dart:math';

import 'package:chronolog/core/calendar_structure.dart';
import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/eras.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/records.dart';
import 'package:test/test.dart';

import 'corpus.dart';

typedef Attempted<T> = ({T? value, String? refusal});

Attempted<T> _try<T>(T Function() body) {
  try {
    return (value: body(), refusal: null);
  } catch (error) {
    return (value: null, refusal: refusalText(error));
  }
}

const String _alphabet = 'abcdefghijklmnopqrstuvwxyz';

String _name(Random random) =>
    [for (var i = 0; i < 3 + random.nextInt(5); i++) _alphabet[random.nextInt(_alphabet.length)]]
        .join();

/// A count field as an author might type it: a good one, a blank, or one of the
/// three ways it can be wrong.
String _count(Random random) => switch (random.nextInt(8)) {
  0 => '',
  1 => '0',
  2 => '8.5',
  3 => 'twelve',
  _ => '${1 + random.nextInt(30)}',
};

/// The declaration those same rungs make, assembled by hand. Independent of
/// [buildCoordinateStructure] on purpose: it is the other side of the
/// biconditional.
Json _byHand(List<LevelRow> rows, List<CycleRow> cycles) => {
  'kind': 'nested',
  'levels': [
    for (final (index, row) in rows.indexed)
      {
        'name': row.name.trim(),
        if (index > 0) 'within': rows[index - 1].name.trim(),
        if (index > 0 && row.transition.trim().isNotEmpty) 'transition': row.transition.trim(),
        if (index > 0 && row.transition.trim().isEmpty && row.count.trim().isNotEmpty)
          'radix': row.count.trim(),
        if (parseNameList(row.names).isNotEmpty) 'names': parseNameList(row.names),
      },
  ],
  if (cycles.isNotEmpty)
    'cycles': [
      for (final cycle in cycles)
        {
          'name': cycle.name.trim(),
          'radix': cycle.length.trim(),
          'offset': cycle.phase.trim().isEmpty ? '0' : cycle.phase.trim(),
          if (parseNameList(cycle.names).isNotEmpty) 'names': parseNameList(cycle.names),
        },
    ],
};

void main() {
  group('the law is the arbiter', () {
    test('random ladders: whatever the grid accepts, the law accepts', () {
      var accepted = 0, gridOnly = 0, both = 0;
      for (final seed in seeds(80)) {
        final random = Random(seed);
        final depth = 1 + random.nextInt(5);
        final names = <String>[];
        while (names.length < depth) {
          final next = _name(random);
          if (!names.contains(next)) names.add(next);
        }
        final transitions = ['', ...registeredTransitions(), 'julian.months'];
        final rows = <LevelRow>[
          for (final (index, name) in names.indexed)
            (
              name: name,
              count: index == 0 ? '' : _count(random),
              transition: index == 0 || random.nextInt(4) != 0
                  ? ''
                  : transitions[random.nextInt(transitions.length)],
              names: '',
            ),
        ];
        final cycles = <CycleRow>[
          if (random.nextBool())
            (
              name: _name(random),
              length: '${1 + random.nextInt(9)}',
              phase: '${random.nextInt(9) - 4}',
              names: '',
            ),
        ];
        final grid = _try(() => buildCoordinateStructure(levels: rows, cycles: cycles));
        final hand = _try(() => CoordinateLaw.parse(_byHand(rows, cycles)));
        if (grid.value != null) {
          accepted += 1;
          expect(
            hand.refusal,
            isNull,
            reason: 'seed $seed: the grid accepted a ladder the law refuses',
          );
          // And the thing it returned is itself constructible, every time.
          expect(_try(() => CoordinateLaw.parse(grid.value)).refusal, isNull, reason: 'seed $seed');
          expect(CoordinateLaw.parse(grid.value).levelNames(), names, reason: 'seed $seed');
        } else if (hand.refusal == null) {
          gridOnly += 1;
        } else {
          both += 1;
        }
      }
      // All three outcomes actually happened, so none of the branches above was
      // dead.
      expect(accepted, greaterThan(0));
      expect(gridOnly, greaterThan(0), reason: 'the grid refuses more');
      expect(both, greaterThan(0), reason: 'law refusals propagate');
    });

    test('RULED ANCHOR: an unresolvable ladder is refused at authoring time', () {
      final document = createEmptyWorkspaceDocument();
      final laws = CoordinateLaws();
      final rows = editableCoordinateStructure(laws.of(document.toJson(), 'frame:wall-time'))!;
      expect(
        _try(
          () => buildCoordinateStructure(
            levels: [
              for (final level in rows.levels)
                if (level.name == 'month')
                  (
                    name: level.name,
                    count: level.count,
                    transition: 'julian.months',
                    names: level.names,
                  )
                else
                  level,
            ],
            cycles: rows.cycles,
          ),
        ).refusal,
        contains('nothing implements'),
      );
      expect(
        _try(
          () => buildCoordinateStructure(
            levels: [
              for (final level in rows.levels)
                if (level.name == 'hour')
                  (name: level.name, count: '0', transition: '', names: level.names)
                else
                  level,
            ],
          ),
        ).refusal,
        contains('positive whole number'),
      );
      expect(_try(() => buildCoordinateStructure()).refusal, contains('needs at least one level'));
      expect(
        _try(
          () => buildCoordinateStructure(
            levels: const [
              (name: 'year', count: '', transition: '', names: ''),
              (name: 'YEAR', count: '4', transition: '', names: ''),
            ],
          ),
        ).refusal,
        contains('declared twice'),
      );
      expect(
        _try(
          () => buildCoordinateStructure(
            levels: const [
              (name: 'year', count: '', transition: '', names: ''),
              (name: 'not a name!', count: '4', transition: '', names: ''),
            ],
          ),
        ).refusal,
        contains('simple name'),
      );
      expect(
        _try(
          () => buildCoordinateStructure(
            levels: [
              for (final level in rows.levels)
                if (level.name == 'day')
                  (name: level.name, count: '31', transition: 'gregorian.days', names: '')
                else
                  level,
            ],
          ),
        ).refusal,
        contains('one or the other'),
      );
    });
  });

  group('a list is measured against its own meaning', () {
    test('random name lists: right count passes, wrong count states both', () {
      for (final seed in seeds(60)) {
        final random = Random(seed);
        final required = 1 + random.nextInt(12);
        final unit = _name(random);
        final given = 1 + random.nextInt(12);
        final list = [for (var i = 0; i < given; i++) _name(random)];
        final attempt = _try(() => validateNameList(list, required, '$unit names', unit));
        if (given == required) {
          expect(attempt.value, list, reason: 'seed $seed');
        } else {
          // BOTH numbers, and the unit named: an author cannot correct a
          // mismatch that is never shown to them.
          expect(attempt.refusal, contains('$required name'), reason: 'seed $seed');
          expect(attempt.refusal, contains('$given '), reason: 'seed $seed');
          expect(attempt.refusal, contains(unit), reason: 'seed $seed');
        }
        // A count that VARIES cannot be named one at a time at all, and the
        // refusal says what to do instead.
        final varies = _try(() => validateNameList(list, null, '$unit names', unit));
        expect(varies.refusal, contains('varies in number'));
        expect(varies.refusal, contains('cycle'));
        // An empty list is not an authoring claim, so it is never measured.
        expect(validateNameList(const [], null, 'anything'), isEmpty);
        expect(validateNameList(const [], 7, 'anything'), isEmpty);
      }
    });

    test('RULED ANCHOR: the wording states both counts and names the unit', () {
      expect(
        _try(() => validateNameList(['one', 'two'], 8, 'month names', 'month')).refusal,
        'month names needs 8 names, one for each month; 2 were given.',
      );
      expect(
        _try(() => validateNameList(['one'], 2, 'month names', 'month')).refusal,
        'month names needs 2 names, one for each month; 1 was given.',
      );
      // A repeated name is accepted: distinctness is not authoring's job.
      expect(validateNameList(['Mon', 'mon'], 2, 'weekday names', 'weekday'), ['Mon', 'mon']);
    });

    test('the parser takes the author typing, not a canonical form', () {
      expect(parseNameList('a, ,b,,c , '), ['a', 'b', 'c']);
      expect(parseNameList(['a', ' b ']), ['a', 'b']);
      expect(parseNameList(null), isEmpty);
      expect(parseNameList(''), isEmpty);
      expect(parseNameList(' Mon , Tue , Batman , Thu , Fri , Sat , Sun , '), [
        'Mon',
        'Tue',
        'Batman',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ]);
    });

    test('the count a level requires comes from its own edge', () {
      // A fixed radix answers with itself.
      expect(requiredNameCount(name: 'month', count: '8'), 8);
      // A transition whose mean is a whole number answers with it; one whose
      // count genuinely varies answers null, which is what refuses the list.
      expect(requiredNameCount(name: 'month', transition: 'gregorian.months'), 12);
      expect(requiredNameCount(name: 'day', transition: 'gregorian.days'), isNull);
      expect(requiredNameCount(name: 'day', transition: countVaries), isNull);
      expect(requiredNameCount(name: 'day'), isNull);
    });
  });

  group('a week is a cycle, not a level', () {
    test('RULED ANCHOR: seven weekday names are accepted and take effect', () {
      var document = createEmptyWorkspaceDocument();
      final laws = CoordinateLaws();
      final rows = editableCoordinateStructure(laws.of(document.toJson(), 'frame:wall-time'))!;
      expect(rows.cycles.map((cycle) => cycle.name), ['weekday']);
      expect(rows.cycles.first.length, '7');
      expect(rows.cycles.first.phase, '4');

      final built = buildCoordinateStructure(
        levels: rows.levels,
        cycles: [
          (
            name: 'weekday',
            length: '7',
            phase: rows.cycles.first.phase,
            names: 'Mon,Tue,Batman,Thu,Fri,Sat,Sun',
          ),
        ],
        kind: rows.kind,
        previous: document.frames['frame:wall-time']!.coordinate,
      );
      document = document.put(
        'frames',
        'frame:wall-time',
        document.frames['frame:wall-time']!.withField('coordinate', built),
      );
      final law = CoordinateLaws().of(document.toJson(), 'frame:wall-time');
      expect(law.weekdayNames(), ['Mon', 'Tue', 'Batman', 'Thu', 'Fri', 'Sat', 'Sun']);
      // Day 5 sits at cycle index (5 + 4) mod 7 = 2, the position renamed.
      expect(law.weekdayLabel(Rational(BigInt.from(5))), 'Batman');
      expect(
        law.weekdayLabel(Rational(BigInt.from(3))),
        'Mon',
        reason: 'the phase is data, so the rest of the list stays put',
      );
    });

    test('RULED ANCHOR: naming the days inside a month is refused as such', () {
      final document = createEmptyWorkspaceDocument();
      final rows = editableCoordinateStructure(
        CoordinateLaws().of(document.toJson(), 'frame:wall-time'),
      )!;
      final refusal = _try(
        () => buildCoordinateStructure(
          levels: [
            for (final level in rows.levels)
              if (level.name == 'day')
                (
                  name: level.name,
                  count: level.count,
                  transition: level.transition,
                  names: 'Mon,Tue,Batman,Thu,Fri,Sat,Sun',
                )
              else
                level,
          ],
          cycles: rows.cycles,
        ),
      ).refusal;
      // NOT "you have to define the same number of days" -- a count the author
      // can never satisfy. The refusal says the count varies, and says what to
      // author instead.
      expect(refusal, contains('varies in number'));
      expect(refusal, contains('cycle'));
      expect(refusal, isNot(contains('needs 31')));
    });

    test('a cycle refuses a bad length, a bad phase, and a bad name list', () {
      final level = const [(name: 'day', count: '', transition: '', names: '')];
      expect(
        _try(
          () => buildCoordinateStructure(
            levels: level,
            cycles: const [(name: 'weekday', length: '7', phase: '0', names: 'Mon,Tue,Wed')],
          ),
        ).refusal,
        contains('needs 7 names'),
      );
      expect(
        _try(
          () => buildCoordinateStructure(
            levels: level,
            cycles: const [(name: 'weekday', length: '7', phase: 'half', names: '')],
          ),
        ).refusal,
        contains('whole number of units'),
      );
      expect(
        _try(
          () => buildCoordinateStructure(
            levels: level,
            cycles: const [(name: 'weekday', length: '0', phase: '0', names: '')],
          ),
        ).refusal,
        contains('positive whole number'),
      );
      expect(
        _try(
          () => buildCoordinateStructure(
            levels: level,
            cycles: const [(name: '7 days!', length: '7', phase: '0', names: '')],
          ),
        ).refusal,
        contains('simple name'),
      );
    });
  });

  group('the declaration editor', () {
    test('RULED ANCHOR: Wall Time round-trips through the grid unchanged', () {
      final document = createEmptyWorkspaceDocument();
      final law = CoordinateLaws().of(document.toJson(), 'frame:wall-time');
      final rows = editableCoordinateStructure(law)!;
      expect(rows.levels.map((level) => level.name), [
        'year',
        'month',
        'day',
        'hour',
        'minute',
        'second',
        'subsecond',
      ]);
      expect(rows.levels.firstWhere((level) => level.name == 'hour').count, '24');
      expect(
        rows.levels.firstWhere((level) => level.name == 'month').transition,
        'gregorian.months',
      );
      expect(
        rows.levels.firstWhere((level) => level.name == 'month').names,
        startsWith('January, February'),
      );
      // A level whose count comes from a transition reads back as "varies", not
      // as a blank the author might fill in with a lie.
      expect(rows.levels.firstWhere((level) => level.name == 'day').transition, 'gregorian.days');

      final rebuilt = buildCoordinateStructure(
        levels: rows.levels,
        cycles: rows.cycles,
        baseLevel: rows.baseLevel,
        origin: rows.origin,
        kind: rows.kind,
        previous: document.frames['frame:wall-time']!.coordinate,
      );
      expect(CoordinateLaw.parse(rebuilt).levelNames(), law.levelNames());
      expect((rebuilt['cycles'] as List).length, 1);
      expect(coordinateStructureSummary(rebuilt), contains('One year = 146097/400 days'));
    });

    test('every registered transition is offered, plus the fixed-count option', () {
      final choices = transitionChoices();
      expect(choices.first.value, '');
      expect(choices.first.label, 'Fixed count');
      expect(choices.skip(1).map((choice) => choice.value), registeredTransitions());
      for (final choice in choices.skip(1)) {
        expect(choice.label, contains(choice.value));
        expect(choice.label, contains(transitionDefinition(choice.value)!.summary));
      }
    });

    test('RULED ANCHOR: baseLevel and origin ride for an invented uniform ladder', () {
      final built = buildCoordinateStructure(
        levels: const [
          (name: 'year', count: '', transition: '', names: ''),
          (name: 'month', count: '12', transition: '', names: ''),
          (name: 'day', count: '30', transition: '', names: ''),
        ],
        baseLevel: 'day',
        origin: '0',
      );
      expect(built['baseLevel'], 'day');
      expect(built['origin'], const {'days': '0'});
      final law = CoordinateLaw.parse(built, frameId: 'uniform');
      expect(law.positional, isTrue);
      expect(law.baseLevel, 'day');

      // Blank fields are OMITTED, never stored empty, so a document that never
      // authored either stays byte-identical to one that still doesn't.
      final rows = editableCoordinateStructure(law)!;
      expect(rows.baseLevel, 'day');
      expect(rows.origin, '0');
      final without = buildCoordinateStructure(levels: rows.levels, kind: rows.kind);
      expect(without.containsKey('baseLevel'), isFalse);
      expect(without.containsKey('origin'), isFalse);
      expect(without.containsKey('cycles'), isFalse);
    });

    test('a key the grid never heard of survives an edit untouched', () {
      final previous = <String, dynamic>{
        'kind': 'nested',
        'levels': const [
          {'name': 'age'},
        ],
        'x-authored-by': 'the author',
        // The `fixed` block is where the frozen declaration layer reads the atom
        // and epoch from, so an edit here must not quietly change either.
        'fixed': const {'smallestUnitDays': '2', 'epochDays': '11'},
      };
      final built = buildCoordinateStructure(
        levels: const [
          (name: 'age', count: '', transition: '', names: ''),
          (name: 'beat', count: '9', transition: '', names: ''),
        ],
        previous: previous,
      );
      expect(built['x-authored-by'], 'the author');
      expect(built['fixed'], previous['fixed']);
      final law = CoordinateLaw.parse(built);
      expect(law.atomDays, Rational(BigInt.two));
      expect(law.epochDays, Rational(BigInt.from(11)));
    });

    test('editableCoordinateStructure answers null for no law at all', () {
      expect(editableCoordinateStructure(null), isNull);
    });

    test('a summary describes what a declaration adds up to', () {
      expect(
        coordinateStructureSummary(const {
          'kind': 'nested',
          'levels': [
            {'name': 'year'},
            {'name': 'month', 'within': 'year', 'radix': '8'},
            {'name': 'day', 'within': 'month', 'radix': '8'},
          ],
          'baseLevel': 'day',
          'origin': {'days': '0'},
        }),
        'One year = 64 days (64). 8 month per year 8 day per month',
      );
      expect(coordinateStructureSummary(const {}), 'No levels declared.');
    });
  });

  group('frame authoring', () {
    test('RULED ANCHOR: structure authoring follows the coordinate capability', () {
      // `frame:wall-time` is a LINE and is the frame every derived calendar
      // inherits its structure from. Gating on "calendar" withheld the whole
      // surface from it.
      expect(
        frameAuthoringCapabilities('line', const [
          'line',
          'temporal',
          'gregorian',
        ]).calendarStructure,
        isTrue,
      );
      expect(frameAuthoringCapabilities('measure', const ['measure']).calendarStructure, isTrue);
      expect(frameAuthoringCapabilities('cycle').calendarStructure, isTrue);
      expect(frameAuthoringCapabilities('line').coordinate, isTrue);
      // A group owns no coordinate, so it authors no structure.
      expect(frameAuthoringCapabilities('group').calendarStructure, isFalse);
      expect(frameAuthoringCapabilities('importance').calendarStructure, isFalse);
    });

    test('structure authoring and the coordinate capability never disagree', () {
      for (final seed in seeds(30)) {
        final random = Random(seed);
        final kinds = [...traitsByFrameKind.keys, _name(random)];
        final kind = kinds[random.nextInt(kinds.length)];
        final traits = [
          for (var i = 0; i < random.nextInt(4); i++)
            random.nextBool() ? kinds[random.nextInt(kinds.length)] : _name(random),
        ];
        final can = frameAuthoringCapabilities(kind, traits);
        expect(can.calendarStructure, can.coordinate, reason: 'seed $seed');
        expect(can.basis, can.coordinate, reason: 'seed $seed');
        // Observed boundaries and period data are narrower claims, never wider.
        if (can.observedBoundaries || can.periodData) {
          expect(can.coordinate, isTrue, reason: 'seed $seed');
        }
      }
    });

    test('observed boundaries and period data follow what a frame IS', () {
      expect(frameAuthoringCapabilities('cycle').observedBoundaries, isTrue);
      expect(frameAuthoringCapabilities('calendar').observedBoundaries, isTrue);
      expect(frameAuthoringCapabilities('line').observedBoundaries, isFalse);
      expect(
        frameAuthoringCapabilities('group', const ['set', 'group', 'cycle']).observedBoundaries,
        isTrue,
      );
      expect(frameAuthoringCapabilities('other').periodData, isTrue);
      expect(frameAuthoringCapabilities('measure').periodData, isFalse);
    });

    test('traits are ADDITIVE: nothing a frame already carried is dropped', () {
      for (final seed in seeds(30)) {
        final random = Random(seed);
        final existing = [for (var i = 0; i < random.nextInt(6); i++) _name(random)];
        final entered = [for (var i = 0; i < random.nextInt(3); i++) _name(random)];
        final kinds = [...traitsByFrameKind.keys, _name(random)];
        final kind = kinds[random.nextInt(kinds.length)];
        final result = additiveFrameTraits(kind, entered, existing);
        for (final trait in [...existing, ...entered, ...?traitsByFrameKind[kind]]) {
          expect(result, contains(trait), reason: 'seed $seed');
        }
        expect(result.toSet(), hasLength(result.length), reason: 'no duplicates');
        expect(result, isNot(contains('')));
      }
    });

    test('RULED ANCHOR: an edit preserves composable traits in order', () {
      expect(
        additiveFrameTraits(
          'group',
          const ['group'],
          const ['set', 'calendar', 'line', 'cycle', 'custom-law'],
        ),
        ['set', 'calendar', 'line', 'cycle', 'custom-law', 'group'],
      );
    });
  });
}
