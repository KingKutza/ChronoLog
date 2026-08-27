// The staple substrate.
//
// A STAPLE IS AN EDGE, NOT AN ATTRIBUTE. It connects exactly two things at one
// point -- LEXICON.md's founding conception, where "an event attached to
// multiple lines staples them together at that point", and the owner's ruling
// that "the point and purpose of a staple is to connect two things at a point.
// Here we say we connect my personal calendar frame and this event at a point,
// which is the event's end. Then we can project the two relative to eachother."
//
// DIRECTIONAL, NOT TYPED. A staple is two ends IN ORDER, and any two scopes may
// join. The JavaScript's `connects` end-scope gate -- and `endScopePair` /
// `stapleKindScopes`, which existed only to read it -- have no counterpart here.
// `kind` keeps ONLY the flags that SELECT A DERIVATION: does this kind partition
// a series, may it carry a following rule, do its ends carry a position at all,
// does it anchor a point of an object's extent. Which two things a connection
// joins is the author's business.
//
// The staple axiom is why this module exists at all: "there is no such thing as
// a time-native object, only objects better or worse stapled to time." Placement
// is not a property an object has; it is derived from the connections the object
// participates in. [Staples.resolveObjectExtent] is that derivation, and the
// start-time-plus-duration shape the app was built under is its zero-connection
// degenerate case rather than its only shape.
//
// Every coordinate is compared through exact [Rational] days, never as text --
// ICS writes month "01" where an editor field writes "1", so a string comparison
// between two spellings of one instant is silently wrong.
//
// THE INDEX SEAM. Overscale doctrine: [Staples.resolveObjectExtent] runs once
// per object inside fact indexing and recurses through connection chains, so a
// document-wide relation scan per lookup is the difference between usable and
// unusable at 500 calendars. The projection engine does not exist yet, so every
// index arrives here as an INJECTED FUNCTION -- [LawOf], [StaplesOf],
// [PlacementOf], [FactsOf] -- each with a document-scanning default for a
// law-free caller and a direct test. When the engine lands it passes its own
// index reads and the defaults go unused; nothing here carries an
// index-or-scan dual path of its own.

import 'coordinate_entry.dart';
import 'coordinate_law.dart';
import 'document.dart';
import 'eras.dart';
import 'exact.dart';
import 'records.dart';

// --- The kind registry ------------------------------------------------------

/// What a `kind` SELECTS: a derivation, and nothing about what it may join.
///
/// Deliberately stricter than frame traits, which stay valid data when
/// unfamiliar. A trait is a claim about capability a renderer may ignore with no
/// consequence; a kind nothing honours would silently move things on screen --
/// or silently fail to.
class StapleKind {
  const StapleKind(
    this.label, {
    this.partitions = false,
    this.carriesRule = false,
    this.positions = true,
    this.anchors = false,
  });

  final String label;

  /// Does this kind divide a series' rules into segments?
  final bool partitions;

  /// May this kind carry a following rule (`payload.rule`)?
  final bool carriesRule;

  /// Do this kind's ends carry a position at all?
  final bool positions;

  /// Does this kind anchor a named point of an object's extent?
  final bool anchors;
}

/// The registered kinds. Adding one is an entry plus its interpretation.
///
/// Constraint bounds ("can't go later than like 7:30/8") are deliberately NOT
/// registered. LEXICON.md marks them "Adjacent, unruled", and registering a kind
/// whose semantics nobody has ruled would be inventing meaning.
const Map<String, StapleKind> stapleKinds = {
  // On a series, an end staple cuts the rule. On an OBJECT it is the terminal
  // abutment the owner ruled for completion: "the end of this todo abuts the
  // beginning of this event". Same kind, no completion special case anywhere:
  // which reading an end staple gets is the consumer's derivation, never a field
  // on the record. `anchors: false` is load-bearing for the object case too -- a
  // completion instant names when the todo finished, not where the object sits,
  // so it must never relocate the extent.
  'end': StapleKind('Ends here', partitions: true),
  'inflection': StapleKind('Rule changes here', partitions: true, carriesRule: true),
  'phase': StapleKind("Anchors the cycle's phase"),
  'anchor': StapleKind('Anchors a point', anchors: true),
  // Frame to frame, each end a coordinate under ITS OWN frame's law. A set of
  // these between two frames is a CORRESPONDENCE, and the substrate must not
  // assume it is monotonic, total, or one-to-one: one point on frame A may
  // correspond to many disjoint points and regions on frame B -- the dot over
  // the i corresponds to every Tuesday AND to July -- and a stretch of A may
  // correspond to nothing at all. Multiple correspondences therefore project as
  // MULTIPLE: never averaged into one mapped position, never sorted into
  // monotone order, never interpolated across a gap.
  'correspondence': StapleKind('Corresponds to a point on another frame'),
  // Eras are frames stapled together, and a succession is the boundary between
  // two consecutive ones. The only kind whose ends carry NO POSITION: every
  // other kind names a place on a frame, while a succession names an adjacency,
  // and the boundary IS wherever the earlier era's extent runs out. Authoring it
  // as a coordinate would create a second fact that can disagree.
  'succession': StapleKind('Precedes the next era', positions: false),
};

StapleKind? stapleKind(String? kind) => kind == null ? null : stapleKinds[kind];

// --- Ends -------------------------------------------------------------------

/// The default point of an object end. A connection that says nothing about
/// which point it touches says the object's start -- the honest reading, and the
/// one every pre-connection document's placement already meant.
const String defaultPoint = 'start';

/// Reading a staple's two ends.
///
/// The JavaScript's nine near-identical filters over a two-element list melt to
/// these three plus `ends.whereType<FrameEnd>()`, which the sealed types give
/// for free. Authored order is the record's own order: no derivation below reads
/// index 0 as "the source" or index 1 as "the follower", because direction is
/// not stored. An instant known at one end propagates to the other, and which
/// end is known is a fact about the document rather than about the staple --
/// which is what makes `A.end <-> B.start` and `B.start <-> A.end` the same
/// connection, as they must be.
extension StapleEnds on Relation {
  /// Where the end naming [id] sits, or -1.
  int endIndexOf(String id) => ends.indexWhere((end) => end.id == id);

  /// The counterpart of the end at [index], BY POSITION. Two ends can be
  /// value-equal, so this is found by index rather than by identity or equality:
  /// a frame stapled to itself at two points is a legitimate correspondence.
  StapleEnd? otherThan(int index) {
    final both = ends;
    return both.length == 2 && index >= 0 && index < 2 ? both[1 - index] : null;
  }

  FrameEnd? get firstFrameEnd {
    for (final end in ends) {
      if (end is FrameEnd) return end;
    }
    return null;
  }
}

