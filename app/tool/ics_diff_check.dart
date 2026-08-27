// Differential harness for the ICS boundary, Dart side. Replays the ICS files
// `app/tool/ics_diff_gen.mjs` generated against the shipped JavaScript and
// compares every answer as an exact string. Uncounted tooling: nothing under
// lib/ imports this.
//
// Run (from app/):
//
//   dart run tool/ics_diff_check.dart
//
// which shells out to `node tool/ics_diff_gen.mjs` itself, or, to keep the cases
// around for inspection (app/build/ is already ignored):
//
//   node tool/ics_diff_gen.mjs > build/ics-diff-cases.json
//   dart run tool/ics_diff_check.dart build/ics-diff-cases.json
//
// Exit code 0 means every comparable case agreed. The RULED DIVERGENCE CLASSES
// are reported separately and never compared -- see the generator's header for
// the full statement of each:
//
//   D1  a file carrying the X-CHRONOLOG dialect. The dialect is DEAD both
//       directions, so the JavaScript's reconstructed anchors and its sibling
//       segment VEVENTs have no counterpart here. Counted, skipped whole.
//   D2  a file carrying a VTODO. The mapping is ON HOLD, so the port retains the
//       component verbatim. VEVENT semantics are still compared; only the bytes
//       sit out, because the JavaScript moves the VTODO after every VEVENT.
//   D3  a malformed RRULE part with no `=`. The JavaScript's own slice arithmetic
//       ate its last character; the port keeps it. A fixed defect. Counted.

import 'dart:convert';
import 'dart:io';

import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/eras.dart' show asList, asMap;
import 'package:chronolog/core/ics.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';

int checked = 0;
int semanticCases = 0;
int exportCases = 0;
int dialectSkipped = 0;
int vtodoExportSkipped = 0;
int ruleParseSkipped = 0;
final List<String> failures = [];

void compare(String where, Object? expected, Object? actual) {
  checked += 1;
  final left = jsonEncode(expected);
  final right = jsonEncode(actual);
  if (left != right) {
    failures.add('$where\n    js   $left\n    dart $right');
  }
}

final CoordinateLaws laws = CoordinateLaws();

// --- The same answers, asked of the port -------------------------------------

Map<String, Object?>? placementAnswer(Document document, String eventId) {
  for (final relation in document.relations.values) {
    if (relation.type != 'attachment' || relation.event != eventId) continue;
    final parameters = asMap(relation.extra['parameters']) ?? const {};
    return {
      'role': relation.role,
      'levels': [
        for (final level in Coordinate.fromJson(relation.coordinate).levels)
          [level.level, level.value],
      ],
      'dateOnly': parameters['dateOnly'],
      'utc': parameters['utc'],
      'timeZone': parameters['timeZone'],
    };
  }
  return null;
}

Map<String, Object?> semantics(IcsImport result) {
  final document = result.document;
  final raw = document.toJson();
  final events = <String, Object?>{};
  for (final id in result.events) {
    final event = document.events[id]!;
    events['${event.payload?['uid']}'] = {
      'title': event.payload?['title'],
      'description': event.payload?['description'],
      'location': event.payload?['location'],
      'status': event.payload?['status'],
      'categories': event.payload?['categories'],
      'durationDays': laws.durationDays(event.duration, document: raw).toJson(),
      'traits': [...event.traits]..sort(),
      'placement': placementAnswer(document, id),
    };
  }
  final patterns = <String, Object?>{};
  for (final id in result.patterns) {
    final pattern = document.patterns[id]!;
    patterns['${asMap(pattern.extra['provenance'])?['uid']}'] = {
      'kind': pattern.kind,
      'rrule': pattern.extra['rrule'],
      'rawRule': pattern.extra['rawRule'],
      'exdates': [for (final day in asList(pattern.extra['exdates'])) '$day']..sort(),
      'exdateProperties': [
        for (final row in asList(pattern.extra['exdateProperties']))
          {
            'params': [
              for (final param in asList(asMap(row)?['params']))
                [asMap(param)?['name'], asMap(param)?['values']],
            ],
            'values': [
              for (final item in asList(asMap(row)?['values']))
                [asMap(item)?['value'], asMap(item)?['day']],
            ],
          },
      ],
      'templateEventUid': document.events[pattern.templateEvent]?.payload?['uid'],
      'hasTemplateRelation': pattern.templateRelation != null,
      'appliesTo': asList(pattern.extra['appliesTo']).length,
    };
  }
  final overrides = [
    for (final override in document.overrides.values)
      {
        'key': override.virtualId.substring(override.virtualId.lastIndexOf('/') + 1),
        'suppress': override.suppress,
        'replacements': [
          for (final id in override.replacements) '${document.events[id]?.payload?['uid'] ?? id}',
        ]..sort(),
      },
  ]..sort(_byRow);
  final suggestions = [
    for (final item in result.suggestions)
      {'kind': item.kind, 'uid': item.uid, 'count': item.events.length},
  ]..sort(_byRow);
  return {
    'frames': [
      for (final id in result.frames)
        {
          'title': document.frames[id]?.title,
          'traits': [...?document.frames[id]?.traits]..sort(),
        },
    ],
    'events': events,
    'patterns': patterns,
    'overrides': overrides,
    'suggestions': suggestions,
    'warnings': [...result.warnings]..sort(),
  };
}

