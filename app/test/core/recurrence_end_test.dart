// The spec is generative (Don, 2026-08-27): "We should never be testing for a
// specific case, we should be testing for a general case." Every assertion below
// is a property quantified over seeded random generation, except the ones
// labelled RULED ANCHOR -- the exact strings the JavaScript spec quotes, which
// are the wire format's own law and not derivable from a property.
//
// What an UNTIL means to the engine is asserted against the engine, in
// rrule_test.dart; this file is the derivation of the values themselves.
//
// The seed is fixed so a failure reproduces exactly. Change it only to widen
// coverage deliberately, never to make a red suite green.

import 'dart:math';

import 'package:chronolog/core/recurrence_end.dart';
import 'package:chronolog/core/rrule.dart';
import 'package:test/test.dart';

const specSeed = 20260827;
const iterations = 250;

// --- Generators ---------------------------------------------------------------

// Independent restatements of the padding the wire format requires, written from
// RFC 5545 rather than from the module under test.
String _year(BigInt year) => (year.isNegative ? '-' : '') + year.abs().toString().padLeft(4, '0');

String _two(int value) => '$value'.padLeft(2, '0');

({BigInt year, int month, int day}) _date(Random r) =>
    (year: BigInt.from(r.nextInt(6000) - 2000), month: 1 + r.nextInt(12), day: 1 + r.nextInt(28));

// Written form, with the month and day padded only half the time: a date input
// hands over `2026-1-5` as readily as `2026-01-05`.
String _written(Random r, ({BigInt year, int month, int day}) date) {
  final month = r.nextBool() ? _two(date.month) : '${date.month}';
  final day = r.nextBool() ? _two(date.day) : '${date.day}';
  return '${date.year}-$month-$day';
}

RRule _randomRule(Random r) {
  const parts = ['FREQ', 'INTERVAL', 'BYDAY', 'BYMONTHDAY', 'WKST', 'RSCALE'];
  const values = ['WEEKLY', '2', 'MO,WE', '1,-1', 'SU', 'GREGORY'];
  final rule = <String, String>{};
  for (var i = 0; i < parts.length; i++) {
    if (r.nextBool()) rule[parts[i]] = values[i];
  }
  // Either end may already be written, including the illegal pair, because the
  // point of `applyRecurrenceEnd` is that whatever it is handed comes back with
  // exactly one of them.
  if (r.nextBool()) rule['COUNT'] = '${1 + r.nextInt(50)}';
  if (r.nextBool()) rule['UNTIL'] = '20261231T235959';
  return rule;
}

