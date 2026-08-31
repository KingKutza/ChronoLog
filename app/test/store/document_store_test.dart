// The autosave flow's spec.
//
// The store-side rulings of the JavaScript's history spec ride here: the
// debounce batches a burst into one write with one entry per commit, an explicit
// force is never downgraded by coalescing, deferral is refcounted EXACTLY -- N
// holds need N releases -- and undo and redo persist as forward entries.
//
// No case sleeps. The debounce runs on a clock the spec moves, and the writes
// run through a file seam the spec can gate and break on demand.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:chronolog/core/ops.dart';
import 'package:chronolog/store/data_dir.dart';
import 'package:chronolog/store/document_store.dart';
import 'package:chronolog/store/journal.dart';
import 'package:chronolog/store/seams.dart';
import 'package:test/test.dart';

import '../core/corpus.dart';
import 'harness.dart';

void main() {
  late Directory root;
  late ManualScheduler scheduler;

  setUp(() async {
    root = await tempRoot('autosave');
    scheduler = ManualScheduler();
  });
  tearDown(() async => removeRoot(root));

  DocumentStore open({
    StoreFiles files = const IoStoreFiles(),
    void Function(SaveStatus)? onStatus,
  }) => DocumentStore(dataRoot: root.path, files: files, scheduler: scheduler, onStatus: onStatus);

  /// The debounce, fired on the spec's clock, waited on properly.
  Future<void> fire(DocumentStore store) async {
    await scheduler.advance(store.delay);
    await store.inFlight;
  }

  /// The journal as it stands on disk. An absent file is an empty journal:
  /// nothing has been appended yet, which is a state and not an error.
  List<JournalEntry> written() {
    final file = File(storePath(root.path, journalFileName));
    return parseJournal(file.existsSync() ? file.readAsBytesSync() : const []).entries;
  }

  test('the debounce batches several commits into one write, one entry per commit', () async {
    final files = InstrumentedFiles();
    final store = open(files: files);
    await store.load();
    final base = files.steps.length;
    store.commit('Create event', store.document.put('meta', 'one', '1'));
    store.commit('Edit event', store.document.put('meta', 'one', '2'));
    store.commit('Create event', store.document.put('meta', 'two', '3'));
    expect(store.pending, isTrue);
    expect(written(), isEmpty, reason: 'nothing is written before the debounce fires');

    await fire(store);
    final appends = files.steps.sublist(base).where((step) => step == 'appendSynced');
    expect(appends, hasLength(1), reason: 'one write for the whole burst');
    final entries = written();
    expect(entries, hasLength(3), reason: 'each commit keeps its own entry and label');
    expect(
      [for (final entry in entries) entry.label],
      ['Create event', 'Edit event', 'Create event'],
    );
    expect([for (final entry in entries) entry.seq], [1, 2, 3]);
    expect(store.pending, isFalse);
    expect(store.status.state, SaveState.clean);
  });

  test('overlapping saves are serialized into one follow-up write', () async {
    final gate = Completer<void>();
    var gated = 0;
    final store = open(
      files: InstrumentedFiles(
        before: (step, index) async {
          if (step == 'appendSynced' && gated++ == 0) await gate.future;
        },
      ),
    );
    await store.load();
    store.commit('one', store.document.put('meta', 'one', '1'));
    final first = store.save();
    await scheduler.pump();
    store.commit('two', store.document.put('meta', 'two', '2'));
    final second = store.save();
    final third = store.save();
    expect(identical(second, third), isTrue, reason: 'a third request joins the one follow-up');
    gate.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect([for (final entry in written()) entry.label], ['one', 'two']);
    expect(store.pending, isFalse);
  });

  test('an explicit force is carried through the coalescing and never downgraded', () async {
    Future<int> run({required bool forceTheFollowUp}) async {
      final directory = await tempRoot('force');
      try {
        final gate = Completer<void>();
        var gated = 0;
        final store = DocumentStore(
          dataRoot: directory.path,
          scheduler: ManualScheduler(),
          files: InstrumentedFiles(
            before: (step, index) async {
              if (step == 'appendSynced' && gated++ == 0) await gate.future;
            },
          ),
        );
        await store.load();
        store.commit('A', store.document.put('meta', 'a', '1'));
        // A draft opens: ordinary autosave is held off, "Save now" is not.
        store.beginDeferred();
        final first = store.save(force: true);
        await Future<void>.delayed(Duration.zero);
        store.commit('B', store.document.put('meta', 'b', '2'));
        final second = store.save();
        final third = store.save(force: forceTheFollowUp);
        expect(identical(second, third), isTrue);
        gate.complete();
        expect(await first, isTrue);
        await second;
        return store.journal.entryCount;
      } finally {
        await removeRoot(directory);
      }
    }

    expect(
      await run(forceTheFollowUp: true),
      2,
      reason: 'the queued follow-up carried the force, so "Save now" wrote through the draft',
    );
    expect(
      await run(forceTheFollowUp: false),
      1,
      reason: 'without a force the follow-up is an ordinary autosave and the draft holds it',
    );
  });

  test('draft deferral holds edits until the draft resolves', () async {
    final store = open();
    await store.load();
    store.beginDeferred();
    store.commit('Draft edit', store.document.put('meta', 'draft', '1'));
    expect(await store.save(), isFalse);
    expect(written(), isEmpty, reason: 'a draft in progress writes nothing');
    expect(store.pending, isTrue);
    expect(scheduler.armed, 0, reason: 'and no timer is left armed behind it');

    store.endDeferred();
    expect(scheduler.armed, 1, reason: 'the release re-arms the debounce');
    await fire(store);
    expect(written(), hasLength(1), reason: 'the accumulated ops go out on commit');
  });

  test('a cancelled draft releases autosave exactly once even when close paths repeat', () async {
    final store = open();
    await store.load();
    store.beginDeferred();
    store.commit('Draft edit', store.document.put('meta', 'draft', '1'));
    store.endDeferred(); // Cancel resolves the draft.
    store.endDeferred(); // The click-away after cancel is harmless.
    store.endDeferred();
    expect(store.deferrals, 0);
    expect(await store.save(), isTrue);
    expect(written(), hasLength(1));
  });

  test('N holds need N releases, whatever order they arrive in and whatever throws', () async {
    final store = open();
    for (final seed in seeds(120)) {
      final random = Random(seed);
      var holds = 0;
      for (var step = 0; step < 24; step += 1) {
        switch (random.nextInt(3)) {
          case 0:
            store.beginDeferred();
            holds += 1;
          case 1:
            if (holds > 0) holds -= 1;
            store.endDeferred();
          case 2:
            // A draft whose body throws still releases its own hold, and only
            // its own: the `finally` is the whole guarantee.
            try {
              await store.deferring<void>(() async => throw StateError('cancelled'));
            } on StateError {
              // Expected.
            }
        }
        expect(store.deferrals, holds, reason: 'seed $seed step $step');
      }
      for (var extra = 0; extra < holds + 3; extra += 1) {
        store.endDeferred();
      }
      expect(store.deferrals, 0, reason: 'seed $seed: releases can never drive it negative');
    }
  });

  test('undo and redo persist as forward entries', () async {
    final store = open();
    final boot = await store.load();
    final before = mapSnapshot(boot.document);
    final renamed = boot.document.put('meta', 'title', 'Renamed');
    final bundle = bundleOps(before, mapSnapshot(renamed));
    store.commit('Rename', renamed);
    expect(await store.save(force: true), isTrue);

    store.collect('Undo Rename', bundle.inverseOps);
    expect(await store.save(force: true), isTrue);
    expect(store.document, boot.document, reason: 'the undo is applied, not rewound');
    expect(store.journal.entryCount, 2, reason: 'a journal is a history; history does not shrink');

    final undone = await JournalStore(dataRoot: root.path).load();
    expect(undone.document, boot.document);
    expect(undone.replayed, 2);

    store.collect('Redo Rename', bundle.ops);
    expect(await store.save(force: true), isTrue);
    final redone = await JournalStore(dataRoot: root.path).load();
    expect(redone.document, renamed);
    expect(redone.replayed, 3);
  });

  test('a failed write hands the ops back so no edit is lost', () async {
    final store = open(
      files: InstrumentedFiles(
        before: (step, index) async {
          if (step == 'appendSynced') throw StateError('disk on fire');
        },
      ),
    );
    await store.load();
    store.commit('Create event', store.document.put('meta', 'one', '1'));
    expect(await store.save(force: true), isFalse);
    expect(store.pending, isTrue, reason: 'the pending ops survive a failed write');
    expect(store.seq, 0, reason: 'and the sequence number does not advance');
    expect(store.status.state, SaveState.error);
    expect(store.status.error, isA<StateError>());
  });

  test('the status vocabulary is five states and no more', () async {
    final seen = <SaveState>[];
    final store = open(onStatus: (status) => seen.add(status.state));
    await store.load();
    store.commit('Edit', store.document.put('meta', 'one', '1'));
    await fire(store);
    await store.close();
    expect(seen, contains(SaveState.loading));
    expect(seen, contains(SaveState.clean));
    expect(seen, contains(SaveState.dirty));
    expect(seen, contains(SaveState.saving));
    expect(seen.toSet().length, lessThanOrEqualTo(SaveState.values.length));
    expect(store.status.dirty, isFalse);
    expect(store.status.seq, store.seq);
  });

  test('replacing the document drops the ops that described the old one', () async {
    final store = open();
    await store.load();
    store.commit('Edit', store.document.put('meta', 'one', '1'));
    final replacement = Corpus(specSeed).document();
    await store.replaceDocument(replacement);
    expect(store.pending, isFalse);
    expect(store.journal.entryCount, 0);
    final reload = await JournalStore(dataRoot: root.path).load();
    expect(reload.document, replacement);
    expect(reload.replayed, 0);
  });

  test('a compaction writes pending edits first, then folds', () async {
    final store = open();
    await store.load();
    for (var index = 0; index < 4; index += 1) {
      store.commit('Edit $index', store.document.put('meta', 'probe-$index', '$index'));
    }
    final folded = await store.compact();
    expect(folded, 4, reason: 'the pending edits were written before the fold, not after it');
    expect(store.journal.entryCount, 0);
    final reload = await JournalStore(dataRoot: root.path).load();
    expect(reload.document, store.document);
    expect(reload.replayed, 0);
  });

  test('a reopened store is the document the live one held', () async {
    for (final seed in seeds(24)) {
      final directory = await tempRoot('reopen');
      try {
        final clock = ManualScheduler();
        final store = DocumentStore(
          dataRoot: directory.path,
          scheduler: clock,
          establish: () => Corpus(seed).document(),
        );
        await store.load();
        final edits = randomEdits(seed, store.document, 9);
        final random = Random(seed);
        for (final edit in edits) {
          store.collect(edit.label, edit.ops);
          // Sometimes let the debounce fire, sometimes pile the next edit on
          // top of it: the reopened document cannot depend on which.
          if (random.nextBool()) {
            await clock.advance(store.delay);
            await store.inFlight;
          }
        }
        await store.close();
        final reload = await JournalStore(dataRoot: directory.path).load();
        expect(reload.document, store.document, reason: 'seed $seed');
        expect(store.pending, isFalse, reason: 'seed $seed');
      } finally {
        await removeRoot(directory);
      }
    }
  });

  // --- THE SAVE LOCATION IS THE USER'S TO CHOOSE (Don, 8.31) -----------------
  //
  // "I don't appear to be able to set a save location." A move is not a file
  // copy: the document is written at the new place through the SAME journal
  // machinery, so "saves are updates, not overwrites" survives the move, and a
  // directory another chronolog occupies is refused in words rather than
  // replaced -- there is no confirmation dialog anywhere to ask with.

  test('a move writes the document at the chosen place and keeps saving there', () async {
    final chosen = await tempRoot('moved-to');
    addTearDown(() => removeRoot(chosen));
    final store = open();
    await store.load();
    store.commit('Before the move', store.document.put('meta', 'one', '1'));
    expect(await store.relocate(chosen.path), isNull, reason: 'an empty directory accepts it');

    final moved = await JournalStore(dataRoot: chosen.path).load();
    expect(moved.document, store.document, reason: 'the whole document travelled');

    // And the journal keeps journalling THERE: a later edit appends beside the
    // new snapshot, never back at the old location. What the old journal held
    // when the move happened is the pre-move history and stays exactly that.
    final left = written().map((entry) => entry.label).toList();
    store.commit('After the move', store.document.put('meta', 'two', '2'));
    await fire(store);
    final here = parseJournal(
      File(storePath(chosen.path, journalFileName)).readAsBytesSync(),
    ).entries;
    expect(here.map((entry) => entry.label), ['After the move']);
    expect(
      written().map((entry) => entry.label),
      left,
      reason: 'nothing is appended at the place it left',
    );
    expect(
      (await JournalStore(dataRoot: chosen.path).load()).document,
      store.document,
      reason: 'reopening the new location is the document as it now stands',
    );
  });

  test('everything committed reaches the old files before the move, and they are left there',
      () async {
    final chosen = await tempRoot('moved-from');
    addTearDown(() => removeRoot(chosen));
    final store = open();
    await store.load();
    store.commit('Said and not yet written', store.document.put('meta', 'one', '1'));
    expect(store.pending, isTrue, reason: 'the debounce has not fired');
    await store.relocate(chosen.path);
    expect(
      written().map((entry) => entry.label),
      ['Said and not yet written'],
      reason: 'a move never costs an edit the process was told about',
    );
    expect(
      File(storePath(root.path, snapshotFileName)).existsSync(),
      isTrue,
      reason: 'the old files are left in place; deleting them is not this call to make',
    );
  });

  test('a directory another chronolog occupies is refused, in words, and nothing is written',
      () async {
    final occupied = await tempRoot('occupied');
    addTearDown(() => removeRoot(occupied));
    final sitting = DocumentStore(dataRoot: occupied.path, scheduler: ManualScheduler());
    await sitting.load();
    sitting.commit('The one already living here', sitting.document.put('meta', 'theirs', 'yes'));
    await sitting.save(force: true);
    final theirs = (await JournalStore(dataRoot: occupied.path).load()).document;

    final store = open();
    await store.load();
    store.commit('Mine', store.document.put('meta', 'mine', 'yes'));
    final refused = await store.relocate(occupied.path);
    expect(refused, isNotNull, reason: 'refuse loudly, never guess');
    expect(refused, contains(occupied.path), reason: 'the words name the place');
    expect(
      (await JournalStore(dataRoot: occupied.path).load()).document,
      theirs,
      reason: 'the document already there is untouched',
    );
    expect(store.journal.dataRoot, root.path, reason: 'a refused move moved nothing');
  });

  test('the sequence carries across a move: a new file, not a new history', () async {
    final chosen = await tempRoot('moved-seq');
    addTearDown(() => removeRoot(chosen));
    final store = open();
    await store.load();
    for (var index = 0; index < 4; index += 1) {
      store.commit('edit $index', store.document.put('meta', 'n', '$index'));
      await fire(store);
    }
    final before = store.seq;
    await store.relocate(chosen.path);
    expect(store.seq, greaterThan(before), reason: 'monotone across the move');
    store.commit('after', store.document.put('meta', 'n', 'last'));
    await fire(store);
    expect(
      parseJournal(File(storePath(chosen.path, journalFileName)).readAsBytesSync()).entries.single.seq,
      greaterThan(before),
    );
  });

  test('a move to where the document already is does nothing at all', () async {
    final store = open();
    await store.load();
    expect(await store.relocate(root.path), isNull);
    expect(store.journal.dataRoot, root.path);
    expect(await store.relocate('  '), isNotNull, reason: 'a location needs a path');
  });
}
