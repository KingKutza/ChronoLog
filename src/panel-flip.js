// Where a dropdown panel goes so it stays inside the window. No DOM code lives
// here; callers pass measured rectangles and apply the result.
//
// The bug this exists for: the lens Options panel was pinned `right: 0` against
// its summary, so it always opened leftward. Once the context bar became the left
// third of the workspace, opening leftward from a button near the left edge ran
// the panel straight off the window — visible on Tactical, but a property of the
// pinning, not of that lens. A panel has to choose its side from the room it
// actually has.
//
// The preference order is: open in the reading direction (panel's start edge on
// the anchor's start edge), flip to the opposite edge if that overflows, and only
// then clamp. Clamping last matters — flipping keeps the panel visually attached
// to its anchor, while clamping detaches it, so it is the last resort rather than
// the first answer.

export const PANEL_MARGIN = 8;
export const PANEL_GAP = 6;

function clamp(value, low, high) {
  // A panel wider or taller than the window has no satisfying position; pinning
  // it to the low edge at least keeps its start visible and its scroll usable.
  if (high < low) return low;
  return Math.max(low, Math.min(high, value));
}

function span(rect, startKey, endKey, sizeKey) {
  const start = Number(rect?.[startKey]) || 0;
  const size = Number(rect?.[sizeKey]);
  if (Number.isFinite(size) && size > 0) return { start, end: start + size };
  return { start, end: Number(rect?.[endKey]) || start };
}

export function panelPlacement(input = {}) {
  const margin = Number.isFinite(Number(input.margin)) ? Number(input.margin) : PANEL_MARGIN;
  const gap = Number.isFinite(Number(input.gap)) ? Number(input.gap) : PANEL_GAP;
  const anchorX = span(input.anchor, "left", "right", "width");
  const anchorY = span(input.anchor, "top", "bottom", "height");
  const width = Math.max(0, Number(input.panel?.width) || 0);
  const height = Math.max(0, Number(input.panel?.height) || 0);
  const viewportWidth = Math.max(0, Number(input.viewport?.width) || 0);
  const viewportHeight = Math.max(0, Number(input.viewport?.height) || 0);

  const lowX = margin;
  const highX = viewportWidth - width - margin;
  let align = "start";
  let left = anchorX.start;
  if (left > highX) {
    // Flip: hang the panel's end edge off the anchor's end edge.
    align = "end";
    left = anchorX.end - width;
  }
  if (left < lowX || left > highX) {
    align = "clamped";
    left = clamp(left, lowX, highX);
  }

  const lowY = margin;
  const highY = viewportHeight - height - margin;
  let placement = "below";
  let top = anchorY.end + gap;
  if (top > highY) {
    const above = anchorY.start - gap - height;
    // Only flip upward when there is genuinely more room there; otherwise a short
    // window would send the panel off the top instead of off the bottom.
    if (above >= lowY) {
      placement = "above";
      top = above;
    }
  }
  if (top < lowY || top > highY) {
    placement = placement === "above" ? "above-clamped" : "below-clamped";
    top = clamp(top, lowY, highY);
  }

  return { left, top, align, placement };
}
