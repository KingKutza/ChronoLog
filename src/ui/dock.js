import {
  DOCK_PAGE_DURATION_MS,
  DOCK_WIDTH_MAX,
  DOCK_WIDTH_MIN,
  appendCard,
  cardTranslatePercent,
  clampDockWidth,
  dockPagerState,
  dockWidthFromDrag,
  normalizeDockSide,
  pagerIsMoving,
  reconcileCardOrder,
  removeCard,
  requestPage,
  requestPageTo,
  settlePage,
  snapDockWidth,
  swapCards
} from "../dock-layout.js";
import { byId } from "./dom-helpers.js";

// The dock: one multi-function panel that hosts every editor as a full-bleed
// card, paged one at a time. It replaces the right-hand inspector drawer, and the
// difference is not cosmetic — the drawer was an overlay that covered the stage,
// while the dock takes a real grid track, so opening it narrows the stage
// instead. There are no floating windows.
//
// All the geometry and state arithmetic lives in src/dock-layout.js, which is
// DOM-free and tested. This module is the part that cannot be tested without a
// browser, so it deliberately holds no rules of its own: it measures, calls into
// dock-layout, and applies the answer.
export function createDock(app, dom) {
  const { root, dock, resize, rail, viewport, strip } = dom;

  // Cards are held in insertion order in a Map; the rail's display order is the
  // session's `dockOrder`, which is append-only and only ever rearranged by the
  // user dragging a handle.
  const cards = new Map();
  let pager = dockPagerState(0, null);
  let dragState = null;
  let handleDrag = null;
  let settleTimer = null;

  function order() {
    return reconcileCardOrder(app.session.dockOrder, [...cards.keys()]);
  }

  function setOrder(next) {
    app.session.dockOrder = next;
  }

  function isOpen() {
    return cards.size > 0;
  }

  // The card the user is looking at, or heading to. Reading `index` alone would
  // name the card being left for the whole 220ms of a page, so every caller that
  // asked "which card is active" got a stale answer mid-animation.
  function effectiveIndex() {
    return pagerIsMoving(pager) ? pager.target : pager.index;
  }

  function activeId() {
    return order()[effectiveIndex()] || null;
  }

  function applyWidth() {
    const fraction = clampDockWidth(app.session.dockWidth);
    root.style.setProperty("--dock-width", String(fraction));
    // The track is a pixel length so a drag can be exact; the fraction is what
    // persists, so the dock keeps its proportion when the window resizes. A closed
    // dock reports a zero track rather than a stale one, so the variable never
    // disagrees with what is on screen.
    const available = isOpen() ? workspaceWidth() : 0;
    root.style.setProperty("--dock-track", `${Math.round(fraction * available)}px`);
  }

  function workspaceWidth() {
    const measured = dock.parentElement?.getBoundingClientRect().width || 0;
    return measured > 0 ? measured : root.getBoundingClientRect().width || 0;
  }

  function applyChrome() {
    const open = isOpen();
    root.dataset.dockSide = normalizeDockSide(app.session.dockSide);
    root.dataset.dockOpen = String(open);
    dock.hidden = !open;
    dock.dataset.open = String(open);
    applyWidth();
    for (const id of ["new-frame", "manage-frames"]) {
      byId(id)?.setAttribute("aria-expanded", String(open));
    }
  }

  // The strip is translated and nothing else changes, so paging is a
  // compositor-only animation. `data-animating` is switched off for a silent jump
  // (opening a card, closing one) and on for a user-driven page.
  function applyPager({ animate = true } = {}) {
    const ids = order();
    const index = effectiveIndex();
    strip.dataset.animating = String(Boolean(animate) && pagerIsMoving(pager));
    strip.style.transform = `translateX(${cardTranslatePercent(index, ids.length)}%)`;
    ids.forEach((id, position) => {
      const card = cards.get(id);
      if (!card) return;
      const current = position === index;
      card.element.setAttribute("aria-hidden", String(!current));
      // An off-screen card must not be a tab stop, or paging would hand focus to
      // something nobody can see.
      card.element.inert = !current;
    });
    for (const handle of rail.querySelectorAll(".dock-handle")) {
      handle.setAttribute("aria-selected", String(handle.dataset.cardId === ids[index]));
    }
  }

  function settle() {
    if (settleTimer) {
      clearTimeout(settleTimer);
      settleTimer = null;
    }
    if (!pagerIsMoving(pager)) return;
    pager = settlePage(pager);
    applyPager({ animate: false });
  }

  // `transitionend` is the normal way a page commits, but it is not a guarantee:
  // a dock that is hidden, a transform that does not actually change, or a user
  // with reduced motion produces no transition at all. Without a fallback the
  // pager would stay mid-flight forever and every later page would compound off a
  // target that never landed.
  function armSettle() {
    if (settleTimer) clearTimeout(settleTimer);
    settleTimer = setTimeout(settle, DOCK_PAGE_DURATION_MS + 80);
  }

  strip.addEventListener("transitionend", (event) => {
    if (event.target === strip && event.propertyName === "transform") settle();
  });

  function renderRail() {
    const ids = order();
    rail.replaceChildren();
    for (const id of ids) {
      const card = cards.get(id);
      if (!card) continue;
      const handle = document.createElement("button");
      handle.type = "button";
      handle.className = "dock-handle";
      handle.dataset.cardId = id;
      handle.setAttribute("role", "tab");
      handle.draggable = true;
      handle.title = card.title;
      const label = document.createElement("span");
      label.className = "dock-handle-label";
      label.textContent = card.title;
      handle.append(label);
      if (card.closable !== false) {
        const close = document.createElement("span");
        close.className = "dock-handle-close";
        close.setAttribute("role", "button");
        close.setAttribute("aria-label", `Close ${card.title}`);
        close.textContent = "×";
        handle.append(close);
      }
      rail.append(handle);
    }
  }

  function renderStrip() {
    const ids = order();
    // Reordering is done by re-appending existing nodes, never by rebuilding
    // them: a card holds a live form with a provisional draft and focus in it.
    for (const id of ids) {
      const card = cards.get(id);
      if (card) strip.append(card.element);
    }
  }

  function render({ animate = false } = {}) {
    renderRail();
    renderStrip();
    const count = order().length;
    if (pager.index >= count) pager = dockPagerState(Math.max(0, count - 1), null);
    applyChrome();
    applyPager({ animate });
  }

  // Opening a card that is already open focuses it rather than duplicating it.
  // Identity is the caller's `id`, which is how "open this event" twice lands on
  // one card instead of two views of the same object.
  //
  // `refresh` is how a card opts into staying live: pass a handler and it is
  // called every time `refreshDockCards()` runs (see below), so the caller is
  // responsible for reconciling its own body against the document rather than
  // this module rebuilding it. Omit it and the card is left alone, which is the
  // right answer for a card holding a provisional draft or an in-progress form
  // that a naive rebuild would destroy.
  function openCard({ id, title, body, closable = true, onClose = null, refresh = null }) {
    const existing = cards.get(id);
    if (existing) {
      existing.title = title || existing.title;
      if (body) {
        existing.body.replaceChildren(body);
      }
      if (refresh) existing.refresh = refresh;
      cards.set(id, existing);
      setOrder(appendCard(order(), id));
      render();
      focusCard(id, { animate: false });
      return existing;
    }
    const element = document.createElement("section");
    element.className = "dock-card";
    element.dataset.cardId = id;
    element.setAttribute("role", "tabpanel");
    element.setAttribute("aria-label", title || "Card");
    const bodyNode = document.createElement("div");
    bodyNode.className = "dock-card-body";
    if (body) bodyNode.append(body);
    element.append(bodyNode);
    const card = { id, title: title || "Card", element, body: bodyNode, closable, onClose, refresh };
    cards.set(id, card);
    setOrder(appendCard(order(), id));
    render();
    focusCard(id, { animate: false });
    return card;
  }

  // The one place every open card is asked to notice the document changed
  // underneath it. This replaces what used to be a hand-maintained list of
  // per-card calls in the render loop (one for the roster cards, none for the
  // Frames browser, and nothing stopping the next card from being forgotten the
  // same way) with a mechanism: a card registers its own reactivity by passing
  // `refresh` to `openDockCard`, and that is the only way a card gets touched
  // here. A card that never registered one is left exactly alone.
  function refreshDockCards() {
    for (const card of cards.values()) card.refresh?.();
  }

  function closeCard(id) {
    const card = cards.get(id);
    if (!card) return false;
    cards.delete(id);
    setOrder(removeCard(order(), id));
    card.element.remove();
    card.onClose?.(id);
    // A dock with nothing in it closes: an empty panel holding the stage's width
    // hostage is worse than no panel.
    render();
    return true;
  }

  function closeAllCards() {
    for (const id of [...cards.keys()]) {
      const card = cards.get(id);
      cards.delete(id);
      card.element.remove();
      card.onClose?.(id);
    }
    setOrder([]);
    pager = dockPagerState(0, null);
    render();
  }

  // A card that has just appeared should already be there; only a move between
  // existing cards is worth animating. So opening passes `animate: false`, which
  // commits synchronously instead of waiting on a transition.
  function focusCard(id, { animate = true } = {}) {
    const ids = order();
    const index = ids.indexOf(id);
    if (index < 0) return false;
    pager = requestPageTo(pager, index, ids.length);
    if (!animate) {
      settle();
      applyPager({ animate: false });
      return true;
    }
    applyPager({ animate: true });
    if (pagerIsMoving(pager)) armSettle();
    return true;
  }

  function pageBy(delta) {
    const ids = order();
    if (ids.length < 2) return;
    pager = requestPage(pager, delta, ids.length);
    applyPager({ animate: true });
    if (pagerIsMoving(pager)) armSettle();
  }

  function pageTo(index) {
    const ids = order();
    if (!ids.length) return;
    pager = requestPageTo(pager, index, ids.length);
    applyPager({ animate: true });
    if (pagerIsMoving(pager)) armSettle();
  }

  rail.addEventListener("click", (event) => {
    const handle = event.target.closest(".dock-handle");
    if (!handle) return;
    if (event.target.closest(".dock-handle-close")) {
      closeCard(handle.dataset.cardId);
      return;
    }
    focusCard(handle.dataset.cardId);
  });

  // Handles reorder only by explicit user drag. Nothing else in the system may
  // rearrange them, which is what makes the rail a stable place to aim.
  rail.addEventListener("dragstart", (event) => {
    const handle = event.target.closest(".dock-handle");
    if (!handle) return;
    handleDrag = handle.dataset.cardId;
    handle.dataset.dragging = "true";
    event.dataTransfer?.setData("text/plain", handleDrag);
  });

  rail.addEventListener("dragover", (event) => {
    const handle = event.target.closest(".dock-handle");
    if (!handleDrag || !handle || handle.dataset.cardId === handleDrag) return;
    event.preventDefault();
    handle.dataset.drop = "true";
  });

  rail.addEventListener("dragleave", (event) => {
    const handle = event.target.closest(".dock-handle");
    if (handle) delete handle.dataset.drop;
  });

  rail.addEventListener("drop", (event) => {
    const handle = event.target.closest(".dock-handle");
    if (!handleDrag || !handle) return;
    event.preventDefault();
    const active = activeId();
    setOrder(swapCards(order(), handleDrag, handle.dataset.cardId));
    handleDrag = null;
    render();
    // The card the user was looking at stays the card they are looking at, even
    // though its position in the rail changed.
    if (active) focusCard(active, { animate: false });
  });

  rail.addEventListener("dragend", () => {
    handleDrag = null;
    for (const handle of rail.querySelectorAll(".dock-handle")) {
      delete handle.dataset.dragging;
      delete handle.dataset.drop;
    }
  });

  // Shift- or ctrl-scroll over the dock cycles cards. A plain wheel is left to
  // the card's own scrolling, which is usually a long form.
  dock.addEventListener("wheel", (event) => {
    if (!event.shiftKey && !event.ctrlKey && !event.metaKey) return;
    if (order().length < 2) return;
    event.preventDefault();
    const delta = event.deltaY || event.deltaX;
    if (!delta) return;
    pageBy(delta > 0 ? 1 : -1);
  }, { passive: false });

  // Width drag. The lens re-renders once at rest, not per frame: during the drag
  // only the CSS custom property moves, which is a layout the browser can do
  // without the projection being rebuilt.
  function beginResize(event) {
    dragState = { pointerId: event.pointerId };
    resize.dataset.dragging = "true";
    resize.setPointerCapture?.(event.pointerId);
    event.preventDefault();
  }

  function moveResize(event) {
    if (!dragState || dragState.pointerId !== event.pointerId) return;
    const bounds = dock.parentElement?.getBoundingClientRect();
    if (!bounds) return;
    const raw = dockWidthFromDrag({
      side: normalizeDockSide(app.session.dockSide),
      pointerX: event.clientX,
      workspaceLeft: bounds.left,
      workspaceWidth: bounds.width
    });
    app.session.dockWidth = snapDockWidth(raw);
    applyWidth();
  }

  function endResize(event) {
    if (!dragState || (event && dragState.pointerId !== event.pointerId)) return;
    dragState = null;
    delete resize.dataset.dragging;
    // One render at rest. This is the whole reason the drag writes a CSS variable
    // instead of calling scheduleRender per pointermove.
    app.scheduleRender();
  }

  resize.addEventListener("pointerdown", beginResize);
  resize.addEventListener("pointermove", moveResize);
  resize.addEventListener("pointerup", endResize);
  resize.addEventListener("pointercancel", endResize);

  resize.addEventListener("keydown", (event) => {
    // A nudge of one hour, or half an hour, of a day's worth of screen width
    // -- expressed as a fraction of one day under the primary frame's own
    // law, so an hour is genuinely 1/23 of the day on a 23-hour frame rather
    // than the bare civil 1/24 this used to hardcode. `unitDays("hour")` is
    // null only for a declaration that gives "hour" a transition instead of a
    // radix, which no authored frame does; `meanUnitDays` is the fallback for
    // that theoretical case rather than a silent throw.
    const law = app.session.law;
    const hourDays = law.unitDays("hour") ?? law.meanUnitDays("hour");
    const step = hourDays
      ? (event.shiftKey ? hourDays.toNumber() : hourDays.div(2).toNumber())
      : (event.shiftKey ? 1 / 24 : 1 / 48);
    const side = normalizeDockSide(app.session.dockSide);
    // Left and Right always mean "narrower" and "wider" relative to the dock's
    // own edge, so the keys agree with what the user sees rather than with the
    // axis direction.
    const outward = side === "right" ? "ArrowLeft" : "ArrowRight";
    const inward = side === "right" ? "ArrowRight" : "ArrowLeft";
    let next = null;
    if (event.key === outward) next = clampDockWidth(app.session.dockWidth + step);
    else if (event.key === inward) next = clampDockWidth(app.session.dockWidth - step);
    else if (event.key === "Home") next = DOCK_WIDTH_MIN;
    else if (event.key === "End") next = DOCK_WIDTH_MAX;
    else return;
    event.preventDefault();
    app.session.dockWidth = next;
    applyWidth();
    app.scheduleRender();
  });

  function setSide(side) {
    app.session.dockSide = normalizeDockSide(side);
    applyChrome();
    app.scheduleRender();
  }

  function toggleSide() {
    setSide(normalizeDockSide(app.session.dockSide) === "right" ? "left" : "right");
  }

  window.addEventListener("resize", applyWidth);

  render();

  return {
    openDockCard: openCard,
    closeDockCard: closeCard,
    closeAllDockCards: closeAllCards,
    refreshDockCards,
    focusDockCard: focusCard,
    dockCardIds: () => order(),
    hasDockCard: (id) => cards.has(id),
    activeDockCardId: activeId,
    dockIsOpen: isOpen,
    dockCardBody: (id) => cards.get(id)?.body || null,
    pageDockBy: pageBy,
    pageDockTo: pageTo,
    setDockSide: setSide,
    toggleDockSide: toggleSide,
    applyDockChrome: applyChrome
  };
}
