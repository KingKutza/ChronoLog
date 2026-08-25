// The Board lens's own projection math. Pure over `{document, engine}` --
// the renderer wiring lives in src/projections.js, following the
// lines.js/radial.js per-lens-module pattern.
//
// Deliberately independent of src/list.js even where the two compute similar
// things (the Spiral/Radial precedent: "there is no common sub straight
// except that data. both lenses... independently project the data per there
// own rules. Never should we let a change to one lense impact any other
// lense except where the change was to the data"). The only sharing is the
// data layer that already exists -- rosterEntries, state derivations, the
// staple substrate -- never a common column model.
import { DONE_STATE_FRAME_ID, isStateFrame, containsSummary, rosterEntries } from "./object-kinds.js";
import { staplesForObject } from "./staples.js";

// "Columns are the grouping": the Board's one setting names which grouping
// supplies its columns. There are no filters -- visibility is which frames
// the session projects.
export const BOARD_GROUPINGS = Object.freeze(["state", "importance", "container", "frame"]);

export function normalizeBoardGrouping(value) {
  return BOARD_GROUPINGS.includes(value) ? value : "state";
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

// The state a card renders with -- same vocabulary as everywhere else (done,
// closed, sparse, open-as-absence), derived here for this lens's own cards.
function cardState(chronologDocument, engine, entry, stateFrameIds, groups) {
  if (stateFrameIds.includes(DONE_STATE_FRAME_ID)) return "done";
  if (stateFrameIds.length) return "closed";
  const described = String(chronologDocument?.events?.[entry.id]?.payload?.description || "").trim();
  if (described || groups.length) return null;
  if (staplesForObject(chronologDocument, entry.id, engine).length) return null;
  return "sparse";
}

/**
 * The Board's columns: `{grouping, columns: [{key, title, entries, meta}]}`.
 *
 * Population is the session's frame selection, never a filter knob: a
 * state-affiliated todo projects through its state frame (deselecting Done is
 * how completed work leaves the board), an unaffiliated-by-state todo needs
 * its placement frame selected, and an unplaced todo belongs to the null
 * frame and always renders.
 *
 * Empty columns are NEVER emitted -- a column exists because entries put it
 * there, which is what keeps a narrow screen from paying for full-width
 * nothing. The null column leads; named columns follow in title order.
 */
export function boardColumns(chronologDocument, engine, { grouping = "state", selectedFrames = [] } = {}) {
  const mode = normalizeBoardGrouping(grouping);
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
      state: cardState(chronologDocument, engine, entry, stateFrameIds, groups)
    });
  }
  const columns = new Map();
  const put = (key, title, entry, meta = null) => {
    const column = columns.get(key) || { key, title, entries: [], meta };
    column.entries.push(entry);
    columns.set(key, column);
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
  const ordered = [...columns.values()].sort((left, right) => {
    if (left.key === null) return -1;
    if (right.key === null) return 1;
    return String(left.title).localeCompare(String(right.title)) || String(left.key).localeCompare(String(right.key));
  });
  return { grouping: mode, columns: ordered };
}
