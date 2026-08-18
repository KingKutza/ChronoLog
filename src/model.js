import {
  Rational,
  civilCoordinateToDays,
  coordinate,
  daysToCivilCoordinate
} from "./exact.js";
import { mapSnapshot, opsFromMaps, putOp } from "./ops.js";

export const SCHEMA_VERSION = "chronolog/1";

export function createId(prefix = "item") {
  if (globalThis.crypto?.randomUUID) return `${prefix}:${globalThis.crypto.randomUUID()}`;
  if (globalThis.crypto?.getRandomValues) {
    const bytes = globalThis.crypto.getRandomValues(new Uint8Array(16));
    return `${prefix}:${Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("")}`;
  }
  let hex = "";
  while (hex.length < 32) {
    hex += Math.floor(Math.random() * 0x100000000).toString(16).padStart(8, "0");
  }
  return `${prefix}:${hex.slice(0, 32)}`;
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

// The structural frames a workspace cannot function without: a nested
// human-time magnitude frame (used for durations and other measures) and a
// gregorian wall-time frame (the basis every calendar and event attachment
// hangs off of). This is the default first-run document -- deliberately
// empty of calendars, groups, events, and patterns; those are authored by
// the user, never seeded.
export function createEmptyWorkspaceDocument(title = "Untitled Chronolog") {
  const document = createDocument(title);
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
    if (!event || typeof event !== "object") {
      errors.push(`Event ${id} must be an object`);
      continue;
    }
    if (event.id !== id) errors.push(`Event map key ${id} does not match its id`);
    if (!Array.isArray(event.traits)) errors.push(`Event ${id} requires traits`);
    if (!event.magnitudes?.duration) errors.push(`Event ${id} requires an intrinsic duration`);
    for (const [kind, magnitude] of Object.entries(event.magnitudes || {})) {
      if (!magnitude || typeof magnitude !== "object") {
        errors.push(`Event ${id} magnitude ${kind} must be an object`);
        continue;
      }
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
    if (!frame || typeof frame !== "object") {
      errors.push(`Frame ${id} must be an object`);
      continue;
    }
    if (frame.id !== id) errors.push(`Frame map key ${id} does not match its id`);
    if (!Array.isArray(frame.traits)) errors.push(`Frame ${id} requires traits`);
    if (frame.basis && !document.frames?.[frame.basis]) errors.push(`Frame ${id} has a missing basis`);
    if (frame.coordinateDefinition && !document.frames?.[frame.coordinateDefinition]) {
      errors.push(`Frame ${id} has a missing coordinate definition`);
    }
    if (frame.coordinateDefinition === id) errors.push(`Frame ${id} cannot define coordinates through itself`);
    if (frame.law?.pattern && !document.patterns?.[frame.law.pattern]) {
      errors.push(`Frame ${id} references a missing law pattern`);
    }
    if (frame.period?.kind === "event-defined") validateEventDefinedPeriod(document, frame, errors);
    if (frame.query?.excludeGroups?.length || frame.query?.notGroups?.length) {
      errors.push(`Group ${id} uses recursive negation, which is not defined`);
    }
  }
  for (const [id, pattern] of Object.entries(document.patterns || {})) {
    if (!pattern || typeof pattern !== "object") {
      errors.push(`Pattern ${id} must be an object`);
      continue;
    }
    if (pattern.id !== id) errors.push(`Pattern map key ${id} does not match its id`);
    if (!pattern.language) errors.push(`Pattern ${id} lacks a language`);
    if (pattern.kind === "ics-rrule") {
      if (!document.events?.[pattern.templateEvent]) {
        errors.push(`Pattern ${id} references a missing template event`);
      }
      if (pattern.templateRelation != null && !document.relations?.[pattern.templateRelation]) {
        errors.push(`Pattern ${id} references a missing template relation`);
      }
    }
  }
  for (const [id, relation] of Object.entries(document.relations || {})) {
    if (!relation || typeof relation !== "object") {
      errors.push(`Relation ${id} must be an object`);
      continue;
    }
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
    } else if (relation.type === "membership") {
      const group = document.frames?.[relation.group];
      if (!group?.traits?.includes("group")) {
        errors.push(`Membership ${id} references a missing group`);
      }
      if (!document.events?.[relation.member] && !document.frames?.[relation.member]) {
        errors.push(`Membership ${id} references a missing member`);
      }
      if (relation.include === false || relation.mode === "exclude") {
        errors.push(`Membership ${id} uses negative group membership, which is not defined`);
      }
    } else if (relation.type === "shared-segment") {
      validateSharedSegment(document, relation, errors);
    } else if (relation.type === "termination") {
      validateTermination(document, relation, errors);
    } else if (relation.type === "displacement") {
      validateDisplacement(document, relation, errors);
    } else if (relation.type === "coordinate-mapping") {
      validateCoordinateMapping(document, relation, errors);
    } else {
      errors.push(`Relation ${id} has an unknown type`);
    }
  }
  for (const [id, override] of Object.entries(document.overrides || {})) {
    if (!override || typeof override !== "object") {
      errors.push(`Override ${id} must be an object`);
      continue;
    }
    if (override.id !== id) errors.push(`Override map key ${id} does not match its id`);
    const virtual = typeof override.virtual === "string" ? override.virtual : "";
    const patternId = virtual.slice(0, virtual.lastIndexOf("/"));
    if (!patternId || !document.patterns?.[patternId]) {
      errors.push(`Override ${id} references a missing virtual pattern`);
    }
    for (const replacement of override.replacements || []) {
      if (!document.events?.[replacement]) {
        errors.push(`Override ${id} replacement references a missing event`);
      }
    }
  }
  return { valid: errors.length === 0, errors };
}

