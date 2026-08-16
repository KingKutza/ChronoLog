import {
  Rational,
  coordinate,
  daysFromCivil,
  daysToCivilCoordinate
} from "./exact.js";
import { normalizeRadialGuideValues, positiveRadialCycle } from "./radial.js";

const DETENTS = [
  { name: "Intimate", scale: 0, span: 5 },
  { name: "Tactical", scale: 1, span: 21 },
  { name: "Strategic", scale: 2, span: 274 }
];

function interpolateLog(left, right, amount) {
  return Math.exp(Math.log(left) + (Math.log(right) - Math.log(left)) * amount);
}

export function spanForScale(scale) {
  const value = Math.max(0, Math.min(2, Number(scale)));
  if (value <= 1) return interpolateLog(DETENTS[0].span, DETENTS[1].span, value);
  return interpolateLog(DETENTS[1].span, DETENTS[2].span, value - 1);
}

export function scaleForSpan(span) {
  const value = Math.max(1, Number(span));
  if (value <= DETENTS[1].span) {
    return Math.log(value / DETENTS[0].span) / Math.log(DETENTS[1].span / DETENTS[0].span);
  }
  return 1 + Math.log(value / DETENTS[1].span) / Math.log(DETENTS[2].span / DETENTS[1].span);
}

const PROJECTIONS = ["calendar", "wall", "lines", "radial"];
// This is deliberately a small registry rather than a collection of special
// cases in the toolbar.  A future lens needs one entry here plus a renderer;
// persisted workspaces then get its default position without losing a user's
// existing ordering.
export const LENS_CATALOG = Object.freeze({
  intimate: Object.freeze({ title: "Intimate", projection: "calendar", capabilities: ["continuous-scroll", "vertical-zoom", "time-window", "zones"] }),
  tactical: Object.freeze({ title: "Tactical", projection: "calendar", capabilities: ["grid-window", "zones"] }),
  strategic: Object.freeze({ title: "Strategic", projection: "calendar", capabilities: ["month-window", "density", "zones"] }),
  wall: Object.freeze({ title: "Wall", projection: "wall", capabilities: ["month-window", "record-slashes", "zones"] }),
  lines: Object.freeze({ title: "Lines", projection: "lines", capabilities: ["topology", "time-window"] }),
  spiral: Object.freeze({ title: "Spiral", projection: "radial", capabilities: ["cycle", "radial-guides", "labels"] }),
  radial: Object.freeze({ title: "Radial", projection: "radial", capabilities: ["cycle", "radial-guides", "labels"] })
});
export const DEFAULT_LENS_ORDER = Object.freeze(Object.keys(LENS_CATALOG));
const LENSES = DEFAULT_LENS_ORDER;
const RADIAL_MODES = ["spiral", "concentric"];
const INTIMATE_HOUR_PIXELS_MIN = 8;
const INTIMATE_HOUR_PIXELS_MAX = 144;

export function sanitizeSessionParameters(parameters, chronologDocument) {
  const frames = chronologDocument?.frames || {};
  const input = {};
  const frame = parameters.get("frame");
  if (frame && frames[frame]) {
    input.activeFrame = frame;
  }
  const projection = parameters.get("projection");
  if (PROJECTIONS.includes(projection)) input.projection = projection;
  if (parameters.has("scale")) {
    const scale = Number(parameters.get("scale"));
    if (Number.isFinite(scale)) input.scale = Math.max(0, Math.min(2, scale));
  }
  const radialMode = parameters.get("radial");
  if (RADIAL_MODES.includes(radialMode)) input.radialMode = radialMode;
  return input;
}

export function normalizeLensWorkspace(input = {}) {
  const requestedOrder = Array.isArray(input.lensOrder) ? input.lensOrder : [];
  const requestedEnabled = Array.isArray(input.enabledLenses) ? input.enabledLenses : null;
  const order = [...requestedOrder, ...DEFAULT_LENS_ORDER]
    .filter((lens, index, values) => Object.hasOwn(LENS_CATALOG, lens) && values.indexOf(lens) === index);
  const enabled = (requestedEnabled || DEFAULT_LENS_ORDER)
    .filter((lens, index, values) => Object.hasOwn(LENS_CATALOG, lens) && values.indexOf(lens) === index);
  // A workspace without a reachable projection is not useful. Restore the
  // first ordered lens instead of silently retaining a dead toolbar.
  if (!enabled.length) enabled.push(order[0] || DEFAULT_LENS_ORDER[0]);
  return { lensOrder: order, enabledLenses: enabled };
}

