// A BASIS IS AN AUTHORED ONE MATH FUNCTION.
//
// Ruled 2026-08-31 (Don): "it is assumed to have its own basis frame and that
// could be any valid One Math Expression. a linear equation a non-linear
// equation a piecewise equeation, an all point, a loop, A list/stack, or
// anything else." The acceptance is his own worked era:
//
//   "era 1 would be a peicewise function, where we say y is 0 when x <=0, Y is x
//    when x is >=0 && x<=1051, then we would define 1 is year, year contains 14
//    months, that breakdown in this order as this list of decimals."
//
// That sentence is two things, and this spec keeps them apart because they
// landed apart: the FUNCTION is built and green below, and the UNIT BREAKDOWN's
// second half -- children of unequal, authored lengths -- has no spelling yet
// and is a RED at the bottom naming its work item.
//
// FRESH SEED EVERY RUN. The story is written as an example, which the generative
// ruling allows for a story; everything else is a property over random bases.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/core/basis_function.dart';
import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/eras.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/math.dart';
import 'package:test/test.dart';

final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

/// Don's era, spelled as a document: fourteen months to the year, and a
/// piecewise basis that is dead before its beginning and flows for 1051 units.
Map<String, Object?> eraOne({Object? basis}) => {
  'frames': <String, Object?>{
    'era:one': <String, Object?>{
      'id': 'era:one',
      'title': 'The First Era',
      'traits': ['line', 'temporal'],
      'basis':
          basis ??
          {
            'variable': 'x',
            'pieces': [
              {'when': 'x <= 0', 'is': '0'},
              {'when': 'x >= 0 and x <= 1051', 'is': 'x'},
            ],
          },
      'coordinate': {
        'kind': 'nested',
        'baseLevel': 'year',
        'levels': [
          {'name': 'year'},
          {'name': 'month', 'within': 'year', 'radix': '14'},
        ],
      },
    },
  },
};

Coordinate year(int value, [int? month]) => Coordinate.of([
  ('year', '$value'),
  if (month != null) ('month', '$month'),
]);

CoordinateLaw lawOf(Map<String, Object?> document) => CoordinateLaws().of(document, 'era:one');

