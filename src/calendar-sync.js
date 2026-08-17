import { importICS, property } from "./ics.js";
import { clone, createDocument, touch } from "./model.js";

function sourceFrame(document, sourceId) {
  return Object.values(document.frames || {}).find((frame) => frame?.foreign?.ics?.source === sourceId) || null;
}

function sourceEventKey(event) {
  const component = event?.foreign?.ics?.component;
  const uid = event?.payload?.uid || (component ? property(component, "UID")?.value : "") || "";
  const recurrence = component ? property(component, "RECURRENCE-ID")?.value || "" : "";
  return `${component?.name || "VEVENT"}\u0000${uid}\u0000${recurrence}`;
}

function sourcePatternKey(pattern) {
  return `${pattern?.kind || "pattern"}\u0000${pattern?.provenance?.uid || pattern?.title || ""}`;
}

function sourceRelationKey(relation) {
  return `${relation?.event || ""}\u0000${relation?.role || ""}\u0000${relation?.parameters?.stamp ? "stamp" : ""}`;
}

function sourceOwned(value, sourceId) {
  return value?.provenance?.source === sourceId;
}

function replaceSourceReference(value, from, to) {
  const next = clone(value);
  if (next?.foreign?.ics?.source === from) next.foreign.ics.source = to;
  if (next?.provenance?.source === from) next.provenance.source = to;
  if (next?.codec?.source === from) next.codec.source = to;
  return next;
}

function eventBindings(document, sourceId) {
  const bindings = new Map();
  for (const event of Object.values(document.events || {})) {
    if (event?.foreign?.ics?.source === sourceId) {
      bindings.set(sourceEventKey(event), { kind: "event", event, targetId: event.id });
    }
    for (const staple of event?.foreign?.stapled || []) {
      if (staple?.foreign?.ics?.source !== sourceId) continue;
      bindings.set(sourceEventKey({ payload: staple.payload, foreign: staple.foreign }), {
        kind: "staple", event, staple, targetId: event.id
      });
    }
  }
  return bindings;
}

function removeDanglingEventReferences(document, eventId) {
  for (const [id, relation] of Object.entries(document.relations || {})) {
    if (relation.event === eventId || relation.member === eventId) delete document.relations[id];
  }
  for (const [id, pattern] of Object.entries(document.patterns || {})) {
    if (pattern.templateEvent === eventId) delete document.patterns[id];
  }
  for (const [id, override] of Object.entries(document.overrides || {})) {
    override.replacements = (override.replacements || []).filter((value) => value !== eventId);
    if (!override.replacements.length && override.suppress !== true) delete document.overrides[id];
  }
}

function removeSourceOwnedRecords(document, sourceId) {
  for (const [id, value] of Object.entries(document.relations || {})) {
    if (sourceOwned(value, sourceId)) delete document.relations[id];
  }
  for (const [id, value] of Object.entries(document.patterns || {})) {
    if (sourceOwned(value, sourceId)) delete document.patterns[id];
  }
  for (const [id, value] of Object.entries(document.overrides || {})) {
    if (sourceOwned(value, sourceId)) delete document.overrides[id];
  }
}

function removeSource(document, sourceId) {
  const frame = sourceFrame(document, sourceId);
  removeSourceOwnedRecords(document, sourceId);
  for (const [id, event] of Object.entries(document.events || {})) {
    if (event?.foreign?.ics?.source === sourceId) {
      delete document.events[id];
      removeDanglingEventReferences(document, id);
      continue;
    }
    if (event?.foreign?.stapled) {
      event.foreign.stapled = event.foreign.stapled.filter((entry) => entry?.foreign?.ics?.source !== sourceId);
      if (!event.foreign.stapled.length) delete event.foreign.stapled;
    }
  }
  if (frame) {
    for (const [id, relation] of Object.entries(document.relations || {})) {
      if (relation.frame === frame.id || relation.parent === frame.id || relation.child === frame.id) {
        delete document.relations[id];
      }
    }
    delete document.frames[frame.id];
  }
  delete document.foreign?.ics?.sources?.[sourceId];
}

