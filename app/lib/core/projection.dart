// Pure Dart. Nothing under lib/core/ may import Flutter or a third-party
// package.
//
// PROJECTION IS BOOLEAN ALGEBRA OVER CONNECTIONS (Don, 2026-08-26).
//
// A projection is an expression in the ONE MATH (`math.dart`) over open
// identifiers, and an identifier names a frame. The leaf question is always the
// same one: IS THIS OBJECT INCLUDED BY THAT FRAME -- answered over the four ruled
// connection routes, which are placement, membership (transitively),
// staple-to-frame, and staple-to-object. `or` is union, `and` is intersection,
// `not` is complement within the universe the terms name, `xor` is what it says.
// Selecting a frame is `Projection.of([frame])`, and selecting three frames is
// their OR: union by default, because that is what a person means by picking
// three calendars.
//
// CONNECTION IS NOT INCLUSION (Don, ruling on the leaf predicate). The two words
// are not synonyms and this file is careful with them. In Don's own example: "an
// event on two frames does connect them but does not include them. If a' is on A
// and B, and I project A I get a' but not B... if I project A and B then I get A,
// B, and a' -- and A and B are connected at a'." Every connection is real and
// nothing here erases one: the graph is what Lines draws and what graph distance
// for weight traverses. What a connection does NOT do is drag the far frame's
// content into a projection that never named it. [ProjectionEngine.includes] is
// where that distinction is executable, and it says so at both of its halves.
//
// WHAT THIS REPLACES, and it is replacement rather than a layer (JC-1): the
// query selector (a second, parallel, non-composable matcher) is a leaf predicate
// in `indexes.dart` now; the ordinary/display membership duality is one pool; and
// the state-gate -- frame-selection-as-visibility, which silently dropped a ToDo
// whose state frame was unselected -- has no counterpart anywhere. Filters are
// authored as NOT, so the three refusals that used to greet a negation are gone,
// not relocated.
//
// NOT GATES VISIBILITY AND NEVER MODIFIES WEIGHT (ruling 10). A negated term is
// carried MARKED into the weight rings rather than filtered out of them, so that
// invariant is enforced in one place -- `weight.dart`'s `composeWeight` -- rather
// than trusted to every caller.
//
// D13/D14 ARE DEAD: `queryState` and the `frame.law.pattern` formula branches
// were unreachable (no authoring surface writes `frame.law`, and
// `pattern.exports` names nothing). Pattern dispatch is still an OPEN SEAM --
// [_expand] has exactly one switch point, and `ics-rrule` is one COMPILED
// DIALECT sitting at it. A native one-math expression pattern plugs in beside it
// without restructuring anything above.

import 'coordinate_entry.dart';
import 'coordinate_law.dart';
import 'correspondence.dart';
import 'document.dart';
import 'era_chain.dart';
import 'eras.dart' show firstMatch, refusalText;
import 'exact.dart';
import 'falloff.dart';
import 'frame_projection.dart';
import 'indexes.dart';
import 'math.dart';
import 'object_kinds.dart';
import 'ops.dart';
import 'records.dart';
import 'recurrence_end.dart' show RecurrenceEnd;
import 'rrule.dart';
import 'staples.dart';
import 'strategic_density.dart' show FactIdentity, stableFactKey;
import 'weight.dart';

// --- Computation bounds -----------------------------------------------------
//
// COORDINATOR RULING: these are COMPUTATION tuning and are exempt from ruling 9,
// which governs what is SHOWN. Ruling 9 killed the thirteen scattered per-lens
// truncation caps because a display cap is one derived budget the caller owns --
// which is why `queryFacts` takes its limit as a PARAMETER and holds no number.
// The bounds below are about how much generated work is worth keeping in memory
// between queries; no arrangement of them can hide a fact from a caller who asked
// for it, only make the second ask slower.

/// A COUNT-bounded rule whose whole life is worth caching at once.
const int maxCachedRecurrenceCount = 256;

/// The whole-series cache's total fact budget.
const int maxRecurrenceSeriesFacts = 12000;

/// The windowed cache's entry and fact budgets, and its window width in days.
const int maxRecurrenceWindows = 256;
const int maxRecurrenceWindowFacts = 16000;
const int recurrenceWindowDays = 64;

// --- The projection expression ----------------------------------------------

/// A projection: one expression in the one math, plus what its identifiers name.
///
/// BINDINGS exist because a frame id is not a legal identifier in the math's
/// grammar (`frame:wall-time` is three tokens). A selection built from ids
/// therefore builds its tree directly and binds nothing; an AUTHORED expression
/// is written in whatever names the author has -- a frames browser knows the
/// mapping -- and binds them here. Either way the tree, the parser and the
/// evaluator are the same ones weight formulas and falloff use.
class Projection {
  Projection(this.expression, {this.bindings = const {}});

  /// The default for a plain frame selection: OR of the selected frames. Union
  /// by default, and built as a tree rather than as text, so no id has to survive
  /// a tokenizer that was never asked to accept one.
  factory Projection.of(Iterable<String> frameIds) {
    final ids = frameIds.toList();
    if (ids.isEmpty) return Projection(const Lit(false, 0));
    var tree = Name(ids.first, 0) as Expr;
    for (final id in ids.skip(1)) {
      tree = Binary('or', tree, Name(id, 0), 0);
    }
    return Projection(tree);
  }

  /// An authored projection. Refusals are [MathRefusal] and carry a position, so
  /// an editor can point at the character that defeated it.
  factory Projection.parse(String source, {Map<String, String> bindings = const {}}) =>
      Projection(parse(source), bindings: bindings);

  final Expr expression;
  final Map<String, String> bindings;

  /// The frames this projection names, in tree order, deduped. Tree order is the
  /// contract: the FIRST is the primary -- whose law reads the query window, and
  /// which goes last among the weight rings as the projecting frame.
  late final List<String> frames = {for (final identifier in _walk(expression)) frameOf(identifier)}
      .toList();

  /// The frames a NOT reaches. A frame appearing both negated and positive is
  /// NOT marked: it is a real modifier somewhere in the expression, and the mark
  /// exists to keep a purely negative term out of the weight chain.
  late final Set<String> negatedFrames = () {
    final polarity = <String, bool>{};
    _polarity(expression, false, polarity);
    return {
      for (final entry in polarity.entries)
        if (entry.value) frameOf(entry.key),
    };
  }();

  String? get primaryFrame => frames.isEmpty ? null : frames.first;

  String frameOf(String identifier) => bindings[identifier] ?? identifier;

  /// Is this object in the projection's UNIVERSE at all?
  ///
  /// The universe is the OR of every frame the expression names, negated ones
  /// included -- which is what "NOT is complement within the OR-ed universe"
  /// means literally. A projection talks about the frames it names and about
  /// nothing else, so `not b` selects nothing rather than the whole document, and
  /// De Morgan holds on populations because both sides complement within the same
  /// set.
  bool inUniverse(bool Function(String frameId) includes) => frames.any(includes);

  /// Does this projection admit an object with these connections?
  ///
  /// Strictly a truth value: an expression that evaluates to a number is a
  /// refusal, not a truthy guess, because meaning is authored and a type
  /// confusion is not a meaning.
  bool admits(bool Function(String frameId) includes) {
    final value = evaluate(expression, Env(resolver: (name) => includes(frameOf(name))));
    if (value is bool) return value;
    throw const MathRefusal('A projection must come to a truth value, not a number');
  }

  @override
  String toString() => '$expression';

  static List<String> _walk(Expr node) => [
    if (node is Name) node.name,
    for (final child in childrenOf(node)) ..._walk(child),
  ];

  static void _polarity(Expr node, bool negated, Map<String, bool> out) {
    if (node is Name) {
      out[node.name] = (out[node.name] ?? true) && negated;
      return;
    }
    final flip = node is Unary && node.op == 'not';
    for (final child in childrenOf(node)) {
      _polarity(child, flip ? !negated : negated, out);
    }
  }
}

// --- What a projection produces ---------------------------------------------

/// One projected fact: an object, the placement that puts it there, and the
/// exact day it resolved to.
///
/// [day] is EXACT and always present -- the field report the virtual-fact
/// resolution fix turned on: "every projected occurrence carries its own day", so
/// nothing downstream has to reconstruct a window to find what it just drew.
class Fact {
  Fact({
    required this.kind,
    required this.event,
    required this.relation,
    required this.day,
    required this.coordinate,
    this.virtualId = '',
    this.precision,
    this.extent,
    this.pattern,
  });

