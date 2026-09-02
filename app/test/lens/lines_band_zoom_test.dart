// ONE BAND PER SPACE, AND THE WHEEL IS THE ZOOM (ISSUES 9.2, Lines).
//
// Don's rulings: frames sharing a coordinate space merge into ONE banded line
// (strips in their colours, the prime in the middle, jumps deflecting up above
// it and down below it); the Window number IS the zoom and the wheel drives it
// continuously -- today `_grow` rounds the span to whole days and clamps at 1,
// so at a small window a notch does nothing in either direction.

import 'package:chronolog/session/settings.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('frames on one coordinate space paint as one band of strips', () {
    // WORK ITEM (ISSUES 9.2, banded line): `LinesPainter` lays out one line per
    // admitted frame at `yOf(line.index)`; no band exists. When it does, this
    // test seeds N calendars on Wall Time plus one frame on its own axis and
    // asserts the painter emits exactly one band with N strips (plus one
    // separate line), every fact's jump on its own frame's strip, deflecting to
    // the side its stack position says.
    fail(
      'ISSUES 9.2: Lines draws one line per frame even when they share every coordinate. '
      'Merge same-space frames into one band; then assert strips and deflections here.',
    );
  });

  test('a wheel notch changes the Lines span by exactly the step, at any window', () {
    // The rounding lives in the view tile's `_grow` (private): `Rational(next.round())`
    // clamped at 1. The ruled shape is a continuous span with a settings-fed floor.
    final settings = Settings(defaults: const []);
    final state = ViewState(lensId: 'lines');
    final before = state.number('days', settings);
    // WORK ITEM (ISSUES 9.2): expose the zoom step as a pure function of the view
    // state (span x factor, floored by `lines.minDays`), and assert here that for
    // spans of 1, 2, 3 and 14 days one notch in each direction multiplies by the
    // step exactly -- no integer rounding. Until that seam exists this light
    // stays red by construction.
    fail(
      'ISSUES 9.2: the Window (days) span is rounded to an integer on every zoom step, so '
      'at $before days a notch can be a no-op both ways. Make the span continuous, the floor '
      'a settings key in the span\'s unit, and the wheel a transform during the gesture.',
    );
  });
}
