// Properties of the two roster lenses, and of the capture that feeds them.
//
// The rulings under test: population is the projection and no state gate
// exists; an empty section is never emitted; a column exists before its first
// card; a capture ASKS before it writes; a completion says where the object
// went instead of vanishing.

import 'package:chronolog/core/object_kinds.dart';
import 'package:chronolog/core/todo_shape.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/lens/todo/board.dart';
import 'package:chronolog/lens/todo/capture_bar.dart';
import 'package:chronolog/lens/todo/list.dart';
import 'package:chronolog/lens/todo/row.dart';
import 'package:chronolog/lens/view_tile.dart';
import 'package:chronolog/session/lens_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../edit/harness.dart';
import '../../helpers/projection_scene.dart';
import '../painters/grid_scene.dart';

final List<Bench> _open = [];

/// An editor over a scene's document, through the real store on a temp root the
/// spec tears down.
Future<Editor> editorOver(Scene world) async {
  final bench = await openEditor(world.document, label: 'todo');
  _open.add(bench);
  return bench.editor;
}

Future<void> pump(WidgetTester tester, Widget lens) => tester.pumpWidget(
  MaterialApp(
    theme: themeDataFor(shipped['paper']!),
    home: Scaffold(body: SizedBox(width: 900, height: 700, child: lens)),
  ),
);

Scene todoWorld({int open = 3, int done = 2}) {
  final world = Scene()..calendar('calendar:a');
  world.group('frame:errands', const []);
  world.document = world.document.put(
    'frames',
    'frame:errands',
    world.document.frames['frame:errands']!.copyWith(title: 'Errands'),
  );
  for (var index = 0; index < open + done; index += 1) {
    final id = world.object(title: 'Task $index', duration: '0');
    world.document = world.document.put(
      'events',
      id,
      world.document.events[id]!.copyWith(traits: const ['event', 'task', 'todo']),
    );
    world.place('calendar:a', civil(2026, 8, 18 + (index % 4)), event: id);
    world.join('frame:errands', id);
  }
  return world;
}

void main() {
  tearDown(() async {
    for (final bench in _open) {
      await closeEditor(bench);
    }
    _open.clear();
  });

  test(
    'every registered roster lens is a lens the catalog declares, and none is a time surface',
    () {
      registerTodoLenses();
      expect(lensWidgets.keys, isNotEmpty);
      for (final id in lensWidgets.keys) {
        expect(lensCatalog[id], isNotNull, reason: '$id is not in the catalog');
        expect(lensCatalog[id]!.isTimeSurface, isFalse);
      }
    },
  );

  test('an unplaced capture is still on the roster: nothing that has no home is lost', () async {
    final editor = await editorOver(todoWorld());
    final capture = editor.captureQuickTodo('Buy milk')!;
    expect(capture.ask, isNull);
    editor.confirmCapture(capture);
    final scene = todoSceneOf(editor, const ['calendar:a', 'frame:errands']);
    final entries = todoEntries(scene, 900, 700);
    expect(entries.drawn.any((entry) => entry.title == 'Buy milk'), isTrue);
  });

  test('sections are never empty, and the unnamed one leads', () async {
    final editor = await editorOver(todoWorld());
    for (final grouping in lensGroupings) {
      final scene = todoSceneOf(
        editor,
        const ['calendar:a', 'frame:errands'],
        view: {'grouping': grouping},
      );
      final entries = todoEntries(scene, 900, 700);
      final sections = sectionsOf<TodoEntry>(entries.drawn, (entry) => placementsOf(scene, entry));
      expect(sections, isNotEmpty, reason: grouping);
      for (final section in sections) {
        expect(section.entries, isNotEmpty, reason: '$grouping/${section.title}');
      }
      final unnamed = sections.indexWhere((section) => section.key == null);
      if (unnamed >= 0) expect(unnamed, 0, reason: 'the unnamed section leads');
    }
  });

  test('completing an object does not remove it from a roster that projects its state', () async {
    final editor = await editorOver(todoWorld());
    final scene = todoSceneOf(editor, const ['calendar:a', 'frame:errands']);
    final before = todoEntries(scene, 900, 700).drawn;
    editor.toggleState(before.first.id, doneStateFrameId);
    final after = todoEntries(scene, 900, 700).drawn;
    expect(after.map((entry) => entry.id), contains(before.first.id));
    expect(after.firstWhere((entry) => entry.id == before.first.id).states, isNotEmpty);
  });

  test('a capture with a near-miss group ASKS, and commits nothing until confirmed', () async {
    final editor = await editorOver(todoWorld());
    final events = editor.document.events.length;
    final capture = editor.captureQuickTodo('Post a letter #erronds')!;
    expect(capture.ask, isNotNull);
    expect(capture.ask!.candidates.map((c) => c.id), contains('frame:errands'));
    expect(editor.document.events.length, events, reason: 'the ask wrote nothing');
    editor.confirmCapture(capture, groupId: capture.ask!.candidates.first.id);
    expect(editor.document.events.length, events + 1);
  });

  testWidgets('the List lens renders with no calendar frame at all', (tester) async {
    final editor = (await tester.runAsync(() => editorOver(Scene())))!;
    await pump(tester, ListLens(todoSceneOf(editor, const [])));
    expect(tester.takeException(), isNull);
    expect(find.byType(CaptureBar), findsOneWidget);
  });

  testWidgets('the List lens shows one capture field and one row per entry', (tester) async {
    final editor = (await tester.runAsync(() => editorOver(todoWorld(open: 3, done: 0))))!;
    await pump(tester, ListLens(todoSceneOf(editor, const ['calendar:a', 'frame:errands'])));
    expect(tester.takeException(), isNull);
    // Exactly one capture input on the surface (survey B22).
    expect(find.byType(CaptureBar), findsOneWidget);
    expect(find.byType(TodoRow), findsNWidgets(3));
  });

  testWidgets('a Board column exists before its first card, and captures into itself', (
    tester,
  ) async {
    final editor = (await tester.runAsync(() => editorOver(todoWorld())))!;
    // A state frame nothing is in yet: its column must still be there, or the
    // first card can never be put in it.
    editor.commit(
      'Author a state',
      ensureStateFrame(editor.document, id: 'frame:state-parked', title: 'Parked').document,
    );
    final scene = todoSceneOf(
      editor,
      const ['calendar:a', 'frame:errands'],
      lens: 'board',
      view: const {'grouping': 'state'},
    );
    await pump(tester, BoardLens(scene));
    expect(tester.takeException(), isNull);
    // The column's NAME is its own widget beside its count (ISSUES 9.1): a
    // heading that welds the two into one string is a name the surface cannot
    // hand to anything.
    expect(find.text('Parked'), findsOneWidget);
    expect(find.text('· 0'), findsWidgets);
    // Every column head carries its own capture, seeded with that column's fact.
    expect(find.byType(CaptureBar), findsWidgets);
  });

  testWidgets('a capture from a column head is born carrying the column state', (tester) async {
    final editor = (await tester.runAsync(() => editorOver(todoWorld())))!;
    final scene = todoSceneOf(editor, const ['calendar:a', 'frame:errands'], lens: 'board');
    await pump(
      tester,
      Material(
        child: CaptureBar(scene: scene, seed: const {'state': doneStateFrameId}),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'Mow the lawn');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    final born = editor.document.events.values.firstWhere(
      (event) => event.payload?['title'] == 'Mow the lawn',
    );
    expect(editor.engine.facts.stateAffiliations(born.id).map((s) => s.frame), [doneStateFrameId]);
  });
}
