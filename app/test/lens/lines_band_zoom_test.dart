// ONE BAND PER SPACE, AND THE WHEEL IS THE ZOOM (ISSUES 9.2, Lines).
//
// Don's rulings: frames sharing a coordinate space merge into ONE banded line
// ("with items on each jumping -- like you show -- in their colour, going out
// top or bottom relative to their position in the stack. Prime in the middle,
// defaults up"); the Window number IS the zoom and the wheel drives it
// continuously -- `_grow` used to round the span to whole days and clamp at 1,
// so at a small window a notch did nothing in either direction.
//
// Then the span ruling that supersedes the shape: A SPAN IS A UNIT AND A
// NUMBER, ZOOM IS MOVING THAT NUMBER, and the number holds FLOATS -- "radial.
// inward at 1 times a wheel notch is 1.1 and stays 1.1." So a notch multiplies
// Lines' `days` by exactly `pointer.zoomStep`, at any window, with the floor a
// settings key in the span's own unit and never the integer one.
//
// THE CONTRACT this file names (keys, not symbols): the band's geometry is
// settings -- `lines.strip` (one strip's thickness) and `lines.jump` (how far a
// mark deflects from its strip) -- and the band is asked of the painter's own
// hit list: every same-space frame's marks lie within one band around the
// field's centre line, the prime's deflect UP, each companion's deflect to ONE
// side, and a frame on another space is its own line outside the band.

import 'dart:math';

import 'package:chronolog/app.dart';
import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/lens/lens_painter.dart';
import 'package:chronolog/lens/painters/lines.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/lens/view_tile.dart';
import 'package:chronolog/session/settings.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:chronolog/store/document_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import '../helpers/projection_scene.dart';
import '../store/harness.dart';
import 'painters/grid_scene.dart';

const String tileId = 'view:1';
const String wallTime = 'frame:wall-time';
const Size surface = Size(1200, 620);