void main() {
  // ignore: avoid_print
  print('basis_function seed: $runSeed  (pin CHRONOLOG_SEED to reproduce)');

  group("Don's era one, as written", () {
    test('the flowing stretch resolves coordinate to days and back', () {
      final law = lawOf(eraOne());
      expect(law.basis, isNotNull);
      // The ladder is untouched: fourteen months to the year, and the basis
      // warps the COUNT rather than the units it is spelled in.
      expect(law.baseLevel, 'year');
      expect(law.baseAtoms, Rational.fromInt(14));
      for (final at in [2, 17, 500, 1051]) {
        final days = law.toDays(year(at));
        expect(law.fromDays(days), year(at), reason: 'year $at should round-trip');
      }
      // Year ONE is where the two pieces meet -- the dead stretch's whole
      // preimage and the flowing stretch's first step sit at the one place --
      // so it does NOT come back, and refusing there is the model being exact
      // rather than the model being broken.
      expect(() => law.fromDays(law.toDays(year(1))), throwsA(isA<LawRefusal>()));
      // y = x over the flowing stretch, so a year is a year's worth of units.
      expect(
        law.toDays(year(3)) - law.toDays(year(2)),
        law.toDays(year(2)) - law.toDays(year(1)),
      );
    });

    test('the dead stretch advances nothing, and asking it back refuses in '
        'words rather than picking one of its instants', () {
      final law = lawOf(eraOne());
      final start = law.toDays(year(1));
      // "y is 0 when x <= 0": every year at or before the first sits at the one
      // same place, because nothing there advances.
      for (final at in [0, -1, -40, -1051]) {
        expect(law.toDays(year(at)), start, reason: 'year $at is still day zero');
      }
      expect(
        () => law.fromDays(start),
        throwsA(
          isA<LawRefusal>().having(
            (error) => error.message,
            'message',
            allOf(contains('a whole stretch'), contains('no single position')),
          ),
        ),
      );
    });

    test('past the last piece nothing has a position, and it says so', () {
      final law = lawOf(eraOne());
      expect(
        () => law.toDays(year(1053)),
        throwsA(
          isA<LawRefusal>().having(
            (error) => error.message,
            'message',
            allOf(contains('no piece of this basis covers'), contains('x = 1052')),
          ),
        ),
      );
    });

    test('a nested radix ladder is one spelling of the general basis, not the '
        'only one: the same frame without a function is unchanged', () {
      final plain = eraOne();
      final frames = plain['frames']! as Map<String, Object?>;
      frames['era:one'] = <String, Object?>{...frames['era:one']! as Map<String, Object?>}
        ..remove('basis');
      final law = lawOf(plain);
      expect(law.basis, isNull);
      final flowed = lawOf(eraOne());
      // Inside the flowing stretch the two laws agree exactly, which is what
      // "y = x is plain flow" means in executable terms.
      for (final at in [1, 2, 900]) {
        expect(
          flowed.toDays(year(at)) - flowed.toDays(year(1)),
          law.toDays(year(at)) - law.toDays(year(1)),
        );
      }
    });
  });

  group('inversion is exact or it refuses', () {
    test('a straight-line basis inverts exactly, whatever line it is', () {
      final random = Random(runSeed);
      for (var i = 0; i < 60; i += 1) {
        final slope = 1 + random.nextInt(9);
        final intercept = random.nextInt(200) - 100;
        final law = lawOf(
          eraOne(basis: {'expression': '$intercept + $slope * x'}),
        );
        for (var trial = 0; trial < 6; trial += 1) {
          final at = 1 + random.nextInt(3000);
          expect(law.fromDays(law.toDays(year(at))), year(at));
        }
      }
    });

    test('a flat piece answers many-valued and a curve answers by name; neither '
        'is approximated', () {
      final flat = BasisFunction.parse(const {'expression': '7'}, 'test')!;
      expect(flat.inverse(Rational.fromInt(7)).manyValued, isTrue);
      expect(flat.inverse(Rational.fromInt(7)).at, isEmpty);
      expect(flat.inverse(Rational.fromInt(8)).manyValued, isFalse);

      for (final curve in ['x * x', 'x ^ 2', 'min(x, 4)', 'x > 0 ? x : 0 - x']) {
        final basis = BasisFunction.parse({'expression': curve}, 'test')!;
        expect(
          basis.inverse(Rational.one).refusal,
          allOf(contains('not a straight line'), contains(curve)),
          reason: curve,
        );
      }
    });

    test('the straight-line reading is a proof about the tree, not a sample of '
        'it', () {
      final random = Random(runSeed + 1);
      for (var i = 0; i < 80; i += 1) {
        final a = random.nextInt(40) - 20, b = 1 + random.nextInt(9);
        final spelling = [
          '$a + $b * x',
          'x * $b + $a',
          '($a - x) * $b',
          '(x + $a) / $b',
          '0 - ($a - $b * x)',
        ][random.nextInt(5)];
        final line = straightLine(parse(spelling), 'x')!;
        // The claimed line is checked against the evaluator at two places,
        // which is what makes the structural reading and the one math agree.
        for (final at in [Rational.fromInt(0), Rational.fromInt(37)]) {
          final direct = evaluateSource(spelling, Env(values: {'x': at}));
          expect(line.intercept + line.slope * at, direct, reason: spelling);
        }
      }
      expect(straightLine(parse('x * x'), 'x'), isNull);
      expect(straightLine(parse('x / x'), 'x'), isNull);
      expect(straightLine(parse('abs(x)'), 'x'), isNull);
      expect(straightLine(parse('y + 1'), 'x'), isNull);
    });

    test('a flow that lands between whole units names no coordinate, and says '
        'so rather than rounding to one it could have meant', () {
      // SCOPED HONESTLY (8.31): the basis warps the WHOLE-UNIT count and the
      // levels below it ride untouched, so a flow whose values are not whole
      // numbers has no whole count to hand back. Refusing by name is the answer;
      // rounding would put an instant at a year nobody wrote.
      final law = lawOf(eraOne(basis: const {'expression': 'x / 3'}));
      expect(
        () => law.fromDays(law.toDays(year(3))),
        throwsA(
          isA<LawRefusal>().having(
            (error) => error.message,
            'message',
            anyOf(
              contains('between two of its own units'),
              contains('not a whole one'),
              contains('nothing in this basis reaches'),
            ),
          ),
        ),
      );
      // Where the flow does land whole, it round-trips exactly.
      expect(law.fromDays(law.toDays(year(4))), year(4));
    });

    test('several places answering one value is refused, never picked', () {
      // Two flowing pieces that both reach the same value: legal data, and no
      // single coordinate there.
      final basis = BasisFunction.parse(const {
        'pieces': [
          {'when': 'x < 0', 'is': '0 - x'},
          {'when': 'x >= 0', 'is': 'x'},
        ],
      }, 'test')!;
      final answer = basis.inverse(Rational.fromInt(5));
      expect(answer.at, [Rational.fromInt(-5), Rational.fromInt(5)]);
      expect(
        () => basis.invert(Rational.fromInt(5)),
        throwsA(
          isA<LawRefusal>().having(
            (error) => error.message,
            'message',
            contains('reaches 5 at 2 places'),
          ),
        ),
      );
    });
  });

  group('a shape this build cannot evaluate is still data', () {
    // Ruled legal the same night: "an all point, a loop, A list/stack, or
    // anything else." Each loads, keeps its authored word, and refuses
    // evaluation in that word -- which is the only honest thing a build can do
    // with a meaning nobody has implemented.
    for (final held in [
      {'all': true},
      {
        'loop': {'every': '12'},
      },
      {
        'list': ['a', 'b', 'c'],
      },
      {'stack': 3},
    ]) {
      test('a basis authored as ${held.keys.single} loads and refuses by name', () {
        final basis = BasisFunction.parse(held, 'The First Era')!;
        expect(basis.held, held.keys.single);
        expect(
          () => basis.forward(Rational.one),
          throwsA(
            isA<LawRefusal>().having(
              (error) => error.message,
              'message',
              allOf(contains(held.keys.single), contains('cannot evaluate')),
            ),
          ),
        );
        expect(basis.inverse(Rational.one).refusal, contains(held.keys.single));
        // And the law carrying it still RESOLVES -- a basis nobody can evaluate
        // is not a broken frame, it is a frame whose positions are unstated.
        final law = lawOf(eraOne(basis: held));
        expect(law.basis?.held, held.keys.single);
        expect(() => law.toDays(year(1)), throwsA(isA<LawRefusal>()));
      });
    }

    test('a basis that says nothing at all is no basis, and the frame is '
        'unchanged', () {
      expect(BasisFunction.parse(const <String, Object?>{}, 'test'), isNull);
      expect(BasisFunction.parse('frame:wall-time', 'test'), isNull);
      expect(BasisFunction.parse(null, 'test'), isNull);
    });
  });

  group('the unit breakdown', () {
    test('fourteen months to the year is the ladder the frame already has', () {
      final law = lawOf(eraOne());
      expect(law.level('month')?.radix, Rational.fromInt(14));
      expect(law.unitsPer('month', 'year'), Rational.fromInt(14));
    });

    // RED, deliberately. WORK ITEM: authored unequal child lengths -- "that
    // breakdown in this order as this list of decimals". A level today declares
    // ONE radix (every child the same length) or a registered transition (the
    // Gregorian month table). Don's era one wants neither: fourteen months whose
    // lengths are an authored list of decimals summing to the year. Nothing in
    // the declaration layer can spell that, so a document that writes it is read
    // as though every month were equal -- which is silently wrong, and is the
    // class this red exists to keep lit.
    test('RED -- a level whose children have authored, unequal lengths has no '
        'spelling yet', () {
      final document = eraOne();
      final frame = (document['frames']! as Map<String, Object?>)['era:one']!
          as Map<String, Object?>;
      final lengths = ['0.05', '0.06', '0.07', '0.08', '0.09', '0.10', '0.11'];
      frame['coordinate'] = {
        'kind': 'nested',
        'baseLevel': 'year',
        'levels': [
          {'name': 'year'},
          {'name': 'month', 'within': 'year', 'children': lengths},
        ],
      };
      final law = CoordinateLaws().attempt(document, 'era:one').resolved;
      if (law == null) {
        fail(
          'A basis with an authored list of child lengths does not resolve at'
          ' all. WORK ITEM: the level ladder needs an authored per-child length'
          ' list ("that breakdown in this order as this list of decimals")'
          ' beside `radix` and `transition`.',
        );
      }
      final first = law.toDays(year(1, 2)) - law.toDays(year(1, 1));
      final second = law.toDays(year(1, 3)) - law.toDays(year(1, 2));
      expect(
        first,
        isNot(second),
        reason:
            'The authored list says month 1 and month 2 are different lengths.'
            ' WORK ITEM: `children` is carried as an unread extra, so every'
            ' month reads as the same length -- silently. The level ladder needs'
            ' an authored per-child length list beside `radix` and `transition`,'
            ' and the one math is where those decimals should be evaluated.',
      );
    });
  });
}
