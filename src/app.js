import { createCelestialDocument } from "./celestial.js";
import { ChronologEngine } from "./engine.js";
import {
  Rational,
  civilFromDays,
  coordinate,
  daysFromCivil,
  daysInMonth,
  daysToCivilCoordinate,
  formatCivil,
  levelValue
} from "./exact.js";
import { exportICS, importICS } from "./ics.js";
import { additiveFrameTraits, preservedFrameSchema } from "./frame-edit.js";
import {
  CommandHistory,
  addEvent,
  addFrame,
  addPattern,
  addRelation,
  clone,
  createId,
  durationMagnitude,
  eventRelations,
  stapleEvents,
  touch,
  validateDocument
} from "./model.js";
import {
  calendarFrames,
  groupFrames,
  renderMinimap,
  renderProjection
} from "./projections.js";
import { FIXED_RADIAL_CYCLES, cyclePeriodHint, resolveRadialCycle } from "./radial.js";
import {
  DETENTS,
  INTIMATE_HOUR_PIXELS_MAX,
  INTIMATE_HOUR_PIXELS_MIN,
  ViewSession,
  minimapDragFocus,
  minimapDragState,
  sanitizeSessionParameters
} from "./session.js";
import {
  AutosaveStore,
  downloadText,
  parseDocument
} from "./store.js";

const byId = (id) => document.getElementById(id);
const projection = byId("projection");
const minimap = byId("minimap");
const inspector = byId("inspector");
const inspectorBody = byId("inspector-body");
const inspectorTitle = byId("inspector-title");
const toastNode = byId("toast");
const lensControls = byId("lens-controls");
const WORKSPACE_TARGET = { remoteUrl: "/api/document", filename: "chronolog.chronolog" };
const LOCAL_WORKSPACE_TARGET = /^https?:$/.test(location.protocol) ? WORKSPACE_TARGET : {};
const SESSION_STORAGE_KEY = "chronolog:view-session:1";
const THEME_STORAGE_KEY = "chronolog:color-theme:1";
const THEME_FIELDS = {
  ground: "Ground", surface: "Surface", paper: "Paper", ink: "Ink",
  muted: "Muted", now: "Now", green: "Positive", blue: "Accent"
};

function storedSession() {
  try {
    return JSON.parse(localStorage.getItem(SESSION_STORAGE_KEY) || "{}");
  } catch {
    return {};
  }
}

function storedTheme() {
  try { return JSON.parse(localStorage.getItem(THEME_STORAGE_KEY) || "{}"); } catch { return {}; }
}

function applyTheme(theme) {
  for (const name of Object.keys(THEME_FIELDS)) {
    const value = theme[name];
    if (/^#[0-9a-f]{6}$/i.test(value || "")) document.documentElement.style.setProperty(`--${name}`, value);
    else document.documentElement.style.removeProperty(`--${name}`);
  }
}

applyTheme(storedTheme());

let chronolog = createCelestialDocument();
let engine = new ChronologEngine(chronolog);
const initialFrame = calendarFrames(chronolog)[0]?.id || "";
const session = new ViewSession({
  activeFrame: initialFrame,
  projection: "calendar",
  scale: 1,
  radialMode: "spiral",
  ...storedSession(),
  ...sanitizeSessionParameters(new URLSearchParams(location.search), chronolog)
});
let renderQueued = false;
let toastTimer = null;
let lensControlsSignature = "";
const viewScroll = new Map();
let pendingIntimateRebase = null;
let pendingIntimateZoom = null;
let intimateScrollGuard = 0;
let provisionalEvent = null;
let documentLoading = true;

const store = new AutosaveStore({
  onStatus(status) {
    const node = byId("save-status");
    node.dataset.state = status.state;
    node.textContent = status.message;
  }
});
store.attach(chronolog, WORKSPACE_TARGET);

let history = makeHistory();

function makeHistory() {
  return new CommandHistory(chronolog, (change) => {
    if (change.frameOnly) engine.refreshFrame(change.frameOnly);
    else if (!change.viewOnly) engine.setDocument(chronolog, { preserveRecurrence: change.preserveRecurrence });
    reconcileSession();
    store.markDirty();
    scheduleRender();
    if (change.historyLimited) {
      toast("Change applied, but this large operation was not kept in undo history.");
    }
  });
}

function replaceDocument(next, storageTarget = {}) {
  provisionalEvent = null;
  chronolog = next;
  engine = new ChronologEngine(chronolog);
  history = makeHistory();
  store.attach(chronolog, storageTarget);
  closeInspector();
  reconcileSession();
  scheduleRender();
}

function reconcileSession() {
  const leadingFrame = chronolog.frames[session.activeFrame]
    ? session.activeFrame
    : calendarFrames(chronolog)[0]?.id || "";
  session.setLeadingFrame(leadingFrame);
  const cycles = radialCycleOptions();
  const activeCycle = resolveRadialCycle(cycles, session.activeCycle);
  if (activeCycle) {
    session.activeCycle = activeCycle.id;
    session.radialCycle = activeCycle.period;
  }
  const open = session.inspector;
  if (!open?.id) return;
  const pool = open.type === "event"
    ? chronolog.events
    : open.type === "frame"
      ? chronolog.frames
      : chronolog.patterns;
  if (!pool[open.id]) closeInspector();
}

function context() {
  return { document: chronolog, engine, session, loading: documentLoading };
}

function scheduleRender() {
  try { localStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(session.toJSON())); } catch {}
  if (renderQueued) return;
  renderQueued = true;
  requestAnimationFrame(() => {
    renderQueued = false;
    render();
  });
}

function render() {
  const previousScroll = projection.querySelector("[data-scroll-key]");
  if (previousScroll && !(previousScroll.dataset.scrollKey === "intimate" && (pendingIntimateRebase || pendingIntimateZoom))) {
    viewScroll.set(previousScroll.dataset.scrollKey, {
      top: previousScroll.scrollTop,
      left: previousScroll.scrollLeft
    });
  }
  updateCalendarSelect();
  updateChrome();
  updateLensControls();
  renderProjection(projection, context());
  const nextScroll = projection.querySelector("[data-scroll-key]");
  if (nextScroll) {
    let saved = viewScroll.get(nextScroll.dataset.scrollKey);
    if (nextScroll.dataset.scrollKey === "intimate" && pendingIntimateRebase) saved = pendingIntimateRebase;
    if (nextScroll.dataset.scrollKey === "intimate" && pendingIntimateZoom) {
      const hourPixels = Number(nextScroll.dataset.hourPixels || 28);
      const bufferHours = Number(nextScroll.dataset.bufferHours || 24);
      const headerPixels = Number(nextScroll.dataset.headerPixels || 70);
      saved = {
        top: headerPixels + (bufferHours + pendingIntimateZoom.localHour) * hourPixels - pendingIntimateZoom.offset,
        left: pendingIntimateZoom.left
      };
    }
    if (saved) {
      const intimateProgrammaticScroll = nextScroll.dataset.scrollKey === "intimate";
      const scrollGuard = intimateProgrammaticScroll ? ++intimateScrollGuard : 0;
      nextScroll.scrollTop = saved.top;
      nextScroll.scrollLeft = saved.left;
      if (nextScroll.dataset.scrollKey === "intimate" && (pendingIntimateRebase || pendingIntimateZoom)) {
        viewScroll.set("intimate", { top: nextScroll.scrollTop, left: nextScroll.scrollLeft });
        pendingIntimateRebase = null;
        pendingIntimateZoom = null;
      }
      if (intimateProgrammaticScroll) {
        requestAnimationFrame(() => {
          if (intimateScrollGuard === scrollGuard) intimateScrollGuard = 0;
        });
      }
    } else if (nextScroll.dataset.scrollKey === "intimate") {
      const bufferHours = Number(nextScroll.dataset.bufferHours || 0);
      const hourPixels = Number(nextScroll.dataset.hourPixels || 56);
      const initialHour = Number(nextScroll.dataset.initialHour || session.intimateStartHour);
      const scrollGuard = ++intimateScrollGuard;
      nextScroll.scrollTop = Math.max(0, 70 + (bufferHours + initialHour) * hourPixels - nextScroll.clientHeight / 2);
      requestAnimationFrame(() => {
        if (intimateScrollGuard === scrollGuard) intimateScrollGuard = 0;
      });
    }
  }
  renderMinimap(minimap, context());
}

function updateCalendarSelect() {
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

function selectLeadingFrame(frameId) {
  if (!calendarFrames(chronolog).some((frame) => frame.id === frameId)) return;
  session.setLeadingFrame(frameId);
  const matchingCycle = Object.values(chronolog.frames).find(
    (frame) => frame.traits.includes("cycle") && frame.calendar === session.activeFrame
  );
  if (matchingCycle) selectCycle(matchingCycle.id);
  refreshFramesPanel();
  scheduleRender();
}

function updateChrome() {
  byId("shared-focus").checked = session.sharedFocus;
  byId("focus-readout").textContent = formatCivil(daysToCivilCoordinate(session.currentFocus()), true);
  byId("undo").disabled = history.undoStack.length === 0;
  byId("redo").disabled = history.redoStack.length === 0;
  document.querySelectorAll("[data-lens]").forEach((button) => {
    button.classList.toggle("active", button.dataset.lens === session.currentLens());
  });
}

function shiftFocusMonths(offset) {
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

function updateLensControls() {
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
      scheduleRender();
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
      action(Math.max(min, Math.min(max, Math.round(Number(input.value) || value))));
      scheduleRender();
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
      scheduleRender();
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
      scheduleRender();
    });
    label.append(input);
    return label;
  };
  const readout = (text) => {
    const node = document.createElement("span");
    node.className = "lens-readout";
    node.textContent = text;
    return node;
  };

  const controls = [];
  let primaryControlIndexes = [];
  const hourLabel = (hour) => hour === 0 || hour === 24 ? "12 AM" : hour === 12 ? "12 PM" : `${hour % 12} ${hour < 12 ? "AM" : "PM"}`;
  const todayControl = button("◎", goToToday, "Center this lens on today");
  todayControl.id = "today";
  todayControl.classList.add("today-target");
  if (lens === "intimate") {
    const visibleHours = Math.max(1, (projection.clientHeight - 70) / session.intimateHourPixels);
    const zoomOut = button("−", () => adjustWindow(1), "Zoom Intimate out (keyboard: −)");
    zoomOut.setAttribute("aria-label", "Zoom Intimate out");
    const zoomIn = button("+", () => adjustWindow(-1), "Zoom Intimate in (keyboard: +)");
    zoomIn.setAttribute("aria-label", "Zoom Intimate in");
    todayControl.title = "Center Intimate on today and now";
    todayControl.setAttribute("aria-label", "Center Intimate on today and now");
    controls.push(
      button("« week", () => session.move(-7)),
      button("‹ day", () => session.move(-1)),
      zoomOut,
      readout(`~${visibleHours < 10 ? visibleHours.toFixed(1) : Math.round(visibleHours)} hr screen`),
      zoomIn,
      button("day ›", () => session.move(1)),
      button("week »", () => session.move(7)),
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
    primaryControlIndexes = [1, 2, 3];
  } else if (lens === "tactical") {
    controls.push(
      button("‹ row", () => session.move(-session.tacticalColumns)),
      readout(`${session.tacticalRows} × ${session.tacticalColumns} · ${session.tacticalRows * session.tacticalColumns} days`),
      button("row ›", () => session.move(session.tacticalColumns)),
      number("rows", session.tacticalRows, 1, 8, (value) => { session.tacticalRows = value; }),
      number("days / row", session.tacticalColumns, 1, 14, (value) => { session.tacticalColumns = value; })
    );
    primaryControlIndexes = [0, 1, 2];
  } else if (lens === "lines") {
    controls.push(
      button("‹ fortnight", () => session.move(-14)),
      readout(`${session.linesDays} days`),
      button("fortnight ›", () => session.move(14)),
      number("window", session.linesDays, 3, 90, (value) => { session.linesDays = value; })
    );
    primaryControlIndexes = [0, 1, 2];
  } else if (["strategic", "wall"].includes(lens)) {
    const property = lens === "strategic" ? "strategicMonths" : "wallMonths";
    const maximum = lens === "wall" ? 12 : 18;
    controls.push(
      button("‹ month", () => shiftFocusMonths(-1)),
      readout(`${session[property]} month${session[property] === 1 ? "" : "s"}`),
      button("month ›", () => shiftFocusMonths(1)),
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
    primaryControlIndexes = [0, 1, 2];
  } else if (["spiral", "radial"].includes(lens)) {
    const cycleDays = session.radialCycle.toNumber();
    const divisions = session.radialDivisions || (cycleDays >= 5 ? Math.max(1, Math.round(cycleDays)) : 24);
    const subdivisionDays = cycleDays / divisions;
    const subdivision = subdivisionDays < 1
      ? `${(subdivisionDays * 24).toFixed(subdivisionDays * 24 < 10 ? 1 : 0)} hr / spoke`
      : `${subdivisionDays.toFixed(subdivisionDays < 10 ? 1 : 0)} days / spoke`;
    controls.push(
      button("‹ cycle", () => session.move(session.radialCycle.neg())),
      select("cycle", cycles.map((cycle) => [cycle.id, cycle.title]), session.activeCycle, selectCycle),
      readout(`${divisions} ticks · ${subdivision}`),
      button("cycle ›", () => session.move(session.radialCycle))
    );
    if (lens === "spiral") {
      controls.push(
        number("inward", session.radialPast, 0, 12, (value) => { session.radialPast = value; }),
        number("outward", session.radialFuture, 0, 12, (value) => { session.radialFuture = value; })
      );
    }
    controls.push(
      checkbox("labels", session.radialLabels, (value) => { session.radialLabels = value; }),
      number("ticks (0 auto)", session.radialDivisions, 0, 64, (value) => { session.radialDivisions = value; }),
      number("bold every (0 auto)", session.radialMajorEvery, 0, 16, (value) => { session.radialMajorEvery = value; }),
      select("marks", [["auto", "Cycle aware"], ["day-night", "Midnight + noon"], ["plain", "Plain"]], session.radialMarks, (value) => { session.radialMarks = value; })
    );
    primaryControlIndexes = [0, 2, 3];
  }
  if (lens === "intimate") controls.push(checkbox("zone fill", session.intimateZoneFill, (value) => { session.intimateZoneFill = value; }));
  if (lens === "tactical") controls.push(checkbox("zone fill", session.tacticalZoneFill, (value) => { session.tacticalZoneFill = value; }));
  const primaryControls = primaryControlIndexes.map((index) => controls[index]);
  const optionControls = controls.filter((_, index) => !primaryControlIndexes.includes(index));
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
  lensControls.append(...primaryControls, options, todayControl);
}

function toast(message, error = false) {
  clearTimeout(toastTimer);
  toastNode.textContent = message;
  toastNode.classList.toggle("error", error);
  toastNode.classList.add("show");
  toastTimer = setTimeout(() => toastNode.classList.remove("show"), 3600);
}

function closeInspector() {
  discardProvisionalDraft();
  dismissInspector();
}

function dismissInspector() {
  const wasFramesBrowser = inspector.dataset.panel === "frames-browser";
  inspector.classList.remove("open");
  delete inspector.dataset.panel;
  session.inspector = null;
  byId("new-frame").setAttribute("aria-expanded", "false");
  if (wasFramesBrowser) byId("new-frame").focus();
}

function discardProvisionalDraft(nextEventId = null) {
  if (!provisionalEvent || provisionalEvent.id === nextEventId) return false;
  const eventId = provisionalEvent.id;
  provisionalEvent = null;
  try {
    executeEventChange("Discard provisional draft", eventId, (documentValue) => {
      delete documentValue.events[eventId];
      for (const [id, relation] of Object.entries(documentValue.relations)) {
        if (relation.event === eventId) delete documentValue.relations[id];
      }
    }, true);
  } finally {
    // A close or validation failure must never leave the document permanently
    // deferred. The draft is a transaction, not an autosave lock.
    store.endDeferred();
  }
  return true;
}

function resolveProvisionalDraft(nextEventId = null) {
  if (!provisionalEvent || provisionalEvent.id === nextEventId) return true;
  discardProvisionalDraft();
  return true;
}

function commitProvisionalDraft(eventId) {
  if (!provisionalEvent || provisionalEvent.id !== eventId) return false;
  provisionalEvent = null;
  store.endDeferred();
  return true;
}

function openInspector(title, body, panel = "object") {
  inspectorTitle.textContent = title;
  inspectorBody.replaceChildren(body);
  inspector.dataset.panel = panel;
  inspector.classList.add("open");
}

function focusInspectorEditor(eventId) {
  requestAnimationFrame(() => {
    if (session.inspector?.type !== "event" || session.inspector.id !== eventId) return;
    const title = inspectorBody.querySelector('input[name="title"]');
    if (!(title instanceof HTMLInputElement)) return;
    title.focus({ preventScroll: true });
    title.select();
  });
}

function escapeHTML(value = "") {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function parseDateText(text) {
  const match = /^([+-]?\d+)-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2}(?:\.\d+)?))?)?$/.exec(
    String(text).trim()
  );
  if (!match) throw new Error("Use year-month-day and optional hour:minute:second");
  return coordinate([
    { level: "year", value: match[1] },
    { level: "month", value: match[2] },
    { level: "day", value: match[3] },
    { level: "hour", value: match[4] || "0" },
    { level: "minute", value: match[5] || "0" },
    { level: "second", value: match[6] || "0" }
  ]);
}

