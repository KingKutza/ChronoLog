// Pure Dart. Nothing under lib/core/ may import Flutter or a third-party
// package.
//
// THE ONE MATH (Don, 2026-08-27): "one math, used everywhere." The boolean
// projection algebra, weight formulas, falloff composition, and the time-flow
// functions time travel will be re-founded on are ONE expression language,
// ONE parser, ONE evaluator. This file is that language and nothing else: it
// knows about numbers, truth values, and names. It does not know what a frame
// is, what a connection is, or what a weight means.
//
// The grammar is basic algebra, in Don's words: "if I can describe with basic
// algebra how membership should alter a member, then I should be able to do
// that." What died with the narrowing (strings, arrays, records,
// comprehensions, modules, `fn`, member access, transcendentals, comments)
// died because nothing described membership with it.
//
// THE LEAF SEAM is [Env]: every open-vocabulary name -- the weight variable
// `w`, a frame name in a projection expression, a connection predicate -- is
// just an identifier resolved by the caller. `w * 1.5` and
// `work and not done` are the same tree walked by the same evaluator; the
// difference lives entirely in what the resolver hands back. That is what
// makes one math one math rather than three languages that rhyme.

import 'exact.dart';

/// A refusal, not an error: the formula could not be read or could not be
/// evaluated, and says where. Every refusal raised here is this type, so a
/// caller that must never propagate one (see `weight.dart`'s
/// [applyWeightFormula]) has exactly one thing to catch.
class MathRefusal implements Exception {
  final String message;

  /// Character offset in the source, or -1 for a refusal with no position.
  final int position;

  const MathRefusal(this.message, [this.position = -1]);

  @override
  String toString() => position < 0 ? message : '$message at $position';
}

/// Evaluation fuel: one unit per node visited. A formula is authored by a
/// person and read on the projection hot path, so the bound is generous
/// enough that no honest formula meets it and small enough that no formula
/// can hang a frame.
const int defaultFuel = 250000;

/// Nesting depth cap, counted in expression levels rather than parser frames.
/// The JS parser's cap existed so `((((...1...))))` refused cleanly instead of
/// overflowing the stack; that stays true here and is pinned by the spec.
const int maxNestingDepth = 500;

/// Numeric size cap, in bits of numerator or denominator. The JS runtime
/// counted decimal digits (`maxIntegerDigits`, 4096); bits cost nothing to
/// read off a [BigInt] where decimal length costs a full conversion, and the
/// purpose -- refuse before an exact value eats the heap -- is unchanged.
const int maxValueBits = 16384;

/// Exponent magnitude cap, checked before any power is computed.
const int maxExponent = 65536;

// --- The tree ----------------------------------------------------------------

/// A parsed expression. Public because analysis rides on it: the projection
/// engine reads [identifiersOf] to learn which frames a term names, and the
/// inspector's derivation explainer prints it back.
///
/// [at] is the source offset the node started at, so a refusal raised while
/// evaluating deep inside a tree still points at the text that caused it.
sealed class Expr {
  final int at;
  const Expr(this.at);
}

/// A number or a truth value. [value] is a [Rational] or a [bool] -- never a
/// host `double`, and never anything else.
class Lit extends Expr {
  final Object value;
  const Lit(this.value, super.at);
  @override
  String toString() => '$value';
}

class Name extends Expr {
  final String name;
  const Name(this.name, super.at);
  @override
  String toString() => name;
}

class Unary extends Expr {
  /// `-` or `not`.
  final String op;
  final Expr operand;
  const Unary(this.op, this.operand, super.at);
  @override
  String toString() => op == 'not' ? '(not $operand)' : '(-$operand)';
}

class Binary extends Expr {
  final String op;
  final Expr left, right;
  const Binary(this.op, this.left, this.right, super.at);
  @override
  String toString() => '($left $op $right)';
}

class Cond extends Expr {
  final Expr condition, yes, no;
  const Cond(this.condition, this.yes, this.no, super.at);
  @override
  String toString() => '($condition ? $yes : $no)';
}

/// A call to one of the five builtins. The callee is a name, not an
/// expression, because nothing in this language produces a function -- which
/// is also why a builtin's name never appears in [identifiersOf].
class Call extends Expr {
  final String name;
  final List<Expr> args;
  const Call(this.name, this.args, super.at);
  @override
  String toString() => '$name(${args.join(', ')})';
}

