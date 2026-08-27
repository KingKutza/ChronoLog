// The two shipped real documents, loaded as files.
//
// These are the only pinned facts in the spec, and they are pinned deliberately:
// they are FIXTURES OF THE FILE FORMAT, not assertions about behaviour. The
// JavaScript validator reports zero errors on both (captured by running it
// directly), and both are full of the time-travel taxonomy whose validators died
// as written -- so if this build refused either of them, or altered a byte, the
// ruling that unknown types are data would be a claim with nothing behind it.

import 'dart:convert';
import 'dart:io';

import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/validate.dart';
import 'package:test/test.dart';

/// `dart test` runs from the package root, and the fixtures live beside it.
File fixture(String name) => File('../fixtures/$name');

const String taxonomy = 'time-travel-taxonomy.chronolog.json';
const String skyland = 'skyland-coordinate-mapping.chronolog.json';

void main() {
  test('both fixtures parse, and the schema is left exactly as written', () {
    for (final name in [taxonomy, skyland]) {
      final document = Document.fromJson(jsonDecode(fixture(name).readAsStringSync()) as Json);
      expect(document.schema, 'chronolog/1', reason: name);
      expect(document.frames, isNotEmpty, reason: name);
    }
  });

  test('both validate with exactly the errors the JavaScript reports: none', () {
    // RULED ANCHOR, measured: `validateDocument` from src/model.js reports
    // valid=true, errors=0 for both files. This build must agree, which it can
    // only do by treating every taxonomy relation as data.
    for (final name in [taxonomy, skyland]) {
      final document = Document.fromJson(jsonDecode(fixture(name).readAsStringSync()) as Json);
      expect(validateDocument(document).errors, isEmpty, reason: name);
    }
  });

  test('the taxonomy fixture round-trips byte for byte', () {
    // The strongest statement available: this file was written by
    // `JSON.stringify(document, null, 2)` plus a trailing newline, so a
    // two-space rendering of what loaded must be the file again -- no key moved,
    // no field dropped, no value reformatted, across eight relation types this
    // build has no validator for.
    final text = fixture(taxonomy).readAsStringSync();
    final document = Document.fromJson(jsonDecode(text) as Json);
    final rendered = '${JsonEncoder.withIndent('  ').convert(document.toJson())}\n';
    expect(rendered, text);
  });

  test('the skyland fixture round-trips value for value', () {
    // Written with a different indentation, so byte equality is not the claim;
    // the claim is that nothing was lost, including a coordinate mapping's
    // nested interval anchors and its author's note.
    final text = fixture(skyland).readAsStringSync();
    final parsed = jsonDecode(text);
    final document = Document.fromJson(parsed as Json);
    expect(document.toJson(), parsed);

    final mapping = document.relations.values.single;
    expect(mapping.type, 'coordinate-mapping');
    expect(mapping.extra['direction'], 'forward');
    final anchors = mapping.extra['anchors'] as List;
    expect((anchors.single as Map)['continuity'], 'discontinuous');
    expect((anchors.single as Map)['note'], contains('no implied interpolation exists'));
  });

  test('the taxonomy fixture keeps every unknown relation type it carries', () {
    final document = Document.fromJson(jsonDecode(fixture(taxonomy).readAsStringSync()) as Json);
    final types = document.relations.values.map((r) => r.type).toSet();
    // Named here as a record of what is being protected, not as a vocabulary:
    // these four had hardcoded validators, and the data outlives them.
    expect(types, containsAll(['shared-segment', 'termination', 'displacement']));
    // A termination's own fields survive, unvalidated and unaltered.
    final termination = document.relations['termination:sealed-fork']!;
    expect(termination.extra, {
      'line': 'line:fork',
      'terminator': 'attachment:sealed-fork',
      'state': 'sealed',
    });
    // And a pattern in a language this build cannot evaluate loads intact.
    final pattern = document.patterns['pattern:groundhog-loop-days']!;
    expect(pattern.language, 'chronolog-topology/1');
    expect(pattern.kind, 'topology-replication');
    expect(pattern.extra['copies'], ['line:loop-day-1', 'line:loop-day-2']);
  });

  test('a frame that authors no coordinate is silent, not broken', () {
    final document = Document.fromJson(jsonDecode(fixture(taxonomy).readAsStringSync()) as Json);
    final measure = document.frames['measure:proper-time']!;
    expect(measure.coordinate, isNull);
    expect(measure.traits, ['line', 'measure', 'duration']);
    expect(validateDocument(document).errors, isEmpty);
  });
}