function friendlyDuration(event) {
  const seconds = magnitudeDays(event?.magnitudes?.duration).mul(86400).toNumber();
  if (!Number.isFinite(seconds) || seconds <= 0) return { amount: "0", unit: "minute" };
  for (const [unit, factor] of [["day", 86400], ["hour", 3600], ["minute", 60]]) {
    const amount = seconds / factor;
    if (Number.isInteger(amount)) return { amount: String(amount), unit };
  }
  return { amount: String(Math.round(seconds)), unit: "second" };
}

function openThemeEditor() {
  const current = getComputedStyle(document.documentElement);
  const form = document.createElement("form");
  form.className = "theme-form";
  form.innerHTML = `<p class="field-note">Edit the application palette. Frame and event colors remain independent.</p>
    <div class="theme-grid">${Object.entries(THEME_FIELDS).map(([name, label]) => `<label class="field"><span>${label}</span><input type="color" name="${name}" value="${escapeHTML(current.getPropertyValue(`--${name}`).trim())}"></label>`).join("")}</div>
    <div class="inspector-actions"><button class="instrument-button primary" type="submit">Save theme</button><button class="instrument-button" id="reset-theme" type="button">Use default</button></div>`;
  form.addEventListener("submit", (event) => {
    event.preventDefault();
    const data = new FormData(form);
    const theme = Object.fromEntries(Object.keys(THEME_FIELDS).map((name) => [name, String(data.get(name))]));
    localStorage.setItem(THEME_STORAGE_KEY, JSON.stringify(theme));
    applyTheme(theme);
    dismissInspector();
  });
  form.querySelector("#reset-theme").addEventListener("click", () => {
    localStorage.removeItem(THEME_STORAGE_KEY);
    applyTheme({});
    dismissInspector();
  });
  openInspector("Color theme", form);
}

function radialCycleOptions() {
  const documentCycles = Object.values(chronolog.frames)
    .filter((frame) => frame.traits?.includes("cycle"))
    .map((frame) => {
      const period = cyclePeriodHint(frame.period);
      return {
        id: frame.id,
        title: period ? frame.title : `${frame.title} (variable)` ,
        days: (period || session.radialCycle).toJSON(),
        variable: !period
      };
    });
  return [...FIXED_RADIAL_CYCLES, ...documentCycles];
}

function selectCycle(cycleId) {
  const choice = radialCycleOptions().find((cycle) => cycle.id === cycleId);
  if (!choice) return;
  const period = Rational.parse(choice.days);
  if (period.compare(0) <= 0) {
    toast("A cycle period must be positive.", true);
    return;
  }
  session.activeCycle = cycleId;
  session.radialCycle = period;
}

function temporalRelations(eventId) {
  return eventRelations(chronolog, eventId).filter(
    (relation) => chronolog.frames[relation.frame]?.traits.includes("calendar")
  );
}

function primaryRelation(eventId) {
  const all = temporalRelations(eventId);
  return all.find((relation) => relation.frame === session.activeFrame && relation.role !== "completed")
    || all.find((relation) => relation.role !== "completed")
    || null;
}

function relationDate(relation) {
  return relation?.coordinate ? formatCivil(relation.coordinate, true) : "";
}

function relationDateParts(relation) {
  if (!relation?.coordinate) return { date: "", time: "" };
  const value = relation.coordinate;
  const year = levelValue(value, "year", 0n).toString().padStart(4, "0");
  const month = levelValue(value, "month", 1n).toString().padStart(2, "0");
  const day = levelValue(value, "day", 1n).toString().padStart(2, "0");
  const hour = levelValue(value, "hour", 0n).toString().padStart(2, "0");
  const minute = levelValue(value, "minute", 0n).toString().padStart(2, "0");
  return { date: `${year}-${month}-${day}`, time: relation.parameters?.dateOnly ? "" : `${hour}:${minute}` };
}

function findVisibleFact(virtualId, nearDay = null) {
  const window = nearDay === null
    ? session.window(1.25)
    : {
        start: Rational.parse(nearDay).sub(Rational.parse(1).div(86400)),
        end: Rational.parse(nearDay).add(Rational.parse(1).div(86400))
      };
  return engine.queryFacts({
    frame: session.activeFrame,
    start: daysToCivilCoordinate(window.start),
    end: daysToCivilCoordinate(window.end),
    limit: nearDay === null ? 1600 : 5000
  }).facts.find((fact) => fact.virtualId === virtualId);
}

function recurrenceFormChoice(pattern) {
  const frequency = String(pattern?.rrule?.FREQ || "").toUpperCase();
  const byDay = String(pattern?.rrule?.BYDAY || "").toUpperCase().split(",")
    .map((value) => value.trim()).filter(Boolean).sort().join(",");
  return frequency === "WEEKLY" && byDay === "FR,MO,TH,TU,WE" ? "WEEKDAYS" : frequency;
}

function prepareMaterialization(fact, coordinateValue = fact.relation.coordinate) {
  const explicitEvent = clone(fact.event);
  explicitEvent.id = createId("event");
  explicitEvent.traits = explicitEvent.traits.filter((trait) => trait !== "generated");
  const patternId = fact.event.provenance?.pattern;
  explicitEvent.provenance = {
    kind: "explicit",
    replaces: fact.virtualId,
    pattern: patternId,
    originalCoordinate: clone(fact.relation.coordinate)
  };
  const explicitRelation = clone(fact.relation);
  explicitRelation.id = createId("relation");
  explicitRelation.event = explicitEvent.id;
  explicitRelation.coordinate = clone(coordinateValue);
  explicitRelation.provenance = { kind: "explicit", replaces: fact.virtualId };
  const override = {
    id: createId("override"),
    virtual: fact.virtualId,
    suppress: true,
    replacements: [explicitEvent.id]
  };
  const templateEventId = chronolog.patterns[patternId]?.templateEvent;
  const relations = templateEventId ? eventRelations(chronolog, templateEventId)
    .filter((relation) => relation.type === "attachment"
      && chronolog.frames[relation.frame]?.traits.includes("group"))
    .map((relation) => ({ ...clone(relation), id: createId("relation"), event: explicitEvent.id })) : [];
  return { event: explicitEvent, relation: explicitRelation, relations, override };
}

function applyMaterialization(documentValue, prepared) {
  documentValue.events[prepared.event.id] = prepared.event;
  documentValue.relations[prepared.relation.id] = prepared.relation;
  for (const relation of prepared.relations || []) documentValue.relations[relation.id] = relation;
  documentValue.overrides[prepared.override.id] = prepared.override;
}

function revertMaterialization(documentValue, prepared) {
  delete documentValue.overrides[prepared.override.id];
  delete documentValue.relations[prepared.relation.id];
  for (const relation of prepared.relations || []) delete documentValue.relations[relation.id];
  delete documentValue.events[prepared.event.id];
}

function captureEventBundle(documentValue, eventId, trackedOverrideIds = []) {
  const tracked = new Set(trackedOverrideIds);
  for (const [id, override] of Object.entries(documentValue.overrides)) {
    if (override.replacements?.includes(eventId)) tracked.add(id);
  }
  return {
    event: clone(documentValue.events[eventId]),
    relations: Object.fromEntries(Object.entries(documentValue.relations)
      .filter(([, relation]) => relation.event === eventId)
      .map(([id, relation]) => [id, clone(relation)])),
    patterns: Object.fromEntries(Object.entries(documentValue.patterns)
      .filter(([, pattern]) => pattern.templateEvent === eventId)
      .map(([id, pattern]) => [id, clone(pattern)])),
    trackedOverrideIds: [...tracked],
    overrides: Object.fromEntries(Object.entries(documentValue.overrides)
      .filter(([id]) => tracked.has(id)).map(([id, override]) => [id, clone(override)]))
  };
}

function restoreEventBundle(documentValue, eventId, bundle) {
  const tracked = new Set(bundle.trackedOverrideIds || Object.keys(bundle.overrides));
  for (const [id, relation] of Object.entries(documentValue.relations)) {
    if (relation.event === eventId) delete documentValue.relations[id];
  }
  for (const [id, pattern] of Object.entries(documentValue.patterns)) {
    if (pattern.templateEvent === eventId) delete documentValue.patterns[id];
  }
  for (const [id, override] of Object.entries(documentValue.overrides)) {
    if (tracked.has(id) || override.replacements?.includes(eventId)) delete documentValue.overrides[id];
  }
  if (bundle.event) documentValue.events[eventId] = clone(bundle.event);
  else delete documentValue.events[eventId];
  Object.assign(documentValue.relations, clone(bundle.relations));
  Object.assign(documentValue.patterns, clone(bundle.patterns));
  Object.assign(documentValue.overrides, clone(bundle.overrides));
}

