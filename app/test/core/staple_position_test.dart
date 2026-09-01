// AN OBJECT WHOSE ONLY POSITION IS A STAPLE MUST PROJECT THROUGH IT
// (ISSUES 9.1: "Right-clicked an event, chose 'New todo here', and it authored
// an anchor to Wall Time -- not to the event under the pointer").
//
// Don's ruling on the mechanism: the todo rides the event. "The todo wants a
// staple to the event (directional, the todo's point identified with the
// event's), so it rides if the event moves -- anchoring to the frame instead
// bakes in a position that goes stale the moment the event is re-said."
//
// The substrate always resolved through those staples; what nothing did was
// ENUMERATE such an object, so it resolved to a position no surface asked for
// and a companion placement had to be minted beside the staple to make it draw.
// That companion is the stale coordinate the report names.
//
// The properties, quantified over seeded worlds: a stapled object with NO
// placement of its own draws; it MOVES when the object it rides moves, without
// a single record of its own being rewritten; and one that rides nothing
// positioned refuses in words rather than sitting silently nowhere.

import 'dart:math';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/staples.dart';
import 'package:test/test.dart';

import '../helpers/projection_scene.dart';
import 'corpus.dart';

const String frameId = 'calendar:a';

Rational civilDays(int year, int month, int day) =>
    Rational(daysFromCivil(BigInt.from(year), month, day));

QueryResult over(Scene scene, int day) {
  final engine = ProjectionEngine(scene.document);
  final start = civilDays(2026, 9, day);
  return engine.queryFacts(
    Projection.of(const [frameId]),
    start: start - Rational.fromInt(30),
    end: start + Rational.fromInt(30),
  );
}

/// Don's exact authoring path, minus the companion placement: an event on a
/// calendar, and a todo whose only sentence is "my start is that event's start".
({Scene scene, String host, String rider}) ridingWorld(int day, {int hour = 9}) {
  final scene = Scene()..calendar(frameId);
  final host = scene.object(title: 'Lunch');
  scene.place(frameId, civil(2026, 9, day, hour), event: host);
  final rider = scene.object(title: 'Chase the grading rubric', duration: '0');
  scene.document = scene.document.put(
    'events',
    rider,
    scene.document.events[rider]!.copyWith(traits: const ['event', 'task', 'todo']),
  );
  scene.staple(
    kind: 'anchor',
    ends: [ObjectEnd(rider, point: 'start'), ObjectEnd(host, point: 'start')],
  );
  return (scene: scene, host: host, rider: rider);
}

