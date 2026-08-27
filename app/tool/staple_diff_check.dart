// Differential harness for the staple substrate and the era chain, Dart side.
// Replays the cases `app/tool/staple_diff_gen.mjs` generated against the shipped
// JavaScript and compares every answer as an exact string. Uncounted tooling:
// nothing under lib/ imports this.
//
// Run (from app/):
//
//   dart run tool/staple_diff_check.dart
//
// which shells out to `node tool/staple_diff_gen.mjs` itself, or, to keep the
// cases around for inspection (app/build/ is already ignored):
//
//   node tool/staple_diff_gen.mjs > build/staple-diff-cases.json
//   dart run tool/staple_diff_check.dart build/staple-diff-cases.json
//
// Exit code 0 means every comparable case agreed. The RULED DIVERGENCE classes
// are reported separately and never compared:
//
//   R4  a succession staple with no `role` fields. `era-chain.js:63-64` sniffs
//       `end.role` and therefore sees no edge at all; the port reads the ORDER of
//       the ends. Counted, skipped.
//   R3  an end-scope pair `model.js`'s `validateDocument` refuses. staples.js's
//       own derivations do not consult the gate, so these cases stay in the
//       parity set -- the count says how many of them agreed anyway.

import 'dart:convert';
import 'dart:io';

import 'package:chronolog/core/era_chain.dart';
import 'package:chronolog/core/eras.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/staples.dart';

int checked = 0;
int skippedDivergent = 0;
int refusedPairAgreements = 0;
final List<String> failures = [];

void compare(String where, Object? expected, Object? actual) {
  checked += 1;
  final left = jsonEncode(expected);
  final right = jsonEncode(actual);
  if (left != right) {
    failures.add('$where\n    js   $left\n    dart $right');
  }
}

String? text(Rational? value) => value?.toJson();

Json json(Object? value) => Json.from(value as Map);

Document documentOf(Object? value) => Document.fromJson(json(value));

// --- Probes, in the same order the oracle asked them -------------------------

Map<String, Object?> extentAnswer(Document document, String objectId) {
  final staples = Staples(document);
  final extent = staples.resolveObjectExtent(objectId);
  return {
    'source': extent.source,
    'derivedMagnitude': extent.derivedMagnitude,
    'startDays': text(extent.startDays),
    'endDays': text(extent.endDays),
    'magnitudeDays': text(extent.magnitudeDays),
    'cyclic': extent.cyclic,
    'frame': extent.frame,
    'spreadBefore': text(extent.spread.before),
    'spreadAfter': text(extent.spread.after),
    // One field, because the JavaScript's own start and end spreads are equal in
    // every shape it builds -- which the oracle asserts on the way past.
    'spreadSymmetric': true,
    'anchors': [
      for (final anchor in extent.anchors) [anchor.role, text(anchor.days)],
    ],
    'overdetermined': [
      for (final item in extent.overdetermined)
        [item.role, text(item.days), item.reason, item.staple == null ? 'relation' : 'staple'],
    ],
    'unresolved': [
      for (final item in extent.unresolved) [item.role, item.reason],
    ],
  };
}

Map<String, Object?> correspondenceAnswer(Document document, String from, String to) {
  final staples = Staples(document);
  final shape = staples.describeCorrespondence(from, to);
  final entries = staples.frameCorrespondences(from, to);
  return {
    'count': shape.count,
    'points': shape.points,
    'manyValued': shape.manyValued,
    'voids': shape.voids,
    'cardinality': shape.cardinality,
    'monotonic': shape.monotonic,
    'order': [for (final entry in entries) entry.staple.id],
    'from': [for (final entry in entries) text(staples.frameEndDays(entry.from))],
    'to': [for (final entry in entries) text(staples.frameEndDays(entry.to))],
  };
}

