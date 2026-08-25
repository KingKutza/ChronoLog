// The staple substrate.
//
// A STAPLE IS AN EDGE, NOT AN ATTRIBUTE. It connects exactly two things at one
// point -- LEXICON.md's founding conception, where "an event attached to
// multiple lines staples them together at that point", and the owner's ruling
// that "the point and purpose of a staple is to connect two things at a point.
// Here we say we connect my personal calendar frame and this event at a point,
// which is the event's end. Then we can project the two relative to eachother."
//
// So a staple carries two ENDS, and neither is privileged. Each end names a
// thing plus WHERE ON THAT THING the touch point is:
//
//   {frame, coordinate}   a position in a coordinate space. The frame's own
//                         declared law (src/coordinate-law.js) is what makes the
//                         coordinate mean an instant at all, which is why the
//                         frame travels with it rather than being looked up.
//   {object, point}       a named point of an object's extent -- start, end,
//                         midpoint, or a point the user named, which carries its
//                         own `offset` from the object's start.
//   {series}             a whole pattern, positioned by the other end.
//
// The substrate does not care what the two things are, only that each end can
// answer "where is your touch point". That is what lets event <-> event work
// ("the staple is the end of one event and the start of the next, so that they
// project seamlessly as a pair") on the same machinery as event <-> frame, and
// what leaves todos and notes needing no new mechanism.
//
// The staple axiom is the reason this module exists at all: "there is no such
// thing as a time-native object, only objects better or worse stapled to time."
// Placement is not a property an object has; it is derived from the connections
// the object participates in. `resolveObjectExtent` is that derivation, and the
// start-time-plus-duration shape the app was built under is its zero-connection
// degenerate case rather than its only shape.
//
// DOM-free and pure over `{document, engine}` so the whole substrate is testable
// as a contract. Every coordinate is compared through exact Rational days
// (`engine.coordinateDays`), never as text -- ICS writes month "01" where the
// generator writes "1", so a string comparison between two spellings of one
// instant is silently wrong.

import { Rational, coordinate, levelValue } from "./exact.js";
import { GREGORIAN_LAW, coordinateLaw, transitionDefinition } from "./coordinate-law.js";
import { coordinateEntryDepth } from "./coordinate-entry.js";
import { durationMagnitudeDays } from "./model.js";

// The kind registry. `kind` is validated against this rather than hardcoded, so
// adding a kind is one entry plus its interpretation.
//
// Deliberately stricter than frame traits, which stay valid data when
// unfamiliar. A trait is a claim about capability that a renderer may ignore
// with no consequence; a staple kind SELECTS A DERIVATION, and a kind nothing
// honours would silently move things on screen -- or silently fail to.
//
//   connects    the END SHAPES this kind may take, as canonical sorted scope
//               pairs ("object+frame"). This is the whole of what a kind is
//               allowed to join, and it is a PAIR because a staple is an edge:
//               a series' rule segments are cut at instants, so end/inflection/
//               phase join a series to a coordinate space and nothing else,
//               while an anchor joins an object either to a coordinate space or
//               to another object, and a correspondence joins two coordinate
//               spaces directly.
//   partitions  does this kind divide a series' rules into segments
//   carriesRule may this kind carry a following rule (`payload.rule`)
//   positions   do this kind's ends carry a position at all (default true)
//   anchors     does this kind anchor a named point of an object's extent
export const STAPLE_KINDS = Object.freeze({
  // On a series, an end staple cuts the rule (partitions). On an OBJECT it is
  // the terminal abutment the owner ruled for completion: "the end of this todo
  // abuts the beginning of this event" -- the object's `end` point stapled to
  // the instant it finished. Same kind, no completion special case anywhere:
  // which reading an end staple gets is the consumer's derivation, never a
  // field on the record. `anchors: false` is load-bearing for the object case
  // too -- a completion instant names when the todo finished, not where the
  // object sits, so it must never relocate the extent.
  end: Object.freeze({
    label: "Ends here",
    connects: Object.freeze(["frame+series", "frame+object"]),
    partitions: true,
    carriesRule: false,
    anchors: false
  }),
  inflection: Object.freeze({
    label: "Rule changes here",
    connects: Object.freeze(["frame+series"]),
    partitions: true,
    carriesRule: true,
    anchors: false
  }),
  phase: Object.freeze({
    label: "Anchors the cycle's phase",
    connects: Object.freeze(["frame+series"]),
    partitions: false,
    carriesRule: false,
    anchors: false
  }),
  anchor: Object.freeze({
    label: "Anchors a point",
    connects: Object.freeze(["frame+object", "object+object", "frame+series"]),
    partitions: false,
    carriesRule: false,
    anchors: true
  }),
  // Frame to frame, each end a coordinate under ITS OWN frame's law.
  //
  // Owner ruling: a nonlinear frame (Jeremy Bearimy) is to be represented as it
  // is, non-linearly. A set of these staples between two frames is a
  // CORRESPONDENCE, and the substrate must not assume it is monotonic, total, or
  // one-to-one. One point on frame A may correspond to many disjoint points and
  // regions on frame B -- the dot over the i corresponds to every Tuesday AND to
  // July -- and a stretch of A may correspond to nothing at all. Multiple
  // correspondences therefore project as MULTIPLE: never averaged into one
  // mapped position, never sorted into monotone order, never interpolated across
  // a gap. That is the same rule overdetermined anchors already follow, for the
  // same reason -- an average of two true answers is a third answer nobody
  // authored.
  //
  // Distinct from a `coordinate-mapping` relation and never a replacement for
  // it: a mapping declares a RELATIONSHIP between positions or intervals, with
  // explicit continuity and direction, and may be read across its own span. A
  // correspondence staple declares one bare touch point and claims nothing at
  // all about the space between it and the next one. The four frame concepts
  // must not collapse into each other (AGENTS.md), and this is the seam.
  correspondence: Object.freeze({
    label: "Corresponds to a point on another frame",
    connects: Object.freeze(["frame+frame"]),
    partitions: false,
    carriesRule: false,
    anchors: false
  }),
  // Frame to frame, and deliberately WITHOUT a coordinate on either end.
  //
  // Owner ruling: eras are frames stapled together. An era owns its own year
  // numbering and extent; the boundary between two consecutive eras is this
  // staple, and the roles carry the whole of its meaning -- the `end` end names
  // the era that finishes and the `start` end names the era that begins. There
  // is no coordinate to author because there is nothing to author: the boundary
  // IS wherever the earlier era's extent runs out, and stating it twice would
  // create two facts that can disagree.
  //
  // Distinct from `correspondence`, which claims a bare touch point between two
  // frames and nothing about the space around it. A succession claims adjacency
  // and ORDER: the two eras meet exactly, with no gap and no overlap, which is
  // what lets a chain of them derive every era's range from one authored pin.
  succession: Object.freeze({
    label: "Precedes the next era",
    connects: Object.freeze(["frame+frame"]),
    partitions: false,
    carriesRule: false,
    anchors: false,
    // The only kind whose ends carry NO POSITION. Every other kind names a place
    // on a frame; a succession names an adjacency, and the boundary IS wherever
    // the earlier era's extent runs out. Authoring it as a coordinate would
    // create a second fact that can disagree with the extent, and authoring it
    // as a `void` would say "deliberately nowhere" when the truth is "derived".
    positions: false
  })
});

