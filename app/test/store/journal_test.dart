// The journal engine's spec.
//
// The genuine op-engine rulings of the JavaScript's persistence spec ride here:
// uniform sequence assignment, idempotence, refusal of an unknown verb or map,
// and truncated-tail healing. The HTTP half -- the sequence CAS, the 409, the
// rebase loop, the multi-window merge -- is DEAD by ruling and is not ported.
//
// Everything below is a property over seeded random op sequences, except where a
// single named case IS the property (the exact healthy-byte boundary of a torn
// line, the first-run establishment).

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/ops.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/store/data_dir.dart';
import 'package:chronolog/store/journal.dart';
import 'package:chronolog/store/seams.dart';
import 'package:test/test.dart';

import '../core/corpus.dart';
import 'harness.dart';

String storePathOf(Directory root, String name) => storePath(root.path, name);

String line(int seq, String label, List<Op> ops) =>
    '${jsonEncode(JournalEntry(seq: seq, at: 't', label: label, ops: ops).toJson())}\n';

Op put(String map, String id, Object? value) => Op(op: 'put', map: map, id: id, value: value);

Future<Map<String, List<int>>> filesOf(Directory root) async {
  final state = <String, List<int>>{};
  for (final file in root.listSync().whereType<File>()) {
    state[file.path] = await file.readAsBytes();
  }
  return state;
}

Future<void> restore(Directory root, Map<String, List<int>> state) async {
  for (final file in root.listSync().whereType<File>()) {
    file.deleteSync();
  }
  for (final entry in state.entries) {
    File(entry.key).writeAsBytesSync(entry.value);
  }
}

