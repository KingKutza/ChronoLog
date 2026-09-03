// NEW, OPEN, DELETE: THE DOCUMENT HAS DOORS (ISSUES 9.2, Don's first report).
//
// "No clear mechanism to delete all the old data and start a new chronolog --
// I had to follow the path and delete the directory." Don's ruling: New is a
// fresh document at a new location (old files left in place) by default; Open
// reaches another chronolog ("sometimes it makes sense to have two chronologs");
// Delete-all is its own door behind a type-the-word confirmation -- "type the
// word, obliviate-style -- because full deletion is mostly a testing act but
// has legitimate cases and no undo."
//
// The typed word is `document.deleteWord`, a settings key: nothing here spells
// it. The deletion is asked of the disk the store writes to and of the document
// the app stands on afterwards, through the card as rendered.

import 'package:chronolog/cards/card_factory.dart';
import 'package:chronolog/cards/document_card.dart';
import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:chronolog/store/document_store.dart';
import 'package:chronolog/store/journal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../cards/harness.dart';
import '../cards/object_harness.dart';
import '../store/harness.dart';

typedef DoorBench = ({Editor editor, DocumentStore store, MemoryFiles disk, Chrome chrome, CardFactory factory});

/// A bench whose disk is visible, with one authored event SAVED to it, so there
/// are bytes for the door to delete.
Future<DoorBench> openWithBytes() async {
  final disk = MemoryFiles();
  final store = DocumentStore(
    dataRoot: 'memory',
    files: disk,
    scheduler: ManualScheduler(),
    establish: createEmptyWorkspaceDocument,
  );
  await store.load();
  final settings = chronologSettings();
  final editor = Editor(store, settings: settings.tunable);
  final calendar = editor.document.frames.values.firstWhere((f) => f.traits.contains('temporal')).id;
  editor.createAt(calendar, Rational.fromInt(20500), Rational.fromInt(20500) + Rational.fromInt(1, 24));
  await store.save(force: true);
  final views = ViewBook();
  final stage = Stage(tunable: settings.tunable, onLens: views.setLens);
  return (
    editor: editor,
    store: store,
    disk: disk,
    chrome: Chrome(settings: settings, stage: stage, views: views, editor: editor),
    factory: CardFactory(editor, settings, stage),
  );
}

Future<void> pumpDocument(WidgetTester tester, DoorBench bench) => pumpCard(
  tester,
  bench.chrome,
  CardHost(
    factory: bench.factory,
    request: const (klass: 'document', id: null, kind: null, frameId: null, startDays: null, endDays: null),
    tileId: 'card:document:one',
    // A whole card shell wants a BOUNDED height -- it scrolls its own body.
    child: SizedBox(height: cardSurface.height, child: const DocumentCard()),
  ),
);

void main() {
  testWidgets('the document card offers New, Open and Delete-all', (tester) async {
    final bench = (await tester.runAsync(() => openCards(createEmptyWorkspaceDocument())))!;
    await pumpCard(tester, bench.chrome, const DocumentCard());
    expect(
      find.textContaining(RegExp('new chronolog|new document', caseSensitive: false)),
      findsWidgets,
      reason: 'ISSUES 9.2: no door mints an empty document; `relocate` and `replaceDocument` exist unused',
    );
    expect(
      find.textContaining(RegExp(r'\bopen\b', caseSensitive: false)),
      findsWidgets,
      reason: 'ISSUES 9.2: no door opens a different location\'s chronolog',
    );
    expect(
      find.textContaining(RegExp('delete all', caseSensitive: false)),
      findsWidgets,
      reason:
          'ISSUES 9.2 (Don: option b behind a type-the-word popup): a full-deletion door, '
          'explicitly destructive, never silent.',
    );
  });

  testWidgets('delete-all requires the typed word and leaves nothing behind', (tester) async {
    // "A full deletion door ('delete all data, start clean as of a fresh
    // install') behind a type-to-confirm popup." The wrong word does nothing at
    // all; the right word takes the snapshot and the journal off the disk and
    // stands the app on an empty document -- two structural frames and nothing
    // else, which is what a first run establishes.
    final bench = (await tester.runAsync(openWithBytes))!;
    final word = bench.chrome.settings.text('document.deleteWord');
    expect(word, isNotEmpty, reason: 'the word is a settings key');
    expect(bench.disk.find(snapshotFileName) ?? bench.disk.find(journalFileName), isNotNull, reason: 'there are bytes to delete');
    final before = bench.editor.document;
    expect(before.events, isNotEmpty);
    await pumpDocument(tester, bench);
    await tapPart(tester, 'Delete all data');
    final field = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          (widget.decoration?.hintText ?? '').toLowerCase().contains('type'),
    );
    expect(field, findsOneWidget, reason: 'the door asks for the word, in a field that says so');
    // The wrong word: nothing changes, on disk or in the document.
    await tester.enterText(field, '$word-not');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Delete all data…'), warnIfMissed: false);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(bench.editor.document.events.keys, equals(before.events.keys), reason: 'the wrong word deletes nothing');
    expect(bench.disk.find(snapshotFileName) ?? bench.disk.find(journalFileName), isNotNull, reason: 'and touches no file');
    // The word itself.
    await tester.enterText(field, word);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Delete all data…'), warnIfMissed: false);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pumpAndSettle();
    // "Start clean as of a fresh install": the old snapshot and journal are
    // erased, and what a first run establishes stands in their place -- so no
    // byte of the old document survives on disk, and the journal starts again.
    final snapshot = bench.disk.find(snapshotFileName);
    for (final id in before.events.keys) {
      expect(
        snapshot ?? '',
        isNot(contains(id)),
        reason: 'ISSUES 9.2: the old snapshot at the data root still names $id -- it was not erased',
      );
    }
    final journal = (bench.disk.find(journalFileName) ?? '').trim();
    expect(journal, isEmpty, reason: 'the journal is gone or empty: nothing to replay');
    expect(bench.store.seq, equals(0), reason: 'and the sequence starts again, as a fresh install does');
    final after = bench.editor.document;
    expect(after.events, isEmpty, reason: 'the app stands on an empty document');
    expect(
      after.frames.keys.toSet(),
      equals(createEmptyWorkspaceDocument().frames.keys.toSet()),
      reason: 'two structural frames and nothing else -- a fresh install',
    );
  });
}
