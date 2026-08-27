// Variable-precision coordinate entry: the spec.
//
// Generative by ruling (Don, 2026-08-27): "We should never be testing for a
// specific case, we should be testing for a general case." So the properties
// below quantify over RANDOM LADDERS -- random invented level names, random
// radices, a random continuous tail, and the registered Gregorian family's own
// variable levels -- and over every authored depth each ladder admits. The cases
// labelled RULED ANCHOR are the worked examples the rulings state in words, or a
// refusal whose sentence is itself the contract; neither is derivable from a
// property.
//
// The restatements here are written from the RULINGS and from the law's own
// public surface (`levels`, `namesFor`, `transitionDefinition`), deliberately
// not from coordinate_entry.dart, so agreement between them means something.
//
// Nothing below builds a coordinate by hand except in a ruled anchor: the random
// coordinates are DRILLED through the picker, which is what makes "the picker
// offers exactly what the field accepts" a property rather than a hope.

import 'dart:math';

import 'package:chronolog/core/coordinate_entry.dart';
import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/era_chain.dart';
import 'package:chronolog/core/eras.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/records.dart';
import 'package:test/test.dart';

const int specSeed = 20260827;
const int iterations = 120;

T _pick<T>(Random random, List<T> items) => items[random.nextInt(items.length)];

CoordinateLaw _law(Json declaration, String frameId) =>
    CoordinateLaw(Declaration.parse(declaration, 'Frame $frameId'), frameId: frameId);

/// A custom, non-Gregorian nested ladder: fixed 8/8/8 radices, authored level
/// and value names, no transition and no CLDR calendar anywhere. Mirrors the
/// shape of the skyland fiction's own timeline, with authored value names on one
/// level so name resolution against a NON-Gregorian vocabulary is exercised too.
const List<String> skylandSeasons = [
  'Ashfall',
  'Ashen',
  'Waking',
  'Bloom',
  'Highsun',
  'Ember',
  'Harvest',
  'Hollow',
];

CoordinateLaw skylandLaw() => _law({
  'kind': 'nested',
  'levels': [
    {'name': 'epoch'},
    {'name': 'season', 'within': 'epoch', 'radix': '8', 'names': skylandSeasons},
    {'name': 'pulse', 'within': 'season', 'radix': '8'},
    {'name': 'beat', 'within': 'pulse', 'radix': '8'},
  ],
}, 'line:skyland-test');

// --- Random ladders ---------------------------------------------------------

/// An invented ladder: a root nobody can count, one to four constant-radix
/// levels, and optionally the continuous tail. Level names are invented, so
/// nothing can resolve through the registered Gregorian vocabulary by accident.
Json _inventedLadder(Random random, {required bool tail, required bool names}) {
  final rungs = 1 + random.nextInt(4);
  final namedRung = names ? 1 + random.nextInt(rungs) : -1;
  return {
    'kind': 'nested',
    'levels': [
      {'name': 'root'},
      for (var index = 1; index <= rungs; index += 1)
        {
          'name': 'rung$index',
          'within': index == 1 ? 'root' : 'rung${index - 1}',
          'radix': '${2 + random.nextInt(23)}',
          if (index == namedRung)
            'names': [for (var offset = 0; offset < 40; offset += 1) 'name$offset'],
        },
      if (tail) {'name': 'grain', 'within': 'rung$rungs'},
    ],
  };
}

/// A ladder counting in the REGISTERED calendar, so the properties see levels
/// whose child count genuinely varies -- a leap February, a leap year -- rather
/// than only constant radices.
Json _registeredLadder(Random random) {
  final above = _pick(random, [
    [
      {'name': 'year'},
      {'name': 'month', 'within': 'year', 'transition': 'gregorian.months'},
    ],
    [
      {'name': 'year'},
      {'name': 'month', 'within': 'year', 'transition': 'gregorian.months'},
      {'name': 'day', 'within': 'month', 'transition': 'gregorian.days'},
    ],
    [
      {'name': 'year'},
      {'name': 'day', 'within': 'year', 'transition': 'gregorian.daysInYear'},
    ],
  ]);
  final below = random.nextInt(4);
  var parent = '${above.last['name']}';
  final rungs = <Json>[];
  for (var index = 1; index <= below; index += 1) {
    rungs.add({'name': 'sub$index', 'within': parent, 'radix': '${2 + random.nextInt(60)}'});
    parent = 'sub$index';
  }
  return {
    'kind': 'nested',
    'levels': [
      ...above,
      ...rungs,
      if (below > 0 && random.nextBool()) {'name': 'grain', 'within': parent},
    ],
  };
}

/// A vocabulary of distinct single-word names, some sharing a prefix.
const List<String> namePool = [
  'Ash',
  'Ashen',
  'Ashfall',
  'Bloom',
  'Blossom',
  'Ember',
  'Emberfall',
  'Harvest',
  'Hollow',
  'Wake',
  'Waking',
  'Highsun',
];

/// A ladder whose bounded level DECLARES its own vocabulary, as against
/// [_registeredLadder], whose month level INHERITS one it never spelled out.
Json _alphabeticLadder(Random random, [List<String>? names]) {
  final chosen = names ?? ([...namePool]..shuffle(random)).take(2 + random.nextInt(10)).toList();
  return {
    'kind': 'nested',
    'levels': [
      {'name': 'root'},
      {'name': 'named', 'within': 'root', 'radix': '${chosen.length}', 'names': chosen},
      {'name': 'grain', 'within': 'named', 'radix': '${2 + random.nextInt(9)}'},
    ],
  };
}