  /// `explicit` for an authored placement, `virtual` for a generated occurrence.
  final String kind;
  final Event event;
  final Relation relation;
  final Rational day;
  final Json coordinate;

  /// The occurrence's stable virtual id, or empty for an authored placement.
  final String virtualId;

  /// AUTHORED PRECISION: THE LEVEL THE AUTHOR STOPPED AT, by name.
  ///
  /// A coordinate of `{year: 1973}` resolves to the start of 1973 and comes back
  /// from the law with every level filled in, at which point it is
  /// indistinguishable from an authored January 1st midnight -- the missing
  /// levels supplied by the law, not by the author. So depth is read from the
  /// SOURCE coordinate and travels here.
  ///
  /// A NAME rather than a count, because that is the thing consumers compare: the
  /// partition-close rule asks whether the depth is below the base ladder, which
  /// is a question about which rung it is. A count would also read a
  /// rung-skipping coordinate as coarser than authored -- `{year, day}` on a
  /// year/month/day ladder stopped at the DAY.
  final String? precision;

  /// The resolved extent, for a fact placed by anchoring connections, so a
  /// renderer can read spread and overdetermination without re-deriving them.
  final Extent? extent;

  /// The pattern this occurrence came from. ONE provenance for a whole series:
  /// every segment's facts name the same pattern, because a rule change is not a
  /// new identity.
  final String? pattern;

  /// What dedupe and the stable order key on. The RELATION, not the event: two
  /// relations placing one event on two member frames are two real placements.
  String get identity => virtualId.isEmpty ? relation.id : virtualId;

  FactIdentity get order =>
      (day: day, event: event.id, virtualId: virtualId, relation: relation.id);
}

/// A refusal one query collected, in the author's own words. `source` is
/// whatever produced it -- a pattern id for a pattern, a frame id for a frame --
/// so one channel carries both.
typedef ProjectionError = ({String source, String message});

/// What one query came to. `truncated` is A LOWER BOUND, never a silent drop:
/// true means at least one more fact existed inside the window than the caller's
/// budget allowed. `fromDays`/`toDays` are the window as the primary frame's own
/// law read it, so a caller can see what it actually asked about.
typedef QueryResult = ({
  List<Fact> facts,
  List<ProjectionError> errors,
  bool truncated,
  Rational fromDays,
  Rational toDays,
});

typedef _Explicit = ({List<Fact> facts, Rational maxDuration, String? error});

// --- The engine -------------------------------------------------------------

/// One edge of the connection graph, in the vocabulary of the connection that
/// made it. A kind is a string, not an enum: an unfamiliar connection is data a
/// later surface may learn to draw rather than a crash.
typedef GraphEdge = ({String from, String to, String kind});

const String containsEdge = 'contains', stapleEdge = 'staple';
const String membershipEdge = 'membership', placementEdge = 'placement';

/// How a STRUCTURAL predicate is spelled as a name a person can bind: the word
/// `stapled`, then the noun the far end of the staple calls itself. Written
/// once, here, so the projection engine and every surface that offers the term
/// spell it the same way.
const String stapledTerm = 'stapled:';

class ProjectionEngine {
  ProjectionEngine(Document document, {AuthoredDepthOf? precisionOf})
    : precisionOf = precisionOf ?? authoredDepth {
    // The era lookup reads `this.document` rather than a captured one, so it is
    // current after every edit; the raw map argument is ignored, exactly as
    // `eraLookup` documents, because that map and this document describe the same
    // document by construction here.
    laws = CoordinateLaws(eras: (_, frameId) => frameEraContext(this.document, frameId));
    setDocument(document);
  }

  /// The authored-precision seam, defaulting to `coordinate_entry.dart`'s own
  /// [authoredDepth] -- ONE derivation, so the partition-close rule and this
  /// engine cannot disagree about what an author wrote.
  final AuthoredDepthOf precisionOf;

  late final CoordinateLaws laws;
  late Document document;
  late Indexes indexes;
  late Staples staples;
  late ObjectFacts facts;

  /// The document in the map form [CoordinateLaws] caches on -- FRAMES ONLY,
  /// because that is every key law resolution reads (`coordinate`,
  /// `coordinateDefinition`, `basis`, `kind`). Serializing the whole document per
  /// reindex would cost a full deep copy of the relation map to answer a question
  /// about frames; keeping the same map object between edits that touched no
  /// frame is what keeps the law cache warm.
  late Map<String, Object?> _raw;

  FrameProjection? _frameProjection;
  Correspondences? _correspondences;

  final Map<String, List<Fact>> _explicit = {};
  final Map<String, Rational> _maxDuration = {};
  final Map<String, List<ProjectionError>> _errors = {};
  final Map<String, Map<String, int>> _reach = {}, _above = {};
  final Map<String, Set<String>> _terms = {};
  final Map<String, List<Fact>> _series = {}, _windows = {};
  int _seriesFacts = 0, _windowFacts = 0;

  /// WHY A PATTERN PRODUCED LESS THAN IT SAYS (ISSUES 9.1). Kept beside the
  /// generated facts rather than thrown, so a series whose second segment is
  /// broken still delivers its first -- and says what the second cost. Dropped
  /// in lockstep with the caches the generator filled, because a refusal read off
  /// a cache hit that never re-ran the generator would be the silence again.
  final Map<String, String> _patternRefusals = {};

  // --- Being told what changed (D6) -----------------------------------------

  /// The full-rebuild path: a new document, nothing preserved.
  void setDocument(Document next) {
    document = next;
    _reindex(framesChanged: true, doomed: null);
  }

  /// THE ENGINE IS TOLD WHAT CHANGED. The JavaScript could not be, so it kept a
  /// fingerprint of every staple in the document and compared it on every
  /// `setDocument` to decide whether a caller's `preserveRecurrence` claim was
  /// safe -- a whole machinery of distrust, because a caller keyed its claim on
  /// which MAP a record lived in and a staple lives in the same map a plain
  /// attachment does. With ops as the change representation the question is
  /// answerable exactly, so the fingerprint and the distrust are gone.
  ///
  /// Applying the ops HERE, rather than taking an already-changed document beside
  /// them, is what makes the invariant statable and testable: this must answer
  /// identically to a full [setDocument] rebuild, for every sequence of ops.
  void applyChange(List<Op> ops) {
    if (ops.isEmpty) return;
    final doomed = _doomed(ops);
    final framesChanged = ops.any((op) => op.map == 'frames');
    document = applyOps(document, ops);
    _reindex(framesChanged: framesChanged, doomed: doomed);
  }

  /// Which patterns' generated occurrences these ops can have moved. Null means
  /// "any of them" -- a frame's law changed, and a law change can move every
  /// occurrence in the document.
  Set<String>? _doomed(List<Op> ops) {
    final doomed = <String>{};
    var attachmentTouched = false;
    for (final op in ops) {
      switch (op.map) {
        case 'frames':
          return null;
        case 'patterns':
          doomed.add(op.id);
        case 'events':
          for (final pattern in document.patterns.values) {
            if (pattern.templateEvent == op.id) doomed.add(pattern.id);
          }
        case 'relations':
          for (final relation in [document.relations[op.id], _asRelation(op)]) {
            if (relation == null) continue;
            if (relation.isStaple) {
              doomed.addAll(relation.ends.whereType<SeriesEnd>().map((end) => end.series));
            } else if (relation.type == 'attachment') {
              attachmentTouched = true;
            }
          }
          // DERIVED, and only derived (ruled 2026-09-01). A pattern's template
          // placement comes from its template event, so an edit to a connection
          // that places that event moves the series -- and nothing on the
          // pattern record says so, because nothing on it is asked.
          for (final pattern in document.patterns.values) {
            for (final relation in [document.relations[op.id], _asRelation(op)]) {
              if (relation?.event != null && relation!.event == pattern.templateEvent) {
                doomed.add(pattern.id);
              }
            }
          }
      }
    }
    if (attachmentTouched) {
      // A LIVE EXCLUSION is a reference to another frame's events, resolved at
      // projection time -- so adding a holiday changes a series with no edit to
      // the series, and the cached occurrences of any pattern that could be
      // reading one have to go. Conservative on purpose: over-dropping costs a
      // regeneration, under-dropping shows an occurrence that no longer happens.
      for (final pattern in document.patterns.values) {
        if (pattern.extra['exclude'] != null || indexes.staplesOf(pattern.id).isNotEmpty) {
          doomed.add(pattern.id);
        }
      }
    }
    return doomed;
  }

