// THE FLOOR COARSENS THE SURFACE; IT DOES NOT DROP DAYS (ISSUES 9.2, Don).
//
// `intimate.minColumnPixels` was "the narrowest a day may become before the lens
// shows fewer of them". The rule ladder exists for exactly the case it was
// guarding against -- Don, 8.28/8.31: "the surface coarsens as it shrinks and
// SUBDIVIDES as it grows", two-tier at every rung -- so a narrow column is a
// solved problem, and the setting becomes the width at which a COLUMN steps a
// rung, not the width at which a day vanishes. Thirty days on Intimate is
// thirty narrow columns ruled at a coarser rung, which is a picture, where
// seven-of-thirty is a lie.
//
// The rules:
//
//   A column has a rung of its own -- `columnRung` -- a function of its width
//   the way the rail's rung is a function of an hour's height, from the same
//   ladder (`lens/ladder.dart`) and no other.
//   As the column narrows the rung only ever coarsens; it never flattens to one
//   tier and the count of days never moves.
//   The width at which it steps is `intimate.minColumnPixels`, a setting; there
//   is no literal in the lens.
//
// Nothing here says WHAT a coarser column rung changes about the drawing -- the
// labels, the marks, the lanes -- only that the rung exists, comes from the
// ladder, and moves the right way.

import 'dart:math';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/lens/lens_painter.dart';
import 'package:chronolog/lens/painters/intimate.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import '../helpers/projection_scene.dart';
import 'painters/grid_scene.dart';

const String frameId = 'calendar:a';

LensScene scene(Scene world, int span, double width, {Map<String, Rational> settings = const {}}) {
  final engine = ProjectionEngine(world.document);
  return LensScene(
    engine: engine,
    projection: Projection.of(const [frameId]),
    law: engine.lawOf(frameId),
    focusDays: civilDays(2026, 8, 18),
    view: {'span': '$span'},
    theme: shipped['paper']!,
    nowDays: civilDays(2026, 8, 18),
    size: Size(width, 720),
    tunable: (key) => settings[key] ?? allTunables(key),
  );
}

void main() {
  test('as a column narrows its rung coarsens, never flattens, and the day count holds', () {
    final random = Random(specSeed);
    for (var iteration = 0; iteration < 12; iteration += 1) {
      final span = 2 + random.nextInt(40);
      final world = Scene()..calendar(frameId);
      Rational? lastMinor;
      // Widths descending: the same span squeezed into less and less room.
      for (var width = 3000.0; width >= 240; width -= 120 + random.nextInt(200)) {
        final painter = IntimatePainter(scene(world, span, width));
        render(painter, painter.scene.size);
        final rung = painter.columnRung;
        expect(rung.minor > Rational.zero, isTrue, reason: 'a rung has a minor at every width');
        expect(
          rung.major > rung.minor,
          isTrue,
          reason: 'at ${width.toStringAsFixed(0)} px the column rung went flat -- one tier is forbidden',
        );
        if (lastMinor != null) {
          expect(
            rung.minor >= lastMinor,
            isTrue,
            reason:
                'ISSUES 9.2: narrowing from a wider column made the rung FINER ($lastMinor -> '
                '${rung.minor}). "The surface coarsens as it shrinks."',
          );
        }
        lastMinor = rung.minor;
        final day = painter.law.dayOf(painter.scene.focusDays);
        final start = Rational(day) * painter.law.dayDays;
        final measured =
            painter.project(start + painter.law.dayDays)!.dx - painter.project(start)!.dx;
        expect(
          measured,
          closeTo((width - painter.scene.px('intimate.rail')) / span, 1e-6),
          reason: 'ISSUES 9.2: the count is not what a narrow column changes',
        );
      }
    }
  });

  test('the width at which a column steps a rung is the setting, not a number in the lens', () {
    // Two settings for the floor, one wide and one narrow. At a column width
    // between them the wide setting has already stepped the rung and the narrow
    // one has not -- which can only be true if the setting is what is read.
    final world = Scene()..calendar(frameId);
    const span = 6;
    const width = 1500.0;
    final generous = IntimatePainter(
      scene(world, span, width, settings: {'intimate.minColumnPixels': Rational.fromInt(4000)}),
    );
    final sparing = IntimatePainter(
      scene(world, span, width, settings: {'intimate.minColumnPixels': Rational.fromInt(1)}),
    );
    render(generous, generous.scene.size);
    render(sparing, sparing.scene.size);
    expect(
      generous.columnRung.minor >= sparing.columnRung.minor,
      isTrue,
      reason: 'a wider floor is a coarser column at the same width',
    );
    expect(
      generous.columnRung,
      isNot(equals(sparing.columnRung)),
      reason:
          'ISSUES 9.2: `intimate.minColumnPixels` moved from 1 to 4000 and the column rung did '
          'not move -- the floor is being read from somewhere other than the setting.',
    );
  });
}