/// Can this label be TYPED at all? A single alphabetic token is what
/// separator-agnostic tokenizing can carry; a multi-word name or one bearing
/// digits cannot survive tokenizing in the first place, which is a separate
/// question from whether the field knows the vocabulary.
bool _typable(String label) => RegExp(r'^[A-Za-z]+$').hasMatch(label);

/// Is this the ladder's continuous tail -- the trailing level declaring neither
/// a radix nor a transition? Restated from the ruling, off the law's own levels.
bool _isTail(CoordinateLaw law, String name) {
  final last = law.levels.isEmpty ? null : law.levels.last;
  return last != null &&
      last.name == name &&
      last.radix == null &&
      last.transition == null &&
      law.levels.length > 1;
}

/// The low bound of a level, restated: a level the family counts from one is
/// one-based, everything else is zero-based.
BigInt _base(CoordinateLaw law, String name) =>
    law.family?.defaults[name] == '1' ? BigInt.one : BigInt.zero;

/// How many children a level has, restated from its own declaration and its
/// transition's own rule -- never from coordinate_entry.dart.
BigInt? _count(CoordinateLaw law, String name, Coordinate chosen) {
  final level = law.level(name);
  if (level?.radix != null) return level!.radix!.n;
  final transition = level?.transition;
  if (transition == null) return null;
  return transitionDefinition(transition)!.childrenIn({
    for (final entry in chosen.levels)
      if (BigInt.tryParse(entry.value) case final BigInt value) entry.level: value,
  });
}

/// A random coordinate at [depth], DRILLED through the picker: every value comes
/// from the rung that offered it, so a coordinate this produces is one the field
/// itself must accept.
Coordinate _drill(CoordinateLaw law, Random random, int depth, {String Function()? root}) {
  var value = Coordinate.empty;
  for (var step = 0; step < depth; step += 1) {
    final rungs = coordinatePickerLadder(law, value);
    if (rungs.isEmpty) break;
    final open = rungs.last;
    if (open.chosen != null) break;
    final String chosen;
    if (open.bounded) {
      chosen = _pick(random, open.options).value;
    } else if (_isTail(law, open.level)) {
      chosen = '0.${1 + random.nextInt(9998)}${1 + random.nextInt(9)}';
    } else {
      // The one value no rung can offer: the root is unbounded by construction,
      // so the caller supplies it. An era law's root is a year that era HAS.
      chosen = root == null ? '${random.nextInt(4000) - 2000}' : root();
    }
    value = Coordinate([
      for (final entry in value.levels)
        if (entry.level != open.level) entry,
      (level: open.level, value: chosen),
    ]);
  }
  return value;
}

// --- Era chains -------------------------------------------------------------

/// An era chain over one ladder: a calendar frame carrying the ladder, one frame
/// per era inheriting it through `basis`, and a succession staple per boundary.
/// DIRECTION IS THE ORDER of the ends; no `role` field appears anywhere here.
CoordinateLaw chainLaw(List<Json> eras, Json ladder, String eraId) {
  var document = Document(
    meta: const {'title': 'chain'},
    frames: {
      'frame:chain-calendar': Frame(
        id: 'frame:chain-calendar',
        title: 'Chain calendar',
        traits: const ['line', 'temporal', 'calendar', 'group'],
        extra: {'coordinate': ladder},
      ),
      for (final era in eras)
        '${era['id']}': Frame(
          id: '${era['id']}',
          title: '${(era['era'] as Json)['name']}',
          traits: const ['line', 'temporal', 'era'],
          extra: {'basis': 'frame:chain-calendar', 'era': era['era']},
        ),
    },
  );
  for (final (index, era) in eras.indexed) {
    if (index + 1 >= eras.length) continue;
    document = putStaple(
      document,
      id: 'succession:${era['id']}',
      kind: 'succession',
      ends: [StapleEnd.frame('${era['id']}'), StapleEnd.frame('${eras[index + 1]['id']}')],
    ).document;
  }
  return CoordinateLaws(eras: eraLookup(document)).of(document.toJson(), eraId);
}

/// BCE descending and open below, CE ascending and open above -- a suffix affix
/// on the registered Gregorian ladder.
final List<Json> bceCeChain = [
  {
    'id': 'era:bce',
    'era': {
      'key': 'BCE',
      'name': 'Before Common Era',
      'direction': 'descending',
      'firstYear': '1',
      'years': 'open',
      'affix': 'suffix',
    },
  },
  {
    'id': 'era:ce',
    'era': {
      'key': 'CE',
      'name': 'Common Era',
      'direction': 'ascending',
      'firstYear': '1',
      'years': 'open',
      'affix': 'suffix',
      'anchor': {'year': '1', 'properYear': '1'},
    },
  },
];

const Json plainGregorianLadder = {
  'kind': 'gregorian',
  'levels': [
    {'name': 'year'},
    {'name': 'month', 'within': 'year', 'transition': 'gregorian.months'},
    {'name': 'day', 'within': 'month', 'transition': 'gregorian.days'},
    {'name': 'hour', 'within': 'day', 'radix': '24'},
    {'name': 'minute', 'within': 'hour', 'radix': '60'},
    {'name': 'second', 'within': 'minute', 'radix': '60'},
  ],
};

/// A uniform 365-day year with no month and no Gregorian family at all, under a
/// true era chain: Merethic open below, three bounded eras, Fourth Era open
/// above. A prefix affix on a wholly non-Gregorian ladder.
const Json tamrielLadder = {
  'kind': 'nested',
  'baseLevel': 'day',
  'levels': [
    {'name': 'year'},
    {'name': 'day', 'within': 'year', 'radix': '365'},
    {'name': 'hour', 'within': 'day', 'radix': '24'},
  ],
};

