// The staple substrate.
//
// Owner ruling (8.19, on the shipped end-staple): it "presupposes that an end
// staple is special. I see no clear mechanism to add an arbitrary number or
// type of staples or to use them to define any facet of the series other than
// its termination." So nothing here treats "end" as structural. A staple is a
// member of an OPEN COLLECTION on any object -- LEXICON.md: "todos, and
// Events, and any future objects can have arbitrarily many staples of
// arbitrary type arbitrarily placed, and should be able to render
// accordingly" -- and `kind: "end"` is one registered entry whose
// interpretation happens to be "terminate, with no rule following".
//
// The staple axiom is the reason this module exists at all: "there is no such
// thing as a time-native object, only objects better or worse stapled to
// time." Placement is therefore not a property an object has; it is something
// derived from the staples the object carries. `resolveObjectExtent` below is
// that derivation, and the start-time-plus-duration shape the app was built
// under becomes its zero-anchor degenerate case rather than its only shape.
//
// DOM-free and pure over `{document, engine}` so the whole substrate is
// testable as a contract. Every coordinate is compared through exact Rational
// days (`engine.coordinateDays`), never as text -- ICS writes month "01" where
// the generator writes "1", so a string comparison between two spellings of
// one instant is silently wrong.

import { Rational } from "./exact.js";
import { durationMagnitudeDays } from "./model.js";

// The kind registry. `kind` is validated against this rather than hardcoded,
// which is the mechanism the owner found missing -- adding a kind is one entry
// plus its interpretation.
//
// Deliberately stricter than frame traits, which stay valid data when
// unfamiliar. A trait is a claim about capability that a renderer may ignore
// with no consequence; a staple kind SELECTS A DERIVATION, and a kind nothing
// honours would silently move things on screen -- or silently fail to. That is
// the same reasoning model.js's original note gave for rejecting unimplemented
// kinds, kept, with the registry now supplying the extension path it lacked.
//
//   targets     which maps this kind may staple (a series is a pattern, an
//               object is an event; see `stapleTarget`)
//   partitions  does this kind divide a series' rules into segments
//   carriesRule may this kind carry a following rule (`payload.rule`)
//   anchors     does this kind anchor a named point of an object's extent
export const STAPLE_KINDS = Object.freeze({
  end: Object.freeze({
    label: "Ends the rule here",
    targets: Object.freeze(["series"]),
    partitions: true,
    carriesRule: false,
    anchors: false
  }),
  inflection: Object.freeze({
    label: "Rule changes here",
    targets: Object.freeze(["series"]),
    partitions: true,
    carriesRule: true,
    anchors: false
  }),
  phase: Object.freeze({
    label: "Anchors the cycle's phase",
    targets: Object.freeze(["series"]),
    partitions: false,
    carriesRule: false,
    anchors: false
  }),
  anchor: Object.freeze({
    label: "Anchors a point",
    targets: Object.freeze(["series", "object"]),
    partitions: false,
    carriesRule: false,
    anchors: true
  })
});

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

