// The spec is generative (Don, 2026-08-27): "We should never be testing for a
// specific case, we should be testing for a general case." Every assertion
// below is a property quantified over seeded random generation. The few
// exceptions are labelled RULED ANCHOR -- asserted law that is not derivable
// as a property -- or WITNESS, where the property being proven is that a case
// EXISTS.
//
// The seed is fixed so a failure reproduces exactly. Change it only to widen
// coverage deliberately, never to make a red suite green.
//
// What this covers: the one math (`lib/core/math.dart`), display weight and
// the blessed composition chain (`lib/core/weight.dart`), and falloff
// (`lib/core/falloff.dart`), each as properties rather than pinned cases.

import 'dart:math';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/falloff.dart';
import 'package:chronolog/core/math.dart';
import 'package:chronolog/core/weight.dart';
import 'package:test/test.dart';

const specSeed = 20260827;
const iterations = 200;

// --- Generators --------------------------------------------------------------

const _numberNames = ['w', 'x', 'y', 'z'];
const _truthNames = ['p', 'q', 'r', 's'];
const _comparisons = ['<', '<=', '>', '>=', '==', '!='];

/// Nonzero, so a generated `/` or `%` never divides by zero and every
/// generated tree has a value to compare.
Rational _small(Random r) => Rational.fromInt(1 + r.nextInt(9));

String _decimalText(Random r) {
  final whole = r.nextInt(1000);
  final places = r.nextInt(4);
  if (places == 0) return '$whole';
  final fraction = List.generate(places, (_) => r.nextInt(10)).join();
  return '$whole.$fraction';
}

/// A numeric expression. [branching] admits the forms that skip subtrees --
/// ternaries and short-circuiting booleans -- which the fuel-boundary
/// property must exclude to count node visits exactly.
Expr _number(Random r, int depth, {bool branching = true}) {
  if (depth <= 0 || r.nextInt(4) == 0) {
    return r.nextBool() ? Lit(_small(r), 0) : Name(_numberNames[r.nextInt(_numberNames.length)], 0);
  }
  Expr child() => _number(r, depth - 1, branching: branching);
  switch (r.nextInt(branching ? 9 : 8)) {
    case 0:
      return Unary('-', child(), 0);
    case 1:
      return Binary('+', child(), child(), 0);
    case 2:
      return Binary('-', child(), child(), 0);
    case 3:
      return Binary('*', child(), child(), 0);
    case 4:
      // The divisor is a literal so it is never zero.
      return Binary('/', child(), Lit(_small(r), 0), 0);
    case 5:
      return Binary('%', child(), Lit(_small(r), 0), 0);
    case 6:
      return Call(r.nextBool() ? 'min' : 'max', [child(), child()], 0);
    case 7:
      return Call(['abs', 'floor', 'ceil'][r.nextInt(3)], [child()], 0);
    default:
      return Cond(_truth(r, depth - 1), child(), child(), 0);
  }
}

Expr _truth(Random r, int depth) {
  if (depth <= 0 || r.nextInt(3) == 0) {
    return r.nextBool()
        ? Name(_truthNames[r.nextInt(_truthNames.length)], 0)
        : Lit(r.nextBool(), 0);
  }
  switch (r.nextInt(6)) {
    case 0:
      return Unary('not', _truth(r, depth - 1), 0);
    case 1:
      return Binary('and', _truth(r, depth - 1), _truth(r, depth - 1), 0);
    case 2:
      return Binary('or', _truth(r, depth - 1), _truth(r, depth - 1), 0);
    case 3:
      return Binary('xor', _truth(r, depth - 1), _truth(r, depth - 1), 0);
    default:
      return Binary(
        _comparisons[r.nextInt(_comparisons.length)],
        _number(r, depth - 1),
        _number(r, depth - 1),
        0,
      );
  }
}

Env _env(Random r) => Env(
  values: {
    for (final name in _numberNames)
      name: Rational(BigInt.from(r.nextInt(40) - 20), BigInt.from(1 + r.nextInt(6))),
    for (final name in _truthNames) name: r.nextBool(),
  },
);

int _nodes(Expr e) => switch (e) {
  Lit() || Name() => 1,
  Unary(:final operand) => 1 + _nodes(operand),
  Binary(:final left, :final right) => 1 + _nodes(left) + _nodes(right),
  Cond(:final condition, :final yes, :final no) => 1 + _nodes(condition) + _nodes(yes) + _nodes(no),
  Call(:final args) => args.fold(1, (sum, a) => sum + _nodes(a)),
};

/// An outcome is a value or a refusal reduced to its message, so a property
/// can compare two evaluations that both legitimately refuse.
Object _outcome(Expr e, Env env, {int fuel = defaultFuel}) {
  try {
    return evaluate(e, env, fuel: fuel);
  } on MathRefusal catch (refusal) {
    return 'REFUSED: ${refusal.message}';
  }
}

