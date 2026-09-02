// THREE GROUPINGS ARE ONE FILTER; IMPORTANCE IS WEIGHT (ISSUES 9.2).
//
// Don: "Why is frame not the default, and what do state and importance indicate
// if both are staples to frames?" Under his rulings, state / container / frame
// are one grouping -- the frame at the far end of a staple -- differing only in
// which frames are admitted as columns. Frame is the unfiltered case, so it is
// the default. Importance bands the derived weight and is labelled WEIGHT.

import 'package:chronolog/core/todo_shape.dart';
import 'package:test/test.dart';

void main() {
  test('the board\'s default grouping is the unfiltered one: frame', () {
    expect(
      normalizeGrouping(null),
      equals('frame'),
      reason:
          'ISSUES 9.2: state defaulted. State and container are FILTERS over the frame grouping '
          '(state frames only; containment far ends only); frame is the whole set.',
    );
  });

  test('the weight-band grouping is labelled weight, and state/container are authored filters', () {
    // WORK ITEM (ISSUES 9.2, grouping melt): `lensGroupings` is a closed list of
    // four names read by name in the board and the row. When the melt lands,
    // the grouping is "by frame" with the admitted column set an authored
    // projection expression, and the one non-staple grouping reads as a weight
    // band whose bands are the settings thresholds. This asserts the labels a
    // person sees say "weight", never "importance", and that "state" and
    // "container" are expressible as filters over "frame".
    fail(
      'ISSUES 9.2: `importance` is weight banded against settings thresholds and should say so; '
      'state and container should melt into frame + filter. Land the melt, then assert here.',
    );
  });
}
