// A BASIS IS AN AUTHORED ONE MATH FUNCTION.
//
// Pure Dart. Nothing under lib/core/ may import Flutter or a third-party package.
//
// Ruled 2026-08-31 (Don): "it is assumed to have its own basis frame and that
// could be any valid One Math Expression. a linear equation a non-linear
// equation a piecewise equeation, an all point, a loop, A list/stack, or
// anything else." And the worked example, which is the acceptance:
//
//   "era 1 would be a peicewise function, where we say y is 0 when x <=0, Y is x
//    when x is >=0 && x<=1051, then we would define 1 is year, year contains 14
//    months, that breakdown in this order as this list of decimals."
//
// So a frame's `basis` is EITHER another frame whose structure it inherits (the
// spelling that has always worked) OR a function of its own axis. This file is
// the second, and it is the first step of the law-into-one-math merger.
//
// THE ENGINE IS math.dart's. One expression language, one parser, one evaluator:
// there is no second grammar here, and a nested radix ladder remains perfectly
// valid data as ONE SPELLING of the general basis rather than as the only one.
//
// WHAT IT DOES. A basis maps a count on the frame's own axis (x, in its base
// units) to a count on the axis it is measured against (y, the same units) --
// so `y = x` is a frame whose time flows plainly, `y = 0` is a stretch where
// nothing advances, and a piecewise assembly of the two is Don's era 1: dead
// before its beginning, flowing for 1051 units. The ladder underneath is
// untouched; a basis warps the COUNT, not the units it is spelled in.
//
// AND WHERE IT CANNOT ANSWER, IT SAYS SO. Inversion is exact where a piece is a
// straight line in x and MANY-VALUED where a piece is flat -- an author who
// writes `y = 0 when x <= 0` has said that every x below zero is day zero, and
// answering with one of them would be the model picking. Anything else refuses
// in the author's own words rather than approximating.

import 'eras.dart';
import 'exact.dart';
import 'math.dart';

/// The variable a basis is written in, unless the author names another. `x` is
/// what Don wrote; it is a default, not a keyword, and an authored `variable`
/// replaces it everywhere.
const String basisVariable = 'x';

/// One piece: when it applies, and what it says.
///
/// [when] is null for a piece with no guard -- the fallback, which is what a
/// single-expression basis is exactly one of. Pieces are tried IN AUTHORED
/// ORDER and the first whose guard holds answers, so Don's two pieces overlapping
/// at x = 0 is not an ambiguity: the order he wrote them in is the answer.
typedef BasisPiece = ({Expr? when, Expr value, String whenSource, String valueSource});

/// What an inverse came to.
///
/// [at] is every x the pieces send to the asked-for y, ascending. [manyValued]
/// is true when a FLAT piece answers -- a whole stretch of the axis maps to this
/// one value, so there is no single x and never will be. [refusal] carries the
/// author's sentence when a piece could not be inverted at all, and it may be
/// non-null alongside answers: a partial enumeration is not an enumeration, and
/// saying so is the honest report.
typedef BasisInverse = ({List<Rational> at, bool manyValued, String? refusal});

/// A basis authored as a function.
///
/// Refuses at PARSE time for a shape it cannot read, so a frame with a broken
/// basis reports through the same law-refusal seam every other declaration
/// failure does -- rather than failing at draw time, once per instant.
class BasisFunction {
  BasisFunction._(this.variable, this.pieces, this.label, this.held);

