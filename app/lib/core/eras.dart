// Pure Dart. Nothing under lib/core/ may import Flutter or a third-party
// package.
//
// True eras. Owner ruling: "Hard No. Epochs, true epochs no faking" — an era is
// a level of the coordinate itself, not a display label pasted over a proleptic
// year. An era-qualified coordinate stores the ERA and the year WITHIN it, never
// the linearized year, because a record that kept the linearization plus a label
// would silently re-anchor every date the moment an era's span were corrected.
// And an era may count DOWN, which no single continuous axis can express at all:
// 2500 BCE is older than 44 BCE while 44 CE is newer than 1 CE.
//
// This file is document-free. It converts between an era-qualified year and a
// PROPER YEAR (the integer index the frame's own year ladder counts in), formats
// and parses era-qualified text, and refuses a table it cannot resolve. Turning
// a proper year into days is coordinate_law.dart's job, because that depends on
// how long a year is — the year ladder's business, not the table's.

/// A refusal in the author's own words.
///
/// Every failure in this file and in coordinate_law.dart is one of these, so a
/// surface reports the sentence verbatim rather than translating an exception
/// class into prose of its own. The refusal message IS the contract: an author
/// who hand-edits a declaration and one who uses a form see the same sentence.
class LawRefusal implements Exception {
  const LawRefusal(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The sentence to report for any thrown value. Non-refusals (a malformed
/// number reaching arithmetic) still carry text an author can act on.
String refusalText(Object error) => error is LawRefusal ? error.message : '$error';

/// The first item satisfying [test], or null. Declared here, alongside the
/// refusal vocabulary and the two integer readers, because coordinate_law.dart
/// already imports this file for [EraTable] and duplicating them would put the
/// same four lines in two places.
T? firstMatch<T>(Iterable<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}

/// An authored field as text: absent, null, and blank are one state.
String declaredText(Object? value) => (value ?? '').toString().trim();

final RegExp _wholePattern = RegExp(r'^[+-]?\d+$');
final RegExp _digits = RegExp(r'^\d+$');
// No leading whitespace, and no comma or semicolon anywhere: an era name has to
// survive both a parsed list and a parsed coordinate.
final RegExp _eraName = RegExp(r'^[^\s,;][^,;]*$');

BigInt wholeBigInt(Object? value, String label) {
  final text = declaredText(value);
  if (!_wholePattern.hasMatch(text)) {
    throw LawRefusal('$label must be a whole number.');
  }
  return BigInt.parse(text);
}

BigInt _positiveBigInt(Object? value, String label) {
  final parsed = wholeBigInt(value, label);
  if (parsed <= BigInt.zero) {
    throw LawRefusal('$label must be greater than zero.');
  }
  return parsed;
}

Map<String, Object?>? asMap(Object? value) =>
    value is Map ? {for (final entry in value.entries) '${entry.key}': entry.value} : null;

List<Object?> asList(Object? value) => value is List ? value : const [];

/// Which end of an era's span may be open, per direction. An era with no `years`
/// is OPEN, and only one end of the table can be open in each direction: a
/// descending open era counts upward as it goes back, so it can only be listed
/// FIRST; an ascending open era can only be listed LAST. An ascending era open
/// at the bottom would have to start at negative infinity, and a descending era
/// open at the top would have to count down from it. Both are refused rather
/// than clamped to something invented.
const List<String> eraDirections = ['ascending', 'descending'];

/// One era.
///
/// [key] is the era's stored identity — what a coordinate's era actually holds
/// ("3E"), as short and stable as a record needs. [name] is the human label and
/// may be rewritten without touching a single stored coordinate.
///
/// [firstProper] and [lastProper] are ascending-order bounds in PROPER YEARS
/// regardless of which way this era's own numbering runs; null means open at
/// that end. They are derived by [EraTable] from its single anchor and are the
/// only mutable state here — written once during construction, before the table
/// is published, so a resolved table is effectively immutable.
class EraEntry {
  EraEntry(
    this.name,
    this.key,
    this.direction,
    this.years,
    this.firstYear,
    this.affix,
    this.ordinal,
  );

  /// The authored row, refused rather than repaired. `abbrev`/`abbreviation` are
  /// accepted spellings of `key`, and `"open"` is an open span rather than a
  /// length — reading it as one would be a silent misparse.
  factory EraEntry.parse(Map<String, Object?>? entry, int index) {
    final name = declaredText(entry?['name']);
    if (name.isEmpty || !_eraName.hasMatch(name)) {
      throw LawRefusal('Era ${index + 1} needs a name (no commas or semicolons).');
    }
    var key = declaredText(entry?['key']);
    if (key.isEmpty) key = declaredText(entry?['abbrev']);
    if (key.isEmpty) key = declaredText(entry?['abbreviation']);
    if (key.isEmpty) key = name;
    if (!_eraName.hasMatch(key)) {
      throw LawRefusal('The "$name" era\'s key cannot contain a comma or semicolon.');
    }
    // A purely numeric key or name would make "12 34" unreadable — there would
    // be no way to tell the era from the year. Refusing it here is what lets
    // `parse` treat the numeric token as the year with nothing left to guess.
    for (final token in [name, key]) {
      if (_digits.hasMatch(token)) {
        throw LawRefusal(
          'An era cannot be called "$token"; a number alone cannot be told apart from a year.',
        );
      }
    }
    final direction = entry?['direction'] == null ? 'ascending' : declaredText(entry!['direction']);
    if (!eraDirections.contains(direction)) {
      throw LawRefusal(
        'The "$name" era\'s numbering must be ascending or descending, not "$direction".',
      );
    }
    final declaredYears = declaredText(entry?['years']);
    final open = declaredYears.isEmpty || declaredYears.toLowerCase() == 'open';
    final affix = entry?['affix'] == null ? 'prefix' : declaredText(entry!['affix']);
    if (affix != 'prefix' && affix != 'suffix') {
      throw LawRefusal('The "$name" era\'s label must sit before or after its year, not "$affix".');
    }
    final ordinal = declaredText(entry?['ordinal']);
    // `firstYear` is which number an era's years START at, authored rather than
    // assumed: an era counting its first year as 0 is a convention, not an error.
    return EraEntry(
      name,
      key,
      direction,
      open ? null : _positiveBigInt(declaredYears, 'The "$name" era\'s length'),
      wholeBigInt(entry?['firstYear'] ?? '1', 'The "$name" era\'s first year'),
      affix,
      ordinal.isEmpty ? null : wholeBigInt(ordinal, 'The "$name" era\'s ordinal'),
    );
  }

  final String name, key, direction, affix;
  final BigInt? years, ordinal;
  final BigInt firstYear;
  BigInt? firstProper, lastProper;

  bool get open => years == null;
  bool get descending => direction == 'descending';

  /// The stored identity under its other authored spelling.
  String get abbrev => key;
}

/// An era-qualified year as text names these two things and nothing else.
typedef EraQualified = ({String era, String year});

/// A proper year resolved back to the era that owns it plus the year within.
typedef EraYear = ({EraEntry entry, BigInt year});

/// The one anchor: "this era's year N is proper year P".
typedef EraAnchor = ({String era, BigInt year, BigInt properYear});

class EraTable {
  EraTable._(this.entries, this.anchor);

  /// Every other era's range derives from ONE anchor plus the bounded spans,
  /// which is what keeps the arithmetic exact and the authoring honest: the
  /// author states one alignment they actually know rather than a per-era offset
  /// table nobody can verify.
  factory EraTable.parse(Map<String, Object?>? declaration) {
    final rows = asList(declaration?['entries']);
    if (rows.isEmpty) {
      throw const LawRefusal('An era table needs at least one era.');
    }
    final entries = [for (final (index, row) in rows.indexed) EraEntry.parse(asMap(row), index)];
    _order(entries);
    _assertDistinctTokens(entries);
    _assertOpennessLegal(entries);
    final anchor = _parseAnchor(asMap(declaration?['anchor']), entries);
    _resolveRanges(entries, anchor);
    return EraTable._(List.unmodifiable(entries), anchor);
  }

  final List<EraEntry> entries;
  final EraAnchor anchor;

  EraEntry? era(Object? token) {
    final wanted = declaredText(token).toLowerCase();
    if (wanted.isEmpty) return null;
    return firstMatch(
      entries,
      (entry) => entry.key.toLowerCase() == wanted || entry.name.toLowerCase() == wanted,
    );
  }

  /// The stored identities, which is what a coordinate's era holds.
  List<String> eraKeys() => [for (final entry in entries) entry.key];

  List<String> eraNames() => [for (final entry in entries) entry.name];

  /// The era a proper year falls in, or null when the year lies outside every
  /// declared era — a calendar closed at both ends genuinely has no year there,
  /// and inventing one is what "no faking" forbids.
  EraEntry? eraAtProperYear(BigInt properYear) => firstMatch(
    entries,
    (entry) =>
        (entry.firstProper == null || properYear >= entry.firstProper!) &&
        (entry.lastProper == null || properYear <= entry.lastProper!),
  );

  /// (era, yearWithinEra) to a proper year. Descending eras count backwards from
  /// their own newest year, which is where BCE's missing year zero comes from:
  /// 1 BCE and 1 CE are adjacent proper years 0 and 1, so nothing has to
  /// special-case a gap that was never there.
  BigInt toProperYear(Object? eraToken, Object? yearWithinEra) {
    final entry = era(eraToken);
    if (entry == null) {
      throw LawRefusal(
        '"${declaredText(eraToken)}" is not one of this calendar\'s eras (${eraKeys().join(', ')}).',
      );
    }
    final year = wholeBigInt(yearWithinEra, 'A year in "${entry.name}"');
    _assertYearInEra(entry, year);
    final offset = year - entry.firstYear;
    return entry.descending ? entry.lastProper! - offset : entry.firstProper! + offset;
  }

  /// The exact inverse of [toProperYear], refusing rather than clamping when the
  /// year is outside the calendar entirely.
  EraYear fromProperYear(BigInt properYear) {
    final entry = eraAtProperYear(properYear);
    if (entry == null) {
      throw LawRefusal(
        'Proper year $properYear falls outside every declared era of this calendar.',
      );
    }
    return (
      entry: entry,
      year:
          entry.firstYear +
          (entry.descending ? entry.lastProper! - properYear : properYear - entry.firstProper!),
    );
  }

  /// "3E 433", "ME 2500", "44 BCE" — the affix each era authored for itself.
  String format(Object? eraToken, Object? yearWithinEra) {
    final entry = era(eraToken);
    if (entry == null) {
      throw LawRefusal('"${declaredText(eraToken)}" is not one of this calendar\'s eras.');
    }
    final year = '$yearWithinEra';
    return entry.affix == 'suffix' ? '$year ${entry.key}' : '${entry.key} $year';
  }

  String formatProperYear(BigInt properYear) {
    final resolved = fromProperYear(properYear);
    return format(resolved.entry.key, resolved.year);
  }

  /// Text to (era, year), accepting an era's name or its key on either side of
  /// the number regardless of which affix that era formats with — a reader who
  /// types "433 3E" means the same date as "3E 433". Returns null when no era
  /// token is present at all, so a caller can tell "this names no era" apart
  /// from "this names an era I do not have".
  EraQualified? parse(Object? text) {
    final trimmed = declaredText(text);
    if (trimmed.isEmpty) return null;
    final tokens = [
      for (final token in trimmed.split(RegExp(r'[\s,]+')))
        if (token.isNotEmpty) token,
    ];
    if (tokens.length >= 2) {
      // The YEAR is the numeric token; everything else is the era, joined back
      // up so a multi-word name ("Third Era 433") resolves as readily as its
      // key. No era may be purely numeric, so exactly one end of the text can be
      // the number and there is nothing to disambiguate.
      final leadingYear = _digits.hasMatch(tokens.first);
      final trailingYear = _digits.hasMatch(tokens.last);
      if (leadingYear == trailingYear) return null;
      final entry = era(
        (leadingYear ? tokens.sublist(1) : tokens.sublist(0, tokens.length - 1)).join(' '),
      );
      return entry == null
          ? null
          : (era: entry.key, year: leadingYear ? tokens.first : tokens.last);
    }
    // A bare "3E433" cannot be split by shape: a key may itself contain digits,
    // so it is readable only BY THE AUTHORED NAMES — "3E" is an era and "3E4" is
    // not. Each era is tried as a literal prefix and suffix, and two eras
    // matching the same text is refused rather than resolved by precedence.
    final distinct = <String>{};
    EraQualified? candidate;
    final lower = trimmed.toLowerCase();
    for (final entry in entries) {
      for (final token in [entry.name, entry.key]) {
        final key = token.toLowerCase();
        String? year;
        if (lower.startsWith(key) && _digits.hasMatch(trimmed.substring(token.length))) {
          year = trimmed.substring(token.length);
        } else if (lower.endsWith(key) &&
            _digits.hasMatch(trimmed.substring(0, trimmed.length - token.length))) {
          year = trimmed.substring(0, trimmed.length - token.length);
        }
        if (year == null) continue;
        distinct.add('${entry.key}/$year');
        candidate ??= (era: entry.key, year: year);
      }
    }
    return distinct.length == 1 ? candidate : null;
  }

  /// The rows an authoring surface edits, in the order they are declared.
  Map<String, Object?> toDeclaration() => {
    'anchor': {'era': anchor.era, 'year': '${anchor.year}', 'properYear': '${anchor.properYear}'},
    'entries': [
      for (final entry in entries)
        {
          'name': entry.name,
          'key': entry.key,
          'direction': entry.direction,
          if (entry.years != null) 'years': '${entry.years}',
          if (entry.affix != 'prefix') 'affix': entry.affix,
        },
    ],
  };

  /// Human-readable ranges, for a form's live preview.
  String summary() => [
    for (final entry in entries)
      '${entry.key}: ${entry.years == null ? 'open-ended' : '${entry.years} years'},'
          ' ${entry.direction}, proper years'
          ' ${entry.firstProper ?? 'open'}..${entry.lastProper ?? 'open'}',
  ].join(' · ');
}

/// An explicit `ordinal` on every era is authoritative over the order they
/// happen to be listed in. Declaring it on SOME of them is refused rather than
/// half-honoured: a table half-ordered by ordinal and half by position has no
/// single answer to which era comes first.
void _order(List<EraEntry> entries) {
  final ordinals = [
    for (final entry in entries)
      if (entry.ordinal != null) entry,
  ];
  if (ordinals.isEmpty) return;
  if (ordinals.length != entries.length) {
    throw const LawRefusal(
      'Either every era declares an ordinal or none does; a partly-ordered table has no order.',
    );
  }
  if ({for (final entry in entries) entry.ordinal}.length != entries.length) {
    throw const LawRefusal(
      'Two eras share an ordinal; each must state its own place in the sequence.',
    );
  }
  entries.sort((left, right) => left.ordinal!.compareTo(right.ordinal!));
}

void _assertDistinctTokens(List<EraEntry> entries) {
  final seen = <String>{};
  for (final entry in entries) {
    for (final token in [entry.name, entry.key]) {
      if (!seen.add(token.toLowerCase())) {
        throw LawRefusal(
          'Two eras answer to "$token"; each name and abbreviation must be distinct.',
        );
      }
    }
  }
}

/// Openness has to be legal before any range can be derived: an open era in the
/// middle leaves both of its neighbours unresolvable.
void _assertOpennessLegal(List<EraEntry> entries) {
  for (final (index, entry) in entries.indexed) {
    if (!entry.open) continue;
    if (entry.descending && index != 0) {
      throw LawRefusal(
        'The "${entry.name}" era counts down with no stated length, so it is the'
        " calendar's oldest era and must be listed first.",
      );
    }
    if (!entry.descending && index != entries.length - 1) {
      throw LawRefusal(
        'The "${entry.name}" era counts up with no stated length, so it is the'
        " calendar's newest era and must be listed last.",
      );
    }
  }
}

EraAnchor _parseAnchor(Map<String, Object?>? anchor, List<EraEntry> entries) {
  final wanted = declaredText(anchor?['era']);
  final found = firstMatch(entries, (entry) => entry.key == wanted || entry.name == wanted);
  if (found == null) {
    throw LawRefusal(
      'The era table\'s anchor names "${wanted.isEmpty ? '(nothing)' : wanted}", which is'
      ' not one of its eras (${entries.isEmpty ? 'none declared' : [for (final entry in entries) entry.name].join(', ')}).',
    );
  }
  return (
    era: found.key,
    // Whole, not positive: an era may number its years from 0, and the anchor is
    // checked against that era's own span rather than against a presumed 1.
    year: wholeBigInt(anchor?['year'] ?? '1', "The anchor's year"),
    properYear: wholeBigInt(
      anchor?['properYear'] ?? anchor?['year'] ?? '1',
      "The anchor's proper year",
    ),
  );
}

void _assertYearInEra(EraEntry entry, BigInt year, [String prefix = 'There is']) {
  if (year < entry.firstYear) {
    throw LawRefusal(
      '$prefix year $year of "${entry.name}", which numbers its years from ${entry.firstYear}.',
    );
  }
  if (entry.years != null && year > entry.firstYear + entry.years! - BigInt.one) {
    throw LawRefusal(
      '$prefix year $year of "${entry.name}", which is only ${entry.years} years long.',
    );
  }
}

/// Ranges in PROPER YEARS, derived from the single anchor outward, with
/// contiguity and order CHECKED rather than assumed: a span that contradicts its
/// neighbours is refused here, before anything is stored.
void _resolveRanges(List<EraEntry> entries, EraAnchor anchor) {
  final anchorIndex = entries.indexWhere((entry) => entry.key == anchor.era);
  final anchored = entries[anchorIndex];
  _assertYearInEra(anchored, anchor.year, 'The anchor sits at');

  // For a descending era its FIRST-NUMBERED year is its newest, so the anchor
  // pins the era's upper bound; for an ascending era the first-numbered year is
  // its oldest, pinning the lower bound. `firstYear` is the number that first
  // year actually carries, so the offset is measured from it, not from a
  // presumed 1.
  final offset = anchor.year - anchored.firstYear;
  if (anchored.descending) {
    anchored.lastProper = anchor.properYear + offset;
    anchored.firstProper = anchored.years == null
        ? null
        : anchored.lastProper! - anchored.years! + BigInt.one;
  } else {
    anchored.firstProper = anchor.properYear - offset;
    anchored.lastProper = anchored.years == null
        ? null
        : anchored.firstProper! + anchored.years! - BigInt.one;
  }

  for (var index = anchorIndex + 1; index < entries.length; index += 1) {
    final previous = entries[index - 1];
    final entry = entries[index];
    if (previous.lastProper == null) {
      throw LawRefusal(
        '"${previous.name}" has no stated length, so "${entry.name}" cannot know where it begins.',
      );
    }
    entry.firstProper = previous.lastProper! + BigInt.one;
    entry.lastProper = entry.years == null ? null : entry.firstProper! + entry.years! - BigInt.one;
  }
  for (var index = anchorIndex - 1; index >= 0; index -= 1) {
    final next = entries[index + 1];
    final entry = entries[index];
    if (next.firstProper == null) {
      throw LawRefusal(
        '"${next.name}" has no stated beginning, so "${entry.name}" cannot know where it ends.',
      );
    }
    entry.lastProper = next.firstProper! - BigInt.one;
    entry.firstProper = entry.years == null ? null : entry.lastProper! - entry.years! + BigInt.one;
  }

  for (final (index, entry) in entries.indexed) {
    if (entry.firstProper != null &&
        entry.lastProper != null &&
        entry.firstProper! > entry.lastProper!) {
      throw LawRefusal('The "${entry.name}" era\'s length leaves it ending before it begins.');
    }
    if (index == 0) continue;
    final previous = entries[index - 1];
    if (previous.lastProper != null &&
        entry.firstProper != null &&
        previous.lastProper! + BigInt.one != entry.firstProper!) {
      throw LawRefusal(
        '"${previous.name}" ends at proper year ${previous.lastProper} but'
        ' "${entry.name}" begins at ${entry.firstProper}; eras must meet exactly,'
        ' with no gap and no overlap.',
      );
    }
  }
}

/// What a frame's place in the succession chain says about its era.
///
/// THE ERA IS THE FRAME. This is injected into a [CoordinateLaw] by the law
/// resolver — nothing about an era is read from a coordinate declaration. The
/// declaration describes the year ladder the era counts in, inherited from its
/// basis; the era supplies only where its own year 1 falls. So a coordinate on an
/// era frame carries a plain year, and the frame it is attached to is which era
/// it means.
///
/// `countable: false` is an era with no year axis at all: ordered and connected,
/// never acquiring day ordinals. Its law refuses conversion rather than
/// computing one.
class EraContext {
  EraContext.countable(EraTable this.table, EraEntry this.entry)
    : countable = true,
      key = null,
      name = null;

  EraContext.uncountable({required String this.key, required String this.name})
    : countable = false,
      table = null,
      entry = null;

  final bool countable;
  final EraTable? table;
  final EraEntry? entry;
  final String? key, name;

  /// The era's stored identity, whichever half of the model carries it.
  String? get identity => entry?.key ?? key;

  /// How this era names itself in a refusal.
  String get label => entry?.name ?? name ?? key ?? 'This era';
}
