// The op vocabulary: what a committed change to the document IS, as the record
// list a journal can persist and replay.
//
// An op names a map and a record id and either assigns the WHOLE record or
// deletes it. Records are the unit, never fields. That is deliberate: a journal
// can apply and compact ops with no idea what an event or a frame is, and
// applying the same put or delete twice lands on the same state -- which is what
// makes a crash mid-write survivable and a retry safe.
//
// THERE IS EXACTLY ONE DEFINITION HERE. The JavaScript kept a second copy of
// `applyOps` in its journal tool; two copies that drifted apart would corrupt
// documents quietly, so [applyOps] below is the only one that exists.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'records.dart';

part 'ops.freezed.dart';

/// One record-level op. `value` holds either a live record or the parsed JSON a
/// journal replay hands back, so a put carries the whole record either way.
/// `op` is `put` or `del`, read by [applyOps] and by nothing else.
@Freezed(fromJson: false, toJson: false)
abstract class Op with _$Op {
  const Op._();
  const factory Op({required String op, required String map, required String id, Object? value}) =
      _Op;

  factory Op.fromJson(Json json) => Op(
    op: '${json['op'] ?? ''}',
    map: '${json['map'] ?? ''}',
    id: '${json['id'] ?? ''}',
    value: json['value'],
  );

  Json toJson() => {'op': op, 'map': map, 'id': id, if (value != null) 'value': jsonValue(value)};
}

Op putOp(String map, String id, Object? value) => Op(op: 'put', map: map, id: id, value: value);

Op delOp(String map, String id) => Op(op: 'del', map: map, id: id);

/// The one definition of what an op means. Idempotent by construction, and
/// total: an unknown map or verb is refused by name rather than skipped, because
/// a silently dropped op is a document that quietly disagrees with its journal.
Document applyOps(Document document, Iterable<Op> ops) {
  var next = document;
  for (final op in ops) {
    if (op.id.isEmpty) throw ArgumentError('journal op needs a record id');
    next = switch (op.op) {
      'put' => next.put(op.map, op.id, op.value),
      'del' => next.remove(op.map, op.id),
      _ => throw ArgumentError('unknown journal op "${op.op}"'),
    };
  }
  return next;
}

/// A per-map snapshot of record identities, taken before an edit. Cheap by
/// construction: one reference per record, no traversal into the records.
Map<String, Map<String, Object?>> mapSnapshot(
  Document document, [
  List<String> maps = recordMaps,
]) => {for (final map in maps) map: Map.of(document.records(map))};

/// The identity diff. A record that is still the same value was not rewritten,
/// so it emits nothing; anything else is a put, and anything that vanished is a
/// delete. Immutable records make the precondition structural -- no in-place
/// mutation exists that could leave a changed record looking untouched -- which
/// is why this is the whole capture strategy rather than a fallback for one.
List<Op> opsFromMaps(
  Map<String, Map<String, Object?>> before,
  Map<String, Map<String, Object?>> after,
) {
  final ops = <Op>[];
  for (final map in recordMaps) {
    final previous = before[map] ?? const {};
    final next = after[map] ?? const {};
    for (final entry in next.entries) {
      final was = previous[entry.key];
      final untouched = identical(was, entry.value) || was == entry.value;
      if (previous.containsKey(entry.key) && untouched) continue;
      ops.add(putOp(map, entry.key, entry.value));
    }
    for (final id in previous.keys) {
      if (!next.containsKey(id)) ops.add(delOp(map, id));
    }
  }
  return ops;
}

/// Forward and inverse ops for one edit. ONE bundle shape: the three the
/// JavaScript carried (an event plus its related maps, a frame plus its related
/// maps, and the already-per-map set variants) were the same per-map collection
/// wearing three constructors, and the inverse needs no extra capture because
/// the before-collection already holds it.
({List<Op> ops, List<Op> inverseOps}) bundleOps(
  Map<String, Map<String, Object?>> before,
  Map<String, Map<String, Object?>> after,
) => (ops: opsFromMaps(before, after), inverseOps: opsFromMaps(after, before));

/// One committed edit's label and ops.
typedef OpEntry = ({String label, List<Op> ops});

/// Accumulates committed edits until the store writes them. One entry per
/// commit, so a debounce batches several edits into one write without flattening
/// them into an indistinguishable blob. Order is preserved: a put followed by a
/// delete of the same record means something different than the reverse.
class OpLog {
  final List<OpEntry> _entries = [];

  List<OpEntry> get entries => List.unmodifiable(_entries);

  int get length => _entries.length;

  int get opCount => _entries.fold(0, (total, entry) => total + entry.ops.length);

  void collect(String label, List<Op> ops) {
    if (ops.isNotEmpty) _entries.add((label: label, ops: ops));
  }

  /// The pending entries, emptying the log. A failed write hands them back with
  /// [restore] so nothing is lost.
  List<OpEntry> drain() {
    final drained = List.of(_entries);
    _entries.clear();
    return drained;
  }

  void restore(List<OpEntry> entries) => _entries.insertAll(0, entries);

  void clear() => _entries.clear();
}
