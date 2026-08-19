import {
  Rational,
  civilFromDays,
  daysFromCivil,
  daysInMonth
} from "../exact.js";
import { calendarFrames } from "../projections.js";
import { FIXED_RADIAL_CYCLES, cyclePeriodHint, normalizeRadialGuideValues, radialGuideSettings, resolveRadialCycle } from "../radial.js";
import { DEFAULT_LENS_ORDER, LENS_CATALOG } from "../session.js";
import { createDropdownRegistry, exclusiveOpenSet, outsideInteractionCloses, panelPlacement, wrapFocusIndex } from "../panel-flip.js";
import { parseDocument } from "../store.js";
import { THEME_FIELDS, THEME_PRESETS, normalizeTheme } from "../visual-language.js";
import { byId, escapeHTML } from "./dom-helpers.js";

const THEME_STORAGE_KEY = "chronolog:color-theme:1";
const NAMED_THEME_STORAGE_KEY = "chronolog:color-themes:1";

export function storedTheme() {
  try { return JSON.parse(localStorage.getItem(THEME_STORAGE_KEY) || "{}"); } catch { return {}; }
}

// Named user themes are distinct from THEME_PRESETS (visual-language.js's two
// built-in presets) and from the single "currently applied" theme above — a
// map of name -> 8-field palette the user can grow, reload, and overwrite by
// name. Kept here (not in visual-language.js, owned elsewhere this wave) and
// as plain data-in/data-out functions so the storage shape is testable
// without a DOM: only storedNamedThemes()/writeNamedThemes() touch
// localStorage at all.
export function storedNamedThemes() {
  try {
    const raw = JSON.parse(localStorage.getItem(NAMED_THEME_STORAGE_KEY) || "{}");
    return normalizeNamedThemes(raw);
  } catch { return {}; }
}

export function normalizeNamedThemes(raw) {
  const themes = {};
  if (!raw || typeof raw !== "object") return themes;
  for (const [name, palette] of Object.entries(raw)) {
    const trimmed = String(name || "").trim();
    if (!trimmed) continue;
    themes[trimmed] = normalizeTheme(palette);
  }
  return themes;
}

// Saving under a name already present overwrites it; any other name creates
// a new entry — this single rule is the whole "save as new, not only
// override" fix, driven entirely by what the user types in the name field.
export function upsertNamedTheme(themes, name, palette) {
  const trimmed = String(name || "").trim();
  if (!trimmed) return themes;
  return { ...themes, [trimmed]: normalizeTheme(palette) };
}

