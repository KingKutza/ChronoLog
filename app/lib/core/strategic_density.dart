// Per-day fact budget for the Strategic scale.
//
// Strategic is deliberately a TOPOLOGY view: a very dense calendar must still
// show WHERE activity exists, so the first busy week cannot be allowed to eat the
// whole renderer's fact allowance. The budget is spent per day, which is what
// keeps every date in the range represented.
//
// NO ARBITRARY CAP. The JavaScript hardcoded 48 facts per day; ruling 9 replaced
// the thirteen scattered per-lens caps with ONE magnitude-driven overscale
// budget, so the budget arrives as a parameter and this module holds no number.
//
// `truncated` means the displayed count is a LOWER BOUND -- never that a later
// date quietly vanished from the view.

import 'exact.dart';

/// The four fields a projected fact is ordered by. The tie-break has to be
/// total, deterministic and identical across reload, so it is stated here once
/// rather than left to whatever order a query happened to return.
typedef FactIdentity = ({Rational day, String event, String virtualId, String relation});

/// A refusal a day's query collected. Deduped across the range, because one
/// unresolvable pattern would otherwise report itself once per day drawn.
typedef DensityError = ({String pattern, String message});

typedef DayResult<T> = ({List<T> facts, bool truncated, List<DensityError> errors});

/// Facts for one whole day, given the budget. Small and synchronous on purpose:
/// keeping the bucketing rule out here makes it testable with no renderer.
typedef DayQuery<T> = DayResult<T> Function(BigInt day, BigInt after, int budget);

/// One day's answer. `minimum` is the honest floor -- the shown count plus one
/// when the budget cut the day short -- and the shown count is `facts.length`,
/// stated once rather than carried twice.
typedef DensityDay<T> = ({BigInt day, List<T> facts, bool truncated, int minimum});

/// NUL joins the parts because it is the one character none of them can contain:
/// any printable separator could appear inside a field and make two different
/// facts key alike.
String stableFactKey(FactIdentity fact) =>
    [fact.day.toJson(), fact.event, fact.virtualId, fact.relation].join('\u0000');

List<T> stableFacts<T>(Iterable<T> facts, FactIdentity Function(T) identify) => [...facts]
  ..sort((left, right) => stableFactKey(identify(left)).compareTo(stableFactKey(identify(right))));

({List<DensityDay<T>> days, List<DensityError> errors, int perDayBudget}) aggregateDensity<T>({
  required Object start,
  required Object end,
  required int perDayBudget,
  required DayQuery<T> queryDay,
  required FactIdentity Function(T) identify,
}) {
  final first = _exact(start).floor();
  final after = _exact(end).ceil();
  final days = <DensityDay<T>>[];
  final errors = <String, DensityError>{};
  for (var day = first; day < after; day += BigInt.one) {
    final result = queryDay(day, day + BigInt.one, perDayBudget);
    final facts = stableFacts(result.facts, identify);
    days.add((
      day: day,
      facts: facts,
      truncated: result.truncated,
      // The honest floor: at least one more exists, and we are not claiming to
      // know how many.
      minimum: facts.length + (result.truncated ? 1 : 0),
    ));
    for (final error in result.errors) {
      errors.putIfAbsent('${error.pattern}\u0000${error.message}', () => error);
    }
  }
  return (days: days, errors: errors.values.toList(), perDayBudget: perDayBudget);
}

Rational _exact(Object value) => value is Rational ? value : Rational.parse('$value');
