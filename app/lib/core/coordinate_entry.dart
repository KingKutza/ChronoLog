// The placement field: ONE variable-precision coordinate entry, never separate
// date and time inputs. Owner's ruling: "a single field ... that allows for a
// variable precision entry, eg. Type month day year hour minute second
// millisecond, or pull a picker that lets you zoom it in."
//
// PRECISION TYPED IS COORDINATE DEPTH -- a [Coordinate] whose levels stop
// early, the same partial shape the rest of the model already reads. Depth is
// never fuzziness: no uncertainty or spread data is produced, inferred, or
// implied anywhere below. Meaning is authored elsewhere.
//
// Every level name, order, radix, value-name list and 0-vs-1-based numbering
// comes from the governing frame's own [CoordinateLaw]. Nothing here hardcodes
// twelve months, twenty-four hours or sixty minutes, and nothing here touches
// the Gregorian day kernel -- a custom calendar's field parses and formats in
// ITS OWN units, through the law it was handed.
//
// Pure and surface-free: this module parses text, formats text, and describes
// picker data. The widget that renders it is a different slice's job.

import 'dart:math';

import 'coordinate_law.dart';
import 'eras.dart';
import 'exact.dart';

/// Every separator a human actually types between coordinate values. Runs
/// collapse, and which character was used carries no positional meaning, so
/// "2026-08-20", "2026 8 20" and "2026.08.20" tokenize identically.
///
/// The one place a "." behaves specially is not here at all: it is the fact
/// that the trailing continuous-tail level always reinterprets its raw digits
/// as a fraction of its parent unit, whichever separator preceded them. That is
/// what makes "17:00:30.250" and "17 00 30 250" the same instant.
final RegExp _separators = RegExp(r'[\s\-/.,:]+');
final RegExp _wholeToken = RegExp(r'^\d+$');
final RegExp _nameToken = RegExp(r'^[A-Za-z]+$');

/// The low bound for a level's legal values. A level whose family default is
/// "1" counts from one (a Gregorian month, a Gregorian day); everything else --
/// every below-base level, and every level of a family-less custom law --
/// counts from zero. A rule about the DEFAULT, never a per-name list, so a
/// custom family's own defaults are read the same way.
BigInt _levelBase(CoordinateLaw law, String name) =>
    law.family?.defaults[name] == '1' ? BigInt.one : BigInt.zero;

/// The trailing level with neither radix nor transition -- the ladder's
/// continuous tail (Gregorian's `subsecond`). Only this level may ever carry a
/// fractional value, and only as the LAST declared level: by the law's own
/// construction rule it is the unique level whose count cannot be determined.
bool _isContinuousTail(CoordinateLaw law, int index) {
  final level = law.levels[index];
  return index == law.levels.length - 1 && level.radix == null && level.transition == null;
}

/// How many children a bounded level actually has, given the coarser values
/// already fixed above it. [parts] is keyed by level name exactly as a
/// transition's own `childrenIn` expects it, so a leap February answers 29 and
/// a common one 28. Null when the level is unbounded -- the root and the
/// continuous tail -- and there is no count to check against or enumerate.
BigInt? _childCount(CoordinateLaw law, Level level, Map<String, BigInt> parts) {
  if (level.radix != null) return level.radix!.n;
  final transition = level.transition;
  if (transition == null) return null;
  return transitionDefinition(transition)?.childrenIn(parts);
}

/// The proper year an era-local year resolves to, or null when this era has no
/// such year. The stored coordinate keeps the LOCAL year the author typed (433,
/// never 4249) while a transition below the year level -- Gregorian's leap
/// February -- resolves against the PROPER one: "45 BCE" is proper year -44 and
/// IS a leap year though neither two-digit form is divisible by four.
BigInt? _properYear(CoordinateLaw law, String localYear) {
  try {
    return law.eraTable!.toProperYear(law.eraKey(), localYear);
  } catch (_) {
    return null;
  }
}

/// The law's own level order, in the author's own names, for the one refusal
/// message every parse failure shares. The continuous tail is left out: it is
/// never typed as a standalone position, only attached as a fraction of the
/// level before it.
List<String> _guidanceLevels(CoordinateLaw law) {
  final names = law.levelNames();
  final trimmed = names.length > 1 && _isContinuousTail(law, names.length - 1)
      ? names.sublist(0, names.length - 1)
      : names;
  if (!law.hasEras() || trimmed.isEmpty) return trimmed;
  // The era and the year are typed as ONE position, not two: an era key alone
  // names no year, and a bare number alone does not say which era it counts in.
  // The era is the FRAME, not a level, so there is one year position -- written
  // bare ("433") or qualified with this era's own key ("3E 433").
  return ['${trimmed.first} (e.g. "${law.eraKey()} 1" or "1")', ...trimmed.skip(1)];
}

