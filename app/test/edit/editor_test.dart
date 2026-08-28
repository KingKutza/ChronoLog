// The transaction model's spec.
//
// Properties over seeded generation, never pinned counts: the corpus is the same
// document the model core's own spec runs on, so a cascade that breaks a real
// shape breaks here.

import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/ops.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/validate.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:test/test.dart';

import '../core/corpus.dart';
import 'harness.dart';

void main() {
  late Bench bench;
  late Editor editor;

  Future<void> openOn(Document document) async {
    bench = await openEditor(document);
    editor = bench.editor;
  }

  tearDown(() async => closeEditor(bench));

  /// One retitling per object, committed through the one door.
  List<String> retitleEverything(Editor editor) {
    final states = <String>[stateOf(editor.document)];
    for (final id in editor.document.events.keys.toList()) {
      final event = editor.document.events[id]!;
      editor.commit(
        'Retitle',
        editor.document.put('events', id, event.copyWith(payload: {'title': 'retitled $id'})),
      );
      states.add(stateOf(editor.document));
    }
    return states;
  }

  group('history', () {
    test('undo after do is identity on the document, for a whole walk of edits', () async {
      await openOn(Corpus(specSeed).document());
      final states = retitleEverything(editor);
      for (var index = states.length - 1; index > 0; index -= 1) {
        expect(editor.undo(), isTrue);
        expect(stateOf(editor.document), states[index - 1], reason: 'undo $index');
      }
      expect(editor.undo(), isFalse, reason: 'nothing left to undo');
    });

    test('redo after undo after do is do', () async {
      await openOn(Corpus(specSeed + 1).document());
      final states = retitleEverything(editor);
      while (editor.undo()) {}
      for (var index = 1; index < states.length; index += 1) {
        expect(editor.redo(), isTrue);
        expect(stateOf(editor.document), states[index], reason: 'redo $index');
      }
      expect(editor.redo(), isFalse);
    });

    test('undo and redo are FORWARD journal entries, never a rewind', () async {
      await openOn(Corpus(specSeed + 2).document());
      final id = editor.document.events.keys.first;
      editor.commit(
        'Retitle',
        editor.document.put(
          'events',
          id,
          editor.document.events[id]!.copyWith(payload: {'title': 'moved'}),
        ),
      );
      final afterEdit = bench.store.journal.seq;
      expect(bench.store.pending, isTrue);
      editor.undo();
      editor.redo();
      // The store still holds every entry: three edits are pending, not one
      // edit and two rewinds of it.
      expect(bench.store.pending, isTrue);
      expect(bench.store.journal.seq, afterEdit, reason: 'nothing was written yet');
    });

    test('an edit that changes nothing writes nothing and pushes no undo entry', () async {
      await openOn(Corpus(specSeed + 3).document());
      final before = stateOf(editor.document);
      editor.commit('No-op', editor.document);
      expect(editor.canUndo, isFalse);
      expect(stateOf(editor.document), before);
    });

    test('the history depth is a tunable, and the oldest entry falls off it', () async {
      final document = Corpus(specSeed + 4).document();
      final root = await openEditor(document, label: 'depth');
      final small = Editor(root.store, settings: (key) => Rational.fromInt(2));
      for (var index = 0; index < 5; index += 1) {
        small.commit('Probe $index', small.document.put('meta', 'probe', '$index'));
      }
      expect(small.history.length, 2);
      await closeEditor(root);
      bench = await openEditor(document);
      editor = bench.editor;
    });
  });

  group('cascades', () {
    test('deleting any object leaves no dangling reference, in one undo entry', () async {
      for (final seed in [specSeed, specSeed + 5, specSeed + 6]) {
        final document = Corpus(seed).document();
        expect(validateDocument(document).errors, isEmpty, reason: 'the corpus starts valid');
        for (final id in document.events.keys) {
          bench = await openEditor(document, label: 'delete');
          editor = bench.editor;
          final before = stateOf(editor.document);
          editor.deleteObject(id);
          expect(editor.refusals, isEmpty, reason: 'deleting $id');
          expect(editor.document.events.containsKey(id), isFalse);
          expect(validateDocument(editor.document).errors, isEmpty, reason: 'after deleting $id');
          expect(editor.history.length, 1, reason: 'the cascade rode in ONE entry');
          expect(editor.undo(), isTrue);
          expect(stateOf(editor.document), before, reason: 'undo restores the whole cascade');
          await closeEditor(bench);
        }
      }
      bench = await openEditor(const Document());
      editor = bench.editor;
    });

    test('deleting a frame takes its attachments and refuses to orphan content', () async {
      final document = Corpus(specSeed + 7).document();
      for (final id in document.frames.keys) {
        bench = await openEditor(document, label: 'frame');
        editor = bench.editor;
        editor.deleteFrame(id);
        if (editor.refusals.isNotEmpty) {
          // Refuse loudly, never guess: a frame another frame or object is built
          // on is not deleted quietly, and the edit did not land.
          expect(editor.document.frames.containsKey(id), isTrue);
          expect(editor.canUndo, isFalse);
        } else {
          expect(validateDocument(editor.document).errors, isEmpty, reason: 'after $id');
          for (final relation in editor.document.relations.values) {
            expect(relation.frame, isNot(id));
            expect(relation.group, isNot(id));
          }
        }
        await closeEditor(bench);
      }
      bench = await openEditor(const Document());
      editor = bench.editor;
    });

    test('a removed pattern takes its overrides with it', () async {
      final document = Corpus(specSeed + 8).document();
      await openOn(document);
      for (final id in document.patterns.keys) {
        editor.commitOps('Delete series', [delOp('patterns', id)]);
        expect(editor.refusals, isEmpty);
        for (final override in editor.document.overrides.values) {
          expect(overridePatternId(override), isNot(id));
        }
      }
      expect(validateDocument(editor.document).errors, isEmpty);
    });
  });

  test('resync forgets a history that describes a document that is gone', () async {
    await openOn(Corpus(specSeed + 9).document());
    editor.commit('Probe', editor.document.put('meta', 'probe', '1'));
    expect(editor.canUndo, isTrue);
    editor.resync();
    expect(editor.canUndo, isFalse);
    expect(editor.canRedo, isFalse);
  });
}