function addSource(document, scratch, sourceId) {
  const source = scratch.foreign.ics.sources[sourceId];
  const frame = sourceFrame(scratch, sourceId);
  document.foreign.ics.sources[sourceId] = clone(source);
  if (frame) document.frames[frame.id] = clone(frame);
  for (const event of Object.values(scratch.events)) {
    if (event?.foreign?.ics?.source === sourceId) document.events[event.id] = clone(event);
  }
  for (const [name, records] of [["relations", scratch.relations], ["patterns", scratch.patterns], ["overrides", scratch.overrides]]) {
    for (const value of Object.values(records)) {
      if (sourceOwned(value, sourceId)) document[name][value.id] = clone(value);
    }
  }
  return frame?.id || null;
}

function reconcileSource(document, scratch, previousSourceId, incomingSourceId) {
  const previousFrame = sourceFrame(document, previousSourceId);
  const incomingFrame = sourceFrame(scratch, incomingSourceId);
  const bindings = eventBindings(document, previousSourceId);
  const matchedKeys = new Set();
  const eventIdMap = new Map();
  const oldRelations = Object.values(document.relations).filter((value) => sourceOwned(value, previousSourceId));
  const oldPatterns = Object.values(document.patterns).filter((value) => sourceOwned(value, previousSourceId));
  const relationIds = new Map();
  const patternIds = new Map();

  removeSourceOwnedRecords(document, previousSourceId);

  for (const incomingEvent of Object.values(scratch.events).filter((event) => event?.foreign?.ics?.source === incomingSourceId)) {
    const key = sourceEventKey(incomingEvent);
    const binding = bindings.get(key);
    matchedKeys.add(key);
    if (binding?.kind === "event") {
      const preservedDisplay = binding.event.display;
      const next = replaceSourceReference(incomingEvent, incomingSourceId, previousSourceId);
      next.id = binding.targetId;
      if (preservedDisplay) next.display = preservedDisplay;
      document.events[binding.targetId] = next;
      eventIdMap.set(incomingEvent.id, binding.targetId);
    } else if (binding?.kind === "staple") {
      const next = replaceSourceReference(incomingEvent, incomingSourceId, previousSourceId);
      binding.staple.payload = clone(next.payload);
      binding.staple.foreign = clone(next.foreign);
      eventIdMap.set(incomingEvent.id, binding.targetId);
    } else {
      const next = replaceSourceReference(incomingEvent, incomingSourceId, previousSourceId);
      document.events[next.id] = next;
      eventIdMap.set(incomingEvent.id, next.id);
    }
  }

  for (const [key, binding] of bindings) {
    if (matchedKeys.has(key)) continue;
    if (binding.kind === "event") {
      delete document.events[binding.targetId];
      removeDanglingEventReferences(document, binding.targetId);
    } else {
      binding.event.foreign.stapled = binding.event.foreign.stapled.filter((entry) => entry !== binding.staple);
      if (!binding.event.foreign.stapled.length) delete binding.event.foreign.stapled;
    }
  }

  const previousFrameId = previousFrame?.id || incomingFrame?.id;
  for (const incoming of Object.values(scratch.relations).filter((value) => sourceOwned(value, incomingSourceId))) {
    const next = replaceSourceReference(incoming, incomingSourceId, previousSourceId);
    next.event = eventIdMap.get(next.event) || next.event;
    if (next.frame === incomingFrame?.id) next.frame = previousFrameId;
    const reusable = oldRelations.find((value) => sourceRelationKey(value) === sourceRelationKey(next));
    if (reusable) next.id = reusable.id;
    relationIds.set(incoming.id, next.id);
    document.relations[next.id] = next;
  }

  for (const incoming of Object.values(scratch.patterns).filter((value) => sourceOwned(value, incomingSourceId))) {
    const next = replaceSourceReference(incoming, incomingSourceId, previousSourceId);
    const reusable = oldPatterns.find((value) => sourcePatternKey(value) === sourcePatternKey(next));
    if (reusable) next.id = reusable.id;
    patternIds.set(incoming.id, next.id);
    next.frame = next.frame === incomingFrame?.id ? previousFrameId : next.frame;
    next.appliesTo = (next.appliesTo || []).map((id) => id === incomingFrame?.id ? previousFrameId : id);
    next.templateEvent = eventIdMap.get(next.templateEvent) || next.templateEvent;
    next.templateRelation = relationIds.get(next.templateRelation) || next.templateRelation;
    document.patterns[next.id] = next;
  }

  for (const incoming of Object.values(scratch.overrides).filter((value) => sourceOwned(value, incomingSourceId))) {
    const next = replaceSourceReference(incoming, incomingSourceId, previousSourceId);
    for (const [from, to] of patternIds) {
      if (next.virtual?.startsWith(`${from}/`)) next.virtual = `${to}${next.virtual.slice(from.length)}`;
    }
    next.replacements = (next.replacements || []).map((id) => eventIdMap.get(id) || id);
    document.overrides[next.id] = next;
  }

  const incomingSource = replaceSourceReference(scratch.foreign.ics.sources[incomingSourceId], incomingSourceId, previousSourceId);
  incomingSource.id = previousSourceId;
  document.foreign.ics.sources[previousSourceId] = incomingSource;
  if (incomingFrame) {
    const nextFrame = replaceSourceReference(incomingFrame, incomingSourceId, previousSourceId);
    nextFrame.id = previousFrameId;
    if (previousFrame?.display) nextFrame.display = clone(previousFrame.display);
    if (previousFrame?.color) nextFrame.color = previousFrame.color;
    document.frames[previousFrameId] = nextFrame;
  }
  return previousFrameId;
}

