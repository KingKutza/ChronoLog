// The on-disk truth: a plaintext snapshot, and an append-only journal beside it.
//
// `chronolog.chronolog` is the serialized document -- compact JSON with a
// trailing newline, so the plaintext document diffs. Every committed edit
// appends one JSONL line to `chronolog.journal`. Loading is snapshot plus
// replay. Compaction folds the journal back into the snapshot and empties it.
//
// SAVES ARE UPDATES, NOT OVERWRITES. This file is that ruling in code: ordinary
// editing never rewrites the document, it appends the ops that changed it. The
// whole document is written on exactly three occasions -- establishing a file
// that does not exist yet, compaction, and the owner deliberately replacing the
// document, which is also how a MOVE to a chosen save location writes its first
// snapshot -- and none of them is autosave.
//
// ZERO DOMAIN KNOWLEDGE. An op names a map and a record id and either assigns
// the whole record or deletes it, uniformly for all seven maps. That uniformity
// is what lets this fold a journal into a snapshot with no idea what an event, a
// frame or an ICS source is.
//
// SINGLE WRITER. One master isolate owns the document and this journal, so there
// is no sequence-number CAS, no conflict type, and no rebase loop here. Those
// existed to arbitrate between browser windows over HTTP, and that whole surface
// is ruled out of pass one.

import 'dart:convert';

import '../core/document.dart';
import '../core/ops.dart';
import '../core/records.dart';
import '../core/validate.dart';
import 'data_dir.dart';
import 'seams.dart';

const String snapshotFileName = 'chronolog.chronolog';
const String journalFileName = 'chronolog.journal';
const String journalStateFileName = '.chronolog-journal-state.json';

const int _newline = 0x0a;

/// The plaintext document writer. Compact, one trailing newline, and the record
/// order records.dart declares -- so two saves of the same document are the same
/// bytes and a diff shows only what changed.
String serializeDocument(Document document) => '${jsonEncode(document.toJson())}\n';

/// One committed edit as the journal stores it: its sequence number, when it was
/// written, its own label, and the ops that are the edit.
class JournalEntry {
  const JournalEntry({required this.seq, required this.at, required this.label, required this.ops});

  final int seq;
  final String at;
  final String label;
  final List<Op> ops;

  Json toJson() => {
    'seq': seq,
    'ts': at,
    'label': label,
    'ops': [for (final op in ops) op.toJson()],
  };

  /// Null when the line is not an entry. A line missing its seq or its ops is
  /// not a partially good entry, it is not an entry.
  static JournalEntry? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    final seq = raw['seq'];
    final ops = raw['ops'];
    if (seq is! int || ops is! List) return null;
    return JournalEntry(
      seq: seq,
      at: '${raw['ts'] ?? ''}',
      label: '${raw['label'] ?? ''}',
      ops: [
        for (final op in ops)
          if (op is Map) Op.fromJson(Json.from(op)),
      ],
    );
  }
}

/// What a load found.
///
/// TWO KINDS OF NEWS, kept apart because they are answered differently.
/// [reports] is what the store had to do to the FILES -- a torn tail dropped, a
/// missing snapshot replayed onto an empty document -- and an empty list means
/// the files were whole. [findings] is what the validator says about the
/// DOCUMENT, in its own vocabulary; the owner reads those and decides. Neither
/// one ever refuses the load.
typedef JournalLoad = ({
  Document document,
  bool present,
  int replayed,
  int seq,
  List<String> reports,
  List<String> findings,
});

/// A journal buffer read as entries.
///
/// [healthyBytes] is the offset just past the last entry that parsed, so the
/// caller can cut the file back to it. A process killed mid-append leaves a
/// partial final line; that line is DROPPED with a report rather than taken as a
/// reason to refuse the document. An unreadable interior line is skipped with a
/// report and left in place -- losing one edit is bad, rewriting a journal to
/// tidy it is worse.
({List<JournalEntry> entries, List<String> reports, int healthyBytes}) parseJournal(
  List<int> bytes,
) {
  final entries = <JournalEntry>[];
  final reports = <String>[];
  var healthy = 0;
  var start = 0;
  var line = 0;
  while (start < bytes.length) {
    final found = bytes.indexOf(_newline, start);
    final torn = found < 0;
    final end = torn ? bytes.length : found;
    line += 1;
    if (end > start) {
      final entry = JournalEntry.tryFrom(_decode(bytes.sublist(start, end)));
      if (entry == null) {
        reports.add(
          torn
              ? 'Dropped a truncated final journal line (${end - start} bytes); '
                    'the last append did not complete.'
              : 'Skipped an unreadable journal line at line $line.',
        );
      } else {
        entries.add(entry);
        healthy = torn ? end : end + 1;
      }
    }
    start = end + 1;
  }
  return (entries: entries, reports: reports, healthyBytes: healthy);
}