  Relation? _asRelation(Op op) => switch (op.value) {
    final Relation relation => relation,
    final Map<String, dynamic> json => Relation.fromJson(json),
    _ => null,
  };

  void _reindex({required bool framesChanged, required Set<String>? doomed}) {
    if (framesChanged) {
      _raw = {
        'frames': {for (final entry in document.frames.entries) entry.key: entry.value.toJson()},
      };
      laws.invalidate();
    }
    indexes = Indexes(document);
    // ONE engine-scoped substrate instance, not one per query: its extent memos
    // and the index reads it is handed are the whole point of the seam.
    staples = Staples(
      document,
      laws: laws,
      lawOf: (frameId) => laws.attempt(_raw, frameId).resolved,
      staplesOf: indexes.staplesOf,
      placementOf: indexes.placementOf,
      factsOf: (frameId) => [
        for (final fact in explicitFacts(frameId)) (day: fact.day, event: fact.event),
      ],
    );
    // ONE INSTANCE IS ONE GENERATION: the reindex is a new [ObjectFacts] rather
    // than a memo somebody has to remember to clear.
    facts = ObjectFacts(
      document,
      indexedChildren: indexes.childrenOf,
      indexedParents: indexes.parentsOf,
      indexedGroups: indexes.directGroupsOf,
      indexedStaples: indexes.staplesOf,
    );
    _explicit.clear();
    _maxDuration.clear();
    _errors.clear();
    _reach.clear();
    _above.clear();
    _terms.clear();
    _frameProjection = null;
    _correspondences = null;
    if (doomed == null) {
      _series.clear();
      _windows.clear();
      _patternRefusals.clear();
      _seriesFacts = 0;
      _windowFacts = 0;
      return;
    }
    for (final patternId in doomed) {
      _patternRefusals.remove(patternId);
      _seriesFacts -= _series.remove(patternId)?.length ?? 0;
      for (final key in _windows.keys.where((key) => virtualPatternId(key) == patternId).toList()) {
        _windowFacts -= _windows.remove(key)?.length ?? 0;
      }
    }
  }

  /// One frame's own indexes dropped, leaving everything else standing. The
  /// group union is never cached (see [_populate]), so nothing up an ancestor
  /// chain needs invalidating when a member changes.
  void refreshFrame(String frameId) {
    _explicit.remove(frameId);
    _maxDuration.remove(frameId);
    _errors.remove(frameId);
    _reach.clear();
    _terms.clear();
  }

  // --- Coordinates and laws -------------------------------------------------

  CoordinateLaw lawOf(String frameId) => laws.of(_raw, frameId);

  Rational coordinateDays(String frameId, Json? value) =>
      lawOf(frameId).toDays(Coordinate.fromJson(value));

  Json daysCoordinate(String frameId, Rational days) =>
      Json.from(lawOf(frameId).fromDays(days).toJson());

  /// Which frame's law reads a query window's own coordinates.
  ///
  /// Normally the queried frame itself; NULL when it owns no positional
  /// coordinate space, meaning "read the window through the registered standard
  /// boundary". This is the collapsed-to-one-day bug, fixed generally rather than
  /// by a trait test: a frame with no declared levels permissively reads a bare
  /// `day` level, so a year/month/day window became `[1, 1]` and every group
  /// answered zero. Deciding by CAPABILITY rather than by the `group` trait is
  /// what makes a group with a basis or its own ladder keep reading its own law,
  /// and an era or invented frame keep reading its own too.
  String? windowFrameFor(String frameId) {
    final law = laws.attempt(_raw, frameId).resolved;
    return law != null && law.positional ? frameId : null;
  }

  // --- Accessors (D15) ------------------------------------------------------

  /// An object's own occurrence-math duration, read through THIS document's law
  /// (the magnitude's own frame, normally the human-time measure) rather than the
  /// registered standard -- a duration measured against the wrong law is exactly
  /// the silent wrongness the coordinate-law layer exists to remove.
  Rational eventDurationDays(Event? event) => laws.durationDays(event?.duration, document: _raw);

  List<String> eventFrames(String eventId) => indexes.framesOf(eventId);

  List<String> eventCalendarFrames(String eventId) => [
    for (final frameId in indexes.framesOf(eventId))
      if (document.frames[frameId]?.traits.contains('calendar') ?? false) frameId,
  ];

  List<Pattern> matchingPatterns(String frameId) => indexes.patternsFor(frameId);

  // --- The whole connection graph -------------------------------------------

  /// Cross-frame correspondence over THIS document, built once per generation
  /// and sharing this engine's law cache. One instance, so no surface builds a
  /// second by deep-copying the document to ask one question.
  FrameProjection get frameProjection => _frameProjection ??= FrameProjection({
    ..._raw,
    'relations': {for (final entry in document.relations.entries) entry.key: entry.value.toJson()},
  }, laws: laws);

  /// The evaluable correspondence over THIS document, built once per generation
  /// on this engine's own substrate instance. [frameProjection] answers WHETHER
  /// two frames correspond; this answers WHERE an instant on one lands on the
  /// other, from the same authored staple set.
  Correspondences get correspondences => _correspondences ??= Correspondences(staples);

  /// The frame whose declaration actually governs [frameId]. Two frames
  /// resolving to one space correspond by identity and need no staple.
  String coordinateSpaceOf(String frameId) => frameProjection.coordinateSpaceOf(frameId);

  /// Every connection one record has, as edges away from it -- the whole graph,
  /// under the honest name. Deterministic: ids sort, so two runs over one
  /// document draw the same picture.
  ///
  /// CONNECTION IS NOT INCLUSION: this is the graph, not the projection. Both
  /// ends of every staple appear from either side by construction.
  List<GraphEdge> connectionsOf(String id) {
    final edges = <GraphEdge>[
      for (final child in indexes.childrenOf(id)) (from: id, to: child, kind: containsEdge),
      for (final parent in indexes.parentsOf(id)) (from: parent, to: id, kind: containsEdge),
      for (final group in indexes.directGroupsOf(id)) (from: id, to: group, kind: membershipEdge),
    ];
    for (final staple in indexes.staplesOf(id)) {
      for (final end in indexes.endsOf(staple)) {
        if (end.id != id) edges.add((from: id, to: end.id, kind: stapleEdge));
      }
    }
    if (document.events.containsKey(id)) {
      for (final frame in indexes.framesOf(id)) {
        edges.add((from: id, to: frame, kind: placementEdge));
      }
    } else {
      for (final member in indexes.memberObjects(id).toList()..sort()) {
        edges.add((from: member, to: id, kind: membershipEdge));
      }
      for (final attachment in indexes.attachmentsOf(id)) {
        if (attachment.event case final String event) {
          edges.add((from: event, to: id, kind: placementEdge));
        }
      }
    }
    return edges;
  }

  /// EVERY NAME THIS OBJECT IS ADMITTED UNDER, as one set.
  ///
  /// "The projection language must therefore admit object ids and graph
  /// predicates as names, not only frames -- a core extension." (Don, ISSUES
  /// 9.2, on authoring board columns: "one column for a frame shows all todos
  /// stapled to that frame, another all todos stapled to an OBJECT, another only
  /// paired todos".)
  ///
  /// THE ALGEBRA DOES NOT CHANGE. [Projection.admits] already takes a predicate
  /// over names; what was missing is which names an object answers to. So this
  /// is the one call every column and every lens makes --
  /// `projection.admits(engine.termsOf(id).contains)` -- and whether a term
  /// names a frame, another object or a shape of the graph is the caller's
  /// business and never the algebra's.
  ///
  /// Three sources, one vocabulary:
  ///  * every frame the object reaches -- its own placement frames and the
  ///    frames those sit inside (route one), plus [modifyingFrames]' walk;
  ///  * every record its staples NAME, which is how "stapled to that meeting"
  ///    becomes sayable at all;
  ///  * the structural predicates that hold of it, spelled `stapled:<noun>`
  ///    from the far end's own [StapleEnd.noun] -- so `stapled:object` is
  ///    Don's "only PAIRED todos" and nothing here enumerates the shapes.
  Set<String> termsOf(String objectId) => _terms[objectId] ??= _names(objectId);

  Set<String> _names(String objectId) {
    final terms = <String>{};
    // Route one: an object's own placements are the names it wears directly,
    // and a frame inside a frame is that frame too.
    for (final frameId in indexes.framesOf(objectId)) {
      terms.addAll(framesAbove(frameId).keys);
    }
    terms.addAll(modifyingFrames(objectId).keys);
    for (final staple in indexes.staplesOf(objectId)) {
      for (final end in indexes.endsOf(staple)) {
        if (end.id == objectId) continue;
        terms.add(end.id);
        terms.add('$stapledTerm${end.noun}');
      }
    }
    return terms;
  }

