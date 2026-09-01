// Pure Dart. Nothing under lib/core/ may import Flutter or a third-party
// package.
//
// Display weight: how a membership alters a member. Don's ruling, verbatim:
// "if I can describe with basic algebra how membership should alter a member,
// then I should be able to do that." A weight formula is an expression in the
// one math (`math.dart`) with one bound name, the incoming weight, handing
// back the weight this ring passes onward.
//
// Nothing here reaches a document, an engine, or an index. Everything this
// module needs arrives as plain values -- which is what lets `composeWeight`
// below be the chain contract itself rather than a traversal that happens to
// produce one.

import 'exact.dart';
import 'falloff.dart';
import 'math.dart';

/// The one name a weight formula can read: the weight arriving from the base
/// verdict or from every prior ring, in chain order. Exported so every
/// caller that builds or displays a formula names it the same way instead of
/// restating the literal.
const String weightVariable = 'w';

/// The other name a weight formula may read: SIGNED DAYS FROM THE INSTANT THE
/// PROJECTOR IS LOOKING FROM to this object's home -- positive ahead, negative
/// behind, zero while the object is happening.
///
/// Proximity is not a second weight mechanism, and nothing here special-cases
/// it: it is one more bound value in the one math, so `display.proximity` and
/// `display.weight` are the same kind of authored sentence and a projector that
/// wants near things loud writes it as arithmetic rather than asking for a knob.
/// A formula that never names it is unaffected.
const String proximityVariable = 'days';

final RegExp _plainNumber = RegExp(r'^[+-]?(?:\d+(?:\.\d+)?|\.\d+)$');

/// Is this authored text a bare number rather than a formula?
///
/// THE ONE TEST (ISSUES 9.1). Every knob that offers sugar -- a plain number
/// meaning something specific to that knob -- has to ask the same question the
/// same way, or two knobs disagree about whether `.5` is a number. Exported
/// rather than re-written per knob, which is what `display.proximity` was doing
/// with its own copy of this expression.
bool isPlainWeightNumber(String text) => _plainNumber.hasMatch(text);

/// THE SUGAR RULE, and the migration it exists for: every `display.weight`
/// authored before formulas existed is a plain number `n`, and its meaning was
/// always "multiply the incoming weight by n". Turning that same number into
/// `w * (n)` reproduces that meaning exactly -- no document is rewritten and
/// no record changes shape. A non-numeric string is already an authored
/// formula and is used verbatim. Nothing authored (null, blank) is the
/// identity `w`, which is also what a missing knob has always meant.
///
/// An exact [Rational] skips the plain-number test deliberately: `1/3` prints
/// as a fraction, which is not a decimal literal, and treating it as a
/// verbatim formula would silently drop the `w`.
String normalizeWeightFormula(Object? value) {
  if (value == null) return weightVariable;
  if (value is Rational) return '$weightVariable * (${value.toJson()})';
  if (value is num) {
    return value.isFinite ? '$weightVariable * ($value)' : weightVariable;
  }
  final text = value.toString().trim();
  if (text.isEmpty) return weightVariable;
  return isPlainWeightNumber(text) ? '$weightVariable * ($text)' : text;
}

/// Evaluates one ring's authored weight (a number, a formula string, or
/// nothing) against the weight arriving into it.
///
/// "A broken knob must never silently change what renders": an unparseable
/// formula, an unknown name, a fuel or size breach, a truth value where a
/// number belongs, or a negative result all return [incoming] UNCHANGED --
/// the same no-op a ring with no authored weight produces. Deliberately
/// silent at this layer; [validateWeightFormula] is where a caller asks "is
/// this valid" so it can tell an author BEFORE the formula ever reaches this
/// fallback. Zero is not a failure: a frame is allowed to demote to nothing.
Rational applyWeightFormula(
  Object? formula,
  Rational incoming, {
  Map<String, Rational> environment = const {},
}) => evaluateWeightFormula(formula, incoming, environment: environment) ?? incoming;

/// The same evaluation, answering NULL where [applyWeightFormula] answers
/// [incoming]: the formula would not read, or came to something that is not a
/// weight.
///
/// ONE EVALUATOR (ISSUES 9.1). The two callers want the same arithmetic and
/// differ only in what they do about a refusal -- a ring in the blessed chain
/// passes the weight through untouched, while an OPTIONAL ring omits itself
/// rather than reporting a step that did nothing. Written once so a knob cannot
/// quietly acquire its own idea of what a weight formula is.
Rational? evaluateWeightFormula(
  Object? formula,
  Rational incoming, {
  Map<String, Rational> environment = const {},
}) {
  try {
    final result = evaluateSource(
      normalizeWeightFormula(formula),
      // The incoming weight wins any collision: `w` is this function's own
      // contract and an environment cannot redefine it out from under a formula.
      Env(values: {...environment, weightVariable: incoming}),
    );
    return result is! Rational || result.isNegative ? null : result;
  } catch (_) {
    return null;
  }
}

/// Authoring-time validation: parses and evaluates the formula just typed
/// (sugar included) against a probe weight of 1, so a bad formula gets a real
/// message at submit time instead of silently doing nothing the next time
/// something renders. This checks that the formula RUNS and produces a
/// number, not that it behaves for every possible incoming weight -- a
/// formula can be well-formed and still divide by zero for some specific `w`,
/// which is a runtime concern [applyWeightFormula] already guards.
({bool valid, String? error}) validateWeightFormula(Object? source) {
  try {
    final result = evaluateSource(
      normalizeWeightFormula(source),
      Env(values: {weightVariable: Rational.one}),
    );
    if (result is! Rational) {
      return (valid: false, error: 'A weight formula must produce a number.');
    }
    return (valid: true, error: null);
  } on MathRefusal catch (refusal) {
    return (valid: false, error: refusal.toString());
  }
}

