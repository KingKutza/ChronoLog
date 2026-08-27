// Pure Dart. Nothing under lib/core/ may import Flutter or a third-party
// package.
//
// This whole file is RFC 5545 recurrence evaluation over the PROLEPTIC
// GREGORIAN calendar specifically -- the WIRE FORMAT's own calendar, not the
// document's coordinate law. `_weekday`, `_weekdayCodes`, `daysInMonth`, and
// the month/day candidate machinery all assume a standard civil year, exactly
// as RFC 5545 defines FREQ/BYDAY/BYMONTHDAY. Melting this onto an arbitrary law
// is a separate roadmap item (pattern authoring beyond RRULE); an RSCALE naming
// a calendar this build has not registered is refused rather than silently
// evaluated as Gregorian -- see [unsupportedCalendarScale], which is the actual
// guard, and which every expansion passes through.

import 'exact.dart';

/// One RRULE as its parts by name, exactly as the wire text spells them.
typedef RRule = Map<String, String>;

/// Answers whether this build has registered the calendar RSCALE names.
typedef ScaleRegistry = bool Function(String scale);

/// A rule this build will not project, in words an author can read. The engine
/// catches this per pattern and reports it, which is why refusing is always
/// preferred to guessing.
class RecurrenceRefusal implements Exception {
  final String message;
  const RecurrenceRefusal(this.message);
  @override
  String toString() => message;
}

Never _refuse(String message) => throw RecurrenceRefusal(message);

// Weekday zero is Sunday, as RFC 5545 numbers BYDAY and as `_weekday` counts.
const List<String> _weekdayCodes = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];
const int _monday = 1;

final BigInt _b4 = BigInt.from(4),
    _b7 = BigInt.from(7),
    _b12 = BigInt.from(12),
    _maxRRuleCount = BigInt.from(10000);

/// No cap at all, spelled as a bound the occurrence list can be compared to.
const int noOccurrenceLimit = 0x7FFFFFFFFFFFFFFF;

// An absent rule part and a blank one are the same thing, which is what the
// JavaScript's truthiness tests said and what ICS text produces.
String? _part(RRule rule, String key) {
  final value = rule[key];
  return (value == null || value.isEmpty) ? null : value;
}

// A comma-separated integer list, which is how every BY* part is written.
List<int> _integers(String text) => [for (final part in text.split(',')) int.parse(part.trim())];

int _weekday(BigInt day) => floorMod(day + _b4, _b7).toInt();

// The Monday that opens a day's week: the WKST this build counts weeks from.
BigInt _weekOf(BigInt day) => day - BigInt.from((_weekday(day) - _monday) % 7);

BigInt _monthIndex(CivilDay civil) => civil.year * _b12 + BigInt.from(civil.month - 1);

// Where a generator starts: cycle zero whenever COUNT is written, because every
// earlier occurrence still has to be counted, and otherwise [ahead] cycles
// straight to the window -- never backwards past the base.
BigInt _skip(BigInt? count, BigInt ahead) =>
    count != null || ahead < BigInt.zero ? BigInt.zero : ahead;

final RegExp _compactStamp = RegExp(r'^([+-]?\d{4,})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})Z?)?$');

/// RFC 5545's own compact timestamp format (`YYYYMMDDTHHMMSSZ`): 24, 1440,
/// 86400 are the WIRE FORMAT's units (a compact ICS timestamp's hour is always
/// a standard hour), not this document's coordinate law -- melting them onto a
/// document law would misread every UNTIL/RECURRENCE-ID this parses.
Rational? compactIcsDay(String? value) {
  final m = _compactStamp.firstMatch(value ?? '');
  if (m == null) return null;
  int part(int index) => int.parse(m[index]!);
  final date = Rational(daysFromCivil(BigInt.parse(m[1]!), part(2), part(3)));
  if (m[4] == null) return date;
  return date +
      Rational.fromInt(part(4), 24) +
      Rational.fromInt(part(5), 1440) +
      Rational.fromInt(part(6), 86400);
}

typedef _ByDay = ({int? ordinal, int weekday});

