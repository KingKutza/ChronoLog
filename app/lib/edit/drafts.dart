// Edit-session drafts: what an open editor card holds while it is open.
//
// Keyed by object id, because N cards hold N drafts. The store's autosave
// deferral is REFCOUNTED, so N open drafts hold autosave off exactly N times and
// the last one to close releases it. Every terminal path releases in a `finally`
// -- a draft is a transaction, never an autosave lock, and a failure must not
// leave the document permanently unsaveable.

import 'dart:convert';

import '../core/records.dart';
import '../core/series_heal.dart';
import 'editor.dart';

/// One open edit session. Idempotent per object: asking for a draft that is
/// already open hands back the same one rather than a second hold.
class Draft {
  Draft._(this.editor, this.objectId, {required this.provisional});

  final Editor editor;
  final String objectId;

  /// A provisional object was created BY this draft and has not been kept yet:
  /// discarding the draft removes it, and the cascade takes its placement with
  /// it. A draft over an object that already existed discards nothing.
  final bool provisional;

  bool _open = true;

  bool get open => _open;

  Document get document => editor.document;

  void commit(String label, Document next) {
    if (_open) editor.commit(label, next);
  }

  /// Keep the work and release the hold. Closing is also where a materialized
  /// occurrence is asked whether it still deviates from its series: if it does
  /// not, the convergence invariant retires it and the projection reasserts. A
  /// close that settles nothing writes nothing and pushes no undo entry.
  void close() => _release('Close editor', keep: true);

  /// Throw the work away, as its own undo transaction.
  void discard() => _release('Discard draft', keep: false);

  void _release(String label, {required bool keep}) {
    if (!_open) return;
    _open = false;
    try {
      if (!keep && provisional) {
        editor.commit(label, document.remove('events', objectId));
      } else {
        editor.commit(label, document, converge: HealScope(eventIds: {objectId}));
      }
    } finally {
      // Whatever the card did, it is no longer holding anything: a record still
      // pending here was never authored, so closing it means nothing happened.
      editor.pending.remove(objectId);
      editor.store.endDeferred();
      editor.drafts.remove(objectId);
    }
  }
}

extension Drafts on Editor {
  /// Open an edit session over [objectId], holding autosave off until it closes.
  ///
  /// [holding] is a record that does not exist yet: the session edits it, and
  /// the document only ever hears about it if a value lands on it.
  Draft beginDraft(String objectId, {bool provisional = false, Event? holding}) {
    final existing = drafts[objectId];
    if (existing != null && existing.open) return existing;
    if (holding != null) pending[objectId] = holding;
    store.beginDeferred();
    return drafts[objectId] = Draft._(this, objectId, provisional: provisional);
  }

  /// Every open draft, closed. What a lifecycle pause does before the process
  /// lets go, so no hold outlives the session that took it.
  void closeDrafts() {
    for (final draft in drafts.values.toList()) {
      draft.close();
    }
  }
}

// --- A record nobody has authored yet ---------------------------------------

/// Seeds every pending record into the document an edit is about to run over,
/// so every row of a card edits a REAL record and no surface needs a second
/// shape for "not saved yet".
///
/// E1 (2026-08-28): "created events that receive no updates auto-save when
/// closed, rather than waiting till at least one value is set somewhere." A new
/// object is held here, out of the document, until the first authored value
/// lands -- and then value and record are one op list, one journal entry, one
/// undo entry, because they arrive through the same [Editor.transaction].
Document seedPending(Document document, Map<String, Event> pending) {
  var next = document;
  for (final entry in pending.entries) {
    if (!next.events.containsKey(entry.key)) next = next.put('events', entry.key, entry.value);
  }
  return next;
}

/// Undoes [seedPending] for every record this edit left untouched and unnamed,
/// so nothing reaches the document, the undo stack, the journal or disk. A
/// record the edit DID change or point at is authored from here on: it leaves
/// [pending], so no later edit can weed it back out.
Document weedPending(Document document, Map<String, Event> pending) {
  var next = document;
  for (final id in pending.keys.toList()) {
    final held = next.events[id];
    if (held == null) continue;
    if (jsonEncode(held.toJson()) != jsonEncode(pending[id]!.toJson()) || _named(next, id)) {
      pending.remove(id);
      continue;
    }
    next = next.remove('events', id);
  }
  return next;
}

/// Does any record name [id]? The declared reference graph, asked in the one
/// direction [namedBy] answers -- a placement, a membership, a containment, a
/// staple end, a pattern's template, an override's replacement, all at once.
bool _named(Document document, String id) => recordMapsTyped.any(
  (map) =>
      map != 'events' && document.records(map).values.any((record) => namedBy(record).contains(id)),
);
