import { FormulaRuntime } from "./formula.js";
import {
  Rational,
  civilFromDays,
  daysFromCivil,
  daysInMonth,
  floorDiv,
  floorMod
} from "./exact.js";
import {
  applyVirtualOverrides,
  coordinateToDays,
  daysToCoordinate,
  durationMagnitude,
  durationMagnitudeDays,
  stableVirtualId,
  validateDocument
} from "./model.js";

function rational(value) {
  return Rational.parse(value);
}

function within(value, start, end) {
  const point = rational(value);
  return point.compare(start) >= 0 && point.compare(end) <= 0;
}

function attachmentDay(engine, relation) {
  if (!relation.coordinate) return null;
  return engine.coordinateDays(relation.frame, relation.coordinate);
}

// A reference to model.js's canonical durationMagnitudeDays, not a second
// implementation: this used to duplicate that arithmetic here, unclamped and
// throwing, under the same name as the unrelated model.js/drag.js/inspector.js
// helper (src/model.js's `durationMagnitudeDays`) until the melt stage
// reconciled both onto model.js's tolerant/clamped behavior. Kept as a
// one-line event-shaped alias so the four call sites below stay unchanged.
function eventDurationDays(event) {
  return durationMagnitudeDays(event?.magnitudes?.duration);
}

const WEEKDAYS = { SU: 0n, MO: 1n, TU: 2n, WE: 3n, TH: 4n, FR: 5n, SA: 6n };
const MAX_CACHED_RECURRENCE_COUNT = 256;
const MAX_RRULE_COUNT = 10_000n;
const MAX_RECURRENCE_SERIES_FACTS = 12_000;
const MAX_RECURRENCE_WINDOWS = 256;
const MAX_RECURRENCE_WINDOW_FACTS = 16_000;

function weekday(day) {
  return floorMod(BigInt(day) + 4n, 7n);
}

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

function occurrenceFacts(engine, pattern, lower, upper, limit = Infinity) {
  const document = engine.document;
  const relation = document.relations[pattern.templateRelation];
  const event = document.events[pattern.templateEvent];
  if (!relation || !event?.id || !relation.coordinate) return [];
  const base = engine.coordinateDays(relation.frame, relation.coordinate);
  const baseWhole = base.floor();
  const time = base.sub(baseWhole);
  const rule = pattern.rrule || {};
  const frequency = String(rule.FREQ || "").toUpperCase();
  const interval = BigInt(rule.INTERVAL || 1);
  if (interval <= 0n) throw new RangeError(`RRULE INTERVAL must be positive, got ${rule.INTERVAL}`);
  const count = rule.COUNT ? BigInt(rule.COUNT) : null;
  if (count !== null && count > MAX_RRULE_COUNT) {
    throw new RangeError(`RRULE COUNT exceeds the safe limit of ${MAX_RRULE_COUNT}`);
  }
  const until = compactIcsDay(rule.UNTIL);
  const excluded = new Set(pattern.exdates || []);
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

  return days.map((day) => {
    const virtualId = stableVirtualId(pattern.id, `occurrence-${day.toJSON()}`);
    const virtualEvent = {
      ...event,
      id: virtualId,
      provenance: { kind: "pattern", pattern: pattern.id, key: day.toJSON() }
    };
    const virtualRelation = {
      ...relation,
      id: `${virtualId}/attachment`,
      event: virtualId,
      coordinate: engine.daysCoordinate(relation.frame, day),
      provenance: { kind: "pattern", pattern: pattern.id, key: day.toJSON() }
    };
    return {
      kind: "virtual",
      virtualId,
      event: virtualEvent,
      relation: virtualRelation,
      day: day.toJSON(),
      coordinate: virtualRelation.coordinate
    };
  });
}

export class ChronologEngine {
  constructor(document, options = {}) {
    this.runtime = options.runtime || new FormulaRuntime(options.formula);
    this.compiledPatterns = new Map();
    this.setDocument(document);
  }

  setDocument(document, options = {}) {
    const preserveRecurrence = options.preserveRecurrence === true && this.document === document;
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
    return { membersByGroup: members, membershipsByMember, frameByEvent };
  }

  rebuildGroupMemberships() {
    const persisted = this.buildGroupIndex((frameId) => this.isOrdinaryGroup(frameId));
    this.groupMembersByGroup = persisted.membersByGroup;
    this.groupMembershipsByMember = persisted.membershipsByMember;
    this.groupFrameByEvent = persisted.frameByEvent;

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
    this.explicitFactsByFrame.delete(frameId);
    this.explicitMaxDurationByFrame.delete(frameId);
    this.rebuildGroupMemberships();
  }

  indexedExplicitFacts(frameId) {
    const cached = this.explicitFactsByFrame.get(frameId);
    if (cached) return cached;
    const templateRelations = new Set(
      this.matchingPatterns(frameId)
        .filter((pattern) => pattern.kind === "ics-rrule")
        .map((pattern) => pattern.templateRelation)
    );
    const entries = [];
    let maxDuration = Rational.parse(0);
    for (const relation of this.relationsByFrame.get(frameId) || []) {
      if (!relation.coordinate || templateRelations.has(relation.id)) continue;
      const event = this.document.events[relation.event];
      if (!event) continue;
      const day = attachmentDay(this, relation);
      if (!day) continue;
      const duration = eventDurationDays(event);
      if (duration.compare(maxDuration) > 0) maxDuration = duration;
      entries.push({
        day,
        fact: {
          kind: "explicit",
          event,
          relation,
          day: day.toJSON(),
          coordinate: relation.coordinate
        }
      });
    }
    entries.sort((left, right) => left.day.compare(right.day));
    this.explicitFactsByFrame.set(frameId, entries);
    this.explicitMaxDurationByFrame.set(frameId, maxDuration);
    return entries;
  }

  recurrenceFacts(pattern, lower, upper, limit) {
    const hasCount = pattern.rrule?.COUNT !== undefined;
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
    const fromDays = this.coordinateDays(frame, start);
    const toDays = this.coordinateDays(frame, end);
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
        && entry.day.add(eventDurationDays(entry.fact.event)).compare(lower) <= 0
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
          const templateDuration = eventDurationDays(this.document.events[pattern.templateEvent]);
          const recurrenceLower = includeOverlaps ? lower.sub(templateDuration) : lower;
          const emitted = this.recurrenceFacts(pattern, recurrenceLower, upper, remaining)
            .filter((fact) => (
              rational(fact.day).compare(lower) >= 0
              || rational(fact.day).add(eventDurationDays(fact.event)).compare(lower) > 0
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
