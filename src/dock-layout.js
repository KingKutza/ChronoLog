// Dock panel geometry and state, DOM-free. The dock is the resizable side
// panel that holds a horizontal strip of cards (one card visible at a time,
// paged like a carousel). Everything a drag, a click, or a transition-end
// handler needs to decide lives here as pure functions, so the dock's rules
// are testable in a repo with no DOM-execution tests; `dock.js` (DOM layer)
// only reads pointer/element measurements and calls into this module.

export const DOCK_SIDES = Object.freeze(["right", "left"]);

export const DOCK_WIDTH_MIN = 1 / 8;
export const DOCK_WIDTH_MAX = 2 / 3;

// The default width, used whenever an input is missing or unusable. 1/3 sits
// comfortably inside [MIN, MAX] and is itself a snap point, so a dock that
// falls back to it is already at rest rather than needing a further snap.
const DOCK_WIDTH_DEFAULT = 1 / 3;

export const DOCK_WIDTH_SNAPS = Object.freeze([1 / 8, 1 / 4, 1 / 3, 1 / 2, 2 / 3]);

export const DOCK_SNAP_TOLERANCE = 0.02;

export const DOCK_PAGE_DURATION_MS = 220;
export const DOCK_PAGE_EASING = "cubic-bezier(.25,.9,.25,1)";

// Only "left" is ever recognized as the other side; every other value,
// including garbage, collapses to the default "right". This keeps the dock
// from landing in an undefined visual state just because a caller passed the
// wrong thing.
export function normalizeDockSide(side) {
  return side === "left" ? "left" : "right";
}

// Clamped into the allowed band. Non-finite or otherwise unusable input falls
// back to the default width rather than producing NaN or an out-of-band dock.
export function clampDockWidth(fraction) {
  const value = Number(fraction);
  if (!Number.isFinite(value)) return DOCK_WIDTH_DEFAULT;
  return Math.max(DOCK_WIDTH_MIN, Math.min(DOCK_WIDTH_MAX, value));
}

// Pulls a dragged width onto the nearest snap point when it is close enough,
// so a drag that ends near a common width (a quarter, a third, a half) lands
// on it exactly instead of one pixel off. Values outside tolerance of every
// snap are left alone — the dock is allowed to rest at an arbitrary width.
//
// DOCK_WIDTH_SNAPS is walked in ascending order and ties are broken by a
// strict "closer than" comparison, so at an exact midpoint between two snaps
// the first (smaller) one found keeps its claim. That is an arbitrary choice
// among two equally valid ones, but it has to be some fixed choice or the
// same drag position could snap two different ways on two different runs.
export function snapDockWidth(fraction, tolerance = DOCK_SNAP_TOLERANCE) {
  const clamped = clampDockWidth(fraction);
  let nearest = clamped;
  let nearestDistance = Infinity;
  for (const snap of DOCK_WIDTH_SNAPS) {
    const distance = Math.abs(clamped - snap);
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearest = snap;
    }
  }
  return nearestDistance <= tolerance ? nearest : clamped;
}

// The raw fraction a pointer position implies, before clamping or snapping.
// A right-side dock's near edge is the workspace's right edge, so its width
// grows as the pointer moves left, toward the workspace interior; a left-side
// dock is the mirror image. A workspace with no measured width cannot imply
// any fraction, so this returns the default rather than dividing by zero.
export function dockWidthFromDrag({ side, pointerX, workspaceLeft = 0, workspaceWidth } = {}) {
  const width = Number(workspaceWidth);
  if (!(width > 0)) return DOCK_WIDTH_DEFAULT;
  const left = Number(workspaceLeft) || 0;
  const x = Number(pointerX) || 0;
  return normalizeDockSide(side) === "left"
    ? (x - left) / width
    : (left + width - x) / width;
}

// The dock's on-screen width in whole pixels, for layout that cannot use
// fractional CSS. Negative or missing workspace width floors at zero rather
// than producing a negative panel.
export function dockPixelWidth(fraction, workspaceWidth) {
  const width = Math.max(0, Number(workspaceWidth) || 0);
  return Math.round(clampDockWidth(fraction) * width);
}

// --- Pager -----------------------------------------------------------------
//
// The dock shows one card at a time from a horizontal strip. Pager state is
// `{ index, target }`: `index` is the card currently settled and shown;
// `target` is the card being animated toward, or null when nothing is moving.
//
// The semantic that matters is RETARGET, not QUEUE: repeated page requests
// before the animation finishes must not stack up N transitions. They must
// keep moving the same single target and let one animation chase it. This is
// what keeps rapid clicking or key-repeat from producing a stutter of queued
// slides that arrive long after the user stopped asking for them.

