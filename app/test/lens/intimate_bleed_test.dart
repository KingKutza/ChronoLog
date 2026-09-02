// NO PAPER SLIDES IN, AND THE HAND NEVER WAITS ON A QUERY (ISSUES 9.2, Intimate).
//
// "Drag is a bit more choppy than before, and a new column does not render till
// there is room for a whole column, so we still drag white onto the screen."
// The gutter is painted over the left bleed column; the pan commits (re-plan,
// re-query, repaint, synchronously) every column and every 160 px. The rules:
//
//   The rail is chrome and does not slide. The bleed is sized to the viewport.
//   A commit never runs in the pointer path.

import 'package:chronolog/lens/painters/intimate.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/projection_scene.dart';
import 'painters/grid_scene.dart';

const String frameId = 'calendar:a';

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
    // WORK ITEM (ISSUES 9.2): `_paintGutter` fills paper from -bleed.dx to the rail,
    // covering the left bleed column laid out under the rail. When the rail is
    // its own untranslated layer, this test renders to an image, translates one
    // column toward the past, and asserts no paper pixel appears in the column
    // area to the right of the rail.
    fail(
      'ISSUES 9.2: the gutter paints over the past-side bleed column. Paint the rail and gutter '
      'above the translated columns in their own layer; assert by pixel-sampling here.',
    );
  });

  test('a commit never runs in the pointer handler', () {
    fail(
      'ISSUES 9.2: `_panMove` calls `pan(days)` synchronously when travel passes the bleed. '
      'Keep translating the old raster, build the new painter next frame, swap when painted; '
      'assert frame times over a two-viewport drag stay within `perf.frameMillis`.',
    );
  });
}