// The canonical key for a pair of end scopes: sorted, so an edge's key does not
// depend on which end was authored first.
export function endScopePair(left, right) {
  return [String(left), String(right)].sort().join("+");
}

/** Which scopes this kind can appear on at all, derived from its `connects`. */
export function stapleKindScopes(kind) {
  const definition = stapleKind(kind);
  if (!definition) return [];
  const scopes = new Set();
  for (const pair of definition.connects) {
    for (const scope of pair.split("+")) scopes.add(scope);
  }
  return [...scopes].sort();
}

// Constraint bounds ("can't go later than like 7:30/8") are deliberately NOT
// registered. LEXICON.md marks them "Adjacent, unruled: 'can't go later than
// 7:30' reads as a bound -- a constraint staple distinct from the fuzzy
// actual." Registering a kind whose semantics nobody has ruled would be
// inventing meaning. The registry above is the one-line path once it is ruled.

export function stapleKind(kind) {
  return Object.hasOwn(STAPLE_KINDS, kind) ? STAPLE_KINDS[kind] : null;
}

export function isStapleKind(kind) {
  return Boolean(stapleKind(kind));
}

// ---------------------------------------------------------------------------
// Ends
// ---------------------------------------------------------------------------

// The default point of an object end. A connection that says nothing about
// which point it touches says the object's start -- the honest reading, and the
// one every pre-connection document's placement already meant.
export const DEFAULT_POINT = "start";

/** The scope an end names, or null when it names nothing resolvable. */
export function endScope(end) {
  if (end?.frame) return "frame";
  if (end?.object) return "object";
  if (end?.series) return "series";
  return null;
}

/** The id an end names, whatever scope it is. */
export function endId(end) {
  return end?.frame || end?.object || end?.series || null;
}

// The four forms a frame end's POSITION can take. An end is "a frame plus a
// position under that frame's own law", and the position is not always one
// instant -- which is the whole content of a nonlinear correspondence.
//
//   coordinate  one point.
//   selector    a position in a repeating cycle or at a level, under this
//               frame's declaration: {cycle: "weekday", value: "Tuesday"} or
//               {level: "month", value: "July"}. "Tuesdays" is NOT one
//               coordinate, and writing it as one would pick an arbitrary
//               Tuesday and call it the answer. Many-valued by construction.
//   span        a region, {from, to} coordinates.
//   void        explicitly nothing. "Sometimes never" is a POSITIVE claim and a
//               different claim from an absent one: an authored void says the
//               author looked and there is no correspondence here, while the
//               absence of a staple says only that nobody has said yet. Reading
//               them as the same thing is how a gap becomes an invitation to
//               interpolate.
export const END_POSITION_FORMS = Object.freeze(["coordinate", "selector", "span", "void"]);

/**
 * Which form this end's position takes, and its payload.
 *
 * `form: null` means the end declares no position at all, which is what a
 * series end and an object end do -- an object end's position is its `point`,
 * resolved from the object's extent, not a coordinate of its own.
 */
export function endPosition(end) {
  if (!end) return { form: null };
  if (end.void === true) return { form: "void" };
  if (end.selector) return { form: "selector", selector: end.selector };
  if (end.span) return { form: "span", span: end.span };
  if (end.coordinate) return { form: "coordinate", coordinate: end.coordinate };
  return { form: null };
}

/**
 * Does the instant `days` satisfy this end's position, under `law`?
 *
 * The membership question a many-valued position can answer, in place of the
 * single-instant question it cannot. A selector reads the frame's own declared
 * cycle or level -- so `{cycle: "weekday", value: "Tuesday"}` resolves through
 * `law.cycleIndex`/`law.cycleNames` and means whatever THAT frame's declaration
 * says a weekday is, including an authored seven-name list that is not the
 * registered one. An authored value name matches case-insensitively; a numeric
 * value matches the cycle index directly.
 *
 * A void position matches nothing, which is the point of it.
 */
export function frameEndMatches(law, end, days) {
  const position = endPosition(end);
  if (position.form === "void" || position.form === null) return false;
  try {
    if (position.form === "coordinate") {
      return law.toDays(position.coordinate).compare(Rational.parse(days)) === 0;
    }
    if (position.form === "span") {
      const at = Rational.parse(days);
      const from = law.toDays(position.span.from);
      const to = law.toDays(position.span.to);
      return at.compare(from) >= 0 && at.compare(to) <= 0;
    }
    return selectorMatches(law, position.selector, days);
  } catch {
    return false;
  }
}

function namedIndex(names, value) {
  if (!Array.isArray(names)) return null;
  const wanted = String(value).trim().toLowerCase();
  const index = names.findIndex((name) => String(name).trim().toLowerCase() === wanted);
  return index === -1 ? null : index;
}

function selectorMatches(law, selector, days) {
  const at = Rational.parse(days);
  if (selector?.cycle) {
    const index = law.cycleIndex(selector.cycle, at);
    if (index === null) return false;
    const named = namedIndex(law.cycleNames(selector.cycle), selector.value);
    if (named !== null) return named === index;
    return Rational.parse(selector.value).compare(index) === 0;
  }
  if (!selector?.level) return false;
  // A level selector reads the level's own value out of the coordinate this
  // instant resolves to, so it means whatever this frame's ladder says that
  // level is -- never a Gregorian month by assumption.
  const atCoordinate = law.fromDays(at);
  const level = atCoordinate?.levels?.find((entry) => entry.level === selector.level);
  if (!level) return false;
  const named = namedIndex(law.namesFor(selector.level), selector.value);
  if (named !== null) {
    // Authored names are one per unit within the parent, and a level whose
    // family counts from one is offset by one against its own name list.
    const base = law.family?.defaults?.[selector.level] === "1" ? 1 : 0;
    return Rational.parse(level.value).compare(named + base) === 0;
  }
  return Rational.parse(level.value).compare(selector.value) === 0;
}

/**
 * A staple's two ends, in authored order.
 *
 * Authored order is the record's own order and nothing more: no derivation
 * below reads index 0 as "the source" or index 1 as "the follower". Direction
 * is not stored because it is not authored -- an instant known at one end
 * propagates to the other, and which end is known is a fact about the document
 * rather than about the staple. That is what makes `A.end <-> B.start` and
 * `B.start <-> A.end` the same connection, as they must be.
 */
export function stapleEnds(staple) {
  const ends = Array.isArray(staple?.ends) ? staple.ends : [];
  return ends.filter((end) => endScope(end) !== null);
}

/** The end of `staple` that names `id`, or null. */
export function stapleEndFor(staple, id) {
  return stapleEnds(staple).find((end) => endId(end) === id) || null;
}

/** The end of `staple` that is not `end`, or null when the staple has only one. */
export function stapleOtherEnd(staple, end) {
  return stapleEnds(staple).find((candidate) => candidate !== end) || null;
}

export function frameEndOf(staple) {
  return stapleEnds(staple).find((end) => endScope(end) === "frame") || null;
}

