// The staple substrate.
//
// A STAPLE IS AN IDENTIFICATION, NOT AN ATTRIBUTE. The owner's full statement:
// "a piece of metal existing in a third dimension that pierces 1 or more pages
// (objects and frames) at 0 or more points causing all of said points to be
// bound together through that third dimension." One thing, always: "n points on
// objects or frames are one point", n >= 0. In plain words, "this point right
// here is also that point right there" -- an event on a calendar, the end of an
// era on the beginning of the next, a todo on an event, the midpoint of a thing
// on itself.
//
// N-ARY, DIRECTIONAL, NOT TYPED. A staple is n ends IN ORDER, and any scopes may
// join. The JavaScript's `connects` end-scope gate -- and `endScopePair` /
// `stapleKindScopes`, which existed only to read it -- have no counterpart here.
// Which things a connection joins, and how many, is the author's business.
//
// THE VERB CARRIES ZERO ENGINE MEANING (ruled 8.31, melted 9.3). `kind` is a
// WORD ON THE CLAIM -- data, like colour: projections include by it, sort by it,
// style by it, and any meaning beyond the identification is authored there.
// Whether a staple anchors a point of an object's extent, whether it positions
// anything, and whether two sheets correspond are read off the SHAPE: which
// ends are objects and which are frames, which point of the object is named,
// whether the far end resolves. Two staples identical in every term derive
// identically whatever word is written on them, and a verb nobody has ever
// typed is not a special case -- it is the ordinary case. What survives in
// [stapleKinds] is wording the cards read, plus the series' own two flags, whose
// structural answer is a ruling Don has not given (see [StapleKind.partitions]).
//
// AND THE REGISTRY IS SHRINKING. Ruled 8.31: "A staple connects n points and says
// each is the same as the other. No exceptions No special cases No extra
// riders." `succession` selected a derivation until that night and now selects
// nothing -- an era boundary is a plain point staple, read through the same
// machinery as every other identification, with [StapleEnds.readEnds] supplying
// the point a positionless record always meant so the old spelling keeps both
// its meaning and its bytes.
//
// IDENTIFICATION, NOT CONTEST. Because the n points ARE one point, two claims
// naming that point on DIFFERENT coordinate spaces are not rivals: they are one
// point on several sheets, and the point simply has a position in each. A
// CONTEST is the narrower thing it always should have been -- two claims in the
// SAME coordinate space that disagree -- and it is still reported, never
// averaged. [Extent.positions] is the per-sheet reading.
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
import 'frame_points.dart';
import 'records.dart';

// --- The kind registry ------------------------------------------------------

/// WHAT A WORD OFFERS, not what it means.
///
/// Every field here is either wording the cards read, or a SERIES flag whose
/// structural answer is an open ruling. Nothing about an object's placement or
/// extent is decided here any more: the shape decides, and the melt that took
/// [anchors] out is why a staple spelled with a word nobody registered anchors
/// exactly as `anchor` does.
class StapleKind {
  const StapleKind(
    this.label, {
    this.partitions = false,
    this.carriesRule = false,
    this.positions = true,
  });

  final String label;

  /// Does this kind divide a series' rules into segments?
  ///
  /// THE ONE DERIVATION STILL SELECTED BY A WORD, and deliberately so: it needs
  /// a ruling, not a refactor. `[series <-> frame instant]` is BYTE-IDENTICAL
  /// under `end`, `phase` and (minus its `payload.rule`) `inflection`, and the
  /// three mean three different things -- cut the rule here, count the cycle's
  /// phase from here, change the rule here. Melting this gate without an answer
  /// would make every phase staple terminate its own series. Reported, not
  /// decided.
  final bool partitions;

  /// May this kind carry a following rule (`payload.rule`)?
  final bool carriesRule;

  /// Do this kind's ends carry a position at all?
  ///
  /// NOTHING SETS THIS FALSE ANY MORE. `succession` was the only entry that
  /// did, and 8.31 dissolved it: every frame end speaks the point vocabulary, so
  /// there is no kind whose ends have nowhere to be. The field survives because
  /// the staple editor still reads it to decide whether to offer a position
  /// field; retiring it belongs with the filed registry-to-shape migration,
  /// which is the same pass that retires [carriesRule] -- a rule is an authored
  /// function now, not a rider a kind permits.
  final bool positions;

}

/// THE WORD AN ANCHORING STAPLE IS SPELLED WITH, said once. Every writer that
/// means "this point is that point" reaches for this rather than retyping the
/// word, so the day the registry retires there is one site to answer for.
const String anchorStapleKind = 'anchor';

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
  // on the record.
  //
  // AND SINCE THE 9.3 MELT THE OBJECT CASE IS NOT THIS ENTRY'S BUSINESS. The
  // `anchors: false` that used to sit here kept a completion instant from
  // relocating the extent -- BY THE WORD, so the identical staple spelled
  // `anchor` relocated it and this one did not. The word cannot decide that, so
  // the shape does, and the shape says the same thing under both spellings:
  // `[object.end = coordinate]` anchors the object's end. WHICH READING that
  // shape gets -- an instant that relocates the extent, or only a statement of
  // when the thing finished -- is Don's open residue, and the completion
  // reading is unharmed either way because [ObjectFacts._instant] reads the
  // same staple off the same shape.
  'end': StapleKind('Ends here', partitions: true),
  'inflection': StapleKind('Rule changes here', partitions: true, carriesRule: true),
  'phase': StapleKind("Anchors the cycle's phase"),
  'anchor': StapleKind('Anchors a point'),
  // Frame to frame, each end a coordinate under ITS OWN frame's law. A set of
  // these between two frames is a CORRESPONDENCE, and the substrate must not
  // assume it is monotonic, total, or one-to-one: one point on frame A may
  // correspond to many disjoint points and regions on frame B -- the dot over
  // the i corresponds to every Tuesday AND to July -- and a stretch of A may
  // correspond to nothing at all. Multiple correspondences therefore project as
  // MULTIPLE: never averaged into one mapped position, never sorted into
  // monotone order, never interpolated across a gap.
  'correspondence': StapleKind('Corresponds to a point on another frame'),
  // A LABEL, NOT A CASE. Ruled 8.31: "A staple connects n points and says each
  // is the same as the other. No exceptions No special cases No extra riders."
  // An era boundary is a plain point staple -- the end of one frame's extent
  // identified with the beginning of another's -- so nothing here selects a
  // derivation any more and `positions: false` is gone with the special
  // handling it named. What survives is the word: an existing record spelled
  // `succession` keeps loading, keeps its meaning, and round-trips byte for
  // byte, because a frame end that names no point is READ as the point the
  // staple's own order always said it was (see [StapleEnds.readEnds]).
  'succession': StapleKind('Precedes the next era'),
};