/// The same total order the oracle sorts by: the row's own values, joined. A
/// deterministic key rather than a re-encoded document, so the two sides cannot
/// disagree about how a map serializes.
int _byRow(Map<String, Object?> left, Map<String, Object?> right) =>
    _rowKey(left).compareTo(_rowKey(right));

String _rowKey(Map<String, Object?> row) =>
    [for (final value in row.values) value is List ? value.join(',') : '$value'].join('|');

Coordinate _coordinate(Object? levels) =>
    Coordinate.of([for (final row in asList(levels)) ('${asList(row).first}', asList(row).last)]);

Future<String> generate() async {
  final result = await Process.run(
    'node',
    ['tool/ics_diff_gen.mjs'],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    stderr.writeln('node tool/ics_diff_gen.mjs failed:\n${result.stderr}');
    exit(2);
  }
  return result.stdout as String;
}

Future<void> main(List<String> arguments) async {
  final source = arguments.isEmpty ? await generate() : File(arguments.first).readAsStringSync();
  final data = jsonDecode(source) as Map<String, Object?>;
  final cases = data['cases'] as List<Object?>;

  for (final (index, raw) in cases.indexed) {
    final item = raw as Map<String, Object?>;
    final where = 'ics case $index';
    if (item['dialect'] == true) {
      dialectSkipped += 1;
      continue;
    }
    if (item['malformedRule'] == true) {
      ruleParseSkipped += 1;
      continue;
    }
    final IcsImport result;
    try {
      result = importIcs(
        '${item['source']}',
        createEmptyWorkspaceDocument(now: DateTime.utc(2026, 8, 7, 12)),
        label: 'Diff',
      );
    } on Object catch (error) {
      failures.add('$where import threw $error');
      continue;
    }
    final expected = asMap(item['expected']);
    if (expected != null) {
      semanticCases += 1;
      final answer = semantics(result);
      for (final field in expected.keys) {
        compare('$where $field', expected[field], answer[field]);
      }
    }
    if (item['vtodo'] == true) {
      vtodoExportSkipped += 1;
      continue;
    }
    final bytes = item['export'];
    if (bytes == null) continue;
    exportCases += 1;
    final window = asMap(item['window']);
    try {
      final actual = exportIcs(
        result.document,
        frame: result.frames.first,
        engine: ProjectionEngine(result.document),
        now: DateTime.utc(2026, 8, 7, 12),
        productId: '-//Chronolog//Diff//EN',
        start: window == null ? null : _coordinate(window['start']),
        end: window == null ? null : _coordinate(window['end']),
      );
      compare('$where export', bytes, actual);
    } on Object catch (error) {
      failures.add('$where export threw $error');
    }
  }

  stdout.writeln('ICS boundary differential');
  stdout.writeln('  seed              ${data['seed']}');
  stdout.writeln('  files generated   ${data['generated']}');
  stdout.writeln('  semantics cases   $semanticCases');
  stdout.writeln('  export cases      $exportCases');
  stdout.writeln('  comparisons       $checked');
  stdout.writeln('  failures          ${failures.length}');
  stdout.writeln(
    '  D1 dialect        $dialectSkipped files skipped whole'
    ' (X-CHRONOLOG is dead both directions)',
  );
  stdout.writeln(
    '  D2 VTODO          $vtodoExportSkipped files compared as semantics only'
    ' (mapping on hold; the component is retained verbatim)',
  );
  stdout.writeln(
    '  D3 rule parse     $ruleParseSkipped files skipped whole'
    ' (a malformed RRULE part; the JavaScript ate its last character)',
  );
  for (final failure in failures.take(20)) {
    stdout.writeln('  FAIL $failure');
  }
  if (failures.length > 20) {
    stdout.writeln('  ... and ${failures.length - 20} more');
  }
  exit(failures.isEmpty ? 0 : 1);
}
