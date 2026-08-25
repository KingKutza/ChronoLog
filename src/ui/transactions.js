import { Rational, nowDays } from "../exact.js";
import { GREGORIAN_LAW, coordinateLaw } from "../coordinate-law.js";
import {
  addEvent,
  addRelation,
  clone,
  createId,
  durationMagnitude,
  overridePatternId,
  removeContainsForObjects,
  removeMembershipsForMembers,
  removeOverridesForPatterns,
  removeStaplesForObjects,
  removeStaplesForPatterns,
  stableVirtualId
} from "../model.js";
import { OBJECT_KINDS, STATE_FRAME_TRAITS, isStateFrame, traitsForObjectKind } from "../object-kinds.js";
import { bundleOps, delOp, putOp, recordOps } from "../ops.js";
import { stapleReferencesId, stapleTouchesAny } from "../staples.js";
import { applySeriesHeal, healCandidateIds, planSeriesHeal } from "../series-heal.js";

// Document-mutation-with-undo helpers shared by the inspector and Frames
// panel. `app` carries the live `chronolog`/`history` references (they are
// reassigned whenever the workspace document is replaced), so every
// exported function re-reads them from `app` at call time rather than
// closing over a value captured once at construction time.
// A relation belongs to an object through whichever field names it: `event`
// (attachments), `member` (memberships -- state affiliations included), or
// either end of a containment edge. The one predicate every bundle capture and
// restore below asks, so a new way for a relation to name an object is one
// edit here rather than one missed filter per bundle shape.
function relationNamesObject(relation, ids) {
  return ids.has(relation.event) || ids.has(relation.member)
    || (relation.type === "contains" && (ids.has(relation.parent) || ids.has(relation.child)));
}

// The state frames a transaction can touch: the first completion toggle mints
// the Done frame inside its own bundle, so bundles capture every state frame
// (a small set by construction) and restores clear-then-reassign them the same
// way they already treat the object's own relations. Undo of the minting
// toggle is what removes the frame again.
function stateFrameEntries(documentValue) {
  return Object.entries(documentValue.frames || {}).filter(([, frame]) => isStateFrame(frame));
}