  /// Reads the authored map, or null when the value names no function at all.
  ///
  /// [held] is the authored shape this build accepts as DATA and cannot yet
  /// evaluate. Ruled legal the same night -- "an all point, a loop, A
  /// list/stack" -- so it loads, round-trips, and refuses evaluation in words
  /// naming what it is, which is the only honest thing a build can do with a
  /// meaning nobody has implemented.
  static BasisFunction? parse(Object? source, String label) {
    if (source is! Map) return null;
    final json = asMap(source)!;
    final variable = declaredText(json['variable']);
    final rows = asList(json['pieces']);
    final single = declaredText(json['expression']);
    if (rows.isEmpty && single.isEmpty) {
      // A basis this build cannot execute is still a basis. The word the author
      // used is carried verbatim into the refusal so the report names the thing
      // rather than "an unsupported basis".
      final held = [
        for (final entry in json.entries)
          if (entry.value != null) entry.key,
      ]..sort();
      return held.isEmpty
          ? null
          : BasisFunction._(
              variable.isEmpty ? basisVariable : variable,
              const [],
              label,
              held.join(', '),
            );
    }
    final pieces = <BasisPiece>[];
    void add(Object? guard, Object? value, int index) {
      final guardText = declaredText(guard);
      final valueText = declaredText(value);
      if (valueText.isEmpty) {
        throw LawRefusal('$label: piece ${index + 1} of this basis says nothing.');
      }
      pieces.add((
        when: guardText.isEmpty ? null : _read(guardText, label),
        value: _read(valueText, label),
        whenSource: guardText,
        valueSource: valueText,
      ));
    }

    if (rows.isEmpty) {
      add(null, single, 0);
    } else {
      for (final (index, row) in rows.indexed) {
        final piece = asMap(row);
        add(piece?['when'], piece?['is'] ?? piece?['value'], index);
      }
    }
    return BasisFunction._(
      variable.isEmpty ? basisVariable : variable,
      List.unmodifiable(pieces),
      label,
      null,
    );
  }

  final String variable;
  final List<BasisPiece> pieces;
  final String label;

  /// The authored keys this build carries but cannot evaluate, or null.
  final String? held;

  static Expr _read(String source, String label) {
    try {
      return parseCached(source);
    } on MathRefusal catch (refusal) {
      throw LawRefusal('$label: "$source" cannot be read as a formula -- ${refusal.message}.');
    }
  }

  /// y, for the count x on this frame's own axis.
  Rational forward(Rational x) {
    if (held != null) {
      throw LawRefusal(
        '$label: this basis is authored as $held, which this build carries but'
        ' cannot evaluate. Nothing in it has a position yet.',
      );
    }
    final env = Env(values: {variable: x});
    for (final piece in pieces) {
      if (!_holds(piece, env)) continue;
      final value = evaluate(piece.value, env);
      if (value is Rational) return value;
      throw LawRefusal(
        '$label: "${piece.valueSource}" answers true or false rather than a place'
        ' on the line.',
      );
    }
    throw LawRefusal(
      '$label: no piece of this basis covers $variable = $x, so nothing there has'
      ' a position.',
    );
  }

  /// Every x this basis sends to [y].
  ///
  /// EXACT, NEVER APPROXIMATE. A piece is inverted by reading its expression's
  /// own STRAIGHT-LINE FORM -- which is a structural fact about the tree, not a
  /// sample of it -- and every candidate is then VERIFIED through [forward], so
  /// a piece's guard and the order the pieces were written in are both honoured
  /// without this having to solve an inequality. A flat piece answers
  /// many-valued and a piece that is not a straight line refuses by name.
  BasisInverse inverse(Rational y) {
    if (held != null) {
      return (at: const [], manyValued: false, refusal: _heldRefusal());
    }
    final found = <Rational>{};
    var manyValued = false;
    String? refusal;
    for (final piece in pieces) {
      final line = straightLine(piece.value, variable);
      if (line == null) {
        refusal ??=
            '$label: "${piece.valueSource}" is not a straight line in $variable,'
            ' so a position in it has no single coordinate here.';
        continue;
      }
      if (line.slope.isZero) {
        // A FLAT PIECE IS A STRETCH, NOT A POINT. "y is 0 when x <= 0" says
        // every x below zero is this one value; picking one of them would be the
        // model inventing the coordinate the author declined to.
        if (line.intercept == y) manyValued = true;
        continue;
      }
      final x = (y - line.intercept) / line.slope;
      // Verified rather than assumed: an earlier piece may already own this x,
      // and the guard may exclude it outright.
      try {
        if (forward(x) == y) found.add(x);
      } on LawRefusal {
        continue;
      }
    }
    final at = found.toList()..sort((left, right) => left.compareTo(right));
    return (at: at, manyValued: manyValued, refusal: refusal);
  }