  /// A GROUP DISPLAY PROPERTY, resolved for one object: the object's own
  /// `display.<field>` first, then [nearest] where a caller knows which frame
  /// supplied the fact, then every frame bearing on the object by increasing
  /// graph distance with ties broken by stable id. Null when nobody authored
  /// one, which is honest -- the caller's shipped default answers instead.
  ///
  /// FRAMES ARE GROUPS (ruled 2026-08-19), so handling -- zone fill, sigil,
  /// falloff half-distance, Strategic promotion -- is authored on a group and
  /// read here, ONCE, never as a per-lens knob.
  Object? authoredHandling(String objectId, String field, {String? nearest}) {
    final own = obj(document.events[objectId]?.extra['display'])?[field];
    if (own != null) return own;
    final rings = modifyingFrames(objectId).entries.toList()
      ..sort((a, b) => a.value != b.value ? a.value.compareTo(b.value) : a.key.compareTo(b.key));
    for (final id in [?nearest, for (final ring in rings) ring.key]) {
      final authored = obj(document.frames[id]?.extra['display'])?[field];
      if (authored != null) return authored;
    }
    return null;
  }

  // --- Which frames bear on an object ---------------------------------------

  /// The frames that may MODIFY this object, and in HOW MANY HOPS.
  ///
  /// Named for what it returns rather than for a route: it is neither the full
  /// connection graph (the object's own placements are route one's edges, not
  /// this walk's -- see [_walk]) nor an inclusion set ([includes] is that, and it
  /// reads this plus route one). What it IS, is the ring input the weight chain
  /// consumes: connected modifying frames by increasing graph distance, which is
  /// step two of the blessed chain.
  ///
  /// Breadth-first, so the distance it reports is the SHORTEST path, and its
  /// visited set is what makes a cyclic connection graph terminate rather than
  /// having to be refused.
  Map<String, int> modifyingFrames(String objectId) => _reach[objectId] ??= _walk(objectId);

  Map<String, int> _walk(String objectId) {
    final found = <String, int>{};
    final seen = <String>{objectId};
    var frontier = [objectId];
    var hop = 1;
    // CONNECTION IS NOT INCLUSION (Don, ruling on this rule): "an event on two
    // frames does connect them but does not include them. If a' is on A and B,
    // and I project A I get a' but not B... if I project A and B then I get A, B,
    // and a' -- and A and B are connected at a'."
    //
    // So a shared placement IS a real edge and nothing here denies it: Lines draws
    // A and B connected at a', and the weight chain traverses it -- `_rings` folds
    // in `framesAbove(fact.relation.frame)`, so the frame a fact sits on is one
    // hop from it and its enclosing frames one more. What a placement never does
    // is INCLUDE the far frame's content in a projection that did not name it.
    // This walk answers inclusion, so the SEED object's own placements are route
    // one's business rather than its own: counting them here would pull a''s
    // A-resolved coordinate into a B-only projection, drawing one object at two
    // positions on one axis with the second authored by nobody.
    //
    // Reached through a STAPLE it is a different claim: the author connected these
    // two objects, so where the far one sits is where this one is relative to --
    // "then we can project the two relative to eachother".
    var throughStaple = false;
    while (frontier.isNotEmpty) {
      final next = <String>[];
      for (final id in frontier) {
        for (final frameId in _directFrames(id, placements: throughStaple)) {
          for (final entry in framesAbove(frameId).entries) {
            final at = hop + entry.value;
            if ((found[entry.key] ?? at + 1) > at) found[entry.key] = at;
          }
        }
        for (final staple in indexes.staplesOf(id)) {
          for (final end in indexes.endsOf(staple)) {
            if (end is ObjectEnd && seen.add(end.object)) next.add(end.object);
          }
        }
      }
      frontier = next;
      hop += 1;
      throughStaple = true;
    }
    return found;
  }

  /// One hop from an object to a frame: its memberships (an authored edge or a
  /// selector leaf, both already in the one pool), the frame end of any staple
  /// touching it, and -- only for an object reached THROUGH a staple -- where it
  /// is placed.
  Iterable<String> _directFrames(String objectId, {required bool placements}) => [
    if (placements) ...indexes.framesOf(objectId),
    ...indexes.directGroupsOf(objectId),
    for (final staple in indexes.staplesOf(objectId))
      // A PLACEMENT IS STILL ROUTE ONE'S BUSINESS (ruled 2026-09-01 does not
      // change this). Every connection is a staple now, so "a staple" stopped
      // being a way to say "not this object's own placement" -- and counting one
      // here would pull a''s A-resolved coordinate into a B-only projection,
      // which is exactly what the comment above forbids. Asked of the SENTENCE,
      // so the exclusion means what it always meant.
      if (placements || !isPlacement(staple, objectId))
        for (final end in indexes.endsOf(staple))
          if (end is FrameEnd) end.frame,
  ];

  /// This frame and every frame it is transitively inside, by hops. Zero for
  /// itself, so the frame an object is placed on sits at distance one from the
  /// object and its enclosing groups fall out one hop further each.
  Map<String, int> framesAbove(String frameId) => _above[frameId] ??= _climb(frameId);

  Map<String, int> _climb(String frameId) {
    final found = {frameId: 0};
    var frontier = [frameId];
    var hop = 1;
    while (frontier.isNotEmpty) {
      final next = <String>[];
      for (final id in frontier) {
        for (final group in indexes.directGroupsOf(id)) {
          if (found.containsKey(group)) continue;
          found[group] = hop;
          next.add(group);
        }
      }
      frontier = next;
      hop += 1;
    }
    return found;
  }

  String? _sourceOf(Fact fact) =>
      fact.virtualId.isEmpty ? fact.event.id : document.patterns[fact.pattern]?.templateEvent;

  /// THE LEAF PREDICATE: is this fact INCLUDED by that frame? Everything the
  /// algebra decides reduces to this, which is why it reads the same routes in
  /// both directions: the fact's own placement frame and the frames above it,
  /// then the source object's [modifyingFrames]. [_populate] enumerates
  /// candidates by walking those routes the other way, and the two must agree --
  /// an asymmetry here is a fact collected and then rejected at best, and one
  /// silently missed at worst.
  bool includes(Fact fact, String frameId) {
    final frame = fact.relation.frame;
    if (frame != null && (frame == frameId || framesAbove(frame).containsKey(frameId))) {
      return true;
    }
    final source = _sourceOf(fact);
    if (source == null || !modifyingFrames(source).containsKey(frameId)) return false;
    // CONNECTION IS NOT INCLUSION, the other half. The object routes INCLUDE an
    // object's facts in a frame from wherever they sit -- that is what makes a
    // group, an importance frame or a stapled frame show a ToDo placed on a
    // calendar. But when the object ALSO has a placement on the asked-about frame,
    // only that placement represents it there: a' on A and B is connected to both,
    // and projecting A includes a' at its A position, never additionally at its
    // B-resolved one. Two positions for one object on one axis, with the second
    // authored by nobody. Route one has already answered for the placements that
    // do belong here.
    return !indexes.framesOf(source).contains(frameId);
  }

  // --- Explicit facts per frame (D10) ---------------------------------------

  /// The objects placed directly on this frame's own coordinate axis, sorted by
  /// day and cached. A record whose extent or coordinate cannot resolve is
  /// SKIPPED rather than aborting the frame, and the FIRST reason is kept, so a
  /// frame with thousands of broken records names itself once.
  List<Fact> explicitFacts(String frameId) {
    final cached = _explicit[frameId];
    if (cached != null) return cached;
    final resolved = _direct(frameId);
    final ordered = [...resolved.facts]..sort((left, right) => left.day.compareTo(right.day));
    _maxDuration[frameId] = resolved.maxDuration;
    _errors[frameId] = [
      if (resolved.error case final String message) (source: frameId, message: message),
    ];
    return _explicit[frameId] = ordered;
  }

