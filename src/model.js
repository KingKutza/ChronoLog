import {
  Rational,
  civilCoordinateToDays,
  coordinate,
  daysToCivilCoordinate
} from "./exact.js";

export const SCHEMA_VERSION = "chronolog/1";

let sequence = 0;

export function createId(prefix = "item") {
  if (globalThis.crypto?.randomUUID) return `${prefix}:${globalThis.crypto.randomUUID()}`;
  sequence += 1;
  return `${prefix}:${Date.now().toString(36)}-${sequence.toString(36)}`;
}

export function createDocument(title = "Untitled Chronolog") {
  return {
    schema: SCHEMA_VERSION,
    meta: { title, created: new Date().toISOString(), modified: new Date().toISOString() },
    frames: {},
    events: {},
    patterns: {},
    relations: {},
    overrides: {},
    foreign: {}
  };
}

export function clone(value) {
  return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
}

export function validateDocument(document) {
  const errors = [];
  if (!document || typeof document !== "object") return { valid: false, errors: ["Document is not an object"] };
  if (document.schema !== SCHEMA_VERSION) errors.push(`Unsupported schema: ${document.schema || "(missing)"}`);
  for (const key of ["frames", "events", "patterns", "relations", "overrides", "foreign"]) {
    if (!document[key] || typeof document[key] !== "object" || Array.isArray(document[key])) {
      errors.push(`${key} must be an object map`);
    }
  }
  for (const [id, event] of Object.entries(document.events || {})) {
    if (event.id !== id) errors.push(`Event map key ${id} does not match its id`);
    if (!Array.isArray(event.traits)) errors.push(`Event ${id} requires traits`);
    if (!event.magnitudes?.duration) errors.push(`Event ${id} requires an intrinsic duration`);
    for (const [kind, magnitude] of Object.entries(event.magnitudes || {})) {
      if (!magnitude.frame || !document.frames?.[magnitude.frame]) {
        errors.push(`Event ${id} magnitude ${kind} references a missing frame`);
      }
      if (!magnitude.value?.levels) errors.push(`Event ${id} magnitude ${kind} lacks a nested value`);
    }
    if (
      (event.traits?.includes("task") || event.traits?.includes("terminator"))
      && !isZeroDuration(event)
    ) {
      errors.push(`Event ${id} must have zero duration for its task/terminator trait`);
    }
  }
  for (const [id, frame] of Object.entries(document.frames || {})) {
    if (frame.id !== id) errors.push(`Frame map key ${id} does not match its id`);
    if (!Array.isArray(frame.traits)) errors.push(`Frame ${id} requires traits`);
    if (frame.basis && !document.frames?.[frame.basis]) errors.push(`Frame ${id} has a missing basis`);
    if (frame.law?.pattern && !document.patterns?.[frame.law.pattern]) {
      errors.push(`Frame ${id} references a missing law pattern`);
    }
  }
  for (const [id, pattern] of Object.entries(document.patterns || {})) {
    if (pattern.id !== id) errors.push(`Pattern map key ${id} does not match its id`);
    if (!pattern.language) errors.push(`Pattern ${id} lacks a language`);
  }
  for (const [id, relation] of Object.entries(document.relations || {})) {
    if (relation.id !== id) errors.push(`Relation map key ${id} does not match its id`);
    if (relation.type === "attachment") {
      if (!document.events?.[relation.event]) errors.push(`Attachment ${id} references a missing event`);
      if (!document.frames?.[relation.frame]) errors.push(`Attachment ${id} references a missing frame`);
      const event = document.events?.[relation.event];
      const frame = document.frames?.[relation.frame];
      if (
        event?.traits?.includes("task")
        && frame?.traits?.includes("calendar")
        && !["observed", "completed"].includes(relation.role)
      ) {
        errors.push(`Task attachment ${id} must be retrospective`);
      }
    } else if (relation.type === "composition") {
      if (!document.frames?.[relation.parent] || !document.frames?.[relation.child]) {
        errors.push(`Composition ${id} references a missing frame`);
      }
    } else {
      errors.push(`Relation ${id} has an unknown type`);
    }
  }
  return { valid: errors.length === 0, errors };
}

export function addFrame(document, input) {
  const frame = {
    id: input.id || createId("frame"),
    traits: input.traits || ["set"],
    title: input.title || "Untitled frame",
    ...clone(input)
  };
  document.frames[frame.id] = frame;
  touch(document);
  return frame;
}

export function addEvent(document, input = {}) {
  const event = {
    id: input.id || createId("event"),
    traits: input.traits || ["event"],
    magnitudes: input.magnitudes || { duration: durationMagnitude("0") },
    payload: input.payload || { title: "Untitled event" },
    ...clone(input)
  };
  document.events[event.id] = event;
  touch(document);
  return event;
}

export function addPattern(document, input) {
  const pattern = {
    id: input.id || createId("pattern"),
    language: input.language || "chronolog-formula/1",
    constants: input.constants || {},
    source: input.source || "",
    exports: input.exports || { state: "state", facts: "facts" },
    ...clone(input)
  };
  document.patterns[pattern.id] = pattern;
  touch(document);
  return pattern;
}

