// ONE SUBSTRATE, ONE LIST -- AND NOW ONE SHAPE (Don, ruled 2026-09-01).
//
// "Break the stupid compatibility, break it every time, that is the point of
// alpha." A connection is a staple. `effectiveObjectStaples` lists every one of
// them, and there is no longer a second kind of record for it to fold in: the
// implicit placement row and the multi-kind table both died with the kinds they
// accommodated.
//
// The three properties. EVERY staple that names this object is one of its
// sentences -- the same set the heal compares against, so the card and the heal
// cannot disagree. LISTING IS NOT POSITIONING: an affiliation says nothing about
// where, so a derivation about position must read no claim out of it. And an
// AFFILIATION READS THE SAME FROM BOTH ENDS: identification carries no
// direction, so there is no arrow to read and no near side that is privileged.

import 'dart:math';

import 'package:chronolog/core/falloff.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/series_heal.dart';
import 'package:chronolog/core/staples.dart';
import 'package:test/test.dart';

import '../helpers/projection_scene.dart';
import 'corpus.dart';

const String frameId = 'calendar:a';

/// One object wearing every sentence at once: placed, affiliated with a group,
/// anchored to a neighbour, and held by it.
({Scene scene, String object, String other}) spokenWorld(int day) {
  final scene = Scene()..calendar(frameId);
  scene.group('frame:errands', const []);
  final object = scene.object(title: 'Chase the grading rubric');
  scene.place(frameId, civil(2026, 9, day, 9), event: object);
  final other = scene.object(title: 'Neighbour');
  scene.place(frameId, civil(2026, 9, day, 14), event: other);
  scene.join('frame:errands', object);
  scene.staple(
    kind: 'anchor',
    ends: [ObjectEnd(object, point: 'end'), ObjectEnd(other, point: 'start')],
  );
  // Containment: object ends alone, both silent -- all of this is all of that.
  scene.staple(ends: [ObjectEnd(object), ObjectEnd(other)]);
  return (scene: scene, object: object, other: other);
}

void main() {
  for (final seed in seeds(5)) {
    final random = Random(seed);
    final day = 2 + random.nextInt(20);

    test('every staple that names the object is one of its sentences (seed $seed)', () {
      final world = spokenWorld(day);
      final staples = Staples(world.scene.document);
      final listed = {
        for (final row in staples.effectiveObjectStaples(world.object)) row.staple?.id,
      }..removeWhere((id) => id == null);

      // The heal's own reading of "what this occurrence contains" is the
      // reference set: one shape means the two cannot drift apart.
      final referencing = {
        for (final relation in relationsReferencing(world.scene.document, world.object))
          relation.id,
      };
      expect(
        listed,
        containsAll(referencing),
        reason:
            'ISSUES (9.1, ruled): one substrate, one list — the card shows every '
            'sentence and the heal reads the same truth.',
      );
      expect(
        staples.effectiveObjectStaples(world.object).every((row) => row.staple != null),
        isTrue,
        reason: 'there is no second kind of record left to synthesize a row from',
      );
    });

    test('an affiliation reads the same from both ends (seed $seed)', () {
      final world = spokenWorld(day);
      final staples = Staples(world.scene.document);
      final held = staples.effectiveObjectStaples(world.other);
      final holds = staples.effectiveObjectStaples(world.object);

      // The containment staple: both objects find it, and neither finds an
      // arrow. Which one the tree reads as held-by is the AUTHORED ORDER, and
      // the identification itself is symmetric.
      Relation containment(List<ConnectionRow> rows) => rows
          .map((row) => row.staple!)
          .firstWhere((staple) => stapledContainments(staple).isNotEmpty);
      expect(
        containment(holds).id,
        containment(held).id,
        reason:
            'ruled 2026-09-01: "there would not so much be membership, as it is '
            'not directional" — one sentence, readable from either end.',
      );
      final edge = stapledContainments(containment(holds)).single;
      expect(edge.child, world.object);
      expect(edge.parent, world.other);

      // And the group side of an affiliation to a FRAME is decided by structure
      // -- which end is a frame -- never by which field was written first.
      final affiliation = holds
          .map((row) => row.staple!)
          .firstWhere((staple) => stapledAffiliations(staple).isNotEmpty);
      expect(stapledAffiliations(affiliation).single.frame, 'frame:errands');
      expect(stapledAffiliations(affiliation).single.object, world.object);
    });

    test('listing everything is not positioning from everything (seed $seed)', () {
      final world = spokenWorld(day);
      final rows = Staples(world.scene.document).effectiveObjectStaples(world.object);
      for (final row in rows) {
        if (stapledAffiliations(row.staple!).isNotEmpty ||
            stapledContainments(row.staple!).isNotEmpty) {
          expect(
            row.positions,
            isFalse,
            reason: '"this belongs to that" says nothing about when',
          );
        }
      }
      expect(rows.where((row) => row.positions), isNotEmpty);

      // The home a projection reads is IDENTICAL with and without the sentences
      // that say nothing about where -- stated as a difference of two worlds
      // rather than as a number.
      DayExtent homeIn(Document document) {
        final engine = ProjectionEngine(document);
        final fact = engine
            .queryFacts(
              Projection.of(const [frameId]),
              start: civil(2026, 9, 1),
              end: civil(2026, 10, 1),
            )
            .facts
            .firstWhere((row) => row.event.id == world.object);
        return engine.homeOf(fact)!;
      }

      var quiet = world.scene.document;
      for (final relation in world.scene.document.relations.values) {
        if (stapledAffiliations(relation).isNotEmpty ||
            stapledContainments(relation).isNotEmpty) {
          quiet = quiet.remove('relations', relation.id);
        }
      }
      expect(homeIn(world.scene.document), homeIn(quiet));
    });
  }
}