export function applyICSSnapshot(document, {
  connectionId,
  text,
  label = "Subscribed calendar",
  provider = "ics",
  revision = null,
  fetchedAt = new Date().toISOString()
}) {
  if (!connectionId) throw new Error("Calendar sync connection ID is required");
  const scratch = createDocument("Calendar sync import");
  const imported = importICS(text, scratch, { label });
  document.foreign ||= {};
  document.foreign.ics ||= { sources: {} };
  const previous = Object.values(document.foreign.ics.sources).filter(
    (source) => source?.sync?.connectionId === connectionId
  );
  const previousByKey = new Map(previous.map((source) => [source.sync.calendarKey, source]));
  const retained = new Set();
  const frames = [];

  const incomingSources = Object.values(scratch.foreign.ics?.sources || {});
  for (const [index, source] of incomingSources.entries()) {
    const calendarKey = property(source.component, "X-CHRONOLOG-SOURCE-ID")?.value || String(index);
    source.sync = { connectionId, calendarKey, provider, revision, fetchedAt, readOnly: true };
    const matched = previousByKey.get(calendarKey);
    if (matched) {
      retained.add(matched.id);
      frames.push(reconcileSource(document, scratch, matched.id, source.id));
    } else {
      frames.push(addSource(document, scratch, source.id));
    }
  }
  for (const source of previous) {
    if (!retained.has(source.id)) removeSource(document, source.id);
  }
  touch(document);
  return {
    connectionId,
    frames: frames.filter(Boolean),
    calendars: incomingSources.length,
    events: imported.events.length,
    warnings: imported.warnings,
    suggestions: imported.suggestions
  };
}

export function calendarSyncConnections(document) {
  const connections = new Map();
  for (const source of Object.values(document?.foreign?.ics?.sources || {})) {
    if (!source?.sync?.connectionId) continue;
    const current = connections.get(source.sync.connectionId) || {
      id: source.sync.connectionId,
      provider: source.sync.provider || "ics",
      labels: [],
      fetchedAt: source.sync.fetchedAt || null,
      revision: source.sync.revision || null,
      readOnly: source.sync.readOnly !== false
    };
    current.labels.push(source.label || source.id);
    if (source.sync.fetchedAt > current.fetchedAt) current.fetchedAt = source.sync.fetchedAt;
    connections.set(current.id, current);
  }
  return [...connections.values()];
}

