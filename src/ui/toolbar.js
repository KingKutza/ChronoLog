import {
  Rational,
  civilFromDays,
  daysFromCivil,
  daysInMonth
} from "../exact.js";
import { calendarFrames } from "../projections.js";
import { FIXED_RADIAL_CYCLES, cyclePeriodHint, normalizeRadialGuideValues, radialGuideSettings, resolveRadialCycle } from "../radial.js";
import { DEFAULT_LENS_ORDER, LENS_CATALOG } from "../session.js";
import { parseDocument } from "../store.js";
import { THEME_FIELDS, THEME_PRESETS, normalizeTheme } from "../visual-language.js";
import { byId, escapeHTML } from "./dom-helpers.js";

const THEME_STORAGE_KEY = "chronolog:color-theme:1";

export function storedTheme() {
  try { return JSON.parse(localStorage.getItem(THEME_STORAGE_KEY) || "{}"); } catch { return {}; }
}

export function applyTheme(theme) {
  const palette = normalizeTheme(theme);
  for (const name of Object.keys(THEME_FIELDS)) {
    document.documentElement.style.setProperty(`--${name}`, palette[name]);
  }
  document.documentElement.dataset.theme = theme?.preset || "custom";
}

// The lens bar, document menu, history controls, create menu, theme editor
// and lens-workspace configuration dialog. `app` carries the live
// document/session/history/store plus the cross-module calls this toolbar
// makes into the inspector (`app.createEventAt`, `app.closeInspector`, ...),
// the Frames panel (`app.selectLeadingFrame`) and the drag/wheel module
// (`app.adjustWindow`).
export function createToolbar(app, dom) {
  const { projection, inspector, inspectorBody, lensControls, LOCAL_WORKSPACE_TARGET } = dom;
  let lensControlsSignature = "";

  function updateCalendarSelect() {
    const { chronolog, session } = app;
    const select = byId("active-calendar");
    const frames = calendarFrames(chronolog);
    const currentOptions = [...select.options].map((option) => option.value).join("|");
    const nextOptions = frames.map((frame) => frame.id).join("|");
    if (currentOptions !== nextOptions) {
      select.replaceChildren();
      for (const frame of frames) {
        const option = document.createElement("option");
        option.value = frame.id;
        option.textContent = frame.title;
        select.append(option);
      }
    } else {
      frames.forEach((frame, index) => {
        if (select.options[index]) select.options[index].textContent = frame.title;
      });
    }
    select.value = session.activeFrame;
  }

  function updateChrome() {
    const { session, history } = app;
    byId("shared-focus").checked = session.sharedFocus;
    byId("undo").disabled = history.undoStack.length === 0;
    byId("redo").disabled = history.redoStack.length === 0;
    const lensBar = byId("lens-bar");
    for (const lens of session.lensOrder) {
      const button = lensBar.querySelector(`[data-lens="${lens}"]`);
      if (button) lensBar.append(button);
    }
    document.querySelectorAll("[data-lens]").forEach((button) => {
      const available = session.enabledLenses.includes(button.dataset.lens);
      button.hidden = !available;
      button.disabled = !available;
      button.classList.toggle("active", button.dataset.lens === session.currentLens());
    });
  }

  // Compaction repairs a document it had to change to make loadable. Say so on
  // the way in — a silent repair is how the condition that caused it stays
  // invisible until the next thing breaks.
  function repairSuffix(repairs) {
    return repairs.length ? ` · ${repairs.map((repair) => repair.message).join(" · ")}` : "";
  }

  function closeDocumentMenu() {
    byId("document-menu").open = false;
  }

  function closeCreateMenu() {
    byId("create-menu").open = false;
  }

  function confirmDocumentReplacement() {
    const { store } = app;
    if (!store.pending) return true;
    return globalThis.confirm("Open a different document? Unsaved changes in the current document are already recoverable through its autosave target, but this session will switch documents.");
  }

  function shiftFocusMonths(offset) {
    const { session } = app;
    const focus = session.currentFocus();
    const civil = civilFromDays(focus.floor());
    const total = civil.year * 12n + civil.month - 1n + BigInt(offset);
    const year = total >= 0n ? total / 12n : (total - 11n) / 12n;
    const month = ((total % 12n) + 12n) % 12n + 1n;
    const day = civil.day > BigInt(daysInMonth(year, month))
      ? BigInt(daysInMonth(year, month))
      : civil.day;
    session.setFocus(new Rational(daysFromCivil(year, month, day)).add(focus.sub(focus.floor())));
  }

  function resetCurrentLensView() {
    const { session } = app;
    const lens = session.currentLens();
    if (!session.resetLensView(lens)) return;
    app.viewScroll.delete(lens);
    if (lens === "intimate") {
      app.pendingIntimateRebase = null;
      app.pendingIntimateZoom = null;
    }
    app.toast(`${LENS_CATALOG[lens].title} view reset to defaults.`);
  }

  function updateLensControls() {
    const { session } = app;
    const lens = session.currentLens();
    const previousLens = lensControls.dataset.lens;
    const optionsWasOpen = previousLens === lens
      && Boolean(lensControls.querySelector(".lens-control-overflow")?.open);
    const cycles = radialCycleOptions();
    const signature = JSON.stringify({
      lens,
      intimateBack: session.intimateBack,
      intimateForward: session.intimateForward,
      intimateGrain: session.intimateGrain,
      intimateHourPixels: session.intimateHourPixels,
      intimateStartHour: session.intimateStartHour,
      intimateEndHour: session.intimateEndHour,
      tacticalRows: session.tacticalRows,
      tacticalColumns: session.tacticalColumns,
      strategicMonths: session.strategicMonths,
      strategicMode: session.strategicMode,
      intimateZoneFill: session.intimateZoneFill,
      tacticalZoneFill: session.tacticalZoneFill,
      strategicZoneFill: session.strategicZoneFill,
      wallZoneFill: session.wallZoneFill,
      wallMonths: session.wallMonths,
      linesMonths: session.linesMonths,
      linesDays: session.linesDays,
      strategicDetail: session.strategicDetail,
      wallDetail: session.wallDetail,
      strategicRecordSlashes: session.strategicRecordSlashes,
      wallRecordSlashes: session.wallRecordSlashes,
      radialMode: session.radialMode,
      radialPast: session.radialPast,
      radialFuture: session.radialFuture,
      radialLabels: session.radialLabels,
      radialDivisions: session.radialDivisions,
      radialMajorEvery: session.radialMajorEvery,
      radialMarks: session.radialMarks,
      activeCycle: session.activeCycle,
      cycles: cycles.map((cycle) => [cycle.id, cycle.title, cycle.days])
    });
    if (signature === lensControlsSignature) return;
    lensControlsSignature = signature;
    lensControls.dataset.lens = lens;
    lensControls.replaceChildren();

    const button = (text, action, title = "") => {
      const node = document.createElement("button");
      node.type = "button";
      node.className = "lens-control";
      node.textContent = text;
      node.title = title;
      node.addEventListener("click", () => {
        action();
        app.scheduleRender();
      });
      return node;
    };
    const number = (labelText, value, min, max, action) => {
      const label = document.createElement("label");
      label.className = "lens-control";
      label.append(document.createTextNode(labelText));
      const input = document.createElement("input");
      input.type = "number";
      input.min = String(min);
      input.max = String(max);
      input.value = String(value);
      input.addEventListener("change", () => {
        const requested = Number(input.value);
        action(Math.max(min, Math.min(max, Math.round(Number.isFinite(requested) ? requested : value))));
        app.scheduleRender();
      });
      label.append(input);
      return label;
    };
    const checkbox = (labelText, value, action) => {
      const label = document.createElement("label");
      label.className = "lens-control";
      const input = document.createElement("input");
      input.type = "checkbox";
      input.checked = value;
      input.addEventListener("change", () => {
        action(input.checked);
        app.scheduleRender();
      });
      label.append(input, document.createTextNode(labelText));
      return label;
    };
    const select = (labelText, options, value, action) => {
      const label = document.createElement("label");
      label.className = "lens-control";
      label.append(document.createTextNode(labelText));
      const input = document.createElement("select");
      for (const [optionValue, optionText] of options) {
        const option = document.createElement("option");
        option.value = optionValue;
        option.textContent = optionText;
        option.selected = optionValue === value;
        input.append(option);
      }
      input.addEventListener("change", () => {
        action(input.value);
        app.scheduleRender();
      });
      label.append(input);
      return label;
    };
    const radialGuideSelect = (labelText, value, maximum, title, action) => {
      const options = [["0", "Auto"]];
      for (let index = 1; index <= maximum; index += 1) options.push([String(index), String(index)]);
      const control = select(labelText, options, String(value), (next) => action(Number(next)));
      control.classList.add("radial-guide-control");
      control.title = title;
      control.querySelector("select").title = title;
      return control;
    };
    const readout = (text) => {
      const node = document.createElement("span");
      node.className = "lens-readout";
      node.textContent = text;
      return node;
    };

    // Three destinations, chosen per control rather than sliced out of one list
    // by index. The old index slicing is why Intimate lost its forward step: the
    // primary set was [1, 2, 3] of a seven-control list, which happens to take
    // "back one day", "zoom out" and the readout, and leaves "day ›" and
    // "week »" reachable only through Options.
    //
    //   navControls — anything that moves the window. These sit at the bar's
    //     right end, in one group with the today and reset targets they mirror.
    //   barControls — a lens's own primary affordance, at the left end.
    //   controls    — everything else, in the Options panel. The window-span
    //     readouts live here now: on the bar they were the one element allowed
    //     to grow, so they spanned it. Blank space in the middle is correct.
    const controls = [];
    const navControls = [];
    const barControls = [];
    const hourLabel = (hour) => hour === 0 || hour === 24 ? "12 AM" : hour === 12 ? "12 PM" : `${hour % 12} ${hour < 12 ? "AM" : "PM"}`;
    const todayControl = button("◎", goToToday, "Center this lens on today");
    todayControl.id = "today";
    todayControl.classList.add("today-target");
    const resetControl = button("↺", resetCurrentLensView, `Reset ${LENS_CATALOG[lens].title} view to defaults`);
    resetControl.id = "reset-view";
    resetControl.setAttribute("aria-label", `Reset ${LENS_CATALOG[lens].title} view to defaults`);
    if (lens === "intimate") {
      const visibleHours = Math.max(1, (projection.clientHeight - 70) / session.intimateHourPixels);
      const zoomOut = button("−", () => app.adjustWindow(1), "Zoom Intimate out (keyboard: −)");
      zoomOut.setAttribute("aria-label", "Zoom Intimate out");
      const zoomIn = button("+", () => app.adjustWindow(-1), "Zoom Intimate in (keyboard: +)");
      zoomIn.setAttribute("aria-label", "Zoom Intimate in");
      todayControl.title = "Center Intimate on today and now";
      todayControl.setAttribute("aria-label", "Center Intimate on today and now");
      navControls.push(
        button("« week", () => session.move(-7), "Back one week"),
        button("‹ day", () => session.move(-1), "Back one day"),
        button("day ›", () => session.move(1), "Forward one day"),
        button("week »", () => session.move(7), "Forward one week")
      );
      barControls.push(zoomOut, zoomIn);
      controls.push(
        readout(`~${visibleHours < 10 ? visibleHours.toFixed(1) : Math.round(visibleHours)} hr screen`),
        number("back", session.intimateBack, 0, 14, (value) => { session.intimateBack = value; }),
        number("forward", session.intimateForward, 0, 14, (value) => { session.intimateForward = value; }),
        select("grain", [["15", "15 min"], ["30", "30 min"], ["60", "1 hour"]], String(session.intimateGrain), (value) => { session.intimateGrain = Number(value); }),
        select("from", Array.from({ length: 24 }, (_, hour) => [String(hour), hourLabel(hour)]), String(session.intimateStartHour), (value) => {
          session.intimateStartHour = Math.min(Number(value), session.intimateEndHour - 1);
        }),
        select("to", Array.from({ length: 24 }, (_, index) => index + 1).map((hour) => [String(hour), hourLabel(hour)]), String(session.intimateEndHour), (value) => {
          session.intimateEndHour = Math.max(Number(value), session.intimateStartHour + 1);
        })
      );
    } else if (lens === "tactical") {
      navControls.push(
        button("‹ row", () => session.move(-session.tacticalColumns), "Back one row of days"),
        button("row ›", () => session.move(session.tacticalColumns), "Forward one row of days")
      );
      controls.push(
        readout(`${session.tacticalRows} × ${session.tacticalColumns} · ${session.tacticalRows * session.tacticalColumns} days`),
        number("rows", session.tacticalRows, 1, 8, (value) => { session.tacticalRows = value; }),
        number("days / row", session.tacticalColumns, 1, 14, (value) => { session.tacticalColumns = value; })
      );
    } else if (lens === "lines") {
      navControls.push(
        button("‹ fortnight", () => session.move(-14), "Back one fortnight"),
        button("fortnight ›", () => session.move(14), "Forward one fortnight")
      );
      controls.push(
        readout(`${session.linesDays} days`),
        number("window", session.linesDays, 3, 90, (value) => { session.linesDays = value; })
      );
    } else if (["strategic", "wall"].includes(lens)) {
      const property = lens === "strategic" ? "strategicMonths" : "wallMonths";
      const maximum = lens === "wall" ? 12 : 18;
      navControls.push(
        button("‹ month", () => shiftFocusMonths(-1), "Back one month"),
        button("month ›", () => shiftFocusMonths(1), "Forward one month")
      );
      controls.push(
        readout(`${session[property]} month${session[property] === 1 ? "" : "s"}`),
        number("window", session[property], 1, maximum, (value) => { session[property] = value; })
      );
      if (lens === "strategic") {
        controls.push(select("show", [
          ["signal", "Signal"],
          ["blocks", "Large blocks"],
          ["all", "All events"]
        ], session.strategicMode, (value) => { session.strategicMode = value; }));
        controls.push(
          checkbox("record slashes", session.strategicRecordSlashes, (value) => { session.strategicRecordSlashes = value; }),
          checkbox("zone fill", session.strategicZoneFill, (value) => { session.strategicZoneFill = value; })
        );
      } else {
        controls.push(
          checkbox("detail", session.wallDetail, (value) => { session.wallDetail = value; }),
          checkbox("record slashes", session.wallRecordSlashes, (value) => { session.wallRecordSlashes = value; }),
          checkbox("zone fill", session.wallZoneFill, (value) => { session.wallZoneFill = value; })
        );
      }
    } else if (["spiral", "radial"].includes(lens)) {
      const cycleDays = session.radialCycle.toNumber();
      const guide = radialGuideSettings(session);
      const divisions = guide.divisions;
      const subdivisionDays = cycleDays / divisions;
      const subdivision = subdivisionDays < 1
        ? `${(subdivisionDays * 24).toFixed(subdivisionDays * 24 < 10 ? 1 : 0)} hr / spoke`
        : `${subdivisionDays.toFixed(subdivisionDays < 10 ? 1 : 0)} days / spoke`;
      navControls.push(
        button("‹ cycle", () => session.move(session.radialCycle.neg()), "Back one cycle"),
        button("cycle ›", () => session.move(session.radialCycle), "Forward one cycle")
      );
      controls.push(
        select("cycle", cycles.map((cycle) => [cycle.id, cycle.title]), session.activeCycle, selectCycle),
        readout(`${divisions} ticks · ${subdivision}`)
      );
      if (lens === "spiral") {
        controls.push(
          number("inward", session.radialPast, 0, 12, (value) => { session.radialPast = value; }),
          number("outward", session.radialFuture, 0, 12, (value) => { session.radialFuture = value; })
        );
      }
      controls.push(
        checkbox("labels", session.radialLabels, (value) => { session.radialLabels = value; }),
        radialGuideSelect(
          "ticks",
          session.radialDivisions,
          64,
          "Auto chooses a cycle-aware number of ticks. Manual tick counts are limited to 64.",
          (value) => {
            const normalized = normalizeRadialGuideValues({ ...session, radialDivisions: value });
            session.radialDivisions = normalized.radialDivisions;
            session.radialMajorEvery = normalized.radialMajorEvery;
          }
        ),
        radialGuideSelect(
          "major marks",
          session.radialMajorEvery,
          guide.divisions,
          session.radialMajorEvery === 0
            ? "Auto chooses a cycle-aware major-mark interval."
            : `Every ${session.radialMajorEvery} tick${session.radialMajorEvery === 1 ? "" : "s"}; values larger than the tick count are adjusted to fit.`,
          (value) => { session.radialMajorEvery = value; }
        ),
        select("marks", [["auto", "Cycle aware"], ["day-night", "Midnight + noon"], ["plain", "Plain"]], session.radialMarks, (value) => { session.radialMarks = value; })
      );
    }
    if (lens === "intimate") controls.push(checkbox("zone fill", session.intimateZoneFill, (value) => { session.intimateZoneFill = value; }));
    if (lens === "tactical") controls.push(checkbox("zone fill", session.tacticalZoneFill, (value) => { session.tacticalZoneFill = value; }));
    const optionControls = controls;
    const options = document.createElement("details");
    options.className = "lens-control-overflow";
    options.open = optionsWasOpen;
    const summary = document.createElement("summary");
    summary.textContent = "Options";
    summary.title = `More ${lens} controls`;
    const optionPanel = document.createElement("div");
    optionPanel.className = "lens-control-overflow-panel";
    optionPanel.append(...optionControls);
    options.append(summary, optionPanel);
    // One right-hand group: window movement, then today, then reset. The group's
    // `margin-left: auto` is the only thing holding the bar's middle open, which
    // is why nothing else on the bar may grow.
    const windowGroup = document.createElement("div");
    windowGroup.className = "lens-control-group";
    windowGroup.setAttribute("role", "group");
    windowGroup.setAttribute("aria-label", `${LENS_CATALOG[lens].title} window`);
    windowGroup.append(...navControls, todayControl, resetControl);
    lensControls.append(...barControls, options, windowGroup);
  }

  function openThemeEditor() {
    const current = getComputedStyle(document.documentElement);
    const form = document.createElement("form");
    form.className = "theme-form";
    form.innerHTML = `<p class="field-note">Theme controls the instrument chrome and semantic states. Frame and event colors remain authored data; sigils retain meaning without color.</p>
    <div class="theme-presets" role="group" aria-label="Theme preset"><button class="instrument-button small" type="button" data-theme-preset="paper">Warm paper</button><button class="instrument-button small" type="button" data-theme-preset="night">Night cockpit</button></div>
    <div class="theme-grid">${Object.entries(THEME_FIELDS).map(([name, label]) => `<label class="field"><span>${label}</span><input type="color" name="${name}" value="${escapeHTML(current.getPropertyValue(`--${name}`).trim())}"></label>`).join("")}</div>
    <div class="inspector-actions"><button class="instrument-button primary" type="submit">Save theme</button><button class="instrument-button" id="reset-theme" type="button">Use default</button></div>`;
    form.addEventListener("submit", (event) => {
      event.preventDefault();
      const data = new FormData(form);
      const theme = { ...Object.fromEntries(Object.keys(THEME_FIELDS).map((name) => [name, String(data.get(name))])), preset: form.dataset.themePreset || "custom" };
      localStorage.setItem(THEME_STORAGE_KEY, JSON.stringify(theme));
      applyTheme(theme);
      app.dismissInspector();
    });
    form.querySelector("#reset-theme").addEventListener("click", () => {
      localStorage.removeItem(THEME_STORAGE_KEY);
      applyTheme({});
      app.dismissInspector();
    });
    for (const button of form.querySelectorAll("[data-theme-preset]")) {
      button.addEventListener("click", () => {
        const preset = THEME_PRESETS[button.dataset.themePreset];
        for (const [name, value] of Object.entries(preset)) form.elements[name].value = value;
        form.dataset.themePreset = button.dataset.themePreset;
        applyTheme({ ...preset, preset: button.dataset.themePreset });
      });
    }
    for (const input of form.querySelectorAll('input[type="color"]')) {
      input.addEventListener("input", () => { form.dataset.themePreset = "custom"; });
    }
    app.openInspector("Color theme", form);
  }

  function openLensWorkspace() {
    const { session } = app;
    let draftOrder = [...session.lensOrder];
    let draftEnabled = new Set(session.enabledLenses);
    const wrapper = document.createElement("form");
    wrapper.className = "event-form";
    const note = document.createElement("p");
    note.className = "field-note";
    note.textContent = "Choose the lenses that belong in this workspace and arrange their toolbar order. Each lens keeps only the controls it declares; this does not delete its settings.";
    const list = document.createElement("div");
    list.className = "frame-group-list";
    const render = () => {
      list.replaceChildren();
      for (const lens of draftOrder) {
        const spec = LENS_CATALOG[lens];
        const row = document.createElement("div");
        row.className = "frame-group-row";
        const enabled = document.createElement("label");
        enabled.className = "check-chip";
        const input = document.createElement("input");
        input.type = "checkbox";
        input.name = "enabled-lens";
        input.value = lens;
        input.checked = draftEnabled.has(lens);
        input.addEventListener("change", () => {
          if (input.checked) draftEnabled.add(lens);
          else draftEnabled.delete(lens);
        });
        enabled.append(input, document.createTextNode(spec.title));
        const capabilities = document.createElement("small");
        capabilities.textContent = spec.capabilities.join(" · ");
        const previous = document.createElement("button");
        previous.type = "button"; previous.className = "instrument-button"; previous.textContent = "↑";
        previous.title = `Move ${spec.title} earlier`;
        previous.addEventListener("click", () => {
          const index = draftOrder.indexOf(lens);
          if (index > 0) [draftOrder[index - 1], draftOrder[index]] = [draftOrder[index], draftOrder[index - 1]];
          render();
        });
        const next = document.createElement("button");
        next.type = "button"; next.className = "instrument-button"; next.textContent = "↓";
        next.title = `Move ${spec.title} later`;
        next.addEventListener("click", () => {
          const index = draftOrder.indexOf(lens);
          if (index >= 0 && index < draftOrder.length - 1) [draftOrder[index + 1], draftOrder[index]] = [draftOrder[index], draftOrder[index + 1]];
          render();
        });
        row.append(enabled, capabilities, previous, next);
        list.append(row);
      }
    };
    render();
    const actions = document.createElement("div");
    actions.className = "inspector-actions";
    const restore = document.createElement("button");
    restore.type = "button"; restore.className = "instrument-button"; restore.textContent = "Restore defaults";
    restore.addEventListener("click", () => { draftOrder = [...DEFAULT_LENS_ORDER]; draftEnabled = new Set(DEFAULT_LENS_ORDER); render(); });
    const save = document.createElement("button");
    save.type = "submit"; save.className = "instrument-button primary"; save.textContent = "Save workspace lenses";
    actions.append(restore, save);
    wrapper.append(note, list, actions);
    wrapper.addEventListener("submit", (event) => {
      event.preventDefault();
      session.configureLenses({ lensOrder: draftOrder, enabledLenses: [...draftEnabled] });
      app.dismissInspector();
      app.scheduleRender();
    });
    app.openInspector("Workspace lenses", wrapper);
  }

  function radialCycleOptions() {
    const { chronolog } = app;
    const documentCycles = Object.values(chronolog.frames)
      .filter((frame) => frame.traits?.includes("cycle"))
      .map((frame) => {
        const period = cyclePeriodHint(frame.period);
        return {
          id: frame.id,
          title: period ? frame.title : `${frame.title} (variable)`,
          ...(period ? { days: period.toJSON() } : {}),
          period: frame.period,
          variable: !period
        };
      });
    return [...FIXED_RADIAL_CYCLES, ...documentCycles];
  }

  function reconcileRadialCycle() {
    const { session } = app;
    const resolved = resolveRadialCycle(radialCycleOptions(), session.activeCycle, session.currentFocus());
    if (!resolved) return null;
    session.activeCycle = resolved.id;
    session.radialResolution = resolved;
    // Never substitute a prior/mean cycle for an unresolved selection.
    if (resolved.period) session.radialCycle = resolved.period;
    return resolved;
  }

  function selectCycle(cycleId) {
    const { session } = app;
    if (!radialCycleOptions().some((cycle) => cycle.id === cycleId)) return;
    session.activeCycle = cycleId;
    const resolved = reconcileRadialCycle();
    if (!resolved?.period) {
      app.toast("This cycle has no resolvable boundaries yet.", true);
      return;
    }
  }

  function goToToday() {
    const { session } = app;
    const now = new Date();
    session.setFocus(new Rational(daysFromCivil(
      BigInt(now.getFullYear()), BigInt(now.getMonth() + 1), BigInt(now.getDate())
    )));
    if (session.currentLens() === "intimate") {
      const scroll = projection.querySelector(".intimate-scroll");
      app.pendingIntimateZoom = {
        localHour: now.getHours() + now.getMinutes() / 60,
        offset: scroll?.clientHeight / 2 || projection.clientHeight / 2,
        left: scroll?.scrollLeft || 0
      };
    }
  }

  document.querySelectorAll("[data-lens]").forEach((button) => {
    button.addEventListener("click", () => {
      app.session.setLens(button.dataset.lens);
      app.scheduleRender();
    }, true);
  });

  byId("active-calendar").addEventListener("change", (event) => {
    app.selectLeadingFrame(event.target.value);
  });

  byId("shared-focus").addEventListener("change", (event) => {
    app.session.toggleShared(event.target.checked);
    app.scheduleRender();
  });

  byId("undo").addEventListener("click", () => app.history.undo());
  byId("redo").addEventListener("click", () => app.history.redo());
  for (const [id, kind] of [["new-event", "event"], ["new-todo", "todo"], ["new-note", "note"]]) {
    byId(id).addEventListener("click", () => {
      closeCreateMenu();
      app.createEventAt(app.session.currentFocus(), app.session.currentFocus(), kind);
    });
  }

  byId("create-menu").addEventListener("toggle", (event) => {
    if (event.currentTarget.open) closeDocumentMenu();
  });
  byId("document-menu").addEventListener("toggle", (event) => {
    if (event.currentTarget.open) closeCreateMenu();
  });

  byId("theme-settings").addEventListener("click", () => {
    closeDocumentMenu();
    openThemeEditor();
  });
  byId("lens-settings").addEventListener("click", () => {
    closeDocumentMenu();
    openLensWorkspace();
  });

  document.addEventListener("pointerdown", (event) => {
    const createMenu = byId("create-menu");
    if (createMenu.open && !createMenu.contains(event.target)) closeCreateMenu();
    if (!app.hasProvisionalDraft() || !inspector.classList.contains("open") || inspector.contains(event.target)) return;
    app.closeInspector();
  });

  byId("open-document").addEventListener("click", async () => {
    if (!confirmDocumentReplacement()) return;
    closeDocumentMenu();
    if (!globalThis.showOpenFilePicker) {
      byId("document-file").click();
      return;
    }
    try {
      const [handle] = await globalThis.showOpenFilePicker({
        multiple: false,
        types: [{
          description: "Chronolog document",
          accept: {
            "application/x-chronolog": [".chronolog"],
            "application/json": [".json"]
          }
        }]
      });
      const file = await handle.getFile();
      const repairs = [];
      app.replaceDocument(parseDocument(await file.text(), repairs), { handle, filename: file.name });
      app.toast(`Opened ${file.name} · autosave attached${repairSuffix(repairs)}`);
    } catch (error) {
      if (error.name !== "AbortError") app.toast(error.message, true);
    }
  });

  byId("document-file").addEventListener("change", async (event) => {
    const file = event.target.files?.[0];
    if (!file) return;
    try {
      if (!confirmDocumentReplacement()) return;
      const repairs = [];
      app.replaceDocument(parseDocument(await file.text(), repairs), LOCAL_WORKSPACE_TARGET);
      // A different document replaces the workspace wholesale: it becomes the
      // new snapshot, and journaling continues from there. This is the one
      // remaining whole-document upload.
      if (LOCAL_WORKSPACE_TARGET.api) await app.store.uploadSnapshot();
      app.toast(`Opened ${file.name} · autosave attached to the local workspace${repairSuffix(repairs)}`);
    } catch (error) {
      app.toast(error.message, true);
    } finally {
      event.target.value = "";
    }
  });

  byId("save-document").addEventListener("click", async () => {
    const { store, chronolog } = app;
    closeDocumentMenu();
    try {
      if (!store.handle && !store.api && LOCAL_WORKSPACE_TARGET.api) {
        // Nothing was attached, so this document has never been journaled.
        // Establish it as the workspace snapshot, then journal from there.
        store.attach(chronolog, LOCAL_WORKSPACE_TARGET);
        await store.uploadSnapshot();
      } else if (store.handle || store.api) await store.save(true);
      else if (globalThis.showSaveFilePicker) await store.chooseFile();
      else store.download("chronolog.chronolog");
    } catch (error) {
      if (error.name !== "AbortError") app.toast(error.message, true);
    }
  });

  byId("save-as-document").addEventListener("click", async () => {
    const { store } = app;
    closeDocumentMenu();
    try {
      if (globalThis.showSaveFilePicker) await store.chooseFile();
      else store.download("chronolog.chronolog");
    } catch (error) {
      if (error.name !== "AbortError") app.toast(error.message, true);
    }
  });

  // The download-a-copy / reload-latest pair is gone with the whole-document
  // compare-and-swap that made it necessary. Concurrent edits now collide per
  // record and merge in place, so there is no keep-both decision to put to the
  // owner.

  window.addEventListener("keydown", (event) => {
    const { session, history } = app;
    if (event.key === "Escape" && inspector.classList.contains("open")) {
      event.preventDefault();
      app.closeInspector();
      return;
    }
    const editing = /^(INPUT|TEXTAREA|SELECT)$/.test(event.target.tagName);
    if (editing) return;
    if (event.key === "Delete" && session.inspector?.type === "event") {
      const deleteButton = inspectorBody.querySelector("#delete-object");
      if (deleteButton) {
        event.preventDefault();
        deleteButton.click();
      }
      return;
    }
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "z") {
      event.preventDefault();
      if (event.shiftKey) history.redo();
      else history.undo();
      return;
    }
    if (event.key === "ArrowLeft") session.move(Rational.parse(-session.visibleSpan() / 8));
    else if (event.key === "ArrowRight") session.move(Rational.parse(session.visibleSpan() / 8));
    else if (event.key === "+" || event.key === "=") app.adjustWindow(-1);
    else if (event.key === "-") app.adjustWindow(1);
    else if (event.key.toLowerCase() === "n") {
      app.createEventAt(session.currentFocus());
      return;
    } else if (/^[1-7]$/.test(event.key)) {
      session.setLens(["intimate", "tactical", "strategic", "wall", "lines", "spiral", "radial"][Number(event.key) - 1]);
    } else return;
    event.preventDefault();
    app.scheduleRender();
  });

  window.addEventListener("beforeunload", (event) => {
    const { store } = app;
    if (store.pending) {
      event.preventDefault();
      event.returnValue = "";
    }
  });

  return { updateCalendarSelect, updateChrome, updateLensControls, closeDocumentMenu, reconcileRadialCycle, selectCycle };
}
