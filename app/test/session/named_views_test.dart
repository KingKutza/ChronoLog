// A BOARD IS A NAMED SUBTREE, SAVED WHERE LAYOUTS ARE (ISSUES 9.2, Don's rulings).
//
// "I should be able to author boards ... save column layouts and filters, and
// have a few sets I work between." Verified: a view's state lives in the
// session's view file PER VIEW TILE ID -- unnamed, bound to the tile, gone when
// the tile closes. Don's answers: named views live where persistent layouts
// live (the layout file in the data root); presets and boards are one record
// kind -- a named subtree whose leaves are projection tiles (columns) plus the
// lens tunables; a view tile SHOWS a named view.

import 'package:test/test.dart';

void main() {
  test('a named view survives its tile and is shown by another', () {
    // WORK ITEM (ISSUES 9.2, named views): no record kind holds a named view;
    // `ViewBook` keys state by tile id. When the record exists this test saves
    // the focused view's state under a name, closes the tile, opens a fresh
    // view tile, shows the named view in it, and asserts lens, projection
    // expression, columns (in order, each with its own expression) and tunables
    // round-trip byte-for-byte through the layout file.
    fail(
      'ISSUES 9.2: views are unnamed per-tile state in the view file. Add the named-subtree '
      'record beside layout presets in the layout file, then assert the round-trip here.',
    );
  });

  test('layout presets and boards are one record kind', () {
    fail(
      'ISSUES 9.2 (Don: boards live where persistent layouts live): a preset is a named '
      'subtree whose leaves are any tiles; a board is one whose leaves are column tiles. '
      'One record, two uses -- assert a preset can hold a board and a board can be preset.',
    );
  });
}
