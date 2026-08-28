// The minimap's boundary label ladder.
//
// LABELS LAND ON REAL BOUNDARIES, never at even fractions of the window. "Q1-26
// Q2-26" has to sit where the quarters actually start or the label is decoration
// rather than a coordinate. The stride is anchored to month zero so a given
// stride always lands on the same boundaries wherever the window sits --
// quarters stay on the first month of each quarter no matter where you panned
// from.
//
// THE FORMAT FOLLOWS THE STRIDE ACTUALLY CHOSEN, not the level asked for, so a
// lens tells the truth about what its labels mark. Intimate reads a clock when
// half-day boundaries fit and a date when they do not, and never grows a year at
// either end, because its ladder stops at week strides. The one level that
// outranks its own stride is `quarter`, whose rungs are month strides but whose
// text is always a quarter.
//
// BUDGETS ARE PER FORMAT, not one number: a quarter packs far tighter than a
// date and a time.
//
// A LAW WITH NO MONTHS GETS NO MONTH RUNG. Not a guessed generic walk -- the
// month rungs are dropped from the ladder outright, so a day-granularity lens
// degrades to the day and hour rungs it CAN compute and a month-granularity one
// reports no ticks rather than placing a label its law cannot place. Likewise a
// day outside every declared era omits its label instead of inventing a year.

import '../../core/exact.dart';
import '../law_context.dart';
import '../tunables.dart';

/// One placed label: where it sits, which format produced it, and its text.
typedef LabelTick = ({Rational days, String format, String text});

/// The FINEST level each lens may label at. A lens never labels more finely than
/// this, and the ladder coarsens from here until the labels fit.
const Map<String, String> labelGranularity = {
  'intimate': 'hour',
  'tactical': 'day',
  'lines': 'day',
  'wall': 'month',
  'strategic': 'quarter',
  'spiral': 'month',
  'radial': 'month',
};

String granularityFor(String lens) => labelGranularity[lens] ?? 'day';

/// Each level's stride ladder, coarsest-fitting first. The hour ladder tops out
/// at a week, which is structurally why Intimate can never print a year.
const Map<String, List<(String, int)>> labelLadders = {
  'hour': [
    ('hour', 1),
    ('hour', 2),
    ('hour', 3),
    ('hour', 4),
    ('hour', 6),
    ('hour', 8),
    ('hour', 12),
    ('day', 1),
    ('day', 2),
    ('day', 7),
  ],
  'day': [('day', 1), ('day', 2), ('day', 3), ('day', 7), ('day', 14), ('month', 1), ('month', 3)],
  'month': [('month', 1), ('month', 2), ('month', 3), ('month', 6), ('month', 12), ('month', 24)],
  'quarter': [('month', 3), ('month', 6), ('month', 12), ('month', 24), ('month', 60)],
};

/// The ticks for one range at one granularity.
///
/// [maxLabels] overrides the per-format budget for a caller that knows its own
/// width; zero means "use the budget". The analytic estimate skips rungs that
/// cannot possibly fit, so a wide range never materializes tens of thousands of
/// boundaries in order to throw them away.
List<LabelTick> labelTicks(
  Rational start,
  Rational end,
  String level,
  LawContext law, {
  int maxLabels = 0,
  Tunable? read,
}) {
  if (end <= start) return const [];
  final ladder = [
    for (final rung in labelLadders[level] ?? labelLadders['day']!)
      if (rung.$1 != 'month' || law.hasMonths) rung,
  ];
  if (ladder.isEmpty) return const [];
  final range = (end - start).toDouble();
  String? format;
  var limit = 0;
  var ticks = <Rational>[];
  for (final (unit, step) in ladder) {
    final chosen = _format(unit, level);
    final budget = maxLabels > 0 ? maxLabels : count(read, 'minimap.budget.$chosen');
    limit = budget < 2 ? 2 : budget;
    if (range / (_strideDays(unit, law) * step) > limit * 2) continue;
    format = chosen;
    ticks = _strideTicks(start, end, unit, step, law);
    if (ticks.length <= limit) break;
  }
  if (format == null) {
    // Nothing on the ladder could fit: the coarsest rung is walked anyway and
    // decimated to the FALLBACK budget, which is tighter than any format's own.
    // A range this wide for this granularity is already past the point where the
    // labels are a coordinate rather than a hint.
    final (unit, step) = ladder.last;
    format = _format(unit, level);
    final budget = maxLabels > 0 ? maxLabels : count(read, 'minimap.budget.fallback');
    limit = budget < 2 ? 2 : budget;
    ticks = _strideTicks(start, end, unit, step, law);
  }
  if (ticks.length > limit) {
    final stride = (ticks.length / limit).ceil();
    ticks = [
      for (final (index, tick) in ticks.indexed)
        if (index % stride == 0) tick,
    ];
  }
  return [
    for (final days in ticks)
      if (labelText(days, format, law) case final String text when text.isNotEmpty)
        (days: days, format: format, text: text),
  ];
}

