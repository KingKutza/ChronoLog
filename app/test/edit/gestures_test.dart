// The gesture write-path's spec.
//
// The surfaces are not here; what is here is what a drag MEANS. Every case runs
// against a real projection engine, so a materialization the engine cannot
// reassert would fail rather than pass on a hand-written stub.

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/object_kinds.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/staples.dart';
import 'package:chronolog/core/validate.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:test/test.dart';

import '../helpers/projection_scene.dart';
import 'harness.dart';

const String calendarId = 'calendar:work';

void main() {
  late Bench bench;
  late Editor editor;

  Future<Editor> openScene(Scene scene) async {
    bench = await openEditor(scene.document, label: 'gesture');
    return editor = bench.editor;
  }

  tearDown(() async => closeEditor(bench));

  Scene workCalendar() => Scene()..calendar(calendarId);

  Rational dayOf(int year, int month, int day) =>
      editor.engine.coordinateDays(calendarId, civil(year, month, day));

  List<Fact> facts() => editor.engine
      .queryFacts(Projection.of([calendarId]), start: civil(2026, 7, 1), end: civil(2026, 10, 1))
      .facts;

  group('create', () {
    test('a drag places the object under THAT frame\'s law, with the drag\'s duration', () async {
      await openScene(workCalendar());
      final start = dayOf(2026, 8, 3);
      final id = editor.createAt(calendarId, start, start + Rational.fromInt(1, 2));
      final placement = editor.document.relations.values.firstWhere(
        (relation) => isPlacement(relation, id),
      );
      expect(placement.frame, calendarId);
      expect(editor.engine.coordinateDays(calendarId, placement.coordinate), start);
      // Half a day of this frame's own seconds, asked of the measure law rather
      // than of a constant.
      expect(editor.engine.eventDurationDays(editor.document.events[id]), Rational.fromInt(1, 2));
      expect(validateDocument(editor.document).errors, isEmpty);
    });

    test('a zero-duration kind takes none however far the drag went', () async {
      await openScene(workCalendar());
      final start = dayOf(2026, 8, 3);
      final id = editor.createAt(calendarId, start, start + Rational.one, kind: 'todo');
      expect(editor.engine.eventDurationDays(editor.document.events[id]).isZero, isTrue);
      expect(objectKindForEvent(editor.document.events[id]), 'todo');
    });

    test('a drag with no span gives a spanning kind the shipped default', () async {
      await openScene(workCalendar());
      final start = dayOf(2026, 8, 3);
      final id = editor.createAt(calendarId, start, start);
      expect(
        editor.engine.eventDurationDays(editor.document.events[id]),
        editor.setting('edit.newSpanDays'),
      );
    });
  });

  group('move', () {
    Scene weekly() {
      final scene = workCalendar();
      scene.series(calendarId, {'FREQ': 'WEEKLY'}, at: civil(2026, 8, 3, 9, 0));
      return scene;
    }

    test('dragging a generated occurrence materializes it, and the slot is suppressed', () async {
      await openScene(weekly());
      final occurrence = facts().firstWhere((fact) => fact.virtualId.isNotEmpty);
      final virtualId = occurrence.virtualId;
      final moved = editor.moveFact(occurrence, occurrence.day + Rational.one);
      expect(moved, isNotNull);
      expect(editor.document.events[moved]!.traits, isNot(contains('generated')));
      expect(
        editor.document.overrides.values.where(
          (override) => override.virtualId == virtualId && override.suppress,
        ),
        hasLength(1),
      );
      expect(validateDocument(editor.document).errors, isEmpty);
      // The series no longer projects that slot; the authored twin stands in it.
      final after = facts();
      expect(after.where((fact) => fact.virtualId == virtualId), isEmpty);
      expect(after.where((fact) => fact.event.id == moved), hasLength(1));
    });

    test('dropping it back within half a grain restores the series', () async {
      await openScene(weekly());
      final occurrence = facts().firstWhere((fact) => fact.virtualId.isNotEmpty);
      final home = occurrence.day;
      final moved = editor.moveFact(occurrence, home + Rational.one)!;
      final materialized = facts().firstWhere((fact) => fact.event.id == moved);
      expect(editor.moveFact(materialized, home), isNull, reason: 'nothing carries it now');
      expect(editor.document.events.containsKey(moved), isFalse, reason: 'the twin is gone');
      expect(editor.document.overrides.values, isEmpty, reason: 'the slot is unsuppressed');
      expect(
        facts().where((fact) => fact.day == home && fact.virtualId.isNotEmpty),
        hasLength(1),
        reason: 'the projection reasserted',
      );
      expect(validateDocument(editor.document).errors, isEmpty);
    });

    test('an explicit placement keeps its own frame and moves under that law', () async {
      final scene = workCalendar();
      final relationId = scene.place(calendarId, civil(2026, 8, 3, 9, 0), title: 'Standup');
      await openScene(scene);
      final fact = facts().firstWhere((fact) => fact.relation.id == relationId);
      final target = fact.day + Rational.fromInt(3);
      expect(editor.moveFact(fact, target, timed: true), fact.event.id);
      final moved = editor.document.relations[relationId]!;
      expect(editor.engine.coordinateDays(calendarId, moved.coordinate), target);
      expect(obj(moved.extra['parameters'])?['dateOnly'], isFalse);
      expect(editor.undo(), isTrue);
      expect(
        editor.engine.coordinateDays(calendarId, editor.document.relations[relationId]!.coordinate),
        fact.day,
      );
    });
  });

  group('state', () {
    Scene withTodo() {
      final scene = workCalendar();
      scene.place(calendarId, civil(2026, 8, 3), title: 'Ship it');
      return scene;
    }

    test('entering a state writes a membership and the terminal end staple', () async {
      final scene = withTodo();
      await openScene(scene);
      final objectId = editor.document.events.keys.first;
      editor.toggleState(objectId, doneStateFrameId);
      final facts = ObjectFacts(editor.document);
      expect(facts.doneAffiliation(objectId), isNotNull);
      expect(facts.objectEndStaple(objectId), isNotNull);
      expect(isStateFrame(editor.document.frames[doneStateFrameId]), isTrue);
      expect(validateDocument(editor.document).errors, isEmpty);
    });

    test('undo removes the lazily minted state frame', () async {
      await openScene(withTodo());
      final objectId = editor.document.events.keys.first;
      expect(editor.document.frames.containsKey(doneStateFrameId), isFalse, reason: 'never seeded');
      editor.toggleState(objectId, doneStateFrameId);
      expect(editor.document.frames.containsKey(doneStateFrameId), isTrue);
      expect(editor.undo(), isTrue);
      expect(editor.document.frames.containsKey(doneStateFrameId), isFalse);
    });

    test('toggling twice returns the document to where it started', () async {
      final scene = withTodo();
      await openScene(scene);
      final before = stateOf(editor.document);
      final objectId = editor.document.events.keys.first;
      editor.toggleState(objectId, doneStateFrameId);
      editor.toggleState(objectId, doneStateFrameId);
      final facts = ObjectFacts(editor.document);
      expect(facts.stateAffiliations(objectId), isEmpty);
      expect(facts.objectEndStaple(objectId), isNull, reason: 'the instant went with the state');
      // The Done frame stays: it is authored now, and a frame the user may have
      // retitled is not unmade by leaving it.
      expect(editor.document.frames.containsKey(doneStateFrameId), isTrue);
      expect(stateOf(editor.document), isNot(before));
      expect(editor.document.relations.length, editor.document.relations.length);
    });

    test('a second state reuses the one end staple this object already has', () async {
      await openScene(withTodo());
      final objectId = editor.document.events.keys.first;
      editor.toggleState(objectId, doneStateFrameId);
      final first = ObjectFacts(editor.document).objectEndStaple(objectId);
      editor.toggleState(objectId, 'frame:state-archived', title: 'Archived');
      expect(ObjectFacts(editor.document).objectEndStaple(objectId)!.id, first!.id);
      expect(ObjectFacts(editor.document).stateAffiliations(objectId), hasLength(2));
    });
  });

  test('containment passes no judgment, and is undoable', () async {
    final scene = workCalendar();
    final parent = scene.object(title: 'Project');
    final child = scene.object(title: 'Step');
    await openScene(scene);
    editor.setContains(parent, child, true);
    expect(ObjectFacts(editor.document).children(parent), [child]);
    editor.setContains(parent, child, true);
    expect(editor.history.length, 1, reason: 'saying it twice says it once');
    editor.setContains(parent, parent, true);
    expect(editor.history.length, 1, reason: 'a thing containing itself says nothing');
    editor.setContains(parent, child, false);
    expect(ObjectFacts(editor.document).children(parent), isEmpty);
    expect(validateDocument(editor.document).errors, isEmpty);
  });
}
