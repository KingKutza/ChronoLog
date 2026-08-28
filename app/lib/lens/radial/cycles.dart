// Cycle resolution for Radial and Spiral.
//
// STRICTER THAN A DURATION, DELIBERATELY. `law.magnitudeDays` is tolerant by
// contract -- imported data is plausibly dirty and a mean is better than a
// refusal there. Here it is not: a ring drawn on a cycle whose length was
// guessed is a picture of a fact nobody stated. So every level of a period must
// resolve to an EXACT length under the governing law, and a level whose length
// varies (a Gregorian month) fails that test and takes the boundary path
// instead.
//
// Four outcomes, and `unsupported` is one of them rather than a fallback: a
// fixed period resolved exactly; a month cycle resolved at its own two
// boundaries, which the schema fully describes, without pretending a month has a
// mean length; an event-defined cycle resolved against its authored, strictly
// ordered boundary series with no extrapolation past either end; or an explicit
// refusal carrying its own sentence.
//
// THE CHOICES COME FROM THE LAW. The web build shipped a hardcoded catalog of
// one, five and seven days. A cycle is the law's own -- one base unit, and one
// of each cycle the law declares -- so a world with a five-day week gets a
// five-day week and nobody had to type a 7.

import 'dart:math' as math;

import '../../core/coordinate_law.dart';
import '../../core/eras.dart';
import '../../core/event_cycle.dart';
import '../../core/exact.dart';
import '../../core/records.dart';
import '../tunables.dart';

/// One offered cycle. `days` is a period already known exactly; `period` is an
/// authored magnitude or an event-defined declaration that still has to resolve.
typedef CycleOption = ({String id, String title, Json? period, Rational? days});

/// What a resolution came to. `unsupported` carries [refusal] -- the sentence
/// shown to the author, in the law's own vocabulary.
typedef CycleResolution = ({
  String id,
  Rational? period,
  Rational? start,
  Rational? end,
  bool dynamic,
  bool unsupported,
  String? refusal,
});

/// The cycles this law itself offers: its base unit, and one turn of every cycle
/// it declares. Nothing is invented -- a law with no week offers no week.
List<CycleOption> lawCycles(CoordinateLaw law) => [
  (id: 'law:${law.baseLevel}', title: law.baseLevel, period: null, days: law.baseDays),
  for (final cycle in law.cycles())
    (id: 'law:${cycle.name}', title: cycle.name, period: null, days: cycle.radix * law.baseDays),
];

/// A period's exact length in days, or NULL when any of its levels has no exact
/// length under this law. `unitDays` is null for precisely the levels whose
/// length varies, which is what keeps a month unsupported here while staying a
/// legitimate duration everywhere else.
Rational? cyclePeriodHint(Json? magnitude, CoordinateLaw law) {
  final levels = asList(obj(magnitude?['value'])?['levels']);
  if (levels.isEmpty) return null;
  var total = Rational.zero;
  for (final row in levels) {
    final entry = asMap(row);
    final factor = law.unitDays(declaredText(entry?['level']));
    if (factor == null) return null;
    try {
      total += Rational.parse(declaredText(entry?['value'])) * factor;
    } catch (_) {
      return null;
    }
  }
  return total > Rational.zero ? total : null;
}

CycleResolution _refuse(String id, String message) => (
  id: id,
  period: null,
  start: null,
  end: null,
  dynamic: false,
  unsupported: true,
  refusal: message,
);

/// Resolves the interval a radial-family lens is allowed to draw.
CycleResolution resolveCycle(
  List<CycleOption> options,
  String? activeId, {
  required CoordinateLaw law,
  Rational? focus,
  Tunable? read,
}) {
  final choice =
      options.where((option) => option.id == activeId).firstOrNull ?? options.firstOrNull;
  if (choice == null) return _refuse(activeId ?? '', 'No cycle is offered for this frame.');
  final fixed = choice.days ?? cyclePeriodHint(choice.period, law);
  if (fixed != null && fixed > Rational.zero) {
    return (
      id: choice.id,
      period: fixed,
      start: null,
      end: null,
      dynamic: false,
      unsupported: false,
      refusal: null,
    );
  }
  if (declaredText(choice.period?['kind']) == 'event-defined') {
    if (focus == null) {
      return _refuse(choice.id, 'An event-defined cycle needs a focus to resolve against.');
    }
    final attempt = resolveEventCycle(choice.period, focus);
    final cycle = attempt.resolved;
    if (cycle == null) return _refuse(choice.id, attempt.refusal!);
    return (
      id: choice.id,
      period: cycle.period,
      start: cycle.start,
      end: cycle.end,
      dynamic: true,
      unsupported: false,
      refusal: null,
    );
  }
  return _monthCycle(choice, law, focus, read);
}

