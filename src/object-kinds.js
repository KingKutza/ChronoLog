import {
  DEFAULT_POINT,
  endScope,
  stapleEndFor,
  stapleOtherEnd,
  staplesForObject
} from "./staples.js";

export const OBJECT_KINDS = Object.freeze({
  event: Object.freeze({
    label: "Event",
    newTitle: "New event",
    traits: Object.freeze(["event"]),
    relationRole: "placed",
    zeroDuration: false
  }),
  todo: Object.freeze({
    label: "ToDo",
    newTitle: "New ToDo",
    traits: Object.freeze(["event", "task", "todo"]),
    relationRole: "observed",
    zeroDuration: true
  }),
  note: Object.freeze({
    label: "Note",
    newTitle: "New note",
    traits: Object.freeze(["event", "note"]),
    relationRole: "placed",
    zeroDuration: true
  })
});

const CONTROLLED_TRAITS = new Set(["event", "task", "todo", "note"]);

export function normalizeObjectKind(value) {
  return Object.hasOwn(OBJECT_KINDS, value) ? value : "event";
}

export function objectKindForEvent(event) {
  if (event?.traits?.some((trait) => trait === "task" || trait === "todo")) return "todo";
  if (event?.traits?.includes("note")) return "note";
  return "event";
}

// ---------------------------------------------------------------------------
// State frames
// ---------------------------------------------------------------------------

// STATE IS A FRAME, NOT A PROPERTY (owner ruling). "Done" -- and any future
// state: cancelled, postponed -- is a frame the user authors, and an object
// being in that state IS its membership in that frame, through the same
// membership relation every other group uses. No resolution roles, no verb
// registry, no enum: the whole vocabulary of states is whichever state frames
// the document holds. A state frame may later carry an atomic stack-ordered
// time law; nothing here precludes that, and nothing builds it.
//
// A state frame is a group frame ("group" is what lets membership validation
// and the engine's membership index admit it) carrying the "state" trait on
// top -- the same additive-trait shape an importance frame uses.
export const STATE_FRAME_TRAITS = Object.freeze(["set", "group", "state"]);

// The one deterministic state frame the substrate itself ever names: the Done
// frame, minted lazily by the first completion (toggle, inspector field, ICS
// import, or the legacy-relation repair) and never seeded into an empty
// document. Deterministic id so every path -- and every window -- converges on
// ONE frame rather than each minting its own "Done".
export const DONE_STATE_FRAME_ID = "frame:state-done";
export const DONE_STATE_TITLE = "Done";

export function isStateFrame(frame) {
  return Boolean(frame?.traits?.includes("group") && frame?.traits?.includes("state"));
}

// Create-if-missing, in place; the caller's transaction owns capture and undo.
// An existing frame is returned untouched -- the user may have retitled or
// recolored it, and that authorship must survive every later toggle.
export function ensureStateFrame(document, id = DONE_STATE_FRAME_ID, title = DONE_STATE_TITLE) {
  const existing = document.frames?.[id];
  if (existing) return existing;
  const frame = { id, title, traits: [...STATE_FRAME_TRAITS] };
  document.frames[id] = frame;
  return frame;
}

// ---------------------------------------------------------------------------
// State affiliations
// ---------------------------------------------------------------------------

// THE COMPLETION INSTANT IS A STAPLE, AND IT IS TERMINAL (owner ruling: "the
// end of this todo abuts the beginning of this event"). The registered `end`
// kind, the object's own `end` point, the other end a frame coordinate --
// backdating is nothing but that coordinate. This finds that staple; null is
// a legal answer, because a state affiliation with no staple is legal (done,
// instant unstated).
export function objectEndStaple(chronologDocument, objectId, engine = null) {
  for (const staple of staplesForObject(chronologDocument, objectId, engine)) {
    if (staple.kind !== "end") continue;
    const near = stapleEndFor(staple, objectId);
    if (!near || (near.point || DEFAULT_POINT) !== "end") continue;
    const far = stapleOtherEnd(staple, near);
    if (endScope(far) !== "frame" || !far.coordinate) continue;
    return staple;
  }
  return null;
}

