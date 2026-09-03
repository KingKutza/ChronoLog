// SELECT MANY, SAY ONE SENTENCE (ISSUES 9.2, Don's rulings on multi-select).
//
// One gesture vocabulary on EVERY lens: a marquee (right-drag; ctrl-drag as the
// alternative), ctrl-click toggles one, right-click on a selection opens the
// context menu over the SET with mass edits. "Staple EACH to that" is the
// default (N two-ended staples, distance 1); "staple all AS ONE to that" is the
// alt (one N-ary staple, distance 0). Every mass edit is one transaction, one
// undo entry. Bindings are settings keys and must not overlap.
//
// The bindings shipped ahead of the verb (`pointer.marquee` = right+drag,
// `pointer.toggleSelect` = ctrl+left, in `pointerBindingDefaults`), so the
// selection case below drives the REAL chords the settings file names and reads
// the tile's own `selection` back. The two mass edits need a write door on the
// editor that does not exist; its names are this file's contract:
//
//   editor.stapleEach(Iterable<String> objects, StapleEnd far, {String point = startPoint})
//       N two-ended staples, `ObjectEnd(o, point) <-> far`, ONE transaction
//   editor.stapleAsOne(Iterable<String> objects, StapleEnd far, {String point = startPoint})
//       ONE staple with N+1 ends, every `ObjectEnd(o, point)` and `far`
//
// Both are one undo entry, so `editor.history` grows by exactly one and one
// `undo()` takes the whole edit back. The context menu over a selection wears
// both in words -- "Staple each to…" and "Staple all as one to…" -- plus a
// clear-selection row.

import 'package:chronolog/app.dart';
import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/lens/lens_painter.dart';
import 'package:chronolog/lens/painters/intimate.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/lens/view_tile.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:chronolog/store/document_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../edit/harness.dart';
import '../helpers/projection_scene.dart';
import '../store/harness.dart';

const String tileId = 'view:1';
const String wallTime = 'frame:wall-time';
const Size tileSize = Size(1100, 640);

IntimatePainter livePainter(WidgetTester tester) {
  final paints = tester.widgetList<CustomPaint>(
    find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is BledPainter),
  );
  expect(paints, isNotEmpty, reason: 'the view tile hosts its lens through one bled painter');
  return (paints.first.painter! as BledPainter).lens as IntimatePainter;
}

Offset onScreen(WidgetTester tester, Offset local) =>
    tester.getTopLeft(find.byType(ViewTile)) + local;