/// A real Lines view tile over an in-memory store, so the zoom is the tile's own.
Future<({ViewBook views, Settings settings})> layOut(WidgetTester tester) async {
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
  views.of(tileId).lensId = 'lines';
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
          child: Center(child: SizedBox(width: surface.width, height: surface.height, child: tile)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (views: views, settings: settings);
}

LensScene sceneOver(Document document, List<String> frames, Settings settings) {
  final engine = ProjectionEngine(document);
  final focus = civilDays(2026, 8, 18);
  return LensScene(
    engine: engine,
    projection: Projection.of(frames),
    law: engine.lawOf(frames.first),
    focusDays: focus,
    view: const {'days': 30},
    theme: shipped['paper']!,
    nowDays: focus,
    size: surface,
    tunable: settings.tunable,
  );
}

void main() {
  testWidgets('a wheel notch changes the Lines span by exactly the step, at any window', (
    tester,
  ) async {
    // "From any window in the settings' range, one wheel notch in each direction
    // changes the span by exactly the step's factor." No rounding: two opposite
    // notches land back where they started, and a notch at a two-day window is
    // a real step.
    final bed = await layOut(tester);
    final controller = viewTileControllers[tileId]!;
    final step = bed.settings.value('pointer.zoomStep');
    expect(step, isNot(equals(Rational.one)), reason: 'a step that is one is no step');
    expect(
      bed.settings.expressionOf('lines.minDays'),
      isNotEmpty,
      reason: 'ISSUES 9.2: the floor is a settings key in the span\'s own unit, never the integer 1',
    );
    final state = bed.views.of(tileId);
    for (final span in [Rational.fromInt(1, 2), Rational.one, Rational.fromInt(2), Rational.fromInt(3), Rational.fromInt(14)]) {
      state.write('days', span);
      controller.zoom(step);
      expect(
        state.number('days', bed.settings),
        equals(span * step),
        reason:
            'ISSUES 9.2: at a $span-day window a notch out gave ${state.number('days', bed.settings)} '
            '-- the span was rounded to a whole number, so the step was eaten.',
      );
      controller.zoom(Rational.one / step);
      expect(
        state.number('days', bed.settings),
        equals(span),
        reason: 'a notch in undoes a notch out exactly: no rounding anywhere in the zoom',
      );
    }
  });

  test('frames on one coordinate space paint as one band of strips', () {
    // "Frames that share a coordinate SPACE MERGE into one banded line: a band of
    // stacked strips, one per frame in the frame's authored colour, the prime's
    // strip in the MIDDLE; an item on a frame is a JUMP drawn in that frame's
    // colour, deflecting UP for strips above the middle and DOWN for strips
    // below, the prime's jumps defaulting UP; ... frames on DIFFERENT spaces
    // stay separate lines."
    final random = Random(specSeed);
    final settings = chronologSettings();
    for (final key in const ['lines.strip', 'lines.jump']) {
      expect(
        settings.expressionOf(key),
        isNotEmpty,
        reason: 'ISSUES 9.2: the band\'s $key is a settings key with a formula value, never a literal',
      );
    }
    final strip = settings.value('lines.strip').toDouble();
    final jump = settings.value('lines.jump').toDouble();
    final count = 2 + random.nextInt(4);
    final world = Scene();
    final calendars = <String>[];
    for (var index = 0; index < count; index += 1) {
      final id = 'calendar:$index';
      world.calendar(id);
      calendars.add(id);
      // Distinct days for every mark on the surface, so no two marks share an x
      // and the fan-out that separates colliding marks never enters the claim.
      for (var mark = 0; mark < 3; mark += 1) {
        world.place(id, civil(2026, 8, 6 + mark * 8 + index, 9), title: '$id/$mark');
      }
    }
    // A frame on ANOTHER space, pinned to the prime by two correspondences so
    // it can be drawn at all: a separate line, never a strip of this band.
    world.frame('frame:other', const ['set', 'calendar'], {'coordinate': inventedLaw});
    for (final (day, at) in const [(8, 2), (28, 30)]) {
      world.staple(
        kind: 'correspondence',
        ends: [
          FrameEnd(calendars.first, position: Position.coordinate(civil(2026, 8, day))),
          FrameEnd('frame:other', position: Position.coordinate(stroke(at))),
        ],
      );
    }
    for (var mark = 0; mark < 3; mark += 1) {
      world.place('frame:other', stroke(10 + mark * 5, 2), title: 'other/$mark');
    }
    final painter = LinesPainter(sceneOver(world.document, [...calendars, 'frame:other'], settings));
    render(painter, surface);
    final centre = surface.height / 2;
    final reach = count * strip + jump;
    final byFrame = <String, List<double>>{};
    for (final hit in painter.hits) {
      final frame = hit.fact.relation.frame ?? '';
      (byFrame[frame] ??= []).add(hit.bounds.center.dy - centre);
    }
    for (final id in calendars) {
      final offsets = byFrame[id] ?? const [];
      expect(offsets, isNotEmpty, reason: '$id has marks on the surface');
      for (final offset in offsets) {
        expect(
          offset.abs(),
          lessThanOrEqualTo(reach),
          reason:
              'ISSUES 9.2: a mark of $id sits $offset px from the centre line -- Lines draws one '
              'line per frame a lane apart. $count frames on one space are ONE band of $count '
              'strips, and every jump stays within it.',
        );
      }
      final sides = {for (final offset in offsets) offset.sign};
      expect(sides, hasLength(1), reason: 'every jump of $id deflects to the side its strip says');
    }
    expect(
      (byFrame[calendars.first] ?? const []).every((offset) => offset < 0),
      isTrue,
      reason: 'the prime\'s jumps default UP',
    );
    for (final offset in byFrame['frame:other'] ?? const []) {
      expect(
        offset.abs(),
        greaterThan(reach),
        reason: 'a frame on another space is its own line, outside the band',
      );
    }
  });
}