/// The subexpressions of a node, in evaluation order. One place to walk from,
/// so no consumer -- analysis, the derivation explainer, a future optimizer --
/// re-enumerates the node shapes.
List<Expr> childrenOf(Expr node) => switch (node) {
  Lit() || Name() => const [],
  Unary(:final operand) => [operand],
  Binary(:final left, :final right) => [left, right],
  Cond(:final condition, :final yes, :final no) => [condition, yes, no],
  Call(:final args) => args,
};

/// Every open-vocabulary name the expression reads. The projection engine
/// wants this to know which frames a term depends on before evaluating it.
Set<String> identifiersOf(Expr expression) => {
  if (expression is Name) expression.name,
  for (final child in childrenOf(expression)) ...identifiersOf(child),
};

// --- Reading -----------------------------------------------------------------

typedef _Tok = ({String kind, String text, int at});

/// The precedence table, one level per `|` segment, loosest first, so level 4
/// is the empty one: that is `not`, a prefix with no infix form. `not` sitting
/// between `and` and the comparisons is what a person means by
/// `not done and urgent`. Unary `-` binds tighter than `^` (so `-2 ^ 2` is 4),
/// matching the JS parser this replaces.
const String _levels = 'or|xor|and||< <= > >= == !=|+ -|* / %|^';

final Map<String, int> _precedence = {
  for (final (index, ops) in _levels.split('|').indexed)
    for (final op in ops.split(' '))
      if (op.isNotEmpty) op: index + 1,
};

const _arity = {'min': 2, 'max': 2, 'abs': 1, 'floor': 1, 'ceil': 1};

/// Words, not symbols: this is algebra a person writes, so the boolean
/// operators read as English and case does not matter. `true`/`false` are
/// literals here for the same reason they were builtins in the JS runtime.
const Set<String> _keywords = {'and', 'or', 'not', 'xor', 'true', 'false'};

/// One pass over the source: whitespace, a number, a name, or an operator.
/// Longest alternatives first, so `1e5` is one number and `<=` is one
/// operator. Anything this does not match is a character the language has no
/// meaning for.
final RegExp _token = RegExp(
  r'(\s+)|((?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?)|([A-Za-z_]\w*)'
  r'|(<=|>=|==|!=|[-+*/%^<>?:(),])',
);

class _Parser {
  final String source;
  int index = 0;
  int depth = 0;
  _Tok? _ahead;

  _Parser(this.source);

  _Tok _read() {
    while (true) {
      if (index >= source.length) return (kind: 'eof', text: '', at: index);
      final at = index;
      final match = _token.matchAsPrefix(source, at);
      if (match == null) {
        throw MathRefusal('Unexpected character "${source[at]}"', at);
      }
      index = match.end;
      if (match[1] != null) continue;
      if (match[2] != null) return (kind: 'num', text: match[2]!, at: at);
      if (match[3] == null) return (kind: 'op', text: match[4]!, at: at);
      final lower = match[3]!.toLowerCase();
      return _keywords.contains(lower)
          ? (kind: 'op', text: lower, at: at)
          : (kind: 'name', text: match[3]!, at: at);
    }
  }

  _Tok get peek => _ahead ??= _read();

  _Tok take() {
    final token = peek;
    _ahead = null;
    return token;
  }

  bool _eat(String text) {
    if (peek.text != text) return false;
    take();
    return true;
  }

  void _expect(String text) {
    final token = take();
    if (token.text != text) {
      throw MathRefusal('Expected $text, found ${_show(token)}', token.at);
    }
  }

  String _show(_Tok t) => t.kind == 'eof' ? 'end of formula' : t.text;

  /// A full expression, ternary included. The ternary is the loosest form and
  /// right-associative, so `a ? b : c ? d : e` reads as `a ? b : (c ? d : e)`.
  Expr expression() {
    final left = binary(0);
    if (!_eat('?')) return left;
    final yes = expression();
    _expect(':');
    return Cond(left, yes, expression(), left.at);
  }

