// The edit service: ONE door every change to the document goes through.
//
// The ops list IS the undo entry. The JavaScript carried two incompatible
// command shapes -- whole-document JSON snapshots with byte accounting on one
// side, live apply/revert closures on the other -- and both are gone: an
// immutable document's identity diff reports the forward ops, the same diff read
// backwards reports the inverse, and undo and redo are FORWARD journal entries
// like any other edit, because a journal is a history and history does not
// rewind.
//
// Because every door lands here, cascades and the series convergence invariant
// are laws rather than code paths: no caller can commit around them.

import 'package:flutter/foundation.dart';

import '../core/document.dart';
import '../core/exact.dart';
import '../core/math.dart';
import '../core/ops.dart';
import '../core/projection.dart';
import '../core/records.dart';
import '../core/series_heal.dart';
import '../core/staples.dart';
import '../session/settings.dart';
import '../store/document_store.dart';
import 'cascades.dart';
import 'drafts.dart';

export 'capture.dart';
export 'cascades.dart';
export 'drafts.dart';
export 'gestures.dart';
export 'reach.dart';
export 'weight_explain.dart';

/// This area's tunables, as shipped defaults in the one math. Squad C's settings
/// compose this map with every other area's; the settings file overrides by key.
const Map<String, String> editTunableDefaults = {
  'edit.historyDepth': '200',
  'edit.newSpanDays': '1',
  'edit.snapGrainMinutes': '30',
  'edit.groupFuzz': '2',
};

/// One committed edit: its label, what it did, and what undoes it.
typedef Edit = ({String label, List<Op> ops, List<Op> inverse});

class Editor extends ChangeNotifier with FrameSafeNotifier {
  Editor(this.store, {this.settings}) : engine = ProjectionEngine(store.document);

  final DocumentStore store;
  final ProjectionEngine engine;

  /// The tunable reader squad C composes. Absent, every key falls back to
  /// evaluating its own shipped default.
  final Rational Function(String key)? settings;

  /// Open edit-session drafts, keyed by object id. N cards hold N drafts.
  final Map<String, Draft> drafts = {};

  /// Records a card is holding that NOBODY HAS AUTHORED YET (E1, 2026-08-28).
  /// Every transaction sees them, so a card's rows edit real records; a
  /// transaction that changes one or points at one keeps it, and any other
  /// transaction puts it back out of the document. A card closed with nothing
  /// set therefore leaves no record, no undo entry and no journal line.
  final Map<String, Event> pending = {};

  final List<Edit> _undo = [], _redo = [];

  /// Why the last commit was refused, in the reference's own words. Empty is the
  /// ordinary state; a surface reads it and says so where the edit was made.
  List<String> refusals = const [];

  Document get document => store.document;

  /// The staple substrate, ONE instance: the engine already builds it with the
  /// law, index and fact seams bound, so a card asks what the engine answered
  /// rather than standing up a second, thinner copy per rebuild.
  Staples get staples => engine.staples;

  Listenable get changes => this;

  bool get canUndo => _undo.isNotEmpty;

  bool get canRedo => _redo.isNotEmpty;

  /// The edits that would be undone and redone, newest last.
  List<Edit> get history => List.unmodifiable(_undo);

  /// One tunable, read through squad C's settings or evaluated from the shipped
  /// default. No bare number lives in this area.
  Rational setting(String key) {
    final read = settings;
    if (read != null) return read(key);
    final value = evaluateSource(editTunableDefaults[key]!, const Env());
    return value is Rational ? value : Rational.zero;
  }

  /// The unsuppressed projector the heal compares against: the same generator
  /// that reasserts, so the comparison and the reassertion cannot drift.
  UnsuppressedProjector projectorFor(Document next) {
    final over = identical(next, document) ? engine : ProjectionEngine(next);
    return (window) {
      final found = over.queryFacts(
        Projection.of([window.frame]),
        start: window.start,
        end: window.end,
        applyOverrides: false,
        includeOverlaps: true,
      );
      for (final fact in found.facts) {
        if (fact.virtualId != window.virtualId) continue;
        return (virtualId: fact.virtualId, event: fact.event, relation: fact.relation);
      }
      return null;
    };
  }

  /// The commit door. Hand over the document the edit produced; the cascade, the
  /// convergence invariant, the ops, the journal entry and the undo entry all
  /// follow from the two documents. An edit that changes nothing writes nothing.
  ///
  /// [converge] widens the heal beyond what the diff alone reaches -- a card
  /// closing on an occurrence it did not touch.
  void commit(String label, Document next, {HealScope? converge}) =>
      transaction(label, (_) => next, converge: converge);

  /// Ops in hand, already known: applied, then settled like any other edit.
  void commitOps(String label, List<Op> ops) =>
      transaction(label, (current) => applyOps(current, ops));

  /// The transaction: mutate, settle, diff, journal, push undo. Every other door
  /// in this area is one of these with the mutation filled in.
  void transaction(String label, Document Function(Document) mutate, {HealScope? converge}) {
    final before = document;
    final after = weedPending(mutate(seedPending(before, pending)), pending);
    final settled = settle(before, after, projector: projectorFor, converge: converge);
    refusals = settled.refusals;
    if (refusals.isNotEmpty) return notifyListeners();
    final snapshot = mapSnapshot(before);
    if (opsFromMaps(snapshot, mapSnapshot(settled.document)).isEmpty) return;
    final ops = store.commit(label, touch(settled.document));
    engine.applyChange(ops);
    _record((label: label, ops: ops, inverse: opsFromMaps(mapSnapshot(document), snapshot)));
    notifyListeners();
  }

  void _record(Edit edit) {
    _undo.add(edit);
    _redo.clear();
    final depth = setting('edit.historyDepth').floor().toInt();
    while (_undo.length > (depth < 1 ? 1 : depth)) {
      _undo.removeAt(0);
    }
  }

  bool undo() => _step(_undo, _redo, 'Undo', (edit) => edit.inverse);

  bool redo() => _step(_redo, _undo, 'Redo', (edit) => edit.ops);

  bool _step(List<Edit> from, List<Edit> to, String verb, List<Op> Function(Edit) direction) {
    if (from.isEmpty) return false;
    final edit = from.removeLast();
    final ops = direction(edit);
    // A forward journal entry, not a rewind: the store collects it and the
    // engine is told exactly which records moved.
    store.collect('$verb ${edit.label}', ops);
    engine.applyChange(ops);
    to.add(edit);
    notifyListeners();
    return true;
  }

  /// The document was replaced wholesale -- a fresh load, a different file. The
  /// history describes a document that no longer exists.
  void resync() {
    _undo.clear();
    _redo.clear();
    refusals = const [];
    drafts.clear();
    pending.clear();
    engine.setDocument(store.document);
    notifyListeners();
  }

  /// Telling the surface, safely, is [FrameSafeNotifier]'s job -- an edit made
  /// WHILE THE TREE IS BUILDING (a card settling its draft as it mounts or
  /// unmounts) announces after the frame instead of marking an ancestor dirty
  /// inside it. The document is already changed either way; only the repaint
  /// waits.

  /// Delete an object. Its placements, memberships, containment edges, staples
  /// and the overrides that named it travel with it, inside this one entry.
  void deleteObject(String id) =>
      transaction('Delete object', (current) => current.remove('events', id));

  /// Delete a frame. Its attachments, the staple ends that touched it, the
  /// patterns those attachments were the template of, and those patterns'
  /// overrides all travel with it.
  void deleteFrame(String id) =>
      transaction('Delete frame', (current) => current.remove('frames', id));
}