export function minimapDragState(input) {
  const start = Rational.parse(input.start);
  const span = Rational.parse(input.end).sub(start);
  const focus = Rational.parse(input.focus);
  const fraction = Math.max(0, Math.min(1, Number(input.fraction)));
  const positive = span.compare(0) > 0;
  const focusFraction = positive ? focus.sub(start).div(span).toNumber() : 0.5;
  const thumbHalf = positive ? Number(input.visibleSpan) / span.toNumber() / 2 : 0;
  const grabbed = Math.abs(fraction - focusFraction) <= thumbHalf;
  const drag = { start, span, grabOffset: grabbed ? fraction - focusFraction : 0 };
  drag.focus = grabbed ? focus : minimapDragFocus(drag, fraction);
  return drag;
}

export function minimapDragFocus(drag, fraction) {
  const clamped = Math.max(0, Math.min(1, Number(fraction) - drag.grabOffset));
  return drag.start.add(drag.span.mul(String(clamped)));
}

function todayDays() {
  const date = new Date();
  return new Rational(daysFromCivil(
    BigInt(date.getFullYear()),
    BigInt(date.getMonth() + 1),
    BigInt(date.getDate())
  )).add(Rational.parse(date.getHours()).div(24))
    .add(Rational.parse(date.getMinutes()).div(1440));
}

export class ViewSession {
  constructor(input = {}) {
    const lensWorkspace = normalizeLensWorkspace(input);
    this.projection = input.projection || "calendar";
    this.lensOrder = lensWorkspace.lensOrder;
    this.enabledLenses = lensWorkspace.enabledLenses;
    this.scale = Number(input.scale ?? 1);
    this.sharedFocus = input.sharedFocus !== false;
    this.focusDays = Rational.parse(input.focusDays || todayDays());
    this.localFocus = Object.fromEntries(
      Object.entries(input.localFocus || {}).map(([key, value]) => [key, Rational.parse(value)])
    );
    this.activeFrame = input.activeFrame || "calendar:personal";
    this.activeCycle = input.activeCycle || "cycle:lunar";
    this.radialMode = input.radialMode || "spiral";
    this.radialPast = Math.max(0, Math.floor(Number(input.radialPast ?? 1)));
    this.radialFuture = Math.max(0, Math.floor(Number(input.radialFuture ?? 1)));
    this.radialCycle = positiveRadialCycle(input.radialCycle || "29.530588853");
    const radialGuide = normalizeRadialGuideValues({
      radialCycle: this.radialCycle,
      radialDivisions: input.radialDivisions ?? 0,
      radialMajorEvery: input.radialMajorEvery ?? 0
    });
    this.radialDivisions = radialGuide.radialDivisions;
    this.radialMajorEvery = radialGuide.radialMajorEvery;
    this.radialMarks = ["auto", "plain", "day-night"].includes(input.radialMarks) ? input.radialMarks : "auto";
    this.intimateBack = Math.max(0, Math.floor(Number(input.intimateBack ?? 1)));
    this.intimateForward = Math.max(0, Math.floor(Number(input.intimateForward ?? 3)));
    this.intimateGrain = [15, 30, 60].includes(Number(input.intimateGrain))
      ? Number(input.intimateGrain)
      : 15;
    this.intimateHourPixels = Math.max(
      INTIMATE_HOUR_PIXELS_MIN,
      Math.min(INTIMATE_HOUR_PIXELS_MAX, Number(input.intimateHourPixels) || 28)
    );
    this.intimateStartHour = Math.max(0, Math.min(23, Math.floor(Number(input.intimateStartHour ?? 0))));
    this.intimateEndHour = Math.max(this.intimateStartHour + 1, Math.min(24, Math.floor(Number(input.intimateEndHour ?? 24))));
    this.tacticalRows = Math.max(1, Math.floor(Number(input.tacticalRows ?? 3)));
    this.tacticalColumns = Math.max(1, Math.floor(Number(input.tacticalColumns ?? 7)));
    this.strategicMonths = Math.max(1, Math.floor(Number(input.strategicMonths ?? 9)));
    this.strategicMode = ["signal", "blocks", "all"].includes(input.strategicMode)
      ? input.strategicMode
      : "signal";
    this.intimateZoneFill = input.intimateZoneFill ?? input.zoneFill ?? true;
    this.tacticalZoneFill = input.tacticalZoneFill ?? input.zoneFill ?? true;
    this.strategicZoneFill = input.strategicZoneFill ?? input.zoneFill ?? true;
    this.wallZoneFill = input.wallZoneFill ?? input.zoneFill ?? true;
    this.wallMonths = Math.max(1, Math.floor(Number(input.wallMonths ?? 3)));
    this.linesMonths = Math.max(1, Math.floor(Number(input.linesMonths ?? 9)));
    this.linesDays = Math.max(3, Math.floor(Number(input.linesDays ?? 14)));
    this.strategicDetail = Boolean(input.strategicDetail ?? false);
    this.wallDetail = Boolean(input.wallDetail ?? input.detail);
    this.strategicRecordSlashes = Boolean(input.strategicRecordSlashes ?? input.recordSlashes);
    this.wallRecordSlashes = Boolean(input.wallRecordSlashes ?? input.recordSlashes);
    this.radialLabels = input.radialLabels !== false;
    this.selection = input.selection || null;
    this.inspector = input.inspector || null;
    this.minimapDrag = null;
  }

