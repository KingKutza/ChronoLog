// AFFILIATION -- THE WRITER SIDE (Don, ruled 2026-09-01).
//
// "Staples to a point: this point is that point. Staples to an object, no point:
// ALL of this object is that point -- which in practice would be affiliation.
// There would not so much be membership, as it is not directional."
//
// THERE IS NO MEMBERSHIP, ONLY STAPLES.
//
// The readers were unified first (`stapledFrames`, `effectiveObjectStaples`);
// the writers still minted a record kind of their own. They mint a STAPLE now,
// saying the same sentence: a frame end that names NO POINT says "this object is
// in that frame, and nothing about where", which is the whole of what a
// `membership` record ever said.
//
// The discriminator is structural, never a verb: naming a point and naming no
// point are already different sentences, so no kind label decides anything and
// no enum is introduced. That is the claim under test here, from both sides --
// the new spelling is read everywhere the old one was, and the old one keeps
// loading and meaning exactly what it meant.

import 'dart:math';

import 'package:chronolog/core/indexes.dart';
import 'package:chronolog/core/object_kinds.dart';
import 'package:chronolog/core/ops.dart';
import 'package:chronolog/core/staples.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/validate.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:test/test.dart';

import '../core/corpus.dart';
import '../helpers/projection_scene.dart';
import 'harness.dart';

const String calendarId = 'calendar:work';
const String groupId = 'frame:errands';