  _Explicit _direct(String frameId) {
    // The template placement is DERIVED, never read off the pattern's stored id
    // (ISSUES 9.1): a pattern minted without `templateRelation` used to skip
    // nothing here, so the template's own placement drew itself as an ordinary
    // event -- the "appears on one day only" half of the field report.
    final templates = {
      for (final pattern in matchingPatterns(frameId))
        if (pattern.kind == 'ics-rrule') staples.templatePlacement(pattern)?.id,
    };
    final placed = <Fact>[];
    final drawn = <String>{};
    final extents = <String, Extent?>{};
    var maxDuration = Rational.zero;
    String? error;
    // Placements the document holds, and the placements STAPLES SAY (ISSUES 9.1):
    // an object whose only position is a staple has already been positioned by
    // that sentence, and enumerating it here is what lets a surface stop minting
    // a companion placement record beside the staple to make it draw.
    for (final relation in [
      ...indexes.attachmentsOf(frameId),
      ...?staples.stapledPlacements.byFrame[frameId],
    ]) {
      if (templates.contains(relation.id)) continue;
      final event = document.events[relation.event];
      if (event == null) continue;
      // A PLACEMENT NAMES THE PLACEMENT POINT (ISSUES 9.2, Don's double render).
      // A connection that names an instant but touches this object somewhere
      // OTHER than its placement point -- an end anchor, a midpoint, a point the
      // author named -- feeds the extent derivation and is not a mark of its
      // own. Read as one, it drew Don's spanning events twice on every lens that
      // projects Wall Time.
      if (relation.coordinate != null && !isPlacement(relation, event.id)) continue;
      // ONE OBJECT, ONE FRAME, ONE FACT. Two placement-shaped records naming the
      // same object on the same sheet are ONE extent -- the second is reported as
      // a contest by the extent derivation, in words, and never as a second
      // mark. Two placements on DIFFERENT sheets stay two facts: this pass is
      // per frame, so each answers on its own. Asked before the work rather than
      // after it, and CLAIMED only where a fact is actually added below, so a
      // membership relation this frame does not place never spends the mark its
      // object's real placement is owed.
      if (drawn.contains(event.id)) continue;
      // Resolved once per EVENT, not once per relation: two placements of one
      // object would otherwise pay for the same connection-chain walk twice.
      final extent = extents.putIfAbsent(event.id, () {
        try {
          return staples.resolveObjectExtent(event.id);
        } on Object catch (failure) {
          error ??= refusalText(failure);
          return null;
        }
      });
      if (extent == null) continue;
      final anchored =
          extent.startDays != null &&
          (extent.source == 'anchors' || extent.source == 'anchor+magnitude');
      // A coordinate-less attachment is bare MEMBERSHIP -- "this object belongs
      // to this frame" -- and membership alone has never placed anything. It
      // places the object here only when the object's own connections resolve an
      // extent IN THIS FRAME'S space, which is what makes an event defined purely
      // by where it stops appear at all. THE FRAME-IDENTITY CHECK IS LOAD-BEARING
      // rather than defensive: without it every anchored event would also draw
      // itself on each of its groups.
      if (relation.coordinate == null && !(anchored && extent.frame == frameId)) continue;
      Rational? day;
      if (anchored) {
        day = extent.startDays;
      } else {
        final attempt = laws.daysAttempt(
          _raw,
          relation.frame ?? '',
          Coordinate.fromJson(relation.coordinate),
        );
        day = attempt.resolved;
        if (day == null) {
          error ??= attempt.refusal ?? 'Frame ${relation.frame} could not resolve this coordinate.';
          continue;
        }
      }
      if (day == null) continue;
      final duration = anchored ? extent.magnitudeDays : eventDurationDays(event);
      if (duration > maxDuration) maxDuration = duration;
      final space = anchored ? (extent.frame ?? frameId) : frameId;
      final coordinate = anchored ? daysCoordinate(space, day) : relation.coordinate!;
      drawn.add(event.id);
      placed.add(
        Fact(
          kind: 'explicit',
          event: event,
          relation: relation,
          day: day,
          coordinate: coordinate,
          precision: _precision(anchored ? extent : relation, space),
          extent: extent,
        ),
      );
    }
    return (facts: placed, maxDuration: maxDuration, error: error);
  }

  /// The deepest level the author actually wrote for whatever placed this fact.
  /// An extent derived from a connection to another object inherits that object's
  /// precision through the anchor's own frame end, which is why the anchor is
  /// asked before the relation.
  String? _precision(Object source, String frameId) {
    final anchor = source is Extent ? source.anchors.firstOrNull : null;
    final written =
        (anchor == null ? null : _anchorCoordinate(anchor.staple)) ??
        (source is Relation ? source.coordinate : null);
    final law = written == null ? null : laws.attempt(_raw, frameId).resolved;
    return law == null ? null : precisionOf(Coordinate.fromJson(written), law);
  }

  Json? _anchorCoordinate(Relation staple) =>
      firstMatch(
            indexes.endsOf(staple),
            (end) => end is FrameEnd && end.position is CoordinatePosition,
          )?.toJson()['coordinate']
          as Json?;

  // --- Segmented-series projection (D4) -------------------------------------

  /// PATTERN DISPATCH, and it is one switch point on purpose. `ics-rrule` is a
  /// COMPILED DIALECT of the general model, not the model: a native pattern is an
  /// expression in the one math over coordinates and cycles, and when it lands it
  /// is another arm here, with nothing above this line changing.
  List<Fact> _expand(Pattern pattern, Rational lower, Rational upper, int limit) =>
      switch (pattern.kind) {
        'ics-rrule' => _occurrences(pattern, lower, upper, limit),
        // A GENERATOR THIS BUILD CANNOT READ SAYS SO (ISSUES 9.1, the same class
        // as the starved series). An unfamiliar language is DATA and is never
        // refused as invalid -- it loads, it saves, it is not touched -- but a
        // record whose whole purpose is to generate, sitting silently generating
        // nothing, is the defect Don's morning report named. It is told once, in
        // words, beside whatever else the query answered.
        final String kind => _unreadable(pattern, kind),
        null => _unreadable(pattern, ''),
      };

  List<Fact> _unreadable(Pattern pattern, String kind) {
    _refuseFor(
      pattern,
      kind.isEmpty
          ? 'This generator does not say what kind of rule it is, so nothing can read it.'
          : 'This build cannot read a "$kind" generator, so it projects nothing.'
                ' The record is kept exactly as it is.',
    );
    return const [];
  }

