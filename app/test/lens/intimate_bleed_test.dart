// NO PAPER SLIDES IN, AND THE HAND NEVER WAITS ON A QUERY (ISSUES 9.2, Intimate).
//
// "Drag is a bit more choppy than before, and a new column does not render till
// there is room for a whole column, so we still drag white onto the screen."
// The gutter is painted over the left bleed column; the pan commits (re-plan,
// re-query, repaint, synchronously) every column and every 160 px. The rules:
//
//   The rail is chrome and does not slide. The bleed is sized to the viewport.
//   A commit never runs in the pointer path.
//
// The paper is asked of the painter through a recording canvas: the column laid
// out at index -1 sits under the rail, and nothing the columns pass through may
// lay paper over it. The commit is asked of the tile: while the pointer moves
// the focus does not -- a commit inside the handler is exactly the hitch Don
// felt, and the frame budget it must stay under is a settings key.

import 'package:chronolog/app.dart';
import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/lens/painters/intimate.dart';
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

const String frameId = 'calendar:a';
const String tileId = 'view:1';
const String wallTime = 'frame:wall-time';

/// Every FILLED area the painter laid down, with its colour.
class Fills implements Canvas {
  final List<({Rect rect, Color color})> laid = [];
  final List<Offset> _stack = [Offset.zero];

  Offset get _shift => _stack.last;

  void _fill(Rect rect, Paint paint) {
    if (paint.style == PaintingStyle.fill && paint.color.a > 0) {
      laid.add((rect: rect.shift(_shift), color: paint.color));
    }
  }

  @override
  void save() => _stack.add(_shift);

  @override
  void restore() {
    if (_stack.length > 1) _stack.removeLast();
  }

  @override
  void translate(double dx, double dy) => _stack[_stack.length - 1] = _shift + Offset(dx, dy);

  @override
  void drawRect(Rect rect, Paint paint) => _fill(rect, paint);

  @override
  void drawRRect(RRect rrect, Paint paint) => _fill(rrect.outerRect, paint);

  @override
  void drawPath(Path path, Paint paint) => _fill(path.getBounds(), paint);

  @override
  void noSuchMethod(Invocation invocation) {}
}

void main() {
  test('the painted bleed spans at least a viewport each way', () {
    final scene = Scene()..calendar(frameId);
    const size = Size(1200, 800);
    final painter = IntimatePainter(sceneOf(scene.document, const [frameId], size: size));
    render(painter, size);
    expect(
      painter.bleed.dx,
      greaterThanOrEqualTo(size.width),
      reason:
          'ISSUES 9.2: one column of horizontal bleed means a commit every column of travel. '
          'Default the bleed to a viewport of columns (a settings formula), so an ordinary drag '
          'never leaves the painted buffer.',
    );
    expect(
      painter.bleed.dy,
      greaterThanOrEqualTo(size.height),
      reason: 'ISSUES 9.2: 160 px of vertical bleed is a hitch every 160 px; a viewport is the default',
    );
  });

  test('dragging toward the past slides in a day, never paper', () {
    // "The bleed column at index -1 is laid out UNDER the time rail, and
    // `_paintGutter` then fills paper over it -- so dragging toward the past
    // slides in paper. The RAIL IS CHROME AND DOES NOT SLIDE: paint the rail and
    // gutter in their own untranslated layer above the translated columns."
    // Whatever layer the rail takes, nothing the column pass paints may lay
    // paper over the past-side bleed column.
    final scene = Scene()..calendar(frameId);
    const size = Size(1200, 800);
    final painter = IntimatePainter(sceneOf(scene.document, const [frameId], size: size));
    render(painter, size);
    final focus = painter.scene.focusDays;
    final rail = painter.scene.px('intimate.rail');
    final column = painter.project(focus + painter.law.dayDays)!.dx - painter.project(focus)!.dx;
    final pastColumn = Rect.fromLTWH(rail - column, 0, column, size.height);
    final canvas = Fills();
    painter.paint(canvas, size);
    final paper = painter.scene.theme.paper;
    final covering = [
      for (final fill in canvas.laid)
        if (fill.color == paper)
          if (fill.rect.intersect(pastColumn).width > 1 && fill.rect.intersect(pastColumn).height > 1) fill.rect,
    ];
    expect(
      covering,
      isEmpty,
      reason:
          'ISSUES 9.2: paper was laid over the past-side bleed column at $pastColumn by $covering. '
          '"We still drag white onto the screen" -- a column entering from the left must emerge '
          'from under the rail, not from under a gutter fill.',
    );
  });

  testWidgets('a commit never runs in the pointer handler', (tester) async {
    // "COMMIT OFF THE POINTER PATH -- when travel does exhaust the buffer, keep
    // translating the OLD raster and build the new painter in the next frame ...
    // so the hand never waits on a query; the release commits exactly as now."
    // So no pointer move, by itself, moves the focus; and the motion budget the
    // frames must stay under is a settings key.
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
      settings.expressionOf('perf.frameMillis'),
      isNotEmpty,
      reason: 'ISSUES 9.2: the motion budget is a settings key, `perf.frameMillis`, never a literal',
    );
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
    const tileSize = Size(1100, 640);
    await tester.pumpWidget(
      MaterialApp(
        theme: themeDataFor(shipped['paper']!),
        home: Scaffold(
          body: ChromeScope(
            chrome: Chrome(settings: settings, stage: stage, views: views, editor: editor),
            child: Center(child: SizedBox(width: tileSize.width, height: tileSize.height, child: tile)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final start = views.focusOf(tileId);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ViewTile)),
      buttons: kMiddleMouseButton,
    );
    // Two viewports of travel in twelve moves, the way a hand delivers them.
    for (var step = 0; step < 12; step += 1) {
      await gesture.moveBy(Offset(-tileSize.width / 6, 0));
      expect(
        views.focusOf(tileId),
        equals(start),
        reason:
            'ISSUES 9.2: pointer move $step committed the focus inside the handler -- `_panMove` '
            'calls `pan(days)` synchronously when travel passes the bleed. A commit never runs in '
            'the pointer path; the raster translates and the rebuild waits for the next frame.',
      );
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(views.focusOf(tileId), isNot(equals(start)), reason: 'the release commits the whole travel');
  });
}