void main() {
  group('how a rule ends', () {
    test('a mode survives being applied and read back', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final rule = _randomRule(r);
        final date = _date(r);
        final count = 1 + r.nextInt(50);
        for (final mode in RecurrenceEnd.values) {
          final next = applyRecurrenceEnd(
            rule,
            mode: mode,
            count: '$count',
            until: _written(r, date),
          );
          expect(recurrenceEndMode(next), mode, reason: '$rule -> $mode');
        }
      }
    });

    test('exactly one of COUNT and UNTIL survives, and nothing else moves', () {
      final r = Random(specSeed + 1);
      for (var i = 0; i < iterations; i++) {
        final rule = _randomRule(r);
        final before = {...rule};
        final mode = RecurrenceEnd.values[r.nextInt(3)];
        final next = applyRecurrenceEnd(
          rule,
          mode: mode,
          count: r.nextInt(20000) - 5000,
          until: _written(r, _date(r)),
        );
        expect(
          next.containsKey('COUNT') && next.containsKey('UNTIL'),
          isFalse,
          reason: 'RFC 5545 forbids the pair',
        );
        expect(next.containsKey('COUNT'), mode == RecurrenceEnd.count);
        expect(next.containsKey('UNTIL'), mode == RecurrenceEnd.until);
        for (final key in before.keys) {
          if (key == 'COUNT' || key == 'UNTIL') continue;
          expect(next[key], before[key], reason: 'part $key was moved');
        }
        expect(rule, before, reason: 'the rule handed in is never mutated');
      }
    });

    test('a mode nobody implements degrades to never, inventing nothing', () {
      final r = Random(specSeed + 2);
      for (var i = 0; i < iterations; i++) {
        final name = String.fromCharCodes([
          for (var k = 0; k <= r.nextInt(8); k++) 97 + r.nextInt(26),
        ]);
        final expected = RecurrenceEnd.values.any((mode) => mode.name == name) ? name : 'never';
        expect(recurrenceEndNamed(name).name, expected, reason: name);
      }
      expect(recurrenceEndNamed(null), RecurrenceEnd.never);
    });

    test('an end the author left unusable falls back to never', () {
      final r = Random(specSeed + 3);
      for (var i = 0; i < iterations; i++) {
        final junk = [
          '',
          '   ',
          'not a date',
          'tomorrow',
          '2026',
          '${r.nextInt(100)}',
          '2026-13',
        ][r.nextInt(7)];
        final next = applyRecurrenceEnd({'FREQ': 'DAILY'}, mode: RecurrenceEnd.until, until: junk);
        expect(next, {'FREQ': 'DAILY'}, reason: 'until=$junk');
        expect(recurrenceEndMode(next), RecurrenceEnd.never);
      }
    });

    test('an already-compact UNTIL passes through instead of being re-derived', () {
      final r = Random(specSeed + 4);
      for (var i = 0; i < iterations; i++) {
        final date = _date(r);
        final compact = '${_year(date.year)}${_two(date.month)}${_two(date.day)}';
        final written = r.nextBool()
            ? compact
            : '${compact}T${_two(r.nextInt(24))}${_two(r.nextInt(60))}00';
        expect(
          applyRecurrenceEnd(
            const {'FREQ': 'DAILY'},
            mode: RecurrenceEnd.until,
            until: written,
          )['UNTIL'],
          written,
        );
      }
    });
  });

  group('counts', () {
    test('a count is clamped into the range the engine will accept', () {
      final r = Random(specSeed + 5);
      for (var i = 0; i < iterations; i++) {
        final written = r.nextInt(30000) - 10000;
        final normalized = normalizeRecurrenceCount('$written');
        expect(normalized, greaterThanOrEqualTo(countMinimum));
        expect(normalized, lessThanOrEqualTo(countMaximum));
        if (written >= countMinimum && written <= countMaximum) {
          expect(normalized, written);
        } else {
          expect(normalized, written < countMinimum ? countMinimum : countMaximum);
        }
        // Clamping is monotone, so a bigger ask never yields a smaller count.
        expect(
          normalizeRecurrenceCount('${written + 1 + r.nextInt(100)}'),
          greaterThanOrEqualTo(normalized),
        );
        // And idempotent: normalizing a normalized count changes nothing.
        expect(normalizeRecurrenceCount(normalized), normalized);
      }
    });

    test('a fractional count floors rather than rounding', () {
      final r = Random(specSeed + 6);
      for (var i = 0; i < iterations; i++) {
        final whole = r.nextInt(9999);
        final fraction = 1 + r.nextInt(99);
        final expected = whole < countMinimum ? countMinimum : whole;
        expect(normalizeRecurrenceCount('$whole.$fraction'), expected);
      }
    });

    test('a count that is not a number at all is one, never zero', () {
      final r = Random(specSeed + 7);
      for (var i = 0; i < iterations; i++) {
        final junk = ['', '  ', 'six', 'NaN', 'Infinity', '-', '1,000', null][r.nextInt(8)];
        expect(normalizeRecurrenceCount(junk), countMinimum, reason: '$junk');
      }
    });
  });

  group('until values', () {
    test('"ends on a date" always lands at the last second of that date', () {
      final r = Random(specSeed + 8);
      for (var i = 0; i < iterations; i++) {
        final date = _date(r);
        final value = recurrenceUntilForDate(_written(r, date));
        expect(value.endsWith('T235959'), isTrue, reason: value);
        expect(value, '${_year(date.year)}${_two(date.month)}${_two(date.day)}T235959');
        // Whatever the module writes, `compactIcsDay` must be able to read: the
        // value's only job is to be compared against an occurrence.
        expect(compactIcsDay(value), isNotNull);
      }
    });

    test('an UNTIL round-trips back into a date input', () {
      final r = Random(specSeed + 9);
      for (var i = 0; i < iterations; i++) {
        final date = _date(r);
        final canonical = '${_year(date.year)}-${_two(date.month)}-${_two(date.day)}';
        expect(recurrenceUntilDate(recurrenceUntilForDate(_written(r, date))), canonical);
        // The plain date form reads back the same as the timed one.
        expect(
          recurrenceUntilDate('${_year(date.year)}${_two(date.month)}${_two(date.day)}'),
          canonical,
        );
      }
      for (final junk in ['', 'bad', '2026', '2026-12-31', null]) {
        expect(recurrenceUntilDate(junk), '', reason: '$junk');
      }
    });

    test('an occurrence caps at its own instant, date-only when it has none', () {
      final r = Random(specSeed + 10);
      for (var i = 0; i < iterations; i++) {
        final date = _date(r);
        final hour = r.nextInt(24);
        final minute = r.nextInt(60);
        final second = r.nextInt(60);
        final stamp = recurrenceUntilForCoordinate({
          'year': '${date.year}',
          'month': '${date.month}',
          'day': '${date.day}',
          'hour': '$hour',
          'minute': '$minute',
          'second': '$second',
        });
        final compact = '${_year(date.year)}${_two(date.month)}${_two(date.day)}';
        final timed = hour != 0 || minute != 0 || second != 0;
        expect(stamp, timed ? '${compact}T${_two(hour)}${_two(minute)}${_two(second)}' : compact);
        expect(compactIcsDay(stamp), isNotNull);
        expect(recurrenceUntilDate(stamp), recurrenceUntilDate(compact));
        // A coordinate that names no time of day at all is date-only too, and
        // the fallbacks are 1970-01-01, never today.
        expect(
          recurrenceUntilForCoordinate({
            'year': '${date.year}',
            'month': '${date.month}',
            'day': '${date.day}',
          }),
          compact,
        );
      }
      expect(recurrenceUntilForCoordinate(const {}), '19700101');
    });
  });

  // The exact strings the JavaScript spec quotes. They are anchors, not
  // properties: each one pins a reading of RFC 5545 that the properties above
  // quantify over but cannot name.
  group('RULED ANCHOR: the quoted values', () {
    test('a rule reports how it ends', () {
      expect(recurrenceEndMode({'FREQ': 'WEEKLY'}), RecurrenceEnd.never);
      expect(recurrenceEndMode({'FREQ': 'WEEKLY', 'COUNT': '8'}), RecurrenceEnd.count);
      expect(recurrenceEndMode({'FREQ': 'WEEKLY', 'UNTIL': '20261231'}), RecurrenceEnd.until);
      expect(recurrenceEndMode(const {}), RecurrenceEnd.never);
      expect(recurrenceEndMode(null), RecurrenceEnd.never);
      // A blank COUNT is not an end condition.
      expect(recurrenceEndMode({'COUNT': ''}), RecurrenceEnd.never);
    });

    test('COUNT and UNTIL are exclusive whichever way the mode changes', () {
      expect(
        applyRecurrenceEnd(
          const {'FREQ': 'WEEKLY', 'UNTIL': '20261231'},
          mode: RecurrenceEnd.count,
          count: '6',
        ),
        {'FREQ': 'WEEKLY', 'COUNT': '6'},
      );
      expect(
        applyRecurrenceEnd(
          const {'FREQ': 'WEEKLY', 'COUNT': '6'},
          mode: RecurrenceEnd.until,
          until: '2026-12-31',
        ),
        {'FREQ': 'WEEKLY', 'UNTIL': '20261231T235959'},
      );
      expect(applyRecurrenceEnd(const {'FREQ': 'WEEKLY', 'COUNT': '6'}), {'FREQ': 'WEEKLY'});
      expect(
        applyRecurrenceEnd(
          const {'FREQ': 'WEEKLY', 'BYDAY': 'MO,WE', 'INTERVAL': '2'},
          mode: RecurrenceEnd.count,
          count: '3',
        ),
        {'FREQ': 'WEEKLY', 'BYDAY': 'MO,WE', 'INTERVAL': '2', 'COUNT': '3'},
      );
      expect(
        applyRecurrenceEnd(
          const {'FREQ': 'DAILY'},
          mode: RecurrenceEnd.until,
          until: '20270115T120000',
        ),
        {'FREQ': 'DAILY', 'UNTIL': '20270115T120000'},
      );
    });

    test('counts and until values read exactly as the wire format spells them', () {
      expect(normalizeRecurrenceCount('6'), 6);
      expect(normalizeRecurrenceCount(0), 1);
      expect(normalizeRecurrenceCount(-4), 1);
      expect(normalizeRecurrenceCount(99999), 10000);
      expect(normalizeRecurrenceCount(''), 1);
      expect(normalizeRecurrenceCount('3.7'), 3);

      expect(recurrenceUntilDate('20261231T235959'), '2026-12-31');
      expect(recurrenceUntilDate('20261231'), '2026-12-31');
      expect(recurrenceUntilDate(''), '');
      expect(recurrenceUntilDate(null), '');
      expect(recurrenceUntilDate(recurrenceUntilForDate('2027-03-09')), '2027-03-09');

      // A midnight UNTIL would drop a 09:00 series' final occurrence. This is
      // the off-by-one a user reads as a bug, so the value is the day's last
      // second.
      expect(recurrenceUntilForDate('2026-12-31'), '20261231T235959');
      expect(recurrenceUntilForDate('2026-1-5'), '20260105T235959');
      expect(recurrenceUntilForDate('bad'), '');

      expect(
        recurrenceUntilForCoordinate(const {
          'year': '2026',
          'month': '10',
          'day': '5',
          'hour': '9',
          'minute': '30',
        }),
        '20261005T093000',
      );
      expect(
        recurrenceUntilForCoordinate(const {'year': '2026', 'month': '10', 'day': '5'}),
        '20261005',
      );
      expect(
        recurrenceUntilForCoordinate(const {
          'year': '2026',
          'month': '1',
          'day': '2',
          'second': '7',
        }),
        '20260102T000007',
      );
    });
  });
}
