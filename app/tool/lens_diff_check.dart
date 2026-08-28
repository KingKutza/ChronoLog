// Differential harness for the lens substrate, Dart side. Replays the cases
// `app/tool/lens_diff_gen.mjs` generated against the shipped JavaScript and
// compares every answer as an exact string. Uncounted tooling: nothing under
// lib/ imports this.
//
// Run (from app/):
//
//   dart run tool/lens_diff_check.dart
//
// which shells out to `node tool/lens_diff_gen.mjs` itself, or, to keep the cases
// around for inspection (app/build/ is already ignored):
//
//   node tool/lens_diff_gen.mjs > build/lens-diff-cases.json
//   dart run tool/lens_diff_check.dart build/lens-diff-cases.json
//
// Exit code 0 means every comparable case agreed. The RULED DIVERGENCE classes
// are reported separately and never compared:
//
//   L1  the cycle catalog is derived from the governing law rather than from a
//       hardcoded one/five/seven-day list, so a resolution of a MISSING id has no
//       counterpart. Counted, skipped.
//   L2  minimap magnitude multiplies by the composed display weight rather than a
//       three-value importance table. The arithmetic shape is compared with the
//       JavaScript's own multiplier supplied as the weight.
//   L3  the dot field is gone -- the minimap is a particle waveform -- so nothing
//       generates `minimapDotGrid` and its family. The scale they served rides.
//
// THE GEOMETRY HALF LIVES IN A TEST, not here: `polar`, `arcPath` and
// `spiralRibbon` are built on `dart:ui`, which the standalone Dart VM has no
// engine for. `test/lens/geometry_diff_test.dart` replays the SAME generated
// cases -- this file's oracle, run once more -- under `flutter test`, where an
// engine exists. Both halves read one generator, so the seed and the case set
// cannot drift apart.

import 'dart:convert';
import 'dart:io';

import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/lens/law_context.dart';
import 'package:chronolog/lens/lines/plan.dart';
import 'package:chronolog/lens/minimap/field.dart';
import 'package:chronolog/lens/minimap/labels.dart';
import 'package:chronolog/lens/radial/cycles.dart';

int checked = 0;
int cases = 0;
int skippedDivergent = 0;
final List<String> failures = [];

final LawContext law = LawContext(gregorianLaw);

void compare(String where, Object? expected, Object? actual) {
  checked += 1;
  final left = jsonEncode(expected), right = jsonEncode(actual);
  if (left != right) failures.add('$where\n    js   $left\n    dart $right');
}

String fixed(double value) => value.isFinite ? value.toStringAsFixed(6) : '$value';

double number(Object? value) => double.parse('$value');

List<Object?> list(Object? value) => value as List<Object?>;

Map<String, Object?> map(Object? value) => (value as Map).cast<String, Object?>();

