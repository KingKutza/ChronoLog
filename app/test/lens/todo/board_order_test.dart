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
//
// THE CONTRACT this file names (data shapes, not new symbols):
//
//   * `view['columns']` is a list of strings. A string that is a frame id is
//     that frame's one-frame term; any other string is a PROJECTION SOURCE in
//     the one math, frame titles bound as `ViewState.bindingsFor` binds them
//     (`AI_Team and not Done`), and the column's header reads that source. An
//     entry sits in a column when that column's expression admits it.
//   * A header is a `Draggable<String>` carrying its column's entry (a distinct
//     payload from a card's object id) and dropping on another column permutes
//     the list; a single click on a header drops the frame list, whose rows
//     switch the column and whose typed entry offers "New column <name>".
//   * Two entries joined by an object-to-object staple sit ADJACENT in a column
//     as a chain ranked by its heaviest member, and each wears a staple sigil
//     whose hover text names the far object.
//
// The header's DOUBLE-click (open the frame's card in another tile) is ruled but
// not asserted here: `TodoScene` has no frame-open seam yet, and pinning one
// would be naming the door rather than the behaviour. It rides with the surface
// graph test, which already demands a door to every card.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/core/object_kinds.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/lens/theme.dart';
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

Map<String, Object?> at(int day, int hour) => civil(2026, 8, day, hour, 0);

final List<Bench> _open = [];

Future<Bench> bench(Scene scene) async {
  final opened = await openEditor(scene.document, label: 'board-order');
  _open.add(opened);
  return opened;
}

String group(Scene scene, String id, String title) {
  scene.frame(id, const ['set', 'group']);
  scene.document = scene.document.put(
    'frames',
    id,
    scene.document.frames[id]!.copyWith(title: title),
  );
  return id;
}

/// A placed todo, in every group named.
String todoIn(Scene scene, String title, List<String> groups, {int hour = 9}) {
  final id = scene.object(title: title, duration: '0');
  scene.document = scene.document.put(
    'events',
    id,
    scene.document.events[id]!.copyWith(traits: objectKinds['todo']!.traits),
  );
  scene.place(calendar, at(18, hour), event: id);
  for (final frame in groups) {
    scene.staple(ends: [ObjectEnd(id), StapleEnd.frame(frame)]);
  }
  return id;
}

/// The HEADER carrying [title]: the topmost text saying it. A row's meta chips
/// repeat a frame's title, so the words alone name more than one widget.
Finder headerOf(WidgetTester tester, String title) {
  final all = find.text(title).evaluate().toList();
  expect(all, isNotEmpty, reason: 'a column is headed $title');
  all.sort((a, b) => tester.getTopLeft(find.byElementPredicate((e) => e == a)).dy.compareTo(
        tester.getTopLeft(find.byElementPredicate((e) => e == b)).dy,
      ));
  final top = all.first;
  return find.byElementPredicate((element) => element == top);
}

/// The one text saying [title] that sits under the column headed [column].
Finder inColumn(WidgetTester tester, String column, String title) {
  final head = tester.getTopLeft(headerOf(tester, column));
  final width = allTunables('todo.columnWidth').toDouble();
  final within = find.text(title).evaluate().where((element) {
    final dx = tester.getTopLeft(find.byElementPredicate((e) => e == element)).dx;
    return dx >= head.dx && dx < head.dx + width;
  }).toList();
  expect(within, hasLength(1), reason: '$title sits once under $column');
  return find.byElementPredicate((element) => element == within.single);
}

Future<void> pumpBoard(WidgetTester tester, Widget board) async {
  tester.view.physicalSize = const Size(2400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: themeDataFor(shipped['paper']!),
      home: Scaffold(body: board),
    ),
  );
  await tester.pump();
}