/// Which point of an object's extent this end touches.
String endPoint(StapleEnd? end) {
  final named = end is ObjectEnd ? (end.point ?? '').trim() : '';
  return named.isEmpty ? defaultPoint : named;
}

/// A copy of [staple] with every end id rewritten through [remap].
///
/// The one place an id substitution touches an end, so a copy-with-new-ids path
/// (duplicating a frame, reimporting a source that mints fresh ids) cannot leave
/// a connection pointing at the original while claiming to belong to the copy.
/// An id absent from the map is left alone, which is what makes a partial
/// duplicate keep its links to the records that were not copied.
/// Rewritten in the end's OWN JSON, under the key that end form spells its id
/// with, so every field the substrate does not name survives the copy verbatim.
Relation withRemappedEnds(Relation staple, Map<String, String> remap) => staple.withField('ends', [
  for (final end in staple.ends)
    if (remap[end.id] case final String next)
      {...end.toJson(), _idKey(end): next}
    else
      end.toJson(),
]);

String _idKey(StapleEnd end) => switch (end) {
  FrameEnd() => 'frame',
  ObjectEnd() => 'object',
  SeriesEnd() => 'series',
};

// --- Many-valued position membership ----------------------------------------

/// Does the instant [days] satisfy this end's position, under [law]?
///
/// The membership question a many-valued position can answer, in place of the
/// single-instant question it cannot. A selector reads the frame's OWN declared
/// cycle or level -- so `{cycle: weekday, value: Tuesday}` means whatever THAT
/// frame's declaration says a weekday is, including an authored seven-name list
/// that is not the registered one. An authored value name matches
/// case-insensitively; a numeric value matches the index directly.
///
/// A void position matches nothing, which is the point of it, and a span matches
/// by containment.
bool frameEndMatches(CoordinateLaw law, StapleEnd? end, Rational days) {
  if (end is! FrameEnd) return false;
  final position = end.position;
  try {
    final at = position?.coordinate;
    if (at != null) return law.toDays(at) == days;
    final region = position?.span;
    if (region != null) {
      return days >= law.toDays(region.from) && days <= law.toDays(region.to);
    }
    final selector = position?.selector;
    if (selector != null) return _selectorMatches(law, selector, days);
  } catch (_) {
    return false;
  }
  return false;
}

int? _namedIndex(List<String>? names, Object? value) {
  if (names == null) return null;
  final wanted = declaredText(value).toLowerCase();
  final index = names.indexWhere((name) => name.trim().toLowerCase() == wanted);
  return index == -1 ? null : index;
}

bool _selectorMatches(CoordinateLaw law, Json selector, Rational days) {
  final wanted = declaredText(selector['value']);
  final cycle = str(selector['cycle']);
  if (cycle != null) {
    final index = law.cycleIndex(cycle, days);
    if (index == null) return false;
    final named = _namedIndex(law.cycleNames(cycle), wanted);
    return named != null ? named == index : Rational.parse(wanted) == Rational.fromInt(index);
  }
  final name = str(selector['level']);
  if (name == null) return false;
  // A level selector reads the level's own value out of the coordinate this
  // instant resolves to, so it means whatever this frame's ladder says that
  // level is -- never a Gregorian month by assumption.
  final at = law.fromDays(days);
  if (!at.has(name)) return false;
  final value = Rational.parse(at.value(name));
  final named = _namedIndex(law.namesFor(name), wanted);
  // Authored names are one per unit within the parent, and a level whose family
  // counts from one is offset by one against its own name list.
  final base = law.family?.defaults[name] == '1' ? 1 : 0;
  return named != null ? value == Rational.fromInt(named + base) : value == Rational.parse(wanted);
}

// --- Fuzziness --------------------------------------------------------------

/// Asymmetric uncertainty about a connection, resolved to exact days.
///
/// LEXICON.md: "Also a fuzzy staple, e.g. 'about 5ish,' would be good too.
/// Fuzziness becomes per-staple, not per-object." Asymmetric on purpose: "about
/// 5ish" spreads both ways, while "working early to 5ish" and a hard ceiling are
/// different shapes, and a single +/- would flatten the distinction the owner
/// drew between a fuzzy actual and a bound.
class SpreadDays {
  const SpreadDays(this.before, this.after);

  static final SpreadDays zero = SpreadDays(Rational.zero, Rational.zero);

  final Rational before, after;

  /// Uncertainties ADD. When a magnitude is derived from two fuzzy anchors the
  /// spread of the difference is the SUM of the two spreads, never their
  /// difference -- two independent uncertainties do not cancel, and treating
  /// them as if they did would report a confident answer the data does not
  /// support. The same reasoning carries a spread ALONG a connection chain: an
  /// event stapled to the fuzzy end of another event is at least as uncertain as
  /// the event it follows.
  SpreadDays operator +(SpreadDays other) => SpreadDays(before + other.before, after + other.after);

  bool get isZero => before.isZero && after.isZero;
}

// --- Anchoring vocabulary ---------------------------------------------------

/// Fixed role precedence. Two anchors fully determine an extent, so when three
/// or more are present the pair to believe has to be chosen by a rule rather
/// than by whichever happened to be authored first -- otherwise adding an
/// unrelated midpoint anchor would silently move an event. `start` and `end` are
/// the two the owner named first and the two an event's own record already
/// speaks in, so they outrank a midpoint, which outranks an arbitrary named
/// point. They are also the points of an extent the substrate itself knows how
/// to read: anything else is a point the user named, carrying its own offset.
const List<String> anchorRoleOrder = ['start', 'end', 'midpoint'];

int _rolePrecedence(String role) {
  final index = anchorRoleOrder.indexOf(role);
  return index == -1 ? anchorRoleOrder.length : index;
}

/// One believed anchor: which point it names, where that is, and how uncertain.
typedef ResolvedAnchor = ({
  String role,
  Relation staple,
  StapleEnd end,
  Rational days,
  SpreadDays spread,
  String? frame,
});

/// A connection this derivation did not believe, and why -- a second claim on a
/// point already anchored, or a connection that resolves to no instant at all.
/// REPORTED, never averaged and never dropped: an average of two authored
/// positions is a third position nobody wrote, and a silently dropped connection
/// is authored data the author cannot see. [days] is null when nothing resolved;
/// [staple] is null for the object's own placement relation, which [relation]
/// names instead.
typedef Contest = ({
  String role,
  Relation? staple,
  Relation? relation,
  Rational? days,
  String reason,
});

Contest _contest(
  String role,
  String reason, {
  Relation? staple,
  Relation? relation,
  Rational? days,
}) => (role: role, staple: staple, relation: relation, days: days, reason: reason);

/// What the anchoring connections on one object came to.
typedef AnchorSet = ({
  List<ResolvedAnchor> anchors,
  List<Contest> overdetermined,
  List<Contest> unresolved,
  bool cyclic,
});

