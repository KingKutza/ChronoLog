// Pure Dart. Nothing under lib/core/ may import Flutter or a third-party
// package.
//
// The one coordinate-arithmetic engine. Every unit relationship in ChronoLog —
// how many hours are in a day, how long a month is, how a nested coordinate
// becomes a day ordinal, what a duration magnitude is worth — is computed here
// from the governing frame's own declaration.
//
// Two hard rules govern everything below.
//
//   * An unresolvable declaration is a REFUSAL SURFACED TO THE AUTHOR, never a
//     silent fallback. A transition string nothing implements, a radix that is
//     not a positive whole number, a level nesting inside a level that does not
//     exist — each refuses with the frame and the offending name in the message,
//     because a coordinate law that quietly means something other than what is
//     written is unauditable. An editor that accepts an edit and ignores it is
//     worse than one that refuses it.
//   * All coordinate arithmetic is exact. Pixels and layout may be floats; unit
//     law may not.
//
// DESIGN LAW: level names, cycle names, era names and calendar-scale ids are OPEN
// USER VOCABULARY — strings throughout, never enums. Nothing here encodes a right
// way to name or nest a unit, because any system that encodes a right way does in
// the same breath preclude other ways.

import 'eras.dart';
import 'exact.dart';

// --- The Coordinate value type ----------------------------------------------

/// One rung of a coordinate: a level name and the exact text stored against it.
typedef LevelEntry = ({String level, String value});

/// A nested coordinate — an ordered bag of level values, each kept as the exact
/// text the document carries.
///
/// This type is the SHAPE and never the interpretation: only a governing
/// [CoordinateLaw] can say whether `{day: 15}` is the fifteenth of a month or a
/// span of fifteen days. Values stay text because a document's numbers are exact
/// and a host number is not.
class Coordinate {
  const Coordinate(this.levels);

  /// Drops any level whose value is absent: an omitted level and a level valued
  /// null are the same statement.
  factory Coordinate.of(List<(String, Object?)> parts) => Coordinate([
    for (final (level, value) in parts)
      if (value != null) (level: level, value: '$value'),
  ]);

  factory Coordinate.fromJson(Map<String, Object?>? json) => Coordinate([
    for (final row in asList(json?['levels']))
      if (asMap(row)?['value'] != null)
        (level: '${asMap(row)!['level']}', value: '${asMap(row)!['value']}'),
  ]);

  static const Coordinate empty = Coordinate([]);

  final List<LevelEntry> levels;

  /// The stored text at [name], or [fallback] when this coordinate says nothing
  /// about that level. Absent is not zero, so every caller states its own
  /// default rather than inheriting one from here.
  String value(String name, [String fallback = '0']) =>
      firstMatch(levels, (entry) => entry.level == name)?.value ?? fallback;

  bool has(String name) => firstMatch(levels, (entry) => entry.level == name) != null;

  List<String> levelNames() => [for (final entry in levels) entry.level];

  Map<String, Object?> toJson() => {
    'levels': [
      for (final entry in levels) {'level': entry.level, 'value': entry.value},
    ],
  };

