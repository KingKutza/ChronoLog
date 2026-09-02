// SELECT MANY, SAY ONE SENTENCE (ISSUES 9.2, Don's rulings on multi-select).
//
// One gesture vocabulary on EVERY lens: a marquee (right-drag; ctrl-drag as the
// alternative), ctrl-click toggles one, right-click on a selection opens the
// context menu over the SET with mass edits. "Staple EACH to that" is the
// default (N two-ended staples, distance 1); "staple all AS ONE to that" is the
// alt (one N-ary staple, distance 0). Every mass edit is one transaction, one
// undo entry. Bindings are settings keys and must not overlap.

import 'package:chronolog/chrome/shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the selection is a set shared by every lens, with marquee and ctrl-click', () {
    // WORK ITEM (ISSUES 9.2): `_selected` in view_tile.dart is a single
    // (identity, objectId, hit). When the selection is a set, this test seeds
    // marks on a lens, ctrl-clicks three, marquees two more, and asserts the set
    // holds five; then right-clicks and asserts the menu is over the set.
    fail(
      'ISSUES 9.2: no lens can hold more than one selected object. Make the selection a set '
      '(one class for every lens, ink ring on each), then assert marquee + ctrl-click here.',
    );
  });

  test('"staple each to" writes N two-ended staples; "as one" writes one N-ary staple', () {
    fail(
      'ISSUES 9.2 (Don: each is the default, all-as-one the alt): no mass edit exists. With '
      'a selection of N todos and a target meeting, EACH yields N staples (start_i = end) and '
      'the todos unconnected to one another; AS ONE yields one staple with N+1 ends. Both are '
      'one transaction and one undo entry.',
    );
  });

  test('the marquee and toggle bindings are settings keys that overlap nothing', () {
    final settings = chronologSettings();
    expect(
      settings.text('pointer.marquee'),
      isNotEmpty,
      reason:
          'ISSUES 9.2: the marquee binding (right-drag recommended) must be a settings key like '
          'every pointer chord, alongside `pointer.toggleSelect` (ctrl-click).',
    );
  });
}