/// Where an object actually sits, derived from the connections it participates
/// in. [startDays]/[endDays] are null for an object nothing positions.
class Extent {
  Extent({
    this.startDays,
    this.endDays,
    required this.magnitudeDays,
    required this.source,
    this.derivedMagnitude = false,
    this.anchors = const [],
    this.overdetermined = const [],
    this.unresolved = const [],
    this.cyclic = false,
    SpreadDays? spread,
    this.frame,
  }) : spread = spread ?? SpreadDays.zero;

  final Rational? startDays, endDays;
  final Rational magnitudeDays;

  /// Which of the five terminal shapes answered: `anchors`, `anchor+magnitude`,
  /// `placement`, `unresolved`, `unstapled`.
  final String source;
  final bool derivedMagnitude, cyclic;
  final List<ResolvedAnchor> anchors;
  final List<Contest> overdetermined, unresolved;

  /// The fuzziness of the derived extent, so rendering can see it. Data, not a
  /// drawing instruction: the display language for uncertainty is not designed,
  /// so nothing here decides how it looks.
  ///
  /// DEVIATION, and the reason: the JavaScript carries `spread.start` and
  /// `spread.end` separately, and every one of its five terminal shapes assigns
  /// the SAME value to both -- so `extentPointSpread`'s per-point reading (the
  /// end's own for `end`, the mean of the two for `midpoint`) is provably the
  /// identity on every extent that exists. Two fields that cannot differ are one
  /// fact stored twice; a derivation that genuinely wants them to differ splits
  /// this then, with a reason.
  final SpreadDays spread;

  /// The coordinate space the extent was resolved in, propagated along a
  /// connection chain -- a downstream event inherits the space its upstream
  /// anchor was positioned in, which is what "then we can project the two
  /// relative to eachother" needs.
  final String? frame;
}

/// Where on an already-resolved extent a given point sits.
///
/// This is the "each end can answer where its touch point is" half of the
/// connection model, and the only place a point name becomes an instant. A named
/// point the user invented ("shift handover") carries its own offset from the
/// object's start; absent, it behaves as a start anchor, which is the honest
/// default -- it says where the object is without claiming to know which
/// interior point it names. An absent [offsetDays] and a zero one are therefore
/// the same answer.
Rational? extentPointDays(Extent? extent, String point, {Rational? offsetDays}) {
  final start = extent?.startDays, end = extent?.endDays;
  if (start == null || end == null) return null;
  return switch (point) {
    'start' => start,
    'end' => end,
    'midpoint' => (start + end) / Rational.fromInt(2),
    _ => start + (offsetDays ?? Rational.zero),
  };
}

// --- The implicit placement staple ------------------------------------------

/// Any coordinate-carrying attachment places.
///
/// Completion is not an attachment any more (it is a state-frame membership plus
/// an optional end staple), and a membership relation is a different type
/// entirely, so neither needs excluding here.
bool isPlacement(Relation relation, [String? objectId]) =>
    relation.type == 'attachment' &&
    (objectId == null || relation.event == objectId) &&
    relation.coordinate != null;

/// One row of an object's whole effective connection set.
///
/// An `implicit` row has no staple record -- [relation] names the attachment
/// relation that IS the connection, so an editor that changes the coordinate
/// writes that relation rather than minting a staple that would then contradict
/// it. That is what keeps "Start time" from being special: it is one row in this
/// list, with the same fields as every other row, and NO RECORD MOVES.
typedef ConnectionRow = ({
  bool implicit,
  Relation? relation,
  Relation? staple,
  String? kind,
  StapleEnd? near,
  StapleEnd? far,
});

/// One correspondence entry, oriented so `from` is the asked-about frame's own
/// end.
typedef Correspondence = ({Relation staple, FrameEnd from, FrameEnd to});

/// What the correspondence between two frames actually IS, derived from the
/// staples that constitute it. Nothing here is ever stored.
typedef CorrespondenceShape = ({
  int count,
  int points,
  int manyValued,
  int voids,
  String cardinality,
  bool? monotonic,
});

/// The reigning rule of a series segment: everything a generator needs, and
/// nothing about where the segment begins or ends.
class Rule {
  const Rule({
    this.rrule = const {},
    this.baseCoordinate,
    this.frame,
    this.exdates = const [],
    this.exclude,
    this.magnitude,
  });

  final Json rrule;
  final Json? baseCoordinate, exclude, magnitude;
  final String? frame;
  final List<Object?> exdates;
}

/// One rule segment of a series, in chronological order. Opened exclusively by
/// one staple and closed inclusively by the next.
typedef Segment = ({
  int index,
  Rational? fromDays,
  Rational? untilDays,
  Rule rule,
  Relation? openedBy,
  Relation? closedBy,
});

/// A frame's law, or null when its declaration cannot be resolved. Null rather
/// than a throw: one unresolvable frame must not take a whole projection
/// offline.
typedef LawOf = CoordinateLaw? Function(String frameId);

/// Every staple naming [id], in a stable total order.
typedef StaplesOf = List<Relation> Function(String id);

/// The object's own placement relation, or null. A MISS IS NOT AN ANSWER: an
/// index answering this must record "seen, and it has none" distinctly from "not
/// seen", and fall back to a scan for the second -- reading a miss as "unplaced"
/// makes a freshly materialized occurrence look like it sits nowhere.
typedef PlacementOf = Relation? Function(String objectId);

/// One explicit fact on a frame: the day it starts, and the object itself.
typedef ExplicitFact = ({Rational day, Event event});

/// Every explicit fact indexed on a frame, for the live-exclusion sweep.
typedef FactsOf = Iterable<ExplicitFact> Function(String frameId);

typedef _Resolution = ({Set<String> path, Set<String> crossed, Map<String, Extent> memo});

/// The substrate, bound to one document and its index seams.
///
/// Pure over `(document, seams)` so the whole substrate is testable as a
/// contract, and stateless apart from whatever caches the seams themselves hold.
class Staples {
  Staples(
    this.document, {
    CoordinateLaws? laws,
    LawOf? lawOf,
    StaplesOf? staplesOf,
    PlacementOf? placementOf,
    FactsOf? factsOf,
  }) : laws = laws ?? CoordinateLaws() {
    this.lawOf = lawOf ?? _scannedLaw;
    this.staplesOf = staplesOf ?? _scannedStaples;
    this.placementOf = placementOf ?? _scannedPlacement;
    this.factsOf = factsOf ?? _scannedFacts;
  }

  final Document document;

  /// The law resolver. A caller whose document holds era frames passes one built
  /// with `CoordinateLaws(eras: eraLookup(document))`; nothing here reads the
  /// era chain itself, which is what keeps this module and `era_chain.dart`
  /// independent of one another.
  final CoordinateLaws laws;

