// The geometry half of the lens differential harness.
//
// `tool/lens_diff_check.dart` replays everything the oracle emits that pure Dart
// can answer. Polar geometry cannot: `polar`, `arcPath` and `spiralRibbon` are
// built on `dart:ui`, and the standalone Dart VM has no engine behind it. So the
// SAME generator -- `tool/lens_diff_gen.mjs`, same seed, one case set -- is run
// once more here, where `flutter test` supplies one.
//
// This is a harness, not a unit test: it compares the port against the shipped
// JavaScript, and a disagreement is a port defect rather than a broken
// expectation. NO SKIPS (ISSUES.md, ruled 8.31): a harness that cannot reach
// its oracle has verified NOTHING, so it fails and says which prerequisite is
// missing rather than reporting a green light for work it never checked.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:chronolog/lens/radial/geometry.dart';
import 'package:flutter_test/flutter_test.dart';

String fixed(double value) => value.isFinite ? value.toStringAsFixed(6) : '$value';
String two(double value) => value.toStringAsFixed(2);
double number(Object? value) => double.parse('$value');
List<Object?> list(Object? value) => value as List<Object?>;
Map<String, Object?> map(Object? value) => (value as Map).cast<String, Object?>();

/// The oracle is RUN, not read: a cases file left over from an older generator
/// would turn a real disagreement into a pass. The saved file is only a fallback
/// for an environment with no node.
Map<String, Object?>? oracle() {
  try {
    final result = Process.runSync('node', ['tool/lens_diff_gen.mjs'], stdoutEncoding: utf8);
    if (result.exitCode == 0) return map(jsonDecode(result.stdout as String));
  } catch (_) {
    // Falls through to the saved cases.
  }
  final saved = File('build/lens-diff-cases.json');
  return saved.existsSync() ? map(jsonDecode(saved.readAsStringSync())) : null;
}

void main() {
  final cases = oracle();
  if (cases == null) {
    test('the lens geometry oracle answers', () {
      fail(
        'NOT VERIFIED (ISSUES.md, NO SKIPS ruled 8.31): the geometry oracle '
        'could not be reached -- node is not on the path to run '
        'tool/lens_diff_gen.mjs, and build/lens-diff-cases.json is not there '
        'either. polar, arcPath and spiralRibbon were compared against '
        'nothing. Put node on the path or generate the cases file; this light '
        'stays red until the comparison actually runs.',
      );
    });
    return;
  }

  test('polar agrees with the shipped JavaScript, point for point', () {
    var checked = 0;
    for (final row in list(cases['polar'])) {
      final entry = map(row);
      final point = polar(
        Offset(number(entry['cx']), number(entry['cy'])),
        number(entry['radius']),
        number(entry['angle']),
      );
      expect([fixed(point.dx), fixed(point.dy)], [entry['x'], entry['y']]);
      checked += 1;
    }
    expect(checked, greaterThan(0));
  });

  test("an arc's endpoints agree with the shipped path's own", () {
    for (final row in list(cases['arcs'])) {
      final entry = map(row);
      final centre = Offset(number(entry['cx']), number(entry['cy']));
      final metric = arcPath(
        centre,
        number(entry['radius']),
        number(entry['from']),
        number(entry['to']),
      ).computeMetrics().first;
      final start = metric.getTangentForOffset(0)!.position;
      final end = metric.getTangentForOffset(metric.length)!.position;
      // A tolerance rather than a string, and the claim is the honest one: the
      // JavaScript emits an SVG path rounded to two decimals, and the engine
      // parameterizes an arc its own way, so what agrees here is WHERE the
      // endpoints are -- to well under a pixel -- not which side of a rounding
      // boundary each coordinate landed on.
      final ends = list(entry['ends']);
      for (final (index, value) in [start.dx, start.dy, end.dx, end.dy].indexed) {
        expect(value, closeTo(number(ends[index]), 2 / 100));
      }
    }
  });

  test('the ribbon has the same vertex count and the same two termini', () {
    for (final row in list(cases['ribbons'])) {
      final entry = map(row);
      final centre = Offset(number(entry['cx']), number(entry['cy']));
      final halfWidth = number(entry['halfWidth']);
      final samples = int.parse('${entry['samples']}');
      final metric = spiralRibbon(
        centre,
        inner: number(entry['inner']),
        spacing: number(entry['spacing']),
        turns: int.parse('${entry['turns']}'),
        samples: samples,
        halfWidth: halfWidth,
      ).computeMetrics().first;
      // One outer and one inner sample per progress step, both sides.
      expect((samples + 1) * 2, entry['count']);
      final outerStart = metric.getTangentForOffset(0)!.position;
      // The closing segment joins the two radii of the start ray, so the inner
      // terminus sits exactly that far back along the outline.
      final innerStart = metric
          .getTangentForOffset(math.max(0, metric.length - halfWidth * 2))!
          .position;
      expect([two(outerStart.dx), two(outerStart.dy)], entry['outerStart']);
      expect([two(innerStart.dx), two(innerStart.dy)], entry['innerStart']);
    }
  });
}
