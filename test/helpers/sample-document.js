// Synthetic chronolog/1 fixtures for tests. This intentionally contains no
// real calendar data -- it exists so the test suite does not depend on
// src/celestial.js, which is untracked personal field-test data that only
// exists on this machine. Everything here is generic and safe to commit.
import { daysFromCivil } from "../../src/exact.js";
import { addEvent, addFrame, addPattern, addRelation, createDocument, durationMagnitude } from "../../src/model.js";

// A minimal chronolog-formula/1 pattern used by engine/pattern tests that need
// a derived cycle. It emits one "marker" fact per fixed interval -- a plain
// weekly checkpoint, not any kind of physical or astronomical model.
export const MARKER_SOURCE = `
// Minimal weekly-marker demonstration. Constants are data, not occurrences.
fn markerDay(k, ctx) =
  num(ctx.constants.epoch) + k * num(ctx.constants.intervalDays);

fn markerFact(k, ctx) = {
  key: "marker-" + str(k),
  type: "event",
  traits: ["event", "generated", "marker"],
  day: markerDay(k, ctx),
  payload: { title: ctx.constants.title, body: "Generated marker" }
};

export fn state(ctx) = {
  reference: "marker",
  intervalDays: num(ctx.constants.intervalDays),
  epoch: num(ctx.constants.epoch)
};

export fn facts(ctx) = [
  markerFact(k, ctx)
  for k in rangeCycles(
    ctx.fromDays,
    ctx.toDays,
    ctx.constants.epoch,
    ctx.constants.intervalDays
  )
];
`.trim();

export const SAMPLE_MARKER_INTERVAL_DAYS = "7";
export const SAMPLE_MARKER_EPOCH_DAYS = String(daysFromCivil(2026n, 1n, 1n));

// The structural frames a workspace cannot function without: a nested
// human-time magnitude frame (used for durations and other measures) and a
// gregorian wall-time frame (the basis every calendar hangs off of). These
// mirror the generic structure src/celestial.js used to build -- there is
// nothing celestial about them, so they are safe to keep in tracked code.
export function addStructuralFrames(document) {
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
  return document;
}

// Only the structural frames -- a bare canvas for tests that want to author
// their own frames/events/patterns from scratch without any other fixture.
export function createStructuralDocument(title = "Structural sample") {
  return addStructuralFrames(createDocument(title));
}

function addSampleEvents(document) {
  const standup = addEvent(document, {
    id: "event:sample-standup",
    traits: ["event", "work"],
    magnitudes: { duration: durationMagnitude("30", "minute") },
    payload: { title: "Sample standup" }
  });
  addRelation(document, {
    id: "relation:sample-standup-placed",
    type: "attachment",
    event: standup.id,
    frame: "calendar:personal",
    role: "placed",
    coordinate: { levels: [{ level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "10" }] }
  });

  const appointment = addEvent(document, {
    id: "event:sample-appointment",
    traits: ["event", "personal"],
    magnitudes: { duration: durationMagnitude("1", "hour") },
    payload: { title: "Sample appointment" }
  });
  addRelation(document, {
    id: "relation:sample-appointment-placed",
    type: "attachment",
    event: appointment.id,
    frame: "calendar:personal",
    role: "placed",
    coordinate: { levels: [{ level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "12" }] }
  });

  const task = addEvent(document, {
    id: "event:sample-task",
    traits: ["event", "task", "work"],
    magnitudes: { duration: durationMagnitude("0") },
    payload: { title: "Sample completed task" }
  });
  addRelation(document, {
    id: "relation:sample-task-completed",
    type: "attachment",
    event: task.id,
    frame: "calendar:personal",
    role: "completed",
    coordinate: { levels: [{ level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "9" }] }
  });

  addRelation(document, {
    id: "membership:sample-standup",
    type: "membership",
    group: "group:sample",
    member: standup.id
  });
  addRelation(document, {
    id: "membership:sample-task",
    type: "membership",
    group: "group:sample",
    member: task.id
  });

  return { standup, appointment, task };
}

// A small, generic chronolog/1 document: the structural frames, a personal
// calendar, a group, a handful of sample events, and (by default) a tiny
// generated cycle driven by a weekly-marker chronolog-formula/1 pattern.
// Every id and value here is synthetic fixture data invented for tests --
// none of it originates from src/celestial.js.
export function createSampleDocument({
  title = "Sample",
  includeEvents = true,
  includePattern = true
} = {}) {
  const document = createStructuralDocument(title);
  document.meta.created = "2026-08-06T00:00:00.000Z";
  document.meta.modified = "2026-08-06T00:00:00.000Z";

  document.frames["calendar:personal"] = {
    id: "calendar:personal",
    title: "Personal",
    traits: ["set", "calendar"],
    basis: "frame:wall-time",
    codec: { kind: "ics" }
  };

  document.frames["group:sample"] = {
    id: "group:sample",
    title: "Sample group",
    traits: ["set", "group"],
    color: "#3d7ea6"
  };

  if (includePattern) {
    document.frames["calendar:generated"] = {
      id: "calendar:generated",
      title: "Generated markers",
      traits: ["set", "calendar", "generated"],
      basis: "frame:wall-time",
      codec: { kind: "ics" }
    };
    document.frames["frame:marker-state"] = {
      id: "frame:marker-state",
      title: "Marker state",
      traits: ["state", "generated"],
      basis: "frame:wall-time"
    };
    document.frames["cycle:marker"] = {
      id: "cycle:marker",
      title: "Weekly marker",
      traits: ["circle", "cycle"],
      basis: "frame:wall-time",
      calendar: "calendar:generated",
      period: {
        frame: "measure:human-time",
        value: { levels: [{ level: "day", value: SAMPLE_MARKER_INTERVAL_DAYS }] }
      },
      derivedBy: "pattern:marker"
    };
    document.patterns["pattern:marker"] = {
      id: "pattern:marker",
      title: "Weekly marker generator",
      language: "chronolog-formula/1",
      appliesTo: ["calendar:generated", "frame:marker-state"],
      frame: "calendar:generated",
      constants: {
        epoch: SAMPLE_MARKER_EPOCH_DAYS,
        intervalDays: SAMPLE_MARKER_INTERVAL_DAYS,
        title: "Marker"
      },
      source: MARKER_SOURCE,
      exports: { state: "state", facts: "facts" },
      provenance: {
        kind: "model",
        accuracy: "exact-to-stored-model",
        note: "Synthetic weekly-marker generator for tests, not real calendar data."
      }
    };
  }

  if (includeEvents) addSampleEvents(document);

  return document;
}