function executeEventChange(label, eventId, mutate, preserveRecurrence = false) {
  const before = captureEventBundle(chronolog, eventId);
  let after = null;
  history.executeDelta(label, (documentValue) => {
    if (after) restoreEventBundle(documentValue, eventId, after);
    else {
      mutate(documentValue);
      after = captureEventBundle(documentValue, eventId, before.trackedOverrideIds);
    }
  }, (documentValue) => restoreEventBundle(documentValue, eventId, before), { preserveRecurrence });
}

function captureEventSetBundle(documentValue, eventIds) {
  const ids = new Set(eventIds);
  return {
    events: Object.fromEntries(Object.entries(documentValue.events)
      .filter(([id]) => ids.has(id)).map(([id, event]) => [id, clone(event)])),
    relations: Object.fromEntries(Object.entries(documentValue.relations)
      .filter(([, relation]) => ids.has(relation.event)).map(([id, relation]) => [id, clone(relation)])),
    patterns: Object.fromEntries(Object.entries(documentValue.patterns)
      .filter(([, pattern]) => ids.has(pattern.templateEvent)).map(([id, pattern]) => [id, clone(pattern)])),
    overrides: Object.fromEntries(Object.entries(documentValue.overrides)
      .filter(([, override]) => override.replacements?.some((id) => ids.has(id)))
      .map(([id, override]) => [id, clone(override)]))
  };
}

function restoreEventSetBundle(documentValue, eventIds, bundle) {
  const ids = new Set(eventIds);
  for (const id of ids) delete documentValue.events[id];
  for (const [id, relation] of Object.entries(documentValue.relations)) {
    if (ids.has(relation.event)) delete documentValue.relations[id];
  }
  for (const [id, pattern] of Object.entries(documentValue.patterns)) {
    if (ids.has(pattern.templateEvent)) delete documentValue.patterns[id];
  }
  for (const [id, override] of Object.entries(documentValue.overrides)) {
    if (override.replacements?.some((eventId) => ids.has(eventId))) delete documentValue.overrides[id];
  }
  Object.assign(documentValue.events, clone(bundle.events));
  Object.assign(documentValue.relations, clone(bundle.relations));
  Object.assign(documentValue.patterns, clone(bundle.patterns));
  Object.assign(documentValue.overrides, clone(bundle.overrides));
}

function executeEventSetChange(label, eventIds, mutate) {
  const before = captureEventSetBundle(chronolog, eventIds);
  let after = null;
  history.executeDelta(label, (documentValue) => {
    if (after) restoreEventSetBundle(documentValue, eventIds, after);
    else {
      mutate(documentValue);
      after = captureEventSetBundle(documentValue, eventIds);
    }
  }, (documentValue) => restoreEventSetBundle(documentValue, eventIds, before));
}

function executeRecordChange(label, mapName, recordId, mutate, metadata = {}) {
  const before = clone(chronolog[mapName][recordId]);
  let after = null;
  history.executeDelta(label, (documentValue) => {
    if (after) documentValue[mapName][recordId] = clone(after);
    else {
      mutate(documentValue);
      after = clone(documentValue[mapName][recordId]);
    }
  }, (documentValue) => {
    if (before === undefined) delete documentValue[mapName][recordId];
    else documentValue[mapName][recordId] = clone(before);
  }, { preserveRecurrence: mapName !== "patterns", ...metadata });
}

function openVirtualInspector(virtualId) {
  const fact = findVisibleFact(virtualId);
  if (!fact) {
    toast("That generated fact is outside the current query window.", true);
    return;
  }
  const wrapper = document.createElement("div");
  wrapper.innerHTML = `
    <label class="field"><span>Generated by</span>
      <input value="${escapeHTML(fact.event.provenance?.pattern || "")}" readonly>
    </label>
    <label class="field"><span>Title</span>
      <input value="${escapeHTML(fact.event.payload?.title || "")}" readonly>
    </label>
    <label class="field"><span>Occurs</span>
      <input value="${escapeHTML(formatCivil(fact.coordinate, true))}" readonly>
    </label>
    <p style="font:12px/1.5 var(--data);color:var(--muted)">
      Edit only this occurrence, or edit the repeating series that produced it.
    </p>
    <div class="inspector-actions">
      <button class="instrument-button primary" id="materialize" type="button">Edit this occurrence</button>
      <button class="instrument-button" id="edit-series" type="button">Edit series</button>
    </div>`;
  openInspector(fact.event.payload?.title || "Generated fact", wrapper);
  byId("materialize").addEventListener("click", () => {
    const prepared = prepareMaterialization(fact);
    history.executeDelta(
      "Make generated fact explicit",
      (documentValue) => applyMaterialization(documentValue, prepared),
      (documentValue) => revertMaterialization(documentValue, prepared),
      { preserveRecurrence: true }
    );
    openEventInspector(prepared.event.id);
  });
  byId("edit-series").addEventListener("click", () => {
    const pattern = chronolog.patterns[fact.event.provenance?.pattern];
    if (pattern?.templateEvent) openEventInspector(pattern.templateEvent);
  });
}

