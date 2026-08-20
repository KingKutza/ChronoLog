import { EraTable } from "./eras.js";
import { endId, endScope, stapleEnds } from "./staples.js";

// Eras are FRAMES STAPLED TOGETHER.
//
// Owner ruling, replacing an earlier era-table-on-a-declaration model: an era is
// its own frame. It owns its year numbering (where the numbers start, which way
// they run) and its extent; it inherits its month/day structure from a basis; and
// the boundary between two consecutive eras is a `succession` staple, whose two
// ends carry the whole of its meaning through their roles -- `end` names the era
// that finishes, `start` names the era that begins. A calendar spanning eras is a
// GROUP frame over the chain.
//
// Why frames and not a table. An era is exactly the sort of thing a frame already
// is: it has an extent, it holds events, it can be a member of groups, it can be
// displayed or hidden, and it can be handled differently from its neighbours. A
// table row can do none of that. Modelling eras as rows meant every one of those
// capabilities would have had to be reinvented against a second kind of object,
// and the era's own identity would have been a string in a list rather than a
// record with an id -- which is what made era membership, era-level display
// weight, and a non-countable era all inexpressible.
//
// This module walks the chain and derives every era's range. The ARITHMETIC is
// `EraTable`'s, unchanged: ordered eras, per-era direction and first year, one
// authored pin, ranges propagated outward in PROPER YEARS. What changes is where
// the ordered list comes from -- succession staples between frame records rather
// than an array in one declaration -- and that the result is keyed by frame id.

const ERA_ROLES = Object.freeze({ END: "end", START: "start" });

/** The `era` block a frame carries, or null for a frame that is not an era. */
export function eraDeclaration(frame) {
  return frame?.era && typeof frame.era === "object" ? frame.era : null;
}

export function isEraFrame(frame) {
  return eraDeclaration(frame) !== null;
}

/**
 * An era with no metric ladder: ordered and connected, never acquiring day
 * ordinals. The Dawn Era precedes the Merethic and has no year axis at all --
 * time there being the thing that had not started behaving yet -- so it holds
 * events in sequence and answers no question about when.
 *
 * `countable: false` is the authored statement. A frame that simply has no basis
 * is ALSO uncountable in practice, but that is a consequence rather than a
 * claim, and the two are kept distinct so a missing basis reads as an error
 * where it is one.
 */
export function isCountableEra(frame) {
  const era = eraDeclaration(frame);
  if (!era) return false;
  return era.countable !== false;
}

function successionEdges(documentValue) {
  const edges = [];
  for (const relation of Object.values(documentValue?.relations || {})) {
    if (relation?.type !== "staple" || relation.kind !== "succession") continue;
    const ends = stapleEnds(relation).filter((end) => endScope(end) === "frame");
    if (ends.length !== 2) continue;
    const from = ends.find((end) => end.role === ERA_ROLES.END);
    const to = ends.find((end) => end.role === ERA_ROLES.START);
    if (!from || !to) continue;
    edges.push({ relation, from: endId(from), to: endId(to) });
  }
  return edges;
}

/**
 * Every era frame reachable from `frameId` through succession staples, in
 * chain order (oldest first), regardless of which era the caller named.
 *
 * A chain is a linked list, so it is walked rather than sorted: the head is the
 * era nothing succeeds. A fork (two eras claiming the same predecessor) or a
 * cycle is refused rather than resolved by precedence -- both mean the author
 * has said two contradictory things about what follows what.
 */