List<Json> tamrielChain() => [
  for (final (key, name, years, anchored) in [
    ('ME', 'Merethic Era', 'open', false),
    ('1E', 'First Era', '2920', true),
    ('2E', 'Second Era', '896', false),
    ('3E', 'Third Era', '433', false),
    ('4E', 'Fourth Era', 'open', false),
  ])
    {
      'id': 'era:${key.toLowerCase()}',
      'era': {
        'key': key,
        'name': name,
        'direction': key == 'ME' ? 'descending' : 'ascending',
        'firstYear': '1',
        'years': years,
        if (anchored) 'anchor': {'year': '1', 'properYear': '1'},
      },
    },
];

Coordinate _civil(Map<String, String> parts) =>
    Coordinate([for (final entry in parts.entries) (level: entry.key, value: entry.value)]);

void main() {
  // --- The round trip, at every depth, over random ladders -----------------

  group('precision is depth', () {
    test('format then parse is the identity at every authored depth, and the '
        'text it produces is already canonical', () {
      final random = Random(specSeed);
      for (var round = 0; round < iterations; round += 1) {
        final law = random.nextBool()
            ? _law(
                _inventedLadder(random, tail: random.nextBool(), names: random.nextBool()),
                'line:invented-$round',
              )
            : _law(_registeredLadder(random), 'line:registered-$round');
        for (var depth = 1; depth <= law.levels.length; depth += 1) {
          final value = _drill(law, random, depth);
          if (value.levels.isEmpty) continue;
          final text = formatCoordinateEntry(value, law);
          final parsed = parseCoordinateEntry(text, law);
          expect(parsed.coordinate, value, reason: 'round trip of "$text"');
          expect(formatCoordinateEntry(parsed.coordinate, law), text, reason: 'canonical: "$text"');
          // Precision IS depth: the level the author stopped at survives, and
          // the parse reports exactly it.
          expect(parsed.depth, authoredDepth(value, law));
          expect(parsed.depth, law.levels[value.levels.length - 1].name);
        }
      }
    });

    test('authoredDepth reports the deepest level of THIS law present, and '
        'ignores a level the law does not declare', () {
      final random = Random(specSeed + 1);
      for (var round = 0; round < iterations; round += 1) {
        final law = _law(_inventedLadder(random, tail: false, names: false), 'line:depth-$round');
        expect(authoredDepth(Coordinate.empty, law), isNull);
        for (var depth = 1; depth <= law.levels.length; depth += 1) {
          final value = _drill(law, random, depth);
          expect(authoredDepth(value, law), law.levels[depth - 1].name);
          // A level this law never declared is invisible to depth, whichever
          // end of the coordinate it is written on.
          final foreign = Coordinate([
            (level: 'no-such-level', value: '9'),
            ...value.levels,
            (level: 'another-foreign', value: '9'),
          ]);
          expect(authoredDepth(foreign, law), law.levels[depth - 1].name);
        }
      }
    });
  });

  // --- Range refusal, from the level's own count ---------------------------

  group('a value outside a level is refused, never clamped', () {
    test('every bounded level refuses its own base + count and accepts the '
        'value one below it', () {
      final random = Random(specSeed + 2);
      var checked = 0;
      for (var round = 0; round < iterations; round += 1) {
        final law = random.nextBool()
            ? _law(_inventedLadder(random, tail: false, names: false), 'line:range-$round')
            : _law(_registeredLadder(random), 'line:range-greg-$round');
        for (var depth = 1; depth < law.levels.length; depth += 1) {
          final fixed = _drill(law, random, depth);
          final level = law.levels[depth];
          if (_isTail(law, level.name)) continue;
          final count = _count(law, level.name, fixed);
          if (count == null) continue;
          final base = _base(law, level.name);
          final legal = Coordinate([
            ...fixed.levels,
            (level: level.name, value: '${base + count - BigInt.one}'),
          ]);
          expect(
            () => parseCoordinateEntry(formatCoordinateEntry(legal, law), law),
            returnsNormally,
          );
          final over = Coordinate([...fixed.levels, (level: level.name, value: '${base + count}')]);
          expect(
            () => parseCoordinateEntry(formatCoordinateEntry(over, law), law),
            throwsA(isA<LawRefusal>()),
            reason: '${level.name} has $count children from $base',
          );
          checked += 1;
        }
      }
      expect(checked, greaterThan(iterations));
    });

    test('RULED ANCHOR: 2026-02-30 is refused and 2024-02-29 parses, driven by '
        "the transition's own rule", () {
      expect(() => parseCoordinateEntry('2026-02-30', gregorianLaw), throwsA(isA<LawRefusal>()));
      expect(parseCoordinateEntry('2024-02-29', gregorianLaw).coordinate.value('day'), '29');
      expect(() => parseCoordinateEntry('2026-13-01', gregorianLaw), throwsA(isA<LawRefusal>()));
      expect(
        () => parseCoordinateEntry('2026-01-01 24:00', gregorianLaw),
        throwsA(isA<LawRefusal>()),
      );
    });
  });

  // --- Authored names -----------------------------------------------------

  group('an authored name resolves by exact match, then unambiguous 3+ prefix', () {
    const List<String> pool = [
      'Ash',
      'Ashen',
      'Ashfall',
      'Bloom',
      'Blossom',
      'Ember',
      'Emberfall',
      'Harvest',
      'Hollow',
      'Wake',
      'Waking',
      'Highsun',
    ];

    test('a random prefix of a random authored vocabulary resolves iff it is '
        'unambiguous at three characters or more, and an exact match always wins', () {
      final random = Random(specSeed + 3);
      for (var round = 0; round < iterations; round += 1) {
        final names = [...pool]..shuffle(random);
        final chosen = names.take(2 + random.nextInt(names.length - 1)).toList();
        final law = _law({
          'kind': 'nested',
          'levels': [
            {'name': 'root'},
            {'name': 'named', 'within': 'root', 'radix': '${chosen.length}', 'names': chosen},
          ],
        }, 'line:named-$round');
        final target = _pick(random, chosen);
        final length = 1 + random.nextInt(target.length);
        final token = random.nextBool()
            ? target.substring(0, length)
            : target.substring(0, length).toUpperCase();
        final lower = token.toLowerCase();
        // Restated from the ruling, not from the module: exact first, then a
        // 3+-character prefix that exactly one name answers to.
        final exact = chosen.indexWhere((name) => name.toLowerCase() == lower);
        final prefixed = [
          for (final (index, name) in chosen.indexed)
            if (name.toLowerCase().startsWith(lower)) index,
        ];
        final expected = exact >= 0
            ? exact
            : (token.length >= 3 && prefixed.length == 1 ? prefixed.single : -1);
        if (expected < 0) {
          expect(
            () => parseCoordinateEntry('5 $token', law),
            throwsA(isA<LawRefusal>()),
            reason: '"$token" against ${chosen.join(', ')}',
          );
        } else {
          expect(
            parseCoordinateEntry('5 $token', law).coordinate.value('named'),
            '$expected',
            reason: '"$token" against ${chosen.join(', ')}',
          );
        }
      }
    });

    test('RULED ANCHOR: a month name, an unambiguous prefix, a too-short token, '
        "and a custom law's own ambiguity", () {
      expect(parseCoordinateEntry('2026 march 4', gregorianLaw).coordinate.value('month'), '3');
      expect(parseCoordinateEntry('2026 Aug 20', gregorianLaw).coordinate.value('month'), '8');
      // Too short to attempt prefix resolution at all.
      expect(() => parseCoordinateEntry('2026 Ju 4', gregorianLaw), throwsA(isA<LawRefusal>()));
      expect(() => parseCoordinateEntry('2026 Xyz 20', gregorianLaw), throwsA(isA<LawRefusal>()));
      // "Ash" matches both "Ashfall" and "Ashen" in a NON-Gregorian vocabulary,
      // and is refused on the same rule.
      final skyland = skylandLaw();
      expect(() => parseCoordinateEntry('1 Ash', skyland), throwsA(isA<LawRefusal>()));
      expect(parseCoordinateEntry('1 Waking', skyland).coordinate.value('season'), '2');
    });

    test('everything the picker OFFERS, typing ACCEPTS -- including a vocabulary '
        'the law inherits rather than declares', () {
      final random = Random(specSeed + 9);
      var inheritedRungs = 0, namedOptions = 0, numericOptions = 0;
      for (var round = 0; round < iterations; round += 1) {
        final law = switch (random.nextInt(3)) {
          0 => _law(_registeredLadder(random), 'line:offer-registered-$round'),
          1 => _law(_alphabeticLadder(random), 'line:offer-named-$round'),
          _ => gregorianLaw,
        };
        for (var depth = 1; depth < law.levels.length; depth += 1) {
          final fixed = _drill(law, random, depth);
          if (fixed.levels.length != depth) continue;
          final open = coordinatePickerLadder(law, fixed).last;
          if (!open.bounded) continue;
          final head = formatCoordinateEntry(fixed, law);
          if (head.isEmpty) continue;
          // The EFFECTIVE vocabulary -- what the rung labels itself from. A
          // level that inherits one is the case the field used to refuse.
          final vocabulary = law.namesFor(open.level);
          final declared = law.level(open.level)!.names;
          if (vocabulary != null && declared == null) inheritedRungs += 1;
          for (final option in open.options) {
            numericOptions += 1;
            expect(
              parseCoordinateEntry('$head ${option.value}', law).coordinate.value(open.level),
              option.value,
              reason: 'the rung offered ${option.value} on ${open.level}',
            );
            if (vocabulary == null || !_typable(option.label)) continue;
            // An ambiguous name is its own ruled refusal, not an offer/accept
            // gap, so it is excluded rather than asserted either way.
            final lower = option.label.toLowerCase();
            if (vocabulary.where((name) => name.toLowerCase() == lower).length != 1) continue;
            namedOptions += 1;
            expect(
              parseCoordinateEntry('$head ${option.label}', law).coordinate.value(open.level),
              option.value,
              reason: 'the rung labelled ${option.value} "${option.label}" on ${open.level}',
            );
          }
        }
      }
      // The property is worthless if the case it exists for is never generated.
      expect(inheritedRungs, greaterThan(0), reason: 'inherited vocabularies really occur');
      expect(namedOptions, greaterThan(iterations));
      expect(numericOptions, greaterThan(iterations));
    });

    test('RULED DIVERGENCE: a law that INHERITS the registered vocabulary accepts '
        'it in the field, where the JavaScript offered it and refused it', () {
      // Every era-chain fixture's ladder is this shape: a month level counting in
      // the registered calendar, with no names of its own.
      final law = _law(plainGregorianLadder, 'line:inherited');
      expect(law.inheritsRegistered, isTrue);
      expect(law.level('month')!.names, isNull, reason: 'it declares no vocabulary');
      expect(law.namesFor('month')!.first, 'January', reason: 'and inherits one');
      final rung = coordinatePickerLadder(law, _civil({'year': '2026'}))[1];
      expect(rung.options.first.label, 'January', reason: 'which the picker offers');
      // The fix: what the picker offers, typing accepts.
      expect(parseCoordinateEntry('2026 March 4', law).coordinate.value('month'), '3');
      expect(parseCoordinateEntry('2026 Aug 4', law).coordinate.value('month'), '8');
      // And every other rule still governs the inherited vocabulary unchanged.
      expect(() => parseCoordinateEntry('2026 Ju 4', law), throwsA(isA<LawRefusal>()));
      expect(() => parseCoordinateEntry('2026 Ma 4', law), throwsA(isA<LawRefusal>()));
      // A law that counts in NO registered calendar inherits nothing, so its
      // field refuses the Gregorian names exactly as before.
      final skyland = skylandLaw();
      expect(skyland.inheritsRegistered, isFalse);
      expect(() => parseCoordinateEntry('1 January', skyland), throwsA(isA<LawRefusal>()));
    });
  });

  // --- Separators ---------------------------------------------------------

  group('tokenizing is separator-agnostic', () {
    test('every spelling of one random coordinate parses identically', () {
      final random = Random(specSeed + 4);
      for (var round = 0; round < iterations; round += 1) {
        final law = _law(_registeredLadder(random), 'line:sep-$round');
        final value = _drill(law, random, law.levels.length);
        if (value.levels.length < 2) continue;
        final canonical = formatCoordinateEntry(value, law);
        // A proleptic root carries its sign OUTSIDE the token run, so it is not
        // one of the separators being varied.
        final signed = canonical.startsWith('-');
        final tokens = [
          for (final part in (signed ? canonical.substring(1) : canonical).split(
            RegExp(r'[\s\-:]+'),
          ))
            if (part.isNotEmpty) part,
        ];
        for (final separator in [' ', '-', '/', ',', '.', ':', '  ', ' - ']) {
          final spelling = '${signed ? '-' : ''}${tokens.join(separator)}';
          expect(
            parseCoordinateEntry(spelling, law).coordinate,
            value,
            reason: 'spelled "$spelling"',
          );
        }
      }
    });

    test('RULED ANCHOR: six spellings of one instant parse to one coordinate', () {
      final spellings = [
        '2026-08-20 17:00:30.250',
        '2026/08/20 17:00:30.250',
        '2026 08 20 17 00 30 250',
        '2026,08,20,17,00,30,250',
        '2026.08.20.17.00.30.250',
        '2026-08-20 17:00:30,250',
      ];
      final first = parseCoordinateEntry(spellings.first, gregorianLaw).coordinate;
      for (final spelling in spellings.skip(1)) {
        expect(parseCoordinateEntry(spelling, gregorianLaw).coordinate, first);
      }
    });
  });

  // --- The registered standard, pinned ------------------------------------

  group('RULED ANCHOR: the registered standard', () {
    test('each precision depth parses to exactly the levels typed and lands on '
        'the exact instant', () {
      final cases = <(String, Coordinate, String)>[
        ('2026', _civil({'year': '2026'}), 'year'),
        ('2026 8 20', _civil({'year': '2026', 'month': '8', 'day': '20'}), 'day'),
        (
          '2026 8 20 17:00',
          _civil({'year': '2026', 'month': '8', 'day': '20', 'hour': '17', 'minute': '0'}),
          'minute',
        ),
        (
          '2026 8 20 17:00:30.250',
          _civil({
            'year': '2026',
            'month': '8',
            'day': '20',
            'hour': '17',
            'minute': '0',
            'second': '30',
            'subsecond': '0.250',
          }),
          'subsecond',
        ),
      ];
      for (final (text, expected, depth) in cases) {
        final parsed = parseCoordinateEntry(text, gregorianLaw);
        expect(parsed.coordinate, expected, reason: text);
        expect(parsed.depth, depth, reason: text);
        expect(gregorianLaw.toDays(parsed.coordinate), gregorianLaw.toDays(expected), reason: text);
      }
      // Not merely agreement with itself: the minute entry is noon plus five
      // hours, so the day fraction is exactly 17/24.
      final minute = parseCoordinateEntry('2026 8 20 17:00', gregorianLaw).coordinate;
      final days = gregorianLaw.toDays(minute);
      expect((days - Rational(days.floor())).toJson(), '17/24');
    });

    test('canonical text, at day, minute, subsecond and proleptic-negative depth', () {
      final day = _civil({'year': '2026', 'month': '8', 'day': '20'});
      expect(formatCoordinateEntry(day, gregorianLaw), '2026-08-20');
      final minute = _civil({
        'year': '2026',
        'month': '8',
        'day': '20',
        'hour': '17',
        'minute': '0',
      });
      expect(formatCoordinateEntry(minute, gregorianLaw), '2026-08-20 17:00');
      final subsecond = Coordinate([
        ...minute.levels,
        (level: 'second', value: '30'),
        (level: 'subsecond', value: '0.25'),
      ]);
      expect(
        parseCoordinateEntry(
          formatCoordinateEntry(subsecond, gregorianLaw),
          gregorianLaw,
        ).coordinate,
        subsecond,
      );
      final bce = _civil({'year': '-5'});
      expect(formatCoordinateEntry(bce, gregorianLaw), '-5');
      expect(parseCoordinateEntry('-5', gregorianLaw).coordinate, bce);
      expect(formatCoordinateEntry(Coordinate.empty, gregorianLaw), '');
    });

    test('the refusal names the law\'s OWN level order', () {
      for (final text in ['', '   ']) {
        expect(
          () => parseCoordinateEntry(text, gregorianLaw),
          throwsA(
            isA<LawRefusal>().having(
              (error) => error.message,
              'message',
              contains('year, then month, day, hour, minute, second'),
            ),
          ),
        );
      }
      // The continuous tail is never enumerated as a position of its own.
      expect(coordinateEntryHelp(gregorianLaw), isNot(contains('subsecond')));
      expect(
        () => parseCoordinateEntry('2026 8 20 17 0 0 0 0 0', gregorianLaw),
        throwsA(isA<LawRefusal>()),
      );
    });

    test('a fully custom 8/8/8 law parses in its own names and radices, with no '
        'Gregorian leak', () {
      final skyland = skylandLaw();
      final parsed = parseCoordinateEntry('3 Bloom 5 2', skyland);
      expect(parsed.coordinate.levelNames(), ['epoch', 'season', 'pulse', 'beat']);
      expect(parsed.depth, 'beat');
      expect(parsed.coordinate.value('epoch'), '3');
      // "Bloom" is index 3, zero-based: this law's family declares no defaults.
      expect(parsed.coordinate.value('season'), '3');
      expect(parsed.coordinate.value('pulse'), '5');
      expect(parsed.coordinate.value('beat'), '2');
      // Radix 8, not Gregorian's 12.
      expect(() => parseCoordinateEntry('3 7', skyland), returnsNormally);
      expect(() => parseCoordinateEntry('3 8', skyland), throwsA(isA<LawRefusal>()));
      expect(skyland.namesFor('season')![3], 'Bloom');
      expect(skyland.namesFor('month'), isNull);
      expect(gregorianLaw.namesFor('season'), isNull);
      final text = formatCoordinateEntry(parsed.coordinate, skyland);
      expect(text, '3 3:5:2');
      expect(parseCoordinateEntry(text, skyland).coordinate, parsed.coordinate);
    });

    test('the placeholder is derived from the law\'s own declared levels', () {
      expect(
        coordinateEntryPlaceholder(gregorianLaw),
        'year-month-day hour:minute:second:subsecond',
      );
      expect(coordinateEntryPlaceholder(skylandLaw()), 'epoch season:pulse:beat');
    });
  });

  // --- The picker ---------------------------------------------------------

  group('the zoom picker', () {
    test('an unbounded rung NEVER materializes an option list, at any depth, '
        'and a bounded one offers exactly its own count', () {
      final random = Random(specSeed + 5);
      for (var round = 0; round < iterations; round += 1) {
        final law = random.nextBool()
            ? _law(_registeredLadder(random), 'line:pick-greg-$round')
            : _law(
                _inventedLadder(random, tail: random.nextBool(), names: random.nextBool()),
                'line:pick-$round',
              );
        for (var depth = 0; depth <= law.levels.length; depth += 1) {
          final value = _drill(law, random, depth);
          final rungs = coordinatePickerLadder(law, value);
          // One rung per level already fixed, plus the next one revealed --
          // never further, and never past the ladder's own end.
          final fixed = value.levels.length;
          expect(rungs.length, min(fixed + 1, law.levels.length));
          for (final (index, rung) in rungs.indexed) {
            expect(rung.level, law.levels[index].name);
            expect(rung.label, rung.level);
            expect(rung.chosen, index < fixed ? isNotNull : isNull);
            final count = _count(law, rung.level, value);
            // OVERSCALE: no count, no list. The root and the tail are the two
            // levels that can never be enumerated.
            expect(rung.bounded, count != null, reason: rung.level);
            if (count == null) {
              expect(rung.options, isEmpty, reason: '${rung.level} is unbounded');
            } else {
              expect(BigInt.from(rung.options.length), count, reason: rung.level);
              final base = _base(law, rung.level);
              expect(rung.options.first.value, '$base');
              expect(rung.options.last.value, '${base + count - BigInt.one}');
              final names = law.namesFor(rung.level);
              for (final (offset, option) in rung.options.indexed) {
                expect(
                  option.label,
                  names != null && offset < names.length ? names[offset] : option.value,
                );
              }
            }
          }
          expect(
            rungs.where((rung) => !rung.bounded).every((rung) => rung.options.isEmpty),
            isTrue,
          );
        }
      }
    });

    test('drilling reveals exactly one new rung per choice, and stopping is '
        'always legal', () {
      final random = Random(specSeed + 6);
      for (var round = 0; round < iterations; round += 1) {
        final law = _law(_registeredLadder(random), 'line:drill-$round');
        var value = Coordinate.empty;
        final seen = <String>[];
        while (seen.length < law.levels.length) {
          final rungs = coordinatePickerLadder(law, value);
          final open = rungs.last;
          expect(open.chosen, isNull, reason: 'the last rung is always the open one');
          expect(open.level, law.levels[seen.length].name);
          final next = _drill(law, random, seen.length + 1);
          value = next;
          seen.add(open.level);
          final after = coordinatePickerLadder(law, value);
          expect([
            for (final rung in after)
              if (rung.chosen != null) rung.level,
          ], seen);
          expect(after.length, min(seen.length + 1, law.levels.length));
          // Stopping here is a complete answer: the coordinate is at this depth
          // and the field reads its own canonical text straight back.
          expect(authoredDepth(value, law), open.level);
          final text = formatCoordinateEntry(value, law);
          expect(parseCoordinateEntry(text, law).coordinate, value);
        }
      }
    });

    test('RULED ANCHOR: the day rung differs between a leap and a common '
        'February, and re-picking a coarser rung re-derives the finer ones', () {
      final empty = coordinatePickerLadder(gregorianLaw, Coordinate.empty);
      expect(empty.length, 1);
      expect(empty.single.level, 'year');
      expect(empty.single.bounded, isFalse);
      expect(empty.single.options, isEmpty);
      expect(empty.single.chosen, isNull);

      List<PickerRung> ladderFor(String year) =>
          coordinatePickerLadder(gregorianLaw, _civil({'year': year, 'month': '2'}));
      expect([for (final rung in ladderFor('2026')) rung.level], ['year', 'month', 'day']);
      expect(ladderFor('2026').last.options.length, 28);
      expect(ladderFor('2024').last.options.length, 29);
      expect(ladderFor('2026').last.bounded, isTrue);
      expect(ladderFor('2026').last.chosen, isNull);
      expect(ladderFor('2026').last.options.first.value, '1');

      final dayPrecision = _civil({'year': '2026', 'month': '8', 'day': '20'});
      final ladder = coordinatePickerLadder(gregorianLaw, dayPrecision);
      expect([for (final rung in ladder) rung.level], ['year', 'month', 'day', 'hour']);
      expect(ladder[2].chosen, '20');
      expect(ladder[3].chosen, isNull);
      expect(ladder[3].options.length, 24);
      expect(ladder.first.options, isEmpty);
      // The month rung's options are named from the law's own authored names.
      final months = coordinatePickerLadder(gregorianLaw, _civil({'year': '2026'}))[1];
      expect(months.options.length, 12);
      expect(months.options.first.label, 'January');
      expect(months.options[7].label, 'August');
      expect(months.options[7].value, '8');
      // The continuous tail is unbounded too: it subdivides its parent without a
      // fixed count, so there is nothing to enumerate.
      final tail = coordinatePickerLadder(
        gregorianLaw,
        _civil({
          'year': '2026',
          'month': '8',
          'day': '20',
          'hour': '17',
          'minute': '30',
          'second': '15',
        }),
      ).last;
      expect(tail.level, 'subsecond');
      expect(tail.bounded, isFalse);
      expect(tail.options, isEmpty);
    });

    test('RULED ANCHOR: a custom law\'s picker offers ITS OWN rungs, counts and '
        'names', () {
      final skyland = skylandLaw();
      final ladder = coordinatePickerLadder(
        skyland,
        const Coordinate([(level: 'epoch', value: '3')]),
      );
      expect([for (final rung in ladder) rung.level], ['epoch', 'season']);
      expect(ladder.first.chosen, '3');
      expect(ladder.first.bounded, isFalse, reason: 'the root has no parent to be counted within');
      expect(ladder.first.options, isEmpty);
      expect(ladder.last.bounded, isTrue);
      expect(ladder.last.options.length, 8);
      expect([for (final option in ladder.last.options) option.label], skylandSeasons);
      expect(ladder.last.options.any((option) => option.label == 'January'), isFalse);
      final deeper = coordinatePickerLadder(
        skyland,
        const Coordinate([
          (level: 'epoch', value: '3'),
          (level: 'season', value: '2'),
          (level: 'pulse', value: '5'),
        ]),
      );
      expect([for (final rung in deeper) rung.level], ['epoch', 'season', 'pulse', 'beat']);
      expect(deeper.last.options.length, 8);
      expect(deeper.last.bounded, isTrue);
    });
  });

  // --- Eras: one position, two tokens -------------------------------------

  group('an era-qualified year spends two tokens on one level', () {
    test('RULED ANCHOR: a chain era parses, formats back to the text typed, and '
        'accepts a bare year for the same position', () {
      final thirdEra = chainLaw(tamrielChain(), tamrielLadder, 'era:3e');
      final parsed = parseCoordinateEntry('3E 433-308 20', thirdEra);
      // The coordinate carries a PLAIN year: there is no era level, the frame
      // itself is the era.
      expect(parsed.coordinate.levelNames(), ['year', 'day', 'hour']);
      expect(parsed.coordinate.value('year'), '433');
      expect(parsed.coordinate.value('day'), '308');
      expect(parsed.coordinate.value('hour'), '20');
      expect(parsed.depth, 'hour');
      expect(thirdEra.formatYear(parsed.coordinate), '3E 433');
      expect(formatCoordinateEntry(parsed.coordinate, thirdEra), '3E 433-308 20');
      expect(
        parseCoordinateEntry('3E 433-308 20', thirdEra).coordinate,
        parseCoordinateEntry('433-308 20', thirdEra).coordinate,
      );
      // Depth stops at the year itself, exactly like any other level.
      final yearOnly = parseCoordinateEntry('3E 433', thirdEra);
      expect(yearOnly.depth, 'year');
      expect(formatCoordinateEntry(yearOnly.coordinate, thirdEra), '3E 433');
      expect(coordinateEntryPlaceholder(thirdEra), '[3E] year-day hour');
    });

    test('RULED ANCHOR: a suffix affix parses as readily as a prefix one, on '
        'either side of the number', () {
      final bce = chainLaw(bceCeChain, plainGregorianLadder, 'era:bce');
      final ce = chainLaw(bceCeChain, plainGregorianLadder, 'era:ce');
      final parsedBce = parseCoordinateEntry('44 BCE 3 15', bce);
      expect(parsedBce.coordinate.levelNames(), ['year', 'month', 'day']);
      expect(parsedBce.coordinate.value('year'), '44');
      expect(parsedBce.depth, 'day');
      expect(bce.formatYear(parsedBce.coordinate), '44 BCE');
      expect(formatCoordinateEntry(parsedBce.coordinate, bce), startsWith('44 BCE'));
      expect(parseCoordinateEntry('BCE 44 3 15', bce).coordinate, parsedBce.coordinate);
      // 44 BCE and 44 CE are not the same instant.
      final parsedCe = parseCoordinateEntry('44 CE 3 15', ce).coordinate;
      expect(bce.toDays(parsedBce.coordinate), isNot(ce.toDays(parsedCe)));
      expect(coordinateEntryPlaceholder(bce), '[BCE] year-month-day hour:minute:second');
    });

    test('RULED ANCHOR: a qualifier naming another era is refused, never '
        'silently retargeted, and an unknown era is never read as a number', () {
      final thirdEra = chainLaw(tamrielChain(), tamrielLadder, 'era:3e');
      // "4E 5" is a real position -- in a DIFFERENT era. This field types a
      // position on its own frame's law; it is not a frame picker.
      expect(() => parseCoordinateEntry('4E 5 1', thirdEra), throwsA(isA<LawRefusal>()));
      // And a year past this era's own 433-year extent is refused too.
      expect(() => parseCoordinateEntry('3E 434 1', thirdEra), throwsA(isA<LawRefusal>()));
      expect(
        () => parseCoordinateEntry('9Z 12', thirdEra),
        throwsA(isA<LawRefusal>().having((error) => error.message, 'message', contains('year'))),
      );
      // An era-qualified year already states its own direction, so a sign on it
      // is refused rather than compounded.
      expect(() => parseCoordinateEntry('-3E 433', thirdEra), throwsA(isA<LawRefusal>()));
    });

    test('RULED ANCHOR: February 29 resolves against the PROPER year, in the '
        'field and in the picker alike', () {
      final bce = chainLaw(bceCeChain, plainGregorianLadder, 'era:bce');
      // 44 BCE is proper year -43, not divisible by four: not a leap year.
      expect(() => parseCoordinateEntry('44 BCE 2 29', bce), throwsA(isA<LawRefusal>()));
      // 45 BCE is proper year -44 and IS a leap year, though neither two-digit
      // local year looks like one.
      expect(parseCoordinateEntry('45 BCE 2 29', bce).coordinate.value('day'), '29');
      List<PickerRung> ladderFor(String year) =>
          coordinatePickerLadder(bce, _civil({'year': year, 'month': '2'}));
      expect(ladderFor('44').last.level, 'day');
      expect(ladderFor('44').last.options.length, 28);
      expect(ladderFor('45').last.options.length, 29);
    });

    test('RULED ANCHOR: the picker offers no era rung -- eras are frames', () {
      final thirdEra = chainLaw(tamrielChain(), tamrielLadder, 'era:3e');
      final ladder = coordinatePickerLadder(thirdEra, Coordinate.empty);
      expect([for (final rung in ladder) rung.level], ['year']);
      expect(ladder.single.bounded, isFalse);
      expect(ladder.single.options, isEmpty);
    });

    test('an era law round-trips at every depth its ladder admits', () {
      final random = Random(specSeed + 7);
      final laws = [
        chainLaw(tamrielChain(), tamrielLadder, 'era:3e'),
        chainLaw(tamrielChain(), tamrielLadder, 'era:2e'),
        chainLaw(bceCeChain, plainGregorianLadder, 'era:bce'),
        chainLaw(bceCeChain, plainGregorianLadder, 'era:ce'),
      ];
      for (var round = 0; round < iterations; round += 1) {
        final law = _pick(random, laws);
        // A year this era HAS: every chain above declares at least 433 years,
        // and an open era admits any of them.
        String year() => '${1 + random.nextInt(400)}';
        for (var depth = 1; depth <= law.levels.length; depth += 1) {
          final value = _drill(law, random, depth, root: year);
          if (value.levels.isEmpty) continue;
          final text = formatCoordinateEntry(value, law);
          expect(parseCoordinateEntry(text, law).coordinate, value, reason: text);
          expect(formatCoordinateEntry(parseCoordinateEntry(text, law).coordinate, law), text);
          expect(parseCoordinateEntry(text, law).depth, authoredDepth(value, law));
          // The era-qualified year is ONE position: the text carries the era's
          // own key, and the stored coordinate carries a plain local year.
          expect(text, contains(law.eraKey()!));
          expect(value.levelNames(), isNot(contains('era')));
        }
      }
    });
  });

  // --- Depth is never fuzziness -------------------------------------------

  test('nothing here produces, implies or returns fuzziness or spread data', () {
    final random = Random(specSeed + 8);
    for (var round = 0; round < iterations; round += 1) {
      final law = _law(_registeredLadder(random), 'line:pure-$round');
      final value = _drill(law, random, law.levels.length);
      // A coordinate is level/value pairs and nothing else, at every depth.
      for (final entry in value.levels) {
        expect(entry.level, isA<String>());
        expect(entry.value, isA<String>());
      }
      expect(value.toJson().keys.toList(), [
        'levels',
      ], reason: 'no spread, no uncertainty, no confidence');
      for (final rung in coordinatePickerLadder(law, value)) {
        expect(rung.options.every((option) => option.value.isNotEmpty), isTrue);
      }
    }
  });
}
