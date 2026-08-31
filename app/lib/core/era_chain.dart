// Eras are FRAMES STAPLED TOGETHER.
//
// Owner ruling, replacing an earlier era-table-on-a-declaration model: an era is
// its own frame. It owns its year numbering (where the numbers start, which way
// they run) and its extent; it inherits its month/day structure from a basis;
// and the boundary between two consecutive eras is a `succession` staple. A
// calendar spanning eras is a GROUP frame over the chain.
//
// Why frames and not a table. An era is exactly the sort of thing a frame
// already is: it has an extent, it holds events, it can be a member of groups,
// it can be displayed or hidden, and it can be handled differently from its
// neighbours. A table row can do none of that. Modelling eras as rows meant
// every one of those capabilities would have had to be reinvented against a
// second kind of object, and the era's own identity would have been a string in
// a list rather than a record with an id -- which is what made era membership,
// era-level display weight, and a non-countable era all inexpressible.
//
// SUCCESSION IS NOT A KIND. Ruled 2026-08-31: "A staple connects n points and
// says each is the same as the other. No exceptions No special cases No extra
// riders." An era boundary is a PLAIN POINT STAPLE -- one frame's own end
// identified with another frame's own beginning -- and this module derives the
// ordering by READING those points, never by consulting a `kind`. "One happens
// to be the end and the other the beginning, this case is not special for all it
// is common, the end of 1 could just as easily connect to three weeks into 2":
// so an identification naming neither bound orders nothing, which is the right
// answer rather than a missing one.
//
// DIRECTION IS THE POINTS, AND FOR A POSITIONLESS RECORD IT IS THE ORDER. A
// frame end that says nothing about where it touches is read through
// [StapleEnds.readEnds] as the point the staple's own order always meant -- the
// first sheet finishes, every other begins -- so a document written when
// `succession` was a kind keeps its exact meaning and its exact bytes, as one
// SPELLING of the general staple. The JavaScript's `end.role` sniffing has no
// counterpart here and never did.
//
// AND WHERE A BASIS CANNOT LABEL A POINT, THE STAPLE CONNECTS INCLUSIVELY: "the
// end of 1 staples to all of 2." The all-point names both of era 2's bounds, so
// era 2 is read as BEGINNING at that boundary exactly as a named beginning would
// be -- taking part in the order is what an era with no year axis does do.
//
// A BOUNDARY IS ONE POINT, NEVER A CHAIN OF ITS OWN. An n-end staple identifies
// ALL its points as one point, so three consecutive eras are TWO staples and a
// three-end boundary is a BRANCH -- one era finishing where two begin, the two
// successors agreeing about everything up to the boundary and about the
// boundary, and saying nothing about each other after it. So the traversal here
// yields PATHS, not a line, and a derivation that needs one line says which
// paths it found rather than choosing among them.
//
// This module walks the chain and derives every era's range. The ARITHMETIC is
// [EraTable]'s, unchanged: ordered eras, per-era direction and first year, one
// authored pin, ranges propagated outward in PROPER YEARS. What changes is where
// the ordered list comes from -- identified points between frame records rather
// than an array in one declaration -- and that the result is keyed by frame id.

import 'coordinate_law.dart';
import 'eras.dart';
import 'frame_points.dart';
import 'records.dart';
import 'staples.dart';

/// The `era` block a frame carries, or null for a frame that is not an era.
Json? eraDeclaration(Frame? frame) => obj(frame?.extra['era']);

bool isEraFrame(Frame? frame) => eraDeclaration(frame) != null;

/// An era with no metric ladder: ordered and connected, never acquiring day
/// ordinals. The Dawn Era precedes the Merethic and has no year axis at all --
/// time there being the thing that had not started behaving yet -- so it holds
/// events in sequence and answers no question about when.
///
/// `countable: false` is the AUTHORED statement. A frame that simply has no
/// basis is also uncountable in practice, but that is a consequence rather than
/// a claim, and the two are kept distinct so a missing basis reads as an error
/// where it is one.
bool isCountableEra(Frame? frame) {
  final era = eraDeclaration(frame);
  return era != null && era['countable'] != false;
}

/// One succession edge: the staple, the era that FINISHES and one that BEGINS
/// at that boundary.
typedef Succession = ({Relation relation, String from, String to});