// The frame end an end staple carries, as the `{frame, coordinate,
// parameters?}` shape every consumer of "when" already reads (the inspector's
// Completed field, ICS COMPLETED, the roster's completedAt).
function endStapleInstant(staple, objectId) {
  if (!staple) return null;
  const far = stapleOtherEnd(staple, stapleEndFor(staple, objectId));
  return {
    frame: far.frame,
    coordinate: far.coordinate,
    ...(far.parameters ? { parameters: far.parameters } : {}),
    staple
  };
}

/**
 * Every state this object is affiliated with, as `[{frame, title, membership,
 * at}]` in stable frame-id order. `at` is the object's end-staple instant
 * (`{frame, coordinate, parameters?, staple}`), or null when no instant is
 * stated -- and it is a fact about the OBJECT, not about any one state, so
 * every affiliation reports the same one. The one derivation the roster, the
 * inspector, ICS export, and the contains summary all read, so "is this done,
 * and when" has exactly one answer.
 */
export function stateAffiliations(chronologDocument, objectId, engine = null) {
  if (!objectId) return [];
  const at = endStapleInstant(objectEndStaple(chronologDocument, objectId, engine), objectId);
  const entries = [];
  for (const relation of Object.values(chronologDocument?.relations || {})) {
    if (relation?.type !== "membership" || relation.member !== objectId) continue;
    const frame = chronologDocument.frames?.[relation.group];
    if (!isStateFrame(frame)) continue;
    entries.push({ frame: relation.group, title: frame.title || relation.group, membership: relation, at });
  }
  return entries.sort((left, right) => String(left.frame).localeCompare(String(right.frame)));
}

export function doneAffiliation(chronologDocument, objectId, engine = null) {
  return stateAffiliations(chronologDocument, objectId, engine)
    .find((entry) => entry.frame === DONE_STATE_FRAME_ID) || null;
}

// ---------------------------------------------------------------------------
// Containment
// ---------------------------------------------------------------------------

function containsChildren(chronologDocument, engine, objectId) {
  const indexed = engine?.containsByParent;
  if (indexed) return indexed.get(objectId) || [];
  return Object.values(chronologDocument?.relations || {})
    .filter((relation) => relation?.type === "contains" && relation.parent === objectId)
    .map((relation) => relation.child)
    .sort();
}

// Authored done-memberships, as one set -- built once per engine generation
// rather than once per descendant, because a project summary at overscale asks
// about hundreds of children and a per-child relation scan would be quadratic.
function doneMembers(chronologDocument, engine) {
  if (engine?.doneMembersMemo) return engine.doneMembersMemo;
  const members = new Set();
  for (const relation of Object.values(chronologDocument?.relations || {})) {
    if (relation?.type === "membership" && relation.group === DONE_STATE_FRAME_ID) {
      members.add(relation.member);
    }
  }
  if (engine) engine.doneMembersMemo = members;
  return members;
}

/**
 * Display facts about what an object contains: `{direct, total, open, done,
 * cyclic}`. `direct` counts authored child edges' distinct children; `total`
 * counts distinct descendants at any depth; `open`/`done` split those
 * descendants by the done-state derivation. Multi-parent shapes count each
 * descendant once (a diamond is not a cycle), and a genuine cycle is REPORTED
 * (`cyclic: true`) with the loop broken at the revisit -- never thrown, never
 * looped forever, because validation deliberately passes no judgment on
 * family-tree shape and this derivation must survive whatever it admits.
 *
 * Memoized per engine generation (`engine.containsSummaryMemo`, reset by every
 * reindex) so a lens can ask once per rendered row.
 */