  late final LawOf lawOf;
  late final StaplesOf staplesOf;
  late final PlacementOf placementOf;
  late final FactsOf factsOf;

  /// The document in the map form [CoordinateLaws] speaks. Materialized once,
  /// and only by the default law seam: an engine-injected [LawOf] never touches
  /// it.
  late final Map<String, Object?> _raw = document.toJson();

  CoordinateLaw? _scannedLaw(String frameId) =>
      document.frames.containsKey(frameId) ? laws.attempt(_raw, frameId).resolved : null;

  /// The order is by relation id, and it is NOT authoring order: ids are random
  /// UUIDs and carry no creation sequence. What a tie-break needs is an order
  /// that is total, deterministic, and identical across reload, journal replay
  /// and every window looking at the same document, which map key order does not
  /// promise. Two staples therefore always resolve the same way, even though
  /// which of them resolves first is arbitrary.
  List<Relation> _scannedStaples(String id) =>
      document.relations.values
          .where((relation) => relation.isStaple && relation.ends.any((end) => end.id == id))
          .toList()
        ..sort(_byStableOrder);

  Relation? _scannedPlacement(String objectId) =>
      firstMatch(document.relations.values, (relation) => isPlacement(relation, objectId));

  /// Explicit attachments only. A projection engine's own index also carries
  /// generated occurrences; this default sees what the document itself says.
  Iterable<ExplicitFact> _scannedFacts(String frameId) => [
    for (final relation in document.relations.values)
      if (isPlacement(relation) && relation.frame == frameId)
        if (document.events[relation.event] case final Event event)
          if (daysOf(frameId, Coordinate.fromJson(relation.coordinate)) case final Rational day)
            (day: day, event: event),
  ];

  static int _byStableOrder(Relation left, Relation right) => left.id.compareTo(right.id);

  // --- Instants -------------------------------------------------------------

  /// A coordinate under one frame's own law, or null when it cannot be read.
  Rational? daysOf(String frameId, Coordinate? value) {
    if (value == null) return null;
    try {
      return lawOf(frameId)?.toDays(value);
    } catch (_) {
      return null;
    }
  }

  /// The exact instant a frame end names, or null.
  ///
  /// Only a `coordinate` position is ONE instant. A selector, a span and a void
  /// are many-valued or empty, and reducing them to a single day here is exactly
  /// the collapse the correspondence rule forbids -- "Tuesdays" would silently
  /// become one arbitrary Tuesday. Those positions answer [frameEndMatches]
  /// instead, which is a membership question rather than a location one.
  Rational? frameEndDays(StapleEnd? end) =>
      end is FrameEnd ? daysOf(end.frame, end.position?.coordinate) : null;

  /// The instant this staple itself names, or null for a connection whose
  /// instant comes from the objects it joins. Series derivations use this: a rule
  /// segment is cut at an instant, and a series end never connects to another
  /// object, so a series staple always has a frame end to read.
  Rational? stapleDays(Relation staple) => frameEndDays(staple.firstFrameEnd);

  /// What a duration magnitude is worth in days, under the law the magnitude
  /// itself names. A caller that HAS the document must never fall back to the
  /// registered standard, or a magnitude authored under an edited human-time law
  /// resolves to the wrong days.
  Rational magnitudeDays(Magnitude? magnitude) {
    if (magnitude == null) return Rational.zero;
    final frame = magnitude.frame;
    final law = (frame == null ? null : lawOf(frame)) ?? gregorianLaw;
    return law.magnitudeDays(magnitude.coordinate);
  }

  /// Asymmetric per-staple fuzziness in exact days, or null when there is none.
  SpreadDays? spreadDays(Relation staple) {
    final spread = staple.spread;
    if (spread == null) return null;
    final resolved = SpreadDays(magnitudeDays(spread.before), magnitudeDays(spread.after));
    return resolved.isZero ? null : resolved;
  }

  bool isFuzzy(Relation staple) => spreadDays(staple) != null;

  // --- Staples by thing -----------------------------------------------------

  /// Every staple that names [id] AS a [T] -- one derivation, because a series
  /// staple and an object staple differ only in which end form has to name it.
  /// An index that answers for both (a frame and an object may share an id
  /// nowhere, but the index is keyed by id alone) is narrowed here.
  List<Relation> _staplesOn<T extends StapleEnd>(String? id) => id == null
      ? const []
      : [
          for (final staple in staplesOf(id))
            if (staple.ends.whereType<T>().any((end) => end.id == id)) staple,
        ];

  /// Every staple on a series, in a stable, deterministic order.
  List<Relation> staplesForSeries(String? patternId) => _staplesOn<SeriesEnd>(patternId);

  /// Every staple on an object (event/todo/note), in a stable order.
  List<Relation> staplesForObject(String? objectId) => _staplesOn<ObjectEnd>(objectId);

  // --- Correspondence -------------------------------------------------------

  /// Every correspondence this frame participates in, oriented so `from` is
  /// always this frame's own end, optionally narrowed to one counterpart.
  ///
  /// ENUMERATION, NOT RESOLUTION. This returns the whole many-valued set in the
  /// substrate's one stable order and answers no further question about it: it
  /// does not sort by position, does not collapse duplicates, does not pick a
  /// nearest match, and does not report a range. A caller that wants "where does
  /// this instant land on the other frame" gets every answer the author wrote,
  /// or an empty list meaning the author wrote none -- and an empty list is a
  /// fact about the correspondence, never a licence to interpolate one from the
  /// neighbours.
  ///
  /// Each entry keeps both ends whole, coordinate included, because the two
  /// coordinates are written in two different laws and neither can be read
  /// through the other's.
  List<Correspondence> frameCorrespondences(String? frameId, [String? counterpartId]) {
    if (frameId == null) return const [];
    final entries = <Correspondence>[];
    for (final staple in staplesOf(frameId)) {
      if (staple.kind != 'correspondence') continue;
      final ends = staple.ends;
      if (ends.length != 2) continue;
      // Oriented per END rather than per staple: a frame stapled to itself at
      // two different points is a legitimate correspondence (a loop), and it has
      // to enumerate from both of its own ends rather than arbitrarily from one.
      for (final (index, from) in ends.indexed) {
        if (from is! FrameEnd || from.frame != frameId) continue;
        final to = staple.otherThan(index);
        if (to is! FrameEnd) continue;
        if (counterpartId != null && to.frame != counterpartId) continue;
        entries.add((staple: staple, from: from, to: to));
      }
    }
    return entries;
  }