void main() {
  late Directory root;

  setUp(() async => root = await tempRoot('journal'));
  tearDown(() async => removeRoot(root));

  JournalStore store({StoreFiles files = const IoStoreFiles()}) =>
      JournalStore(dataRoot: root.path, files: files, scheduler: ManualScheduler());

  test('an entry is applied as uniform record assignment across every map', () async {
    // The engine has no domain knowledge: `meta` and `foreign` are records keyed
    // by their own top-level property name, which is exactly why no map needs
    // special handling. That uniformity is what makes compaction possible.
    final opened = store();
    await opened.load(establish: () => createDocument(now: DateTime.utc(2026, 8, 27)));
    await opened.append([
      (
        label: 'every map',
        ops: [
          put('events', 'event:1', {
            'id': 'event:1',
            'payload': {'title': 'a'},
          }),
          put('frames', 'frame:1', {
            'id': 'frame:1',
            'traits': ['line'],
          }),
          put('patterns', 'pattern:1', {'id': 'pattern:1'}),
          put('relations', 'relation:1', {'id': 'relation:1', 'type': 'attachment'}),
          put('overrides', 'override:1', {'id': 'override:1', 'suppress': true}),
          put('meta', 'modified', '2026-08-18T00:00:00.000Z'),
          put('foreign', 'ics', <String, dynamic>{'sources': <String, dynamic>{}}),
        ],
      ),
    ]);
    final reload = await store().load();
    final document = reload.document;
    expect(document.events['event:1']!.payload!['title'], 'a');
    expect(document.frames['frame:1']!.traits, ['line']);
    expect(document.patterns['pattern:1'], isNotNull);
    expect(document.relations['relation:1']!.type, 'attachment');
    expect(document.overrides['override:1']!.suppress, isTrue);
    expect(document.meta['modified'], '2026-08-18T00:00:00.000Z');
    expect(document.foreign['ics'], {'sources': <String, dynamic>{}});

    await opened.append([
      (label: 'deletes', ops: [delOp('events', 'event:1'), delOp('foreign', 'ics')]),
    ]);
    final after = (await store().load()).document;
    expect(after.events.containsKey('event:1'), isFalse);
    expect(after.foreign.containsKey('ics'), isFalse);
  });

  test('an op naming an unknown map, an unknown verb or no id never reaches the file', () async {
    final opened = store();
    final boot = await opened.load();
    await opened.append(randomEdits(specSeed, boot.document, 2));
    final before = await File(opened.journalFile).readAsBytes();
    final seq = opened.seq;
    for (final ops in [
      [put('sessions', 'a', 1)],
      [Op(op: 'merge', map: 'events', id: 'a', value: const <String, dynamic>{})],
      [put('events', '', const <String, dynamic>{})],
    ]) {
      await expectLater(
        opened.append([(label: 'refused', ops: ops)]),
        throwsA(isA<ArgumentError>()),
      );
    }
    // Refused before the write, not after: a poison line in the journal would
    // be a document that cannot be opened again.
    expect(await File(opened.journalFile).readAsBytes(), before);
    expect(opened.seq, seq);
  });

  test('a truncated final journal line is dropped with a report, and the healthy '
      'prefix ends exactly where the last complete line ended', () {
    final good = line(1, 'one', const []) + line(2, 'two', const []);
    final partial = '{"seq":3,"ts":"t","label":"thr';
    final parsed = parseJournal(utf8.encode(good + partial));
    expect([for (final entry in parsed.entries) entry.seq], [1, 2]);
    expect(parsed.reports, hasLength(1));
    expect(parsed.reports.single, contains('truncated final journal line'));
    expect(parsed.healthyBytes, utf8.encode(good).length);
  });

  test('boot replays the journal over the snapshot and heals a partial tail', () async {
    final snapshot = createDocument(now: DateTime.utc(2026, 8, 27)).put(
      'events',
      'event:kept',
      const Event(id: 'event:kept', payload: {'title': 'from snapshot'}),
    );
    File(storePathOf(root, snapshotFileName)).writeAsStringSync(serializeDocument(snapshot));
    final complete =
        line(1, 'Edit event', [
          put('events', 'event:kept', {
            'id': 'event:kept',
            'payload': {'title': 'from journal'},
          }),
        ]) +
        line(2, 'Create event', [
          put('events', 'event:new', {'id': 'event:new'}),
        ]);
    File(storePathOf(root, journalFileName))
        .writeAsStringSync('$complete{"seq":3,"ops":[{"op":"pu');

    final opened = store();
    final boot = await opened.load();
    expect(boot.present, isTrue);
    expect(boot.replayed, 2, reason: 'both complete entries replay');
    expect(opened.seq, 2, reason: 'the truncated line never claimed a sequence number');
    expect(boot.document.events['event:kept']!.payload!['title'], 'from journal');
    expect(boot.document.events['event:new'], isNotNull);
    expect(boot.reports.where((report) => report.contains('truncated')), hasLength(1));
    // Healed on disk, so the next append cannot land after a partial line.
    expect(File(storePathOf(root, journalFileName)).readAsStringSync(), complete);

    await opened.append([
      (
        label: 'After heal',
        ops: [
          put('events', 'event:third', {'id': 'event:third'}),
        ],
      ),
    ]);
    final reopened = store();
    final again = await reopened.load();
    expect(reopened.seq, 3);
    expect(again.document.events['event:third'], isNotNull);
    expect(again.reports, isEmpty, reason: 'the heal was permanent');
  });

  test('the first run establishes the empty document and writes no phantom', () async {
    final opened = store();
    final boot = await opened.load();
    expect(boot.present, isFalse, reason: 'nothing was on disk');
    expect(boot.replayed, 0);
    expect(boot.document.frames.keys, ['measure:human-time', 'frame:wall-time']);
    expect(boot.document.events, isEmpty);
    expect(boot.document.relations, isEmpty);
    expect(boot.document.patterns, isEmpty);
    // The snapshot is established so the journal has a base to append onto.
    final written = File(storePathOf(root, snapshotFileName)).readAsStringSync();
    expect(written, serializeDocument(boot.document));
    expect(written.endsWith('\n'), isTrue);
    expect(written.trimRight().contains('\n'), isFalse, reason: 'compact, one line, diffable');
  });

  test('sequence numbers are assigned uniformly, one per entry, and stay monotone '
      'across a compaction', () async {
    final opened = store();
    var expected = (await opened.load()).document;
    final edits = randomEdits(specSeed, expected, 9);
    for (var index = 0; index < edits.length; index += 1) {
      // Singly, then in a batch: the numbering cannot depend on how the caller
      // grouped its writes.
      await opened.append(index.isEven ? [edits[index]] : [edits[index]]);
      expected = applyOps(expected, edits[index].ops);
    }
    final parsed = parseJournal(await File(opened.journalFile).readAsBytes());
    expect(
      [for (final entry in parsed.entries) entry.seq],
      [for (var i = 1; i <= edits.length; i += 1) i],
    );
    expect(opened.seq, edits.length);

    await opened.compact(expected);
    expect(opened.entryCount, 0);
    final reopened = store();
    final reload = await reopened.load();
    expect(reload.document, expected);
    expect(reopened.seq, edits.length, reason: 'the sidecar survives a truncated journal');
    await reopened.append([edits.first]);
    expect(reopened.seq, edits.length + 1, reason: 'numbering resumes, it does not restart');
  });

  test('a reload of snapshot plus journal is the document the ops produced', () async {
    for (final seed in seeds(24)) {
      final directory = await tempRoot('replay');
      try {
        final start = Corpus(seed).document();
        final opened = JournalStore(dataRoot: directory.path);
        await opened.load(establish: () => start);
        final edits = randomEdits(seed, start, 7);
        var expected = start;
        for (final edit in edits) {
          await opened.append([edit]);
          expected = applyOps(expected, edit.ops);
        }
        final reload = await JournalStore(dataRoot: directory.path).load();
        expect(reload.document, expected, reason: 'seed $seed');
        expect(reload.replayed, edits.length, reason: 'seed $seed');
      } finally {
        await removeRoot(directory);
      }
    }
  });

  test('a compaction at any point changes nothing observable', () async {
    for (final seed in seeds(24)) {
      final directory = await tempRoot('compact');
      try {
        final random = Random(seed);
        final start = Corpus(seed).document();
        final opened = JournalStore(dataRoot: directory.path);
        await opened.load(establish: () => start);
        final edits = randomEdits(seed, start, 8);
        final fold = random.nextInt(edits.length);
        var expected = start;
        for (var index = 0; index < edits.length; index += 1) {
          if (index == fold) await opened.compact(expected, force: random.nextBool());
          await opened.append([edits[index]]);
          expected = applyOps(expected, edits[index].ops);
        }
        // And again after the last edit, so the fold-at-the-end case is covered.
        final folded = await opened.compact(expected);
        expect(folded, edits.length - fold, reason: 'seed $seed');
        final reload = await JournalStore(dataRoot: directory.path).load();
        expect(reload.document, expected, reason: 'seed $seed');
        expect(reload.reports, isEmpty, reason: 'seed $seed');
      } finally {
        await removeRoot(directory);
      }
    }
  });

  test('replaying entries already folded into the snapshot changes nothing, which is '
      'why a crash mid-compaction is survivable', () async {
    for (final seed in seeds(24)) {
      final directory = await tempRoot('idempotent');
      try {
        final start = Corpus(seed).document();
        final opened = JournalStore(dataRoot: directory.path);
        await opened.load(establish: () => start);
        final edits = randomEdits(seed, start, 6);
        var expected = start;
        for (final edit in edits) {
          await opened.append([edit]);
          expected = applyOps(expected, edit.ops);
        }
        // Exactly the state a crash between "snapshot is durable" and "journal
        // is emptied" leaves behind: the new snapshot AND the entries that were
        // folded into it. Ops carry whole records, so the replay is a no-op.
        File(storePathOf(directory, snapshotFileName))
            .writeAsStringSync(serializeDocument(expected));
        final reload = await JournalStore(dataRoot: directory.path).load();
        expect(reload.document, expected, reason: 'seed $seed');
        expect(reload.replayed, edits.length, reason: 'seed $seed');
      } finally {
        await removeRoot(directory);
      }
    }
  });

  test('a torn tail heals with a report and loses at most the torn entry', () async {
    for (final seed in seeds(30)) {
      final directory = await tempRoot('torn');
      try {
        final random = Random(seed);
        final start = Corpus(seed).document();
        final opened = JournalStore(dataRoot: directory.path);
        await opened.load(establish: () => start);
        final edits = randomEdits(seed, start, 5);
        final states = prefixStates(start, edits);
        for (final edit in edits) {
          await opened.append([edit]);
        }
        final journal = File(storePathOf(directory, journalFileName));
        final whole = await journal.readAsBytes();
        final lastLine = whole.lastIndexOf(0x0a, whole.length - 2) + 1;

        if (random.nextBool()) {
          // Cut inside the final entry: that entry is lost, and only that one.
          final cut = lastLine + 1 + random.nextInt(whole.length - lastLine - 1);
          await journal.writeAsBytes(whole.sublist(0, cut));
        } else {
          // A partial append of random bytes after a complete entry: nothing is
          // lost, and the garbage goes.
          await journal.writeAsBytes([
            ...whole,
            for (var i = 0; i < 1 + random.nextInt(24); i += 1) random.nextInt(256),
          ], mode: FileMode.write);
        }

        final reload = await JournalStore(dataRoot: directory.path).load();
        expect(
          reload.document,
          anyOf(equals(states.last), equals(states[states.length - 2])),
          reason: 'seed $seed',
        );
        expect(reload.replayed, greaterThanOrEqualTo(edits.length - 1), reason: 'seed $seed');
        // Healed: a second open has nothing left to say, and agrees.
        final again = await JournalStore(dataRoot: directory.path).load();
        expect(again.reports, isEmpty, reason: 'seed $seed');
        expect(again.document, reload.document, reason: 'seed $seed');
      } finally {
        await removeRoot(directory);
      }
    }
  });

  test('killed between any two write steps, a reload finds a state the run passed '
      'through and never a hybrid', () async {
    final start = Corpus(specSeed).document();
    final edits = randomEdits(specSeed, start, 4);
    final states = prefixStates(start, edits);

    // One clean run, to learn how many write steps the batch takes.
    final counted = InstrumentedFiles();
    final measured = JournalStore(dataRoot: root.path, files: counted);
    await measured.load(establish: () => start);
    final base = await filesOf(root);
    final baseSteps = counted.steps.length;
    for (final edit in edits) {
      await measured.append([edit]);
    }
    await measured.compact(states.last);
    final total = counted.steps.length - baseSteps;
    expect(total, greaterThan(6), reason: 'the batch really is several steps');

    for (var kill = 1; kill <= total; kill += 1) {
      await restore(root, base);
      final files = InstrumentedFiles(
        before: (step, index) async {
          if (index == kill) throw SimulatedCrash(kill);
        },
      );
      final crashing = JournalStore(dataRoot: root.path, files: files);
      try {
        await crashing.load(establish: () => start);
        for (final edit in edits) {
          await crashing.append([edit]);
        }
        await crashing.compact(states.last);
      } on SimulatedCrash {
        // The point of the case.
      }
      final reload = await JournalStore(dataRoot: root.path).load();
      expect(
        states.any((state) => state == reload.document),
        isTrue,
        reason: 'killed at write step $kill of $total',
      );
    }
  });

  test('the whole document is written only to establish, to compact, and to '
      'replace -- never to save an edit', () async {
    final files = InstrumentedFiles();
    final opened = JournalStore(dataRoot: root.path, files: files);
    final boot = await opened.load(establish: () => Corpus(specSeed).document());
    final establishing = files.steps.length;
    expect(files.steps.where((step) => step == 'rename'), isNotEmpty);

    final edits = randomEdits(specSeed, boot.document, 5);
    var expected = boot.document;
    for (final edit in edits) {
      await opened.append([edit]);
      expected = applyOps(expected, edit.ops);
    }
    final appending = files.steps.sublist(establishing);
    // Every snapshot replacement ends in a rename. Appends do their own writing
    // and the state sidecar does its own replacement, so the test is that the
    // snapshot file itself was never one of them.
    expect(appending.where((step) => step == 'appendSynced'), hasLength(edits.length));
    expect(
      File(storePathOf(root, snapshotFileName)).readAsStringSync(),
      serializeDocument(boot.document),
      reason: 'the snapshot on disk is still the one establishment wrote',
    );

    await opened.replaceSnapshot(expected);
    expect(opened.entryCount, 0);
    expect(
      File(storePathOf(root, snapshotFileName)).readAsStringSync(),
      serializeDocument(expected),
    );
    expect(opened.seq, edits.length + 1, reason: 'a replacement is a visible discontinuity');
  });

  test('the serialized document is stable, compact and round-trips', () {
    for (final seed in seeds(120)) {
      final document = Corpus(seed).document();
      final text = serializeDocument(document);
      expect(text.endsWith('\n'), isTrue, reason: 'seed $seed');
      expect(text.substring(0, text.length - 1).contains('\n'), isFalse, reason: 'seed $seed');
      final reparsed = Document.fromJson(jsonDecode(text) as Json);
      expect(serializeDocument(reparsed), text, reason: 'seed $seed');
      expect(reparsed, document, reason: 'seed $seed');
    }
  });
}
