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
// DIRECTION IS THE ORDER OF THE ENDS. `ends[0]` is the era that finishes and
// `ends[1]` the era that begins. The JavaScript sniffed `end.role` for this --
// a field `validateStapleEnd` never validated, on a record whose top-level
// `role` is explicitly refused -- so `ERA_ROLES` has no counterpart here. A
// staple is two ends in order; that order is the whole of the succession's
// meaning, and reading it needs no vocabulary of its own.
//
// This module walks the chain and derives every era's range. The ARITHMETIC is
// [EraTable]'s, unchanged: ordered eras, per-era direction and first year, one
// authored pin, ranges propagated outward in PROPER YEARS. What changes is where
// the ordered list comes from -- succession staples between frame records rather
// than an array in one declaration -- and that the result is keyed by frame id.

import 'coordinate_law.dart';
import 'eras.dart';
import 'records.dart';

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

/// One succession edge: the staple, and the two frames in its own order.
typedef Succession = ({Relation relation, String from, String to});

List<Succession> successionEdges(Document document) => [
  for (final relation in document.relations.values)
    if (relation.isStaple && relation.kind == 'succession')
      if (relation.ends.whereType<FrameEnd>().toList() case [final from, final to])
        (relation: relation, from: from.frame, to: to.frame),
];

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

/// Every era frame reachable from [frameId] through succession staples, in chain
/// order (oldest first), regardless of which era the caller named.
///
/// A chain is a linked list, so it is walked rather than sorted: the head is the
/// era nothing succeeds. A fork (two eras claiming the same predecessor) or a
/// cycle is refused rather than resolved by precedence -- both mean the author
/// has said two contradictory things about what follows what.
List<String> eraChainFrames(Document document, String frameId) {
  final members = eraChainMembers(document, frameId);
  if (members.isEmpty) return const [];
  final reachable = members.toSet();
  final next = <String, String>{}, previous = <String, String>{};
  for (final edge in successionEdges(document)) {
    if (!reachable.contains(edge.from) || !reachable.contains(edge.to)) {
      continue;
    }
    if (next.containsKey(edge.from) && next[edge.from] != edge.to) {
      throw LawRefusal('Two eras both follow ${edge.from}; a succession chain cannot fork.');
    }
    if (previous.containsKey(edge.to) && previous[edge.to] != edge.from) {
      throw LawRefusal('Two eras both precede ${edge.to}; a succession chain cannot fork.');
    }
    next[edge.from] = edge.to;
    previous[edge.to] = edge.from;
  }
  final heads = [
    for (final id in members)
      if (!previous.containsKey(id)) id,
  ];
  if (heads.length != 1) {
    throw LawRefusal(
      heads.isEmpty
          ? 'This era chain has no beginning, so its eras form a loop.'
          : 'This era chain has ${heads.length} beginnings'
                ' (${heads.join(', ')}); it must have exactly one.',
    );
  }
  final ordered = <String>[];
  final seen = <String>{};
  String? cursor = heads.first;
  while (cursor != null) {
    if (!seen.add(cursor)) {
      throw LawRefusal('The era chain loops at $cursor.');
    }
    ordered.add(cursor);
    cursor = next[cursor];
  }
  if (ordered.length != members.length) {
    throw const LawRefusal('Some eras in this chain are not connected to the rest of it.');
  }
  return ordered;
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
/// The pin is authored on whichever era frame carries `era.anchor`. Exactly one
/// must, for the same reason [EraTable] takes exactly one: two pins are two
/// facts that can disagree.
EraChain? eraChain(Document document, String frameId) {
  final ordered = eraChainFrames(document, frameId);
  if (ordered.isEmpty) return null;
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
        if (eraDeclaration(document.frames[id]) case final Json era)
          {
            'key': _key(era, id),
            'name': era['name'] ?? document.frames[id]?.title ?? id,
            'direction': era['direction'],
            'years': era['years'],
            'firstYear': era['firstYear'],
            'affix': era['affix'],
          },
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
  final chain = eraChain(document, frameId);
  final entry = chain?.byFrame[frameId];
  if (entry == null) {
    throw LawRefusal('$frameId is an era but is not in its own chain.');
  }
  return EraContext.countable(chain!.table, entry);
}

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
