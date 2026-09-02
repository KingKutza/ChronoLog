// THE BOARD'S COLUMNS ARE AUTHORED (ISSUES 9.2, six board reports).
//
// "Columns move: when I added some todos the second frame moved left." Verified:
// populated columns sort alphabetically and empty standing columns are appended
// after them, so a frame that gains a member jumps. Then Don's rulings: drag a
// header to reorder; single-click a header to switch the column; double-click to
// open the frame; create a frame from a new column; a NOT term per column; a
// staple indicator between connected todos.
//
//   The order IS the authored list `view['columns']`; a column's position never
//   depends on what it holds.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/core/records.dart';
import 'package:chronolog/lens/todo/board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../edit/harness.dart';
import '../../helpers/projection_scene.dart';
import '../painters/grid_scene.dart';

final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

const String calendar = 'calendar:a';

Map<String, Object?> at(int day, int hour) => {
  'levels': [
    {'level': 'year', 'value': '2026'},
    {'level': 'month', 'value': '8'},
    {'level': 'day', 'value': '$day'},
    {'level': 'hour', 'value': '$hour'},
    {'level': 'minute', 'value': '0'},
  ],
};

void main() {
  // ignore: avoid_print
  print('BOARD ORDER RUN SEED: $runSeed  (set CHRONOLOG_SEED=$runSeed to reproduce)');
  final random = Random(runSeed);

  testWidgets('columns stand in the authored order, whatever they hold', (tester) async {
    final scene = Scene()..calendar(calendar);
    final titles = ['Alpha', 'Beta', 'Gamma']..shuffle(random);
    final groups = <String>[];
    for (final title in titles) {
      final id = 'group:${title.toLowerCase()}';
      groups.add(id);
      scene.document = scene.document.put(
        'frames',
        id,
        Frame(id: id, title: title, traits: const ['set', 'group']),
      );
      final todo = scene.mint('event');
      scene.document = scene.document.put(
        'events',
        todo,
        Event(
          id: todo,
          traits: const ['event', 'task', 'todo'],
          magnitudes: const {},
          payload: {'title': 'Todo for $title'},
        ),
      );
      scene.place(calendar, at(18, 9), event: todo);
      scene.staple(ends: [ObjectEnd(todo), StapleEnd.frame(id)]);
    }
    // The authored order is the REVERSE of alphabetical, so a sort would betray it.
    final authored = [...groups]..sort((a, b) => b.compareTo(a));
    final bench = (await tester.runAsync(() => openEditor(scene.document)))!;
    addTearDown(() => closeEditor(bench));
    final board = todoSceneOf(
      bench.editor,
      const [calendar],
      lens: 'board',
      view: {'grouping': 'frame', 'columns': authored},
    );
    tester.view.physicalSize = const Size(2400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BoardLens(board))));
    await tester.pump();
    final xs = [
      for (final id in authored)
        tester.getTopLeft(find.text(scene.document.frames[id]!.title!).first).dx,
    ];
    expect(
      xs,
      equals([...xs]..sort()),
      reason:
          'ISSUES 9.2: the authored order ${authored.map((id) => scene.document.frames[id]!.title)} '
          'came out as x = $xs -- populated columns were sorted by title. Order is the list, never '
          'the contents.',
    );
  });

  test('a header drag writes the authored order; a header click switches the column', () {
    fail(
      'ISSUES 9.2: column headers are inert text with a count. Drag reorders `view[\'columns\']` '
      '(header and card drags are distinct payloads on one target); single-click drops the '
      'frame list with the create door; double-click opens the frame\'s card in another tile.',
    );
  });

  test('a typed name matching no frame offers to create it as a new column', () {
    fail(
      'ISSUES 9.2: "Stand a column..." lists existing frames only, and under the state grouping '
      'offers nothing. A name nothing wears is an offer to make it, through the one new-frame '
      'path with traits from the grouping.',
    );
  });

  test('a column is a projection: AI Team NOT Done is one column, AI Team AND Done another', () {
    fail(
      'ISSUES 9.2: columns are not projection terms -- an entry files under every frame it '
      'touches, so a per-column NOT leaks. A column carries its own expression, default the '
      'one-frame term, with the in / NOT / off three-state on the header\'s drop.',
    );
  });

  test('two stapled todos show their connection: sigil, adjacency in a column, line across', () {
    fail(
      'ISSUES 9.2: `TodoEntry` never reads object-to-object staples, so a follow-up stapled '
      'to its parent shows nothing. Sigil per staple, chained adjacency within a column, a '
      'dust line across columns.',
    );
  });
}