  currentFocus() {
    return this.sharedFocus
      ? this.focusDays
      : this.localFocus[this.projection] || this.focusDays;
  }

  setFocus(value) {
    const next = Rational.parse(value);
    if (this.sharedFocus) this.focusDays = next;
    else this.localFocus[this.projection] = next;
  }

  setLeadingFrame(frameId) {
    if (typeof frameId === "string" && frameId) this.activeFrame = frameId;
  }

  move(days) {
    this.setFocus(this.currentFocus().add(days));
  }

  setIntimateHourPixels(value) {
    this.intimateHourPixels = Math.max(
      INTIMATE_HOUR_PIXELS_MIN,
      Math.min(INTIMATE_HOUR_PIXELS_MAX, Number(value) || this.intimateHourPixels)
    );
  }

  setProjection(projection) {
    if (projection === this.projection) return;
    const current = this.currentFocus();
    if (!this.sharedFocus) this.localFocus[this.projection] = current;
    this.projection = projection;
    if (!this.sharedFocus && !this.localFocus[projection]) {
      this.localFocus[projection] = current;
    }
  }

  currentLens() {
    if (this.projection === "radial") return this.radialMode === "spiral" ? "spiral" : "radial";
    if (this.projection !== "calendar") return this.projection;
    if (this.scale < 0.55) return "intimate";
    if (this.scale < 1.45) return "tactical";
    return "strategic";
  }

  setLens(lens) {
    if (!LENSES.includes(lens) || !this.enabledLenses.includes(lens)) return;
    if (lens === "intimate") {
      this.setProjection("calendar");
      this.scale = 0;
    } else if (lens === "tactical") {
      this.setProjection("calendar");
      this.scale = 1;
    } else if (lens === "strategic") {
      this.setProjection("calendar");
      this.scale = 2;
    } else if (lens === "spiral") {
      this.radialMode = "spiral";
      this.setProjection("radial");
    } else if (lens === "radial") {
      this.radialMode = "concentric";
      this.setProjection("radial");
    } else {
      this.setProjection(lens);
    }
  }

  availableLenses() {
    return this.lensOrder.filter((lens) => this.enabledLenses.includes(lens));
  }

  configureLenses(input = {}) {
    const workspace = normalizeLensWorkspace({
      lensOrder: input.lensOrder ?? this.lensOrder,
      enabledLenses: input.enabledLenses ?? this.enabledLenses
    });
    this.lensOrder = workspace.lensOrder;
    this.enabledLenses = workspace.enabledLenses;
    if (!this.enabledLenses.includes(this.currentLens())) this.setLens(this.availableLenses()[0]);
  }

