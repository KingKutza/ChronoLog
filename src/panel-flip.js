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

// The registry every bar dropdown enrolls in — a hamburger, an overflow
// "Options" drop, a document menu, whatever comes next. It holds no DOM
// knowledge of its own (entries are opaque to it); it exists so placement and
// z-level are driven by *enumerating what is registered*, not by a literal
// list of container ids hand-maintained in the UI module. A dropdown that
// never registers here gets neither edge-flip nor the shared z-level — that
// is the one thing a caller must do, and it is the only thing.
export function createDropdownRegistry() {
  const entries = new Map();
  return {
    register(id, entry) { entries.set(id, entry); },
    unregister(id) { entries.delete(id); },
    has(id) { return entries.has(id); },
    get(id) { return entries.get(id); },
    ids() { return [...entries.keys()]; },
    values() { return [...entries.values()]; }
  };
}

// Mutual exclusion: a bar behaves like one instrument with a single open
// dropdown, not a set of independent toggles — opening a new one puts away
// whatever else was open, the way a radio group works. `openIds` is every
// dropdown currently open (including the one that was just opened); this
// returns the ones that must now close. Every registrant gets this the same
// way, in place of the old create-menu/document-menu hand-paired toggle
// listener that only ever covered that one pair.
export function exclusiveOpenSet(openIds, justOpenedId) {
  return openIds.filter((id) => id !== justOpenedId);
}

// Outside-interaction close: a portaled panel is no longer a DOM descendant
// of its own container, so "did the interaction land outside this dropdown"
// can only be answered with the union of container-or-panel containment —
// not container containment alone, which is what the first pass's
// create-menu-only pointerdown patch had to hand-add. `states` is one
// `{ id, open, hit }` per registered dropdown, `hit` meaning the interaction
// target was inside its container or its (possibly portaled) panel; this
// returns the ids that are open and were not hit, i.e. every dropdown a
// press outside it must close. Feeding every registrant through the same
// function is what makes the rule a property of the class rather than a
// patch some dropdowns happen to have and others don't.
export function outsideInteractionCloses(states) {
  return states.filter((state) => state.open && !state.hit).map((state) => state.id);
}

// Tab/Shift-Tab cycling inside a portaled panel. Once a panel lives in
// #dropdown-layer it is no longer a DOM descendant of its anchor, so the
// browser's native tab order no longer runs summary -> panel -> next
// control; it runs summary -> ... -> wherever #dropdown-layer happens to
// sit in the document. Trapping Tab inside the open panel (wrapping at both
// ends) is the deliberate replacement for that broken order, rather than
// leaving keyboard use to wherever the portal lands.
export function wrapFocusIndex(current, delta, count) {
  if (count <= 0) return -1;
  return ((current + delta) % count + count) % count;
}

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