export function dockPagerState(index = 0, target = null) {
  const normalizedIndex = Math.trunc(Number(index) || 0);
  const normalizedTarget = target === null || target === undefined
    ? null
    : Math.trunc(Number(target) || 0);
  return { index: normalizedIndex, target: normalizedTarget };
}

// Accumulates from the pending target when one exists, otherwise from the
// settled index — that is what makes three fast +1 requests land three cards
// ahead with only one animation in flight, instead of each request retargeting
// from wherever the (unfinished) animation happens to be.
export function requestPage(state, delta, count) {
  const total = Math.trunc(Number(count) || 0);
  if (total <= 0) return { index: 0, target: null };
  const current = dockPagerState(state && state.index, state && state.target);
  const base = current.target !== null ? current.target : current.index;
  const step = Math.trunc(Number(delta) || 0);
  const target = ((base + step) % total + total) % total;
  return { index: current.index, target: target === current.index ? null : target };
}

// The absolute-index counterpart, used by clicking a page handle directly or
// by an ordinal key. Out-of-range requests wrap rather than clamp, so index
// arithmetic upstream (e.g. count - 1 - n) does not need its own bounds check.
export function requestPageTo(state, requested, count) {
  const total = Math.trunc(Number(count) || 0);
  if (total <= 0) return { index: 0, target: null };
  const current = dockPagerState(state && state.index, state && state.target);
  const requestedIndex = Math.trunc(Number(requested) || 0);
  const target = ((requestedIndex % total) + total) % total;
  return { index: current.index, target: target === current.index ? null : target };
}

// What a transition-end handler calls: the pending target becomes the settled
// index, and there is nothing left to animate toward.
export function settlePage(state) {
  const current = dockPagerState(state && state.index, state && state.target);
  return { index: current.target !== null ? current.target : current.index, target: null };
}

export function pagerIsMoving(state) {
  return Boolean(state) && state.target !== null && state.target !== undefined;
}

// The transform offset for the full-bleed card strip; the renderer applies
// this as `translateX(<value>%)`. With no cards there is nothing to offset.
export function cardTranslatePercent(index, count) {
  const total = Math.trunc(Number(count) || 0);
  if (total <= 0) return 0;
  // `|| 0` on the way out folds -0 (from index 0) back to a plain 0, so a
  // renderer comparing against 0 for "not offset" cannot be fooled by sign.
  return (-Math.trunc(Number(index) || 0) * 100) || 0;
}

// --- Card order --------------------------------------------------------
//
// The dock's card order is append-only except for an explicit user
// drag-to-swap: opening a card never reorders the cards already there, and
// the only way two cards trade places is `swapCards`. That keeps the dock
// stable under the app's own churn (cards opening and closing) so a user's
// arrangement is disturbed only by their own action.

export function appendCard(order, id) {
  const list = Array.isArray(order) ? order : [];
  if (list.includes(id)) return [...list];
  return [...list, id];
}

export function removeCard(order, id) {
  const list = Array.isArray(order) ? order : [];
  return list.filter((entry) => entry !== id);
}

// Exchanges the positions of two existing, distinct ids. Anything else (a
// missing id, or swapping an id with itself) is a no-op that still returns a
// fresh copy, so callers can always treat the result as new state.
export function swapCards(order, fromId, toId) {
  const list = Array.isArray(order) ? [...order] : [];
  if (fromId === toId) return list;
  const fromIndex = list.indexOf(fromId);
  const toIndex = list.indexOf(toId);
  if (fromIndex === -1 || toIndex === -1) return list;
  const result = [...list];
  result[fromIndex] = toId;
  result[toIndex] = fromId;
  return result;
}

// Brings the recorded order back in line with which cards actually exist:
// entries of `order` that are still live keep their relative positions, dead
// entries fall out, and any live id not yet recorded is appended in the order
// given. That is how a newly opened card lands at the end without disturbing
// a user's arrangement, and how a closed card leaves without a gap.
export function reconcileCardOrder(order, liveIds) {
  const list = Array.isArray(order) ? order : [];
  const live = Array.isArray(liveIds) ? liveIds : [];
  const liveSet = new Set(live);
  const seen = new Set();
  const result = [];
  for (const id of list) {
    if (liveSet.has(id) && !seen.has(id)) {
      result.push(id);
      seen.add(id);
    }
  }
  for (const id of live) {
    if (!seen.has(id)) {
      result.push(id);
      seen.add(id);
    }
  }
  return result;
}