export function seriesEndOf(staple) {
  return stapleEnds(staple).find((end) => endScope(end) === "series") || null;
}

export function objectEndsOf(staple) {
  return stapleEnds(staple).filter((end) => endScope(end) === "object");
}

// Which map a staple's non-coordinate end points into. `series` names a pattern
// and `object` names an event; a staple reaches at most one series, because a
// series' rules are cut by instants rather than by other objects' extents. Two
// named scopes rather than one polymorphic target because they are different
// maps with different cascade rules -- the same discipline validateTermination
// keeps, where a termination's `line` names a frame and a staple's series names
// a pattern and "the two never interchange".
export function stapleTarget(staple) {
  const series = seriesEndOf(staple);
  if (series) return { scope: "series", id: series.series };
  const objects = objectEndsOf(staple);
  if (objects.length) return { scope: "object", id: objects[0].object };
  return { scope: null, id: null };
}

/**
 * Every id this staple references, by map. The one derivation every cascade
 * sweep shares, so "does this staple point at a record I am deleting" is asked
 * the same way everywhere rather than by hand-reading fields that have since
 * moved onto an end.
 */
export function stapleReferences(staple) {
  const objects = [];
  const series = [];
  const frames = [];
  for (const end of stapleEnds(staple)) {
    if (end.object) objects.push(end.object);
    else if (end.series) series.push(end.series);
    else if (end.frame) frames.push(end.frame);
  }
  return { objects, series, frames };
}

/** Does this staple reference `id` at either end? */
export function stapleReferencesId(staple, id) {
  return stapleEnds(staple).some((end) => endId(end) === id);
}

/**
 * Does this staple reference anything in `ids` at either end?
 *
 * The one predicate every cascade sweep and undo-bundle restore asks. Both ends
 * count: a connection between two events is as much the downstream event's
 * record as the upstream one's, so deleting either has to take it, and a bundle
 * that restores either has to clear it first.
 */
export function stapleTouchesAny(staple, ids) {
  const set = ids instanceof Set ? ids : new Set(ids || []);
  return stapleEnds(staple).some((end) => set.has(endId(end)));
}

// The frame whose law governs this staple's own coordinate, or null for a
// connection that carries no coordinate of its own (an object-to-object staple,
// whose instant comes from the objects).
export function stapleGoverningFrame(staple) {
  return frameEndOf(staple)?.frame || null;
}

/**
 * A copy of this staple with every end id rewritten through `remap`.
 *
 * The one place an id substitution touches an end, so a copy-with-new-ids path
 * (duplicating a frame, reimporting a source that mints fresh ids) cannot leave
 * a connection pointing at the original while claiming to belong to the copy.
 * An id absent from the map is left alone, which is what makes a partial
 * duplicate keep its links to the records that were not copied.
 */
export function withRemappedEnds(staple, remap) {
  const lookup = remap instanceof Map ? remap : new Map(Object.entries(remap || {}));
  return {
    ...staple,
    ends: stapleEnds(staple).map((end) => {
      const key = end.frame ? "frame" : end.object ? "object" : "series";
      const next = lookup.get(endId(end));
      return next === undefined ? { ...end } : { ...end, [key]: next };
    })
  };
}

function allStaples(chronologDocument) {
  return Object.values(chronologDocument?.relations || {}).filter((relation) => relation?.type === "staple");
}

// A stable total order over staples, used for every tie-break in this module.
//
// It is NOT authoring order, and calling it that would be a lie worth avoiding:
// `createId` mints a random UUID, so relation ids carry no creation sequence at
// all. What this order does guarantee is the thing tie-breaks actually need --
// that it is TOTAL, DETERMINISTIC, and identical across reload, journal replay
// and every window looking at the same document, which object key order does
// not promise. Two staples therefore always resolve the same way, even though
// which of them resolves first is arbitrary.
//
// If a staple ever needs to record the sequence it was authored in, that has to
// become a field on the record. Sorting random ids cannot recover it.
function byStableOrder(left, right) {
  return String(left?.id || "").localeCompare(String(right?.id || ""));
}

// Overscale doctrine: `resolveObjectExtent` runs once per event inside the
// engine's fact indexing and now recurses through connection chains, so a
// document-wide relation scan per lookup is the difference between usable and
// unusable at 500 calendars. The engine builds `staplesByObject`/
// `staplesBySeries` in its own reindex (where every other index lives) and is
// passed here; without an engine this falls back to the scan, which is what a
// law-free caller and a direct test want.
function indexedStaples(chronologDocument, engine, index, id) {
  const map = engine?.[index];
  if (map) return map.get(id) || [];
  return allStaples(chronologDocument)
    .filter((staple) => stapleReferencesId(staple, id))
    .sort(byStableOrder);
}

/** Every staple on a series, in a stable, deterministic order. */
export function staplesForSeries(chronologDocument, patternId, engine = null) {
  if (!patternId) return [];
  return indexedStaples(chronologDocument, engine, "staplesBySeries", patternId)
    .filter((staple) => seriesEndOf(staple)?.series === patternId);
}

/** Every staple on an object (event/todo/note), in a stable, deterministic order. */
export function staplesForObject(chronologDocument, objectId, engine = null) {
  if (!objectId) return [];
  return indexedStaples(chronologDocument, engine, "staplesByObject", objectId)
    .filter((staple) => objectEndsOf(staple).some((end) => end.object === objectId));
}

/**
 * Every correspondence this frame participates in, oriented so `from` is always
 * this frame's own end, optionally narrowed to one counterpart frame.
 *
 * ENUMERATION, NOT RESOLUTION. This returns the whole many-valued set in the
 * substrate's one stable order and answers no further question about it: it does
 * not sort by position, does not collapse duplicates, does not pick a nearest
 * match, and does not report a range. A caller that wants "where does this
 * instant land on the other frame" gets every answer the author wrote, or an
 * empty list meaning the author wrote none -- and an empty list is a fact about
 * the correspondence, never a licence to interpolate one from the neighbours.
 *
 * Each entry keeps both ends whole, `coordinate` included, because the two
 * coordinates are written in two different laws and neither can be read through
 * the other's. `frameEndDays(engine, entry.from)` and `frameEndDays(engine,
 * entry.to)` are how each side becomes an instant, each under its own frame.
 */
export function frameCorrespondences(chronologDocument, frameId, counterpartId = null, engine = null) {
  if (!frameId) return [];
  const entries = [];
  for (const staple of indexedStaples(chronologDocument, engine, "staplesByFrame", frameId)) {
    if (staple.kind !== "correspondence") continue;
    const ends = stapleEnds(staple);
    if (ends.length !== 2) continue;
    // Oriented per end rather than per staple: a frame stapled to itself at two
    // different points is a legitimate correspondence (a loop), and it has to
    // enumerate from both of its own ends rather than arbitrarily from one.
    for (const from of ends) {
      if (from.frame !== frameId) continue;
      const to = stapleOtherEnd(staple, from);
      if (endScope(to) !== "frame") continue;
      if (counterpartId && to.frame !== counterpartId) continue;
      entries.push({ staple, from, to });
    }
  }
  return entries;
}