StapleKind? stapleKind(String? kind) => kind == null ? null : stapleKinds[kind];

// --- Ends -------------------------------------------------------------------

/// The object's own beginning, said explicitly. Every write that MEANS the start
/// says this: since the silence below stopped meaning it, a site that leaves the
/// point off is making a different claim, and the difference has to be visible
/// at the write rather than inferred at the read.
const String startPoint = 'start';

/// ALL OF IT -- a point whose size is the object's whole extent.
///
/// "Staples to a point: this point is that point. Staples to an object, no
/// point: ALL of this object is that point -- which in practice would be
/// affiliation." (Don, ruled 2026-09-01.) A point has a size, and the whole is
/// one of the sizes a point may have; it is not a second kind of end.
const String wholePoint = 'all';

/// What an object end that says nothing about which point it touches means.
///
/// RULED 2026-09-01, and it is a reversal: the silence used to read as the
/// object's START. It reads as THE WHOLE OF IT now, exactly parallel to a frame
/// end that names no point meaning "somewhere on that sheet, nothing about
/// where". Both silences say the same thing in their own vocabulary -- the whole
/// of this side is identified with the other -- and that is what an AFFILIATION
/// is.
///
/// Pre-alpha, and the field data holds no silent object ends (every writer named
/// its point), so there is no compat machinery: the reversal is the reading, and
/// every site that meant the start now says [startPoint].
const String defaultPoint = wholePoint;

/// Reading a staple's n ends.
///
/// The JavaScript's nine near-identical filters over a two-element list melt to
/// these plus `ends.whereType<FrameEnd>()`, which the sealed types give for
/// free. Authored order is the record's own order: no derivation below reads
/// index 0 as "the source" or the last index as "the follower", because
/// direction is not stored. An instant known at one end propagates to every
/// other, and which end is known is a fact about the document rather than about
/// the staple -- which is what makes `A.end <-> B.start` and `B.start <-> A.end`
/// the same connection, as they must be.
extension StapleEnds on Relation {
  /// THE STAPLE'S ENDS AS READ: what is authored, plus the point a positionless
  /// frame end has always meant.
  ///
  /// A frame end carrying no position says nothing about where on its own sheet
  /// it touches -- except what the staple's own ORDER says, and that order was
  /// always the whole of an era succession's meaning: the first sheet the metal
  /// pierces FINISHES at this point and every other BEGINS there. That is read
  /// here as an ordinary point expression over each frame's own extent, with no
  /// kind consulted, which is how "the end of 1 meets the beginning of 2" stops
  /// being a case and becomes one spelling of the general staple.
  ///
  /// A LONE frame end is left alone. One sheet pierced at an unnamed point says
  /// only "something of this is here"; reading it as the sheet's own end would
  /// invent a claim from an absence, and there is no second end for the order to
  /// be an order OF.
  ///
  /// Nothing is written. [ends] stays the record's own list, so a document that
  /// arrived spelling this as `succession` saves back exactly as it loaded.
  List<StapleEnd> get readEnds {
    final all = ends;
    var frames = 0, blanks = 0;
    for (final end in all) {
      if (end is! FrameEnd) continue;
      frames += 1;
      if (end.position == null) blanks += 1;
    }
    if (frames < 2 || blanks == 0) return all;
    final read = <StapleEnd>[];
    var ordinal = 0;
    for (final end in all) {
      if (end is! FrameEnd) {
        read.add(end);
        continue;
      }
      final implied = impliedPoint(ordinal++);
      read.add(
        end.position != null
            ? end
            : FrameEnd(end.frame, position: Position.point(implied.from), extra: end.extra),
      );
    }
    return read;
  }

  /// Where the end naming [id] sits, or -1.
  int endIndexOf(String id) => ends.indexWhere((end) => end.id == id);

  /// Every index at which an end names [id] AS a [T]. A staple may pierce one
  /// page at several of its own points -- "the midpoint of itself" -- so asking
  /// for the first would silently drop the rest.
  Iterable<int> endIndexesOf<T extends StapleEnd>(String id) sync* {
    for (final (index, end) in readEnds.indexed) {
      if (end is T && end.id == id) yield index;
    }
  }

  /// Every OTHER end, BY POSITION, in authored order. Two ends can be
  /// value-equal, so this is found by index rather than by identity or equality:
  /// a frame stapled to itself at two points is a legitimate correspondence.
  ///
  /// The n-ary reading of "the other end": with three ends the counterpart of
  /// one is the other two, and every derivation that used to read a single
  /// counterpart reads this instead.
  List<StapleEnd> othersThan(int index) {
    final all = readEnds;
    if (index < 0 || index >= all.length) return const [];
    return [
      for (final (at, end) in all.indexed)
        if (at != index) end,
    ];
  }

  /// The single counterpart of the end at [index] -- the pair case, and null
  /// when this staple identifies more or fewer than two points. Only a caller
  /// that genuinely wants "the one other thing" may use it; everything n-ary
  /// reads [othersThan].
  StapleEnd? otherThan(int index) {
    final others = othersThan(index);
    return others.length == 1 ? others.single : null;
  }

  /// Every sheet this staple pierces, in authored order. `firstFrameEnd` is
  /// gone: "the first frame end" was only ever a stand-in for "the end that
  /// names an instant", which is [Staples.instantEnd] and needs a law to answer.
  List<FrameEnd> get frameEnds => readEnds.whereType<FrameEnd>().toList();
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
/// by containment. A POINT matches by containment too, which is what makes the
/// all-point the INCLUSIVE connection Don ruled: "the end of 1 staples to all of
/// 2" holds at every instant of 2, and a point of size zero holds at exactly one
/// -- the same derivation, differing in size rather than in kind.
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
    final point = lawPointRegion(law, position);
    if (point != null) {
      final (low, high) = point.from <= point.to ? (point.from, point.to) : (point.to, point.from);
      return days >= low && days <= high;
    }
  } catch (_) {
    return false;
  }
  return false;
}