/// A journal line as JSON, or null. Malformed UTF-8 is allowed through the
/// decoder because a torn tail can cut a multi-byte character in half, and a
/// decoder that threw there would turn a healable file into a dead one.
Object? _decode(List<int> bytes) {
  try {
    return jsonDecode(utf8.decode(bytes, allowMalformed: true));
  } on FormatException {
    return null;
  }
}

/// The snapshot-and-journal pair for one data directory.
///
/// It owns the FILES and the sequence number; it does not own the document. The
/// document is handed in when it must be written and handed back when it is
/// read, which is what keeps the live document in exactly one place -- the
/// master isolate's store above this.
class JournalStore {
  /// [continuing] is where this pair's numbering starts. It matters in exactly
  /// one case: a document MOVED to a new directory carries its sequence
  /// forward, so the history reads as one lineage rather than restarting at one.
  JournalStore({
    required this.dataRoot,
    this.files = const IoStoreFiles(),
    this.scheduler = const WallScheduler(),
    int continuing = 0,
  }) : _seq = continuing,
       snapshotFile = storePath(dataRoot, snapshotFileName),
       journalFile = storePath(dataRoot, journalFileName),
       _stateFile = storePath(dataRoot, journalStateFileName);

  final String dataRoot;
  final StoreFiles files;
  final Scheduler scheduler;
  final String snapshotFile;
  final String journalFile;
  final String _stateFile;

  int _seq;
  int _entryCount = 0;

  /// The sequence number of the last entry written. Monotone across a
  /// compaction, which is why the state sidecar exists at all.
  int get seq => _seq;

  /// Entries still in the journal file, folded into the snapshot by a compaction.
  int get entryCount => _entryCount;

  /// Does a chronolog already live here? Asked before a MOVE: a location
  /// another document occupies is not somewhere this one may be written, and
  /// with no confirmation dialogs anywhere the honest answer is to refuse and
  /// say so rather than to overwrite and hope.
  Future<bool> occupied() async =>
      await files.read(snapshotFile) != null ||
      (await files.read(journalFile) ?? const <int>[]).isNotEmpty;

  /// Snapshot plus replay.
  ///
  /// When neither file exists the document is ESTABLISHED -- [establish] mints
  /// it, and its snapshot is written so the journal has a base to append onto.
  /// Nothing is invented: the empty document is whatever the core's factory says
  /// an empty document is.
  Future<JournalLoad> load({Document Function()? establish}) async {
    await files.ensureDirectory(dataRoot);
    final snapshotBytes = await files.read(snapshotFile);
    final journalBytes = await files.read(journalFile) ?? const <int>[];
    final reports = <String>[];
    final parsed = parseJournal(journalBytes);
    reports.addAll(parsed.reports);
    await _healTail(journalBytes, parsed.healthyBytes);
    if (snapshotBytes == null && journalBytes.isEmpty) {
      final document = (establish ?? createEmptyWorkspaceDocument)();
      _seq = 0;
      _entryCount = 0;
      await _atomicWrite(snapshotFile, serializeDocument(document));
      await _writeState();
      return (
        document: document,
        present: false,
        replayed: 0,
        seq: 0,
        reports: reports,
        findings: validateDocument(document).errors,
      );
    }
    var document = const Document();
    if (snapshotBytes == null) {
      reports.add('No snapshot was found; the journal replayed onto an empty document.');
    } else {
      document = Document.fromJson(jsonDecode(_decodeText(snapshotBytes)) as Json);
    }
    for (final entry in parsed.entries) {
      document = applyOps(document, entry.ops);
    }
    final last = parsed.entries.isEmpty ? 0 : parsed.entries.last.seq;
    // Both sources are authoritative in different crash windows: the sidecar
    // survives a truncated journal, the journal survives a lost sidecar.
    _seq = _larger(await _readState(), last);
    _entryCount = parsed.entries.length;
    // The validator REPORTS. Migrations are dead by ruling and nothing here
    // rewrites the file to suit this build; what a load owes the owner is the
    // findings, in the law's own words, not a document that declines to open.
    return (
      document: document,
      present: true,
      replayed: parsed.entries.length,
      seq: _seq,
      reports: reports,
      findings: validateDocument(document).errors,
    );
  }