  /// A series projects PER SEGMENT, and every segment's facts keep the SAME
  /// pattern provenance: a rule change is not a new identity.
  ///
  /// Two segments can never collide on a day. The boundary convention closes a
  /// segment INCLUSIVELY at its own instant and opens the next EXCLUSIVELY, so
  /// consecutive day-ranges are disjoint by construction, and that composes across
  /// any number of segments because the partitioning staples are chronologically
  /// ordered. The exclusive open is a post-filter rather than a narrowed generator
  /// bound, so the generator's skip-ahead stays exactly what an un-segmented
  /// series always had.
  List<Fact> _occurrences(Pattern pattern, Rational lower, Rational upper, int limit) {
    final source = document.events[pattern.templateEvent];
    if (source == null) {
      throw RecurrenceRefusal(
        'This repeat names no template event, so there is nothing to repeat.'
        ' Say which object the rule is about, or delete the rule.',
      );
    }
    // DERIVED, not read off the record (ISSUES 9.1). Absent, stale or wrong, the
    // stored relation id cannot starve the generator: the placement comes from
    // the template event, and Don's document heals on load by this read alone.
    final template = staples.templatePlacement(pattern);
    if (template == null) {
      throw RecurrenceRefusal(
        'This repeat says "${_ruleWords(pattern)}", but its template'
        ' ${_titleOf(source)} sits on no frame, so there is no first occurrence to'
        ' repeat from. Place it, and the rule projects.',
      );
    }
    // A phase staple anchors the cycle's phase for the SERIES, not for one
    // segment, so it is resolved once and replaces every segment's own base --
    // without rewriting any template, which is what makes removing it restore the
    // original phase for free.
    final phase = staples.seriesPhaseDays(pattern);
    final projected = <Fact>[];
    // A SEGMENT THAT CANNOT PRODUCE SAYS SO. Skipping one silently is the same
    // defect the missing template was: the rule is stated, the answer is empty,
    // and nobody said why. The reasons are collected rather than thrown at once
    // because a series can have several segments and the working ones are still
    // owed to the caller -- they are surfaced beside the facts by [_populate].
    final starved = <String>[];
    for (final segment in staples.seriesSegments(pattern)) {
      if (projected.length >= limit) break;
      final base = segment.rule.baseCoordinate;
      if (base == null) {
        starved.add(
          'segment ${segment.index + 1} of "${_ruleWords(pattern)}" has no coordinate'
          ' to repeat from',
        );
        continue;
      }
      final rule = _rrule(segment.rule.rrule);
      final refusal = unsupportedCalendarScale(rule, _registeredScale);
      if (refusal != null) throw RecurrenceRefusal(refusal);
      final frame = segment.rule.frame ?? template.frame ?? '';
      Rational from;
      try {
        from = phase ?? coordinateDays(frame, base);
      } on Object catch (failure) {
        starved.add(
          'segment ${segment.index + 1} of "${_ruleWords(pattern)}" starts at a'
          ' coordinate frame $frame cannot read (${refusalText(failure)})',
        );
        continue;
      }
      final until = _effectiveUntil(segment, rule);
      final open = segment.fromDays;
      final segmentLower = open != null && open > lower ? open : lower;
      final segmentUpper = until != null && until < upper ? until : upper;
      if (segmentLower > segmentUpper) continue;
      var days = ruleOccurrenceDays(
        rule,
        from,
        segmentLower,
        segmentUpper,
        isRegisteredScale: _registeredScale,
        until: until,
        excluded: {for (final value in segment.rule.exdates) '$value'},
        limit: limit == noOccurrenceLimit ? limit : limit - projected.length,
      );
      if (open != null) {
        days = [
          for (final day in days)
            if (day > open) day,
        ];
      }
      // Live exclusions resolved ONCE per query rather than once per occurrence.
      final excluded = segment.rule.exclude == null
          ? null
          : staples.liveExclusionDays(segment.rule.exclude, segmentLower, segmentUpper);
      // A following rule's own magnitude overrides the template's duration for
      // THIS segment's occurrences -- "a different weekday AND a different time
      // of day AND a different duration" -- and absent, the template's applies.
      final magnitudes = segment.rule.magnitude == null
          ? source.magnitudes
          : {...source.magnitudes, 'duration': Magnitude.fromJson(segment.rule.magnitude!)};
      for (final day in days) {
        if (isLiveExcluded(excluded, day)) continue;
        final key = day.toJson();
        final virtualId = stableVirtualId(pattern.id, 'occurrence-$key');
        final provenance = {'kind': 'pattern', 'pattern': pattern.id, 'key': key};
        final coordinate = daysCoordinate(frame, day);
        projected.add(
          Fact(
            kind: 'virtual',
            virtualId: virtualId,
            event: source.copyWith(
              id: virtualId,
              magnitudes: magnitudes,
              extra: {...source.extra, 'provenance': provenance},
            ),
            // The occurrence's own placement, said the one way a placement is
            // said: the template's staple with its object end re-pointed at
            // this occurrence and its frame end carrying this instant.
            relation: template.copyWith(
              id: '$virtualId/attachment',
              extra: {
                ...template.extra,
                'provenance': provenance,
                'ends': [
                  ObjectEnd(virtualId, point: startPoint).toJson(),
                  FrameEnd(frame, position: Position.coordinate(coordinate)).toJson(),
                ],
              },
            ),
            day: day,
            coordinate: coordinate,
            pattern: pattern.id,
          ),
        );
        if (projected.length >= limit) break;
      }
    }
    if (starved.isNotEmpty) _refuseFor(pattern, starved.join('; '));
    return projected;
  }

  /// The rule as the card reads it back, so a refusal quotes the sentence the
  /// author is looking at rather than describing a record.
  String _ruleWords(Pattern pattern) {
    final rrule = obj(pattern.extra['rrule']) ?? const {};
    return [for (final entry in rrule.entries) '${entry.key}=${entry.value}'].join(';');
  }

  String _titleOf(Event event) {
    final title = str(event.payload?['title']) ?? '';
    return title.trim().isEmpty ? event.id : '"$title"';
  }

  /// A stated rule that cannot produce, in words. The FIRST reason is kept, so a
  /// pattern with many broken segments names itself once -- the same discipline
  /// [_direct] keeps for a frame full of broken records.
  void _refuseFor(Pattern pattern, String message) => _patternRefusals[pattern.id] ??= message;

  /// The earlier of a segment's own written UNTIL and the staple that closes it.
  /// Compared as exact days, never as text: ICS writes month `01` where an editor
  /// field writes `1`, and a string comparison between two spellings of one
  /// instant is silently wrong.
  Rational? _effectiveUntil(Segment segment, RRule rule) {
    final written = compactIcsDay(rule[RecurrenceEnd.until.name.toUpperCase()]);
    final closed = segment.untilDays;
    if (closed == null || written == null) return written ?? closed;
    return written <= closed ? written : closed;
  }

  RRule _rrule(Json source) => {
    for (final entry in source.entries)
      if (entry.value != null) entry.key: '${entry.value}',
  };

  bool _registeredScale(String scale) => lawForCalendar(scale) != null;

  // --- Recurrence caching (D5) ----------------------------------------------

  List<Fact> _recurrence(Pattern pattern, Rational lower, Rational upper, int limit) {
    // The whole-series path bounds a rule's life from its own INTERVAL/COUNT/FREQ,
    // which is correct only because an un-segmented rule's whole life IS that
    // bound. A SEGMENTED series can run indefinitely past a bounded-looking first
    // segment, so it is never routed here; it falls through to the windowed cache,
    // which always asks for the query's own true bounds.
    final rrule = obj(pattern.extra['rrule']) ?? const {};
    final written = rrule['COUNT'];
    final segmented = staples.seriesIsSegmented(pattern);
    final count = segmented || written == null ? null : int.tryParse('$written'.trim());
    if (!segmented && written != null && (count == null || count < 1)) {
      return _expand(pattern, lower, upper, limit);
    }
    if (count != null && count <= maxCachedRecurrenceCount) {
      return _wholeSeries(pattern, rrule, count, lower, upper, limit);
    }
    if (count != null) return _expand(pattern, lower, upper, limit);
    return _windowedRecurrence(pattern, lower, upper, limit);
  }

  List<Fact> _wholeSeries(
    Pattern pattern,
    Json rrule,
    int count,
    Rational lower,
    Rational upper,
    int limit,
  ) {
    // Map insertion order IS the LRU order, so a hot series is refreshed by a
    // remove-and-reinsert rather than by another copy of its generated facts.
    var series = _series.remove(pattern.id);
    if (series != null) {
      _series[pattern.id] = series;
    } else {
      final relation = staples.templatePlacement(pattern);
      if (relation?.coordinate == null) {
        // The bounded-rule fast path had the same silent empty the generator
        // did: no template placement, no horizon, no facts, no sentence. It
        // refuses in the generator's own words instead (ISSUES 9.1).
        return _expand(pattern, lower, upper, limit);
      }
      final base = coordinateDays(relation!.frame ?? '', relation.coordinate);
      final interval = BigInt.parse('${rrule['INTERVAL'] ?? 1}');
      final factor = switch ('${rrule['FREQ'] ?? ''}'.toUpperCase()) {
        'DAILY' => 1,
        'WEEKLY' => 7,
        'MONTHLY' => 32,
        _ => 367,
      };
      final horizon = base + Rational(interval * BigInt.from(count * factor) + BigInt.from(367));
      series = _expand(pattern, base, horizon, noOccurrenceLimit);
      while (_series.isNotEmpty && _seriesFacts + series.length > maxRecurrenceSeriesFacts) {
        _seriesFacts -= _series.remove(_series.keys.first)?.length ?? 0;
      }
      _series[pattern.id] = series;
      _seriesFacts += series.length;
    }
    final visible = <Fact>[];
    for (final fact in series) {
      if (fact.day < lower) continue;
      if (fact.day > upper) break;
      visible.add(fact);
      if (visible.length >= limit) break;
    }
    return visible;
  }