function openEventInspector(eventId) {
  if (!resolveProvisionalDraft(eventId)) return false;
  const event = chronolog.events[eventId];
  if (!event) return false;
  session.inspector = { type: "event", id: eventId };
  const relation = primaryRelation(eventId);
  const completed = temporalRelations(eventId).find((item) => item.role === "completed");
  const duration = friendlyDuration(event);
  const calendars = calendarFrames(chronolog);
  const allGroups = groupFrames(chronolog);
  const importanceFrames = allGroups.filter((frame) => frame.traits.includes("importance"));
  const groups = allGroups.filter((frame) => !frame.traits.includes("importance"));
  const recurrence = Object.values(chronolog.patterns).find(
    (pattern) => pattern.kind === "ics-rrule" && pattern.templateEvent === eventId
  );
  const originalRecurrenceChoice = recurrenceFormChoice(recurrence);
  const memberships = new Set(
    eventRelations(chronolog, eventId)
      .filter((item) => chronolog.frames[item.frame]?.traits.includes("group"))
      .map((item) => item.frame)
  );
  const isTask = event.traits.includes("task");
  const startParts = relationDateParts(relation);
  const attachedImportance = importanceFrames.find((frame) => memberships.has(frame.id));
  const importance = attachedImportance?.id || (event.traits.includes("landmark") ? "landmark"
    : event.traits.includes("important") ? "important" : "standard");
  const lensScope = event.display?.lenses || null;
  const visibility = attachedImportance ? "importance-frame" : !lensScope ? "everywhere"
    : ["intimate", "spiral", "radial"].every((lens) => lensScope.includes(lens)) && lensScope.length === 3
      ? "time-signal"
      : ["strategic", "wall", "radial"].every((lens) => lensScope.includes(lens)) && lensScope.length === 3
        ? "planning"
        : "close";
  const wrapper = document.createElement("form");
  wrapper.className = "event-form";
  wrapper.innerHTML = `
    <label class="field"><span>Title</span>
      <input name="title" value="${escapeHTML(event.payload?.title || "")}" required>
    </label>
    <div class="form-row">
      <label class="field"><span>${isTask ? "Observed date" : "Start date"}</span>
        <input name="startDate" type="date" value="${escapeHTML(startParts.date)}">
      </label>
      <label class="field"><span>${isTask ? "Observed time" : "Start time"}</span>
        <input name="startTime" type="time" step="60" value="${escapeHTML(startParts.time)}">
      </label>
    </div>
    <div class="form-row">
      <label class="field"><span>Duration</span>
        <input name="duration" inputmode="decimal" value="${escapeHTML(duration.amount)}">
      </label>
      <label class="field"><span>Units</span>
        <select name="unit">
          ${[["minute", "Minutes"], ["hour", "Hours"], ["day", "Days"], ["second", "Seconds"]]
            .map(([value, label]) => `<option value="${value}" ${duration.unit === value ? "selected" : ""}>${label}</option>`).join("")}
        </select>
      </label>
    </div>
    <label class="field"><span>Calendar</span>
      <select name="frame">
        ${calendars.map((frame) => `<option value="${escapeHTML(frame.id)}"
          ${frame.id === relation?.frame ? "selected" : ""}>${escapeHTML(frame.title)}</option>`).join("")}
      </select>
    </label>
    <div class="form-row recurrence-row">
      <label class="field"><span>Repeats</span>
        <select name="repeat">
          ${[["", "Does not repeat"], ["DAILY", "Daily"], ["WEEKDAYS", "Weekdays (Mon–Fri)"], ["WEEKLY", "Weekly"], ["MONTHLY", "Monthly"], ["YEARLY", "Yearly"]]
            .map(([value, label]) => `<option value="${value}" ${originalRecurrenceChoice === value ? "selected" : ""}>${label}</option>`).join("")}
        </select>
      </label>
      <label class="field recurrence-options"><span>Every</span>
        <input name="interval" type="number" min="1" max="999" value="${escapeHTML(recurrence?.rrule?.INTERVAL || "1")}">
      </label>
    </div>
    <label class="field recurrence-options"><span>Ends after</span>
      <input name="count" type="number" min="1" max="10000" value="${escapeHTML(recurrence?.rrule?.COUNT || "")}" placeholder="Leave blank to continue">
    </label>
    ${isTask ? `<label class="field"><span>Completed at (optional)</span>
      <input name="completed" value="${escapeHTML(relationDate(completed))}">
    </label>` : ""}
    <label class="field"><span>Description</span>
      <textarea name="description">${escapeHTML(event.payload?.description || "")}</textarea>
    </label>
    <label class="field"><span>Location or meeting link</span>
      <input name="location" value="${escapeHTML(event.payload?.location || "")}" placeholder="Room, address, Teams, Zoomâ€¦">
    </label>
    <div class="form-row">
      <label class="field"><span>Importance</span><select name="importance">
        ${[["standard", "Standard"], ["important", "Important (legacy)"], ["landmark", "Landmark (legacy)"],
          ...importanceFrames.map((frame) => [frame.id, frame.title])]
          .map(([value, label]) => `<option value="${value}" ${importance === value ? "selected" : ""}>${label}</option>`).join("")}
      </select></label>
      <label class="field"><span>Visible in</span><select name="visibility">
        ${[...(importanceFrames.length ? [["importance-frame", "Use importance frame"]] : []),
          ["everywhere", "Every lens"], ["time-signal", "Intimate + Spiral + Radial"], ["planning", "Strategic + Wall + Radial"], ["close", "Intimate + Tactical"]]
          .map(([value, label]) => `<option value="${value}" ${visibility === value ? "selected" : ""}>${label}</option>`).join("")}
      </select></label>
    </div>
    <div class="form-row event-color-row">
      <label class="check-chip"><input type="checkbox" name="useColor" ${event.display?.color ? "checked" : ""}>Override group color</label>
      <label class="field"><span>Event color</span><input name="eventColor" type="color" value="${escapeHTML(event.display?.color || "#d4552d")}"></label>
    </div>
    <div class="field"><span>Groups</span>
      <div class="check-row">
        ${groups.map((frame) => `<label class="check-chip" style="--group-color:${escapeHTML(frame.color || "#2e8b57")}">
          <input type="checkbox" name="groups" value="${escapeHTML(frame.id)}"
            ${memberships.has(frame.id) ? "checked" : ""}>${escapeHTML(frame.title)}
        </label>`).join("") || `<span style="color:var(--faint);font:11px var(--data)">No groups yet.</span>`}
      </div>
      <div class="inline-create">
        <input name="newGroup" placeholder="New group (created on Apply)">
        <input name="newGroupColor" type="color" value="#2e8b57" title="New group color">
      </div>
    </div>
    <details class="advanced-fields">
      <summary>Advanced identity</summary>
      <label class="field"><span>Traits</span>
        <input name="traits" value="${escapeHTML(event.traits.join(", "))}">
      </label>
    </details>
    <div class="inspector-actions">
      <button class="instrument-button primary" type="submit">Save</button>
      ${event.provenance?.pattern ? `<button class="instrument-button" id="edit-series" type="button">Edit series</button>` : ""}
      ${provisionalEvent?.id === eventId ? `<button class="instrument-button" id="cancel-draft" type="button">Cancel</button>` : ""}
      <button class="instrument-button danger" id="delete-object" type="button">Delete</button>
    </div>`;
  const syncRecurrenceFields = () => wrapper.classList.toggle(
    "has-recurrence",
    Boolean(wrapper.elements.repeat.value)
  );
  wrapper.elements.repeat.addEventListener("change", syncRecurrenceFields);
  syncRecurrenceFields();
  if (provisionalEvent?.id === eventId) {
    provisionalEvent.form = wrapper;
    wrapper.addEventListener("input", () => { if (provisionalEvent?.id === eventId) provisionalEvent.dirty = true; });
    wrapper.addEventListener("change", () => { if (provisionalEvent?.id === eventId) provisionalEvent.dirty = true; });
  }
  openInspector(event.payload?.title || "Event", wrapper);
  if (provisionalEvent?.id === eventId) focusInspectorEditor(eventId);

  wrapper.querySelector("#edit-series")?.addEventListener("click", () => {
    const pattern = chronolog.patterns[event.provenance?.pattern];
    if (pattern?.templateEvent) openEventInspector(pattern.templateEvent);
  });

  wrapper.addEventListener("submit", (inputEvent) => {
    inputEvent.preventDefault();
    const data = new FormData(wrapper);
    try {
      const nextCoordinate = data.get("startDate")
        ? parseDateText(`${data.get("startDate")} ${data.get("startTime") || "00:00"}`)
        : null;
      const dateOnly = !String(data.get("startTime") || "");
      const completedCoordinate = isTask && data.get("completed")
        ? parseDateText(data.get("completed"))
        : null;
      const repeatChoice = String(data.get("repeat") || "");
      const repeat = repeatChoice === "WEEKDAYS" ? "WEEKLY" : repeatChoice;
      const interval = Math.max(1, Math.min(999, Number(data.get("interval")) || 1));
      const count = String(data.get("count") || "").trim();
      if (repeat && !nextCoordinate) throw new Error("A repeating event needs a start date.");
      const selectedGroups = new Set(data.getAll("groups").map(String));
      const selectedImportance = String(data.get("importance") || "standard");
      if (importanceFrames.some((frame) => frame.id === selectedImportance)) selectedGroups.add(selectedImportance);
      const newGroupTitle = String(data.get("newGroup") || "").trim();
      if (newGroupTitle) {
        const groupId = createId("frame");
        executeRecordChange("Create group", "frames", groupId, (documentValue) => {
          documentValue.frames[groupId] = {
            id: groupId,
            title: newGroupTitle,
            traits: ["set", "group"],
            color: String(data.get("newGroupColor") || "#2e8b57")
          };
        });
        selectedGroups.add(groupId);
      }
      executeEventChange("Edit event", eventId, (documentValue) => {
        const target = documentValue.events[eventId];
        target.payload ||= {};
        target.payload.title = String(data.get("title") || "(untitled)");
        target.payload.description = String(data.get("description") || "");
        target.payload.location = String(data.get("location") || "");
        target.traits = String(data.get("traits") || "event")
          .split(",").map((item) => item.trim()).filter(Boolean);
        target.traits = target.traits.filter((trait) => !["important", "landmark"].includes(trait));
        const importanceChoice = String(data.get("importance") || "standard");
        if (["important", "landmark"].includes(importanceChoice)) target.traits.push(importanceChoice);
        if (!target.traits.includes("event")) target.traits.unshift("event");
        const visibilityChoice = String(data.get("visibility") || "everywhere");
        const lensSets = {
          "time-signal": ["intimate", "spiral", "radial"],
          planning: ["strategic", "wall", "radial"],
          close: ["intimate", "tactical"]
        };
        target.display = { ...(target.display || {}) };
        if (["everywhere", "importance-frame"].includes(visibilityChoice)) delete target.display.lenses;
        else target.display.lenses = lensSets[visibilityChoice];
        if (data.get("useColor")) target.display.color = String(data.get("eventColor") || "#d4552d");
        else delete target.display.color;
        target.magnitudes ||= {};
        const requiresZero = target.traits.includes("task") || target.traits.includes("terminator");
        target.magnitudes.duration = durationMagnitude(
          requiresZero ? "0" : String(data.get("duration") || "0"),
          String(data.get("unit") || "second")
        );
        const chosenFrame = String(data.get("frame") || session.activeFrame);
        let existing = Object.values(documentValue.relations).find(
          (item) => item.type === "attachment"
            && item.event === eventId
            && documentValue.frames[item.frame]?.traits.includes("calendar")
            && item.role !== "completed"
        );
        if (nextCoordinate) {
          if (existing) {
            existing.frame = chosenFrame;
            existing.coordinate = nextCoordinate;
            existing.role = target.traits.includes("task") ? "observed" : "placed";
            existing.parameters = { ...(existing.parameters || {}), dateOnly };
          } else {
            existing = addRelation(documentValue, {
              type: "attachment",
              event: eventId,
              frame: chosenFrame,
              role: target.traits.includes("task") ? "observed" : "placed",
              coordinate: nextCoordinate,
              parameters: { dateOnly }
            });
          }
        } else if (existing) {
          delete documentValue.relations[existing.id];
        }
        const existingCompleted = Object.values(documentValue.relations).find(
          (item) => item.type === "attachment" && item.event === eventId && item.role === "completed"
        );
        if (completedCoordinate) {
          if (existingCompleted) {
            existingCompleted.coordinate = completedCoordinate;
            existingCompleted.frame = chosenFrame;
          } else {
            addRelation(documentValue, {
              type: "attachment",
              event: eventId,
              frame: chosenFrame,
              role: "completed",
              coordinate: completedCoordinate
            });
          }
        } else if (existingCompleted) {
          delete documentValue.relations[existingCompleted.id];
        }
        for (const relationValue of Object.values(documentValue.relations)) {
          if (
            relationValue.type === "attachment"
            && relationValue.event === eventId
            && documentValue.frames[relationValue.frame]?.traits.includes("group")
            && !selectedGroups.has(relationValue.frame)
          ) delete documentValue.relations[relationValue.id];
        }
        for (const frameId of selectedGroups) {
          const exists = Object.values(documentValue.relations).some(
            (item) => item.type === "attachment" && item.event === eventId && item.frame === frameId
          );
          if (!exists) addRelation(documentValue, {
            type: "attachment", event: eventId, frame: frameId, role: "member"
          });
        }
        const existingPattern = Object.values(documentValue.patterns).find(
          (pattern) => pattern.kind === "ics-rrule" && pattern.templateEvent === eventId
        );
        if (!repeat && existingPattern) {
          delete documentValue.patterns[existingPattern.id];
        } else if (repeat) {
          const rrule = { ...(existingPattern?.rrule || {}), FREQ: repeat, INTERVAL: String(interval) };
          if (repeatChoice !== originalRecurrenceChoice) {
            delete rrule.BYDAY;
            delete rrule.BYMONTHDAY;
            delete rrule.BYMONTH;
          }
          if (repeatChoice === "WEEKDAYS") rrule.BYDAY = "MO,TU,WE,TH,FR";
          if (count) rrule.COUNT = String(Math.max(1, Math.min(10000, Number(count) || 1)));
          else delete rrule.COUNT;
          if (existingPattern) {
            existingPattern.rrule = rrule;
            if (existingPattern.rawRule) {
              existingPattern.rawRule = {
                ...existingPattern.rawRule,
                value: Object.entries(rrule).map(([key, value]) => `${key}=${value}`).join(";")
              };
              delete existingPattern.rawRule.raw;
              delete existingPattern.rawRule.verbatim;
            }
            existingPattern.appliesTo = [chosenFrame];
            existingPattern.frame = chosenFrame;
            existingPattern.templateRelation = existing?.id;
          } else {
            addPattern(documentValue, {
              title: `${target.payload.title} recurrence`,
              language: "chronolog-formula/1",
              kind: "ics-rrule",
              appliesTo: [chosenFrame],
              frame: chosenFrame,
              templateEvent: eventId,
              templateRelation: existing?.id,
              rrule,
              source: "export fn state(ctx) = {};\nexport fn facts(ctx) = [];",
              exports: { state: "state", facts: "facts" }
            });
          }
        }
      });
      commitProvisionalDraft(eventId);
      dismissInspector();
    } catch (error) {
      toast(error.message, true);
    }
  });

  wrapper.querySelector("#delete-object").addEventListener("click", () => {
    const wasProvisional = provisionalEvent?.id === eventId;
    if (wasProvisional) provisionalEvent = null;
    executeEventChange("Delete event", eventId, (documentValue) => {
      delete documentValue.events[eventId];
      for (const relationValue of Object.values(documentValue.relations)) {
        if (relationValue.event === eventId) delete documentValue.relations[relationValue.id];
      }
      for (const pattern of Object.values(documentValue.patterns)) {
        if (pattern.templateEvent === eventId) delete documentValue.patterns[pattern.id];
      }
      for (const [id, override] of Object.entries(documentValue.overrides)) {
        if (!override.replacements?.includes(eventId)) continue;
        override.replacements = override.replacements.filter((replacement) => replacement !== eventId);
        if (!override.replacements.length && override.suppress !== true) delete documentValue.overrides[id];
      }
    });
    if (wasProvisional) store.endDeferred();
    dismissInspector();
  });

  wrapper.querySelector("#cancel-draft")?.addEventListener("click", () => {
    if (discardProvisionalDraft()) dismissInspector();
  });
  return true;
}

function frameKind(frame) {
  if (frame?.traits?.includes("calendar")) return "calendar";
  if (frame?.traits?.includes("importance")) return "importance";
  if (frame?.traits?.includes("group")) return "group";
  if (frame?.traits?.includes("cycle")) return "cycle";
  if (frame?.traits?.includes("line") || frame?.traits?.includes("timeline")) return "line";
  if (frame?.traits?.includes("measure")) return "measure";
  return "other";
}

function frameKindTraits(kind, existing = []) {
  return additiveFrameTraits(kind, [], existing);
}

function captureFrameBundle(documentValue, frameId) {
  return {
    frame: clone(documentValue.frames[frameId]),
    relations: Object.fromEntries(Object.entries(documentValue.relations).filter(([, relation]) =>
      relation.frame === frameId || relation.parent === frameId || relation.child === frameId
    ).map(([id, relation]) => [id, clone(relation)])),
    patterns: Object.fromEntries(Object.entries(documentValue.patterns).filter(([, pattern]) =>
      pattern.frame === frameId || pattern.appliesTo?.includes(frameId)
    ).map(([id, pattern]) => [id, clone(pattern)]))
  };
}

function restoreFrameBundle(documentValue, frameId, bundle) {
  for (const [id, relation] of Object.entries(documentValue.relations)) {
    if (relation.frame === frameId || relation.parent === frameId || relation.child === frameId) delete documentValue.relations[id];
  }
  for (const [id, pattern] of Object.entries(documentValue.patterns)) {
    if (pattern.frame === frameId || pattern.appliesTo?.includes(frameId)) delete documentValue.patterns[id];
  }
  if (bundle.frame) documentValue.frames[frameId] = clone(bundle.frame);
  else delete documentValue.frames[frameId];
  Object.assign(documentValue.relations, clone(bundle.relations));
  Object.assign(documentValue.patterns, clone(bundle.patterns));
}

function executeFrameChange(label, frameId, mutate) {
  const before = captureFrameBundle(chronolog, frameId);
  let after = null;
  history.executeDelta(label, (documentValue) => {
    if (after) restoreFrameBundle(documentValue, frameId, after);
    else {
      mutate(documentValue);
      after = captureFrameBundle(documentValue, frameId);
    }
  }, (documentValue) => restoreFrameBundle(documentValue, frameId, before));
}

function legacyFrameForm(frame = null) {
  const isNew = !frame;
  const value = frame || {
    id: "",
    title: "New group",
    traits: ["set", "group"],
    basis: "",
    color: "#2e8b57",
    coordinate: null,
    period: null
  };
  const recordId = value.id || createId("frame");
  const wrapper = document.createElement("form");
  wrapper.innerHTML = `
    <label class="field"><span>Title</span>
      <input name="title" value="${escapeHTML(value.title)}" required>
    </label>
    <label class="field"><span>Traits</span>
      <input name="traits" value="${escapeHTML(value.traits.join(", "))}">
    </label>
    <label class="field"><span>Basis frame</span>
      <select name="basis">
        <option value="">None</option>
        ${Object.values(chronolog.frames).filter((item) => item.id !== value.id)
          .map((item) => `<option value="${escapeHTML(item.id)}"
            ${item.id === value.basis ? "selected" : ""}>${escapeHTML(item.title)}</option>`).join("")}
      </select>
    </label>
    <label class="field"><span>Color</span>
      <input name="color" type="color" value="${escapeHTML(value.color || "#2e8b57")}">
    </label>
    <label class="field"><span>Cycle period in days (when trait includes cycle)</span>
      <input name="period" value="${escapeHTML(
        value.period?.value?.levels?.find((part) => part.level === "day")?.value || ""
      )}">
    </label>
    <label class="field"><span>Coordinate nesting (JSON)</span>
      <textarea name="coordinate" class="code">${escapeHTML(
        value.coordinate ? JSON.stringify(value.coordinate, null, 2) : ""
      )}</textarea>
    </label>
    <div class="inspector-actions">
      <button class="instrument-button primary" type="submit">${isNew ? "Create" : "Apply"}</button>
      ${isNew ? "" : `<button class="instrument-button danger" id="delete-object" type="button">Delete</button>`}
    </div>`;
  wrapper.addEventListener("submit", (event) => {
    event.preventDefault();
    const data = new FormData(wrapper);
    try {
      const coordinateSchema = data.get("coordinate")
        ? JSON.parse(String(data.get("coordinate")))
        : undefined;
      executeRecordChange(isNew ? "Create frame" : "Edit frame", "frames", recordId, (documentValue) => {
        const payload = {
          id: recordId,
          title: String(data.get("title")),
          traits: String(data.get("traits")).split(",").map((item) => item.trim()).filter(Boolean),
          basis: String(data.get("basis") || "") || undefined,
          color: String(data.get("color") || "#2e8b57"),
          coordinate: coordinateSchema,
          period: data.get("period")
            ? {
                frame: "measure:human-time",
                value: coordinate([{ level: "day", value: String(data.get("period")) }])
              }
            : undefined
        };
        if (isNew) addFrame(documentValue, payload);
        else Object.assign(documentValue.frames[recordId], payload);
      }, { frameOnly: recordId });
      openFrameInspector(recordId);
    } catch (error) {
      toast(error.message, true);
    }
  });
  if (!isNew) wrapper.querySelector("#delete-object").addEventListener("click", () => {
    const referenced = Object.values(chronolog.relations).some(
      (relation) => relation.frame === value.id || relation.parent === value.id || relation.child === value.id
    );
    if (referenced) {
      toast("Remove this frame's attachments and compositions before deleting it.", true);
      return;
    }
    executeRecordChange("Delete frame", "frames", value.id, (documentValue) => {
      delete documentValue.frames[value.id];
    });
    openObjectBrowser("frame");
  });
  return wrapper;
}