/// The sentence a refused entry gets, built from the law's OWN level names.
String coordinateEntryHelp(CoordinateLaw law) {
  final names = _guidanceLevels(law);
  if (names.isEmpty) return 'This frame declares no coordinate levels to enter.';
  if (names.length == 1) return 'Enter ${names.first} — as deep as you mean.';
  return 'Enter ${names.first}, then ${names.skip(1).join(', ')} — as deep as you mean.';
}

/// An authored name resolves by case-insensitive exact match first, then by
/// unambiguous prefix of three characters or more -- shorter is never attempted,
/// so "Ju" is refused rather than guessed at. Two names sharing a prefix is
/// refused, never guessed: the caller gets -1 for "no resolution", identically
/// whether the token matched nothing or matched more than one name.
///
/// The vocabulary handed in is the level's EFFECTIVE one -- [CoordinateLaw.namesFor],
/// which includes the names a law counting in the registered calendar inherits
/// rather than only the names its own declaration spells out.
///
/// RULED DIVERGENCE from the JavaScript, and the reason: `coordinate-entry.js`
/// reads the picker's labels through `namesFor` and the field's tokens through
/// the declaration's own `level.names`. Any ladder declaring
/// `transition: "gregorian.months"` without authoring names -- which every
/// era-chain fixture does -- therefore OFFERS "January" in the picker and
/// REFUSES it in the field, for the same level of the same law. The picker and
/// the field disagreeing about one law's vocabulary is an internal contradiction,
/// so the class is fixed here: what the picker offers, typing accepts.
int _resolveAuthoredName(String token, List<String> names) {
  final lower = token.toLowerCase();
  final exact = names.indexWhere((name) => name.toLowerCase() == lower);
  if (exact >= 0) return exact;
  if (token.length < 3) return -1;
  final matches = [
    for (final (index, name) in names.indexed)
      if (name.toLowerCase().startsWith(lower)) index,
  ];
  return matches.length == 1 ? matches.first : -1;
}

/// The value already fixed at [name], or null when the level was never typed --
/// distinct from [Coordinate.value]'s fallback-on-absence contract, because a
/// picker rung and a depth scan both need to tell "fixed at zero" apart from
/// "not fixed at all".
String? _fixed(Coordinate value, String name) =>
    firstMatch(value.levels, (entry) => entry.level == name)?.value;

/// A partial coordinate and the deepest level actually typed for it.
typedef CoordinateEntry = ({Coordinate coordinate, String? depth});

/// Text typed coarse-to-fine, in the law's own level order, to a partial
/// coordinate plus its authored depth.
///
/// Refuses -- never guesses -- anything the law cannot resolve: empty input,
/// more values than the law has levels, a token that is neither a whole number
/// nor an authored name, an ambiguous name prefix, or a value outside a level's
/// own declared range. Every refusal carries [coordinateEntryHelp].
CoordinateEntry parseCoordinateEntry(String? text, CoordinateLaw law) {
  Never fail() => throw LawRefusal(coordinateEntryHelp(law));

  var body = (text ?? '').trim();
  if (body.isEmpty) fail();
  var sign = BigInt.one;
  var hadSign = false;
  if (body.startsWith('+') || body.startsWith('-')) {
    sign = body.startsWith('-') ? -BigInt.one : BigInt.one;
    body = body.substring(1);
    hadSign = true;
  }

  final tokens = [
    for (final token in body.split(_separators))
      if (token.isNotEmpty) token,
  ];
  if (tokens.isEmpty) fail();
  // An era-qualified year spends TWO tokens on the one year level ("3E 433"),
  // so the budget allows one extra token when this law has eras. The per-level
  // walk below still refuses anything that does not actually resolve; this is
  // only the outer bound on how many tokens can ever apply.
  if (tokens.length > law.levels.length + (law.hasEras() ? 1 : 0)) fail();

  final parts = <String, BigInt>{};
  final entries = <LevelEntry>[];
  String? depth;

  // TWO CURSORS, because an era-qualified year spends two tokens on one level.
  // Walking a single index over both would slide every level below the year one
  // position out of step -- the day would be read as the hour.
  var levelIndex = 0;
  for (var index = 0; index < tokens.length; index += 1, levelIndex += 1) {
    if (levelIndex >= law.levels.length) fail();
    final level = law.levels[levelIndex];

    // An era frame's year may be written bare ("433") or QUALIFIED with the
    // era's own key ("3E 433"). The frame already fixes which era is meant, so
    // a qualifier CONFIRMS rather than selects: one naming a different era is
    // refused outright instead of silently retargeting the coordinate onto a
    // frame the caller never asked for.
    if (law.hasEras() && level.name == law.yearLevel) {
      final next = index + 1 < tokens.length ? tokens[index + 1] : '';
      final qualified = law.parseYear('${tokens[index]} $next'.trim());
      if (qualified != null) {
        // An era-qualified year already states its own direction.
        if (hadSign || qualified.era != law.eraKey()) fail();
        final proper = _properYear(law, qualified.year);
        if (proper == null) fail();
        entries.add((level: level.name, value: qualified.year));
        parts[level.name] = proper;
        depth = level.name;
        index += 1;
        continue;
      }
    }

    final token = tokens[index];

    if (_isContinuousTail(law, levelIndex)) {
      if (!_wholeToken.hasMatch(token)) fail();
      entries.add((level: level.name, value: '0.$token'));
      depth = level.name;
      continue;
    }

    final BigInt value;
    final vocabulary = law.namesFor(level.name);
    if (_wholeToken.hasMatch(token)) {
      value = BigInt.parse(token) * (levelIndex == 0 ? sign : BigInt.one);
    } else if (vocabulary != null && _nameToken.hasMatch(token)) {
      final found = _resolveAuthoredName(token, vocabulary);
      if (found < 0) fail();
      value = _levelBase(law, level.name) + BigInt.from(found);
    } else {
      fail();
    }

    final count = _childCount(law, level, parts);
    if (count != null) {
      final base = _levelBase(law, level.name);
      if (value < base || value >= base + count) fail();
    }

    // A bare year on an era law still has to be a year this era HAS, and the
    // level below it still needs the PROPER year for its own count -- the same
    // rule as the qualified branch, so a leap 29th resolves correctly whether
    // or not the era was spelled out.
    if (law.hasEras() && level.name == law.yearLevel) {
      final proper = _properYear(law, '$value');
      if (proper == null) fail();
      parts[level.name] = proper;
    } else {
      parts[level.name] = value;
    }
    entries.add((level: level.name, value: '$value'));
    depth = level.name;
  }

  return (coordinate: Coordinate(entries), depth: depth);
}

