// THE STAPLE-TO SEARCH NEVER GOES BLIND (ISSUES 9.2, Don's overscale question).
//
// "How does the staple-to search work with 50 frames, 2k todos and 1200 events?"
// Verified: a linear sweep cut by a RECORD budget (2000 looked at), so the tail
// of the document is unfindable by any query, and no ranking. The rule:
//
//   Every title is findable by its own words at any document size, and the
//   most-connected candidate ranks first among equals. A budget bounds WORK
//   (the window shown), never DATA (what can be found).
//
// Generative: seeded titles, seeded connection counts.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/cards/connection_picker.dart';
import 'package:chronolog/core/records.dart';
import 'package:test/test.dart';

import '../helpers/projection_scene.dart';

final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

void main() {
  // ignore: avoid_print
  print('SEARCH INDEX RUN SEED: $runSeed  (set CHRONOLOG_SEED=$runSeed to reproduce)');
  final random = Random(runSeed);

  test('50 frames and 3,200 objects: every title is findable by its own word', () {
    final scene = Scene();
    for (var i = 0; i < 50; i += 1) {
      scene.frame('group:$i', const ['set', 'group'], {'title': 'Group $i'});
    }
    final titles = <String, String>{};
    for (var i = 0; i < 3200; i += 1) {
      final word = 'w${random.nextInt(1 << 30).toRadixString(36)}x$i';
      titles[scene.object(title: 'Item $word', duration: '0')] = word;
    }
    final keys = titles.keys.toList();
    final probes = [for (var i = 0; i < 40; i += 1) keys[random.nextInt(keys.length)]];
    final blind = <String>[];
    for (final id in probes) {
      final found = searchConnectables(scene.document, titles[id]!, window: 12, scan: 2000);
      if (!found.hits.any((hit) => hit.id == id)) blind.add(titles[id]!);
    }
    expect(
      blind,
      isEmpty,
      reason:
          'ISSUES 9.2: ${blind.length} of 40 sampled titles cannot be found by their own '
          'unique word -- the record budget skipped them. Index titles; bound the window, not the data.',
    );
  });

  test('among equals, the most-connected candidate ranks first', () {
    final scene = Scene()..calendar('calendar:a');
    final ids = [
      for (var i = 0; i < 6; i += 1) scene.object(title: 'Reggie follow-up $i', duration: '0'),
    ];
    // The hub is minted LAST, so document order alone can never rank it first.
    final hub = ids.last;
    for (var i = 0; i < 5; i += 1) {
      final other = scene.object(title: 'Other $i', duration: '0');
      scene.staple(ends: [ObjectEnd(hub), ObjectEnd(other)]);
    }
    final found = searchConnectables(scene.document, 'reggie', window: 12, scan: 2000);
    expect(found.hits, isNotEmpty);
    expect(
      found.hits.first.id,
      equals(hub),
      reason:
          'ISSUES 9.2: six titles match "reggie"; the one with five connections must rank '
          'first, not whichever the document happened to list first.',
    );
  });
}