export function addRelation(document, input) {
  const relation = {
    id: input.id || createId("relation"),
    role: input.role || (input.type === "composition" ? "segment" : "member"),
    provenance: input.provenance || { kind: "explicit" },
    ...clone(input)
  };
  document.relations[relation.id] = relation;
  touch(document);
  return relation;
}

export function touch(document) {
  document.meta ||= {};
  document.meta.modified = new Date().toISOString();
}

export function durationMagnitude(value = "0", unit = "second", frame = "measure:human-time") {
  return {
    frame,
    value: coordinate([{ level: unit, value: String(value) }])
  };
}

export function isZeroDuration(event) {
  const duration = event?.magnitudes?.duration?.value?.levels || [];
  return duration.every((entry) => Rational.parse(entry.value).isZero());
}

export function eventRelations(document, eventId) {
  return Object.values(document.relations).filter(
    (relation) => relation.type === "attachment" && relation.event === eventId
  );
}

export function frameRelations(document, frameId) {
  return Object.values(document.relations).filter(
    (relation) => relation.type === "attachment" && relation.frame === frameId
  );
}

export function frameChildren(document, frameId) {
  return Object.values(document.relations)
    .filter((relation) => relation.type === "composition" && relation.parent === frameId)
    .sort((a, b) => Number(a.order || 0) - Number(b.order || 0))
    .map((relation) => document.frames[relation.child]);
}

export function coordinateToDays(document, frameId, value) {
  const frame = document.frames[frameId];
  if (!frame) throw new Error(`Unknown frame: ${frameId}`);
  if (frame.coordinate?.kind === "gregorian" || frame.traits.includes("gregorian")) {
    return civilCoordinateToDays(value);
  }
  if (frame.basis) return coordinateToDays(document, frame.basis, value);
  const days = value?.levels?.find((entry) => entry.level === "day");
  if (days) return Rational.parse(days.value);
  throw new Error(`Frame ${frameId} has no temporal coordinate law`);
}

export function daysToCoordinate(document, frameId, days) {
  const frame = document.frames[frameId];
  if (!frame) throw new Error(`Unknown frame: ${frameId}`);
  if (frame.coordinate?.kind === "gregorian" || frame.traits.includes("gregorian")) {
    return daysToCivilCoordinate(days);
  }
  if (frame.basis) return daysToCoordinate(document, frame.basis, days);
  return coordinate([{ level: "day", value: Rational.parse(days).toJSON() }]);
}

export function stableVirtualId(patternId, key) {
  return `${patternId}/${String(key).replace(/[^a-zA-Z0-9._~-]+/g, "-")}`;
}

export function applyVirtualOverrides(document, facts) {
  const suppressed = new Set(
    Object.values(document.overrides || {})
      .filter((override) => override.suppress)
      .map((override) => override.virtual)
  );
  return facts.filter((fact) => !suppressed.has(fact.virtualId));
}

export function suppressVirtual(document, virtualId, replacements = []) {
  const id = createId("override");
  document.overrides[id] = { id, virtual: virtualId, suppress: true, replacements: [...replacements] };
  touch(document);
  return document.overrides[id];
}

export function stapleEvents(document, eventIds) {
  const ids = [...new Set(eventIds)].filter((id) => document.events[id]);
  if (ids.length < 2) return document.events[ids[0]] || null;
  const canonical = document.events[ids[0]];
  canonical.foreign ||= {};
  canonical.foreign.stapled ||= [];
  for (const duplicateId of ids.slice(1)) {
    const duplicate = document.events[duplicateId];
    if (!duplicate) continue;
    canonical.foreign.stapled.push({
      id: duplicateId,
      payload: clone(duplicate.payload),
      foreign: clone(duplicate.foreign || {})
    });
    for (const relation of Object.values(document.relations)) {
      if (relation.event === duplicateId) relation.event = canonical.id;
    }
    for (const pattern of Object.values(document.patterns)) {
      if (pattern.templateEvent === duplicateId) pattern.templateEvent = canonical.id;
    }
    for (const override of Object.values(document.overrides)) {
      override.replacements = (override.replacements || []).map(
        (id) => id === duplicateId ? canonical.id : id
      );
    }
    delete document.events[duplicateId];
  }
  touch(document);
  return canonical;
}

export class CommandHistory {
  constructor(document, onChange = () => {}) {
    this.document = document;
    this.onChange = onChange;
    this.undoStack = [];
    this.redoStack = [];
  }

  execute(label, mutate) {
    const before = clone(this.document);
    mutate(this.document);
    touch(this.document);
    const after = clone(this.document);
    this.undoStack.push({ label, before, after });
    this.redoStack = [];
    this.onChange({ label, document: this.document });
  }

  replace(snapshot) {
    for (const key of Object.keys(this.document)) delete this.document[key];
    Object.assign(this.document, clone(snapshot));
  }

  undo() {
    const command = this.undoStack.pop();
    if (!command) return false;
    this.replace(command.before);
    this.redoStack.push(command);
    this.onChange({ label: `Undo ${command.label}`, document: this.document });
    return true;
  }

  redo() {
    const command = this.redoStack.pop();
    if (!command) return false;
    this.replace(command.after);
    this.undoStack.push(command);
    this.onChange({ label: `Redo ${command.label}`, document: this.document });
    return true;
  }
}
