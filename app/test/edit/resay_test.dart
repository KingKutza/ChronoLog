// RE-SAYING AN END (ISSUES 9.1, two reports and one law).
//
// "No way to move an event incorrectly authored on one frame to another... I
// think this is a sentences error." And its generalization: "No apparent way to
// edit a staple's attached frame to a different frame or object... the only way
// to change what a staple connects is delete-and-recreate, which throws away the
// staple's other terms with it."
//
// The law both invoke: EVERY END OF A CONNECTION IS AN AUTHORED TERM. A term you
// can read but not re-say makes the row display, not authoring. So the verb is
// one verb over one substrate -- "there is no membership, only staples" -- and it
// keeps every other term, translates the coordinate through the two frames' own
// laws, and refuses in words when no correspondence can carry it.

import 'dart:math';

import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/correspondence.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/staples.dart';
import 'package:chronolog/edit/resay.dart';
import 'package:test/test.dart';

import '../core/corpus.dart';
import '../helpers/projection_scene.dart';

const String from = 'calendar:a', onto = 'calendar:b', elsewhere = 'frame:invented';

({Staples staples, Correspondences correspondences}) read(Scene scene) {
  final staples = Staples(scene.document);
  return (staples: staples, correspondences: Correspondences(staples));
}

/// Which term of this sentence names a frame -- asked of the sentence, not
/// guessed from a field name.
String frameEndOf(Scene scene, String relationId) => connectionEnds(
  scene.document.relations[relationId]!,
).singleWhere((end) => end.map == 'frames').slot;

Attempt<Relation> resay(Scene scene, String relationId, String slot, String becomes) {
  final seams = read(scene);
  return resaidConnection(
    seams.staples,
    seams.correspondences,
    scene.document.relations[relationId]!,
    slot: slot,
    becomes: becomes,
  );
}

void main() {
  test('one shape offers its ends, and a retired kind offers none', () {
    final scene = Scene()
      ..calendar(from)
      ..calendar(onto);
    final object = scene.object();
    final placement = scene.place(from, civil(2026, 9, 2, 9), event: object);
    final membership = scene.join(onto, object);
    final staple = scene.staple(
      kind: 'anchor',
      ends: [ObjectEnd(object, point: 'start'), StapleEnd.frame(onto)],
    );
    final invented = scene.mint('relation');
    scene.document = scene.document.put(
      'relations',
      invented,
      Relation(id: invented, type: 'wormhole', extra: {'event': object, 'frame': onto}),
    );

    // REWRITTEN under the ruling of 2026-09-01: there is ONE record shape, so a
    // term is named by its position in the sentence rather than by a field name
    // borrowed from a record kind that no longer exists.
    String slots(String id) =>
        connectionEnds(scene.document.relations[id]!).map((end) => end.slot).join(',');
    for (final id in [placement, membership, staple.id]) {
      expect(slots(id), 'end:0,end:1');
    }
    expect(
      slots(invented),
      isEmpty,
      reason:
          'a retired kind is data, never a refusal — and it has no ends, so it '
          'offers no terms: nothing reads it, and that has to include the card',
    );
  });

  for (final seed in seeds(5)) {
    final random = Random(seed);
    final day = 1 + random.nextInt(20);
    final hour = random.nextInt(23);

    test('a placement re-said onto another frame keeps its instant (seed $seed)', () {
      final scene = Scene()
        ..calendar(from)
        ..calendar(onto);
      final object = scene.object(title: 'Authored on the wrong calendar');
      final placement = scene.place(from, civil(2026, 9, day, hour), event: object);

      final frameSlot = frameEndOf(scene, placement);
      final said = resay(scene, placement, frameSlot, onto).resolved!;
      expect(said.frame, onto);
      expect(said.event, object, reason: 'every other term stands');
      expect(said.type, 'staple');
      final seams = read(scene);
      expect(
        seams.staples.daysOf(onto, Coordinate.fromJson(said.coordinate)),
        seams.staples.daysOf(from, Coordinate.fromJson(scene.document.relations[placement]!.coordinate)),
        reason:
            'ISSUES (9.1): re-framing is re-pointing the frame end and re-expressing '
            'the coordinate in the new frame\'s law — the same instant, said again.',
      );
    });

    test('a staple end re-said keeps the staple\'s other ends (seed $seed)', () {
      final scene = Scene()
        ..calendar(from)
        ..calendar(onto);
      final object = scene.object();
      scene.place(from, civil(2026, 9, day, hour), event: object);
      final staple = scene.staple(
        kind: 'anchor',
        ends: [
          ObjectEnd(object, point: 'start'),
          FrameEnd(from, position: Position.coordinate(civil(2026, 9, day, hour))),
        ],
      );

      final said = resay(scene, staple.id, 'end:1', onto).resolved!;
      final ends = said.ends;
      expect((ends[1] as FrameEnd).frame, onto);
      expect(ends[0], staple.ends[0], reason: 'the other end is not re-said and does not move');
      expect(said.kind, staple.kind);
      final seams = read(scene);
      expect(
        seams.staples.frameEndDays(ends[1]),
        seams.staples.frameEndDays(staple.ends[1]),
        reason: 'the instant is carried across, not the written levels',
      );
    });

    test('a membership re-said is one field and no arithmetic (seed $seed)', () {
      final scene = Scene()
        ..calendar(from)
        ..group('frame:one', const [])
        ..group('frame:two', const []);
      final object = scene.object();
      scene.place(from, civil(2026, 9, day, hour), event: object);
      final membership = scene.join('frame:one', object);

      final said = resay(scene, membership, frameEndOf(scene, membership), 'frame:two')
          .resolved!;
      expect(said.group, 'frame:two');
      expect(said.member, object);
      expect(said.coordinate, isNull, reason: 'a membership names no instant to carry');
    });

    test('an end nothing can carry the instant to REFUSES, and writes nothing '
        '(seed $seed)', () {
      final scene = Scene()..calendar(from);
      // A frame on its own invented ladder, related to nothing.
      scene.frame(elsewhere, const ['set', 'calendar'], const {'coordinate': inventedLaw});
      final object = scene.object();
      final placement = scene.place(from, civil(2026, 9, day, hour), event: object);

      final said = resay(scene, placement, frameEndOf(scene, placement), elsewhere);
      expect(said.resolved, isNull);
      expect(
        said.refusal,
        isNotNull,
        reason:
            'ISSUES (9.1): "or refuse in words when no correspondence can carry it" — '
            'sharing unit lengths is not sharing positions.',
      );
      expect(scene.document.relations[placement]!.frame, from, reason: 'nothing was written');
    });

    test('an end that names nothing, or names it already, is answered plainly '
        '(seed $seed)', () {
      final scene = Scene()
        ..calendar(from)
        ..calendar(onto);
      final object = scene.object();
      final placement = scene.place(from, civil(2026, 9, day, hour), event: object);

      final slot = frameEndOf(scene, placement);
      expect(resay(scene, placement, slot, 'frame:nobody').refusal, contains('frame:nobody'));
      expect(resay(scene, placement, slot, '  ').refusal, isNotNull);
      expect(resay(scene, placement, 'end:9', onto).refusal, contains('no end:9 end'));
      expect(
        resay(scene, placement, slot, from).resolved,
        scene.document.relations[placement],
        reason: 're-saying a term as what it already says changes nothing',
      );
    });
  }
}