/// THE authored-precision derivation: the deepest level of THIS law's ladder the
/// coordinate actually names, in the law's own order, or null for a coordinate
/// that names none of them. A level the law does not declare is ignored, never
/// mistaken for depth.
///
/// Exported prominently because precision IS depth and two consumers outside
/// this module need the same answer: the staple substrate's partition-close
/// rule (a coordinate at or above the base names a PERIOD and closes at its
/// last instant) and the projection engine's `authoredPrecision`. One
/// derivation, so they cannot disagree about what an author wrote.
String? authoredDepth(Coordinate value, CoordinateLaw law) {
  String? deepest;
  for (final level in law.levels) {
    if (value.has(level.name)) deepest = level.name;
  }
  return deepest;
}

/// The signature a consumer injects for [authoredDepth], so a projection can ask
/// for authored precision without importing entry parsing.
typedef AuthoredDepthOf = String? Function(Coordinate value, CoordinateLaw law);

/// A bounded level's own digit width -- the digit length of its own count -- so
/// [formatCoordinateEntry] zero-pads to what THIS law's level actually spans,
/// never to a hardcoded width of two.
String _padded(BigInt value, BigInt count) {
  final digits = value.abs().toString().padLeft('$count'.length, '0');
  return value.isNegative ? '-$digits' : digits;
}

/// The continuous tail's stored value is a fraction of its parent unit
/// (0 <= value < 1, "0.25" for a quarter second). Formatting strips the leading
/// "0." so the digits printed are exactly the digits [parseCoordinateEntry]
/// would reattach a "0." to on the way back in.
String _tailDigits(String raw) {
  final value = Rational.parse(raw);
  if (value < Rational.zero || value >= Rational.one) {
    throw RangeError('A trailing fractional coordinate value must be between 0 and 1 (got $raw).');
  }
  final decimal = value.toDecimal(18);
  final dot = decimal.indexOf('.');
  return dot == -1 ? '0' : decimal.substring(dot + 1);
}