  List<Fact> _windowedRecurrence(Pattern pattern, Rational lower, Rational upper, int limit) {
    final width = BigInt.from(recurrenceWindowDays);
    final first = floorDiv(lower.floor(), width), last = floorDiv(upper.floor(), width);
    final visible = <Fact>[];
    for (var window = first; window <= last; window += BigInt.one) {
      // Keyed so the pattern id is recoverable by the same split every virtual id
      // uses, which is what lets a precise invalidation drop one pattern's
      // windows without knowing how they were keyed.
      final key = stableVirtualId(pattern.id, 'window-$window');
      var entries = _windows.remove(key);
      if (entries != null) {
        _windows[key] = entries;
      } else {
        final start = Rational(window * width);
        final end = start + Rational(width);
        entries = [
          for (final fact in _expand(pattern, start, end, noOccurrenceLimit))
            if (fact.day < end) fact,
        ];
        while (_windows.isNotEmpty &&
            (_windows.length >= maxRecurrenceWindows ||
                _windowFacts + entries.length > maxRecurrenceWindowFacts)) {
          _windowFacts -= _windows.remove(_windows.keys.first)?.length ?? 0;
        }
        // An unusually dense single window is useful for the query in hand and
        // deliberately not retained after it has been drawn.
        if (entries.length <= maxRecurrenceWindowFacts) {
          _windows[key] = entries;
          _windowFacts += entries.length;
        }
      }
      for (final fact in entries) {
        if (fact.day < lower || fact.day > upper) continue;
        visible.add(fact);
        if (visible.length >= limit) return visible;
      }
    }
    return visible;
  }

  /// How many recurrence windows and window-facts are held. Read by the overscale
  /// spec, which asserts these stay inside their bounds under sustained
  /// navigation rather than merely trending that way.
  ({int windows, int windowFacts, int series, int seriesFacts}) get cacheLoad => (
    windows: _windows.length,
    windowFacts: _windowFacts,
    series: _series.length,
    seriesFacts: _seriesFacts,
  );

  // --- Querying (D11, D12) --------------------------------------------------

  /// One frame's facts. The default projection for a plain selection.
  QueryResult queryFrame(
    String frameId, {
    required Object start,
    required Object end,
    int limit = noOccurrenceLimit,
    bool includeOverlaps = false,
    bool applyOverrides = true,
  }) => queryFacts(
    Projection.of([frameId]),
    start: start,
    end: end,
    limit: limit,
    includeOverlaps: includeOverlaps,
    applyOverrides: applyOverrides,
  );

  /// The facts a projection admits inside a window.
  ///
  /// [limit] is THE CALLER'S ONE DERIVED BUDGET (ruling 9): screen space and
  /// magnitude falloff decide what a lens can show, and this module holds no
  /// number of its own. Exceeding it sets [QueryResult.truncated], which is a
  /// LOWER BOUND on what exists, never a silent drop.
  ///
  /// [start] and [end] are coordinates under the window law, or exact
  /// [Rational] days for a caller that already has them.
  ///
  /// `applyOverrides: false` yields the projection as the patterns alone describe
  /// it, suppressed occurrences included. That is what the series heal compares a
  /// materialized occurrence against: an override hides the very slot the heal has
  /// to reconstruct. It deliberately reuses this generator rather than rebuilding
  /// from the template, so the comparison and the reassertion cannot drift.
  QueryResult queryFacts(
    Projection projection, {
    required Object start,
    required Object end,
    int limit = noOccurrenceLimit,
    bool includeOverlaps = false,
    bool applyOverrides = true,
  }) {
    final primary = projection.primaryFrame;
    final windowFrame = primary == null ? null : windowFrameFor(primary);
    final from = _bound(start, windowFrame), to = _bound(end, windowFrame);
    final lower = from <= to ? from : to, upper = from <= to ? to : from;
    final maxFacts = limit < 1 ? 1 : limit;
    final errors = <String, ProjectionError>{};
    final collected = _populate(projection, lower, upper, maxFacts, includeOverlaps, errors);
    final visible = applyOverrides
        ? applyVirtualOverrides(document, collected.facts, (fact) => fact.virtualId)
        : collected.facts;
    visible.sort(_byDay);
    return (
      facts: visible,
      errors: errors.values.toList(),
      truncated: collected.truncated,
      fromDays: lower,
      toDays: upper,
    );
  }

  Rational _bound(Object value, String? frameId) => switch (value) {
    final Rational days => days,
    _ =>
      frameId == null
          ? gregorianLaw.toDays(Coordinate.fromJson(obj(value)))
          : coordinateDays(frameId, obj(value)),
  };

  /// The universe, and the algebra applied to it.
  ///
  /// Candidates are enumerated by walking the ruled routes DOWNWARD from every
  /// frame the expression names -- negated ones included, because the complement
  /// a NOT takes is within the union of what the expression talks about, which is
  /// what makes De Morgan hold on populations. Each candidate is then evaluated
  /// once and kept or dropped; a NOT therefore changes population and, because
  /// its term is carried marked rather than filtered, no weight.
  ///
  /// DELIBERATELY UNCACHED. This module's invalidation is keyed to one changed
  /// frame, and a correct union cache would have to walk every ancestor whenever
  /// any transitively nested member changed. Every member that is an ordinary
  /// frame still hits its own [explicitFacts] cache, so only the merge is
  /// redone: a slow-but-correct query beats a fast-but-wrong one.
  ({List<Fact> facts, bool truncated}) _populate(
    Projection projection,
    Rational lower,
    Rational upper,
    int maxFacts,
    bool includeOverlaps,
    Map<String, ProjectionError> errors,
  ) {
    final candidates = <Fact>[];
    final seen = <String>{};
    var refused = false;
    // Dedupe, then the algebra. Dedupe keys on the RELATION, never the event:
    // the identical relation reached twice -- directly and through a nested
    // member frame, or by two nested paths -- is one fact, while two relations
    // placing one event on two frames are two real placements.
    void offer(Fact fact) {
      if (refused || !seen.add(fact.identity)) return;
      bool reaches(String frameId) => includes(fact, frameId);
      if (!projection.inUniverse(reaches)) return;
      try {
        if (projection.admits(reaches)) candidates.add(fact);
      } on MathRefusal catch (failure) {
        errors['$projection'] = (source: '$projection', message: failure.toString());
        refused = true;
      }
    }

    final sources = <String>{}, objects = <String>{}, patterns = <String, Pattern>{};
    for (final frameId in projection.frames) {
      for (final source in indexes.frameClosure(frameId)) {
        sources.add(source);
        if (indexes.cycles[source] case final String message) {
          errors[source] = (source: source, message: message);
        }
        for (final pattern in matchingPatterns(source)) {
          patterns[pattern.id] = pattern;
        }
        // STAPLE ROUTES: an object stapled to this frame, and transitively an
        // object stapled to that object, connects to it -- the same edges the
        // leaf predicate reads from the other end.
        for (final staple in indexes.staplesOf(source)) {
          for (final end in indexes.endsOf(staple)) {
            if (end is ObjectEnd) objects.add(end.object);
          }
        }
      }
      objects.addAll(indexes.memberObjects(frameId));
    }
    // STAPLE-TO-OBJECT, closed: an object stapled to an object that connects to
    // one of these frames connects to it too, at one more hop. Enumerated as the
    // connected component of the object-to-object staple graph, which is exactly
    // what [modifyingFrames] walks from the other end -- the two must agree, or a
    // fact is admitted by the leaf predicate that enumeration never offered it.
    final queue = [...objects];
    while (queue.isNotEmpty) {
      final objectId = queue.removeLast();
      for (final staple in indexes.staplesOf(objectId)) {
        for (final end in indexes.endsOf(staple)) {
          if (end is ObjectEnd && end.object != objectId && objects.add(end.object)) {
            queue.add(end.object);
          }
        }
      }
    }
    for (final source in sources) {
      for (final error in _frameErrors(source)) {
        errors[error.source] = error;
      }
      // An object placed here that also carries a staple to another object is a
      // BRIDGE: the partner connects to this frame through it, so it has to enter
      // the object routes below even though nothing named it. One lookup per
      // indexed fact, and nothing is added for the overwhelming majority of
      // objects, which carry no object-to-object connection at all.
      for (final fact in explicitFacts(source)) {
        if (indexes.staplesOf(fact.event.id).isNotEmpty) objects.add(fact.event.id);
      }
      _windowed(source, lower, upper, includeOverlaps, offer);
    }
    for (final objectId in objects) {
      // A STAPLED OBJECT THAT STILL SITS NOWHERE SAYS SO. Reported only for the
      // objects this projection actually reaches, so a document-wide loop nobody
      // asked about does not shout at every query.
      if (staples.stapledPlacements.refusals[objectId] case final String message) {
        errors[objectId] = (source: objectId, message: message);
      }
      for (final frameId in indexes.framesOf(objectId)) {
        // A placement on a frame this query already reads was collected by route
        // one; the object routes only import the placements that sit elsewhere.
        // Whether an elsewhere-placement belongs here at all is [includes]'s
        // answer, per asked-about frame, not per object -- a fact on one calendar
        // may belong to a group the object is a member of and NOT to a sibling
        // calendar the object also sits on.
        if (sources.contains(frameId)) continue;
        final floor = lower - _lookback(frameId, includeOverlaps);
        for (final fact in explicitFacts(frameId)) {
          if (fact.relation.event != objectId || fact.day > upper || fact.day < floor) continue;
          offer(fact);
        }
      }
    }
    // TRUNCATION KEEPS THE EARLIEST. Ordering before the cut is day order across
    // the WHOLE population rather than per contributing frame: a group whose
    // members each hold facts must not spend the caller's entire budget on
    // whichever member happened to be walked first.
    candidates.sort(_byDay);
    var truncated = candidates.length > maxFacts;
    final kept = candidates.take(maxFacts).toList();
    for (final pattern in patterns.values) {
      if (kept.length >= maxFacts) {
        truncated = true;
        break;
      }
      final overlap = includeOverlaps
          ? eventDurationDays(document.events[pattern.templateEvent])
          : Rational.zero;
      final remaining = maxFacts - kept.length;
      try {
        final emitted = _recurrence(pattern, lower - overlap, upper, remaining);
        for (final fact in emitted) {
          if (kept.length >= maxFacts) {
            truncated = true;
            break;
          }
          if (fact.day < lower && fact.day + eventDurationDays(fact.event) <= lower) continue;
          if (!seen.add(fact.identity)) continue;
          bool reaches(String frameId) => includes(fact, frameId);
          if (!projection.inUniverse(reaches) || !projection.admits(reaches)) continue;
          kept.add(fact);
        }
        // The generator was BOUNDED BY THE BUDGET, so it stopped rather than
        // offering one more to refuse. Filling the budget exactly is therefore
        // reported as truncation: the flag is a lower bound on what exists, and
        // claiming a completeness we cannot verify would be the silent drop it
        // exists to prevent.
        if (emitted.length >= remaining) truncated = true;
      } on Object catch (failure) {
        errors[pattern.id] = (source: pattern.id, message: refusalText(failure));
      }
      // A REFUSAL BESIDE THE FACTS. A thrown refusal ends the pattern and is the
      // stronger statement, so it stands; a partial one is reported here, which
      // is the only way a series can hand back what it could produce AND say
      // what it could not (ISSUES 9.1).
      if (_patternRefusals[pattern.id] case final String message) {
        errors.putIfAbsent(pattern.id, () => (source: pattern.id, message: message));
      }
    }
    return (facts: kept, truncated: truncated);
  }

