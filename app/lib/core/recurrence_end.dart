// Pure Dart. Nothing under lib/core/ may import Flutter or a third-party
// package.
//
// How an RRULE stops: never, after a number of occurrences (COUNT), or on a
// date (UNTIL). RFC 5545 forbids COUNT and UNTIL in the same rule, so
// [applyRecurrenceEnd] always leaves exactly one of them set -- an unreachable
// combination is worse than a rejected one.
//
// UNTIL values are compared against an occurrence's own ordinal, inclusively:
// `ruleOccurrenceDays` drops an occurrence when `day > until`. Everything below
// therefore puts UNTIL *at or after* the last instant meant to survive, never
// before it.

import 'rrule.dart' show RRule;

/// The three ways a rule can stop. A name that is not one of these is not an
/// error the author has to answer for: it degrades to [never] rather than
/// inventing an end.
enum RecurrenceEnd { never, count, until }

RecurrenceEnd recurrenceEndNamed(String? name) =>
    RecurrenceEnd.values.firstWhere((mode) => mode.name == name, orElse: () => RecurrenceEnd.never);

const int countMinimum = 1;
const int countMaximum = 10000;

RecurrenceEnd recurrenceEndMode(RRule? rrule) {
  // A blank COUNT is not an end condition.
  if ((rrule?['COUNT'] ?? '').trim().isNotEmpty) return RecurrenceEnd.count;
  if ((rrule?['UNTIL'] ?? '').isNotEmpty) return RecurrenceEnd.until;
  return RecurrenceEnd.never;
}

String _padYear(String text) =>
    (text.startsWith('-') ? '-' : '') + text.replaceFirst(RegExp(r'^[+-]'), '').padLeft(4, '0');

String _pad(String value) => value.padLeft(2, '0');

final RegExp _compactDate = RegExp(r'^([+-]?\d{4,})(\d{2})(\d{2})');
final RegExp _writtenDate = RegExp(r'^([+-]?\d+)-(\d{1,2})-(\d{1,2})$');

/// The calendar date an UNTIL falls on, for putting back into a date input.
String recurrenceUntilDate(String? until) {
  final m = _compactDate.firstMatch((until ?? '').trim());
  return m == null ? '' : '${m[1]}-${m[2]}-${m[3]}';
}

/// "Ends on this date" means through the whole of that day, whatever time of day
/// the occurrences fall at -- so the value is the last second of the date, not
/// its midnight. A midnight UNTIL would silently drop a 09:00 series' final
/// occurrence, which is the kind of off-by-one a user reads as a bug.
String recurrenceUntilForDate(String? dateText) {
  final m = _writtenDate.firstMatch((dateText ?? '').trim());
  if (m == null) return '';
  return '${_padYear(m[1]!)}${_pad(m[2]!)}${_pad(m[3]!)}T235959';
}

/// "Stop repeating here" caps the series at one specific occurrence,
/// inclusively, so the value has to be that occurrence's own instant. A
/// date-only series has no time of day and gets the plain date form, which keeps
/// the value type matching the series the way RFC 5545 expects.
///
/// [levels] is a coordinate's levels by name -- the only thing this needs from a
/// coordinate, so the seam stays open until the coordinate-law port lands.
String recurrenceUntilForCoordinate(Map<String, String> levels) {
  String at(String name, [String fallback = '0']) => levels[name] ?? fallback;
  final date =
      '${_padYear(at('year', '1970'))}'
      '${_pad(at('month', '1'))}${_pad(at('day', '1'))}';
  const parts = ['hour', 'minute', 'second'];
  final time = parts.map((n) => _pad('${int.tryParse(at(n)) ?? 0}')).join();
  return time == '000000' ? date : '${date}T$time';
}

int normalizeRecurrenceCount(Object? value) {
  final written = double.tryParse(value?.toString().trim() ?? '');
  if (written == null || !written.isFinite) return countMinimum;
  return written.floorToDouble().clamp(countMinimum, countMaximum).toInt();
}

/// Returns a new rule rather than mutating, and always leaves exactly one of
/// COUNT/UNTIL set.
RRule applyRecurrenceEnd(
  RRule rrule, {
  RecurrenceEnd mode = RecurrenceEnd.never,
  Object? count,
  String? until,
}) {
  final next = RRule.of(rrule)
    ..remove('COUNT')
    ..remove('UNTIL');
  if (mode == RecurrenceEnd.count) {
    next['COUNT'] = '${normalizeRecurrenceCount(count)}';
  } else if (mode == RecurrenceEnd.until) {
    final written = (until ?? '').trim();
    // A mode the author chose but left blank falls back to "never" rather than
    // inventing a date; an already-compact value passes through untouched
    // instead of being re-derived.
    final value = _compactDate.hasMatch(written) ? written : recurrenceUntilForDate(written);
    if (value.isNotEmpty) next['UNTIL'] = value;
  }
  return next;
}