void main() {
  for (final seed in seeds(5)) {
    final random = Random(seed);
    final day = 2 + random.nextInt(20);
    final hour = random.nextInt(23);

    test('an object placed only by a staple draws where the staple says (seed $seed)', () {
      final world = ridingWorld(day, hour: hour);
      final facts = over(world.scene, day).facts;
      final rider = facts.where((fact) => fact.event.id == world.rider);
      expect(
        rider,
        hasLength(1),
        reason:
            'ISSUES (9.1): the staple says the two points are ONE POINT, which has '
            'already said where the todo is — nothing is left for a companion '
            'placement record to add.',
      );
      final host = facts.firstWhere((fact) => fact.event.id == world.host);
      expect(rider.single.day, host.day, reason: 'one point, said once');
      // And it was drawn without a placement record of its own: the position is
      // a reading of the sentence, never a second copy of it.
      expect(
        world.scene.document.relations.values.any((r) => isPlacement(r, world.rider)),
        isFalse,
      );
    });

    test('the rider MOVES when what it rides is re-said, with nothing of its own '
        'rewritten (seed $seed)', () {
      final world = ridingWorld(day, hour: hour);
      final before = over(
        world.scene,
        day,
      ).facts.firstWhere((fact) => fact.event.id == world.rider).day;

      // Re-say the host's placement, and only the host's.
      final placement = world.scene.document.relations.values.firstWhere(
        (relation) => isPlacement(relation, world.host),
      );
      final untouched = {
        for (final entry in world.scene.document.relations.entries)
          if (entry.key != placement.id) entry.key: entry.value,
      };
      // Re-say the host's frame end. The coordinate lives THERE (ruled
      // 2026-09-01, the placement is a staple), so writing a top-level field
      // would edit nothing and the rider would have nothing to ride.
      world.scene.document = world.scene.document.put(
        'relations',
        placement.id,
        placement.withField('ends', [
          for (final end in placement.ends)
            end is FrameEnd
                ? FrameEnd(
                    end.frame,
                    position: Position.coordinate(civil(2026, 9, day - 1, hour)),
                  ).toJson()
                : end.toJson(),
        ]),
      );

      final after = over(
        world.scene,
        day,
      ).facts.firstWhere((fact) => fact.event.id == world.rider).day;
      expect(
        after,
        before - Rational.one,
        reason:
            'ISSUES (9.1): it rides. A baked-in coordinate would have stayed where '
            'it was the moment the event was re-said.',
      );
      for (final entry in untouched.entries) {
        expect(world.scene.document.relations[entry.key], entry.value);
      }
    });

    test('a chain of riders resolves through, however long (seed $seed)', () {
      final world = ridingWorld(day, hour: hour);
      var previous = world.rider;
      final chain = <String>[];
      for (var hop = 0; hop < 1 + random.nextInt(3); hop += 1) {
        final next = world.scene.object(title: 'Hop $hop', duration: '0');
        world.scene.staple(
          kind: 'anchor',
          ends: [ObjectEnd(next, point: 'start'), ObjectEnd(previous, point: 'start')],
        );
        chain.add(next);
        previous = next;
      }
      final facts = over(world.scene, day).facts;
      final host = facts.firstWhere((fact) => fact.event.id == world.host).day;
      for (final id in chain) {
        expect(facts.where((fact) => fact.event.id == id), hasLength(1));
        expect(facts.firstWhere((fact) => fact.event.id == id).day, host);
      }
    });

    test('a rider that rides nothing positioned REFUSES in words (seed $seed)', () {
      final scene = Scene()..calendar(frameId);
      final host = scene.object(title: 'Lunch');
      scene.place(frameId, civil(2026, 9, day, hour), event: host);
      // Two objects stapled only to each other: a loop places nothing, and there
      // is no instant to report.
      final left = scene.object(title: 'Left', duration: '0');
      final right = scene.object(title: 'Right', duration: '0');
      scene.staple(
        kind: 'anchor',
        ends: [ObjectEnd(left, point: 'start'), ObjectEnd(right, point: 'start')],
      );
      scene.staple(
        kind: 'anchor',
        ends: [ObjectEnd(right, point: 'end'), ObjectEnd(left, point: 'end')],
      );
      // What brings them into this query's universe is a SILENT staple to the
      // placed host -- all of the host is all of Left. It connects without
      // positioning, which is exactly the state under test: reachable, and
      // nowhere.
      scene.staple(ends: [ObjectEnd(host), ObjectEnd(left)]);

      final result = over(scene, day);
      final said = result.errors.map((error) => error.message).join(' | ');
      expect(
        result.errors.map((error) => error.source),
        contains(anyOf(left, right)),
        reason:
            'ISSUES (9.1): an object positioned only by connections that resolve '
            'back through it sits nowhere, and sitting nowhere in silence is the '
            'defect — it says so instead. Said: $said',
      );
    });

    test('an object with any placement of its own is never derived twice (seed $seed)', () {
      final world = ridingWorld(day, hour: hour);
      // The old shape: the companion placement beside the staple. It still
      // loads, still draws, and draws exactly ONCE.
      world.scene.place(frameId, civil(2026, 9, day, hour), event: world.rider);
      final facts = over(world.scene, day).facts;
      expect(facts.where((fact) => fact.event.id == world.rider), hasLength(1));
    });
  }
}
