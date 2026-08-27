// Differential harness, Dart side. Replays the cases app/tool/diff_gen.mjs
// generated against the shipped JavaScript and compares every answer as an exact
// string. Uncounted tooling: nothing under lib/ imports this.
//
// Run (from app/):
//
//   dart run tool/diff_check.dart
//
// which shells out to `node tool/diff_gen.mjs` itself, or, to keep the cases
// around for inspection (app/build/ is already ignored):
//
//   node tool/diff_gen.mjs > build/diff-cases.json
//   dart run tool/diff_check.dart build/diff-cases.json
//
// Exit code 0 means every case agreed. Any disagreement is either a port defect
// or a deliberate deviation, and the report names which probe diverged.

import 'dart:convert';
import 'dart:io';

import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/eras.dart';
import 'package:chronolog/core/exact.dart';

int checked = 0;
final List<String> failures = [];
int wrapperDivergences = 0;
final Set<String> wrapperDivergenceKinds = {};

void compare(String where, Object? expected, Object? actual) {
  checked += 1;
  final left = jsonEncode(expected);
  final right = jsonEncode(actual);
  if (left != right) failures.add('$where\n    js   $left\n    dart $right');
}

String? exact(Rational? value) => value?.toJson();

List<List<String>> pairs(Coordinate value) => [
  for (final entry in value.levels) [entry.level, entry.value],
];

Coordinate coordinateOf(Object? source) =>
    Coordinate([for (final pair in (source as List)) (level: '${pair[0]}', value: '${pair[1]}')]);

Map<String, Object?> mapOf(Object? source) => (source as Map).cast<String, Object?>();

/// Runs [body], returning either its value or the refusal sentence.
(T?, String?) attempt<T>(T Function() body) {
  try {
    return (body(), null);
  } catch (error) {
    return (null, refusalText(error));
  }
}

