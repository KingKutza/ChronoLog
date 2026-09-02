// THE PREVIEW AND THE COMMIT ARE ONE ARITHMETIC (ISSUES 9.2, three reports).
//
// "Dragging the start of a multi-day event is inaccurate to the preview";
// "scrolling while dragging across midnight shifts the whole event"; "trying to
// drag lunch up today, the preview is not lining up with where it lands". The
// ghost is the block SHIFTED by the pointer's travel; the commit sets the START
// to the pointer's absolute instant. And no lens has edge grabs: every grab is a
// whole-body move. The rules:
//
//   A move by travel T moves the start by exactly T from any grab point in any
//   segment; a scroll of S during the drag changes the result by 0. A grab band
//   at each end re-says that one point (the ghost grows, not slides).

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a whole-body move by travel T moves the start by exactly T, from any grab point', () {
    // WORK ITEM (ISSUES 9.2): the view tile commits `moveFact(fact, _daysAt(pointerUp))`
    // while the ghost shifts by (head - anchor). When the commit is start +
    // (upDays - downDays), this test grabs seeded facts at seeded offsets within
    // seeded segments, drags by seeded travel, and asserts the new start equals
    // old start plus travel in days -- for one-day and multi-day facts alike.
    fail(
      'ISSUES 9.2: the commit uses the pointer\'s absolute instant, so the grab offset (up to a '
      'whole day on a multi-day event) is added to every move. Commit in delta days.',
    );
  });

  test('a scroll during a drag changes the result by zero', () {
    fail(
      'ISSUES 9.2: the wheel is not gated during a drag and the release reads the pointer on '
      'the NEW painter, so the scroll distance is added to the move. With delta-day commits a '
      'mid-drag scroll is honoured, not added -- assert it.',
    );
  });

  test('an edge grab re-says one point: the end across midnight changes only the end', () {
    fail(
      'ISSUES 9.2: every hit carries `grab: null` and no resize verb exists. A grab band of '
      '`intimate.grab` px at each end re-says that point (the ghost grows); assert the start is '
      'unchanged after an end-edge drag across a midnight boundary.',
    );
  });
}
