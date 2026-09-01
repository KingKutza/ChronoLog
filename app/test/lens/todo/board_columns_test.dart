// A LIST OF THINGS OFFERS TO MAKE THE THING (ISSUES 9.1, the board report).
//
// "In board view group by frame I see no power to pull up frames." Finding (a)
// was that the chosen-columns half was never built: a standing column comes from
// `view['columns']` and NOTHING writes that key, so the empty-column machinery
// waited on an affordance that did not exist. This is the board's side of it —
// the surface reads the key, offers the door that writes it, and says in words
// what the grouping it is showing actually reads.

import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/lens/todo/board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../edit/harness.dart';
import '../../helpers/projection_scene.dart';
import '../painters/grid_scene.dart';

const String frameId = 'calendar:a';

final List<Bench> _open = [];

Future<Editor> editorOver(Scene world) async {
  final bench = await openEditor(world.document, label: 'board-columns');
  _open.add(bench);
  return bench.editor;
}

Scene worldWithFrame() {
  final world = Scene()..calendar(frameId);
  world.frame('frame:tiger', const ['set', 'group']);
  world.document = world.document.put(
    'frames',
    'frame:tiger',
    world.document.frames['frame:tiger']!.copyWith(title: 'AI Tiger Team'),
  );
  return world;
}

Future<void> pump(WidgetTester tester, Widget lens) => tester.pumpWidget(
  MaterialApp(
    theme: themeDataFor(shipped['paper']!),
    home: Scaffold(body: SizedBox(width: 1200, height: 700, child: lens)),
  ),
);

void main() {
  tearDownAll(() async {
    for (final bench in _open) {
      await closeEditor(bench);
    }
  });

  testWidgets('the board offers a door that writes the standing-columns key', (tester) async {
    final written = <String, Object?>{};
    final editor = (await tester.runAsync(() => editorOver(worldWithFrame())))!;
    await pump(
      tester,
      BoardLens(
        todoSceneOf(
          editor,
          const [frameId],
          lens: 'board',
          view: const {'grouping': 'frame', 'columns': <Object?>[]},
          onView: (key, value) => written[key] = value,
        ),
      ),
    );
    await tester.tap(find.text('Stand a column…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI Tiger Team').last);
    await tester.pumpAndSettle();
    expect(
      written['columns'],
      contains('frame:tiger'),
      reason:
          'ISSUES (9.1): the empty-column machinery reads view[columns] and nothing '
          'wrote it — a feature with no door.',
    );
  });

  testWidgets('a chosen column stands before anything is in it', (tester) async {
    final editor = (await tester.runAsync(() => editorOver(worldWithFrame())))!;
    await pump(
      tester,
      BoardLens(
        todoSceneOf(
          editor,
          const [frameId],
          lens: 'board',
          view: const {
            'grouping': 'frame',
            'columns': ['frame:tiger'],
          },
        ),
      ),
    );
    expect(find.text('AI Tiger Team'), findsWidgets);
  });

  testWidgets('the surface says in words what its grouping reads', (tester) async {
    // Finding (c): "Done is a state frame and only the state grouping ever shows
    // it — reasonable, but nothing on the surface says so."
    final editor = (await tester.runAsync(() => editorOver(worldWithFrame())))!;
    for (final grouping in ['frame', 'state']) {
      await pump(
        tester,
        BoardLens(
          todoSceneOf(
            editor,
            const [frameId],
            lens: 'board',
            view: {'grouping': grouping},
          ),
        ),
      );
      expect(
        find.textContaining('Columns are'),
        findsWidgets,
        reason: 'ISSUES (9.1): the $grouping grouping owes one sentence about what it reads',
      );
      // And under group-by-frame the sentence names STAPLES, which is the ruling
      // the columns now follow: there is no membership, only staples.
      if (grouping == 'frame') expect(find.textContaining('stapled'), findsWidgets);
    }
  });
}
