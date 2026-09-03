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
// The hover: "a label plate (title, when, frame) after `pointer.hoverMillis`,
// one shared affordance for every lens mark (the drag ghost's plate painter
// already draws exactly this shape and melts into it), so a pip anywhere can be
// read without a click." Painters draw their text through the canvas, so a
// widget Text carrying the fact's title can only be the plate.
//
// Generative: a random day and a random count.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/app.dart';
import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/lens/lens_painter.dart';
import 'package:chronolog/lens/painters/strategic.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/lens/view_tile.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:chronolog/store/document_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/projection_scene.dart';
import '../store/harness.dart';
import 'painters/grid_scene.dart';

final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

const String frameId = 'calendar:a';
const String wallTime = 'frame:wall-time';
const String tileId = 'view:1';

Map<String, Object?> at(int day, int hour) => civil(2026, 9, day, hour, 0);

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

  testWidgets('hover names any mark', (tester) async {
    // "Hovering any registered hit paints a plate containing the fact's title."
    // The mark here is a Strategic pip -- weight standard, so nothing names it
    // at rest -- and the wait is the settings' own `pointer.hoverMillis`.
    registerShippedLenses();
    final store = DocumentStore(
      dataRoot: 'memory',
      files: MemoryFiles(),
      scheduler: ManualScheduler(),
      establish: createEmptyWorkspaceDocument,
    );
    await tester.runAsync(store.load);
    final settings = chronologSettings();
    expect(
      settings.expressionOf('pointer.hoverMillis'),
      isNotEmpty,
      reason: 'ISSUES 9.2: how long a hover waits before naming is a settings key',
    );
    final editor = Editor(store, settings: settings.tunable);
    final views = ViewBook()..defaultFrames = [wallTime];
    views.of(tileId).lensId = 'strategic';
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
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: themeDataFor(shipped['paper']!),
        home: Scaffold(
          body: ChromeScope(
            chrome: Chrome(settings: settings, stage: stage, views: views, editor: editor),
            child: Center(child: SizedBox(width: 1400, height: 800, child: tile)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final focus = views.focusOf(tileId);
    final title = 'Pip ${random.nextInt(1 << 20)}';
    final id = editor.createAt(wallTime, focus, focus + Rational.fromInt(1, 24));
    editor.transaction(
      'Name it',
      (d) => d.put('events', id, d.events[id]!.copyWith(payload: {...?d.events[id]!.payload, 'title': title})),
    );
    await tester.pumpAndSettle();
    final paints = tester.widgetList<CustomPaint>(
      find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is BledPainter),
    );
    final painter = (paints.first.painter! as BledPainter).lens;
    final hit = painter.hits.firstWhere((hit) => hit.fact.event.id == id);
    expect(find.text(title), findsNothing, reason: 'at rest a pip has no name: nothing to read');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getTopLeft(find.byType(ViewTile)) + hit.bounds.center);
    await tester.pump();
    await tester.pump(Duration(milliseconds: settings.value('pointer.hoverMillis').round().toInt() + 50));
    expect(
      find.textContaining(title),
      findsWidgets,
      reason:
          'ISSUES 9.2: "hover to view the event" -- the view tile\'s hover sets the cursor and '
          'nothing else. After `pointer.hoverMillis` a plate names the mark under the pointer.',
    );
  });
}
