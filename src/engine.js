import { FormulaRuntime } from "./formula.js";
import {
  Rational,
  civilFromDays,
  daysFromCivil,
  daysInMonth,
  floorDiv,
  floorMod
} from "./exact.js";
import { GREGORIAN_LAW, coordinateDaysOrNull, coordinateLaw, coordinateValueError, lawForCalendar } from "./coordinate-law.js";
import { coordinateEntryDepth } from "./coordinate-entry.js";
import {
  applyVirtualOverrides,
  coordinateToDays,
  daysToCoordinate,
  durationMagnitude,
  durationMagnitudeDays,
  stableVirtualId,
  validateDocument
} from "./model.js";
import {
  isLiveExcluded,
  liveExclusionDays,
  resolveObjectExtent,
  seriesIsSegmented,
  seriesPhaseDays,
  seriesSegments,
  frameEndOf,
  isPlacement,
  stapleEnds
} from "./staples.js";

function rational(value) {
  return Rational.parse(value);
}

function within(value, start, end) {
  const point = rational(value);
  return point.compare(start) >= 0 && point.compare(end) <= 0;
}

// D3 (field report): a record whose coordinate cannot resolve under its
// frame's law -- an unknown transition, a coordinate naming levels the law
// does not declare, a non-countable era frame with no metric ladder at all
// -- must drop only THIS record, never abort the whole query. Returns the
// resolved day, or null plus the reason in the author's own words so the
// caller can report it instead of silently dropping the record.
//
// `coordinateDaysOrNull` is the shared refusal seam for a declarative law
// (src/coordinate-law.js); `coordinateValueError` runs the identical
// resolution and hands back why, asked only once resolution has already
// failed, so the common (successful) path never pays for it. A frame
// governed by a compiled coordinate-law PATTERN (`frame.law.pattern`, a
// FormulaRuntime program -- see `ChronologEngine#coordinateDays`'s own other
// branch) is a different resolution path entirely and is asked directly,
// still guarded the same way, so a broken formula law is refused instead of
// aborting the query too.
function attachmentDay(engine, relation) {
  if (!relation.coordinate) return { day: null, reason: null };
  const frame = engine.document.frames[relation.frame];
  if (frame?.law?.pattern && frame.law.toDays) {
    try {
      return { day: engine.coordinateDays(relation.frame, relation.coordinate), reason: null };
    } catch (error) {
      return { day: null, reason: error.message };
    }
  }
  const day = coordinateDaysOrNull(engine.document, relation.frame, relation.coordinate);
  if (day) return { day, reason: null };
  return {
    day: null,
    reason: coordinateValueError(engine.document, relation.frame, relation.coordinate)
      || `Frame ${relation.frame} could not resolve this coordinate.`
  };
}

// This block through `ruleOccurrenceDays`'s BYMONTH/BYMONTHDAY/BYDAY handling
// is RFC 5545 recurrence evaluation over the GREGORIAN calendar specifically --
// the wire format's own calendar, not the document's coordinate law. `weekday`,
// `WEEKDAYS`, `daysInMonth`, and the month/day candidate machinery all assume a
// standard civil year, exactly as RFC 5545 defines FREQ/BYDAY/BYMONTHDAY.
// Melting this onto an arbitrary law is a separate roadmap item (pattern
// authoring beyond RRULE); an RSCALE naming a calendar this build has not
// registered is refused rather than silently evaluated as Gregorian --
// see `unsupportedCalendarScale` below, which is the actual guard.
const WEEKDAYS = { SU: 0n, MO: 1n, TU: 2n, WE: 3n, TH: 4n, FR: 5n, SA: 6n };
const MAX_CACHED_RECURRENCE_COUNT = 256;
const MAX_RRULE_COUNT = 10_000n;
const MAX_RECURRENCE_SERIES_FACTS = 12_000;
const MAX_RECURRENCE_WINDOWS = 256;
const MAX_RECURRENCE_WINDOW_FACTS = 16_000;

function weekday(day) {
  return floorMod(BigInt(day) + 4n, 7n);
}

// RFC 5545's own compact timestamp format (`YYYYMMDDTHHMMSSZ`): /24, /1440,
// /86400 are the WIRE FORMAT's units (a compact ICS timestamp's hour is always
// a standard hour), not this document's coordinate law -- melting them onto a
// document law would misread every UNTIL/RECURRENCE-ID this parses.
function compactIcsDay(value) {
  const match = /^([+-]?\d{4,})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})Z?)?$/.exec(value || "");
  if (!match) return null;
  const base = new Rational(daysFromCivil(BigInt(match[1]), BigInt(match[2]), BigInt(match[3])));
  if (!match[4]) return base;
  return base
    .add(Rational.parse(match[4]).div(24))
    .add(Rational.parse(match[5]).div(1440))
    .add(Rational.parse(match[6]).div(86400));
}