/// EVERY BOUNDARY THE DOCUMENT'S IDENTIFICATIONS STATE, read off the points.
///
/// NO KIND GATE. An edge runs from the era whose own END a staple names to the
/// era whose own BEGINNING it names -- the two facts an ordinary point staple
/// carries. Nothing asks what the record calls itself, so `succession` is a word
/// a file may hold and not a case this walks.
///
/// N-ARY, AND NEVER A CHAIN WITHIN ONE STAPLE. An n-end staple identifies ALL
/// its points as ONE point, so a boundary's ends are ONE point, not a run of
/// consecutive boundaries. Three consecutive eras are TWO staples
/// (end1=begin2, end2=begin3). One THREE-end staple (end1=begin2=begin3) is the
/// Sundering: "in the mythic age humans and elves got along then the sundering
/// came and they have kept separate calendars since. they agree on era 1 and the
/// sundering when they split but nothing since" -- a BRANCHING boundary, one era
/// finishing where two begin. Reading those three ends as the pairs (1,2) and
/// (2,3) would invent an order nobody authored.
///
/// AN IDENTIFICATION NAMING NEITHER BOUND ORDERS NOTHING. "The end of 1 could
/// just as easily connect to three weeks into 2" -- a true and legal statement
/// about where two eras meet, and not a statement about which follows which. It
/// contributes no edge, and the chain says so rather than guessing one.
///
/// NOT NARROWED TO ERAS HERE. An edge onto a frame that is not an era is still
/// an edge: [eraChainMembers] narrows the reachable pile afterwards, which is
/// what lets a refusal name every era the author meant to join rather than the
/// one it happened to start from. It is also what makes Don's sized boundary
/// work -- "it could also be a frame 3 years long and be filled with the
/// chronicals of the sundering war" is just frames stapled at both its ends, and
/// nothing here refuses that shape.
List<Succession> successionEdges(Document document) {
  final edges = <Succession>[];
  for (final relation in document.relations.values) {
    if (!relation.isStaple) continue;
    final finishes = <String>[], begins = <String>[];
    for (final end in relation.readEnds) {
      if (end is! FrameEnd) continue;
      final bounds = boundsNamed(pointSourceOf(end.position?.point));
      // The all-point names BOTH bounds, and an era that cannot label a point
      // along its own line still takes part in the order: it begins here.
      if (bounds.beginning) {
        begins.add(end.frame);
      } else if (bounds.end) {
        finishes.add(end.frame);
      }
    }
    for (final from in finishes) {
      for (final to in begins) {
        edges.add((relation: relation, from: from, to: to));
      }
    }
  }
  return edges;
}

/// Every era frame connected to [frameId] by succession staples, in no
/// particular order, WITHOUT deriving an order.
///
/// Deliberately incapable of failing: a caller that has just been refused an
/// ordering still needs to know which frames the refusal covers, so it can
/// report the chain once instead of once per era.
List<String> eraChainMembers(Document document, String frameId) {
  final edges = successionEdges(document);
  final reachable = <String>{};
  final queue = <String>[frameId];
  while (queue.isNotEmpty) {
    final current = queue.removeLast();
    if (!reachable.add(current)) continue;
    for (final edge in edges) {
      if (edge.from == current) queue.add(edge.to);
      if (edge.to == current) queue.add(edge.from);
    }
  }
  return [
    for (final id in reachable)
      if (isEraFrame(document.frames[id])) id,
  ];
}

/// EVERY succession path that runs through [frameId], each oldest first, each
/// its own chain.
///
/// A branch is not a defect. One era may finish where several begin -- whether
/// the author wrote one three-end staple or two two-end ones, which are the same
/// statement -- and the answer is then two paths that share their head and
/// diverge at the boundary, with NO order invented between the successors. An
/// era stapled to the beginning and the end of other eras ("a broken time
/// thing") is equally legal and equally answered: more paths.
///
/// What is still refused is a document that cannot be walked at all: a loop (no
/// era begins the chain) and a pile of eras with no succession between them.
/// Both mean the author has said something that cannot be a succession, and
/// both are told once for the whole scope.
List<List<String>> eraChainPaths(Document document, String frameId) {
  final members = eraChainMembers(document, frameId).toSet();
  if (!members.contains(frameId)) return const [];
  final edges = [
    for (final edge in successionEdges(document))
      if (edge.from != edge.to && members.contains(edge.from) && members.contains(edge.to)) edge,
  ];
  final next = <String, Set<String>>{}, previous = <String, Set<String>>{};
  for (final edge in edges) {
    (next[edge.from] ??= <String>{}).add(edge.to);
    (previous[edge.to] ??= <String>{}).add(edge.from);
  }
  // One succession, or the author is told which eras are outside it. Narrowing
  // to era frames can strand a member -- two eras joined only THROUGH something
  // that is not an era are not a succession at all -- and that is a fact about
  // the whole pile, reported once.
  final joined = <String>{};
  final walk = <String>[frameId];
  while (walk.isNotEmpty) {
    final current = walk.removeLast();
    if (!joined.add(current)) continue;
    walk.addAll(next[current] ?? const <String>{});
    walk.addAll(previous[current] ?? const <String>{});
  }
  final stranded = [
    for (final id in members)
      if (!joined.contains(id)) id,
  ]..sort();
  if (stranded.isNotEmpty) {
    throw LawRefusal(
      'No succession joins ${stranded.join(', ')} to the rest of these eras,'
      ' so they are not one chain.',
    );
  }
  final heads = [
    for (final id in members)
      if (!previous.containsKey(id)) id,
  ]..sort();
  if (heads.isEmpty) {
    throw const LawRefusal('This era chain has no beginning, so its eras form a loop.');
  }
  final paths = <List<String>>[];
  void follow(List<String> sofar) {
    final current = sofar.last;
    final onward = (next[current] ?? const <String>{}).toList()..sort();
    if (onward.isEmpty) {
      if (sofar.contains(frameId)) paths.add(List.unmodifiable(sofar));
      return;
    }
    for (final step in onward) {
      if (sofar.contains(step)) {
        throw LawRefusal('The era chain loops at $step.');
      }
      follow([...sofar, step]);
    }
  }

  for (final head in heads) {
    follow([head]);
  }
  return paths;
}

