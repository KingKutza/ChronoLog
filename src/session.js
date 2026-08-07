import {
  Rational,
  coordinate,
  daysFromCivil,
  daysToCivilCoordinate
} from "./exact.js";

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
    this.projection = input.projection || "calendar";
    this.scale = Number(input.scale ?? 1);
    this.sharedFocus = input.sharedFocus !== false;
    this.focusDays = Rational.parse(input.focusDays || todayDays());
    this.localFocus = Object.fromEntries(
      Object.entries(input.localFocus || {}).map(([key, value]) => [key, Rational.parse(value)])
    );
    this.activeFrame = input.activeFrame || "calendar:personal";
    this.primeFrame = input.primeFrame || this.activeFrame;
    this.activeCycle = input.activeCycle || "cycle:lunar";
    this.radialMode = input.radialMode || "spiral";
    this.radialPast = Math.max(0, Number(input.radialPast ?? 1));
    this.radialFuture = Math.max(0, Number(input.radialFuture ?? 1));
    this.radialCycle = Rational.parse(input.radialCycle || "29.530588853");
    this.selection = input.selection || null;
    this.inspector = input.inspector || null;
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

  move(days) {
    this.setFocus(this.currentFocus().add(days));
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

  toggleShared(value) {
    const current = this.currentFocus();
    this.sharedFocus = Boolean(value);
    this.focusDays = current;
    if (!this.sharedFocus) this.localFocus[this.projection] = current;
  }

  visibleSpan() {
    if (this.projection === "wall") return this.scale < 1 ? 31 : this.scale < 1.65 ? 92 : 183;
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
      scale: this.scale,
      sharedFocus: this.sharedFocus,
      focusDays: this.focusDays.toJSON(),
      localFocus: Object.fromEntries(
        Object.entries(this.localFocus).map(([key, value]) => [key, value.toJSON()])
      ),
      activeFrame: this.activeFrame,
      primeFrame: this.primeFrame,
      activeCycle: this.activeCycle,
      radialMode: this.radialMode,
      radialPast: this.radialPast,
      radialFuture: this.radialFuture,
      radialCycle: this.radialCycle.toJSON(),
      selection: this.selection
    };
  }
}

export { DETENTS };