export function createTransactions(app) {
  // A bundle that can delete a pattern has to carry that pattern's overrides, or
  // undo brings the series back without its exceptions and redo leaves pointers
  // to nothing. Every capture below therefore tracks overrides two ways: by the
  // event they replace, and by the pattern they belong to.
  function trackPatternOverrides(documentValue, patterns, tracked) {
    const patternIds = new Set(Object.keys(patterns));
    if (!patternIds.size) return tracked;
    for (const [id, override] of Object.entries(documentValue.overrides)) {
      if (patternIds.has(overridePatternId(override))) tracked.add(id);
    }
    return tracked;
  }

  // A staple belongs to its series exactly the way an override belongs to its
  // pattern (see `removeStaplesForPatterns` in model.js). Every bundle that
  // tracks a scope's overrides tracks its staples the same way, so a series
  // that is deleted, or a frame/event whose deletion cascades to its series,
  // takes its end-staple with it -- and undo restores both together.
  function trackPatternStaples(documentValue, patterns, tracked) {
    const patternIds = new Set(Object.keys(patterns));
    if (!patternIds.size) return tracked;
    for (const [id, relation] of Object.entries(documentValue.relations)) {
      if (relation.type === "staple" && stapleTouchesAny(relation, patternIds)) tracked.add(id);
    }
    return tracked;
  }

  // The object-keyed sibling of `trackPatternStaples`, just above. A staple on
  // an OBJECT belongs to that object the way a staple on a series belongs to
  // its pattern, so a bundle that can delete an event has to track that
  // event's own staples the same way it tracks its series' staples -- or undo
  // would restore the event without them.
  function trackObjectStaples(documentValue, objectIds, tracked) {
    // `removeStaplesForObjects` (model.js) accepts either a Set or a plain
    // iterable; every caller here passes whichever shape it already has on
    // hand (an array in `captureEventBundle`, a Set in `captureEventSetBundle`
    // and `capturePatternBundle`), so this normalizes the same way rather than
    // assuming one shape.
    const ids = objectIds instanceof Set ? objectIds : new Set([...(objectIds || [])].filter(Boolean));
    if (!ids.size) return tracked;
    for (const [id, relation] of Object.entries(documentValue.relations)) {
      if (relation.type === "staple" && stapleTouchesAny(relation, ids)) tracked.add(id);
    }
    return tracked;
  }

  // The series convergence invariant, run as a sibling of cascadeRemovedPatterns:
  // a post-mutation settling step inside the same undoable transaction.
  //
  // Owner ruling (8.19): a fork is not the problem, an *unhealed* fork is. So this
  // is not flow control and asks nothing about what the user did — it re-examines
  // the state and, wherever a materialized occurrence now says exactly what its
  // series already says, deletes the override and its event so the projection
  // reasserts. See src/series-heal.js.
  //
  // Two reasons this belongs here rather than in the inspector. First, it then
  // applies to every edit that routes through these helpers, not only to edits made
  // through the editor — which is what makes it a law instead of a code path.
  // Second, the surrounding bundle already tracks the override (via
  // `replacements.includes(eventId)`) and the event itself, so the heal's removals
  // fall out of `bundleOps` as ordinary del ops and `restoreEventBundle` brings
  // the override and its event back together on undo. Undo stays bundle-clean for
  // free rather than by a second mechanism.
  //
  // `healCandidateIds` is a cheap scan over overrides and is checked first, so an
  // ordinary edit to an ordinary event never pays for an engine rebuild.
  function convergeSeries(documentValue, scope) {
    const candidates = healCandidateIds(documentValue, scope);
    if (!candidates.length) return 0;
    // The engine's indices are stale against the mutation just applied, so they
    // have to be refreshed before the projection can be trusted.
    const engine = app.refreshEngine?.(documentValue) || app.engine;
    if (!engine) return 0;
    const plan = planSeriesHeal(documentValue, engine, { overrideIds: candidates });
    return applySeriesHeal(documentValue, plan);
  }

  // Run after a mutation: whatever patterns this bundle captured and the mutation
  // removed take their overrides with them, inside the same undoable transaction.
  // Scoped to the bundle's own patterns on purpose — sweeping orphans that were
  // already in the document is the load-time repair's job, not an edit's.
  function cascadeRemovedPatterns(documentValue, patterns) {
    const removed = new Set();
    for (const patternId of Object.keys(patterns || {})) {
      if (!documentValue.patterns[patternId]) removed.add(patternId);
    }
    removeOverridesForPatterns(documentValue, removed);
    removeStaplesForPatterns(documentValue, removed);
  }

  // The object-keyed sibling of `cascadeRemovedPatterns`, just above, and the
  // actual cascade AGENTS.md asks for: "deleting an event must delete its
  // overrides [staples] in the same undoable transaction." Scoped to the
  // bundle's own candidate event ids for the same reason the pattern sweep is
  // scoped to its own patterns — sweeping every orphaned object staple in the
  // document is the load-time repair's job, not one edit's.
  function cascadeRemovedObjects(documentValue, candidateEventIds) {
    const removed = new Set();
    for (const eventId of candidateEventIds || []) {
      if (eventId && !documentValue.events[eventId]) removed.add(eventId);
    }
    removeStaplesForObjects(documentValue, removed);
    // Containment edges and memberships (state affiliations included) name a
    // deleted object the same way a staple's end does, and dangle the same way
    // -- so they travel in the same transaction, per the same rule.
    removeContainsForObjects(documentValue, removed);
    removeMembershipsForMembers(documentValue, removed);
  }

  // `replacedEventIds` / the extra `events` entries exist for the same reason as in
  // capturePatternBundle: editing a series' template event can converge one of that
  // series' exceptions, and the heal then deletes an event that is NOT `eventId`. The
  // tracked overrides already travel with the bundle (via trackPatternOverrides), so
  // without their replaced events undo would restore an override whose event stayed
  // deleted. `previous` keeps the captured set stable across the before/after pair and
  // supplies the identities `carryForward` reuses.
  function captureEventBundle(documentValue, eventId, trackedOverrideIds = [], previous = null) {
    const tracked = new Set(trackedOverrideIds);
    for (const [id, override] of Object.entries(documentValue.overrides)) {
      if (override.replacements?.includes(eventId)) tracked.add(id);
    }
    const patterns = Object.fromEntries(Object.entries(documentValue.patterns)
      .filter(([, pattern]) => pattern.templateEvent === eventId)
      .map(([id, pattern]) => [id, clone(pattern)]));
    trackPatternOverrides(documentValue, patterns, tracked);
    const trackedStaples = trackPatternStaples(documentValue, patterns, new Set());
    const overrides = Object.fromEntries(Object.entries(documentValue.overrides)
      .filter(([id]) => tracked.has(id)).map(([id, override]) => [id, clone(override)]));
    const replaced = new Set(previous?.replacedEventIds || []);
    for (const override of Object.values(overrides)) {
      for (const id of override.replacements || []) if (id !== eventId) replaced.add(id);
    }
    // This event's own object staples, and the staples of any event a heal
    // already replaced it with -- both are "records this bundle can delete",
    // so both travel with it the same way a series' staples travel with its
    // pattern (`trackPatternStaples`, above).
    trackObjectStaples(documentValue, [eventId, ...replaced], trackedStaples);
    const own = new Set([eventId]);
    return {
      event: clone(documentValue.events[eventId]),
      relations: Object.fromEntries(Object.entries(documentValue.relations)
        .filter(([id, relation]) => relationNamesObject(relation, own)
          || relationNamesObject(relation, replaced)
          || trackedStaples.has(id))
        .map(([id, relation]) => [id, relationNamesObject(relation, own)
          ? clone(relation)
          : carryForward(previous?.relations, id, relation)])),
      // Every state frame travels with every event bundle: the toggle that
      // marks this event done may mint the Done frame in this same
      // transaction, and its undo must remove it. `carryForward` keeps an
      // untouched frame the same object across the before/after pair, so an
      // edit that never touched state emits no frame ops.
      frames: Object.fromEntries(stateFrameEntries(documentValue)
        .map(([id, frame]) => [id, carryForward(previous?.frames, id, frame)])),
      patterns,
      trackedOverrideIds: [...tracked],
      overrides,
      replacedEventIds: [...replaced],
      events: Object.fromEntries([...replaced]
        .filter((id) => documentValue.events[id])
        .map((id) => [id, carryForward(previous?.events, id, documentValue.events[id])]))
    };
  }

  function restoreEventBundle(documentValue, eventId, bundle) {
    const tracked = new Set(bundle.trackedOverrideIds || Object.keys(bundle.overrides));
    // Driven by the stable id list, not by `bundle.events`, so redo re-deletes an
    // occurrence the heal retired (that bundle's events map is empty precisely then).
    const replaced = new Set(bundle.replacedEventIds || []);
    const swept = new Set([eventId, ...replaced]);
    for (const [id, relation] of Object.entries(documentValue.relations)) {
      if (relationNamesObject(relation, swept)) delete documentValue.relations[id];
    }
    // Clear-then-reassign for state frames, mirroring the relations sweep: the
    // bundle captured them all, so whatever the transaction minted or edited
    // comes back to exactly the captured set.
    for (const [id] of stateFrameEntries(documentValue)) delete documentValue.frames[id];
    Object.assign(documentValue.frames, clone(bundle.frames || {}));
    for (const id of replaced) delete documentValue.events[id];
    Object.assign(documentValue.events, clone(bundle.events || {}));
    for (const [id, pattern] of Object.entries(documentValue.patterns)) {
      if (pattern.templateEvent === eventId) delete documentValue.patterns[id];
    }
    const bundlePatterns = new Set(Object.keys(bundle.patterns || {}));
    for (const [id, override] of Object.entries(documentValue.overrides)) {
      if (tracked.has(id)
        || override.replacements?.includes(eventId)
        || bundlePatterns.has(overridePatternId(override))) delete documentValue.overrides[id];
    }
    for (const [id, relation] of Object.entries(documentValue.relations)) {
      if (relation.type !== "staple") continue;
      if (stapleTouchesAny(relation, bundlePatterns)
        || stapleReferencesId(relation, eventId)
        || stapleTouchesAny(relation, replaced)) delete documentValue.relations[id];
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
        cascadeRemovedPatterns(documentValue, before.patterns);
        // Scoped by the event AND by any pattern this event is the template of: the
        // inspector edits a series by editing its template event, and the occurrences
        // such an edit can converge are reachable only through the pattern.
        // `before.patterns` is exactly the patterns whose templateEvent is this event.
        convergeSeries(documentValue, {
          eventIds: [eventId],
          patternIds: Object.keys(before.patterns || {})
        });
        // A first, provisional capture just to learn the full post-mutation
        // `replacedEventIds` (including anything a heal just converged away),
        // so the object-staple cascade below sees the same candidate set the
        // final capture will -- then the real capture runs after the cascade
        // so `after` reflects the post-cascade state that gets journaled.
        const provisional = captureEventBundle(documentValue, eventId, before.trackedOverrideIds, before);
        cascadeRemovedObjects(documentValue, [eventId, ...(provisional.replacedEventIds || [])]);
        after = captureEventBundle(documentValue, eventId, before.trackedOverrideIds, before);
      }
      Object.assign(metadata, bundleOps(before, after, { eventId }));
    }, (documentValue) => restoreEventBundle(documentValue, eventId, before), metadata);
  }

  function captureEventSetBundle(documentValue, eventIds, previous = null) {
    const ids = new Set(eventIds);
    const patterns = Object.fromEntries(Object.entries(documentValue.patterns)
      .filter(([, pattern]) => ids.has(pattern.templateEvent)).map(([id, pattern]) => [id, clone(pattern)]));
    const tracked = trackPatternOverrides(documentValue, patterns, new Set());
    const trackedStaples = trackPatternStaples(documentValue, patterns, new Set());
    trackObjectStaples(documentValue, ids, trackedStaples);
    for (const [id, override] of Object.entries(documentValue.overrides)) {
      if (override.replacements?.some((eventId) => ids.has(eventId))) tracked.add(id);
    }
    return {
      events: Object.fromEntries(Object.entries(documentValue.events)
        .filter(([id]) => ids.has(id)).map(([id, event]) => [id, clone(event)])),
      relations: Object.fromEntries(Object.entries(documentValue.relations)
        .filter(([id, relation]) => relationNamesObject(relation, ids) || trackedStaples.has(id))
        .map(([id, relation]) => [id, clone(relation)])),
      frames: Object.fromEntries(stateFrameEntries(documentValue)
        .map(([id, frame]) => [id, carryForward(previous?.frames, id, frame)])),
      patterns,
      overrides: Object.fromEntries(Object.entries(documentValue.overrides)
        .filter(([id]) => tracked.has(id)).map(([id, override]) => [id, clone(override)]))
    };
  }

  function restoreEventSetBundle(documentValue, eventIds, bundle) {
    const ids = new Set(eventIds);
    for (const id of ids) delete documentValue.events[id];
    for (const [id, relation] of Object.entries(documentValue.relations)) {
      if (relationNamesObject(relation, ids) || (relation.type === "staple" && stapleTouchesAny(relation, ids))) {
        delete documentValue.relations[id];
      }
    }
    for (const [id] of stateFrameEntries(documentValue)) delete documentValue.frames[id];
    Object.assign(documentValue.frames, clone(bundle.frames || {}));
    for (const [id, pattern] of Object.entries(documentValue.patterns)) {
      if (ids.has(pattern.templateEvent)) delete documentValue.patterns[id];
    }
    const bundlePatterns = new Set(Object.keys(bundle.patterns || {}));
    for (const [id, override] of Object.entries(documentValue.overrides)) {
      if (override.replacements?.some((eventId) => ids.has(eventId))
        || bundlePatterns.has(overridePatternId(override))) delete documentValue.overrides[id];
    }
    for (const [id, relation] of Object.entries(documentValue.relations)) {
      if (relation.type === "staple" && stapleTouchesAny(relation, bundlePatterns)) delete documentValue.relations[id];
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
        cascadeRemovedPatterns(documentValue, before.patterns);
        convergeSeries(documentValue, { eventIds });
        cascadeRemovedObjects(documentValue, eventIds);
        after = captureEventSetBundle(documentValue, eventIds, before);
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
    const patterns = Object.fromEntries(Object.entries(documentValue.patterns).filter(([, pattern]) =>
      pattern.frame === frameId || pattern.appliesTo?.includes(frameId)
    ).map(([id, pattern]) => [id, clone(pattern)]));
    const tracked = trackPatternOverrides(documentValue, patterns, new Set());
    const trackedStaples = trackPatternStaples(documentValue, patterns, new Set());
    return {
      frame: clone(documentValue.frames[frameId]),
      relations: Object.fromEntries(Object.entries(documentValue.relations).filter(([id, relation]) =>
        relation.frame === frameId || relation.parent === frameId || relation.child === frameId
        // A membership names its frame as `group` -- deleting a group (or state)
        // frame has to take its memberships, or every member keeps a pointer to
        // nothing and one bad pointer takes the whole file offline at load.
        || relation.group === frameId
        || trackedStaples.has(id)
        // A staple names its frames on its ENDS, so a connection into this frame
        // is not caught by `relation.frame` at all. It has to travel with the
        // frame's deletion, for the same reason as a membership.
        || (relation.type === "staple" && stapleReferencesId(relation, frameId))
      ).map(([id, relation]) => [id, clone(relation)])),
      patterns,
      // Removing a frame removes the patterns scoped to it, so their overrides
      // travel with the bundle too — otherwise deleting a calendar orphans every
      // exception on every series it owned.
      overrides: Object.fromEntries(Object.entries(documentValue.overrides)
        .filter(([id]) => tracked.has(id)).map(([id, override]) => [id, clone(override)]))
    };
  }

  function restoreFrameBundle(documentValue, frameId, bundle) {
    for (const [id, relation] of Object.entries(documentValue.relations)) {
      if (relation.frame === frameId || relation.parent === frameId || relation.child === frameId
        || relation.group === frameId
        || (relation.type === "staple" && stapleReferencesId(relation, frameId))) {
        delete documentValue.relations[id];
      }
    }
    for (const [id, pattern] of Object.entries(documentValue.patterns)) {
      if (pattern.frame === frameId || pattern.appliesTo?.includes(frameId)) delete documentValue.patterns[id];
    }
    const bundlePatterns = new Set(Object.keys(bundle.patterns || {}));
    for (const [id, override] of Object.entries(documentValue.overrides)) {
      if (bundlePatterns.has(overridePatternId(override))) delete documentValue.overrides[id];
    }
    for (const [id, relation] of Object.entries(documentValue.relations)) {
      if (relation.type === "staple" && stapleTouchesAny(relation, bundlePatterns)) delete documentValue.relations[id];
    }
    if (bundle.frame) documentValue.frames[frameId] = clone(bundle.frame);
    else delete documentValue.frames[frameId];
    Object.assign(documentValue.relations, clone(bundle.relations));
    Object.assign(documentValue.patterns, clone(bundle.patterns));
    Object.assign(documentValue.overrides, clone(bundle.overrides || {}));
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
        cascadeRemovedPatterns(documentValue, before.patterns);
        after = captureFrameBundle(documentValue, frameId);
      }
      Object.assign(metadata, bundleOps(before, after, { frameId }));
    }, (documentValue) => restoreFrameBundle(documentValue, frameId, before), metadata);
  }

  // AGENTS.md's rule is that an override belongs to its pattern the way a relation
  // belongs to an event. The series convergence invariant extends that one link
  // further: the materialized event an override *replaces* belongs to the override.
  // Editing a series can converge one of its exceptions (move the series onto the
  // date an exception was dragged to and the exception now says exactly what the
  // series says), and the heal then deletes that event — so this bundle has to
  // carry it, or undo would restore the override while its event stayed deleted.
  // `bundleMaps` already understands `events`/`relations`, so adding them here is
  // enough for the journal ops to come out right.
  // `opsFromMaps` treats a record as untouched only when the before and after bundles
  // hold the SAME OBJECT, so a record this transaction did not change has to be
  // carried by reference rather than cloned a second time — otherwise every capture
  // manufactures a spurious put. Clone on first sight (so a later in-place mutation
  // cannot corrupt the restore value), then reuse that clone while the record is
  // unchanged.
  function carryForward(previousMap, id, value) {
    const previous = previousMap?.[id];
    if (previous && JSON.stringify(previous) === JSON.stringify(value)) return previous;
    return clone(value);
  }

  // `previous` (the before bundle) does two jobs. It keeps the captured event set
  // STABLE across the before/after pair — exactly as `captureEventBundle`'s
  // `trackedOverrideIds` does — because the set is otherwise derived from overrides
  // this same transaction may delete: deleting a pattern removes its overrides, so
  // `after` would stop tracking the replaced event, the diff would read that as a
  // deletion, and journal replay would delete a real event nobody asked to remove.
  // It also supplies the identities `carryForward` reuses. An existing test caught
  // both failures.
  function capturePatternBundle(documentValue, patternId, previous = null) {
    const patterns = documentValue.patterns[patternId]
      ? { [patternId]: clone(documentValue.patterns[patternId]) }
      : {};
    const tracked = trackPatternOverrides(documentValue, { [patternId]: true }, new Set());
    const trackedStaples = trackPatternStaples(documentValue, { [patternId]: true }, new Set());
    const overrides = Object.fromEntries(Object.entries(documentValue.overrides)
      .filter(([id]) => tracked.has(id)).map(([id, override]) => [id, clone(override)]));
    const replaced = new Set(previous?.replacedEventIds || []);
    for (const override of Object.values(overrides)) {
      for (const eventId of override.replacements || []) replaced.add(eventId);
    }
    // A replaced (materialized-then-overridden) occurrence can carry its own
    // object staples, same as any other event -- so if a heal removes one
    // during this edit, its staples travel with it, the same way this
    // series' own end/inflection staples already travel via `trackedStaples`.
    trackObjectStaples(documentValue, replaced, trackedStaples);
    return {
      patterns,
      overrides,
      replacedEventIds: [...replaced],
      events: Object.fromEntries([...replaced]
        .filter((eventId) => documentValue.events[eventId])
        .map((eventId) => [eventId, carryForward(previous?.events, eventId, documentValue.events[eventId])])),
      // The staple this series ends on travels in the same field as the events
      // its overrides replaced -- both are "records this bundle can delete",
      // and `restorePatternBundle` clears stale staples the same way it clears
      // stale overrides before reassigning this map.
      relations: Object.fromEntries(Object.entries(documentValue.relations)
        .filter(([id, relation]) => replaced.has(relation.event) || replaced.has(relation.member)
          || trackedStaples.has(id))
        .map(([id, relation]) => [id, carryForward(previous?.relations, id, relation)]))
    };
  }

  function restorePatternBundle(documentValue, patternId, bundle) {
    delete documentValue.patterns[patternId];
    for (const [id, override] of Object.entries(documentValue.overrides)) {
      if (overridePatternId(override) === patternId) delete documentValue.overrides[id];
    }
    // Driven by the stable id list rather than by `bundle.events`: on redo this
    // runs with the after-bundle, whose events map is empty precisely when a
    // heal removed one -- keying off the map would leave that event's stale
    // staples behind.
    const replaced = new Set(bundle.replacedEventIds || Object.keys(bundle.events || {}));
    for (const [id, relation] of Object.entries(documentValue.relations)) {
      if (relation.type !== "staple") continue;
      if (stapleReferencesId(relation, patternId)
        || stapleTouchesAny(relation, replaced)) delete documentValue.relations[id];
    }
    // Clear the replaced events' current records before restoring, so this works
    // symmetrically whether the transaction being undone deleted them (a heal) or
    // left them in place.
    if (replaced.size) {
      for (const [id, relation] of Object.entries(documentValue.relations)) {
        if (replaced.has(relation.event) || replaced.has(relation.member)) delete documentValue.relations[id];
      }
      for (const eventId of replaced) delete documentValue.events[eventId];
    }
    Object.assign(documentValue.patterns, clone(bundle.patterns));
    Object.assign(documentValue.overrides, clone(bundle.overrides));
    Object.assign(documentValue.events, clone(bundle.events || {}));
    Object.assign(documentValue.relations, clone(bundle.relations || {}));
  }

  // Editing or deleting one pattern together with the overrides that belong to
  // it. `executeRecordChange` cannot do this job: it tracks exactly one record in
  // one map, so a pattern deletion through it leaves the overrides behind.
  function executePatternChange(label, patternId, mutate) {
    const { chronolog, history } = app;
    const before = capturePatternBundle(chronolog, patternId);
    let after = null;
    const metadata = { preserveRecurrence: false };
    history.executeDelta(label, (documentValue) => {
      if (after) restorePatternBundle(documentValue, patternId, after);
      else {
        mutate(documentValue);
        cascadeRemovedPatterns(documentValue, before.patterns);
        // Scoped by pattern, not by event: a series edit can converge an occurrence
        // it never named.
        convergeSeries(documentValue, { patternIds: [patternId] });
        // Same two-pass shape as `executeEventChange`: learn the post-heal
        // `replacedEventIds` first, so a materialized occurrence a heal just
        // removed has its own object staples swept in this same transaction,
        // then capture for real once the cascade has run.
        const provisional = capturePatternBundle(documentValue, patternId, before);
        cascadeRemovedObjects(documentValue, provisional.replacedEventIds || []);
        after = capturePatternBundle(documentValue, patternId, before);
      }
      Object.assign(metadata, bundleOps(before, after));
    }, (documentValue) => restorePatternBundle(documentValue, patternId, before), metadata);
  }

  // Ask the invariant about one occurrence right now, outside any edit.
  //
  // This is the "closing an occurrence you did not change must not leave a fork
  // behind" case (ROADMAP #5). It is deliberately the SAME invariant rather than a
  // second rule about closing: it commits nothing unless the occurrence genuinely
  // matches its series, so a closed-but-edited occurrence is untouched. Planning
  // first also keeps a no-op close from pushing an empty undo entry — the plan is
  // pure, so asking twice costs nothing but an engine refresh.
  function convergeSeriesOccurrence(eventId) {
    const { chronolog } = app;
    if (!eventId || !chronolog?.events?.[eventId]) return false;
    const candidates = healCandidateIds(chronolog, { eventIds: [eventId] });
    if (!candidates.length) return false;
    const engine = app.refreshEngine?.(chronolog) || app.engine;
    if (!engine) return false;
    if (!planSeriesHeal(chronolog, engine, { overrideIds: candidates }).healed) return false;
    // An empty mutation: executeEventChange's own convergence step does the work,
    // so the removal arrives as one ordinary undoable, journaled bundle rather than
    // through a second mechanism.
    executeEventChange("Heal series occurrence", eventId, () => {});
    return true;
  }

  // Bulk-skip: materialize a set of a series' past virtual occurrences and
  // affiliate each to a named STATE frame, as one undoable transaction. The
  // same records "Edit one occurrence" prepares (src/ui/inspector.js's
  // prepareMaterialization: cloned template event, its placement, the
  // template's group attachments, a suppressing override) plus one membership
  // per occurrence -- and the membership is a deviation the series never
  // projects, which is exactly what keeps the convergence invariant from
  // healing a deliberate skip away. Keys are the engine's own occurrence keys
  // (`occurrence-<day>`, src/engine.js), so the day each materialization lands
  // on is the projection's own answer, never re-derived rule math.
  //
  // Ops are static per prepared record (the materializationOps pattern), so
  // the journal, undo, and redo all see one bundle. The state frame itself is
  // minted lazily inside the same transaction when absent, like the Done
  // frame's first toggle.
  function bulkSkipOccurrences(patternId, occurrenceKeys, { stateFrame, title, label = "Skip occurrences" } = {}) {
    const { chronolog, history } = app;
    const pattern = chronolog.patterns?.[patternId];
    const templateEvent = pattern && chronolog.events[pattern.templateEvent];
    const templateRelation = pattern && chronolog.relations[pattern.templateRelation];
    if (!pattern || !templateEvent || !templateRelation || !stateFrame) return 0;
    const engine = app.refreshEngine?.(chronolog) || app.engine || null;
    const overridden = new Set(Object.values(chronolog.overrides).map((override) => override.virtual));
    const groupTemplates = Object.values(chronolog.relations).filter((relation) =>
      relation.type === "attachment"
      && relation.event === pattern.templateEvent
      && chronolog.frames[relation.frame]?.traits?.includes("group"));
    const prepared = [];
    for (const key of new Set(occurrenceKeys || [])) {
      const text = String(key);
      if (!text.startsWith("occurrence-")) continue;
      const virtualId = stableVirtualId(patternId, text);
      // A slot already overridden is already authored -- materializing a second
      // record over it would fork the fork.
      if (overridden.has(virtualId)) continue;
      let coordinate;
      try {
        const days = Rational.parse(text.slice("occurrence-".length));
        coordinate = engine
          ? engine.daysCoordinate(templateRelation.frame, days)
          : coordinateLaw(chronolog, templateRelation.frame).fromDays(days);
      } catch {
        continue;
      }
      const event = clone(templateEvent);
      event.id = createId("event");
      event.traits = (event.traits || []).filter((trait) => trait !== "generated");
      event.provenance = {
        kind: "explicit",
        replaces: virtualId,
        pattern: patternId,
        originalCoordinate: clone(coordinate)
      };
      const relation = clone(templateRelation);
      relation.id = createId("relation");
      relation.event = event.id;
      relation.coordinate = clone(coordinate);
      relation.provenance = { kind: "explicit", replaces: virtualId };
      const groups = groupTemplates.map((source) => ({ ...clone(source), id: createId("relation"), event: event.id }));
      const membership = {
        id: createId("relation"),
        type: "membership",
        group: stateFrame,
        member: event.id,
        provenance: { kind: "explicit" }
      };
      const override = { id: createId("override"), virtual: virtualId, suppress: true, replacements: [event.id] };
      prepared.push({ event, relation, groups, membership, override });
    }
    if (!prepared.length) return 0;
    const mintedFrame = chronolog.frames[stateFrame]
      ? null
      : { id: stateFrame, title: title || stateFrame, traits: [...STATE_FRAME_TRAITS] };
    const apply = (documentValue) => {
      if (mintedFrame) documentValue.frames[stateFrame] = clone(mintedFrame);
      for (const item of prepared) {
        documentValue.events[item.event.id] = clone(item.event);
        documentValue.relations[item.relation.id] = clone(item.relation);
        for (const group of item.groups) documentValue.relations[group.id] = clone(group);
        documentValue.relations[item.membership.id] = clone(item.membership);
        documentValue.overrides[item.override.id] = clone(item.override);
      }
    };
    const revert = (documentValue) => {
      for (const item of prepared) {
        delete documentValue.overrides[item.override.id];
        delete documentValue.relations[item.membership.id];
        for (const group of item.groups) delete documentValue.relations[group.id];
        delete documentValue.relations[item.relation.id];
        delete documentValue.events[item.event.id];
      }
      if (mintedFrame) delete documentValue.frames[stateFrame];
    };
    const ops = [
      ...(mintedFrame ? [putOp("frames", stateFrame, mintedFrame)] : []),
      ...prepared.flatMap((item) => [
        putOp("events", item.event.id, item.event),
        putOp("relations", item.relation.id, item.relation),
        ...item.groups.map((group) => putOp("relations", group.id, group)),
        putOp("relations", item.membership.id, item.membership),
        putOp("overrides", item.override.id, item.override)
      ])
    ];
    const inverseOps = [
      ...prepared.flatMap((item) => [
        delOp("overrides", item.override.id),
        delOp("relations", item.membership.id),
        ...[...item.groups].reverse().map((group) => delOp("relations", group.id)),
        delOp("relations", item.relation.id),
        delOp("events", item.event.id)
      ]),
      ...(mintedFrame ? [delOp("frames", stateFrame)] : [])
    ];
    history.executeDelta(label, apply, revert, { preserveRecurrence: true, ops, inverseOps });
    return prepared.length;
  }

  // The one write path behind every ToDo capture mode: quick enter and the
  // standard inline row both commit through here (placed create keeps its
  // existing createEventAt path). `parsed` is `{title, group?, dateDays?,
  // note?}` -- title required; `group` a group-frame TITLE to match (never
  // minted: meaning is authored, and a typo must not create a frame);
  // `dateDays` a universal day ordinal or null for now; `note` becomes the
  // description. A title-only call writes exactly what the create menu's
  // ToDo writes today: an event with the todo traits plus an observed
  // relation at now, one bundle, one undo.
  function createQuickTodo(parsed = {}) {
    const { chronolog, session } = app;
    const title = String(parsed.title || "").trim();
    if (!title) return null;
    const definition = OBJECT_KINDS.todo;
    const eventId = createId("event");
    const frame = session.activeFrame;
    const wanted = String(parsed.group || "").trim().toLowerCase();
    const groupFrame = wanted
      ? Object.values(chronolog.frames).find((candidate) => candidate.traits?.includes("group")
        && !isStateFrame(candidate)
        && String(candidate.title || "").trim().toLowerCase() === wanted) || null
      : null;
    // The stored coordinate is built under the active frame's own law, never
    // the standard boundary; an unresolvable declaration must not make
    // capture fail (same fallback toggleStateAffiliation takes).
    let law;
    try {
      law = coordinateLaw(chronolog, frame);
    } catch {
      law = GREGORIAN_LAW;
    }
    const at = parsed.dateDays ?? nowDays();
    executeEventChange("Create ToDo", eventId, (documentValue) => {
      addEvent(documentValue, {
        id: eventId,
        traits: traitsForObjectKind([], "todo"),
        magnitudes: { duration: durationMagnitude("0") },
        payload: { title, description: String(parsed.note || ""), location: "" }
      });
      addRelation(documentValue, {
        type: "attachment",
        event: eventId,
        frame,
        role: definition.relationRole,
        coordinate: law.fromDays(at)
      });
      if (groupFrame) {
        addRelation(documentValue, {
          type: "membership",
          group: groupFrame.id,
          member: eventId,
          provenance: { kind: "explicit" }
        });
      }
    }, true);
    return {
      id: eventId,
      group: groupFrame?.id || null,
      // An unmatched group is reported, never guessed at or minted -- the
      // caller decides how to say so.
      unmatchedGroup: wanted && !groupFrame ? String(parsed.group).trim() : null
    };
  }

  return {
    executeEventChange,
    executeEventSetChange,
    executeRecordChange,
    executeFrameChange,
    executePatternChange,
    convergeSeriesOccurrence,
    bulkSkipOccurrences,
    createQuickTodo
  };
}
