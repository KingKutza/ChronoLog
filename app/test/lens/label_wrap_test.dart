// A TALL BLOCK WRAPS ITS TITLE (ISSUES 9.2, Don).
//
// "Where an event has a lot of vertical space it should wrap text rather than
// cut it off." The one shared label painter lays out `maxLines: 1` with an
// ellipsis unconditionally, and Intimate hands it a one-line box whatever the
// block's height. The rule:
//
//   The caller passes the real box; the painter lays out as many lines as fit
//   with the ellipsis on the last line only. And the shared painter lives with
//   the other shared marks, not in one painter's file.

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the painted line count is min(lines that fit, lines the text needs)', () {
    // WORK ITEM (ISSUES 9.2): `paintLabel` (in painters/month_grid.dart, used by
    // five painters) is `maxLines: 1`. When it lays out to the box, this test
    // paints seeded titles into seeded box heights through a recording canvas
    // and asserts the line count, and that no glyph lands outside the block.
    fail(
      'ISSUES 9.2: every lens label is one line and an ellipsis. Lay out to the box height in '
      'the shared painter (moved to lens_painter.dart) and record painted lines to assert here.',
    );
  });
}
