// The spec is generative (Don, 2026-08-27): "We should never be testing for a
// specific case, we should be testing for a general case." Every assertion below
// is a property quantified over seeded random generation, except the ones
// labelled RULED ANCHOR -- asserted law (RFC 7529's RSCALE refusal, the
// frequencies this build will not project) or a worked example the JavaScript
// spec quotes, neither of which is derivable from a property.
//
// The predicates in the "independent restatement" block are written from RFC
// 5545 and from what this build reads, deliberately not from the expansion
// code, so agreement between them means something.
//
// The seed is fixed so a failure reproduces exactly. Change it only to widen
// coverage deliberately, never to make a red suite green.

import 'dart:math';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/recurrence_end.dart';
import 'package:chronolog/core/rrule.dart';
import 'package:test/test.dart';

const specSeed = 20260827;
const iterations = 250;

// Only the Gregorian family is registered in this build; the predicate is the
// seam the law registry will fill.
bool _gregorianOnly(String scale) => const {'GREGORY', 'GREGORIAN'}.contains(scale.toUpperCase());

bool _nothingRegistered(String scale) => false;

const _freqs = ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'];
const _codes = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];
const _monthCodes = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12'];


// Days that always cover one cycle of each frequency, for sizing a window that
// holds a known number of cycles, and a cap on how many cycles a generated
// window spans so no single iteration expands a million occurrences.
const _cycleDays = {'DAILY': 1, 'WEEKLY': 7, 'MONTHLY': 31, 'YEARLY': 366};
const _cycleCap = {'DAILY': 90, 'WEEKLY': 40, 'MONTHLY': 24, 'YEARLY': 8};

// --- Independent restatement of the grammar -----------------------------------

int _weekdayOf(BigInt day) => floorMod(day + BigInt.from(4), BigInt.from(7)).toInt();

final RegExp _tokenPattern = RegExp(r'^([+-]?\d+)?(SU|MO|TU|WE|TH|FR|SA)$');

Set<int> _weekdays(String byDay) => {
  for (final token in byDay.split(','))
    if (_tokenPattern.firstMatch(token) case final m?) _codes.indexOf(m[2]!),
};

// A +/- ordinal names the nth (or nth-last) such weekday of the month; a bare
// weekday names all of them.
bool _matchesByDay(String byDay, CivilDay civil, int length) {
  final weekday = _weekdayOf(daysFromCivil(civil.year, civil.month, civil.day));
  for (final token in byDay.split(',')) {
    final m = _tokenPattern.firstMatch(token);
    if (m == null || _codes.indexOf(m[2]!) != weekday) continue;
    final ordinal = m[1] == null ? null : int.parse(m[1]!);
    if (ordinal == null) return true;
    if (ordinal > 0 && (civil.day - 1) ~/ 7 == ordinal - 1) return true;
    if (ordinal < 0 && (length - civil.day) ~/ 7 == -ordinal - 1) return true;
  }
  return false;
}

bool _dayNamed(String byMonthDay, CivilDay civil) {
  final length = daysInMonth(civil.year, civil.month);
  return byMonthDay
      .split(',')
      .map(int.parse)
      .map((value) => value < 0 ? length + value + 1 : value)
      .contains(civil.day);
}

bool _dayAllowed(RRule rule, int baseDay, CivilDay civil) {
  final length = daysInMonth(civil.year, civil.month);
  final byMonthDay = rule['BYMONTHDAY'];
  final byDay = rule['BYDAY'];
  if (byMonthDay != null) {
    if (!_dayNamed(byMonthDay, civil)) return false;
    if (byDay == null) return true;
    final weekday = _weekdayOf(daysFromCivil(civil.year, civil.month, civil.day));
    return _weekdays(byDay).contains(weekday);
  }
  if (byDay != null) return _matchesByDay(byDay, civil, length);
  return civil.day == baseDay;
}

