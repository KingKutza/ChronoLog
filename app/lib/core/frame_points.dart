// A FRAME'S OWN POINTS.
//
// Pure Dart. Nothing under lib/core/ may import Flutter or a third-party package.
//
// Ruled 2026-08-31, dissolving succession: "A staple connects n points and says
// each is the same as the other. No exceptions No special cases No extra
// riders." Era 1 and era 2 are frames with authored bases, and each basis either
// does or does not have the power to define a point. Where both can, the staple
// connects those two points -- "one happens to be the end and the other the
// beginning, this case is not special for all it is common, the end of 1 could
// just as easily connect to three weeks into 2." Where a basis cannot label a
// point along the line, the staple connects INCLUSIVELY: "the end of 1 staples
// to all of 2."
//
// So a frame end says WHICH OF ITS OWN POINTS it touches, exactly as an object
// end always could, and this file is the whole of that vocabulary.
//
// A POINT IS AN EXPRESSION, NOT A NAME. Ruled the same night: "Why was a named
// point ever a primitive? ... a point is an expression, a name is only a label on
// one." So `beginning` and `end` are not keywords here -- they are ordinary ONE
// MATH names, resolved against the frame's own extent by [pointEnv], and every
// other point a person can write ("three weeks into 2") is the same expression
// language with arithmetic in it. There is no table of legal points, and
// [pointSpellings] holds exactly the one word that is not an expression at all.
//
// A POINT HAS A SIZE. "n points on objects or frames are one point, where a
// point is of size 0, all, or some One Math value between." So the general form
// is a FROM and a TO, and a point of size zero is the degenerate spelling where
// they are the same expression. `all` is the spelling where they are the frame's
// own two bounds -- which is why the all-point needs no machinery of its own.
//
// THE ENGINE IS math.dart's. There is no second parser and no second evaluator
// here; this file only says what the names mean.

import 'eras.dart';
import 'exact.dart';
import 'math.dart';

/// A frame's own extent in exact days: where it begins, and where it runs out.
///
/// [end] is EXCLUSIVE -- the instant the frame runs out rather than the last
/// instant inside it. That is what makes "the end of 1 meets the beginning of 2"
/// arithmetic rather than a rule: for two eras that meet, both expressions
/// resolve to the one same number, and nothing has to reconcile them.
///
/// Either bound is null for a frame open at that end, and asking for a bound
/// that is null refuses in words rather than answering a fabricated number.
typedef FrameExtent = ({Rational? beginning, Rational? end});

/// The two names a point expression may use for the frame's own bounds.
///
/// Named constants rather than literals because ONE derivation reads the
/// SPELLING instead of the number: era ordering has to know which bound an end
/// names before any extent exists to evaluate against, since the ordering is
/// what produces the extents. Everywhere else these are just names in [pointEnv]
/// and nothing distinguishes them from a unit name or an authored one.
const String pointBeginning = 'beginning';
const String pointEnd = 'end';

/// One authored point, as the two expressions every point always is.
typedef PointSource = ({String from, String to});

/// The spellings that are not expressions.
///
/// `all` is a size, not a position, so it is the one word the expression
/// language cannot carry -- it says "from this frame's beginning to its end",
/// which is what this expands it to. Open, and read before anything is parsed:
/// a word absent from here is simply parsed as an expression, so adding a
/// shorthand later takes an entry and nothing else.
const Map<String, PointSource> pointSpellings = {
  'all': (from: pointBeginning, to: pointEnd),
};

/// Which of its own bounds a point's SPELLING claims, read off the text.
///
/// Not off the number: the era chain asks this to derive the ordering that
/// produces the extents the numbers would need. `beginning` touches the
/// beginning, `end` touches the end, `all` touches both, and an expression that
/// computes a point somewhere along the line touches neither -- "three weeks
/// into 2" is a perfectly good identification and it is not a boundary claim.
typedef PointBounds = ({bool beginning, bool end});

const PointBounds noBounds = (beginning: false, end: false);

PointBounds boundsNamed(PointSource? source) => source == null
    ? noBounds
    : (
        beginning: source.from.trim() == pointBeginning,
        end: source.to.trim() == pointEnd,
      );

/// Reads whatever the file carries under `point` into the general form.
///
/// A string is a point of size zero -- the same expression at both ends --
/// unless it is one of the [pointSpellings]. A map carries `from` and `to`
/// outright, and a map naming only one of them means a point of size zero
/// there. Anything else names no point, and answering null is what lets a
/// spelling this build cannot read round-trip untouched instead of being
/// guessed at.
PointSource? pointSourceOf(Object? source) {
  if (source is Map) {
    final from = declaredText(source['from']);
    final to = declaredText(source['to']);
    if (from.isEmpty && to.isEmpty) return null;
    return (from: from.isEmpty ? to : from, to: to.isEmpty ? from : to);
  }
  final text = declaredText(source);
  if (text.isEmpty) return null;
  return pointSpellings[text] ?? (from: text, to: text);
}

/// The point a frame end that says nothing has always meant.
///
/// A frame end carrying no position at all says nothing about WHERE on its own
/// sheet -- except what the staple's own order says, which is the whole of what
/// an era `succession` record ever was: the first sheet it pierces FINISHES at
/// this point and every other BEGINS there. Read here as an ordinary point
/// expression, with no kind consulted anywhere, so an existing record keeps its
/// meaning as one SPELLING of the general staple rather than as a case.
PointSource impliedPoint(int frameEndOrdinal) =>
    frameEndOrdinal == 0 ? const (from: pointEnd, to: pointEnd) : const (from: pointBeginning, to: pointBeginning);

/// The leaf environment a point expression is read in: the frame's own bounds,
/// plus whatever else the caller's law can name (its unit lengths, so "three
/// weeks in" is `beginning + 3 * week` rather than a day count the author has to
/// do the arithmetic for).
///
/// A bound the frame does not have is simply ABSENT rather than zero, so an
/// expression naming it refuses by name instead of answering a fabricated
/// instant.
Env pointEnv(FrameExtent extent, {Resolver? units}) => Env(
  values: {
    if (extent.beginning case final Rational at) pointBeginning: at,
    if (extent.end case final Rational at) pointEnd: at,
  },
  resolver: units,
);

/// The region an authored point names, in exact days.
///
/// Both ends are evaluated through math.dart -- the one evaluator -- and a
/// refusal from it is re-raised as a [LawRefusal] so the sentence reaches the
/// author through the same seam every other coordinate failure does.
///
/// The two ends are NOT sorted. A point authored from a later expression to an
/// earlier one is a fact about what was written, and quietly swapping them would
/// be the model inventing an orientation nobody authored.
({Rational from, Rational to}) evaluatePoint(
  PointSource source,
  FrameExtent extent, {
  Resolver? units,
  String? subject,
}) {
  final env = pointEnv(extent, units: units);
  return (
    from: _evaluate(source.from, env, subject),
    to: source.to == source.from
        ? _evaluate(source.from, env, subject)
        : _evaluate(source.to, env, subject),
  );
}

Rational _evaluate(String source, Env env, String? subject) {
  final Object value;
  try {
    value = evaluateSource(source, env);
  } on MathRefusal catch (refusal) {
    throw LawRefusal(
      '${subject ?? 'This point'} is written as "$source", and ${refusal.message}.',
    );
  }
  if (value is! Rational) {
    throw LawRefusal(
      '${subject ?? 'This point'} is written as "$source", which answers true or'
      ' false rather than a place on the line.',
    );
  }
  return value;
}