function validateEventDefinedPeriod(document, frame, errors) {
  const period = frame.period;
  if (!period.frame || !document.frames?.[period.frame]) errors.push(`Frame ${frame.id} event-defined period references a missing boundary frame`);
  const boundaries = Array.isArray(period.boundaries) ? period.boundaries : [];
  if (boundaries.length < 2) errors.push(`Frame ${frame.id} event-defined period requires at least two boundaries`);
  const ids = new Set();
  let prior = null;
  for (const [index, boundary] of boundaries.entries()) {
    if (!boundary?.id || ids.has(boundary.id)) errors.push(`Frame ${frame.id} event-defined boundary ${index + 1} needs a unique id`);
    ids.add(boundary?.id);
    if (boundary?.event && !document.events?.[boundary.event]) errors.push(`Frame ${frame.id} event-defined boundary ${boundary.id} references a missing event`);
    try {
      const at = Rational.parse(boundary?.at);
      if (prior && at.compare(prior) <= 0) errors.push(`Frame ${frame.id} event-defined boundaries must be strictly ordered`);
      prior = at;
    } catch { errors.push(`Frame ${frame.id} event-defined boundary ${boundary?.id || index + 1} needs an exact coordinate`); }
  }
}

function isCoordinate(value) {
  return Boolean(value && typeof value === "object" && Array.isArray(value.levels)
    && value.levels.every((level) => level && typeof level.level === "string" && typeof level.value === "string"));
}

function validateMappingPosition(document, value, label, errors) {
  if (!value || typeof value !== "object") {
    errors.push(`${label} must be a coordinate or interval`);
    return;
  }
  if (!document.frames?.[value.frame]) errors.push(`${label} references a missing frame ${value.frame || "(missing)"}`);
  if (value.coordinate !== undefined) {
    if (!isCoordinate(value.coordinate)) errors.push(`${label} coordinate must use nested levels`);
    return;
  }
  const interval = value.interval;
  if (!interval || typeof interval !== "object") errors.push(`${label} must contain coordinate or interval start/end coordinates`);
  else {
    if (!isCoordinate(interval.start)) errors.push(`${label} interval start must use nested levels`);
    if (!isCoordinate(interval.end)) errors.push(`${label} interval end must use nested levels`);
  }
}

