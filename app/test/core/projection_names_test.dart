// COLUMNS ARE PROJECTIONS, AND PROJECTIONS NAME MORE THAN FRAMES (ISSUES 9.2).
//
// Don: "one column for a frame shows all todos stapled to that frame, another
// all todos stapled to an OBJECT, another only paired todos; or AI Team AND
// Done vs AI Team NOT Done." The algebra exists (or/and/not/xor over frame
// names). The names did not: an object id or a graph predicate was not
// admitted. "The projection language must therefore admit object ids and graph
// predicates as names, not only frames -- a core extension."
//
// "The stapled pile is a graph, project the graph" (8.31). The algebra itself
// does not change -- `Projection.admits` already takes a predicate over names.
// What changes is WHICH NAMES AN OBJECT ANSWERS TO, and that is one question
// the engine answers:
//
// THE CONTRACT this file names, which does not exist yet:
//
//   ProjectionEngine.termsOf(String objectId) : Set<String>
//
// every name the object is admitted under -- every frame it reaches (what
// `modifyingFrames` already walks), every OBJECT it is stapled to, and the
// structural predicates that hold of it, spelled as names a person can bind:
// `stapled:object` for "has at least one object-to-object staple" (Don's
// "only PAIRED todos"). So `projection.admits(engine.termsOf(id).contains)`
// is the one call every column and every lens makes, whatever the term names.

import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:test/test.dart';

import '../helpers/projection_scene.dart';

void main() {
  test('a projection may name an object: "stapled to that object" is a term', () {
    final scene = Scene()..calendar('calendar:a');
    final meeting = scene.object(title: 'AI Team meeting', duration: '60');
    scene.place('calendar:a', civil(2026, 9, 3, 14), event: meeting);
    final follow = scene.object(title: 'Follow up', duration: '0');
    final loner = scene.object(title: 'Unrelated', duration: '0');
    scene.place('calendar:a', civil(2026, 9, 4, 9), event: loner);
    scene.staple(ends: [ObjectEnd(follow, point: 'start'), ObjectEnd(meeting, point: 'end')]);
    final engine = ProjectionEngine(scene.document);
    final bindings = {'meeting': meeting, 'cal': 'calendar:a'};
    final column = Projection.parse('meeting', bindings: bindings);
    expect(
      column.admits(engine.termsOf(follow).contains),
      isTrue,
      reason:
          'ISSUES 9.2: the projection language binds identifiers to FRAMES only; a column '
          '"stapled to that meeting" cannot be said. An object id is a name in the algebra.',
    );
    expect(
      column.admits(engine.termsOf(loner).contains),
      isFalse,
      reason: 'an object with no staple to the meeting is not admitted by its name',
    );
    final complement = Projection.parse('cal and not meeting', bindings: bindings);
    expect(complement.admits(engine.termsOf(loner).contains), isTrue, reason: 'NOT is its complement');
    expect(complement.admits(engine.termsOf(follow).contains), isFalse);
    // A frame is still a name, in the same set: the follow-up is positioned
    // through the meeting, so it reaches the calendar the meeting sits on.
    expect(
      Projection.parse('cal', bindings: bindings).admits(engine.termsOf(follow).contains),
      isTrue,
      reason: 'frame names and object names are one vocabulary, read from one set',
    );
  });

  test('a structural predicate is a term: only PAIRED todos', () {
    final scene = Scene()..calendar('calendar:a');
    final meeting = scene.object(title: 'AI Team meeting', duration: '60');
    scene.place('calendar:a', civil(2026, 9, 3, 14), event: meeting);
    final paired = scene.object(title: 'Paired', duration: '0');
    scene.staple(ends: [ObjectEnd(paired, point: 'start'), ObjectEnd(meeting, point: 'end')]);
    final alone = scene.object(title: 'Alone', duration: '0');
    scene.place('calendar:a', civil(2026, 9, 4, 9), event: alone);
    final engine = ProjectionEngine(scene.document);
    final column = Projection.parse('paired', bindings: const {'paired': 'stapled:object'});
    expect(
      column.admits(engine.termsOf(paired).contains),
      isTrue,
      reason: 'ISSUES 9.2: "another only PAIRED todos" -- has-an-object-staple is a name in the algebra',
    );
    expect(column.admits(engine.termsOf(alone).contains), isFalse);
    expect(
      column.admits(engine.termsOf(meeting).contains),
      isTrue,
      reason: 'a staple has two ends, and the meeting is paired by the same record',
    );
  });
}