/**
 * What the correspondence between two frames actually is, DERIVED from the
 * staples that constitute it.
 *
 * Cardinality, monotonicity and coverage are properties of the SET, not of any
 * one staple — so they are computed here and never stored. Storing them would
 * put the same claim in two places: an authored `monotonic: false` beside a set
 * of staples that is in fact monotone is an editor accepting an edit and
 * ignoring it, and denormalizing the claim onto every staple in the set means N
 * copies that drift the moment one staple is added. A derivation cannot drift.
 *
 * `monotonic` is `null`, not `true`, when it cannot be decided — a set carrying
 * any many-valued or void position has no single ordering to be monotone
 * against, and reporting `true` there would be a confident answer the data does
 * not support. `voids` counts the authored "corresponds to nothing" claims,
 * which are a positive statement and are never mistaken for the absence of one.
 */
export function describeCorrespondence(chronologDocument, frameA, frameB, engine = null) {
  const entries = frameCorrespondences(chronologDocument, frameA, frameB, engine);
  const sources = new Set();
  const targets = new Set();
  const pairs = [];
  let voids = 0;
  let manyValued = 0;
  for (const entry of entries) {
    if (endPosition(entry.to).form === "void" || endPosition(entry.from).form === "void") {
      voids += 1;
      continue;
    }
    const from = frameEndDays(engine, entry.from);
    const to = frameEndDays(engine, entry.to);
    if (from === null || to === null) {
      manyValued += 1;
      continue;
    }
    sources.add(from.toJSON());
    targets.add(to.toJSON());
    pairs.push({ from, to });
  }
  const total = pairs.length;
  // A DERIVATION THAT NARROWS ITS DOMAIN MUST NARROW ITS CLAIM. The four
  // point-to-point cardinalities are computed over `pairs`, which deliberately
  // excludes every position that is not one instant -- so they may only be
  // reported when nothing was excluded. Reporting "one-to-one" for a set whose
  // other members are selectors would describe the subset this function chose to
  // look at and call it the set, and "empty" for a set of three authored
  // statements would deny they exist.
  //
  //   empty        nothing is authored at all
  //   many-valued  some position is itself many-valued (a selector, a span), so
  //                the set maps one position to many and cannot be one-to-one
  //   void         every authored statement says "nothing corresponds here"
  const cardinality = entries.length === 0 ? "empty"
    : manyValued > 0 ? "many-valued"
      : total === 0 ? "void"
        : sources.size === total && targets.size === total ? "one-to-one"
          : sources.size < total && targets.size === total ? "one-to-many"
            : sources.size === total && targets.size < total ? "many-to-one"
              : "many-to-many";
  let monotonic = null;
  if (!manyValued && !voids && total > 1 && sources.size === total) {
    const ordered = [...pairs].sort((left, right) => left.from.compare(right.from));
    monotonic = ordered.every((pair, index) =>
      index === 0 || pair.to.compare(ordered[index - 1].to) >= 0);
  } else if (!manyValued && !voids && total <= 1) {
    monotonic = true;
  }
  return { count: entries.length, points: total, manyValued, voids, cardinality, monotonic };
}

/**
 * The exact instant a frame end names, or null when it cannot be resolved.
 *
 * Null rather than a throw: an unresolvable end must not take a whole
 * projection offline, and every caller here already has a correct "as if this
 * staple were absent" behavior to fall back on. That is the same conservative
 * direction series-heal.js takes -- a missed derivation leaves an extra record,
 * a wrong one destroys authored data.
 */
// Only a `coordinate` position is ONE instant. A selector, a span, and a void
// are many-valued or empty, and reducing them to a single day here is exactly
// the collapse the correspondence rule forbids -- "Tuesdays" would silently
// become one arbitrary Tuesday. Those positions answer `frameEndMatches`
// instead, which is a membership question rather than a location one.
export function frameEndDays(engine, end) {
  if (!end?.frame || endPosition(end).form !== "coordinate") return null;
  try {
    return engine.coordinateDays(end.frame, end.coordinate) ?? null;
  } catch {
    return null;
  }
}

/**
 * The instant this staple itself names, or null for a connection whose instant
 * comes from the objects it joins rather than from a coordinate.
 *
 * Series derivations use this: a rule segment is cut at an instant, and a
 * series end never connects to another object, so a series staple always has a
 * frame end to read.
 */
export function stapleDays(engine, staple) {
  return frameEndDays(engine, frameEndOf(staple));
}

// ---------------------------------------------------------------------------
// Fuzziness
// ---------------------------------------------------------------------------

// LEXICON.md: "Also a fuzzy staple, e.g. 'about 5ish,' would be good too.
// Fuzziness becomes per-staple, not per-object -- the staple axiom made
// concrete."
//
// Asymmetric on purpose. "About 5ish" spreads both ways; "working early to
// 5ish" and a hard ceiling are different shapes, and a single +/- would flatten
// the distinction the owner drew between a fuzzy actual and a bound. Stored as
// two magnitudes so it reuses the magnitude shape the rest of the model already
// speaks (`{frame, value: {levels}}`), which is also why durationMagnitudeDays
// can read it directly.
//
// Fuzziness lives on the STAPLE, not on either end: it is uncertainty about the
// connection itself. A caller that HAS the document must pass `governing`, or a
// spread magnitude authored under an edited human-time law resolves to the
// wrong days (the same class of bug src/coordinate-law.js exists to make
// impossible).
export function stapleSpreadDays(staple, governing = null) {
  const spread = staple?.spread;
  if (!spread) return null;
  const before = durationMagnitudeDays(spread.before, governing);
  const after = durationMagnitudeDays(spread.after, governing);
  if (before.isZero() && after.isZero()) return null;
  return { before, after };
}

export function isFuzzyStaple(staple, governing = null) {
  return stapleSpreadDays(staple, governing) !== null;
}

const ZERO_SPREAD = Object.freeze({ before: Rational.parse(0), after: Rational.parse(0) });

function spreadOr(staple, governing) {
  return stapleSpreadDays(staple, governing) || ZERO_SPREAD;
}

// Uncertainties ADD. When a magnitude is derived from two fuzzy anchors the
// spread of the difference is the sum of the two spreads, never their
// difference -- two independent uncertainties do not cancel, and treating them
// as if they did would report a confident answer the data does not support.
// The same reasoning carries a spread ALONG a connection chain: an event
// stapled to the fuzzy end of another event is at least as uncertain as the
// event it follows.
function addSpread(left, right) {
  return {
    before: left.before.add(right.before),
    after: left.after.add(right.after)
  };
}

function scaleSpread(spread, factor) {
  return {
    before: spread.before.mul(factor),
    after: spread.after.mul(factor)
  };
}

// ---------------------------------------------------------------------------
// Anchoring
// ---------------------------------------------------------------------------

// LEXICON.md: "We should be able to place a staple - start, end, midpoint,
// etc. - and a magnitude; or two or three staples and calculate magnitude."
//
// Fixed role precedence. Two anchors fully determine an extent, so when three
// or more are present the pair to believe has to be chosen by a rule rather
// than by whichever happened to be authored first -- otherwise adding an
// unrelated midpoint anchor would silently move an event. start and end are
// the two the owner named first and the two an event's own record already
// speaks in, so they outrank a midpoint, which outranks an arbitrary named
// point.
export const ANCHOR_ROLE_ORDER = Object.freeze(["start", "end", "midpoint"]);