/// The region an authored point names under [law], or null when this position is
/// not a point -- or when the frame cannot say where it sits at all.
///
/// The second case is the one the ruling turns on. A basis with "no power to
/// label a point along the line" answers nothing here, and every derivation
/// downstream reads that as association without projection rather than as a
/// position it may invent. The Dawn Era's staple is real; a place in it is not.
({Rational from, Rational to})? lawPointRegion(CoordinateLaw law, Position? position) {
  final source = pointSourceOf(position?.point);
  final extent = law.extentDays;
  if (source == null || extent == null) return null;
  return evaluatePoint(source, extent, units: law.unitNamed, subject: _pointSubject(law));
}

String _pointSubject(CoordinateLaw law) => 'This point of ${law.frameId ?? 'the frame'}';

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

/// Where each identified point of an object sits, PER COORDINATE SPACE: point
/// name to space to exact days. "n points on objects or frames are one point"
/// read out -- a point identified with instants on two sheets has a position in
/// each, and neither is a rival for the other.
typedef PointPositions = Map<String, Map<String, Rational>>;

/// What the anchoring connections on one object came to.
typedef AnchorSet = ({
  List<ResolvedAnchor> anchors,
  List<Contest> overdetermined,
  List<Contest> unresolved,
  PointPositions positions,
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
    this.positions = const {},
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

  /// Every identified point of this object, spelled in each coordinate space
  /// that names it. [startDays] and [endDays] answer in ONE space -- [frame]'s,
  /// the space the leading anchor was written in -- because they are a single
  /// pair of numbers; this is the whole of what the staples said, and it is how
  /// "the sticky note is at 6:45pm 8.30.26 AND at 3rd of Limestone 507" is read
  /// back without either claim being demoted to a contest.
  final PointPositions positions;

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
    startPoint => start,
    'end' => end,
    'midpoint' => (start + end) / Rational.fromInt(2),
    // THE WHOLE IS NOT AN INSTANT (ruled 2026-09-01). A point of size `all`
    // names the entire extent, and collapsing it to one number would pick an
    // edge and call it the answer. Null is the honest reply, and the caller
    // above turns it into a sentence.
    wholePoint => null,
    _ => start + (offsetDays ?? Rational.zero),
  };
}

// --- The implicit placement staple ------------------------------------------

/// AFFILIATION (Don, ruled 2026-09-01).
///
/// "Staples to an object, no point: ALL of this object is that point -- which in
/// practice would be affiliation. There would not so much be membership, as it
/// is not directional."
///
/// So the sentence is symmetric and the word is affiliation, not membership: an
/// identification carries NO DIRECTION, and the `member` -> `group` arrow the old
/// record spelled is SPELLING, NOT DATA. Nothing here reads an arrow, and nothing
/// reads a verb -- a kind label would be the enum the trinity forbids.
///
/// WHAT MAKES A GROUP SIDE IS STRUCTURE: a frame end that names no point. The
/// frame is the sheet the object is somewhere on, which is the whole of what a
/// `membership` record ever said, and it is a fact about which END IS A FRAME
/// rather than about which field was written first. An affiliation between two
/// OBJECTS has no group side at all -- both ends simply belong together, and it
/// reads the same from either one.
///
/// This is the one reading every affiliation reader goes through, so a staple
/// written by the editor and a `membership` record written by an older build are
/// the same edge to the projection, to the state grammar and to the card.
Iterable<({String object, String frame})> stapledAffiliations(Relation staple) sync* {
  if (!staple.isStaple) return;
  final ends = staple.ends;
  for (final end in ends) {
    if (end is! FrameEnd || end.position != null) continue;
    for (final other in ends) {
      if (other is ObjectEnd) yield (object: other.object, frame: end.frame);
    }
  }
}

/// CONTAINMENT, said as a staple (ruled 2026-09-01, the silent object end).
///
/// Every end names an object and every one of them is SILENT -- "all of this is
/// all of that" -- which is the affiliation sentence between two objects, with
/// no group side and no arrow. What the tree reads as parent and child is the
/// AUTHORED ORDER, which is the one ruled carrier of direction ("staples
/// directional not typed; direction is the order"): each end is held by the one
/// after it. The identification itself stays symmetric, and a reader looking
/// from either end finds the same connection.
///
/// ADJACENT PAIRS ONLY. Three ends say A is in B is in C; they do not say A is
/// DIRECTLY in C, and minting that edge would invent a containment nobody wrote
/// where the closure above already derives what follows.
Iterable<({String child, String parent})> stapledContainments(Relation staple) sync* {
  if (!staple.isStaple) return;
  final ends = staple.ends;
  if (ends.length < 2) return;
  for (final end in ends) {
    if (end is! ObjectEnd || (end.point ?? '').trim().isNotEmpty) return;
  }
  for (var index = 0; index + 1 < ends.length; index += 1) {
    yield (child: ends[index].id, parent: ends[index + 1].id);
  }
}

/// Any coordinate-carrying attachment places.
///
/// Completion is not an attachment any more (it is a state-frame membership plus
/// an optional end staple), and a membership relation is a different type
/// entirely, so neither needs excluding here.
/// RE-SAY WHICH OBJECT a connection is about, keeping every other term.
///
/// One definition (ruled 2026-09-01): the id lives on an END, so a writer that
/// spelled it as a field is writing somewhere nothing reads. Every end naming an
/// object is re-pointed, which is what a materialized occurrence wants -- it is
/// the same sentence about a different object.
Relation sayingObject(Relation relation, String objectId) => relation.withField('ends', [
  for (final end in relation.ends)
    end is ObjectEnd
        ? ObjectEnd(objectId, point: end.point, offset: end.offset, extra: end.extra).toJson()
        : end.toJson(),
]);

/// RE-SAY THE INSTANT a connection's frame end names, keeping every other term.
Relation sayingInstant(Relation relation, Json? coordinate) => relation.withField('ends', [
  for (final end in relation.ends)
    end is FrameEnd
        ? FrameEnd(
            end.frame,
            position: coordinate == null ? null : Position.coordinate(coordinate),
            extra: end.extra,
          ).toJson()
        : end.toJson(),
]);

/// WHICH POINT OF AN OBJECT A PLACEMENT LANDS ON THE SHEET.
///
/// Don, ISSUES 9.2: "Whole to point PLACES the object at that point... the whole
/// sits at the instant, the object's own placement point (start by shipped
/// convention) being what lands there." So the object's beginning said outright,
/// and the whole of it -- the two silences that mean "this object is here" --
/// are the placement points. Every other point of the extent (`end`, the
/// midpoint, a point the author named) is an ANCHOR: it says where that point
/// sits and lets the derivation compose the extent around it, and it is not a
/// second statement of where the object is drawn.
bool isPlacementPoint(String point) => point == startPoint || point == wholePoint;