// --- The one math -----------------------------------------------------------

void main() {
  group('the one math: reading and writing', () {
    test('a printed tree re-parses to the same meaning (round trip)', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final tree = _number(r, 1 + r.nextInt(4));
        final env = _env(r);
        final printed = tree.toString();
        expect(_outcome(parse(printed), env), equals(_outcome(tree, env)), reason: printed);
      }
    });

    test('a printed truth tree re-parses to the same meaning', () {
      final r = Random(specSeed + 1);
      for (var i = 0; i < iterations; i++) {
        final tree = _truth(r, 1 + r.nextInt(4));
        final env = _env(r);
        expect(
          _outcome(parse(tree.toString()), env),
          equals(_outcome(tree, env)),
          reason: tree.toString(),
        );
      }
    });

    test('PEMDAS matches an independent reference evaluator', () {
      final r = Random(specSeed + 2);
      for (var i = 0; i < iterations; i++) {
        final terms = <String>[Rational.fromInt(1 + r.nextInt(9)).toString()];
        final count = 1 + r.nextInt(7);
        for (var k = 0; k < count; k++) {
          terms.add(['+', '-', '*', '/', '%'][r.nextInt(5)]);
          terms.add('${1 + r.nextInt(9)}');
        }
        final source = terms.join(' ');
        expect(evaluateSource(source, const Env()), equals(_reference(terms)), reason: source);
      }
    });

    test('^ is right-associative and exact', () {
      final r = Random(specSeed + 3);
      for (var i = 0; i < iterations; i++) {
        final a = Rational.fromInt(2 + r.nextInt(2));
        final b = 1 + r.nextInt(3);
        final c = 1 + r.nextInt(3);
        expect(
          evaluateSource('$a ^ $b ^ $c', const Env()),
          equals(a.pow(pow(b, c) as int)),
          reason: '$a ^ $b ^ $c',
        );
      }
    });

    test('unary minus binds tighter than ^', () {
      final r = Random(specSeed + 4);
      for (var i = 0; i < iterations; i++) {
        final a = 1 + r.nextInt(9);
        final b = 2 * (1 + r.nextInt(2));
        // An even exponent: `-a ^ b` is `(-a) ^ b`, which is positive.
        expect(evaluateSource('-$a ^ $b', const Env()), equals(Rational.fromInt(a).pow(b)));
      }
    });

    test('parentheses override precedence in both directions', () {
      final r = Random(specSeed + 5);
      for (var i = 0; i < iterations; i++) {
        final a = 1 + r.nextInt(9);
        final b = 1 + r.nextInt(9);
        final c = 1 + r.nextInt(9);
        final flat = evaluateSource('$a + $b * $c', const Env());
        final grouped = evaluateSource('($a + $b) * $c', const Env());
        expect(flat, equals(Rational.fromInt(a + b * c)));
        expect(grouped, equals(Rational.fromInt((a + b) * c)));
      }
    });

    test('trailing garbage is refused, never silently truncated', () {
      final r = Random(specSeed + 6);
      const garbage = [')', ' 2', ' )', ' ]', ' ,', ' 3 4'];
      for (var i = 0; i < iterations; i++) {
        final source = _number(r, 1 + r.nextInt(3)).toString();
        // The bare source parses.
        parse(source);
        final polluted = source + garbage[r.nextInt(garbage.length)];
        expect(() => parse(polluted), throwsA(isA<MathRefusal>()), reason: polluted);
      }
    });

    test('nesting refuses cleanly at the cap instead of overflowing', () {
      final r = Random(specSeed + 7);
      for (var i = 0; i < iterations; i++) {
        // The cap counts expression levels; n parentheses is n+1 levels.
        final depth = maxNestingDepth - 20 + r.nextInt(40);
        final source = '${'(' * depth}1${')' * depth}';
        if (depth + 1 > maxNestingDepth) {
          expect(
            () => parse(source),
            throwsA(
              isA<MathRefusal>().having((e) => e.message, 'message', contains('deeply nested')),
            ),
            reason: 'depth $depth',
          );
        } else {
          expect(
            evaluate(parse(source), const Env()),
            equals(Rational.one),
            reason: 'depth $depth',
          );
        }
      }
    });

    test('a decimal literal is exact, never a host double', () {
      final r = Random(specSeed + 8);
      for (var i = 0; i < iterations; i++) {
        final a = _decimalText(r);
        final b = _decimalText(r);
        final c = _decimalText(r);
        expect(
          evaluateSource('$a * $b + $c', const Env()),
          equals(Rational.parse(a) * Rational.parse(b) + Rational.parse(c)),
          reason: '$a * $b + $c',
        );
      }
      // The canonical host-float tell, as a property of the above.
      expect(evaluateSource('0.1 + 0.2 == 0.3', const Env()), isTrue);
    });
  });

  group('the one math: the sandbox', () {
    test('a name nothing binds is refused, whatever the name is', () {
      final r = Random(specSeed + 9);
      const hostish = [
        'window',
        'globalThis',
        'Object',
        'constructor',
        '__proto__',
        'prototype',
        'print',
        'dart',
        'self',
        'process',
        'require',
        'eval',
      ];
      for (var i = 0; i < iterations; i++) {
        final name = r.nextBool() ? hostish[r.nextInt(hostish.length)] : 'n${r.nextInt(1000000)}';
        expect(
          () => evaluateSource(name, const Env()),
          throwsA(
            isA<MathRefusal>().having(
              (e) => e.message,
              'message',
              contains('Unknown formula name'),
            ),
          ),
          reason: name,
        );
      }
    });

    test('the vocabulary is open: a resolver decides what a name means', () {
      final r = Random(specSeed + 10);
      for (var i = 0; i < iterations; i++) {
        final name = 'frame_${r.nextInt(1000)}';
        final value = Rational.fromInt(r.nextInt(100));
        // The engine knows nothing about what the name denotes -- a frame, a
        // predicate, a weight -- only what the resolver hands back.
        expect(
          evaluateSource('$name * 2', Env(resolver: (asked) => asked == name ? value : null)),
          equals(value * Rational.fromInt(2)),
        );
        expect(
          () =>
              evaluateSource('other_$name', Env(resolver: (asked) => asked == name ? value : null)),
          throwsA(isA<MathRefusal>()),
        );
      }
    });

    test('identifiersOf reports the open vocabulary and nothing else', () {
      final r = Random(specSeed + 11);
      for (var i = 0; i < iterations; i++) {
        final tree = _number(r, 1 + r.nextInt(4));
        final names = identifiersOf(tree);
        // Builtin function names are not identifiers: nothing in this
        // language produces a function, so a call is not a name lookup.
        expect(names.intersection({'min', 'max', 'abs', 'floor', 'ceil'}), isEmpty);
        // Every reported name is in the pool, and every name the tree can
        // read is reported: binding exactly these makes it evaluable.
        expect(names.difference({..._numberNames, ..._truthNames}), isEmpty);
        final bound = Env(
          values: {
            for (final name in names)
              name: _truthNames.contains(name) ? r.nextBool() : Rational.fromInt(r.nextInt(9) + 1),
          },
        );
        expect(_outcome(tree, bound), isNot(contains('Unknown formula name')));
      }
    });

    test('fuel exhaustion refuses; it never returns a wrong answer', () {
      final r = Random(specSeed + 12);
      for (var i = 0; i < iterations; i++) {
        // No ternaries or short-circuits: every node is visited exactly once,
        // so the node count IS the fuel a correct evaluation needs.
        final tree = _number(r, 1 + r.nextInt(4), branching: false);
        final env = _env(r);
        final needed = _nodes(tree);
        final full = _outcome(tree, env);
        expect(_outcome(tree, env, fuel: needed), equals(full));
        for (final starved in [needed - 1, r.nextInt(needed)]) {
          expect(
            () => evaluate(tree, env, fuel: starved),
            throwsA(isA<MathRefusal>().having((e) => e.message, 'message', contains('fuel'))),
            reason: '${tree.toString()} on $starved of $needed',
          );
        }
      }
    });

    test('a value too large to hold is refused, not approximated', () {
      final r = Random(specSeed + 13);
      for (var i = 0; i < iterations; i++) {
        final base = 2 + r.nextInt(8);
        final exponent = maxExponent + 1 + r.nextInt(1000000);
        expect(() => evaluateSource('$base ^ $exponent', const Env()), throwsA(isA<MathRefusal>()));
        expect(
          () => evaluateSource('1e${maxExponent + 1 + r.nextInt(1000000)}', const Env()),
          throwsA(isA<MathRefusal>()),
        );
      }
    });
  });

  group('the one math: boolean algebra', () {
    test('De Morgan holds over random truth trees', () {
      final r = Random(specSeed + 14);
      for (var i = 0; i < iterations; i++) {
        final a = _truth(r, 1 + r.nextInt(3)).toString();
        final b = _truth(r, 1 + r.nextInt(3)).toString();
        final env = _env(r);
        expect(
          evaluateSource('not ($a and $b)', env),
          equals(evaluateSource('(not $a) or (not $b)', env)),
          reason: 'not ($a and $b)',
        );
        expect(
          evaluateSource('not ($a or $b)', env),
          equals(evaluateSource('(not $a) and (not $b)', env)),
          reason: 'not ($a or $b)',
        );
      }
    });

    test('double negation is identity; xor is its own definition', () {
      final r = Random(specSeed + 15);
      for (var i = 0; i < iterations; i++) {
        final a = _truth(r, 1 + r.nextInt(3)).toString();
        final b = _truth(r, 1 + r.nextInt(3)).toString();
        final env = _env(r);
        expect(evaluateSource('not not ($a)', env), equals(evaluateSource(a, env)), reason: a);
        expect(
          evaluateSource('$a xor $b', env),
          equals(evaluateSource('($a or $b) and not ($a and $b)', env)),
          reason: '$a xor $b',
        );
      }
    });

    test('the boolean words are case-insensitive', () {
      final r = Random(specSeed + 16);
      for (var i = 0; i < iterations; i++) {
        final a = _truth(r, 1 + r.nextInt(2)).toString();
        final b = _truth(r, 1 + r.nextInt(2)).toString();
        final env = _env(r);
        final shout = '$a AND NOT ($b)'.replaceAll('not (', 'NOT (');
        expect(
          evaluateSource(shout, env),
          equals(evaluateSource('$a and not ($b)', env)),
          reason: shout,
        );
      }
    });

    test('comparison trichotomy: exactly one of <, ==, > holds', () {
      final r = Random(specSeed + 17);
      for (var i = 0; i < iterations; i++) {
        final env = _env(r);
        final results = [
          for (final op in ['<', '==', '>']) evaluateSource('x $op y', env),
        ];
        expect(results.where((held) => held == true).length, equals(1));
        expect(evaluateSource('x <= y', env), equals(results[0] == true || results[1] == true));
        expect(evaluateSource('x >= y', env), equals(results[2] == true || results[1] == true));
        expect(evaluateSource('x != y', env), equals(results[1] == false));
      }
    });

    test('the ternary selects, and only evaluates the arm it selects', () {
      final r = Random(specSeed + 18);
      for (var i = 0; i < iterations; i++) {
        final condition = _truth(r, 1 + r.nextInt(3));
        final env = _env(r);
        final held = evaluate(condition, env) as bool;
        // The unselected arm is a refusal waiting to happen; selecting the
        // other one must not reach it.
        final source = held ? '($condition) ? 7 : 1 / 0' : '($condition) ? 1 / 0 : 7';
        expect(evaluateSource(source, env), equals(Rational.fromInt(7)), reason: source);
      }
    });

    test('types are strict: no truthiness, no coercion, position reported', () {
      final r = Random(specSeed + 19);
      for (var i = 0; i < iterations; i++) {
        final number = _number(r, 1 + r.nextInt(2)).toString();
        final truth = _truth(r, 1 + r.nextInt(2)).toString();
        final env = _env(r);
        for (final source in [
          '($number) and ($truth)',
          '($truth) + 1',
          '($truth) == ($number)',
          '($truth) < ($truth)',
          '($number) ? 1 : 2',
        ]) {
          try {
            evaluateSource(source, env);
            fail('accepted a type confusion: $source');
          } on MathRefusal catch (refusal) {
            expect(refusal.position, greaterThanOrEqualTo(0));
            expect(refusal.position, lessThanOrEqualTo(source.length));
          }
        }
      }
    });
  });

  // --- Display weight -------------------------------------------------------

  group('display weight', () {
    test('the sugar rule: a plain number n means w * n, exactly', () {
      final r = Random(specSeed + 20);
      for (var i = 0; i < iterations; i++) {
        final n = Rational(BigInt.from(r.nextInt(50)), BigInt.from(1 + r.nextInt(8)));
        final w = Rational(BigInt.from(r.nextInt(50)), BigInt.from(1 + r.nextInt(8)));
        expect(applyWeightFormula(n, w), equals(w * n));
        expect(normalizeWeightFormula(n), equals('w * (${n.toJson()})'));
        // The same rule reached through authored text. A repeating fraction
        // has no decimal text, so the text case is generated as text.
        final text = _decimalText(r);
        expect(applyWeightFormula(text, w), equals(w * Rational.parse(text)), reason: text);
        expect(normalizeWeightFormula(text), equals('w * ($text)'));
      }
    });

    test('nothing authored is identity', () {
      final r = Random(specSeed + 21);
      for (var i = 0; i < iterations; i++) {
        final w = Rational(BigInt.from(r.nextInt(99)), BigInt.from(7));
        for (final blank in [null, '', '   ', '\t', 'w', ' w ']) {
          expect(applyWeightFormula(blank, w), equals(w), reason: '$blank');
        }
      }
    });

    test('a broken knob never changes what renders', () {
      final r = Random(specSeed + 22);
      for (var i = 0; i < iterations; i++) {
        final w = Rational(BigInt.from(r.nextInt(99)), BigInt.from(3));
        final unknown = 'unknown_${r.nextInt(10000)}';
        final broken = [
          'w +',
          'w * $unknown',
          unknown,
          'w +++ 3',
          '( w',
          'w ) 2',
          'w * true',
          'w and 2',
          '1 / 0 * w',
          'w / (w - w)',
          'w ^ ${maxExponent + 5}',
          'w ? 1 : 2',
          '',
        ];
        for (final formula in broken) {
          expect(applyWeightFormula(formula, w), equals(w), reason: formula);
        }
        // A result below zero is a broken knob too, and falls back the same
        // way -- but zero itself is a legitimate demotion, not a failure.
        expect(applyWeightFormula('w - ${w + Rational.one}', w), equals(w));
        expect(applyWeightFormula('w * 0', w), equals(Rational.zero));
      }
    });

    test('additive and multiplicative formulas both work, exactly', () {
      final r = Random(specSeed + 23);
      for (var i = 0; i < iterations; i++) {
        final w = Rational(BigInt.from(r.nextInt(90) + 10), BigInt.from(4));
        final c = Rational(BigInt.from(r.nextInt(9)), BigInt.from(2));
        expect(applyWeightFormula('w + ${c.toJson()}', w), equals(w + c));
        expect(
          applyWeightFormula('(w + ${c.toJson()}) * 2', w),
          equals((w + c) * Rational.fromInt(2)),
        );
        // PEMDAS through the real parser, not a flattened fold.
        expect(applyWeightFormula('w + ${c.toJson()} * 2', w), equals(w + c * Rational.fromInt(2)));
      }
    });

    test('validate accepts what apply honors and reports the rest', () {
      final r = Random(specSeed + 24);
      for (var i = 0; i < iterations; i++) {
        final good = 'w * ${1 + r.nextInt(9)} + ${r.nextInt(9)}';
        expect(validateWeightFormula(good).valid, isTrue);
        expect(validateWeightFormula(good).error, isNull);
        expect(
          validateWeightFormula(Rational.fromInt(r.nextInt(9))).valid,
          isTrue,
          reason: 'sugar validates too',
        );
        final bad = validateWeightFormula('w * ${r.nextInt(9)} +');
        expect(bad.valid, isFalse);
        expect(bad.error, isNotNull);
        expect(bad.error, isNotEmpty);
      }
    });

    test('authoring: identity deletes, sugar stores exactly, bad input refuses', () {
      final r = Random(specSeed + 25);
      for (var i = 0; i < iterations; i++) {
        // Identity is a VALUE, not a spelling: blank, `w`, and every spelling
        // of one all delete the field.
        for (final identity in [
          '',
          '   ',
          'w',
          ' w ',
          '1',
          '+1',
          '1.${'0' * (1 + r.nextInt(4))}',
          '01',
        ]) {
          expect(resolveAuthoredWeight(identity), isNull, reason: identity);
        }
        final n = _decimalText(r);
        final stored = resolveAuthoredWeight(n);
        if (Rational.parse(n) == Rational.one) {
          expect(stored, isNull, reason: n);
        } else {
          expect(stored, equals(Rational.parse(n)), reason: n);
        }
        // A negative VALUE refuses. `-0` is zero, which is a legitimate
        // demotion rather than a negative.
        final negated = '-$n';
        if (Rational.parse(negated).isNegative) {
          expect(
            () => resolveAuthoredWeight(negated),
            throwsA(
              isA<MathRefusal>().having((e) => e.message, 'message', contains('zero or greater')),
            ),
            reason: negated,
          );
        } else {
          expect(resolveAuthoredWeight(negated), equals(Rational.zero));
        }
        final formula = 'w * ${1 + r.nextInt(9)} + ${r.nextInt(9)}';
        expect(resolveAuthoredWeight(formula), equals(formula));
        expect(
          () => resolveAuthoredWeight('$formula +'),
          throwsA(isA<MathRefusal>().having((e) => e.message, 'message', contains('invalid'))),
        );
      }
    });

    test('RULED ANCHOR: only new group and importance frames are promoted', () {
      expect(defaultWeightForNewFrame('group'), equals(Rational.fromInt(3, 2)));
      expect(defaultWeightForNewFrame('importance'), equals(Rational.fromInt(3, 2)));
      for (final kind in ['calendar', 'cycle', 'line', 'measure', 'set', 'state', 'other']) {
        expect(defaultWeightForNewFrame(kind), isNull, reason: kind);
      }
    });
  });

  // --- The blessed chain ----------------------------------------------------

  group('the blessed weight chain', () {
    test('rings apply own first, then nearest frames, then the projector', () {
      final r = Random(specSeed + 26);
      for (var i = 0; i < iterations; i++) {
        final rings = _rings(r, 1 + r.nextInt(6));
        final projector = weightRing('projector', _monotone(r), distance: 99);
        final base = Rational.fromInt(1 + r.nextInt(9));
        final own = _monotone(r);
        final derivation = composeWeight(base: base, own: own, frames: rings, projector: projector);
        final expected = rings.where((ring) => !ring.negated).toList()
          ..sort(
            (a, b) =>
                a.distance != b.distance ? a.distance.compareTo(b.distance) : a.id.compareTo(b.id),
          );
        expect(
          derivation.rings.map((step) => step.id).toList(),
          equals([ownWeightRing, ...expected.map((ring) => ring.id), 'projector']),
        );
        // The fold is exactly that order, applied left to right.
        var manual = applyWeightFormula(own, base);
        for (final ring in expected) {
          manual = applyWeightFormula(ring.formula, manual);
        }
        manual = applyWeightFormula(projector.formula, manual);
        expect(derivation.weight, equals(manual));
        // Every ring is shown, with the weight leaving it.
        expect(derivation.rings.last.weight, equals(derivation.weight));
      }
    });

    test('equal distances break on stable id, and only on it', () {
      final r = Random(specSeed + 27);
      for (var i = 0; i < iterations; i++) {
        final distance = 1 + r.nextInt(3);
        final ids = List.generate(5, (k) => 'frame:${r.nextInt(1000)}-$k');
        final rings = [for (final id in ids) weightRing(id, _monotone(r), distance: distance)];
        final forward = composeWeight(base: Rational.one, frames: rings);
        final backward = composeWeight(base: Rational.one, frames: rings.reversed);
        expect(
          forward.rings.map((step) => step.id).skip(1).toList(),
          equals((ids.toList()..sort())),
        );
        // Input order is not an input: the same set folds to the same weight.
        expect(backward.weight, equals(forward.weight));
      }
    });

    test('a NOT-term gates visibility and never modifies weight', () {
      final r = Random(specSeed + 28);
      for (var i = 0; i < iterations; i++) {
        final rings = _rings(r, 1 + r.nextInt(5));
        final without = composeWeight(
          base: Rational.fromInt(2),
          frames: rings.where((ring) => !ring.negated),
        );
        final with_ = composeWeight(
          base: Rational.fromInt(2),
          frames: [...rings, weightRing('frame:negated', 'w * 1000', distance: 0, negated: true)],
        );
        expect(with_.weight, equals(without.weight));
        expect(with_.rings.map((step) => step.id), isNot(contains('frame:negated')));
        expect(
          composeWeight(
            base: Rational.fromInt(2),
            projector: weightRing('p', 'w * 9', negated: true),
          ).weight,
          equals(Rational.fromInt(2)),
        );
      }
    });

    test('THE CHAIN PROPERTY: uniform math applied last cannot reorder', () {
      final r = Random(specSeed + 29);
      for (var i = 0; i < iterations; i++) {
        final population = _population(r, 2 + r.nextInt(6));
        // Monotone and non-negative-safe: `w - c` is NOT monotone under the
        // identity-on-negative rule, which clamps small weights back to
        // themselves. Only formulas that stay non-negative are order-safe,
        // and that is the class the ruling is about.
        final uniform = _monotone(r);
        final before = [for (final member in population) _fold(member, null).weight];
        final after = [
          for (final member in population)
            _fold(member, weightRing('projector', uniform, distance: 1 << 20)).weight,
        ];
        for (var a = 0; a < population.length; a++) {
          for (var b = 0; b < population.length; b++) {
            if (before[a] < before[b]) {
              expect(
                after[a] <= after[b],
                isTrue,
                reason:
                    'projecting with "$uniform" reordered '
                    '${before[a]} < ${before[b]} into '
                    '${after[a]} vs ${after[b]}',
              );
            }
          }
        }
      }
    });

    test('WITNESS: the same math applied mid-chain CAN reorder', () {
      // Why the chain is ruled as it is, in one hand-checked case.
      // Without F: A = 3 * 1 = 3, B = 1 + 3 = 4, so A < B.
      // With F = `w * 2` applied at position (2), nearest: A = (3 * 2) * 1 = 6,
      // B = (1 * 2) + 3 = 5, so A > B -- reversed.
      // With the same F at position (4), last: A = 3 * 2 = 6, B = 4 * 2 = 8 --
      // order held.
      const f = 'w * 2';
      final a = _Member(Rational.fromInt(3), null, [
        weightRing('frame:tail', 'w * 1', distance: 5),
      ]);
      final b = _Member(Rational.fromInt(1), null, [
        weightRing('frame:tail', 'w + 3', distance: 5),
      ]);
      final near = weightRing('frame:F', f, distance: 0);
      final last = weightRing('projector', f, distance: 1 << 20);
      expect(_fold(a, null).weight < _fold(b, null).weight, isTrue);
      expect(
        _fold(_Member(a.base, a.own, [near, ...a.frames]), null).weight >
            _fold(_Member(b.base, b.own, [near, ...b.frames]), null).weight,
        isTrue,
        reason: 'mid-chain application reverses the view order',
      );
      expect(
        _fold(a, last).weight < _fold(b, last).weight,
        isTrue,
        reason: 'the same math applied last leaves the order alone',
      );

      // And the same reversal is findable by search, not just by hand.
      final r = Random(specSeed + 30);
      var witnesses = 0;
      for (var i = 0; i < iterations; i++) {
        final population = _population(r, 2 + r.nextInt(4));
        final uniform = _monotone(r);
        final before = [for (final member in population) _fold(member, null).weight];
        final mid = [
          for (final member in population)
            _fold(
              _Member(member.base, member.own, [
                weightRing('frame:uniform', uniform, distance: 0),
                ...member.frames,
              ]),
              null,
            ).weight,
        ];
        for (var a = 0; a < population.length; a++) {
          for (var b = 0; b < population.length; b++) {
            if (before[a] < before[b] && mid[a] > mid[b]) witnesses++;
          }
        }
      }
      expect(witnesses, greaterThan(0));
    });

    test('falloff is the closing step, applied after the fold', () {
      final r = Random(specSeed + 31);
      for (var i = 0; i < iterations; i++) {
        final population = _population(r, 1);
        final member = population.first;
        final distance = Rational(BigInt.from(r.nextInt(400)), BigInt.from(1 + r.nextInt(4)));
        final half = Rational.fromInt(1 + r.nextInt(30));
        final folded = _fold(member, null).weight;
        final closed = composeWeight(
          base: member.base,
          own: member.own,
          frames: member.frames,
          falloffDistance: distance,
          halfDistanceDays: half,
        );
        expect(closed.weight, equals(apparentMagnitude(folded, distance, halfDistance: half)));
        expect(closed.rings.last.id, equals(falloffWeightRing));
        expect(closed.rings.last.weight, equals(closed.weight));
        // Monotone in distance: further never registers stronger.
        final further = composeWeight(
          base: member.base,
          own: member.own,
          frames: member.frames,
          falloffDistance: distance + Rational.one,
          halfDistanceDays: half,
        );
        expect(further.weight <= closed.weight, isTrue);
      }
    });
  });

  // --- Falloff --------------------------------------------------------------

  group('falloff', () {
    test('apparent magnitude: exact at home, monotone, never zero', () {
      final r = Random(specSeed + 32);
      for (var i = 0; i < iterations; i++) {
        final base = Rational(BigInt.from(1 + r.nextInt(99)), BigInt.from(1 + r.nextInt(9)));
        final half = Rational(BigInt.from(1 + r.nextInt(30)), BigInt.from(1 + r.nextInt(4)));
        expect(
          apparentMagnitude(base, Rational.zero, halfDistance: half),
          equals(base),
          reason: 'exactly the base at distance zero',
        );
        expect(
          apparentMagnitude(base, half, halfDistance: half),
          equals(base / Rational.fromInt(2)),
          reason: 'exactly half at the half distance',
        );
        var previous = base;
        var distance = Rational.zero;
        for (var step = 0; step < 8; step++) {
          distance += Rational(BigInt.from(1 + r.nextInt(1000)), BigInt.from(1 + r.nextInt(7)));
          final value = apparentMagnitude(base, distance, halfDistance: half);
          expect(value < previous, isTrue, reason: 'still falling');
          expect(value > Rational.zero, isTrue, reason: 'never reaches zero');
          previous = value;
        }
      }
    });

    test('distance is a gap, not a direction; a degenerate scale is refused', () {
      final r = Random(specSeed + 33);
      for (var i = 0; i < iterations; i++) {
        final base = Rational.fromInt(1 + r.nextInt(9));
        final distance = Rational(BigInt.from(1 + r.nextInt(999)), BigInt.from(1 + r.nextInt(5)));
        expect(apparentMagnitude(base, -distance), equals(apparentMagnitude(base, distance)));
        for (final bad in [Rational.zero, -distance]) {
          expect(
            () => apparentMagnitude(base, distance, halfDistance: bad),
            throwsA(isA<RangeError>()),
          );
        }
      }
    });

    test('home spans every resolvable staple and nothing else', () {
      final r = Random(specSeed + 34);
      for (var i = 0; i < iterations; i++) {
        final extents = <String, DayExtent?>{};
        final count = r.nextInt(6);
        for (var k = 0; k < count; k++) {
          if (r.nextInt(4) == 0) {
            // A far end that does not resolve to one coordinate contributes
            // nothing -- never a fabricated date.
            extents['end:$k'] = null;
            continue;
          }
          final start = Rational.fromInt(r.nextInt(2000) - 1000);
          extents['end:$k'] = (start: start, end: start + Rational.fromInt(r.nextInt(5)));
        }
        final home = objectHome(extents.keys, (id) => extents[id]);
        final resolved = extents.values.whereType<DayExtent>().toList();
        if (resolved.isEmpty) {
          expect(home, isNull, reason: 'nothing resolvable, so no home');
          expect(distanceFromHome(home, Rational.zero), isNull);
          continue;
        }
        expect(home, isNotNull);
        expect(home!.start, equals(resolved.map((e) => e.start).reduce((a, b) => a < b ? a : b)));
        expect(home.end, equals(resolved.map((e) => e.end).reduce((a, b) => a > b ? a : b)));
        expect(home.start <= home.end, isTrue);
        // Zero anywhere inside the home; the exact gap to the nearer edge
        // outside it.
        for (var probe = 0; probe < 6; probe++) {
          final at = Rational(BigInt.from(r.nextInt(4000) - 2000), BigInt.from(1 + r.nextInt(3)));
          final gap = distanceFromHome(home, at)!;
          if (at >= home.start && at <= home.end) {
            expect(gap, equals(Rational.zero));
          } else {
            expect(gap, equals(at < home.start ? home.start - at : at - home.end));
            expect(gap > Rational.zero, isTrue);
          }
        }
      }
    });

    test('a single staple is a zero-width home at full presence', () {
      final r = Random(specSeed + 35);
      for (var i = 0; i < iterations; i++) {
        final day = Rational.fromInt(r.nextInt(100000) - 50000);
        final home = objectHome(const ['end:one'], (_) => (start: day, end: day));
        expect(home!.start, equals(day));
        expect(home.end, equals(day));
        expect(distanceFromHome(home, day), equals(Rational.zero));
        final base = Rational.fromInt(1 + r.nextInt(9));
        expect(apparentMagnitude(base, distanceFromHome(home, day)!), equals(base));
      }
    });
  });
}

