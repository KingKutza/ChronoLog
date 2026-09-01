// THE NEAR FUTURE MAY WEIGH MORE, WHEN A FRAME SAYS SO (ISSUES 9.1, Don).
//
// "An optional rule on a frame: an importance modifier that makes near future
// events more important, with benefits falling off as items move farther into
// the future." The machinery half-exists — unresolved todos already fade from
// now, and frames already author `display.halfDistance` — so the rule is the
// same mechanism offered to EVENTS, opt-in per frame, through an authored
// `display.proximity` curve. Optional by construction: a frame that authors
// nothing changes nothing, which the guard case pins.

import 'dart:math';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/lens/display_weight.dart';
import 'package:test/test.dart' as plain;
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import '../helpers/projection_scene.dart';
import 'painters/grid_scene.dart';

const String frameId = 'calendar:a';

void main() {
  for (final seed in seeds(5)) {
    final random = Random(seed);
    final near = 1 + random.nextInt(2);
    final far = 12 + random.nextInt(18);

    plain.test('an authored proximity curve boosts the nearer future (seed $seed)', () {
      final scene = Scene()..calendar(frameId);
      // Hoisted on purpose: `scene.document.relations[scene.place(…)]` reads
      // the receiver BEFORE place() mints, and looks up in a document that
      // does not hold the relation yet.
      final nearRelation = scene.place(frameId, civil(2026, 9, 1 + near, 9), title: 'Soon');
      final farRelation = scene.place(frameId, civil(2026, 9, 1 + far, 9), title: 'Later');
      final nearId = '${scene.document.relations[nearRelation]!.event}';
      final farId = '${scene.document.relations[farRelation]!.event}';
      scene.group('frame:pressing', [nearId, farId], extra: {
        'display': {'proximity': '4'},
      });
      final lens = sceneOf(
        scene.document,
        const [frameId],
        now: civilDays(2026, 9, 1),
        focus: civilDays(2026, 9, 1),
      );
      final facts = {
        for (final fact in lens.engine
            .queryFacts(lens.projection,
                start: civilDays(2026, 9, 1), end: civilDays(2026, 9, 1) + Rational.fromInt(40))
            .facts)
          '${fact.event.payload?['title']}': fact,
      };
      final soon = factDisplayWeight(lens, facts['Soon']!).weight;
      final later = factDisplayWeight(lens, facts['Later']!).weight;
      expect(
        soon > later,
        isTrue,
        reason:
            'ISSUES (9.1): the frame authors display.proximity and the event $near day(s) '
            'out weighs $soon against $later at $far day(s) — the authored curve is read '
            'by nothing.',
      );
    });

    plain.test('a frame that authors nothing changes nothing (seed $seed)', () {
      final scene = Scene()..calendar(frameId);
      // Hoisted on purpose: `scene.document.relations[scene.place(…)]` reads
      // the receiver BEFORE place() mints, and looks up in a document that
      // does not hold the relation yet.
      final nearRelation = scene.place(frameId, civil(2026, 9, 1 + near, 9), title: 'Soon');
      final farRelation = scene.place(frameId, civil(2026, 9, 1 + far, 9), title: 'Later');
      final nearId = '${scene.document.relations[nearRelation]!.event}';
      final farId = '${scene.document.relations[farRelation]!.event}';
      scene.group('frame:quiet', [nearId, farId]);
      final lens = sceneOf(
        scene.document,
        const [frameId],
        now: civilDays(2026, 9, 1),
        focus: civilDays(2026, 9, 1),
      );
      final facts = {
        for (final fact in lens.engine
            .queryFacts(lens.projection,
                start: civilDays(2026, 9, 1), end: civilDays(2026, 9, 1) + Rational.fromInt(40))
            .facts)
          '${fact.event.payload?['title']}': fact,
      };
      expect(
        factDisplayWeight(lens, facts['Soon']!).weight,
        factDisplayWeight(lens, facts['Later']!).weight,
        reason: 'optional means optional: no authored curve, no proximity arithmetic',
      );
    });
  }
}