/// A PLACEMENT IS A STAPLE THAT ANCHORS AN OBJECT'S PLACEMENT POINT AT AN
/// INSTANT.
///
/// Four structural facts, no record kind (ruled 2026-09-01, the fourth added
/// 9.2): it ANCHORS a point of an object's extent, which is what tells it apart
/// from an `end` staple carrying a completion instant on the same sheet; its
/// frame end NAMES A COORDINATE, which is what tells it apart from an
/// affiliation; it names this object; and the point it names on this object is
/// the object's own PLACEMENT POINT.
///
/// The fourth is Don's double render (ISSUES 9.2): an end anchor -- object end
/// `point: end`, far end a Wall Time coordinate -- read as a second placement
/// beside the start, so the same event drew twice on every lens projecting Wall
/// Time. An anchor on any other point positions the EXTENT and is never a second
/// mark.
///
/// AND THE FOURTH IS NOW THE WHOLE OF IT. The anchoring fact used to come off
/// the kind registry -- the last place a WORD selected a derivation. What the
/// registry answered was "does this staple anchor a point of an object's
/// extent", and the shape answers it outright: a staple that names a point of
/// this object which is not the whole of it, and identifies that point with
/// something that resolves, HAS anchored it. Naming the whole is an affiliation
/// and claims no point; an unresolvable far end claims a point and fails to
/// find it. Both readings live in [Staples._anchorsOf] already, so nothing here
/// needs to ask a second time: what is left for this predicate is the placement
/// question, which is whether the point named is a PLACEMENT point.
bool isPlacement(Relation relation, [String? objectId]) {
  if (!relation.isStaple) return false;
  if (relation.coordinate == null) return false;
  final named = [
    for (final end in relation.readEnds)
      if (end is ObjectEnd)
        if (objectId == null || end.object == objectId) end,
  ];
  // Asked about no object in particular, the record is about the one its own
  // accessors report -- `relation.event`, the FIRST object end -- so that is the
  // end whose point decides. Asked about an object, every end naming it counts:
  // a staple may pierce one object at more than one of its own points, and if
  // any of them is the placement point, this connection places it.
  return (objectId == null ? named.take(1) : named).any((end) => isPlacementPoint(endPoint(end)));
}

// --- What is identified with what -------------------------------------------

/// One claim an identification makes: a sheet, and where on it -- or nowhere on
/// it at all.
///
/// [position] is null for an end that pierces the page WITHOUT NAMING AN
/// INSTANT. Don's case, ruled 8.31: "Event is stapled to A at point 7/15/27
/// 2:30:54, and is stapled to B at Null Point. There B is associated with A
/// through event but no point on B projects to a given point on A." So a null
/// point is graph association and nothing more, and no derivation may make an
/// anchor of it.
typedef PointClaim = ({String frame, Position? position, String source});

/// Whether this claim says WHERE on its sheet.
///
/// An authored void is the explicit statement that there is nothing here, and an
/// absent position never named a place to begin with; both pierce the page
/// without naming an instant. A selector or a span DOES name places -- many of
/// them -- which is a positional claim even though no single instant can be read
/// off it.
///
/// AND THE ALL-POINT ASSOCIATES WITHOUT PROJECTING. Ruled 8.31: where a basis
/// cannot label a point along its own line, "the end of 1 staples to all of 2"
/// -- a real identification of the two sheets, and no statement about where on
/// the second anything sits. A SIZED point is that claim, told apart from a
/// size-zero one by its own two expressions rather than by any law, so this stays
/// the structural reading it has always been.
bool claimIsPositioned(PointClaim claim) {
  final position = claim.position;
  if (position == null || position is VoidPosition) return false;
  final point = pointSourceOf(position.point);
  return point == null || point.from == point.to;
}

/// EVERY SET OF CLAIMS THE AUTHOR HAS SAID ARE ONE POINT.
///
/// The one reading of "which point identifications exist", so the two seams
/// built on it -- `framesProject` (whether two sheets correspond at all) and
/// `Correspondences` (where an instant lands) -- cannot disagree about what the
/// document says. They differ only in what they do with a group.
///
/// TWO WAYS A GROUP FORMS, and the record type is NOT the discriminator:
///
///   * a staple's own frame ends: n sheets pierced at one point, so every pair
///     of them names that point. A staple touching one sheet and nothing else
///     groups nothing -- it places something there and says nothing about
///     anywhere else.
///   * ONE POINT OF ONE OBJECT: every claim made at that point of that object,
///     however it was spelled. The Dwarf Fortress parable -- the sticky note
///     stapled to the August sheet and to the DF decade sheet relates the two
///     sheets because one point of the sticky is now a point on both -- and the
///     object's own PLACEMENT ATTACHMENT is one of those spellings, because a
///     placement IS the object's first identification. Two staples naming one
///     point are the same point as surely as one staple with three ends is.
List<List<PointClaim>> pointIdentifications(Iterable<Relation> relations) {
  final groups = <List<PointClaim>>[];
  final byObjectPoint = <String, List<PointClaim>>{};
  for (final relation in relations) {
    if (relation.isStaple) {
      // NO KIND GATE. A kind selects a derivation, never a meaning.
      final claims = [
        for (final end in relation.readEnds)
          if (end is FrameEnd) (frame: end.frame, position: end.position, source: relation.id),
      ];
      if (claims.length > 1) groups.add(claims);
      if (claims.isEmpty) continue;
      for (final end in relation.readEnds) {
        if (end is! ObjectEnd) continue;
        (byObjectPoint['${end.object} ${endPoint(end)}'] ??= <PointClaim>[]).addAll(claims);
      }
      continue;
    }
    if (!isPlacement(relation)) continue;
    final frame = relation.frame;
    if (frame == null) continue;
    (byObjectPoint['${relation.event} $startPoint'] ??= <PointClaim>[]).add((
      frame: frame,
      position: Position.coordinate(relation.coordinate ?? const {}),
      source: relation.id,
    ));
  }
  for (final claims in byObjectPoint.values) {
    if (claims.length > 1) groups.add(claims);
  }
  return groups;
}

