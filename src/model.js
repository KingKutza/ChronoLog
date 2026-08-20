import { Rational, coordinate } from "./exact.js";
import { GREGORIAN_DECLARATION, coordinateLaw, durationMagnitudeDays } from "./coordinate-law.js";
import { mapSnapshot, opsFromMaps, putOp } from "./ops.js";
import {
  DEFAULT_POINT,
  STAPLE_KINDS,
  endId,
  endScope,
  endScopePair,
  stapleEnds,
  stapleKind,
  stapleReferencesId,
  stapleTouchesAny
} from "./staples.js";

// Re-exported from coordinate-law.js, where the arithmetic now lives: a
// duration's worth in days is a question about the magnitude frame's declared
// unit ladder, so it is answered there. Kept exported here so every existing
// caller's import path is unchanged.
export { durationMagnitudeDays };

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
  // Wall time ships the REGISTERED Gregorian declaration verbatim -- ladder,
  // radices, month names, and the weekday cycle -- rather than a hand-copied
  // subset of it. The names matter: they are what the minimap and the day
  // headers read, so putting them in the declaration is what makes them
  // editable at all, and Wall Time is the frame every derived calendar inherits
  // its structure from.
  document.frames["frame:wall-time"] = {
    id: "frame:wall-time",
    title: "Wall time",
    traits: ["line", "temporal", "gregorian"],
    coordinate: clone(GREGORIAN_DECLARATION)
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
    } else if (relation.type === "staple") {
      validateStaple(document, relation, errors);
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
    const patternId = overridePatternId(override);
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

// A staple is a member of an OPEN COLLECTION on an object, authored as data
// rather than a rewrite of anything (LEXICON.md's staple anchoring and the
// Rob-and-John scenario). It is NOT the same concept as a `termination`
// relation, which seals or staples a *line* in the time-travel taxonomy
// (validateTermination, above) -- a staple's `series` names a pattern, a
// staple's `object` names an event, a termination's `line` names a frame, and
// none of the three ever interchange.
//
// `kind` is validated against src/staples.js's STAPLE_KINDS registry rather
// than hardcoded to "end", which is the mechanism the owner found missing:
// "I see no clear mechanism to add an arbitrary number or type of staples."
// Adding a kind is one registry entry plus its interpretation. An unregistered
// kind is still refused, for the reason the original note here gave -- a kind
// nothing honours is a shape that silently moves things on screen, or silently
// fails to -- but the registry is now the extension path that was absent.
//
// Every shipped record (`{series, kind: "end", frame, coordinate}`) stays valid
// with no migration: `object`, `role`, `spread` and `payload` are all optional.
function validateMagnitudeShape(document, value, label, errors) {
  if (value === undefined) return;
  if (!value || typeof value !== "object") {
    errors.push(`${label} must be a magnitude object`);
    return;
  }
  if (value.frame !== undefined && !document.frames?.[value.frame]) {
    errors.push(`${label} references a missing frame`);
  }
  if (!Array.isArray(value.value?.levels)) errors.push(`${label} lacks a nested value`);
}

// A frame end declares EXACTLY ONE position form (src/staples.js's
// END_POSITION_FORMS): one coordinate, a selector into this frame's own declared
// cycles or levels, a span, or an authored void. More than one is two claims
// wearing one record, and none is an end that names a frame without saying where
// on it.
//
// A selector's `cycle`/`level` is checked against the frame's OWN law, so a
// selector naming something that frame never declared is refused rather than
// silently matching nothing forever -- the same reasoning the coordinate law
// applies to an unresolvable declaration.
function validateEndPosition(document, end, label, errors, definition = null) {
  // A kind may declare that its ends carry no position at all (`positions:
  // false` -- a succession, whose boundary is derived from the eras it joins).
  // Read from the registry rather than by naming the kind, so a future
  // positionless kind needs no edit here.
  if (definition && definition.positions === false) {
    const declared = ["coordinate", "selector", "span"].filter((form) =>
      end[form] !== undefined && end[form] !== null);
    if (declared.length) {
      errors.push(`${label} declares a ${declared[0]}, but this kind's ends carry no position`);
    }
    return;
  }
  const declared = ["coordinate", "selector", "span", "void"].filter((form) =>
    form === "void" ? end.void === true : end[form] !== undefined && end[form] !== null);
  if (declared.length !== 1) {
    errors.push(
      declared.length === 0
        ? `${label} needs a position: a coordinate, a selector, a span, or an authored void`
        : `${label} declares ${declared.join(" and ")}; an end has exactly one position`
    );
    return;
  }
  const [form] = declared;
  if (form === "void") return;
  if (form === "coordinate") {
    if (!isCoordinate(end.coordinate)) errors.push(`${label} coordinate must use nested levels`);
    return;
  }
  if (form === "span") {
    if (!isCoordinate(end.span?.from) || !isCoordinate(end.span?.to)) {
      errors.push(`${label} span needs a from and a to coordinate, both using nested levels`);
    }
    return;
  }
  const selector = end.selector;
  if (!selector || typeof selector !== "object" || (!selector.cycle && !selector.level)) {
    errors.push(`${label} selector must name a cycle or a level`);
    return;
  }
  if (selector.cycle && selector.level) {
    errors.push(`${label} selector names both a cycle and a level; it names one`);
    return;
  }
  if (selector.value === undefined || selector.value === null || String(selector.value).trim() === "") {
    errors.push(`${label} selector needs a value`);
    return;
  }
  let law = null;
  try {
    law = coordinateLaw(document, end.frame);
  } catch {
    // An unresolvable declaration is already reported against the frame itself;
    // reporting it a second time here would name the wrong record as the fault.
    return;
  }
  if (selector.cycle && !law.cycle(selector.cycle)) {
    errors.push(`${label} selector names the cycle "${selector.cycle}", which this frame does not declare`);
  }
  if (selector.level && !law.has(selector.level)) {
    errors.push(`${label} selector names the level "${selector.level}", which this frame does not declare`);
  }
}

// One end of a connection, validated for the map it points into and for the
// touch point it claims. A frame end must carry the coordinate its frame's law
// gives meaning to; an object end must carry a point name, because "which point"
// is the whole content of the connection at that end.
function validateStapleEnd(document, relation, end, index, errors) {
  const label = `Staple ${relation.id} end ${index + 1}`;
  const scope = endScope(end);
  if (!scope) {
    errors.push(`${label} must name a frame, an object, or a series`);
    return;
  }
  const named = [end.frame, end.object, end.series].filter(Boolean);
  if (named.length > 1) {
    errors.push(`${label} names more than one thing; an end connects to exactly one`);
    return;
  }
  if (scope === "frame") {
    if (!document.frames?.[end.frame]) errors.push(`${label} references a missing frame`);
    validateEndPosition(document, end, label, errors, stapleKind(relation.kind));
    return;
  }
  if (scope === "series") {
    if (!document.patterns?.[end.series]) errors.push(`${label} references a missing series`);
    return;
  }
  if (!document.events?.[end.object]) errors.push(`${label} references a missing object`);
  if (end.point !== undefined && (typeof end.point !== "string" || !end.point.trim())) {
    errors.push(`${label} point must be a non-empty name`);
  }
  validateMagnitudeShape(document, end.offset, `${label} offset`, errors);
}

function validateStaple(document, relation, errors) {
  // Exactly two ends: a staple connects TWO things at a point. One end is an
  // attribute pretending to be an edge and three is a relation nobody has
  // defined, so both are refused rather than resolved by dropping one.
  const ends = stapleEnds(relation);
  if (!Array.isArray(relation.ends) || relation.ends.length !== 2 || ends.length !== 2) {
    errors.push(`Staple ${relation.id} must connect exactly two things`);
  }
  for (const [index, end] of ends.entries()) validateStapleEnd(document, relation, end, index, errors);
  // A frame may be stapled to ITSELF at two different coordinates: that is a
  // nonlinear line crossing its own path, which the correspondence model exists
  // to carry. Two ends at the same coordinate say nothing, and an object or
  // series stapled to itself says nothing either -- an object's own start-to-end
  // span is its duration magnitude, not a connection.
  if (ends.length === 2 && endId(ends[0]) === endId(ends[1])) {
    if (endScope(ends[0]) !== "frame") {
      errors.push(`Staple ${relation.id} connects one ${endScope(ends[0])} to itself`);
    } else if (JSON.stringify(ends[0].coordinate) === JSON.stringify(ends[1].coordinate)) {
      errors.push(`Staple ${relation.id} connects one point to itself`);
    }
  }
  if (ends.filter((end) => endScope(end) === "series").length > 1) {
    errors.push(`Staple ${relation.id} connects two series, which is not defined`);
  }

  const definition = stapleKind(relation.kind);
  if (!definition) {
    errors.push(
      `Staple ${relation.id} kind must be one of ${Object.keys(STAPLE_KINDS).join(", ")}`
    );
  } else if (ends.length === 2) {
    // A kind is defined by the PAIR of scopes it may join, so the check is one
    // canonical-key lookup rather than two half-checks that could disagree.
    const pair = endScopePair(endScope(ends[0]), endScope(ends[1]));
    if (!definition.connects.includes(pair)) {
      errors.push(
        `Staple ${relation.id} kind "${relation.kind}" cannot connect ${pair.replace("+", " to ")}`
        + `; it connects ${definition.connects.join(" or ")}`
      );
    }
  }

  // Fuzziness is per-staple data, so it validates as data: two magnitudes,
  // either of which may be absent. An asymmetric spread is the point -- "about
  // 5ish" and a hard ceiling are different shapes.
  if (relation.spread !== undefined) {
    if (!relation.spread || typeof relation.spread !== "object") {
      errors.push(`Staple ${relation.id} spread must be an object`);
    } else {
      validateMagnitudeShape(document, relation.spread.before, `Staple ${relation.id} spread before`, errors);
      validateMagnitudeShape(document, relation.spread.after, `Staple ${relation.id} spread after`, errors);
    }
  }

  // A following rule is only meaningful on a kind that partitions a series'
  // rules. Carried inside the staple's own record so a rule change is one
  // record-level op, journalled and undone like anything else.
  const head = relation.payload?.rule;
  if (head !== undefined) {
    if (!definition?.carriesRule) {
      errors.push(`Staple ${relation.id} kind "${relation.kind}" cannot carry a following rule`);
    } else if (!head || typeof head !== "object") {
      errors.push(`Staple ${relation.id} following rule must be an object`);
    } else {
      if (!head.rrule || typeof head.rrule !== "object") {
        errors.push(`Staple ${relation.id} following rule requires an rrule`);
      }
      if (head.coordinate !== undefined && !isCoordinate(head.coordinate)) {
        errors.push(`Staple ${relation.id} following rule coordinate must use nested levels`);
      }
      if (head.frame !== undefined && !document.frames?.[head.frame]) {
        errors.push(`Staple ${relation.id} following rule references a missing frame`);
      }
      validateMagnitudeShape(document, head.magnitude, `Staple ${relation.id} following rule magnitude`, errors);
      for (const frameId of head.exclude?.frames || (head.exclude?.frame ? [head.exclude.frame] : [])) {
        if (!document.frames?.[frameId]) {
          errors.push(`Staple ${relation.id} following rule excludes a missing frame`);
        }
      }
    }
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

// Both directions are now one line each, because the dispatch they used to
// perform (walk `coordinateDefinition`, then branch on `kind: "gregorian"` into
// hardcoded civil functions, then fall through to `basis`) IS the coordinate law
// -- and running it from a frame's own declaration instead of from a hardcoded
// branch is what makes an edited ladder take effect. See src/coordinate-law.js.
export function coordinateToDays(document, frameId, value) {
  return coordinateLaw(document, frameId).toDays(value);
}

export function daysToCoordinate(document, frameId, days) {
  return coordinateLaw(document, frameId).fromDays(days);
}

// An override names the occurrence it acts on by a virtual id, which
// `stableVirtualId` builds as `${patternId}/${encodedKey}`. The key is
// percent-encoded, so the last slash is always the boundary — and every consumer
// has to split it the same way or repair and validation will disagree about which
// pattern an override belongs to. That is what this pair exists for: one
// derivation, used by validateDocument, the load-time repair in store.js, the
// undo bundles in ui/transactions.js, and the sync reconciler.
export function virtualPatternId(virtualId) {
  const virtual = typeof virtualId === "string" ? virtualId : "";
  const boundary = virtual.lastIndexOf("/");
  return boundary > 0 ? virtual.slice(0, boundary) : "";
}

export function overridePatternId(override) {
  return virtualPatternId(override?.virtual);
}

// An override belongs to its pattern the way a relation belongs to an event: it
// means "this occurrence of that series is suppressed or replaced". Once the
// series is gone the record can never match a fact again, so deleting a pattern
// without its overrides leaves pointers to nothing — and validateDocument rejects
// the document at its next load, which is how a handful of dead pointers can take
// an entire file offline. Returns how many it removed so callers can report.
export function removeOverridesForPatterns(document, patternIds) {
  const removed = patternIds instanceof Set ? patternIds : new Set(patternIds);
  if (!removed.size) return 0;
  let count = 0;
  for (const [id, override] of Object.entries(document?.overrides || {})) {
    if (!removed.has(overridePatternId(override))) continue;
    delete document.overrides[id];
    count += 1;
  }
  return count;
}

// A staple belongs to its series the way an override does (see
// `removeOverridesForPatterns`, just above): once the series is gone the
// staple can never intersect a projection again, so it travels with pattern
// deletion in the same undoable transaction rather than surviving as a
// pointer to nothing. Returns how many it removed so callers can report.
export function removeStaplesForPatterns(document, patternIds) {
  return removeStaplesReferencing(document, patternIds);
}

// The one sweep both cascades share. A staple has two ends, so "does this
// connection point at a record I am deleting" is a question about EITHER end --
// deleting one event of a stapled pair has to take the connection with it, or
// the surviving event keeps an anchor to nothing and one bad pointer takes the
// whole file offline at its next load.
function removeStaplesReferencing(document, ids) {
  const removed = ids instanceof Set ? ids : new Set(ids);
  if (!removed.size) return 0;
  let count = 0;
  for (const [id, relation] of Object.entries(document?.relations || {})) {
    if (relation?.type !== "staple" || !stapleTouchesAny(relation, removed)) continue;
    delete document.relations[id];
    count += 1;
  }
  return count;
}

// The object-keyed sibling of `removeStaplesForPatterns`, just above. Staples
// are an open collection on ANY object now, so an event's deletion has to
// sweep its own staples exactly the way a pattern's deletion sweeps its own --
// same invariant, same transaction. Otherwise a deleted event leaves staples
// pointing at nothing, and one bad pointer takes the whole file offline at its
// next load.
export function removeStaplesForObjects(document, objectIds) {
  return removeStaplesReferencing(document, objectIds);
}

export { removeStaplesReferencing };

// The three end builders. A staple's ends are data, not prose, and an authoring
// surface that hand-wrote the object literal would be a second place the shape
// is defined -- so these are the shape, and `putStaple` takes what they return.
export function frameEnd(frame, coordinateValue, parameters = null) {
  return {
    frame,
    coordinate: coordinateValue,
    ...(parameters ? { parameters } : {})
  };
}

export function objectEnd(object, point = DEFAULT_POINT, offset = null) {
  return {
    object,
    point,
    ...(offset ? { offset } : {})
  };
}

export function seriesEnd(series) {
  return { series };
}

// A position in one of the frame's own declared cycles or levels: "Tuesdays",
// "July". Many-valued by construction, which is why it is a distinct form
// rather than a coordinate with levels left off -- a partial coordinate is one
// instant at coarse precision, a selector is every instant that satisfies it.
export function selectorEnd(frame, selector) {
  return { frame, selector };
}

export function spanEnd(frame, from, to) {
  return { frame, span: { from, to } };
}

// "Sometimes never", authored. Distinct from the absence of a staple, which says
// only that nobody has said yet.
export function voidEnd(frame) {
  return { frame, void: true };
}

// Placing and removing staples, generalized.
//
// The collection is open: an object may carry arbitrarily many staples of
// arbitrary kind, arbitrarily placed (LEXICON.md). So `putStaple` ADDS by
// default and only updates when handed an explicit `id`. The shipped
// "re-placing updates the one staple" behavior survives in
// `setSeriesEndStaple` below, because for a single end-staple editor field it
// is still right -- but it is no longer what the substrate assumes about
// staples in general, which is exactly the presupposition the owner rejected.
//
// Mutates in place like `suppressVirtual`/`stapleEvents` above; the caller
// wraps this in a transaction.
export function putStaple(document, input = {}) {
  const existing = input.id ? document.relations?.[input.id] : null;
  if (existing && existing.type === "staple") {
    for (const key of Object.keys(existing)) {
      if (key !== "id" && key !== "type") delete existing[key];
    }
    Object.assign(existing, clone({ ...input, id: existing.id, type: "staple" }));
    touch(document);
    return existing;
  }
  const relation = clone({
    ...input,
    id: input.id || createId("relation"),
    type: "staple"
  });
  document.relations[relation.id] = relation;
  touch(document);
  return relation;
}

export function removeStaple(document, stapleId) {
  const existing = document?.relations?.[stapleId];
  if (!existing || existing.type !== "staple") return false;
  delete document.relations[stapleId];
  touch(document);
  return true;
}

// Every staple on a series or an object, in a stable, deterministic order
// (relation id). Deliberately not called authoring order: ids are random UUIDs
// and carry no creation sequence. See `byStableOrder` in src/staples.js -- what
// a tie-break needs is a total order identical across reload and journal
// replay, which object key order does not promise.
//
// Requires a selector: an unfiltered call would return every staple in the
// document, which no caller wants and which would silently "work" while
// meaning something else entirely.
export function staplesFor(document, { series = null, object = null } = {}) {
  if (!series && !object) return [];
  return Object.values(document?.relations || {})
    .filter((relation) => relation?.type === "staple"
      && (!series || stapleReferencesId(relation, series))
      && (!object || stapleReferencesId(relation, object)))
    .sort((left, right) => String(left.id).localeCompare(String(right.id)));
}

// The one place that finds a series' end-staple, shared by the engine (the
// projection intersects the rule's own extent with this), the series editor
// (to show/clear it), and ICS export (to derive the effective UNTIL without
// ever writing the staple into the rule).
//
// A thin named wrapper over the open collection now, rather than the
// substrate's own idea of a privileged record. `kind: "end"` is one registry
// entry among several (src/staples.js); this is the convenience a
// single-end-staple field still wants.
export function seriesEndStaple(document, patternId) {
  if (!patternId) return null;
  return Object.values(document?.relations || {}).find((relation) =>
    relation?.type === "staple" && relation.kind === "end" && stapleReferencesId(relation, patternId)) || null;
}

export function setSeriesEndStaple(document, patternId, frame, coordinateValue, parameters = null) {
  const existing = seriesEndStaple(document, patternId);
  return putStaple(document, {
    ...(existing ? { id: existing.id } : {}),
    kind: "end",
    ends: [seriesEnd(patternId), frameEnd(frame, coordinateValue, parameters)]
  });
}

export function clearSeriesEndStaple(document, patternId) {
  const existing = seriesEndStaple(document, patternId);
  return existing ? removeStaple(document, existing.id) : false;
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
