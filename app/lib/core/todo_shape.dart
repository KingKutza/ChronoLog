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
// because entries put it there.
//
// THREE GROUPINGS ARE ONE GROUPING (Don, ISSUES 9.2: "why is frame not the
// default, and what do state and importance indicate if both are staples to
// frames?"). State, container and frame all column an entry under THE RECORD AT
// THE FAR END OF A STAPLE, and differ only in which far ends they admit --
// state frames only; the objects that hold this one; everything. That is a
// FILTER over one grouping, not three groupings, so the reading is written once
// and the filter is the whole difference. FRAME IS THE UNFILTERED CASE, which
// is why it leads: the default is the first row of the table, never a word
// spelled in a return.
//
// WEIGHT is the odd one and survives separately, relabelled from "importance"
// on Don's own reading ("importance is weight, I assume, and should probably be
// relabeled for clarity"): it is not a staple at all, it bands the DERIVED
// display weight against this lens's own thresholds.
//
// AND EACH GROUPING CARRIES ITS OWN EVERYTHING -- its words, what it columns by,
// what its unnamed column is called, and which columns it can stand empty
// (ISSUES 9.2: "`_seed` switches on the grouping's NAME to decide what a capture
// is born holding -- a closed list deciding meaning, the kind the trinity
// forbids"). Nothing below switches on a grouping's name, and a fifth grouping
// is a row in the table.

import 'object_kinds.dart';
import 'records.dart';

/// One record at the far end of a connection, as a grouping reads it: what it
/// is, and whether it HOLDS the entry -- the authored order of a containment,
/// which is the one ruled carrier of direction.
typedef FarEnd = ({String id, Frame? frame, bool holder});

/// What a grouping columns one entry by: every far end the entry reaches, and
/// the weight band it landed in. A grouping reads whichever it is about.
typedef GroupingSubject = ({Iterable<FarEnd> farEnds, String band});

/// A grouping, whole: one row of the table, answering every question the two
/// roster lenses ask of it.
class TodoGrouping {
  const TodoGrouping({
    required this.key,
    required this.label,
    required this.reads,
    required this.unnamed,
    required this.columnsOf,
    this.standing = _nothingStands,
    this.columnTraits = const [],
  });

  /// The value a view holds, and the word the control reads. The key is a
  /// SPELLING -- an older view saying `importance` still means this row -- and
  /// the label is what a person is shown.
  final String key, label;

  /// What this grouping's columns READ, said in words above them, so a column
  /// that never appears is explained where it fails to appear.
  final String reads;

  /// What the column of entries this grouping has nothing to say about is
  /// called. It leads, and it is never empty.
  final String unnamed;

  /// The keys one entry columns under.
  final Iterable<String> Function(GroupingSubject subject) columnsOf;

  /// The columns that stand before anything is in them, where this grouping can
  /// name them at all: a filter over a bounded authored set can enumerate
  /// itself, and the unfiltered case cannot -- 500 calendars are not 500 empty
  /// columns waiting to be filled.
  final Iterable<String> Function(Iterable<Frame> frames) standing;

  /// The traits a frame minted AS ONE OF THIS GROUPING'S COLUMNS wears -- a
  /// group frame where the columns are frames, a state frame where they are
  /// states (ISSUES 9.2: "traits by grouping ... the same inline instantiation
  /// the sentence rows use"). Empty where a column of this grouping names no
  /// frame at all: a weight band is derived and nothing mints one, and a
  /// container column names an OBJECT, whose create door is the sentence row's
  /// own (ISSUES 9.2, "can I make a note?") rather than a frame wearing an
  /// object's job.
  final List<String> columnTraits;
}

Iterable<String> _nothingStands(Iterable<Frame> frames) => const [];

/// THE TABLE. The first row is the default, because the unfiltered reading is
/// what a person who has said nothing meant.
const List<TodoGrouping> todoGroupings = [
  TodoGrouping(
    key: 'frame',
    label: 'Frame',
    reads: 'Columns are every frame a to-do is stapled to, state frames included.',
    unnamed: 'No frame',
    columnsOf: _everyFrame,
    columnTraits: ['set', 'group'],
  ),
  TodoGrouping(
    key: 'importance',
    label: 'Weight',
    reads: 'Columns are bands of the composed display weight, against this lens own thresholds.',
    unnamed: 'Unweighed',
    columnsOf: _theBand,
  ),
  TodoGrouping(
    key: 'container',
    label: 'Container',
    reads: 'Columns are what holds a to-do.',
    unnamed: 'Held by nothing',
    columnsOf: _whatHoldsIt,
  ),
  TodoGrouping(
    key: 'state',
    label: 'State',
    reads: 'Columns are the state frames this document holds, empty ones included.',
    unnamed: 'Open',
    columnsOf: _stateFramesOnly,
    standing: _everyStateFrame,
    columnTraits: stateFrameTraits,
  ),
];

Iterable<String> _everyFrame(GroupingSubject subject) => [
  for (final end in subject.farEnds)
    if (end.frame != null) end.id,
];

Iterable<String> _stateFramesOnly(GroupingSubject subject) => [
  for (final end in subject.farEnds)
    if (isStateFrame(end.frame)) end.id,
];

Iterable<String> _whatHoldsIt(GroupingSubject subject) => [
  for (final end in subject.farEnds)
    if (end.holder) end.id,
];

Iterable<String> _theBand(GroupingSubject subject) => [subject.band];

Iterable<String> _everyStateFrame(Iterable<Frame> frames) => [
  for (final frame in frames)
    if (isStateFrame(frame)) frame.id,
];

/// The groupings a ToDo lens can section by. List and Board carried identical
/// copies of this list; it is one list, and a fifth grouping is a row.
List<String> get lensGroupings => [for (final grouping in todoGroupings) grouping.key];

/// The grouping a view value names, or the table's first row -- the unfiltered
/// one -- for a value the table does not hold.
TodoGrouping groupingFor(Object? value) {
  for (final grouping in todoGroupings) {
    if (grouping.key == value) return grouping;
  }
  return todoGroupings.first;
}

String normalizeGrouping(Object? value) => groupingFor(value).key;

/// WHAT A CAPTURE BORN IN A COLUMN IS BORN HOLDING, read from the column's own
/// far end rather than from the grouping's name (ISSUES 9.2). A state frame is
/// entered, an ordinary frame is stapled to, an object holds what is born in
/// it, and a column naming no record at all -- a weight band, an authored
/// expression -- seeds nothing, because a band is derived and nothing can be
/// born important.
Map<String, String> columnSeed(Document document, String? key) {
  if (key == null) return const {};
  final frame = document.frames[key];
  if (frame != null) return {isStateFrame(frame) ? 'state' : 'group': key};
  return document.events.containsKey(key) ? {'contains': key} : const {};
}

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
