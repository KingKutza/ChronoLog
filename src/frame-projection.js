import { coordinateLaw } from "./coordinate-law.js";
import { endId, endScope, stapleEnds } from "./staples.js";

// CROSS-FRAME PROJECTION EXISTS ONLY THROUGH STAPLES.
//
// Owner ruling: "For Tamriel, there is no staple between earth and Tamriel, thus
// no way to project one to the other. The moment we place a staple, wherever it
// is everything projects around that, we place 8 that is where lines shows us the
// warp."
//
// Three separate claims, and none of them implies another:
//
//   * `law.sharesStandardAtom()` says two frames' UNITS are comparable in length.
//     A Tamrielic hour and an Earth hour are both hours. That is a statement about
//     duration and says nothing whatever about WHEN.
//   * `law.mapsToClock()` says a frame has a now at all.
//   * a STAPLE PATH says two frames have positional correspondence -- that a
//     position on one names a position on the other.
//
// An authored origin is chain-internal: it anchors a calendar's own eras relative
// to EACH OTHER so the chain resolves exact internal ordinals. It is not a claim
// on any shared axis, and treating it as one is what would silently drop Tamriel's
// Third Era next to 1970 on the wall-time axis -- an invented correspondence
// nobody authored, which is the whole class of error this program refuses.
//
// So with no staple path, neither frame projects onto the other and an overlay
// renders nothing from the far frame. That is an honest refusal, not a gap.
//
// MULTIPLE STAPLES DEFINE THE CORRESPONDENCE EXACTLY AT EACH STAPLED POINT and
// are never averaged into a single rigid offset. Between two stapled points the
// mapping STRETCHES, and that stretch is authored meaning -- the warp. Drawing it
// is the Lines lens's work, not this module's; this module answers only whether
// any correspondence exists at all.

/**
 * The frame whose declaration actually governs `frameId` -- following
 * `coordinateDefinition` and `basis` to the frame that owns the coordinate space.
 * Two frames resolving to the same owner ARE the same space (every era frame of
 * one calendar, for instance), so they project onto each other with no staple.
 */
export function coordinateSpaceOf(documentValue, frameId) {
  try {
    return coordinateLaw(documentValue, frameId).frameId || String(frameId);
  } catch {
    return String(frameId);
  }
}

function frameStapleEdges(documentValue) {
  const edges = [];
  for (const relation of Object.values(documentValue?.relations || {})) {
    if (relation?.type !== "staple") continue;
    const frames = stapleEnds(relation)
      .filter((end) => endScope(end) === "frame")
      .map((end) => endId(end))
      .filter(Boolean);
    // Only a staple that touches TWO frames relates them. A frame+object or
    // frame+series staple places something on one frame and says nothing about
    // any other.
    if (frames.length === 2 && frames[0] !== frames[1]) edges.push(frames);
  }
  return edges;
}

/**
 * Is there any authored correspondence between these two frames?
 *
 * True when they are the same frame, when they resolve to the same coordinate
 * space, or when a chain of frame-to-frame staples connects them. False means
 * exactly what it says: nothing anybody authored relates a position on one to a
 * position on the other, so neither may be drawn on the other's axis.
 */
export function framesProject(documentValue, fromFrameId, ontoFrameId) {
  const from = String(fromFrameId);
  const onto = String(ontoFrameId);
  if (!from || !onto || from === onto) return true;
  if (coordinateSpaceOf(documentValue, from) === coordinateSpaceOf(documentValue, onto)) return true;

  const edges = frameStapleEdges(documentValue);
  if (!edges.length) return false;
  // Reachability over authored staples, plus coordinate-space equivalence at each
  // hop: a staple onto any frame of a shared space reaches every frame of it.
  const target = coordinateSpaceOf(documentValue, onto);
  const seen = new Set([from, coordinateSpaceOf(documentValue, from)]);
  const queue = [from];
  while (queue.length) {
    const current = queue.pop();
    for (const [left, right] of edges) {
      for (const [near, far] of [[left, right], [right, left]]) {
        if (near !== current && coordinateSpaceOf(documentValue, near) !== coordinateSpaceOf(documentValue, current)) continue;
        const farSpace = coordinateSpaceOf(documentValue, far);
        if (far === onto || farSpace === target) return true;
        if (seen.has(far)) continue;
        seen.add(far);
        seen.add(farSpace);
        queue.push(far);
      }
    }
  }
  return false;
}

/**
 * The subset of `frameIds` that may be drawn on `ontoFrameId`'s axis, in the
 * order given, plus the ones refused and why. A caller reports the refusals
 * rather than dropping them silently: a frame that renders nothing because
 * nothing relates it to the view is a fact the author needs told.
 */
export function projectableFrames(documentValue, frameIds, ontoFrameId) {
  const projectable = [];
  const refused = [];
  for (const frameId of frameIds || []) {
    if (framesProject(documentValue, frameId, ontoFrameId)) projectable.push(frameId);
    else {
      refused.push({
        frame: frameId,
        message: `${documentValue?.frames?.[frameId]?.title || frameId} has no authored correspondence with `
          + `${documentValue?.frames?.[ontoFrameId]?.title || ontoFrameId}, so nothing of it can be placed here. `
          + `Staple a point between them to relate the two.`
      });
    }
  }
  return { projectable, refused };
}