final RegExp _byDayToken = RegExp(r'^([+-]?\d+)?(SU|MO|TU|WE|TH|FR|SA)$');

// An unreadable token is dropped, not refused: `BYDAY=MO,rubbish` still means
// Mondays.
List<_ByDay> _parseByDay(String? value) => [
  for (final token in (value ?? '').split(','))
    if (_byDayToken.firstMatch(token.trim().toUpperCase()) case final m?)
      (ordinal: m[1] == null ? null : int.parse(m[1]!), weekday: _weekdayCodes.indexOf(m[2]!)),
];

// Which days of one month a rule names: BYMONTHDAY (negatives counted back from
// the month's own end), narrowed by BYDAY when both are written; BYDAY alone,
// where a +/- ordinal picks the nth such weekday of the month; and failing both,
// the base's own day of the month, which simply does not occur in a month too
// short to hold it.
List<int> _candidates(RRule rule, BigInt year, int month, int baseDay) {
  final length = daysInMonth(year, month);
  int weekdayOf(int day) => _weekday(daysFromCivil(year, month, day));
  final byDay = _parseByDay(_part(rule, 'BYDAY'));
  final byMonthDay = _part(rule, 'BYMONTHDAY');
  final candidates = <int>[];
  if (byMonthDay != null) {
    for (final written in _integers(byMonthDay)) {
      final day = written < 0 ? length + written + 1 : written;
      if (day >= 1 && day <= length) candidates.add(day);
    }
    if (byDay.isNotEmpty) {
      final weekdays = byDay.map((item) => item.weekday).toSet();
      candidates.retainWhere((day) => weekdays.contains(weekdayOf(day)));
    }
  } else if (byDay.isNotEmpty) {
    for (final item in byDay) {
      final matching = [
        for (var day = 1; day <= length; day++)
          if (weekdayOf(day) == item.weekday) day,
      ];
      final ordinal = item.ordinal;
      if (ordinal == null) {
        candidates.addAll(matching);
        continue;
      }
      final index = ordinal > 0 ? ordinal - 1 : matching.length + ordinal;
      if (index >= 0 && index < matching.length) {
        candidates.add(matching[index]);
      }
    }
  } else if (baseDay >= 1 && baseDay <= length) {
    candidates.add(baseDay);
  }
  return candidates.toSet().toList()..sort();
}

// One voice for everything the wire format may name and this build cannot
// project. Never silence: a rule that cannot be honoured is refused with the
// part that defeated it named, and kept exactly as written.
String _unimplemented(String kind, String part, String value) =>
    'RRULE names a $kind this build does not implement '
    '($part=$value); the rule is kept but cannot be projected.';

/// RFC 7529: RSCALE names the calendar a rule counts in. A rule naming a
/// calendar this build has not registered ([isRegisteredScale] answers false)
/// must never be projected as though it counted in Gregorian -- refused
/// honestly instead, with the calendar named in the message. The predicate is
/// injected rather than imported so this module never depends on the law
/// registry; only `gregory` and its aliases answer true today.
String? unsupportedCalendarScale(RRule rrule, ScaleRegistry isRegisteredScale) {
  final requested = _part(rrule, 'RSCALE');
  if (requested == null || isRegisteredScale(requested)) return null;
  return _unimplemented('calendar', 'RSCALE', requested);
}

// RFC 5545 defines fourteen rule parts and RFC 7529 adds two. This build
// implements FREQ, INTERVAL, COUNT, UNTIL (through `ruleOccurrenceDays`'s own
// `until`), BYDAY, BYMONTHDAY, BYMONTH and RSCALE. Every part below is one the
// standards define as deciding WHICH occurrences a rule names, so writing one
// is refused with the part named rather than left silently inert.
final Set<String> _unimplementedParts =
    'BYSECOND BYMINUTE BYHOUR BYYEARDAY BYWEEKNO BYSETPOS WKST SKIP'.split(' ').toSet();

