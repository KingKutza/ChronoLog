// THERE IS NO MEMBERSHIP, ONLY STAPLES (Don, ruled 2026-09-01, answering the
// board report): "the only relationship any object or frame can have to
// another is a staple."
//
// The field report: "In board view group by frame I see no power to pull up
// frames — not Wall time or Done, or AI Tiger Team or anything else." Under
// group-by-frame a todo's columns came from direct group MEMBERSHIP alone, so a
// frame the todo is STAPLED to never columned — Don's own AI Tiger Team
// connection, authored by the picker as an anchor staple, was invisible to the
// board. The ruling makes the claim simple: a todo columns under every frame it
// is stapled to, however the staple was said.

import 'package:chronolog/core/records.dart';
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
  final bench = await openEditor(world.document, label: 'board-staples');
  _open.add(bench);
  return bench.editor;
}

Future<void> pump(WidgetTester tester, Widget lens) => tester.pumpWidget(
  MaterialApp(
    theme: themeDataFor(shipped['paper']!),
    home: Scaffold(body: SizedBox(width: 900, height: 700, child: lens)),
  ),
);

void main() {
  tearDownAll(() async {
    for (final bench in _open) {
      await closeEditor(bench);
    }
  });

  testWidgets('a todo columns under every frame it is stapled to', (tester) async {
    final world = Scene()..calendar(frameId);
    world.frame('frame:tiger', const ['set', 'group']);
    world.document = world.document.put(
      'frames',
      'frame:tiger',
      world.document.frames['frame:tiger']!.copyWith(title: 'AI Tiger Team'),
    );
    final todo = world.object(title: 'Chase the grading rubric', duration: '0');
    world.document = world.document.put(
      'events',
      todo,
      world.document.events[todo]!.copyWith(traits: const ['event', 'task', 'todo']),
    );
    world.place(frameId, civil(2026, 9, 1, 9), event: todo);
    // Don's exact authoring path: the picker's anchor staple, NOT a membership.
    world.staple(
      kind: 'anchor',
      ends: [ObjectEnd(todo, point: 'start'), StapleEnd.frame('frame:tiger')],
    );

    final editor = (await tester.runAsync(() => editorOver(world)))!;
    final scene = todoSceneOf(
      editor,
      const [frameId],
      lens: 'board',
      view: const {'grouping': 'frame'},
    );
    await pump(tester, BoardLens(scene));
    await tester.pump();
    expect(
      find.text('AI Tiger Team'),
      findsWidgets,
      reason:
          'ISSUES (9.1, ruled): there is no membership, only staples — the todo is '
          'stapled to AI Tiger Team and the board columns it under membership alone, '
          'so the connection Don authored is invisible to the grouping.',
    );
  });

  testWidgets('a membership-shaped staple still columns (the old path keeps working)', (
    tester,
  ) async {
    final world = Scene()..calendar(frameId);
    world.group('frame:errands', const []);
    world.document = world.document.put(
      'frames',
      'frame:errands',
      world.document.frames['frame:errands']!.copyWith(title: 'Errands'),
    );
    final todo = world.object(title: 'Buy staples', duration: '0');
    world.document = world.document.put(
      'events',
      todo,
      world.document.events[todo]!.copyWith(traits: const ['event', 'task', 'todo']),
    );
    world.place(frameId, civil(2026, 9, 1, 9), event: todo);
    world.join('frame:errands', todo);

    final editor = (await tester.runAsync(() => editorOver(world)))!;
    final scene = todoSceneOf(
      editor,
      const [frameId],
      lens: 'board',
      view: const {'grouping': 'frame'},
    );
    await pump(tester, BoardLens(scene));
    await tester.pump();
    expect(find.text('Errands'), findsWidgets);
  });
}