// --- Reference evaluator ----------------------------------------------------

/// An independent evaluator for a flat `a op b op c ...` sequence, written
/// against the precedence table rather than the parser: lowest precedence
/// splits last-first (left associative). It exists to disagree with the
/// engine if the engine ever folds left to right.
Rational _reference(List<String> terms) {
  if (terms.length == 1) return Rational.parse(terms.first);
  for (final level in [
    ['+', '-'],
    ['*', '/', '%'],
  ]) {
    for (var i = terms.length - 2; i > 0; i -= 2) {
      if (!level.contains(terms[i])) continue;
      final left = _reference(terms.sublist(0, i));
      final right = _reference(terms.sublist(i + 1));
      return switch (terms[i]) {
        '+' => left + right,
        '-' => left - right,
        '*' => left * right,
        '/' => left / right,
        _ => left % right,
      };
    }
  }
  throw StateError('unreachable: ${terms.join(' ')}');
}

// --- Chain fixtures ---------------------------------------------------------

/// A monotone, non-negative-safe formula: strictly increasing in `w` for every
/// non-negative `w`, and never producing a negative result from one.
String _monotone(Random r) {
  final k = 1 + r.nextInt(5);
  final c = r.nextInt(6);
  return switch (r.nextInt(3)) {
    0 => 'w * $k',
    1 => 'w + $c',
    _ => 'w * $k + $c',
  };
}

List<WeightRing> _rings(Random r, int count) => [
  for (var i = 0; i < count; i++)
    weightRing(
      'frame:${r.nextInt(100)}-$i',
      r.nextInt(5) == 0 ? null : _monotone(r),
      distance: 1 + r.nextInt(4),
      negated: r.nextInt(6) == 0,
    ),
];

class _Member {
  final Rational base;
  final Object? own;
  final List<WeightRing> frames;
  const _Member(this.base, this.own, this.frames);
}

List<_Member> _population(Random r, int count) => [
  for (var i = 0; i < count; i++)
    _Member(
      Rational.fromInt(r.nextInt(20)),
      r.nextBool() ? _monotone(r) : null,
      _rings(r, r.nextInt(4)),
    ),
];

WeightDerivation _fold(_Member member, WeightRing? projector) =>
    composeWeight(base: member.base, own: member.own, frames: member.frames, projector: projector);
