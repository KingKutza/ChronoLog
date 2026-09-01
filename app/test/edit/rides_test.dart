// "NEW TODO HERE", WHERE HERE IS THE OBJECT (ISSUES 9.1).
//
// "Right-clicked an event, chose 'New todo here', and it authored an anchor to
// Wall Time -- not to the event under the pointer... The todo wants a staple to
// the event (directional, the todo's point identified with the event's), so it
// rides if the event moves -- anchoring to the frame instead bakes in a position
// that goes stale the moment the event is re-said."
//
// The staple half landed first, but the companion frame placement was still
// written beside it so the todo would render. That companion IS the baked-in
// coordinate the report names: it says a second time, in a form that cannot
// ride, what the staple already said. The substrate reads a position out of the
// staple now, so the create mints one sentence and only one.

import 'dart:math';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/staples.dart';
import 'package:chronolog/core/validate.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:test/test.dart';

import '../core/corpus.dart';
import '../helpers/projection_scene.dart';
import 'harness.dart';

const String calendarId = 'calendar:work';

void main() {
  late Bench bench;
  late Editor editor;

  Future<Editor> openScene(Scene scene) async {
    bench = await openEditor(scene.document, label: 'rides');
    return editor = bench.editor;
  }

  tearDown(() async => closeEditor(bench));

  Rational dayOf(int year, int month, int day) =>
      editor.engine.coordinateDays(calendarId, civil(year, month, day));

  List<Fact> facts() => editor.engine
      .queryFacts(
        Projection.of(const [calendarId]),
        start: civil(2026, 7, 1),
        end: civil(2026, 10, 1),
      )
      .facts;

  Rational dayOfObject(String id) => facts().firstWhere((fact) => fact.event.id == id).day;

  for (final seed in seeds(5)) {
    final random = Random(seed);
    final day = 2 + random.nextInt(20);

    test('a create said ON an object writes the staple and NO companion placement '
        '(seed $seed)', () async {
      final scene = Scene()..calendar(calendarId);
      final host = scene.object(title: 'Lunch');
      scene.place(calendarId, civil(2026, 8, day, 12), event: host);
      await openScene(scene);

      final todo = editor.createAt(
        calendarId,
        dayOf(2026, 8, day),
        null,
        kind: 'todo',
        stapledTo: host,
      );

      expect(
        editor.document.relations.values.where((r) => isPlacement(r, todo)),
        isEmpty,
        reason:
            'ISSUES (9.1): the staple already said where the todo is, and a frame '
            'coordinate beside it is the stale position the report names.',
      );
      expect(
        editor.staples.staplesForObject(todo),
        hasLength(1),
        reason: 'one act, one sentence',
      );
      expect(validateDocument(editor.document).errors, isEmpty);
      // And it draws, from the sentence alone.
      expect(dayOfObject(todo), dayOfObject(host));
    });

    test('the todo rides when the event is moved (seed $seed)', () async {
      final scene = Scene()..calendar(calendarId);
      final host = scene.object(title: 'Lunch');
      scene.place(calendarId, civil(2026, 8, day, 12), event: host);
      await openScene(scene);

      final todo = editor.createAt(
        calendarId,
        dayOf(2026, 8, day),
        null,
        kind: 'todo',
        stapledTo: host,
      );
      final before = dayOfObject(todo);
      // The RIDER's own records. Every connection is a staple now, so "a staple"
      // is no longer a way to say "not the placement": what this test is about
      // is that nothing naming the TODO was rewritten.
      final riderRecords = {
        for (final entry in editor.document.relations.entries)
          if (entry.value.ends.any((end) => end.id == todo)) entry.key: entry.value,
      };

      final hostFact = facts().firstWhere((fact) => fact.event.id == host);
      editor.moveFact(hostFact, hostFact.day - Rational.fromInt(2));

      expect(
        dayOfObject(todo),
        before - Rational.fromInt(2),
        reason:
            'ISSUES (9.1): "so it rides if the event moves" — the rider was never '
            'touched, and it is somewhere else, because the sentence is somewhere '
            'else.',
      );
      for (final entry in riderRecords.entries) {
        expect(editor.document.relations[entry.key], entry.value);
      }
    });

    test('a create said on EMPTY SPACE still places on the frame (seed $seed)', () async {
      final scene = Scene()..calendar(calendarId);
      await openScene(scene);
      final start = dayOf(2026, 8, day);
      final id = editor.createAt(calendarId, start, null, kind: 'todo');

      final placement = editor.document.relations.values.singleWhere(
        (relation) => isPlacement(relation, id),
      );
      expect(
        placement.frame,
        calendarId,
        reason:
            'over nothing, the pointer\'s coordinate IS the whole sentence — the '
            'frame placement is not being retired, it is being kept for where it '
            'is the only thing said.',
      );
      // Its ONLY sentence is that placement -- which is a staple like every
      // other connection (ruled 2026-09-01), so the claim is that there is no
      // SECOND one, not that there are none.
      expect(editor.staples.staplesForObject(id), hasLength(1));
      expect(isPlacement(editor.staples.staplesForObject(id).single, id), isTrue);
      expect(dayOfObject(id), start);
    });

    test('one act is one undo entry, whichever sentence it wrote (seed $seed)', () async {
      final scene = Scene()..calendar(calendarId);
      final host = scene.object(title: 'Lunch');
      scene.place(calendarId, civil(2026, 8, day, 12), event: host);
      await openScene(scene);
      final before = recordsOf(editor.document);

      editor.createAt(calendarId, dayOf(2026, 8, day), null, kind: 'todo', stapledTo: host);
      expect(editor.undo(), isTrue);
      expect(recordsOf(editor.document), before);
    });
  }
}