/// The canonical text for a coordinate, at exactly its own depth.
///
/// Always numeric -- authored names are never emitted, so the round trip back
/// through [parseCoordinateEntry] is unambiguous: "-" between above-base levels,
/// a space before the first below-base level, ":" between below-base levels.
String formatCoordinateEntry(Coordinate value, CoordinateLaw law) {
  final depthName = authoredDepth(value, law);
  if (depthName == null) return '';
  final baseIndex = law.levels.indexWhere((level) => level.name == law.baseLevel);
  final depthIndex = law.levels.indexWhere((level) => level.name == depthName);
  final parts = <String, BigInt>{};
  final text = StringBuffer();

  // One punctuation rule, shared by the era-qualified token and every ordinary
  // one below it, so the era case is not a second divergent copy.
  void place(int index, String display) => text.write(switch (index) {
    0 => display,
    _ when index <= baseIndex => '-$display',
    _ when index == baseIndex + 1 => ' $display',
    _ => ':$display',
  });

  for (var index = 0; index <= depthIndex; index += 1) {
    final level = law.levels[index];
    final raw = _fixed(value, level.name);
    if (raw == null) {
      throw LawRefusal(
        'Coordinate is missing level "${level.name}" between the root and its own'
        ' depth of "$depthName".',
      );
    }
    // The YEAR renders era-qualified ("3E 433") through the law's own affix. The
    // era is the frame, so it occupies no position of its own -- one token in,
    // one token out, which is what makes the round trip stable. An out-of-table
    // year is already invalid stored data; leave `parts` without one rather than
    // compound that error.
    if (law.hasEras() && level.name == law.yearLevel) {
      place(index, law.formatYear(value));
      final proper = _properYear(law, raw);
      if (proper != null) parts[level.name] = proper;
      continue;
    }
    if (_isContinuousTail(law, index)) {
      place(index, _tailDigits(raw));
      continue;
    }
    final numeric = BigInt.parse(raw);
    final count = _childCount(law, level, parts);
    place(index, count == null ? '$numeric' : _padded(numeric, count));
    parts[level.name] = numeric;
  }
  return text.toString();
}

/// One value a bounded picker rung offers, and the label the law names it by.
typedef PickerOption = ({String value, String label});

/// One rung of the zoomable picker: a level, what is already chosen on it, and
/// -- only when the law can COUNT this level's children -- the values it offers.
typedef PickerRung = ({
  String level,
  String label,
  String? chosen,
  bool bounded,
  List<PickerOption> options,
});

/// The zoomable picker's data: one rung per law level from the root down to and
/// including the first level the coordinate has not yet fixed.
///
/// OVERSCALE DOCTRINE. The root and the continuous tail have no determinable
/// count, so they report `bounded: false` with an EMPTY option list -- never a
/// materialized guess, at any depth. A bounded rung's list comes from its own
/// radix or its transition's `childrenIn` given the coarser values already
/// chosen, so a leap February offers 29 days and a common one 28.
///
/// There is no picker state. The ladder is derived from the coordinate handed
/// in, so drilling is picking a value and asking again -- which is why stopping
/// partway costs nothing and leaves the coordinate at exactly that depth. Eras
/// get no rung: choosing an era is choosing which FRAME to place on, and that
/// happens before this ladder rather than inside it.
List<PickerRung> coordinatePickerLadder(CoordinateLaw law, Coordinate value) {
  final depthName = authoredDepth(value, law);
  final depthIndex = depthName == null
      ? -1
      : law.levels.indexWhere((level) => level.name == depthName);
  final lastIndex = min(depthIndex + 1, law.levels.length - 1);
  if (lastIndex < 0) return const [];

  final parts = <String, BigInt>{};
  final rungs = <PickerRung>[];
  for (var index = 0; index <= lastIndex; index += 1) {
    final level = law.levels[index];
    final chosen = _fixed(value, level.name);
    final count = _childCount(law, level, parts);
    final names = count == null ? null : law.namesFor(level.name);
    final base = _levelBase(law, level.name);
    rungs.add((
      level: level.name,
      label: level.name,
      chosen: chosen,
      bounded: count != null,
      options: count == null
          ? const []
          : [
              for (var offset = 0; BigInt.from(offset) < count; offset += 1)
                (
                  value: '${base + BigInt.from(offset)}',
                  label: names != null && offset < names.length
                      ? names[offset]
                      : '${base + BigInt.from(offset)}',
                ),
            ],
    ));
    if (chosen == null || _isContinuousTail(law, index)) continue;
    // A transition below the year resolves against the PROPER year, not the
    // number typed within this era. Every other level reads its raw chosen
    // value; a malformed one simply counts no children below it.
    final resolved = law.hasEras() && level.name == law.yearLevel
        ? _properYear(law, chosen)
        : BigInt.tryParse(chosen);
    if (resolved != null) parts[level.name] = resolved;
  }
  return rungs;
}

/// The field's own placeholder text -- "year-month-day hour:minute:second" under
/// the registered standard -- derived from the law's declared levels, so a
/// custom calendar's field advertises its own units rather than a Gregorian
/// assumption. Under an era law the year position advertises the era's own key,
/// because that is what may be typed there.
String coordinateEntryPlaceholder(CoordinateLaw law) {
  final above = [for (final level in law.aboveLadder) level.name];
  final head = law.hasEras() && above.isNotEmpty
      ? ['[${law.eraKey()}] ${above.first}', ...above.skip(1)].join('-')
      : above.join('-');
  final below = [for (final level in law.belowLadder) level.name].join(':');
  return below.isEmpty ? head : '$head $below';
}