void main(List<String> arguments) {
  final source = arguments.isEmpty ? _runOracle() : File(arguments.first).readAsStringSync();
  final oracle = map(jsonDecode(source));

  // The generated ladder must BE the shipped one, rung for rung: it is the scale
  // the whole field is read against.
  cases += 1;
  compare('ladder', oracle['ladder'], [for (final rung in magnitudeLadder(null)) fixed(rung)]);

  for (final row in list(oracle['granularity'])) {
    final entry = list(row);
    cases += 1;
    compare('granularity ${entry.first}', entry[1], granularityFor('${entry.first}'));
  }

  for (final row in list(oracle['labels'])) {
    final entry = map(row);
    cases += 1;
    final ticks = labelTicks(
      Rational.parse('${entry['start']}'),
      Rational.parse('${entry['end']}'),
      '${entry['level']}',
      law,
    );
    compare('labels ${entry['level']} ${entry['start']}..${entry['end']}', entry['ticks'], [
      for (final tick in ticks) [tick.days.toJson(), tick.format, tick.text],
    ]);
  }

  for (final row in list(oracle['text'])) {
    final entry = map(row);
    cases += 1;
    compare(
      'text ${entry['format']} ${entry['days']}',
      entry['text'],
      labelText(Rational.parse('${entry['days']}'), '${entry['format']}', law),
    );
  }

  // L2: the shape, with the JavaScript's own multiplier standing in for the
  // composed weight.
  for (final row in list(oracle['magnitude'])) {
    final entry = map(row);
    cases += 1;
    final magnitude =
        (1 + int.parse('${entry['stapleCount']}') + number(entry['durationDays'])) *
        number(entry['weight']);
    compare('magnitude ${entry['stapleCount']}', entry['magnitude'], fixed(magnitude));
  }

  for (final row in list(oracle['ceiling'])) {
    final entry = map(row);
    cases += 1;
    final magnitudes = [for (final value in list(entry['magnitudes'])) number(value)];
    compare('ceiling ${magnitudes.length}', entry['ceiling'], fixed(ceilingFor(magnitudes, null)));
  }

  for (final row in list(oracle['hints'])) {
    final entry = map(row);
    cases += 1;
    final hint = cyclePeriodHint(Json.from(map(entry['magnitude'])), gregorianLaw);
    compare('hint', entry['hint'], hint?.toJson());
  }

  for (final row in list(oracle['months'])) {
    final entry = map(row);
    cases += 1;
    final months = '${entry['months']}';
    final option = (
      id: 'cycle:month',
      title: 'Month',
      period: Json.from({
        'value': {
          'levels': [
            {'level': 'month', 'value': months},
          ],
        },
      }),
      days: null,
    );
    final focus = Rational.parse('${entry['focus']}');
    final resolved = resolveCycle([option], 'cycle:month', law: gregorianLaw, focus: focus);
    compare('month $months unsupported', entry['unsupported'], resolved.unsupported);
    compare('month $months period', entry['period'], resolved.period?.toJson());
    compare('month $months start', entry['start'], resolved.start?.toJson());
    compare('month $months end', entry['end'], resolved.end?.toJson());
    final window = cycleWindow(
      resolved,
      gregorianLaw,
      past: int.parse('${entry['past']}'),
      future: int.parse('${entry['future']}'),
    );
    compare(
      'month $months window',
      entry['window'],
      [?window?.start.toJson(), ?window?.end.toJson()].isEmpty
          ? null
          : [window!.start.toJson(), window.end.toJson()],
    );
  }

  skippedDivergent += list(oracle['missingId']).length;

  for (final row in list(oracle['progress'])) {
    final entry = map(row);
    cases += 1;
    final progress = lineProgress(
      Rational.parse('${entry['day']}'),
      Rational.parse('${entry['start']}'),
      Rational.parse('${entry['end']}'),
    );
    compare('progress', entry['progress'], progress == null ? null : fixed(progress));
  }

  for (final row in list(oracle['fans'])) {
    final entry = map(row);
    cases += 1;
    final points = [
      for (final point in list(entry['points']))
        (id: '${list(point)[0]}', eventId: '${list(point)[1]}', x: number(list(point)[2]), line: 0),
    ];
    final fanned = fanPoints(points, pixelSpan: 995);
    compare('fan ${points.length}', entry['fanned'], [
      for (final point in fanned) [point.id, fixed(point.offset), point.cluster],
    ]);
  }

  stdout.writeln('lens differential: $cases cases · $checked checks');
  stdout.writeln('  ruled divergences skipped: $skippedDivergent (L1 cycle catalog)');
  if (failures.isEmpty) {
    stdout.writeln('PASSED');
    return;
  }
  stdout.writeln('FAILED — ${failures.length} disagreements');
  for (final failure in failures.take(20)) {
    stdout.writeln('  $failure');
  }
  exitCode = 1;
}

String _runOracle() {
  final result = Process.runSync('node', ['tool/lens_diff_gen.mjs'], stdoutEncoding: utf8);
  if (result.exitCode != 0) {
    stderr.writeln(result.stderr);
    throw StateError('the oracle failed to run');
  }
  return result.stdout as String;
}
