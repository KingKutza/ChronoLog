import { renderMinimap, renderProjection } from "../projections.js";

export const SESSION_STORAGE_KEY = "chronolog:view-session:1";

// The render loop and minimap wiring. `app` carries the live document/engine/
// session plus the small bag of transient view state (scroll memory,
// Intimate rebase/zoom requests, the scroll guard) that render() and the
// toolbar's chrome-sync functions (`app.updateCalendarSelect`,
// `app.updateChrome`, `app.updateLensControls`, `app.reconcileRadialCycle`,
// `app.refreshDockCards`) both read and write.
export function createWorkspace(app, dom) {
  const { projection, minimap } = dom;
  let renderQueued = false;

  function context() {
    return { document: app.chronolog, engine: app.engine, session: app.session, loading: app.documentLoading };
  }

  function scheduleRender() {
    try { localStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(app.session.toJSON())); } catch {}
    if (renderQueued) return;
    renderQueued = true;
    requestAnimationFrame(() => {
      renderQueued = false;
      render();
    });
  }

  function render() {
    app.reconcileRadialCycle();
    const previousScroll = projection.querySelector("[data-scroll-key]");
    if (previousScroll && !(previousScroll.dataset.scrollKey === "intimate" && (app.pendingIntimateRebase || app.pendingIntimateZoom))) {
      app.viewScroll.set(previousScroll.dataset.scrollKey, {
        top: previousScroll.scrollTop,
        left: previousScroll.scrollLeft
      });
    }
    app.updateCalendarSelect();
    app.updateChrome();
    // Every open dock card gets one chance to notice the document changed
    // underneath it. This used to be a hand-maintained list of per-card calls
    // right here (the roster cards had one; the Frames browser card did not,
    // which is why importing a calendar while it was open left the new frame
    // invisible until the card was closed and reopened). `refreshDockCards`
    // (src/ui/dock.js) is a registry instead: a card asks to stay live once, by
    // passing `refresh` to `openDockCard` when it opens, and this is the one
    // place that registry is walked — so a future card can forget to add a line
    // here, because there is no line here to add.
    app.refreshDockCards();
    app.updateLensControls();
    renderProjection(projection, context());
    const nextScroll = projection.querySelector("[data-scroll-key]");
    if (nextScroll) {
      let saved = app.viewScroll.get(nextScroll.dataset.scrollKey);
      if (nextScroll.dataset.scrollKey === "intimate" && app.pendingIntimateRebase) saved = app.pendingIntimateRebase;
      if (nextScroll.dataset.scrollKey === "intimate" && app.pendingIntimateZoom) {
        const hourPixels = Number(nextScroll.dataset.hourPixels || 28);
        const bufferHours = Number(nextScroll.dataset.bufferHours || 24);
        const headerPixels = Number(nextScroll.dataset.headerPixels || 70);
        saved = {
          top: headerPixels + (bufferHours + app.pendingIntimateZoom.localHour) * hourPixels - app.pendingIntimateZoom.offset,
          left: app.pendingIntimateZoom.left
        };
      }
      if (saved) {
        const intimateProgrammaticScroll = nextScroll.dataset.scrollKey === "intimate";
        const scrollGuard = intimateProgrammaticScroll ? ++app.intimateScrollGuard : 0;
        nextScroll.scrollTop = saved.top;
        nextScroll.scrollLeft = saved.left;
        if (nextScroll.dataset.scrollKey === "intimate" && (app.pendingIntimateRebase || app.pendingIntimateZoom)) {
          app.viewScroll.set("intimate", { top: nextScroll.scrollTop, left: nextScroll.scrollLeft });
          app.pendingIntimateRebase = null;
          app.pendingIntimateZoom = null;
        }
        if (intimateProgrammaticScroll) {
          requestAnimationFrame(() => {
            if (app.intimateScrollGuard === scrollGuard) app.intimateScrollGuard = 0;
          });
        }
      } else if (nextScroll.dataset.scrollKey === "intimate") {
        const bufferHours = Number(nextScroll.dataset.bufferHours || 0);
        const hourPixels = Number(nextScroll.dataset.hourPixels || 56);
        const initialHour = Number(nextScroll.dataset.initialHour || app.session.intimateStartHour);
        const scrollGuard = ++app.intimateScrollGuard;
        nextScroll.scrollTop = Math.max(0, 70 + (bufferHours + initialHour) * hourPixels - nextScroll.clientHeight / 2);
        requestAnimationFrame(() => {
          if (app.intimateScrollGuard === scrollGuard) app.intimateScrollGuard = 0;
        });
      }
    }
    renderMinimap(minimap, context());
  }

  return { scheduleRender, render };
}
