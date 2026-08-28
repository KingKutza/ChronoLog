// THE ONE OVERSCALE BUDGET (ruling 9, Don 2026-08-27).
//
// The web build carried thirteen scattered truncation caps -- 800, 900, 600,
// 350, 260, 140, 80, 48, 24, 12, 8, 4, 3 -- each hand-picked per lens, none of
// them derived from anything. They are one derivation now: a lens hands in the
// area it has and the footprint of one mark, and screen space says how many
// marks fit. Apparent magnitude and composed weight say WHICH ones; nothing here
// picks by identity.
//
// "If it is not usable at 500 calendars it is improperly built for 3."
//
// WHAT DOES NOT FIT IS A LOWER BOUND, never a silent drop: the remainder becomes
// an "N+" sigil, because the field knows only that at least one more existed.

import 'tunables.dart';

/// What an area can hold, and what to ask the engine for.
///
/// [marks] is what will be drawn. [queryBudget] is deliberately larger: the
/// query has to see more than the surface can draw or weight has nothing to
/// choose between, and `truncated` on the result stays honest about the rest.
typedef Capacity = ({int marks, int queryBudget});

/// Marks that fit in [width] x [height] at the footprint the caller names.
///
/// [stackDepth] is how many marks deep the surface will overlap them -- lanes on
/// a rail, pips in a cell -- and it is a tunable like everything else. The floor
/// keeps a tiny tile from asking for zero facts and rendering an empty document
/// that is not empty.
Capacity capacityOf(
  double width,
  double height,
  Tunable? read, {
  String widthKey = 'capacity.markWidth',
  String heightKey = 'capacity.markHeight',
  String depthKey = 'capacity.stackDepth',
}) {
  final markWidth = pixels(read, widthKey), markHeight = pixels(read, heightKey);
  final across = markWidth <= 0 ? 1 : width / markWidth;
  final down = markHeight <= 0 ? 1 : height / markHeight;
  final depth = pixels(read, depthKey);
  final floor = pixels(read, 'capacity.floor');
  final fits = across * down * (depth <= 0 ? 1 : depth);
  final marks = (fits < floor ? floor : fits).floor();
  final multiple = pixels(read, 'capacity.queryMultiple');
  return (marks: marks, queryBudget: (marks * (multiple < 1 ? 1 : multiple)).ceil());
}

/// What a capacity admits, in the order the caller ranked it -- by composed
/// weight with falloff already applied, which is the only ranking there is.
///
/// [hidden] plus [truncated] is the honest floor: `shown+` when the query itself
/// was cut short OR the area was, and a plain count only when everything a
/// query found is on screen.
typedef Admitted<T> = ({List<T> drawn, int hidden, bool truncated});

Admitted<T> admit<T>(List<T> ranked, Capacity capacity, {bool queryTruncated = false}) {
  final drawn = ranked.length <= capacity.marks ? ranked : ranked.sublist(0, capacity.marks);
  final hidden = ranked.length - drawn.length;
  return (drawn: drawn, hidden: hidden, truncated: queryTruncated || hidden > 0);
}

/// The overflow legend: how many are not drawn, stated as a lower bound. Empty
/// when everything fits, so a caller can test the string rather than a flag.
String overflowLabel(Admitted<Object?> admitted) => admitted.truncated ? '${admitted.hidden}+' : '';