// RFC 5545 section 3.3.10's filter/expand model, stated once as the parts each
// frequency EXPANDS: a BY* part finer than the frequency multiplies occurrences
// inside every cycle, and a part at or coarser than a position the frequency
// already fixes LIMITS instead, dropping occurrences that do not match. Every
// written part therefore holds of every occurrence, whichever frequency wrote
// it. The generators below expand; `_limits` is the other half.
const Map<String, Set<String>> _expands = {
  'DAILY': {},
  'WEEKLY': {'BYDAY'},
  'MONTHLY': {'BYDAY', 'BYMONTHDAY'},
  'YEARLY': {'BYDAY', 'BYMONTHDAY', 'BYMONTH'},
};

// The day-level parts the running frequency does not expand, as a rule of their
// own: asking `_candidates` about that reduced rule is what makes BYMONTHDAY's
// negatives and BYDAY's ordinals mean one thing in both halves of the model.
RRule _limits(RRule rule, Set<String> expands) => {
  for (final part in const ['BYMONTHDAY', 'BYDAY'])
    if (!expands.contains(part) && _part(rule, part) != null) part: rule[part]!,
};

/// One rule segment's own occurrence days within `[lower, upper]`.
///
/// COUNT is counted from [base] and is therefore scoped to THIS segment alone
/// -- a segment is that rule's whole life, so counting emitted occurrences
/// across a rule change (into a segment whose rule may have a different FREQ
/// entirely) would count against a rule that no longer applies. [until] is this
/// segment's own effective stop -- the earlier of the rule's own written UNTIL
/// and the staple that closes it -- and it is compared inclusively.
///
/// [excluded] holds EXDATE days as [Rational.toJson] keys, and an excluded day
/// still counts against COUNT: it occurred, it was merely not delivered.
///
/// BYDAY, BYMONTHDAY and BYMONTH are honoured under every frequency, expanding
/// or limiting as [_expands] rules. A part the standards define as
/// occurrence-affecting and this build does not implement ([_unimplementedParts])
/// is refused with the part named. A key no standard defines as
/// occurrence-affecting -- an `X-` vendor extension, or anything a later profile
/// adds that cannot move an occurrence -- stays inert, because refusing what
/// cannot change the answer would refuse every file with an extension in it.
List<Rational> ruleOccurrenceDays(
  RRule rule,
  Rational base,
  Rational lower,
  Rational upper, {
  required ScaleRegistry isRegisteredScale,
  Rational? until,
  Set<String> excluded = const {},
  int limit = noOccurrenceLimit,
}) {
  final refusal = unsupportedCalendarScale(rule, isRegisteredScale);
  if (refusal != null) _refuse(refusal);
  // In the rule's own written order, so the author is told about the first part
  // that defeated the projection rather than the first this build thought of.
  for (final part in rule.keys) {
    if (_unimplementedParts.contains(part) && _part(rule, part) != null) {
      _refuse(_unimplemented('part', part, rule[part]!));
    }
  }
  final written = _part(rule, 'FREQ');
  final frequency = (written ?? '').toUpperCase();
  final interval = BigInt.parse(_part(rule, 'INTERVAL') ?? '1');
  if (interval <= BigInt.zero) {
    _refuse('RRULE INTERVAL must be positive, got ${rule['INTERVAL']}');
  }
  final countText = _part(rule, 'COUNT');
  final count = countText == null ? null : BigInt.parse(countText);
  if (count != null && count > _maxRRuleCount) {
    _refuse('RRULE COUNT exceeds the safe limit of $_maxRRuleCount');
  }
  final baseWhole = base.floor();
  final baseCivil = civilFromDays(baseWhole);
  final lowerWhole = lower.floor();
  final time = base - Rational(baseWhole);
  final days = <Rational>[];
  var counted = BigInt.zero;

  // The limiting half of the filter/expand model. Day-level limits are asked of
  // `_candidates` and memoized per month, because a DAILY rule asks the same
  // month up to thirty-one times running.
  final expands = _expands[frequency] ?? const {};
  final byMonth = expands.contains('BYMONTH') ? null : _part(rule, 'BYMONTH');
  final months = byMonth == null ? null : _integers(byMonth).toSet();
  final limits = _limits(rule, expands);
  final limited = months != null || limits.isNotEmpty;
  BigInt? memoMonth;
  var memoDays = const <int>[];
  bool allowed(CivilDay civil) {
    if (months != null && !months.contains(civil.month)) return false;
    if (limits.isEmpty) return true;
    final index = _monthIndex(civil);
    if (memoMonth != index) {
      memoMonth = index;
      memoDays = _candidates(limits, civil.year, civil.month, 0);
    }
    return memoDays.contains(civil.day);
  }

  // Candidates arrive in chronological order; emit counts every occurrence at
  // or after the base so COUNT reflects emitted occurrences, not generator
  // cycles. A day a limiting part drops is no occurrence at all, so it is never
  // counted -- and the window check comes first, because a rule whose limits
  // nothing satisfies must still terminate. False means "stop generating".
  bool emit(Rational day) {
    if (day < base) return true;
    if (until != null && day > until) return false;
    if (day > upper) return false;
    if (limited && !allowed(civilFromDays(day.floor()))) return true;
    if (count != null && counted >= count) return false;
    counted += BigInt.one;
    if (day >= lower && !excluded.contains(day.toJson())) {
      days.add(day);
      if (days.length >= limit) return false;
    }
    return true;
  }

  Rational at(BigInt year, int month, int day) => Rational(daysFromCivil(year, month, day)) + time;

  // Every day one month names, in order -- the whole of MONTHLY's and YEARLY's
  // shared inner cycle.
  bool sweep(BigInt year, int month) {
    for (final day in _candidates(rule, year, month, baseCivil.day)) {
      if (!emit(at(year, month, day))) return false;
    }
    return true;
  }

  if (frequency == 'DAILY') {
    var index = _skip(count, ((lower - base) / Rational(interval)).ceil());
    for (; ; index += BigInt.one) {
      if (!emit(base + Rational(index * interval))) break;
    }
  } else if (frequency == 'WEEKLY') {
    final baseWeek = _weekOf(baseWhole);
    final byDay = _parseByDay(_part(rule, 'BYDAY'));
    final selected = byDay.map((item) => item.weekday).toSet();
    if (selected.isEmpty) selected.add(_weekday(baseWhole));
    final lowerWeek = _weekOf(lowerWhole);
    var cycle = _skip(count, floorDiv(lowerWeek - baseWeek, _b7 * interval));
    weekly:
    for (; ; cycle += BigInt.one) {
      final weekStart = baseWeek + cycle * interval * _b7;
      for (var offset = 0; offset < 7; offset++) {
        final day = weekStart + BigInt.from(offset);
        if (!selected.contains(_weekday(day))) continue;
        if (!emit(Rational(day) + time)) break weekly;
      }
    }
  } else if (frequency == 'MONTHLY') {
    final baseMonth = _monthIndex(baseCivil);
    final lowerMonth = _monthIndex(civilFromDays(lowerWhole));
    var cycle = _skip(count, floorDiv(lowerMonth - baseMonth, interval));
    for (; ; cycle += BigInt.one) {
      final index = baseMonth + cycle * interval;
      final year = floorDiv(index, _b12);
      final month = floorMod(index, _b12).toInt() + 1;
      if (at(year, month, 1) > upper) break;
      if (!sweep(year, month)) break;
    }
  } else if (frequency == 'YEARLY') {
    final lowerYear = civilFromDays(lowerWhole).year;
    var cycle = _skip(count, floorDiv(lowerYear - baseCivil.year, interval));
    // No BYMONTH is the base's own month, which is already inside the range.
    final byMonth = _part(rule, 'BYMONTH') ?? '${baseCivil.month}';
    final months = _integers(byMonth).toSet().toList()
      ..removeWhere((month) => month < 1 || month > 12)
      ..sort();
    yearly:
    for (; ; cycle += BigInt.one) {
      final year = baseCivil.year + cycle * interval;
      if (at(year, 1, 1) > upper) break;
      for (final month in months) {
        if (!sweep(year, month)) break yearly;
      }
    }
  } else {
    _refuse('Unsupported FREQ in RRULE: ${written ?? '(missing)'}');
  }
  return days;
}