function validateCoordinateMapping(document, relation, errors) {
  if (!relation.from || !relation.to) {
    errors.push(`Coordinate mapping ${relation.id} requires from and to frame ids`);
    return;
  }
  if (!document.frames?.[relation.from]) errors.push(`Coordinate mapping ${relation.id} references a missing source frame`);
  if (!document.frames?.[relation.to]) errors.push(`Coordinate mapping ${relation.id} references a missing target frame`);
  if (relation.from === relation.to) errors.push(`Coordinate mapping ${relation.id} must relate distinct frames`);
  if (!new Set(["forward", "reverse", "bidirectional"]).has(relation.direction || "bidirectional")) {
    errors.push(`Coordinate mapping ${relation.id} has an invalid direction`);
  }
  const anchors = Array.isArray(relation.anchors) ? relation.anchors : [];
  if (!anchors.length) errors.push(`Coordinate mapping ${relation.id} requires at least one anchor`);
  for (const [index, anchor] of anchors.entries()) {
    validateMappingPosition(document, anchor?.from, `Coordinate mapping ${relation.id} anchor ${index + 1} source`, errors);
    validateMappingPosition(document, anchor?.to, `Coordinate mapping ${relation.id} anchor ${index + 1} target`, errors);
    if (anchor?.from?.frame && anchor.from.frame !== relation.from) {
      errors.push(`Coordinate mapping ${relation.id} anchor ${index + 1} source frame must match from`);
    }
    if (anchor?.to?.frame && anchor.to.frame !== relation.to) {
      errors.push(`Coordinate mapping ${relation.id} anchor ${index + 1} target frame must match to`);
    }
    if (!new Set(["continuous", "discontinuous"]).has(anchor?.continuity || "continuous")) {
      errors.push(`Coordinate mapping ${relation.id} anchor ${index + 1} has an invalid continuity`);
    }
  }
}

// Placeholder for future loss-minimizing migrations when the canonical
// chronolog/1 shape evolves. The canonical result remains chronolog/1:
// generic Frame traits, authored unit definitions under coordinate, and
// Relations for cross-frame meaning.
export function migrateDocument(document) {
  if (!document || typeof document !== "object") return document;
  return document;
}

function attachmentFor(document, id) {
  const relation = document.relations?.[id];
  return relation?.type === "attachment" ? relation : null;
}

function validateSharedSegment(document, relation, errors) {
  const lines = Array.isArray(relation.lines) ? [...new Set(relation.lines)] : [];
  if (lines.length < 2) {
    errors.push(`Shared segment ${relation.id} requires at least two distinct lines`);
    return;
  }
  const anchors = relation.anchors || {};
  const starts = [];
  const ends = [];
  for (const line of lines) {
    if (!document.frames?.[line]) errors.push(`Shared segment ${relation.id} references a missing line ${line}`);
    const anchor = anchors[line];
    const start = attachmentFor(document, anchor?.start);
    const end = attachmentFor(document, anchor?.end);
    if (!start || start.frame !== line) errors.push(`Shared segment ${relation.id} has no start anchor on ${line}`);
    if (!end || end.frame !== line) errors.push(`Shared segment ${relation.id} has no end anchor on ${line}`);
    if (start) starts.push(start.event);
    if (end) ends.push(end.event);
  }
  if (starts.length === lines.length && new Set(starts).size !== 1) {
    errors.push(`Shared segment ${relation.id} start anchors must staple at one event`);
  }
  if (ends.length === lines.length && new Set(ends).size !== 1) {
    errors.push(`Shared segment ${relation.id} end anchors must staple at one event`);
  }
}

function validateTermination(document, relation, errors) {
  const attachment = attachmentFor(document, relation.terminator);
  const event = attachment && document.events?.[attachment.event];
  if (!document.frames?.[relation.line]) errors.push(`Termination ${relation.id} references a missing line`);
  if (!attachment || attachment.frame !== relation.line) {
    errors.push(`Termination ${relation.id} must reference an attachment on its line`);
  }
  if (!event?.traits?.includes("terminator")) {
    errors.push(`Termination ${relation.id} must reference a terminator event`);
  }
  if (!["sealed", "stapled"].includes(relation.state)) {
    errors.push(`Termination ${relation.id} state must be sealed or stapled; open is a rendering state`);
  }
  if (relation.state === "stapled" && attachment) {
    const incidence = eventRelations(document, attachment.event);
    if (incidence.length < 2) errors.push(`Stapled termination ${relation.id} must attach to another line`);
  }
}