  /// Precedence climbing. The depth guard lives here rather than in
  /// [expression] because every recursive path -- parentheses, ternary arms,
  /// call arguments, a right operand, a prefix operand -- passes through it,
  /// so one counter bounds the whole tree.
  Expr binary(int minimum) {
    if (++depth > maxNestingDepth) {
      throw MathRefusal('Formula expression too deeply nested', peek.at);
    }
    try {
      var left = _prefix();
      while (true) {
        final token = peek;
        final precedence = token.kind == 'op' ? _precedence[token.text] : null;
        if (precedence == null || precedence < minimum) return left;
        take();
        // `^` is right-associative; everything else left.
        final right = binary(precedence + (token.text == '^' ? 0 : 1));
        left = Binary(token.text, left, right, token.at);
      }
    } finally {
      depth--;
    }
  }

  Expr _prefix() {
    final token = take();
    if (token.kind == 'num') return Lit(_literal(token), token.at);
    if (token.kind == 'name') {
      return peek.text == '(' ? _call(token) : Name(token.text, token.at);
    }
    if (token.text == 'true' || token.text == 'false') {
      return Lit(token.text == 'true', token.at);
    }
    if (token.text == '-') return Unary('-', binary(9), token.at);
    if (token.text == 'not') return Unary('not', binary(5), token.at);
    if (token.text == '(') {
      final inner = expression();
      _expect(')');
      return inner;
    }
    throw MathRefusal('Unexpected ${_show(token)}', token.at);
  }

  /// The five builtins are the only callable names, and their arity is fixed:
  /// nothing in this language produces a function, so an unknown name before
  /// `(` is a refusal rather than a lookup.
  Expr _call(_Tok token) {
    final wanted = _arity[token.text];
    if (wanted == null) {
      throw MathRefusal('Unknown formula function ${token.text}', token.at);
    }
    take();
    final args = [expression()];
    while (_eat(',')) {
      args.add(expression());
    }
    _expect(')');
    if (args.length != wanted) {
      throw MathRefusal('${token.text} takes $wanted', token.at);
    }
    return Call(token.text, args, token.at);
  }

  /// An exponent is checked before parsing, not after: `1e999999999` would
  /// otherwise allocate the heap on its way to being refused.
  Rational _literal(_Tok token) {
    final e = token.text.toLowerCase().indexOf('e');
    final power = e < 0 ? 0 : int.tryParse(token.text.substring(e + 1));
    if (power == null || power.abs() > maxExponent) {
      throw MathRefusal('Formula numeric size limit exceeded', token.at);
    }
    return _bounded(Rational.parse(token.text), token.at);
  }
}

/// Reads one expression and refuses anything left over. Trailing garbage
/// (`1 + 1) + 2`, `2 2`) is a refusal rather than a silent truncation: a
/// formula the author is still typing must not evaluate as its own prefix.
Expr parse(String source) {
  final parser = _Parser(source);
  final expression = parser.expression();
  final trailing = parser.peek;
  if (trailing.kind == 'eof') return expression;
  throw MathRefusal('Unexpected trailing input ${trailing.text}', trailing.at);
}

// A weight formula is evaluated once per contributing ring per object per
// frame, so the same handful of source strings is parsed thousands of times a
// render. Memoized by source, and cleared wholesale rather than grown without
// bound, because the keys are authored text and a leak here is a leak per
// keystroke.
final Map<String, Expr> _parsed = {};

Expr parseCached(String source) {
  if (_parsed.length > 512) _parsed.clear();
  return _parsed[source] ??= parse(source);
}

// --- Evaluating --------------------------------------------------------------

/// Resolves an open-vocabulary name, or returns null for "I do not know that
/// name" -- which the evaluator turns into a refusal rather than a zero.
typedef Resolver = Object? Function(String name);

/// The leaf environment. [values] answers first, then [resolver]; a name
/// neither knows is unknown. There is no ambient scope, no parent chain, and
/// no host access of any kind -- a formula sees exactly what it is handed.
class Env {
  final Map<String, Object> values;
  final Resolver? resolver;

  const Env({this.values = const {}, this.resolver});

  Object? lookup(String name) => values[name] ?? resolver?.call(name);
}

class _Fuel {
  int left;
  _Fuel(this.left);
}

/// Evaluates [expression] to a [Rational] or a [bool]. Strictly typed: there
/// is no truthiness and no coercion, so comparing a truth value to a number
/// or adding one is a refusal that names the position -- meaning is authored,
/// and a type confusion is not a meaning.
Object evaluate(Expr expression, Env env, {int fuel = defaultFuel}) =>
    _eval(expression, env, _Fuel(fuel));

