// The outside world, injected.
//
// Two seams and nothing else: the filesystem calls this store makes, and the
// clock plus timers its debounce runs on.
//
// The file primitives are deliberately FINE-GRAINED. An atomic replacement is
// composed from them in journal.dart rather than hidden inside one call, because
// "kill the process between any two write steps and a reload finds either the
// old state or the new one, never a hybrid" is only assertable if the steps are
// nameable. The spec names them by wrapping this interface.
//
// The clock is a seam for the same reason at the other end: a 350ms debounce and
// an in-flight coalescing rule are logic, and logic tested by sleeping is logic
// tested by luck.

import 'dart:async';
import 'dart:io';

/// Every file operation this store performs. Nothing here knows what a document
/// is; these are bytes, paths, and durability.
abstract interface class StoreFiles {
  /// The file's bytes, or null when it does not exist.
  Future<List<int>?> read(String path);

  Future<void> ensureDirectory(String path);

  /// Create a file that MUST NOT already exist, write it, flush it through to
  /// the platform, close it. The `open wx` -> fsync half of an atomic
  /// replacement; the exclusive create is what refuses to build on a leftover.
  Future<void> writeNew(String path, List<int> bytes);

  /// Replace [to] with [from]. The half that makes the replacement atomic.
  Future<void> rename(String from, String to);

  /// Append, then flush before answering, so an append the caller was told
  /// committed is on the disk rather than in a buffer.
  Future<void> appendSynced(String path, List<int> bytes);

  /// Cut the file to [length], creating it when absent. Heals a torn tail, and
  /// empties the journal once a compaction's snapshot is durable.
  Future<void> truncate(String path, int length);

  /// Remove the file if it is there. An absent file is already the outcome.
  Future<void> delete(String path);
}

class IoStoreFiles implements StoreFiles {
  const IoStoreFiles();

  @override
  Future<List<int>?> read(String path) async {
    final file = File(path);
    return await file.exists() ? file.readAsBytes() : null;
  }

  @override
  Future<void> ensureDirectory(String path) => Directory(path).create(recursive: true);

  @override
  Future<void> writeNew(String path, List<int> bytes) async {
    await File(path).create(exclusive: true);
    await _write(path, FileMode.writeOnly, bytes);
  }

  @override
  Future<void> rename(String from, String to) => File(from).rename(to);

  @override
  Future<void> appendSynced(String path, List<int> bytes) => _write(path, FileMode.append, bytes);

  @override
  Future<void> truncate(String path, int length) async {
    final handle = await File(path).open(mode: FileMode.append);
    try {
      await handle.truncate(length);
      await handle.flush();
    } finally {
      await handle.close();
    }
  }

  @override
  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  static Future<void> _write(String path, FileMode mode, List<int> bytes) async {
    final handle = await File(path).open(mode: mode);
    try {
      await handle.writeFrom(bytes);
      await handle.flush();
    } finally {
      await handle.close();
    }
  }
}

/// A timer this store can call off. One method, because cancelling is the only
/// thing the debounce ever asks of one.
abstract interface class StoreTimer {
  void cancel();
}

/// The clock and the timers, injected.
abstract interface class Scheduler {
  StoreTimer run(Duration delay, void Function() action);

  /// UTC, always: a journal entry's stamp is read by whoever opens the file
  /// next, and a local-time stamp would be a claim about this machine.
  DateTime now();
}

class WallScheduler implements Scheduler {
  const WallScheduler();

  @override
  StoreTimer run(Duration delay, void Function() action) => _WallTimer(Timer(delay, action));

  @override
  DateTime now() => DateTime.now().toUtc();
}

class _WallTimer implements StoreTimer {
  _WallTimer(this._timer);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}