function duplicateFrame(frameId) {
  const source = chronolog.frames[frameId];
  if (!source) return;
  const nextId = createId("frame");
  const nextFrame = {
    ...clone(source),
    id: nextId,
    title: `${source.title} copy`,
    display: { ...(source.display || {}), mode: "standalone", order: Number(source.display?.order || 0) + 1 }
  };
  const relationMap = new Map();
  const relations = [];
  for (const relation of Object.values(chronolog.relations)) {
    if (relation.frame !== frameId && relation.parent !== frameId && relation.child !== frameId) continue;
    const id = createId("relation");
    relationMap.set(relation.id, id);
    relations.push({
      ...clone(relation), id,
      frame: relation.frame === frameId ? nextId : relation.frame,
      parent: relation.parent === frameId ? nextId : relation.parent,
      child: relation.child === frameId ? nextId : relation.child
    });
  }
  const patterns = Object.values(chronolog.patterns).filter((pattern) =>
    pattern.frame === frameId || pattern.appliesTo?.includes(frameId)
  ).map((pattern) => ({
    ...clone(pattern),
    id: createId("pattern"),
    title: `${pattern.title || "Pattern"} copy`,
    frame: pattern.frame === frameId ? nextId : pattern.frame,
    appliesTo: pattern.appliesTo?.map((id) => id === frameId ? nextId : id),
    templateRelation: relationMap.get(pattern.templateRelation) || pattern.templateRelation
  }));
  history.executeDelta("Duplicate frame", (documentValue) => {
    documentValue.frames[nextId] = clone(nextFrame);
    for (const relation of relations) documentValue.relations[relation.id] = clone(relation);
    for (const pattern of patterns) documentValue.patterns[pattern.id] = clone(pattern);
  }, (documentValue) => {
    delete documentValue.frames[nextId];
    for (const relation of relations) delete documentValue.relations[relation.id];
    for (const pattern of patterns) delete documentValue.patterns[pattern.id];
  });
  openFrameInspector(nextId);
}

function frameForm(frame = null, presetKind = "group", embedded = false) {
  const isNew = !frame;
  const value = frame || {
    id: "", title: `New ${presetKind}`, traits: frameKindTraits(presetKind),
    basis: "", color: "#2e8b57", coordinate: null, period: null, display: {}
  };
  const recordId = value.id || createId("frame");
  const kind = isNew ? presetKind : frameKind(value);
  const frameLenses = ["intimate", "tactical", "strategic", "wall", "lines", "spiral", "radial"];
  const visibleFrameLenses = new Set(value.display?.lenses || frameLenses);
  const wrapper = document.createElement("form");
  wrapper.className = "frame-form";
  const options = (items, selected) => items.map(([id, label]) =>
    `<option value="${id}" ${id === selected ? "selected" : ""}>${label}</option>`).join("");
  wrapper.innerHTML = `
    <div class="frame-type-banner"><strong>${escapeHTML(value.title)}</strong><span>${kind}</span></div>
    <label class="field"><span>Title</span><input name="title" value="${escapeHTML(value.title)}" required></label>
    <div class="form-row">
      <label class="field"><span>Frame type</span><select name="kind">${options([
        ["calendar", "Calendar / timeline"], ["group", "Group"], ["importance", "Importance"], ["cycle", "Cycle"],
        ["line", "Line"], ["measure", "Measure"], ["other", "Other"]
      ], kind)}</select></label>
      <label class="field"><span>Color</span><input name="color" type="color" value="${escapeHTML(value.color || "#2e8b57")}"></label>
    </div>
    ${kind === "group" ? `<div class="form-row">
      <label class="field"><span>Strategic</span><select name="strategic">${options([
        ["auto", "Automatic"], ["show", "Promote to name"], ["hide", "Demote / hide"]
      ], value.display?.strategic || "auto")}</select></label>
    </div>` : ""}
    ${kind === "importance" ? `<div class="form-row">
      <label class="field"><span>Level</span><select name="importanceLevel">${options([
        ["important", "Important"], ["landmark", "Landmark"], ["standard", "Standard"]
      ], value.display?.importance || "important")}</select></label>
      <label class="field"><span>Smallest radial cycle (days)</span><input name="radialMinDays" type="number" min="0" step="0.25" value="${escapeHTML(value.display?.radialMinDays ?? "")}" placeholder="Any"></label>
      <label class="field"><span>Largest radial cycle (days)</span><input name="radialMaxDays" type="number" min="0" step="0.25" value="${escapeHTML(value.display?.radialMaxDays ?? "")}" placeholder="Any"></label>
    </div>` : ""}
    <div class="field"><span>Visible in lenses</span><div class="check-row frame-lens-checks">
      ${frameLenses.map((lens) => `<label class="check-chip"><input type="checkbox" name="frameLenses" value="${lens}" ${visibleFrameLenses.has(lens) ? "checked" : ""}>${lens}</label>`).join("")}
    </div><small>Unchecked lenses hide events governed by this frame.</small></div>
    <p class="field-note">Choose what appears together from Frames while viewing a calendar. This editor changes the frame itself.</p>
    <label class="field"><span>Basis frame</span><select name="basis"><option value="">None</option>${Object.values(chronolog.frames)
      .filter((item) => item.id !== value.id).map((item) => `<option value="${escapeHTML(item.id)}" ${item.id === value.basis ? "selected" : ""}>${escapeHTML(item.title)} · ${frameKind(item)}</option>`).join("")}</select></label>
    <label class="field"><span>Cycle period data (JSON)</span><textarea name="period" class="code" placeholder="Leave blank to preserve existing period">${escapeHTML(value.period ? JSON.stringify(value.period, null, 2) : "")}</textarea></label>
    <details class="advanced-fields"><summary>Advanced frame data</summary>
      <label class="field"><span>Traits</span><input name="traits" value="${escapeHTML(value.traits.join(", "))}"></label>
      <label class="field"><span>Coordinate nesting (JSON)</span><textarea name="coordinate" class="code">${escapeHTML(value.coordinate ? JSON.stringify(value.coordinate, null, 2) : "")}</textarea></label>
    </details>
    <div class="inspector-actions"><button class="instrument-button primary" type="submit">${isNew ? "Create" : "Apply"}</button>
      ${isNew ? "" : `<button class="instrument-button" id="duplicate-object" type="button">Duplicate</button><button class="instrument-button danger" id="delete-object" type="button">Remove</button>`}</div>`;
  wrapper.addEventListener("submit", (event) => {
    event.preventDefault();
    const data = new FormData(wrapper);
    try {
      executeRecordChange(isNew ? "Create frame" : "Edit frame", "frames", recordId, (documentValue) => {
        const selectedKind = String(data.get("kind") || "other");
        const priorDisplay = documentValue.frames[recordId]?.display || {};
        const display = { ...priorDisplay, ...(data.has("strategic") ? { strategic: String(data.get("strategic") || "auto") } : {}) };
        const selectedLenses = data.getAll("frameLenses").map(String);
        if (selectedLenses.length === frameLenses.length) delete display.lenses;
        else display.lenses = selectedLenses;
        if (data.has("importanceLevel")) {
          display.importance = String(data.get("importanceLevel") || "important");
          if (String(data.get("radialMinDays") || "").trim()) display.radialMinDays = Number(data.get("radialMinDays"));
          else delete display.radialMinDays;
          if (String(data.get("radialMaxDays") || "").trim()) display.radialMaxDays = Number(data.get("radialMaxDays"));
          else delete display.radialMaxDays;
        }
        const existing = documentValue.frames[recordId] || {};
        const schema = preservedFrameSchema(existing, data.get("coordinate"), data.get("period"));
        const payload = {
          ...existing, id: recordId,
          title: String(data.get("title") || "Untitled frame"),
          traits: additiveFrameTraits(
            selectedKind,
            String(data.get("traits") || "").split(",").map((item) => item.trim()).filter(Boolean),
            existing.traits || []
          ),
          basis: String(data.get("basis") || "") || undefined,
          color: String(data.get("color") || "#2e8b57"),
          display,
          ...schema
        };
        if (isNew) addFrame(documentValue, payload);
        else Object.assign(documentValue.frames[recordId], payload);
      });
      if (embedded) toast(`Saved ${String(data.get("title") || "frame")}`);
      else closeInspector();
    } catch (error) {
      toast(error.message, true);
    }
  });
  if (!isNew) {
    wrapper.querySelector("#duplicate-object").addEventListener("click", () => duplicateFrame(value.id));
    wrapper.querySelector("#delete-object").addEventListener("click", () => {
      if (!confirm(`Remove ${value.title}? Placements and frame-specific patterns will be detached.`)) return;
      executeFrameChange("Remove frame", value.id, (documentValue) => {
        delete documentValue.frames[value.id];
        for (const [id, relation] of Object.entries(documentValue.relations)) {
          if (relation.frame === value.id || relation.parent === value.id || relation.child === value.id) delete documentValue.relations[id];
        }
        for (const [id, pattern] of Object.entries(documentValue.patterns)) {
          if (pattern.frame === value.id || pattern.appliesTo?.includes(value.id)) delete documentValue.patterns[id];
        }
      });
      openObjectBrowser("frame");
    });
  }
  return wrapper;
}

function openFrameInspector(frameId = null, presetKind = "group") {
  if (!resolveProvisionalDraft()) return;
  const frame = frameId ? chronolog.frames[frameId] : null;
  session.inspector = { type: "frame", id: frameId };
  openInspector(frame?.title || `New ${presetKind}`, frameForm(frame, presetKind));
}

function patternForm(pattern = null) {
  const isNew = !pattern;
  const value = pattern || {
    id: "",
    title: "New pattern",
    language: "chronolog-formula/1",
    appliesTo: [session.activeFrame],
    frame: session.activeFrame,
    constants: {},
    source: "export fn state(ctx) = {};\nexport fn facts(ctx) = [];\n",
    exports: { state: "state", facts: "facts" }
  };
  const recordId = value.id || createId("pattern");
  const wrapper = document.createElement("form");
  wrapper.innerHTML = `
    <label class="field"><span>Title</span>
      <input name="title" value="${escapeHTML(value.title)}" required>
    </label>
    <label class="field"><span>Applies to frame</span>
      <select name="frame">
        ${Object.values(chronolog.frames).map((frame) => `<option value="${escapeHTML(frame.id)}"
          ${value.appliesTo?.includes(frame.id) ? "selected" : ""}>${escapeHTML(frame.title)}</option>`).join("")}
      </select>
    </label>
    <label class="field"><span>Constants (JSON)</span>
      <textarea name="constants" class="code">${escapeHTML(JSON.stringify(value.constants || {}, null, 2))}</textarea>
    </label>
    <label class="field"><span>chronolog-formula/1 source</span>
      <textarea name="source" class="code">${escapeHTML(value.source)}</textarea>
    </label>
    <div id="pattern-output" style="font:11px/1.4 var(--data);white-space:pre-wrap;color:var(--muted)"></div>
    <div class="inspector-actions">
      <button class="instrument-button" id="test-pattern" type="button">Test query</button>
      <button class="instrument-button primary" type="submit">${isNew ? "Create" : "Apply"}</button>
      ${isNew ? "" : `<button class="instrument-button danger" id="delete-object" type="button">Delete</button>`}
    </div>`;
  const test = () => {
    const output = wrapper.querySelector("#pattern-output");
    try {
      const source = String(new FormData(wrapper).get("source"));
      const module = engine.runtime.compile(source);
      const data = new FormData(wrapper);
      const constants = JSON.parse(String(data.get("constants") || "{}"));
      const at = session.currentFocus().toJSON();
      const state = module.call("state", [{
        frame: String(data.get("frame")),
        atDays: at,
        fromDays: session.window().start.toJSON(),
        toDays: session.window().end.toJSON(),
        constants
      }]);
      output.textContent = `Valid.\n${JSON.stringify(state, null, 2).slice(0, 1800)}`;
      output.style.color = "var(--green)";
    } catch (error) {
      output.textContent = error.message;
      output.style.color = "var(--now)";
    }
  };
  wrapper.querySelector("#test-pattern").addEventListener("click", test);
  wrapper.addEventListener("submit", (event) => {
    event.preventDefault();
    const data = new FormData(wrapper);
    try {
      const source = String(data.get("source"));
      engine.runtime.compile(source);
      const constants = JSON.parse(String(data.get("constants") || "{}"));
      executeRecordChange(isNew ? "Create pattern" : "Edit pattern", "patterns", recordId, (documentValue) => {
        const payload = {
          id: recordId,
          title: String(data.get("title")),
          language: "chronolog-formula/1",
          appliesTo: [String(data.get("frame"))],
          frame: String(data.get("frame")),
          constants,
          source,
          exports: { state: "state", facts: "facts" }
        };
        if (isNew) addPattern(documentValue, payload);
        else Object.assign(documentValue.patterns[recordId], payload);
      });
      openPatternInspector(recordId);
    } catch (error) {
      toast(error.message, true);
    }
  });
  if (!isNew) wrapper.querySelector("#delete-object").addEventListener("click", () => {
    executeRecordChange("Delete pattern", "patterns", value.id, (documentValue) => {
      delete documentValue.patterns[value.id];
    });
    openObjectBrowser("pattern");
  });
  return wrapper;
}

