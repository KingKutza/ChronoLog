// A BARE RUN FILLS FROM NOW ABOVE AND IS PRECISION BELOW (ISSUES 9.2, Don:
// "Entering a time on a sentence").
//
// Don's words: "I should be able to put in a time and have it assume today, or
// a day and have it assume all day, or a year, etc. Precision is what you enter
// and it assumes crude measurements match now."
//
// RULED (RULINGS.md #4, the ruled half): what is absent BELOW the typed run is
// precision; what is absent ABOVE it comes from now. So a bare year is a year,
// a day is all day, a time is today. Nothing about the fill is fuzzy: now is a
// definite coordinate, and the levels it supplies are as authored as the typed
// ones. Today `parseCoordinateEntry` reads coarse-to-fine ONLY -- the typed text
// is a prefix of the ladder -- so the precision half already holds and the
// fill-from-now half is a parse failure.
//
// OPEN (RULINGS.md #4, unanswered): which level a bare run binds to when more
// than one reading is legal. "26" must mean the day and "2026" the year, and a
// digit-count test ("four digits means year") is a Gregorian hardcode that
// cannot survive an 8x8x8 calendar. This file does NOT answer it. It asserts
// only what every option on the table agrees on:
//
//   A run of values that is legal at EXACTLY ONE alignment against the ladder
//   -- every value within its level's own range at that alignment, and at
//   least one value out of range at every other -- binds there; the levels
//   above it are filled from now; the levels below it are absent; the depth is
//   the deepest typed level. The alignment is decided by the LAW's own ranges,
//   so the same digits bind to different levels under different laws, and no
//   count of digits is consulted.
//
// The signature it needs, which does not exist yet:
//
//   CoordinateEntry parseCoordinateEntry(String? text, CoordinateLaw law, {Coordinate? now});
//
// WHAT THIS FILE CANNOT PIN, and why it matters to the ruling: the shipped
// Gregorian ladder ends in a continuous tail (`subsecond`) that accepts any
// digit run as a fraction, and it carries minute AND second at radix 60 -- so
// "17:30" is legal as hour:minute AND as minute:second AND as second.subsecond,
// and Don's own "26 3:15 is assumed today" is also legal as year 26, March 15.
// No Gregorian time-of-day is unique by ranges alone, so "a time is today" on
// the shipped ladder waits on the binding ruling. The property is therefore
// quantified over invented constant-radix ladders with no tail and over the
// 8x8x8 law, and the Gregorian anchors below are the ones that ARE unique.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/core/coordinate_entry.dart';
import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/eras.dart';
import 'package:chronolog/core/records.dart';
import 'package:test/test.dart';

final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

String seeded(String message) => '$message  (set CHRONOLOG_SEED=$runSeed to reproduce)';

/// How many random ladders the property is asked over.
const int ladders = 60;

CoordinateLaw lawOf(Json declaration, String frameId) =>
    CoordinateLaw(Declaration.parse(declaration, 'Frame $frameId'), frameId: frameId);

/// An invented ladder: a root nobody can count and one to four constant-radix
/// rungs. NO continuous tail (it would make every run legal as a fraction) and
/// no authored names (a name is not a bare number).
Json inventedLadder(Random random) {
  final rungs = 1 + random.nextInt(4);
  return {
    'kind': 'nested',
    'levels': [
      {'name': 'root'},
      for (var index = 1; index <= rungs; index += 1)
        {
          'name': 'rung$index',
          'within': index == 1 ? 'root' : 'rung${index - 1}',
          'radix': '${2 + random.nextInt(23)}',
        },
    ],
  };
}

/// The 8x8x8 calendar the ruling names: eight seasons of eight pulses of eight
/// beats, counting in no registered calendar at all.
const Json eightLaw = {
  'kind': 'nested',
  'levels': [
    {'name': 'epoch'},
    {'name': 'season', 'within': 'epoch', 'radix': '8'},
    {'name': 'pulse', 'within': 'season', 'radix': '8'},
    {'name': 'beat', 'within': 'pulse', 'radix': '8'},
  ],
};

int radixOf(Level level) => level.radix!.n.toInt();

/// Is [value] within [law]'s range for the level at [index]? The root counts
/// anything; a constant-radix rung counts from zero to its radix.
bool legalAt(CoordinateLaw law, int index, int value) {
  final level = law.levels[index];
  if (level.radix == null) return true;
  return value >= 0 && value < radixOf(level);
}

/// A run legal at exactly one alignment, or null when this ladder would not
/// yield one in a bounded number of draws. The run starts BELOW the root, so
/// there is always at least one level to fill from now, and is at least two
/// values long, because a single value is always legal at the root as well.
({int start, List<int> values})? uniqueRun(Random random, CoordinateLaw law) {
  final count = law.levels.length;
  if (count < 3) return null;
  for (var attempt = 0; attempt < 200; attempt += 1) {
    final start = 1 + random.nextInt(count - 2);
    final length = 2 + random.nextInt(count - start - 1);
    final values = [
      for (var offset = 0; offset < length; offset += 1)
        random.nextInt(radixOf(law.levels[start + offset])),
    ];
    var alignments = 0;
    for (var at = 0; at + length <= count; at += 1) {
      var legal = true;
      for (var offset = 0; offset < length && legal; offset += 1) {
        legal = legalAt(law, at + offset, values[offset]);
      }
      if (legal) alignments += 1;
    }
    if (alignments == 1) return (start: start, values: values);
  }
  return null;
}