// Which map a staple points into. `series` names a pattern and `object` names
// an event; exactly one is present. Two named fields rather than one
// polymorphic `target` because they are different maps with different cascade
// rules -- the same discipline validateTermination already keeps, where a
// termination's `line` names a frame and a staple's `series` names a pattern
// and "the two never interchange".
export function stapleTarget(staple) {
  if (staple?.series) return { scope: "series", id: staple.series };
  if (staple?.object) return { scope: "object", id: staple.object };
  return { scope: null, id: null };
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

/** Every staple on a series, in a stable, deterministic order. */
export function staplesForSeries(chronologDocument, patternId) {
  if (!patternId) return [];
  return allStaples(chronologDocument)
    .filter((staple) => staple.series === patternId)
    .sort(byStableOrder);
}

/** Every staple on an object (event/todo/note), in a stable, deterministic order. */
export function staplesForObject(chronologDocument, objectId) {
  if (!objectId) return [];
  return allStaples(chronologDocument)
    .filter((staple) => staple.object === objectId)
    .sort(byStableOrder);
}

/**
 * The exact instant a staple names, or null when it cannot be resolved.
 *
 * Null rather than a throw: an unresolvable staple must not take a whole
 * projection offline, and every caller here already has a correct
 * "as if this staple were absent" behavior to fall back on. That is the same
 * conservative direction series-heal.js takes -- a missed derivation leaves an
 * extra record, a wrong one destroys authored data.
 */
export function stapleDays(engine, staple) {
  if (!staple?.frame || !staple?.coordinate) return null;
  try {
    const days = engine.coordinateDays(staple.frame, staple.coordinate);
    return days ?? null;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Fuzziness (interpretation 3)
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
export function stapleSpreadDays(staple) {
  const spread = staple?.spread;
  if (!spread) return null;
  const before = durationMagnitudeDays(spread.before);
  const after = durationMagnitudeDays(spread.after);
  if (before.isZero() && after.isZero()) return null;
  return { before, after };
}

export function isFuzzyStaple(staple) {
  return stapleSpreadDays(staple) !== null;
}

const ZERO_SPREAD = Object.freeze({ before: Rational.parse(0), after: Rational.parse(0) });

function spreadOr(staple) {
  return stapleSpreadDays(staple) || ZERO_SPREAD;
}

// Uncertainties ADD. When a magnitude is derived from two fuzzy anchors the
// spread of the difference is the sum of the two spreads, never their
// difference -- two independent uncertainties do not cancel, and treating them
// as if they did would report a confident answer the data does not support.
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
// Anchoring (interpretation 1)
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

function anchorRolePrecedence(role) {
  const index = ANCHOR_ROLE_ORDER.indexOf(role);
  return index === -1 ? ANCHOR_ROLE_ORDER.length : index;
}

function anchorRole(staple) {
  const role = String(staple?.role || "").trim();
  return role || "start";
}

/**
 * Every anchor staple on an object, resolved and ordered by role precedence.
 *
 * One anchor per role wins -- the first in `byStableOrder`. A second staple of
 * the same role is not an error (the collection is open, and rejecting it would
 * lose authored data) but it cannot also be believed, so it is reported as
 * overdetermined and left alone. Which of two same-role staples wins is
 * arbitrary but never unstable; see `byStableOrder` on why that is the honest
 * guarantee rather than "whichever was authored first".
 */
export function objectAnchors(chronologDocument, engine, objectId) {
  const resolved = [];
  const overdetermined = [];
  const seenRoles = new Set();
  for (const staple of staplesForObject(chronologDocument, objectId)) {
    if (!stapleKind(staple.kind)?.anchors) continue;
    const days = stapleDays(engine, staple);
    if (days === null) continue;
    const role = anchorRole(staple);
    if (seenRoles.has(role)) {
      overdetermined.push({ role, staple, days, reason: "another staple already anchors this role" });
      continue;
    }
    seenRoles.add(role);
    resolved.push({ role, staple, days, spread: spreadOr(staple) });
  }
  resolved.sort((left, right) =>
    anchorRolePrecedence(left.role) - anchorRolePrecedence(right.role)
    || byStableOrder(left.staple, right.staple));
  return { anchors: resolved, overdetermined };
}

// A named point carries how far it sits from the object's start, so a name the
// user invented ("shift handover") still resolves to an extent. Absent, a named
// point behaves as a start anchor, which is the honest default: it says where
// the object is without claiming to know which interior point it names.
function namedOffsetDays(staple) {
  return durationMagnitudeDays(staple?.payload?.offset);
}

// The object's own placement relation, read as an implicit `start` anchor.
// This is what makes every existing document resolve identically: an event with
// no anchor staples at all is exactly today's start-plus-duration shape.
function placementRelation(chronologDocument, objectId) {
  return Object.values(chronologDocument?.relations || {}).find((relation) =>
    relation?.type === "attachment"
    && relation.event === objectId
    && relation.coordinate
    && relation.role !== "completed") || null;
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

function extentFromAnchorAndMagnitude(anchor, magnitudeDays) {
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
  const offset = namedOffsetDays(anchor.staple);
  const start = at.sub(offset);
  return { startDays: start, endDays: start.add(magnitudeDays) };
}

/**
 * Where an object actually sits, derived from its staples.
 *
 * This retires the start-time-plus-duration assumption as the ONLY shape while
 * keeping it as the shape a document with no anchor staples still gets, bit for
 * bit. Precedence, when the anchors overdetermine the extent:
 *
 *   0 anchors  the placement relation is the start; magnitude is the object's
 *              own duration. Identical to the behavior before this substrate.
 *   1 anchor   that anchor plus the object's magnitude. An `end` anchor here is
 *              the end-anchored work shift LEXICON.md asks for -- an event
 *              DEFINED by where it stops.
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
 */
export function resolveObjectExtent(chronologDocument, engine, objectId) {
  const event = chronologDocument?.events?.[objectId] || null;
  const magnitudeDays = durationMagnitudeDays(event?.magnitudes?.duration);
  const { anchors, overdetermined } = objectAnchors(chronologDocument, engine, objectId);

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
      const extent = extentFromAnchorAndMagnitude(first, magnitudeFromAnchors);
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
        spread: { start: spread, end: spread },
        frame: first.staple.frame || null
      };
    }
  }

  if (anchors.length >= 1) {
    const anchor = anchors[0];
    const extent = extentFromAnchorAndMagnitude(anchor, magnitudeDays);
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
      spread: { start: anchor.spread, end: anchor.spread },
      frame: anchor.staple.frame || null
    };
  }

  const placement = placementRelation(chronologDocument, objectId);
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
    spread: { start: ZERO_SPREAD, end: ZERO_SPREAD },
    frame: placement.frame || null
  };
}

