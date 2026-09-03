// Pure Dart. Nothing under lib/core/ may import Flutter or a third-party
// package.
//
// "STAPLED HERE" IS A NEIGHBOURHOOD QUERY ON THE GRAPH (ISSUES 9.2, Don: "the
// frame for PTP shows nothing stapled here when there are two events. And frames
// with a lot of events are overflowing rather than showing staples. Perhaps a
// list of stapled items by type.").
//
// What that row asked before was the PLACEMENT index -- placed, not merely
// connected -- so an affiliation, an anchor with no coordinate and a verb nobody
// registered were all invisible in the region built to show them; it walked
// `document.events` alone, so a frame stapled to a frame could never appear, and
// eras are frames stapled together; and it truncated into a dead-end "+N more."
//
// One fix, and it is one question: the whole pile is a graph and this is its
// neighbourhood. Every record kind, every staple, coordinate or none, anchoring
// kind or none.
//
// MELT, NOT A SECOND WALK. `ProjectionEngine.connectionsOf` already answers
// every edge from either side; this GROUPS that answer and re-implements no
// traversal. The headings come from the object-kind CATALOG, handed in, so a
// fourth kind is a heading with no code change here. A window bounds what is
// LISTED and never what is COUNTED -- "if it is not usable at 500 calendars it
// is improperly built for 3".

import 'object_kinds.dart';
import 'projection.dart';

/// One heading of the neighbourhood: which catalog row it is, the row's own
/// label, the TRUE total however few are listed, and the ids listed.
typedef StapledGroup = ({String kind, String label, int total, List<String> window});

/// The word the frames' own heading is filed under. Frames are not in the
/// object catalog -- they are the other thing a staple can name -- so they get
/// their own row rather than a catalog entry that would make a frame an object.
const String stapledFrameKind = 'frame';

/// The heading a frame row wears.
const String stapledFrameLabel = 'Frame';

/// What is stapled to one record, grouped.
class StapledHere {
  const StapledHere(this.groups, this.total);

  /// One group per kind that has members here, in catalog order, with the
  /// frames last. A kind nothing here wears is not a heading: an empty row says
  /// nothing and costs a reader a line.
  final List<StapledGroup> groups;

  /// Everything stapled here, counted whole -- not the sum of what is listed.
  final int total;

  StapledGroup? group(String kind) {
    for (final found in groups) {
      if (found.kind == kind) return found;
    }
    return null;
  }
}

/// THE NEIGHBOURHOOD OF [frameId], read off the one connection graph.
///
/// [kinds] is the object catalog to group by, a parameter so the fourth-kind
/// claim is executable rather than asserted. [window] bounds the ids each group
/// lists and NEVER the count it reports; null lists everything.
StapledHere stapledHere(
  ProjectionEngine engine,
  String frameId, {
  Map<String, ObjectKind> kinds = objectKinds,
  int? window,
}) {
  final document = engine.document;
  // Deterministic, and each neighbour counted ONCE however many edges say so:
  // two records are neighbours or they are not, and a second sentence saying
  // the same thing is not a second member.
  final neighbours = <String>{
    for (final edge in engine.connectionsOf(frameId))
      for (final id in [edge.from, edge.to])
        if (id != frameId) id,
  }.toList()..sort();

  final members = <String, List<String>>{};
  for (final id in neighbours) {
    // A staple end may name a record the document does not hold. That is a real
    // fact about the pile and the pile search is where it is asked; a heading
    // cannot say what kind a record it does not have is, so it is not one here.
    final kind = document.frames.containsKey(id)
        ? stapledFrameKind
        : document.events.containsKey(id)
        ? objectKindForEvent(document.events[id], kinds: kinds)
        : null;
    if (kind == null) continue;
    (members[kind] ??= []).add(id);
  }

  final groups = <StapledGroup>[
    for (final kind in [...kinds.keys, stapledFrameKind])
      if (members[kind] case final List<String> here)
        (
          kind: kind,
          label: kinds[kind]?.label ?? stapledFrameLabel,
          total: here.length,
          window: window == null ? here : here.take(window).toList(),
        ),
  ];
  return StapledHere(groups, groups.fold(0, (sum, group) => sum + group.total));
}