  /// Cardinality, monotonicity and coverage are properties of the SET, not of
  /// any one staple -- so they are computed here and never stored. Storing them
  /// would put the same claim in two places: an authored `monotonic: false`
  /// beside a set that is in fact monotone is an editor accepting an edit and
  /// ignoring it, and denormalizing the claim onto every staple means N copies
  /// that drift the moment one staple is added. A derivation cannot drift.
  ///
  /// `monotonic` is null, not true, when it cannot be decided -- a set carrying
  /// any many-valued or void position has no single ordering to be monotone
  /// against, and reporting true there would be a confident answer the data does
  /// not support. `voids` counts the authored "corresponds to nothing" claims,
  /// which are a positive statement and are never mistaken for the absence of
  /// one.
  CorrespondenceShape describeCorrespondence(String frameA, String frameB) {
    final entries = frameCorrespondences(frameA, frameB);
    final sources = <String>{}, targets = <String>{};
    final pairs = <(Rational, Rational)>[];
    var voids = 0, manyValued = 0;
    for (final entry in entries) {
      if (entry.to.position is VoidPosition || entry.from.position is VoidPosition) {
        voids += 1;
        continue;
      }
      final from = frameEndDays(entry.from), to = frameEndDays(entry.to);
      if (from == null || to == null) {
        manyValued += 1;
        continue;
      }
      sources.add(from.toJson());
      targets.add(to.toJson());
      pairs.add((from, to));
    }
    final total = pairs.length;
    // A DERIVATION THAT NARROWS ITS DOMAIN MUST NARROW ITS CLAIM. The four
    // point-to-point cardinalities are computed over `pairs`, which deliberately
    // excludes every position that is not one instant -- so they may only be
    // reported when nothing was excluded. Reporting "one-to-one" for a set whose
    // other members are selectors would describe the subset this function chose
    // to look at and call it the set, and "empty" for a set of three authored
    // statements would deny they exist.
    final one = sources.length == total, onto = targets.length == total;
    final cardinality = entries.isEmpty
        ? 'empty' // nothing is authored at all
        : manyValued > 0
        ? 'many-valued' // some position is itself many-valued
        : total == 0
        ? 'void' // every statement says "nothing corresponds here"
        : one && onto
        ? 'one-to-one'
        : onto
        ? 'one-to-many'
        : one
        ? 'many-to-one'
        : 'many-to-many';
    // Undecidable rather than false: see the doc comment.
    final decidable = manyValued == 0 && voids == 0;
    final ordered = [...pairs]..sort((left, right) => left.$1.compareTo(right.$1));
    bool? monotonic = decidable && total <= 1 ? true : null;
    if (decidable && total > 1 && one) {
      monotonic = !ordered.indexed.any((row) => row.$1 > 0 && row.$2.$2 < ordered[row.$1 - 1].$2);
    }
    return (
      count: entries.length,
      points: total,
      manyValued: manyValued,
      voids: voids,
      cardinality: cardinality,
      monotonic: monotonic,
    );
  }

  // --- Anchoring ------------------------------------------------------------

  /// The object's own placement relation, read as an implicit `start` connection
  /// to the frame it is attached to. This is the migration, and it is a READING
  /// rather than a rewrite: an event placed by a plain attachment relation IS an
  /// event stapled at its start to that frame.
  Relation? placementRelation(String objectId) => placementOf(objectId);

  /// The object's whole effective connection set: its implicit placement staple
  /// first, then every authored staple, each tagged with what an editor needs to
  /// write it back.
  List<ConnectionRow> effectiveObjectStaples(String objectId) {
    final rows = <ConnectionRow>[];
    final placement = placementRelation(objectId);
    if (placement != null) {
      final parameters = placement.extra['parameters'];
      rows.add((
        implicit: true,
        relation: placement,
        staple: null,
        kind: 'anchor',
        near: ObjectEnd(objectId, point: defaultPoint),
        far: FrameEnd(
          placement.frame ?? '',
          position: Position.coordinate(placement.coordinate ?? const {}),
          extra: parameters == null ? const {} : {'parameters': parameters},
        ),
      ));
    }
    for (final staple in staplesForObject(objectId)) {
      final index = staple.endIndexOf(objectId);
      rows.add((
        implicit: false,
        relation: null,
        staple: staple,
        kind: staple.kind,
        near: index < 0 ? null : staple.ends[index],
        far: staple.otherThan(index),
      ));
    }
    return rows;
  }

  /// Every anchoring connection this object participates in, resolved and
  /// ordered by role precedence.
  ///
  /// One anchor per role wins -- the first in stable order. A second connection
  /// touching the same point is not an error (the collection is open, and
  /// rejecting it would lose authored data) but it cannot also be believed, so it
  /// is reported as overdetermined and left alone. An object whose start comes
  /// from a connection AND from its own frame staple lands here, reported, never
  /// averaged.
  AnchorSet objectAnchors(String objectId) => _anchorsOf(objectId, _newResolution());