export function removeNamedTheme(themes, name) {
  const trimmed = String(name || "").trim();
  if (!trimmed || !Object.hasOwn(themes, trimmed)) return themes;
  const next = { ...themes };
  delete next[trimmed];
  return next;
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
  const { projection, lensControls, LOCAL_WORKSPACE_TARGET } = dom;
  let lensControlsSignature = "";

  // One shared mechanism every bar dropdown routes through — see A1 in the
  // 8.19 field report, widened from "edge-flip and z-level" to the full
  // contract the owner's operating principle asks for: placement, z-level,
  // close-on-outside-interaction, Escape, mutual exclusion, keyboard focus,
  // and ARIA. A dropdown enrolls by calling registerBarDropdown once it has
  // built its <details> container and panel; from then on this module owns
  // every one of those as class behaviour, never a per-instance fix:
  //   - edge-flip: placePanel() measures and applies panelPlacement() on open
  //     and on every registered dropdown's resize sweep (placeOpenPanels()).
  //   - z-level: the panel is moved into #dropdown-layer, a plain sibling of
  //     every bar with one shared z-index, while open — the only thing that
  //     escapes a bar's own stacking context (see app.css's #dropdown-layer
  //     comment). It is returned to its original spot in the DOM on close so
  //     a rebuild that walks the live tree (renderHiddenLenses's
  //     dataset.signature check) still finds it.
  //   - outside-interaction close, Escape, mutual exclusion and focus are
  //     wired once below (the toggle listener and the document-level
  //     pointerdown/keydown listeners) and apply to every id the registry
  //     knows about — no dropdown carries its own copy of any of them. The
  //     decidable parts of each rule (which ids close, where focus wraps)
  //     are pure functions in src/panel-flip.js so they are tested without a
  //     DOM at all; this module only measures and applies.
  // The registry (src/panel-flip.js) is what makes this enumerable: adding a
  // future dropdown means calling registerBarDropdown once, nothing more —
  // placeOpenPanels(), the outside/Escape/mutual-exclusion listeners and the
  // audit test all drive off dropdowns.ids()/values().
  const dropdownLayer = byId("dropdown-layer");
  const dropdowns = createDropdownRegistry();

  function returnDropdownHome(entry) {
    const { panel, home, next } = entry;
    if (panel.parentElement !== dropdownLayer) return;
    if (next && next.parentElement === home) home.insertBefore(panel, next);
    else home.append(panel);
  }

  // The interactive elements a keyboard user can land on inside a panel —
  // used both to give an open panel its first focus and to trap Tab inside
  // it (wrapFocusIndex in panel-flip.js does the wrap arithmetic). A panel
  // with none of these still gets its own tabindex="-1" in
  // registerBarDropdown, so focus always has somewhere correct to go even
  // when a panel is momentarily just a note ("No calendar frames yet").
  function focusableElements(panel) {
    return [...panel.querySelectorAll("button, input, select, textarea, a[href]")]
      .filter((node) => !node.disabled && !node.hidden && node.tabIndex !== -1);
  }

  function focusIntoPanel(panel) {
    const [first] = focusableElements(panel);
    (first || panel).focus?.();
  }

  // Registers (or re-registers) one attachment point. Re-registering under an
  // id already in use is the rebuild path — the lens-control Options panel
  // gets a new <details> and panel every time updateLensControls() rebuilds
  // the context bar. If the previous panel for this id was portaled into the
  // shared layer, sweeping it here is what keeps a rebuilt dropdown from
  // leaking an orphaned copy of itself into the layer forever.
  function registerBarDropdown(id, { container, panel, anchor }) {
    const previous = dropdowns.get(id);
    if (previous && previous.panel !== panel && previous.panel.parentElement === dropdownLayer) {
      // The old panel's container is being discarded by this same rebuild
      // (updateLensControls replaces the whole <details> node), so there is
      // no home worth returning it to — only removing it from the layer
      // prevents the leak.
      previous.panel.remove();
    }
    // ARIA correctness is a registration-time property, not something a
    // dropdown opts into: the panel gets a stable id and the anchor points
    // at it with aria-controls (aria-owns would also fit, but aria-controls
    // is the relationship built for exactly this case — the controlled
    // element is not a DOM descendant of the control once portaled) and
    // declares aria-haspopup. aria-expanded is kept live in sync() below,
    // since it tracks state rather than structure.
    panel.id = panel.id || `${id}-panel`;
    panel.setAttribute("tabindex", "-1");
    anchor.setAttribute("aria-haspopup", "true");
    anchor.setAttribute("aria-controls", panel.id);
    const entry = {
      container,
      panel,
      anchor,
      home: panel.parentElement === dropdownLayer ? container : panel.parentElement,
      next: panel.nextSibling
    };
    dropdowns.register(id, entry);
    const sync = () => {
      if (container.open) {
        dropdownLayer.append(panel);
        placePanel(panel, anchor);
      } else {
        returnDropdownHome(entry);
      }
      anchor.setAttribute("aria-expanded", String(Boolean(container.open)));
    };
    entry.sync = sync;
    container.addEventListener("toggle", () => {
      sync();
      if (!container.open) return;
      // Mutual exclusion: a bar behaves like one instrument with a single
      // open dropdown, not independent toggles (exclusiveOpenSet in
      // panel-flip.js is the decidable part). This used to be one hand-paired
      // toggle listener between create-menu and document-menu only; every
      // registrant now gets it, so a third, fourth, fifth dropdown needs no
      // new listener naming its siblings.
      const openIds = dropdowns.ids().filter((otherId) => dropdowns.get(otherId).container.open);
      for (const otherId of exclusiveOpenSet(openIds, id)) closeBarDropdown(otherId);
      // Keyboard reachability: the panel is no longer a DOM descendant of its
      // anchor once portaled, so tab order no longer runs summary -> panel ->
      // next control. Focus starts inside the panel on open instead of
      // waiting on an order that no longer exists; see the document-level
      // keydown listener below for the Tab trap that keeps it there.
      focusIntoPanel(panel);
    });
    // A rebuild can hand this function a container that is already open (the
    // Options panel preserves its open state across a rebuild) — that state
    // change happened before this call, so no "toggle" event will fire for
    // it. Sync once immediately so an open panel is portaled and placed
    // without waiting on one. This bare sync deliberately skips mutual
    // exclusion and focus-into-panel: a rebuild is not a user opening
    // anything, and stealing focus mid-rebuild (e.g. while they are typing in
    // an Options field) would be exactly the kind of surprise this contract
    // exists to prevent.
    sync();
  }

  // Setting `.open` on a <details> from script (rather than a user click on
  // its summary) queues the "toggle" event rather than firing it inline —
  // and a portaled panel's native hide-on-close only works once it is back
  // under its <details>, since `details:not([open]) > *` is what hides it.
  // Every programmatic close in this module goes through here so the panel
  // is actually returned home in the same tick its container closes, instead
  // of floating in the layer for a frame. `returnFocus` is only for Escape
  // (the one place the contract requires focus to move back to the anchor);
  // every other close leaves focus wherever the interaction that caused it
  // already put focus (the item just clicked, the dropdown that is opening
  // in this one's place), which is what a user expects.
  function closeBarDropdown(id, { returnFocus = false } = {}) {
    const entry = dropdowns.get(id);
    if (!entry) return;
    const wasOpen = entry.container.open;
    entry.container.open = false;
    entry.sync();
    if (wasOpen && returnFocus) entry.anchor.focus?.();
  }

  // Static markup dropdowns need zero JS to enroll: a `data-bar-dropdown`
  // attribute on the <details> in pocket-instrument.html is swept once here,
  // and its id becomes the registry id. A brand-new static dropdown is
  // exactly one attribute in the HTML, not an entry hand-added to a list in
  // this file — the explicit array this replaced is the same shape of bug
  // the class exists to close off (#hidden-lenses was once simply absent
  // from a hand-kept list). The panel is whichever child of the <details>
  // is not its <summary>, so no per-dropdown panel class name needs to be
  // named here either. The lens-control Options drop still enrolls itself
  // from updateLensControls(), since it is rebuilt (a new <details> and
  // panel) on every signature change and so cannot live in static markup.
  for (const container of document.querySelectorAll("[data-bar-dropdown]")) {
    const anchor = container.querySelector("summary");
    const panel = [...container.children].find((child) => child !== anchor);
    if (anchor && panel) registerBarDropdown(container.id, { container, panel, anchor });
  }

  // Outside-interaction close, for every registered dropdown at once. The
  // rule (outsideInteractionCloses in panel-flip.js) is: a dropdown that is
  // open and whose container-or-panel did not contain the interaction target
  // closes. Checking the panel as well as the container is what makes this
  // correct for a portaled panel without each dropdown patching itself —
  // the first pass's create-menu-only version of this check
  // (`container.contains(event.target)` plus a hand-added panel check) is
  // gone; create-menu now carries no special-case code of its own.
  document.addEventListener("pointerdown", (event) => {
    const states = dropdowns.ids().map((id) => {
      const entry = dropdowns.get(id);
      return {
        id,
        open: entry.container.open,
        hit: entry.container.contains(event.target) || entry.panel.contains(event.target)
      };
    });
    for (const id of outsideInteractionCloses(states)) closeBarDropdown(id);
  });

  // "Frame", not "Calendar" — the dropdown selects which frame(s) project,
  // and a frame need not be a calendar. Multiple frames can be checked: the
  // first (session.activeFrame) stays the leading frame that supplies
  // primary coordinates, exactly as ROADMAP's frame model requires; the rest
  // are companions. Selecting or checking a frame here never creates a
  // mapping — it only ever writes session state.
  function updateFrameSelect() {
    const { chronolog, session } = app;
    const entry = dropdowns.get("frame-select");
    if (!entry) return;
    const { panel } = entry;
    const summaryValue = byId("frame-select").querySelector(".frame-select-summary-value");
    const frames = calendarFrames(chronolog);
    session.pruneFrameSelection(frames.map((frame) => frame.id));
    const signature = frames.map((frame) => `${frame.id} ${frame.title}`).join("|");
    if (panel.dataset.signature !== signature) {
      panel.dataset.signature = signature;
      panel.replaceChildren();
      for (const frame of frames) {
        const label = document.createElement("label");
        label.className = "check-chip";
        const input = document.createElement("input");
        input.type = "checkbox";
        input.name = "frame-select";
        input.value = frame.id;
        input.addEventListener("change", () => {
          const checked = [...panel.querySelectorAll('input[type="checkbox"]:checked')].map((node) => node.value);
          const previousLeading = session.activeFrame;
          // Never allow a frame drop with nothing selected — the same guard
          // spirit as lens enablement: a control that can select itself into
          // uselessness is a trap, not a feature.
          session.setFrameSelection(checked.length ? checked : [previousLeading]);
          if (session.activeFrame !== previousLeading) app.selectLeadingFrame(session.activeFrame);
          else app.scheduleRender();
        });
        label.append(input, document.createTextNode(frame.title));
        panel.append(label);
      }
      if (!frames.length) {
        const note = document.createElement("p");
        note.className = "field-note";
        note.textContent = "No calendar frames yet.";
        panel.append(note);
      }
    }
    const selected = new Set(session.selectedFrames());
    panel.querySelectorAll('input[type="checkbox"]').forEach((input) => {
      input.checked = selected.has(input.value);
    });
    const leading = frames.find((frame) => frame.id === session.activeFrame);
    const extra = session.companionFrames.length;
    summaryValue.textContent = leading ? `${leading.title}${extra ? ` +${extra}` : ""}` : "No frames";
  }

  function updateChrome() {
    const { session, history } = app;
    byId("shared-focus").checked = session.sharedFocus;
    byId("undo").disabled = history.undoStack.length === 0;
    byId("redo").disabled = history.redoStack.length === 0;
    // The toggle used to just read "Dock side" — no indication of which side
    // is current or what pressing it does. The label now names the live
    // state directly; the title spells out the effect for anyone hovering.
    const dockSide = byId("dock-side");
    const otherSide = session.dockSide === "left" ? "right" : "left";
    dockSide.textContent = `Dock side: ${session.dockSide === "left" ? "Left" : "Right"}`;
    dockSide.title = `Move the dock to the ${otherSide} edge`;
    dockSide.setAttribute("aria-label", dockSide.title);
    const lensBar = byId("lens-bar");
    for (const lens of session.lensOrder) {
      const button = lensBar.querySelector(`[data-lens="${lens}"]`);
      if (button) lensBar.append(button);
    }
    // The ToDo/Notes buttons and the hidden-lens drop always sit after the lenses,
    // whatever order the lenses themselves are in.
    for (const id of ["open-todos", "open-notes", "hidden-lenses"]) {
      const node = byId(id);
      if (node) lensBar.append(node);
    }
    lensBar.querySelectorAll("[data-lens]").forEach((button) => {
      const available = session.enabledLenses.includes(button.dataset.lens);
      button.hidden = !available;
      button.disabled = !available;
      button.classList.toggle("active", button.dataset.lens === session.currentLens());
    });
    renderHiddenLenses();
  }

  // Hidden lenses are not gone, only off the bar: they collect in a drop at its
  // right end so a lens can always be reached without opening a settings surface
  // first. Picking one restores it to the bar and switches to it.
  //
  // It restores rather than making a temporary visit on purpose. `setLens` refuses
  // a lens that is not enabled, and `configureLenses` switches away from a lens it
  // has just disabled — so "visit while staying hidden" would have to fight two
  // invariants that exist for good reason. Restoring is also trivially reversible
  // from the same Configure lenses surface that hid it.
  function renderHiddenLenses() {
    const { session } = app;
    // The panel handle comes from the registry, not `drop.querySelector(...)`
    // — once opened, the panel lives in #dropdown-layer and is no longer a
    // descendant of `drop` at all, so a fresh query would find nothing.
    const entry = dropdowns.get("hidden-lenses");
    if (!entry) return;
    const { container: drop, panel } = entry;
    const hidden = session.lensOrder.filter((lens) => !session.enabledLenses.includes(lens));
    drop.hidden = hidden.length === 0;
    if (!hidden.length) {
      closeBarDropdown("hidden-lenses");
      return;
    }
    const signature = hidden.join("|");
    if (panel.dataset.signature === signature) return;
    panel.dataset.signature = signature;
    panel.replaceChildren();
    for (const lens of hidden) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "instrument-button small";
      button.textContent = LENS_CATALOG[lens].title;
      button.title = `Show ${LENS_CATALOG[lens].title} on the view bar again`;
      button.addEventListener("click", () => {
        closeBarDropdown("hidden-lenses");
        session.configureLenses({ enabledLenses: [...session.enabledLenses, lens] });
        session.setLens(lens);
        app.scheduleRender();
      });
      panel.append(button);
    }
  }

  // Every dropdown panel in the chrome is positioned from measurement rather than
  // pinned to an edge in CSS. Pinning is what sent the lens Options panel off the
  // left of the window once the context bar became the left third: it was fixed
  // `right: 0` against its summary, so it could only ever open leftward. The panel
  // is placed as `fixed` so no ancestor's overflow can clip it either.
  function placePanel(panel, anchor) {
    if (!panel || !anchor) return;
    panel.style.position = "fixed";
    panel.style.left = "0px";
    panel.style.top = "0px";
    panel.style.right = "auto";
    panel.style.bottom = "auto";
    const placement = panelPlacement({
      anchor: anchor.getBoundingClientRect(),
      panel: panel.getBoundingClientRect(),
      viewport: { width: window.innerWidth, height: window.innerHeight }
    });
    panel.style.left = `${placement.left}px`;
    panel.style.top = `${placement.top}px`;
    panel.dataset.placement = placement.placement;
    panel.dataset.align = placement.align;
  }

  // Re-measure on open, and again whenever the window changes shape underneath an
  // open panel. Driven entirely by the registry: every registered dropdown that
  // is currently open gets re-placed, so a future dropdown that calls
  // registerBarDropdown is covered here with no change to this function.
  function placeOpenPanels() {
    for (const entry of dropdowns.values()) {
      if (entry.container.open) placePanel(entry.panel, entry.anchor);
    }
  }

  app.placeOpenPanels = placeOpenPanels;
  window.addEventListener("resize", placeOpenPanels);

  // Compaction repairs a document it had to change to make loadable. Say so on
  // the way in — a silent repair is how the condition that caused it stays
  // invisible until the next thing breaks.
  function repairSuffix(repairs) {
    return repairs.length ? ` · ${repairs.map((repair) => repair.message).join(" · ")}` : "";
  }

  function closeDocumentMenu() {
    closeBarDropdown("document-menu");
  }

  function closeCreateMenu() {
    closeBarDropdown("create-menu");
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
    registerBarDropdown("lens-control-overflow", { container: options, panel: optionPanel, anchor: summary });
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
    let namedThemes = storedNamedThemes();
    const form = document.createElement("form");
    form.className = "theme-form";
    const savedOptions = Object.keys(namedThemes).sort((left, right) => left.localeCompare(right))
      .map((name) => `<option value="${escapeHTML(name)}">${escapeHTML(name)}</option>`).join("");
    form.innerHTML = `<p class="field-note">Theme controls the instrument chrome and semantic states. Frame and event colors remain authored data; sigils retain meaning without color.</p>
    <div class="theme-presets" role="group" aria-label="Theme preset"><button class="instrument-button small" type="button" data-theme-preset="paper">Warm paper</button><button class="instrument-button small" type="button" data-theme-preset="night">Night cockpit</button></div>
    <div class="theme-saved-themes" role="group" aria-label="Saved themes">
      <select id="theme-saved-select" aria-label="Load a saved theme"><option value="">Load a saved theme…</option>${savedOptions}</select>
      <button class="instrument-button small" id="delete-saved-theme" type="button" ${Object.keys(namedThemes).length ? "" : "disabled"}>Delete loaded</button>
    </div>
    <div class="theme-grid">${Object.entries(THEME_FIELDS).map(([name, label]) => `<label class="field"><span>${label}</span><input type="color" name="${name}" value="${escapeHTML(current.getPropertyValue(`--${name}`).trim())}"></label>`).join("")}</div>
    <label class="field"><span>Theme name</span><input name="themeName" placeholder="Name it to save it, e.g. Dusk trail"></label>
    <div class="inspector-actions">
      <button class="instrument-button" id="apply-theme" type="button">Apply</button>
      <button class="instrument-button primary" type="submit">Save theme</button>
      <button class="instrument-button" id="reset-theme" type="button">Use default</button>
    </div>`;
    const currentTheme = () => ({
      ...Object.fromEntries(Object.keys(THEME_FIELDS).map((name) => [name, String(form.elements[name].value)])),
      preset: form.dataset.themePreset || "custom"
    });
    // Apply makes the current edits the live, active theme without closing
    // the dialog or requiring a name — the missing affordance the owner
    // flagged (previously the only way to see a change was Save, which also
    // closed the editor). Saving under a name is the separate, optional step
    // for keeping it reusable.
    form.querySelector("#apply-theme").addEventListener("click", () => {
      const theme = currentTheme();
      localStorage.setItem(THEME_STORAGE_KEY, JSON.stringify(theme));
      applyTheme(theme);
    });
    form.addEventListener("submit", (event) => {
      event.preventDefault();
      const theme = currentTheme();
      localStorage.setItem(THEME_STORAGE_KEY, JSON.stringify(theme));
      applyTheme(theme);
      const name = String(new FormData(form).get("themeName") || "").trim();
      if (name) {
        namedThemes = upsertNamedTheme(namedThemes, name, theme);
        localStorage.setItem(NAMED_THEME_STORAGE_KEY, JSON.stringify(namedThemes));
      }
      app.dismissInspector();
    });
    form.querySelector("#reset-theme").addEventListener("click", () => {
      localStorage.removeItem(THEME_STORAGE_KEY);
      applyTheme({});
      app.dismissInspector();
    });
    form.querySelector("#theme-saved-select").addEventListener("change", (event) => {
      const name = event.target.value;
      const theme = namedThemes[name];
      if (!theme) return;
      for (const field of Object.keys(THEME_FIELDS)) form.elements[field].value = theme[field];
      form.dataset.themePreset = "custom";
      form.elements.themeName.value = name;
      applyTheme(theme);
    });
    form.querySelector("#delete-saved-theme").addEventListener("click", () => {
      const name = form.querySelector("#theme-saved-select").value || form.elements.themeName.value;
      if (!name || !Object.hasOwn(namedThemes, name)) return;
      namedThemes = removeNamedTheme(namedThemes, name);
      localStorage.setItem(NAMED_THEME_STORAGE_KEY, JSON.stringify(namedThemes));
      app.dismissInspector();
      openThemeEditor();
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
    // "Hide" rather than "enable": unchecking a lens takes it off the view bar and
    // into the drop at the bar's right end, where it stays reachable. Nothing is
    // deleted and no lens setting is lost, which is why this is a display choice
    // and lives in the view session rather than the document.
    note.textContent = "Uncheck a lens to take it off the view bar. Hidden lenses stay reachable from the drop at the bar's right end, and keep all their own settings. Arrange the order here too; the number keys follow whatever order you see.";
    // A dedicated class rather than the Frames panel's `.frame-group-list` /
    // `.frame-group-row` — those are also used by frames-panel.js's group
    // presence controls, which this wave does not touch, and the two lists
    // now need different layouts (name + checkbox + reorder sharing one line
    // here, so the whole list fits without scrolling).
    const list = document.createElement("div");
    list.className = "lens-workspace-list";
    const render = () => {
      list.replaceChildren();
      for (const lens of draftOrder) {
        const spec = LENS_CATALOG[lens];
        const row = document.createElement("div");
        row.className = "lens-workspace-row";
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
        const meta = document.createElement("small");
        meta.className = "lens-workspace-meta";
        meta.title = spec.description;
        meta.textContent = `${spec.description} — ${spec.capabilities.join(" · ")}`;
        const previous = document.createElement("button");
        previous.type = "button"; previous.className = "instrument-button lens-reorder lens-reorder-up"; previous.textContent = "↑";
        previous.title = `Move ${spec.title} earlier`;
        previous.addEventListener("click", () => {
          const index = draftOrder.indexOf(lens);
          if (index > 0) [draftOrder[index - 1], draftOrder[index]] = [draftOrder[index], draftOrder[index - 1]];
          render();
        });
        const next = document.createElement("button");
        next.type = "button"; next.className = "instrument-button lens-reorder lens-reorder-down"; next.textContent = "↓";
        next.title = `Move ${spec.title} later`;
        next.addEventListener("click", () => {
          const index = draftOrder.indexOf(lens);
          if (index >= 0 && index < draftOrder.length - 1) [draftOrder[index + 1], draftOrder[index]] = [draftOrder[index], draftOrder[index + 1]];
          render();
        });
        row.append(enabled, previous, next, meta);
        list.append(row);
      }
    };
    render();
    const actions = document.createElement("div");
    actions.className = "inspector-actions";
    const restore = document.createElement("button");
    restore.type = "button"; restore.className = "instrument-button"; restore.textContent = "Restore defaults";
    restore.addEventListener("click", () => { draftOrder = [...DEFAULT_LENS_ORDER]; draftEnabled = new Set(DEFAULT_LENS_ORDER); render(); });
    const commit = () => session.configureLenses({ lensOrder: draftOrder, enabledLenses: [...draftEnabled] });
    // Apply makes the checked/ordered draft the live workspace without closing
    // the dialog — the same commit-without-close path the theme editor got
    // (owner item 13, generalized past the theme editor alone). It is cheap
    // here because lens order/visibility is ViewSession state, not a document
    // edit: there is no undo entry to multiply by applying repeatedly, unlike
    // the event editor's Save.
    const apply = document.createElement("button");
    apply.type = "button"; apply.id = "apply-lens-workspace"; apply.className = "instrument-button"; apply.textContent = "Apply";
    apply.addEventListener("click", () => {
      commit();
      app.scheduleRender();
    });
    const save = document.createElement("button");
    save.type = "submit"; save.className = "instrument-button primary"; save.textContent = "Save workspace lenses";
    actions.append(restore, apply, save);
    wrapper.append(note, list, actions);
    wrapper.addEventListener("submit", (event) => {
      event.preventDefault();
      commit();
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

  // The Frame drop's own checkboxes (built in updateFrameSelect) each wire
  // their "change" directly — a single-value "change" on one control no
  // longer fits once the control accepts multiple selections.

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

  // Mutual exclusion between create-menu and document-menu (opening one used
  // to close the other via a hand-paired pair of toggle listeners naming
  // each other) is now registerBarDropdown's own toggle handler, applying to
  // every registered dropdown uniformly — see its "Mutual exclusion" comment
  // above. Neither menu carries any special-case code of its own any more.

  byId("theme-settings").addEventListener("click", () => {
    closeDocumentMenu();
    openThemeEditor();
  });
  byId("lens-settings").addEventListener("click", () => {
    closeDocumentMenu();
    openLensWorkspace();
  });
  byId("dock-side").addEventListener("click", () => {
    closeDocumentMenu();
    app.toggleDockSide();
  });
  // Settings opens the surfaces that exist today. The settings takeover view that
  // replaces the stage is ROADMAP #3; this button is the entry point it will
  // inherit, so the owner has one predictable place to look in the meantime.
  byId("settings").addEventListener("click", () => {
    closeDocumentMenu();
    openLensWorkspace();
  });
  byId("open-todos").addEventListener("click", () => app.openRoster("todo"));
  byId("open-notes").addEventListener("click", () => app.openRoster("note"));

  // A press outside the dock used to discard a provisional draft and close the
  // panel. That was harmless when the panel was a drawer floating over the stage,
  // and it is poison now the dock owns a grid track: pressing down to drag out a
  // new event collapsed the dock, so the stage widened under the pointer in the
  // middle of the gesture and then the dock reopened on release.
  //
  // The rule is now explicit: stage interactions never collapse the dock. It
  // closes when the user closes it — its last card's handle, or Escape. A
  // provisional draft therefore survives until it is saved or its card is closed,
  // which is also the only reading that makes sense once several drafts can be
  // open at once. (Create-menu's own outside-click-to-close is the generic
  // pointerdown listener registered above with every other bar dropdown; it
  // no longer needs, or has, code of its own here.)

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
    // A bar dropdown's own keyboard contract takes priority over every other
    // shortcut while it is open: Escape closes it and returns focus to its
    // anchor (the one place this module forces focus anywhere), and Tab/
    // Shift-Tab are trapped inside its panel (wrapFocusIndex in
    // panel-flip.js) because a portaled panel is no longer where the
    // document's native tab order would carry Tab to next. This is driven by
    // the registry, not a named dropdown, so it covers every attachment
    // point the same way.
    const openDropdownId = dropdowns.ids().find((id) => dropdowns.get(id).container.open);
    if (openDropdownId) {
      const entry = dropdowns.get(openDropdownId);
      if (event.key === "Escape") {
        event.preventDefault();
        closeBarDropdown(openDropdownId, { returnFocus: true });
        return;
      }
      if (event.key === "Tab") {
        const focusables = focusableElements(entry.panel);
        if (focusables.length) {
          const currentIndex = focusables.indexOf(document.activeElement);
          const nextIndex = wrapFocusIndex(currentIndex, event.shiftKey ? -1 : 1, focusables.length);
          event.preventDefault();
          focusables[nextIndex]?.focus();
          return;
        }
      }
    }
    if (event.key === "Escape" && app.dockIsOpen()) {
      event.preventDefault();
      app.closeInspector();
      return;
    }
    // Dock paging works while a field has focus, because a card is usually a form
    // and requiring the user to leave it before cycling cards would defeat the
    // point of paging. PageUp/PageDown do not type anything, so they are safe here.
    if (app.dockIsOpen() && (event.key === "PageUp" || event.key === "PageDown")) {
      event.preventDefault();
      app.pageDockBy(event.key === "PageDown" ? 1 : -1);
      return;
    }
    const editing = /^(INPUT|TEXTAREA|SELECT)$/.test(event.target.tagName);
    if (editing) return;
    if (event.key === "Delete" && session.inspector?.type === "event") {
      const deleteButton = app.dockCardBody("panel:object")?.querySelector("#delete-object");
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
    } else if (/^[1-9]$/.test(event.key) && (event.altKey || app.dockIsOpen() && event.ctrlKey)) {
      // Ordinal keys jump to a card by position in the rail. They are modified so
      // the bare digits stay with the lenses, which are the more frequent target.
      event.preventDefault();
      app.pageDockTo(Number(event.key) - 1);
      return;
    } else if (/^[1-7]$/.test(event.key)) {
      // The digits follow the bar the user is looking at, not a fixed catalogue
      // order. With a lens hidden or reordered, the old hard-coded list meant 4
      // could land on a lens that was not the fourth button — or on a hidden one,
      // where `setLens` refused and the key silently did nothing.
      const visible = session.availableLenses();
      const lens = visible[Number(event.key) - 1];
      if (!lens) return;
      session.setLens(lens);
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

  // Exported under its historical name (workspace.js's render loop calls
  // `app.updateCalendarSelect()`) even though the dropdown itself is now the
  // Frame drop — renaming the call site is out of scope for this file.
  // barDropdowns is exposed mainly so the placement/z-level contract can be
  // tested by enumerating what is actually registered, rather than a test
  // hand-maintaining its own list of attachment points (the exact shape of
  // bug this item exists to close off).
  return {
    updateCalendarSelect: updateFrameSelect,
    updateChrome,
    updateLensControls,
    closeDocumentMenu,
    reconcileRadialCycle,
    selectCycle,
    barDropdowns: dropdowns
  };
}