export function eraChainFrames(documentValue, frameId) {
  const edges = successionEdges(documentValue);
  const reachable = new Set();
  const queue = [String(frameId)];
  while (queue.length) {
    const current = queue.pop();
    if (reachable.has(current)) continue;
    reachable.add(current);
    for (const edge of edges) {
      if (edge.from === current) queue.push(edge.to);
      if (edge.to === current) queue.push(edge.from);
    }
  }
  const members = [...reachable].filter((id) => isEraFrame(documentValue?.frames?.[id]));
  if (!members.length) return [];

  const next = new Map();
  const previous = new Map();
  for (const edge of edges) {
    if (!reachable.has(edge.from) || !reachable.has(edge.to)) continue;
    if (next.has(edge.from) && next.get(edge.from) !== edge.to) {
      throw new TypeError(
        `Two eras both follow ${edge.from}; a succession chain cannot fork.`
      );
    }
    if (previous.has(edge.to) && previous.get(edge.to) !== edge.from) {
      throw new TypeError(
        `Two eras both precede ${edge.to}; a succession chain cannot fork.`
      );
    }
    next.set(edge.from, edge.to);
    previous.set(edge.to, edge.from);
  }
  const heads = members.filter((id) => !previous.has(id));
  if (heads.length !== 1) {
    throw new TypeError(
      heads.length
        ? `This era chain has ${heads.length} beginnings (${heads.join(", ")}); it must have exactly one.`
        : "This era chain has no beginning, so its eras form a loop."
    );
  }
  const ordered = [];
  const seen = new Set();
  let cursor = heads[0];
  while (cursor) {
    if (seen.has(cursor)) throw new TypeError(`The era chain loops at ${cursor}.`);
    seen.add(cursor);
    ordered.push(cursor);
    cursor = next.get(cursor) || null;
  }
  if (ordered.length !== members.length) {
    throw new TypeError("Some eras in this chain are not connected to the rest of it.");
  }
  return ordered;
}

/**
 * The chain as an `EraTable` plus the frame index that maps a frame id to its
 * entry. NON-COUNTABLE eras are excluded from the table: they have no year axis,
 * so they take part in the ORDER and in nothing else. Their place in the chain is
 * still returned, because ordering is exactly what they do have.
 *
 * The pin is authored on whichever era frame carries `era.anchor`. Exactly one
 * must, for the same reason `EraTable` takes exactly one: two pins are two facts
 * that can disagree.
 */
export function eraChain(documentValue, frameId) {
  const ordered = eraChainFrames(documentValue, frameId);
  if (!ordered.length) return null;

  const countable = ordered.filter((id) => isCountableEra(documentValue.frames[id]));
  const pins = ordered.filter((id) => eraDeclaration(documentValue.frames[id])?.anchor);
  if (pins.length !== 1) {
    throw new TypeError(
      pins.length
        ? `This era chain is pinned ${pins.length} times (${pins.join(", ")}); exactly one era states where it sits.`
        : "This era chain states nowhere that it sits; one era must carry an anchor."
    );
  }
  const pinFrame = documentValue.frames[pins[0]];
  const pinEra = eraDeclaration(pinFrame);
  if (!isCountableEra(pinFrame)) {
    throw new TypeError(`${pins[0]} has no year axis, so it cannot anchor the chain.`);
  }

  const entries = countable.map((id) => {
    const era = eraDeclaration(documentValue.frames[id]);
    return {
      key: era.key || id,
      name: era.name || documentValue.frames[id].title || era.key || id,
      direction: era.direction,
      years: era.years,
      firstYear: era.firstYear,
      affix: era.affix,
      frame: id
    };
  });
  const table = new EraTable({
    anchor: {
      era: pinEra.key || pins[0],
      year: pinEra.anchor.year,
      properYear: pinEra.anchor.properYear
    },
    entries
  });
  // `EraTable` may reorder by `ordinal`; the chain's own order is authoritative
  // here, so entries are matched back by key rather than by position.
  const byFrame = new Map();
  for (const id of countable) {
    const era = eraDeclaration(documentValue.frames[id]);
    byFrame.set(id, table.era(era.key || id));
  }
  return { ordered, countable, table, byFrame, pin: pins[0] };
}

/**
 * The era context one frame's coordinate law needs: its own entry in the chain
 * and the table that entry belongs to. Null for a frame that is not an era.
 *
 * A non-countable era resolves to `{ countable: false }` and no table: its law
 * must refuse day ordinals rather than compute them, which is what "ordered,
 * connected, never acquiring day ordinals" means in executable terms.
 */
export function frameEraContext(documentValue, frameId) {
  const frame = documentValue?.frames?.[frameId];
  if (!isEraFrame(frame)) return null;
  if (!isCountableEra(frame)) {
    const era = eraDeclaration(frame);
    return { countable: false, key: era.key || frameId, name: era.name || frame.title || frameId };
  }
  const chain = eraChain(documentValue, frameId);
  const entry = chain?.byFrame.get(String(frameId));
  if (!entry) throw new TypeError(`${frameId} is an era but is not in its own chain.`);
  return { countable: true, entry, table: chain.table, chain };
}