// The points of an extent the substrate itself knows how to read. Anything else
// is a point the user named, which carries its own offset from the start.
export const EXTENT_POINTS = ANCHOR_ROLE_ORDER;

function anchorRolePrecedence(role) {
  const index = ANCHOR_ROLE_ORDER.indexOf(role);
  return index === -1 ? ANCHOR_ROLE_ORDER.length : index;
}

function endPoint(end) {
  const point = String(end?.point || "").trim();
  return point || DEFAULT_POINT;
}

// A named point carries how far it sits from the object's start, so a name the
// user invented ("shift handover") still resolves to an extent. Absent, a named
// point behaves as a start anchor, which is the honest default: it says where
// the object is without claiming to know which interior point it names.
//
// The offset lives on the END rather than on the staple, because both ends of a
// connection can be named points and each needs its own.
function namedOffsetDays(end, governing) {
  return durationMagnitudeDays(end?.offset, governing);
}

/**
 * Where on an already-resolved extent a given point sits.
 *
 * This is the "each end can answer where its touch point is" half of the
 * connection model, and the only place a point name becomes an instant.
 */
export function extentPointDays(extent, point, end = null, governing = null) {
  if (!extent || extent.startDays === null || extent.endDays === null) return null;
  const name = String(point || DEFAULT_POINT);
  if (name === "start") return extent.startDays;
  if (name === "end") return extent.endDays;
  if (name === "midpoint") return extent.startDays.add(extent.endDays).div(2);
  return extent.startDays.add(namedOffsetDays(end, governing));
}

// The uncertainty of a point on a resolved extent: its own end's spread for
// start and end, and the mean of the two for anything derived from both.
function extentPointSpread(extent, point) {
  const name = String(point || DEFAULT_POINT);
  if (name === "end") return extent.spread?.end || ZERO_SPREAD;
  if (name === "midpoint") {
    return scaleSpread(addSpread(extent.spread?.start || ZERO_SPREAD, extent.spread?.end || ZERO_SPREAD), Rational.parse("1/2"));
  }
  return extent.spread?.start || ZERO_SPREAD;
}

// The object's own placement relation, read as an implicit `start` connection to
// the frame it is attached to.
//
// This is the migration, and it is a READING rather than a rewrite: an event
// placed by a plain attachment relation IS an event stapled at its start to that
// frame, so nothing the user authored has to move for the connection model to
// govern it. `effectiveObjectStaples` exposes the same reading to an authoring
// surface, so "Start time" can be presented as the default staple it always was
// without a migration pass having to touch a single record.
export function placementRelation(chronologDocument, objectId, engine = null) {
  // Overscale doctrine: this is asked once per object inside fact indexing and
  // again at every step of a connection chain, so a document-wide relation scan
  // here is quadratic on the whole document. The engine indexes it in its own
  // reindex; the scan remains for a law-free or direct-test caller.
  // A MISS IS NOT AN ANSWER. The index records every object the engine has seen
  // attached to anything, mapping to its placement relation or to null for "seen,
  // and it has none" -- so absence from the index means the engine has not seen
  // this object at all, which happens whenever a caller resolves against a
  // document it has mutated since the last reindex (src/series-heal.js does
  // exactly that, by design). Reading a miss as "unplaced" would make a freshly
  // materialized occurrence look like it sits nowhere, and an index that answers
  // confidently about what it has not seen is worse than no index.
  const indexed = engine?.placementByEvent;
  if (indexed?.has(objectId)) return indexed.get(objectId);
  return Object.values(chronologDocument?.relations || {}).find((relation) =>
    isPlacement(relation, objectId)) || null;
}

export function isPlacement(relation, objectId = null) {
  // Any coordinate-carrying attachment places. Completion is not an attachment
  // any more (it is a state-frame membership plus an optional end staple --
  // src/object-kinds.js's stateAffiliations), and a membership relation is a
  // different type entirely, so neither needs excluding here.
  return Boolean(relation?.type === "attachment"
    && (objectId === null || relation.event === objectId)
    && relation.coordinate);
}

/**
 * The object's whole effective connection set: its implicit placement staple
 * first, then every authored staple, each tagged with what an editor needs to
 * write it back.
 *
 * `implicit` entries have no staple record -- `relation` names the attachment
 * relation that IS the connection, so an editor that changes the coordinate
 * writes that relation rather than minting a staple that would then contradict
 * it. That is what keeps "Start time" from being special: it is one row in this
 * list, with the same fields as every other row.
 */
export function effectiveObjectStaples(chronologDocument, objectId, engine = null) {
  const rows = [];
  const placement = placementRelation(chronologDocument, objectId, engine);
  if (placement) {
    rows.push({
      implicit: true,
      relation: placement,
      staple: null,
      kind: "anchor",
      near: { object: objectId, point: DEFAULT_POINT },
      far: {
        frame: placement.frame,
        coordinate: placement.coordinate,
        ...(placement.parameters ? { parameters: placement.parameters } : {})
      }
    });
  }
  for (const staple of staplesForObject(chronologDocument, objectId, engine)) {
    const near = stapleEndFor(staple, objectId);
    rows.push({
      implicit: false,
      relation: null,
      staple,
      kind: staple.kind,
      near,
      far: stapleOtherEnd(staple, near)
    });
  }
  return rows;
}

function derivedMagnitude(first, second) {
  // Exact throughout. The pair is already in role-precedence order, so the
  // arithmetic only has to cover the three orderings that order can produce.
  const pair = `${first.role}+${second.role}`;
  if (pair === "start+end") return second.days.sub(first.days);
  if (pair === "start+midpoint") return second.days.sub(first.days).mul(2);
  if (pair === "end+midpoint") return first.days.sub(second.days).mul(2);
  // Any other pairing involves a named point whose relationship to the other
  // anchor is not defined by the substrate. Refusing is correct: inventing a
  // magnitude from two points whose meaning nobody declared is exactly the
  // "invented interpolation" AGENTS.md forbids for coordinate mappings.
  return null;
}

function extentFromAnchorAndMagnitude(anchor, magnitudeDays, governing) {
  const at = anchor.days;
  if (anchor.role === "end") {
    return { startDays: at.sub(magnitudeDays), endDays: at };
  }
  if (anchor.role === "midpoint") {
    const half = magnitudeDays.div(2);
    return { startDays: at.sub(half), endDays: at.add(half) };
  }
  if (anchor.role === "start") {
    return { startDays: at, endDays: at.add(magnitudeDays) };
  }
  const offset = namedOffsetDays(anchor.end, governing);
  const start = at.sub(offset);
  return { startDays: start, endDays: start.add(magnitudeDays) };
}

/**
 * Every anchoring connection this object participates in, resolved and ordered
 * by role precedence.
 *
 * One anchor per role wins -- the first in `byStableOrder`. A second connection
 * touching the same point is not an error (the collection is open, and rejecting
 * it would lose authored data) but it cannot also be believed, so it is reported
 * as overdetermined and left alone. An object whose start comes from a
 * connection AND from its own frame staple lands here, reported, never averaged.
 */