// RFC 5545's general model, restated: every BY* part a rule writes holds of
// every occurrence, whichever frequency wrote it -- expanding or limiting is
// only how the generator gets there. Where a frequency fixes a position no
// written part names, the base supplies it: a YEARLY rule with no BYMONTH
// recurs in the base's own month, a MONTHLY or YEARLY rule with no day part on
// the base's own day of the month, a WEEKLY rule with no BYDAY on the base's
// own weekday.
bool _satisfies(RRule rule, Rational base, Rational day) {
  final civil = civilFromDays(day.floor());
  final baseCivil = civilFromDays(base.floor());
  final freq = rule['FREQ'];
  final byMonth = rule['BYMONTH'];
  final months = byMonth != null
      ? byMonth.split(',').map(int.parse).toSet()
      : (freq == 'YEARLY' ? {baseCivil.month} : null);
  if (months != null && !months.contains(civil.month)) return false;
  if (freq == 'WEEKLY') {
    final byDay = rule['BYDAY'];
    final selected = byDay == null ? <int>{} : _weekdays(byDay);
    if (selected.isEmpty) selected.add(_weekdayOf(base.floor()));
    if (!selected.contains(_weekdayOf(day.floor()))) return false;
    final byMonthDay = rule['BYMONTHDAY'];
    return byMonthDay == null || _dayNamed(byMonthDay, civil);
  }
  if (rule['BYMONTHDAY'] == null && rule['BYDAY'] == null) {
    return freq != 'MONTHLY' && freq != 'YEARLY' || civil.day == baseCivil.day;
  }
  return _dayAllowed(rule, baseCivil.day, civil);
}

// Which cycle of the rule a day falls in, in the frequency's own unit.
BigInt _cycleOf(RRule rule, Rational day) {
  final whole = day.floor();
  final civil = civilFromDays(whole);
  switch (rule['FREQ']) {
    case 'WEEKLY':
      return floorDiv(whole - BigInt.from((_weekdayOf(whole) - 1) % 7), BigInt.from(7));
    case 'MONTHLY':
      return civil.year * BigInt.from(12) + BigInt.from(civil.month - 1);
    case 'YEARLY':
      return civil.year;
  }
  return whole;
}

// --- Generators ---------------------------------------------------------------

List<T> _pick<T>(Random r, List<T> from) {
  final picked = [
    for (final item in from)
      if (r.nextBool()) item,
  ];
  return picked.isEmpty ? [from[r.nextInt(from.length)]] : picked;
}

// Negatives count back from the month's own end. `productive` stays inside 28 so
// every named day exists in every month, which is what the exact-count
// properties need.
List<int> _monthDays(Random r, bool productive) {
  final span = productive ? 28 : 34;
  return {for (var i = 0; i <= r.nextInt(3); i++) (r.nextBool() ? 1 : -1) * (1 + r.nextInt(span))}
      .toList();
}

List<String> _byDayTokens(Random r, bool productive) {
  final ordinals = productive
      ? const ['1', '2', '3', '4', '-1', '-2', '-3', '-4', '+2']
      : const ['1', '5', '6', '-1', '-5', '0', '+3', '-6'];
  return [
    for (final code in _pick(r, _codes))
      r.nextBool() ? code : '${ordinals[r.nextInt(ordinals.length)]}$code',
  ];
}

Rational _randomBase(Random r, {int dayCap = 31}) {
  final year = BigInt.from(r.nextInt(6000) - 2000);
  final month = 1 + r.nextInt(12);
  final day = 1 + r.nextInt(min(dayCap, daysInMonth(year, month)));
  final date = Rational(daysFromCivil(year, month, day));
  if (r.nextBool()) return date;
  return date +
      Rational.fromInt(r.nextInt(24), 24) +
      Rational.fromInt(r.nextInt(60), 1440) +
      Rational.fromInt(r.nextInt(60), 86400);
}