/// The text one tick carries.
///
/// A law with an era table shows the era-qualified year in place of the
/// two-digit civil one: "Q1-26" asserts nothing true about a calendar whose year
/// is "3E 433". A day outside every declared era comes back EMPTY and is dropped.
String labelText(Rational days, String format, LawContext law) {
  final whole = days.floor();
  final civil = civilFromDays(whole);
  final month = civil.month;
  final shortYear = floorMod(civil.year, BigInt.from(100)).toString().padLeft(2, '0');
  final era = law.hasEras ? law.eraYear(Rational(whole)) : null;
  if (law.hasEras && era == null) return '';
  switch (format) {
    case 'quarter':
      final quarter = (month - 1) ~/ 3 + 1;
      return era == null ? 'Q$quarter-$shortYear' : 'Q$quarter-$era';
    case 'month':
      final name = law.monthShort(month) ?? '';
      return era == null ? "$name '$shortYear" : '$name $era';
    case 'hour':
      final minutes = law.minuteOfDay(days);
      final perHour = law.minutesPerHour;
      final hour = (minutes / perHour).floor() % law.hoursPerDay.round();
      final minute = (minutes % perHour).round();
      final clock = '${'$hour'.padLeft(2, '0')}:${'$minute'.padLeft(2, '0')}';
      return '${law.monthShort(month) ?? ''} ${civil.day} $clock';
    default:
      return '${law.monthShort(month) ?? ''} ${civil.day}';
  }
}

/// Only `quarter` outranks its own stride unit.
String _format(String unit, String level) =>
    level == 'quarter' && unit == 'month' ? 'quarter' : unit;

/// The real day-length of one stride unit. Units compose BOTTOM-UP: an hour does
/// not shrink to a twenty-third on a 23-hour frame -- the DAY moves around a
/// fixed hour -- so this asks the law for the hour's own absolute length. This
/// feeds only the "would this rung fit at all" estimate, so a host double here is
/// a heuristic and never a stored coordinate.
double _strideDays(String unit, LawContext law) {
  if (unit == 'hour') {
    final exact = law.law.unitDays('hour') ?? law.law.meanUnitDays('hour');
    return exact != null ? exact.toDouble() : 1 / law.hoursPerDay.toDouble();
  }
  if (unit == 'month') return law.law.meanMonthDays().toDouble();
  return law.dayDays.toDouble();
}

List<Rational> _strideTicks(Rational start, Rational end, String unit, int step, LawContext law) {
  final all = switch (unit) {
    'month' => _monthStarts(start, end, step),
    'hour' => _hourStarts(start, end, step, law),
    _ => _dayStarts(start, end, step, law),
  };
  return [
    for (final value in all)
      if (value >= start && value <= end) value,
  ];
}

/// The registered Gregorian ladder's own month-boundary walk. A declaration
/// whose month ladder is not Gregorian needs its own walk to land ticks on ITS
/// boundaries; guessing one generically is out of scope, which is exactly why
/// `hasMonths` gates the rung rather than this walk falling back to something.
List<Rational> _monthStarts(Rational start, Rational end, int step) {
  final twelve = BigInt.from(12);
  final first = civilFromDays(start.floor()), last = civilFromDays(end.ceil());
  final stride = BigInt.from(step);
  final from = first.year * twelve + BigInt.from(first.month - 1);
  final to = last.year * twelve + BigInt.from(last.month - 1);
  // Anchored to month zero, so a stride lands on the same boundaries whatever
  // window it was asked from.
  final days = <Rational>[];
  for (var index = from - floorMod(from, stride); index <= to; index += stride) {
    days.add(
      Rational(daysFromCivil(floorDiv(index, twelve), floorMod(index, twelve).toInt() + 1, 1)),
    );
  }
  return days;
}

List<Rational> _dayStarts(Rational start, Rational end, int step, LawContext law) {
  final stride = BigInt.from(step);
  final first = law.dayOf(start), last = law.dayOf(end) + BigInt.one;
  final days = <Rational>[];
  for (var day = first - floorMod(first, stride); day <= last; day += stride) {
    days.add(Rational(day) * law.dayDays);
  }
  return days;
}

/// The step is chosen from a ladder tuned to divide the standard day evenly; a
/// law whose day holds a different number of hours may leave a shorter last slot
/// rather than an exact division, which the ceiling here still reaches the end of
/// the day with instead of falling short.
List<Rational> _hourStarts(Rational start, Rational end, int step, LawContext law) {
  final perDay = law.hoursPerDay.toDouble() / step;
  final slots = perDay < 1 ? 1 : perDay.ceil();
  final first = law.dayOf(start), last = law.dayOf(end) + BigInt.one;
  final days = <Rational>[];
  for (var day = first; day <= last; day += BigInt.one) {
    for (var slot = 0; slot < slots; slot += 1) {
      final offset = Rational.fromInt(slot * step) / law.hoursPerDay * law.dayDays;
      days.add(Rational(day) * law.dayDays + offset);
    }
  }
  return days;
}
