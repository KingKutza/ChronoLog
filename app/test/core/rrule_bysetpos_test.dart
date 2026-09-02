// THE SECOND MONDAY PROJECTS (ISSUES 9.2, the import wall of errors).
//
// Don's Work calendar carries sixteen rules of the form
// `FREQ=MONTHLY;BYDAY=MO;BYSETPOS=2` -- Outlook's ordinary spelling for "the
// second Monday of the month" -- and BYSETPOS sat in the engine's unimplemented
// list, so sixteen series refused to project. The rule:
//
//   BYSETPOS is RFC 5545's filter over the expanded set: the nth (or the -nth)
//   of the candidates the rule already computes. A BYSETPOS rule projects the
//   same occurrences a reference expansion gives, and WKST lands with it,
//   because it changes what "every two weeks" means.
//
// Generative: a random weekday, a random position including -1, a random year.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/rrule.dart';
import 'package:test/test.dart';

final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

const List<String> codes = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];

/// 1970-01-01 was a Thursday; Sunday is 0.
int weekdayOf(BigInt day) => ((day + BigInt.from(4)) % BigInt.from(7)).toInt();

BigInt firstOf(int year, int month) => month == 13
    ? daysFromCivil(BigInt.from(year + 1), 1, 1)
    : daysFromCivil(BigInt.from(year), month, 1);

/// The days in [year]/[month] that fall on [weekday], in order.
List<BigInt> weekdaysIn(int year, int month, int weekday) {
  final first = firstOf(year, month), next = firstOf(year, month + 1);
  return [
    for (var day = first; day < next; day += BigInt.one)
      if (weekdayOf(day) == weekday) day,
  ];
}

void main() {
  // ignore: avoid_print
  print('BYSETPOS RUN SEED: $runSeed  (set CHRONOLOG_SEED=$runSeed to reproduce)');
  final random = Random(runSeed);

  test('FREQ=MONTHLY;BYDAY=xx;BYSETPOS=n projects the nth weekday of every month', () {
    final weekday = random.nextInt(7);
    final position = random.nextBool() ? -1 : 1 + random.nextInt(4);
    final year = 2000 + random.nextInt(60);
    final expected = <BigInt>{};
    for (var month = 1; month <= 12; month += 1) {
      final candidates = weekdaysIn(year, month, weekday);
      final index = position > 0 ? position - 1 : candidates.length + position;
      if (index >= 0 && index < candidates.length) expected.add(candidates[index]);
    }
    final base = expected.reduce((a, b) => a < b ? a : b);
    final RRule rule = {'FREQ': 'MONTHLY', 'BYDAY': codes[weekday], 'BYSETPOS': '$position'};
    late List<Rational> projected;
    try {
      projected = ruleOccurrenceDays(
        rule,
        Rational(base),
        Rational(firstOf(year, 1)),
        Rational(firstOf(year, 13)),
        isRegisteredScale: (_) => true,
      );
    } on RecurrenceRefusal catch (refusal) {
      fail(
        'ISSUES 9.2: the rule refused instead of projecting -- "${refusal.message}". '
        'BYSETPOS is an index into the candidates the engine already computes.',
      );
    }
    expect(
      {for (final day in projected) day.floor()},
      equals(expected),
      reason:
          'ISSUES 9.2: BYSETPOS=$position of ${codes[weekday]} in $year must be exactly the '
          'reference expansion (${expected.length} occurrences).',
    );
  });

  test('WKST decides which week an interval counts from', () {
    // A Saturday+Sunday rule every second week: with WKST=SU the pair sits in one
    // week; with WKST=MO it straddles two, so the SECOND week's Sunday is skipped.
    final year = 2000 + random.nextInt(60);
    final base = weekdaysIn(year, 1, 6).first; // the first Saturday of January
    for (final wkst in const ['SU', 'MO']) {
      final RRule rule = {'FREQ': 'WEEKLY', 'INTERVAL': '2', 'BYDAY': 'SA,SU', 'WKST': wkst};
      try {
        final days = ruleOccurrenceDays(
          rule,
          Rational(base),
          Rational(base),
          Rational(base + BigInt.from(28)),
          isRegisteredScale: (_) => true,
        );
        expect(days, isNotEmpty, reason: 'a WKST=$wkst rule must project');
      } on RecurrenceRefusal catch (refusal) {
        fail('ISSUES 9.2: WKST=$wkst refused -- "${refusal.message}". WKST lands with BYSETPOS.');
      }
    }
  });
}