/// The one succession running through [frameId], oldest first -- the linear
/// case, which is most of them.
///
/// A branch has no single order, and picking one silently is exactly what the
/// ruling forbids, so a caller wanting ONE ordering is told there are several
/// and which they are. [eraChainPaths] is what a caller that can carry a branch
/// asks instead.
List<String> eraChainFrames(Document document, String frameId) {
  final paths = eraChainPaths(document, frameId);
  if (paths.isEmpty) return const [];
  if (paths.length > 1) throw LawRefusal(_branched(document, frameId, paths));
  return paths.single;
}

String _branched(Document document, String frameId, List<List<String>> paths) =>
    '${_title(document, frameId)} lies on ${paths.length} successions '
    '(${[for (final path in paths) path.map((id) => _title(document, id)).join(' > ')].join('; ')}),'
    ' so there is no single order here. Say which succession this asks about.';

String _title(Document document, String frameId) {
  final title = declaredText(document.frames[frameId]?.title);
  return title.isEmpty ? frameId : title;
}

/// The chain as an [EraTable] plus the frame index that maps a frame id to its
/// entry.
/// [ordered] is every era in the chain, oldest first, non-countable ones
/// included: ordering is exactly what they do have. [countable] is the eras with
/// a year axis, in chain order -- NON-COUNTABLE eras are excluded from the table
/// because they take part in the ORDER and in nothing else. [pin] is the frame
/// carrying the one authored anchor.
typedef EraChain = ({
  List<String> ordered,
  List<String> countable,
  EraTable table,
  Map<String, EraEntry> byFrame,
  String pin,
});

/// The chain resolved, or null when [frameId] belongs to no chain at all.
///
/// One answer, so a BRANCH is reported rather than picked: an era that finishes
/// where two begin belongs to two chains, and [eraChains] is what a caller that
/// can carry both asks.
EraChain? eraChain(Document document, String frameId) {
  final ordered = eraChainFrames(document, frameId);
  return ordered.isEmpty ? null : _resolve(document, ordered);
}

/// The chain resolved ONCE PER SUCCESSION PATH through [frameId], oldest first
/// within each.
///
/// The branch answer: each path is its own chain, with its own pin and its own
/// derived ranges, and nothing is reconciled between them. Two calendars that
/// diverge at one boundary agree about everything before it and about the
/// boundary itself, and say nothing whatever about each other after it -- which
/// is the Sundering, expressed rather than described.
List<EraChain> eraChains(Document document, String frameId) => [
  for (final path in eraChainPaths(document, frameId)) _resolve(document, path),
];

/// One path's arithmetic: ordered eras, per-era direction and first year, one
/// authored pin, ranges propagated outward in PROPER YEARS.
///
/// The pin is authored on whichever era frame carries `era.anchor`. Exactly one
/// must, for the same reason [EraTable] takes exactly one: two pins are two
/// facts that can disagree. On a branch this is per PATH -- a pin past the
/// branch pins only the paths that run through it, and a path with none is told
/// so.
EraChain _resolve(Document document, List<String> ordered) {
  final countable = [
    for (final id in ordered)
      if (isCountableEra(document.frames[id])) id,
  ];
  final pins = [
    for (final id in ordered)
      if (eraDeclaration(document.frames[id])?['anchor'] != null) id,
  ];
  if (pins.length != 1) {
    throw LawRefusal(
      pins.isEmpty
          ? 'This era chain states nowhere that it sits; one era must carry an'
                ' anchor.'
          : 'This era chain is pinned ${pins.length} times'
                ' (${pins.join(', ')}); exactly one era states where it sits.',
    );
  }
  final pinFrame = document.frames[pins.first];
  final pinEra = eraDeclaration(pinFrame)!;
  if (!isCountableEra(pinFrame)) {
    throw LawRefusal('${pins.first} has no year axis, so it cannot anchor the chain.');
  }
  final pinAnchor = obj(pinEra['anchor']) ?? const {};
  final table = EraTable.parse({
    'anchor': {
      'era': _key(pinEra, pins.first),
      'year': pinAnchor['year'],
      'properYear': pinAnchor['properYear'],
    },
    'entries': [
      for (final id in countable)
        if (eraDeclaration(document.frames[id]) case final Json era) _row(document, id, era),
    ],
  });
  // [EraTable] may reorder by `ordinal`; the chain's own order is authoritative
  // here, so entries are matched back by key rather than by position.
  return (
    ordered: ordered,
    countable: countable,
    table: table,
    byFrame: {
      for (final id in countable)
        if (table.era(_key(eraDeclaration(document.frames[id])!, id)) case final EraEntry entry)
          id: entry,
    },
    pin: pins.first,
  );
}