/// The single place that decides what gets STORED for a given piece of typed
/// input, so every authoring surface makes the same call for the same text --
/// including the storage-economy rule that an input meaning identity (blank,
/// `1`, or `w` itself) DELETES the field rather than keeping a redundant
/// no-op.
///
/// Returns the value to assign: an exact [Rational] for sugar, the [String]
/// verbatim for a formula, or null when the field should be deleted. Throws a
/// [MathRefusal] whose message is meant to be shown to the author when the
/// input cannot be stored.
Object? resolveAuthoredWeight(String? rawInput) {
  final input = (rawInput ?? '').trim();
  if (input.isEmpty || input == weightVariable) return null;
  if (isPlainWeightNumber(input)) {
    final numeric = Rational.parse(input);
    if (numeric.isNegative) {
      throw const MathRefusal('Display weight must be zero or greater.');
    }
    // Identity is a VALUE, not a spelling: `1`, `1.0`, `1.00` and `+1` all
    // mean "no change", so every one of them deletes the field.
    return numeric == Rational.one ? null : numeric;
  }
  final validation = validateWeightFormula(input);
  if (!validation.valid) {
    throw MathRefusal('Display weight formula is invalid: ${validation.error}');
  }
  return input;
}

/// Groups default to a promotion so objects that cross more frames read as
/// more prominent. Narrowed to newly created GROUP and IMPORTANCE frames,
/// never calendars: every event already belongs to a calendar, so boosting
/// every calendar uniformly promotes nothing relative to anything else. This
/// feeds a blank authoring form's INITIAL value only; it is never applied to,
/// or migrated onto, a frame that already exists.
Rational? defaultWeightForNewFrame(String kind) =>
    kind == 'group' || kind == 'importance' ? _promotion : null;

final Rational _promotion = Rational.fromInt(3, 2);

/// One ring of the weight chain: something that has authored math and a graph
/// distance from the object whose weight is being derived.
///
/// - `id` is stable; ties at equal `distance` break on it -- meaningless, just
///   stable.
/// - `formula` is the authored value: a number, a formula string, or nothing.
/// - `distance` is measured in connections. Nearest applies first.
/// - `negated` marks a NOT-term. NOT-terms gate visibility and NEVER modify
///   weight; carrying the mark here enforces that in one place instead of
///   trusting every caller to filter first.
typedef WeightRing = ({String id, Object? formula, int distance, bool negated});

/// A ring with the two common defaults filled in, so a caller states only
/// what it means.
WeightRing weightRing(String id, Object? formula, {int distance = 1, bool negated = false}) =>
    (id: id, formula: formula, distance: distance, negated: negated);

/// One applied ring, in order, for the inspector's derivation explainer:
/// ruling 10 requires that it "shows every ring." `via` is the math applied
/// at this ring as text; `weight` is what leaves it.
typedef WeightStep = ({String id, String via, Rational weight});

/// The step ids for the two rings that are not frames.
const String ownWeightRing = 'object';
const String falloffWeightRing = 'falloff';

typedef WeightDerivation = ({Rational weight, List<WeightStep> rings});

/// THE BLESSED CHAIN (Don, 2026-08-27, ruling 10) -- nesting, inside out:
///
///   1. the object's own authored math ([own]);
///   2. connected modifying frames by INCREASING graph distance, nearest
///      first ([frames]);
///   3. ties at equal distance broken deterministically by stable id;
///   4. the projecting frame or expression LAST among frames ([projector]) --
///      uniform monotone math applied last cannot reorder the view, which is
///      exactly what "matters least" requires;
///   5. apparent-magnitude falloff as the projector's own closing step
///      ([falloffDistance]), multiplicatively, per JC-8.
///
/// Order is contract, not detail: mixed `+` and `*` do not commute, so
/// `(w + 1) * 2` is not `w * 2 + 1` and which ring goes first is observable.
/// Weight is projection-relative by design -- the same object weighs
/// differently seen from different projectors, and that is the point.
///
/// THE SEAM: no graph is walked here. Neither the projection engine nor the
/// connection indexes exist yet, and when they do, traversal is theirs. This
/// function takes a PRECOMPUTED ordering input -- rings that already know
/// their distance -- and owns the sort, the fold, and the closing step. A
/// caller supplies distances; it does not supply order.
WeightDerivation composeWeight({
  required Rational base,
  Object? own,
  Iterable<WeightRing> frames = const [],
  WeightRing? projector,
  Rational? falloffDistance,
  Rational? halfDistanceDays,
  Map<String, Rational> environment = const {},
}) {
  final rings = <WeightStep>[];
  var weight = base;
  void apply(String id, Object? formula) {
    weight = applyWeightFormula(formula, weight, environment: environment);
    rings.add((id: id, via: normalizeWeightFormula(formula), weight: weight));
  }

  apply(ownWeightRing, own);
  final ordered = frames.where((ring) => !ring.negated).toList()
    ..sort(
      (a, b) => a.distance != b.distance ? a.distance.compareTo(b.distance) : a.id.compareTo(b.id),
    );
  for (final ring in ordered) {
    apply(ring.id, ring.formula);
  }
  if (projector != null && !projector.negated) {
    apply(projector.id, projector.formula);
  }
  if (falloffDistance != null) {
    final half = halfDistanceDays ?? defaultHalfDistanceDays;
    weight = apparentMagnitude(weight, falloffDistance, halfDistance: half);
    final gap = falloffDistance.abs().toJson();
    rings.add((
      id: falloffWeightRing,
      via: 'w * ${half.toJson()} / (${half.toJson()} + $gap)',
      weight: weight,
    ));
  }
  return (weight: weight, rings: rings);
}