  /// The one answer, or the author's sentence about why there is not one.
  ///
  /// This is the shape the coordinate law wants: it needs a single coordinate or
  /// a refusal it can pass on, and "several" and "a whole stretch" are refusals
  /// with different sentences rather than one vague failure.
  Rational invert(Rational y) {
    final answer = inverse(y);
    if (answer.refusal != null) throw LawRefusal(answer.refusal!);
    if (answer.manyValued) {
      throw LawRefusal(
        '$label: a whole stretch of this basis sits at $y, so there is no single'
        ' position there to name.',
      );
    }
    if (answer.at.isEmpty) {
      throw LawRefusal('$label: nothing in this basis reaches $y.');
    }
    if (answer.at.length > 1) {
      throw LawRefusal(
        '$label: this basis reaches $y at ${answer.at.length} places'
        ' (${answer.at.join(', ')}), so a position there has no single'
        ' coordinate.',
      );
    }
    return answer.at.single;
  }

  String _heldRefusal() =>
      '$label: this basis is authored as $held, which this build carries but'
      ' cannot evaluate.';

  bool _holds(BasisPiece piece, Env env) {
    final guard = piece.when;
    if (guard == null) return true;
    final value = evaluate(guard, env);
    if (value is bool) return value;
    throw LawRefusal(
      '$label: "${piece.whenSource}" answers a number rather than true or false,'
      ' so it cannot say when this piece applies.',
    );
  }
}

/// The straight line an expression IS in [variable] -- `intercept + slope * x`
/// -- or null when it is not one.
///
/// Structural, so the answer is a proof rather than a sample: a tree built from
/// numbers, the variable, negation, addition, subtraction, multiplication by a
/// constant and division by a constant is a straight line and nothing else is.
/// A ternary is deliberately excluded: nested piecewise belongs in the pieces
/// list, where each branch can be inverted and verified on its own.
({Rational intercept, Rational slope})? straightLine(Expr node, String variable) => switch (node) {
  Lit(:final value) => value is Rational ? (intercept: value, slope: Rational.zero) : null,
  Name(:final name) =>
    name == variable ? (intercept: Rational.zero, slope: Rational.one) : null,
  Unary(op: '-', :final operand) => _scale(straightLine(operand, variable), -Rational.one),
  Binary(op: '+', :final left, :final right) => _add(
    straightLine(left, variable),
    straightLine(right, variable),
    Rational.one,
  ),
  Binary(op: '-', :final left, :final right) => _add(
    straightLine(left, variable),
    straightLine(right, variable),
    -Rational.one,
  ),
  Binary(op: '*', :final left, :final right) => _multiply(
    straightLine(left, variable),
    straightLine(right, variable),
  ),
  Binary(op: '/', :final left, :final right) => _divide(
    straightLine(left, variable),
    straightLine(right, variable),
  ),
  _ => null,
};

({Rational intercept, Rational slope})? _scale(
  ({Rational intercept, Rational slope})? line,
  Rational by,
) => line == null ? null : (intercept: line.intercept * by, slope: line.slope * by);

({Rational intercept, Rational slope})? _add(
  ({Rational intercept, Rational slope})? left,
  ({Rational intercept, Rational slope})? right,
  Rational sign,
) => left == null || right == null
    ? null
    : (
        intercept: left.intercept + right.intercept * sign,
        slope: left.slope + right.slope * sign,
      );

/// A product is a straight line only when ONE side carries the variable: `x * x`
/// is a curve, and reporting a line for it would be wrong rather than
/// approximate.
({Rational intercept, Rational slope})? _multiply(
  ({Rational intercept, Rational slope})? left,
  ({Rational intercept, Rational slope})? right,
) {
  if (left == null || right == null) return null;
  if (left.slope.isZero) return _scale(right, left.intercept);
  if (right.slope.isZero) return _scale(left, right.intercept);
  return null;
}

({Rational intercept, Rational slope})? _divide(
  ({Rational intercept, Rational slope})? left,
  ({Rational intercept, Rational slope})? right,
) {
  if (left == null || right == null) return null;
  if (!right.slope.isZero || right.intercept.isZero) return null;
  return _scale(left, Rational.one / right.intercept);
}