export function containsSummary(chronologDocument, engine, objectId) {
  const memo = engine?.containsSummaryMemo;
  const cached = memo?.get(objectId);
  if (cached) return cached;
  const directChildren = [...new Set(containsChildren(chronologDocument, engine, objectId))];
  const seen = new Set();
  let cyclic = false;
  // Iterative DFS with an explicit on-path set: `seen` alone cannot tell a
  // diamond (legal, counted once) from a loop (reported), and recursion would
  // overflow on the deep chains the validator deliberately allows.
  const path = new Set([objectId]);
  const stack = [{ children: directChildren, index: 0 }];
  while (stack.length) {
    const top = stack[stack.length - 1];
    if (top.index >= top.children.length) {
      stack.pop();
      if (top.id !== undefined) path.delete(top.id);
      continue;
    }
    const child = top.children[top.index];
    top.index += 1;
    if (path.has(child)) {
      cyclic = true;
      continue;
    }
    if (seen.has(child)) continue;
    seen.add(child);
    path.add(child);
    stack.push({ id: child, children: containsChildren(chronologDocument, engine, child), index: 0 });
  }
  const done = doneMembers(chronologDocument, engine);
  let doneCount = 0;
  for (const child of seen) if (done.has(child)) doneCount += 1;
  const summary = {
    direct: directChildren.length,
    total: seen.size,
    open: seen.size - doneCount,
    done: doneCount,
    cyclic
  };
  memo?.set(objectId, summary);
  return summary;
}

// ---------------------------------------------------------------------------
// The roster query
// ---------------------------------------------------------------------------

// The ToDo and Notes roster: every object of one kind, with the coordinate it
// is stapled at. Pure over the document so the roster's contents and ordering
// are testable without a DOM.
//
// This is deliberately a flat roster, not the staple/decay model. Floats living
// at their staples, projecting forward for a keep-range and lapsing from the
// present view is ROADMAP #2 and is not decided yet; showing every object of a
// kind is the honest placeholder, because it invents no lifecycle rule that would
// later have to be unwound. A completed ToDo is still one of these entries --
// completion is a fact about the object, never a reason to stop listing it.
export function rosterEntries(chronologDocument, requestedKind) {
  const kind = normalizeObjectKind(requestedKind);
  const events = Object.values(chronologDocument?.events || {})
    .filter((event) => objectKindForEvent(event) === kind);
  const placements = new Map();
  const doneMemberships = new Set();
  const completionInstants = new Map();
  for (const [id, relation] of Object.entries(chronologDocument?.relations || {})) {
    // Done is a state-frame affiliation, and the instant is the object's own
    // end staple -- the same two facts stateAffiliations derives per object,
    // read here in one pass so the whole roster costs one relation sweep.
    if (relation?.type === "membership" && relation.group === DONE_STATE_FRAME_ID) {
      doneMemberships.add(relation.member);
      continue;
    }
    if (relation?.type === "staple" && relation.kind === "end") {
      for (const end of relation.ends || []) {
        if (!end?.object || (end.point || DEFAULT_POINT) !== "end") continue;
        const far = stapleOtherEnd(relation, end);
        if (endScope(far) !== "frame" || !far.coordinate) continue;
        const current = completionInstants.get(end.object);
        // First in the substrate's stable order (relation id), matching
        // objectEndStaple, so the roster and the inspector name one instant.
        if (!current || String(id).localeCompare(String(current.id)) < 0) {
          completionInstants.set(end.object, { id, coordinate: far.coordinate });
        }
      }
      continue;
    }
    if (!relation?.event) continue;
    if (relation.coordinate && !placements.has(relation.event)) placements.set(relation.event, relation);
  }
  return events
    .map((event) => {
      const relation = placements.get(event.id) || null;
      return {
        id: event.id,
        title: event.payload?.title || "(untitled)",
        coordinate: relation?.coordinate || null,
        frame: relation?.frame || null,
        // A roster row has to be able to say "this one has no staple yet" rather
        // than inventing a date for it.
        anchored: Boolean(relation?.coordinate),
        // Done-frame membership, and the end-staple instant if one is stated --
        // membership with no instant is legal, so `completed` never requires
        // `completedAt`.
        completed: doneMemberships.has(event.id),
        completedAt: completionInstants.get(event.id)?.coordinate || null
      };
    })
    .sort((left, right) => left.title.localeCompare(right.title) || left.id.localeCompare(right.id));
}

export function traitsForObjectKind(existingTraits, requestedKind) {
  const kind = normalizeObjectKind(requestedKind);
  const extra = (existingTraits || []).filter((trait) => !CONTROLLED_TRAITS.has(trait));
  return [...new Set([...OBJECT_KINDS[kind].traits, ...extra])];
}
