// The edit-session draft's spec: the refcounted hold, the discard that is its
// own undo entry, and the convergence invariant on close.

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
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
    bench = await openEditor(scene.document, label: 'draft');
    return editor = bench.editor;
  }

  tearDown(() async => closeEditor(bench));

  Scene twoObjects() {
    final scene = Scene()..calendar(calendarId);
    scene.place(calendarId, civil(2026, 8, 3), title: 'One');
    scene.place(calendarId, civil(2026, 8, 4), title: 'Two');
    return scene;
  }

  test('N drafts hold autosave off exactly N times, and each releases its own', () async {
    await openScene(twoObjects());
    final ids = editor.document.events.keys.toList();
    expect(bench.store.deferrals, 0);
    final first = editor.beginDraft(ids[0]);
    final second = editor.beginDraft(ids[1]);
    expect(bench.store.deferrals, 2);
    // Idempotent per object: asking again is the same session, not a second hold.
    expect(identical(editor.beginDraft(ids[0]), first), isTrue);
    expect(bench.store.deferrals, 2);
    first.close();
    expect(bench.store.deferrals, 1);
    second.discard();
    expect(bench.store.deferrals, 0);
    // A release that runs twice cannot drive the count below zero.
    second.close();
    expect(bench.store.deferrals, 0);
  });

  test('closing an untouched card writes nothing and pushes no undo entry', () async {
    await openScene(twoObjects());
    final before = stateOf(editor.document);
    editor.beginDraft(editor.document.events.keys.first).close();
    expect(editor.canUndo, isFalse);
    expect(stateOf(editor.document), before);
  });

  test('a provisional object vanishes on discard, restoring the document', () async {
    await openScene(twoObjects());
    final before = recordsOf(editor.document);
    final id = editor.createAt(
      calendarId,
      editor.engine.coordinateDays(calendarId, civil(2026, 8, 10)),
      null,
    );
    final draft = editor.beginDraft(id, provisional: true);
    expect(editor.document.events.containsKey(id), isTrue);
    draft.discard();
    expect(editor.document.events.containsKey(id), isFalse);
    expect(
      editor.document.relations.values.where((relation) => relation.event == id),
      isEmpty,
      reason: 'the cascade took its placement',
    );
    expect(recordsOf(editor.document), before, reason: 'every record back as it was');
    expect(validateDocument(editor.document).errors, isEmpty);
  });

  test('the discard is its own undo entry, so an accidental one is recoverable', () async {
    await openScene(twoObjects());
    final id = editor.createAt(
      calendarId,
      editor.engine.coordinateDays(calendarId, civil(2026, 8, 10)),
      null,
    );
    editor.beginDraft(id, provisional: true).discard();
    expect(editor.history.length, 2, reason: 'the create, then the discard');
    expect(editor.undo(), isTrue);
    expect(editor.document.events.containsKey(id), isTrue);
  });

  // E1 (2026-08-28). A record nobody has authored yet reaches nothing: not the
  // document, not the undo stack, not the journal, not disk.
  group('a held record is a draft until the first authored value', () {
    Future<String> holdOne() async {
      await openScene(twoObjects());
      final held = editor.newObject('event', title: '');
      editor.beginDraft(held.id, provisional: true, holding: held);
      return held.id;
    }

    test('holding one writes nothing, and unrelated edits leave it held', () async {
      final held = await holdOne();
      final before = recordsOf(editor.document);
      expect(editor.document.events.containsKey(held), isFalse);
      expect(editor.canUndo, isFalse);
      // Someone else's edit runs over the seeded document and puts it back.
      editor.deleteObject(editor.document.events.keys.first);
      expect(editor.document.events.containsKey(held), isFalse);
      expect(editor.pending, contains(held));
      editor.undo();
      expect(recordsOf(editor.document), before);
    });

    test('closing it untouched leaves the document byte-identical', () async {
      final held = await holdOne();
      final before = stateOf(editor.document);
      editor.drafts[held]!.close();
      expect(stateOf(editor.document), before);
      expect(editor.canUndo, isFalse);
      expect(editor.pending, isEmpty);
      expect(bench.store.deferrals, 0);
    });

    test('the value and the record it belongs to are ONE entry', () async {
      final held = await holdOne();
      editor.transaction(
        'Name it',
        (d) => d.put('events', held, d.events[held]!.withField('color', '#123456')),
      );
      expect(editor.document.events[held]?.extra['color'], '#123456');
      expect(editor.history, hasLength(1));
      expect(editor.pending, isEmpty, reason: 'authored for good; no later edit weeds it');
      expect(editor.undo(), isTrue);
      expect(editor.document.events.containsKey(held), isFalse);
      expect(validateDocument(editor.document).errors, isEmpty);
    });

    test('a record merely POINTED AT is minted too', () async {
      final held = await holdOne();
      final placed = editor.placement(
        held,
        calendarId,
        editor.engine.coordinateDays(calendarId, civil(2026, 8, 11)),
        'placed',
      );
      editor.transaction('Place it', (d) => d.put('relations', placed.id, placed));
      expect(editor.document.events.containsKey(held), isTrue);
      expect(editor.history, hasLength(1));
      expect(validateDocument(editor.document).errors, isEmpty);
    });

    test('two cards hold two independent records', () async {
      await openScene(twoObjects());
      final ids = [for (var index = 0; index < 2; index++) editor.newObject('event', title: '')];
      for (final held in ids) {
        editor.beginDraft(held.id, provisional: true, holding: held);
      }
      expect(editor.pending.keys, unorderedEquals(ids.map((event) => event.id)));
      editor.transaction(
        'Name one',
        (d) => d.put('events', ids.first.id, d.events[ids.first.id]!.withField('color', '#abcdef')),
      );
      expect(editor.document.events.containsKey(ids.first.id), isTrue);
      expect(editor.document.events.containsKey(ids.last.id), isFalse);
      expect(editor.history, hasLength(1));
    });
  });

  test('closing an unchanged occurrence retires it and the projection reasserts', () async {
    final scene = Scene()..calendar(calendarId);
    scene.series(calendarId, {'FREQ': 'WEEKLY'}, at: civil(2026, 8, 3, 9, 0));
    await openScene(scene);
    List<Fact> facts() => editor.engine
        .queryFacts(Projection.of([calendarId]), start: civil(2026, 7, 1), end: civil(2026, 10, 1))
        .facts;
    final occurrence = facts().firstWhere((fact) => fact.virtualId.isNotEmpty);
    final virtualId = occurrence.virtualId;
    // "Edit this occurrence": materialized because the user asked, not as a side
    // effect of opening anything -- and it survives its own transaction.
    final parts = editor.materializeFact(occurrence);
    editor.commit('Edit one occurrence', parts.document);
    expect(editor.document.events.containsKey(parts.event), isTrue);
    expect(editor.document.overrides.values, hasLength(1));
    // Changing nothing and closing: the invariant retires the twin.
    editor.beginDraft(parts.event).close();
    expect(editor.document.events.containsKey(parts.event), isFalse);
    expect(editor.document.overrides.values, isEmpty);
    expect(
      facts().where((fact) => fact.virtualId == virtualId),
      hasLength(1),
      reason: 'the series says it again',
    );
    expect(validateDocument(editor.document).errors, isEmpty);
  });

  test('a real deviation survives its card closing', () async {
    final scene = Scene()..calendar(calendarId);
    scene.series(calendarId, {'FREQ': 'WEEKLY'}, at: civil(2026, 8, 3, 9, 0));
    await openScene(scene);
    final occurrence = editor.engine
        .queryFacts(Projection.of([calendarId]), start: civil(2026, 7, 1), end: civil(2026, 10, 1))
        .facts
        .firstWhere((fact) => fact.virtualId.isNotEmpty);
    final moved = editor.moveFact(occurrence, occurrence.day + Rational.one)!;
    editor.beginDraft(moved).close();
    expect(editor.document.events.containsKey(moved), isTrue);
    expect(editor.document.overrides.values, hasLength(1));
  });
}
