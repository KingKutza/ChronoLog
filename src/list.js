// The List lens's own projection math. Pure over `{document, engine}` --
// the renderer wiring lives in src/projections.js, following the
// lines.js/radial.js per-lens-module pattern.
//
// This module is deliberately independent of src/board.js even where the two
// compute similar things (the Spiral/Radial precedent, taken fully: "there is
// no common sub straight except that data. both lenses... independently
// project the data per there own rules"). The only sharing allowed is the
// data layer that already exists -- rosterEntries, state derivations, the
// staple substrate -- never a common section model.
import { DONE_STATE_FRAME_ID, isStateFrame, containsSummary, rosterEntries } from "./object-kinds.js";
import { staplesForObject } from "./staples.js";

// One grouping choice supplies the sections; there are no filters. "By
// controlling the frames projected we can effect the identical view as would
// be rendered by a filter."
export const LIST_GROUPINGS = Object.freeze(["state", "importance", "container", "frame"]);

export function normalizeListGrouping(value) {
  return LIST_GROUPINGS.includes(value) ? value : "state";
}

function membershipGroups(chronologDocument, engine, objectId) {
  if (engine?.eventDisplayGroupMemberships) {
    return engine.eventDisplayGroupMemberships(objectId).map((entry) => entry.group);
  }
  return Object.values(chronologDocument?.relations || {})
    .filter((relation) => relation?.type === "membership" && relation.member === objectId)
    .map((relation) => relation.group);
}

function containerParents(chronologDocument, engine, objectId) {
  if (engine?.parentsByChild) return engine.parentsByChild.get(objectId) || [];
  return Object.values(chronologDocument?.relations || {})
    .filter((relation) => relation?.type === "contains" && relation.child === objectId)
    .map((relation) => relation.parent)
    .sort();
}

// The state a row renders with. "sparse" is the honest cheap title-only
// predicate: no state affiliation, no group membership of any kind, no
// description, and no authored staple beyond the creation placement (which is
// an attachment relation, not a staple record).
function entryState(chronologDocument, engine, entry, stateFrameIds, groups) {
  if (stateFrameIds.includes(DONE_STATE_FRAME_ID)) return "done";
  if (stateFrameIds.length) return "closed";
  const described = String(chronologDocument?.events?.[entry.id]?.payload?.description || "").trim();
  if (described || groups.length) return null;
  if (staplesForObject(chronologDocument, entry.id, engine).length) return null;
  return "sparse";
}

/**
 * The List's sections: `{grouping, sections: [{key, title, entries, meta}]}`.
 *
 * Population is the session's frame selection, not a filter knob. A todo
 * affiliated with a state frame projects THROUGH that frame -- it renders
 * (with that state's treatment) only while the state frame is selected, so
 * deselecting Done is how completed work leaves the view. A todo with no
 * state affiliation renders when its placement frame is selected; a todo
 * with no placement at all belongs to the null frame and always renders --
 * an unfiled capture must never be invisible.
 *
 * Empty sections are never emitted -- sections exist because entries put
 * them there. The null section (Open / No frame / ...) leads; named sections
 * follow in title order.
 */
export function listSections(chronologDocument, engine, { grouping = "state", selectedFrames = [] } = {}) {
  const mode = normalizeListGrouping(grouping);
  const frames = chronologDocument?.frames || {};
  const selected = new Set(selectedFrames);
  const entries = [];
  for (const entry of rosterEntries(chronologDocument, "todo")) {
    const groups = membershipGroups(chronologDocument, engine, entry.id);
    const stateFrameIds = groups.filter((id) => isStateFrame(frames[id]));
    if (stateFrameIds.length) {
      if (!stateFrameIds.some((id) => selected.has(id))) continue;
    } else if (entry.frame && !selected.has(entry.frame)) continue;
    entries.push({
      ...entry,
      groups,
      stateFrameIds,
      state: entryState(chronologDocument, engine, entry, stateFrameIds, groups)
    });
  }
  const sections = new Map();
  const put = (key, title, entry, meta = null) => {
    const section = sections.get(key) || { key, title, entries: [], meta };
    section.entries.push(entry);
    sections.set(key, section);
  };
  for (const entry of entries) {
    if (mode === "state") {
      if (!entry.stateFrameIds.length) put(null, "Open", entry);
      else for (const id of entry.stateFrameIds) put(id, frames[id]?.title || id, entry);
    } else if (mode === "importance") {
      const importance = entry.groups.filter((id) => frames[id]?.traits?.includes("importance"));
      if (!importance.length) put(null, "No importance", entry);
      else for (const id of importance) put(id, frames[id]?.title || id, entry);
    } else if (mode === "container") {
      const parents = containerParents(chronologDocument, engine, entry.id);
      if (!parents.length) put(null, "No container", entry);
      else {
        for (const parent of parents) {
          put(parent, chronologDocument?.events?.[parent]?.payload?.title || parent, entry,
            containsSummary(chronologDocument, engine, parent));
        }
      }
    } else if (!entry.frame) {
      put(null, "No frame", entry);
    } else {
      put(entry.frame, frames[entry.frame]?.title || entry.frame, entry);
    }
  }
  const ordered = [...sections.values()].sort((left, right) => {
    if (left.key === null) return -1;
    if (right.key === null) return 1;
    return String(left.title).localeCompare(String(right.title)) || String(left.key).localeCompare(String(right.key));
  });
  return { grouping: mode, sections: ordered };
}
