// The shape half of the ToDo lenses.
//
// WHAT IS NOT HERE. The population half -- WHICH entries a lens sees -- became
// the projection engine's boolean algebra and left this layer entirely, and the
// state-gate that used to do that job here died with it: a ToDo whose state frame
// was unselected was silently dropped, in list.js and again byte-identically in
// board.js, and frame-selection-as-visibility is now expressed as NOT over
// connections. Nothing below asks which frames are selected.
//
// What remains is genuinely per-lens and genuinely shape: a section is a section
// because entries put it there. The four groupings are DATA, one shared list, not
// an enum -- and the state vocabulary is open strings, because the states are
// whichever state frames the document holds.

import 'object_kinds.dart';
import 'records.dart';

/// The groupings a ToDo lens can section by. List and Board carried identical
/// copies of this list; it is one list, and a fifth grouping is a row.
const List<String> lensGroupings = ['state', 'importance', 'container', 'frame'];

String normalizeGrouping(Object? value) =>
    lensGroupings.contains(value) ? value as String : 'state';

/// The state a row or card renders with, as one derivation for every lens.
///
/// `sparse` is the honest cheap title-only predicate: no state affiliation, no
/// group membership of any kind, no description, and no authored staple. `null`
/// is open-as-absence -- nothing to say, which is not the same as "open" being a
/// state somebody authored.
String? entryState(
  ObjectFacts facts,
  String objectId, {
  required List<String> stateFrames,
  required List<String> groups,
}) {
  // DONE IS A FRAME LIKE ANY OTHER (ISSUES 9.2). The second of the two readers
  // that used to return `done` for one hard-coded frame and `closed` for every
  // other; both go through the one predicate now and no id is read.
  if (resolvedByState(stateFrames)) return resolvedStateWord;
  final description = str(facts.document.events[objectId]?.payload?['description']);
  if ((description ?? '').trim().isNotEmpty || groups.isNotEmpty) return null;
  return facts.staples(objectId).isEmpty ? 'sparse' : null;
}

/// Where one entry belongs. A `null` key is the unnamed section -- Open, No
/// frame, No container -- and an entry may belong to several at once.
typedef Placement = ({String? key, String title, Object? meta});

typedef Section<T> = ({String? key, String title, List<T> entries, Object? meta});

/// Sections over an ALREADY-POPULATED entry list.
///
/// Empty sections are never emitted, by construction. The null section leads --
/// an unfiled capture must never be invisible or buried -- and named sections
/// follow in title order, broken by key so two same-titled frames keep a stable
/// order.
List<Section<T>> sectionsOf<T>(
  Iterable<T> entries,
  Iterable<Placement> Function(T entry) placementsOf,
) {
  final sections = <String?, Section<T>>{};
  for (final entry in entries) {
    for (final (key: key, title: title, meta: meta) in placementsOf(entry)) {
      (sections[key] ??= (key: key, title: title, entries: <T>[], meta: meta)).entries.add(entry);
    }
  }
  return sections.values.toList()..sort((left, right) {
    if (left.key == null) return -1;
    if (right.key == null) return 1;
    final byTitle = left.title.compareTo(right.title);
    return byTitle == 0 ? left.key!.compareTo(right.key!) : byTitle;
  });
}