/// A full coordinate under [law]: every level fixed at a legal value.
Coordinate anyNow(Random random, CoordinateLaw law) => Coordinate([
  for (final level in law.levels)
    (
      level: level.name,
      value: '${level.radix == null ? 1000 + random.nextInt(9000) : random.nextInt(radixOf(level))}',
    ),
]);

const List<String> separators = [' ', '-', ':', '/', '.'];

void main() {
  // ignore: avoid_print
  print('BARE NUMBER RUN SEED: $runSeed  (set CHRONOLOG_SEED=$runSeed to reproduce)');

  test('a run legal at exactly one alignment binds there, fills from now above, and stops below', () {
    final random = Random(runSeed);
    var checked = 0;
    for (var index = 0; index < ladders; index += 1) {
      final law = index % 6 == 0
          ? lawOf(eightLaw, 'frame:eight-$index')
          : lawOf(inventedLadder(random), 'frame:invented-$index');
      final run = uniqueRun(random, law);
      if (run == null) continue;
      final now = anyNow(random, law);
      final text = run.values.join(separators[random.nextInt(separators.length)]);
      final ladder = law.levelNames().join('/');
      final CoordinateEntry parsed;
      try {
        parsed = parseCoordinateEntry(text, law, now: now);
      } on LawRefusal catch (refusal) {
        fail(
          seeded(
            'ISSUES 9.2: "$text" under $ladder is legal at exactly one alignment (from '
            '${law.levels[run.start].name}) and was refused: $refusal. What is absent above '
            'the run comes from now.',
          ),
        );
      }
      for (var at = 0; at < law.levels.length; at += 1) {
        final name = law.levels[at].name;
        if (at < run.start) {
          expect(
            parsed.coordinate.value(name, ''),
            now.value(name, ''),
            reason: seeded('"$text" under $ladder: $name is above the run and comes from now'),
          );
        } else if (at < run.start + run.values.length) {
          expect(
            parsed.coordinate.value(name, ''),
            '${run.values[at - run.start]}',
            reason: seeded('"$text" under $ladder: $name is the typed value at its one legal alignment'),
          );
        } else {
          expect(
            parsed.coordinate.has(name),
            isFalse,
            reason: seeded('"$text" under $ladder: $name is below the run, and absence below is precision'),
          );
        }
      }
      expect(
        parsed.depth,
        law.levels[run.start + run.values.length - 1].name,
        reason: seeded('"$text" under $ladder: the depth is the deepest typed level'),
      );
      checked += 1;
    }
    expect(checked, greaterThan(ladders ~/ 4), reason: seeded('enough ladders yielded a unique run'));
  });

  test('a bare year is a year: the one alignment that admits 2026 is the root', () {
    // A now the shipped law would accept: `anyNow` suits constant radices only,
    // and Gregorian's month and day count through transitions.
    final random = Random(runSeed + 1);
    final now = Coordinate.of([
      ('year', 1990 + random.nextInt(60)),
      ('month', 1 + random.nextInt(12)),
      ('day', 1 + random.nextInt(28)),
      ('hour', random.nextInt(24)),
      ('minute', random.nextInt(60)),
      ('second', random.nextInt(60)),
    ]);
    final parsed = parseCoordinateEntry('2026', gregorianLaw, now: now);
    expect(parsed.coordinate.value('year', ''), '2026');
    expect(parsed.depth, 'year');
    for (final level in gregorianLaw.levels.skip(1)) {
      expect(
        parsed.coordinate.has(level.name),
        isFalse,
        reason: seeded('a bare year stops at the year: ${level.name} is precision, not a fill'),
      );
    }
  });

  test('the same digits bind by the LAW\'s ranges, never by their count', () {
    // Under an 8x8x8 calendar nothing but the root admits 12, so "12" is the
    // epoch, whatever two digits would mean elsewhere. (Under Gregorian the same
    // text is legal at five levels, which is the open ruling, and is not
    // asserted.)
    final random = Random(runSeed + 2);
    final law = lawOf(eightLaw, 'frame:eight');
    final parsed = parseCoordinateEntry('12', law, now: anyNow(random, law));
    expect(parsed.coordinate.value('epoch', ''), '12', reason: seeded('12 is legal only at the epoch'));
    expect(parsed.depth, 'epoch');
    expect(parsed.coordinate.has('season'), isFalse);
  });

  test('a run legal at NO alignment is refused, never guessed', () {
    // "9 9" under eight-by-eight: 9 is out of every bounded range, so no
    // alignment places the second value. A refusal in the law's own words.
    final random = Random(runSeed + 3);
    final law = lawOf(eightLaw, 'frame:eight');
    expect(
      () => parseCoordinateEntry('9 9', law, now: anyNow(random, law)),
      throwsA(isA<LawRefusal>()),
      reason: seeded('no alignment admits "9 9" under 8x8x8; the fill must not invent one'),
    );
  });
}