/// A month cycle, resolved at its OWN two boundaries. The schema describes them
/// fully, so this is exact -- and it is the one place a variable-length unit is
/// drawable, because nothing here averages it.
CycleResolution _monthCycle(CycleOption choice, CoordinateLaw law, Rational? focus, Tunable? read) {
  final levels = asList(obj(choice.period?['value'])?['levels']);
  final only = levels.length == 1 ? asMap(levels.first) : null;
  final months = only == null || declaredText(only['level']) != 'month'
      ? 0
      : int.tryParse(declaredText(only['value'])) ?? 0;
  final ceiling = count(read, 'radial.monthCycleMax');
  if (!law.hasMonths()) {
    return _refuse(choice.id, 'This law declares no month, so a month cycle cannot be placed.');
  }
  if (focus == null || months < 1 || months > ceiling) {
    return _refuse(choice.id, 'This cycle has no length that can be resolved exactly.');
  }
  final civil = civilFromDays(focus.floor());
  final start = Rational(daysFromCivil(civil.year, civil.month, 1));
  final after = _addMonths(civil.year, civil.month, months);
  final end = Rational(daysFromCivil(after.$1, after.$2, 1));
  return (
    id: choice.id,
    period: end - start,
    start: start,
    end: end,
    dynamic: true,
    unsupported: false,
    refusal: null,
  );
}

(BigInt, int) _addMonths(BigInt year, int month, int count) {
  final twelve = BigInt.from(12);
  final index = year * twelve + BigInt.from(month - 1 + count);
  return (floorDiv(index, twelve), floorMod(index, twelve).toInt() + 1);
}

/// The visible window of a multi-turn spiral: whole cycles before and after the
/// focus, refused outright where the authored series does not reach that far.
({Rational start, Rational end})? cycleWindow(
  CycleResolution resolution,
  CoordinateLaw law, {
  int past = 0,
  int future = 0,
  Json? period,
}) {
  if (resolution.unsupported) return null;
  final before = past < 0 ? 0 : past, after = future < 0 ? 0 : future;
  if (declaredText(period?['kind']) == 'event-defined') {
    final window = eventCycleWindow(period, resolution.start, past: before, future: after);
    final resolved = window.resolved;
    return resolved == null ? null : (start: resolved.start, end: resolved.end);
  }
  final start = resolution.start, end = resolution.end, span = resolution.period;
  if (span == null) return null;
  if (start == null || end == null) {
    return (start: -span * Rational.fromInt(before), end: span * Rational.fromInt(after + 1));
  }
  // A month window steps by whole months, never by the current month's length.
  final civil = civilFromDays(start.floor());
  final months = ((end - start) / law.meanMonthDays()).round().toInt();
  final from = _addMonths(civil.year, civil.month, -months * before);
  final to = _addMonths(civil.year, civil.month, months * (after + 1));
  return (
    start: Rational(daysFromCivil(from.$1, from.$2, 1)),
    end: Rational(daysFromCivil(to.$1, to.$2, 1)),
  );
}

/// The guide ring's own settings: how many divisions, how often a major mark,
/// and whether the day/night band applies.
typedef GuideSettings = ({Rational cycleDays, int divisions, int majorEvery, bool dayNight});

/// Divisions default to THIS LAW'S hours for a cycle about a day long -- a
/// 23-hour day gets 23 ticks around the ring, not 24 with one that marks
/// nothing. A longer cycle ticks by its own base unit instead.
GuideSettings guideSettings(
  CoordinateLaw law,
  Rational cycleDays, {
  int? divisions,
  int? majorEvery,
  String marks = 'auto',
  Tunable? read,
}) {
  final ceiling = count(read, 'radial.divisionsMax');
  final short = tunable(read, 'radial.hourCycleDays');
  final long = tunable(read, 'radial.weekCycleDays');
  final units = (cycleDays / law.baseDays);
  final resolved = divisions != null && divisions > 0
      ? math.min(divisions, ceiling)
      : units >= short
      ? math.max(1, math.min(units.round().toInt(), ceiling))
      : math.max(1, math.min(law.unitsPer('hour').round().toInt(), ceiling));
  final major = majorEvery != null && majorEvery > 0
      ? math.min(majorEvery, resolved)
      : units >= long
      ? math.min(count(read, 'radial.majorWeek'), resolved)
      : units >= short
      ? 1
      : math.max(1, (resolved / count(read, 'radial.majorQuarter')).round());
  return (
    cycleDays: cycleDays,
    divisions: resolved,
    majorEvery: major,
    dayNight:
        marks == 'day-night' ||
        (marks == 'auto' && (units <= Rational.fromInt(2) || units >= long)),
  );
}
