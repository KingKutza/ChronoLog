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
//
// And Don's ruling on what a zone IS (the Code Freeze covering Labor Day): FILL
// IS GROUND, A MARK IS FIGURE. A ground paints beneath everything as one ordered
// pass every surface shares; A GROUND SPANS BY NATURE -- it was confined to a
// chip box only because it was treated as a mark -- and A GROUND DOES NOT LANE,
// so nothing here puts a zone through the lane packer.
//
// THE CONTRACT this file names, which does not exist yet: beside `hits`, a
// painter records the zones it drew DURING paint --
//
//   LensPainter.zones : List<({Fact fact, Rect bounds})>
//
// one entry per painted zone segment, built in the same pass as the pixels so
// the list and the picture are one derivation (the same reason `hits` is built
// during paint). The shared pass fills it; a lens that paints its zone its own
// way (Intimate's band) still records through the one list.

import 'dart:math';

import 'package:chronolog/app.dart';
import 'package:chronolog/lens/view_tile.dart';
import 'package:chronolog/session/lens_catalog.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import '../helpers/projection_scene.dart';
import 'painters/grid_scene.dart';

const String frameId = 'calendar:a';

void main() {
  test('a zoned todo shows on every timed lens in the catalog', () {
    registerShippedLenses();
    final random = Random(specSeed);
    final timed = [
      for (final spec in lensCatalog.values)
        if (spec.isTimeSurface) spec.id,
    ];
    expect(timed, isNotEmpty);
    final spanDays = 2 + random.nextInt(3);
    final scene = Scene()..calendar(frameId);
    // Zone-ness is a GROUP property (ruled 2026-08-27): the group says zone, and
    // every member draws as one on every lens at once.
    scene.group('group:ooo', const [], extra: const {'display': {'zone': true}});
    final zoned = scene.object(title: 'Out of office', duration: '${spanDays * 24 * 60}');
    scene.join('group:ooo', zoned);
    scene.place(frameId, civil(2026, 8, 17, 8), event: zoned);
    // Two FIGURES, one on the ground's first day and one on its last.
    final first = scene.object(title: 'First day', duration: '60');
    scene.place(frameId, civil(2026, 8, 17, 10), event: first);
    final last = scene.object(title: 'Last day', duration: '60');
    scene.place(frameId, civil(2026, 8, 17 + spanDays - 1, 10), event: last);
    const size = Size(1400, 900);
    var painted = 0;
    for (final id in timed) {
      final build = lensPainters[id];
      if (build == null) continue;
      painted += 1;
      final painter = build(sceneOf(scene.document, const [frameId], size: size));
      render(painter, size);
      final recorded = painter.zones.where((zone) => zone.fact.event.id == zoned).toList();
      expect(
        recorded,
        isNotEmpty,
        reason:
            'ISSUES 9.2: $id painted no zone for a zone-handled object spanning $spanDays days. '
            'One zone pass is shared by every timed lens; a lens supplies only its projection.',
      );
      for (final zone in recorded) {
        expect(zone.bounds.isEmpty, isFalse, reason: 'a recorded zone has an area on $id');
      }
      // A GROUND SPANS BY NATURE: the figures on the span's first and last days
      // both sit inside what the ground covers, on every lens that draws them.
      final ground = recorded.map((zone) => zone.bounds).reduce((a, b) => a.expandToInclude(b));
      for (final figure in [first, last]) {
        final mark = painter.hits.where((hit) => hit.fact.event.id == figure).firstOrNull;
        if (mark == null) continue;
        expect(
          ground.inflate(1).contains(mark.bounds.center),
          isTrue,
          reason:
              'Don: "a zone does not span the cells it covers" -- on $id the ground stops short of '
              'the figure on its ${figure == first ? 'first' : 'last'} day. A ground spans; a chip '
              'box was a mark\'s shape.',
        );
      }
    }
    expect(painted, greaterThan(1), reason: 'the catalog registers more than one timed painter');
  });
}
