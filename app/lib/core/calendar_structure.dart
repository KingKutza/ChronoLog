// Frame and coordinate-structure AUTHORING.
//
// This is the surface a field report found missing: "When I go into wall time
// there is no section to definecalendar structure, which is weird as that is the
// frame defining the inherited calendar structure. and when I go into my personal
// calendar using Wall Time as a basis to override the list of week day names,
// with Mon,Tue,Batman,Thu,Fri,Sat,Sun I get an error telling me I have to define
// the same number of days, which is weird as I did define the same number of
// days."
//
// Both halves of that report are rulings here.
//
//   * STRUCTURE AUTHORING FOLLOWS THE COORDINATE CAPABILITY, not the `calendar`
//     trait. `frame:wall-time` is a LINE and is also the frame every derived
//     calendar inherits its structure from; gating on "calendar" withheld the
//     whole surface from it.
//   * A NAME LIST IS CHECKED AGAINST THE COUNT ITS OWN MEANING REQUIRES, never a
//     neighbouring count that happens to sit nearby in the schema. Seven weekday
//     names belong to a seven-long CYCLE, not to a level whose parent holds
//     twenty-eight to thirty-one of them -- and a level whose count VARIES cannot
//     be named one at a time at all. Every refusal states BOTH counts, because an
//     author cannot correct a mismatch that is never shown to them.
//
// THE LAW IS THE ARBITER. [buildCoordinateStructure] validates by CONSTRUCTING A
// REAL [CoordinateLaw]: an unknown transition, a mixed calendar family, or a
// ladder no family can execute is refused at authoring time in the law's own
// words rather than discovered at render time. An editor that accepts an edit and
// ignores it is worse than one that refuses it.
//
// WHAT DIED. The fixed-calendar BUILDER and its `matchesFixedBlock` drift
// detector are gone: the `levels` ladder is the single authority, and a second
// summary of the same structure could only ever disagree with it. Its
// ladder-producing path is this module's own -- a row with a name and a count IS
// a level -- so nothing was lost with it. A `fixed` block an existing document
// carries is preserved untouched, because that same block is where the frozen
// declaration layer reads `smallestUnitDays` and `epochDays` from.

import 'coordinate_law.dart';
import 'eras.dart';
import 'exact.dart';
import 'records.dart';

// --- Frame authoring --------------------------------------------------------

/// The traits a kind CONTRIBUTES. Additive, never a replacement: the author's own
/// traits and whatever else the frame already carried all survive.
const Map<String, List<String>> traitsByFrameKind = {
  'calendar': ['set', 'calendar'],
  'group': ['set', 'group'],
  'importance': ['set', 'group', 'importance'],
  'cycle': ['circle', 'cycle'],
  'line': ['line', 'timeline'],
  'measure': ['measure'],
  'other': [],
};

List<String> additiveFrameTraits(
  String kind, [
  Iterable<String> entered = const [],
  Iterable<String> existing = const [],
]) => {
  for (final trait in [...existing, ...entered, ...?traitsByFrameKind[kind]])
    if (trait.isNotEmpty) trait,
}.toList();

typedef FrameCapabilities = ({
  bool basis,
  bool calendarStructure,
  bool observedBoundaries,
  bool coordinate,
  bool periodData,
});

/// What makes a frame temporal at all: it owns a coordinate, so it can author
/// that coordinate's structure.
const Set<String> _temporalKinds = {
  'calendar', 'cycle', 'line', 'timeline', 'measure', 'other', //
};

/// Which authoring surfaces a frame of this kind and these traits offers. Each
/// answer is a claim about what the frame IS, never about what it is called.
FrameCapabilities frameAuthoringCapabilities(String kind, [Iterable<String> traits = const []]) {
  final values = {kind, ...traits};
  bool any(Set<String> of) => of.any(values.contains);
  final temporal = any(_temporalKinds);
  return (
    basis: temporal,
    calendarStructure: temporal,
    observedBoundaries: any(const {'calendar', 'cycle'}),
    coordinate: temporal,
    periodData: any(const {'calendar', 'cycle', 'other'}),
  );
}

// --- Authored name lists ----------------------------------------------------

final RegExp _unitName = RegExp(r'^[a-z][a-z0-9-]*$', caseSensitive: false);
final RegExp _whole = RegExp(r'^[+-]?\d+$');

/// THE parser for every comma-separated list of authored names in the program.
/// Whitespace and a trailing comma are the author's typing, not an error.
List<String> parseNameList(Object? text) => [
  for (final name in text is Iterable ? text : declaredText(text).split(','))
    if (declaredText(name).isNotEmpty) declaredText(name),
];

