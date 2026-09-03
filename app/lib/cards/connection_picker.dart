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
import '../core/indexes.dart';
import '../core/math.dart';
import '../core/pile_search.dart';
import '../core/projection.dart';
import '../core/records.dart';
import 'card_chrome.dart';

/// Something a connection can reach: a frame or an object.
typedef Connectable = ({String id, String label, String kind});

/// What one search came to. [more] is a LOWER BOUND on what was left unlisted.
typedef ConnectableHits = ({List<Connectable> hits, int more, bool scanned});

/// A WINDOWED, RANKED FIND OVER THE WHOLE DOCUMENT.
///
/// ISSUES 9.2 (Don, on 50 frames and 3,200 objects): this swept the record maps
/// linearly and stopped at [scan] RECORDS, so the tail of the document could not
/// be found by any query and the twelve rows shown were the first twelve
/// substring matches in map order rather than the best. A budget must bound
/// WORK, never DATA -- so the titles are indexed ([TitleIndex], built once per
/// document generation beside every other index) and the index is consulted in
/// full. Every title is findable by its own words at any document size.
///
/// [window] is how many rows a surface will draw and [more] is an honest lower
/// bound on the rest. [scan] survives as what it should always have been: a cap
/// on the ORDERING work, and because candidates arrive best-tier first it can
/// only cost order among equals -- never findability.
/// DOES THIS QUERY SPEAK THE PILE GRAMMAR (ISSUES 9.2: "it is a search term,
/// not a new panel")?
///
/// It does when it NAMES one of the graph measures. Parsing alone cannot be the
/// test -- a bare word parses as an identifier in the one math, and "orphan" is
/// a thing people type looking for a title. So the door is the vocabulary: a
/// query that says `staples`, `unresolved` or `neighbours` is asking about the
/// graph, and every other query is the title find it always was.
bool speaksPileGrammar(String query) {
  for (final measure in const [stapleCountName, unresolvedCountName, neighbourCountName]) {
    if (RegExp(r'\b' + measure + r'\b').hasMatch(query)) return true;
  }
  return false;
}

ConnectableHits searchConnectables(
  Document document,
  String query, {
  required int window,
  required int scan,
  String? exclude,
  bool frames = true,
  bool objects = true,
  ProjectionEngine? engine,
}) {
  if (query.trim().isEmpty) return (hits: const [], more: 0, scanned: false);
  // THE PILE GRAMMAR, IN THE BOX A PERSON ALREADY TYPES INTO. One search
  // surface: `staples == 0` finds the orphans here, exactly as it does
  // anywhere else, and a query the algebra refuses falls back to the title find
  // rather than answering nothing.
  if (objects && speaksPileGrammar(query)) {
    try {
      final over = engine ?? ProjectionEngine(document);
      final found = searchPile(over, query, window: window);
      final index = titleIndexOf(document);
      final hits = [
        for (final id in found.ids)
          if (id != exclude)
            (id: id, label: index.labelOf(id), kind: index.kindOf(id)),
      ];
      return (hits: hits, more: found.more, scanned: true);
    } on MathRefusal {
      // Not a sentence the algebra can read, so it was never a pile search.
    }
  }
  final index = titleIndexOf(document);
  final matches = index.matching(query);
  final candidates = <({String id, int tier})>[];
  var more = 0;
  for (final entry in matches.entries) {
    if (entry.key == exclude) continue;
    final kind = index.kindOf(entry.key);
    if (kind == 'frame' && !frames) continue;
    if (kind == 'object' && !objects) continue;
    // THE SCAN CAPS THE WORK, and stopping is the cap. Counting on past it
    // would be work the budget said not to do -- [more] is a LOWER bound on
    // what was left, and zero is a lower bound like any other.
    if (candidates.length >= scan) break;
    candidates.add((id: entry.key, tier: entry.value));
  }
  // AMONG EQUALS, THE MOST CONNECTED FIRST. The pile is a graph, so project the
  // graph: a thing already stapled to six others is what a person reaching for a
  // name is reaching for. Label and id follow only as a total, deterministic
  // tie-break, so two windows looking at one document show the same rows.
  candidates.sort((left, right) {
    if (left.tier != right.tier) return left.tier - right.tier;
    final byDegree = index.degreeOf(right.id) - index.degreeOf(left.id);
    if (byDegree != 0) return byDegree;
    final byLabel = index.labelOf(left.id).compareTo(index.labelOf(right.id));
    return byLabel != 0 ? byLabel : left.id.compareTo(right.id);
  });
  final hits = [
    for (final candidate in candidates.take(window))
      (id: candidate.id, label: index.labelOf(candidate.id), kind: index.kindOf(candidate.id)),
  ];
  return (hits: hits, more: more + (candidates.length - hits.length), scanned: true);
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
