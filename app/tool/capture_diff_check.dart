// Differential harness for the quick-capture grammar, Dart side. Replays the
// cases `app/tool/capture_diff_gen.mjs` generated against the shipped
// `src/ui/todo-capture.js` and compares every answer as an exact string.
// Uncounted tooling: nothing under lib/ imports this.
//
// Run (from app/):
//
//   dart run tool/capture_diff_check.dart
//
// which shells out to `node tool/capture_diff_gen.mjs` itself, or, to keep the
// cases around for inspection (app/build/ is already ignored):
//
//   node tool/capture_diff_gen.mjs > build/capture-diff-cases.json
//   dart run tool/capture_diff_check.dart build/capture-diff-cases.json
//
// Exit code 0 means every comparable case agreed. Only the GRAMMAR is compared,
// because only the grammar survived: the JavaScript's group lookup was exact
// equality and its miss was reported AFTER the object had been committed, both
// of which the 8.26 ruling replaces outright.
//
// The date words are compared under the Gregorian law, which is what the
// JavaScript's own `daysFromCivil` reads them under. Under any other law the
// port answers in THAT law's own days and the JavaScript has no counterpart to
// disagree with, which is the point of the change rather than a divergence to
// count.

import 'dart:convert';
import 'dart:io';

import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/edit/capture_grammar.dart';

int checked = 0;
final List<String> failures = [];

void compare(String where, Object? expected, Object? actual) {
  checked += 1;
  final left = jsonEncode(expected);
  final right = jsonEncode(actual);
  if (left != right) failures.add('$where\n    js   $left\n    dart $right');
}

Future<String> generate() async {
  final result = await Process.run(
    'node',
    ['tool/capture_diff_gen.mjs'],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    stderr.writeln('node tool/capture_diff_gen.mjs failed:\n${result.stderr}');
    exit(2);
  }
  return result.stdout as String;
}

Future<void> main(List<String> arguments) async {
  final source = arguments.isEmpty ? await generate() : File(arguments.first).readAsStringSync();
  final data = jsonDecode(source) as Map<String, Object?>;
  final cases = data['cases'] as List<Object?>;
  var parses = 0, dates = 0;

  for (final (index, raw) in cases.indexed) {
    final item = raw as Map<String, Object?>;
    final where = '${item['kind']} case $index (${jsonEncode(item['text'])})';
    switch (item['kind']) {
      case 'parse':
        parses += 1;
        final line = parseQuickTodo('${item['text']}');
        compare(
          where,
          item['parsed'],
          line == null
              ? null
              : {'title': line.title, 'group': line.group, 'date': line.date, 'note': line.note},
        );
      case 'date':
        dates += 1;
        final days = quickDateDays(
          '${item['text']}',
          gregorianLaw,
          Rational.parse('${item['today']}'),
        );
        compare(where, item['days'], days?.toJson());
      default:
        failures.add('$where has no probe');
    }
  }

  stdout.writeln('quick-capture differential');
  stdout.writeln('  seed              ${data['seed']}');
  stdout.writeln('  grammar cases     $parses');
  stdout.writeln('  date cases        $dates');
  stdout.writeln('  comparisons       $checked');
  stdout.writeln('  failures          ${failures.length}');
  for (final failure in failures.take(20)) {
    stdout.writeln('  FAIL $failure');
  }
  if (failures.length > 20) stdout.writeln('  ... and ${failures.length - 20} more');
  exit(failures.isEmpty ? 0 : 1);
}
