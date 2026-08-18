import { clone } from "../model.js";
import { bundleOps, recordOps } from "../ops.js";

// Document-mutation-with-undo helpers shared by the inspector and Frames
// panel. `app` carries the live `chronolog`/`history` references (they are
// reassigned whenever the workspace document is replaced), so every
// exported function re-reads them from `app` at call time rather than
// closing over a value captured once at construction time.
export function createTransactions(app) {
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

  // The before/after bundles are exactly the records this edit can reach, so
  // they convert straight into the journal's op list. `metadata` is filled in
  // from inside `apply`, which runs before `executeDelta` emits the change —
  // and again on redo, which keeps the ops current for a replayed apply.
  function executeEventChange(label, eventId, mutate, preserveRecurrence = false) {
    const { chronolog, history } = app;
    const before = captureEventBundle(chronolog, eventId);
    let after = null;
    const metadata = { preserveRecurrence };
    history.executeDelta(label, (documentValue) => {
      if (after) restoreEventBundle(documentValue, eventId, after);
      else {
        mutate(documentValue);
        after = captureEventBundle(documentValue, eventId, before.trackedOverrideIds);
      }
      Object.assign(metadata, bundleOps(before, after, { eventId }));
    }, (documentValue) => restoreEventBundle(documentValue, eventId, before), metadata);
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
    const { chronolog, history } = app;
    const before = captureEventSetBundle(chronolog, eventIds);
    let after = null;
    const metadata = {};
    history.executeDelta(label, (documentValue) => {
      if (after) restoreEventSetBundle(documentValue, eventIds, after);
      else {
        mutate(documentValue);
        after = captureEventSetBundle(documentValue, eventIds);
      }
      Object.assign(metadata, bundleOps(before, after));
    }, (documentValue) => restoreEventSetBundle(documentValue, eventIds, before), metadata);
  }

  function executeRecordChange(label, mapName, recordId, mutate, metadata = {}) {
    const { chronolog, history } = app;
    const before = clone(chronolog[mapName][recordId]);
    let after = null;
    const change = { preserveRecurrence: mapName !== "patterns", ...metadata };
    history.executeDelta(label, (documentValue) => {
      if (after) documentValue[mapName][recordId] = clone(after);
      else {
        mutate(documentValue);
        after = clone(documentValue[mapName][recordId]);
      }
      Object.assign(change, recordOps(mapName, recordId, before, after));
    }, (documentValue) => {
      if (before === undefined) delete documentValue[mapName][recordId];
      else documentValue[mapName][recordId] = clone(before);
    }, change);
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
    const { chronolog, history } = app;
    const before = captureFrameBundle(chronolog, frameId);
    let after = null;
    const metadata = {};
    history.executeDelta(label, (documentValue) => {
      if (after) restoreFrameBundle(documentValue, frameId, after);
      else {
        mutate(documentValue);
        after = captureFrameBundle(documentValue, frameId);
      }
      Object.assign(metadata, bundleOps(before, after, { frameId }));
    }, (documentValue) => restoreFrameBundle(documentValue, frameId, before), metadata);
  }

  return { executeEventChange, executeEventSetChange, executeRecordChange, executeFrameChange };
}
