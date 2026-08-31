// The far-end typeahead.
//
// OVERSCALE. The web build enumerated and sorted every event in the document
// into one `<select>`, once per open card, rebuilt on every scope change --
// "at 500 calendars this is the worst chrome path in the app". Nothing here
// enumerates: an empty query lists nothing, a query walks a bounded scan, and
// the overflow is reported as a LOWER BOUND ("+48") exactly as a lens reports a
// truncated fact window.
//
// A hit is a title and a kind, never a bare record id.

import 'package:flutter/material.dart';

import '../chrome/controls.dart';
import '../core/records.dart';
import 'card_chrome.dart';

/// Something a connection can reach: a frame or an object.
typedef Connectable = ({String id, String label, String kind});

/// What one search came to. [more] is a LOWER BOUND on what was left unlisted.
typedef ConnectableHits = ({List<Connectable> hits, int more, bool scanned});

String _titleOf(Object record) => switch (record) {
  Frame(:final title, :final id) => (title ?? '').trim().isEmpty ? id : title!.trim(),
  Event(:final payload, :final id) =>
    (str(payload?['title']) ?? '').trim().isEmpty ? id : str(payload!['title'])!.trim(),
  _ => '',
};

/// A windowed find over the document: never a full enumeration, and never a
/// sort of everything. The first [window] title matches in map order, plus how
/// many more the bounded scan saw.
ConnectableHits searchConnectables(
  Document document,
  String query, {
  required int window,
  required int scan,
  String? exclude,
  bool frames = true,
  bool objects = true,
}) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return (hits: const [], more: 0, scanned: false);
  final hits = <Connectable>[];
  var more = 0, seen = 0;
  void sweep(Iterable<DocumentRecord> records, String kind) {
    for (final record in records) {
      if (seen++ >= scan) return;
      if (record.id == exclude) continue;
      final label = _titleOf(record);
      if (!label.toLowerCase().contains(needle)) continue;
      hits.length < window ? hits.add((id: record.id, label: label, kind: kind)) : more += 1;
    }
  }

  if (frames) sweep(document.frames.values, 'frame');
  if (objects) sweep(document.events.values, 'object');
  return (hits: hits, more: more, scanned: true);
}

/// A find box whose hits are the only list it ever draws.
class ConnectionPicker extends StatefulWidget {
  const ConnectionPicker({
    super.key,
    required this.document,
    required this.onPicked,
    this.hint = 'Find a frame or an object',
    this.exclude,
    this.frames = true,
    this.objects = true,
    this.onCreate,
  });

  final Document document;
  final void Function(Connectable) onPicked;
  final String hint;
  final String? exclude;
  final bool frames, objects;

  /// Makes what nothing is called yet, by kind and by the typed name.
  ///
  /// ISSUES (8.31): "Typing a frame name that does not exist offers to
  /// instantiate it, opening a second card to set that frame up", and
  /// SENTENCES.md rules the same for objects. Absent, a name nothing wears is
  /// reported and nothing is offered -- stated, never a dead click.
  final void Function(String kind, String name)? onCreate;

  @override
  State<ConnectionPicker> createState() => _ConnectionPickerState();
}

class _ConnectionPickerState extends State<ConnectionPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final found = searchConnectables(
      widget.document,
      _query,
      window: cardPx(context, 'card.searchWindow').round(),
      scan: cardPx(context, 'card.searchScan').round(),
      exclude: widget.exclude,
      frames: widget.frames,
      objects: widget.objects,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        CardField(
          value: _query,
          hint: widget.hint,
          onChanged: (text) => setState(() => _query = text),
        ),
        if (!found.scanned)
          cardNote(context, 'Type to find one — the whole document is never listed.')
        else if (found.hits.isEmpty)
          // A NAME NOTHING WEARS IS AN OFFER, not a dead end: making it is one
          // tap, and the thing made opens its own card to be set up.
          cardWrap(context, [
            cardNote(context, 'Nothing here is called that.'),
            if (widget.onCreate case final void Function(String, String) make)
              for (final kind in [
                if (widget.frames) 'frame',
                if (widget.objects) 'object',
              ])
                namedAction(
                  context,
                  'Create $kind "${_query.trim()}"…',
                  hint: 'Makes it and opens its card.',
                  onTap: () {
                    make(kind, _query.trim());
                    setState(() => _query = '');
                  },
                ),
          ])
        else
          cardWrap(context, [
            for (final hit in found.hits)
              cardLink(context, '${hit.kind == 'frame' ? '▤' : '●'} ${hit.label}', () {
                widget.onPicked(hit);
                setState(() => _query = '');
              }),
          ]),
        // A lower bound, never a silent drop.
        if (found.more > 0) cardNote(context, '+${found.more} more — narrow the find.'),
      ],
    );
  }
}
