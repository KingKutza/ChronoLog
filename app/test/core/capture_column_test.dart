// A COLUMN-BORN TODO HAS ONE STAPLE (ISSUES 9.2, Don's ruling on the board).
//
// "If I have a non-time frame as a column and I author a bunch of todos stapled
// to it, they would only be on that frame." Verified: the capture also placed
// every todo on the board's projected calendar frame at NOW, which is why they
// appeared under the group AND under Wall Time. The rule:
//
//   A capture confirmed INTO a group with no time said writes exactly one
//   connection -- the staple to that group -- and no calendar placement. A todo
//   with only a group staple has no position, and that is fine.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/staples.dart';
import 'package:chronolog/edit/capture.dart';
import 'package:test/test.dart';

import '../edit/harness.dart';

final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

void main() {
  // ignore: avoid_print
  print('CAPTURE COLUMN RUN SEED: $runSeed  (set CHRONOLOG_SEED=$runSeed to reproduce)');
  final random = Random(runSeed);

  test('a capture into a group with no time said writes no placement', () async {
    final bench = await openEditor(createEmptyWorkspaceDocument());
    addTearDown(() => closeEditor(bench));
    final editor = bench.editor;
    final calendar = editor.document.frames.values
        .firstWhere((frame) => frame.traits.contains('temporal'))
        .id;
    final group = 'group:${random.nextInt(1 << 20)}';
    editor.transaction(
      'New group',
      (d) => d.put(
        'frames',
        group,
        Frame(id: group, title: 'AI Team', traits: const ['set', 'group']),
      ),
    );
    final capture = editor.captureQuickTodo(
      'Follow up with Reggie',
      frameId: calendar,
      todayDays: Rational.fromInt(random.nextInt(1000)),
    );
    expect(capture, isNotNull);
    final id = editor.confirmCapture(capture!, groupId: group);
    final mine = editor.document.relations.values
        .where((relation) => relation.ends.whereType<ObjectEnd>().any((end) => end.object == id))
        .toList();
    expect(
      mine.where((relation) => isPlacement(relation, id)),
      isEmpty,
      reason:
          'ISSUES 9.2: born in a column, stapled to the group, placed on NOTHING. The '
          'calendar placement at NOW is what put every column todo under Wall Time too.',
    );
    expect(
      mine.where((relation) => relation.ends.any((end) => end is FrameEnd && end.frame == group)),
      hasLength(1),
      reason: 'exactly one staple, to the group',
    );
  });
}
