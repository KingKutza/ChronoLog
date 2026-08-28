// The store spec's seams and generators.
//
// Every case that touches the disk touches a fresh directory under the system
// temp root and deletes it again; nothing here writes into the repository.
//
// The two seams are what make the spec assert things a sleep never could: the
// scheduler runs the debounce on a clock the test moves, and the file wrapper
// NAMES every write step, so "kill the process between any two of them" is an
// enumeration rather than a hope.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/ops.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/store/plaintext_file.dart';
import 'package:chronolog/store/seams.dart';

Future<Directory> tempRoot(String label) => Directory.systemTemp.createTemp('chronolog-$label-');

Future<void> removeRoot(Directory root) async {
  try {
    await root.delete(recursive: true);
  } on FileSystemException {
    // A directory the platform is still holding is a cleanup problem, never a
    // result: the case already answered.
  }
}

/// Timers on a clock the test moves.
class ManualScheduler implements Scheduler {
  DateTime clock = DateTime.utc(2026, 8, 27);
  final List<_Task> _tasks = [];

  int get armed => _tasks.where((task) => !task.cancelled).length;

  @override
  DateTime now() => clock;

  @override
  StoreTimer run(Duration delay, void Function() action) {
    final task = _Task(clock.add(delay), action);
    _tasks.add(task);
    return task;
  }

  /// Move the clock and fire everything that came due, earliest first, pumping
  /// the event loop between callbacks so an async save can get started.
  Future<void> advance(Duration by) async {
    clock = clock.add(by);
    for (;;) {
      _tasks.removeWhere((task) => task.cancelled);
      final due = _tasks.where((task) => !task.due.isAfter(clock)).toList()
        ..sort((left, right) => left.due.compareTo(right.due));
      if (due.isEmpty) return;
      _tasks.remove(due.first);
      due.first.action();
      await pump();
    }
  }

  Future<void> pump() => Future<void>.delayed(Duration.zero);
}

class _Task implements StoreTimer {
  _Task(this.due, this.action);

  final DateTime due;
  final void Function() action;
  bool cancelled = false;

  @override
  void cancel() => cancelled = true;
}

/// A DISK THAT IS A MAP. The one in-memory store the whole spec shares.
///
/// A widget test runs inside a fake-async zone, so REAL file I/O inside
/// `testWidgets` never completes -- the load awaits a future the zone will not
/// run. Everything here answers in memory, which is also the honest shape for a
/// card or surface spec: what the surface does is the subject, and the
/// filesystem is not.
class MemoryFiles implements StoreFiles {
  final Map<String, List<int>> contents = {};

  /// What was written to the one path ending in [name], as text.
  String? find(String name) {
    for (final entry in contents.entries) {
      if (entry.key.endsWith(name)) return utf8.decode(entry.value);
    }
    return null;
  }

  void write(String path, String text) => contents[path] = utf8.encode(text);

  /// The bytes under each path, so a spec can assert what was written.
  Map<String, List<int>> get written => contents;

  void put(PlaintextFile file, String text) => write(file.path, text);

  @override
  Future<List<int>?> read(String path) async => contents[path];

  @override
  Future<void> ensureDirectory(String path) async {}

  @override
  Future<void> writeNew(String path, List<int> bytes) async => contents[path] = [...bytes];

  @override
  Future<void> rename(String from, String to) async {
    final bytes = contents.remove(from);
    if (bytes != null) contents[to] = bytes;
  }

  @override
  Future<void> appendSynced(String path, List<int> bytes) async =>
      contents[path] = [...?contents[path], ...bytes];

  @override
  Future<void> truncate(String path, int length) async =>
      contents[path] = [...?contents[path]?.take(length)];

  @override
  Future<void> delete(String path) async => contents.remove(path);

  @override
  Future<List<String>> namesIn(String path) async {
    final under = [
      for (final key in contents.keys)
        if (key.startsWith('$path/') || key.startsWith('$path${Platform.pathSeparator}')) key,
    ];
    return {for (final key in under) _lastSegment(key)}.toList()..sort();
  }

  static String _lastSegment(String path) {
    final cut = [
      path.lastIndexOf('/'),
      path.lastIndexOf(Platform.pathSeparator),
    ].reduce((a, b) => a > b ? a : b);
    return cut < 0 ? path : path.substring(cut + 1);
  }
}

