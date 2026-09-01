// THERE IS NO MEMBERSHIP, ONLY STAPLES (Don, ruled 2026-09-01).
//
// "The only relationship any object or frame can have to another is a staple."
// The document still spells that sentence four ways -- an attachment's frame, a
// membership edge, a frame's own query selector, an authored staple's frame end
// -- and every reader that counted one spelling made the others invisible. The
// board report is the proof: Don's AI Tiger Team connection, said by the picker
// as an anchor staple, could not column on a grouping that read memberships.
//
// The property, quantified over seeded worlds rather than pinned to one
// arrangement: EVERY SPELLING ANSWERS THE SAME QUESTION. A frame an object is
// connected to appears in `stapledFrames` whichever way the connection was
// authored, and a frame nothing connects it to never does.

import 'dart:math';

import 'package:chronolog/core/indexes.dart';
import 'package:chronolog/core/records.dart';
import 'package:test/test.dart';

import '../helpers/projection_scene.dart';
import 'corpus.dart';

const String home = 'calendar:a';
const String stranger = 'frame:unrelated';

/// The four spellings, as functions of one world. Named by how the AUTHOR said
/// it, not by which record map it landed in -- which is the whole point.
final Map<String, void Function(Scene, String object, String frame)> spellings = {
  'placed on it': (scene, object, frame) =>
      scene.place(frame, civil(2026, 9, 3, 9), event: object),
  'a member of it': (scene, object, frame) => scene.join(frame, object),
  'stapled to it': (scene, object, frame) => scene.staple(
    kind: 'anchor',
    ends: [ObjectEnd(object, point: 'start'), StapleEnd.frame(frame)],
  ),
  'selected by it': (scene, object, frame) => scene.document = scene.document.put(
    'frames',
    frame,
    scene.document.frames[frame]!.withField('query', {
      'ids': [object],
    }),
  ),
};

void main() {
  for (final seed in seeds(5)) {
    final random = Random(seed);
    final said = spellings.keys.elementAt(random.nextInt(spellings.length));

    test('an object $said is stapled to it, whatever the record says (seed $seed)', () {
      final scene = Scene()..calendar(home);
      scene.frame('frame:said', const ['set', 'group']);
      scene.frame(stranger, const ['set', 'group']);
      final object = scene.object(title: 'Chase the grading rubric');
      scene.place(home, civil(2026, 9, random.nextInt(20) + 1, 9), event: object);
      spellings[said]!(scene, object, 'frame:said');

      final frames = Indexes(scene.document).stapledFrames(object);
      expect(
        frames,
        contains('frame:said'),
        reason:
            'ISSUES (9.1, ruled): the object is $said, and one read must answer for '
            'every spelling — a reader that counts one makes the rest invisible.',
      );
      expect(frames, contains(home), reason: 'its placement is a staple too');
      expect(frames, isNot(contains(stranger)), reason: 'nothing was said about that frame');
    });

    test('a frame inside a frame the object is in counts, one hop further (seed $seed)', () {
      final scene = Scene()..calendar(home);
      final object = scene.object();
      scene.place(home, civil(2026, 9, 4, 9), event: object);
      scene.group('frame:inner', [object]);
      scene.group('frame:outer', const ['frame:inner']);

      final frames = Indexes(scene.document).stapledFrames(object);
      expect(frames, containsAll(const ['frame:inner', 'frame:outer']));
    });

    test('the answer is a set of FRAMES, sorted and deduped (seed $seed)', () {
      final scene = Scene()..calendar(home);
      final object = scene.object();
      final other = scene.object(title: 'Neighbour');
      scene.place(home, civil(2026, 9, 5, 9), event: object);
      // The same frame said three ways at once, plus a staple to another OBJECT,
      // which is a connection and not a frame.
      scene.join(home, object);
      scene.staple(
        kind: 'anchor',
        ends: [ObjectEnd(object, point: 'start'), StapleEnd.frame(home)],
      );
      scene.staple(
        kind: 'anchor',
        ends: [ObjectEnd(object, point: 'end'), ObjectEnd(other, point: 'start')],
      );

      final frames = Indexes(scene.document).stapledFrames(object);
      expect(frames.toSet().length, frames.length, reason: 'one connection is one answer');
      expect(frames, orderedEquals([...frames]..sort()));
      expect(frames, isNot(contains(other)), reason: 'an object end is not a frame');
    });
  }
}