function validateDisplacement(document, relation, errors) {
  const directions = new Set(["forward", "reverse", "stationary"]);
  if (!document.frames?.[relation.traveler]) errors.push(`Displacement ${relation.id} references a missing traveler line`);
  if (!document.frames?.[relation.world]) errors.push(`Displacement ${relation.id} references a missing world line`);
  if (relation.properDirection !== "forward") {
    errors.push(`Displacement ${relation.id} must advance traveler proper time forward`);
  }
  if (!directions.has(relation.worldDirection)) {
    errors.push(`Displacement ${relation.id} has an invalid world direction`);
  }
  for (const endpoint of ["origin", "destination"]) {
    const values = relation[endpoint] || {};
    const traveler = attachmentFor(document, values.traveler);
    const world = attachmentFor(document, values.world);
    if (!traveler || traveler.frame !== relation.traveler) {
      errors.push(`Displacement ${relation.id} ${endpoint} lacks a traveler attachment`);
    }
    if (!world || world.frame !== relation.world) {
      errors.push(`Displacement ${relation.id} ${endpoint} lacks a world attachment`);
    }
  }
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

export function durationMagnitudeDays(magnitude) {
  const factors = {
    week: "7",
    day: "1",
    hour: "1/24",
    minute: "1/1440",
    second: "1/86400"
  };
  let total = Rational.parse(0);
  for (const part of magnitude?.value?.levels || []) {
    const factor = factors[part.level];
    if (factor !== undefined) total = total.add(Rational.parse(part.value).mul(factor));
  }
  return total;
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

// An open end is deliberately not stored on a line. It means this particular
// projection stopped before reaching a persisted terminator, not that the line
// itself has died. Callers pass the attachment visible at the rendered edge.
export function renderTerminatorState(document, lineId, boundaryAttachmentId) {
  const termination = Object.values(document.relations || {}).find((relation) =>
    relation.type === "termination"
      && relation.line === lineId
      && relation.terminator === boundaryAttachmentId
  );
  return termination?.state || "open";
}

export function coordinateToDays(document, frameId, value) {
  return coordinateToDaysSeen(document, frameId, value, new Set());
}

function coordinateToDaysSeen(document, frameId, value, seen) {
  if (seen.has(frameId)) throw new Error(`Coordinate definition cycle at ${frameId}`);
  seen.add(frameId);
  const frame = document.frames[frameId];
  if (!frame) throw new Error(`Unknown frame: ${frameId}`);
  if (frame.coordinateDefinition) return coordinateToDaysSeen(document, frame.coordinateDefinition, value, seen);
  if (frame.coordinate?.kind === "gregorian" || frame.traits.includes("gregorian")) {
    return civilCoordinateToDays(value);
  }
  if (frame.basis) return coordinateToDaysSeen(document, frame.basis, value, seen);
  const days = value?.levels?.find((entry) => entry.level === "day");
  if (days) return Rational.parse(days.value);
  throw new Error(`Frame ${frameId} has no temporal coordinate law`);
}

export function daysToCoordinate(document, frameId, days) {
  return daysToCoordinateSeen(document, frameId, days, new Set());
}

function daysToCoordinateSeen(document, frameId, days, seen) {
  if (seen.has(frameId)) throw new Error(`Coordinate definition cycle at ${frameId}`);
  seen.add(frameId);
  const frame = document.frames[frameId];
  if (!frame) throw new Error(`Unknown frame: ${frameId}`);
  if (frame.coordinateDefinition) return daysToCoordinateSeen(document, frame.coordinateDefinition, days, seen);
  if (frame.coordinate?.kind === "gregorian" || frame.traits.includes("gregorian")) {
    return daysToCivilCoordinate(days);
  }
  if (frame.basis) return daysToCoordinateSeen(document, frame.basis, days, seen);
  return coordinate([{ level: "day", value: Rational.parse(days).toJSON() }]);
}

export function stableVirtualId(patternId, key) {
  const encoded = String(key).replace(
    /[^a-zA-Z0-9._~-]/g,
    (char) => Array.from(
      new TextEncoder().encode(char),
      (byte) => `%${byte.toString(16).toUpperCase().padStart(2, "0")}`
    ).join("")
  );
  return `${patternId}/${encoded}`;
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
  constructor(document, onChange = () => {}, limit = 200, maxSnapshotBytes = 32 * 1024 * 1024) {
    this.document = document;
    this.onChange = onChange;
    this.limit = limit;
    this.maxSnapshotBytes = maxSnapshotBytes;
    this.undoStack = [];
    this.redoStack = [];
  }

  commandBytes(command) {
    if (command.bytes !== undefined) return command.bytes;
    return ((command.before?.length || 0) + (command.after?.length || 0)) * 2;
  }

  retainedBytes() {
    return [...this.undoStack, ...this.redoStack]
      .reduce((total, command) => total + this.commandBytes(command), 0);
  }

  trim() {
    while (this.undoStack.length > this.limit) this.undoStack.shift();
    while (this.undoStack.length && this.retainedBytes() > this.maxSnapshotBytes) {
      this.undoStack.shift();
    }
  }

  // Every committed change reports the record-level ops that produced it, so
  // the store can append them to the journal. The caller supplies the ops it
  // knows about; the `meta.modified` bump that `touch` just applied is added
  // here, because a replay that skipped it would drift from this document.
  emit(label, metadata = {}, ops = null) {
    const { ops: forward, inverseOps, ...rest } = metadata;
    void forward;
    void inverseOps;
    this.onChange({
      label,
      document: this.document,
      ...rest,
      ...(ops ? { ops: [...ops, putOp("meta", "modified", this.document.meta.modified)] } : {})
    });
  }

  execute(label, mutate) {
    const before = JSON.stringify(this.document);
    const beforeMaps = mapSnapshot(this.document);
    try {
      mutate(this.document);
    } catch (error) {
      this.replace(before);
      throw error;
    }
    touch(this.document);
    const after = JSON.stringify(this.document);
    this.redoStack = [];
    const command = { label, before, after, bytes: (before.length + after.length) * 2 };
    const historyLimited = command.bytes > this.maxSnapshotBytes;
    if (!historyLimited) {
      this.undoStack.push(command);
      this.trim();
    }
    // The whole-snapshot path cannot know which records the mutation touched,
    // so it falls back to an identity diff over the maps.
    this.emit(label, { historyLimited }, opsFromMaps(beforeMaps, mapSnapshot(this.document)));
  }

  executeDelta(label, apply, revert, metadata = {}) {
    try {
      apply(this.document);
    } catch (error) {
      // Delta callers make revert safe for partially-applied work so large
      // imports can recover without cloning the entire calendar first.
      revert(this.document);
      throw error;
    }
    touch(this.document);
    this.undoStack.push({ label, apply, revert, metadata, bytes: 0 });
    this.redoStack = [];
    this.trim();
    this.emit(label, metadata, metadata.ops || null);
  }

  replace(snapshot) {
    const restored = typeof snapshot === "string" ? JSON.parse(snapshot) : clone(snapshot);
    for (const key of Object.keys(this.document)) delete this.document[key];
    Object.assign(this.document, restored);
  }

  // Undo and redo commit journal entries of their own: an undo is not a
  // rewind of the file, it is a new edit that happens to restore earlier
  // record values. The delta path already captured both directions, so undo
  // simply commits the inverse ops it was handed.
  undo() {
    const command = this.undoStack.pop();
    if (!command) return false;
    let ops = command.metadata?.inverseOps || null;
    if (command.revert) {
      command.revert(this.document);
      touch(this.document);
    } else {
      const beforeMaps = mapSnapshot(this.document);
      this.replace(command.before);
      ops = opsFromMaps(beforeMaps, mapSnapshot(this.document));
    }
    this.redoStack.push(command);
    this.emit(`Undo ${command.label}`, command.metadata, ops);
    return true;
  }

  redo() {
    const command = this.redoStack.pop();
    if (!command) return false;
    let ops = command.metadata?.ops || null;
    if (command.apply) {
      command.apply(this.document);
      touch(this.document);
    } else {
      const beforeMaps = mapSnapshot(this.document);
      this.replace(command.after);
      ops = opsFromMaps(beforeMaps, mapSnapshot(this.document));
    }
    this.undoStack.push(command);
    this.emit(`Redo ${command.label}`, command.metadata, ops);
    return true;
  }
}