  /// Append committed edits, each keeping its own label, and flush before
  /// answering. Sequence numbers are assigned here and only here, one per entry,
  /// uniformly -- so the file's order and its numbering can never disagree.
  Future<int> append(List<OpEntry> entries) async {
    if (entries.isEmpty) return _seq;
    // The gate is the DEFINITION, not a restatement of it: an op this build
    // cannot replay must never reach the file, and applyOps is what "can
    // replay" means. An unknown verb, an unknown map or a record id that is
    // not one is refused here rather than persisted as a poison line.
    applyOps(const Document(), [for (final entry in entries) ...entry.ops]);
    final at = scheduler.now().toUtc().toIso8601String();
    final body = StringBuffer();
    var seq = _seq;
    for (final entry in entries) {
      seq += 1;
      body.writeln(
        jsonEncode(JournalEntry(seq: seq, at: at, label: entry.label, ops: entry.ops).toJson()),
      );
    }
    await files.appendSynced(journalFile, utf8.encode(body.toString()));
    _seq = seq;
    _entryCount += entries.length;
    await _writeState();
    return _seq;
  }

  /// Fold the journal into a new snapshot and empty it. Returns how many entries
  /// were folded.
  ///
  /// THE ORDER IS THE SAFETY. The snapshot is durable before the journal is
  /// dropped, so a crash in between leaves entries in the journal that are
  /// already folded into the snapshot -- and replaying them is harmless BECAUSE
  /// OPS ARE IDEMPOTENT. That is why a put carries the whole record rather than
  /// a field-level change: the same put applied twice lands on the same state,
  /// which is what makes a crash mid-compaction survivable at all.
  Future<int> compact(Document document, {bool force = false}) async {
    if (_entryCount == 0 && !force) return 0;
    final folded = _entryCount;
    await _snapshotAndReset(document);
    return folded;
  }

  /// Whole-document replacement: the owner opening a different document into
  /// this data directory. Never part of autosave. The journal is dropped because
  /// its ops describe a document that no longer exists, and the sequence number
  /// advances rather than resetting so the discontinuity is visible in the file.
  Future<void> replaceSnapshot(Document document) async {
    _seq += 1;
    await _snapshotAndReset(document);
  }

  Future<void> _snapshotAndReset(Document document) async {
    await _atomicWrite(snapshotFile, serializeDocument(document));
    await _writeState();
    await files.truncate(journalFile, 0);
    _entryCount = 0;
  }

  /// Write-new, flush, rename. The replacement is one filesystem step, so a
  /// reader either sees the whole old snapshot or the whole new one. The
  /// temporary is deleted first because a crash can leave one behind, and
  /// building on a leftover is the one thing an exclusive create refuses.
  Future<void> _atomicWrite(String path, String text) async {
    final temporary = '$path.tmp';
    await files.delete(temporary);
    await files.writeNew(temporary, utf8.encode(text));
    await files.rename(temporary, path);
  }

  /// Cut a torn tail off so the next append cannot land after a partial line,
  /// and guarantee the file ends on a newline so it cannot land inside a good
  /// one either.
  Future<void> _healTail(List<int> bytes, int healthy) async {
    if (bytes.isEmpty) return;
    if (healthy != bytes.length) await files.truncate(journalFile, healthy);
    if (healthy > 0 && bytes[healthy - 1] != _newline) {
      await files.appendSynced(journalFile, const [_newline]);
    }
  }

  Future<int> _readState() async {
    final bytes = await files.read(_stateFile);
    if (bytes == null) return 0;
    final parsed = _decode(bytes);
    final seq = parsed is Map ? parsed['seq'] : null;
    return seq is int ? seq : 0;
  }

  Future<void> _writeState() => _atomicWrite(_stateFile, '${jsonEncode({'seq': _seq})}\n');

  String _decodeText(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

  static int _larger(int a, int b) => a > b ? a : b;
}