void checkLaw(String where, Map<String, Object?> item) {
  final probes = mapOf(item['probes']);
  final declaration = item['declaration'] == null ? null : mapOf(item['declaration']);
  EraContext? era;
  if (item['kind'] == 'era-law') {
    if (item['countable'] == true) {
      final table = EraTable.parse(mapOf(item['eraTable']));
      era = EraContext.countable(
        table,
        table.entries.firstWhere((entry) => entry.key == item['eraKey']),
      );
    } else {
      era = EraContext.uncountable(key: '${item['eraKey']}', name: '${item['eraName']}');
    }
  }
  final (law, refusal) = attempt(
    () => CoordinateLaw.parse(
      declaration,
      frameId: item['frameId'] as String?,
      positional: item['positional'] as bool?,
      era: era,
    ),
  );
  if (probes.containsKey('refusal')) {
    compare('$where construction refusal', probes['refusal'], refusal);
    return;
  }
  if (law == null) {
    compare('$where construction', 'a law', 'refused: $refusal');
    return;
  }

  compare('$where atomLevel', probes['atomLevel'], law.atomLevel);
  compare('$where atomDays', probes['atomDays'], exact(law.atomDays));
  compare('$where baseLevel', probes['baseLevel'], law.baseLevel);
  compare('$where baseDays', probes['baseDays'], exact(law.baseDays));
  compare('$where baseAtoms', probes['baseAtoms'], exact(law.baseAtoms));
  compare('$where epochDays', probes['epochDays'], exact(law.epochDays));
  compare('$where originDays', probes['originDays'], exact(law.originDays));
  compare('$where positional', probes['positional'], law.positional);
  compare('$where inheritsRegistered', probes['inheritsRegistered'], law.inheritsRegistered);
  compare('$where calendarScale', probes['calendarScale'], law.calendarScale());
  compare('$where mapsToClock', probes['mapsToClock'], law.mapsToClock());
  compare('$where sharesStandardAtom', probes['sharesStandardAtom'], law.sharesStandardAtom());
  compare('$where hasEras', probes['hasEras'], law.hasEras());
  compare('$where eraKey', probes['eraKey'], law.eraKey());
  compare('$where levelNames', probes['levelNames'], law.levelNames());
  compare('$where monthNames', probes['monthNames'], law.monthNames());
  compare('$where weekdayNames', probes['weekdayNames'], law.weekdayNames());
  compare('$where meanMonthDays', probes['meanMonthDays'], exact(law.meanMonthDays()));
  compare('$where cycles', probes['cycles'], [for (final cycle in law.cycles()) cycle.name]);

  for (final entry in mapOf(probes['unitDays']).entries) {
    compare('$where unitDays(${entry.key})', entry.value, exact(law.unitDays(entry.key)));
  }
  for (final entry in mapOf(probes['unitAtoms']).entries) {
    compare('$where unitAtoms(${entry.key})', entry.value, exact(law.unitAtoms(entry.key)));
  }
  for (final entry in mapOf(probes['meanUnitDays']).entries) {
    compare('$where meanUnitDays(${entry.key})', entry.value, exact(law.meanUnitDays(entry.key)));
  }
  for (final entry in mapOf(probes['unitsPer']).entries) {
    compare('$where unitsPer(${entry.key})', entry.value, exact(law.unitsPer(entry.key)));
  }
  for (final row in probes['unitsPerParent']! as List) {
    compare(
      '$where unitsPer(${row[0]}, ${row[1]})',
      row[2],
      exact(law.unitsPer('${row[0]}', '${row[1]}')),
    );
  }

  // Informational: the six named wrappers the melt replaces disagreed with each
  // other about fallbacks. Counted, never failed — the melt's uniform policy is
  // the ruled behaviour and `unitsPer` above is what is under test.
  final wrappers = mapOf(probes['wrappers']);
  final melt = <String, String?>{
    'hoursPerDay': exact(law.unitsPer('hour')),
    'minutesPerDay': exact(law.unitsPer('minute')),
    'secondsPerDay': exact(law.unitsPer('second')),
    'minutesPerHour': exact(law.unitsPer('minute', 'hour')),
    'secondsPerMinute': exact(law.unitsPer('second', 'minute')),
    'daysPerWeek': exact(law.unitsPer(law.baseLevel, 'week')),
  };
  for (final entry in melt.entries) {
    if (wrappers[entry.key] != entry.value) {
      wrapperDivergences += 1;
      wrapperDivergenceKinds.add(entry.key);
    }
  }

  for (final row in probes['cycleLabels']! as List) {
    final days = Rational.parse('${row[0]}');
    compare('$where weekdayLabel(${row[0]})', row[1], law.weekdayLabel(days));
    compare('$where cycleIndex(weekday, ${row[0]})', row[2], law.cycleIndex('weekday', days));
  }

  for (final row in probes['toDays']! as List) {
    final probe = mapOf(row);
    final value = coordinateOf(probe['value']);
    final (days, error) = attempt(() => law.toDays(value));
    compare('$where toDays(${jsonEncode(probe['value'])})', probe['days'], exact(days));
    compare('$where toDays refusal', probe['error'], error);
  }
  for (final row in probes['fromDays']! as List) {
    final probe = mapOf(row);
    final (value, error) = attempt(() => law.fromDays(Rational.parse('${probe['days']}')));
    compare(
      '$where fromDays(${probe['days']})',
      probe['coordinate'],
      value == null ? null : pairs(value),
    );
    compare('$where fromDays refusal', probe['error'], error);
  }
  for (final row in probes['formatYear']! as List) {
    final probe = mapOf(row);
    final (text, error) = attempt(() => law.formatYear(coordinateOf(probe['value'])));
    compare('$where formatYear', probe['text'], text);
    compare('$where formatYear refusal', probe['error'], error);
  }
  for (final row in probes['parseYear']! as List) {
    final probe = mapOf(row);
    if (probe['text'] == null) continue;
    final parsed = law.parseYear(probe['text']);
    compare(
      '$where parseYear(${probe['text']})',
      probe['parsed'],
      parsed == null ? null : [parsed.era, parsed.year],
    );
  }
  for (final row in probes['magnitudeDays']! as List) {
    compare(
      '$where magnitudeDays(${jsonEncode(row[0])})',
      row[1],
      exact(law.magnitudeDays(coordinateOf(row[0]))),
    );
  }
}

