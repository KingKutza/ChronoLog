// Op capture: turning a committed document mutation into the record-level
// put/delete list that the journal persists.
//
// An op names a map and a record id and either assigns the full record value
// or deletes it. Records are the unit — not fields — so a put always carries
// the whole record. That is deliberate: the server can apply and compact ops
// with no idea what an event or a frame is.
//
// Two capture strategies feed the same op shape:
//
//   * Bundle diff, for the transaction helpers. Those already collect the
//     before/after records surrounding an edit, and that bundle IS the set of
//     records the edit may touch, so every record in the after-bundle becomes
//     a put and anything that vanished becomes a delete.
//
//   * Reference diff, for wholesale rewrites like an ICS import or calendar
//     pull, where deep-copying the document to compare it would cost more than
//     the edit itself. A shallow snapshot of each map is taken before the
//     mutation and compared by object identity afterwards: a record that still
//     points at the same object was not rewritten. This is only sound because
//     those paths replace whole records instead of mutating them in place —
//     see the invariant noted in `src/calendar-sync.js`.
//
// Op values hold live references into the document rather than copies. The
// store serializes them when it posts, so a record edited again inside the
// same debounce window is persisted once, in its final state.

export const RECORD_MAPS = ["events", "frames", "patterns", "relations", "overrides", "meta", "foreign"];

const RECORD_MAP_SET = new Set(RECORD_MAPS);

export function putOp(map, id, value) {
  return { op: "put", map, id, value };
}

export function delOp(map, id) {
  return { op: "del", map, id };
}

// Applies record-level ops to a document in place. This is the one
// implementation of what an op MEANS: the client replays a conflicting
// window's ops with it, and the server replays the journal and compacts with
// it. Two copies of this that drifted apart would corrupt documents quietly,
// so `tools/journal.js` imports this rather than keeping its own.
//
// Ops are idempotent by construction — applying the same put or delete twice
// lands on the same state — which is what makes a crash mid-compaction
// survivable and makes conflict rebasing safe to retry.
export function applyOps(document, ops = []) {
  let applied = 0;
  for (const op of ops) {
    if (!op || typeof op !== "object") throw new TypeError("journal op must be an object");
    if (!RECORD_MAP_SET.has(op.map)) throw new RangeError(`unknown journal map "${op.map}"`);
    if (typeof op.id !== "string" || !op.id) throw new TypeError("journal op needs a record id");
    const map = (document[op.map] ||= {});
    if (op.op === "put") {
      if (op.value === undefined) throw new TypeError(`put op for ${op.map}/${op.id} carries no value`);
      map[op.id] = op.value;
    } else if (op.op === "del") {
      delete map[op.id];
    } else {
      throw new RangeError(`unknown journal op "${op.op}"`);
    }
    applied += 1;
  }
  return applied;
}

// A shallow, per-map snapshot of record identities. Cheap by construction: one
// pointer per record, no traversal into the records themselves.
export function mapSnapshot(document, maps = RECORD_MAPS) {
  const snapshot = {};
  for (const map of maps) snapshot[map] = { ...(document[map] || {}) };
  return snapshot;
}

// Diffs two per-map record collections into ops. A record present in `after`
// under the same identity as in `before` is treated as untouched; anything
// else is a put, and anything that disappeared is a delete.
export function opsFromMaps(before, after) {
  const ops = [];
  for (const map of RECORD_MAPS) {
    const previous = before[map] || {};
    const next = after[map] || {};
    for (const [id, value] of Object.entries(next)) {
      if (id in previous && previous[id] === value) continue;
      ops.push(putOp(map, id, value));
    }
    for (const id of Object.keys(previous)) {
      if (!(id in next)) ops.push(delOp(map, id));
    }
  }
  return ops;
}

// Normalizes the several bundle shapes the transaction helpers use into the
// per-map form `opsFromMaps` expects. `captureEventBundle` carries one `event`
// plus related maps; `captureFrameBundle` carries one `frame`; the set variants
// already carry maps.
export function bundleMaps(bundle, { eventId = null, frameId = null } = {}) {
  const maps = { events: {}, frames: {}, patterns: {}, relations: {}, overrides: {} };
  if (!bundle) return maps;
  if (bundle.events) Object.assign(maps.events, bundle.events);
  if (bundle.frames) Object.assign(maps.frames, bundle.frames);
  if (bundle.relations) Object.assign(maps.relations, bundle.relations);
  if (bundle.patterns) Object.assign(maps.patterns, bundle.patterns);
  if (bundle.overrides) Object.assign(maps.overrides, bundle.overrides);
  if (eventId && bundle.event) maps.events[eventId] = bundle.event;
  if (frameId && bundle.frame) maps.frames[frameId] = bundle.frame;
  return maps;
}

// Forward and inverse ops for one edit, from its before/after bundles. The
// inverse is what undo commits: the bundles hold the before-values already, so
// no extra capture is needed.
export function bundleOps(before, after, scope = {}) {
  const beforeMaps = bundleMaps(before, scope);
  const afterMaps = bundleMaps(after, scope);
  return {
    ops: opsFromMaps(beforeMaps, afterMaps),
    inverseOps: opsFromMaps(afterMaps, beforeMaps)
  };
}

// Forward and inverse ops for a single record in one map.
export function recordOps(map, id, before, after) {
  return {
    ops: after === undefined ? [delOp(map, id)] : [putOp(map, id, after)],
    inverseOps: before === undefined ? [delOp(map, id)] : [putOp(map, id, before)]
  };
}

// Accumulates committed edits until the store posts them. One entry per
// commit, so the debounce batches several edits into a single request without
// flattening them into one indistinguishable blob — the journal keeps each
// edit's own label and op list. Order is preserved, because a put followed by
// a delete of the same record means something different than the reverse.
export class OpLog {
  constructor() {
    this.entries = [];
  }

  get length() {
    return this.entries.length;
  }

  get opCount() {
    return this.entries.reduce((total, entry) => total + entry.ops.length, 0);
  }

  collect(label, ops = []) {
    if (!ops?.length) return this;
    this.entries.push({ label, ops });
    return this;
  }

  // Returns the pending entries and empties the log. A failed post hands them
  // back with `restore` so nothing is lost.
  drain() {
    const entries = this.entries;
    this.entries = [];
    return entries;
  }

  restore(entries = []) {
    if (entries.length) this.entries = [...entries, ...this.entries];
    return this;
  }

  clear() {
    this.entries = [];
  }
}