  AnchorSet _anchorsOf(String objectId, _Resolution resolution) {
    final resolved = <ResolvedAnchor>[];
    final overdetermined = <Contest>[], unresolved = <Contest>[];
    final seenRoles = <String>{};
    var cyclic = false;
    for (final staple in staplesForObject(objectId)) {
      if (!(stapleKind(staple.kind)?.anchors ?? false)) continue;
      // Traversing an edge must not count as arriving back at it. A staple
      // between A and B is ONE edge, and because direction is not stored both
      // objects see it; asking B where it is while resolving A would otherwise
      // find that same staple pointing back at A and call it a cycle. Skipping
      // the edge already being crossed is what leaves a real cycle -- two
      // DIFFERENT staples closing a loop -- as the only thing the path guard
      // fires on.
      if (resolution.crossed.contains(staple.id)) continue;
      final index = staple.endIndexOf(objectId);
      final near = index < 0 ? null : staple.ends[index];
      final far = staple.otherThan(index);
      final role = endPoint(near);
      if (far == null) {
        unresolved.add(
          _contest(role, 'this staple has only one end, so it connects nothing', staple: staple),
        );
        continue;
      }
      Rational? days;
      var spread = spreadDays(staple) ?? SpreadDays.zero;
      String? frame;
      if (far is FrameEnd) {
        days = frameEndDays(far);
        frame = far.frame;
      } else if (far is ObjectEnd) {
        // A connection whose other end resolves back through this object cannot
        // be resolved at all: the pair would each be waiting on the other.
        // Reported rather than iterated to a fixed point, because there is no
        // instant to report and guessing one would place an object nobody
        // positioned.
        if (resolution.path.contains(far.object)) {
          cyclic = true;
          unresolved.add(
            _contest(
              role,
              'this connection resolves back through the object it places',
              staple: staple,
            ),
          );
          continue;
        }
        final upstream = _resolveExtent(far.object, (
          path: {...resolution.path, objectId},
          crossed: {...resolution.crossed, staple.id},
          memo: resolution.memo,
        ));
        // A cycle anywhere below makes THIS answer path-dependent too, so it has
        // to travel up: the memo is only safe for a subtree that resolved
        // without one, and a diamond over a cycle would otherwise cache an
        // answer that is only true for the path it was reached by.
        if (upstream.cyclic) cyclic = true;
        final point = endPoint(far);
        days = extentPointDays(upstream, point, offsetDays: magnitudeDays(far.offset));
        if (days != null) {
          spread = spread + upstream.spread;
          frame = upstream.frame;
        }
      }
      if (days == null) {
        unresolved.add(
          _contest(role, "this connection's other end has no resolvable position", staple: staple),
        );
      } else if (seenRoles.add(role)) {
        resolved.add((
          role: role,
          staple: staple,
          end: near!,
          days: days,
          spread: spread,
          frame: frame,
        ));
      } else {
        overdetermined.add(
          _contest(
            role,
            'another connection already anchors this point',
            staple: staple,
            days: days,
          ),
        );
      }
    }
    resolved.sort(
      (left, right) => _rolePrecedence(left.role) != _rolePrecedence(right.role)
          ? _rolePrecedence(left.role) - _rolePrecedence(right.role)
          : _byStableOrder(left.staple, right.staple),
    );

    // The object's own placement relation IS an implicit start connection to the
    // frame it is attached to, so a connection that also claims `start` is a
    // second claim on the same point. Anchors take precedence -- that is the
    // documented order -- but the contest has to be REPORTED rather than
    // silently won, because the surface that authored both is the only place
    // that can resolve it.
    final placement = resolved.any((anchor) => anchor.role == defaultPoint)
        ? placementRelation(objectId)
        : null;
    if (placement != null) {
      overdetermined.add(
        _contest(
          defaultPoint,
          "this object's own placement also names its start",
          relation: placement,
        ),
      );
    }
    return (
      anchors: resolved,
      overdetermined: overdetermined,
      unresolved: unresolved,
      cyclic: cyclic,
    );
  }

  static _Resolution _newResolution() =>
      (path: <String>{}, crossed: <String>{}, memo: <String, Extent>{});

  /// Where an object actually sits, derived from the connections it participates
  /// in.
  ///
  /// This retires the start-time-plus-duration assumption as the ONLY shape
  /// while keeping it as the shape a document with no authored staples still
  /// gets, bit for bit. Precedence, when the anchors overdetermine the extent:
  ///
  ///   0 anchors  the placement relation is the start; magnitude is the object's
  ///              own duration. Identical to the behavior before this substrate.
  ///   1 anchor   that anchor plus the object's magnitude. An `end` anchor here
  ///              is the end-anchored work shift LEXICON.md asks for -- an event
  ///              DEFINED by where it stops. It is also the seamless pair: the
  ///              downstream event's start IS the upstream event's end, so
  ///              moving the upstream event moves this one, through the
  ///              connection.
  ///   2 anchors  the extent is fully determined and the MAGNITUDE IS DERIVED;
  ///              the object's own duration is ignored for placement rather than
  ///              fought with.
  ///   3+ anchors the two highest-precedence roles determine the extent. Every
  ///              remaining anchor is returned in `overdetermined` and is NEVER
  ///              averaged into the answer -- an average of contradictory
  ///              anchors is an invented value, and the surface that authored
  ///              them is the only place that can resolve the contradiction.
  Extent resolveObjectExtent(String objectId) => _deriveExtent(objectId, _newResolution());

  /// The memo is only safe for a subtree that resolved without hitting a cycle:
  /// a cyclic result depends on which path reached it, so caching it would leak
  /// one object's resolution order into another's answer. It is also keyed by the
  /// set of edges already crossed, because skipping a different edge can give a
  /// different answer -- one memo per traversal state, never one per object.
  Extent _resolveExtent(String objectId, _Resolution resolution) {
    final key = resolution.crossed.isEmpty
        ? objectId
        : '$objectId ${(resolution.crossed.toList()..sort()).join(' ')}';
    final cached = resolution.memo[key];
    if (cached != null) return cached;
    final extent = _deriveExtent(objectId, resolution);
    if (!extent.cyclic) resolution.memo[key] = extent;
    return extent;
  }

  Extent _deriveExtent(String objectId, _Resolution resolution) {
    final magnitude = magnitudeDays(document.events[objectId]?.duration);
    final found = _anchorsOf(objectId, resolution);
    final anchors = found.anchors;
    final derived = anchors.length >= 2 ? _derivedMagnitude(anchors[0], anchors[1]) : null;

    // The one-anchor and two-anchor shapes differ in exactly three things: where
    // the magnitude comes from, how many anchors were believed, and what the
    // rest are told. Everything else -- and in particular that the extent is
    // placed from the LEADING anchor -- is one derivation, so it is written once.
    //
    // Placed from the HIGHEST-PRECEDENCE anchor, never from whichever of the
    // pair happens to be earlier. Those differ: for an end+midpoint pair the
    // magnitude is 2*(end - mid), and the start is `end - magnitude` = 2*mid -
    // end, which is EARLIER than either anchor. Treating the earlier anchor as
    // the start would put the start at the midpoint and silently halve the
    // event.
    if (anchors.isNotEmpty) {
      final leading = anchors.first;
      final size = derived == null ? magnitude : derived.abs();
      final (start, end) = _fromAnchor(leading, size);
      final spread = derived == null ? leading.spread : leading.spread + anchors[1].spread;
      return Extent(
        startDays: start,
        endDays: end,
        magnitudeDays: size,
        source: derived == null ? 'anchor+magnitude' : 'anchors',
        derivedMagnitude: derived != null,
        anchors: anchors,
        overdetermined: [
          ...found.overdetermined,
          for (final other in anchors.skip(derived == null ? 1 : 2))
            _contest(
              other.role,
              derived == null
                  ? 'its role pairing with the leading anchor derives no'
                        ' magnitude'
                  : 'two higher-precedence anchors already determine the extent',
              staple: other.staple,
              days: other.days,
            ),
        ],
        unresolved: found.unresolved,
        cyclic: found.cyclic,
        spread: spread,
        frame: leading.frame,
      );
    }

    // A zero-staple object is legitimate -- LEXICON.md: "Zero-staple objects are
    // possible; most carry one or more." It simply has no extent to report,
    // which a caller must handle rather than be handed a fabricated date for.
    final placement = placementRelation(objectId);
    final startDays = placement == null
        ? null
        : daysOf(placement.frame ?? '', Coordinate.fromJson(placement.coordinate));
    return Extent(
      startDays: startDays,
      endDays: startDays == null ? null : startDays + magnitude,
      magnitudeDays: magnitude,
      source: placement == null
          ? 'unstapled'
          : startDays == null
          ? 'unresolved'
          : 'placement',
      overdetermined: found.overdetermined,
      unresolved: found.unresolved,
      cyclic: found.cyclic,
      frame: placement?.frame,
    );
  }