function compareBigInt(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

function parseByDay(value) {
  return String(value || "").split(",").map((token) => {
    const match = /^([+-]?\d+)?(SU|MO|TU|WE|TH|FR|SA)$/.exec(token.trim().toUpperCase());
    if (!match) return null;
    return { ordinal: match[1] ? Number(match[1]) : null, weekday: WEEKDAYS[match[2]] };
  }).filter(Boolean);
}

function monthDayCandidates(rule, year, month, baseDay) {
  const length = BigInt(daysInMonth(year, month));
  const byDay = rule.BYDAY ? parseByDay(rule.BYDAY) : [];
  let candidates;
  if (rule.BYMONTHDAY) {
    candidates = rule.BYMONTHDAY.split(",").map((value) => {
      const monthDay = BigInt(value);
      return monthDay < 0n ? length + monthDay + 1n : monthDay;
    }).filter((monthDay) => monthDay >= 1n && monthDay <= length);
    if (byDay.length) {
      const weekdays = byDay.map((item) => item.weekday);
      candidates = candidates.filter((monthDay) =>
        weekdays.includes(weekday(daysFromCivil(year, month, monthDay))));
    }
  } else if (byDay.length) {
    candidates = [];
    for (const item of byDay) {
      const matching = [];
      for (let monthDay = 1n; monthDay <= length; monthDay += 1n) {
        if (weekday(daysFromCivil(year, month, monthDay)) === item.weekday) matching.push(monthDay);
      }
      if (item.ordinal === null) candidates.push(...matching);
      else {
        const pick = item.ordinal > 0
          ? matching[item.ordinal - 1]
          : matching[matching.length + item.ordinal];
        if (pick !== undefined) candidates.push(pick);
      }
    }
  } else {
    candidates = [baseDay].filter((monthDay) => monthDay >= 1n && monthDay <= length);
  }
  return [...new Set(candidates)].sort(compareBigInt);
}

// This series' rule change segment 0 is cut off at: the earlier of the rule's
// own written extent (UNTIL) and whatever partitioning staple ends segment 0
// (an "end" staple, or an "inflection" staple that hands off to a following
// rule -- both partition, per src/staples.js's STAPLE_KINDS). Segment 0 IS
// the pattern's own rrule, so this is exactly `segmentEffectiveUntilDays`
// applied to `seriesSegments(...)[0]` -- kept as a named export because
// `src/ics.js` reuses it to reflect the staple in an exported RRULE's UNTIL
// at serialization time without the staple ever being written into the rule.
// Comparison is exact Rational days throughout (`compactIcsDay`,
// `coordinateDays`), never string equality -- ICS writes month "01" where the
// generator writes "1".
export function seriesEffectiveUntilDays(engine, pattern) {
  return segmentEffectiveUntilDays(seriesSegments(engine, pattern)[0]);
}

// The earlier of a segment's own written RRULE UNTIL and the staple that
// closes it (`segment.untilDays`, from src/staples.js's seriesSegments --
// null for the series' final segment, which runs to whatever the caller's
// query bounds are). One derivation shared by every segment, segment 0
// included, which is what lets `seriesEffectiveUntilDays` above be a one-line
// call rather than a second copy of this comparison.
function segmentEffectiveUntilDays(segment) {
  const ruleUntil = compactIcsDay(segment?.rrule?.UNTIL);
  const stapleUntil = segment?.untilDays ?? null;
  if (!stapleUntil) return ruleUntil;
  if (!ruleUntil) return stapleUntil;
  return ruleUntil.compare(stapleUntil) <= 0 ? ruleUntil : stapleUntil;
}

// One rule segment's own occurrence days within [lower, upper] -- the exact
// generation math a single, un-segmented series has always used, now taking
// its rule/base/bounds as parameters instead of reading them off `pattern`
// directly. `occurrenceFacts` below calls this once per segment
// (src/staples.js's seriesSegments) and concatenates.
//
// COUNT is counted from `base` and is therefore scoped to THIS segment alone
// -- a segment is that rule's whole life, so counting emitted occurrences
// across a rule change (into a segment whose rule may have a different FREQ
// entirely) would count against a rule that no longer applies. `until` is
// this segment's own effective stop (`segmentEffectiveUntilDays`): the
// earlier of the rule's own written UNTIL and the staple that closes it.
function ruleOccurrenceDays(rule, base, lower, upper, until, excluded, limit) {
  const baseWhole = base.floor();
  const time = base.sub(baseWhole);
  const frequency = String(rule.FREQ || "").toUpperCase();
  const interval = BigInt(rule.INTERVAL || 1);
  if (interval <= 0n) throw new RangeError(`RRULE INTERVAL must be positive, got ${rule.INTERVAL}`);
  const count = rule.COUNT ? BigInt(rule.COUNT) : null;
  if (count !== null && count > MAX_RRULE_COUNT) {
    throw new RangeError(`RRULE COUNT exceeds the safe limit of ${MAX_RRULE_COUNT}`);
  }
  const days = [];
  let counted = 0n;

  // Candidates arrive in chronological order; emit counts every occurrence at or
  // after the base so COUNT reflects emitted occurrences, not generator cycles.
  const emit = (day) => {
    if (day.compare(base) < 0) return true;
    if (until && day.compare(until) > 0) return false;
    if (count !== null && counted >= count) return false;
    counted += 1n;
    if (day.compare(upper) > 0) return false;
    if (day.compare(lower) >= 0 && !excluded.has(day.toJSON())) {
      days.push(day);
      if (days.length >= limit) return false;
    }
    return true;
  };

  if (frequency === "DAILY") {
    let index = 0n;
    if (count === null) {
      const skip = lower.sub(base).div(interval).ceil();
      if (skip > 0n) index = skip;
    }
    for (;; index += 1n) {
      if (!emit(base.add(index * interval))) break;
    }
  } else if (frequency === "WEEKLY") {
    const baseWeek = baseWhole - floorMod(weekday(baseWhole) - WEEKDAYS.MO, 7n);
    const selected = parseByDay(rule.BYDAY).map((item) => item.weekday);
    if (!selected.length) selected.push(weekday(baseWhole));
    let cycle = 0n;
    if (count === null) {
      const lowerWhole = lower.floor();
      const lowerWeek = lowerWhole - floorMod(weekday(lowerWhole) - WEEKDAYS.MO, 7n);
      cycle = floorDiv(lowerWeek - baseWeek, 7n * interval);
      if (cycle < 0n) cycle = 0n;
    }
    weekly: for (;; cycle += 1n) {
      const weekStart = baseWeek + cycle * interval * 7n;
      for (let offset = 0n; offset < 7n; offset += 1n) {
        if (!selected.includes(weekday(weekStart + offset))) continue;
        if (!emit(new Rational(weekStart + offset).add(time))) break weekly;
      }
    }
  } else if (frequency === "MONTHLY") {
    const baseCivil = civilFromDays(baseWhole);
    const baseMonth = baseCivil.year * 12n + baseCivil.month - 1n;
    let cycle = 0n;
    if (count === null) {
      const lowerCivil = civilFromDays(lower.floor());
      cycle = floorDiv(lowerCivil.year * 12n + lowerCivil.month - 1n - baseMonth, interval);
      if (cycle < 0n) cycle = 0n;
    }
    monthly: for (;; cycle += 1n) {
      const monthIndex = baseMonth + cycle * interval;
      const year = floorDiv(monthIndex, 12n);
      const month = floorMod(monthIndex, 12n) + 1n;
      if (new Rational(daysFromCivil(year, month, 1n)).add(time).compare(upper) > 0) break;
      for (const monthDay of monthDayCandidates(rule, year, month, baseCivil.day)) {
        if (!emit(new Rational(daysFromCivil(year, month, monthDay)).add(time))) break monthly;
      }
    }
  } else if (frequency === "YEARLY") {
    const baseCivil = civilFromDays(baseWhole);
    let cycle = 0n;
    if (count === null) {
      const lowerCivil = civilFromDays(lower.floor());
      cycle = floorDiv(lowerCivil.year - baseCivil.year, interval);
      if (cycle < 0n) cycle = 0n;
    }
    const months = rule.BYMONTH
      ? [...new Set(rule.BYMONTH.split(",").map((value) => BigInt(value)))]
        .filter((month) => month >= 1n && month <= 12n)
        .sort(compareBigInt)
      : [baseCivil.month];
    yearly: for (;; cycle += 1n) {
      const year = baseCivil.year + cycle * interval;
      if (new Rational(daysFromCivil(year, 1n, 1n)).add(time).compare(upper) > 0) break;
      for (const month of months) {
        for (const monthDay of monthDayCandidates(rule, year, month, baseCivil.day)) {
          if (!emit(new Rational(daysFromCivil(year, month, monthDay)).add(time))) break yearly;
        }
      }
    }
  } else {
    throw new Error(`Unsupported FREQ in RRULE: ${rule.FREQ || "(missing)"}`);
  }

  return days;
}

// RFC 7529: RSCALE names the calendar a rule counts in. A rule naming a
// calendar this build has not registered (`lawForCalendar` returns null) must
// never be projected as though it counted in Gregorian -- refused honestly
// instead, with the calendar named in the message. This is the one choke
// point every segment's own rule passes through (segment 0's `pattern.rrule`
// and every following segment's own rule alike), so it throws rather than
// guesses; `queryFacts`'s existing per-pattern try/catch is what turns that
// throw into an author-facing entry in `errors` instead of a crashed render.
function unsupportedCalendarScale(rrule) {
  const requested = rrule?.RSCALE;
  if (!requested) return null;
  return lawForCalendar(requested)
    ? null
    : `RRULE names a calendar this build does not implement (RSCALE=${requested}); the rule is kept but cannot be projected.`;
}

// A series projects per segment (LEXICON.md's Rob-and-John scenario: "a series
// is an identity whose rules are segments partitioned by staples"). Every
// segment's occurrences are generated by the same `ruleOccurrenceDays` a
// single un-segmented series always used, clipped to that segment's own life,
// and concatenated -- but EVERY fact from EVERY segment keeps the SAME
// pattern provenance (`provenance.kind: "pattern", pattern: pattern.id`).
// That is the whole point of the ruling: a rule change is not a new identity.
//
// Virtual ids stay `stableVirtualId(pattern.id, "occurrence-<day>")`, exactly
// as an un-segmented series has always keyed them (so existing overrides and
// materializations keep resolving after this change). Two segments can never
// collide on a day: the boundary convention (src/staples.js) closes a segment
// INCLUSIVELY at its own `untilDays` and the next segment is filtered to
// STRICTLY AFTER that same instant below, so consecutive segments' day-ranges
// are disjoint by construction, and that disjointness composes across any
// number of segments because the partitioning staples are chronologically
// ordered. The Rob-and-John acceptance test asserts this directly (no
// duplicate virtual ids across the Monday/Thursday segments).
function occurrenceFacts(engine, pattern, lower, upper, limit = Infinity) {
  const document = engine.document;
  const templateRelation = document.relations[pattern.templateRelation];
  const templateEvent = document.events[pattern.templateEvent];
  if (!templateRelation || !templateEvent?.id) return [];

  // A phase staple (LEXICON.md: "stapling an arbitrary occurrence anchors the
  // cycle's phase") replaces every segment's own base instant for cycle
  // counting, without rewriting any segment's template -- removing it
  // restores each segment's original phase for free. It is a property of the
  // series as a whole, not of one segment, so it is resolved once here.
  const phaseDays = seriesPhaseDays(engine, pattern);
  const segments = seriesSegments(engine, pattern);
  const facts = [];

  for (const segment of segments) {
    if (facts.length >= limit) break;
    if (!segment.baseCoordinate) continue;
    const scaleError = unsupportedCalendarScale(segment.rrule);
    if (scaleError) throw new Error(scaleError);
    const frame = segment.frame || templateRelation.frame;
    let templateBase;
    try {
      templateBase = engine.coordinateDays(frame, segment.baseCoordinate);
    } catch {
      continue;
    }
    const base = phaseDays !== null ? phaseDays : templateBase;
    const until = segmentEffectiveUntilDays(segment);

    // BOUNDARY CONVENTION (src/staples.js, load-bearing): a partitioning
    // staple closes its segment INCLUSIVELY (folded into `until` above) and
    // opens the next one EXCLUSIVELY. The exclusive open is enforced as a
    // post-filter below rather than folded into the generator's own lower
    // bound, so `ruleOccurrenceDays`'s skip-ahead optimizations stay exactly
    // what they were for an un-segmented series; `segmentLower` only narrows
    // the bound passed in for efficiency; it is not what makes the boundary
    // exclusive.
    const segmentLower = segment.fromDays !== null && segment.fromDays.compare(lower) > 0
      ? segment.fromDays
      : lower;
    const segmentUpper = until !== null && until.compare(upper) < 0 ? until : upper;
    if (segmentLower.compare(segmentUpper) > 0) continue;

    const excluded = new Set(segment.exdates || []);
    const remaining = limit === Infinity ? Infinity : limit - facts.length;
    let days = ruleOccurrenceDays(segment.rrule || {}, base, segmentLower, segmentUpper, until, excluded, remaining);
    if (segment.fromDays !== null) {
      days = days.filter((day) => day.compare(segment.fromDays) > 0);
    }

    // Live exclusions (LEXICON.md's Rob-and-John beat 2): "skip holidays
    // (events on frame xyz)" is a reference to another frame's events,
    // resolved at projection time, resolved ONCE per query rather than once
    // per occurrence -- adding a holiday to the referenced calendar changes
    // this series with no edit to the series itself.
    if (segment.exclude) {
      const excludedDays = liveExclusionDays(engine, segment.exclude, segmentLower, segmentUpper);
      if (excludedDays) days = days.filter((day) => !isLiveExcluded(excludedDays, day));
    }

    for (const day of days) {
      const virtualId = stableVirtualId(pattern.id, `occurrence-${day.toJSON()}`);
      // A following rule's `magnitude` (LEXICON.md's Rob-and-John scenario:
      // "a different weekday AND a different time of day AND a different
      // duration") overrides the template event's own duration for this
      // segment's occurrences; absent, the template's own duration applies
      // exactly as it always has.
      const magnitudes = segment.magnitude
        ? { ...templateEvent.magnitudes, duration: segment.magnitude }
        : templateEvent.magnitudes;
      const virtualEvent = {
        ...templateEvent,
        id: virtualId,
        magnitudes,
        provenance: { kind: "pattern", pattern: pattern.id, key: day.toJSON() }
      };
      const virtualRelation = {
        ...templateRelation,
        id: `${virtualId}/attachment`,
        event: virtualId,
        frame,
        coordinate: engine.daysCoordinate(frame, day),
        provenance: { kind: "pattern", pattern: pattern.id, key: day.toJSON() }
      };
      facts.push({
        kind: "virtual",
        virtualId,
        event: virtualEvent,
        relation: virtualRelation,
        day: day.toJSON(),
        coordinate: virtualRelation.coordinate
      });
      if (facts.length >= limit) break;
    }
  }

  return facts;
}

// A cheap fingerprint of every staple relation in the document, used only to
// decide whether `setDocument`'s `preserveRecurrence` request is actually
// safe -- see the comment on `setDocument` below for the trap this closes.
// Every field a staple's own derivations read participates -- its kind, its
// spread, its following-rule payload, and both of its ends including each end's
// point, coordinate and offset -- so a connection moving, changing kind, or
// being re-pointed at a different object all change the signature; unrelated
// relations (any non-staple) never do, which is what keeps this cheap on a
// document whose edit had nothing to do with staples at all.
function stapleSignature(document) {
  const staples = Object.values(document?.relations || {})
    .filter((relation) => relation?.type === "staple")
    .map((relation) => JSON.stringify(relation))
    .sort();
  return staples.join(" ");
}

export class ChronologEngine {
  constructor(document, options = {}) {
    this.runtime = options.runtime || new FormulaRuntime(options.formula);
    this.compiledPatterns = new Map();
    this.setDocument(document);
  }

  // CACHE INVALIDATION TRAP, closed here rather than per-caller: a staple
  // edit changes what a pattern projects (a new end/inflection moves where a
  // segment stops, a phase staple moves what a cycle counts from, an
  // exclusion's referenced frame can change what a live reference drops), so
  // `recurrenceSeries`/`recurrenceWindows` must never survive a staple change
  // -- regardless of what `options.preserveRecurrence` claims. That flag is
  // authored per call site by `src/ui/transactions.js` keyed on WHICH MAP a
  // record lives in (`executeRecordChange`'s `mapName !== "patterns"`
  // default), and a staple is a `relations` record -- the same map plain
  // attachments and group memberships live in, which really can be edited
  // with the recurrence cache safely preserved. A caller cannot tell those
  // apart from the map name alone, so trusting the flag unconditionally would
  // make "preserve" a per-kind special case that is only right until the next
  // relations-map edit path happens to touch a staple. The general rule
  // instead: compare the document's own staple relations before and after,
  // independent of anything the caller believes it preserved, and only honor
  // `preserveRecurrence` when staples provably did not change.
  setDocument(document, options = {}) {
    const requestedPreserve = options.preserveRecurrence === true && this.document === document;
    const currentStapleSignature = stapleSignature(document);
    const staplesChanged = this.stapleSignature !== undefined && this.stapleSignature !== currentStapleSignature;
    const preserveRecurrence = requestedPreserve && !staplesChanged;
    this.stapleSignature = currentStapleSignature;
    this.document = document;
    this.compiledPatterns.clear();
    this.patternsForEveryFrame = [];
    this.patternsByFrame = new Map();
    this.relationsByFrame = new Map();
    this.groupFrameByEvent = new Map();
    this.groupMembershipsByMember = new Map();
    this.groupMembersByGroup = new Map();
    // Display-only counterparts of the three maps above -- see `isDisplayGroup`.
    this.displayGroupFrameByEvent = new Map();
    this.displayGroupMembershipsByMember = new Map();
    this.displayGroupMembersByGroup = new Map();
    this.framesByEvent = new Map();
    this.calendarFrameByEvent = new Map();
    this.explicitFactsByFrame = new Map();
    this.explicitMaxDurationByFrame = new Map();
    this.explicitErrorsByFrame = new Map();
    if (!preserveRecurrence) {
      this.recurrenceSeries = new Map();
      this.recurrenceSeriesFacts = 0;
      this.recurrenceWindows = new Map();
      this.recurrenceWindowFacts = 0;
    }

    for (const pattern of Object.values(document.patterns)) {
      if (!pattern.appliesTo?.length) {
        this.patternsForEveryFrame.push(pattern);
        continue;
      }
      for (const frameId of pattern.appliesTo) {
        const patterns = this.patternsByFrame.get(frameId) || [];
        patterns.push(pattern);
        this.patternsByFrame.set(frameId, patterns);
      }
    }

    // Overscale doctrine: `resolveObjectExtent` runs once per event during fact
    // indexing and follows connection chains through other objects, so "every
    // staple touching this id" has to be O(1). Both ends are indexed, because a
    // connection is reachable from either thing it joins.
    // The object's implicit placement staple, indexed for the same reason its
    // explicit ones are: extent resolution asks for it once per object and again
    // at every step of a connection chain.
    // Every object with ANY attachment is recorded, mapping to its placement
    // relation or to null -- "seen, and it has none" has to be a hit, or an
    // object placed purely by a connection (a coordinate-less membership) would
    // miss and pay a document-wide scan on every lookup.
    this.placementByEvent = new Map();
    for (const relation of Object.values(document.relations)) {
      if (relation.type !== "attachment") continue;
      const current = this.placementByEvent.get(relation.event) || null;
      if (!current) this.placementByEvent.set(relation.event, isPlacement(relation) ? relation : null);
    }
    this.staplesByObject = new Map();
    this.staplesBySeries = new Map();
    this.staplesByFrame = new Map();
    for (const relation of Object.values(document.relations)) {
      if (relation.type !== "staple") continue;
      for (const end of stapleEnds(relation)) {
        const index = end.object ? this.staplesByObject
          : end.series ? this.staplesBySeries
            : end.frame ? this.staplesByFrame : null;
        if (!index) continue;
        const id = end.object || end.series || end.frame;
        const bucket = index.get(id) || [];
        if (!bucket.includes(relation)) bucket.push(relation);
        index.set(id, bucket);
      }
    }
    // The same total, deterministic order src/staples.js tie-breaks on, applied
    // once here rather than per lookup.
    for (const index of [this.staplesByObject, this.staplesBySeries, this.staplesByFrame]) {
      for (const bucket of index.values()) {
        bucket.sort((left, right) => String(left.id).localeCompare(String(right.id)));
      }
    }

    for (const relation of Object.values(document.relations)) {
      if (relation.type === "membership") continue;
      if (relation.type !== "attachment") continue;
      const relations = this.relationsByFrame.get(relation.frame) || [];
      relations.push(relation);
      this.relationsByFrame.set(relation.frame, relations);
      const eventFrames = this.framesByEvent.get(relation.event) || new Set();
      eventFrames.add(relation.frame);
      this.framesByEvent.set(relation.event, eventFrames);
      if (document.frames[relation.frame]?.traits.includes("calendar")
        && !this.calendarFrameByEvent.has(relation.event)) {
        this.calendarFrameByEvent.set(relation.event, relation.frame);
      }
    }
    this.rebuildGroupMemberships();
  }

  // Which frame's law should read a query window's own coordinates. Normally the
  // queried frame itself; null for a group frame that owns no coordinate space,
  // meaning "use the registered standard boundary". A group WITH a basis or its
  // own ladder is a coordinate space like any other and keeps reading its own.
  windowFrameFor(frameId) {
    if (!this.isOrdinaryGroup(frameId)) return frameId;
    try {
      return coordinateLaw(this.document, frameId).positional ? frameId : null;
    } catch {
      return null;
    }
  }

  isOrdinaryGroup(frameId) {
    const frame = this.document.frames[frameId];
    return Boolean(frame?.traits?.includes("group") && !frame.traits?.includes("importance"));
  }

  // The display-side union of ordinary groups and importance frames. Persisted
  // authoring, validation, and `isOrdinaryGroup` itself never consult this --
  // an importance frame's own base traits already include "group" (see
  // `frame-edit.js`'s TRAITS_BY_KIND, additive under kind-switching), so an
  // importance frame is authored exactly like a group: same attachment/
  // membership relation shape, same query shape. What was missing was display
  // bookkeeping willing to look at it that way. This predicate exists so the
  // color cascade, sigil selection, minimap weighting, and per-lens group
  // presence can treat "group" and "importance frame" as one membership pool
  // for rendering, without changing what "group" means anywhere the document
  // itself is read or written.
  isDisplayGroup(frameId) {
    const frame = this.document.frames[frameId];
    return Boolean(frame?.traits?.includes("group") || frame?.traits?.includes("importance"));
  }

  queryGroupMembers(group, isGroup = (frameId) => this.isOrdinaryGroup(frameId)) {
    const query = group.query;
    if (!query || typeof query !== "object") return [];
    if (query.excludeGroups?.length || query.notGroups?.length) return [];
    const all = { ...this.document.events, ...this.document.frames };
    const ids = Array.isArray(query.ids) ? new Set(query.ids) : null;
    const traitsAll = Array.isArray(query.traitsAll) ? query.traitsAll : [];
    const traitsAny = Array.isArray(query.traitsAny) ? query.traitsAny : [];
    const groups = Array.isArray(query.groups) ? query.groups : [];
    const matches = [];
    for (const [id, member] of Object.entries(all)) {
      const traits = member.traits || [];
      if (ids && !ids.has(id)) continue;
      if (traitsAll.some((trait) => !traits.includes(trait))) continue;
      if (traitsAny.length && !traitsAny.some((trait) => traits.includes(trait))) continue;
      matches.push({ member: id, provenance: { kind: "query", group: group.id, query: "selector" } });
    }
    for (const nested of groups) {
      if (isGroup(nested)) {
        matches.push({ member: nested, provenance: { kind: "query", group: group.id, query: "group" } });
      }
    }
    return matches;
  }

  // Builds one membership index (members-by-group, memberships-by-member, and
  // the single-frame-per-event shortcut) against whichever "is this a group"
  // predicate is passed in. `rebuildGroupMemberships` runs this twice: once
  // for `isOrdinaryGroup` (the persisted-facing index nothing here changes)
  // and once for `isDisplayGroup` (the union display consumers read).
  buildGroupIndex(isGroup) {
    const groups = Object.values(this.document.frames).filter((frame) => isGroup(frame.id));
    const members = new Map(groups.map((group) => [group.id, new Map()]));
    const add = (groupId, memberId, provenance, mergeProvenance = true) => {
      const inGroup = members.get(groupId);
      if (!inGroup) return false;
      const existing = inGroup.get(memberId) || [];
      // Membership itself is a set.  We retain independently authored/query
      // reasons for a direct member, but do not manufacture infinitely many
      // cyclic path explanations for an already-known inherited member.
      if (existing.length && !mergeProvenance) return false;
      const key = JSON.stringify(provenance);
      if (existing.some((item) => JSON.stringify(item) === key)) return false;
      inGroup.set(memberId, [...existing, provenance]);
      return true;
    };
    // Legacy group attachments are authored edges. New membership relations
    // additionally admit frames, including groups, without inventing a new root type.
    for (const relation of Object.values(this.document.relations)) {
      if (relation.type === "attachment" && isGroup(relation.frame)) {
        add(relation.frame, relation.event, { kind: "authored", relation: relation.id });
      }
      if (relation.type === "membership" && isGroup(relation.group) && relation.include !== false && relation.mode !== "exclude") {
        add(relation.group, relation.member, { kind: "authored", relation: relation.id });
      }
    }
    for (const group of groups) {
      for (const match of this.queryGroupMembers(group, isGroup)) add(group.id, match.member, match.provenance);
    }
    // A snapshot of ONE authored hop -- taken before the fixed point below
    // flattens nested groups into `members` -- for `groupUnionFacts` (a group
    // frame's query unions its members) to recurse over itself, one frame at a
    // time with its own cycle guard. Consuming the ALREADY-flattened `members`
    // instead would make every nested member reachable through more than one
    // ancestor get its own facts recomputed once per path that reaches it;
    // this keeps the recursion at exactly one visit per direct edge. `add`
    // never mutates an existing provenance array in place (it always writes a
    // new one), so mutating `members` afterward cannot reach back into this
    // copy.
    const directMembers = new Map([...members].map(([groupId, inGroup]) => [groupId, new Map(inGroup)]));
    // Positive nesting is monotonic, so repeatedly adding inherited members reaches
    // the finite graph's least fixed point. A self-edge therefore becomes a no-op.
    let changed = true;
    while (changed) {
      changed = false;
      for (const group of groups) {
        for (const [memberId, provenance] of [...members.get(group.id)]) {
          if (!isGroup(memberId)) continue;
          for (const [nestedMember, nestedProvenance] of members.get(memberId) || []) {
            for (const source of nestedProvenance) {
              if (add(group.id, nestedMember, {
                kind: "nested", group: group.id, via: memberId, source
              }, false)) changed = true;
            }
          }
        }
      }
    }
    const membershipsByMember = new Map();
    for (const [groupId, inGroup] of members) {
      for (const [memberId, provenance] of inGroup) {
        const memberships = membershipsByMember.get(memberId) || new Map();
        memberships.set(groupId, provenance);
        membershipsByMember.set(memberId, memberships);
      }
    }
    const frameByEvent = new Map();
    for (const [eventId, memberships] of membershipsByMember) {
      if (!this.document.events[eventId]) continue;
      const first = [...memberships.keys()].sort()[0];
      if (first) frameByEvent.set(eventId, first);
    }
    return { membersByGroup: members, membershipsByMember, frameByEvent, directMembersByGroup: directMembers };
  }

  rebuildGroupMemberships() {
    const persisted = this.buildGroupIndex((frameId) => this.isOrdinaryGroup(frameId));
    this.groupMembersByGroup = persisted.membersByGroup;
    this.groupMembershipsByMember = persisted.membershipsByMember;
    this.groupFrameByEvent = persisted.frameByEvent;
    // Query-facing only: a group frame's query unions this (see
    // `groupUnionFacts`), never anything importance-only, so it is built from
    // the SAME `isOrdinaryGroup` index the persisted membership above uses,
    // not the display union below.
    this.groupDirectMembersByGroup = persisted.directMembersByGroup;

    const display = this.buildGroupIndex((frameId) => this.isDisplayGroup(frameId));
    this.displayGroupMembersByGroup = display.membersByGroup;
    this.displayGroupMembershipsByMember = display.membershipsByMember;
    this.displayGroupFrameByEvent = display.frameByEvent;
  }

  validate() {
    return validateDocument(this.document);
  }

  patternModule(pattern) {
    const cached = this.compiledPatterns.get(pattern.id);
    if (cached?.source === pattern.source) return cached.module;
    const module = this.runtime.compile(pattern.source);
    this.compiledPatterns.set(pattern.id, { source: pattern.source, module });
    return module;
  }

  matchingPatterns(frameId) {
    return [...this.patternsForEveryFrame, ...(this.patternsByFrame.get(frameId) || [])]
      .filter((pattern) => pattern.enabled !== false);
  }

  eventGroupFrame(eventId) {
    return this.groupFrameByEvent.get(eventId) || null;
  }

  eventGroupMemberships(eventId) {
    return [...(this.groupMembershipsByMember.get(eventId) || new Map())]
      .map(([group, provenance]) => ({ group, provenance }));
  }

  groupMembers(groupId) {
    return [...(this.groupMembersByGroup.get(groupId) || new Map())]
      .map(([member, provenance]) => ({ member, provenance }));
  }

  // One authored hop only -- not the transitively-flattened membership
  // `groupMembers` returns. `groupUnionFacts` is the one caller: it does its
  // own recursion (with its own cycle guard) over this edge, so it must see a
  // group's nested member frames exactly once, not once per already-flattened
  // appearance.
  groupDirectMembers(groupId) {
    return [...(this.groupDirectMembersByGroup?.get(groupId) || new Map())]
      .map(([member, provenance]) => ({ member, provenance }));
  }

  // Display-facing counterparts: same shape, but the membership pool is
  // `isDisplayGroup` (ordinary groups union importance frames) instead of
  // `isOrdinaryGroup` alone. The color cascade, sigil selection, minimap
  // weighting, and per-lens group presence read these; nothing that authors
  // or validates the document does.
  eventDisplayGroupFrame(eventId) {
    return this.displayGroupFrameByEvent.get(eventId) || null;
  }

  eventDisplayGroupMemberships(eventId) {
    return [...(this.displayGroupMembershipsByMember.get(eventId) || new Map())]
      .map(([group, provenance]) => ({ group, provenance }));
  }

  displayGroupMembers(groupId) {
    return [...(this.displayGroupMembersByGroup.get(groupId) || new Map())]
      .map(([member, provenance]) => ({ member, provenance }));
  }

  eventCalendarFrame(eventId) {
    return this.calendarFrameByEvent.get(eventId) || null;
  }

  eventCalendarFrames(eventId) {
    return this.eventFrames(eventId).filter((frameId) => this.document.frames[frameId]?.traits.includes("calendar"));
  }

  groupEventMembers(groupId) {
    return this.groupMembers(groupId)
      .map(({ member }) => member)
      .filter((member) => Boolean(this.document.events[member]));
  }

  displayGroupEventMembers(groupId) {
    return this.displayGroupMembers(groupId)
      .map(({ member }) => member)
      .filter((member) => Boolean(this.document.events[member]));
  }

  eventFrames(eventId) {
    return [...(this.framesByEvent.get(eventId) || [])];
  }

  refreshFrame(frameId) {
    const affectedEvents = new Set((this.relationsByFrame.get(frameId) || []).map((relation) => relation.event));
    for (const eventId of affectedEvents) {
      if (this.groupFrameByEvent.get(eventId) === frameId) this.groupFrameByEvent.delete(eventId);
      if (this.calendarFrameByEvent.get(eventId) === frameId) this.calendarFrameByEvent.delete(eventId);
    }
    const frame = this.document.frames[frameId];
    if (frame?.traits.includes("group") && !frame?.traits.includes("importance")) {
      for (const eventId of affectedEvents) this.groupFrameByEvent.set(eventId, frameId);
    }
    if (frame?.traits.includes("calendar")) {
      for (const eventId of affectedEvents) this.calendarFrameByEvent.set(eventId, frameId);
    }
    // A group frame's own union is never cached here (see `groupUnionFacts`),
    // so nothing extra needs invalidating up an ancestor chain when a member
    // changes -- only this one frame's own leaf-level cache entries, exactly
    // as before group queries existed.
    this.explicitFactsByFrame.delete(frameId);
    this.explicitMaxDurationByFrame.delete(frameId);
    this.explicitErrorsByFrame.delete(frameId);
    this.rebuildGroupMemberships();
  }

  // Anchor-aware placement (src/staples.js's `resolveObjectExtent`, the
  // end-anchored work shift LEXICON.md asks for): an object with no anchor
  // staples must resolve BIT-IDENTICALLY to before this existed
  // (`source: "placement"`, `day`/`coordinate` computed exactly as
  // `attachmentDay` always has), which is the hard regression requirement
  // test/staple-anchoring.test.js guards directly. An object anchored by a
  // staple (an end anchor plus a magnitude, or two anchors that derive the
  // magnitude themselves) is placed at its resolved extent instead, and the
  // full extent rides along on the fact as an ADDED field (`fact.extent`) so
  // a renderer can read spread/overdetermination without re-deriving them --
  // existing fields and their meaning are untouched either way.
  //
  // The "completed" role is deliberately excluded from anchor placement: it
  // names a distinct instant (when a todo was finished), not where the object
  // sits, so an anchor on the object must not relocate it. Extent is still
  // attached for information, just never used to move `day`/`coordinate`.
  //
  // `resolveObjectExtent` is looked up once per event id (not once per
  // relation) via `extentByEvent` below -- a "completed" and a "placed"
  // relation on the same event would otherwise pay for the same document-wide
  // staple scan twice.
  // An event's own occurrence-math duration, read through THIS document's own
  // law (the magnitude's `frame`, normally `measure:human-time`) rather than
  // the registered standard -- a method, not the free function this used to
  // be, because the engine always has its own document and a call site that
  // has the document must pass it (src/coordinate-law.js's own rule).
  eventDurationDays(event) {
    return durationMagnitudeDays(event?.magnitudes?.duration, this.document);
  }

  // The deepest level the author actually wrote for whatever placed this fact,
  // or null when nothing placed it at a coordinate at all (an extent derived
  // from a connection to another object inherits that object's precision through
  // the anchor's own end).
  authoredPrecision(source) {
    const end = source?.anchors?.[0] ? frameEndOf(source.anchors[0].staple) : null;
    const written = end?.coordinate || source?.coordinate || null;
    if (!written) return null;
    const frameId = end?.frame || source?.frame || null;
    if (!frameId) return null;
    try {
      return coordinateEntryDepth(written, coordinateLaw(this.document, frameId));
    } catch {
      return null;
    }
  }

  // The events placed directly on `frameId`'s own coordinate axis by a plain
  // attachment relation (`relation.frame === frameId`) -- everything this
  // method did before a group frame's query learned to union its members,
  // unchanged, and reused AS-IS for a group frame's own directly-attached
  // events (a group frame can double as a plain calendar; that half of a
  // group's facts is not a member-frame union at all and must keep working
  // exactly as it always has). D3: a record whose extent or coordinate
  // cannot resolve is skipped rather than aborting the rest of the frame,
  // and `error` carries the FIRST reason encountered so a frame with many
  // broken records reports once, not once per record.
  directExplicitEntries(frameId) {
    const templateRelations = new Set(
      this.matchingPatterns(frameId)
        .filter((pattern) => pattern.kind === "ics-rrule")
        .map((pattern) => pattern.templateRelation)
    );
    const entries = [];
    let maxDuration = Rational.parse(0);
    const extentByEvent = new Map();
    let error = null;
    const recordSkip = (message) => { if (!error) error = message; };
    for (const relation of this.relationsByFrame.get(frameId) || []) {
      if (templateRelations.has(relation.id)) continue;
      const event = this.document.events[relation.event];
      if (!event) continue;
      let extent = extentByEvent.get(event.id);
      if (extent === undefined) {
        try {
          extent = resolveObjectExtent(this.document, this, event.id);
        } catch (extentError) {
          // src/staples.js resolves an anchor chain through `engine.coordinateDays`
          // directly and throws on the same three unresolvable-law conditions
          // `attachmentDay` guards below; caught here since that file is not this
          // fix's to change.
          recordSkip(extentError.message);
          extent = null;
        }
        extentByEvent.set(event.id, extent);
      }
      if (!extent) continue;
      const anchored = relation.role !== "completed"
        && extent.startDays !== null
        && (extent.source === "anchors" || extent.source === "anchor+magnitude");
      // A coordinate-less attachment relation is bare MEMBERSHIP -- "this object
      // belongs to this frame" -- and membership alone has never placed anything.
      // It places the object here only when the object's own connections resolve
      // an extent IN THIS FRAME'S coordinate space, which is what makes an event
      // defined purely by where it stops appear at all: the placement coordinate
      // it used to need is exactly what a staple now supplies. The frame identity
      // check is load-bearing rather than defensive: an event's group attachments
      // are coordinate-less too, and without it every anchored event would also
      // draw itself on each of its groups.
      if (!relation.coordinate && !(anchored && extent.frame === relation.frame)) continue;
      let day = null;
      if (anchored) {
        day = extent.startDays;
      } else {
        const resolved = attachmentDay(this, relation);
        day = resolved.day;
        if (!day && resolved.reason) recordSkip(resolved.reason);
      }
      if (!day) continue;
      const duration = anchored ? extent.magnitudeDays : this.eventDurationDays(event);
      if (duration.compare(maxDuration) > 0) maxDuration = duration;
      const coordinate = anchored ? this.daysCoordinate(extent.frame || relation.frame, day) : relation.coordinate;
      entries.push({
        day,
        fact: {
          kind: "explicit",
          event,
          relation,
          day: day.toJSON(),
          coordinate,
          // AUTHORED PRECISION, carried so display can honour it. A coordinate
          // of {year: 1973} resolves to the start of 1973 and comes back from
          // `fromDays` with every level filled in, at which point it is
          // indistinguishable from an authored January 1st midnight -- the
          // missing levels having been supplied by the law, not by the author.
          // Depth is authored data (an entry stops where the author stopped) and
          // must not be inferred back out of a resolved instant, so it is read
          // from the SOURCE coordinate and travels on the fact.
          precision: this.authoredPrecision(anchored ? extent : relation),
          extent
        }
      });
    }
    return { entries, maxDuration, error };
  }

  // A group frame is not a coordinate space (AGENTS.md's frame model: the
  // four concepts stay distinct, and selecting or displaying a frame never
  // creates a mapping) -- so its facts are the UNION of its own direct
  // members, each resolved under that member's OWN law, never re-resolved
  // under the group's. Two shapes of member both count (`groupDirectMembers`,
  // one authored hop -- see its own doc comment for why not the flattened
  // index): a member FRAME contributes its own facts recursively (through
  // `indexedExplicitFacts`, so a nested member frame that is itself a group
  // unions again the same way); a member EVENT contributes nothing extra
  // here, because an event's placement lives on whatever frame it is
  // actually attached to -- if that frame is this group itself, plain
  // `directExplicitEntries` above already has it, exactly as before groups
  // could be queried at all.
  //
  // DEDUPE IDENTITY is the relation, not the event: two relations placing one
  // event on two different member frames are two real placements (both
  // survive); the identical relation reached twice -- once directly and once
  // through a nested member frame that also lists it, or through two
  // different nested paths -- is the same fact and collapses to one. Merge
  // order does not matter: whichever copy is kept is structurally identical.
  //
  // `seen` is the cycle guard, carrying every group id already on the CURRENT
  // recursion path (not a document-wide "visited" set, so the same group
  // reachable via two independent, non-cyclic paths is still unioned twice
  // over -- see the dedupe above for why that is still exactly one fact). A
  // group that (transitively) contains itself stops at the repeat and reports
  // once through `errorsByFrame`, the same per-frame-per-query channel D3's
  // unresolvable-coordinate errors use.
  //
  // NOT cached in `explicitFactsByFrame`: this file's one invalidation seam,
  // `refreshFrame(frameId)`, is keyed to a single changed frame. A correct
  // cache would have to walk every ancestor group whenever any transitively-
  // nested member changes, and proving that holds across every call site that
  // can mutate a member's own relations (most of them outside this file,
  // per this task's own file ownership) is exactly the guarantee a wrong
  // cache would silently violate -- on the very field-measured defect this
  // exists to fix. Recomputing costs O(sum of each direct member's own fact
  // count) per query: every member that is an ORDINARY calendar frame (not
  // itself a group) still hits its own existing `explicitFactsByFrame` entry,
  // so a shallow group over a handful of calendars stays cheap; only the
  // union's own merge/sort/dedupe work is unconditionally redone, which is
  // the honest tradeoff overscale doctrine asks for here: a slow-but-correct
  // query beats a fast-but-wrong one.
  groupUnionFacts(groupId, seen) {
    if (seen.has(groupId)) {
      return {
        entries: [],
        maxDuration: Rational.parse(0),
        errorsByFrame: new Map([[
          groupId,
          `Group ${groupId} contains itself; the cycle was broken here rather than unioned forever.`
        ]])
      };
    }
    const nextSeen = new Set(seen);
    nextSeen.add(groupId);

    const own = this.directExplicitEntries(groupId);
    const byRelation = new Map(own.entries.map((entry) => [entry.fact.relation.id, entry]));
    let maxDuration = own.maxDuration;
    const errorsByFrame = new Map();
    if (own.error) errorsByFrame.set(groupId, own.error);

    for (const { member } of this.groupDirectMembers(groupId)) {
      if (!this.document.frames[member]) continue; // a member EVENT: see doc comment above.
      const result = this.isOrdinaryGroup(member)
        ? this.groupUnionFacts(member, nextSeen)
        : {
            entries: this.indexedExplicitFacts(member),
            maxDuration: this.explicitMaxDurationByFrame.get(member) || Rational.parse(0),
            errorsByFrame: (() => {
              const memberErrors = this.explicitErrorsByFrame.get(member) || [];
              return new Map(memberErrors.map((entry) => [entry.frame, entry.message]));
            })()
          };
      for (const entry of result.entries) {
        const key = entry.fact.relation.id;
        if (!byRelation.has(key)) byRelation.set(key, entry);
      }
      if (result.maxDuration.compare(maxDuration) > 0) maxDuration = result.maxDuration;
      for (const [frame, message] of result.errorsByFrame) {
        if (!errorsByFrame.has(frame)) errorsByFrame.set(frame, message);
      }
    }

    const entries = [...byRelation.values()].sort((left, right) => left.day.compare(right.day));
    return { entries, maxDuration, errorsByFrame };
  }

  indexedExplicitFacts(frameId) {
    if (this.isOrdinaryGroup(frameId)) {
      const { entries, maxDuration, errorsByFrame } = this.groupUnionFacts(frameId, new Set());
      this.explicitMaxDurationByFrame.set(frameId, maxDuration);
      this.explicitErrorsByFrame.set(
        frameId,
        [...errorsByFrame].map(([frame, message]) => ({ frame, message }))
      );
      return entries;
    }
    const cached = this.explicitFactsByFrame.get(frameId);
    if (cached) return cached;
    const { entries, maxDuration, error } = this.directExplicitEntries(frameId);
    entries.sort((left, right) => left.day.compare(right.day));
    this.explicitFactsByFrame.set(frameId, entries);
    this.explicitMaxDurationByFrame.set(frameId, maxDuration);
    this.explicitErrorsByFrame.set(frameId, error ? [{ frame: frameId, message: error }] : []);
    return entries;
  }

  recurrenceFacts(pattern, lower, upper, limit) {
    // The small-COUNT fast path below caches a whole rule's life by bounding
    // it from `pattern.rrule`'s own INTERVAL/COUNT/FREQ (`horizon`, just
    // below) -- correct only because an un-segmented rule's whole life IS
    // that bound. A segmented series (src/staples.js's seriesSegments) can
    // run on well past segment 0's own COUNT-bounded life -- the Rob-and-John
    // scenario's Thursday-lunch segment is exactly this: indefinite, years
    // after a bounded-looking first segment. So a segmented pattern is never
    // routed through the horizon-bounded cache; it falls through to the
    // windowed cache below, which always asks `occurrenceFacts` for the
    // query's own true bounds and therefore stays correct across any number
    // of segments.
    const segmented = seriesIsSegmented(this, pattern);
    const hasCount = !segmented && pattern.rrule?.COUNT !== undefined;
    const count = Number(pattern.rrule?.COUNT);
    if (hasCount && (
      !Number.isSafeInteger(count)
      || count < 1
      || count > MAX_CACHED_RECURRENCE_COUNT
    )) {
      return occurrenceFacts(this, pattern, lower, upper, limit);
    }
    if (hasCount) {
      let series = this.recurrenceSeries.get(pattern.id);
      if (series) {
        // Map insertion order is the LRU order. Refresh hot series without
        // allocating another copy of their generated facts.
        this.recurrenceSeries.delete(pattern.id);
        this.recurrenceSeries.set(pattern.id, series);
      } else {
        const relation = this.document.relations[pattern.templateRelation];
        if (!relation?.coordinate) return [];
        const base = this.coordinateDays(relation.frame, relation.coordinate);
        const interval = BigInt(pattern.rrule?.INTERVAL || 1);
        const frequency = String(pattern.rrule?.FREQ || "").toUpperCase();
        const factor = frequency === "DAILY" ? 1n
          : frequency === "WEEKLY" ? 7n
            : frequency === "MONTHLY" ? 32n
              : 367n;
        const horizon = base.add(interval * BigInt(count) * factor + 367n);
        series = occurrenceFacts(this, pattern, base, horizon).map((fact) => ({
          day: rational(fact.day),
          fact
        }));
        while (
          this.recurrenceSeries.size
          && this.recurrenceSeriesFacts + series.length > MAX_RECURRENCE_SERIES_FACTS
        ) {
          const oldest = this.recurrenceSeries.keys().next().value;
          this.recurrenceSeriesFacts -= this.recurrenceSeries.get(oldest).length;
          this.recurrenceSeries.delete(oldest);
        }
        this.recurrenceSeries.set(pattern.id, series);
        this.recurrenceSeriesFacts += series.length;
      }
      const visible = [];
      for (const entry of series) {
        if (entry.day.compare(lower) < 0) continue;
        if (entry.day.compare(upper) > 0) break;
        visible.push(entry.fact);
        if (visible.length >= limit) break;
      }
      return visible;
    }

    const width = 64n;
    const firstWindow = floorDiv(lower.floor(), width);
    const lastWindow = floorDiv(upper.floor(), width);
    const visible = [];
    for (let window = firstWindow; window <= lastWindow; window += 1n) {
      const key = `${pattern.id}\u0000${window}`;
      let entries = this.recurrenceWindows.get(key);
      if (entries) {
        this.recurrenceWindows.delete(key);
        this.recurrenceWindows.set(key, entries);
      } else {
        const windowStart = new Rational(window * width);
        const windowEnd = windowStart.add(width);
        entries = occurrenceFacts(this, pattern, windowStart, windowEnd)
          .map((fact) => ({ day: rational(fact.day), fact }))
          .filter((entry) => entry.day.compare(windowEnd) < 0);
        while (
          this.recurrenceWindows.size
          && (
            this.recurrenceWindows.size >= MAX_RECURRENCE_WINDOWS
            || this.recurrenceWindowFacts + entries.length > MAX_RECURRENCE_WINDOW_FACTS
          )
        ) {
          const oldest = this.recurrenceWindows.keys().next().value;
          this.recurrenceWindowFacts -= this.recurrenceWindows.get(oldest).length;
          this.recurrenceWindows.delete(oldest);
        }
        // An unusually dense single window is useful for the current query but
        // is deliberately not retained after it has been rendered.
        if (entries.length <= MAX_RECURRENCE_WINDOW_FACTS) {
          this.recurrenceWindows.set(key, entries);
          this.recurrenceWindowFacts += entries.length;
        }
      }
      for (const entry of entries) {
        if (entry.day.compare(lower) < 0 || entry.day.compare(upper) > 0) continue;
        visible.push(entry.fact);
        if (visible.length >= limit) return visible;
      }
    }
    return visible;
  }

  coordinateDays(frameId, value) {
    const frame = this.document.frames[frameId];
    const law = frame?.law;
    if (law?.pattern && law.toDays) {
      const pattern = this.document.patterns[law.pattern];
      if (!pattern) throw new Error(`Frame ${frameId} references missing law pattern ${law.pattern}`);
      const output = this.patternModule(pattern).call(law.toDays, [{
        frame: frameId,
        value,
        parameters: law.parameters || {},
        constants: pattern.constants || {}
      }]);
      return rational(output?.days ?? output);
    }
    return coordinateToDays(this.document, frameId, value);
  }

  daysCoordinate(frameId, days) {
    const frame = this.document.frames[frameId];
    const law = frame?.law;
    if (law?.pattern && law.fromDays) {
      const pattern = this.document.patterns[law.pattern];
      if (!pattern) throw new Error(`Frame ${frameId} references missing law pattern ${law.pattern}`);
      const output = this.patternModule(pattern).call(law.fromDays, [{
        frame: frameId,
        days: rational(days).toJSON(),
        parameters: law.parameters || {},
        constants: pattern.constants || {}
      }]);
      if (!output?.levels) throw new TypeError(`Frame law ${law.fromDays} must return a nested coordinate`);
      return output;
    }
    return daysToCoordinate(this.document, frameId, days);
  }

  queryState({ frame, coordinate, selection = null }) {
    const atDays = this.coordinateDays(frame, coordinate);
    const values = {};
    const errors = [];
    for (const pattern of this.matchingPatterns(frame)) {
      const exportName = pattern.exports?.state;
      if (!exportName) continue;
      try {
        values[pattern.id] = this.patternModule(pattern).call(exportName, [{
          frame,
          atDays: atDays.toJSON(),
          selection,
          constants: pattern.constants || {}
        }]);
      } catch (error) {
        errors.push({ pattern: pattern.id, message: error.message });
      }
    }
    return { frame, coordinate, atDays: atDays.toJSON(), values, errors };
  }

  // `applyOverrides: false` yields the projection as the patterns alone describe
  // it, with suppressed occurrences still present. That is what the series heal
  // (src/series-heal.js) compares a materialized occurrence against: an override
  // hides the very slot the heal has to reconstruct, so it must be able to ask
  // "what would this series project here if nothing had overridden it?".
  //
  // It deliberately reuses this generator rather than rebuilding the projection
  // from the pattern's template. The heal's whole purpose is to decide when the
  // projection may reassert, so the comparison has to run through the same code
  // that will then do the reasserting — a second derivation could drift and the
  // heal would either destroy authored edits or never fire.
  queryFacts({ frame, start, end, selection = null, limit = Infinity, includeOverlaps = false, applyOverrides = true }) {
    // A GROUP frame is not a coordinate space, so it cannot resolve a window
    // expressed as a coordinate. Reading one through its own (empty) law is what
    // silently collapsed a group query to a single day: a law with no declared
    // levels permissively reads the bare `day` level, so a year/month/day window
    // became [1, 1] and every group answered zero. The bounds are resolved
    // through the registered standard boundary instead -- the same rule ICS and
    // the host clock already follow when the outside world hands in a civil
    // time and no frame law owns it.
    const windowLaw = this.windowFrameFor(frame);
    const fromDays = windowLaw === null
      ? GREGORIAN_LAW.toDays(start)
      : this.coordinateDays(windowLaw, start);
    const toDays = windowLaw === null
      ? GREGORIAN_LAW.toDays(end)
      : this.coordinateDays(windowLaw, end);
    const ascending = fromDays.compare(toDays) <= 0;
    const lower = ascending ? fromDays : toDays;
    const upper = ascending ? toDays : fromDays;
    const maxFacts = Number.isFinite(Number(limit))
      ? Math.max(1, Math.floor(Number(limit)))
      : Infinity;
    const facts = [];
    const errors = [];
    let truncated = false;
    const explicit = this.indexedExplicitFacts(frame);
    // D3: one entry per broken frame reaches the author here, through the same
    // channel `renderErrors` already displays for a broken pattern -- reusing
    // its `{pattern, message}` shape (with the offending FRAME id in `pattern`)
    // rather than a shape src/projections.js's `renderErrors` does not read,
    // since that file is not this fix's to change. Deduped per frame already,
    // by `indexedExplicitFacts`/`groupUnionFacts` above -- a broken frame with
    // thousands of records, or one reachable through several member paths,
    // still names itself exactly once per query.
    for (const skipped of this.explicitErrorsByFrame.get(frame) || []) {
      errors.push({ pattern: skipped.frame, message: skipped.message });
    }
    const explicitLookback = includeOverlaps
      ? this.explicitMaxDurationByFrame.get(frame) || Rational.parse(0)
      : Rational.parse(0);
    const explicitLower = lower.sub(explicitLookback);
    let low = 0;
    let high = explicit.length;
    while (low < high) {
      const middle = (low + high) >>> 1;
      if (explicit[middle].day.compare(explicitLower) < 0) low = middle + 1;
      else high = middle;
    }
    for (let index = low; index < explicit.length; index += 1) {
      const entry = explicit[index];
      if (entry.day.compare(upper) > 0) break;
      if (
        includeOverlaps
        && entry.day.compare(lower) < 0
        && entry.day.add(this.eventDurationDays(entry.fact.event)).compare(lower) <= 0
      ) continue;
      if (facts.length >= maxFacts) {
        truncated = true;
        break;
      }
      facts.push(entry.fact);
    }

    for (const pattern of this.matchingPatterns(frame)) {
      if (facts.length >= maxFacts) {
        truncated = true;
        break;
      }
      if (pattern.kind === "ics-rrule") {
        try {
          const remaining = maxFacts === Infinity ? Infinity : maxFacts - facts.length;
          const templateDuration = this.eventDurationDays(this.document.events[pattern.templateEvent]);
          const recurrenceLower = includeOverlaps ? lower.sub(templateDuration) : lower;
          const emitted = this.recurrenceFacts(pattern, recurrenceLower, upper, remaining)
            .filter((fact) => (
              rational(fact.day).compare(lower) >= 0
              || rational(fact.day).add(this.eventDurationDays(fact.event)).compare(lower) > 0
            ));
          facts.push(...emitted.slice(0, remaining));
          if (emitted.length >= remaining) truncated = true;
        } catch (error) {
          errors.push({ pattern: pattern.id, message: error.message });
        }
        continue;
      }
      const exportName = pattern.exports?.facts;
      if (!exportName) continue;
      try {
        const emitted = this.patternModule(pattern).call(exportName, [{
          frame,
          fromDays: lower.toJSON(),
          toDays: upper.toJSON(),
          selection,
          constants: pattern.constants || {}
        }]);
        if (!Array.isArray(emitted)) throw new TypeError("facts export must return a list");
        for (const output of emitted) {
          if (facts.length >= maxFacts) {
            truncated = true;
            break;
          }
          const virtualId = stableVirtualId(pattern.id, output.key);
          if (output.type === "event") {
            const day = rational(output.day);
            if (!within(day, lower, upper)) continue;
            const event = {
              id: virtualId,
              traits: output.traits || ["event", "generated"],
              magnitudes: output.magnitudes || { duration: durationMagnitude("0") },
              payload: output.payload || { title: output.key },
              provenance: { kind: "pattern", pattern: pattern.id, key: output.key }
            };
            const relation = {
              id: `${virtualId}/attachment`,
              type: "attachment",
              event: virtualId,
              frame: output.frame || pattern.frame || frame,
              role: output.role || "placed",
              coordinate: this.daysCoordinate(output.frame || pattern.frame || frame, day),
              provenance: { kind: "pattern", pattern: pattern.id, key: output.key }
            };
            facts.push({
              kind: "virtual",
              virtualId,
              event,
              relation,
              day: day.toJSON(),
              coordinate: relation.coordinate
            });
          } else if (output.type === "frame") {
            facts.push({
              kind: "virtual",
              virtualId,
              frame: {
                ...structuredClone(output),
                id: virtualId,
                provenance: { kind: "pattern", pattern: pattern.id, key: output.key }
              }
            });
          } else if (output.type === "relation") {
            facts.push({
              kind: "virtual",
              virtualId,
              relation: {
                ...structuredClone(output),
                id: virtualId,
                provenance: { kind: "pattern", pattern: pattern.id, key: output.key }
              }
            });
          }
        }
      } catch (error) {
        errors.push({ pattern: pattern.id, message: error.message });
      }
    }

    const visible = (applyOverrides ? applyVirtualOverrides(this.document, facts) : facts)
      .sort((left, right) => rational(left.day || 0).compare(rational(right.day || 0)))
      .slice(0, maxFacts);
    return {
      frame,
      start,
      end,
      fromDays: lower.toJSON(),
      toDays: upper.toJSON(),
      facts: visible,
      errors,
      truncated
    };
  }
}