function openPatternInspector(patternId = null) {
  if (!resolveProvisionalDraft()) return;
  const pattern = patternId ? chronolog.patterns[patternId] : null;
  session.inspector = { type: "pattern", id: patternId };
  openInspector(pattern?.title || "New pattern", patternForm(pattern));
}

function groupForm(group = null) {
  const isNew = !group;
  const id = group?.id || createId("frame");
  const wrapper = document.createElement("form");
  wrapper.innerHTML = `
    <label class="field"><span>Group name</span>
      <input name="title" value="${escapeHTML(group?.title || "New group")}" required autofocus>
    </label>
    <label class="field"><span>Color</span>
      <input name="color" type="color" value="${escapeHTML(group?.color || "#2e8b57")}">
    </label>
    <p class="field-note">Groups give events a shared color and their own side line. Assign them from any event.</p>
    <div class="inspector-actions">
      <button class="instrument-button primary" type="submit">${isNew ? "Create group" : "Save group"}</button>
      ${isNew ? "" : `<button class="instrument-button danger" id="delete-object" type="button">Delete group</button>`}
    </div>`;
  wrapper.addEventListener("submit", (event) => {
    event.preventDefault();
    const data = new FormData(wrapper);
    executeRecordChange(isNew ? "Create group" : "Edit group", "frames", id, (documentValue) => {
      documentValue.frames[id] = {
        ...(documentValue.frames[id] || {}),
        id,
        title: String(data.get("title") || "New group"),
        traits: ["set", "group"],
        color: String(data.get("color") || "#2e8b57")
      };
    });
    openObjectBrowser("frame");
  });
  if (!isNew) wrapper.querySelector("#delete-object").addEventListener("click", () => {
    const referenced = Object.values(chronolog.relations).some((relation) => relation.frame === id);
    if (referenced) {
      toast("Remove this group from its events before deleting it.", true);
      return;
    }
    executeRecordChange("Delete group", "frames", id, (documentValue) => {
      delete documentValue.frames[id];
    });
    openObjectBrowser("frame");
  });
  return wrapper;
}

function openGroupInspector(groupId = null) {
  const group = groupId ? chronolog.frames[groupId] : null;
  session.inspector = { type: "frame", id: groupId };
  openInspector(group?.title || "New group", groupForm(group));
}

function legacyObjectBrowser(kind) {
  const records = kind === "frame" ? groupFrames(chronolog) : Object.values(chronolog.patterns);
  const wrapper = document.createElement("div");
  const create = document.createElement("button");
  create.type = "button";
  create.className = "instrument-button primary";
  create.textContent = kind === "frame" ? "Create group" : "Create advanced pattern";
  create.addEventListener("click", () => kind === "frame" ? openGroupInspector() : openPatternInspector());
  wrapper.append(create, document.createElement("hr"));
  for (const record of records) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "event-chip";
    button.textContent = `${record.title || record.id} · ${(record.traits || [record.language]).join(", ")}`;
    button.addEventListener("click", () =>
      kind === "frame" ? openGroupInspector(record.id) : openPatternInspector(record.id)
    );
    wrapper.append(button);
  }
  openInspector(kind === "frame" ? "Groups" : "Advanced patterns", wrapper);
}

const objectBrowserScope = { frame: "all", pattern: "current" };

function patternRelevantToLens(pattern) {
  const window = session.window();
  if (pattern.kind === "ics-rrule") {
    try {
      return engine.recurrenceFacts(pattern, window.start, window.end, 1).length > 0;
    } catch {
      return true;
    }
  }
  return !pattern.appliesTo?.length || pattern.appliesTo.includes(session.activeFrame);
}

function frameRelevantToLens(frame) {
  if (!frame.traits.includes("calendar")) return true;
  if (frame.id === session.activeFrame
    || chronolog.frames[session.activeFrame]?.display?.overlays?.includes(frame.id)) return true;
  const window = session.window();
  if (engine.indexedExplicitFacts(frame.id).some((entry) =>
    entry.day.compare(window.start) >= 0 && entry.day.compare(window.end) <= 0
  )) return true;
  return Object.values(chronolog.patterns).some((pattern) =>
    (pattern.frame === frame.id || pattern.appliesTo?.includes(frame.id)) && patternRelevantToLens(pattern)
  );
}

function frameViewCard() {
  const activeFrameId = session.activeFrame;
  const active = chronolog.frames[activeFrameId];
  const display = active?.display || {};
  const viewCard = document.createElement("section");
  viewCard.className = "frame-view-card";
  const leading = document.createElement("label");
  leading.className = "field";
  const leadingLabel = document.createElement("span");
  leadingLabel.textContent = "Leading frame";
  const leadingSelect = document.createElement("select");
  leadingSelect.id = "frame-leading-select";
  for (const frame of calendarFrames(chronolog)) {
    const option = document.createElement("option");
    option.value = frame.id;
    option.textContent = frame.title;
    option.selected = frame.id === activeFrameId;
    leadingSelect.append(option);
  }
  leadingSelect.addEventListener("change", () => selectLeadingFrame(leadingSelect.value));
  leading.append(leadingLabel, leadingSelect);
  const heading = document.createElement("h3");
  heading.textContent = `Shown with ${active?.title || "active calendar"}`;
  const note = document.createElement("p");
  note.className = "field-note";
  note.textContent = "Events on this calendar bring their groups automatically. Include another calendar or line, force a whole group into this view, or hide a group here.";
  viewCard.append(leading, heading, note);
  const included = new Set(display.overlays || []);
  const related = Object.values(chronolog.frames).filter((frame) => frame.id !== activeFrameId
    && (frame.traits.includes("calendar") || frame.traits.includes("line") || frame.traits.includes("timeline")));
  if (related.length) {
    const label = document.createElement("strong");
    label.className = "fieldset-title";
    label.textContent = "Include calendars and lines";
    const choices = document.createElement("div");
    choices.className = "frame-view-grid";
    for (const frame of related.sort((left, right) => left.title.localeCompare(right.title))) {
      const choice = document.createElement("label");
      choice.className = "check-chip";
      const input = document.createElement("input");
      input.type = "checkbox";
      input.checked = included.has(frame.id);
      input.addEventListener("change", () => {
        executeRecordChange("Change calendar view", "frames", activeFrameId, (documentValue) => {
          const target = documentValue.frames[activeFrameId];
          const overlays = new Set(target.display?.overlays || []);
          if (input.checked) overlays.add(frame.id);
          else overlays.delete(frame.id);
          target.display = { ...(target.display || {}), overlays: [...overlays] };
        }, { viewOnly: true });
      });
      choice.append(input, document.createTextNode(`${frame.title} · ${frameKind(frame)}`));
      choices.append(choice);
    }
    viewCard.append(label, choices);
  }
  const groups = groupFrames(chronolog);
  if (groups.length) {
    const label = document.createElement("strong");
    label.className = "fieldset-title";
    label.textContent = "Groups in this view";
    const groupList = document.createElement("div");
    groupList.className = "frame-group-list";
    for (const group of groups) {
      const row = document.createElement("div");
      row.className = "frame-group-row";
      const name = document.createElement("strong");
      name.textContent = group.title;
      name.style.setProperty("--group-color", group.color || "#2e8b57");
      const presence = document.createElement("select");
      presence.title = `${group.title} in ${active?.title || "this calendar"}`;
      for (const [value, text] of [["auto", "Automatic"], ["show", "Include all"], ["hide", "Hide here"]]) {
        const option = document.createElement("option");
        option.value = value;
        option.textContent = text;
        option.selected = (display.groupModes?.[group.id] || "auto") === value;
        presence.append(option);
      }
      presence.addEventListener("change", () => {
        executeRecordChange("Change group visibility", "frames", activeFrameId, (documentValue) => {
          const target = documentValue.frames[activeFrameId];
          const groupModes = { ...(target.display?.groupModes || {}) };
          if (presence.value === "auto") delete groupModes[group.id];
          else groupModes[group.id] = presence.value;
          target.display = { ...(target.display || {}), groupModes };
        }, { viewOnly: true });
      });
      const strategic = document.createElement("select");
      strategic.title = `${group.title} in Strategic`;
      for (const [value, text] of [["auto", "Strategic: automatic"], ["show", "Strategic: promote"], ["hide", "Strategic: demote"]]) {
        const option = document.createElement("option");
        option.value = value;
        option.textContent = text;
        option.selected = (group.display?.strategic || "auto") === value;
        strategic.append(option);
      }
      strategic.addEventListener("change", () => {
        executeRecordChange("Change strategic priority", "frames", group.id, (documentValue) => {
          const target = documentValue.frames[group.id];
          target.display = { ...(target.display || {}), strategic: strategic.value };
        }, { viewOnly: true });
      });
      row.append(name, presence, strategic);
      groupList.append(row);
    }
    viewCard.append(label, groupList);
  }
  return viewCard;
}

function openObjectBrowser(kind) {
  if (!resolveProvisionalDraft()) return;
  const wrapper = document.createElement("div");
  wrapper.className = "object-browser";
  const toolbar = document.createElement("div");
  toolbar.className = "object-browser-toolbar";
  const search = document.createElement("input");
  search.type = "search";
  search.placeholder = "Filter by name or type";
  const scope = document.createElement("select");
  for (const [value, label] of [["current", "Current lens"], ["all", "All"]]) {
    const option = document.createElement("option");
    option.value = value;
    option.textContent = label;
    option.selected = objectBrowserScope[kind] === value;
    scope.append(option);
  }
  toolbar.append(search, scope);
  wrapper.append(toolbar);
  if (kind === "frame") {
    wrapper.append(frameViewCard());
    const createRow = document.createElement("div");
    createRow.className = "object-create-row";
    for (const [value, label] of [["calendar", "+ Calendar"], ["group", "+ Group"], ["importance", "+ Importance"], ["cycle", "+ Cycle"], ["line", "+ Line"]]) {
      const create = document.createElement("button");
      create.type = "button";
      create.className = `instrument-button${value === "group" ? " primary" : ""}`;
      create.textContent = label;
      create.addEventListener("click", () => openFrameInspector(null, value));
      createRow.append(create);
    }
    wrapper.append(createRow);
  } else {
    const create = document.createElement("button");
    create.type = "button";
    create.className = "instrument-button primary";
    create.textContent = "Create advanced pattern";
    create.addEventListener("click", () => openPatternInspector());
    wrapper.append(create);
  }
  const list = document.createElement("div");
  list.className = "object-list";
  wrapper.append(list);
  const paint = () => {
    objectBrowserScope[kind] = scope.value;
    const query = search.value.trim().toLowerCase();
    let records = kind === "frame" ? Object.values(chronolog.frames) : Object.values(chronolog.patterns);
    if (scope.value === "current") records = records.filter(kind === "frame" ? frameRelevantToLens : patternRelevantToLens);
    records = records.filter((record) => `${record.title || record.id} ${(record.traits || [record.language]).join(" ")}`.toLowerCase().includes(query));
    if (kind === "frame") records.sort((left, right) => frameKind(left).localeCompare(frameKind(right)) || left.title.localeCompare(right.title));
    list.replaceChildren();
    for (const record of records) {
      const row = document.createElement(kind === "frame" ? "details" : "div");
      row.className = `object-row${kind === "frame" ? " frame-expander" : ""}`;
      const edit = document.createElement("button");
      if (kind !== "frame") edit.type = "button";
      edit.className = "object-row-main";
      const type = kind === "frame" ? frameKind(record) : record.kind || "pattern";
      edit.innerHTML = `<span class="object-type">${escapeHTML(type)}</span><strong>${escapeHTML(record.title || record.id)}</strong><small>${escapeHTML(record.id)}</small>`;
      if (kind === "frame") {
        const summary = document.createElement("summary");
        summary.className = "object-row-main";
        summary.innerHTML = edit.innerHTML;
        row.append(summary, frameForm(record, frameKind(record), true));
      } else {
        edit.addEventListener("click", () => openPatternInspector(record.id));
        row.append(edit);
      }
      list.append(row);
    }
    if (!records.length) {
      const empty = document.createElement("p");
      empty.className = "field-note";
      empty.textContent = "Nothing matches this scope.";
      list.append(empty);
    }
  };
  search.addEventListener("input", paint);
  scope.addEventListener("change", paint);
  paint();
  const isFramesBrowser = kind === "frame";
  openInspector(kind === "frame" ? "Frames" : "Patterns", wrapper, isFramesBrowser ? "frames-browser" : "object-browser");
  if (isFramesBrowser) {
    byId("new-frame").setAttribute("aria-expanded", "true");
    // Opening Frames is intentionally passive for the workspace.  Focusing
    // the filter remains useful for keyboard users, but must not ask the
    // browser to scroll the projection or its focused timeline into view.
    search.focus({ preventScroll: true });
  }
}

