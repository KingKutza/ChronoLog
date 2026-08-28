// EVERY SETTING THE PROGRAM READS HAS A SHIPPED DEFAULT.
//
// "No literals in lenses or chrome" is only true if the other half holds: a key
// a surface names must resolve. `Settings` answers an unknown key with zero and
// a refusal, which draws a wrong surface quietly -- a threshold of zero promotes
// everything, a pixel size of zero paints nothing. So this reads the source of
// every file under `lib/`, collects the keys it actually names, and refuses
// loudly here rather than on someone's screen.
//
// The scan is deliberately literal-minded: a quoted, dotted, lowercase-leading
// string whose first segment is one of the composed areas IS a settings key.
// Keys built by interpolation cannot be read that way, so the families they
// range over are named below and asserted whole.

import 'dart:convert';
import 'dart:io';

import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/lens/minimap/labels.dart';
import 'package:chronolog/session/lens_catalog.dart';
import 'package:test/test.dart';

/// A quoted dotted key, optionally a prefix (`stage.snap.`).
final RegExp _literal = RegExp("'([a-z][A-Za-z0-9]*(?:[.][A-Za-z0-9]+)+[.]?)'");

/// Every key that is spelled by interpolation rather than written out, named by
/// the family it ranges over so the assertion is still exact.
///
/// The promotion pair is per lens (`promotionOf`'s `keyPrefix`), so every lens
/// that promotes has to carry one; the minimap's label budget is per format.
const List<String> _promoting = [
  'weight',
  'intimate',
  'tactical',
  'strategic',
  'wall',
  'lines',
  'spiral',
  'radial',
  'tree',
  'todo.list',
  'todo.board',
];

List<File> _sources(Directory root) => [
  for (final entry in root.listSync(recursive: true))
    if (entry is File && entry.path.endsWith('.dart') && !entry.path.endsWith('.freezed.dart'))
      entry,
];

void main() {
  final settings = chronologSettings();
  final known = {...settings.keys, ...settings.shippedText.keys};
  final areas = {for (final key in known) key.split('.').first};

  void resolves(String key, String where) {
    if (key.endsWith('.')) {
      expect(
        known.any((named) => named.startsWith(key)),
        isTrue,
        reason: '$where reads the family "$key" and no shipped default begins with it',
      );
      return;
    }
    // Both vocabularies: a tunable evaluates through the one math, a text
    // setting is a chord or a name and reading it as algebra would be a
    // category error. Either one shipping the key is an answer.
    expect(
      settings.expressionOf(key).isNotEmpty || settings.shippedText.containsKey(key),
      isTrue,
      reason: '$where reads "$key" and no defaults map ships one',
    );
  }

  test('every settings key any file in lib/ names resolves against the composed defaults', () {
    final root = Directory('lib');
    expect(root.existsSync(), isTrue, reason: 'run from app/');
    var found = 0;
    for (final source in _sources(root)) {
      // Import directives quote dotted names too, and a file name is not a
      // setting: `import 'document.dart'` is not a read of `document.dart`.
      final lines = const LineSplitter()
          .convert(source.readAsStringSync())
          .where((line) => !line.trimLeft().startsWith('import '))
          .where((line) => !line.trimLeft().startsWith('export '));
      for (final match in _literal.allMatches(lines.join(' '))) {
        final key = match[1]!;
        if (!areas.contains(key.split('.').first)) continue;
        found += 1;
        resolves(key, source.path);
      }
    }
    expect(found, greaterThan(0), reason: 'the scan found no keys at all, so it proves nothing');
  });

  test('every lens that promotes carries its own pair of thresholds', () {
    for (final prefix in _promoting) {
      resolves('$prefix.importantAt', 'promotionOf($prefix)');
      resolves('$prefix.landmarkAt', 'promotionOf($prefix)');
    }
  });

  test('the minimap has a label budget for every format its ladder can choose', () {
    final formats = {
      for (final rungs in labelLadders.values)
        for (final rung in rungs) rung.$1,
      ...labelGranularity.values,
      'fallback',
    };
    for (final format in formats) {
      resolves('minimap.budget.$format', 'the minimap label ladder');
    }
  });

  test('every view key a lens declares names a shipped default', () {
    for (final spec in lensCatalog.values) {
      for (final entry in spec.viewDefaults.entries) {
        resolves(entry.value, '${spec.id}.${entry.key}');
      }
      final scale = spec.scaleKey;
      if (scale == null) continue;
      expect(
        spec.controls.any((control) => control.key == scale),
        isTrue,
        reason: '${spec.id} scales "$scale", which it does not declare',
      );
    }
  });
}