/// One row of an object's whole effective connection set.
///
/// An `implicit` row has no staple record -- [relation] names the attachment
/// relation that IS the connection, so an editor that changes the coordinate
/// writes that relation rather than minting a staple that would then contradict
/// it. That is what keeps "Start time" from being special: it is one row in this
/// list, with the same fields as every other row, and NO RECORD MOVES.
/// [fars] is every end the connection identifies this one WITH, in authored
/// order; [far] is its single member for the pair case and null otherwise, which
/// is what a one-counterpart editor field still wants to read.
///
/// [positions] says whether this connection makes a claim about WHERE. The
/// implicit placement and every authored staple record do; a membership, a
/// containment and a coordinate-less attachment say only that two things are
/// connected, and a derivation about position must not read a claim out of a
/// sentence that made none. It is what keeps LISTING everything (ruled 9.1) from
/// silently becoming POSITIONING from everything.
typedef ConnectionRow = ({
  bool implicit,
  Relation? relation,
  Relation? staple,
  String? kind,
  StapleEnd? near,
  StapleEnd? far,
  List<StapleEnd> fars,
  bool positions,
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
  Rational? frameEndDays(StapleEnd? end) =>
      end is FrameEnd ? positionDays(end.frame, end.position) : null;

  /// THE ONE READING of "where on this sheet does this position sit".
  ///
  /// Only a `coordinate` and a point of SIZE ZERO are one instant. A selector, a
  /// span, a void and a SIZED point are many-valued or empty, and reducing any
  /// of them to a single day here is exactly the collapse the correspondence
  /// rule forbids -- "Tuesdays" would silently become one arbitrary Tuesday, and
  /// "all of era 2" would become one arbitrary year of it. Those positions
  /// answer [frameEndMatches] instead, which is a membership question rather
  /// than a location one.
  ///
  /// Every seam asks HERE. `framesProject` reads which sheets a point relates,
  /// `Correspondences` reads where an instant lands, and the anchor derivation
  /// reads where an object sits; three readings of one authored position could
  /// disagree, and one cannot.
  Rational? positionDays(String frameId, Position? position) {
    if (position == null) return null;
    final at = position.coordinate;
    if (at != null) return daysOf(frameId, at);
    final region = pointRegionOf(frameId, position);
    return region != null && region.from == region.to ? region.from : null;
  }

  /// The region an authored point names on [frameId], or null.
  ({Rational from, Rational to})? pointRegionOf(String frameId, Position? position) {
    final law = lawOf(frameId);
    if (law == null) return null;
    try {
      return lawPointRegion(law, position);
    } catch (_) {
      return null;
    }
  }

  /// Why an authored point on [frameId] could not be read, in the author's own
  /// words, or null when it reads -- or names no point to begin with.
  ///
  /// The query path swallows refusals so one broken frame cannot take a whole
  /// projection offline; this is how a surface asks what was swallowed. "The
  /// end of the Dawn Era" has no answer, and saying so is the answer.
  String? pointRefusal(String frameId, Position? position) {
    if (pointSourceOf(position?.point) == null) return null;
    final law = lawOf(frameId);
    if (law == null) return 'Frame $frameId has no coordinate law, so it has no points to name.';
    if (law.extentDays == null) {
      return '${_frameTitle(frameId)} does not say where it begins or ends, so it'
          ' cannot label a point along its own line. A staple reaching it'
          ' connects to all of it.';
    }
    try {
      lawPointRegion(law, position);
      return null;
    } catch (error) {
      return refusalText(error);
    }
  }

  String _frameTitle(String frameId) {
    final title = declaredText(document.frames[frameId]?.title);
    return title.isEmpty ? frameId : title;
  }

  /// The frame end this staple names an instant at, or null. N-ARY: the staple
  /// may pierce several sheets at the one point it identifies, so this is the
  /// first end in AUTHORED ORDER that resolves to an instant rather than
  /// literally the first frame end -- a sheet whose law cannot read its
  /// coordinate must not take the whole staple offline when another sheet spells
  /// the same point readably.
  FrameEnd? instantEnd(Relation staple) {
    for (final end in staple.readEnds) {
      if (end is FrameEnd && frameEndDays(end) != null) return end;
    }
    return null;
  }

  /// The instant this staple itself names, or null for a connection whose
  /// instant comes from the objects it joins. Series derivations use this: a rule
  /// segment is cut at an instant, and a series end never connects to another
  /// object, so a series staple always has a frame end to read.
  Rational? stapleDays(Relation staple) => frameEndDays(instantEnd(staple));

  /// The coordinate space a frame's positions are actually written in. Two
  /// frames that resolve to the same owner ARE one sheet (every era frame of one
  /// calendar), and an unresolvable law is its own sheet -- a broken declaration
  /// relates to nothing rather than to everything.
  String coordinateSpaceOf(String frameId) => lawOf(frameId)?.frameId ?? frameId;

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
            if (staple.readEnds.whereType<T>().any((end) => end.id == id)) staple,
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
      // NO KIND GATE (the verb law). SENTENCES.md says the structural reading
      // outright -- "two frame points made one is what we call a
      // correspondence" -- so a correspondence is a SHAPE, not a word: this
      // frame's own end, another frame's end, both points made one. The gate
      // that read `kind != 'correspondence'` meant an era boundary spelled
      // `succession` corresponded two sheets and was invisible to every caller
      // asking whether they correspond, while the identical staple spelled
      // `correspondence` was not. [successionEdges] already reads that boundary
      // off the points with no kind gate; this is the same document read the
      // same way.
      final ends = staple.readEnds;
      // Oriented per END rather than per staple: a frame stapled to itself at
      // two different points is a legitimate correspondence (a loop), and it has
      // to enumerate from both of its own ends rather than arbitrarily from one.
      //
      // N-ARY: one staple may say three points are one point, and that is three
      // ORDERED PAIRS from each of this frame's own ends -- every sheet the
      // metal pierces corresponds to every other, which is what makes a staple
      // through a third frame relate the first two.
      for (final (index, from) in ends.indexed) {
        if (from is! FrameEnd || from.frame != frameId) continue;
        for (final to in staple.othersThan(index)) {
          if (to is! FrameEnd) continue;
          if (counterpartId != null && to.frame != counterpartId) continue;
          entries.add((staple: staple, from: from, to: to));
        }
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

  /// The object's own placement, which is a staple like every other connection:
  /// its start identified with a point on a frame. The name survives the melt
  /// because callers ask a question about the OBJECT, not about a record kind.
  Relation? placementRelation(String objectId) => placementOf(objectId);

  /// A SERIES' TEMPLATE PLACEMENT, DERIVED -- AND ONLY DERIVED.
  ///
  /// The pattern names its template EVENT and an event's placement is derivable
  /// from the event, so storing the placement's id a second time was what made
  /// "minted without it" a reachable silent state at all (ISSUES 9.1). The field
  /// is not written and is NOT READ: a record that still carries one keeps it,
  /// byte for byte, and it means nothing. There is one truth and this is it.
  Relation? templatePlacement(Pattern pattern) {
    final event = pattern.templateEvent;
    return event == null ? null : placementOf(event);
  }

  /// AN OBJECT WHOSE ONLY POSITION IS A STAPLE (ISSUES 9.1, "New todo on this").
  ///
  /// A placement is read as an implicit start staple to a frame. This is that
  /// reading run BACKWARDS, and it is the same one sentence: a staple that says
  /// this object's point and a positioned point are ONE POINT has already said
  /// where the object is, so there is nothing left for a companion placement
  /// record to add -- and a companion record is worse than redundant, because it
  /// bakes in a coordinate that goes stale the moment the far end is re-said,
  /// while the staple rides.
  ///
  /// The extent substrate already resolves through object-to-object staples
  /// transitively and already refuses on cycles and unreachable ends; what was
  /// missing is that nothing ENUMERATED such an object, so it resolved to a
  /// position no surface ever asked for. This is that enumeration, grouped by the
  /// frame the staples land the object on, as the placement the staples say.
  ///
  /// The relations handed back are DERIVED and are never in the document: they
  /// carry the staple's own id in their provenance so a surface can say which
  /// sentence positions the object, and their id is stable across generations so
  /// dedupe and selection hold still.
  late final ({Map<String, List<Relation>> byFrame, Map<String, String> refusals})
  stapledPlacements = _deriveStapledPlacements();

  ({Map<String, List<Relation>> byFrame, Map<String, String> refusals}) _deriveStapledPlacements() {
    // AN OBJECT IS ALREADY SPOKEN FOR when some staple names it AND names a
    // frame -- placed there, or affiliated with it -- because the explicit pass
    // enumerates it through that connection. What is derived here is the object
    // whose only connections are to other OBJECTS, which nothing else would ever
    // offer to a frame.
    final attached = <String>{}, stapled = <String>{};
    for (final relation in document.relations.values) {
      if (!relation.isStaple) continue;
      final objects = [
        for (final end in relation.ends)
          if (end is ObjectEnd) end.object,
      ];
      stapled.addAll(objects);
      if (relation.ends.any((end) => end is FrameEnd)) attached.addAll(objects);
    }
    final byFrame = <String, List<Relation>>{};
    final refusals = <String, String>{};
    for (final objectId in stapled.toList()..sort()) {
      // An object with ANY attachment already enumerates through it -- including
      // the coordinate-less one that is bare membership, which the explicit pass
      // places from its resolved extent. Only an object nothing has ever placed
      // is derived here, so no object is ever offered twice.
      if (attached.contains(objectId) || !document.events.containsKey(objectId)) continue;
      final Extent extent;
      try {
        extent = resolveObjectExtent(objectId);
      } on Object catch (failure) {
        refusals[objectId] = refusalText(failure);
        continue;
      }
      final days = extent.startDays, frame = extent.frame;
      if (days == null || frame == null) {
        // A REFUSAL IS OWED ONLY WHERE A POINT WAS NAMED (ISSUES 9.2, the email
        // note). "An object whose connections are ALL affiliations is not
        // 'positioned only by connections that fail' -- it is unpositioned by
        // design, and the correct surface for that is silence on the lens."
        // Something has to have gone wrong for there to be anything to say, so
        // the failed claim itself is the gate: an unresolved point-naming
        // anchor, or a loop.
        if (extent.unresolved.isNotEmpty || extent.cyclic) {
          refusals[objectId] = _unpositioned(objectId, extent);
        }
        continue;
      }
      final coordinate = lawOf(frame)?.fromDays(days).toJson();
      if (coordinate == null) {
        refusals[objectId] =
            'Frame $frame has no coordinate law, so nothing can be'
            ' written on it.';
        continue;
      }
      final staple = extent.anchors.firstOrNull?.staple;
      (byFrame[frame] ??= []).add(
        Relation(
          id: 'staple-placement/${staple?.id ?? objectId}/$objectId',
          type: 'staple',
          extra: {
            'kind': 'anchor',
            'role': 'placed',
            'provenance': {'kind': 'staple', 'staple': ?staple?.id},
            'ends': [
              ObjectEnd(objectId, point: startPoint).toJson(),
              FrameEnd(frame, position: Position.coordinate(Json.from(coordinate))).toJson(),
            ],
          },
        ),
      );
    }
    return (byFrame: byFrame, refusals: refusals);
  }

  /// WHY A STAPLED OBJECT STILL SITS NOWHERE, in words. A cycle and an
  /// unreachable far end are different facts and are told apart, because the
  /// author fixes them differently: one is a loop to break, the other a point to
  /// say.
  String _unpositioned(String objectId, Extent extent) {
    final title = str(document.events[objectId]?.payload?['title']);
    final named = title == null || title.trim().isEmpty ? objectId : '"$title"';
    if (extent.cyclic) {
      return '$named is positioned only by connections, and they resolve back'
          ' through it -- a loop places nothing. Say one of these points against'
          ' something already positioned.';
    }
    final reasons = {for (final contest in extent.unresolved) contest.reason};
    return reasons.isEmpty
        ? '$named is connected to nothing that has a position, so there is nowhere'
              ' to draw it.'
        : '$named is positioned only by connections, and ${reasons.join('; ')}.';
  }

  /// THE OBJECT'S WHOLE CONNECTION SET -- ALL OF IT (Don, ruled 2026-09-01).
  ///
  /// One list, and now it is one loop: a connection IS a staple, so there is no
  /// implicit row to synthesize from a placement record and no table of other
  /// record kinds to fold in. Both accommodations are gone with the kinds they
  /// accommodated -- a record still spelled `attachment`, `membership` or
  /// `contains` is inert data and is listed by nobody, because nothing reads it.
  ///
  /// One ROW PER OWN END, not per staple: a staple that pierces this object at
  /// two of its own points says two things about it, and a row that named only
  /// the first would leave the second unauthorable.
  List<ConnectionRow> effectiveObjectStaples(String objectId) {
    final rows = <ConnectionRow>[];
    for (final staple in staplesForObject(objectId)) {
      for (final index in staple.endIndexesOf<ObjectEnd>(objectId)) {
        final fars = staple.othersThan(index);
        rows.add((
          implicit: false,
          relation: null,
          staple: staple,
          kind: staple.kind,
          near: staple.readEnds[index],
          far: fars.length == 1 ? fars.single : null,
          fars: fars,
          // An affiliation says the two belong together and nothing about where,
          // so a derivation about position must read no claim out of it -- and
          // WHICH POINT THIS END NAMES is that distinction, said in the record
          // rather than in the word on it. The whole of a thing is not a point
          // any position can be read off; every other point is.
          positions: endPoint(staple.readEnds[index]) != wholePoint,
        ));
      }
    }
    return rows;
  }

  /// Every anchoring connection this object participates in, resolved and
  /// ordered by role precedence.
  ///
  /// ONE ANCHOR PER POINT PER SHEET. A point holds one position in each
  /// coordinate space, so a claim naming this object's start on frame A and a
  /// claim naming it on frame B are ONE POINT ON TWO SHEETS -- both believed,
  /// both readable through [AnchorSet.positions], neither a rival for the other.
  /// That is the staple's own definition: the n points it names ARE one point.
  ///
  /// A CONTEST is the narrower thing: two claims in the SAME coordinate space
  /// that DISAGREE. It is not an error (the collection is open, and rejecting it
  /// would lose authored data) but it cannot also be believed, so it is reported
  /// as overdetermined and left alone, never averaged. Two claims in one space
  /// that AGREE are the same point said twice -- a restatement, not a rival, and
  /// nothing to report.
  AnchorSet objectAnchors(String objectId) => _anchorsOf(objectId, _newResolution());

  AnchorSet _anchorsOf(String objectId, _Resolution resolution) {
    // Emission order is kept so the tie-break below is total: several claims can
    // come off ONE staple (the n-ary case), which makes the staple id alone an
    // equal key. Authored end order decides between them.
    final claims = <({ResolvedAnchor anchor, int order})>[];
    final overdetermined = <Contest>[], unresolved = <Contest>[];
    var cyclic = false;
    var order = 0;
    for (final staple in staplesForObject(objectId)) {
      // NO KIND GATE (the verb law, ISSUES 8.31 and the 9.3 melt). The gate here
      // read `stapleKind(kind)?.anchors`, so the same identification anchored
      // this object's point spelled `anchor` and said nothing spelled anything
      // else -- a word choosing a derivation. Every filter that gate stood in
      // for is written below and is structural: an end naming the WHOLE claims
      // no point, an end identified with nothing places nothing, and a far end
      // that does not resolve is reported unresolved. A staple whose verb
      // nobody has ever typed anchors exactly as `anchor` does.
      //
      // Traversing an edge must not count as arriving back at it. A staple
      // between A and B is ONE edge, and because direction is not stored both
      // objects see it; asking B where it is while resolving A would otherwise
      // find that same staple pointing back at A and call it a cycle. Skipping
      // the edge already being crossed is what leaves a real cycle -- two
      // DIFFERENT staples closing a loop -- as the only thing the path guard
      // fires on.
      if (resolution.crossed.contains(staple.id)) continue;
      // One pass PER OWN END: a staple may pierce this object at more than one
      // of its own points, and each of those points is anchored by everything
      // else the staple names.
      for (final index in staple.endIndexesOf<ObjectEnd>(objectId)) {
        final near = staple.readEnds[index];
        final role = endPoint(near);
        // AN ANCHOR CANNOT NAME THE WHOLE (ruled 2026-09-01). A point of size
        // `all` is the entire extent, and an anchor asks where ONE point sits --
        // so a staple that anchors this object by its whole is saying something
        // no position can be derived from.
        //
        // AND IT IS NOT A CONTEST (Don, ISSUES 9.2): "Whole to whole says THIS
        // IS CONNECTED TO THAT." An affiliation is not a claim on a point, so it
        // cannot FAIL to resolve one -- reporting it as unresolved is what wrote
        // the ultra-long extent note and the lens-top banner about the email
        // note. The derivation passes over it in SILENCE: the object is
        // unpositioned by design, which is a fact its card states in one line
        // and no surface refuses over.
        if (role == wholePoint) continue;
        final fars = staple.othersThan(index);
        if (fars.isEmpty) {
          unresolved.add(
            _contest(
              role,
              'this staple identifies nothing with this point, so it places nothing',
              staple: staple,
            ),
          );
          continue;
        }
        // EVERY other end is a claim on this one point. With three ends that is
        // two claims, and under the identification they are two spellings of one
        // instant rather than a fight.
        for (final far in fars) {
          Rational? days;
          var spread = spreadDays(staple) ?? SpreadDays.zero;
          String? frame;
          if (far is FrameEnd) {
            days = frameEndDays(far);
            frame = far.frame;
          } else if (far is ObjectEnd) {
            // A connection whose other end resolves back through this object
            // cannot be resolved at all: the pair would each be waiting on the
            // other. Reported rather than iterated to a fixed point, because
            // there is no instant to report and guessing one would place an
            // object nobody positioned.
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
            // A cycle anywhere below makes THIS answer path-dependent too, so it
            // has to travel up: the memo is only safe for a subtree that
            // resolved without one, and a diamond over a cycle would otherwise
            // cache an answer that is only true for the path it was reached by.
            if (upstream.cyclic) cyclic = true;
            final point = endPoint(far);
            days = extentPointDays(upstream, point, offsetDays: magnitudeDays(far.offset));
            // THE FAR SIDE OF AN AFFILIATION, silent for the same reason as the
            // near side (ISSUES 9.2): a whole is not an instant, so nothing is
            // derived -- and nothing was claimed, so nothing is contested.
            if (point == wholePoint) continue;
            if (days != null) {
              spread = spread + upstream.spread;
              frame = upstream.frame;
            }
          }
          if (days == null) {
            unresolved.add(
              _contest(
                role,
                "this connection's other end has no resolvable position",
                staple: staple,
              ),
            );
            continue;
          }
          claims.add((
            anchor: (
              role: role,
              staple: staple,
              end: near,
              days: days,
              spread: spread,
              frame: frame,
            ),
            order: order++,
          ));
        }
      }
    }
    claims.sort((left, right) {
      final byRole = _rolePrecedence(left.anchor.role) - _rolePrecedence(right.anchor.role);
      if (byRole != 0) return byRole;
      final byStaple = _byStableOrder(left.anchor.staple, right.anchor.staple);
      return byStaple != 0 ? byStaple : left.order - right.order;
    });

    final resolved = <ResolvedAnchor>[];
    final positions = <String, Map<String, Rational>>{};
    for (final claim in claims) {
      final anchor = claim.anchor;
      final sheet = positions.putIfAbsent(anchor.role, () => <String, Rational>{});
      final standing = sheet[spaceOfFrame(anchor.frame)];
      if (standing == null) {
        sheet[spaceOfFrame(anchor.frame)] = anchor.days;
        resolved.add(anchor);
      } else if (standing != anchor.days) {
        overdetermined.add(
          _contest(
            anchor.role,
            'another connection already anchors this point in the same '
            'coordinate space, at a different instant',
            staple: anchor.staple,
            days: anchor.days,
          ),
        );
      }
      // standing == days: one point said twice. Agreement is not a contest.
    }

    // THE PLACEMENT BLOCK IS GONE (ruled 2026-09-01). It existed to fold a
    // record of another kind into this pass as if it were a staple; the
    // placement IS a staple now, so the loop above already walked it, and
    // keeping a second path would be two readings of one record disagreeing.

    return (
      anchors: resolved,
      overdetermined: overdetermined,
      unresolved: unresolved,
      positions: positions,
      cyclic: cyclic,
    );
  }

  /// The coordinate space a nullable frame reference names. A connection whose
  /// upstream chain never reached a frame has no sheet, and the empty key is that
  /// -- distinct from every frame's own space, so two space-less claims on one
  /// point still contest each other.
  String spaceOfFrame(String? frameId) =>
      frameId == null || frameId.isEmpty ? '' : _spaces[frameId] ??= coordinateSpaceOf(frameId);

  final Map<String, String> _spaces = {};

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
    // [startDays] and [endDays] are ONE PAIR OF NUMBERS, so they can only answer
    // in one coordinate space: the leading anchor's. Anchors on other sheets are
    // the same points spelled elsewhere -- carried whole in `anchors` and
    // `positions`, believed, and never contested against these. Only the sheet
    // being answered in can overdetermine the answer.
    final sheet = anchors.isEmpty ? '' : spaceOfFrame(anchors.first.frame);
    final here = [
      for (final anchor in anchors)
        // A claim whose chain never reached a frame belongs to no sheet, so it
        // is not on ANOTHER one either: it still pairs with the sheet being
        // answered in. Only two KNOWN and DIFFERENT spaces separate.
        if (sheet.isEmpty ||
            spaceOfFrame(anchor.frame).isEmpty ||
            spaceOfFrame(anchor.frame) == sheet)
          anchor,
    ];
    final derived = here.length >= 2 ? _derivedMagnitude(here[0], here[1]) : null;

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
    if (here.isNotEmpty) {
      final leading = here.first;
      final size = derived == null ? magnitude : derived.abs();
      final (start, end) = _fromAnchor(leading, size);
      final spread = derived == null ? leading.spread : leading.spread + here[1].spread;
      return Extent(
        startDays: start,
        endDays: end,
        magnitudeDays: size,
        source: derived == null ? 'anchor+magnitude' : 'anchors',
        derivedMagnitude: derived != null,
        anchors: anchors,
        overdetermined: [
          ...found.overdetermined,
          for (final other in here.skip(derived == null ? 1 : 2))
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
        positions: found.positions,
        cyclic: found.cyclic,
        spread: spread,
        frame: leading.frame,
      );
    }

    // A zero-staple object is legitimate -- LEXICON.md: "Zero-staple objects are
    // possible; most carry one or more." It simply has no extent to report,
    // which a caller must handle rather than be handed a fabricated date for.
    // And it really is zero-staple now: a placement is an anchoring staple like
    // any other, so there is no second kind of record left to fall back to.
    return Extent(
      magnitudeDays: magnitude,
      // "Nobody said" and "somebody said something that will not resolve" are
      // different facts and are named differently, or a broken coordinate reads
      // as an object nobody ever placed.
      source: found.unresolved.isEmpty && !found.cyclic ? 'unstapled' : 'unresolved',
      overdetermined: found.overdetermined,
      unresolved: found.unresolved,
      positions: found.positions,
      cyclic: found.cyclic,
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
    final template = templatePlacement(pattern);
    final partitioning =
        <({Relation staple, FrameEnd end, Rational days})>[
          for (final staple in staplesForSeries(pattern.id))
            if (stapleKind(staple.kind)?.partitions ?? false)
              if (instantEnd(staple) case final FrameEnd end)
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

  /// The set of whole days a series' live exclusions cover, over a bounded
  /// window: the days events on the referenced FRAMES occupy, plus the days a
  /// SELECTOR matches.
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
    // THE SECOND EXCLUSION SENTENCE: "except every time that matches" (ISSUES
    // 8.31, evening: "no clear way to put in an except weekends and holidays").
    // A selector is the {cycle, value} form the position selectors already
    // speak, read against the frame it NAMES -- so "Saturday" means whatever
    // that frame's own declaration says a Saturday is, and there is no second
    // matcher and no set of legal selector kinds.
    final selectors = [
      for (final row in asList(exclude?['selectors']))
        if (obj(row) case final Json selector) selector,
    ];
    if (frames.isEmpty && selectors.isEmpty) return null;
    final days = <String>{};
    final from = lower.floor(), to = upper.floor();
    for (final selector in selectors) {
      final law = lawOf(str(selector['frame']) ?? '');
      if (law == null) continue;
      for (var day = from; day <= to; day += BigInt.one) {
        if (_selectorMatches(law, selector, Rational(day))) days.add('$day');
      }
    }
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
// one surviving flag says it partitions a series. This is the convenience a
// single-end-staple editor field still wants, and the one place the engine, the
// series editor and ICS export all find that record.
//
// STILL SPELLED BY THE WORD, and it is the same open ruling [StapleKind.partitions]
// carries: on a SERIES, `end`, `phase` and `inflection` are one shape, so a
// structural finder here would hand the series editor a phase staple to
// overwrite. The word stays until Don says what `[series <-> instant]` means.

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