export function objectAnchors(chronologDocument, engine, objectId, context = null) {
  const resolution = context || newResolution();
  const resolved = [];
  const overdetermined = [];
  const unresolved = [];
  const seenRoles = new Set();
  let cyclic = false;
  for (const staple of staplesForObject(chronologDocument, objectId, engine)) {
    if (!stapleKind(staple.kind)?.anchors) continue;
    // Traversing an edge must not count as arriving back at it. A staple between
    // A and B is ONE edge, and because direction is not stored both objects see
    // it; asking B where it is while resolving A would otherwise find that same
    // staple pointing back at A and call it a cycle. Skipping the edge already
    // being crossed is what leaves a real cycle -- two DIFFERENT staples closing
    // a loop -- as the only thing the path guard fires on.
    if (resolution.crossed.has(staple.id)) continue;
    const near = stapleEndFor(staple, objectId);
    const far = stapleOtherEnd(staple, near);
    const role = endPoint(near);
    if (!far) {
      unresolved.push({ role, staple, reason: "this staple has only one end, so it connects nothing" });
      continue;
    }
    let days = null;
    let spread = spreadOr(staple, chronologDocument);
    let frame = null;
    if (endScope(far) === "frame") {
      days = frameEndDays(engine, far);
      frame = far.frame;
    } else if (endScope(far) === "object") {
      // A connection whose other end resolves back through this object cannot be
      // resolved at all: the pair would each be waiting on the other. Reported
      // rather than iterated to a fixed point, because there is no instant to
      // report and guessing one would place an object nobody positioned.
      if (resolution.path.has(far.object)) {
        cyclic = true;
        unresolved.push({ role, staple, reason: "this connection resolves back through the object it places" });
        continue;
      }
      const upstream = resolveExtent(chronologDocument, engine, far.object, {
        ...resolution,
        path: new Set([...resolution.path, objectId]),
        crossed: new Set([...resolution.crossed, staple.id])
      });
      // A cycle anywhere below makes THIS answer path-dependent too, so it has
      // to travel up: the memo is only safe for a subtree that resolved without
      // one, and a diamond over a cycle would otherwise cache an answer that is
      // only true for the path it was reached by.
      if (upstream.cyclic) cyclic = true;
      days = extentPointDays(upstream, endPoint(far), far, chronologDocument);
      if (days !== null) {
        spread = addSpread(spread, extentPointSpread(upstream, endPoint(far)));
        frame = upstream.frame || null;
      }
    }
    if (days === null) {
      unresolved.push({ role, staple, reason: "this connection's other end has no resolvable position" });
      continue;
    }
    if (seenRoles.has(role)) {
      overdetermined.push({ role, staple, days, reason: "another connection already anchors this point" });
      continue;
    }
    seenRoles.add(role);
    resolved.push({ role, staple, end: near, days, spread, frame });
  }
  resolved.sort((left, right) =>
    anchorRolePrecedence(left.role) - anchorRolePrecedence(right.role)
    || byStableOrder(left.staple, right.staple));

  // The object's own placement relation IS an implicit start connection to the
  // frame it is attached to, so a connection that also claims `start` is a
  // second claim on the same point. Anchors take precedence -- that is the
  // documented order -- but the contest has to be REPORTED rather than silently
  // won, because the surface that authored both is the only place that can
  // resolve it. Never averaged: an average of two authored positions is a third
  // position nobody wrote.
  if (resolved.length) {
    const placement = placementRelation(chronologDocument, objectId, engine);
    if (placement && resolved.some((anchor) => anchor.role === DEFAULT_POINT)) {
      overdetermined.push({
        role: DEFAULT_POINT,
        staple: null,
        relation: placement,
        days: null,
        reason: "this object's own placement also names its start"
      });
    }
  }
  return { anchors: resolved, overdetermined, unresolved, cyclic };
}

function newResolution() {
  return { path: new Set(), crossed: new Set(), memo: new Map() };
}

// The memo is only safe for a subtree that resolved without hitting a cycle: a
// cyclic result depends on which path reached it, so caching it would leak one
// object's resolution order into another's answer. It is also keyed by the set of
// edges already crossed, because skipping a different edge can give a different
// answer -- one memo per traversal state, never one per object.
function resolveExtent(chronologDocument, engine, objectId, resolution) {
  const key = resolution.crossed.size ? `${objectId} ${[...resolution.crossed].sort().join(" ")}` : objectId;
  const cached = resolution.memo.get(key);
  if (cached) return cached;
  const extent = deriveExtent(chronologDocument, engine, objectId, resolution);
  if (!extent.cyclic) resolution.memo.set(key, extent);
  return extent;
}

/**
 * Where an object actually sits, derived from the connections it participates in.
 *
 * This retires the start-time-plus-duration assumption as the ONLY shape while
 * keeping it as the shape a document with no authored staples still gets, bit
 * for bit. Precedence, when the anchors overdetermine the extent:
 *
 *   0 anchors  the placement relation is the start; magnitude is the object's
 *              own duration. Identical to the behavior before this substrate.
 *   1 anchor   that anchor plus the object's magnitude. An `end` anchor here is
 *              the end-anchored work shift LEXICON.md asks for -- an event
 *              DEFINED by where it stops. It is also the seamless pair: the
 *              downstream event's start IS the upstream event's end, so moving
 *              the upstream event moves this one, through the connection.
 *   2 anchors  the extent is fully determined and the MAGNITUDE IS DERIVED; the
 *              object's own duration is ignored for placement rather than
 *              fought with.
 *   3+ anchors the two highest-precedence roles determine the extent. Every
 *              remaining anchor is returned in `overdetermined` and is NEVER
 *              averaged into the answer -- an average of contradictory anchors
 *              is an invented value, and the surface that authored them is the
 *              only place that can resolve the contradiction.
 *
 * `spread` carries the fuzziness of the derived start and end so rendering can
 * see it. It is data, not a drawing instruction: the display language for
 * uncertainty is not designed, so nothing here decides how it looks.
 *
 * `frame` is the coordinate space the extent was resolved in, propagated along
 * a connection chain -- a downstream event inherits the space its upstream
 * anchor was positioned in, which is what "then we can project the two relative
 * to eachother" needs.
 */
export function resolveObjectExtent(chronologDocument, engine, objectId) {
  return deriveExtent(chronologDocument, engine, objectId, newResolution());
}

