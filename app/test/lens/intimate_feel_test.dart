// INTIMATE UNDER THE HAND (ISSUES 9.1, Don's morning test): two reports, one
// seam.
//
// "Dragging on intimate, previously smooth, now feels like it is ratcheting
// between positions" and "drags are not showing a preview" — panLanding
// truncates the SHOWN transform to whole columns and the bleed is vertical
// only, so a sideways drag shows nothing until a full column and then commits a
// repaint per column. The ruled contract: what the eye may be shown live is
// bounded by what is PAINTED past the viewport, so the surface owes a
// horizontal bleed and a continuous shown.dx inside it.
//
// "When I click on an event or todo and drag it, the event does not move — it
// drags to create a new event." The block's grab region is a nine-pixel
// unpainted strip; the ruled contract: the common gesture gets the common verb
// — a drag that starts anywhere on a mark moves it, and creating through an
// occupied span is what wears the modifier.

import 'dart:math';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/lens/painters/intimate.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import '../helpers/projection_scene.dart';
import 'painters/grid_scene.dart';

const String frameId = 'calendar:a';

IntimatePainter paintedOver(Scene scene, Rational focus) {
  final lens = sceneOf(scene.document, const [frameId], focus: focus, now: focus);
  final painter = IntimatePainter(lens);
  render(painter, lens.size);
  return painter;
}

void main() {
  for (final seed in seeds(5)) {
    final random = Random(seed);
    final day = 4 + random.nextInt(20);
    final hour = 8 + random.nextInt(8);

    testWidgets('a sideways drag inside the bleed is previewed, not swallowed (seed $seed)', (
      tester,
    ) async {
      final scene = Scene()..calendar(frameId);
      scene.place(frameId, civil(2026, 9, day, hour), title: 'Block');
      final painter = paintedOver(scene, civilDays(2026, 9, day));
      expect(
        painter.bleed.dx,
        greaterThan(0),
        reason:
            'ISSUES (9.1): a surface whose columns step sideways owes a horizontal '
            'bleed, or a partial-column slide has nothing painted to show.',
      );
      final dx = (10 + random.nextInt(70)).toDouble();
      final landing = painter.panLanding(Offset(dx, 0));
      expect(
        landing.shown.dx.abs(),
        greaterThan(0),
        reason:
            'ISSUES (9.1): a ${dx.toStringAsFixed(0)}px sideways drag shows NO motion — '
            'the missing preview, and the first tooth of the ratchet.',
      );
    });

    testWidgets('a drag starting anywhere on a mark grabs it (seed $seed)', (tester) async {
      final scene = Scene()..calendar(frameId);
      scene.place(frameId, civil(2026, 9, day, hour), title: 'Block');
      final painter = paintedOver(
        scene,
        civilDays(2026, 9, day) + Rational.fromInt(hour, 24),
      );
      expect(painter.hits, isNotEmpty, reason: 'the block painted and carries its hit');
      final block = painter.hits.first.bounds;
      expect(
        painter.markAt(block.center),
        isNotNull,
        reason: 'the body answers a click — the two-region hit is not in question',
      );
      expect(
        painter.grabAt(block.center),
        isNotNull,
        reason:
            'ISSUES (9.1): the centre of the block grabs nothing — the grab region is '
            'a nine-pixel unpainted strip, and the common gesture (drag the event you '
            'are pointing at) falls through to create. Alt is the stated way to create '
            'through an occupied span; the body moves.',
      );
    });
  }
}
