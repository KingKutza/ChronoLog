import {
  Rational,
  civilFromDays,
  daysFromCivil,
  daysInMonth,
  formatCivil,
  nowDays
} from "./exact.js";
import { coordinateLaw, GREGORIAN_LAW, daysToCivilCoordinate, displayLaw } from "./coordinate-law.js";
import { projectableFrames } from "./frame-projection.js";
import { arcPath, polar, radialCycleWindow, radialGuideSettings, radialRenderState, spiralRibbonPath } from "./radial.js";
import { isStateFrame, objectKindForEvent } from "./object-kinds.js";
import { factMatchesSelection } from "./session.js";
import { aggregateLinePoints, lineFramePlan, lineProgress, linesRenderState } from "./lines.js";
import { listSections } from "./list.js";
import { boardColumns } from "./board.js";
import { apparentMagnitude, objectHome } from "./falloff.js";
import { aggregateStrategicDays, STRATEGIC_DAY_FACT_LIMIT } from "./strategic-density.js";
import { fixedCalendarDefinition, fixedCalendarParts, fixedDayLabel, fixedMonthWindow } from "./calendar-projection.js";
import {
  MINIMAP_BUCKETS,
  MINIMAP_GRID_ROWS,
  minimapColumnReach,
  minimapDotGrid,
  minimapEventMagnitude,
  minimapLabelGranularity,
  minimapLabelTicks
} from "./minimap.js";
import {
  IMPORTANCE_WEIGHT_THRESHOLD,
  SIGIL_VOCABULARY,
  factImportance,
  factImportanceWeight,
  resolveObjectColor,
  sigilAriaLabel,
  sigilDescription,
  sigilForFact,
  todoStateForFact
} from "./visual-language.js";

const SVG_NS = "http://www.w3.org/2000/svg";
// The minimap is an activity preview, not a second event list.

// The law governing this render pass: every unit relationship below (hours per
// day, minutes per day, month names, the weekday cycle) reads THIS, set exactly
// once per pass by `renderProjection`/`renderMinimap`, so an edited coordinate
// declaration (radix 23 for "hour", say) reaches every helper in the file
// rather than the ~50 call sites that used to carry 24/1440/86400 as literals
// no edit could touch. Defaults to the registered standard so a helper called
// outside a render pass (a test invoking one of the `*ForTest` exports below)
// still gets coherent Gregorian arithmetic rather than an unset law.
let activeLaw = GREGORIAN_LAW;

function minutesPerDayNumber() {
  return activeLaw.minutesPerDay().toNumber();
}

function hoursPerDayNumber() {
  return activeLaw.hoursPerDay().toNumber();
}

function minutesPerHourNumber() {
  return activeLaw.minutesPerHour().toNumber();
}

// Short forms are always derived from the authored name, never a parallel
// abbreviation table -- an authored weekday or month name unlike "Sunday" or
// "January" must still be able to show up abbreviated.
function weekdayShortLabel(day) {
  return activeLaw.weekdayLabel(day).slice(0, 3).toUpperCase();
}

function monthShortName(monthOneBased) {
  const name = activeLaw.monthNames()[Number(monthOneBased) - 1];
  return name ? name.slice(0, 3) : "";
}

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function svgElement(tag, attributes = {}) {
  const node = document.createElementNS(SVG_NS, tag);
  for (const [name, value] of Object.entries(attributes)) node.setAttribute(name, String(value));
  return node;
}

function calendarFrames(document) {
  return Object.values(document.frames)
    .filter((frame) => frame.traits.includes("calendar"))
    .sort((left, right) => left.title.localeCompare(right.title));
}

function groupFrames(document) {
  return Object.values(document.frames)
    .filter((frame) => frame.traits.includes("group"))
    .sort((left, right) => left.title.localeCompare(right.title));
}

function layeredCalendarFrames(context, requestedFrame) {
  if (requestedFrame !== context.session.activeFrame) return [context.document.frames[requestedFrame]].filter(Boolean);
  // Multi-select means every selected frame overlays, from every surface —
  // the 8.19 field report's item 1: only frames[leadingId].display.overlays
  // used to reach here, so checking a companion in the toolbar's Frame drop
  // or the frames panel wrote view state the renderer never consumed. The
  // one selection (src/frame-selection.js, via session.js) is now the only
  // source: it puts the primary first (it owns axis/labels/coordinate law),
  // then every other selected frame that still exists. Companions are
  // subordinate display companions only — their coordinates are never
  // converted (AGENTS.md's frame model, point 4).
  // A state frame can be selected (its selection is what admits its members
  // into the ToDo lenses' projection) but it carries no axis and no
  // coordinate law, so it never overlays a time surface.
  return context.session.selectedFrames()
    .map((id) => context.document.frames[id])
    .filter((frame) => frame && !isStateFrame(frame));
}

// Display-facing: uses the isDisplayGroup union so a group's per-lens display
// settings (Strategic promote/demote, per-calendar presence) and its color
// still apply once it also carries the "importance" trait. Nothing that
// authors or validates the document reads this.
function factGroupFrame(context, fact) {
  const direct = context.engine.eventDisplayGroupFrame(fact.event.id);
  if (direct) return direct;
  const pattern = context.document.patterns[fact.event.provenance?.pattern];
  return pattern?.templateEvent
    ? context.engine.eventDisplayGroupFrame(pattern.templateEvent)
    : null;
}

function factVisibleInLens(context, fact) {
  const lens = context.session.currentLens();
  const pattern = context.document.patterns[fact.event.provenance?.pattern];
  const source = pattern?.templateEvent ? context.document.events[pattern.templateEvent] : fact.event;
  const lenses = source?.display?.lenses || fact.event.display?.lenses;
  if (Array.isArray(lenses) && !lenses.includes(lens)) return false;
  const sourceId = pattern?.templateEvent || fact.event.id;
  const governingFrames = new Set(context.engine.eventFrames(sourceId));
  const governingFrameId = fact.displayFrame || fact.relation?.frame;
  if (governingFrameId) governingFrames.add(governingFrameId);
  for (const frameId of governingFrames) {
    const frame = context.document.frames[frameId];
    if (!frame || frame.traits?.includes("importance")) continue;
    if (Array.isArray(frame.display?.lenses) && !frame.display.lenses.includes(lens)) return false;
  }
  const importanceFrames = context.engine.eventFrames(sourceId)
    .map((id) => context.document.frames[id])
    .filter((frame) => frame?.traits?.includes("importance"));
  if (!importanceFrames.length) return true;
  const cycleDays = context.session.radialCycle.toNumber();
  return importanceFrames.some((frame) => {
    if (Array.isArray(frame.display?.lenses) && !frame.display.lenses.includes(lens)) return false;
    if (["spiral", "radial"].includes(lens)) {
      if (Number.isFinite(Number(frame.display?.radialMinDays)) && cycleDays < Number(frame.display.radialMinDays)) return false;
      if (Number.isFinite(Number(frame.display?.radialMaxDays)) && cycleDays > Number(frame.display.radialMaxDays)) return false;
    }
    return true;
  });
}

function factColor(context, fact) {
  const pattern = context.document.patterns[fact.event.provenance?.pattern];
  const source = pattern?.templateEvent ? context.document.events[pattern.templateEvent] : fact.event;
  return resolveObjectColor({
    document: context.document,
    engine: context.engine,
    object: fact.event,
    sourceObject: source,
    activeFrame: context.session.activeFrame,
    displayFrame: fact.displayFrame,
    relationFrame: fact.relation?.frame,
    groupSizes: context.colorGroupSizes ||= new Map(),
    fallback: fact.event.traits?.includes("celestial") ? "#6d63b8" : "#d4552d"
  });
}

