// The autosave flow: one owner, one document, one journal.
//
// Saving is not "write the document", it is "append the ops this session
// committed". A 350ms debounce batches a burst of edits into one write, ONE
// ENTRY PER COMMIT, so the journal keeps every edit's own label.
//
// Three behaviours here are load-bearing and were ported deliberately rather
// than re-derived:
//
//   REFCOUNTED DEFERRAL. N open drafts hold autosave off exactly N times.
//   [endDeferred] cannot drive the count below zero, so a `finally` that runs
//   twice -- cancel, then the click-away after cancel -- is harmless, and a
//   `finally` that runs once can never leave autosave stuck off.
//
//   IN-FLIGHT COALESCING THAT CARRIES FORCE FORWARD. Several callers pile up
//   behind one in-flight save and share a single follow-up. If any of them asked
//   for a forced save -- "Save now", a draft closing -- the follow-up must carry
//   that force, or the explicit request is quietly downgraded to an ordinary
//   autosave.
//
//   A FAILED WRITE HANDS THE OPS BACK. Drained entries are restored to the log
//   on error, so a failure costs a retry and never an edit.
//
// SINGLE PROCESS. There is no server, no sequence CAS, no rebase, no
// multi-window merge: one master isolate owns the document and the journal.

import 'dart:async';

import '../core/ops.dart';
import '../core/records.dart';
import 'journal.dart';
import 'seams.dart';

/// The status vocabulary. Five states, and no server-only ones: `detached` had
/// meaning only when a save target could be absent, and `conflict-rebasing` and
/// `downloaded` belonged to the browser build that died.
enum SaveState { loading, clean, dirty, saving, error }

/// What the store tells its owner. A STATE, not a sentence: the words a person
/// reads are the chrome's to write, and putting them here would make this file
/// the place two languages have to live.
typedef SaveStatus = ({SaveState state, bool dirty, int seq, Object? error});

class DocumentStore {
  DocumentStore({
    required String dataRoot,
    StoreFiles files = const IoStoreFiles(),
    Scheduler scheduler = const WallScheduler(),
    this.delay = const Duration(milliseconds: 350),
    this.establish,
    this.onStatus,
  }) : _scheduler = scheduler,
       journal = JournalStore(dataRoot: dataRoot, files: files, scheduler: scheduler);

  final JournalStore journal;
  final Duration delay;

  /// What an empty document is, when no file exists yet. The core's factory
  /// answers that question; nothing here invents a record the owner did not
  /// author.
  final Document Function()? establish;

  final void Function(SaveStatus status)? onStatus;
  final Scheduler _scheduler;
  final OpLog _log = OpLog();

  Document _document = const Document();
  SaveStatus _status = (state: SaveState.loading, dirty: false, seq: 0, error: null);
  int _deferred = 0;
  StoreTimer? _timer;
  Future<bool>? _inFlight;
  Future<bool>? _queued;
  bool _queuedForce = false;

  /// The live document. THE one copy: every read goes through here, so a pane
  /// can never render a document the journal has not been told about.
  Document get document => _document;

  /// Edits committed but not yet written.
  bool get pending => _log.length > 0;

  /// Open drafts holding autosave off.
  int get deferrals => _deferred;

  int get seq => journal.seq;

  SaveStatus get status => _status;

  /// The write currently in flight, or null. The master isolate asks this
  /// before it lets the process go, and it is how a debounce that fired on its
  /// own can be waited on rather than slept past.
  Future<bool>? get inFlight => _inFlight;

  /// Boot. Repairs, refusals and a torn journal tail all come back as reports
  /// for the owner to surface; a load never refuses the document over them.
  Future<JournalLoad> load() async {
    _cancel();
    _log.clear();
    _deferred = 0;
    _emit(SaveState.loading);
    final result = await journal.load(establish: establish);
    _document = result.document;
    _emit(SaveState.clean);
    return result;
  }