/// Every write step, named, with a hook before each one. Reads pass straight
/// through and are not steps: nothing a read does can leave a file half written.
class InstrumentedFiles implements StoreFiles {
  InstrumentedFiles({this.inner = const IoStoreFiles(), this.before});

  final StoreFiles inner;
  final Future<void> Function(String step, int index)? before;
  final List<String> steps = [];

  Future<void> _step(String name) async {
    steps.add(name);
    if (before != null) await before!(name, steps.length);
  }

  @override
  Future<List<int>?> read(String path) => inner.read(path);

  @override
  Future<void> ensureDirectory(String path) async {
    await _step('ensureDirectory');
    return inner.ensureDirectory(path);
  }

  @override
  Future<void> writeNew(String path, List<int> bytes) async {
    await _step('writeNew');
    return inner.writeNew(path, bytes);
  }

  @override
  Future<void> rename(String from, String to) async {
    await _step('rename');
    return inner.rename(from, to);
  }

  @override
  Future<void> appendSynced(String path, List<int> bytes) async {
    await _step('appendSynced');
    return inner.appendSynced(path, bytes);
  }

  @override
  Future<void> truncate(String path, int length) async {
    await _step('truncate');
    return inner.truncate(path, length);
  }

  @override
  Future<void> delete(String path) async {
    await _step('delete');
    return inner.delete(path);
  }

  @override
  Future<List<String>> namesIn(String path) => inner.namesIn(path);
}

/// The kill signal. Its own type so a case can tell a simulated crash from a
/// defect that happened to throw.
class SimulatedCrash implements Exception {
  const SimulatedCrash(this.step);

  final int step;

  @override
  String toString() => 'SimulatedCrash at write step $step';
}

/// A random walk of committed edits over [start], each one an entry the journal
/// would have written. The ops come from the identity diff, so they are the ops
/// a real commit would have reported.
///
/// Every state the walk passes through stays VALID: a deletion only ever takes
/// an object the walk minted itself, which nothing references, so the load-time
/// validator's findings stay a separate question from the journal's own.
List<OpEntry> randomEdits(int seed, Document start, int count) {
  final random = Random(seed);
  final entries = <OpEntry>[];
  final minted = <String>[];
  var document = start;
  for (var index = 0; index < count; index += 1) {
    final before = mapSnapshot(document);
    document = _mutate(random, document, index, minted);
    final ops = opsFromMaps(before, mapSnapshot(document));
    if (ops.isNotEmpty) entries.add((label: 'edit $index', ops: ops));
  }
  return entries;
}

Document _mutate(Random random, Document document, int index, List<String> minted) {
  final events = document.events.keys.toList();
  final relations = document.relations.keys.toList();
  switch (random.nextInt(6)) {
    case 0:
      final id = 'event:minted-$index';
      minted.add(id);
      return document.put(
        'events',
        id,
        Event(
          id: id,
          traits: const ['event'],
          magnitudes: {'duration': durationMagnitude('${random.nextInt(90)}', 'minute')},
          payload: {'title': 'minted $index'},
        ),
      );
    case 1:
      if (events.isEmpty) break;
      final id = events[random.nextInt(events.length)];
      return document.put(
        'events',
        id,
        document.events[id]!.copyWith(payload: {'title': 'edited $index'}),
      );
    case 2:
      if (minted.isEmpty) break;
      return document.remove('events', minted.removeAt(random.nextInt(minted.length)));
    case 3:
      return document.put('meta', 'modified', '2026-08-27T00:00:${index % 60}.000Z');
    case 4:
      if (relations.isEmpty) break;
      return document.remove('relations', relations[random.nextInt(relations.length)]);
    case 5:
      return document.put('foreign', 'probe-$index', {'seen': index});
  }
  return document;
}

/// Every state a run of [entries] passes through, in order: the document before
/// the first entry, then after each one. A crash can land on any of these and on
/// nothing else -- that is what "either the old state or the new one, never a
/// hybrid" means when more than one edit is in the batch.
List<Document> prefixStates(Document start, List<OpEntry> entries) {
  final states = <Document>[start];
  var document = start;
  for (final entry in entries) {
    document = applyOps(document, entry.ops);
    states.add(document);
  }
  return states;
}