function refreshFramesPanel() {
  if (inspector.classList.contains("open") && inspector.dataset.panel === "frames-browser") {
    const current = inspectorBody.querySelector(".frame-view-card");
    if (current) current.replaceWith(frameViewCard());
  }
}

function openStapleSuggestions(suggestions) {
  const grouped = new Map();
  for (const suggestion of suggestions) {
    const existing = grouped.get(suggestion.uid) || new Set();
    suggestion.events.forEach((id) => existing.add(id));
    grouped.set(suggestion.uid, existing);
  }
  const wrapper = document.createElement("div");
  const note = document.createElement("p");
  note.style.cssText = "font:12px/1.5 var(--data);color:var(--muted)";
  note.textContent = "Matching ICS UIDs remain distinct. Stapling is explicit and makes one Event carry every attachment.";
  wrapper.append(note);
  for (const [uid, ids] of grouped) {
    const card = document.createElement("section");
    card.style.cssText = "padding:10px 0;border-top:1px solid var(--hair)";
    const title = document.createElement("strong");
    title.style.cssText = "display:block;font:700 11px/1.4 var(--data)";
    title.textContent = uid;
    const detail = document.createElement("div");
    detail.style.cssText = "margin:4px 0 8px;color:var(--muted);font:11px/1.4 var(--data)";
    detail.textContent = [...ids]
      .map((id) => chronolog.events[id]?.payload?.title || id)
      .join(" · ");
    const button = document.createElement("button");
    button.type = "button";
    button.className = "instrument-button";
    button.textContent = "Staple these identities";
    button.addEventListener("click", () => {
      const eventIds = [...ids].filter((id) => chronolog.events[id]);
      if (eventIds.length < 2) {
        card.remove();
        return;
      }
      executeEventSetChange("Staple matching ICS identities", eventIds, (documentValue) => {
        stapleEvents(documentValue, eventIds);
      });
      card.remove();
      toast("Stapled matching identities.");
    });
    card.append(title, detail, button);
    wrapper.append(card);
  }
  openInspector("Staple suggestions", wrapper);
}

function createEventAt(startDay, endDay = startDay) {
  resolveProvisionalDraft();
  store.beginDeferred();
  const eventId = createId("event");
  const relationId = createId("relation");
  const start = Rational.parse(startDay);
  const end = Rational.parse(endDay);
  const orderedStart = start.compare(end) <= 0 ? start : end;
  let orderedEnd = start.compare(end) <= 0 ? end : start;
  if (orderedEnd.compare(orderedStart) === 0) {
    orderedEnd = orderedStart.add(session.currentLens() === "intimate"
      ? Rational.parse(session.intimateGrain).div(1440)
      : 1);
  }
  try {
    executeEventChange("Create event", eventId, (documentValue) => {
      const event = addEvent(documentValue, {
        id: eventId,
        traits: ["event"],
        magnitudes: {
          duration: durationMagnitude(orderedEnd.sub(orderedStart).mul(86400).toJSON(), "second")
        },
        payload: { title: "New event", description: "", location: "" }
      });
      addRelation(documentValue, {
        id: relationId,
        type: "attachment",
        event: event.id,
        frame: session.activeFrame,
        role: "placed",
        coordinate: daysToCivilCoordinate(orderedStart)
      });
    }, true);
    provisionalEvent = { id: eventId, dirty: false, form: null };
    if (!openEventInspector(eventId)) {
      discardProvisionalDraft();
      dismissInspector();
    }
  } catch (error) {
    if (provisionalEvent?.id === eventId) discardProvisionalDraft();
    else store.endDeferred();
    toast(`Could not create event: ${error.message}`, true);
  }
}

let zoomWheel = 0;
let panWheel = 0;
let radialWheelAnimation = null;

function animateRadialWheel(delta) {
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
    scheduleRender();
    if (progress < 1) {
      animation.frame = requestAnimationFrame(advance);
    } else {
      session.setFocus(animation.target);
      radialWheelAnimation = null;
      scheduleRender();
      requestAnimationFrame(() => requestAnimationFrame(() => {
        if (!radialWheelAnimation) document.body.classList.remove("radial-wheel-motion");
      }));
    }
  };
  radialWheelAnimation.frame = requestAnimationFrame(advance);
}

function prepareIntimateZoom(value, pointerOffset = null) {
  const scroll = projection.querySelector(".intimate-scroll");
  const offset = pointerOffset ?? scroll?.clientHeight / 2 ?? projection.clientHeight / 2;
  const hourPixels = Number(scroll?.dataset.hourPixels || session.intimateHourPixels);
  const bufferHours = Number(scroll?.dataset.bufferHours || 24);
  const headerPixels = Number(scroll?.dataset.headerPixels || 70);
  const localHour = scroll
    ? (scroll.scrollTop + offset - headerPixels) / hourPixels - bufferHours
    : (session.intimateStartHour + session.intimateEndHour) / 2;
  pendingIntimateRebase = null;
  pendingIntimateZoom = { localHour, offset, left: scroll?.scrollLeft || 0 };
  session.setIntimateHourPixels(value);
}