function deriveExtent(chronologDocument, engine, objectId, resolution) {
  const event = chronologDocument?.events?.[objectId] || null;
  const magnitudeDays = durationMagnitudeDays(event?.magnitudes?.duration, chronologDocument);
  const { anchors, overdetermined, unresolved, cyclic } = objectAnchors(chronologDocument, engine, objectId, resolution);

  if (anchors.length >= 2) {
    const [first, second] = anchors;
    const derived = derivedMagnitude(first, second);
    if (derived !== null) {
      const magnitudeFromAnchors = derived.abs();
      // The extent is placed from the HIGHEST-PRECEDENCE anchor, not from
      // whichever of the pair happens to be earlier. Those differ: for an
      // end+midpoint pair the magnitude is 2*(end - mid), and the start is
      // `end - magnitude` = 2*mid - end, which is EARLIER than either anchor.
      // Treating the earlier anchor as the start would put the start at the
      // midpoint and silently halve the event.
      const extent = extentFromAnchorAndMagnitude(first, magnitudeFromAnchors, chronologDocument);
      const spread = addSpread(first.spread, second.spread);
      return {
        ...extent,
        magnitudeDays: magnitudeFromAnchors,
        source: "anchors",
        derivedMagnitude: true,
        anchors,
        overdetermined: [
          ...overdetermined,
          ...anchors.slice(2).map((anchor) => ({
            role: anchor.role,
            staple: anchor.staple,
            days: anchor.days,
            reason: "two higher-precedence anchors already determine the extent"
          }))
        ],
        unresolved,
        cyclic,
        spread: { start: spread, end: spread },
        frame: first.frame || null
      };
    }
  }

  if (anchors.length >= 1) {
    const anchor = anchors[0];
    const extent = extentFromAnchorAndMagnitude(anchor, magnitudeDays, chronologDocument);
    return {
      ...extent,
      magnitudeDays,
      source: "anchor+magnitude",
      derivedMagnitude: false,
      anchors,
      overdetermined: [
        ...overdetermined,
        ...anchors.slice(1).map((other) => ({
          role: other.role,
          staple: other.staple,
          days: other.days,
          reason: "its role pairing with the leading anchor derives no magnitude"
        }))
      ],
      unresolved,
      cyclic,
      spread: { start: anchor.spread, end: anchor.spread },
      frame: anchor.frame || null
    };
  }

  const placement = placementRelation(chronologDocument, objectId, engine);
  if (!placement) {
    // A zero-staple object is legitimate -- LEXICON.md: "Zero-staple objects
    // are possible; most carry one or more." It simply has no extent to
    // report, which a caller must handle rather than be handed a fabricated
    // date for.
    return {
      startDays: null,
      endDays: null,
      magnitudeDays,
      source: "unstapled",
      derivedMagnitude: false,
      anchors: [],
      overdetermined,
      unresolved,
      cyclic,
      spread: { start: ZERO_SPREAD, end: ZERO_SPREAD },
      frame: null
    };
  }
  let startDays = null;
  try {
    startDays = engine.coordinateDays(placement.frame, placement.coordinate);
  } catch {
    startDays = null;
  }
  if (startDays === null) {
    return {
      startDays: null,
      endDays: null,
      magnitudeDays,
      source: "unresolved",
      derivedMagnitude: false,
      anchors: [],
      overdetermined,
      unresolved,
      cyclic,
      spread: { start: ZERO_SPREAD, end: ZERO_SPREAD },
      frame: placement.frame || null
    };
  }
  return {
    startDays,
    endDays: startDays.add(magnitudeDays),
    magnitudeDays,
    source: "placement",
    derivedMagnitude: false,
    anchors: [],
    overdetermined,
    unresolved,
    cyclic,
    spread: { start: ZERO_SPREAD, end: ZERO_SPREAD },
    frame: placement.frame || null
  };
}

// ---------------------------------------------------------------------------
// Series partitioning
// ---------------------------------------------------------------------------

// LEXICON.md, the Rob-and-John scenario: "a series is an identity whose rules
// are segments partitioned by staples ... a staple at an inflection point ends
// the reigning rule, and a new rule may follow on the same series or a new
// series may begin, on preference."
//
// BOUNDARY CONVENTION, and it is load-bearing: a partitioning staple CLOSES the
// reigning segment inclusively and OPENS the following one exclusively. The
// inclusive close is the end-staple's own behavior ("the staple's own occurrence
// survives; nothing after it projects"), and once close is inclusive, exclusive
// open is the only choice that does not project the staple instant twice.

// A partitioning staple closes its segment at the END OF THE UNIT THE AUTHOR
// NAMED, not at the instant that unit happens to begin.
//
// Ruled for "ends on a date" (src/recurrence-end.js): "'Ends on this date' means
// through the whole of that day, whatever time of day the occurrences fall at --
// so the value is the last second of the date, not its midnight. A midnight
// UNTIL would silently drop a 09:00 series' final occurrence, which is the kind
// of off-by-one a user reads as a bug." A bare-date staple cutting at midnight is
// that same bug one layer up, so it takes the same answer.
//
// The rule is generic rather than kind-special, and it is drawn where
// `recurrenceUntilForCoordinate` already draws it: a coordinate authored at or
// above the base unit names a PERIOD (a day, a month, a year) and closes at that
// period's last instant, while a coordinate that descends into the levels below
// the base names a clock INSTANT and closes exactly there. Precision is authored
// data -- the depth the author stopped at -- so this reads it off the coordinate
// rather than inferring it from a resolved day.
//
// "Last instant" is the next unit's start less one of the law's own finest
// measurable steps, which under the registered standard is the 23:59:59 that
// `recurrenceUntilForDate` writes -- the same value by the same reasoning.
function partitionCloseDays(law, coordinateValue, days) {
  if (days === null || !law) return days;
  const depth = coordinateEntryDepth(coordinateValue, law);
  if (!depth) return days;
  if (law.belowLadder.some((level) => level.name === depth)) return days;
  const next = incrementedToDepth(law, coordinateValue, depth);
  if (next === null) return days;
  try {
    const step = Rational.parse(1).div(law.secondsPerDay());
    return law.toDays(next).sub(step);
  } catch {
    return days;
  }
}

// The low value of a level, read from the family's own defaults rather than
// assumed: a level the calendar counts from one is one-based, anything else is
// zero-based.
function levelFloor(law, name) {
  return law.family?.defaults?.[name] === "1" ? 1n : 0n;
}

function childrenInLevel(law, name, parts) {
  const level = law.level(name);
  if (!level) return null;
  if (level.radix) return level.radix.n;
  if (!level.transition) return null;
  try {
    return transitionDefinition(level.transition)?.childrenIn(parts) ?? null;
  } catch {
    return null;
  }
}

// The coordinate one unit later at `depth`, carrying into the coarser levels when
// the increment runs off the end of its parent -- so the day after the 31st is the
// 1st of the next month, computed from the level's OWN declared child count
// (`radix`, or its transition's `childrenIn`) and never from a hardcoded calendar.
// The root has no parent to carry into, which is what terminates this.
function incrementedToDepth(law, coordinateValue, depth) {
  const ladder = law.aboveLadder.map((level) => level.name);
  const index = ladder.indexOf(depth);
  if (index < 0) return null;
  const parts = {};
  for (const name of ladder) {
    parts[name] = BigInt(levelValue(coordinateValue, name, law.family?.defaults?.[name] ?? "0"));
  }
  for (let at = index; at >= 0; at -= 1) {
    const name = ladder[at];
    parts[name] += 1n;
    if (at === 0) break;
    const count = childrenInLevel(law, name, parts);
    const floor = levelFloor(law, name);
    if (count === null || parts[name] < floor + count) break;
    parts[name] = floor;
  }
  return coordinate(ladder.slice(0, index + 1).map((name) => ({ level: name, value: parts[name].toString() })));
}