// A rule inside the grammar this build implements. `productive` narrows the BY*
// parts to shapes that name at least one day in every cycle -- without that, a
// rule like BYMONTHDAY=31;BYDAY=SU can skip years, and no property may claim an
// exact occurrence count.
RRule _randomRule(Random r, {bool productive = false}) {
  final freq = _freqs[r.nextInt(_freqs.length)];
  final rule = <String, String>{'FREQ': freq};
  if (r.nextBool()) rule['INTERVAL'] = '${1 + r.nextInt(4)}';
  if (freq == 'WEEKLY' && r.nextInt(3) > 0) {
    rule['BYDAY'] = _pick(r, _codes).join(',');
  } else if (freq == 'MONTHLY' || freq == 'YEARLY') {
    // Shape 2 is the base's own day of the month, which names no BY* part at
    // all. Shape 3 intersects BYMONTHDAY with BYDAY and can therefore name no
    // day at all in a given month, so it is out of the productive grammar.
    final shape = r.nextInt(productive ? 3 : 4);
    if (shape == 0 || shape == 3) {
      rule['BYMONTHDAY'] = _monthDays(r, productive).join(',');
    }
    if (shape == 1) rule['BYDAY'] = _byDayTokens(r, productive).join(',');
    if (shape == 3) rule['BYDAY'] = _pick(r, _codes).join(',');
  }
  // Parts the frequency LIMITS rather than expands. A limit can empty a whole
  // cycle, so it is outside the productive grammar the exact-count properties
  // need -- but it must hold of every occurrence just the same.
  if (freq == 'YEARLY' ? r.nextBool() : !productive && r.nextInt(3) == 0) {
    rule['BYMONTH'] = _pick(r, _monthCodes).join(',');
  }
  if (!productive && r.nextInt(3) == 0) {
    if (freq == 'DAILY') rule['BYDAY'] = _pick(r, _codes).join(',');
    if (freq == 'DAILY' || freq == 'WEEKLY') {
      rule['BYMONTHDAY'] = _monthDays(r, false).join(',');
    }
  }
  return rule;
}

// A part this frequency limits rather than expands, and that the rule does not
// already write -- adding one may only narrow what the rule names.
MapEntry<String, String>? _limitingPart(Random r, RRule rule) {
  final freq = rule['FREQ'];
  final choices = <MapEntry<String, String>>[
    if (freq != 'YEARLY' && rule['BYMONTH'] == null)
      MapEntry('BYMONTH', _pick(r, _monthCodes).join(',')),
    if ((freq == 'DAILY' || freq == 'WEEKLY') && rule['BYMONTHDAY'] == null)
      MapEntry('BYMONTHDAY', _monthDays(r, false).join(',')),
    if (freq == 'DAILY' && rule['BYDAY'] == null) MapEntry('BYDAY', _pick(r, _codes).join(',')),
  ];
  return choices.isEmpty ? null : choices[r.nextInt(choices.length)];
}

int _period(RRule rule) => _cycleDays[rule['FREQ']]! * int.parse(rule['INTERVAL'] ?? '1');

// A window that starts up to two cycles either side of the base -- before it to
// exercise the plain walk, after it to exercise the skip-ahead.
({Rational lower, Rational upper}) _window(Random r, RRule rule, Rational base) {
  final period = _period(rule);
  final cycles = 3 + r.nextInt(_cycleCap[rule['FREQ']]!);
  return (
    lower: base + Rational(BigInt.from((r.nextInt(5) - 2) * period)),
    upper: base + Rational(BigInt.from(cycles * period)),
  );
}

List<Rational> _days(
  RRule rule,
  Rational base,
  Rational lower,
  Rational upper, {
  Rational? until,
  Set<String> excluded = const {},
  int limit = noOccurrenceLimit,
}) => ruleOccurrenceDays(
  rule,
  base,
  lower,
  upper,
  isRegisteredScale: _gregorianOnly,
  until: until,
  excluded: excluded,
  limit: limit,
);

String _civilText(Rational day) {
  final civil = civilFromDays(day.floor());
  final month = '${civil.month}'.padLeft(2, '0');
  return '${civil.year}-$month-${'${civil.day}'.padLeft(2, '0')}';
}

RRule _parseRule(String text) => {
  for (final part in text.split(';'))
    part.substring(0, part.indexOf('=')): part.substring(part.indexOf('=') + 1),
};

// The JavaScript spec drove these through the ICS importer and the engine; the
// same claim here is DTSTART parsed by `compactIcsDay` and a 2026-2028 window.
List<String> _expand(
  String rrule,
  String dtstart, {
  String from = '20260101',
  String to = '20280101',
  ScaleRegistry? scales,
}) => ruleOccurrenceDays(
  _parseRule(rrule),
  compactIcsDay(dtstart)!,
  compactIcsDay(from)!,
  compactIcsDay(to)!,
  isRegisteredScale: scales ?? _gregorianOnly,
).map(_civilText).toList();

