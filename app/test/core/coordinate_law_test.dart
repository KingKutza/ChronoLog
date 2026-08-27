// The spec is generative (Don, 2026-08-27): "we should never be testing for a
// specific case, we should be testing for a general case… randint generate a
// random non-Gregorian frame, does it take events, pass." Every assertion below
// is a property quantified over seeded random generation, EXCEPT the ones
// labelled RULED ANCHOR — asserted law (an epoch's phase, a refusal's exact
// sentence, a fixture's own numbers) that cannot be derived from a property.
//
// The seed is fixed so a failure reproduces exactly. Change it only to widen
// coverage deliberately, never to make a red suite green.
//
// ORDERING NOTE: the registry is process-global by design (it is the extension
// seam a new calendar family is added through). The one test that registers an
// extra family is declared LAST, and the test that pins the registered set
// exactly is declared FIRST, so the two do not fight. Do not run this file with
// --test-randomize-ordering-seed.

import 'dart:math';

import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/eras.dart';
import 'package:chronolog/core/exact.dart';
import 'package:test/test.dart';

const specSeed = 20260827;
const iterations = 120;

// --- Generators --------------------------------------------------------------

const _alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

/// Level, cycle and era names are OPEN user vocabulary, so the generator invents
/// its own alphabet rather than drawing from a fixed list: nothing in the law may
/// depend on a name it recognizes.
String _word(Random r, Set<String> used) {
  while (true) {
    final length = 3 + r.nextInt(6);
    final word = [
      for (var index = 0; index < length; index += 1) _alphabet[r.nextInt(_alphabet.length)],
    ].join();
    if (used.add(word.toLowerCase())) return word;
  }
}

/// A random radix ladder: random depth, random radices, random level names, a
/// random base level, a random origin, and sometimes an authored atom length.
/// Every non-root level carries a radix, so the ladder has no continuous tail and
/// its arithmetic is exactly invertible.
class _Ladder {
  _Ladder(this.names, this.radices, this.baseIndex, this.originDays, this.atomDays);

  factory _Ladder.random(Random r) {
    final depth = 2 + r.nextInt(4);
    final used = <String>{};
    final names = [for (var index = 0; index < depth; index += 1) _word(r, used)];
    return _Ladder(
      names,
      [BigInt.one, for (var index = 1; index < depth; index += 1) BigInt.from(2 + r.nextInt(39))],
      1 + r.nextInt(depth - 1),
      '${r.nextInt(4001) - 2000}',
      r.nextBool() ? null : '1/${1 + r.nextInt(100)}',
    );
  }

  final List<String> names;
  final List<BigInt> radices;
  final int baseIndex;
  final String originDays;
  final String? atomDays;

  Map<String, Object?> get json => {
    'kind': 'nested',
    'origin': {'days': originDays},
    'baseLevel': names[baseIndex],
    if (atomDays != null) 'atomDays': atomDays,
    'levels': [
      for (final (index, name) in names.indexed)
        {
          'name': name,
          if (index > 0) 'within': names[index - 1],
          if (index > 0) 'radix': '${radices[index]}',
        },
    ],
  };

  /// A value in range for every rung: the root is unbounded, rungs at or above
  /// the base are one-based, and rungs below it are zero-based offsets inside
  /// their parent.
  Coordinate coordinate(Random r) => Coordinate.of([
    for (final (index, name) in names.indexed)
      (
        name,
        index == 0
            ? '${r.nextInt(2001) - 1000}'
            : index <= baseIndex
            ? '${1 + r.nextInt(radices[index].toInt())}'
            : '${r.nextInt(radices[index].toInt())}',
      ),
  ]);
}

/// The registered civil ladder with its unit counts parameterized. Editing
/// `hoursPerDay` is exactly the edit the field report named ("Hour:Day:23").
Map<String, Object?> _civilLadder({
  int hoursPerDay = 24,
  int minutesPerHour = 60,
  int secondsPerMinute = 60,
  bool subsecond = true,
}) => {
  'kind': 'gregorian',
  'levels': [
    {'name': 'year'},
    {'name': 'month', 'within': 'year', 'transition': 'gregorian.months'},
    {'name': 'day', 'within': 'month', 'transition': 'gregorian.days'},
    {'name': 'hour', 'within': 'day', 'radix': '$hoursPerDay'},
    {'name': 'minute', 'within': 'hour', 'radix': '$minutesPerHour'},
    {'name': 'second', 'within': 'minute', 'radix': '$secondsPerMinute'},
    if (subsecond) {'name': 'subsecond', 'within': 'second'},
  ],
};

Coordinate _civil(int year, int month, int day, [int? hour, int? minute, int? second]) =>
    Coordinate.of([
      ('year', year),
      ('month', month),
      ('day', day),
      ('hour', hour),
      ('minute', minute),
      ('second', second),
    ]);

/// A random era table: random count, random directions, random spans, random
/// names, a random anchor inside a randomly chosen era. Openness is generated
/// only where the law permits it — descending first, ascending last — because an
/// open era in the middle is a refusal, tested separately.
Map<String, Object?> _randomEraTable(Random r) {
  final count = 1 + r.nextInt(5);
  final used = <String>{};
  final entries = <Map<String, Object?>>[];
  final descendingFirst = count > 1 && r.nextBool();
  final openLast = r.nextBool();
  for (var index = 0; index < count; index += 1) {
    final descending = index == 0 && descendingFirst;
    final open = descending ? r.nextBool() : (index == count - 1 && openLast);
    entries.add({
      'name': '${_word(r, used)} Era',
      'key': _word(r, used),
      'direction': descending ? 'descending' : 'ascending',
      'firstYear': '${r.nextInt(3)}',
      'years': open ? 'open' : '${1 + r.nextInt(3000)}',
      if (r.nextBool()) 'affix': 'suffix',
    });
  }
  final anchored = entries[r.nextInt(count)];
  final firstYear = int.parse('${anchored['firstYear']}');
  final span = anchored['years'] == 'open' ? 20 : int.parse('${anchored['years']}');
  return {
    'anchor': {
      'era': anchored['key'],
      'year': '${firstYear + r.nextInt(span)}',
      'properYear': '${r.nextInt(8001) - 4000}',
    },
    'entries': entries,
  };
}

// --- Helpers ----------------------------------------------------------------

void expectRefusal(void Function() body, Pattern sentence, {String? reason}) {
  expect(
    body,
    throwsA(predicate<Object>((error) => refusalText(error).contains(sentence))),
    reason: reason ?? 'expected a refusal matching $sentence',
  );
}

Map<String, Object?> _document(Map<String, Map<String, Object?>> frames) => {
  'frames': {for (final entry in frames.entries) entry.key: entry.value},
};

// --- The registry -----------------------------------------------------------