Future<({Editor editor, ViewBook views})> layOut(WidgetTester tester) async {
  registerShippedLenses();
  final store = DocumentStore(
    dataRoot: 'memory',
    files: MemoryFiles(),
    scheduler: ManualScheduler(),
    establish: createEmptyWorkspaceDocument,
  );
  await store.load();
  final settings = chronologSettings();
  final editor = Editor(store, settings: settings.tunable);
  final views = ViewBook()..defaultFrames = [wallTime];
  views.of(tileId).lensId = 'intimate';
  final stage = Stage(tunable: settings.tunable, onLens: views.setLens);
  final tile = ViewTile(
    tileId: tileId,
    surface: (
      editor: editor,
      settings: settings,
      views: views,
      stage: stage,
      objectCard: null,
      frameCard: null,
      settingsCard: null,
    ),
  );
  stage.open(TileSpec(id: tileId, type: 'view', klass: 'lens', title: 'View', build: (_) => tile));
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: themeDataFor(shipped['paper']!),
      home: Scaffold(
        body: ChromeScope(
          chrome: Chrome(settings: settings, stage: stage, views: views, editor: editor),
          child: Center(
            child: SizedBox(width: tileSize.width, height: tileSize.height, child: tile),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (editor: editor, views: views);
}

void main() {
  testWidgets('the selection is a set shared by every lens, with marquee and ctrl-click', (
    tester,
  ) async {
    // "A modifier-drag pulls a MARQUEE box ... ctrl-click adds and removes one
    // at a time, and right-click on a selection opens the context menu over the
    // SELECTION with mass edits, plus a clear-selection door." The chords are
    // the ones the settings ship.
    final bed = await layOut(tester);
    final focus = bed.views.focusOf(tileId);
    final law = livePainter(tester).law;
    // Six half-hour events down the focus day: three to ctrl-click, two to box,
    // one left alone.
    final ids = <String>[];
    for (var hour = 0; hour < 6; hour += 1) {
      final start = focus + law.daysOfMinute(Rational.fromInt(90 * hour));
      ids.add(bed.editor.createAt(wallTime, start, start + law.daysOfMinute(Rational.fromInt(30))));
    }
    await tester.pumpAndSettle();
    final controller = viewTileControllers[tileId]!;
    Rect boxOf(String id) => livePainter(tester).hits.firstWhere((hit) => hit.fact.event.id == id).bounds;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    for (final id in ids.take(3)) {
      await tester.tapAt(onScreen(tester, boxOf(id).center));
      await tester.pumpAndSettle();
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(
      controller.selection,
      hasLength(3),
      reason:
          'ISSUES 9.2: `_selected` is a single (identity, objectId, hit); three ctrl-clicks left '
          '${controller.selection.length} selected. The selection is a SET, one class for every lens.',
    );
    // The marquee: a right-drag from above the fourth to below the fifth, in
    // the empty margin beside the blocks.
    final fourth = boxOf(ids[3]), fifth = boxOf(ids[4]);
    final marquee = await tester.startGesture(
      onScreen(tester, Offset(fourth.right + 4, fourth.top - 4)),
      buttons: kSecondaryMouseButton,
    );
    await marquee.moveTo(onScreen(tester, Offset(fifth.left - 4, fifth.bottom + 4)));
    await tester.pump();
    await marquee.up();
    await tester.pumpAndSettle();
    expect(
      controller.selection,
      hasLength(5),
      reason:
          'ISSUES 9.2: a right-drag marquee over two more must ADD them: '
          '${controller.selection.length} selected after it.',
    );
    // Right-click over the set, without travel: the menu over the SELECTION.
    final press = await tester.startGesture(
      onScreen(tester, boxOf(ids.first).center),
      buttons: kSecondaryMouseButton,
    );
    await press.up();
    await tester.pumpAndSettle();
    for (final row in const ['Staple each to', 'Staple all as one to', 'Clear selection']) {
      expect(
        find.textContaining(RegExp(row, caseSensitive: false)),
        findsWidgets,
        reason: 'ISSUES 9.2: the menu over a selection wears "$row" in words',
      );
    }
  });

  test('"staple each to" writes N two-ended staples; "as one" writes one N-ary staple', () async {
    // Don: "'staple EACH of these to that' writes N two-ended staples -- every
    // selected start is that end, graph distance 1 from the target and the
    // selected objects NOT connected to one another -- while 'staple all of
    // these TOGETHER to that' writes ONE N-ary staple, 'n points are one point'
    // ... Every mass edit is ONE transaction and one undo entry."
    final scene = Scene()..calendar('calendar:a');
    final meeting = scene.object(title: 'AI Team meeting', duration: '60');
    scene.place('calendar:a', civil(2026, 9, 3, 14), event: meeting);
    final todos = [for (var index = 0; index < 5; index += 1) scene.object(title: 'Action $index', duration: '0')];
    final bench = await openEditor(scene.document, label: 'multiselect');
    addTearDown(() => closeEditor(bench));
    final editor = bench.editor;
    final meetingEnd = editor.engine.staples.resolveObjectExtent(meeting).endDays;
    expect(meetingEnd, isNotNull);

    final relationsBefore = editor.document.relations.length;
    final historyBefore = editor.history.length;
    editor.stapleEach(todos, ObjectEnd(meeting, point: 'end'));
    expect(
      editor.document.relations.length - relationsBefore,
      equals(todos.length),
      reason: 'EACH is N two-ended staples',
    );
    expect(editor.history.length - historyBefore, equals(1), reason: 'and ONE undo entry');
    for (final todo in todos) {
      expect(
        editor.engine.staples.resolveObjectExtent(todo).startDays,
        equals(meetingEnd),
        reason: 'every selected start is that end',
      );
      final neighbours = editor.engine.connectionsOf(todo).map((edge) => edge.from == todo ? edge.to : edge.from);
      expect(
        neighbours.where(todos.contains),
        isEmpty,
        reason: 'the selected objects are NOT connected to one another (graph distance 1 from the target)',
      );
    }
    expect(editor.undo(), isTrue);
    expect(editor.document.relations.length, equals(relationsBefore), reason: 'one undo takes it all back');

    editor.stapleAsOne(todos, ObjectEnd(meeting, point: 'end'));
    final added = editor.document.relations.values
        .where((relation) => relation.isStaple && relation.ends.length == todos.length + 1)
        .toList();
    expect(
      editor.document.relations.length - relationsBefore,
      equals(1),
      reason: 'AS ONE is one staple',
    );
    expect(added, hasLength(1), reason: 'with N+1 ends: every start and the target');
    expect(editor.history.length - historyBefore, equals(1), reason: 'and ONE undo entry');
    for (final todo in todos) {
      expect(
        editor.engine.staples.resolveObjectExtent(todo).startDays,
        equals(meetingEnd),
        reason: 'n points are one point: every start is the meeting\'s end',
      );
      expect(added.single.ends.whereType<ObjectEnd>().map((end) => end.object), contains(todo));
    }
  });

  test('the marquee and toggle bindings are settings keys that overlap nothing', () {
    final settings = chronologSettings();
    for (final key in const ['pointer.marquee', 'pointer.toggleSelect']) {
      expect(
        settings.text(key),
        isNotEmpty,
        reason:
            'ISSUES 9.2: the marquee binding (right-drag recommended) must be a settings key like '
            'every pointer chord, alongside `pointer.toggleSelect` (ctrl-click).',
      );
      expect(
        settings.contested(key),
        isFalse,
        reason: 'Don: "clear, consistent, and does not overlap other keybindings" -- $key is uncontested',
      );
    }
  });
}