function lawForFrame(chronologDocument, frameId) {
  if (!chronologDocument || !frameId || !chronologDocument.frames?.[frameId]) return null;
  try {
    return coordinateLaw(chronologDocument, frameId);
  } catch {
    return null;
  }
}

/**
 * A series' rule segments, in chronological order.
 *
 * One staple with no following rule yields exactly two entries' worth of
 * meaning -- a bounded segment 0 and nothing after it -- which is why a lone
 * end-staple works through this without a special case.
 */
export function seriesSegments(engine, pattern) {
  const chronologDocument = engine?.document;
  const templateRelation = chronologDocument?.relations?.[pattern?.templateRelation] || null;
  const partitioning = staplesForSeries(chronologDocument, pattern?.id, engine)
    .filter((staple) => stapleKind(staple.kind)?.partitions)
    .map((staple) => {
      const end = frameEndOf(staple);
      const authored = stapleDays(engine, staple);
      // Both the inclusive close and the following segment's exclusive open use
      // the SAME instant, or occurrences between the authored midnight and the
      // end of the named unit would fall into both segments.
      const days = partitionCloseDays(lawForFrame(chronologDocument, end?.frame), end?.coordinate, authored);
      return { staple, end, authored, days };
    })
    .filter((entry) => entry.days !== null)
    .sort((left, right) => left.days.compare(right.days) || byStableOrder(left.staple, right.staple));

  const segments = [];
  let reigning = {
    fromDays: null,
    rrule: pattern?.rrule || {},
    baseCoordinate: templateRelation?.coordinate || null,
    frame: templateRelation?.frame || pattern?.frame || null,
    exdates: pattern?.exdates || [],
    exclude: pattern?.exclude || null,
    magnitude: null,
    openedBy: null
  };

  for (const entry of partitioning) {
    segments.push({ ...reigning, index: segments.length, untilDays: entry.days, closedBy: entry.staple });
    const head = entry.staple.payload?.rule;
    // No following rule: this staple terminates the series. The degenerate
    // case, and the one a lone end-staple consists of.
    if (!head) return segments;
    reigning = {
      fromDays: entry.days,
      rrule: head.rrule || {},
      baseCoordinate: head.coordinate || entry.end?.coordinate || null,
      frame: head.frame || entry.end?.frame || reigning.frame,
      exdates: head.exdates || [],
      exclude: head.exclude ?? null,
      magnitude: head.magnitude || null,
      openedBy: entry.staple
    };
  }
  segments.push({ ...reigning, index: segments.length, untilDays: null, closedBy: null });
  return segments;
}

/**
 * The instant segment 0 is cut off at by a staple, or null when no partitioning
 * staple exists.
 *
 * `seriesEffectiveUntilDays` in src/engine.js intersects this with the rule's
 * own written UNTIL. Keeping the two separate is what lets removing a staple
 * restore the full projection for free -- the rule keeps saying what it says.
 */
export function seriesStapleUntilDays(engine, pattern) {
  const segments = seriesSegments(engine, pattern);
  return segments[0]?.untilDays ?? null;
}

/** Does this series' rule change part-way through, rather than merely stopping? */
export function seriesIsSegmented(engine, pattern) {
  return seriesSegments(engine, pattern).length > 1;
}

// ---------------------------------------------------------------------------
// Occurrence phase
// ---------------------------------------------------------------------------

/**
 * The base instant a series' generator should count cycles from.
 *
 * LEXICON.md: "stapling an arbitrary occurrence anchors the cycle's phase."
 * A phase staple replaces the template relation's coordinate AS THE GENERATOR'S
 * BASE without rewriting the template -- the same discipline as the end-staple,
 * so removing the phase staple restores the original phase for free. Irregular
 * night-shift cycles are the authoring case this serves.
 *
 * Returns null when no phase staple applies, meaning "use the segment's own
 * base coordinate".
 */
export function seriesPhaseDays(engine, pattern) {
  const staples = staplesForSeries(engine?.document, pattern?.id, engine)
    .filter((staple) => staple.kind === "phase");
  for (const staple of staples) {
    const days = stapleDays(engine, staple);
    if (days !== null) return days;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Exclusions as live references
// ---------------------------------------------------------------------------

// LEXICON.md, Rob-and-John beat 2: "skip holidays (events on frame xyz)" and
// "holiday exclusion is a live reference to another frame's events, not a baked
// list." So this resolves at PROJECTION time against whatever those frames
// currently hold. Adding a holiday to the referenced calendar changes the
// series with no edit to the series, and removing one puts the meeting back.
//
// Matched by WHOLE DAY, not by instant. A holiday is an all-day event; a 6:15
// meeting on that date has to be skipped even though it shares no instant with
// a midnight-to-midnight span. Comparing instants would silently keep every
// timed occurrence on every holiday, which reads as the feature not working.

function excludedFrameIds(exclude) {
  if (!exclude) return [];
  if (Array.isArray(exclude.frames)) return exclude.frames.filter(Boolean);
  if (exclude.frame) return [exclude.frame];
  return [];
}

/**
 * The set of whole days covered by events on the referenced frames, over a
 * bounded window.
 *
 * Bounded on purpose: the referenced frame can be an entire imported holiday
 * calendar, and a projection only ever needs the window it is drawing. Days are
 * keyed by their exact integer day number as text, so membership is an exact
 * numeric identity and never a coordinate-spelling comparison.
 */
export function liveExclusionDays(engine, exclude, lower, upper) {
  const frames = excludedFrameIds(exclude);
  if (!frames.length) return null;
  const days = new Set();
  const from = Rational.parse(lower).floor();
  const to = Rational.parse(upper).floor();
  for (const frameId of frames) {
    let entries = [];
    try {
      entries = engine.indexedExplicitFacts(frameId) || [];
    } catch {
      continue;
    }
    for (const entry of entries) {
      const start = entry.day;
      if (start === null || start === undefined) continue;
      const duration = durationMagnitudeDays(entry.fact?.event?.magnitudes?.duration, engine.document);
      const first = start.floor();
      // An all-day event stored as a 1-day duration covers exactly its own
      // day, so the last covered day is derived from the final instant strictly
      // inside the span rather than from the exclusive end. The nudge only has
      // to be smaller than one base day to land in the right whole day, so it
      // reads through the REGISTERED standard's own finest unit rather than a
      // bare 86400 -- any unit finer than one base unit gives the same answer,
      // which is why this does not need the governing frame's own law.
      const endInstant = start.add(duration);
      const last = duration.isZero() ? first : endInstant.sub(Rational.parse(1).div(GREGORIAN_LAW.secondsPerDay())).floor();
      if (last < from || first > to) continue;
      const begin = first < from ? from : first;
      const finish = last > to ? to : last;
      for (let day = begin; day <= finish; day += 1n) days.add(day.toString());
    }
  }
  return days;
}

/** Is this occurrence's own day excluded by a live reference? */
export function isLiveExcluded(excludedDays, dayRational) {
  if (!excludedDays || !excludedDays.size) return false;
  return excludedDays.has(Rational.parse(dayRational).floor().toString());
}

export { addSpread as addStapleSpread, scaleSpread as scaleStapleSpread };