void main() {
  test('RULED ANCHOR: the registry holds exactly the standard entries, and an '
      'unregistered calendar is refused rather than computed as Gregorian', () {
    // Declared first on purpose — see the ORDERING NOTE at the top of the file.
    expect(registeredTransitions(), ['gregorian.days', 'gregorian.daysInYear', 'gregorian.months']);
    expect(registeredCalendars(), [gregory]);
    // RFC 7529's own text is inconsistent about GREGORY vs GREGORIAN, so both
    // resolve; nothing else does.
    expect(lawForCalendar('gregory'), same(lawForCalendar('GREGORIAN')));
    expect(lawForCalendar('gregory')!.unitsPer('hour'), Rational.fromInt(24));
    expect(gregorianLaw.calendarScale(), gregory);
  });

  test('a calendar nothing has registered resolves to no law, whatever it is '
      'called', () {
    final r = Random(specSeed);
    final used = <String>{'gregory', 'gregorian'};
    for (var index = 0; index < iterations; index += 1) {
      final name = _word(r, used);
      expect(lawForCalendar(name), isNull, reason: name);
      expect(calendarFamily(name), isNull, reason: name);
    }
    expect(lawForCalendar(''), isNull);
    expect(lawForCalendar(null), isNull);
  });

  test('a transition string nothing implements is refused with the frame, the '
      'offending name, and the alternatives', () {
    final r = Random(specSeed + 1);
    final used = <String>{'gregorian.days', 'gregorian.daysInYear', 'gregorian.months'};
    for (var index = 0; index < iterations; index += 1) {
      final invented = '${_word(r, used)}.months';
      expectRefusal(
        () => CoordinateLaw.parse({
          'kind': 'gregorian',
          'levels': [
            {'name': 'year'},
            {'name': 'month', 'within': 'year', 'transition': invented},
          ],
        }, frameId: 'frame:$index'),
        RegExp(
          'Frame frame:$index.*${RegExp.escape(invented)}.*nothing implements'
          '.*gregorian\\.months',
        ),
      );
    }
  });

  test('a ladder its own family cannot execute is a refusal, never a guess', () {
    // Only "year > month > day", "year > month", "year > day-of-year" and a bare
    // year are Gregorian ladders. Any other arrangement of the same transitions
    // is a different calendar, and inventing a conversion for it is exactly the
    // silent wrongness the registry removes.
    expectRefusal(
      () => CoordinateLaw.parse({
        'kind': 'gregorian',
        'levels': [
          {'name': 'year'},
          {'name': 'day', 'within': 'year', 'transition': 'gregorian.days'},
        ],
      }),
      'cannot execute the level ladder',
    );
  });

  // --- Bottom-up composition ------------------------------------------------

  test('unit magnitudes compose bottom-up: a level is worth the product of the '
      'radices beneath it, over random ladders', () {
    final r = Random(specSeed + 2);
    for (var index = 0; index < iterations; index += 1) {
      final ladder = _Ladder.random(r);
      final law = CoordinateLaw.parse(ladder.json, frameId: 'frame:$index');
      expect(law.atomLevel, ladder.names.last);
      expect(
        law.atomDays,
        ladder.atomDays == null ? Rational.one : Rational.parse(ladder.atomDays!),
      );
      for (var rung = 0; rung < ladder.names.length; rung += 1) {
        var product = Rational.one;
        for (var below = rung + 1; below < ladder.names.length; below += 1) {
          product *= Rational(ladder.radices[below]);
        }
        expect(law.unitAtoms(ladder.names[rung]), product, reason: ladder.names[rung]);
        expect(law.unitDays(ladder.names[rung]), product * law.atomDays);
      }
      // The base unit's length is composed, never assumed to be one day.
      expect(law.baseDays, law.unitDays(ladder.names[ladder.baseIndex]));
      expect(law.baseAtoms, law.unitAtoms(ladder.names[ladder.baseIndex]));
    }
  });

  test('random radix ladders round-trip toDays/fromDays exactly, in both '
      'directions', () {
    final r = Random(specSeed + 3);
    for (var index = 0; index < iterations; index += 1) {
      final ladder = _Ladder.random(r);
      final law = CoordinateLaw.parse(ladder.json, frameId: 'frame:$index');
      expect(law.positional, isTrue, reason: 'a uniform ladder with an origin');
      // Coordinate out and back.
      final value = ladder.coordinate(r);
      final days = law.toDays(value);
      final back = law.fromDays(days);
      expect(law.toDays(back), days);
      final belowSignificant = [
        for (var rung = ladder.baseIndex + 1; rung < ladder.names.length; rung += 1)
          value.value(ladder.names[rung]),
      ].any((text) => text != '0');
      if (belowSignificant) {
        expect(back, value, reason: 'every rung comes back as authored');
      } else {
        // Midnight stays a bare date: the below-base rungs are omitted when they
        // are all zero, which is the shape every stored document expects.
        expect(back.levelNames(), ladder.names.sublist(0, ladder.baseIndex + 1));
        for (var rung = 0; rung <= ladder.baseIndex; rung += 1) {
          expect(back.value(ladder.names[rung]), value.value(ladder.names[rung]));
        }
      }
      // Day ordinal out and back, on the ladder's own atom grid.
      final ordinal =
          Rational.parse(ladder.originDays) +
          Rational(BigInt.from(r.nextInt(400001) - 200000)) * law.atomDays;
      expect(law.toDays(law.fromDays(ordinal)), ordinal);
    }
  });

  test('a random 23-to-30-hour day changes what one hour is worth everywhere at '
      'once, and never changes the hour itself', () {
    final r = Random(specSeed + 4);
    for (var index = 0; index < iterations; index += 1) {
      final hours = 20 + r.nextInt(11);
      final minutes = 2 + r.nextInt(90);
      final seconds = 2 + r.nextInt(90);
      final law = CoordinateLaw.parse(
        _civilLadder(hoursPerDay: hours, minutesPerHour: minutes, secondsPerMinute: seconds),
        frameId: 'frame:wall-$index',
      );
      // Owner ruling: "I did not change the lenght of an hour I changed the
      // length of a day." A radix is a statement about the unit ABOVE it, so the
      // hour's own length is a function of what is beneath it and nothing else.
      final second = Rational.fromInt(1, 86400);
      expect(law.unitDays('second'), second);
      expect(law.unitDays('minute'), second * Rational.fromInt(seconds));
      expect(law.unitDays('hour'), second * Rational.fromInt(seconds * minutes));
      // ...and the DAY is however many of those hours the author wrote.
      expect(law.unitDays('day'), law.unitDays('hour')! * Rational.fromInt(hours));
      // Changing only the day radix moves the day and nothing below it.
      final other = CoordinateLaw.parse(
        _civilLadder(hoursPerDay: hours + 1, minutesPerHour: minutes, secondsPerMinute: seconds),
      );
      expect(other.unitDays('hour'), law.unitDays('hour'));
      expect(other.unitDays('minute'), law.unitDays('minute'));
      expect(other.unitDays('day'), isNot(law.unitDays('day')));

      // The per-day counts fall out of the shortened day rather than out of
      // fattened parts, through the one accessor that replaced six wrappers.
      expect(law.unitsPer('hour'), Rational.fromInt(hours));
      expect(law.unitsPer('minute'), Rational.fromInt(hours * minutes));
      expect(law.unitsPer('second'), Rational.fromInt(hours * minutes * seconds));
      expect(law.unitsPer('minute', 'hour'), Rational.fromInt(minutes));
      expect(law.unitsPer('second', 'minute'), Rational.fromInt(seconds));

      // Duration magnitudes agree, or the same event is two different lengths in
      // two different lenses.
      expect(law.magnitudeDays(Coordinate.of([('hour', 1)])), law.unitDays('hour'));
      expect(law.magnitudeDays(Coordinate.of([('day', 1)])), law.unitDays('day'));
      expect(
        law.magnitudeDays(Coordinate.of([('minute', 3), ('second', 2)])),
        law.unitDays('minute')! * Rational.fromInt(3) +
            law.unitDays('second')! * Rational.fromInt(2),
      );

      // Conversion, stated as differences because the absolute position of a
      // given day now drifts: twelve hours in is twelve of THIS law's hours in,
      // and successive day boundaries are one of THIS law's days apart.
      final midnight = law.toDays(_civil(2026, 8, 20, 0, 0, 0));
      final twelve = law.toDays(_civil(2026, 8, 20, 12, 0, 0));
      expect(twelve - midnight, law.unitDays('hour')! * Rational.fromInt(12));
      expect(law.toDays(_civil(2026, 8, 21, 0, 0, 0)) - midnight, law.unitDays('day'));
      expect(law.fromDays(twelve), _civil(2026, 8, 20, 12, 0, 0));
      // MIDNIGHT DRIFT: the frame's day N sits at N of its own days, so an edited
      // day length necessarily slides against the standard calendar.
      expect(midnight, civilCoordinateToDays(_civil(2026, 8, 20)) * law.unitDays('day')!);
      // The DATE ladder is still Gregorian, so the rule stays ICS-expressible
      // even though the instants it names are not standard instants.
      expect(law.calendarScale(), gregory);
    }
  });

  test('RULED ANCHOR: the registered Gregorian means are exact, and a variable '
      'level reports no constant length at all', () {
    expect(gregorianLaw.meanMonthDays(), Rational.parse('48699/1600'));
    expect(gregorianLaw.meanMonthDays().toDouble(), 30.436875);
    expect(gregorianLaw.meanUnitDays('year'), Rational.parse('146097/400'));
    expect(
      gregorianLaw.unitDays('month'),
      isNull,
      reason: 'a month has no constant length and must not pretend to',
    );
    expect(gregorianLaw.unitDays('day'), Rational.one);
    expect(gregorianLaw.unitDays('hour'), Rational.parse('1/24'));
    expect(gregorianLaw.unitDays('minute'), Rational.parse('1/1440'));
    expect(gregorianLaw.unitDays('second'), Rational.parse('1/86400'));
    expect(gregorianLaw.unitsPer('day', 'week'), Rational.fromInt(7));
    // A week is not a declared level, so it resolves through the registered
    // standard table and is seven STANDARD days.
    expect(gregorianLaw.magnitudeDays(Coordinate.of([('week', 2)])), Rational.fromInt(14));
  });

  test('RULED ANCHOR: the standard boundary is exact in both directions and '
      'keeps a bare date bare', () {
    final noon = civilCoordinateToDays(_civil(2026, 8, 20, 12, 0, 0));
    expect(noon - Rational(noon.floor()), Rational.parse('1/2'));
    expect(daysToCivilCoordinate(noon), _civil(2026, 8, 20, 12, 0, 0));
    final bare = Coordinate.of([('year', 2026), ('month', 8), ('day', 20)]);
    expect(daysToCivilCoordinate(civilCoordinateToDays(bare)), bare);
    expect(formatCivil(daysToCivilCoordinate(noon), includeTime: true), '2026-08-20 12:00:00');
  });

  test('the standard boundary round-trips every random civil instant, and the '
      'continuous tail carries whatever the second grid cannot', () {
    final r = Random(specSeed + 5);
    for (var index = 0; index < iterations; index += 1) {
      final onGrid =
          Rational(BigInt.from(r.nextInt(2000001) - 1000000)) * Rational.fromInt(1, 86400);
      final resolved = daysToCivilCoordinate(onGrid);
      expect(civilCoordinateToDays(resolved), onGrid);
      expect(resolved.has('subsecond'), isFalse, reason: 'nothing is left over');
      // Off the grid, the tail appears and carries the residue to its documented
      // twelve places — a truncation bound of the tail itself, not of the ladder.
      final offGrid = onGrid + Rational.fromInt(1, 3) * Rational.fromInt(1, 86400);
      final tailed = daysToCivilCoordinate(offGrid);
      expect(tailed.has('subsecond'), isTrue);
      expect(
        (civilCoordinateToDays(tailed) - offGrid).abs() <
            Rational.fromInt(1, 86400) * Rational.parse('1/1000000000'),
        isTrue,
      );
    }
  });

  // --- Cycles ---------------------------------------------------------------

  test('RULED ANCHOR: day zero is a Thursday, which is the phase the shipped '
      'weekday derivation carried as a literal', () {
    expect(gregorianLaw.cycleIndex('weekday', Rational.zero), 4);
    expect(gregorianLaw.weekdayLabel(Rational.zero), 'Thursday');
    expect(gregorianLaw.weekdayLabel(Rational.fromInt(3)), 'Sunday');
    expect(gregorianLaw.monthNames()!.first, 'January');
    expect(gregorianLaw.weekdayNames()!.length, 7);
  });

  test('a random cycle names its own positions, verbatim, and a world with no '
      'week has no weekday names', () {
    final r = Random(specSeed + 6);
    for (var index = 0; index < iterations; index += 1) {
      final used = <String>{};
      final cycleName = _word(r, used);
      final radix = 2 + r.nextInt(12);
      final offset = r.nextInt(41) - 20;
      final names = [for (var slot = 0; slot < radix; slot += 1) _word(r, used)];
      final law = CoordinateLaw.parse({
        ...gregorianDeclarationJson,
        'cycles': [
          {'name': cycleName, 'radix': '$radix', 'offset': '$offset', 'names': names},
        ],
      }, frameId: 'frame:cycle-$index');
      for (var probe = 0; probe < 8; probe += 1) {
        final day = r.nextInt(200001) - 100000;
        final expected = ((day + offset) % radix + radix) % radix;
        expect(law.cycleIndex(cycleName, Rational.fromInt(day)), expected);
        expect(law.cycleLabel(cycleName, Rational.fromInt(day)), names[expected]);
      }
      // A declaration that authors cycles of its own still inherits the
      // registered week, because it counts in the registered calendar.
      expect(law.hasWeekdays(), isTrue);
      expect(law.cycles().length, 2);

      // But a law counting in no registered calendar has no week unless it says
      // so, and handing it seven Gregorian names would invent a fact.
      final invented = CoordinateLaw.parse(_Ladder.random(r).json);
      expect(invented.weekdayNames(), isNull);
      expect(invented.hasWeekdays(), isFalse);
      expect(invented.weekdayLabel(Rational.zero), isNull);
      expect(invented.monthNames(), isNull);
      expect(invented.hasMonths(), isFalse);
      expect(invented.cycles(), isEmpty);
    }
  });

  test('a cycle whose name list disagrees with its own radix is refused, with '
      'both counts named', () {
    final r = Random(specSeed + 7);
    for (var index = 0; index < iterations; index += 1) {
      final radix = 2 + r.nextInt(20);
      var given = 1 + r.nextInt(24);
      if (given == radix) given = radix + 1;
      final used = <String>{};
      final cycleName = _word(r, used);
      expectRefusal(
        () => CoordinateLaw.parse({
          'levels': [
            {'name': 'day'},
          ],
          'cycles': [
            {
              'name': cycleName,
              'radix': '$radix',
              'names': [for (var slot = 0; slot < given; slot += 1) _word(r, used)],
            },
          ],
        }, frameId: 'frame:$index'),
        RegExp(
          'the "$cycleName" cycle repeats every $radix but $given '
          'name${given == 1 ? ' was' : 's were'} given',
        ),
      );
    }
  });

  // --- Declaration refusals -------------------------------------------------

  test('a declaration that cannot be resolved is refused in the law\'s own level '
      'names, over random ladders', () {
    final r = Random(specSeed + 8);
    for (var index = 0; index < iterations; index += 1) {
      final ladder = _Ladder.random(r);
      final label = 'Frame frame:$index';
      final first = ladder.names.first;
      final last = ladder.names.last;
      final used = <String>{for (final name in ladder.names) name.toLowerCase()};
      final absent = _word(r, used);

      expectRefusal(
        () => CoordinateLaw.parse({
          'levels': [
            {'name': first},
            {'name': first, 'within': first, 'radix': '2'},
          ],
        }, frameId: 'frame:$index'),
        '$label: level "$first" is declared twice.',
      );
      expectRefusal(
        () => CoordinateLaw.parse({
          'levels': [
            {'name': first},
            {'name': last, 'within': absent, 'radix': '2'},
          ],
        }, frameId: 'frame:$index'),
        '$label: level "$last" nests inside "$absent", which is not a level above it.',
      );
      expectRefusal(
        () => CoordinateLaw.parse({
          'levels': [
            {'name': first},
            {'name': last, 'within': first, 'radix': '0'},
          ],
        }, frameId: 'frame:$index'),
        '$label: level "$last" needs a positive whole radix, not 0.',
      );
      expectRefusal(
        () => CoordinateLaw.parse({
          'levels': [
            {'name': first},
            {'name': last, 'within': first, 'radix': '${1 + 2 * r.nextInt(9)}/2'},
          ],
        }, frameId: 'frame:$index'),
        'needs a positive whole radix',
      );
      expectRefusal(
        () => CoordinateLaw.parse({
          'levels': [
            {'name': first},
            {'name': last, 'within': first, 'radix': absent},
          ],
        }, frameId: 'frame:$index'),
        '$label: level "$last" has a radix that is not a number ($absent).',
      );
      expectRefusal(
        () => CoordinateLaw.parse({
          'levels': [
            {'name': first},
            {'name': last, 'within': first, 'radix': '7', 'transition': 'gregorian.months'},
          ],
        }, frameId: 'frame:$index'),
        'declares both a radix and a transition; a level has one or the other',
      );
      expectRefusal(
        () => CoordinateLaw.parse({
          'levels': [
            {'name': first},
            {'name': last, 'within': first, 'radix': '2'},
          ],
          'baseLevel': absent,
        }, frameId: 'frame:$index'),
        '$label: the base unit is declared as "$absent", which is not one of its '
        'levels ($first, $last).',
      );
      expectRefusal(
        () => CoordinateLaw.parse({
          ...ladder.json,
          'fixed': {'epochDays': '${1 + r.nextInt(500)}'},
        }, frameId: 'frame:$index'),
        'states its starting day twice, as a fixed-calendar epoch and as an origin',
      );
      expectRefusal(
        () => CoordinateLaw.parse({
          'levels': [
            {'name': first},
          ],
          'atomDays': '-${1 + r.nextInt(500)}',
        }, frameId: 'frame:$index'),
        '$label: the smallest unit must be longer than zero days.',
      );
    }
  });

  // --- Positionality by registry, never by label ----------------------------

  test('an executable ladder is positional whatever its kind string says, and a '
      'measure frame stays a magnitude whatever its ladder is', () {
    final r = Random(specSeed + 9);
    final used = <String>{};
    for (var index = 0; index < iterations; index += 1) {
      // Measured defect: an identical year > month > day declaration resolved
      // positional=false purely because its kind was spelled differently, and
      // 2026-08-20 then read as day ordinal 20 — off by fifty-six years.
      final kind = _word(r, used);
      final declaration = {
        'kind': kind,
        'levels': [
          {'name': 'year'},
          {
            'name': 'month',
            'within': 'year',
            'transition': 'gregorian.months',
            // Authored names win over the registered ones.
            'names': [for (var slot = 0; slot < 12; slot += 1) _word(r, used)],
          },
          {'name': 'day', 'within': 'month', 'transition': 'gregorian.days'},
        ],
      };
      final laws = CoordinateLaws();
      final positional = laws.of(
        _document({
          'calendar:$index': {'id': 'calendar:$index', 'coordinate': declaration},
        }),
        'calendar:$index',
      );
      expect(positional.positional, isTrue);
      final value = Coordinate.of([('year', 2026), ('month', 8), ('day', 20)]);
      expect(positional.toDays(value), civilCoordinateToDays(value));
      expect(positional.monthNames(), isNotNull);
      expect(positional.monthNames()!.first, isNot('January'));

      // The one semantic marker that survives is `measure`, and it is not a label
      // for arithmetic: it says what the frame IS, so its levels are counts.
      final measure = laws.of(
        _document({
          'measure:$index': {
            'id': 'measure:$index',
            'traits': ['measure'],
            'coordinate': declaration,
          },
        }),
        'measure:$index',
      );
      expect(measure.positional, isFalse);
      expect(measure.mapsToClock(), isFalse);
      // Its declared radices still govern magnitudes, which is the half that
      // matters for a measure frame.
      expect(measure.meanUnitDays('year'), Rational.parse('146097/400'));
    }
  });

  test('a law with no family refuses a foreign coordinate instead of reading it '
      'as a count, over random ladders', () {
    final r = Random(specSeed + 10);
    for (var index = 0; index < iterations; index += 1) {
      final ladder = _Ladder.random(r);
      final json = {...ladder.json}..remove('origin');
      final laws = CoordinateLaws();
      final document = _document({
        'measure:$index': {
          'id': 'measure:$index',
          'traits': ['measure'],
          'coordinate': json,
        },
      });
      final law = laws.of(document, 'measure:$index');
      expect(law.positional, isFalse);
      // Measured defect: a {year, month, day} coordinate handed to a family-less
      // law whose base level happened to be `day` placed 1973-03-15 at day 15.
      final foreign = Coordinate.of([('year', 1973), ('month', 3), ('day', 15)]);
      final missing = [
        for (final name in ['year', 'month', 'day'])
          if (!law.has(name)) name,
      ];
      expectRefusal(() => law.toDays(foreign), 'declares no ${missing.join(', ')} level');
      expect(laws.valueError(document, 'measure:$index', foreign), isNotNull);
      expect(laws.daysOrNull(document, 'measure:$index', foreign), isNull);
      // A value made only of levels it does declare reads as the count it is.
      final count = r.nextInt(2000) - 1000;
      expect(
        law.toDays(Coordinate.of([(law.baseLevel, count)])),
        Rational.fromInt(count) * law.baseDays,
      );
    }
  });

  test('the three distinct claims stay distinct: an own axis, a shared atom, and '
      'a place on the running clock', () {
    final r = Random(specSeed + 11);
    for (var index = 0; index < iterations; index += 1) {
      final ladder = _Ladder.random(r);
      // An authored origin IS a statement that these positions are comparable to
      // real days, so all three claims hold.
      final anchored = CoordinateLaw.parse(ladder.json);
      expect(anchored.positional, isTrue);
      expect(anchored.sharesStandardAtom(), isTrue);
      expect(anchored.mapsToClock(), isTrue);
      // An author may say outright that this world has no now. Its axis is still
      // real and its units are still commensurable; only the Now line goes.
      final clockless = CoordinateLaw.parse({...ladder.json, 'clock': false});
      expect(clockless.positional, isTrue);
      expect(clockless.sharesStandardAtom(), isTrue);
      expect(clockless.mapsToClock(), isFalse);
      // With no origin and no authored atom, the ladder still converts on its own
      // axis — refusing to would collapse every event onto position 1 — but it
      // claims no relation to Earth days.
      final own = {...ladder.json}
        ..remove('origin')
        ..remove('atomDays');
      final unanchored = CoordinateLaw.parse(own);
      expect(unanchored.positional, isTrue);
      expect(unanchored.sharesStandardAtom(), isFalse);
      expect(unanchored.mapsToClock(), isFalse);
      final value = ladder.coordinate(r);
      expect(
        unanchored.toDays(unanchored.fromDays(unanchored.toDays(value))),
        unanchored.toDays(value),
      );
      // A uniform ladder is no CLDR calendar scale, so a series counting in it is
      // not ICS-expressible as a rule.
      expect(unanchored.calendarScale(), isNull);
      expect(anchored.calendarScale(), isNull);
    }
  });

  // --- Resolution, caching and the refusal seam -----------------------------

  test('a frame inherits an edited ladder through its basis, and an applied edit '
      'is live on the next ask', () {
    final r = Random(specSeed + 12);
    for (var index = 0; index < iterations; index += 1) {
      final hours = 2 + r.nextInt(60);
      final laws = CoordinateLaws();
      final document = _document({
        'frame:wall-time': {
          'id': 'frame:wall-time',
          'coordinate': _civilLadder(hoursPerDay: hours),
        },
        'calendar:personal': {
          'id': 'calendar:personal',
          'traits': ['set', 'calendar'],
          'basis': 'frame:wall-time',
        },
      });
      // "That is the frame defining the inherited calendar structure": the basis
      // outranks a frame's own non-calendar declaration.
      expect(laws.of(document, 'calendar:personal').unitsPer('hour'), Rational.fromInt(hours));
      final probe = _civil(2026, 8, 20, 1, 0, 0);
      expect(
        laws.of(document, 'calendar:personal').toDays(probe),
        laws.of(document, 'frame:wall-time').toDays(probe),
      );
      // Asked twice, the same law comes back — resolution is O(1) after the first
      // call because the engine asks inside occurrence loops.
      expect(laws.of(document, 'calendar:personal'), same(laws.of(document, 'calendar:personal')));

      // A REPLACED declaration is noticed by identity, with no explicit
      // invalidation at all — the shape an applied edit actually arrives in.
      final replaced = hours + 1;
      (document['frames']! as Map)['frame:wall-time'] = {
        'id': 'frame:wall-time',
        'coordinate': _civilLadder(hoursPerDay: replaced),
      };
      expect(laws.of(document, 'frame:wall-time').unitsPer('hour'), Rational.fromInt(replaced));

      // An IN-PLACE mutation — the shape an undo or a replay can produce — is
      // covered by the explicit invalidation the edit path calls.
      final mutated = replaced + 1;
      final levels =
          ((((document['frames']! as Map)['frame:wall-time'] as Map)['coordinate'] as Map)['levels']
                  as List)
              .cast<Map<String, Object?>>();
      levels.firstWhere((level) => level['name'] == 'hour')['radix'] = '$mutated';
      expect(
        laws.of(document, 'frame:wall-time').unitsPer('hour'),
        Rational.fromInt(replaced),
        reason: 'identity alone cannot see this',
      );
      laws.invalidate(document);
      expect(laws.of(document, 'frame:wall-time').unitsPer('hour'), Rational.fromInt(mutated));
      laws.invalidate();
      expect(laws.of(document, 'frame:wall-time').unitsPer('hour'), Rational.fromInt(mutated));
    }
  });

  test('one refusal seam answers every question about a broken frame, and a '
      'broken frame never blanks the stage', () {
    final r = Random(specSeed + 13);
    for (var index = 0; index < iterations; index += 1) {
      final laws = CoordinateLaws();
      final document = _document({
        'frame:broken': {
          'id': 'frame:broken',
          'coordinate': {
            ..._civilLadder(),
            'levels': [
              {'name': 'year'},
              {'name': 'hour', 'within': 'year', 'radix': '-${1 + r.nextInt(99)}'},
            ],
          },
        },
        'frame:fine': {
          'id': 'frame:fine',
          'traits': ['gregorian'],
        },
      });
      expect(laws.lawError(document, 'frame:fine'), isNull);
      expect(laws.lawError(document, 'frame:broken'), contains('positive whole radix'));
      expect(laws.attempt(document, 'frame:broken'), isA<Refused<CoordinateLaw>>());
      expect(laws.attempt(document, 'frame:fine'), isA<Resolved<CoordinateLaw>>());
      // Display falls back to the registered standard rather than refusing to
      // draw, and the error is how a surface asks what went wrong.
      expect(laws.display(document, 'frame:broken'), same(gregorianLaw));
      expect(laws.display(document, null), same(gregorianLaw));
      expect(laws.lawError(document, 'frame:missing'), contains('Unknown frame'));
      // A frame deferring to itself is a cycle, reported rather than hung on.
      final looped = _document({
        'frame:loop': {'id': 'frame:loop', 'coordinateDefinition': 'frame:loop'},
      });
      expect(laws.lawError(looped, 'frame:loop'), contains('Coordinate definition cycle'));
    }
  });

  test('a malformed duration magnitude is tolerated rather than refused, and an '
      'unknown level is skipped rather than guessed at', () {
    final r = Random(specSeed + 14);
    final laws = CoordinateLaws();
    for (var index = 0; index < iterations; index += 1) {
      final used = <String>{'week', 'day', 'hour', 'minute', 'second'};
      final unknown = _word(r, used);
      expect(gregorianLaw.magnitudeDays(null), Rational.zero);
      expect(
        gregorianLaw.magnitudeDays(Coordinate.of([('minute', unknown)])),
        Rational.zero,
        reason: 'an unparseable magnitude yields zero rather than refusing',
      );
      expect(gregorianLaw.magnitudeDays(Coordinate.of([(unknown, 3)])), Rational.zero);
      // A negative sum clamps: every caller treats a duration as a non-negative
      // span.
      expect(
        gregorianLaw.magnitudeDays(Coordinate.of([('hour', -(1 + r.nextInt(9)))])),
        Rational.zero,
      );
      // With no governing law named, the registered standard answers.
      final minutes = 1 + r.nextInt(2000);
      expect(
        laws.durationMagnitudeDays({
          'value': {
            'levels': [
              {'level': 'minute', 'value': '$minutes'},
            ],
          },
        }),
        Rational.fromInt(minutes, 1440),
      );
      expect(laws.durationMagnitudeDays(null), Rational.zero);
    }
  });

  // --- Codec round trips ----------------------------------------------------

  test('coordinates and declarations round-trip through the document format '
      'unchanged, over random ladders', () {
    final r = Random(specSeed + 15);
    for (var index = 0; index < iterations; index += 1) {
      final ladder = _Ladder.random(r);
      final value = ladder.coordinate(r);
      expect(Coordinate.fromJson(value.toJson()), value);
      expect(Coordinate.fromJson(null), Coordinate.empty);
      // An omitted level and a level valued null are the same statement.
      expect(Coordinate.of([(ladder.names.first, null)]), Coordinate.empty);

      final declaration = Declaration.parse(ladder.json, 'test');
      final again = Declaration.parse(declaration.toJson(), 'test');
      expect(again.kind, declaration.kind);
      expect(again.baseLevel, declaration.baseLevel);
      expect(again.atomDays, declaration.atomDays);
      expect(again.origin, declaration.origin);
      expect(again.levels.length, declaration.levels.length);
      for (final (rung, level) in declaration.levels.indexed) {
        expect(again.levels[rung].name, level.name);
        expect(again.levels[rung].within, level.within);
        expect(again.levels[rung].radix, level.radix);
        expect(again.levels[rung].transition, level.transition);
      }
      // And the law built from the round-tripped declaration is the same law.
      expect(CoordinateLaw(again).toDays(value), CoordinateLaw(declaration).toDays(value));
    }
  });

  // --- Eras -----------------------------------------------------------------

  test('random era tables derive contiguous ranges from ONE anchor and round-trip '
      'every year in every era', () {
    final r = Random(specSeed + 16);
    for (var index = 0; index < iterations; index += 1) {
      final table = EraTable.parse(_randomEraTable(r));
      // Contiguity, checked rather than assumed: no gap and no overlap.
      for (var slot = 1; slot < table.entries.length; slot += 1) {
        expect(table.entries[slot].firstProper, table.entries[slot - 1].lastProper! + BigInt.one);
      }
      for (final entry in table.entries) {
        final span = entry.years?.toInt() ?? 20;
        final year = entry.firstYear + BigInt.from(r.nextInt(span));
        final proper = table.toProperYear(entry.key, year);
        final back = table.fromProperYear(proper);
        expect(back.entry.key, entry.key);
        expect(back.year, year);
        expect(table.eraAtProperYear(proper)!.key, entry.key);
        // A descending era's higher number is the OLDER year.
        if (entry.descending && span > 1) {
          final older = entry.firstYear + BigInt.from(span - 1);
          expect(table.toProperYear(entry.key, older) < proper || older == year, isTrue);
        }
        // Format and parse, on either side of the number, whatever affix the era
        // authored for itself.
        final text = table.format(entry.key, year);
        expect(table.parse(text), (era: entry.key, year: '$year'));
        expect(table.parse('${entry.key} $year'), (era: entry.key, year: '$year'));
        expect(table.parse('$year ${entry.key}'), (era: entry.key, year: '$year'));
        // A multi-word name resolves as readily as its key.
        expect(table.parse('${entry.name} $year'), (era: entry.key, year: '$year'));
        expect(table.formatProperYear(proper), table.format(entry.key, year));
        // A qualifier naming no era of this calendar is refused, never read as a
        // bare number.
        expect(table.parse('$year'), isNull);
        expect(table.parse(''), isNull);
      }
      final used = <String>{
        for (final entry in table.entries) entry.key.toLowerCase(),
        for (final entry in table.entries) entry.name.toLowerCase(),
      };
      final absent = _word(r, used);
      expectRefusal(() => table.toProperYear(absent, '1'), 'is not one of this calendar\'s eras');
      expectRefusal(() => table.format(absent, '1'), 'is not one of this calendar\'s eras');
      expect(table.parse('$absent 1'), isNull);
      expect(table.eraKeys().length, table.entries.length);
      expect(table.eraNames().length, table.entries.length);
      expect(table.summary(), contains(table.entries.first.key));
    }
  });

  test('a descending era counts back, so there is no year-zero seam at any '
      'random anchor', () {
    final r = Random(specSeed + 17);
    for (var index = 0; index < iterations; index += 1) {
      final older = _word(r, <String>{});
      final newer = _word(r, {older.toLowerCase()});
      final anchorYear = r.nextInt(8001) - 4000;
      final table = EraTable.parse({
        'anchor': {'era': newer, 'year': '1', 'properYear': '$anchorYear'},
        'entries': [
          {'key': older, 'name': '$older Era', 'direction': 'descending', 'years': 'open'},
          {'key': newer, 'name': '$newer Era', 'direction': 'ascending', 'years': 'open'},
        ],
      });
      // Year 1 of the descending era and year 1 of the era after it are ADJACENT
      // proper years. Nothing special-cases a gap that was never there.
      expect(table.toProperYear(older, '1') + BigInt.one, table.toProperYear(newer, '1'));
      // Counting further back walks strictly backwards, one proper year per year.
      final steps = 1 + r.nextInt(4000);
      expect(
        table.toProperYear(older, '$steps'),
        table.toProperYear(older, '1') - BigInt.from(steps - 1),
      );
      expect(table.fromProperYear(table.toProperYear(older, '$steps')).year, BigInt.from(steps));
    }
  });

  test('RULED ANCHOR: BCE/CE and the Tamriel chain derive the ranges their '
      'fixtures state', () {
    final bceCe = EraTable.parse({
      'anchor': {'era': 'CE', 'year': '1', 'properYear': '1'},
      'entries': [
        {
          'key': 'BCE',
          'name': 'Before Common Era',
          'direction': 'descending',
          'firstYear': '1',
          'years': 'open',
          'affix': 'suffix',
        },
        {
          'key': 'CE',
          'name': 'Common Era',
          'direction': 'ascending',
          'firstYear': '1',
          'years': 'open',
          'affix': 'suffix',
        },
      ],
    });
    // Year 0 does not exist: 1 BCE and 1 CE are adjacent proper years 0 and 1.
    expect(bceCe.toProperYear('BCE', '1'), BigInt.zero);
    expect(bceCe.toProperYear('CE', '1'), BigInt.one);
    expect(bceCe.toProperYear('BCE', '2500'), BigInt.from(-2499));
    expect(bceCe.format('BCE', '44'), '44 BCE');
    expect(bceCe.parse('44 BCE'), (era: 'BCE', year: '44'));
    expect(bceCe.parse('BCE 44'), (era: 'BCE', year: '44'));

    final tamriel = EraTable.parse({
      'anchor': {'era': '1E', 'year': '1', 'properYear': '1'},
      'entries': [
        {
          'key': 'ME',
          'ordinal': '0',
          'name': 'Merethic Era',
          'direction': 'descending',
          'firstYear': '1',
          'years': 'open',
        },
        {
          'key': '1E',
          'ordinal': '1',
          'name': 'First Era',
          'direction': 'ascending',
          'firstYear': '1',
          'years': '2920',
        },
        {
          'key': '2E',
          'ordinal': '2',
          'name': 'Second Era',
          'direction': 'ascending',
          'firstYear': '1',
          'years': '896',
        },
        {
          'key': '3E',
          'ordinal': '3',
          'name': 'Third Era',
          'direction': 'ascending',
          'firstYear': '1',
          'years': '433',
        },
        {
          'key': '4E',
          'ordinal': '4',
          'name': 'Fourth Era',
          'direction': 'ascending',
          'firstYear': '1',
          'years': 'open',
        },
      ],
    });
    Map<String, List<BigInt?>> ranges(EraTable table) => {
      for (final entry in table.entries) entry.abbrev: [entry.firstProper, entry.lastProper],
    };
    expect(ranges(tamriel)['1E'], [BigInt.one, BigInt.from(2920)]);
    expect(ranges(tamriel)['2E'], [BigInt.from(2921), BigInt.from(3816)]);
    expect(ranges(tamriel)['3E'], [BigInt.from(3817), BigInt.from(4249)]);
    expect(ranges(tamriel)['4E'], [BigInt.from(4250), null]);
    expect(ranges(tamriel)['ME'], [null, BigInt.zero]);
    expect(tamriel.toProperYear('3E', '433'), BigInt.from(4249));
    expect(tamriel.toProperYear('ME', '2500'), BigInt.from(-2499));
    // `ordinal` orders the table regardless of the order the entries are listed
    // in, and `"open"` is an open span rather than a length.
    expect(tamriel.eraKeys(), ['ME', '1E', '2E', '3E', '4E']);
    expect(tamriel.era('ME')!.years, isNull);
    // A bare "3E433" is readable only BY THE AUTHORED NAMES.
    expect(tamriel.parse('3E433'), (era: '3E', year: '433'));
    expect(tamriel.parse('Third Era 433'), (era: '3E', year: '433'));
  });

  test('an era table that cannot be resolved is refused before anything is '
      'stored, over random tables', () {
    final r = Random(specSeed + 18);
    for (var index = 0; index < iterations; index += 1) {
      final source = _randomEraTable(r);
      final entries = (source['entries']! as List).cast<Map<String, Object?>>();
      final anchor = source['anchor']! as Map<String, Object?>;
      EraTable make(List<Map<String, Object?>> rows, [Map<String, Object?>? which]) =>
          EraTable.parse({'anchor': which ?? anchor, 'entries': rows});

      expectRefusal(
        () => EraTable.parse({'entries': const []}),
        'An era table needs at least one era.',
      );
      // An open era in the middle leaves both of its neighbours unresolvable.
      if (entries.length >= 3) {
        final middleOpen = [
          for (final (slot, row) in entries.indexed)
            {...row, if (slot == 1) 'years': 'open', if (slot == 1) 'direction': 'ascending'},
        ];
        expectRefusal(
          () => make(middleOpen),
          RegExp('counts up with no stated length.*must be listed last', dotAll: true),
        );
        final middleDescending = [
          for (final (slot, row) in entries.indexed)
            {...row, if (slot == 1) 'years': 'open', if (slot == 1) 'direction': 'descending'},
        ];
        expectRefusal(
          () => make(middleDescending),
          RegExp('counts down with no stated length.*must be listed first', dotAll: true),
        );
      }
      // A span must be a positive whole number of years.
      final first = entries.first;
      expectRefusal(
        () => make([
          {...first, 'years': '0'},
        ]),
        'must be greater than zero',
      );
      expectRefusal(
        () => make([
          {...first, 'years': '${1 + r.nextInt(20)}.5'},
        ]),
        'must be a whole number',
      );
      // Two eras answering to the same token cannot be told apart on the way in.
      expectRefusal(
        () => make([
          {...first, 'years': '10'},
          {...first, 'name': '${first['name']} Redux', 'years': '10'},
        ]),
        'Two eras answer to "${first['key']}"',
      );
      // A number alone cannot be told apart from a year.
      expectRefusal(
        () => make([
          {...first, 'key': '${1 + r.nextInt(999)}'},
        ]),
        'a number alone cannot be told apart from a year',
      );
      // Ordinals are all or nothing: a partly-ordered table has no order.
      if (entries.length >= 2) {
        expectRefusal(
          () => make([
            {...entries[0], 'ordinal': '0', 'years': '10', 'direction': 'ascending'},
            {...entries[1], 'years': '10', 'direction': 'ascending'},
          ]),
          'Either every era declares an ordinal or none does',
        );
        expectRefusal(
          () => make([
            {...entries[0], 'ordinal': '3', 'years': '10', 'direction': 'ascending'},
            {...entries[1], 'ordinal': '3', 'years': '10', 'direction': 'ascending'},
          ]),
          'Two eras share an ordinal',
        );
      }
      // The anchor has to name a real era and sit inside it.
      final absent = _word(r, {
        for (final row in entries) '${row['key']}'.toLowerCase(),
        for (final row in entries) '${row['name']}'.toLowerCase(),
      });
      expectRefusal(
        () => make(entries, {'era': absent, 'year': '1', 'properYear': '1'}),
        'is not one of its eras',
      );
      // A year outside every declared era has no name and is refused rather than
      // given an invented one.
      final closed = make(
        [
          {...first, 'years': '100', 'firstYear': '1', 'direction': 'ascending'},
        ],
        {'era': first['key'], 'year': '1', 'properYear': '1'},
      );
      expectRefusal(
        () => closed.fromProperYear(BigInt.from(200)),
        'falls outside every declared era',
      );
      expectRefusal(() => closed.toProperYear(first['key'], '101'), 'only 100 years long');
      expectRefusal(() => closed.toProperYear(first['key'], '0'), 'numbers its years from 1');
    }
  });

  test('an era\'s first year is authored, not assumed to be 1, at random '
      'starting numbers', () {
    final r = Random(specSeed + 19);
    for (var index = 0; index < iterations; index += 1) {
      final key = _word(r, <String>{});
      final firstYear = r.nextInt(41) - 20;
      final span = 1 + r.nextInt(500);
      final table = EraTable.parse({
        'anchor': {'era': key, 'year': '$firstYear', 'properYear': '$firstYear'},
        'entries': [
          {
            'key': key,
            'name': '$key Era',
            'direction': 'ascending',
            'firstYear': '$firstYear',
            'years': '$span',
          },
        ],
      });
      expect(table.toProperYear(key, '$firstYear'), BigInt.from(firstYear));
      expect(table.fromProperYear(BigInt.from(firstYear)).year, BigInt.from(firstYear));
      expectRefusal(() => table.toProperYear(key, '${firstYear + span}'), 'only $span years long');
      expectRefusal(
        () => table.toProperYear(key, '${firstYear - 1}'),
        'numbers its years from $firstYear',
      );
    }
  });

  test('an era frame\'s law counts the era\'s own years and refuses a position '
      'that belongs to a neighbour, over random tables', () {
    final r = Random(specSeed + 20);
    var exercised = 0;
    for (var index = 0; index < iterations; index += 1) {
      final table = EraTable.parse(_randomEraTable(r));
      for (final entry in table.entries) {
        if (entry.years == null) continue;
        final law = CoordinateLaw.parse(
          _civilLadder(),
          frameId: 'era:${entry.key}',
          era: EraContext.countable(table, entry),
        );
        expect(law.hasEras(), isTrue);
        expect(law.eraKey(), entry.key);
        expect(law.eras().length, table.entries.length);
        // A coordinate on an era frame carries a PLAIN year; the frame it is
        // attached to is which era it means.
        final year = entry.firstYear + BigInt.from(r.nextInt(entry.years!.toInt()));
        final value = Coordinate.of([('year', year), ('month', 6), ('day', 15)]);
        final days = law.toDays(value);
        expect(law.fromDays(days), value, reason: 'the era-local year comes back');
        expect(law.formatYear(value), table.format(entry.key, year));
        expect(law.parseYear(law.formatYear(value)), (era: entry.key, year: '$year'));
        expect(law.formatYearAtDays(days), table.format(entry.key, year));
        // The PROPER year is what the family ladder actually counts in.
        final proper = table.toProperYear(entry.key, year);
        expect(
          days,
          civilCoordinateToDays(Coordinate.of([('year', proper), ('month', 6), ('day', 15)])),
        );
        // A year past this era's own extent is refused, never wrapped into a
        // neighbour.
        expectRefusal(
          () => law.toDays(Coordinate.of([('year', entry.firstYear + entry.years!)])),
          'only ${entry.years} years long',
        );
        // And a day ordinal belonging to another era refuses rather than silently
        // renumbering into it.
        final outside = table.eraAtProperYear(proper + entry.years!);
        if (outside != null && outside.key != entry.key) {
          expectRefusal(
            () => law.fromDays(
              civilCoordinateToDays(
                Coordinate.of([('year', proper + entry.years!), ('month', 6), ('day', 15)]),
              ),
            ),
            'That position falls in ${outside.name}, not ${entry.name}.',
          );
          exercised += 1;
        }
      }
    }
    expect(exercised, greaterThan(0), reason: 'the neighbour refusal was reached');
  });

  test('an era with no year axis refuses conversion outright, at random names', () {
    final r = Random(specSeed + 21);
    for (var index = 0; index < iterations; index += 1) {
      final used = <String>{};
      final key = _word(r, used);
      final name = '${_word(r, used)} Era';
      final law = CoordinateLaw.parse(
        _civilLadder(),
        frameId: 'era:$key',
        era: EraContext.uncountable(key: key, name: name),
      );
      // "Ordered, connected, never acquiring day ordinals" is the whole of what it
      // claims, so it is never positional and never has a now.
      expect(law.positional, isFalse);
      expect(law.mapsToClock(), isFalse);
      expect(law.hasEras(), isFalse);
      expect(law.eraKey(), key);
      expectRefusal(
        () => law.toDays(_civil(2026, 8, 20)),
        '$name has no year axis, so nothing in it has a date.',
      );
      expectRefusal(
        () => law.fromDays(Rational.fromInt(r.nextInt(10000))),
        '$name has no year axis, so no position in it has a date.',
      );
    }
  });

  test('an era that counts years needs a ladder its family can execute, and says '
      'so when it has none', () {
    final r = Random(specSeed + 22);
    for (var index = 0; index < iterations; index += 1) {
      final key = _word(r, <String>{});
      final table = EraTable.parse({
        'anchor': {'era': key, 'year': '1', 'properYear': '1'},
        'entries': [
          {
            'key': key,
            'name': '$key Era',
            'direction': 'ascending',
            'years': '${1 + r.nextInt(999)}',
          },
        ],
      });
      // A ladder with an unmeasured rung above its base is one no family can
      // execute, so no family may renumber its years either.
      final unmeasured = _word(r, <String>{'year'});
      expectRefusal(
        () => CoordinateLaw.parse(
          {
            'levels': [
              {'name': 'year'},
              {'name': unmeasured, 'within': 'year'},
            ],
            'baseLevel': unmeasured,
            'atomDays': '1',
          },
          frameId: 'era:$key',
          era: EraContext.countable(table, table.entries.first),
        ),
        'this era counts years, so it needs a year ladder its family can execute',
      );
    }
  });

  test('a law with no era table behaves exactly as one without eras ever did', () {
    final r = Random(specSeed + 23);
    for (var index = 0; index < iterations; index += 1) {
      final year = r.nextInt(6000) - 3000;
      final value = Coordinate.of([('year', year), ('month', 8), ('day', 20)]);
      expect(gregorianLaw.hasEras(), isFalse);
      expect(gregorianLaw.eras(), isEmpty);
      expect(gregorianLaw.eraKey(), isNull);
      expect(gregorianLaw.parseYear('44 BCE'), isNull);
      expect(gregorianLaw.formatYear(value), '$year');
      expect(gregorianLaw.fromDays(gregorianLaw.toDays(value)), value);
    }
  });

  // --- The extension seam, exercised last (see the ORDERING NOTE) ------------

  test('a new calendar family is a registration, and a ladder mixing two '
      'families is refused with both named', () {
    // Registered rather than special-cased is the whole claim of the registry:
    // adding a calendar is one call plus its transitions, and nothing else in the
    // program changes. This is also the only way to reach the family-mix refusal,
    // since the standard build ships transitions for exactly one family.
    registerCalendarFamily(_LunarFamily());
    registerTransition(
      'lunar.months',
      family: 'lunar',
      meanChildren: Rational.parse('12'),
      summary: '12 lunations',
    );
    expect(registeredTransitions(), contains('lunar.months'));
    expect(transitionDefinition('lunar.months')!.family.name, 'lunar');
    expect(transitionDefinition('lunar.months')!.childrenIn(const {}), BigInt.from(12));
    expect(registeredCalendars(), [gregory], reason: 'a family naming no CLDR scale claims none');
    expectRefusal(
      () => CoordinateLaw.parse({
        'levels': [
          {'name': 'year'},
          {'name': 'month', 'within': 'year', 'transition': 'gregorian.months'},
          {'name': 'moon', 'within': 'month', 'transition': 'lunar.months'},
        ],
      }, frameId: 'frame:spliced'),
      RegExp('levels mix the (gregorian and lunar|lunar and gregorian) calendar families'),
    );
    expectRefusal(
      () => registerTransition('lunar.days', family: 'nothing', meanChildren: Rational.one),
      'names an unregistered calendar family',
    );
    expectRefusal(
      () => registerTransition('lunar.zero', family: 'lunar', meanChildren: Rational.zero),
      'needs a positive mean child count',
    );
    // A frame whose ladder the new family can execute converts through the same
    // seam Gregorian does, with no privileged branch anywhere.
    final law = CoordinateLaw.parse({
      'levels': [
        {'name': 'year'},
        {'name': 'moon', 'within': 'year', 'transition': 'lunar.months'},
      ],
    }, frameId: 'frame:lunar');
    expect(law.calendarScale(), isNull);
    expect(law.positional, isTrue);
    expect(law.toDays(Coordinate.of([('year', 2), ('moon', 3)])), Rational.fromInt(2 * 12 + 3));
    expect(law.meanUnitDays('year'), Rational.fromInt(12));
  });
}

/// A second family, registered by the test above purely to prove the seam is
/// open. It counts twelve lunations of one day each, which is enough arithmetic
/// to execute a ladder and no more.
class _LunarFamily extends CalendarFamily {
  @override
  String get name => 'lunar';

  @override
  String? get calendar => null;

  @override
  bool supports(List<Level> ladder) => ladder.length == 2;

  @override
  BigInt toWholeUnits(List<Level> ladder, List<BigInt> parts) =>
      parts[0] * BigInt.from(12) + parts[1];

  @override
  List<(String, BigInt)> fromWholeUnits(List<Level> ladder, BigInt wholeUnits) => [
    (ladder[0].name, floorDiv(wholeUnits, BigInt.from(12))),
    (ladder[1].name, floorMod(wholeUnits, BigInt.from(12))),
  ];
}