/// Parse (memoized) and evaluate in one step.
Object evaluateSource(String source, Env env, {int fuel = defaultFuel}) =>
    evaluate(parseCached(source), env, fuel: fuel);

Object _eval(Expr node, Env env, _Fuel fuel) {
  if (--fuel.left < 0) {
    throw MathRefusal('Formula fuel limit exceeded', node.at);
  }
  final at = node.at;
  return switch (node) {
    Lit(:final value) => value,
    Name(:final name) => env.lookup(name) ?? (throw MathRefusal('Unknown formula name: $name', at)),
    Unary(:final op, :final operand) =>
      op == 'not'
          ? !_truth(_eval(operand, env, fuel), at)
          : _bounded(-_number(_eval(operand, env, fuel), at), at),
    Cond(:final condition, :final yes, :final no) => _eval(
      _truth(_eval(condition, env, fuel), at) ? yes : no,
      env,
      fuel,
    ),
    Call(:final name, :final args) => _builtin(name, [
      for (final argument in args) _number(_eval(argument, env, fuel), argument.at),
    ]),
    Binary() => _binary(node, env, fuel),
  };
}

Rational _builtin(String name, List<Rational> a) => switch (name) {
  'min' => a[0] <= a[1] ? a[0] : a[1],
  'max' => a[0] >= a[1] ? a[0] : a[1],
  'abs' => a[0].abs(),
  'floor' => Rational(a[0].floor()),
  _ => Rational(a[0].ceil()),
};

Object _binary(Binary node, Env env, _Fuel fuel) {
  final at = node.at;
  // `and`/`or` short-circuit, so a guard clause can protect the arm behind it
  // (`half > 0 and w / half > 1`) the way an author expects.
  if (node.op == 'and' || node.op == 'or') {
    final left = _truth(_eval(node.left, env, fuel), at);
    if (left == (node.op == 'or')) return left;
    return _truth(_eval(node.right, env, fuel), at);
  }
  final left = _eval(node.left, env, fuel);
  final right = _eval(node.right, env, fuel);
  // One truth value on either side makes this a truth-value operation, and
  // `_truth` refuses the other side if it is a number: a number and a truth
  // value are never equal, never ordered, and never added.
  if (left is bool || right is bool) {
    final a = _truth(left, at), b = _truth(right, at);
    return switch (node.op) {
      '==' => a == b,
      '!=' || 'xor' => a != b,
      _ => throw MathRefusal('Truth values do not order or add', at),
    };
  }
  final a = _number(left, at), b = _number(right, at);
  return switch (node.op) {
    '<' => a < b,
    '<=' => a <= b,
    '>' => a > b,
    '>=' => a >= b,
    // `Rational` is stored reduced, so structural equality already agrees
    // with `compareTo`.
    '==' => a == b,
    '!=' => a != b,
    '+' => _bounded(a + b, at),
    '-' => _bounded(a - b, at),
    '*' => _bounded(a * b, at),
    '/' => _bounded(a / _nonZero(b, at), at),
    '%' => _bounded(a % _nonZero(b, at), at),
    '^' => _bounded(a.pow(_wholeExponent(a, b, at)), at),
    // `xor` reaches here only with numbers on both sides.
    _ => throw MathRefusal('Expected a truth value, found a number', at),
  };
}

int _wholeExponent(Rational base, Rational exponent, int at) {
  if (exponent.d != BigInt.one) {
    throw MathRefusal('An exponent must be a whole number', at);
  }
  if (exponent.abs() > _exponentCap) {
    throw MathRefusal('Formula numeric size limit exceeded', at);
  }
  if (base.isZero && exponent.isNegative) _nonZero(base, at);
  return exponent.n.toInt();
}

final Rational _exponentCap = Rational.fromInt(maxExponent);

Rational _nonZero(Rational value, int at) =>
    value.isZero ? throw MathRefusal('Division by zero', at) : value;

Rational _number(Object value, int at) =>
    value is Rational ? value : throw MathRefusal('Expected a number, found a truth value', at);

bool _truth(Object value, int at) =>
    value is bool ? value : throw MathRefusal('Expected a truth value, found a number', at);

Rational _bounded(Rational value, int at) =>
    value.n.bitLength > maxValueBits || value.d.bitLength > maxValueBits
    ? throw MathRefusal('Formula numeric size limit exceeded', at)
    : value;
