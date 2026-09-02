// NAMELESS MARKS FLOW; THE CELL'S AREA IS THE BUDGET (ISSUES 9.2, Strategic).
//
// "All the sigils stack on the left edge -- why not fill the space, or a row
// per type in order of importance, and hover to view the event." Verified: each
// admitted fact takes a full-width row, a pip at its left, so a cell with room
// for forty pips shows a dozen and "N+". The rule:
//
//   A pip that shows no name does not take a row. Pips wrap across the cell,
//   grouped and weight-ordered, so a cell of N nameless facts draws all N while
//   N x footprint <= the cell's area. Hover names any mark.
//
// Generative: a random day and a random count.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/lens/painters/strategic.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/projection_scene.dart';
import 'painters/grid_scene.dart';

final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

const String frameId = 'calendar:a';

Map<String, Object?> at(int day, int hour) => {
  'levels': [
    {'level': 'year', 'value': '2026'},
    {'level': 'month', 'value': '9'},
    {'level': 'day', 'value': '$day'},
    {'level': 'hour', 'value': '$hour'},
    {'level': 'minute', 'value': '0'},
  ],
};

void main() {
  // ignore: avoid_print
  print('STRATEGIC FLOW RUN SEED: $runSeed  (set CHRONOLOG_SEED=$runSeed to reproduce)');
  final random = Random(runSeed);

  test('a cell with area for N nameless pips draws all N', () {
    final scene = Scene()..calendar(frameId);
    final day = 1 + random.nextInt(28), count = 30 + random.nextInt(20);
    final ids = <String>{};
    for (var i = 0; i < count; i += 1) {
      final id = scene.object(title: '', duration: '15');
      scene.place(frameId, at(day, 8 + (i % 10)), event: id);
      ids.add(id);
    }
    // A generous surface: six month-rows by up to 31 columns, each cell roughly
    // 100 x 330 px -- thousands of square pixels per pip.
    const size = Size(3200, 2000);
    final lens = sceneOf(scene.document, const [frameId], size: size, focus: civilDays(2026, 9, day));
    final painter = StrategicPainter(lens);
    render(painter, size);
    final drawn = painter.hits.where((hit) => ids.contains(hit.fact.event.id)).length;
    expect(
      drawn,
      equals(count),
      reason:
          'ISSUES 9.2: $drawn of $count nameless marks registered in a cell with room for all of '
          'them -- each took a full-width row and the cell overflowed to "N+" with most of its '
          'area blank. Nameless pips flow across the cell.',
    );
  });

  test('hover names any mark', () {
    // WORK ITEM (ISSUES 9.2): the view tile's hover sets the cursor and nothing
    // else. When the shared hover plate exists (the drag ghost's plate painter,
    // melted), this test hovers a registered hit and asserts a plate carrying the
    // fact's title is painted.
    fail(
      'ISSUES 9.2: no hover label exists on any lens mark. Melt the ghost\'s plate into a '
      'shared hover affordance after `pointer.hoverMillis`, then assert the title here.',
    );
  });
}