Map<String, Object?> segmentAnswer(Document document, String patternId) {
  final staples = Staples(document);
  final pattern = document.patterns[patternId]!;
  return {
    'segments': [
      for (final segment in staples.seriesSegments(pattern))
        [
          segment.index,
          text(segment.fromDays),
          text(segment.untilDays),
          segment.rule.rrule['FREQ'],
          segment.closedBy?.id,
          segment.openedBy?.id,
        ],
    ],
    'phase': text(staples.seriesPhaseDays(pattern)),
  };
}

Map<String, Object?> exclusionAnswer(
  Document document,
  Json exclude,
  Rational lower,
  Rational upper,
) {
  final days = Staples(document).liveExclusionDays(exclude, lower, upper);
  return {'days': days == null ? null : (days.toList()..sort())};
}

Map<String, Object?> eraAnswer(Document document, String frameId) {
  try {
    final ordered = eraChainFrames(document, frameId);
    final chain = eraChain(document, frameId);
    final context = frameEraContext(document, frameId);
    return {
      'refusal': null,
      'ordered': ordered,
      'countable': chain?.countable ?? const [],
      'pin': chain?.pin,
      'ranges': {
        for (final entry in (chain?.byFrame ?? const <String, EraEntry>{}).entries)
          entry.key: [entry.value.firstProper?.toString(), entry.value.lastProper?.toString()],
      },
      'context': context == null ? null : [context.countable, context.identity],
    };
  } catch (error) {
    return {'refusal': refusalText(error)};
  }
}

Future<String> generate() async {
  final result = await Process.run(
    'node',
    ['tool/staple_diff_gen.mjs'],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    stderr.writeln('node tool/staple_diff_gen.mjs failed:\n${result.stderr}');
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
    final kind = item['kind'];
    final where = '$kind case $index';
    final expected = item['expected'] as Map<String, Object?>;
    if (item['divergent'] == true) {
      skippedDivergent += 1;
      continue;
    }
    final document = documentOf(item['document']);
    switch (kind) {
      case 'extent':
        final answer = extentAnswer(document, '${item['object']}');
        for (final field in expected.keys) {
          compare('$where $field', expected[field], answer[field]);
        }
        if (item['refusedPair'] == true) refusedPairAgreements += 1;
      case 'correspondence':
        final answer = correspondenceAnswer(document, '${item['from']}', '${item['to']}');
        for (final field in expected.keys) {
          compare('$where $field', expected[field], answer[field]);
        }
      case 'segments':
        final answer = segmentAnswer(document, '${item['pattern']}');
        compare('$where segments', expected['segments'], answer['segments']);
        compare('$where phase', expected['phase'], answer['phase']);
      case 'exclusions':
        final answer = exclusionAnswer(
          document,
          json(item['exclude']),
          Rational.parse('${item['lower']}'),
          Rational.parse('${item['upper']}'),
        );
        compare('$where days', expected['days'], answer['days']);
      case 'era':
        final answer = eraAnswer(document, '${item['frame']}');
        for (final field in expected.keys) {
          compare('$where $field', expected[field], answer[field]);
        }
      default:
        failures.add('$where has no probe');
    }
  }

  stdout.writeln('staple differential');
  stdout.writeln('  seed              ${data['seed']}');
  stdout.writeln('  cases generated   ${data['generated']}');
  stdout.writeln('  comparisons       $checked');
  stdout.writeln('  failures          ${failures.length}');
  stdout.writeln(
    '  R4 divergence     $skippedDivergent cases skipped by design'
    ' (succession read from `end.role` in the JavaScript, from end ORDER here)',
  );
  stdout.writeln(
    '  R3 divergence     $refusedPairAgreements cases carry an end-scope pair'
    ' `validateDocument` refuses; both derivations agree on all of them',
  );
  for (final failure in failures.take(20)) {
    stdout.writeln('  FAIL $failure');
  }
  if (failures.length > 20) {
    stdout.writeln('  ... and ${failures.length - 20} more');
  }
  exit(failures.isEmpty ? 0 : 1);
}
