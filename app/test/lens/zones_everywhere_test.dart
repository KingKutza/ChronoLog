// A ZONE IS DRAWN ON EVERY TIMED LENS (ISSUES 9.2, Don).
//
// "Zone is working on Intimate but not on Strategic -- or Tactical or Wall."
// `zoneFill`/`zoneBand` are imported by the Intimate painter alone; the month
// grid's old fill was removed under the 9.1 sigil-and-line ruling and nothing
// replaced it. The rule:
//
//   One zone pass shared by every timed lens, each lens supplying only its
//   point-to-pixel projection. Asserted by iterating the catalog, never a
//   written list of lens names.

import 'package:chronolog/session/lens_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a zoned todo shows its sigil and line on every timed lens in the catalog', () {
    final timed = [
      for (final spec in lensCatalog.values)
        if (spec.isTimeSurface) spec.id,
    ];
    expect(timed, isNotEmpty);
    // WORK ITEM (ISSUES 9.2): no shared zone pass exists; only Intimate paints
    // zones. When the pass exists, this test builds a zoned todo, paints each
    // timed lens from the catalog, and asserts the painter recorded the zone's
    // sigil and line geometry for it.
    fail(
      'ISSUES 9.2: zones are painted by Intimate only. Build one shared zone pass and assert it '
      'over every timed lens in the catalog: ${timed.join(', ')}.',
    );
  });
}
