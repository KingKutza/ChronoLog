// The quick-capture grammar: text in, a parsed line and an exact day out.
//
// PURE DART. Nothing here reaches a document, an editor or a host API, which is
// what lets the differential harness (`tool/capture_diff_check.dart`) replay it
// against the shipped `src/ui/todo-capture.js` on the Dart VM.
//
// The grammar is order-free and first-token-wins, and it is PROVISIONAL pending
// the owner's delimiter vocabulary. `#group` names a group frame, `@date` names
// a day, ` > ` opens a note; every other word is the title, in the order typed.
// No token is required -- a bare line is a title-only ToDo.

import '../core/coordinate_law.dart';
import '../core/exact.dart';

/// The parsed line. Every field but the title may be empty.
typedef QuickTodo = ({String title, String group, String date, String note});

const String _noteDelimiter = ' > ';

/// The line, parsed. Null when there is no title left to name an object with.
QuickTodo? parseQuickTodo(String text) {
  final raw = text.trim();
  if (raw.isEmpty) return null;
  final cut = raw.indexOf(_noteDelimiter);
  final head = cut < 0 ? raw : raw.substring(0, cut);
  final note = cut < 0 ? '' : raw.substring(cut + _noteDelimiter.length).trim();
  final words = <String>[];
  var group = '', date = '';
  for (final word in head.trim().split(RegExp(r'\s+'))) {
    if (word.length > 1 && word.startsWith('#') && group.isEmpty) {
      group = word.substring(1);
    } else if (word.length > 1 && word.startsWith('@') && date.isEmpty) {
      date = word.substring(1);
    } else {
      words.add(word);
    }
  }
  final title = words.join(' ').trim();
  return title.isEmpty ? null : (title: title, group: group, date: date, note: note);
}

final RegExp _ahead = RegExp(r'^\+(\d+)d?$');
final RegExp _iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$');
final RegExp _slash = RegExp(r'^(\d{1,2})/(\d{1,2})(?:/(\d{4}))?$');

/// A date word as a day on [law]'s own axis, or null for "not understood" --
/// never a guessed date. A law with no year/month/day ladder refuses the calendar
/// forms outright rather than reading them under a boundary it does not have; the
/// relative forms are counts of days and hold under any law.
Rational? quickDateDays(String text, CoordinateLaw law, Rational today) {
  final value = text.trim().toLowerCase();
  if (value.isEmpty) return null;
  final from = Rational(today.floor());
  if (value == 'today') return from;
  if (value == 'tomorrow') return from + Rational.one;
  final ahead = _ahead.firstMatch(value);
  if (ahead != null) return from + Rational.parse(ahead[1]!);
  if (!law.has('year') || !law.has('month') || !law.has('day')) return null;
  final iso = _iso.firstMatch(value), slash = _slash.firstMatch(value);
  final parts = switch ((iso, slash)) {
    (final RegExpMatch it, _) => (year: it[1]!, month: it[2]!, day: it[3]!),
    (_, final RegExpMatch it) => (
      year: it[3] ?? law.fromDays(from).value('year'),
      month: it[1]!,
      day: it[2]!,
    ),
    _ => null,
  };
  if (parts == null) return null;
  try {
    return law.toDays(
      Coordinate([
        (level: 'year', value: parts.year),
        (level: 'month', value: parts.month),
        (level: 'day', value: parts.day),
      ]),
    );
  } on Exception {
    return null;
  }
}

/// Damerau--Levenshtein, capped: how far past [limit] two strings are is not a
/// question a fuzzy match asks, so the walk stops caring.
int editDistance(String a, String b, int limit) {
  if ((a.length - b.length).abs() > limit) return limit + 1;
  var previous = List<int>.generate(b.length + 1, (index) => index);
  var older = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i += 1) {
    final row = List<int>.filled(b.length + 1, 0)..[0] = i;
    var best = i;
    for (var j = 1; j <= b.length; j += 1) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var step = [row[j - 1] + 1, previous[j] + 1, previous[j - 1] + cost].reduce(_smaller);
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        step = _smaller(step, older[j - 2] + 1);
      }
      row[j] = step;
      best = _smaller(best, step);
    }
    if (best > limit) return limit + 1;
    older = previous;
    previous = row;
  }
  return previous[b.length];
}

int _smaller(int a, int b) => a < b ? a : b;
