// The one variable-precision coordinate field: the spec.
//
// Properties over seeded random coordinates DRILLED through the picker ladder,
// under every law shape a card has to speak -- the registered Gregorian one, a
// 23-hour day, a wholly custom 8/8/8 ladder with authored value names, and both
// directions of an era chain. Nothing here pins a date.

import 'dart:math';

import 'package:chronolog/cards/coordinate_field.dart';
import 'package:chronolog/core/coordinate_entry.dart';
import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/eras.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import 'object_harness.dart';

/// A random coordinate of this law, built ONLY by picking rungs -- which is the
/// same door the field's own picker writes through, so a coordinate the spec
/// invents cannot be one the picker could never produce.
Coordinate drill(CoordinateLaw law, Random random, int depth, {String? root}) {
  var value = Coordinate.empty;
  for (var rung = 0; rung < depth; rung += 1) {
    final open = coordinatePickerLadder(law, value).last;
    final picked = open.bounded && open.options.isNotEmpty
        ? open.options[random.nextInt(open.options.length)].value
        : root ?? '${random.nextInt(2000)}';
    if (!open.bounded && rung > 0) return value;
    value = coordinateAt(value, law, open.level, picked);
  }
  return value;
}

void main() {
  late CardBench bench;

  setUp(() async => bench = await openCards(Corpus(specSeed).document()));

  testWidgets('a coordinate typed at its own depth comes back at that depth', (tester) async {
    final random = Random(specSeed);
    var rounds = 0;
    for (final law in lawsUnderTest()) {
      for (var depth = 1; depth <= law.levels.length; depth += 1) {
        final authored = drill(law, random, depth, root: law.hasEras() ? '400' : null);
        if (authored.levels.isEmpty) continue;
        final text = coordinateText(authored, law);
        if (text.isEmpty) continue;
        Coordinate? seen;
        String? seenDepth;
        await pumpHosted(
          tester,
          bench,
          CoordinateField(
            key: ValueKey('$text of ${law.frameId}'),
            law: law,
            value: null,
            onChanged: (value, at) {
              seen = value;
              seenDepth = at;
            },
          ),
        );
        await tester.enterText(find.byType(TextField), text);
        await tester.pump();
        expect(seen, authored, reason: '$text under ${law.frameId}');
        expect(seenDepth, authoredDepth(authored, law), reason: 'depth of $text');
        // Depth is PRECISION, never uncertainty: the field states no spread.
        expect(seen!.levels.length, authored.levels.length);
        rounds += 1;
      }
    }
    expect(rounds, greaterThan(0));
  });

  testWidgets('a refusal is the law\'s own sentence, and nothing is guessed', (tester) async {
    const refused = 'not a coordinate at all';
    for (final (index, law) in lawsUnderTest().indexed) {
      var calls = 0;
      await pumpHosted(
        tester,
        bench,
        CoordinateField(
          key: ValueKey('refusal $index'),
          law: law,
          value: null,
          onChanged: (_, _) => calls += 1,
        ),
      );
      await tester.enterText(find.byType(TextField), refused);
      await tester.pump();
      expect(calls, 0, reason: 'a refused entry writes nothing');
      // The sentence shown is the one the LAW itself refused with, in its own
      // level names -- not a message this spec wrote down.
      String sentence;
      try {
        parseCoordinateEntry(refused, law);
        sentence = '';
      } on Object catch (refusal) {
        sentence = refusalText(refusal);
      }
      expect(sentence, isNotEmpty);
      expect(find.text(sentence), findsOneWidget);
      expect(sentence, contains(law.levels.first.name));
    }
  });

  testWidgets('the picker never materializes an unbounded rung', (tester) async {
    for (final law in lawsUnderTest()) {
      for (final rung in coordinatePickerLadder(law, Coordinate.empty)) {
        if (!rung.bounded) expect(rung.options, isEmpty, reason: '${rung.level} of ${law.frameId}');
      }
    }
  });

  testWidgets('emptying the field states "unstated" rather than a zero', (tester) async {
    Object? seen = 'untouched';
    await pumpHosted(
      tester,
      bench,
      CoordinateField(law: gregorianLaw, value: null, onChanged: (value, _) => seen = value),
    );
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(seen, isNull);
  });
}
