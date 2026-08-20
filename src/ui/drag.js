import { Rational, formatCivil } from "../exact.js";
import { coordinateLaw } from "../coordinate-law.js";
import {
  INTIMATE_COLUMN_PIXELS_FALLBACK,
  intimatePanStep,
  intimateWheelStep,
  scrollSlack,
  wheelHorizontalDelta
} from "../intimate-pan.js";
import { clone, durationMagnitudeDays } from "../model.js";
import { putOp } from "../ops.js";
import { minimapDragFocus, minimapDragState } from "../session.js";

// Pointer/wheel/drag mapping onto the lens surfaces: wheel pan/zoom
// (including the radial "spin" animation and Intimate's hour-pixel zoom),
// dragging an existing event onto a new cell, drag-to-create, the Intimate
// rail's continuous-scroll rebasing, and the minimap's drag-to-scrub. `app`
// carries the live document/engine/session/history plus the small bag of
// transient view state (`viewScroll`, `pendingIntimateRebase`,
// `pendingIntimateZoom`, `intimateScrollGuard`) that the render loop in
// workspace.js also reads and writes.
export function createDragController(app, dom) {
  const { projection, minimap } = dom;

  let zoomWheel = 0;
  let panWheel = 0;
  let intimateWheelCarry = 0;
  let radialWheelAnimation = null;

  function intimateScroll() {
    return projection.querySelector(".intimate-scroll");
  }

  // The governing frame's hours-per-day, as a plain number for pixel/layout
  // math. Every `dataset.bufferHours`/`dataset.timelineHours` fallback below
  // used to assume a bare 24; this is what they fall back to instead, so a
  // 23-hour frame gets 23-hour columns rather than one silently missing hour.
  function frameHoursPerDay() {
    return app.session.hoursPerDay().toNumber();
  }

  // One day column's width in pixels: the distance a horizontal gesture has to
  // cover to be worth one day of window movement.
  function intimateColumnPixels() {
    const width = projection.querySelector(".intimate-day-column")?.getBoundingClientRect().width || 0;
    return width > 1 ? width : INTIMATE_COLUMN_PIXELS_FALLBACK;
  }

  // LEXICON's "roll, first dose" gives the header the horizontal gesture:
  // "drag the header / horizontal wheel slides the window". The day-header strip
  // and the hour rail are chrome — no event is ever created by dragging across
  // them — so a plain drag there pans, while a plain drag inside a day column
  // still creates. Shift-drag pans anywhere, exactly as before, so a modifier
  // never means two different things.
  function intimatePanSurface(target) {
    return Boolean(target?.closest?.(".intimate-header,.intimate-gutter,.intimate-corner"));
  }

  function animateRadialWheel(delta) {
    const { session } = app;
    const current = session.currentFocus();
    const priorTarget = radialWheelAnimation?.target || current;
    radialWheelAnimation = {
      from: current,
      target: priorTarget.add(delta),
      started: performance.now(),
      lens: session.currentLens(),
      frame: radialWheelAnimation?.frame || 0
    };
    document.body.classList.add("radial-wheel-motion");
    if (radialWheelAnimation.frame) return;
    const advance = (now) => {
      const animation = radialWheelAnimation;
      if (!animation || animation.lens !== session.currentLens()) {
        radialWheelAnimation = null;
        document.body.classList.remove("radial-wheel-motion");
        return;
      }
      const progress = Math.min(1, (now - animation.started) / 240);
      const eased = 1 - (1 - progress) ** 3;
      session.setFocus(animation.from.add(animation.target.sub(animation.from).mul(String(eased))));
      app.scheduleRender();
      if (progress < 1) {
        animation.frame = requestAnimationFrame(advance);
      } else {
        session.setFocus(animation.target);
        radialWheelAnimation = null;
        app.scheduleRender();
        requestAnimationFrame(() => requestAnimationFrame(() => {
          if (!radialWheelAnimation) document.body.classList.remove("radial-wheel-motion");
        }));
      }
    };
    radialWheelAnimation.frame = requestAnimationFrame(advance);
  }

  function prepareIntimateZoom(value, pointerOffset = null) {
    const { session } = app;
    const scroll = projection.querySelector(".intimate-scroll");
    const offset = pointerOffset ?? scroll?.clientHeight / 2 ?? projection.clientHeight / 2;
    const hourPixels = Number(scroll?.dataset.hourPixels || session.intimateHourPixels);
    const bufferHours = Number(scroll?.dataset.bufferHours || frameHoursPerDay());
    const headerPixels = Number(scroll?.dataset.headerPixels || 70);
    const localHour = scroll
      ? (scroll.scrollTop + offset - headerPixels) / hourPixels - bufferHours
      : (session.intimateStartHour + session.intimateEndHour) / 2;
    app.pendingIntimateRebase = null;
    app.pendingIntimateZoom = { localHour, offset, left: scroll?.scrollLeft || 0 };
    session.setIntimateHourPixels(value);
  }

  function adjustWindow(steps) {
    const { session } = app;
    const lens = session.currentLens();
    if (lens === "intimate") {
      prepareIntimateZoom(session.intimateHourPixels * 1.2 ** (-steps));
    } else if (lens === "tactical") {
      session.tacticalRows = Math.max(1, Math.min(8, session.tacticalRows + steps));
    } else if (lens === "strategic") {
      session.strategicMonths = Math.max(1, Math.min(18, session.strategicMonths + steps));
    } else if (lens === "wall") {
      session.wallMonths = Math.max(1, Math.min(12, session.wallMonths + steps));
    } else if (lens === "lines") {
      session.linesMonths = Math.max(1, Math.min(18, session.linesMonths + steps));
    } else {
      session.radialFuture = Math.max(0, Math.min(12, session.radialFuture + steps));
    }
  }

  function panFromWheel(event) {
    const { session } = app;
    if (session.currentLens() === "intimate" && !event.ctrlKey && !event.metaKey) {
      // Vertical wheel is the rail's own scrolling and stays native. Horizontal
      // wheel spends the rail's slack natively too, and becomes window movement
      // only once the rail is pinned at an edge — so a narrow window scrolls its
      // columns, and a wide window, which has no horizontal slack at all because
      // the columns are `1fr`, moves time instead of doing nothing.
      const horizontal = wheelHorizontalDelta(event);
      if (!horizontal) return;
      const scroll = intimateScroll();
      const slack = scroll
        ? scrollSlack(scroll.scrollLeft, scroll.scrollWidth - scroll.clientWidth, horizontal)
        : 0;
      if (slack > 0.5) return;
      event.preventDefault();
      const step = intimateWheelStep({ carried: intimateWheelCarry, delta: horizontal });
      intimateWheelCarry = step.carried;
      if (!step.dayShift) return;
      session.move(step.dayShift);
      app.scheduleRender();
      return;
    }
    event.preventDefault();
    if (event.ctrlKey || event.metaKey) {
      if (session.currentLens() === "intimate") {
        const scroll = intimateScroll();
        const offset = scroll
          ? Math.max(0, Math.min(scroll.clientHeight, event.clientY - scroll.getBoundingClientRect().top))
          : null;
        prepareIntimateZoom(session.intimateHourPixels * Math.exp(-event.deltaY * 0.002), offset);
        app.scheduleRender();
        return;
      }
      zoomWheel += event.deltaY;
      const steps = Math.trunc(zoomWheel / 90);
      if (!steps) return;
      zoomWheel -= steps * 90;
      adjustWindow(steps);
    } else {
      panWheel += Math.abs(event.deltaY) >= Math.abs(event.deltaX) ? event.deltaY : event.deltaX;
      const steps = Math.trunc(panWheel / 90);
      if (!steps) return;
      panWheel -= steps * 90;
      if (session.projection === "radial") {
        animateRadialWheel(session.radialCycle.mul(steps));
        return;
      } else if (session.currentLens() === "intimate") {
        session.move(steps);
      } else if (session.currentLens() === "tactical") {
        session.move(event.shiftKey ? steps : steps * session.tacticalColumns);
      } else {
        const rate = session.visibleSpan() / 18;
        session.move(Rational.parse(String(steps * rate)));
      }
    }
    app.scheduleRender();
  }

  // Keep the browser's scroll position continuous when the finite Intimate rail
  // is recentered.  This has to happen in the same scroll task: deferring the
  // replacement to another animation frame lets the user see the rail pause at
  // its seam (usually near a midnight marker).
  function rebaseIntimateScroll(scroll, direction) {
    const hourPixels = Number(scroll.dataset.hourPixels || 56);
    // `dataset.hoursPerDay` lives on this same element (it already carries
    // `hourPixels`) when the projection has one to offer; absent that, the
    // governing law is the fallback -- never the bare civil 24.
    const hoursPerDay = Number(scroll.dataset.hoursPerDay) || frameHoursPerDay();
    const dayPixels = hourPixels * hoursPerDay;
    app.pendingIntimateRebase = {
      top: Math.max(0, scroll.scrollTop - direction * dayPixels),
      left: scroll.scrollLeft
    };
    app.session.move(direction);
    app.render();
  }

  let eventDrag = null;
  let dropTarget = null;
  let dragPreview = null;
  let dragPreviewFrame = 0;
  let queuedDragPreview = null;
  let suppressEventClick = false;

  function cellAtPoint(x, y) {
    return document.elementFromPoint(x, y)?.closest?.("[data-create-day],[data-drop-start]") || null;
  }

  function clearEventDrag() {
    if (dragPreviewFrame) cancelAnimationFrame(dragPreviewFrame);
    dragPreviewFrame = 0;
    queuedDragPreview = null;
    eventDrag?.item.classList.remove("drag-source");
    dropTarget?.classList.remove("drop-target");
    dragPreview?.remove();
    document.body.classList.remove("event-dragging");
    eventDrag = null;
    dropTarget = null;
    dragPreview = null;
  }

  function queueDragPreview(event, cell) {
    queuedDragPreview = { clientX: event.clientX, clientY: event.clientY, cell };
    if (dragPreviewFrame) return;
    dragPreviewFrame = requestAnimationFrame(() => {
      dragPreviewFrame = 0;
      const queued = queuedDragPreview;
      queuedDragPreview = null;
      if (queued) updateDragPreview(queued, queued.cell);
    });
  }

  function updateDragPreview(event, cell) {
    if (!eventDrag?.active) return;
    if (!dragPreview) {
      dragPreview = document.createElement("div");
      dragPreview.className = "drag-preview";
      document.body.append(dragPreview);
    }
    dragPreview.style.left = `${Math.min(innerWidth - 250, event.clientX + 16)}px`;
    dragPreview.style.top = `${Math.min(innerHeight - 80, event.clientY + 16)}px`;
    const title = eventDrag.title || "Event";
    if (!cell) {
      if (dragPreview.parentElement !== document.body) document.body.append(dragPreview);
      dragPreview.classList.remove("cell-preview");
      dragPreview.style.height = "auto";
      dragPreview.textContent = `${title}\nRelease over a time cell to move`;
      dragPreview.dataset.valid = "false";
      return;
    }
    const destination = destinationForDrop(cell, event.clientX, event.clientY, eventDrag.sourceDay);
    if (!(cell instanceof SVGElement)) {
      if (dragPreview.parentElement !== cell) cell.append(dragPreview);
      dragPreview.classList.add("cell-preview");
      dragPreview.style.left = "4px";
      dragPreview.style.right = "4px";
      if (cell.classList.contains("intimate-day-column")) {
        const timelineStart = Rational.parse(cell.dataset.timelineStart || cell.dataset.createDay);
        const perDayHours = frameHoursPerDay();
        const timelineDays = Number(cell.dataset.timelineHours || perDayHours) / perDayHours;
        dragPreview.style.top = `${destination.sub(timelineStart).toNumber() / timelineDays * 100}%`;
        dragPreview.style.height = `${Math.max(.75, eventDrag.durationDays / timelineDays * 100)}%`;
      } else {
        dragPreview.style.top = "28px";
        dragPreview.style.height = "auto";
      }
    } else {
      if (dragPreview.parentElement !== document.body) document.body.append(dragPreview);
      dragPreview.classList.remove("cell-preview");
    }
    // `destination` is a universal day ordinal; the preview reads it through
    // the same display law (`session.law`) the geometry above was laid out
    // under, not the standard boundary.
    dragPreview.textContent = `${title}\nâ†’ ${formatCivil(app.session.law.fromDays(destination), true)}`;
    dragPreview.dataset.valid = "true";
  }

  function destinationForDrop(cell, clientX, clientY, sourceDay) {
    const { session } = app;
    if (cell.dataset.timelineStart) {
      const start = Rational.parse(cell.dataset.timelineStart);
      const bounds = cell.getBoundingClientRect();
      const minutesPerHour = session.law.minutesPerHour().toNumber();
      const totalMinutes = Number(cell.dataset.timelineHours || frameHoursPerDay()) * minutesPerHour;
      const fraction = Math.max(0, Math.min(0.999999, (clientY - bounds.top) / bounds.height));
      const minute = Math.round(fraction * totalMinutes / session.intimateGrain) * session.intimateGrain;
      return start.add(Rational.parse(Math.min(totalMinutes - session.intimateGrain, minute)).div(session.minutesPerDay()));
    }
    if (cell.dataset.dropStart) {
      const start = Rational.parse(cell.dataset.dropStart);
      const end = Rational.parse(cell.dataset.dropEnd);
      const bounds = cell.getBoundingClientRect();
      if (cell.dataset.dropKind === "linear") {
        const fraction = Math.max(0, Math.min(1, (clientX - bounds.left) / bounds.width));
        return start.add(end.sub(start).mul(String(fraction)));
      }
      let localX = (clientX - bounds.left) / bounds.width * 900;
      let localY = (clientY - bounds.top) / bounds.height * 720;
      if (cell.createSVGPoint && cell.getScreenCTM()) {
        const point = cell.createSVGPoint();
        point.x = clientX;
        point.y = clientY;
        const local = point.matrixTransform(cell.getScreenCTM().inverse());
        localX = local.x;
        localY = local.y;
      }
      let angle = Math.atan2(localY - 360, localX - 450) + Math.PI / 2;
      angle = ((angle % (Math.PI * 2)) + Math.PI * 2) % (Math.PI * 2);
      const angleTurn = angle / (Math.PI * 2);
      let progress = angleTurn;
      if (cell.dataset.radialMode === "spiral") {
        const turns = Number(cell.dataset.radialTurns);
        const radius = Math.hypot(localX - 450, localY - 360);
        const estimatedTurn = (radius - Number(cell.dataset.radialInner)) / Number(cell.dataset.radialSpacing);
        const turn = Math.round(estimatedTurn - angleTurn) + angleTurn;
        progress = Math.max(0, Math.min(1, turn / turns));
      }
      return start.add(end.sub(start).mul(String(progress)));
    }
    const base = Rational.parse(cell.dataset.createDay);
    if (cell.classList.contains("intimate-day-column")) {
      const bounds = cell.getBoundingClientRect();
      const fraction = Math.max(0, Math.min(0.999999, (clientY - bounds.top) / bounds.height));
      const timelineStart = Rational.parse(cell.dataset.timelineStart || base);
      const timelineMinutes = Number(cell.dataset.timelineHours || frameHoursPerDay()) * session.law.minutesPerHour().toNumber();
      const minute = Math.min(
        timelineMinutes - session.intimateGrain,
        Math.max(0, Math.round(fraction * timelineMinutes / session.intimateGrain) * session.intimateGrain)
      );
      return timelineStart.add(Rational.parse(minute).div(session.minutesPerDay()));
    }
    const source = Rational.parse(sourceDay);
    return base.add(source.sub(source.floor()));
  }

  let createDrag = null;
  let createPreview = null;

  function clearCreateDragPreview() {
    createPreview?.remove();
    createPreview = null;
    for (const cell of createDrag?.rangeCells || []) cell.classList.remove("create-range");
    document.body.classList.remove("calendar-panning");
  }

  projection.addEventListener("wheel", panFromWheel, { passive: false });

  projection.addEventListener("scroll", (event) => {
    const scroll = event.target;
    if (!(scroll instanceof HTMLElement)
      || !scroll.classList.contains("intimate-scroll")
      || app.intimateScrollGuard
      || app.pendingIntimateRebase
      || app.pendingIntimateZoom) return;
    const hourPixels = Number(scroll.dataset.hourPixels || 56);
    const edge = hourPixels * 6;
    if (scroll.scrollTop < edge) {
      rebaseIntimateScroll(scroll, -1);
    } else if (scroll.scrollTop + scroll.clientHeight > scroll.scrollHeight - edge) {
      rebaseIntimateScroll(scroll, 1);
    }
  }, true);

  projection.addEventListener("pointerdown", (event) => {
    if (event.shiftKey) return;
    const item = event.target.closest("[data-event-id]");
    if (!item || (!item.dataset.relationId && !item.dataset.virtualId)) return;
    eventDrag = {
      item,
      relationId: item.dataset.relationId,
      virtualId: item.dataset.virtualId,
      sourceDay: item.dataset.factDay,
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      title: item.textContent.trim() || item.getAttribute("aria-label") || "Event",
      durationDays: durationMagnitudeDays(app.chronolog.events[item.dataset.eventId]?.magnitudes?.duration, app.chronolog).toNumber(),
      active: false
    };
  });

  projection.addEventListener("pointermove", (event) => {
    if (!eventDrag || eventDrag.pointerId !== event.pointerId) return;
    if (!eventDrag.active && Math.hypot(
      event.clientX - eventDrag.startX,
      event.clientY - eventDrag.startY
    ) < 6) return;
    if (!eventDrag.active) {
      eventDrag.active = true;
      eventDrag.item.classList.add("drag-source");
      document.body.classList.add("event-dragging");
      projection.setPointerCapture?.(event.pointerId);
    }
    event.preventDefault();
    const nextTarget = cellAtPoint(event.clientX, event.clientY);
    if (nextTarget !== dropTarget) {
      dropTarget?.classList.remove("drop-target");
      dropTarget = nextTarget;
      dropTarget?.classList.add("drop-target");
    }
    queueDragPreview(event, nextTarget);
  });

  projection.addEventListener("pointerup", (event) => {
    if (!eventDrag || eventDrag.pointerId !== event.pointerId) return;
    const { chronolog, engine, session, history } = app;
    const drag = eventDrag;
    const cell = dropTarget || cellAtPoint(event.clientX, event.clientY);
    const wasActive = drag.active;
    clearEventDrag();
    if (!wasActive) return;
    suppressEventClick = true;
    setTimeout(() => { suppressEventClick = false; }, 0);
    event.preventDefault();
    if (!cell) return;
    const destination = destinationForDrop(cell, event.clientX, event.clientY, drag.sourceDay);
    const timedDrop = cell.classList.contains("intimate-day-column");
    if (drag.virtualId) {
      const fact = app.findVisibleFact(drag.virtualId, drag.sourceDay);
      if (!fact) {
        app.toast("That recurring occurrence could not be resolved for moving.", true);
        return;
      }
      // The materialized relation inherits `fact.relation.frame` unchanged
      // (`prepareMaterialization` clones it), so the new coordinate is built
      // under THAT frame's own law, not the standard boundary -- a companion
      // frame's coordinate is never reinterpreted under a different law.
      const nextCoordinate = coordinateLaw(chronolog, fact.relation.frame).fromDays(destination);
      const prepared = app.prepareMaterialization(fact, nextCoordinate);
      if (timedDrop) {
        prepared.relation.parameters ||= {};
        prepared.relation.parameters.dateOnly = false;
      }
      history.executeDelta(
        "Move recurring occurrence",
        (documentValue) => app.applyMaterialization(documentValue, prepared),
        (documentValue) => app.revertMaterialization(documentValue, prepared),
        { preserveRecurrence: true, ...app.materializationOps(prepared) }
      );
      return;
    }
    if (!chronolog.relations[drag.relationId]) return;
    const draggedEventId = drag.item.dataset.eventId;
    const draggedEvent = chronolog.events[draggedEventId];
    const originalCoordinate = draggedEvent?.provenance?.originalCoordinate;
    if (draggedEvent?.provenance?.replaces && originalCoordinate) {
      const originalDay = engine.coordinateDays(chronolog.relations[drag.relationId].frame, originalCoordinate);
      const snapTolerance = Rational.parse(session.intimateGrain).div(2880);
      if (originalDay.sub(destination).abs().compare(snapTolerance) <= 0) {
        app.executeEventChange("Restore recurring occurrence", draggedEventId, (documentValue) => {
          delete documentValue.events[draggedEventId];
          for (const [id, relation] of Object.entries(documentValue.relations)) {
            if (relation.event === draggedEventId) delete documentValue.relations[id];
          }
          for (const [id, override] of Object.entries(documentValue.overrides)) {
            if (override.replacements?.includes(draggedEventId)) delete documentValue.overrides[id];
          }
        }, { preserveRecurrence: true });
        return;
      }
    }
    // The moved relation keeps its own frame -- a companion frame's coordinate
    // is never reinterpreted under the primary's law (AGENTS.md's frame model)
    // -- so the new coordinate is built under THAT frame's own law.
    const nextCoordinate = coordinateLaw(chronolog, chronolog.relations[drag.relationId].frame).fromDays(destination);
    const previousCoordinate = clone(chronolog.relations[drag.relationId].coordinate);
    const previousParameters = clone(chronolog.relations[drag.relationId].parameters);
    const previousRelation = clone(chronolog.relations[drag.relationId]);
    const metadata = { preserveRecurrence: true };
    history.executeDelta("Move event", (documentValue) => {
      const relation = documentValue.relations[drag.relationId];
      if (!relation) throw new Error("The event placement no longer exists");
      relation.coordinate = clone(nextCoordinate);
      if (timedDrop) {
        relation.parameters ||= {};
        relation.parameters.dateOnly = false;
      }
      Object.assign(metadata, {
        ops: [putOp("relations", drag.relationId, relation)],
        inverseOps: [putOp("relations", drag.relationId, previousRelation)]
      });
    }, (documentValue) => {
      const relation = documentValue.relations[drag.relationId];
      if (!relation) return;
      relation.coordinate = clone(previousCoordinate);
      if (previousParameters === undefined) delete relation.parameters;
      else relation.parameters = clone(previousParameters);
    }, metadata);
  });

  projection.addEventListener("pointercancel", () => clearEventDrag());

  projection.addEventListener("pointerdown", (event) => {
    const { session } = app;
    if (!event.shiftKey && event.target.closest("[data-event-id],button")) return;
    const cell = event.target.closest("[data-create-day],[data-drop-start]");
    const pan = event.shiftKey || intimatePanSurface(event.target);
    if (!cell && !pan) return;
    const scroll = intimateScroll();
    createDrag = {
      pointerId: event.pointerId,
      start: cell
        ? destinationForDrop(cell, event.clientX, event.clientY, cell.dataset.createDay)
        : session.currentFocus(),
      startX: event.clientX,
      startY: event.clientY,
      startFocus: session.currentFocus(),
      startScrollTop: scroll?.scrollTop || 0,
      startScrollLeft: scroll?.scrollLeft || 0,
      pan,
      appliedDays: 0,
      active: false,
      rangeCells: [...projection.querySelectorAll("[data-create-day]")]
    };
    event.preventDefault();
    if (createDrag.pan) document.body.classList.add("calendar-panning");
    projection.setPointerCapture?.(event.pointerId);
  });

  projection.addEventListener("pointermove", (event) => {
    if (!createDrag || createDrag.pointerId !== event.pointerId) return;
    const { session } = app;
    const dx = event.clientX - createDrag.startX;
    const dy = event.clientY - createDrag.startY;
    if (!createDrag.active && Math.hypot(dx, dy) < 5) return;
    createDrag.active = true;
    event.preventDefault();
    if (createDrag.pan) {
      if (session.currentLens() === "intimate") {
        const scroll = intimateScroll();
        if (scroll) {
          // Both axes come out of the same gesture, never chosen against each
          // other: the drag is free. Horizontal motion the rail cannot absorb
          // becomes whole-day window movement, which is the only thing that
          // works on a window wide enough to have no horizontal slack.
          const step = intimatePanStep({
            startScrollLeft: createDrag.startScrollLeft,
            startScrollTop: createDrag.startScrollTop,
            dx,
            dy,
            maxScrollLeft: scroll.scrollWidth - scroll.clientWidth,
            maxScrollTop: scroll.scrollHeight - scroll.clientHeight,
            columnPixels: intimateColumnPixels(),
            appliedDays: createDrag.appliedDays
          });
          scroll.scrollTop = step.scrollTop;
          scroll.scrollLeft = step.scrollLeft;
          if (step.dayDelta) {
            createDrag.appliedDays = step.dayShift;
            // The window step reflows the day columns. Pin the rail's scroll
            // through that reflow so the hours under the pointer hold still —
            // and deliberately do not shift `top` by a day the way the vertical
            // midnight rebase does: paging sideways should show the same hours
            // of a different day, not the same instant.
            app.pendingIntimateRebase = { top: step.scrollTop, left: step.scrollLeft };
            session.move(step.dayDelta);
            app.scheduleRender();
          }
        }
        return;
      }
      const bounds = projection.getBoundingClientRect();
      const gesture = Math.abs(dx) >= Math.abs(dy) ? dx / Math.max(1, bounds.width) : -dy / Math.max(1, bounds.height);
      session.setFocus(createDrag.startFocus.sub(Rational.parse(String(gesture * session.visibleSpan()))));
      app.scheduleRender();
      return;
    }
    const cell = document.elementFromPoint(event.clientX, event.clientY)?.closest?.("[data-create-day]");
    if (!cell) return;
    const end = destinationForDrop(cell, event.clientX, event.clientY, createDrag.start.toJSON());
    if (!createPreview) {
      createPreview = document.createElement("div");
      createPreview.className = "drag-preview";
      document.body.append(createPreview);
    }
    const perDayHours = frameHoursPerDay();
    const duration = end.sub(createDrag.start).abs().mul(session.hoursPerDay()).toNumber();
    createPreview.style.left = `${Math.min(innerWidth - 260, event.clientX + 16)}px`;
    createPreview.style.top = `${Math.min(innerHeight - 80, event.clientY + 16)}px`;
    if (!(cell instanceof SVGElement)) {
      if (createPreview.parentElement !== cell) cell.append(createPreview);
      createPreview.classList.add("cell-preview");
      createPreview.style.left = "4px";
      createPreview.style.right = "4px";
      createPreview.style.top = cell.classList.contains("intimate-day-column")
        ? `${(createDrag.start.compare(end) <= 0 ? createDrag.start : end).sub(Rational.parse(cell.dataset.timelineStart || cell.dataset.createDay)).toNumber() / (Number(cell.dataset.timelineHours || perDayHours) / perDayHours) * 100}%`
        : "28px";
      createPreview.style.height = cell.classList.contains("intimate-day-column")
        ? `${Math.max(.75, Math.min(100, duration / Number(cell.dataset.timelineHours || perDayHours) * 100))}%`
        : "auto";
    }
    const firstDay = createDrag.start.floor() < end.floor() ? createDrag.start.floor() : end.floor();
    const lastDay = createDrag.start.floor() > end.floor() ? createDrag.start.floor() : end.floor();
    for (const rangeCell of createDrag.rangeCells) {
      const day = BigInt(rangeCell.dataset.createDay);
      rangeCell.classList.toggle("create-range", day >= firstDay && day <= lastDay);
    }
    createPreview.textContent = `New event\n${formatCivil(app.session.law.fromDays(createDrag.start), true)} · ${duration < 1 ? `${Math.round(duration * 60)} min` : `${duration.toFixed(1)} hr`}`;
  });

  projection.addEventListener("pointerup", (event) => {
    if (!createDrag || createDrag.pointerId !== event.pointerId) return;
    const drag = createDrag;
    clearCreateDragPreview();
    createDrag = null;
    if (drag.pan) {
      const scroll = projection.querySelector(".intimate-scroll");
      if (scroll) app.viewScroll.set("intimate", { top: scroll.scrollTop, left: scroll.scrollLeft });
      panWheel = 0;
      return;
    }
    const cell = document.elementFromPoint(event.clientX, event.clientY)?.closest?.("[data-create-day]")
      || event.target.closest?.("[data-create-day]");
    if (!cell) return;
    let end = destinationForDrop(cell, event.clientX, event.clientY, drag.start.toJSON());
    if (!cell.classList.contains("intimate-day-column")) end = new Rational(end.floor() + 1n);
    suppressEventClick = drag.active;
    app.createEventAt(drag.start, end);
  });

  projection.addEventListener("pointercancel", () => {
    clearCreateDragPreview();
    createDrag = null;
    panWheel = 0;
  });

  // Single click selects; double click opens the editor card.
  //
  // The split exists because opening a card is no longer a cheap, reversible
  // glance — it takes a real grid track away from the stage, and with plural cards
  // a stray click while scanning a busy week would pile up editors nobody asked
  // for. So a single click is the glance: it selects the object, which highlights
  // it and gives the keyboard something to act on, and changes nothing else.
  // Nothing is created, opened, or paged.
  projection.addEventListener("click", (event) => {
    if (suppressEventClick) {
      suppressEventClick = false;
      event.preventDefault();
      return;
    }
    const item = event.target.closest("[data-event-id]");
    if (!item) return;
    event.stopPropagation();
    selectStageObject(item);
  });

  projection.addEventListener("dblclick", (event) => {
    const item = event.target.closest("[data-event-id]");
    if (!item) return;
    event.stopPropagation();
    event.preventDefault();
    // A double click implies its own single click, so the object is already
    // selected by the time this runs — the two agree rather than compete.
    // The exact day this fact was rendered at (stamped by bindFact) is the
    // resolution window -- see openVirtualInspector's comment: this is what
    // makes a clicked occurrence resolve regardless of which lens or render
    // buffer put it on screen.
    if (item.dataset.virtualId) app.openVirtualInspector(item.dataset.virtualId, item.dataset.factDay);
    else app.openEventInspector(item.dataset.eventId);
  });

  function selectStageObject(item) {
    const { session } = app;
    const next = {
      type: "event",
      id: item.dataset.eventId,
      virtualId: item.dataset.virtualId || null,
      day: item.dataset.factDay || null
    };
    // Clicking the selected object again clears the selection, so a click is
    // always its own undo and never leaves the stage in a state the user cannot
    // get out of without opening something.
    const current = session.selection;
    const same = current?.id === next.id && (current?.virtualId || null) === next.virtualId;
    session.selection = same ? null : next;
    app.scheduleRender();
  }

  minimap.addEventListener("pointerdown", (event) => {
    const { session } = app;
    if (radialWheelAnimation?.frame) cancelAnimationFrame(radialWheelAnimation.frame);
    radialWheelAnimation = null;
    document.body.classList.remove("radial-wheel-motion");
    const svg = minimap.querySelector("svg");
    if (!svg) return;
    const bounds = minimap.getBoundingClientRect();
    session.minimapDrag = minimapDragState({
      start: svg.dataset.minimapStart,
      end: svg.dataset.minimapEnd,
      focus: session.currentFocus(),
      visibleSpan: session.visibleSpan(),
      fraction: (event.clientX - bounds.left) / bounds.width
    });
    session.setFocus(session.minimapDrag.focus);
    minimap.setPointerCapture?.(event.pointerId);
    app.scheduleRender();
  });

  minimap.addEventListener("pointermove", (event) => {
    const { session } = app;
    if (!session.minimapDrag || !minimap.hasPointerCapture?.(event.pointerId)) return;
    const bounds = minimap.getBoundingClientRect();
    const fraction = (event.clientX - bounds.left) / bounds.width;
    session.setFocus(minimapDragFocus(session.minimapDrag, fraction));
    app.scheduleRender();
  });

  minimap.addEventListener("pointerup", () => {
    const { session } = app;
    if (!session.minimapDrag) return;
    session.minimapDrag = null;
    app.scheduleRender();
  });

  minimap.addEventListener("pointercancel", () => {
    const { session } = app;
    if (!session.minimapDrag) return;
    session.minimapDrag = null;
    app.scheduleRender();
  });

  return { adjustWindow };
}
