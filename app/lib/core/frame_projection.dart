// CROSS-FRAME PROJECTION EXISTS ONLY THROUGH STAPLES.
//
// Ruling: "For Tamriel, there is no staple between earth and Tamriel, thus no way
// to project one to the other. The moment we place a staple, wherever it is
// everything projects around that, we place 8 that is where lines shows us the
// warp."
//
// Three separate claims, and none of them implies another:
//
//   * `law.sharesStandardAtom()` says two frames' UNITS are comparable in length.
//     A Tamrielic hour and an Earth hour are both hours. That is a statement
//     about duration and says nothing whatever about WHEN.
//   * `law.mapsToClock()` says a frame has a now at all.
//   * a STAPLE PATH says two frames have positional correspondence -- that a
//     position on one names a position on the other.
//
// An authored origin is CHAIN-INTERNAL: it anchors a calendar's own eras relative
// to EACH OTHER so the chain resolves exact internal ordinals. It is not a claim
// on any shared axis, and treating it as one is what would silently drop
// Tamriel's Third Era next to 1970 on the wall-time axis -- an invented
// correspondence nobody authored, which is the whole class of error this program
// refuses.
//
// So with no staple path, neither frame projects onto the other and an overlay
// renders nothing from the far frame. That is an honest refusal, not a gap.
//
// MULTIPLE STAPLES DEFINE THE CORRESPONDENCE EXACTLY AT EACH STAPLED POINT and
// are never averaged into a single rigid offset. Between two stapled points the
// mapping STRETCHES, and that stretch is authored meaning -- the warp. Drawing it
// is the Lines lens's work; this module answers only whether any correspondence
// exists at all.
//
// THE SEAM. The document arrives in the RAW MAP form the coordinate-law layer
// caches on: handing [CoordinateLaws] a freshly built map would defeat its
// identity cache on every call. The relation records are parsed off that same map
// once per instance, through the record layer's own reader, so an end's scope is
// decided in exactly one place.

import 'coordinate_law.dart';
import 'eras.dart';
import 'records.dart';

/// One frame refused an axis, with the sentence the author is shown.
typedef Refusal = ({String frame, String message});

class FrameProjection {
  FrameProjection(this.document, {CoordinateLaws? laws}) : laws = laws ?? CoordinateLaws();

  final Map<String, Object?> document;
  final CoordinateLaws laws;
  final Map<String, String> _spaces = {};
  late final List<(String, String)> _edges = _frameEdges();

  /// The frame whose declaration actually governs [frameId] -- following
  /// `coordinateDefinition` and `basis` to the frame that owns the coordinate
  /// space. Two frames resolving to the same owner ARE the same space (every era
  /// frame of one calendar), so they project onto each other with no staple. An
  /// unresolvable law is its own space: a broken declaration relates it to
  /// nothing rather than to everything.
  String coordinateSpaceOf(String frameId) =>
      _spaces[frameId] ??= laws.attempt(document, frameId).resolved?.frameId ?? frameId;

  /// Only a staple touching TWO frames relates them. A frame+object or
  /// frame+series staple places something on one frame and says nothing about
  /// any other.
  List<(String, String)> _frameEdges() {
    final edges = <(String, String)>[];
    for (final row in asMap(document['relations'])?.values ?? const []) {
      final relation = asMap(row);
      if (relation == null || relation['type'] != 'staple') continue;
      final frames = [
        for (final end in Relation.fromJson(relation).ends)
          if (end is FrameEnd) end.frame,
      ];
      if (frames.length == 2 && frames[0] != frames[1]) {
        edges.add((frames[0], frames[1]));
      }
    }
    return edges;
  }

  /// Is there any authored correspondence between these two frames?
  ///
  /// True when they are the same frame, when they resolve to the same coordinate
  /// space, or when a chain of frame-to-frame staples connects them. False means
  /// exactly what it says: nothing anybody authored relates a position on one to
  /// a position on the other, so neither may be drawn on the other's axis.
  bool framesProject(String from, String onto) {
    if (from.isEmpty || onto.isEmpty || from == onto) return true;
    if (coordinateSpaceOf(from) == coordinateSpaceOf(onto)) return true;
    if (_edges.isEmpty) return false;
    // Reachability over authored staples, plus coordinate-space equivalence at
    // each hop: a staple onto any frame of a shared space reaches every frame of
    // it.
    final target = coordinateSpaceOf(onto);
    final seen = {from, coordinateSpaceOf(from)};
    final queue = [from];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (final (left, right) in _edges) {
        for (final (near, far) in [(left, right), (right, left)]) {
          if (near != current && coordinateSpaceOf(near) != coordinateSpaceOf(current)) {
            continue;
          }
          final farSpace = coordinateSpaceOf(far);
          if (far == onto || farSpace == target) return true;
          if (!seen.add(far)) continue;
          seen.add(farSpace);
          queue.add(far);
        }
      }
    }
    return false;
  }

  /// The subset of [frameIds] that may be drawn on [onto]'s axis, in the order
  /// given, plus the ones refused and why. A caller REPORTS the refusals rather
  /// than dropping them silently: a frame that renders nothing because nothing
  /// relates it to the view is a fact the author needs told.
  ({List<String> projectable, List<Refusal> refused}) projectableFrames(
    Iterable<String> frameIds,
    String onto,
  ) {
    final projectable = <String>[];
    final refused = <Refusal>[];
    for (final frameId in frameIds) {
      if (framesProject(frameId, onto)) {
        projectable.add(frameId);
      } else {
        refused.add((
          frame: frameId,
          message:
              '${_title(frameId)} has no authored correspondence with '
              '${_title(onto)}, so nothing of it can be placed here. '
              'Staple a point between them to relate the two.',
        ));
      }
    }
    return (projectable: projectable, refused: refused);
  }

  String _title(String frameId) {
    final title = asMap(asMap(document['frames'])?[frameId])?['title'];
    return declaredText(title).isEmpty ? frameId : declaredText(title);
  }
}