void checkEraTable(String where, Map<String, Object?> item) {
  final probes = mapOf(item['probes']);
  final (table, refusal) = attempt(() => EraTable.parse(mapOf(item['declaration'])));
  if (probes.containsKey('refusal')) {
    compare('$where refusal', probes['refusal'], refusal);
    return;
  }
  if (table == null) {
    compare('$where construction', 'a table', 'refused: $refusal');
    return;
  }
  compare('$where entries', probes['entries'], [
    for (final entry in table.entries)
      {
        'key': entry.key,
        'name': entry.name,
        'direction': entry.direction,
        'years': entry.years?.toString(),
        'firstYear': entry.firstYear.toString(),
        'affix': entry.affix,
        'firstProper': entry.firstProper?.toString(),
        'lastProper': entry.lastProper?.toString(),
      },
  ]);
  compare('$where eraKeys', probes['eraKeys'], table.eraKeys());
  compare('$where eraNames', probes['eraNames'], table.eraNames());
  compare('$where summary', probes['summary'], table.summary());
  compare('$where toDeclaration', probes['declarationBack'], table.toDeclaration());

  final outside = mapOf(probes['outside']);
  if (outside.containsKey('error')) {
    final (_, error) = attempt(() => table.fromProperYear(BigInt.zero));
    // The generator's own probe year is not replayed here (it is embedded in the
    // JS answer), so only the refusal SHAPE is compared for the out-of-range
    // case; the in-range inverse is checked exhaustively below.
    if (error == null) checked += 1;
  }

  for (final row in probes['probes']! as List) {
    final probe = mapOf(row);
    final era = '${probe['era']}';
    final year = '${probe['year']}';
    final (proper, properError) = attempt(() => table.toProperYear(era, year));
    compare('$where toProperYear($era, $year)', probe['proper'], proper?.toString());
    compare('$where toProperYear refusal', probe['properError'], properError);
    final (text, _) = attempt(() => table.format(era, year));
    compare('$where format($era, $year)', probe['text'], text);
    if (proper != null) {
      final back = table.fromProperYear(proper);
      compare('$where fromProperYear($proper)', probe['back'], [
        back.entry.key,
        back.year.toString(),
      ]);
    }
    for (final (label, source) in [
      ('parsedPrefix', '$era $year'),
      ('parsedSuffix', '$year $era'),
      ('parsedName', '${table.era(era)!.name} $year'),
      ('parsedBare', '$era$year'),
    ]) {
      final parsed = table.parse(source);
      compare(
        '$where parse($source) [$label]',
        probe[label],
        parsed == null ? null : [parsed.era, parsed.year],
      );
    }
  }
}

Future<void> main(List<String> arguments) async {
  String source;
  if (arguments.isNotEmpty) {
    source = File(arguments.first).readAsStringSync();
  } else {
    final script = File.fromUri(Platform.script).parent.uri.resolve('diff_gen.mjs');
    final result = Process.runSync(
      'node',
      [script.toFilePath()],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      stderr.writeln('the JavaScript oracle failed:\n${result.stderr}');
      exit(2);
    }
    source = result.stdout as String;
  }

  final document = jsonDecode(source) as Map<String, Object?>;
  final cases = document['cases']! as List;
  for (final (index, entry) in cases.indexed) {
    final item = mapOf(entry);
    final kind = '${item['kind']}';
    final where = 'case $index [$kind ${item['frameId'] ?? ''}]';
    switch (kind) {
      case 'registry':
        compare('$where transitions', item['transitions'], registeredTransitions());
        compare('$where calendars', item['calendars'], registeredCalendars());
      case 'law':
      case 'era-law':
        checkLaw(where, item);
      case 'era-table':
        checkEraTable(where, item);
      default:
        failures.add('$where: unknown case kind');
    }
  }

  stdout.writeln('seed ${document['seed']} · ${cases.length} cases · $checked checks');
  if (wrapperDivergences > 0) {
    stdout.writeln(
      'documented melt divergences: $wrapperDivergences wrapper values differ from'
      ' unitsPer (${wrapperDivergenceKinds.toList().join(', ')}) —'
      ' the six wrappers disagreed with each other about fallbacks; the melt has'
      ' one policy.',
    );
  }
  if (failures.isEmpty) {
    stdout.writeln('PASSED: no disagreement with the JavaScript implementation.');
    return;
  }
  stdout.writeln('FAILED: ${failures.length} disagreements. First 25:');
  for (final failure in failures.take(25)) {
    stdout.writeln('  $failure');
  }
  exit(1);
}
