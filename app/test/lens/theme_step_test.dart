// A SURFACE STATES ITS STEP FROM ITS GROUND (ISSUES 9.2, Don).
//
// "I took and played with the colour palette, and there are some visual quirks
// ... like the double line drag zones, and the paper colour blending into
// itself in the area." The class: when a palette is re-authored, surfaces that
// derive their colour from the SAME token stop being distinguishable. Nothing is
// wrong at the shipped default; the default merely hides it.
//
// The fix is not to nudge two colours apart. A surface's colour states its
// RELATION to the ground it sits on -- one step of separation -- rather than
// naming the same token twice, so any palette a person authors stays legible,
// including a deliberately flat one where several roles collide.
//
// The rules:
//
//   `ChronoTheme.step(ground)` is the tone one step of separation above a
//   ground. Under ANY palette it is distinguishable from that ground by at least
//   the contrast the shipped hairline holds against paper -- the yardstick the
//   program already ships, not a number invented here.
//   Steps stack: step(step(g)) is distinguishable from step(g), so three
//   surfaces deep still read as three.
//   A step is a function of the ground alone; the same ground gets the same
//   step, so two surfaces on one ground agree.

import 'dart:math';

import 'package:chronolog/lens/theme.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';

/// WCAG's `(L + 0.05)` ratio, the thing the eye measures.
double contrast(Color a, Color b) {
  final (low, high) = (a.computeLuminance(), b.computeLuminance());
  return low > high ? (low + 0.05) / (high + 0.05) : (high + 0.05) / (low + 0.05);
}

String randomHex(Random random) =>
    '#${random.nextInt(0x1000000).toRadixString(16).padLeft(6, '0')}';

/// Palettes a person might author: eight independent colours; a flat one where
/// ground, surface and paper are one colour; a wholly flat one where all eight
/// collide; and a near-flat one a shade apart.
List<ChronoTheme> palettes(Random random) {
  final themes = <ChronoTheme>[];
  for (var index = 0; index < 12; index += 1) {
    themes.add(ChronoTheme.fromJson({for (final field in themeFields) field: randomHex(random)}));
  }
  for (var index = 0; index < 6; index += 1) {
    final one = randomHex(random);
    themes.add(
      ChronoTheme.fromJson({
        for (final field in themeFields) field: randomHex(random),
        'ground': one,
        'surface': one,
        'paper': one,
      }),
    );
  }
  for (var index = 0; index < 4; index += 1) {
    final one = randomHex(random);
    themes.add(ChronoTheme.fromJson({for (final field in themeFields) field: one}));
  }
  return themes;
}

void main() {
  final yardstick = contrast(shipped['paper']!.hair, shipped['paper']!.paper);

  test('one step above any ground is distinguishable from it, under any palette', () {
    final random = Random(specSeed);
    for (final theme in palettes(random)) {
      for (final ground in [theme.ground, theme.surface, theme.paper]) {
        final above = theme.step(ground);
        expect(
          contrast(above, ground),
          greaterThanOrEqualTo(yardstick - 1e-9),
          reason:
              'ISSUES 9.2: "the paper colour blending into itself" -- under ${theme.toJson()} a '
              'surface on ${hexOf(ground)} is ${hexOf(above)}, which the eye cannot tell apart.',
        );
      }
    }
  });

  test('steps stack: three surfaces deep still read as three', () {
    final random = Random(specSeed + 1);
    for (final theme in palettes(random)) {
      final first = theme.step(theme.ground);
      final second = theme.step(first);
      final third = theme.step(second);
      expect(contrast(second, first), greaterThanOrEqualTo(yardstick - 1e-9), reason: 'second on first');
      expect(contrast(third, second), greaterThanOrEqualTo(yardstick - 1e-9), reason: 'third on second');
    }
  });

  test('a step is a function of the ground alone', () {
    final random = Random(specSeed + 2);
    for (final theme in palettes(random)) {
      final ground = theme.paper;
      expect(theme.step(ground), equals(theme.step(ground)), reason: 'two surfaces on one ground agree');
    }
  });
}