  static int _byDay(Fact left, Fact right) => left.day != right.day
      ? left.day.compareTo(right.day)
      : stableFactKey(left.order).compareTo(stableFactKey(right.order));

  List<ProjectionError> _frameErrors(String frameId) {
    explicitFacts(frameId);
    return _errors[frameId] ?? const [];
  }

  Rational _lookback(String frameId, bool includeOverlaps) =>
      includeOverlaps ? _maxDuration[frameId] ?? Rational.zero : Rational.zero;

  /// BINARY SEARCH into the sorted explicit index, then a forward walk that stops
  /// at the window's own upper bound. `includeOverlaps` widens the lower bound by
  /// the frame's longest duration and then drops the records whose spans really do
  /// end before the window opens -- so a long event that started earlier is drawn,
  /// and one that merely started earlier is not.
  void _windowed(
    String frameId,
    Rational lower,
    Rational upper,
    bool includeOverlaps,
    void Function(Fact) offer,
  ) {
    final placed = explicitFacts(frameId);
    final floor = lower - _lookback(frameId, includeOverlaps);
    var low = 0, high = placed.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (placed[middle].day < floor) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    for (var index = low; index < placed.length; index += 1) {
      final fact = placed[index];
      if (fact.day > upper) break;
      if (includeOverlaps &&
          fact.day < lower &&
          fact.day + eventDurationDays(fact.event) <= lower) {
        continue;
      }
      offer(fact);
    }
  }

  // --- Display weight -------------------------------------------------------

  /// The blessed chain (ruling 10), wired: the object's own math, then connected
  /// modifying frames by increasing graph distance, then the projecting frame
  /// last, then apparent-magnitude falloff as the projector's closing step.
  ///
  /// The traversal is this module's -- `weight.dart` takes rings that already know
  /// their distance and owns the sort, the fold and the closing step. NOT-marked
  /// terms are passed THROUGH rather than filtered out, which is what makes "NOT
  /// never modifies weight" enforceable in one place. [at] is the instant the
  /// projector is looking from; absent, there is no falloff step.
  WeightDerivation weightOf(
    Fact fact,
    Projection projection, {
    Rational? at,
    Rational? halfDistanceDays,
  }) {
    final rings = _rings(fact);
    final primary = projection.primaryFrame;
    final home = at == null ? null : homeOf(fact);
    final signed = at == null ? null : proximityDaysOf(fact, at, home: home);
    WeightRing ring(String id, int distance) => weightRing(
      id,
      _authoredWeight(document.frames[id]?.extra),
      distance: distance,
      negated: projection.negatedFrames.contains(id),
    );
    return composeWeight(
      base: Rational.one,
      own: _authoredWeight(fact.event.extra),
      frames: [
        for (final entry in rings.entries)
          if (entry.key != primary) ring(entry.key, entry.value),
      ],
      projector: primary == null ? null : ring(primary, rings[primary] ?? 0),
      falloffDistance: at == null ? null : distanceFromHome(home, at),
      halfDistanceDays: halfDistanceDays,
      environment: {proximityVariable: ?signed},
    );
  }

  /// PROXIMITY, AND THERE IS ONE OF IT (ISSUES 9.1).
  ///
  /// Signed days from the instant a projector is looking from to this fact's
  /// home: positive ahead, negative behind, zero while the object is happening.
  /// Bound into every weight formula's environment under [proximityVariable] by
  /// [weightOf], and read directly by an optional ring like `display.proximity`
  /// that wants the same number -- because it IS the same number, and two
  /// derivations of one idea disagree the first time a home gains breadth.
  ///
  /// [home] is an optimization only: a caller that already resolved the fact's
  /// home passes it rather than paying for the connection walk twice.
  Rational? proximityDaysOf(Fact fact, Rational at, {DayExtent? home}) =>
      signedDistanceFromHome(home ?? homeOf(fact), at);

  /// Every frame that could modify this fact's weight, by SHORTEST graph
  /// distance. The fact's own placement frame sits at one, its enclosing groups
  /// one further each, and everything the source object reaches by membership or
  /// by a staple chain at however many hops it takes.
  Map<String, int> _rings(Fact fact) {
    final rings = <String, int>{};
    final frame = fact.relation.frame;
    if (frame != null) {
      for (final entry in framesAbove(frame).entries) {
        rings[entry.key] = entry.value + 1;
      }
    }
    final source = _sourceOf(fact);
    for (final entry in (source == null ? const {} : modifyingFrames(source)).entries) {
      final known = rings[entry.key];
      if (known == null || entry.value < known) rings[entry.key] = entry.value;
    }
    return rings;
  }

  Object? _authoredWeight(Json? extra) => obj(extra?['display'])?['weight'];

  /// Where an object LIVES on the days axis: the range its own resolvable
  /// connections span, its implicit placement staple included. A generated
  /// occurrence's home is its own occurrence -- the template's extent is where
  /// the SERIES was authored, not where this instance sits.
  DayExtent? homeOf(Fact fact) {
    if (fact.virtualId.isNotEmpty) {
      return (start: fact.day, end: fact.day + eventDurationDays(fact.event));
    }
    final reached = <String, DayExtent>{};
    void note(String id, Rational? from, Rational? to) {
      if (from != null) reached[id] = (start: from, end: to ?? from);
    }

    final objectId = fact.event.id;
    final own = staples.resolveObjectExtent(objectId);
    note(objectId, own.startDays, own.endDays);
    for (final row in staples.effectiveObjectStaples(objectId)) {
      // LISTING EVERYTHING IS NOT POSITIONING FROM EVERYTHING (ISSUES 9.1). The
      // connection set is whole now -- memberships and containments included --
      // and a home is built only from the connections that make a claim about
      // where. "This belongs to that" says nothing about when, and reading a
      // position out of it would invent one.
      if (!row.positions) continue;
      switch (row.far) {
        case final FrameEnd end:
          note(end.frame, staples.frameEndDays(end), null);
        case final ObjectEnd end:
          final extent = staples.resolveObjectExtent(end.object);
          note(end.object, extent.startDays, extent.endDays);
        case _:
      }
    }
    return objectHome(reached.keys, (id) => reached[id]);
  }
}