// ---------------------------------------------------------------------------
// Series partitioning (interpretation 2)
// ---------------------------------------------------------------------------

// LEXICON.md, the Rob-and-John scenario: "a series is an identity whose rules
// are segments partitioned by staples ... a staple at an inflection point ends
// the reigning rule, and a new rule may follow on the same series or a new
// series may begin, on preference."
//
// BOUNDARY CONVENTION, and it is load-bearing: a partitioning staple CLOSES the
// reigning segment inclusively and OPENS the following one exclusively. The
// inclusive close is the shipped end-staple's own behavior ("the staple's own
// occurrence survives; nothing after it projects"), and once close is
// inclusive, exclusive open is the only choice that does not project the staple
// instant twice.

/**
 * A series' rule segments, in chronological order.
 *
 * One staple with no following rule yields exactly two entries' worth of
 * meaning -- a bounded segment 0 and nothing after it -- which is why the
 * shipped end-staple keeps working through this without a special case.
 */
export function seriesSegments(engine, pattern) {
  const chronologDocument = engine?.document;
  const templateRelation = chronologDocument?.relations?.[pattern?.templateRelation] || null;
  const partitioning = staplesForSeries(chronologDocument, pattern?.id)
    .filter((staple) => stapleKind(staple.kind)?.partitions)
    .map((staple) => ({ staple, days: stapleDays(engine, staple) }))
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
    // case, and the one the whole shipped end-staple consists of.
    if (!head) return segments;
    reigning = {
      fromDays: entry.days,
      rrule: head.rrule || {},
      baseCoordinate: head.coordinate || entry.staple.coordinate || null,
      frame: head.frame || entry.staple.frame || reigning.frame,
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
// Occurrence phase (interpretation 4)
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
  const staples = staplesForSeries(engine?.document, pattern?.id)
    .filter((staple) => staple.kind === "phase");
  for (const staple of staples) {
    const days = stapleDays(engine, staple);
    if (days !== null) return days;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Exclusions as live references (interpretation 5)
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
      const duration = durationMagnitudeDays(entry.fact?.event?.magnitudes?.duration);
      const first = start.floor();
      // An all-day event stored as a 1-day duration covers exactly its own
      // day, so the last covered day is derived from the final instant strictly
      // inside the span rather than from the exclusive end.
      const endInstant = start.add(duration);
      const last = duration.isZero() ? first : endInstant.sub(Rational.parse(1).div(86400)).floor();
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