void main() {
  // ignore: avoid_print
  print('BOARD ORDER RUN SEED: $runSeed  (set CHRONOLOG_SEED=$runSeed to reproduce)');
  final random = Random(runSeed);

  tearDownAll(() async {
    for (final opened in _open) {
      await closeEditor(opened);
    }
  });

  testWidgets('columns stand in the authored order, whatever they hold', (tester) async {
    final scene = Scene()..calendar(calendar);
    final titles = ['Alpha', 'Beta', 'Gamma']..shuffle(random);
    final groups = <String>[];
    for (final title in titles) {
      final id = group(scene, 'group:${title.toLowerCase()}', title);
      groups.add(id);
      todoIn(scene, 'Todo for $title', [id]);
    }
    // The authored order is the REVERSE of alphabetical, so a sort would betray it.
    final authored = [...groups]..sort((a, b) => b.compareTo(a));
    final opened = (await tester.runAsync(() => bench(scene)))!;
    final board = todoSceneOf(
      opened.editor,
      const [calendar],
      lens: 'board',
      view: {'grouping': 'frame', 'columns': authored},
    );
    await pumpBoard(tester, BoardLens(board));
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

  testWidgets('a header drag writes the authored order; a header click switches the column', (
    tester,
  ) async {
    // "Drag a column header to reorder; the order IS the authored list -- a drop
    // permutes `view['columns']`. Header drag and card drag are different
    // payloads on the same target." And: "SINGLE click drops the list of other
    // frames the column can be switched to."
    final scene = Scene()..calendar(calendar);
    final ids = [
      for (final title in const ['Alpha', 'Beta', 'Gamma'])
        group(scene, 'group:${title.toLowerCase()}', title),
    ];
    final spare = group(scene, 'group:delta', 'Delta');
    for (final id in ids) {
      todoIn(scene, 'Todo for $id', [id]);
    }
    final written = <String, Object?>{};
    final opened = (await tester.runAsync(() => bench(scene)))!;
    await pumpBoard(
      tester,
      BoardLens(
        todoSceneOf(
          opened.editor,
          const [calendar],
          lens: 'board',
          view: {'grouping': 'frame', 'columns': ids},
          onView: (key, value) => written[key] = value,
        ),
      ),
    );
    final column = allTunables('todo.columnWidth').toDouble();
    // Drag the LAST header onto the first column.
    await tester.drag(headerOf(tester, 'Gamma'), Offset(-2 * column, 0));
    await tester.pumpAndSettle();
    final reordered = written['columns'];
    expect(
      reordered,
      isA<List<Object?>>(),
      reason: 'ISSUES 9.2: column headers are inert text with a count; a header drag writes nothing.',
    );
    final order = [for (final id in reordered! as List<Object?>) '$id'];
    expect(order.toSet(), equals(ids.toSet()), reason: 'a drag permutes, it never adds or drops');
    expect(order.first, equals(ids.last), reason: 'the dragged column now leads');
    written.clear();
    // A single click on a header drops the list of other frames; choosing one
    // SWITCHES the column in place.
    await tester.tap(headerOf(tester, 'Alpha'));
    await tester.pumpAndSettle();
    expect(
      find.text('Delta'),
      findsWidgets,
      reason: 'ISSUES 9.2: the header\'s single click drops the frames it can be switched to',
    );
    await tester.tap(find.text('Delta').last);
    await tester.pumpAndSettle();
    final switched = [for (final id in (written['columns'] as List<Object?>? ?? const []) as List) '$id'];
    expect(switched, contains(spare), reason: 'the column now stands for Delta');
    expect(switched, isNot(contains(ids.first)), reason: 'and no longer for Alpha');
    expect(switched.length, equals(ids.length), reason: 'a switch is a switch, not an add');
  });

  testWidgets('a typed name matching no frame offers to create it as a new column', (tester) async {
    // "A name nothing wears is an offer to MAKE it. The chooser gains a typed
    // entry; a typed name matching no frame offers 'New column <name>' which
    // mints the frame through the one new-frame path (traits by grouping),
    // stands it as a column, and appends it to the authored order."
    final scene = Scene()..calendar(calendar);
    final existing = group(scene, 'group:alpha', 'Alpha');
    todoIn(scene, 'Todo for Alpha', [existing]);
    final name = 'Zed ${random.nextInt(1000)}';
    final written = <String, Object?>{};
    final opened = (await tester.runAsync(() => bench(scene)))!;
    await pumpBoard(
      tester,
      BoardLens(
        todoSceneOf(
          opened.editor,
          const [calendar],
          lens: 'board',
          view: {'grouping': 'frame', 'columns': [existing]},
          onView: (key, value) => written[key] = value,
        ),
      ),
    );
    await tester.tap(find.text('Stand a column…'));
    await tester.pumpAndSettle();
    final entry = find.byType(TextField);
    expect(
      entry,
      findsWidgets,
      reason: 'ISSUES 9.2: "Stand a column…" lists existing frames only and has no typed entry',
    );
    await tester.enterText(entry.first, name);
    await tester.pumpAndSettle();
    final offer = find.textContaining(RegExp('New column', caseSensitive: false));
    expect(offer, findsWidgets, reason: 'a name nothing wears is an offer to make it');
    await tester.tap(offer.first);
    await tester.pumpAndSettle();
    final minted = opened.editor.document.frames.values
        .where((frame) => frame.title == name)
        .toList();
    expect(minted, hasLength(1), reason: 'one frame named $name was minted');
    expect(minted.single.traits, contains('group'), reason: 'a group frame, under frame grouping');
    final columns = [for (final id in (written['columns'] as List<Object?>? ?? const []) as List) '$id'];
    expect(columns.last, equals(minted.single.id), reason: 'it joins the authored order at the end');
    expect(columns.first, equals(existing), reason: 'the standing column holds its place');
  });

  testWidgets('a column is a projection: AI Team NOT Done is one column, AI Team AND Done another', (
    tester,
  ) async {
    // "A COLUMN IS A PROJECTION -- by default the one-frame term `A`, authorable
    // to `A and not Done`, and an entry sits in a column when that column's
    // expression admits it; the view's projection is the OR of its columns." A
    // done item admitted through one column must not leak into the other.
    final scene = Scene()..calendar(calendar);
    final team = group(scene, 'group:ai', 'AI Team');
    scene.frame(doneStateFrameId, stateFrameTraits);
    scene.document = scene.document.put(
      'frames',
      doneStateFrameId,
      scene.document.frames[doneStateFrameId]!.copyWith(title: doneStateTitle),
    );
    final open = todoIn(scene, 'Still open', [team]);
    final done = todoIn(scene, 'Already done', [team, doneStateFrameId], hour: 10);
    const notDone = 'AI_Team and not Done', andDone = 'AI_Team and Done';
    final opened = (await tester.runAsync(() => bench(scene)))!;
    await pumpBoard(
      tester,
      BoardLens(
        todoSceneOf(
          opened.editor,
          const [calendar],
          lens: 'board',
          view: const {
            'grouping': 'frame',
            'columns': [notDone, andDone],
          },
        ),
      ),
    );
    final first = find.text(notDone), second = find.text(andDone);
    expect(
      first,
      findsOneWidget,
      reason: 'ISSUES 9.2: a column carries its own expression, and its header reads it',
    );
    expect(second, findsOneWidget);
    final divide = tester.getTopLeft(second).dx;
    String openTitle = scene.document.events[open]!.payload!['title'] as String;
    String doneTitle = scene.document.events[done]!.payload!['title'] as String;
    expect(find.text(openTitle), findsOneWidget, reason: 'the open todo sits in exactly one column');
    expect(
      tester.getTopLeft(find.text(openTitle)).dx,
      lessThan(divide),
      reason: 'and it is the NOT Done column',
    );
    expect(
      find.text(doneTitle),
      findsOneWidget,
      reason:
          'ISSUES 9.2: an entry filed under every frame it touches, so a per-column NOT leaked. '
          'The done todo is in ONE column.',
    );
    expect(
      tester.getTopLeft(find.text(doneTitle)).dx,
      greaterThanOrEqualTo(divide),
      reason: 'and it is the AND Done column',
    );
  });

  testWidgets('two stapled todos show their connection: sigil, adjacency in a column', (
    tester,
  ) async {
    // "The row wears a staple sigil per object-staple, hover reads the sentence;
    // two stapled entries in the SAME column sit ADJACENT as a chain -- the chain
    // ranks by its heaviest member and its members keep their order inside it, so
    // weight still orders the column but never separates what a sentence joined."
    final scene = Scene()..calendar(calendar);
    final team = group(scene, 'group:ai', 'AI Team');
    final parent = todoIn(scene, 'Ask Reggie', [team]);
    final child = todoIn(scene, 'Chase Reggie', [team], hour: 11);
    final between = todoIn(scene, 'Buy milk', [team], hour: 10);
    // Weights that would put the stranger BETWEEN the pair: parent heaviest,
    // stranger next, child lightest. The child reaches the parent's rings
    // through the staple, so its own term has to say it is lighter.
    scene.group('group:heavy', [parent], weight: 'w * 9');
    scene.group('group:medium', [between], weight: 'w * 6');
    scene.document = scene.document.put(
      'events',
      child,
      scene.document.events[child]!.withField('display', const {'weight': '0.5'}),
    );
    scene.staple(
      kind: 'anchor',
      ends: [ObjectEnd(child, point: 'start'), ObjectEnd(parent, point: 'end')],
    );
    final opened = (await tester.runAsync(() => bench(scene)))!;
    await pumpBoard(
      tester,
      BoardLens(
        todoSceneOf(
          opened.editor,
          const [calendar],
          lens: 'board',
          view: {'grouping': 'frame', 'columns': [team]},
        ),
      ),
    );
    String titleOf(String id) => scene.document.events[id]!.payload!['title'] as String;
    // Under frame grouping every stapled frame columns, so the rows repeat
    // across the surface; the chain claim is about ONE column.
    final yParent = tester.getTopLeft(inColumn(tester, 'AI Team', titleOf(parent))).dy;
    final yChild = tester.getTopLeft(inColumn(tester, 'AI Team', titleOf(child))).dy;
    final yBetween = tester.getTopLeft(inColumn(tester, 'AI Team', titleOf(between))).dy;
    expect(yParent, lessThan(yChild), reason: 'the chain ranks by its heaviest member, the parent');
    expect(
      yChild,
      lessThan(yBetween),
      reason:
          'ISSUES 9.2: weight put a stranger between two todos a sentence joined. A chain is '
          'adjacent; weight orders the column and never separates it.',
    );
    final sigil = find.byWidgetPredicate(
      (widget) => widget is Tooltip && (widget.message ?? '').contains(titleOf(parent)),
    );
    expect(
      sigil,
      findsWidgets,
      reason:
          'ISSUES 9.2: "I would expect a sigil, a line, an adjacency, something." The child '
          'wears a staple sigil whose hover reads the sentence naming the parent.',
    );
  });
}