void main() {
  group('compactIcsDay', () {
    test('reads the wire format in the wire format\'s own units', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final year = BigInt.from(r.nextInt(8000) - 2000);
        final month = 1 + r.nextInt(12);
        final day = 1 + r.nextInt(daysInMonth(year, month));
        final hour = r.nextInt(24), minute = r.nextInt(60), second = r.nextInt(60);
        final sign = year.isNegative ? '-' : '';
        final digits = year.abs().toString().padLeft(4, '0');
        final date = '$sign$digits${'$month'.padLeft(2, '0')}${'$day'.padLeft(2, '0')}';
        final time =
            '${'$hour'.padLeft(2, '0')}${'$minute'.padLeft(2, '0')}'
            '${'$second'.padLeft(2, '0')}';
        final whole = Rational(daysFromCivil(year, month, day));
        expect(compactIcsDay(date), whole);
        expect(
          compactIcsDay('${date}T${time}Z'),
          whole +
              Rational.fromInt(hour, 24) +
              Rational.fromInt(minute, 1440) +
              Rational.fromInt(second, 86400),
        );
        expect(compactIcsDay('${date}T$time'), compactIcsDay('${date}T${time}Z'));
      }
    });

    test('refuses anything that is not a compact stamp', () {
      for (final text in ['', '2026-01-05', '202601', 'rubbish', '20260105T0900']) {
        expect(compactIcsDay(text), isNull, reason: text);
      }
      expect(compactIcsDay(null), isNull);
    });
  });

  group('expansion', () {
    test('every occurrence satisfies its rule and rides the base\'s time', () {
      final r = Random(specSeed + 1);
      var seen = 0;
      for (var i = 0; i < iterations; i++) {
        final rule = _randomRule(r);
        final base = _randomBase(r);
        final window = _window(r, rule, base);
        final time = base - Rational(base.floor());
        final days = _days(rule, base, window.lower, window.upper, limit: 2000);
        seen += days.length;
        for (final day in days) {
          expect(_satisfies(rule, base, day), isTrue, reason: '$rule $base $day');
          expect(day >= base, isTrue, reason: 'never before the base');
          expect(day >= window.lower && day <= window.upper, isTrue);
          expect(day - Rational(day.floor()), time);
        }
      }
      // A property that would pass on empty expansions proves nothing.
      expect(seen, greaterThan(10 * iterations));
    });

    test('occurrences are strictly increasing', () {
      final r = Random(specSeed + 2);
      for (var i = 0; i < iterations; i++) {
        final rule = _randomRule(r);
        final base = _randomBase(r);
        final window = _window(r, rule, base);
        final days = _days(rule, base, window.lower, window.upper, limit: 2000);
        for (var k = 1; k < days.length; k++) {
          expect(days[k] > days[k - 1], isTrue, reason: '$rule at $k');
        }
      }
    });

    test('INTERVAL spacing holds: every occurrence lands on a rule cycle', () {
      final r = Random(specSeed + 3);
      for (var i = 0; i < iterations; i++) {
        final rule = _randomRule(r);
        final base = _randomBase(r);
        final window = _window(r, rule, base);
        final interval = BigInt.parse(rule['INTERVAL'] ?? '1');
        final baseCycle = _cycleOf(rule, base);
        for (final day in _days(rule, base, window.lower, window.upper, limit: 2000)) {
          final distance = _cycleOf(rule, day) - baseCycle;
          expect(floorMod(distance, interval), BigInt.zero, reason: '$rule $base $day');
        }
      }
    });

    test('the same rule expands identically every time', () {
      final r = Random(specSeed + 4);
      for (var i = 0; i < iterations; i++) {
        final rule = _randomRule(r);
        final base = _randomBase(r);
        final window = _window(r, rule, base);
        final once = _days(rule, base, window.lower, window.upper, limit: 2000);
        final twice = _days({...rule}, base, window.lower, window.upper, limit: 2000);
        expect(twice, once);
      }
    });

    test('a windowed expansion equals the walk from the base, filtered', () {
      final r = Random(specSeed + 5);
      for (var i = 0; i < iterations; i++) {
        final rule = _randomRule(r);
        final base = _randomBase(r);
        final window = _window(r, rule, base);
        final windowed = _days(rule, base, window.lower, window.upper);
        final walked = _days(rule, base, base, window.upper);
        expect(windowed, walked.where((day) => day >= window.lower).toList());
      }
    });

    test('a limiting part only ever narrows what a rule names', () {
      final r = Random(specSeed + 6);
      var exercised = 0;
      for (var i = 0; i < iterations; i++) {
        final rule = _randomRule(r);
        final base = _randomBase(r);
        final window = _window(r, rule, base);
        final part = _limitingPart(r, rule);
        if (part == null) continue;
        exercised++;
        final all = _days(rule, base, window.lower, window.upper, limit: 2000);
        final narrowed = _days(
          {...rule, part.key: part.value},
          base,
          window.lower,
          window.upper,
          limit: 2000,
        );
        expect(narrowed.length, lessThanOrEqualTo(all.length));
        for (final day in narrowed) {
          expect(all.contains(day), isTrue, reason: '${part.key}=${part.value} invented $day');
        }
      }
      expect(exercised, greaterThan(iterations ~/ 4));
    });

    test('DAILY with BYDAY is WEEKLY with BYDAY, where the RFC makes them one', () {
      final r = Random(specSeed + 13);
      for (var i = 0; i < iterations; i++) {
        final byDay = _pick(r, _codes).join(',');
        final base = _randomBase(r);
        final upper = base + Rational(BigInt.from(7 * (3 + r.nextInt(40))));
        // At INTERVAL=1 both name every selected weekday at or after the base:
        // one expands inside the week, the other limits the day, and the
        // occurrence set cannot tell the difference.
        expect(
          _days({'FREQ': 'DAILY', 'BYDAY': byDay}, base, base, upper),
          _days({'FREQ': 'WEEKLY', 'BYDAY': byDay}, base, base, upper),
          reason: 'BYDAY=$byDay from $base',
        );
      }
    });

    test('a limit truncates the expansion and nothing else', () {
      final r = Random(specSeed + 7);
      for (var i = 0; i < iterations; i++) {
        final rule = _randomRule(r);
        final base = _randomBase(r);
        final window = _window(r, rule, base);
        final all = _days(rule, base, window.lower, window.upper, limit: 2000);
        final limit = 1 + r.nextInt(6);
        expect(
          _days(rule, base, window.lower, window.upper, limit: limit),
          all.take(limit).toList(),
        );
      }
    });
  });

  group('ending a rule', () {
    test('COUNT emits exactly COUNT, counted from the base', () {
      final r = Random(specSeed + 8);
      for (var i = 0; i < iterations; i++) {
        final rule = _randomRule(r, productive: true);
        final base = _randomBase(r, dayCap: 28);
        final count = 1 + r.nextInt(10);
        rule['COUNT'] = '$count';
        final period = BigInt.from(_period(rule));
        final days = _days(
          rule,
          base,
          base - Rational(period),
          base + Rational(period * BigInt.from(count + 2)),
        );
        expect(days.length, count, reason: '$rule from $base');
        if (_satisfies(rule, base, base)) {
          expect(days.first, base, reason: 'the base is occurrence one');
        }
      }
    });

    test('COUNT is counted from the base even when the window starts later', () {
      final r = Random(specSeed + 9);
      for (var i = 0; i < iterations; i++) {
        final rule = _randomRule(r, productive: true);
        final base = _randomBase(r, dayCap: 28);
        final count = 1 + r.nextInt(6);
        rule['COUNT'] = '$count';
        final period = BigInt.from(_period(rule));
        final all = _days(rule, base, base, base + Rational(period * BigInt.from(count + 2)));
        // A window opening after the last counted occurrence sees nothing: the
        // count belongs to the rule, not to the query.
        final after = all.last + Rational(BigInt.one);
        expect(_days(rule, base, after, after + Rational(period * BigInt.from(20))), isEmpty);
      }
    });

    test('UNTIL runs through the whole of the day it names, and no further', () {
      final r = Random(specSeed + 10);
      var exercised = 0;
      for (var i = 0; i < iterations; i++) {
        final rule = _randomRule(r, productive: true);
        final base = _randomBase(r, dayCap: 28);
        final upper = base + Rational(BigInt.from(_period(rule) * 14));
        final all = _days(rule, base, base, upper);
        if (all.length < 3) continue;
        exercised++;
        final index = 1 + r.nextInt(all.length - 2);
        final until = recurrenceUntilForDate(_civilText(all[index]));
        expect(until.endsWith('T235959'), isTrue);
        expect(
          _days(rule, base, base, upper, until: compactIcsDay(until)),
          all.sublist(0, index + 1),
          reason: 'inclusive through $until',
        );
        // The same date at midnight is the off-by-one `recurrenceUntilForDate`
        // exists to avoid: it drops that date's own timed occurrence.
        if (base > Rational(base.floor())) {
          expect(
            _days(rule, base, base, upper, until: Rational(all[index].floor())),
            all.sublist(0, index),
          );
        }
      }
      expect(exercised, greaterThan(iterations ~/ 2));
    });

    test('EXDATE removes exactly the days it names', () {
      final r = Random(specSeed + 11);
      for (var i = 0; i < iterations; i++) {
        final rule = _randomRule(r);
        final base = _randomBase(r);
        final window = _window(r, rule, base);
        final all = _days(rule, base, window.lower, window.upper, limit: 2000);
        if (all.isEmpty) continue;
        final removed = {
          for (final day in all)
            if (r.nextInt(3) == 0) day.toJson(),
        };
        // Keys no occurrence falls on cannot change the expansion.
        final noise = {
          Rational(all.first.floor() - BigInt.from(1 + r.nextInt(9))).toJson(),
          'not-a-day',
        };
        expect(
          _days(
            rule,
            base,
            window.lower,
            window.upper,
            excluded: {...removed, ...noise},
            limit: 2000,
          ),
          all.where((day) => !removed.contains(day.toJson())).toList(),
        );
      }
    });
  });

  group('refusals', () {
    test('RULED ANCHOR: an unregistered RSCALE is refused, the calendar named', () {
      final plain = _expand('FREQ=WEEKLY;COUNT=3', '20260105T090000Z');
      expect(plain, ['2026-01-05', '2026-01-12', '2026-01-19']);
      for (final scale in ['GREGORIAN', 'GREGORY', 'gregory']) {
        expect(
          _expand('RSCALE=$scale;FREQ=WEEKLY;COUNT=3', '20260105T090000Z'),
          plain,
          reason: 'a registered scale resolves exactly as FREQ alone',
        );
      }
      expect(
        () => _expand('RSCALE=HEBREW;FREQ=YEARLY;COUNT=3', '20260101T090000Z'),
        throwsA(
          isA<RecurrenceRefusal>().having(
            (error) => error.message,
            'message',
            allOf(contains('RSCALE=HEBREW'), contains('cannot be projected')),
          ),
        ),
      );
      // The rule survives the refusal: it is kept exactly as written, never
      // rewritten into something projectable.
      final rule = _parseRule('RSCALE=HEBREW;FREQ=YEARLY;COUNT=3');
      expect(
        () =>
            _days(rule, Rational(BigInt.zero), Rational(BigInt.zero), Rational(BigInt.from(1000))),
        throwsA(isA<RecurrenceRefusal>()),
      );
      expect(rule, {'RSCALE': 'HEBREW', 'FREQ': 'YEARLY', 'COUNT': '3'});
    });

    test('a registered scale is the only thing that passes the gate', () {
      final r = Random(specSeed + 12);
      for (var i = 0; i < iterations; i++) {
        final rule = _randomRule(r);
        final base = _randomBase(r);
        final window = _window(r, rule, base);
        expect(
          unsupportedCalendarScale(rule, _nothingRegistered),
          isNull,
          reason: 'no RSCALE is not an unregistered RSCALE',
        );
        rule['RSCALE'] = ['HEBREW', 'ISLAMIC-CIVIL', 'CHINESE', 'ETHIOPIC'][r.nextInt(4)];
        expect(
          () => _days(rule, base, window.lower, window.upper),
          throwsA(isA<RecurrenceRefusal>()),
        );
        expect(
          unsupportedCalendarScale(rule, _gregorianOnly),
          contains('RSCALE=${rule['RSCALE']}'),
        );
      }
    });

    test('a part the standards define and this build lacks is refused, named', () {
      final r = Random(specSeed + 14);
      for (var i = 0; i < iterations; i++) {
        final rule = _randomRule(r);
        final base = _randomBase(r);
        final window = _window(r, rule, base);
        // THE PARTS THIS BUILD REALLY LACKS, asked of the build. A copy here
        // went stale the day BYSETPOS and WKST were implemented, and a spec
        // asserting a snapshot asserts nothing.
        final part = unimplementedRuleParts[r.nextInt(unimplementedRuleParts.length)];
        final value = '${1 + r.nextInt(9)}';
        rule[part] = value;
        expect(
          () => _days(rule, base, window.lower, window.upper),
          throwsA(
            isA<RecurrenceRefusal>().having(
              (error) => error.message,
              'message',
              allOf(contains('$part=$value'), contains('cannot be projected')),
            ),
          ),
          reason: part,
        );
        // Blank is not written, here as everywhere else in the rule.
        rule[part] = '';
        expect(() => _days(rule, base, window.lower, window.upper), returnsNormally);
      }
    });

    test('a key no standard defines as occurrence-affecting stays inert', () {
      final r = Random(specSeed + 15);
      for (var i = 0; i < iterations; i++) {
        final rule = _randomRule(r);
        final base = _randomBase(r);
        final window = _window(r, rule, base);
        // Refusing what cannot change the answer would refuse every file with a
        // vendor extension in it.
        final noisy = {
          ...rule,
          'X-CHRONOLOG-FRAME': 'calendar:personal',
          'X-WR-CALNAME': 'Rules',
          'NONSENSE': '${r.nextInt(99)}',
        };
        expect(
          _days(noisy, base, window.lower, window.upper, limit: 2000),
          _days(rule, base, window.lower, window.upper, limit: 2000),
        );
      }
    });

    test('RULED ANCHOR: sub-day and unknown frequencies are refused', () {
      for (final freq in ['HOURLY', 'MINUTELY', 'SECONDLY', 'BOGUS']) {
        expect(
          () => _expand('FREQ=$freq;COUNT=3', '20260101T090000Z'),
          throwsA(
            isA<RecurrenceRefusal>().having(
              (error) => error.message,
              'message',
              allOf(contains('Unsupported FREQ'), contains(freq)),
            ),
          ),
          reason: freq,
        );
      }
      expect(
        () => _days(
          {'COUNT': '3'},
          Rational(BigInt.zero),
          Rational(BigInt.zero),
          Rational(BigInt.from(100)),
        ),
        throwsA(
          isA<RecurrenceRefusal>().having(
            (error) => error.message,
            'message',
            contains('(missing)'),
          ),
        ),
      );
    });

    test('RULED ANCHOR: a non-positive INTERVAL is refused, never looped', () {
      for (final interval in ['0', '-1', '-999']) {
        expect(
          () => _expand('FREQ=DAILY;INTERVAL=$interval;COUNT=5', '20260101'),
          throwsA(
            isA<RecurrenceRefusal>().having(
              (error) => error.message,
              'message',
              contains('INTERVAL'),
            ),
          ),
          reason: interval,
        );
      }
    });

    test('RULED ANCHOR: a pathological COUNT is refused before it can lock up', () {
      expect(
        () => _expand('FREQ=DAILY;COUNT=999999999999', '20260101'),
        throwsA(
          isA<RecurrenceRefusal>().having(
            (error) => error.message,
            'message',
            contains('safe limit'),
          ),
        ),
      );
      // The limit itself is usable, so the refusal is a cap and not a ceiling
      // one occurrence too low.
      expect(_expand('FREQ=DAILY;COUNT=10000', '20260101').length, 731);
    });
  });

  // Worked examples the JavaScript spec quotes. They are anchors, not
  // properties: each one pins a reading of RFC 5545 that the properties above
  // quantify over but cannot name.
  group('RULED ANCHOR: the worked examples', () {
    const start = '20260105T090000Z';
    test('WEEKLY with COUNT and INTERVAL', () {
      final weekly = _expand('FREQ=WEEKLY;COUNT=8', start);
      expect(weekly.length, 8);
      expect(weekly.first, '2026-01-05');
      expect(weekly.last, '2026-02-23');
      expect(_expand('FREQ=WEEKLY;INTERVAL=2;COUNT=3', start), [
        '2026-01-05',
        '2026-01-19',
        '2026-02-02',
      ]);
      expect(_expand('FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=5', start), [
        '2026-01-05',
        '2026-01-07',
        '2026-01-09',
        '2026-01-12',
        '2026-01-14',
      ]);
    });

    test('COUNT counts emitted occurrences, not generator cycles', () {
      expect(_expand('FREQ=MONTHLY;BYMONTHDAY=1,15;COUNT=4', '20260101T090000Z'), [
        '2026-01-01',
        '2026-01-15',
        '2026-02-01',
        '2026-02-15',
      ]);
      final long = _expand('FREQ=MONTHLY;BYMONTHDAY=31;COUNT=12', '20260131T090000Z');
      expect(long.length, 12);
      expect(long.last, '2027-08-31');
    });

    test('a COUNT window that opens after the count is spent sees nothing', () {
      expect(
        _expand('FREQ=DAILY;COUNT=5', '20260101T090000Z', from: '20260201', to: '20260301'),
        isEmpty,
      );
    });

    test('a windowed rule without COUNT fast-forwards, INTERVAL intact', () {
      expect(_expand('FREQ=WEEKLY;INTERVAL=2', start, from: '20260201', to: '20260301'), [
        '2026-02-02',
        '2026-02-16',
      ]);
    });

    test('MONTHLY BYDAY ordinals, positive and negative', () {
      expect(_expand('FREQ=MONTHLY;BYDAY=2TU;COUNT=3', '20260113T090000Z'), [
        '2026-01-13',
        '2026-02-10',
        '2026-03-10',
      ]);
      expect(_expand('FREQ=MONTHLY;BYDAY=-1FR;COUNT=2', '20260130T090000Z'), [
        '2026-01-30',
        '2026-02-27',
      ]);
      expect(_expand('FREQ=MONTHLY;BYDAY=TU;COUNT=5', '20260106T090000Z'), [
        '2026-01-06',
        '2026-01-13',
        '2026-01-20',
        '2026-01-27',
        '2026-02-03',
      ]);
    });

    test('YEARLY expands BYMONTH against BYMONTHDAY', () {
      expect(_expand('FREQ=YEARLY;BYMONTH=3,9;BYMONTHDAY=1,15;COUNT=6', '20260301T090000Z'), [
        '2026-03-01',
        '2026-03-15',
        '2026-09-01',
        '2026-09-15',
        '2027-03-01',
        '2027-03-15',
      ]);
    });

    test('an inclusive cap keeps the occurrence it names, drops every later one', () {
      final rule = _parseRule('FREQ=WEEKLY;COUNT=8');
      final base = compactIcsDay(start)!;
      final lower = compactIcsDay('20260101')!;
      final upper = compactIcsDay('20280101')!;
      expect(_days(rule, base, lower, upper).length, 8);

      // The editor's own path: switching to a date drops COUNT, and the ICS
      // value it writes lands at the last second of the chosen day.
      final capped = applyRecurrenceEnd(
        rule,
        mode: RecurrenceEnd.until,
        until: recurrenceUntilForCoordinate(const {
          'year': '2026',
          'month': '1',
          'day': '19',
          'hour': '9',
        }),
      );
      expect(capped['COUNT'], isNull);
      expect(capped['UNTIL'], '20260119T090000');
      expect(
        _days(capped, base, lower, upper, until: compactIcsDay(capped['UNTIL'])).map(_civilText),
        ['2026-01-05', '2026-01-12', '2026-01-19'],
      );

      final dated = applyRecurrenceEnd(rule, mode: RecurrenceEnd.until, until: '2026-01-19');
      expect(dated['UNTIL'], '20260119T235959');
      expect(
        _days(dated, base, lower, upper, until: compactIcsDay(dated['UNTIL'])).map(_civilText),
        ['2026-01-05', '2026-01-12', '2026-01-19'],
      );
      // A midnight UNTIL on the chosen date would have dropped it.
      expect(_days(rule, base, lower, upper, until: compactIcsDay('20260119')).map(_civilText), [
        '2026-01-05',
        '2026-01-12',
      ]);
      // And "never" runs past the old count entirely.
      final never = applyRecurrenceEnd(rule);
      expect(_days(never, base, lower, upper).length, greaterThan(8));
    });
  });
}