void main() {
  late Bench bench;
  late Editor editor;

  Future<Editor> openScene(Scene scene) async {
    bench = await openEditor(scene.document, label: 'melt');
    return editor = bench.editor;
  }

  tearDown(() async => closeEditor(bench));

  Scene world(int day) {
    final scene = Scene()..calendar(calendarId);
    scene.group(groupId, const []);
    return scene;
  }

  for (final seed in seeds(5)) {
    final random = Random(seed);
    final day = 2 + random.nextInt(20);

    test('the membership writer mints a staple, and every reader agrees (seed $seed)', () async {
      final scene = world(day);
      final object = scene.object(title: 'Buy staples');
      scene.place(calendarId, civil(2026, 9, day, 9), event: object);
      await openScene(scene);

      final said = editor.membership(object, groupId);
      editor.commitOps('Join', [putOp('relations', said.id, said)]);

      final written = editor.document.relations[said.id]!;
      expect(written.isStaple, isTrue, reason: 'ruled: the only relationship is a staple');
      expect(
        written.ends.whereType<FrameEnd>().single.position,
        isNull,
        reason: 'a frame end naming no point IS the membership sentence',
      );

      // Every reader that ever answered "is this in that frame" answers yes.
      final indexes = editor.engine.indexes;
      expect(indexes.directGroupsOf(object), contains(groupId));
      expect(indexes.memberObjects(groupId), contains(object));
      expect(indexes.stapledFrames(object), contains(groupId));
      expect(validateDocument(editor.document).errors, isEmpty);
    });

    test('the two spellings are the SAME edge, everywhere (seed $seed)', () async {
      final scene = world(day);
      final byRecord = scene.object(title: 'Old spelling');
      final byStaple = scene.object(title: 'New spelling');
      for (final id in [byRecord, byStaple]) {
        scene.place(calendarId, civil(2026, 9, day, 9), event: id);
      }
      scene.join(groupId, byRecord);
      await openScene(scene);

      final said = editor.membership(byStaple, groupId);
      editor.commitOps('Join', [putOp('relations', said.id, said)]);

      final indexes = editor.engine.indexes;
      expect(indexes.directGroupsOf(byRecord), indexes.directGroupsOf(byStaple));
      expect(indexes.memberObjects(groupId), containsAll([byRecord, byStaple]));
      // And the projection populates from the group identically for both.
      final facts = editor.engine
          .queryFacts(
            Projection.of(const [groupId]),
            start: civil(2026, 9, 1),
            end: civil(2026, 10, 1),
          )
          .facts
          .map((fact) => fact.event.id);
      expect(facts, containsAll([byRecord, byStaple]));
    });

    test('a state written as a staple is the same Done (seed $seed)', () async {
      final scene = world(day);
      final todo = scene.object(title: 'Chase the rubric', duration: '0');
      scene.document = scene.document.put(
        'events',
        todo,
        scene.document.events[todo]!.copyWith(traits: const ['event', 'task', 'todo']),
      );
      scene.place(calendarId, civil(2026, 9, day, 9), event: todo);
      await openScene(scene);

      editor.toggleState(todo, doneStateFrameId, frame: calendarId);
      expect(
        editor.engine.facts.stateAffiliations(todo).map((entry) => entry.frame),
        contains(doneStateFrameId),
        reason:
            'ruled 2026-09-01: the state grammar reads both spellings, or a Done '
            'written by this build and one written by an older one are different '
            'facts.',
      );
      // And it comes back off, through whichever record carried it.
      editor.toggleState(todo, doneStateFrameId, frame: calendarId);
      expect(editor.engine.facts.stateAffiliations(todo), isEmpty);
    });

    test('an anchor staple that NAMES a point is not a membership (seed $seed)', () {
      final scene = world(day);
      final object = scene.object();
      scene.place(calendarId, civil(2026, 9, day, 9), event: object);
      // The same two things connected, but the frame end says WHERE. That is a
      // different sentence and must not become an edge in the membership pool.
      scene.staple(
        kind: 'anchor',
        ends: [
          ObjectEnd(object, point: 'start'),
          FrameEnd(groupId, position: Position.coordinate(civil(2026, 9, day, 9))),
        ],
      );
      final indexes = Indexes(scene.document);
      expect(
        indexes.directGroupsOf(object),
        isNot(contains(groupId)),
        reason:
            'the discriminator is structural: naming a point and naming no point '
            'are already different sentences, so no verb has to decide.',
      );
      // It is still a connection, and the whole-graph read still sees it.
      expect(indexes.stapledFrames(object), contains(groupId));
    });

    test('the containment writer mints a staple, and every reader agrees (seed $seed)', () async {
      final scene = world(day);
      final holder = scene.object(title: 'The project');
      final held = scene.object(title: 'The task');
      for (final id in [holder, held]) {
        scene.place(calendarId, civil(2026, 9, day, 9), event: id);
      }
      await openScene(scene);

      editor.setContains(holder, held, true);

      final said = editor.document.relations.values.singleWhere(
        (relation) => stapledContainments(relation).isNotEmpty,
      );
      expect(said.isStaple, isTrue, reason: 'ruled: the only relationship is a staple');
      expect(
        said.ends.every((end) => end is ObjectEnd && end.point == null),
        isTrue,
        reason:
            'ISSUES (9.1, ruled): object ends alone, every one of them silent — '
            '"all of this is all of that", with no group side and no arrow.',
      );

      // Every reader that ever answered "what holds this" answers the same.
      final facts = editor.engine.facts;
      expect(facts.children(holder), contains(held));
      expect(facts.parents(held), contains(holder));
      expect(editor.engine.indexes.childrenOf(holder), contains(held));
      expect(editor.engine.indexes.parentsOf(held), contains(holder));
      expect(facts.containsSummary(holder).direct, 1);
      expect(validateDocument(editor.document).errors, isEmpty);

      // And it comes back off through the same one verb.
      editor.setContains(holder, held, false);
      expect(editor.engine.indexes.childrenOf(holder), isEmpty);
    });

    test('a silent object end is the whole of it, and start is said, never assumed '
        '(seed $seed)', () async {
      expect(defaultPoint, wholePoint);
      expect(defaultPoint, isNot(startPoint));

      final scene = world(day);
      final object = scene.object(title: 'Placed');
      scene.place(calendarId, civil(2026, 9, day, 9), event: object);
      await openScene(scene);

      // The placement says `start` out loud, because the silence means something
      // else now and a write that meant the start has to keep saying so.
      final placement = editor.document.relations.values.singleWhere(
        (relation) => isPlacement(relation, object),
      );
      expect(placement.ends.whereType<ObjectEnd>().single.point, startPoint);

      // A silent end reads as the whole, and a whole is not an instant: an
      // anchor that names one refuses in words rather than picking an edge.
      final other = scene.object(title: 'Rides nothing');
      editor.commitOps('Say it', [
        putOp(
          'relations',
          'relation:silent',
          Relation(
            id: 'relation:silent',
            type: 'staple',
            extra: {
              'kind': 'anchor',
              'ends': [ObjectEnd(other).toJson(), ObjectEnd(object, point: startPoint).toJson()],
            },
          ),
        ),
      ]);
      final extent = editor.staples.resolveObjectExtent(other);
      expect(extent.startDays, isNull, reason: 'a whole is not an instant');
      expect(
        extent.unresolved.map((contest) => contest.reason).join(' '),
        contains('whole of this object'),
        reason: 'ISSUES (9.1): it refuses in words rather than picking an edge',
      );
    });
  }
}