  /// The commit door: hand over the document the edit produced, and the ops it
  /// took are derived by identity diff. There is no whole-document fallback for
  /// a mutation path that forgets to report -- the ops are computed here, from
  /// the two documents, so forgetting is not expressible.
  List<Op> commit(String label, Document next) {
    final ops = opsFromMaps(mapSnapshot(_document), mapSnapshot(next));
    _document = next;
    _collect(label, ops);
    return ops;
  }

  /// The other commit door: ops in hand, already known. This is how undo and
  /// redo persist -- as FORWARD entries carrying the inverse ops, appended like
  /// any other edit, because a journal is a history and history does not rewind.
  void collect(String label, List<Op> ops) {
    _document = applyOps(_document, ops);
    _collect(label, ops);
  }

  void _collect(String label, List<Op> ops) {
    _log.collect(label, ops);
    if (!pending) return;
    _cancel();
    _emit(SaveState.dirty);
    if (_deferred == 0) _arm();
  }

  void beginDeferred() {
    _deferred += 1;
    _cancel();
  }

  void endDeferred() {
    if (_deferred == 0) return;
    _deferred -= 1;
    if (_deferred > 0 || !pending) return;
    _emit(SaveState.dirty);
    _arm();
  }

  /// A draft's whole life, with the release in a `finally`. The refcount is what
  /// makes this safe to nest: two drafts open at once hold twice, and each
  /// releases its own hold whether it commits, cancels or throws.
  Future<T> deferring<T>(Future<T> Function() body) async {
    beginDeferred();
    try {
      return await body();
    } finally {
      endDeferred();
    }
  }

  /// Write now. [force] means an explicit request -- "Save now", a draft closing
  /// -- which overrides an open deferral and is carried through any coalescing.
  Future<bool> save({bool force = false}) {
    final inFlight = _inFlight;
    if (inFlight != null) {
      _queuedForce = _queuedForce || force;
      return _queued ??= inFlight.then((_) {
        final followUp = _queuedForce;
        _queued = null;
        _queuedForce = false;
        return save(force: followUp);
      });
    }
    late Future<bool> run;
    run = _write(force).whenComplete(() {
      if (identical(_inFlight, run)) _inFlight = null;
    });
    _inFlight = run;
    return run;
  }

  Future<bool> _write(bool force) async {
    if (_deferred > 0 && !force) return false;
    if (!pending && !force) return true;
    _cancel();
    // Drain and write as one step. An edit committed while the append is in
    // flight is NOT in these entries, so it stays pending for the follow-up
    // rather than being reported saved when it never reached the file.
    final entries = _log.drain();
    if (entries.isEmpty) {
      _emit(SaveState.clean);
      return true;
    }
    _emit(SaveState.saving);
    try {
      await journal.append(entries);
    } catch (error) {
      _log.restore(entries);
      _emit(SaveState.error, error);
      return false;
    }
    _emit(pending ? SaveState.dirty : SaveState.clean);
    if (pending && _deferred == 0) _arm();
    return true;
  }

  /// Fold the journal into the snapshot. Pending edits are written first, so a
  /// compaction never folds a document the journal has not caught up with.
  Future<int> compact({bool force = false}) async {
    await save(force: true);
    final folded = await journal.compact(_document, force: force);
    _emit(pending ? SaveState.dirty : SaveState.clean);
    return folded;
  }

  /// The owner deliberately replacing the document. Pending ops are DROPPED
  /// because they describe a document that no longer exists.
  Future<void> replaceDocument(Document next) async {
    _cancel();
    _log.clear();
    _document = next;
    await journal.replaceSnapshot(next);
    _emit(SaveState.clean);
  }

  /// Flush and stand down -- the lifecycle-pause save. What a `beforeunload`
  /// dirty guard used to ask a person, a process can simply do.
  Future<void> close() async {
    _cancel();
    await save(force: true);
  }

  void _arm() => _timer = _scheduler.run(delay, () {
    _timer = null;
    save().ignore();
  });

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void _emit(SaveState state, [Object? error]) {
    _status = (state: state, dirty: pending, seq: journal.seq, error: error);
    onStatus?.call(_status);
  }
}