function queryFacts(context, frame, startDays, endDays, limit = 800) {
  const { engine } = context;
  const frames = layeredCalendarFrames(context, frame);
  const sources = new Map(frames.map((frameValue) => [frameValue.id, { frame: frameValue, filterGroups: null }]));
  const base = context.document.frames[frame];
  for (const [groupId, mode] of Object.entries(base?.display?.groupModes || {})) {
    if (mode !== "show") continue;
    // Group membership is composable (authored, queried, and recursively
    // inherited), so inclusion cannot be inferred from legacy attachments.
    // `groupId` may name an importance frame -- the Frames panel's per-
    // calendar presence control offers one row per isDisplayGroup frame, so
    // this must read the same union or an importance frame's "Include all"
    // silently does nothing.
    for (const eventId of engine.displayGroupEventMembers(groupId)) {
      for (const calendarId of engine.eventCalendarFrames(eventId)) {
        const calendar = context.document.frames[calendarId];
        if (!calendar) continue;
        const source = sources.get(calendarId) || { frame: calendar, filterGroups: new Set() };
        if (source.filterGroups === null) continue;
        source.filterGroups.add(groupId);
        sources.set(calendarId, source);
      }
    }
  }
  const perFrameLimit = Math.max(80, Math.ceil(limit / Math.max(1, sources.size)) + 24);
  // `startDays`/`endDays` are universal day ordinals, and `sources` can hold
  // several calendar frames at once (the base frame plus every included
  // companion) whose laws need not agree -- companion coordinates are never
  // reinterpreted under another frame's law (AGENTS.md's frame model), so each
  // source resolves the window under its OWN law rather than one shared
  // standard-civil coordinate applied to every frame alike.
  // CROSS-FRAME PROJECTION EXISTS ONLY THROUGH STAPLES (src/frame-projection.js).
  // A companion frame with no authored correspondence to the viewed frame is
  // REFUSED rather than drawn: a shared atom makes two calendars' units
  // comparable in length and says nothing about when, and an authored origin
  // anchors a calendar's own eras to each other and makes no claim on this axis.
  // Placing Tamriel's Third Era next to 1970 because both count days from an
  // internal zero would be a correspondence nobody authored.
  const projection = projectableFrames(
    context.document,
    [...sources.values()].map((source) => source.frame.id),
    frame
  );
  const projectable = new Set(projection.projectable);
  const results = [...sources.values()].filter((source) => projectable.has(source.frame.id)).map((source) => {
    const sourceLaw = coordinateLaw(context.document, source.frame.id);
    return {
      frame: source.frame,
      filterGroups: source.filterGroups,
      result: engine.queryFacts({
        frame: source.frame.id,
        start: sourceLaw.fromDays(startDays),
        end: sourceLaw.fromDays(endDays),
        limit: perFrameLimit,
        includeOverlaps: true
      })
    };
  });
  const refusedProjection = projection.refused;
  const groupModes = context.document.frames[frame]?.display?.groupModes || {};
  const merged = results.flatMap(({ frame: frameValue, filterGroups, result }) => result.facts
    .filter((fact) => !filterGroups || filterGroups.has(factGroupFrame(context, fact)))
    .map((fact) => ({
    ...fact,
    displayFrame: frameValue.id,
    displayLayer: frameValue.id === frame ? "base" : "included"
  }))).filter((fact) => factVisibleInLens(context, fact)
      && groupModes[factGroupFrame(context, fact)] !== "hide")
    .sort((left, right) => Rational.parse(left.day).compare(Rational.parse(right.day)));
  const seen = new Set();
  const facts = merged.filter((fact) => {
    const key = `${fact.event.id}\u0000${fact.virtualId || ""}\u0000${fact.day}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  }).slice(0, limit);
  return {
    frame,
    start: coordinateLaw(context.document, frame).fromDays(startDays),
    end: coordinateLaw(context.document, frame).fromDays(endDays),
    facts,
    // A companion refused for want of an authored correspondence is reported in
    // the same channel as any other per-source reason: rendering nothing and
    // saying nothing would look identical to an empty calendar.
    errors: [
      ...results.flatMap(({ result }) => result.errors || []),
      ...refusedProjection.map((entry) => ({ pattern: entry.frame, message: entry.message }))
    ],
    truncated: facts.length >= limit || results.some(({ result }) => result.truncated)
  };
}

function queryStrategicFacts(context, frame, start, end) {
  const ordinary = queryFacts(context, frame, new Rational(start), new Rational(end), 800);
  if (!ordinary.truncated) return { ...ordinary, density: null };
  const density = aggregateStrategicDays({
    start,
    end,
    perDayLimit: STRATEGIC_DAY_FACT_LIMIT,
    queryDay(dayStart, dayEnd, limit) {
      return queryFacts(context, frame, new Rational(dayStart), new Rational(dayEnd), limit);
    }
  });
  return {
    ...ordinary,
    // This is no longer an error condition: every date has a bounded,
    // deterministic sample and advertises any lower-bound count in its cell.
    facts: density.days.flatMap((entry) => entry.facts),
    errors: density.errors,
    truncated: false,
    density
  };
}

function factsByDay(facts, visibleStart, visibleEnd) {
  const map = new Map();
  const dayMinutes = minutesPerDayNumber();
  for (const fact of facts) {
    const start = Rational.parse(fact.day);
    const duration = Rational.parse(String(durationMinutes(fact.event))).div(activeLaw.minutesPerDay());
    const end = start.add(duration);
    const first = start.floor();
    const afterLast = duration.compare(0) > 0 ? end.ceil() : first + 1n;
    const clippedFirst = visibleStart === undefined
      ? first
      : first > Rational.parse(visibleStart).floor() ? first : Rational.parse(visibleStart).floor();
    const visibleAfter = visibleEnd === undefined ? afterLast : Rational.parse(visibleEnd).ceil();
    const clippedAfter = afterLast < visibleAfter ? afterLast : visibleAfter;
    for (let day = clippedFirst; day < clippedAfter; day += 1n) {
      const key = day.toString();
      const list = map.get(key) || [];
      const segmentStartMinute = day === first ? minuteOfDay(start) : 0;
      const segmentEndMinute = duration.compare(0) <= 0
        ? segmentStartMinute
        : day === end.floor() ? minuteOfDay(end) : dayMinutes;
      list.push({
        ...fact,
        displayDay: key,
        segmentStartMinute,
        segmentEndMinute,
        continuation: day > first,
        continuesAfter: day + 1n < afterLast
      });
      map.set(key, list);
    }
  }
  return map;
}

function minuteOfDay(day) {
  const value = Rational.parse(day);
  return value.sub(value.floor()).mul(activeLaw.minutesPerDay()).toNumber();
}

// The one duration-in-minutes primitive: a magnitude's worth in days comes from
// the governing law (`magnitudeDays` -- an hour is 1/23 of a day on a 23-hour
// frame, not a fixed 1/24), then that day count becomes THIS display's
// minutes. The old parallel factor table {week:10080, day:1440, hour:60, ...}
// could not see an edited hour radix at all, which is the bug this melts away.
function durationMinutes(event) {
  const days = activeLaw.magnitudeDays(event?.magnitudes?.duration);
  const minutes = days.mul(activeLaw.minutesPerDay()).toNumber();
  return Number.isFinite(minutes) ? Math.max(0, minutes) : 0;
}

function clockLabel(minutes) {
  const minutesPerHour = Math.max(1, minutesPerHourNumber());
  const hoursPerDay = Math.max(1, hoursPerDayNumber());
  const whole = Math.max(0, Math.floor(minutes));
  const hour = Math.floor(whole / minutesPerHour) % hoursPerDay;
  const minute = Math.floor(whole % minutesPerHour);
  const half = hoursPerDay / 2;
  const suffix = hour < half ? "a" : "p";
  const displayHour = Math.floor(hour % half) || Math.ceil(half);
  return `${displayHour}${minute ? `:${String(minute).padStart(2, "0")}` : ""}${suffix}`;
}

// The selection in force for this render pass. Every lens funnels its fact nodes
// through `bindFact`, so marking selection there covers all seven at once; the
// alternative was threading `context` through every call site of a function whose
// whole job is stamping dataset attributes. `renderProjection` is the single
// entry point, so this is set exactly once per pass.
let activeSelection = null;

function bindFact(node, fact) {
  node.dataset.eventId = fact.event.id;
  node.dataset.factDay = fact.day;
  if (fact.virtualId) node.dataset.virtualId = fact.virtualId;
  else if (fact.relation?.id) node.dataset.relationId = fact.relation.id;
  if (factMatchesSelection(activeSelection, fact)) node.dataset.selected = "true";
  return node;
}

// Falloff (src/falloff.js) reaching the display-weight pathway: an UNRESOLVED
// todo (no done/closed affiliation) seen from farther past its home registers
// with lower apparent magnitude. The ratio is h/(h+d) -- apparentMagnitude of
// a unit base -- exact until the `.toNumber()` boundary here, where it joins
// the weight numbers (already plain JS numbers) it modifies. Null means "no
// falloff applies": not a todo, done/closed (their state grammar already says
// what they are), no home, a home not yet past, or a law with no now-mapping
// (no clock, no honest distance from now).
function todoFalloffRatio(context, fact) {
  if (!activeLaw.mapsToClock()) return null;
  if (objectKindForEvent(fact.event) !== "todo") return null;
  const state = todoStateForFact(context, fact);
  if (state === "done" || state === "closed") return null;
  const memo = context.todoFalloffMemo ||= new Map();
  if (memo.has(fact.event.id)) return memo.get(fact.event.id);
  const home = objectHome(context.document, context.engine, fact.event.id);
  const now = nowDays();
  let ratio = null;
  if (home && now.compare(home.endDays) > 0) {
    ratio = apparentMagnitude("1", now.sub(home.endDays)).toNumber();
  }
  memo.set(fact.event.id, ratio);
  return ratio;
}

// The opacity ramp's buckets, and the lens's falloff floor: bucket 3 is the
// floor -- a lapsed todo fades to it and no further, so it still renders at
// its historical staples when scrolled to. It lapses from prominence, never
// from truth.
function todoFalloffBucket(ratio) {
  if (ratio === null || ratio > 0.75) return null;
  if (ratio > 0.5) return "1";
  if (ratio > 0.25) return "2";
  return "3";
}

// The falloff-aware importance verdict every renderer in this file reads in
// place of bare `factImportance`: identical for everything except an
// unresolved todo past its home, whose composed weight is scaled by the
// apparent-magnitude ratio before the same thresholds apply -- so a promoted
// but long-lapsed todo demotes in every importance-driven treatment at once.
function factRenderImportance(context, fact) {
  const ratio = todoFalloffRatio(context, fact);
  if (ratio === null) return factImportance(context, fact);
  const weight = factImportanceWeight(context, fact) * ratio;
  if (weight >= IMPORTANCE_WEIGHT_THRESHOLD.landmark) return "landmark";
  if (weight >= IMPORTANCE_WEIGHT_THRESHOLD.important) return "important";
  return "standard";
}

function applySigil(node, fact, context) {
  const sigil = sigilForFact(fact, durationMinutes(fact.event), factRenderImportance(context, fact), minutesPerDayNumber());
  const vocabulary = SIGIL_VOCABULARY[sigil];
  node.dataset.sigil = sigil;
  node.dataset.sigilGlyph = vocabulary.glyph;
  // The cross-lens ToDo state stamp and falloff bucket ride the same funnel
  // as the sigil, so every mark -- chip, intimate float, pip, line dot,
  // radial arc -- carries them without per-lens wiring. State is a modifier
  // axis over the task ○ glyph; the aria label composes it.
  const todoState = todoStateForFact(context, fact);
  if (todoState) node.dataset.todoState = todoState;
  const falloffBucket = todoFalloffBucket(todoFalloffRatio(context, fact));
  if (falloffBucket) node.dataset.todoFalloff = falloffBucket;
  node.setAttribute("aria-label", sigilAriaLabel(sigil, todoState, fact.event.payload?.title));
  return sigil;
}

function eventChip(context, fact, compact = false) {
  const spanning = durationMinutes(fact.event) >= minutesPerDayNumber();
  const lens = context.session.currentLens();
  const zone = Boolean(context.session[`${lens}ZoneFill`]) && spanning;
  const zoneClass = !zone ? "" : fact.continuation
    ? fact.continuesAfter ? " zone-fill zone-middle" : " zone-fill zone-end"
    : fact.continuesAfter ? " zone-fill zone-start" : " zone-fill";
  const chip = element("button", `event-chip${compact ? " compact" : ""}${zoneClass}`);
  chip.type = "button";
  bindFact(chip, fact);
  applySigil(chip, fact, context);
  chip.style.setProperty("--event-color", factColor(context, fact));
  chip.textContent = fact.event.payload?.title || "(untitled)";
  const frame = context.document.frames[fact.displayFrame || fact.relation?.frame || context.session.activeFrame];
  chip.title = `${chip.textContent} · ${fixedDayLabel(frame, fact.day) || formatCivil(fact.coordinate, true)}`;
  return chip;
}

function applyZoneDay(context, cell, facts, labelTarget = null) {
  const lens = context.session.currentLens();
  if (!context.session[`${lens}ZoneFill`]) return null;
  const fact = facts.find((item) => durationMinutes(item.event) >= minutesPerDayNumber());
  if (!fact) return null;
  cell.classList.add("zone-day");
  cell.style.setProperty("--zone-color", factColor(context, fact));
  if (!fact.continuation && labelTarget) {
    const label = element("span", "zone-day-title", fact.event.payload?.title || "(untitled)");
    labelTarget.append(label);
  }
  return fact;
}

function renderErrors(target, result) {
  if (!result.errors?.length && !result.truncated) return;
  const error = element("div", "projection-error");
  error.textContent = [
    ...(result.errors || []).map((item) => `${item.pattern}: ${item.message}`),
    ...(result.truncated ? ["Dense window: showing a bounded set of events. Narrow the window for detail."] : [])
  ].join(" · ");
  target.append(error);
}

function renderIntimate(target, context) {
  const calendar = context.document.frames[context.session.activeFrame];
  const focus = context.session.currentFocus();
  const firstDay = focus.floor() - BigInt(context.session.intimateBack);
  const dayCount = context.session.intimateBack + context.session.intimateForward + 1;
  const lastDay = firstDay + BigInt(dayCount - 1);
  const hourPixels = context.session.intimateHourPixels;
  // This frame's own hour/minute relationships -- a 23-hour day makes for a
  // 23-slot rail, not a 24-slot one with an unreachable hour at the bottom.
  const hoursPerDay = hoursPerDayNumber();
  const minutesPerDay = minutesPerDayNumber();
  const minutesPerHour = minutesPerHourNumber();
  const visibleHours = Math.max(1, (target.clientHeight - 70) / hourPixels);
  // Leave several complete days on either side of the viewport.  Rebuilding a
  // virtual rail is still necessary eventually, but keeping that seam well
  // away from the next midnight makes ordinary day-to-day scrolling continuous.
  const bufferDays = BigInt(Math.max(3, Math.ceil(visibleHours / hoursPerDay) + 1));
  const queryStart = firstDay - bufferDays;
  const queryEnd = lastDay + bufferDays + 1n;
  const result = queryFacts(
    context,
    context.session.activeFrame,
    new Rational(queryStart),
    new Rational(queryEnd),
    900
  );
  const byDay = factsByDay(result.facts, queryStart, queryEnd);
  const wrap = element("div", "intimate");
  wrap.style.setProperty("--days", String(dayCount));
  const header = element("div", "intimate-header");
  header.append(element("div", "intimate-corner", "TIME"));
  const now = new Date();
  const today = daysFromCivil(BigInt(now.getFullYear()), BigInt(now.getMonth() + 1), BigInt(now.getDate()));
  for (let day = firstDay; day <= lastDay; day += 1n) {
    const dayHeader = element("div", `intimate-dayhead${day === today ? " today" : ""}`);
    dayHeader.dataset.createDay = day.toString();
    const allDay = (byDay.get(day.toString()) || []).filter((fact) => fact.relation.parameters?.dateOnly
      || (context.session.intimateZoneFill && durationMinutes(fact.event) >= minutesPerDay));
    dayHeader.append(element("strong", "", fixedDayLabel(calendar, day) || (() => {
      const civil = civilFromDays(day);
      return `${weekdayShortLabel(day)} ${civil.month}/${civil.day}`;
    })()));
    const allDayLane = element("div", "intimate-all-day-lane");
    const zoneFact = applyZoneDay(context, dayHeader, allDay, allDayLane);
    for (const fact of allDay.filter((item) => item !== zoneFact).slice(0, 2)) allDayLane.append(eventChip(context, fact, true));
    dayHeader.append(allDayLane);
    if (allDay.length) dayHeader.title = `${allDay.length} all-day event${allDay.length === 1 ? "" : "s"}`;
    header.append(dayHeader);
  }
  const railDays = Number(bufferDays * 2n + 1n);
  const railHours = railDays * hoursPerDay;
  const railHeight = railHours * hourPixels;
  const scroll = element("div", "intimate-scroll");
  scroll.dataset.scrollKey = "intimate";
  scroll.dataset.bufferHours = String(Number(bufferDays) * hoursPerDay);
  scroll.dataset.hourPixels = String(hourPixels);
  // Published alongside hourPixels so src/ui/drag.js and src/ui/workspace.js
  // (which count `dataset.timelineHours`/`dataset.bufferHours` in THIS frame's
  // hours, per their own dataset contract) can agree on what one hour is
  // without recomputing it from the document themselves.
  scroll.dataset.hoursPerDay = String(hoursPerDay);
  scroll.dataset.headerPixels = "70";
  scroll.dataset.initialHour = String((context.session.intimateStartHour + context.session.intimateEndHour) / 2);
  const body = element("div", "intimate-body");
  const gutter = element("div", "intimate-gutter");
  gutter.style.height = `${railHeight}px`;
  for (let hour = 0; hour < railHours; hour += 1) {
    const label = element("span", "intimate-hour-label", clockLabel((hour % hoursPerDay) * minutesPerHour));
    label.style.top = `${hour * hourPixels}px`;
    gutter.append(label);
  }
  for (let boundary = 1; boundary < railDays; boundary += 1) {
    const line = element("div", "intimate-midnight-line");
    line.style.top = `${boundary * hoursPerDay * hourPixels}px`;
    gutter.append(line);
  }
  body.append(gutter);
  for (let day = firstDay; day <= lastDay; day += 1n) {
    const column = element("div", `intimate-day-column${day === today ? " today" : ""}`);
    column.style.height = `${railHeight}px`;
    column.style.setProperty("--grain-px", `${hourPixels * context.session.intimateGrain / minutesPerHour}px`);
    column.dataset.createDay = day.toString();
    column.dataset.timelineStart = (day - bufferDays).toString();
    column.dataset.timelineHours = String(railHours);
    const timed = [];
    for (let offset = -Number(bufferDays); offset <= Number(bufferDays); offset += 1) {
      const segmentDay = day + BigInt(offset);
      const segmentIndex = offset + Number(bufferDays);
      const dayFacts = byDay.get(segmentDay.toString()) || [];
      const spanning = dayFacts.find((fact) => context.session.intimateZoneFill && durationMinutes(fact.event) >= minutesPerDay);
      if (spanning) {
        const fill = element("div", "intimate-zone-segment");
        fill.style.top = `${segmentIndex * hoursPerDay * hourPixels}px`;
        fill.style.height = `${hoursPerDay * hourPixels}px`;
        fill.style.setProperty("--zone-color", factColor(context, spanning));
        column.append(fill);
      }
      timed.push(...dayFacts
        .filter((fact) => !fact.relation.parameters?.dateOnly
          && !(context.session.intimateZoneFill && durationMinutes(fact.event) >= minutesPerDay))
        .map((fact) => {
          const start = segmentIndex * minutesPerDay + Math.max(0, fact.segmentStartMinute);
          const end = segmentIndex * minutesPerDay + Math.min(minutesPerDay, Math.max(
            fact.segmentEndMinute,
            fact.segmentStartMinute + context.session.intimateGrain
          ));
          return { fact, start, end };
        })
        .filter((item) => item.end > item.start));
    }
    timed.sort((left, right) => left.start - right.start);
    const assignLanes = (items) => {
      const laneEnds = [];
      for (const item of items) {
        let lane = laneEnds.findIndex((end) => end <= item.start);
        if (lane < 0) lane = laneEnds.length;
        laneEnds[lane] = item.end;
        item.lane = lane;
      }
      for (const item of items) {
        const overlaps = items.filter((other) => other.start < item.end && other.end > item.start);
        item.laneCount = Math.max(1, ...overlaps.map((other) => other.lane + 1));
      }
    };
    // Notes and ToDos are floats, not blocks of committed time, so they get their
    // own lane group and right-align in the column. They read as marginalia beside
    // the day rather than competing with events for its width.
    //
    // Lane assignment is otherwise frame-agnostic: `displayLayer` ("base" vs.
    // "included") says which frame supplied a fact for coloring/labeling
    // purposes only -- it used to also gate a second, independent lane group
    // for companion-frame facts, sized by a fixed shrinking-width formula that
    // never looked at what it actually overlapped. That is the 8.19 field
    // report's item 2: swap which selected frame is primary and the facts that
    // used to render normally pile into that narrow companion strip instead,
    // because their lane math changed with their displayLayer even though
    // nothing about their temporal overlap did. Every selected frame overlays
    // equally (src/frame-selection.js; AGENTS.md's frame model, point 4), so
    // lane assignment -- and the width/position it drives -- must depend only
    // on temporal overlap: one lane group for all timed (non-float) facts,
    // primary and companion together.
    const isFloat = (item) => ["todo", "note"].includes(objectKindForEvent(item.fact.event));
    assignLanes(timed.filter((item) => !isFloat(item)));
    assignLanes(timed.filter((item) => isFloat(item)));
    for (const item of timed.slice(0, 80)) {
      const included = item.fact.displayLayer === "included";
      const important = factRenderImportance(context, item.fact) !== "standard";
      const continuation = item.fact.continuation && durationMinutes(item.fact.event) < minutesPerDay;
      const float = isFloat(item);
      const button = element("button", `intimate-event${included ? " included-event" : ""}${float ? " float-event" : ""}${important ? " important-event" : ""}${continuation ? " continuation-event" : ""}`);
      button.type = "button";
      bindFact(button, item.fact);
      applySigil(button, item.fact, context);
      button.style.setProperty("--event-color", factColor(context, item.fact));
      button.style.top = `${item.start / minutesPerHour * hourPixels}px`;
      button.style.height = `${Math.max(13, (item.end - item.start) / minutesPerHour * hourPixels)}px`;
      if (float) {
        // Right-edge anchoring is the ruling (ROADMAP #2: floats read as
        // marginalia down the right of the day); it is not a reason to
        // narrow one. Absent a genuine overlapping float, a float claims the
        // full column, same as a lone timed event would -- only a real
        // neighbour (item.laneCount, computed above for the float group same
        // as it is for the timed group) may divide the width, mirrored from
        // the right instead of the left.
        button.style.right = `${item.lane / item.laneCount * 100}%`;
        button.style.width = `calc(${100 / item.laneCount}% - 3px)`;
      } else {
        button.style.left = `${item.lane / item.laneCount * 100}%`;
        button.style.width = `calc(${100 / item.laneCount}% - 3px)`;
      }
      button.append(
        element("strong", "", `${continuation ? "↳ " : ""}${item.fact.event.payload?.title || "(untitled)"}${continuation ? " · continued" : ""}`),
        element("time", "", clockLabel(item.start % minutesPerDay)),
        ...(item.fact.event.payload?.location && item.end - item.start >= 30
          ? [element("span", "event-location", item.fact.event.payload.location)]
          : [])
      );
      column.append(button);
    }
    // The spectrum: an open todo whose staple is ahead of the view's now
    // occupies the stretch now→staple. A light span treatment on the todo's
    // own lane -- never a second event -- from the now line up to where its
    // chip sits. Withheld with the now line itself under a law with no
    // now-mapping, and never drawn for done/closed todos: their state grammar
    // already says what they are.
    if (activeLaw.mapsToClock() && today >= day - bufferDays && today <= day + bufferDays) {
      const nowRailMinutes = Number(today - (day - bufferDays)) * minutesPerDay + minuteOfDay(nowDays());
      for (const item of timed.slice(0, 80)) {
        if (!isFloat(item) || objectKindForEvent(item.fact.event) !== "todo") continue;
        if (item.start <= nowRailMinutes) continue;
        const state = todoStateForFact(context, item.fact);
        if (state === "done" || state === "closed") continue;
        const span = element("div", "todo-spectrum");
        span.style.setProperty("--event-color", factColor(context, item.fact));
        span.style.top = `${nowRailMinutes / minutesPerHour * hourPixels}px`;
        span.style.height = `${(item.start - nowRailMinutes) / minutesPerHour * hourPixels}px`;
        span.style.right = `${item.lane / item.laneCount * 100}%`;
        span.style.width = `calc(${100 / item.laneCount}% - 3px)`;
        column.append(span);
      }
    }
    for (let boundary = 1; boundary < railDays; boundary += 1) {
      const boundaryDay = day - bufferDays + BigInt(boundary);
      const previousCivil = civilFromDays(boundaryDay - 1n);
      const nextCivil = civilFromDays(boundaryDay);
      const marker = element("div", "intimate-midnight-marker");
      marker.style.top = `${boundary * hoursPerDay * hourPixels}px`;
      marker.append(
        element("span", "midnight-before", fixedDayLabel(calendar, boundaryDay - 1n, true) || `${previousCivil.month}/${previousCivil.day}`),
        element("strong", "", "MIDNIGHT"),
        element("span", "midnight-after", fixedDayLabel(calendar, boundaryDay, true) || `${nextCivil.month}/${nextCivil.day}`)
      );
      column.append(marker);
    }
    // Owner's field note: "no artificial Now line on a calendar with no
    // now-mapping." A law that does not place its coordinates on the running
    // clock at all has no "today" to draw a line through, so the whole marker
    // (not merely its line) is withheld.
    if (activeLaw.mapsToClock() && today >= day - bufferDays && today <= day + bufferDays) {
      const line = element("div", "intimate-now");
      // The fraction of a real day elapsed is frame-agnostic (a day is a day
      // regardless of how many units it is divided into for display), so
      // `minuteOfDay` under the governing law turns that fraction into THIS
      // rail's minutes -- not a fixed 24/60 read off the host clock.
      const nowMinute = minuteOfDay(nowDays());
      const segmentIndex = Number(today - (day - bufferDays));
      line.style.top = `${(segmentIndex * minutesPerDay + nowMinute) / minutesPerHour * hourPixels}px`;
      column.append(line);
    }
    body.append(column);
  }
  scroll.append(header, body);
  wrap.append(scroll);
  target.append(wrap);
  renderErrors(target, result);
}

function strategicPresentation(context, fact) {
  const group = context.document.frames[factGroupFrame(context, fact)];
  const visibility = group?.display?.strategic || "auto";
  if (visibility === "hide" || (visibility === "auto" && /reserved\s*time/i.test(group?.title || ""))) {
    return "none";
  }
  if (visibility === "show") return "name";
  const duration = durationMinutes(fact.event);
  // Strategic was the one importance-aware lens that hand-rolled its own check
  // instead of asking `factImportance`, and it got two things wrong: it never
  // consulted importance frames at all, so an object made important by group
  // affiliation was invisible here at any duration; and its trait list omitted
  // "landmark", so the stronger half of the legacy mechanism was invisible too.
  // A short, non-recurring object with `important === false` degrades to "none",
  // which is why the data vanished rather than merely rendering plainly.
  //
  // The imported-category regex that used to sit here is gone on purpose: meaning
  // is authored, never inferred, and specifically not from imported categories.
  // It was the only place in the codebase that promoted an object on the strength
  // of a provider's category string.
  const important = factRenderImportance(context, fact) !== "standard";
  const pattern = context.document.patterns[fact.event.provenance?.pattern];
  const frequency = String(pattern?.rrule?.FREQ || "").toUpperCase();
  if (context.session.strategicMode === "blocks") return duration >= 240 ? "name" : "none";
  if (context.session.strategicMode === "all") return duration >= 240 || important ? "name" : "pip";
  if (duration >= 240 || important || ["MONTHLY", "YEARLY"].includes(frequency)) return "name";
  if (frequency === "WEEKLY") return "pip";
  return "none";
}

function renderTactical(target, context) {
  const calendar = context.document.frames[context.session.activeFrame];
  const focusDay = context.session.currentFocus().floor();
  const total = context.session.tacticalRows * context.session.tacticalColumns;
  const start = focusDay - BigInt(Math.floor(total / 2));
  const result = queryFacts(context, context.session.activeFrame, new Rational(start), new Rational(start + BigInt(total)), 600);
  const byDay = factsByDay(result.facts, start, start + BigInt(total));
  // The spectrum, Tactical's shape of it: an open todo stapled ahead of the
  // view's now washes the cells from today through its staple day -- a
  // zone-like treatment, never a second event; the chip stays at its staple.
  // Withheld under a law with no now-mapping, same as the now line.
  const spectrumDays = new Set();
  if (activeLaw.mapsToClock()) {
    const now = new Date();
    const nowDay = daysFromCivil(BigInt(now.getFullYear()), BigInt(now.getMonth() + 1), BigInt(now.getDate()));
    for (const fact of result.facts) {
      if (objectKindForEvent(fact.event) !== "todo") continue;
      const state = todoStateForFact(context, fact);
      if (state === "done" || state === "closed") continue;
      const factDay = Rational.parse(fact.day).floor();
      if (factDay <= nowDay) continue;
      const first = nowDay > start ? nowDay : start;
      const last = factDay < start + BigInt(total) ? factDay : start + BigInt(total) - 1n;
      for (let spanDay = first; spanDay <= last; spanDay += 1n) spectrumDays.add(spanDay.toString());
    }
  }
  const grid = element("div", "tactical-grid");
  grid.style.setProperty("--rows", String(context.session.tacticalRows));
  grid.style.setProperty("--columns", String(context.session.tacticalColumns));
  const dayMinutes = minutesPerDayNumber();
  for (let offset = 0n; offset < BigInt(total); offset += 1n) {
    const day = start + offset;
    const civil = civilFromDays(day);
    const weekday = activeLaw.cycleIndex("weekday", day);
    const fixed = fixedCalendarParts(calendar, day);
    const cell = element("section", `tactical-day${weekday === 0 || weekday === 6 ? " weekend" : ""}`);
    if (spectrumDays.has(day.toString())) cell.classList.add("todo-spectrum-day");
    cell.dataset.createDay = day.toString();
    const header = element("header", "day-heading");
    header.append(
      element("span", "weekday", fixed?.parts.at(-1)?.label || fixed?.parts.at(-1)?.name || weekdayShortLabel(day)),
      element("strong", "", fixedDayLabel(calendar, day, true) || `${civil.month}/${civil.day}`),
      element("small", "", fixed ? fixed.parts[0].value.toString() : civil.year.toString())
    );
    cell.append(header);
    const dayFacts = byDay.get(day.toString()) || [];
    const zoneFact = applyZoneDay(context, cell, dayFacts, header);
    const displayFacts = dayFacts.filter((item) => item !== zoneFact
      && !(item.continuation && durationMinutes(item.event) < dayMinutes));
    for (const fact of displayFacts.slice(0, 12)) cell.append(eventChip(context, fact));
    if (displayFacts.length > 12) cell.append(element("div", "event-overflow", `+${displayFacts.length - 12} more`));
    grid.append(cell);
  }
  target.append(grid);
  renderErrors(target, result);
}

function addMonths(yearValue, monthValue, offsetValue) {
  const total = BigInt(yearValue) * 12n + BigInt(monthValue) - 1n + BigInt(offsetValue);
  return {
    year: total >= 0n ? total / 12n : (total - 11n) / 12n,
    month: ((total % 12n) + 12n) % 12n + 1n
  };
}

function monthCard(context, year, month, facts, detailed = false) {
  const card = element("section", detailed ? "wall-month" : "strategic-month");
  const heading = element("header", "month-heading");
  heading.append(
    element("strong", "", activeLaw.monthNames()[Number(month) - 1]),
    element("span", "", year.toString())
  );
  card.append(heading);
  const weekdays = element("div", "month-weekdays");
  // The header initials are this frame's own weekday names, Monday-first to
  // match the grid's column order below (`lead`). A hardcoded M-T-W-T-F-S-S row
  // would silently disagree with an authored weekday list, which is exactly the
  // divergence the law exists to prevent -- and it also assumed a seven-day
  // week, which the cycle's own radix is free not to be.
  const weekdayCycle = activeLaw.weekdayNames();
  for (let index = 0; index < weekdayCycle.length; index += 1) {
    const name = weekdayCycle[(index + 1) % weekdayCycle.length];
    weekdays.append(element("span", "", name.slice(0, 1).toUpperCase()));
  }
  card.append(weekdays);
  const grid = element("div", "month-days");
  const first = daysFromCivil(year, month, 1n);
  const now = new Date();
  const today = daysFromCivil(BigInt(now.getFullYear()), BigInt(now.getMonth() + 1), BigInt(now.getDate()));
  // Blank cells before the 1st, in this grid's Monday-first column order --
  // derived from the law's own weekday cycle index (Sunday = 0) rather than a
  // second, independent floorMod formula, so an edited weekday offset moves
  // both together.
  const lead = (activeLaw.cycleIndex("weekday", first) + 6) % 7;
  for (let index = 0; index < lead; index += 1) grid.append(element("div", "month-pad"));
  const totalDays = daysInMonth(year, month);
  const dayMinutes = minutesPerDayNumber();
  for (let day = 1; day <= totalDays; day += 1) {
    const ordinal = daysFromCivil(year, month, BigInt(day));
    const cell = element("div", "month-day");
    if (context.session.wallRecordSlashes && ordinal < today) cell.classList.add("record-slash");
    cell.dataset.createDay = ordinal.toString();
    const dayLabel = element("b", "month-number", String(day));
    cell.append(dayLabel);
    const entries = (facts.get(ordinal.toString()) || [])
      .filter((item) => !(item.continuation && durationMinutes(item.event) < dayMinutes));
    const zoneFact = applyZoneDay(context, cell, entries, dayLabel);
    if (detailed) {
      for (const fact of entries.filter((item) => item !== zoneFact).slice(0, 4)) cell.append(eventChip(context, fact, true));
    } else {
      const pips = element("div", "event-pips");
      for (const fact of entries.slice(0, 8)) {
        const pip = element("button", "event-pip");
        pip.type = "button";
        bindFact(pip, fact);
        applySigil(pip, fact, context);
        pip.style.background = factColor(context, fact);
        pip.title = fact.event.payload?.title || "(untitled)";
        pips.append(pip);
      }
      cell.append(pips);
    }
    grid.append(cell);
  }
  card.append(grid);
  return card;
}

function fixedMonthCard(context, frame, start, span, facts, detailed = false) {
  const definition = fixedCalendarDefinition(frame);
  const first = fixedCalendarParts(frame, start);
  if (!definition || !first) return null;
  const card = element("section", detailed ? "wall-month fixed-month" : "strategic-month fixed-month");
  const monthPart = first.parts[1];
  const dayUnit = definition.units.at(-1);
  const columns = Number(definition.radices.at(-1));
  card.style.setProperty("--calendar-columns", String(columns));
  card.style.setProperty("--calendar-rows", String(Math.ceil(Number(span) / columns)));
  const heading = element("header", "month-heading");
  heading.append(
    element("strong", "", monthPart.label || `${monthPart.name} ${monthPart.value}`),
    element("span", "", `${first.parts[0].name} ${first.parts[0].value}`)
  );
  card.append(heading);
  const headers = element("div", "month-weekdays");
  headers.style.setProperty("--calendar-columns", String(columns));
  for (let index = 0; index < columns; index += 1) {
    headers.append(element("span", "", dayUnit.labels?.[index] || `${dayUnit.name} ${index + 1}`));
  }
  card.append(headers);
  const grid = element("div", "month-days");
  grid.style.setProperty("--calendar-columns", String(columns));
  grid.style.setProperty("--calendar-rows", String(Math.ceil(Number(span) / columns)));
  const today = daysFromCivil(BigInt(new Date().getFullYear()), BigInt(new Date().getMonth() + 1), BigInt(new Date().getDate()));
  for (let offset = 0n; offset < span; offset += 1n) {
    const ordinal = start + offset;
    const parts = fixedCalendarParts(frame, ordinal)?.parts || [];
    const cell = element("div", "month-day");
    if (context.session.wallRecordSlashes && ordinal < today) cell.classList.add("record-slash");
    cell.dataset.createDay = ordinal.toString();
    const dayLabel = element("b", "month-number", parts.at(-1)?.label || parts.at(-1)?.value?.toString() || String(offset + 1n));
    cell.append(dayLabel);
    const entries = (facts.get(ordinal.toString()) || []).filter((item) => !(item.continuation && durationMinutes(item.event) < minutesPerDayNumber()));
    const zoneFact = applyZoneDay(context, cell, entries, dayLabel);
    if (detailed) {
      for (const fact of entries.filter((item) => item !== zoneFact).slice(0, 4)) cell.append(eventChip(context, fact, true));
    } else {
      const pips = element("div", "event-pips");
      for (const fact of entries.slice(0, 8)) {
        const pip = element("button", "event-pip");
        pip.type = "button";
        bindFact(pip, fact);
        applySigil(pip, fact, context);
        pip.style.background = factColor(context, fact);
        pip.title = fact.event.payload?.title || "(untitled)";
        pips.append(pip);
      }
      cell.append(pips);
    }
    grid.append(cell);
  }
  card.append(grid);
  return card;
}

function renderFixedCalendarMonths(target, context, detailed) {
  const frame = context.document.frames[context.session.activeFrame];
  const count = detailed ? context.session.wallMonths : context.session.strategicMonths;
  const months = fixedMonthWindow(frame, context.session.currentFocus(), count);
  if (!months) return false;
  const start = months[0].start;
  const after = months.at(-1).start + months.at(-1).span;
  const result = queryFacts(context, context.session.activeFrame, new Rational(start), new Rational(after), 800);
  const byDay = factsByDay(result.facts, start, after);
  const container = element("div", detailed ? "wall-grid fixed-calendar-grid" : "wall-grid fixed-calendar-grid strategic-fixed-grid");
  container.dataset.scrollKey = detailed ? "wall" : "strategic";
  container.style.setProperty("--wall-columns", String(Math.min(count, count <= 2 ? count : 3)));
  for (const month of months) container.append(fixedMonthCard(context, frame, month.start, month.span, byDay, detailed));
  target.append(container);
  renderErrors(target, result);
  return true;
}

function renderStrategic(target, context) {
  if (renderFixedCalendarMonths(target, context, false)) return;
  const focusCivil = civilFromDays(context.session.currentFocus().floor());
  const monthCount = context.session.strategicMonths;
  const firstMonth = addMonths(focusCivil.year, focusCivil.month, -Math.floor(monthCount / 2));
  const lastMonth = addMonths(firstMonth.year, firstMonth.month, monthCount);
  const start = daysFromCivil(firstMonth.year, firstMonth.month, 1n);
  const end = daysFromCivil(lastMonth.year, lastMonth.month, 1n);
  const result = queryStrategicFacts(context, context.session.activeFrame, start, end);
  const byDay = result.density
    ? new Map(result.density.days.map((entry) => [
      entry.day,
      factsByDay(entry.facts, BigInt(entry.day), BigInt(entry.day) + 1n).get(entry.day) || []
    ]))
    : factsByDay(result.facts, start, end);
  const densityByDay = new Map((result.density?.days || []).map((entry) => [entry.day, entry]));
  if (result.density) {
    const notice = element(
      "div",
      "strategic-density-notice",
      `Dense view · each day shows up to ${result.density.perDayLimit} events; ${result.density.perDayLimit}+ marks a lower bound.`
    );
    notice.dataset.density = "aggregated";
    target.append(notice);
  }
  const path = element("div", "strategic-path");
  path.dataset.scrollKey = "strategic";
  path.style.setProperty("--strategic-months", String(monthCount));
  const now = new Date();
  const today = daysFromCivil(BigInt(now.getFullYear()), BigInt(now.getMonth() + 1), BigInt(now.getDate()));
  const dayMinutes = minutesPerDayNumber();
  for (let index = 0; index < monthCount; index += 1) {
    const current = addMonths(firstMonth.year, firstMonth.month, index);
    const row = element("section", "strategic-row");
    const label = element("header", "strategic-label", monthShortName(current.month));
    label.append(element("small", "", current.year.toString()));
    row.append(label);
    const monthLength = daysInMonth(current.year, current.month);
    for (let day = 1; day <= 31; day += 1) {
      if (day > monthLength) {
        row.append(element("div", "strategic-day pad"));
        continue;
      }
      const ordinal = daysFromCivil(current.year, current.month, BigInt(day));
      const weekday = activeLaw.cycleIndex("weekday", ordinal);
      const classes = ["strategic-day"];
      if (weekday === 0 || weekday === 6) classes.push("weekend");
      if (ordinal < today) classes.push("past");
      if (ordinal === today) classes.push("today");
      if (context.session.strategicRecordSlashes && ordinal < today) classes.push("record-slash");
      const cell = element("div", classes.join(" "));
      cell.dataset.createDay = ordinal.toString();
      cell.append(element("div", "strategic-day-number", `${day} ${activeLaw.weekdayLabel(ordinal).slice(0, 1)}`));
      const facts = (byDay.get(ordinal.toString()) || [])
        .filter((item) => !(item.continuation && durationMinutes(item.event) < dayMinutes));
      const zoneFact = applyZoneDay(context, cell, facts, cell.firstElementChild);
      const presented = facts.map((fact) => ({ fact, mode: strategicPresentation(context, fact) }))
        .filter((item) => item.mode !== "none" && item.fact !== zoneFact);
      const named = presented.filter((item) => item.mode === "name");
      const pipFacts = presented.filter((item) => item.mode === "pip");
      for (const item of named.slice(0, 3)) cell.append(eventChip(context, item.fact, true));
      if (pipFacts.length) {
        const pips = element("div", "event-pips");
        for (const { fact } of pipFacts.slice(0, 8)) {
          const pip = element("button", "event-pip");
          pip.type = "button";
          bindFact(pip, fact);
          applySigil(pip, fact, context);
          pip.style.background = factColor(context, fact);
          pip.title = fact.event.payload?.title || "(untitled)";
          pips.append(pip);
        }
        cell.append(pips);
      }
      const density = densityByDay.get(ordinal.toString());
      if (density?.truncated) {
        const overflow = element("div", "strategic-density-count", `${density.shown}+`);
        overflow.title = `At least ${density.minimum} events on this day; the Strategic view shows its first ${density.shown} stable events.`;
        cell.append(overflow);
      }
      row.append(cell);
    }
    path.append(row);
  }
  target.append(path);
  renderErrors(target, result);
}

function renderCalendar(target, context) {
  if (context.session.scale < 0.55) renderIntimate(target, context);
  else if (context.session.scale < 1.45) renderTactical(target, context);
  else renderStrategic(target, context);
}

function renderWall(target, context) {
  if (renderFixedCalendarMonths(target, context, true)) return;
  const focus = civilFromDays(context.session.currentFocus().floor());
  const count = context.session.wallMonths;
  const firstMonth = addMonths(focus.year, focus.month, -Math.floor(count / 2));
  const after = addMonths(firstMonth.year, firstMonth.month, count);
  const start = daysFromCivil(firstMonth.year, firstMonth.month, 1n);
  const end = daysFromCivil(after.year, after.month, 1n);
  const result = queryFacts(context, context.session.activeFrame, new Rational(start), new Rational(end), 800);
  const byDay = factsByDay(result.facts, start, end);
  const grid = element("div", "wall-grid");
  grid.dataset.scrollKey = "wall";
  grid.style.setProperty("--wall-columns", String(Math.min(count, count <= 2 ? count : 3)));
  for (let index = 0; index < count; index += 1) {
    const current = addMonths(firstMonth.year, firstMonth.month, index);
    grid.append(monthCard(context, current.year, current.month, byDay, context.session.wallDetail));
  }
  target.append(grid);
  renderErrors(target, result);
}

function renderSimpleLines(target, context) {
  const window = context.session.window();
  const width = 1200;
  const height = 620;
  const primeY = height / 2;
  const xFor = (day) => 145 + lineProgress(day, window.start, window.end) * 995;
  // A selected state frame is not an unsupported companion -- it is not a
  // companion here at all: its selection governs the ToDo lenses' population
  // and claims nothing about this axis.
  const plan = lineFramePlan(
    context.document,
    context.session.activeFrame,
    context.session.companionFrames.filter((id) => !isStateFrame(context.document.frames[id]))
  );
  if (plan.topology) {
    renderTopologyLines(target, context, plan.topology);
    return;
  }
  const prime = plan.leading;
  const secondaryFrames = plan.companions;
  // `frame` varies per call (the prime frame, then each secondary), and a
  // secondary's coordinates are never reinterpreted under another frame's law
  // (AGENTS.md's frame model) -- so the window is resolved under THAT frame's
  // own law, not one shared standard-civil coordinate.
  const directQuery = (frame, limit) => context.engine.queryFacts({
    frame: frame.id,
    start: coordinateLaw(context.document, frame.id).fromDays(window.start),
    end: coordinateLaw(context.document, frame.id).fromDays(window.end),
    includeOverlaps: true,
    limit
  });
  const svg = svgElement("svg", {
    class: "lines-svg", viewBox: `0 0 ${width} ${height}`, role: "img",
    "aria-label": "Prime frame with related frames entering and leaving at staple points"
  });
  svg.dataset.dropStart = window.start.toJSON();
  svg.dataset.dropEnd = window.end.toJSON();
  svg.dataset.dropKind = "linear";
  const appendState = (state, message) => {
    svg.dataset.linesState = state;
    const label = svgElement("text", {
      x: width / 2, y: height / 2 + 5, "text-anchor": "middle", class: `lines-state lines-state-${state}`
    });
    label.textContent = message;
    svg.append(label);
    target.append(svg);
  };
  if (context.loading) {
    appendState(linesRenderState({ loading: true }), "Loading timeline data…");
    return;
  }
  if (!plan.supported) {
    appendState(linesRenderState({ supported: false }), "Lines requires an active calendar frame");
    return;
  }
  const primeResult = directQuery(prime, 260);
  const secondary = secondaryFrames.map((frame) => ({ frame, result: directQuery(frame, 140) }));
  for (let index = 0; index < 8; index += 1) {
    const progress = index / 7;
    const x = 145 + progress * 995;
    const day = window.start.add(window.end.sub(window.start).mul(String(progress)));
    svg.append(svgElement("line", { x1: x, y1: 52, x2: x, y2: 565, class: "line-tick" }));
    const label = svgElement("text", { x, y: 594, "text-anchor": index ? "middle" : "start", class: "minimap-label" });
    // A fixed calendar is an explicit mapping and gets its own units.  For
    // every other calendar retain the historical civil label rather than
    // claiming that an arbitrary frame has Gregorian fields.
    label.textContent = fixedDayLabel(prime, day, true)
      || formatCivil(daysToCivilCoordinate(day)).replace(/ 00:00:00$/, "");
    svg.append(label);
  }
  svg.append(svgElement("path", {
    d: `M 145 ${primeY} L 1140 ${primeY}`, fill: "none",
    stroke: prime?.color || "#d4552d", "stroke-width": 6, "stroke-linecap": "round"
  }));
  const primeLabel = svgElement("text", { x: 24, y: primeY + 5, class: "line-label", fill: prime?.color || "#d4552d" });
  primeLabel.textContent = `Prime · ${prime?.title || "Calendar"}`;
  svg.append(primeLabel);
  const primeEvents = new Set(primeResult.facts.map((fact) => fact.event.id));
  const primePoints = aggregateLinePoints(primeResult.facts.map((fact) => ({
    id: fact.virtualId || fact.event.id, eventId: fact.event.id, fact, x: lineProgress(fact.day, window.start, window.end)
  })).filter((point) => point.x >= 0 && point.x <= 1));
  for (const point of primePoints) {
    const { fact } = point;
    const x = 145 + point.x * 995;
    if (x < 145 || x > 1140) continue;
    const y = primeY + point.offset;
    const dot = svgElement("circle", { cx: x, cy: y, r: point.clusterSize > 1 ? 5 : 4.5, fill: factColor(context, fact), class: "line-event", tabindex: 0 });
    bindFact(dot, fact);
    applySigil(dot, fact, context);
    const title = svgElement("title");
    title.textContent = `${fact.event.payload?.title || "(untitled)"}${point.clusterSize > 1 ? ` · ${point.clusterSize} nearby events` : ""}`;
    dot.append(title);
    if (point.offset) svg.append(svgElement("line", { x1: x, y1: primeY, x2: x, y2: y, stroke: factColor(context, fact), "stroke-width": 1.2 }));
    svg.append(dot);
  }
  secondary.forEach(({ frame, result }, index) => {
    const xs = result.facts.map((fact) => xFor(fact.day)).filter((x) => x >= 145 && x <= 1140);
    const firstX = xs.length ? Math.max(145, Math.min(...xs) - 24) : 145;
    const lastX = xs.length ? Math.min(1140, Math.max(...xs) + 24) : 1140;
    const apexY = primeY + (index % 2 ? 1 : -1) * (75 + Math.floor(index / 2) * 52);
    const middleX = (firstX + lastX) / 2;
    const path = `M ${firstX} ${primeY} C ${firstX + 35} ${primeY}, ${firstX + 35} ${apexY}, ${middleX} ${apexY} C ${lastX - 35} ${apexY}, ${lastX - 35} ${primeY}, ${lastX} ${primeY}`;
    svg.append(svgElement("path", { d: path, fill: "none", stroke: frame.color || "#497bc1", "stroke-width": 3.5, "stroke-linecap": "round" }));
    const label = svgElement("text", { x: middleX, y: apexY - 9, "text-anchor": "middle", class: "line-label", fill: frame.color || "#497bc1" });
    label.textContent = frame.title;
    svg.append(label);
    const points = aggregateLinePoints(result.facts.map((fact) => ({
      id: fact.virtualId || fact.event.id, eventId: fact.event.id, fact, x: lineProgress(fact.day, window.start, window.end)
    })).filter((point) => point.x >= 0 && point.x <= 1));
    for (const point of points) {
      const { fact } = point;
      const x = 145 + point.x * 995;
      if (x < firstX || x > lastX) continue;
      const p = lastX === firstX ? 0.5 : (x - firstX) / (lastX - firstX);
      const y = primeY + (apexY - primeY) * Math.sin(Math.PI * p) + point.offset;
      const shared = primeEvents.has(fact.event.id);
      if (shared) svg.append(svgElement("line", { x1: x, y1: primeY, x2: x, y2: y, stroke: "#51483d", "stroke-width": 1.5, "stroke-dasharray": "3 3" }));
      const dot = svgElement("circle", { cx: x, cy: y, r: shared ? 7 : 4.5, fill: frame.color || "#497bc1", stroke: shared ? "#2a2620" : "none", "stroke-width": 2, class: "line-event", tabindex: 0 });
      bindFact(dot, fact);
      applySigil(dot, fact, context);
      const title = svgElement("title");
      title.textContent = `${fact.event.payload?.title || "(untitled)"}${shared ? " · staple" : ""}${point.clusterSize > 1 ? ` · ${point.clusterSize} nearby events` : ""}`;
      dot.append(title);
      svg.append(dot);
    }
  });
  const results = [primeResult, ...secondary.map((item) => item.result)];
  const errors = results.flatMap((result) => result.errors || []);
  const factCount = results.reduce((total, result) => total + result.facts.length, 0);
  const truncated = results.some((result) => result.truncated);
  const state = linesRenderState({ factCount, errorCount: errors.length, truncated });
  svg.dataset.linesState = state;
  if (state !== "ordinary") {
    const status = svgElement("text", {
      x: width / 2, y: height - 15, "text-anchor": "middle", class: `lines-state lines-state-${state}`
    });
    status.textContent = state === "empty" ? "No events in this window"
      : state === "dense" ? "Dense window · some events are not shown"
      : "Some timeline data could not be rendered";
    svg.append(status);
  }
  if (plan.unsupportedCompanions.length) {
    const unsupported = svgElement("text", {
      x: width - 60, y: 30, "text-anchor": "end", class: "lines-state lines-state-unsupported"
    });
    unsupported.textContent = `${plan.unsupportedCompanions.length} unsupported companion selection${plan.unsupportedCompanions.length === 1 ? "" : "s"}`;
    svg.append(unsupported);
  }
  target.append(svg);
  renderErrors(target, {
    errors,
    truncated
  });
}

function renderTopologyLines(target, context, topology) {
  const width = 1200; const height = 620; const left = 180; const right = 1120;
  const svg = svgElement("svg", { class: "lines-svg", viewBox: `0 0 ${width} ${height}`, role: "img", "aria-label": "Authored frame topology" });
  const frames = topology.frames;
  const rowY = (index) => frames.length <= 1 ? height / 2 : 85 + index * ((height - 170) / (frames.length - 1));
  const lane = new Map(frames.map((frame, index) => [frame.id, rowY(index)]));
  const events = new Map();
  for (const attachment of topology.attachments) {
    const list = events.get(attachment.event) || []; list.push(attachment); events.set(attachment.event, list);
  }
  const orderedEvents = [...events.entries()].sort(([leftId], [rightId]) => leftId.localeCompare(rightId));
  const xForEvent = new Map(orderedEvents.map(([id], index) => [id, left + (index + 1) * (right - left) / (orderedEvents.length + 1)]));
  frames.forEach((frame, index) => {
    const y = rowY(index); const color = frame.color || (index === 0 ? "#d4552d" : "#497bc1");
    svg.append(svgElement("path", { d: `M ${left} ${y} L ${right} ${y}`, fill: "none", stroke: color, "stroke-width": index === 0 ? 5 : 3, "stroke-linecap": "round" }));
    const label = svgElement("text", { x: 24, y: y + 5, fill: color, class: "line-label" });
    label.textContent = `${index === 0 ? "Prime · " : ""}${frame.title} · unmapped units`; svg.append(label);
  });
  for (const relation of topology.links) {
    if (relation.type === "shared-segment") {
      const first = relation.lines?.find((id) => lane.has(id)); const second = relation.lines?.find((id) => id !== first && lane.has(id));
      const start = context.document.relations?.[relation.anchors?.[first]?.start]?.event;
      const end = context.document.relations?.[relation.anchors?.[first]?.end]?.event;
      if (first && second && start && end && xForEvent.has(start) && xForEvent.has(end)) {
        svg.append(svgElement("path", { d: `M ${xForEvent.get(start)} ${lane.get(first)} C ${(xForEvent.get(start) + xForEvent.get(end)) / 2} ${lane.get(first)}, ${(xForEvent.get(start) + xForEvent.get(end)) / 2} ${lane.get(second)}, ${xForEvent.get(end)} ${lane.get(second)}`, fill: "none", stroke: "#51483d", "stroke-width": 2, "stroke-dasharray": "5 4" }));
      }
    } else {
      const origin = context.document.relations?.[relation.origin?.world]?.event || context.document.relations?.[relation.origin?.traveler]?.event;
      const destination = context.document.relations?.[relation.destination?.world]?.event || context.document.relations?.[relation.destination?.traveler]?.event;
      if (origin && destination && xForEvent.has(origin) && xForEvent.has(destination)) svg.append(svgElement("path", { d: `M ${xForEvent.get(origin)} ${lane.get(relation.world) || height / 2} Q ${(xForEvent.get(origin) + xForEvent.get(destination)) / 2} 44 ${xForEvent.get(destination)} ${lane.get(relation.world) || height / 2}`, fill: "none", stroke: "#a46b12", "stroke-width": 2, "marker-end": "url(#lines-arrow)" }));
    }
  }
  const defs = svgElement("defs"); const marker = svgElement("marker", { id: "lines-arrow", markerWidth: 8, markerHeight: 8, refX: 7, refY: 4, orient: "auto" }); marker.append(svgElement("path", { d: "M 0 0 L 8 4 L 0 8 z", fill: "#a46b12" })); defs.append(marker); svg.prepend(defs);
  for (const [eventId, attachments] of orderedEvents) {
    const positions = aggregateLinePoints(attachments.map((attachment) => ({ id: attachment.id, eventId, attachment, x: 0.5 })), { pixelSpan: 1, clusterPixels: 0 });
    for (const point of positions) {
      const fact = { event: context.document.events[eventId], relation: point.attachment, coordinate: point.attachment.coordinate };
      const dot = svgElement("circle", { cx: xForEvent.get(eventId), cy: lane.get(point.attachment.frame) + point.offset, r: 6, fill: factColor(context, fact), class: "line-event", tabindex: 0 });
      bindFact(dot, fact); applySigil(dot, fact, context); const title = svgElement("title"); title.textContent = `${sigilDescription(fact, durationMinutes(fact.event), factRenderImportance(context, fact), minutesPerDayNumber())} · ${fact.event?.payload?.title || eventId} · authored incidence`; dot.append(title); svg.append(dot);
    }
  }
  const status = svgElement("text", { x: width / 2, y: height - 18, "text-anchor": "middle", class: "lines-state" });
  status.textContent = orderedEvents.length ? "Topology shown from authored incidences; no cross-frame coordinate mapping inferred." : "No authored topology incidences."; svg.append(status);
  svg.dataset.linesState = orderedEvents.length ? "ordinary" : "empty"; target.append(svg);
}

// An event mark is a point-in-time indicator, not a boundary that has to
// read flush: it keeps a round cap in both radial-family lenses (Radial's
// ring arcs and the Spiral's own event arcs), deliberately, in every lens
// that uses this helper. That is a different question from whether the
// mark's own path sits exactly where it should -- Radial's arcPath is a
// constant-radius circular arc (tangent exactly perpendicular to its own
// radius, so the mark's long axis reads as sitting square on the radius it
// occupies) and the Spiral event loop in renderRadial deliberately mirrors
// that (a constant-radius arcPath at the event's own midpoint radius) rather
// than tracking the spiral's own radial growth across the event's span --
// see the comment there. Neither path construction has anything to do with
// this cap.
//
// The track (the timeline's own spiral ribbon, or a Radial ring's backing
// circle) is the opposite case: its own start/stop termini must read flush,
// which is a geometry question (see spiralRibbonPath in src/radial.js), not
// a cap question. Conflating the two -- giving the TRACK's terminus a cap
// decision, or giving an EVENT mark the track's flush-terminus treatment --
// is exactly the bug this class of comment exists to prevent.
//
// So this renderer deliberately sets NO stroke-linecap of its own. The cap
// is decided once, in `.radial-event-arc` in app.css (`round`). Note the
// sibling paths in this file (Lines, the radial guide rings) do set
// "stroke-linecap" as an attribute for their own reasons -- do not copy that
// here: an author style or attribute here would silently outrank the
// stylesheet and make that CSS rule a dead letter.
function radialEventPath(context, fact, attributes) {
  const path = svgElement("path", {
    class: "radial-event-arc",
    tabindex: 0,
    pathLength: 1,
    ...attributes
  });
  bindFact(path, fact);
  const sigil = applySigil(path, fact, context);
  path.classList.add(`sigil-${sigil}`);
  const title = svgElement("title");
  title.textContent = `${sigilDescription(fact, durationMinutes(fact.event), factRenderImportance(context, fact), minutesPerDayNumber())} · ${fact.event.payload?.title || "(untitled)"}`;
  path.append(title);
  return path;
}

function radialEventLabel(layer, fact, x, y, labels, anchor = "start") {
  const title = fact.event.payload?.title || "(untitled)";
  if (labels.some((point) => point.title === title
    || (Math.abs(point.y - y) < 15 && Math.abs(point.x - x) < 145))) return;
  labels.push({ x, y, title });
  const label = svgElement("text", { x, y, "text-anchor": anchor, class: "radial-event-label" });
  label.textContent = title.length > 30 ? `${title.slice(0, 29)}…` : title;
  layer.append(label);
}

function radialNowLine(svg, start, end, turns = 1) {
  // Owner's field note: "no artificial Now line on a calendar with no
  // now-mapping." A law that does not place its coordinates on the running
  // clock has no "now" to mark, so the whole line is withheld rather than
  // drawn at a guessed position.
  if (!activeLaw.mapsToClock()) return;
  const now = nowDays();
  if (now.compare(start) < 0 || now.compare(end) > 0) return;
  const progress = now.sub(start).div(end.sub(start)).toNumber();
  const angle = -Math.PI / 2 + progress * turns * Math.PI * 2;
  const [x1, y1] = polar(450, 360, 58, angle);
  const [x2, y2] = polar(450, 360, 326, angle);
  svg.append(svgElement("line", { x1, y1, x2, y2, class: "radial-now-line" }));
}

function renderRadial(target, context) {
  const { session } = context;
  const width = 900;
  const height = 720;
  const cx = 450;
  const cy = 360;
  const resolution = session.radialResolution;
  const unsupported = resolution?.unsupported;
  const cycle = resolution?.period || session.radialCycle;
  const dynamicWindow = resolution?.dynamic
    ? radialCycleWindow(resolution, session.radialMode === "spiral" ? session.radialPast : 0, session.radialMode === "spiral" ? session.radialFuture : 0)
    : null;
  const start = dynamicWindow
    ? dynamicWindow.start
    : session.radialMode === "spiral"
      ? session.currentFocus().sub(cycle.mul(session.radialPast + 0.5))
      : session.currentFocus().sub(cycle.div(2));
  const end = dynamicWindow
    ? dynamicWindow.end
    : session.radialMode === "spiral"
      ? session.currentFocus().add(cycle.mul(session.radialFuture + 0.5))
      : session.currentFocus().add(cycle.div(2));
  const radialLabels = [];
  const labelLayer = svgElement("g", { class: "radial-label-layer" });
  const svg = svgElement("svg", {
    class: "radial-svg",
    viewBox: `0 0 ${width} ${height}`,
    role: "img",
    "aria-label": `${session.radialMode} cycle calendar`
  });
  svg.dataset.dropStart = start.toJSON();
  svg.dataset.dropEnd = end.toJSON();
  svg.dataset.dropKind = "radial";
  svg.dataset.radialMode = session.radialMode;
  if (unsupported) svg.dataset.radialState = "unsupported";
  svg.append(svgElement("circle", {
    cx, cy, r: 54, fill: "#f5efe2", stroke: "#bdb19e", "stroke-width": 2
  }));
  const centerLabel = svgElement("text", {
    x: cx, y: cy + 4, "text-anchor": "middle", class: "radial-center"
  });
  centerLabel.textContent = formatCivil(session.focusCoordinate());
  svg.append(centerLabel);
  if (unsupported) {
    const status = svgElement("text", {
      x: cx, y: cy + 30, "text-anchor": "middle", class: "radial-state-label"
    });
    status.textContent = "Cycle boundaries are not defined by this document";
    svg.append(status);
    target.append(svg);
    return;
  }
  const result = queryFacts(context, session.activeFrame, start, end, 350);
  const renderState = radialRenderState(result.facts.length, result.truncated);
  svg.dataset.radialState = renderState;
  const guide = radialGuideSettings(session);
  for (let tick = 0; tick < guide.divisions; tick += 1) {
    const angle = -Math.PI / 2 + tick / guide.divisions * Math.PI * 2;
    const [x1, y1] = polar(cx, cy, 62, angle);
    const [x2, y2] = polar(cx, cy, 326, angle);
    const major = tick % guide.majorEvery === 0;
    svg.append(svgElement("line", {
      x1, y1, x2, y2,
      class: major ? "radial-time-line major midnight" : "radial-time-line midnight"
    }));
    if (guide.dayNight) {
      const noonAngle = -Math.PI / 2 + (tick + 0.5) / guide.divisions * Math.PI * 2;
      const [noonX1, noonY1] = polar(cx, cy, 310, noonAngle);
      const [noonX2, noonY2] = polar(cx, cy, 326, noonAngle);
      svg.append(svgElement("line", { x1: noonX1, y1: noonY1, x2: noonX2, y2: noonY2, class: "radial-noon-tick" }));
    }
    if (major) {
      const [labelX, labelY] = polar(cx, cy, 338, angle);
      const elapsedDays = guide.cycleDays * tick / guide.divisions;
      const denomination = elapsedDays === 0
        ? "cycle start"
        : guide.cycleDays >= 20 && guide.majorEvery === 7 ? `Week ${Math.round(tick / 7)}`
        : elapsedDays < 1 ? `+${(elapsedDays * hoursPerDayNumber()).toFixed(1)}h` : `+${elapsedDays.toFixed(1)}d`;
      const tickLabel = svgElement("text", {
        x: labelX, y: labelY + 3,
        "text-anchor": "middle",
        class: "radial-time-label"
      });
      tickLabel.textContent = denomination;
      svg.append(tickLabel);
    }
  }

  if (session.radialMode === "spiral") {
    const turns = session.radialPast + session.radialFuture + 1;
    const inner = 82;
    const spacing = Math.min(78, 252 / Math.max(turns, 1));
    svg.dataset.radialTurns = String(turns);
    svg.dataset.radialInner = String(inner);
    svg.dataset.radialSpacing = String(spacing);
    const samples = Math.max(180, turns * 120);
    const backingColor = context.document.frames[session.activeFrame]?.color || "#84735d";
    // The track (this timeline's own spiral ribbon) is a filled polygon, not
    // a stroked open path with a linecap -- see spiralRibbonPath's doc
    // comment for why only a radius-offset polygon lands flush on the
    // vertical ray both ends terminate on, exactly, regardless of the
    // spiral's pitch. Event marks are the opposite case (radialEventPath
    // below): they keep round caps deliberately.
    svg.append(svgElement("path", {
      d: spiralRibbonPath(cx, cy, inner, spacing, turns, samples, Math.max(34, spacing * 0.9) / 2),
      fill: backingColor, opacity: 0.16
    }));
    svg.append(svgElement("path", {
      d: spiralRibbonPath(cx, cy, inner, spacing, turns, samples, 0.7),
      fill: backingColor, opacity: 0.28
    }));
    radialNowLine(svg, start, end, turns);
    const items = result.facts.map((fact) => {
      const progress = Rational.parse(fact.day).sub(start).div(end.sub(start)).toNumber();
      const duration = Math.max(durationMinutes(fact.event) / minutesPerDayNumber() / end.sub(start).toNumber(), 0.0025);
      return { fact, progress, end: Math.min(1, progress + duration), lane: 0 };
    }).filter((item) => item.progress >= 0 && item.progress < 1)
      .sort((left, right) => left.progress - right.progress);
    const laneEnds = [];
    for (const item of items) {
      let lane = laneEnds.findIndex((laneEnd) => laneEnd <= item.progress);
      if (lane < 0) lane = laneEnds.length < 5 ? laneEnds.length : laneEnds.indexOf(Math.min(...laneEnds));
      item.lane = lane;
      laneEnds[lane] = item.end;
    }
    const laneCount = Math.max(1, laneEnds.length);
    const availableBand = Math.max(7, spacing - 8);
    const laneStep = availableBand / laneCount;
    for (const item of items) {
      const { fact, progress: startProgress, end: endProgress } = item;
      const laneOffset = (item.lane - (laneCount - 1) / 2) * laneStep;
      // An event mark's own long axis sits perpendicular to the radius it
      // occupies, exactly like a Radial-ring event's arcPath -- a circle's
      // tangent is exactly perpendicular to its own radius everywhere (see
      // radial-stability.test.js), which a mixed radial+angular path
      // following the spiral's own pitch is not. So the mark is drawn as a
      // constant-radius arc at its own midpoint progress -- the same radius
      // its label already anchors to below -- rather than tracking the
      // spiral's growth across its own span. A duration long enough to carry
      // its own span across a meaningful fraction of a turn will render as a
      // single arc at that one representative radius rather than a true
      // multi-turn spiral; ordinary calendar events are far shorter than a
      // full turn, so this is the shape that actually reads as "sitting on"
      // one point of the ribbon rather than skewed across it.
      const midProgress = (startProgress + endProgress) / 2;
      const radius = inner + midProgress * turns * spacing + laneOffset;
      const startAngle = -Math.PI / 2 + startProgress * turns * Math.PI * 2;
      const endAngle = -Math.PI / 2 + endProgress * turns * Math.PI * 2;
      svg.append(radialEventPath(context, fact, {
        d: arcPath(cx, cy, radius, startAngle, endAngle),
        stroke: factColor(context, fact),
        "stroke-width": durationMinutes(fact.event)
          ? Math.min(factRenderImportance(context, fact) === "landmark" ? 11 : 8, Math.max(3, laneStep * 0.72))
          : 4
      }));
      if (session.radialLabels && radialLabels.length < 24) {
        const [x, y] = polar(cx, cy, radius + 8, (startAngle + endAngle) / 2);
        radialEventLabel(labelLayer, fact, x, y, radialLabels, Math.cos((startAngle + endAngle) / 2) < 0 ? "end" : "start");
      }
    }
  } else {
    radialNowLine(svg, start, end);
    const bandMap = new Map();
    for (const fact of result.facts) {
      const templateEvent = context.document.patterns[fact.event.provenance?.pattern]?.templateEvent;
      const frameId = context.engine.eventCalendarFrame(fact.event.id)
        || (templateEvent ? context.engine.eventCalendarFrame(templateEvent) : null)
        || fact.displayFrame || fact.relation?.frame || session.activeFrame;
      const groupId = factGroupFrame(context, fact);
      const key = `${frameId}\u0000${groupId || ""}`;
      const frame = context.document.frames[frameId];
      const group = context.document.frames[groupId];
      const band = bandMap.get(key) || {
        key, frameId, groupId,
        title: `${frame?.title || frameId} · ${group?.title || "Ungrouped"}`,
        color: group?.color || frame?.color || "#d4cab9",
        facts: []
      };
      band.facts.push(fact);
      bandMap.set(key, band);
    }
    const bands = [...bandMap.values()].sort((left, right) => left.title.localeCompare(right.title));
    const outer = 278;
    const spacing = Math.min(48, 210 / Math.max(1, bands.length));
    const ringRadius = (index) => outer - (bands.length - 1 - index) * spacing;
    if (bands.length === 0) {
      svg.append(svgElement("circle", {
        cx, cy, r: outer, fill: "none", class: "radial-empty-ring"
      }));
    }
    for (let ring = 0; ring < bands.length; ring += 1) {
      const radius = ringRadius(ring);
      svg.append(svgElement("circle", {
        cx, cy, r: radius, fill: "none",
        stroke: bands[ring].color,
        opacity: 0.16,
        "stroke-width": Math.max(8, spacing * 0.98)
      }));
      const label = svgElement("text", {
        x: cx,
        y: cy - radius - 5,
        "text-anchor": "middle",
        class: "minimap-label"
      });
      label.textContent = bands[ring].title;
      svg.append(label);
    }
    for (let ring = 0; ring < bands.length; ring += 1) {
      const band = bands[ring];
      const items = band.facts.map((fact) => {
        const progress = Math.max(0, Rational.parse(fact.day).sub(start).div(cycle).toNumber());
        const duration = Math.max(durationMinutes(fact.event) / minutesPerDayNumber() / cycle.toNumber(), 0.004);
        return { fact, progress, end: Math.min(0.9995, progress + duration), lane: 0 };
      }).filter((item) => item.progress < 0.9995)
        .sort((left, right) => left.progress - right.progress);
      const laneEnds = [];
      for (const item of items) {
        let lane = laneEnds.findIndex((laneEnd) => laneEnd <= item.progress);
        if (lane < 0) lane = laneEnds.length < 5 ? laneEnds.length : laneEnds.indexOf(Math.min(...laneEnds));
        item.lane = lane;
        laneEnds[lane] = item.end;
      }
      const laneCount = Math.max(1, laneEnds.length);
      const laneStep = Math.min(8, Math.max(3, spacing * 0.52 / laneCount));
      for (const item of items) {
        const radius = ringRadius(ring) + (item.lane - (laneCount - 1) / 2) * laneStep;
        const startAngle = -Math.PI / 2 + item.progress * Math.PI * 2;
        const endAngle = -Math.PI / 2 + item.end * Math.PI * 2;
        svg.append(radialEventPath(context, item.fact, {
          d: arcPath(cx, cy, radius, startAngle, endAngle),
          stroke: factColor(context, item.fact),
          "stroke-width": Math.max(factRenderImportance(context, item.fact) === "landmark" ? 5 : 3, laneStep * 0.72)
        }));
        if (session.radialLabels && radialLabels.length < 24) {
          const middle = (startAngle + endAngle) / 2;
          const [x, y] = polar(cx, cy, radius + 7, middle);
          radialEventLabel(labelLayer, item.fact, x, y, radialLabels, Math.cos(middle) < 0 ? "end" : "start");
        }
      }
    }
  }
  if (renderState !== "ordinary") {
    const status = svgElement("text", {
      x: cx, y: height - 24, "text-anchor": "middle", class: "radial-state-label"
    });
    status.textContent = renderState === "empty"
      ? "No events in this cycle"
      : "Dense window · showing the first 350 events";
    svg.append(status);
  }
  svg.append(labelLayer);
  target.append(svg);
  renderErrors(target, result);
}

// ---------------------------------------------------------------------------
// The ToDo lenses: List and Board
// ---------------------------------------------------------------------------

// Capture chrome, shared by both ToDo lenses the way the data layer is: it is
// the write path's surface (delegated to src/ui/todo-capture.js, committed
// through createQuickTodo in src/ui/transactions.js), not either lens's
// projection rules -- nothing about sections or columns passes through here.
// Quick enter is the pinned input; Tab opens the inline standard row (group,
// date, note) -- never a dock card. State lives on session.todoCapture
// (transient, never serialized) so a mid-typing re-render loses nothing.
function todoCaptureBar(context) {
  const capture = context.session.todoCapture || {};
  const bar = element("div", "todo-capture");
  const input = element("input", "todo-quick-input");
  input.type = "text";
  input.value = capture.text || "";
  input.placeholder = "New ToDo · #group @date > note";
  input.dataset.quickCapture = "true";
  input.setAttribute("aria-label", "Quick ToDo entry: Enter creates, Tab opens fields");
  bar.append(input);
  let focusTarget = capture.focus === "quick" ? input : null;
  if (capture.expanded) {
    const row = element("div", "todo-capture-fields");
    for (const field of ["group", "date", "note"]) {
      const label = element("label", "todo-capture-field");
      label.append(element("span", "", field));
      const fieldInput = element("input");
      fieldInput.type = "text";
      fieldInput.value = capture[field] || "";
      fieldInput.dataset.captureField = field;
      fieldInput.setAttribute("aria-label", `ToDo ${field}`);
      if (capture.focus === field) focusTarget = fieldInput;
      label.append(fieldInput);
      row.append(label);
    }
    bar.append(row);
  }
  // Renders replace the whole projection subtree, so the field that had the
  // caret is a fresh node every pass; the capture state names it, and the
  // renderer focuses it AFTER appending to the live tree -- focus on a
  // detached node is a silent no-op. A stub DOM has no focus() and skips it.
  return { bar, focusTarget };
}

function todoSectionMeta(section) {
  if (section.meta) return `${section.meta.open} open · ${section.meta.done} done`;
  return `${section.entries.length}`;
}

function todoListRow(context, entry) {
  const row = element("div", "todo-row");
  if (entry.state) row.dataset.todoState = entry.state;
  const check = element("input", "todo-check");
  check.type = "checkbox";
  check.checked = entry.state === "done";
  check.dataset.todoToggle = entry.id;
  check.setAttribute("aria-label", entry.state === "done" ? `Mark ${entry.title} not done` : `Mark ${entry.title} done`);
  const open = element("button", "todo-open");
  open.type = "button";
  open.dataset.eventId = entry.id;
  if (factMatchesSelection(activeSelection, { event: { id: entry.id } })) open.dataset.selected = "true";
  open.append(
    element("strong", "", entry.title),
    element("small", "", entry.anchored ? formatCivil(entry.coordinate, true) : "no staple yet")
  );
  row.append(check, open);
  return row;
}

// List: one column, narrow-first -- capture fast, check off, see the shape.
function renderList(target, context) {
  const wrap = element("div", "todo-list");
  wrap.dataset.scrollKey = "todo-list";
  const capture = todoCaptureBar(context);
  wrap.append(capture.bar);
  const plan = listSections(context.document, context.engine, {
    grouping: context.session.listGrouping,
    selectedFrames: context.session.selectedFrames()
  });
  for (const section of plan.sections) {
    const node = element("section", "todo-section");
    node.dataset.sectionKey = section.key === null ? "" : section.key;
    const header = element("header", "todo-section-title");
    header.append(element("strong", "", section.title), element("small", "", todoSectionMeta(section)));
    node.append(header);
    for (const entry of section.entries) node.append(todoListRow(context, entry));
    wrap.append(node);
  }
  if (!plan.sections.length) {
    wrap.append(element("p", "todo-empty", "Nothing to do. Type above to capture."));
  }
  target.append(wrap);
  capture.focusTarget?.focus?.();
}

// The Board's own card builder -- deliberately not the List's row builder,
// per the lens-independence ruling; only the data layer is shared.
function todoBoardCard(context, entry) {
  const card = element("div", "todo-card");
  if (entry.state) card.dataset.todoState = entry.state;
  const check = element("input", "todo-check");
  check.type = "checkbox";
  check.checked = entry.state === "done";
  check.dataset.todoToggle = entry.id;
  check.setAttribute("aria-label", entry.state === "done" ? `Mark ${entry.title} not done` : `Mark ${entry.title} done`);
  const open = element("button", "todo-open");
  open.type = "button";
  open.dataset.eventId = entry.id;
  if (factMatchesSelection(activeSelection, { event: { id: entry.id } })) open.dataset.selected = "true";
  open.append(
    element("strong", "", entry.title),
    element("small", "", entry.anchored ? formatCivil(entry.coordinate, true) : "no staple yet")
  );
  card.append(check, open);
  return card;
}

// Board: columns are the grouping. Columns scroll horizontally at narrow
// width; an empty group renders no column at all -- boardColumns never emits
// one, so a phone is never spent on full-width nothing.
function renderBoard(target, context) {
  const wrap = element("div", "todo-board-wrap");
  wrap.dataset.scrollKey = "todo-board";
  const capture = todoCaptureBar(context);
  wrap.append(capture.bar);
  const plan = boardColumns(context.document, context.engine, {
    grouping: context.session.boardGrouping,
    selectedFrames: context.session.selectedFrames()
  });
  const board = element("div", "todo-board");
  for (const column of plan.columns) {
    const node = element("section", "todo-column");
    node.dataset.columnKey = column.key === null ? "" : column.key;
    const header = element("header", "todo-column-title");
    header.append(element("strong", "", column.title), element("small", "", todoSectionMeta(column)));
    node.append(header);
    for (const entry of column.entries) node.append(todoBoardCard(context, entry));
    board.append(node);
  }
  if (!plan.columns.length) {
    board.append(element("p", "todo-empty", "Nothing to do. Type above to capture."));
  }
  wrap.append(board);
  target.append(wrap);
  capture.focusTarget?.focus?.();
}

export function renderProjection(target, context) {
  target.replaceChildren();
  activeSelection = context.session.selection || null;
  activeLaw = context.session.law ?? displayLaw(context.document, context.session);
  target.dataset.projection = context.session.projection;
  if (context.session.projection === "calendar") renderCalendar(target, context);
  else if (context.session.projection === "wall") renderWall(target, context);
  else if (context.session.projection === "lines") renderSimpleLines(target, context);
  else if (context.session.projection === "list") renderList(target, context);
  else if (context.session.projection === "board") renderBoard(target, context);
  else renderRadial(target, context);
}

export function renderMinimap(target, context) {
  target.replaceChildren();
  activeLaw = context.session.law ?? displayLaw(context.document, context.session);
  const span = Rational.parse(String(context.session.visibleSpan()));
  const drag = context.session.minimapDrag;
  const focus = context.session.currentFocus();
  const rangeKey = `${context.session.currentLens()}|${span.toJSON()}`;
  let outerStart;
  let outerEnd;
  if (drag) {
    outerStart = drag.start;
    outerEnd = drag.start.add(drag.span);
  } else {
    const previous = context.session.minimapRange;
    if (!previous || previous.key !== rangeKey) {
      outerStart = focus.sub(span.mul(2.5));
      outerEnd = focus.add(span.mul(2.5));
    } else {
      outerStart = previous.start;
      outerEnd = previous.end;
      const rangeSpan = outerEnd.sub(outerStart);
      const innerStart = outerStart.add(rangeSpan.mul("0.12"));
      const innerEnd = outerStart.add(rangeSpan.mul("0.88"));
      if (focus.compare(innerStart) < 0) {
        const shift = focus.sub(outerStart.add(rangeSpan.mul("0.25")));
        outerStart = outerStart.add(shift);
        outerEnd = outerEnd.add(shift);
      } else if (focus.compare(innerEnd) > 0) {
        const shift = focus.sub(outerStart.add(rangeSpan.mul("0.75")));
        outerStart = outerStart.add(shift);
        outerEnd = outerEnd.add(shift);
      }
    }
  }
  context.session.minimapRange = { key: rangeKey, start: outerStart, end: outerEnd };
  // The minimap is navigation chrome, so it never triggers a second recurrence
  // expansion. Binary-search the explicit indexes, then aggregate only the
  // in-range entries into the fixed number of display columns.
  const indexedRanges = [];
  for (const frame of layeredCalendarFrames(context, context.session.activeFrame)) {
    const indexed = context.engine.indexedExplicitFacts(frame.id);
    let low = 0;
    let high = indexed.length;
    while (low < high) {
      const middle = (low + high) >>> 1;
      if (indexed[middle].day.compare(outerStart) < 0) low = middle + 1;
      else high = middle;
    }
    let after = low;
    high = indexed.length;
    while (after < high) {
      const middle = (after + high) >>> 1;
      if (indexed[middle].day.compare(outerEnd) <= 0) after = middle + 1;
      else high = middle;
    }
    indexedRanges.push({ entries: indexed, start: low, end: after });
  }
  const binCount = MINIMAP_BUCKETS;
  const magnitudes = new Float64Array(binCount);
  // Objects per bucket, tracked alongside magnitude so the dot field can honour
  // its "every object is at least one dot" floor. A span counts in every bucket
  // it crosses: it is present there, so the bucket must not read as free.
  const counts = new Uint16Array(binCount);
  const rangeDays = outerEnd.sub(outerStart);
  const seenFacts = new Set();
  let indexedFactCount = 0;
  for (const range of indexedRanges) {
    for (let index = range.start; index < range.end; index += 1) {
      const fact = { ...range.entries[index].fact, displayFrame: range.entries[index].fact.relation?.frame };
      const key = `${fact.event.id}\u0000${fact.day}`;
      if (seenFacts.has(key)) continue;
      seenFacts.add(key);
      indexedFactCount += 1;
      const start = Rational.parse(fact.day);
      const duration = Rational.parse(String(durationMinutes(fact.event))).div(activeLaw.minutesPerDay());
      const startFraction = start.sub(outerStart).div(rangeDays).toNumber();
      const endFraction = start.add(duration).sub(outerStart).div(rangeDays).toNumber();
      const firstBin = Math.max(0, Math.min(binCount - 1, Math.floor(startFraction * binCount)));
      const lastBin = Math.max(firstBin, Math.min(binCount - 1, Math.floor(endFraction * binCount)));
      const occupiedBins = lastBin - firstBin + 1;
      const sourceId = fact.event.id;
      const magnitude = minimapEventMagnitude({
        durationDays: duration.toNumber(),
        stapleCount: Math.max(0, context.engine.eventFrames(sourceId).length - 1),
        importance: factRenderImportance(context, fact)
      }) / occupiedBins;
      for (let bin = firstBin; bin <= lastBin; bin += 1) {
        magnitudes[bin] += magnitude;
        if (counts[bin] < 0xffff) counts[bin] += 1;
      }
    }
  }
  const dotGrid = minimapDotGrid(magnitudes, { rows: MINIMAP_GRID_ROWS, counts });
  const svg = svgElement("svg", {
    viewBox: "0 0 1000 120",
    preserveAspectRatio: "none",
    role: "img",
    "aria-label": "Time minimap"
  });
  svg.dataset.minimapStart = outerStart.toJSON();
  svg.dataset.minimapEnd = outerEnd.toJSON();
  const lens = context.session.currentLens();
  const granularity = minimapLabelGranularity(lens);
  const title = svgElement("title");
  title.textContent = `Activity field, ${dotGrid.columns} buckets across ${granularity}-labelled boundaries. Each object is at least one dot; duration, cross-frame staples and importance add more. A full column is ${dotGrid.ceiling} magnitude or above. ${indexedFactCount} event${indexedFactCount === 1 ? "" : "s"} in range.`;
  const gridTop = 16;
  const gridHeight = 98;
  const columnWidth = 960 / dotGrid.columns;
  const rowHeight = gridHeight / dotGrid.rows;
  const baselineTop = gridTop + dotGrid.baseline * rowHeight;
  const definitions = svgElement("defs");
  // Both the unlit ground and the lit columns are drawn as pattern-filled
  // rects rather than one circle per cell. At 288x25 the cell-per-node approach
  // would put 7200 nodes into a surface that re-renders on every pan frame; the
  // pattern tiles from the same origin as the grid, so a rect whose edges land
  // on cell boundaries paints exactly the dots that cell range owns.
  for (const [id, radius, className] of [
    ["minimap-dot-unlit", 0.85, "minimap-grid-unlit"],
    ["minimap-dot-lit", 1.15, "minimap-grid-active"],
    ["minimap-dot-baseline", 1, "minimap-grid-baseline"]
  ]) {
    const pattern = svgElement("pattern", {
      id,
      x: 20,
      y: gridTop,
      width: columnWidth,
      height: rowHeight,
      patternUnits: "userSpaceOnUse"
    });
    pattern.append(svgElement("circle", { cx: columnWidth / 2, cy: rowHeight / 2, r: radius, class: className }));
    definitions.append(pattern);
  }
  svg.append(title, definitions, svgElement("rect", {
    x: 20,
    y: gridTop,
    width: 960,
    height: gridHeight,
    fill: "url(#minimap-dot-unlit)",
    class: "minimap-dot-field"
  }));
  // Every column owns a baseline dot on the field's centre row, so the axis reads
  // as a continuous line through the middle even where nothing is scheduled. One
  // rect covers the whole baseline row, and activity never overdraws it — the axis
  // stays the axis.
  svg.append(svgElement("rect", {
    x: 20,
    y: baselineTop,
    width: 960,
    height: rowHeight,
    fill: "url(#minimap-dot-baseline)",
    class: "minimap-dot-field"
  }));
  // Runs of equal height collapse into one rect, which keeps a quiet field down
  // to a handful of nodes and a saturated one down to a few hundred. Each run is
  // two bands, above and below the axis, because a column grows outward from it.
  for (let column = 0; column < dotGrid.columns;) {
    const dots = dotGrid.columnDots[column];
    let end = column + 1;
    while (end < dotGrid.columns && dotGrid.columnDots[end] === dots) end += 1;
    if (dots) {
      const reach = minimapColumnReach(dots, dotGrid.rows, dotGrid.baseline);
      const x = 20 + column * columnWidth;
      const width = (end - column) * columnWidth;
      if (reach.above) {
        svg.append(svgElement("rect", {
          x,
          y: baselineTop - reach.above * rowHeight,
          width,
          height: reach.above * rowHeight,
          fill: "url(#minimap-dot-lit)",
          class: "minimap-dot-field"
        }));
      }
      if (reach.below) {
        svg.append(svgElement("rect", {
          x,
          y: baselineTop + rowHeight,
          width,
          height: reach.below * rowHeight,
          fill: "url(#minimap-dot-lit)",
          class: "minimap-dot-field"
        }));
      }
    }
    column = end;
  }
  const rangeSpan = outerEnd.sub(outerStart);
  const positionFor = (value) => 20 + value.sub(outerStart).div(rangeSpan).toNumber() * 960;
  for (const tick of minimapLabelTicks(outerStart, outerEnd, granularity, 0, activeLaw)) {
    const tickX = positionFor(tick.days);
    svg.append(svgElement("line", { x1: tickX, y1: 13, x2: tickX, y2: gridTop + gridHeight, class: "minimap-tick" }));
    // Boundary labels sit just right of their own boundary rather than centred
    // on it, so the text and the line it names cannot drift apart.
    const label = svgElement("text", {
      x: Math.min(978, tickX + 2),
      y: 11,
      "text-anchor": tickX > 940 ? "end" : "start",
      class: "minimap-label"
    });
    label.textContent = tick.text;
    svg.append(label);
  }
  const viewportStart = context.session.currentFocus().sub(span.div(2));
  const x = positionFor(viewportStart);
  const width = span.div(rangeSpan).toNumber() * 960;
  svg.append(svgElement("rect", {
    x, y: gridTop - 2, width, height: gridHeight + 4, rx: 2,
    class: "minimap-window"
  }));
  const focusX = positionFor(focus);
  svg.append(svgElement("line", {
    x1: focusX, y1: gridTop - 4, x2: focusX, y2: gridTop + gridHeight + 4,
    class: "minimap-focus-line"
  }));
  // Owner's field note: "no artificial Now line on a calendar with no
  // now-mapping." A law that does not place its coordinates on the running
  // clock has no "now" to mark, so the whole line is withheld rather than
  // drawn at a guessed position.
  const now = nowDays();
  if (activeLaw.mapsToClock() && now.compare(outerStart) >= 0 && now.compare(outerEnd) <= 0) {
    const nowX = positionFor(now);
    svg.append(svgElement("line", {
      x1: nowX, y1: gridTop - 6, x2: nowX, y2: gridTop + gridHeight + 6,
      class: "minimap-now-line"
    }));
  }
  target.append(svg);
}

// Exposed for tests only: importance deciding whether an object renders at all is
// exactly the kind of rule that must be pinned, and it cannot be reached through
// renderProjection without a DOM.
export {
  calendarFrames,
  groupFrames,
  layeredCalendarFrames as layeredCalendarFramesForTest,
  queryFacts as queryFactsForTest,
  strategicPresentation as strategicPresentationForTest
};
