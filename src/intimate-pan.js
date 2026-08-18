// Free two-axis panning for the Intimate rail. No DOM code lives here so the
// gesture arithmetic is testable; `drag.js` supplies measurements and applies
// the result.
//
// The problem this solves: Intimate's day columns are `minmax(120px, 1fr)`, so
// on any window wide enough to fit `back + forward + 1` days at 120px there is
// no horizontal overflow at all. Setting `scrollLeft` then does nothing and the
// horizontal half of the gesture is silently dead — which is what happened to
// horizontal drag and horizontal wheel on a wide display.
//
// So horizontal motion spends the rail's own slack first, and once the rail is
// pinned at an edge the remaining motion becomes whole-day window steps. On a
// narrow window that reads as scrolling that keeps going; on a wide window,
// where there is no slack at all, it reads as dragging time directly. Vertical
// motion is applied at the same time from the same gesture, never chosen
// against it: the drag is free in both axes.
//
// Nothing here commits to LEXICON's parked "roll" law (continuous sub-day
// sliding that settles to a whole-day detent on release). Steps are whole days
// throughout, so the window is always on a real day boundary and every gesture
// is exactly reversible by dragging back.

export const INTIMATE_WHEEL_NOTCH = 90;
export const INTIMATE_COLUMN_PIXELS_FALLBACK = 120;

// `dx`/`dy` are cumulative from the gesture's start, so the caller can recompute
// from scratch on every pointermove without accumulating drift. `appliedDays` is
// how many day steps this gesture has already committed; `dayDelta` is what is
// left to apply now, which is what keeps the re-render from paging twice.
export function intimatePanStep(input = {}) {
  const columnPixels = Math.max(1, Number(input.columnPixels) || INTIMATE_COLUMN_PIXELS_FALLBACK);
  const maxScrollLeft = Math.max(0, Number(input.maxScrollLeft) || 0);
  const maxScrollTop = Number.isFinite(Number(input.maxScrollTop)) && Number(input.maxScrollTop) > 0
    ? Number(input.maxScrollTop)
    : Infinity;
  const dx = Number(input.dx) || 0;
  const dy = Number(input.dy) || 0;
  const appliedDays = Math.trunc(Number(input.appliedDays) || 0);

  const scrollTop = Math.max(0, Math.min(maxScrollTop, (Number(input.startScrollTop) || 0) - dy));
  const wanted = (Number(input.startScrollLeft) || 0) - dx;
  const scrollLeft = Math.max(0, Math.min(maxScrollLeft, wanted));
  // Whatever the rail could not absorb becomes time. `trunc` (not floor) keeps
  // the two directions symmetric around zero, so a gesture that returns to its
  // origin returns the window to its origin.
  const overshoot = wanted - scrollLeft;
  const dayShift = Math.trunc(overshoot / columnPixels);
  return { scrollLeft, scrollTop, overshoot, dayShift, dayDelta: dayShift - appliedDays };
}

// The wheel equivalent. Horizontal wheel intent is spent on the rail's slack by
// the browser's own native scrolling; this only runs once that slack is gone,
// and carries the sub-notch remainder so slow trackpad motion still accumulates
// into steps instead of being rounded away.
export function intimateWheelStep(input = {}) {
  const notch = Math.max(1, Number(input.notch) || INTIMATE_WHEEL_NOTCH);
  const total = (Number(input.carried) || 0) + (Number(input.delta) || 0);
  const dayShift = Math.trunc(total / notch);
  return { carried: total - dayShift * notch, dayShift };
}

// A wheel event's horizontal intent. Trackpads report `deltaX` directly; a
// mouse wheel with shift held reports `deltaY` and the platform expects that to
// mean horizontal, which the browser only honours when the surface can actually
// scroll horizontally.
export function wheelHorizontalDelta(event = {}) {
  const x = Number(event.deltaX) || 0;
  if (x) return x;
  return event.shiftKey ? Number(event.deltaY) || 0 : 0;
}

// How much room the surface still has in the direction the gesture is pushing.
// While this is positive the browser's native scrolling should be left alone.
export function scrollSlack(position, maximum, delta) {
  const at = Math.max(0, Number(position) || 0);
  const limit = Math.max(0, Number(maximum) || 0);
  if (!delta) return 0;
  return delta > 0 ? limit - at : at;
}