/// THE count check. [required] null means the count varies, which is refused with
/// its reason rather than with a number the author can never satisfy.
///
/// A name is NOT required to be distinct: the letters of a word repeat, and a
/// fictional calendar may legitimately give two months the same name. What
/// distinctness protected was lookup-by-name, and an ambiguous name is a question
/// for whatever looks names up to refuse -- not a reason to forbid authoring it.
List<String> validateNameList(List<String> names, int? required, String subject, [String? unit]) {
  if (names.isEmpty) return names;
  if (required == null) {
    throw LawRefusal(
      '$subject varies in number, so its members cannot be named one at a time.'
      ' Name a repeating cycle instead (a seven-name week is a cycle, not a'
      ' level).',
    );
  }
  if (names.length != required) {
    throw LawRefusal(
      '$subject needs $required name${required == 1 ? '' : 's'}, one for each'
      ' ${unit ?? subject}; ${names.length}'
      ' ${names.length == 1 ? 'was' : 'were'} given.',
    );
  }
  return names;
}

// --- The coordinate declaration, as editable rows ---------------------------

/// A level whose count comes from a transition has no constant count to show.
const String countVaries = 'varies';

/// A level row as a form shows it. There is no `within` field: a level nests
/// inside the row above it, and a second statement of that could only ever
/// disagree with the ladder.
typedef LevelRow = ({String name, String count, String transition, String names});

typedef CycleRow = ({String name, String length, String phase, String names});

typedef CoordinateStructure = ({
  String kind,
  List<LevelRow> levels,
  List<CycleRow> cycles,
  String baseLevel,
  String origin,
});

/// The rows a form shows for a law, whether authored on this frame or inherited.
///
/// There is deliberately no `eras` field: an era is not a table on this
/// declaration. An era is its OWN FRAME, chained to its neighbours by a
/// succession staple, and authoring that chain is a staple concern.
CoordinateStructure? editableCoordinateStructure(CoordinateLaw? law) {
  if (law == null) return null;
  return (
    kind: law.declaration.kind,
    levels: [
      for (final (index, level) in law.levels.indexed)
        (
          name: level.name,
          count: level.radix?.toJson() ?? '',
          transition: level.transition ?? (index > 0 && level.radix == null ? countVaries : ''),
          names: (level.names ?? law.namesFor(level.name) ?? const []).join(', '),
        ),
    ],
    // Every cycle in force, authored or inherited: a week is a CYCLE and not a
    // level, which is the whole content of the Batman fix.
    cycles: [
      for (final cycle in law.cycles())
        (
          name: cycle.name,
          length: cycle.radix.toJson(),
          phase: '${cycle.offset}',
          names: (cycle.names ?? const []).join(', '),
        ),
    ],
    // Only ever the AUTHORED value, never the law's inferred default: a plain
    // Gregorian ladder infers its base level and origin from its transitions,
    // and echoing that inference back as though it were authored would attach an
    // origin to a declaration that never asked for one.
    baseLevel: law.declaration.baseLevel ?? '',
    origin: law.declaration.origin ?? '',
  );
}

/// Every transition an author may pick, with the wording the form shows. One
/// list, from the registry, so the form can never offer a name the law refuses.
List<({String value, String label})> transitionChoices() => [
  (value: '', label: 'Fixed count'),
  for (final name in registeredTransitions())
    (value: name, label: '$name (${transitionDefinition(name)!.summary})'),
];

/// A trimmed level row with its names already parsed.
typedef _Row = ({String name, String count, String transition, List<String> names});

/// How many children a level's edge yields, for validating a names list against
/// it: an exact count for a fixed radix, null for a transition whose count varies
/// -- and a names list against one of those is refused, with the reason.
///
/// Takes the two fields it actually reads rather than a whole row, so the answer
/// cannot depend on anything else about the level.
int? requiredNameCount({required String name, String count = '', String transition = ''}) {
  final named = transition == countVaries ? '' : transition.trim();
  if (named.isNotEmpty) {
    final mean = transitionDefinition(named)?.meanChildren;
    return mean != null && mean.d == BigInt.one ? mean.n.toInt() : null;
  }
  return count.trim().isEmpty ? null : _positiveWhole(count.trim(), '$name count').n.toInt();
}

/// The authoring surface's own count refusal, so the message names the field the
/// author typed in before its names are counted against it. The law re-checks
/// every radix independently; this exists for the sentence, not the safety -- and
/// the sentence matters, because the JavaScript let its number parser's own
/// "Invalid exact number: twelve" reach the author instead.
Rational _positiveWhole(String value, String subject) {
  try {
    final parsed = Rational.parse(value);
    if (parsed > Rational.zero && parsed.d == BigInt.one) return parsed;
  } on FormatException {
    // Falls through to the author-facing refusal below.
  }
  throw LawRefusal('$subject must be a positive whole number.');
}