  restoreDefaultLenses() {
    this.configureLenses({ lensOrder: DEFAULT_LENS_ORDER, enabledLenses: DEFAULT_LENS_ORDER });
  }

  toggleShared(value) {
    const current = this.currentFocus();
    this.sharedFocus = Boolean(value);
    this.focusDays = current;
    if (!this.sharedFocus) this.localFocus[this.projection] = current;
  }

  visibleSpan() {
    const lens = this.currentLens();
    if (lens === "intimate") return this.intimateBack + this.intimateForward + 1;
    if (lens === "tactical") return this.tacticalRows * this.tacticalColumns;
    if (lens === "strategic") return this.strategicMonths * 30.4375;
    if (lens === "wall") return this.wallMonths * 30.4375;
    if (lens === "lines") return this.linesDays;
    if (this.projection === "radial") {
      return this.radialCycle.mul(this.radialPast + this.radialFuture + 1).toNumber();
    }
    return spanForScale(this.scale);
  }

  window(multiplier = 1) {
    const span = Rational.parse(String(this.visibleSpan() * multiplier));
    return {
      start: this.currentFocus().sub(span.div(2)),
      end: this.currentFocus().add(span.div(2))
    };
  }

  focusCoordinate() {
    return daysToCivilCoordinate(this.currentFocus());
  }

  setCivilFocus(year, month, day, hour = 0, minute = 0, second = 0) {
    const value = coordinate([
      { level: "year", value: String(year) },
      { level: "month", value: String(month) },
      { level: "day", value: String(day) },
      { level: "hour", value: String(hour) },
      { level: "minute", value: String(minute) },
      { level: "second", value: String(second) }
    ]);
    const ordinal = new Rational(daysFromCivil(BigInt(year), BigInt(month), BigInt(day)))
      .add(Rational.parse(hour).div(24))
      .add(Rational.parse(minute).div(1440))
      .add(Rational.parse(second).div(86400));
    this.setFocus(ordinal);
    return value;
  }

  toJSON() {
    return {
      projection: this.projection,
      lensOrder: [...this.lensOrder],
      enabledLenses: [...this.enabledLenses],
      scale: this.scale,
      sharedFocus: this.sharedFocus,
      focusDays: this.focusDays.toJSON(),
      localFocus: Object.fromEntries(
        Object.entries(this.localFocus).map(([key, value]) => [key, value.toJSON()])
      ),
      activeFrame: this.activeFrame,
      activeCycle: this.activeCycle,
      radialMode: this.radialMode,
      radialPast: this.radialPast,
      radialFuture: this.radialFuture,
      radialCycle: this.radialCycle.toJSON(),
      radialDivisions: this.radialDivisions,
      radialMajorEvery: this.radialMajorEvery,
      radialMarks: this.radialMarks,
      intimateBack: this.intimateBack,
      intimateForward: this.intimateForward,
      intimateGrain: this.intimateGrain,
      intimateHourPixels: this.intimateHourPixels,
      intimateStartHour: this.intimateStartHour,
      intimateEndHour: this.intimateEndHour,
      tacticalRows: this.tacticalRows,
      tacticalColumns: this.tacticalColumns,
      strategicMonths: this.strategicMonths,
      strategicMode: this.strategicMode,
      intimateZoneFill: this.intimateZoneFill,
      tacticalZoneFill: this.tacticalZoneFill,
      strategicZoneFill: this.strategicZoneFill,
      wallZoneFill: this.wallZoneFill,
      wallMonths: this.wallMonths,
      linesMonths: this.linesMonths,
      linesDays: this.linesDays,
      strategicDetail: this.strategicDetail,
      wallDetail: this.wallDetail,
      strategicRecordSlashes: this.strategicRecordSlashes,
      wallRecordSlashes: this.wallRecordSlashes,
      radialLabels: this.radialLabels,
      selection: this.selection
    };
  }
}

export { DETENTS, INTIMATE_HOUR_PIXELS_MIN, INTIMATE_HOUR_PIXELS_MAX };