function adjustWindow(steps) {
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
  if (session.currentLens() === "intimate" && !event.ctrlKey && !event.metaKey) return;
  event.preventDefault();
  if (event.ctrlKey || event.metaKey) {
    if (session.currentLens() === "intimate") {
      const scroll = projection.querySelector(".intimate-scroll");
      const offset = scroll
        ? Math.max(0, Math.min(scroll.clientHeight, event.clientY - scroll.getBoundingClientRect().top))
        : null;
      prepareIntimateZoom(session.intimateHourPixels * Math.exp(-event.deltaY * 0.002), offset);
      scheduleRender();
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
  scheduleRender();
}

document.querySelectorAll("[data-lens]").forEach((button) => {
  button.addEventListener("click", () => {
    session.setLens(button.dataset.lens);
    scheduleRender();
  }, true);
});

byId("active-calendar").addEventListener("change", (event) => {
  selectLeadingFrame(event.target.value);
});

byId("shared-focus").addEventListener("change", (event) => {
  session.toggleShared(event.target.checked);
  scheduleRender();
});

function goToToday() {
  const now = new Date();
  session.setFocus(new Rational(daysFromCivil(
    BigInt(now.getFullYear()), BigInt(now.getMonth() + 1), BigInt(now.getDate())
  )));
  if (session.currentLens() === "intimate") {
    const scroll = projection.querySelector(".intimate-scroll");
    pendingIntimateZoom = {
      localHour: now.getHours() + now.getMinutes() / 60,
      offset: scroll?.clientHeight / 2 || projection.clientHeight / 2,
      left: scroll?.scrollLeft || 0
    };
  }
}

byId("undo").addEventListener("click", () => history.undo());
byId("redo").addEventListener("click", () => history.redo());
byId("close-inspector").addEventListener("click", closeInspector);
byId("new-event").addEventListener("click", () => createEventAt(session.currentFocus()));
byId("new-frame").addEventListener("click", () => {
  if (inspector.classList.contains("open") && inspector.dataset.panel === "frames-browser") {
    closeInspector();
    return;
  }
  openObjectBrowser("frame");
});
byId("new-pattern").addEventListener("click", () => openObjectBrowser("pattern"));
byId("theme-settings").addEventListener("click", () => {
  byId("app-menu").open = false;
  openThemeEditor();
});

document.addEventListener("pointerdown", (event) => {
  if (!provisionalEvent || !inspector.classList.contains("open") || inspector.contains(event.target)) return;
  closeInspector();
});

projection.addEventListener("wheel", panFromWheel, { passive: false });

// Keep the browser's scroll position continuous when the finite Intimate rail
// is recentered.  This has to happen in the same scroll task: deferring the
// replacement to another animation frame lets the user see the rail pause at
// its seam (usually near a midnight marker).
function rebaseIntimateScroll(scroll, direction) {
  const hourPixels = Number(scroll.dataset.hourPixels || 56);
  const dayPixels = hourPixels * 24;
  pendingIntimateRebase = {
    top: Math.max(0, scroll.scrollTop - direction * dayPixels),
    left: scroll.scrollLeft
  };
  session.move(direction);
  render();
}

projection.addEventListener("scroll", (event) => {
  const scroll = event.target;
  if (!(scroll instanceof HTMLElement)
    || !scroll.classList.contains("intimate-scroll")
    || intimateScrollGuard
    || pendingIntimateRebase
    || pendingIntimateZoom) return;
  const hourPixels = Number(scroll.dataset.hourPixels || 56);
  const edge = hourPixels * 6;
  if (scroll.scrollTop < edge) {
    rebaseIntimateScroll(scroll, -1);
  } else if (scroll.scrollTop + scroll.clientHeight > scroll.scrollHeight - edge) {
    rebaseIntimateScroll(scroll, 1);
  }
}, true);

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
      const timelineDays = Number(cell.dataset.timelineHours || 24) / 24;
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
  dragPreview.textContent = `${title}\nâ†’ ${formatCivil(daysToCivilCoordinate(destination), true)}`;
  dragPreview.dataset.valid = "true";
}

function destinationForDrop(cell, clientX, clientY, sourceDay) {
  if (cell.dataset.timelineStart) {
    const start = Rational.parse(cell.dataset.timelineStart);
    const bounds = cell.getBoundingClientRect();
    const totalMinutes = Number(cell.dataset.timelineHours || 24) * 60;
    const fraction = Math.max(0, Math.min(0.999999, (clientY - bounds.top) / bounds.height));
    const minute = Math.round(fraction * totalMinutes / session.intimateGrain) * session.intimateGrain;
    return start.add(Rational.parse(Math.min(totalMinutes - session.intimateGrain, minute)).div(1440));
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
    const timelineMinutes = Number(cell.dataset.timelineHours || 24) * 60;
    const minute = Math.min(
      timelineMinutes - session.intimateGrain,
      Math.max(0, Math.round(fraction * timelineMinutes / session.intimateGrain) * session.intimateGrain)
    );
    return timelineStart.add(Rational.parse(minute).div(1440));
  }
  const source = Rational.parse(sourceDay);
  return base.add(source.sub(source.floor()));
}

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
    durationDays: magnitudeDays(chronolog.events[item.dataset.eventId]?.magnitudes?.duration).toNumber(),
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
  const nextCoordinate = daysToCivilCoordinate(destination);
  const timedDrop = cell.classList.contains("intimate-day-column");
  if (drag.virtualId) {
    const fact = findVisibleFact(drag.virtualId, drag.sourceDay);
    if (!fact) {
      toast("That recurring occurrence could not be resolved for moving.", true);
      return;
    }
    const prepared = prepareMaterialization(fact, nextCoordinate);
    if (timedDrop) {
      prepared.relation.parameters ||= {};
      prepared.relation.parameters.dateOnly = false;
    }
    history.executeDelta(
      "Move recurring occurrence",
      (documentValue) => applyMaterialization(documentValue, prepared),
      (documentValue) => revertMaterialization(documentValue, prepared),
      { preserveRecurrence: true }
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
      executeEventChange("Restore recurring occurrence", draggedEventId, (documentValue) => {
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
  const previousCoordinate = clone(chronolog.relations[drag.relationId].coordinate);
  const previousParameters = clone(chronolog.relations[drag.relationId].parameters);
  history.executeDelta("Move event", (documentValue) => {
    const relation = documentValue.relations[drag.relationId];
    if (!relation) throw new Error("The event placement no longer exists");
    relation.coordinate = clone(nextCoordinate);
    if (timedDrop) {
      relation.parameters ||= {};
      relation.parameters.dateOnly = false;
    }
  }, (documentValue) => {
    const relation = documentValue.relations[drag.relationId];
    if (!relation) return;
    relation.coordinate = clone(previousCoordinate);
    if (previousParameters === undefined) delete relation.parameters;
    else relation.parameters = clone(previousParameters);
  }, { preserveRecurrence: true });
});

projection.addEventListener("pointercancel", () => clearEventDrag());

let createDrag = null;
let createPreview = null;
function clearCreateDragPreview() {
  createPreview?.remove();
  createPreview = null;
  for (const cell of createDrag?.rangeCells || []) cell.classList.remove("create-range");
  document.body.classList.remove("calendar-panning");
}
projection.addEventListener("pointerdown", (event) => {
  if (!event.shiftKey && event.target.closest("[data-event-id],button")) return;
  const cell = event.target.closest("[data-create-day],[data-drop-start]");
  if (!cell) return;
  const start = destinationForDrop(cell, event.clientX, event.clientY, cell.dataset.createDay);
  createDrag = {
    pointerId: event.pointerId,
    start,
    startX: event.clientX,
    startY: event.clientY,
    startFocus: session.currentFocus(),
    startScrollTop: projection.querySelector(".intimate-scroll")?.scrollTop || 0,
    startScrollLeft: projection.querySelector(".intimate-scroll")?.scrollLeft || 0,
    pan: event.shiftKey,
    active: false,
    rangeCells: [...projection.querySelectorAll("[data-create-day]")]
  };
  event.preventDefault();
  if (createDrag.pan) document.body.classList.add("calendar-panning");
  projection.setPointerCapture?.(event.pointerId);
});
projection.addEventListener("pointermove", (event) => {
  if (!createDrag || createDrag.pointerId !== event.pointerId) return;
  const dx = event.clientX - createDrag.startX;
  const dy = event.clientY - createDrag.startY;
  if (!createDrag.active && Math.hypot(dx, dy) < 5) return;
  createDrag.active = true;
  event.preventDefault();
  if (createDrag.pan) {
    if (session.currentLens() === "intimate") {
      const scroll = projection.querySelector(".intimate-scroll");
      if (scroll) {
        scroll.scrollTop = createDrag.startScrollTop - dy;
        scroll.scrollLeft = createDrag.startScrollLeft - dx;
      }
      return;
    }
    const bounds = projection.getBoundingClientRect();
    const gesture = Math.abs(dx) >= Math.abs(dy) ? dx / Math.max(1, bounds.width) : -dy / Math.max(1, bounds.height);
    session.setFocus(createDrag.startFocus.sub(Rational.parse(String(gesture * session.visibleSpan()))));
    scheduleRender();
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
  const duration = end.sub(createDrag.start).abs().mul(24).toNumber();
  createPreview.style.left = `${Math.min(innerWidth - 260, event.clientX + 16)}px`;
  createPreview.style.top = `${Math.min(innerHeight - 80, event.clientY + 16)}px`;
  if (!(cell instanceof SVGElement)) {
    if (createPreview.parentElement !== cell) cell.append(createPreview);
    createPreview.classList.add("cell-preview");
    createPreview.style.left = "4px";
    createPreview.style.right = "4px";
    createPreview.style.top = cell.classList.contains("intimate-day-column")
      ? `${(createDrag.start.compare(end) <= 0 ? createDrag.start : end).sub(Rational.parse(cell.dataset.timelineStart || cell.dataset.createDay)).toNumber() / (Number(cell.dataset.timelineHours || 24) / 24) * 100}%`
      : "28px";
    createPreview.style.height = cell.classList.contains("intimate-day-column")
      ? `${Math.max(.75, Math.min(100, duration / Number(cell.dataset.timelineHours || 24) * 100))}%`
      : "auto";
  }
  const firstDay = createDrag.start.floor() < end.floor() ? createDrag.start.floor() : end.floor();
  const lastDay = createDrag.start.floor() > end.floor() ? createDrag.start.floor() : end.floor();
  for (const rangeCell of createDrag.rangeCells) {
    const day = BigInt(rangeCell.dataset.createDay);
    rangeCell.classList.toggle("create-range", day >= firstDay && day <= lastDay);
  }
  createPreview.textContent = `New event\n${formatCivil(daysToCivilCoordinate(createDrag.start), true)} · ${duration < 1 ? `${Math.round(duration * 60)} min` : `${duration.toFixed(1)} hr`}`;
});
projection.addEventListener("pointerup", (event) => {
  if (!createDrag || createDrag.pointerId !== event.pointerId) return;
  const drag = createDrag;
  clearCreateDragPreview();
  createDrag = null;
  if (drag.pan) {
    const scroll = projection.querySelector(".intimate-scroll");
    if (scroll) viewScroll.set("intimate", { top: scroll.scrollTop, left: scroll.scrollLeft });
    panWheel = 0;
    return;
  }
  const cell = document.elementFromPoint(event.clientX, event.clientY)?.closest?.("[data-create-day]")
    || event.target.closest?.("[data-create-day]");
  if (!cell) return;
  let end = destinationForDrop(cell, event.clientX, event.clientY, drag.start.toJSON());
  if (!cell.classList.contains("intimate-day-column")) end = new Rational(end.floor() + 1n);
  suppressEventClick = drag.active;
  createEventAt(drag.start, end);
});
projection.addEventListener("pointercancel", () => {
  clearCreateDragPreview();
  createDrag = null;
  panWheel = 0;
});

projection.addEventListener("click", (event) => {
  if (suppressEventClick) {
    suppressEventClick = false;
    event.preventDefault();
    return;
  }
  const item = event.target.closest("[data-event-id]");
  if (!item) return;
  event.stopPropagation();
  if (item.dataset.virtualId) openVirtualInspector(item.dataset.virtualId);
  else openEventInspector(item.dataset.eventId);
});

minimap.addEventListener("pointerdown", (event) => {
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
  scheduleRender();
});

minimap.addEventListener("pointermove", (event) => {
  if (!session.minimapDrag || !minimap.hasPointerCapture?.(event.pointerId)) return;
  const bounds = minimap.getBoundingClientRect();
  const fraction = (event.clientX - bounds.left) / bounds.width;
  session.setFocus(minimapDragFocus(session.minimapDrag, fraction));
  scheduleRender();
});

minimap.addEventListener("pointerup", () => {
  if (!session.minimapDrag) return;
  session.minimapDrag = null;
  scheduleRender();
});

minimap.addEventListener("pointercancel", () => {
  if (!session.minimapDrag) return;
  session.minimapDrag = null;
  scheduleRender();
});

byId("open-document").addEventListener("click", async () => {
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
    replaceDocument(parseDocument(await file.text()), { handle, filename: file.name });
    toast(`Opened ${file.name} · autosave attached`);
  } catch (error) {
    if (error.name !== "AbortError") toast(error.message, true);
  }
});
byId("document-file").addEventListener("change", async (event) => {
  const file = event.target.files?.[0];
  if (!file) return;
  try {
    replaceDocument(parseDocument(await file.text()), LOCAL_WORKSPACE_TARGET);
    toast(`Opened ${file.name} · autosave attached to the local workspace`);
  } catch (error) {
    toast(error.message, true);
  } finally {
    event.target.value = "";
  }
});

byId("save-document").addEventListener("click", async () => {
  try {
    if (!store.handle && !store.remoteUrl && LOCAL_WORKSPACE_TARGET.remoteUrl) {
      store.attach(chronolog, LOCAL_WORKSPACE_TARGET);
      store.markDirty();
    }
    if (store.handle || store.remoteUrl) await store.save(true);
    else if (globalThis.showSaveFilePicker) await store.chooseFile();
    else store.download("chronolog.chronolog");
  } catch (error) {
    if (error.name !== "AbortError") toast(error.message, true);
  }
});

byId("save-as-document").addEventListener("click", async () => {
  try {
    if (globalThis.showSaveFilePicker) await store.chooseFile();
    else store.download("chronolog.chronolog");
  } catch (error) {
    if (error.name !== "AbortError") toast(error.message, true);
  }
});

const IMPORT_MAPS = ["frames", "events", "patterns", "relations", "overrides"];

function importCalendar(text, label) {
  const beforeIds = Object.fromEntries(
    IMPORT_MAPS.map((name) => [name, new Set(Object.keys(chronolog[name]))])
  );
  const hadIcs = Object.prototype.hasOwnProperty.call(chronolog.foreign, "ics");
  const beforeSourceIds = new Set(Object.keys(chronolog.foreign.ics?.sources || {}));
  let additions = null;
  let addedSources = null;
  let result = null;

  const removeNewEntries = (documentValue) => {
    for (const name of IMPORT_MAPS) {
      const ids = additions ? Object.keys(additions[name]) : Object.keys(documentValue[name])
        .filter((id) => !beforeIds[name].has(id));
      for (const id of ids) delete documentValue[name][id];
    }
    const sourceIds = addedSources ? Object.keys(addedSources) : Object.keys(
      documentValue.foreign.ics?.sources || {}
    ).filter((id) => !beforeSourceIds.has(id));
    for (const id of sourceIds) delete documentValue.foreign.ics?.sources?.[id];
    if (!hadIcs && !Object.keys(documentValue.foreign.ics?.sources || {}).length) {
      delete documentValue.foreign.ics;
    }
  };

  const apply = (documentValue) => {
    if (additions) {
      for (const name of IMPORT_MAPS) Object.assign(documentValue[name], additions[name]);
      documentValue.foreign.ics ||= { sources: {} };
      documentValue.foreign.ics.sources ||= {};
      Object.assign(documentValue.foreign.ics.sources, addedSources);
      return;
    }
    try {
      result = importICS(text, documentValue, { label });
      additions = Object.fromEntries(IMPORT_MAPS.map((name) => [
        name,
        Object.fromEntries(Object.entries(documentValue[name]).filter(([id]) => !beforeIds[name].has(id)))
      ]));
      addedSources = Object.fromEntries(Object.entries(documentValue.foreign.ics?.sources || {})
        .filter(([id]) => !beforeSourceIds.has(id)));
    } catch (error) {
      removeNewEntries(documentValue);
      throw error;
    }
  };

  history.executeDelta(
    `Import ${label}`,
    apply,
    (documentValue) => removeNewEntries(documentValue)
  );
  return result;
}

byId("import-ics").addEventListener("click", () => byId("ics-file").click());
byId("ics-file").addEventListener("change", async (event) => {
  for (const file of event.target.files || []) {
    try {
      const text = await file.text();
      const result = importCalendar(text, file.name.replace(/\.ics$/i, ""));
      selectLeadingFrame(result.frames[0] || session.activeFrame);
      toast(
        `Imported ${result.events.length} items from ${file.name}`
        + (result.suggestions.length ? ` · ${result.suggestions.length} staple suggestion(s)` : "")
        + (result.warnings.length ? ` · ${result.warnings.length} warning(s): ${result.warnings[0]}` : "")
      );
      if (result.suggestions.length) openStapleSuggestions(result.suggestions);
    } catch (error) {
      toast(`${file.name}: ${error.message}`, true);
    }
  }
  event.target.value = "";
  scheduleRender();
});

byId("export-ics").addEventListener("click", () => {
  try {
    const window = session.window();
    const text = exportICS(chronolog, {
      frame: session.activeFrame,
      start: daysToCivilCoordinate(window.start),
      end: daysToCivilCoordinate(window.end),
      engine
    });
    const title = chronolog.frames[session.activeFrame]?.title || "calendar";
    downloadText(text, `${title.replace(/[^\w.-]+/g, "-")}.ics`, "text/calendar");
    toast("Exported the visible calendar window.");
  } catch (error) {
    toast(error.message, true);
  }
});

window.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && inspector.classList.contains("open")) {
    event.preventDefault();
    closeInspector();
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
  else if (event.key === "+" || event.key === "=") adjustWindow(-1);
  else if (event.key === "-") adjustWindow(1);
  else if (event.key.toLowerCase() === "n") {
    createEventAt(session.currentFocus());
    return;
  } else if (/^[1-7]$/.test(event.key)) {
    session.setLens(["intimate", "tactical", "strategic", "wall", "lines", "spiral", "radial"][Number(event.key) - 1]);
  } else return;
  event.preventDefault();
  scheduleRender();
});

window.addEventListener("beforeunload", (event) => {
  if (store.revision !== store.savedRevision) {
    event.preventDefault();
    event.returnValue = "";
  }
});

async function loadWorkspaceDocument() {
  store.status("loading", "Loading workspace document…");
  try {
    const response = await fetch(WORKSPACE_TARGET.remoteUrl, { cache: "no-store" });
    if (response.status === 404) {
      store.attach(chronolog, WORKSPACE_TARGET);
      toast("No workspace document found; starting a new chronolog.chronolog file.");
      return;
    }
    if (!response.ok) throw new Error(await response.text() || `Open returned ${response.status}`);
    const loadedName = response.headers.get("x-chronolog-file") || "chronolog.chronolog";
    replaceDocument(parseDocument(await response.text()), WORKSPACE_TARGET);
    toast(loadedName === "chronolog.json"
      ? "Auto-loaded legacy chronolog.json · next autosave migrates to chronolog.chronolog"
      : `Auto-loaded ${loadedName}`);
  } catch (error) {
    store.attach(chronolog, LOCAL_WORKSPACE_TARGET);
    toast(`Workspace autoload unavailable: ${error.message}`, true);
  } finally {
    documentLoading = false;
  }
}

render();
await loadWorkspaceDocument();
const validation = validateDocument(chronolog);
if (!validation.valid) toast(validation.errors.join(" · "), true);
render();