  /// The magnitude two anchors imply. The pair is already in role-precedence
  /// order, so the arithmetic only has to cover the three orderings that order
  /// can produce. Any other pairing involves a named point whose relationship to
  /// the other anchor is not defined by the substrate: refusing is correct,
  /// because inventing a magnitude from two points whose meaning nobody declared
  /// is exactly the invented interpolation the model forbids.
  static Rational? _derivedMagnitude(ResolvedAnchor first, ResolvedAnchor second) =>
      switch ('${first.role}+${second.role}') {
        'start+end' => second.days - first.days,
        'start+midpoint' => (second.days - first.days) * Rational.fromInt(2),
        'end+midpoint' => (first.days - second.days) * Rational.fromInt(2),
        _ => null,
      };

  (Rational, Rational) _fromAnchor(ResolvedAnchor anchor, Rational magnitude) {
    final at = anchor.days;
    final half = magnitude / Rational.fromInt(2);
    final end = anchor.end;
    // A named point resolves through its own authored offset from the start,
    // which is what lets a name the user invented still place an extent.
    final named = at - magnitudeDays(end is ObjectEnd ? end.offset : null);
    return switch (anchor.role) {
      'end' => (at - magnitude, at),
      'midpoint' => (at - half, at + half),
      'start' => (at, at + magnitude),
      _ => (named, named + magnitude),
    };
  }

  // --- Series partitioning --------------------------------------------------

  /// A series' rule segments, in chronological order.
  ///
  /// LEXICON.md, the Rob-and-John scenario: "a series is an identity whose rules
  /// are segments partitioned by staples ... a staple at an inflection point ends
  /// the reigning rule, and a new rule may follow on the same series or a new
  /// series may begin, on preference."
  ///
  /// BOUNDARY CONVENTION, and it is load-bearing: a partitioning staple CLOSES
  /// the reigning segment inclusively and OPENS the following one exclusively.
  /// The inclusive close is the end-staple's own behavior ("the staple's own
  /// occurrence survives; nothing after it projects"), and once close is
  /// inclusive, exclusive open is the only choice that does not project the
  /// staple instant twice. One staple with no following rule yields exactly two
  /// entries' worth of meaning -- a bounded segment 0 and nothing after it --
  /// which is why a lone end-staple works through this without a special case.
  List<Segment> seriesSegments(Pattern pattern) {
    final template = document.relations[pattern.templateRelation];
    final partitioning =
        <({Relation staple, FrameEnd end, Rational days})>[
          for (final staple in staplesForSeries(pattern.id))
            if (stapleKind(staple.kind)?.partitions ?? false)
              if (staple.firstFrameEnd case final FrameEnd end)
                // Both the inclusive close and the following segment's exclusive
                // open use the SAME instant, or occurrences between the authored
                // midnight and the end of the named unit would fall into both.
                if (_partitionClose(end, stapleDays(staple)) case final Rational at)
                  (staple: staple, end: end, days: at),
        ]..sort(
          (left, right) => left.days != right.days
              ? left.days.compareTo(right.days)
              : _byStableOrder(left.staple, right.staple),
        );

    final segments = <Segment>[];
    var reigning = Rule(
      rrule: obj(pattern.extra['rrule']) ?? const {},
      baseCoordinate: template?.coordinate,
      frame: template?.frame ?? str(pattern.extra['frame']),
      exdates: asList(pattern.extra['exdates']),
      exclude: obj(pattern.extra['exclude']),
    );
    Rational? from;
    Relation? openedBy;
    void close(Rational? until, Relation? closedBy) => segments.add((
      index: segments.length,
      fromDays: from,
      untilDays: until,
      rule: reigning,
      openedBy: openedBy,
      closedBy: closedBy,
    ));
    for (final entry in partitioning) {
      close(entry.days, entry.staple);
      final head = obj(entry.staple.payload?['rule']);
      // No following rule: this staple terminates the series. The degenerate
      // case, and the one a lone end-staple consists of.
      if (head == null) return segments;
      final authored = entry.end.position;
      reigning = Rule(
        rrule: obj(head['rrule']) ?? const {},
        baseCoordinate:
            obj(head['coordinate']) ?? (authored is CoordinatePosition ? authored.json : null),
        frame: str(head['frame']) ?? entry.end.frame,
        exdates: asList(head['exdates']),
        exclude: obj(head['exclude']),
        magnitude: obj(head['magnitude']),
      );
      from = entry.days;
      openedBy = entry.staple;
    }
    close(null, null);
    return segments;
  }

  /// Does this series' rule change part-way through, rather than merely
  /// stopping?
  bool seriesIsSegmented(Pattern pattern) => seriesSegments(pattern).length > 1;

  /// A partitioning staple closes its segment at the END OF THE UNIT THE AUTHOR
  /// NAMED, not at the instant that unit happens to begin.
  ///
  /// Ruled for "ends on a date": "'Ends on this date' means through the whole of
  /// that day, whatever time of day the occurrences fall at -- so the value is
  /// the last second of the date, not its midnight. A midnight UNTIL would
  /// silently drop a 09:00 series' final occurrence, which is the kind of
  /// off-by-one a user reads as a bug." A bare-date staple cutting at midnight is
  /// that same bug one layer up, so it takes the same answer.
  ///
  /// The rule is generic rather than kind-special: a coordinate authored at or
  /// above the base unit names a PERIOD (a day, a month, a year) and closes at
  /// that period's last instant, while a coordinate that descends below the base
  /// names a clock INSTANT and closes exactly there. Precision is authored data
  /// -- the depth the author stopped at -- so this reads it off the coordinate
  /// rather than inferring it from a resolved day. "Last instant" is the next
  /// unit's start less one of the law's own finest measurable steps.
  Rational? _partitionClose(FrameEnd end, Rational? days) {
    final value = end.position?.coordinate;
    final law = lawOf(end.frame);
    if (days == null || value == null || law == null) return days;
    final depth = authoredDepth(value, law);
    if (depth == null) return days;
    if (law.belowLadder.any((level) => level.name == depth)) return days;
    final next = _incrementedToDepth(law, value, depth);
    if (next == null) return days;
    try {
      return law.toDays(next) - Rational.one / law.unitsPer('second');
    } catch (_) {
      return days;
    }
  }

  // --- Occurrence phase -----------------------------------------------------