  @override
  bool operator ==(Object other) {
    if (other is! Coordinate) return false;
    if (other.levels.length != levels.length) return false;
    for (var index = 0; index < levels.length; index += 1) {
      if (levels[index] != other.levels[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(levels);

  @override
  String toString() => [for (final entry in levels) '${entry.level}=${entry.value}'].join(' ');
}

/// The plain civil rendering of a coordinate, for a host interface that speaks
/// standard Gregorian text. Display, not arithmetic: nothing in the model may
/// read a value back out of this string.
String formatCivil(Coordinate value, {bool includeTime = false}) {
  final date =
      '${value.value('year', '1970')}'
      '-${value.value('month', '1').padLeft(2, '0')}'
      '-${value.value('day', '1').padLeft(2, '0')}';
  if (!includeTime) return date;
  return '$date ${value.value('hour').padLeft(2, '0')}'
      ':${value.value('minute').padLeft(2, '0')}'
      ':${value.value('second').padLeft(2, '0')}';
}

// --- The declaration value layer --------------------------------------------

/// One rung of a declared ladder.
///
/// [radix] says how many of THESE fit in the parent, so it describes the
/// PARENT's length and says nothing about its own. A [transition] says that
/// count is not constant and names the rule that answers instead. A level
/// declares one or the other — or neither, which is the unbounded fractional
/// tail (`subsecond`).
class Level {
  const Level({required this.name, this.within, this.radix, this.transition, this.names});

  final String name;
  final String? within;
  final String? transition;
  final Rational? radix;

  /// Authored names for this level's values, one per unit within its parent.
  final List<String>? names;

  Map<String, Object?> toJson() => {
    'name': name,
    if (within != null) 'within': within,
    if (radix != null) 'radix': radix!.toJson(),
    if (transition != null) 'transition': transition,
    if (names != null) 'names': names,
  };
}

/// A fixed-length repetition over the base unit with its own names and phase.
///
/// A weekday is deliberately NOT a ladder level: seven days repeat across month
/// and year boundaries without regard for either. Modelling it as a level is what
/// forced an authoring surface to demand one name per day of the month.
class Cycle {
  const Cycle({required this.name, required this.radix, required this.offset, this.names});

  final String name;
  final Rational radix;

  /// The cycle index of day zero — the phase.
  final BigInt offset;
  final List<String>? names;

  Map<String, Object?> toJson() => {
    'name': name,
    'radix': radix.toJson(),
    if (offset != BigInt.zero) 'offset': '$offset',
    if (names != null) 'names': names,
  };
}

/// A frame's `coordinate` block, parsed.
///
/// The authored map is KEPT, and every scalar is read back off it, so field names
/// match the JSON document format exactly in both directions and a declaration
/// written by hand, by a form, or by the JavaScript implementation is one thing —
/// including the alternate spellings of a single fact (`atomDays` /
/// `baseUnitDays` / `fixed.smallestUnitDays`), which survive a round trip as the
/// author wrote them rather than being canonicalized behind their back.
///
/// Shape checking that a Dart constructor already performs is not repeated here.
/// What rides is the refusals, whose sentences are the author's contract.
class Declaration {
  const Declaration._(this.source, this.levels, this.cycles);

  const Declaration() : this._(const {}, const [], const []);

  /// [label] names the offending frame in every refusal, so an ad-hoc
  /// declaration (a form previewing an unsaved edit) parses fine without one.
  factory Declaration.parse(Map<String, Object?>? json, String label) {
    _installStandards();
    if (json == null) return const Declaration();
    return Declaration._(json, _parseLevels(json, label), _parseCycles(json, label));
  }

  final Map<String, Object?> source;
  final List<Level> levels;
  final List<Cycle> cycles;

  String get kind => source['kind'] == null ? 'nested' : declaredText(source['kind']);

  /// Which of its own levels the family's whole-unit arithmetic counts in. A
  /// uniform ladder has no transition to infer it from, so it says so outright,
  /// and that statement outranks every inference.
  String? get baseLevel => _text('baseLevel');

  /// The absolute length of the finest declared unit, under any of its three
  /// authored spellings.
  String? get atomDays =>
      _text('atomDays') ?? _text('baseUnitDays') ?? _fixedText('smallestUnitDays');

  String? get epochDays => _fixedText('epochDays');

  bool get hasFixed => asMap(source['fixed']) != null;

  bool get hasOrigin => source['origin'] != null;

  String? get origin {
    final authored = source['origin'];
    if (authored == null) return null;
    final block = asMap(authored);
    return declaredText(block == null ? authored : block['days']);
  }

  /// `false` is an author saying outright that this calendar has no now. A world
  /// with no relation to this one has none, and drawing a Now line on it invents
  /// a fact.
  bool? get clock => source['clock'] is bool ? source['clock'] as bool : null;

  String? _text(String key) => source[key] == null ? null : declaredText(source[key]);

  String? _fixedText(String key) {
    final value = asMap(source['fixed'])?[key];
    return value == null ? null : declaredText(value);
  }

  Level? level(String name) => firstMatch(levels, (entry) => entry.name == name);

  Map<String, Object?> toJson() => {
    ...source,
    'kind': kind,
    'levels': [for (final entry in levels) entry.toJson()],
    if (cycles.isNotEmpty) 'cycles': [for (final entry in cycles) entry.toJson()],
  };
}

Rational _positiveWholeRadix(Object? value, String label, String levelName) {
  final Rational parsed;
  try {
    parsed = Rational.parse(declaredText(value));
  } catch (_) {
    throw LawRefusal('$label: level "$levelName" has a radix that is not a number ($value).');
  }
  if (parsed <= Rational.zero || parsed.d != BigInt.one) {
    throw LawRefusal('$label: level "$levelName" needs a positive whole radix, not $value.');
  }
  return parsed;
}

List<String>? _parseNames(Object? names) {
  if (names is! List) return null;
  final cleaned = [
    for (final name in names)
      if (declaredText(name).isNotEmpty) declaredText(name),
  ];
  return cleaned.isEmpty ? null : List.unmodifiable(cleaned);
}

List<Level> _parseLevels(Map<String, Object?> json, String label) {
  final declared = asList(json['levels']);
  final levels = <Level>[];
  final seen = <String>{};
  for (final (index, row) in declared.indexed) {
    final entry = asMap(row);
    final name = declaredText(entry?['name']);
    if (name.isEmpty) {
      throw LawRefusal('$label: level ${index + 1} has no name.');
    }
    if (seen.contains(name)) {
      throw LawRefusal('$label: level "$name" is declared twice.');
    }
    // Nesting defaults to the level directly above, which is what every ladder
    // written by hand means.
    final declaredWithin = entry?['within'] != null
        ? declaredText(entry!['within'])
        : (index == 0 ? '' : declaredText(asMap(declared[index - 1])?['name']));
    final within = index == 0 || declaredWithin.isEmpty ? null : declaredWithin;
    if (index > 0 && !seen.contains(within)) {
      throw LawRefusal(
        '$label: level "$name" nests inside "${within ?? '(nothing)'}", which is'
        ' not a level above it.',
      );
    }
    final transition = entry?['transition'] == null ? null : declaredText(entry!['transition']);
    if (transition != null) {
      assertTransition(transition, '$label: level "$name"');
    }
    final radix = entry?['radix'];
    final hasRadix = radix != null && declaredText(radix).isNotEmpty;
    if (transition != null && hasRadix) {
      throw LawRefusal(
        '$label: level "$name" declares both a radix and a transition; a level has'
        ' one or the other.',
      );
    }
    levels.add(
      Level(
        name: name,
        within: within,
        radix: transition != null || !hasRadix ? null : _positiveWholeRadix(radix, label, name),
        transition: transition,
        names: _parseNames(entry?['names']) ?? _parseNames(entry?['labels']),
      ),
    );
    seen.add(name);
  }
  return List.unmodifiable(levels);
}

List<Cycle> _parseCycles(Map<String, Object?> json, String label) {
  final cycles = <Cycle>[];
  for (final row in asList(json['cycles'])) {
    final entry = asMap(row);
    final name = declaredText(entry?['name']);
    if (name.isEmpty) throw LawRefusal('$label: a cycle has no name.');
    final radix = _positiveWholeRadix(entry?['radix'], label, name);
    final names = _parseNames(entry?['names']);
    // A list is checked against the count its own meaning requires: seven names
    // against a radix of seven, never twelve against eight.
    if (names != null && BigInt.from(names.length) != radix.n) {
      throw LawRefusal(
        '$label: the "$name" cycle repeats every ${radix.n} but ${names.length}'
        ' name${names.length == 1 ? ' was' : 's were'} given.',
      );
    }
    cycles.add(
      Cycle(
        name: name,
        radix: radix,
        offset: entry?['offset'] == null
            ? BigInt.zero
            : wholeBigInt(entry!['offset'], '$label: the "$name" cycle\'s offset'),
        names: names,
      ),
    );
  }
  return List.unmodifiable(cycles);
}

// --- The transition / family / CLDR registry --------------------------------
//
// A `transition` on a level says "the number of these inside their parent is not
// a constant; ask this rule". It is the counterpart of `radix`, which says the
// count IS a constant.
//
// Each transition belongs to a FAMILY, and a family owns the closed-form
// conversion for the whole-unit part of a ladder, because that arithmetic cannot
// be derived from per-level counts without iterating from the epoch: proleptic
// Gregorian needs its 400-year era formula, and a future family will need its own.
//
// A family is also a CALENDAR SCALE in the CLDR sense, and that identity is what
// crosses the ICS boundary: RFC 7529 lets a recurrence rule name the calendar it
// counts in (`RSCALE=HEBREW`) using CLDR names. So Gregorian is not privileged
// here — it is simply the first entry, and Hebrew, Islamic and the rest are
// ordinary additional entries, each one a `registerCalendarFamily` call plus its
// transitions. Nothing else in the program changes to gain one.
//
// A calendar nothing has registered is REFUSED HONESTLY rather than computed as
// though it were Gregorian: `lawForCalendar` returns null, and the caller's job
// is to preserve the author's rule verbatim and say it cannot be projected.

/// The extension seam. Open by construction: a family is registered, never
/// special-cased, which is what makes a wholly invented calendar convert through
/// the same path Gregorian does.
abstract class CalendarFamily {
  String get name;

  /// The CLDR calendar scale this family counts in, or null for a family that
  /// executes a ladder and names no standard calendar — such a family reports no
  /// scale, and the ICS boundary converts or refuses rather than claiming one.
  String? get calendar => name;

  /// Other spellings a wire format may use for the same scale.
  List<String> get aliases => const [];

  /// The canonical ladder this scale counts in, which is what an `RSCALE` naming
  /// it resolves to.
  Declaration? get declaration => null;

  /// The value a level takes when a coordinate says nothing about it.
  Map<String, String> get defaults => const {};

  /// A family receives the LADDER it is asked to execute — the ordered level
  /// descriptors from the root down to the base — rather than only a signature,
  /// because it may need the levels' own radices to do its arithmetic at all.
  bool supports(List<Level> ladder);

  BigInt toWholeUnits(List<Level> ladder, List<BigInt> parts);

  List<(String, BigInt)> fromWholeUnits(List<Level> ladder, BigInt wholeUnits);
}

/// How many children one parent has when that count is not constant.
class Transition {
  const Transition({
    required this.name,
    required this.family,
    required this.meanChildren,
    required this.childrenIn,
    required this.summary,
  });

  final String name;
  final CalendarFamily family;

  /// The exact mean, which is what a variable level's mean unit length is built
  /// from — never a float standing in for it.
  final Rational meanChildren;

  /// How many children a SPECIFIC parent has. Used by the authoring surface to
  /// describe a variable level honestly ("28-31") and available to any consumer
  /// that needs a real count rather than a mean.
  final BigInt Function(Map<String, BigInt> parts) childrenIn;
  final String summary;
}

final Map<String, Transition> _transitions = {};
final Map<String, CalendarFamily> _families = {};
final Map<String, CalendarFamily> _calendars = {};
final Map<String, CoordinateLaw> _calendarLaws = {};
bool _installed = false;

CalendarFamily registerCalendarFamily(CalendarFamily family) {
  _installStandards();
  if (family.name.isEmpty) {
    throw const LawRefusal('A calendar family needs a name.');
  }
  _families[family.name] = family;
  final calendar = family.calendar;
  if (calendar != null) {
    for (final id in [calendar, ...family.aliases]) {
      _calendars[id.toLowerCase()] = family;
    }
  }
  return family;
}

Transition registerTransition(
  String name, {
  required String family,
  required Rational meanChildren,
  BigInt Function(Map<String, BigInt> parts)? childrenIn,
  String? summary,
}) {
  _installStandards();
  if (name.isEmpty) throw const LawRefusal('A transition needs a name.');
  final resolved = _families[family];
  if (resolved == null) {
    throw LawRefusal('Transition $name names an unregistered calendar family.');
  }
  if (meanChildren <= Rational.zero) {
    throw LawRefusal('Transition $name needs a positive mean child count.');
  }
  return _transitions[name] = Transition(
    name: name,
    family: resolved,
    meanChildren: meanChildren,
    childrenIn: childrenIn ?? ((_) => meanChildren.n),
    summary: summary ?? name,
  );
}

Transition? transitionDefinition(String name) {
  _installStandards();
  return _transitions[name];
}

List<String> registeredTransitions() {
  _installStandards();
  return _transitions.keys.toList()..sort();
}

/// Every CLDR calendar scale this build can actually count in.
List<String> registeredCalendars() {
  _installStandards();
  return {for (final family in _calendars.values) family.calendar!}.toList()..sort();
}

CalendarFamily? calendarFamily(Object? calendarId) {
  _installStandards();
  return _calendars[declaredText(calendarId).toLowerCase()];
}

/// The law a CLDR calendar scale name resolves to, or null when nothing
/// implements that calendar. Memoized because the ICS boundary asks per rule.
CoordinateLaw? lawForCalendar(Object? calendarId) {
  final family = calendarFamily(calendarId);
  final declaration = family?.declaration;
  if (family == null || declaration == null) return null;
  return _calendarLaws[family.calendar!] ??= CoordinateLaw(
    declaration,
    frameId: 'calendar:${family.calendar}',
    positional: true,
  );
}

/// The one refusal message for a transition string nothing implements, shared by
/// declaration parsing and by the authoring surface — so an author sees the same
/// sentence whether the bad name arrived by hand-edited JSON or by a form field,
/// and the list of alternatives is never two lists.
Transition assertTransition(String name, String subject) {
  _installStandards();
  final known = _transitions[name];
  if (known != null) return known;
  final alternatives = registeredTransitions();
  throw LawRefusal(
    '$subject uses the transition "$name", which nothing implements.'
    ' Known transitions: ${alternatives.isEmpty ? '(none)' : alternatives.join(', ')}.',
  );
}

// --- The Gregorian family ---------------------------------------------------
//
// 400 Gregorian years span exactly 146097 days, which is where every exact mean
// below comes from: 146097/400 days per year, 146097/4800 per month — the value
// a minimap used to carry as the float literal 30.436875.

final Rational _gregorianEraDays = Rational(BigInt.from(146097));
final Rational meanGregorianYear = _gregorianEraDays / Rational.fromInt(400);
final Rational meanGregorianMonth = _gregorianEraDays / Rational.fromInt(4800);

/// CLDR spells the proleptic Gregorian calendar `gregory`. RFC 7529's own text is
/// not consistent about whether an RSCALE names it `GREGORY` or `GREGORIAN`, so
/// both are accepted on the way in; on the way out the question never arises,
/// because Gregorian is RSCALE's default and a rule counting in it omits the
/// parameter entirely.
const String gregory = 'gregory';

const List<String> standardMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> standardWeekdayNames = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

/// The registered standard, as a document would write it.
///
/// The names and the weekday cycle live HERE, in a declaration, rather than as
/// private arrays inside a renderer: that is what makes them editable at all. A
/// frame whose declaration omits them inherits these, so a document authored
/// before they existed reads exactly as it always did. `offset: 4` is the cycle
/// index of day zero (1970-01-01, a Thursday).
const Map<String, Object?> gregorianDeclarationJson = {
  'kind': 'gregorian',
  'levels': [
    {'name': 'year'},
    {
      'name': 'month',
      'within': 'year',
      'transition': 'gregorian.months',
      'names': standardMonthNames,
    },
    {'name': 'day', 'within': 'month', 'transition': 'gregorian.days'},
    {'name': 'hour', 'within': 'day', 'radix': '24'},
    {'name': 'minute', 'within': 'hour', 'radix': '60'},
    {'name': 'second', 'within': 'minute', 'radix': '60'},
    {'name': 'subsecond', 'within': 'second'},
  ],
  'cycles': [
    {'name': 'weekday', 'radix': '7', 'offset': '4', 'names': standardWeekdayNames},
  ],
};

/// Parsed lazily, because parsing asserts its transition strings and those are
/// registered by [_installStandards].
final Declaration gregorianDeclaration = Declaration.parse(
  gregorianDeclarationJson,
  'The registered Gregorian calendar',
);

class _GregorianFamily extends CalendarFamily {
  // The ladders this family knows how to execute, keyed by the ordered
  // transition names below the root. A declaration whose ladder is not listed is
  // an authoring error rather than a guess: "year then month then day" and "year
  // then day-of-year" are different calendars, and inventing a conversion for a
  // shape nobody wrote is exactly the class of silent wrongness this removes.
  static const Set<String> _ladders = {
    '',
    'gregorian.months',
    'gregorian.months+gregorian.days',
    'gregorian.daysInYear',
  };

  @override
  String get name => 'gregorian';

  @override
  String? get calendar => gregory;

  @override
  List<String> get aliases => const ['gregorian'];

  @override
  Declaration? get declaration => gregorianDeclaration;

  /// A bare year/month/day coordinate with no time levels means midnight on that
  /// date, and an absent year means the day-zero epoch year.
  @override
  Map<String, String> get defaults => const {'year': '1970', 'month': '1', 'day': '1'};

  String signature(List<Level> ladder) =>
      [for (final level in ladder.skip(1)) level.transition ?? ''].join('+');

  @override
  bool supports(List<Level> ladder) => _ladders.contains(signature(ladder));

  @override
  BigInt toWholeUnits(List<Level> ladder, List<BigInt> parts) => switch (signature(ladder)) {
    'gregorian.months' => daysFromCivil(parts[0], parts[1].toInt(), 1),
    'gregorian.months+gregorian.days' => daysFromCivil(
      parts[0],
      parts[1].toInt(),
      parts[2].toInt(),
    ),
    'gregorian.daysInYear' => daysFromCivil(parts[0], 1, 1) + parts[1] - BigInt.one,
    _ => daysFromCivil(parts[0], 1, 1),
  };

  @override
  List<(String, BigInt)> fromWholeUnits(List<Level> ladder, BigInt days) {
    final civil = civilFromDays(days);
    return switch (signature(ladder)) {
      'gregorian.months' => [('year', civil.year), ('month', BigInt.from(civil.month))],
      'gregorian.months+gregorian.days' => [
        ('year', civil.year),
        ('month', BigInt.from(civil.month)),
        ('day', BigInt.from(civil.day)),
      ],
      'gregorian.daysInYear' => [
        ('year', civil.year),
        ('day', days - daysFromCivil(civil.year, 1, 1) + BigInt.one),
      ],
      _ => [('year', civil.year)],
    };
  }
}

/// The uniform positional family: any ladder whose levels above the base all
/// count a CONSTANT number of children. This is what a wholly invented calendar
/// needs — 12 months of 30 days in a 360-day year, or Tamriel's fixed year — and
/// it is registered rather than special-cased.
///
/// It names no CLDR calendar scale, so a series counting in it is not
/// ICS-expressible as a rule even though its dates resolve to exact ordinals.
///
/// Root values are 1-based, matching the family defaults every other level uses,
/// and may be zero or negative: a descending era resolves to proper years at or
/// below zero, and floored division carries that through exactly rather than
/// truncating toward zero.
class _UniformFamily extends CalendarFamily {
  @override
  String get name => 'uniform';

  @override
  String? get calendar => null;

  /// Whole units of the base level spanned by one unit of each ladder level.
  List<BigInt> spans(List<Level> ladder) {
    final spans = List<BigInt>.filled(ladder.length, BigInt.one);
    var span = BigInt.one;
    for (var index = ladder.length - 1; index >= 0; index -= 1) {
      spans[index] = span;
      if (index > 0) span *= ladder[index].radix!.n;
    }
    return spans;
  }

  @override
  bool supports(List<Level> ladder) =>
      ladder.isNotEmpty &&
      ladder
          .skip(1)
          .every(
            (level) =>
                level.radix != null && level.transition == null && level.radix!.d == BigInt.one,
          );

  @override
  BigInt toWholeUnits(List<Level> ladder, List<BigInt> parts) {
    final spans = this.spans(ladder);
    var total = BigInt.zero;
    for (var index = 0; index < ladder.length; index += 1) {
      total += (parts[index] - BigInt.one) * spans[index];
    }
    return total;
  }

  @override
  List<(String, BigInt)> fromWholeUnits(List<Level> ladder, BigInt wholeUnits) {
    final spans = this.spans(ladder);
    var remainder = wholeUnits;
    final values = <(String, BigInt)>[];
    for (var index = 0; index < ladder.length; index += 1) {
      final amount = floorDiv(remainder, spans[index]);
      remainder -= amount * spans[index];
      values.add((ladder[index].name, amount + BigInt.one));
    }
    return values;
  }
}

final CalendarFamily gregorianFamily = _GregorianFamily();
final CalendarFamily uniformFamily = _UniformFamily();

/// The registered standards, installed once. Every registry read passes through
/// here first, so the order of lazy initialization cannot leave a transition
/// string unresolvable at the moment a declaration asks for it.
void _installStandards() {
  if (_installed) return;
  _installed = true;
  registerCalendarFamily(gregorianFamily);
  registerCalendarFamily(uniformFamily);
  registerTransition(
    'gregorian.months',
    family: 'gregorian',
    meanChildren: Rational.fromInt(12),
    summary: '12 months',
  );
  registerTransition(
    'gregorian.days',
    family: 'gregorian',
    meanChildren: meanGregorianMonth,
    childrenIn: (parts) => BigInt.from(
      daysInMonth(parts['year'] ?? BigInt.from(1970), (parts['month'] ?? BigInt.one).toInt()),
    ),
    summary: '28-31 days',
  );
  registerTransition(
    'gregorian.daysInYear',
    family: 'gregorian',
    meanChildren: meanGregorianYear,
    childrenIn: (parts) => BigInt.from(isLeapYear(parts['year'] ?? BigInt.from(1970)) ? 366 : 365),
    summary: '365 or 366 days',
  );
}

/// The unit relationships a partial declaration inherits. A calendar that omits
/// the `hour` level entirely is not asserting that hours do not exist; it simply
/// has not authored them, and a display that needs an hour rail gets the
/// registered standard rather than a crash. Anything a declaration DOES author
/// always wins.
final Map<String, Rational> standardUnitDays = {
  'week': Rational.fromInt(7),
  'day': Rational.one,
  'hour': Rational.fromInt(1, 24),
  'minute': Rational.fromInt(1, 1440),
  'second': Rational.fromInt(1, 86400),
};

String _label(String? frameId) =>
    frameId == null ? 'This coordinate declaration' : 'Frame $frameId';

// --- CoordinateLaw ----------------------------------------------------------

class CoordinateLaw {
  /// [positional] says whether this declaration names POSITIONS on a timeline (a
  /// calendar: year/month/day resolve to a day ordinal through a family) or
  /// MAGNITUDES (a measure frame: the base level's value already IS a count). It
  /// defaults to "positional if a family can execute the ladder", and the law
  /// resolver passes it explicitly so a measure frame keeps reading its own base
  /// level rather than being reinterpreted as a date.
  CoordinateLaw(Declaration? declaration, {this.frameId, bool? positional, EraContext? era})
    : declaration = declaration ?? const Declaration() {
    _installStandards();
    final label = _label(frameId);
    final declared = this.declaration;
    levels = declared.levels;
    for (final level in levels) {
      _byName[level.name] = level;
    }
    for (final cycle in declared.cycles) {
      _cycles[cycle.name] = cycle;
    }

    // THE ATOM: the finest declared unit, the one everything else is composed
    // from. Its own absolute length is the one thing composition cannot supply,
    // so it comes from the registered standard for a unit of that name (a second
    // is 1/86400 of a standard day wherever it appears) or is authored outright.
    //
    // It is also the shared denominator for cross-frame comparison: two laws
    // relate absolutely exactly insofar as they share an atom. Two frames with no
    // shared atom have no automatic absolute relation at all — that is what
    // connection staples are for, and inventing one would be the same fabrication
    // as an invented origin.
    final finest = levels.isEmpty ? null : levels.last;
    // A continuous tail is not a unit of its own; the finest FIXED unit is the
    // level above it.
    atomLevel =
        finest != null && finest.radix == null && finest.transition == null && levels.length > 1
        ? levels[levels.length - 2].name
        : finest?.name;
    final authoredAtom = declared.atomDays;
    atomDays = authoredAtom != null
        ? Rational.parse(authoredAtom)
        : (standardUnitDays[atomLevel] ?? Rational.one);
    if (atomDays <= Rational.zero) {
      throw LawRefusal('$label: the smallest unit must be longer than zero days.');
    }

    // The BASE LEVEL is the level the family's whole-unit arithmetic COUNTS IN —
    // the "day" of this ladder. It is no longer "one standard day": under
    // bottom-up composition its length is whatever its own radices make it, so a
    // frame declaring 23 hours in a day has a base unit of 23 standard hours and
    // its day sequence DRIFTS against the standard calendar. That drift is the
    // ruling, not a defect: successive day boundaries fall 23 standard hours
    // apart because the day is the thing that was shortened.
    final deepestTransition = firstMatch(levels.reversed, (level) => level.transition != null);
    final declaredBase = declared.baseLevel;
    if (declaredBase != null && declaredBase.isNotEmpty && !_byName.containsKey(declaredBase)) {
      throw LawRefusal(
        '$label: the base unit is declared as "$declaredBase", which is not one of'
        ' its levels (${levels.isEmpty ? 'none' : levelNames().join(', ')}).',
      );
    }
    baseLevel =
        (declaredBase != null && declaredBase.isNotEmpty ? declaredBase : null) ??
        (declared.hasFixed && levels.isNotEmpty ? levels.last.name : null) ??
        deepestTransition?.name ??
        (levels.isEmpty ? null : levels.first.name) ??
        'day';
    epochDays = Rational.parse(declared.epochDays ?? '0');

    final baseIndex = levels.indexWhere((level) => level.name == baseLevel);
    aboveLadder = baseIndex < 0 ? const [] : List.unmodifiable(levels.sublist(0, baseIndex + 1));
    belowLadder = baseIndex < 0 ? const [] : List.unmodifiable(levels.sublist(baseIndex + 1));

    // The ERA TABLE sits above the year level and renumbers it. It converts
    // (era, year) to the PROPER YEAR the ladder already counts in, and the family
    // takes it from there — which is what keeps eras first-class instead of a
    // label over a linearized year. The era level is deliberately NOT part of the
    // family's ladder.
    this.era = era;
    eraTable = era != null && era.countable ? era.table : null;
    eraEntry = era != null && era.countable ? era.entry : null;
    uncountableEra = era != null && !era.countable;
    yearLevel = eraTable == null ? null : (levels.isEmpty ? null : levels.first.name);

    // Every transition above the base must belong to one family: half a Gregorian
    // ladder spliced onto half of something else is not a calendar.
    final families = <String>{
      for (final level in familyLadder)
        if (level.transition != null) _transitions[level.transition]!.family.name,
    };
    if (families.length > 1) {
      throw LawRefusal('$label: levels mix the ${families.join(' and ')} calendar families.');
    }
    var resolved = families.isEmpty ? null : _families[families.first];
    // A uniform ladder is FULLY COMPUTABLE from its own radices under bottom-up
    // composition, so it converts without waiting for an origin: positions on the
    // frame's OWN axis need no external anchor, and refusing to compute them is
    // what silently collapsed every invented-calendar event onto position 1.
    //
    // What an origin (or a shared atom) adds is the separate, stronger claim that
    // those positions are comparable to standard days — see [mapsToClock]. A
    // frame's own axis being real and its relation to Earth days being unstated
    // are not in tension: the first is arithmetic, the second is a fact about the
    // world that only an author can supply.
    if (resolved == null && familyLadder.isNotEmpty && uniformFamily.supports(familyLadder)) {
      resolved = uniformFamily;
    }
    if (resolved != null && !resolved.supports(familyLadder)) {
      throw LawRefusal(
        '$label: the ${resolved.name} family cannot execute the level ladder'
        ' ${[for (final level in familyLadder) level.name].join(' > ')}.',
      );
    }
    if (declared.hasOrigin) {
      originDays = Rational.parse(declared.origin ?? '0');
      // A fixed-calendar epoch and an origin are two statements of the same fact
      // — where this calendar's counting begins. Carrying both would silently add
      // them together, so one of them has to go rather than be reconciled here.
      if (!epochDays.isZero) {
        throw LawRefusal(
          '$label: the declaration states its starting day twice, as a'
          ' fixed-calendar epoch and as an origin. Keep one.',
        );
      }
    } else {
      originDays = Rational.zero;
    }
    // An era with no year axis is never positional, whatever ladder it may have
    // inherited: "ordered, connected, never acquiring day ordinals" is the whole
    // of what it claims.
    this.positional = uncountableEra
        ? false
        : (positional == null
              ? resolved != null
              : (positional || declared.hasOrigin) && resolved != null);
    family = this.positional ? resolved : null;
    if (eraTable != null && family == null) {
      throw LawRefusal(
        '$label: this era counts years, so it needs a year ladder its family can'
        ' execute — inherit one from a basis calendar.',
      );
    }
    // Retained even when this law is not positional, so an authoring surface can
    // still describe a measure frame's variable levels ("365 or 366 days").
    declaredFamily = resolved;
    // Inheriting the registered calendar's NAMES and CYCLES is a claim about
    // counting in that calendar, so it is gated on the family naming a CLDR
    // calendar scale — not merely on there being a family at all. The `uniform`
    // family executes any constant-radix ladder and names no calendar, so an
    // invented calendar gets no Gregorian months and no seven-day week unless it
    // declares them.
    inheritsRegistered = resolved?.calendar != null;
  }

  /// Parses a declaration straight from the document's own map form.
  factory CoordinateLaw.parse(
    Map<String, Object?>? json, {
    String? frameId,
    bool? positional,
    EraContext? era,
  }) => CoordinateLaw(
    Declaration.parse(json, _label(frameId)),
    frameId: frameId,
    positional: positional,
    era: era,
  );

  final Declaration declaration;

  /// Appears only in refusal messages.
  final String? frameId;

  late final Map<String, Level> _byName = {};
  late final Map<String, Cycle> _cycles = {};
  final Map<String, Rational?> _unitDays = {}, _unitAtoms = {};
  late final List<Level> levels, aboveLadder, belowLadder;
  late final String baseLevel;
  late final String? atomLevel, yearLevel;
  late final Rational atomDays, epochDays, originDays;
  late final EraContext? era;
  late final EraTable? eraTable;
  late final EraEntry? eraEntry;
  late final CalendarFamily? family, declaredFamily;
  late final bool positional, uncountableEra, inheritsRegistered;

  /// The ordered levels the family executes, root first, down to the base.
  List<Level> get familyLadder => aboveLadder;

  // --- Structure ------------------------------------------------------------

  /// The base unit's own length, COMPOSED from its radices rather than assumed to
  /// be one standard day.
  Rational get baseDays => unitDays(baseLevel) ?? atomDays;

  /// How many atoms one base unit spans — the family's counting granularity.
  Rational get baseAtoms => unitAtoms(baseLevel) ?? Rational.one;

  Level? level(String name) => _byName[name];

  bool has(String name) => _byName.containsKey(name);

  List<String> levelNames() => [for (final level in levels) level.name];

  /// Authored names for a level's values (January..December), or null when
  /// nothing names them.
  ///
  /// The registered standard is inherited ONLY by a law that actually counts in
  /// that registered calendar. A custom calendar whose second level happens to be
  /// spelled "month" is not the Gregorian month and must not be handed twelve
  /// Gregorian names — an authoring surface would then show twelve names against
  /// a radix of eight and refuse the author's own structure.
  List<String>? namesFor(String name) {
    final authored = level(name)?.names;
    if (authored != null) return authored;
    if (!inheritsRegistered) return null;
    return gregorianDeclaration.level(name)?.names;
  }

  /// The names of this law's month-scale level, or NULL when it has no such
  /// concept at all. A caller that draws a month grid must handle null by not
  /// drawing one: inheriting the standard is right for a law that COUNTS in the
  /// registered calendar and simply left a level unnamed, and a fabrication for a
  /// law that has no months.
  List<String>? monthNames() {
    final monthLevel =
        firstMatch(levels, (level) => level.transition == 'gregorian.months') ?? level('month');
    final authored = monthLevel == null ? null : namesFor(monthLevel.name);
    if (authored != null) return authored;
    if (monthLevel != null && inheritsRegistered) return standardMonthNames;
    return inheritsRegistered && levels.isEmpty ? standardMonthNames : null;
  }

  bool hasMonths() => monthNames() != null;

  /// The CLDR calendar scale this law's DATE ladder counts in, or null when it
  /// counts in no registered calendar at all.
  ///
  /// This is the question the ICS boundary asks: RSCALE governs the date ladder a
  /// recurrence rule counts in and nothing below the base unit, so a frame that
  /// redefines its hours still counts dates in `gregory` and its rules stay
  /// spec-expressible, while a frame counting in no registered calendar must
  /// export concrete projections instead of a rule ICS would misread.
  String? calendarScale() => family?.calendar;

  // --- Unit magnitudes ------------------------------------------------------

  /// Exact days per one unit of [name], or null for a level whose length varies
  /// (a Gregorian month). [meanUnitDays] answers for those.
  Rational? unitDays(String name) {
    if (_unitDays.containsKey(name)) return _unitDays[name];
    final atoms = unitAtoms(name);
    return _unitDays[name] = atoms == null ? null : atoms * atomDays;
  }

  /// How many atoms one unit of [name] spans, or null when it varies.
  ///
  /// UNITS ARE DEFINED BY COMPOSITION FROM BELOW. Owner ruling: "that is wrong, I
  /// did not change the lenght of an hour I changed the length of a day. Day is
  /// defined as a number of hours, which are themselves a number of minutes,
  /// ect." So the finest declared unit is the ATOM, and every level's length is
  /// the product of the radices beneath it. Editing hour-within-day to 23 makes
  /// the DAY twenty-three standard hours long and leaves the hour untouched.
  Rational? unitAtoms(String name) {
    if (_unitAtoms.containsKey(name)) return _unitAtoms[name];
    return _unitAtoms[name] = _computeUnitAtoms(name);
  }

  Rational? _computeUnitAtoms(String name) {
    final level = this.level(name);
    if (level == null) {
      final standard = standardUnitDays[name];
      return standard == null ? null : standard / atomDays;
    }
    if (name == atomLevel) return Rational.one;
    // A level's OWN edge says how many of IT fit in its parent, so it describes
    // the PARENT's length and says nothing about its own. Only the child's edge
    // does that. Reading a level's own transition here is what made `day` — which
    // carries "how many days in a month" — look like a unit of no fixed length.
    final child = firstMatch(levels, (entry) => entry.within == name);
    if (child == null) return Rational.one;
    // A level containing a transition has no constant length and says so by
    // returning null rather than a mean masquerading as exact.
    if (child.transition != null) return null;
    final childAtoms = unitAtoms(child.name);
    // A level with no radix beneath it (the continuous tail) subdivides its
    // parent continuously rather than into a fixed count, so it contributes a
    // factor of one: a value of 0.25 there means a quarter of one parent unit.
    return childAtoms == null ? null : childAtoms * (child.radix ?? Rational.one);
  }

  /// Exact mean days per unit, defined for every level: a variable level's mean
  /// comes from its transition's registered mean child count, so a Gregorian
  /// month is exactly 146097/4800 days rather than the float 30.436875.
  Rational? meanUnitDays(String name) {
    final exact = unitDays(name);
    if (exact != null) return exact;
    final level = this.level(name);
    if (level == null) return null;
    final child = firstMatch(levels, (entry) => entry.within == level.name);
    if (child == null) return null;
    final childMean = meanUnitDays(child.name);
    if (childMean == null) return null;
    final perParent = child.transition == null
        ? child.radix
        : _transitions[child.transition]?.meanChildren;
    return perParent == null ? null : childMean * perParent;
  }

  /// How many units of [name] fit in one unit of [per] — "how many minutes in a
  /// day", "how many minutes in an hour", "how many days in a week". [per]
  /// defaults to the base unit.
  ///
  /// This is the one accessor that replaced the 1440s, and the one that replaced
  /// six named wrappers each re-hardcoding its own fallback. When this law never
  /// authored either unit, the ratio comes from the registered standard table —
  /// one table, in one place, rather than a constant per wrapper.
  ///
  /// The one uniform policy differs from those wrappers in exactly one place: a
  /// law whose BASE unit has no constant length (a ladder based on a Gregorian
  /// month) answers with that unit's exact mean, where the retired
  /// `daysPerWeek` silently substituted the atom and so reported seconds per
  /// week as days per week.
  Rational unitsPer(String name, [String? per]) {
    final unit = unitDays(name) ?? meanUnitDays(name);
    final parent = per == null ? baseDays : (unitDays(per) ?? meanUnitDays(per));
    if (unit == null || unit.isZero || parent == null || parent.isZero) {
      final standardUnit = standardUnitDays[name];
      final standardParent = standardUnitDays[per ?? 'day'];
      if (standardUnit == null || standardParent == null || standardUnit.isZero) {
        return Rational.one;
      }
      return standardParent / standardUnit;
    }
    return parent / unit;
  }

  /// The mean length of the level a month-scale stride steps by. A label ladder
  /// needs a stride in days for a variable unit; this is the exact value it
  /// needs, per this frame's own law.
  Rational meanMonthDays() {
    final monthLevel =
        firstMatch(levels, (level) => level.transition == 'gregorian.months') ?? level('month');
    return (monthLevel == null ? null : meanUnitDays(monthLevel.name)) ?? meanGregorianMonth;
  }

  // --- Duration magnitudes --------------------------------------------------

  /// What a bag of level counts ({hour: 2, minute: 30}) is worth in days under
  /// THIS law. A 23-hour day makes "2 hours" worth 2/23 of a day, and every
  /// consumer of a duration has to agree about that or the same event is two
  /// different lengths in two different lenses.
  ///
  /// Tolerant by contract: an unparseable magnitude yields zero rather than
  /// refusing (imported ICS is plausibly dirty), a level this law does not know
  /// is skipped, and a negative sum clamps to zero because every caller treats a
  /// duration as a non-negative span.
  Rational magnitudeDays(Coordinate? magnitude) {
    var total = Rational.zero;
    try {
      for (final part in magnitude?.levels ?? const <LevelEntry>[]) {
        final unit = unitDays(part.level) ?? meanUnitDays(part.level);
        if (unit != null) total += Rational.parse(part.value) * unit;
      }
    } catch (_) {
      return Rational.zero;
    }
    return total > Rational.zero ? total : Rational.zero;
  }

  // --- Cycles ---------------------------------------------------------------

  Cycle? cycle(String name) {
    final declared = _cycles[name];
    if (declared != null) return declared;
    // Same rule as [namesFor]: only a law that counts in the registered calendar
    // inherits its cycles. A law that does not has no week unless it says so.
    if (!inheritsRegistered) return null;
    return firstMatch(gregorianDeclaration.cycles, (entry) => entry.name == name);
  }

  List<String>? cycleNames(String name) => cycle(name)?.names;

  /// Every cycle in force, authored ones and the registered standard ones this
  /// declaration never overrode. An authoring surface needs the effective set,
  /// not just what happens to be written on this frame.
  List<Cycle> cycles() {
    final effective = <String, Cycle>{};
    if (inheritsRegistered) {
      for (final standard in gregorianDeclaration.cycles) {
        effective[standard.name] = cycle(standard.name)!;
      }
    }
    effective.addAll(_cycles);
    return effective.values.toList();
  }

  /// Which position in the cycle a given day ordinal falls on.
  int? cycleIndex(String name, Rational days) {
    final cycle = this.cycle(name);
    if (cycle == null) return null;
    final ordinal = ((days - epochDays) / baseDays).floor();
    return floorMod(ordinal + cycle.offset, cycle.radix.n).toInt();
  }

  String? cycleLabel(String name, Rational days) {
    final cycle = this.cycle(name);
    if (cycle == null) return null;
    final index = cycleIndex(name, days)!;
    final names = cycle.names;
    return names != null && index < names.length ? names[index] : '${cycle.name} ${index + 1}';
  }

  /// The weekday cycle's names, or NULL when this law declares no such cycle and
  /// inherits no calendar that would. A world with no week has no weekday names,
  /// and handing it seven Gregorian ones invents a fact.
  List<String>? weekdayNames() =>
      cycleNames('weekday') ?? (inheritsRegistered ? standardWeekdayNames : null);

  bool hasWeekdays() => weekdayNames() != null;

  String? weekdayLabel(Rational days) => hasWeekdays() ? cycleLabel('weekday', days) : null;

  // --- Eras -----------------------------------------------------------------

  bool hasEras() => eraTable != null;

  /// This era's stored key, or null for a frame that is not an era.
  String? eraKey() => era?.identity;

  List<EraEntry> eras() => eraTable?.entries ?? const [];

  /// How a year renders under this law: "3E 433" where the law has eras, and the
  /// plain year otherwise. Reads whichever levels the law actually declares
  /// rather than assuming a `year` level exists.
  String formatYear(Coordinate value) {
    if (eraTable == null) {
      final level = familyLadder.isNotEmpty
          ? familyLadder.first.name
          : (levels.isEmpty ? null : levels.first.name);
      return level == null ? '' : value.value(level, '');
    }
    return eraTable!.format(eraEntry!.key, value.value(yearLevel!, '1'));
  }

  /// The era-qualified year at a day ordinal, or the plain year without eras.
  String formatYearAtDays(Rational days) => formatYear(fromDays(days));

  /// Era-qualified text ("3E 433", "44 BCE") to (era, year), or null.
  EraQualified? parseYear(Object? text) => eraTable?.parse(text);

  /// Does this law place its coordinates on the running clock at all?
  ///
  /// Only a positional law does: a non-positional law reads its base level as a
  /// bare count with no statement of which day anything begins on, so "now" has
  /// no position in it. An author may also say so outright with `clock: false` —
  /// a calendar of a world with no relation to this one has no now, and drawing a
  /// Now line on it invents a fact.
  bool mapsToClock() =>
      !uncountableEra && positional && sharesStandardAtom() && declaration.clock != false;

  /// Does this law's atom resolve to a standard duration?
  ///
  /// The atom is the shared denominator for absolute comparison, so this is the
  /// question "are this frame's positions commensurable with Earth days at all?".
  /// A ladder whose finest unit is a `letter` of a handwritten phrase has a
  /// perfectly good axis of its own and no answer here — and an authored
  /// `atomDays` or `origin` IS that answer, which is why either one counts.
  ///
  /// Without it, [toDays] still returns exact, ordered positions, but they are
  /// positions on THIS frame's axis and comparing them to another frame's is
  /// meaningless. That is what correspondence staples exist to state.
  bool sharesStandardAtom() =>
      declaration.atomDays != null ||
      declaration.hasOrigin ||
      (atomLevel != null && standardUnitDays.containsKey(atomLevel));

  // --- Conversion -----------------------------------------------------------

  /// A nested coordinate to an exact day ordinal.
  ///
  /// With a family, the ladder above the base resolves in closed form and the
  /// levels below add their own fractions — so `hour` genuinely contributes 1/23
  /// of a day once the declaration says radix 23. Without a family there is no
  /// origin to count from, so the base level's value IS the count.
  Rational toDays(Coordinate value) {
    if (uncountableEra) {
      throw LawRefusal(
        '${era!.label} has no year axis, so nothing in it has a date. Its events'
        ' are ordered by their place in the era chain and nothing else.',
      );
    }
    final family = this.family;
    if (family != null) {
      final parts = <BigInt>[];
      for (final level in familyLadder) {
        // The era table owns the year level's numbering, so that value is the
        // PROPER year it resolves to rather than whatever the coordinate stored.
        if (eraTable != null && level.name == yearLevel) {
          parts.add(_properYear(value));
          continue;
        }
        parts.add(BigInt.parse(value.value(level.name, family.defaults[level.name] ?? '1')));
      }
      // In ATOMS first, then out to standard days once: the whole-unit count is
      // in base units, each of which is [baseAtoms] atoms long, and the levels
      // below contribute their own atoms directly. Composing in the atom is what
      // makes a shortened day shorten the absolute span rather than compress the
      // hours inside it.
      final whole = family.toWholeUnits(familyLadder, parts);
      final atoms = Rational(whole) * baseAtoms + _belowAtoms(value);
      return atoms * atomDays + epochDays + originDays;
    }
    // A value naming levels this law does not declare is NOT a value in this law,
    // and reading its base level as a bare count would answer a question nobody
    // asked: a {year, month, day} coordinate handed to a law with no family
    // placed 1973-03-15 at day 15, silently, because `day` happened to be the
    // base level. A magnitude of "15 days" and the fifteenth of March are not the
    // same number, so this refuses instead of reading.
    //
    // A law that declares no levels at all is a bare day axis and keeps the
    // permissive read: there is nothing there to contradict.
    if (levels.isNotEmpty) {
      final foreign = [
        for (final entry in value.levels)
          if (!_byName.containsKey(entry.level)) entry.level,
      ];
      if (foreign.isNotEmpty) {
        throw LawRefusal(
          'Frame ${frameId ?? '(anonymous)'} declares no ${foreign.join(', ')} level,'
          ' so this coordinate is not a position in it (its levels are'
          ' ${levelNames().join(', ')}).',
        );
      }
    }
    final raw =
        firstMatch(value.levels, (entry) => entry.level == baseLevel) ??
        firstMatch(value.levels, (entry) => entry.level == 'day');
    if (raw == null) {
      throw LawRefusal('Frame ${frameId ?? '(anonymous)'} has no temporal coordinate law');
    }
    return Rational.parse(raw.value) * baseDays + epochDays;
  }

  /// A day ordinal back to a nested coordinate. The levels below the base only
  /// appear when at least one of them is non-zero, so midnight stays a bare
  /// date — the shape every stored document expects.
  Coordinate fromDays(Rational days, [int fractionPlaces = 12]) {
    if (uncountableEra) {
      throw LawRefusal('${era!.label} has no year axis, so no position in it has a date.');
    }
    final family = this.family;
    if (family == null) {
      return Coordinate.of([(baseLevel, ((days - epochDays) / baseDays).toJson())]);
    }
    // Into ATOMS once, then decompose: whole base units first, then whatever
    // atoms are left spent down the below-base ladder.
    final atoms = (days - epochDays - originDays) / atomDays;
    final whole = (atoms / baseAtoms).floor();
    var remainder = atoms - baseAtoms * Rational(whole);
    // Under an era law the year that comes back is the era-LOCAL year, because
    // the frame is already the era, and the round trip preserves what the author
    // wrote rather than a linearized equivalent of it. A proper year outside this
    // era's own range means the ordinal does not belong to this era at all, and
    // that refuses rather than silently renumbering into a neighbour.
    final above = <LevelEntry>[
      for (final (name, amount) in family.fromWholeUnits(familyLadder, whole))
        (
          level: name,
          value: eraTable != null && name == yearLevel ? '${_localYear(amount)}' : '$amount',
        ),
    ];
    final below = <LevelEntry>[];
    var significant = false;
    for (final (index, level) in belowLadder.indexed) {
      final unit = unitAtoms(level.name);
      if (unit == null) continue;
      // The continuous tail carries whatever is left as a fraction of one of its
      // own units, and only appears at all when there is something left.
      if (index == belowLadder.length - 1 && level.radix == null) {
        if (!remainder.isZero) {
          below.add((level: level.name, value: (remainder / unit).toDecimal(fractionPlaces)));
          significant = true;
        }
        continue;
      }
      final amount = (remainder / unit).floor();
      remainder -= unit * Rational(amount);
      if (amount != BigInt.zero) significant = true;
      below.add((level: level.name, value: '$amount'));
    }
    return Coordinate(significant ? [...above, ...below] : above);
  }

  /// The proper year an era-qualified coordinate names. The era is REQUIRED: a
  /// year with no era on a calendar that has eras is genuinely ambiguous, and
  /// defaulting it to "the era the anchor happens to sit in" would be exactly the
  /// invented meaning this model refuses.
  BigInt _properYear(Coordinate value) =>
      eraTable!.toProperYear(eraEntry!.key, value.value(yearLevel!, '1'));

  BigInt _localYear(BigInt properYear) {
    final resolved = eraTable!.fromProperYear(properYear);
    if (resolved.entry.key != eraEntry!.key) {
      throw LawRefusal('That position falls in ${resolved.entry.name}, not ${eraEntry!.name}.');
    }
    return resolved.year;
  }

  Rational _belowAtoms(Coordinate value) {
    var total = Rational.zero;
    for (final level in belowLadder) {
      final unit = unitAtoms(level.name);
      if (unit == null) continue;
      total += Rational.parse(value.value(level.name)) * unit;
    }
    return total;
  }
}

// --- Resolution and caching -------------------------------------------------

/// What a frame's place in the succession chain says about its era. Injected
/// rather than read from a declaration, because the chain is derived from
/// relation records: a staple edit changes a law without changing its
/// declaration at all.
typedef EraLookup = EraContext? Function(Map<String, Object?> document, String frameId);

/// The declaration a frame's coordinates are actually governed by, plus the
/// identity to cache it under.
typedef _Resolved = ({Object? source, Declaration? ready, String frameId, bool? positional});

typedef _Cached = ({Object? source, String eraKey, CoordinateLaw law});

/// Law resolution with its cache, and the one refusal seam every "what is wrong
/// with this?" question in the model asks.
///
/// Overscale doctrine: the engine asks for a frame's law inside occurrence loops,
/// so resolution has to be O(1) after the first call. The cache is keyed by
/// document identity (a plain [Map] key, which Dart hashes by identity, plus an
/// explicit [invalidate]) and checked two ways on every hit: the resolved
/// declaration's own identity, and the era key. Identity alone would miss an
/// in-place mutation; the explicit call alone would miss an undo that swaps whole
/// records. Both together mean an applied coordinate edit is live on the next
/// render, which is the failure this replaces: "I swaped both Wall Time and Human
/// time magnitude to Hour:Day:23 ... and uppon inspection there still appears to
/// be 24 hours in a day".
class CoordinateLaws {
  CoordinateLaws({this.eras});

  final EraLookup? eras;
  final Map<Map<String, Object?>, Map<String, _Cached>> _cache = {};

  CoordinateLaw of(Map<String, Object?> document, String frameId) {
    final resolved = _resolveDeclaration(document, frameId, <String>{});
    final perDocument = _cache.putIfAbsent(document, () => {});
    final era = eras?.call(document, frameId);
    final eraKey = era == null ? '' : '${era.identity}:${era.countable}';
    final cached = perDocument[frameId];
    if (cached != null && identical(cached.source, resolved.source) && cached.eraKey == eraKey) {
      return cached.law;
    }
    final law = CoordinateLaw(
      resolved.ready ?? Declaration.parse(asMap(resolved.source), _label(resolved.frameId)),
      frameId: resolved.frameId,
      positional: resolved.positional,
      era: era,
    );
    perDocument[frameId] = (source: resolved.source, eraKey: eraKey, law: law);
    return law;
  }

  /// Called by every committed change. Without a document, the whole cache goes.
  void invalidate([Map<String, Object?>? document]) {
    if (document == null) {
      _cache.clear();
    } else {
      _cache.remove(document);
    }
  }

  Attempt<CoordinateLaw> attempt(Map<String, Object?> document, String frameId) =>
      _attempt(() => of(document, frameId));

  Attempt<Rational> daysAttempt(Map<String, Object?> document, String frameId, Coordinate value) =>
      _attempt(() => of(document, frameId).toDays(value));

  /// What is wrong with this frame's declaration, in the author's words, or null
  /// when it resolves. A frame editor shows this instead of letting an
  /// unresolvable law fail silently at render time.
  String? lawError(Map<String, Object?> document, String frameId) =>
      attempt(document, frameId).refusal;

  /// What is wrong with this COORDINATE under its frame's law. The
  /// refuse-before-store discipline extends to validation: a document whose era
  /// coordinates only fail at query time is not a valid document, and reporting
  /// it as one defers a certain failure to the worst possible moment.
  String? valueError(Map<String, Object?> document, String frame, Coordinate v) =>
      daysAttempt(document, frame, v).refusal;

  /// The query path's refusal posture: a single unresolvable frame must not take
  /// down a whole projection, so a caller can skip the record and collect the
  /// reason rather than abort the query.
  Rational? daysOrNull(Map<String, Object?> document, String frame, Coordinate v) =>
      daysAttempt(document, frame, v).resolved;

  /// The law that governs DISPLAY arithmetic for a render pass: the primary
  /// frame's. Falls back to the registered standard when there is no primary yet
  /// or its declaration is unresolvable, because a broken frame must not blank
  /// the stage; [lawError] is how a surface asks what went wrong.
  CoordinateLaw display(Map<String, Object?> document, String? frameId) =>
      frameId == null ? gregorianLaw : attempt(document, frameId).resolved ?? gregorianLaw;

  /// The one duration-in-days primitive, melted onto the law.
  ///
  /// [document] names the law through the magnitude's own `frame` (normally a
  /// measure frame). A call site that has the document MUST pass it: the standard
  /// fallback exists for genuinely law-free contexts, not as a convenience,
  /// because a duration measured against the wrong law is the same class of
  /// silent wrongness this module removes.
  Rational durationMagnitudeDays(
    Map<String, Object?>? magnitude, {
    Map<String, Object?>? document,
    CoordinateLaw? law,
  }) => magnitudeLaw(
    magnitude,
    document: document,
    law: law,
  ).magnitudeDays(Coordinate.fromJson(asMap(magnitude?['value'])));

  CoordinateLaw magnitudeLaw(
    Map<String, Object?>? magnitude, {
    Map<String, Object?>? document,
    CoordinateLaw? law,
  }) {
    if (law != null) return law;
    final frameId = magnitude?['frame'];
    if (document != null && frameId is String && asMap(document['frames'])?[frameId] != null) {
      return display(document, frameId);
    }
    return gregorianLaw;
  }
}

/// The one resolution chain, walked in the order a frame's own mental model
/// needs: an explicit `coordinateDefinition`, then the gregorian-kind
/// default-ladder shorthand, then a frame's own authored origin, then `basis`.
///
/// POSITIONALITY IS A PROPERTY OF THE LADDER AND THE REGISTRY, never of a kind
/// string or a trait. `positional: null` hands the decision to the law, which asks
/// whether a registered family can actually execute the ladder — so an identical
/// year > month > day declaration resolves the same way whether or not anyone
/// remembered to write `kind: "gregorian"` on it. Deciding by label instead
/// placed 2026-08-20 at day ordinal 20, silently.
///
/// The one semantic marker that survives is `measure`, and it is not a label for
/// arithmetic: it says what the frame IS. A measure frame's coordinate is a
/// MAGNITUDE — "5 days" — so its levels are counts and no family may reinterpret
/// them as a date.
///
/// The BASIS deliberately outranks a frame's own non-calendar declaration: a
/// calendar whose basis is Wall Time inherits Wall Time's law, including a radix
/// edited there, without restating the ladder itself.
_Resolved _resolveDeclaration(Map<String, Object?> document, String frameId, Set<String> seen) {
  if (!seen.add(frameId)) {
    throw LawRefusal('Coordinate definition cycle at $frameId');
  }
  final frame = asMap(asMap(document['frames'])?[frameId]);
  if (frame == null) throw LawRefusal('Unknown frame: $frameId');
  final definition = frame['coordinateDefinition'];
  if (definition is String && definition.isNotEmpty) {
    return _resolveDeclaration(document, definition, seen);
  }
  final declaration = asMap(frame['coordinate']);
  final authored = asList(declaration?['levels']).isNotEmpty;
  final traits = [for (final trait in asList(frame['traits'])) '$trait'];
  final measure = traits.contains('measure') || traits.contains('duration');
  final positional = measure ? false : null;
  _Resolved own(Object? source, Declaration? ready) =>
      (source: source, ready: ready, frameId: frameId, positional: positional);
  if (declaration?['kind'] == 'gregorian' || traits.contains('gregorian')) {
    // A gregorian frame with no authored ladder gets the registered one, which is
    // what the kind has always meant here. It survives only as this
    // default-ladder shorthand, never as the positionality answer.
    return authored
        ? own(frame['coordinate'], null)
        : own(gregorianDeclaration, gregorianDeclaration);
  }
  // An authored ORIGIN is a frame stating that its own levels name positions, so
  // such a frame owns its coordinates outright and does not defer to a basis.
  if (authored && declaration!['origin'] != null) {
    // The authored map itself, never a copy: the cache keys on its identity.
    return own(frame['coordinate'], null);
  }
  final basis = frame['basis'];
  if (basis is String && basis.isNotEmpty) {
    return _resolveDeclaration(document, basis, seen);
  }
  return own(frame['coordinate'], null);
}

// --- The refusal seam -------------------------------------------------------

/// A resolved answer or the author's own sentence about why there isn't one. The
/// four wrappers that each used to carry their own try/catch are thin adapters
/// over this.
sealed class Attempt<T> {
  const Attempt();

  /// The answer, or null when there is not one.
  T? get resolved => switch (this) {
    Resolved(:final value) => value,
    _ => null,
  };

  /// The author's sentence, or null when the question was answered.
  String? get refusal => switch (this) {
    Refused(:final message) => message,
    _ => null,
  };
}

final class Resolved<T> extends Attempt<T> {
  const Resolved(this.value);
  final T value;
}

final class Refused<T> extends Attempt<T> {
  const Refused(this.message);
  final String message;
}

Attempt<T> _attempt<T>(T Function() body) {
  try {
    return Resolved(body());
  } catch (error) {
    return Refused(refusalText(error));
  }
}

// --- The standard boundary --------------------------------------------------
//
// RFC 5545 times, the host wall clock, and any other interface that speaks plain
// civil Gregorian convert HERE, through the registered entries, and nowhere else.
// ICS is an explicitly lossy boundary that always speaks standard civil
// Gregorian: an edited coordinate law never reinterprets an incoming ICS time,
// and a coordinate under a non-standard law is converted at the boundary rather
// than emitted as though its level values were Gregorian.
//
// These are named functions rather than inline calls on [gregorianLaw] because
// the name is the assertion: a call site that reads `civilCoordinateToDays` is
// declaring "standard Gregorian, deliberately, not this document's law".

final CoordinateLaw gregorianLaw = CoordinateLaw(gregorianDeclaration, frameId: 'gregorian');

Rational civilCoordinateToDays(Coordinate value) => gregorianLaw.toDays(value);

Coordinate daysToCivilCoordinate(Rational days, [int subsecondPlaces = 12]) =>
    gregorianLaw.fromDays(days, subsecondPlaces);
