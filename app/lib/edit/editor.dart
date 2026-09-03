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
import 'resay.dart';

export 'capture.dart';
export 'cascades.dart';
export 'clipboard.dart';
export 'drafts.dart';
export 'gestures.dart';
export 'reach.dart';
export 'resay.dart';
export 'weight_explain.dart';

/// This area's tunables, as shipped defaults in the one math. Squad C's settings
/// compose this map with every other area's; the settings file overrides by key.
const Map<String, String> editTunableDefaults = {
  'edit.historyDepth': '200',
  'edit.newSpanDays': '1',
  'edit.snapGrainMinutes': '30',
  'edit.groupFuzz': '2',
  // How far a keyboard duplicate lands from the thing it duplicates, in days.
  // A twin exactly on its source is two marks at one coordinate, which every
  // timed lens draws as one, so the paste steps -- and how far it steps is the
  // person's, like every other number in this area.
  'edit.pasteStepDays': '1',
};

/// ONE AUTHORED SETTINGS CHANGE: the key, what stood on it, and what it became.
///
/// [was] and [now] are OVERRIDES, and null is a real value in both: the file
/// records only overrides, so undoing the first write of a key must restore the
/// ABSENCE of one rather than write the shipped value back as authorship
/// nobody claimed.
typedef SettingEdit = ({String key, String? was, String? now});

/// One committed edit: its label, what it did, and what undoes it.
///
/// A SETTINGS WRITE RIDES THE SAME HISTORY (ISSUES 9.2, Don: "settings edits
/// like theme changes should be subject to undo"). It was unrecoverable because
/// there were two stores and only one of them was journalled -- and two undo
/// stacks would be the enum in another costume, so an edit carries whichever of
/// the two it was and one ctrl+z crosses the boundary without the person
/// knowing there was one.
typedef Edit = ({String label, List<Op> ops, List<Op> inverse, List<SettingEdit> settings});

class Editor extends ChangeNotifier with FrameSafeNotifier {
  Editor(this.store, {this.settings, this.settingsStore})
    : engine = ProjectionEngine(store.document);

  final DocumentStore store;
  final ProjectionEngine engine;

  /// The tunable reader squad C composes. Absent, every key falls back to
  /// evaluating its own shipped default.
  final Rational Function(String key)? settings;

  /// The settings STORE, not only its reader: a settings write is an authored
  /// change like any other and rides this history, which means this door has to
  /// be able to make one and take it back.
  final Settings? settingsStore;

  /// Open edit-session drafts, keyed by object id. N cards hold N drafts.
  final Map<String, Draft> drafts = {};

  /// WHAT THE LAST COPY CARRIED -- the records themselves, snapshot at the copy,
  /// never their ids. A cut still holds its record after the document has let
  /// it go, and a paste taken after the source was edited pastes what was
  /// copied; ids could say neither. Empty is the ordinary state and means
  /// nothing has been copied.
  List<Event> get clipboard => List.unmodifiable(_clipboard);

  /// The one writer, so [Clipboard] can hold records without the list itself
  /// being reachable for a surface to mutate behind the editor's back.
  void setClipboard(List<Event> events) {
    _clipboard
      ..clear()
      ..addAll(events);
  }

  final List<Event> _clipboard = [];

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
    _record((
      label: label,
      ops: ops,
      inverse: opsFromMaps(mapSnapshot(document), snapshot),
      settings: const [],
    ));
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

  /// AUTHOR ONE SETTING, THROUGH THE ONE HISTORY.
  ///
  /// The card's door for both families -- [Settings] already knows which a key
  /// is. Accepted: the value takes effect and one undo entry is pushed.
  /// Refused: the reason comes back, nothing changes, and no entry exists,
  /// because a refusal is not an edit.
  String? setSetting(String key, String written) {
    final store = settingsStore;
    if (store == null) {
      return 'No settings are open here, so "$key" has nowhere to be authored.';
    }
    final was = store.overrideOf(key);
    if (was == written) return null;
    final refusal = _writeSetting(store, key, written);
    if (refusal != null) return refusal;
    _record((
      label: 'Set $key',
      ops: const [],
      inverse: const [],
      settings: [(key: key, was: was, now: written)],
    ));
    notifyListeners();
    return null;
  }

  /// UNAUTHOR ONE SETTING, through the same history. Resetting is a change a
  /// person made like any other, and a change you cannot take back is the
  /// complaint this whole door answers.
  bool resetSetting(String key) {
    final store = settingsStore;
    if (store == null) return false;
    final was = store.overrideOf(key);
    if (was == null) return false;
    store.reset(key);
    _record((
      label: 'Reset $key',
      ops: const [],
      inverse: const [],
      settings: [(key: key, was: was, now: null)],
    ));
    notifyListeners();
    return true;
  }

  String? _writeSetting(Settings store, String key, String? written) {
    if (written == null) {
      store.reset(key);
      return null;
    }
    if (store.isText(key)) {
      store.setText(key, written);
      return null;
    }
    return store.set(key, written);
  }

  bool undo() => _step(_undo, _redo, 'Undo', (edit) => edit.inverse);

  bool redo() => _step(_redo, _undo, 'Redo', (edit) => edit.ops);

  bool _step(List<Edit> from, List<Edit> to, String verb, List<Op> Function(Edit) direction) {
    if (from.isEmpty) return false;
    final edit = from.removeLast();
    // A settings entry and a record entry sit in ONE list, in the order they
    // were made, so walking back crosses the boundary without noticing it.
    final settings = settingsStore;
    final backwards = verb == 'Undo';
    for (final said in edit.settings) {
      if (settings != null) _writeSetting(settings, said.key, backwards ? said.was : said.now);
    }
    final ops = direction(edit);
    if (ops.isNotEmpty) {
      // A forward journal entry, not a rewind: the store collects it and the
      // engine is told exactly which records moved.
      store.collect('$verb ${edit.label}', ops);
      engine.applyChange(ops);
    }
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

  /// RE-SAY ONE END OF A CONNECTION, keeping every other term.
  ///
  /// The verb behind "move this event to another frame" and "attach this note to
  /// that frame instead" -- one transaction, because they are one sentence being
  /// re-said and not two features. [slot] is the end's own word for itself, from
  /// [connectionEnds]; the coordinate is translated through the two frames' laws
  /// and the authored correspondence, or nothing is written and the refusal is
  /// in [refusals] for the surface to say where the edit was made.
  ///
  /// Returns whether it landed, so a card can keep the row open on a refusal.
  bool resay(String relationId, {required String slot, required String becomes}) {
    final relation = document.relations[relationId];
    if (relation == null) {
      refusals = ['That connection is no longer in the document.'];
      notifyListeners();
      return false;
    }
    final said = resaidConnection(
      staples,
      engine.correspondences,
      relation,
      slot: slot,
      becomes: becomes,
    );
    final landed = said.resolved;
    if (landed == null) {
      refusals = [said.refusal!];
      notifyListeners();
      return false;
    }
    transaction('Re-say connection', (current) => current.put('relations', relationId, landed));
    return refusals.isEmpty;
  }

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