/// Build a coordinate declaration from edited rows, refusing in the author's own
/// words anything unresolvable.
///
/// [previous] carries every key this grid has never heard of straight through:
/// levels, cycles, base level and origin are its business, and a key it does not
/// know is data it has no business deleting.
Json buildCoordinateStructure({
  List<LevelRow> levels = const [],
  List<CycleRow> cycles = const [],
  String baseLevel = '',
  String origin = '',
  String kind = 'nested',
  Json? previous,
}) {
  final rows = <_Row>[
    for (final row in levels)
      if (_trim(row) case final it
          when it.name.isNotEmpty ||
              it.count.isNotEmpty ||
              it.transition.isNotEmpty ||
              it.names.isNotEmpty)
        it,
  ];
  if (rows.isEmpty) {
    throw const LawRefusal('A coordinate declaration needs at least one level.');
  }
  final built = <Json>[];
  for (final (index, row) in rows.indexed) {
    if (!_unitName.hasMatch(row.name)) {
      throw LawRefusal('Level ${index + 1} needs a simple name (letters, numbers, or hyphens).');
    }
    if (rows.take(index).any((seen) => seen.name.toLowerCase() == row.name.toLowerCase())) {
      throw LawRefusal('Level "${row.name}" is declared twice.');
    }
    if (index > 0 && row.transition.isNotEmpty && row.count.isNotEmpty) {
      throw LawRefusal(
        'Level "${row.name}" has both a count and a transition;'
        ' it takes one or the other.',
      );
    }
    // An unimplemented transition is refused BEFORE its names are counted:
    // otherwise the author is told their name list is the wrong length when the
    // real problem is that nothing can count the level at all.
    if (index > 0 && row.transition.isNotEmpty) {
      assertTransition(row.transition, 'Level "${row.name}"');
    }
    validateNameList(
      row.names,
      index == 0
          ? null
          : requiredNameCount(name: row.name, count: row.count, transition: row.transition),
      '${row.name} names',
      row.name,
    );
    final fixed = index > 0 && row.transition.isEmpty && row.count.isNotEmpty;
    built.add({
      'name': row.name,
      if (index > 0) 'within': rows[index - 1].name,
      if (index > 0 && row.transition.isNotEmpty) 'transition': row.transition,
      if (fixed) 'radix': _positiveWhole(row.count, '${row.name} count').toJson(),
      if (row.names.isNotEmpty) 'names': row.names,
    });
  }
  final builtCycles = <Json>[];
  for (final row in cycles) {
    final name = row.name.trim();
    final length = row.length.trim();
    final names = parseNameList(row.names);
    if (name.isEmpty && length.isEmpty && names.isEmpty) continue;
    if (!_unitName.hasMatch(name)) {
      throw const LawRefusal('A cycle needs a simple name (letters, numbers, or hyphens).');
    }
    final radix = _positiveWhole(length, 'The "$name" cycle length');
    validateNameList(names, radix.n.toInt(), 'The "$name" cycle', name);
    final phase = row.phase.trim().isEmpty ? '0' : row.phase.trim();
    if (!_whole.hasMatch(phase)) {
      throw LawRefusal('The "$name" cycle phase must be a whole number of units.');
    }
    builtCycles.add({
      'name': name,
      'radix': radix.toJson(),
      'offset': phase,
      if (names.isNotEmpty) 'names': names,
    });
  }
  // `baseLevel`/`origin` are what a wholly invented, uniform ladder (no
  // registered transition anywhere in it) needs to become positional at all:
  // baseLevel says which level is one day, origin says the exact day ordinal its
  // first unit begins on. Blank fields are OMITTED rather than stored empty, so a
  // document that never authored either stays byte-identical to one that still
  // doesn't -- which is why the three optional keys are dropped from whatever
  // `previous` carried and only then put back.
  final base = baseLevel.trim(), from = origin.trim();
  final declaration = <String, dynamic>{...?previous, 'kind': kind}
    ..remove('cycles')
    ..remove('baseLevel')
    ..remove('origin')
    ..['levels'] = built;
  if (builtCycles.isNotEmpty) declaration['cycles'] = builtCycles;
  if (base.isNotEmpty) declaration['baseLevel'] = base;
  if (from.isNotEmpty) declaration['origin'] = {'days': from};
  // The law is the arbiter. If it cannot be constructed, the declaration is not
  // authorable, and the author gets the law's own sentence rather than a render
  // that silently means something else.
  CoordinateLaw.parse(declaration);
  return declaration;
}

/// A one-line, author-facing summary of what a declaration adds up to.
String coordinateStructureSummary(Json? declaration) {
  final law = CoordinateLaw.parse(declaration);
  if (law.levels.isEmpty) return 'No levels declared.';
  final root = law.levels.first;
  final rootDays = law.meanUnitDays(root.name);
  return [
    rootDays == null
        ? 'One ${root.name} has no fixed length.'
        : 'One ${root.name} = ${rootDays.toJson()} days'
              ' (${rootDays.toDecimal(6)}).',
    for (final level in law.levels.skip(1))
      '${level.radix?.toJson() ?? transitionDefinition(level.transition ?? '')?.summary ?? countVaries}'
          ' ${level.name} per ${level.within}',
  ].join(' ');
}

/// A level row as the author left it, trimmed, with its names parsed. A row
/// reading back as "varies" carries the FORM's word for "no fixed count", never a
/// transition name to store.
_Row _trim(LevelRow row) => (
  name: row.name.trim(),
  count: row.count.trim(),
  transition: row.transition == countVaries ? '' : row.transition.trim(),
  names: parseNameList(row.names),
);
