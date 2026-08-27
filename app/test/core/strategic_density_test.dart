// The per-day fact budget.
//
// The property is the one the whole mechanism exists for: however the facts fall,
// EVERY day in the range is represented, no day spends more than the budget, and
// a truncated day's count reads as a lower bound. A first busy week that ate the
// allowance would show up here as a missing date, which is exactly the failure
// the topology view cannot afford.
//
// The budget arrives as a parameter and this spec never names a number of its
// own: no arbitrary integer caps.

import 'dart:math';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/strategic_density.dart';
import 'package:test/test.dart';

import 'corpus.dart';

typedef Fact = ({String id, Rational day, String virtualId, String relation});

FactIdentity _identify(Fact fact) =>
    (day: fact.day, event: fact.id, virtualId: fact.virtualId, relation: fact.relation);

void main() {
  test('random ranges: every day is represented, none overspends', () {
    for (final seed in seeds(60)) {
      final random = Random(seed);
      final start = random.nextInt(400) - 200;
      final span = 1 + random.nextInt(30);
      final budget = 1 + random.nextInt(6);
      final asked = <String>[];
      final produced = <String, int>{};
      final plan = aggregateDensity<Fact>(
        start: '$start',
        end: '${start + span}',
        perDayBudget: budget,
        identify: _identify,
        queryDay: (day, after, given) {
          expect(given, budget, reason: 'seed $seed: the budget is per day');
          expect(after, day + BigInt.one, reason: 'seed $seed: one whole day');
          asked.add('$day');
          // Some days are empty, some are crowded well past the budget.
          final wanted = random.nextInt(3) == 0 ? 0 : random.nextInt(budget * 3);
          final shown = wanted > budget ? budget : wanted;
          produced['$day'] = shown;
          return (
            facts: [
              for (var index = 0; index < shown; index++)
                (
                  id: 'event:${random.nextInt(99)}',
                  day: Rational(day),
                  virtualId: '',
                  relation: 'relation:${random.nextInt(99)}',
                ),
            ],
            truncated: wanted > budget,
            errors: const [],
          );
        },
      );
      // Every day in the range, in order, none skipped and none doubled.
      expect(plan.days, hasLength(span), reason: 'seed $seed');
      expect([for (final day in plan.days) '${day.day}'], asked, reason: 'seed $seed');
      expect(plan.perDayBudget, budget);
      for (final day in plan.days) {
        expect(day.facts.length, lessThanOrEqualTo(budget), reason: 'seed $seed');
        expect(day.facts.length, produced['${day.day}'], reason: 'seed $seed');
        // A LOWER BOUND, never a claim to know how many were dropped, and never
        // a date that quietly vanished.
        expect(day.minimum, day.facts.length + (day.truncated ? 1 : 0));
        expect(day.minimum, greaterThanOrEqualTo(day.facts.length));
        final keys = [for (final fact in day.facts) stableFactKey(_identify(fact))];
        expect(keys, orderedEquals([...keys]..sort()), reason: 'seed $seed');
      }
    }
  });

  test('the tie-break is total and stable under any input order', () {
    for (final seed in seeds(40)) {
      final random = Random(seed);
      final facts = <Fact>[
        for (var index = 0; index < 2 + random.nextInt(20); index++)
          (
            // Deliberately few distinct days and ids, so ties are common.
            id: 'event:${random.nextInt(3)}',
            day: Rational(BigInt.from(random.nextInt(3)), BigInt.from(1 + random.nextInt(3))),
            virtualId: random.nextBool() ? '' : 'pattern:1/${random.nextInt(3)}',
            relation: 'relation:${random.nextInt(3)}',
          ),
      ];
      final once = stableFacts(facts, _identify);
      final shuffled = [...facts]..shuffle(random);
      final twice = stableFacts(shuffled, _identify);
      expect(
        [for (final fact in twice) stableFactKey(_identify(fact))],
        [for (final fact in once) stableFactKey(_identify(fact))],
        reason: 'seed $seed: the order does not depend on the input order',
      );
      // The source list is never mutated.
      expect(facts.length, once.length);
    }
  });

  test('RULED ANCHOR: dense days keep their place, and their counts are floors', () {
    final plan = aggregateDensity<Fact>(
      start: 10,
      end: 13,
      perDayBudget: 2,
      identify: _identify,
      queryDay: (day, _, limit) {
        expect(limit, 2);
        Fact fact(String id) => (id: id, day: Rational(day), virtualId: '', relation: '');
        final rows = <String, List<Fact>>{
          '10': [fact('b'), fact('a')],
          '11': [fact('late')],
          '12': [fact('d'), fact('c')],
        };
        return (
          facts: rows['$day'] ?? const [],
          truncated: day == BigInt.from(10) || day == BigInt.from(12),
          errors: const [],
        );
      },
    );
    expect([for (final day in plan.days) '${day.day}'], ['10', '11', '12']);
    expect(
      [
        for (final day in plan.days) [for (final fact in day.facts) fact.id],
      ],
      [
        ['a', 'b'],
        ['late'],
        ['c', 'd'],
      ],
    );
    expect(
      [for (final day in plan.days) (day.truncated, day.facts.length, day.minimum)],
      [(true, 2, 3), (false, 1, 1), (true, 2, 3)],
    );
  });

  test('an unresolvable pattern reports once for the range, not once per day', () {
    final plan = aggregateDensity<Fact>(
      start: '0',
      end: '40',
      perDayBudget: 3,
      identify: _identify,
      queryDay: (day, _, _) => (
        facts: const [],
        truncated: false,
        errors: [
          (pattern: 'pattern:broken', message: 'nothing implements that'),
          (pattern: 'pattern:broken', message: 'nothing implements that'),
          if (day == BigInt.zero) (pattern: 'pattern:other', message: 'nothing implements that'),
        ],
      ),
    );
    expect(plan.errors, hasLength(2));
    expect(plan.errors.map((error) => error.pattern), ['pattern:broken', 'pattern:other']);
  });

  test('a fractional range covers every day it touches at all', () {
    final plan = aggregateDensity<Fact>(
      // Half of day 4 through a sliver of day 7: all four days are drawn.
      start: '9/2',
      end: '43/6',
      perDayBudget: 1,
      identify: _identify,
      queryDay: (_, _, _) => (facts: const [], truncated: false, errors: const []),
    );
    expect([for (final day in plan.days) '${day.day}'], ['4', '5', '6', '7']);
    // An empty range asks nothing.
    expect(
      aggregateDensity<Fact>(
        start: '5',
        end: '5',
        perDayBudget: 1,
        identify: _identify,
        queryDay: (_, _, _) => (facts: const [], truncated: false, errors: const []),
      ).days,
      isEmpty,
    );
  });
}
