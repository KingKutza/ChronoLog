import { daysFromCivil } from "./exact.js";
import { createDocument } from "./model.js";

export const CELESTIAL_SOURCE = `
// Compact mean-orbit demonstration. Constants are data, not occurrences.
fn angle(days, period, phase) =
  mod((days / num(period) + num(phase)) * tau, tau);

fn orbit(days, period, phase, radius) = {
  angle: angle(days, period, phase),
  x: cos(angle(days, period, phase)) * num(radius),
  y: sin(angle(days, period, phase)) * num(radius),
  radius: num(radius)
};

fn phaseDay(k, offset, ctx) =
  num(ctx.constants.newMoonEpoch) +
  (k + offset) * num(ctx.constants.synodicMonth);

fn phaseFact(k, offset, slug, title, ctx) = {
  key: slug + "-" + str(k),
  type: "event",
  traits: ["event", "celestial", "phase"],
  day: phaseDay(k, offset, ctx),
  payload: { title: title, body: "Moon", phase: slug }
};

fn factsFor(k, ctx) = [
  phaseFact(k, 0, "new-moon", "New Moon", ctx),
  phaseFact(k, 0.25, "first-quarter", "First Quarter Moon", ctx),
  phaseFact(k, 0.5, "full-moon", "Full Moon", ctx),
  phaseFact(k, 0.75, "last-quarter", "Last Quarter Moon", ctx)
];

export fn state(ctx) = {
  reference: "mean-ecliptic",
  earth: orbit(
    ctx.atDays,
    ctx.constants.earthYear,
    ctx.constants.earthPhase,
    ctx.constants.astronomicalUnitKm
  ),
  sunGeocentric: orbit(
    ctx.atDays,
    ctx.constants.earthYear,
    num(ctx.constants.earthPhase) + 0.5,
    ctx.constants.astronomicalUnitKm
  ),
  moonGeocentric: orbit(
    ctx.atDays,
    ctx.constants.siderealMonth,
    ctx.constants.moonPhase,
    ctx.constants.moonDistanceKm
  ),
  lunarPhase: mod(
    (ctx.atDays - num(ctx.constants.newMoonEpoch)) /
    num(ctx.constants.synodicMonth),
    1
  ),
  lunarIllumination: (
    1 - cos(
      mod(
        (ctx.atDays - num(ctx.constants.newMoonEpoch)) /
        num(ctx.constants.synodicMonth),
        1
      ) * tau
    )
  ) / 2
};

export fn facts(ctx) = concat([
  factsFor(k, ctx)
  for k in rangeCycles(
    ctx.fromDays,
    ctx.toDays,
    ctx.constants.newMoonEpoch,
    ctx.constants.synodicMonth
  )
]);
`.trim();

export function createCelestialDocument() {
  const document = createDocument("Chronolog");
  document.meta.created = "2026-08-06T00:00:00.000Z";
  document.meta.modified = "2026-08-06T00:00:00.000Z";
  document.frames["measure:human-time"] = {
    id: "measure:human-time",
    title: "Human time magnitude",
    traits: ["line", "measure", "duration"],
    coordinate: {
      kind: "nested",
      levels: [
        { name: "year" },
        { name: "day", within: "year", transition: "gregorian.daysInYear" },
        { name: "hour", within: "day", radix: "24" },
        { name: "minute", within: "hour", radix: "60" },
        { name: "second", within: "minute", radix: "60" },
        { name: "subsecond", within: "second" }
      ]
    }
  };
  document.frames["frame:wall-time"] = {
    id: "frame:wall-time",
    title: "Wall time",
    traits: ["line", "temporal", "gregorian"],
    coordinate: {
      kind: "gregorian",
      levels: [
        { name: "year" },
        { name: "month", within: "year", transition: "gregorian.months" },
        { name: "day", within: "month", transition: "gregorian.days" },
        { name: "hour", within: "day", radix: "24" },
        { name: "minute", within: "hour", radix: "60" },
        { name: "second", within: "minute", radix: "60" },
        { name: "subsecond", within: "second" }
      ]
    }
  };
  document.frames["calendar:personal"] = {
    id: "calendar:personal",
    title: "Personal",
    traits: ["set", "calendar"],
    basis: "frame:wall-time",
    codec: { kind: "ics" }
  };
  document.frames["calendar:celestial"] = {
    id: "calendar:celestial",
    title: "Celestial",
    traits: ["set", "calendar", "generated"],
    basis: "frame:wall-time",
    codec: { kind: "ics" }
  };
  document.frames["group:celestial"] = {
    id: "group:celestial",
    title: "Celestial",
    traits: ["set", "group"],
    color: "#6d63b8"
  };
  document.frames["frame:mean-ecliptic"] = {
    id: "frame:mean-ecliptic",
    title: "Mean ecliptic state",
    traits: ["state", "celestial"],
    basis: "frame:wall-time"
  };
  document.frames["cycle:lunar"] = {
    id: "cycle:lunar",
    title: "Lunar month",
    traits: ["circle", "cycle"],
    basis: "frame:wall-time",
    calendar: "calendar:celestial",
    period: {
      frame: "measure:human-time",
      value: {
        levels: [{ level: "day", value: "29.530588853" }]
      }
    },
    derivedBy: "pattern:celestial"
  };

  const newMoonDay = daysFromCivil(2000n, 1n, 6n);
  document.patterns["pattern:celestial"] = {
    id: "pattern:celestial",
    title: "Earth–Moon–Sun mean-orbit model",
    language: "chronolog-formula/1",
    appliesTo: ["calendar:celestial", "frame:mean-ecliptic"],
    frame: "calendar:celestial",
    constants: {
      astronomicalUnitKm: "149597870.7",
      earthYear: "365.256363004",
      earthPhase: "0.279273",
      moonDistanceKm: "384400",
      siderealMonth: "27.321661",
      synodicMonth: "29.530588853",
      moonPhase: "0.157",
      newMoonEpoch: `${newMoonDay}+547/720`.includes("+")
        ? String(newMoonDay * 720n + 547n) + "/720"
        : String(newMoonDay)
    },
    source: CELESTIAL_SOURCE,
    exports: { state: "state", facts: "facts" },
    provenance: {
      kind: "model",
      accuracy: "exact-to-stored-model",
      note: "Compact mean-orbit demonstration, not a physical ephemeris."
    }
  };
  return document;
}

export const celestialDocument = createCelestialDocument();