  /// The base instant a series' generator should count cycles from.
  ///
  /// LEXICON.md: "stapling an arbitrary occurrence anchors the cycle's phase." A
  /// phase staple replaces the template relation's coordinate AS THE GENERATOR'S
  /// BASE without rewriting the template -- the same discipline as the
  /// end-staple, so removing the phase staple restores the original phase for
  /// free. Null means "use the segment's own base coordinate".
  Rational? seriesPhaseDays(Pattern pattern) {
    for (final staple in staplesForSeries(pattern.id)) {
      if (staple.kind != 'phase') continue;
      final days = stapleDays(staple);
      if (days != null) return days;
    }
    return null;
  }

  // --- Exclusions as live references ----------------------------------------

  /// The set of whole days covered by events on the referenced frames, over a
  /// bounded window.
  ///
  /// LEXICON.md, Rob-and-John beat 2: "skip holidays (events on frame xyz)" and
  /// "holiday exclusion is a live reference to another frame's events, not a
  /// baked list." So this resolves at PROJECTION time against whatever those
  /// frames currently hold: adding a holiday changes the series with no edit to
  /// the series, and removing one puts the meeting back.
  ///
  /// Matched by WHOLE DAY, not by instant. A holiday is an all-day event; a 6:15
  /// meeting on that date has to be skipped even though it shares no instant
  /// with a midnight-to-midnight span. Bounded on purpose: the referenced frame
  /// can be an entire imported holiday calendar, and a projection only ever needs
  /// the window it is drawing.
  Set<String>? liveExclusionDays(Json? exclude, Rational lower, Rational upper) {
    final authored = exclude?['frames'];
    final frames = [
      for (final frame in authored is List ? authored : [exclude?['frame']])
        if (str(frame) case final String id)
          if (id.isNotEmpty) id,
    ];
    if (frames.isEmpty) return null;
    final days = <String>{};
    final from = lower.floor(), to = upper.floor();
    for (final frameId in frames) {
      for (final entry in factsOf(frameId)) {
        final duration = magnitudeDays(entry.event.duration);
        final first = entry.day.floor();
        // An all-day event stored as a 1-day duration covers exactly its own
        // day, so the last covered day is derived from the final instant
        // strictly inside the span rather than from the exclusive end. The nudge
        // only has to be smaller than one base day to land in the right whole
        // day, so it reads through the REGISTERED standard's own finest unit.
        final last = duration.isZero
            ? first
            : (entry.day + duration - Rational.one / gregorianLaw.unitsPer('second')).floor();
        if (last < from || first > to) continue;
        final finish = last > to ? to : last;
        for (var day = first < from ? from : first; day <= finish; day += BigInt.one) {
          days.add('$day');
        }
      }
    }
    return days;
  }
}

/// Is this occurrence's own day excluded by a live reference? Days are keyed by
/// their exact integer day number as text, so membership is an exact numeric
/// identity and never a coordinate-spelling comparison.
bool isLiveExcluded(Set<String>? excludedDays, Rational day) =>
    excludedDays != null && excludedDays.isNotEmpty && excludedDays.contains('${day.floor()}');

// --- The levels ladder, one unit later --------------------------------------
//
// Authored precision itself is `coordinate_entry.dart`'s: [authoredDepth] is the
// one derivation of "the depth the author stopped at", shared with the
// projection engine's own precision reading, so the partition-close rule and a
// fact's reported precision cannot disagree about what an author wrote. The seam
// this module carried until that landed is gone rather than duplicated.

/// The low value of a level, read from the family's own defaults rather than
/// assumed: a level the calendar counts from one is one-based, anything else is
/// zero-based.
BigInt _levelFloor(CoordinateLaw law, String name) =>
    law.family?.defaults[name] == '1' ? BigInt.one : BigInt.zero;

BigInt? _childrenInLevel(CoordinateLaw law, String name, Map<String, BigInt> parts) {
  final level = law.level(name);
  final transition = level?.transition;
  if (level?.radix != null) return level!.radix!.n;
  if (level == null || transition == null) return null;
  try {
    return transitionDefinition(transition)?.childrenIn(parts);
  } catch (_) {
    return null;
  }
}

/// The coordinate one unit later at [depth], carrying into the coarser levels
/// when the increment runs off the end of its parent -- so the day after the
/// 31st is the 1st of the next month, computed from the level's OWN declared
/// child count (`radix`, or its transition's `childrenIn`) and never from a
/// hardcoded calendar. The root has no parent to carry into, which terminates
/// this.
Coordinate? _incrementedToDepth(CoordinateLaw law, Coordinate value, String depth) {
  final ladder = [for (final level in law.aboveLadder) level.name];
  final index = ladder.indexOf(depth);
  if (index < 0) return null;
  final parts = <String, BigInt>{
    for (final name in ladder)
      name: BigInt.parse(value.value(name, law.family?.defaults[name] ?? '0')),
  };
  for (var at = index; at >= 0; at -= 1) {
    final name = ladder[at];
    parts[name] = parts[name]! + BigInt.one;
    if (at == 0) break;
    final count = _childrenInLevel(law, name, parts);
    final floor = _levelFloor(law, name);
    if (count == null || parts[name]! < floor + count) break;
    parts[name] = floor;
  }
  return Coordinate([
    for (final name in ladder.take(index + 1)) (level: name, value: '${parts[name]}'),
  ]);
}

// --- The single end-staple convenience --------------------------------------
//
// A thin named wrapper over the open collection, rather than the substrate's own
// idea of a privileged record: `end` is one registry entry among several, whose
// flags say it partitions a series and anchors nothing. This is the convenience
// a single-end-staple editor field still wants, and the one place the engine,
// the series editor and ICS export all find that record.

Relation? seriesEndStaple(Document document, String? patternId) =>
    patternId == null || patternId.isEmpty
    ? null
    : firstMatch(
        document.relations.values,
        (relation) =>
            relation.isStaple &&
            relation.kind == 'end' &&
            relation.ends.any((end) => end.id == patternId),
      );

/// Re-placing UPDATES the one end staple, which is still right for a single
/// editor field even though it is no longer what the substrate assumes about
/// staples in general. The ends are `[series, frame]`: direction is that order.
({Document document, Relation staple}) setSeriesEndStaple(
  Document document,
  String patternId,
  String frame,
  Json coordinate, {
  Json? parameters,
}) => putStaple(
  document,
  id: seriesEndStaple(document, patternId)?.id,
  kind: 'end',
  ends: [
    StapleEnd.series(patternId),
    StapleEnd.frame(
      frame,
      position: Position.coordinate(coordinate),
      extra: parameters == null ? const {} : {'parameters': parameters},
    ),
  ],
);

Document clearSeriesEndStaple(Document document, String patternId) {
  final existing = seriesEndStaple(document, patternId);
  return existing == null ? document : removeStaple(document, existing.id);
}