Json _row(Document document, String id, Json era) => {
  'key': _key(era, id),
  'name': era['name'] ?? document.frames[id]?.title ?? id,
  'direction': era['direction'],
  'years': era['years'],
  'firstYear': era['firstYear'],
  'affix': era['affix'],
};

String _key(Json era, String frameId) {
  final authored = declaredText(era['key']);
  return authored.isEmpty ? frameId : authored;
}

/// The era context one frame's coordinate law needs: its own entry in the chain
/// and the table that entry belongs to. Null for a frame that is not an era.
///
/// A non-countable era resolves to an uncountable context with no table: its law
/// must refuse day ordinals rather than compute them, which is what "ordered,
/// connected, never acquiring day ordinals" means in executable terms.
EraContext? frameEraContext(Document document, String frameId) {
  final frame = document.frames[frameId];
  if (!isEraFrame(frame)) return null;
  final era = eraDeclaration(frame)!;
  if (!isCountableEra(frame)) {
    return EraContext.uncountable(
      key: _key(era, frameId),
      name: declaredText(era['name']).isNotEmpty
          ? declaredText(era['name'])
          : (frame?.title ?? frameId),
    );
  }
  final chains = eraChains(document, frameId);
  if (chains.isEmpty) {
    throw LawRefusal('$frameId is an era but is not in its own chain.');
  }
  final chain = chains.length == 1 ? chains.single : _agreed(document, frameId, chains);
  final entry = chain.byFrame[frameId];
  if (entry == null) {
    throw LawRefusal('$frameId is an era but is not in its own chain.');
  }
  return EraContext.countable(chain.table, entry);
}

/// What every succession through this era AGREES it says -- the branch answer
/// for one frame's own law.
///
/// An era before a branch is in several chains at once, and its law needs one
/// table. Picking a path's table would be picking a successor's calendar to
/// speak for the shared past, which is precisely the silent choice the ruling
/// forbids. So the table is the run every path shares, head-first, up to and
/// including this era: the eras every succession places identically. Past that
/// run the paths differ and this frame's law says nothing rather than something
/// only one of them believes.
///
/// When the shared run does not reach this era -- a pin past the branch, or an
/// era with two predecessors that place it differently -- there is nothing
/// agreed to answer with, and the caller is told which successions disagree.
EraChain _agreed(Document document, String frameId, List<EraChain> chains) {
  final shared = <String>[];
  for (var index = 0; ; index += 1) {
    final id = index < chains.first.ordered.length ? chains.first.ordered[index] : null;
    if (id == null) break;
    final same = chains.every(
      (chain) =>
          index < chain.ordered.length &&
          chain.ordered[index] == id &&
          _placedAlike(chain.byFrame[id], chains.first.byFrame[id]),
    );
    if (!same) break;
    shared.add(id);
  }
  if (!shared.contains(frameId)) {
    throw LawRefusal(
      '${_title(document, frameId)} sits in a different place in each of the'
      ' ${chains.length} successions it lies on, so where it sits has no single'
      ' answer here. Say which succession this asks about.',
    );
  }
  return _resolve(document, shared);
}

/// Two paths place an era alike when both give it the same proper-year range --
/// or both leave it out of the table, which a non-countable era always is.
bool _placedAlike(EraEntry? left, EraEntry? right) =>
    left?.firstProper == right?.firstProper &&
    left?.lastProper == right?.lastProper &&
    left?.key == right?.key;

/// The [EraLookup] a [CoordinateLaws] takes, bound to the document the chain is
/// derived from. An era edit changes a law without changing its declaration at
/// all, which is why the law layer asks for this rather than reading a field.
///
/// SEAM: [CoordinateLaws] speaks the document's raw map form and this speaks
/// records, so the raw argument is ignored -- correct exactly while the two
/// describe the same document, which binding here is the statement of. When the
/// engine lands it holds both forms and hands each layer the one it has.
EraLookup eraLookup(Document document) =>
    (_, frameId) => frameEraContext(document, frameId);
