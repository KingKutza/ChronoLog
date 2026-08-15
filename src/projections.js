import {
  Rational,
  civilFromDays,
  coordinate,
  daysFromCivil,
  daysInMonth,
  daysToCivilCoordinate,
  floorMod,
  formatCivil,
  levelValue
} from "./exact.js";
import { radialGuideSettings, radialRenderState } from "./radial.js";
import { lineFramePlan, lineProgress, linesRenderState } from "./lines.js";

const SVG_NS = "http://www.w3.org/2000/svg";
const WEEKDAYS = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
const MONTHS = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December"
];

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
  const base = context.document.frames[requestedFrame];
  const contextual = (base?.display?.overlays || [])
    .map((id) => context.document.frames[id])
    .filter((frame) => frame && frame.id !== requestedFrame);
  const legacy = contextual.length ? [] : calendarFrames(context.document)
    .filter((frame) => frame.id !== requestedFrame && ["overlay", "underlay"].includes(frame.display?.mode));
  return [...new Map([base, ...contextual, ...legacy]
    .filter(Boolean).map((frame) => [frame.id, frame])).values()];
}

function factGroupFrame(context, fact) {
  const direct = context.engine.eventGroupFrame(fact.event.id);
  if (direct) return direct;
  const pattern = context.document.patterns[fact.event.provenance?.pattern];
  return pattern?.templateEvent
    ? context.engine.eventGroupFrame(pattern.templateEvent)
    : null;
}

function factVisibleInLens(context, fact) {
  const pattern = context.document.patterns[fact.event.provenance?.pattern];
  const source = pattern?.templateEvent ? context.document.events[pattern.templateEvent] : fact.event;
  const lenses = source?.display?.lenses || fact.event.display?.lenses;
  if (Array.isArray(lenses) && !lenses.includes(context.session.currentLens())) return false;
  const sourceId = pattern?.templateEvent || fact.event.id;
  const governingFrames = new Set(context.engine.eventFrames(sourceId));
  if (fact.displayFrame || fact.relation?.frame) governingFrames.add(fact.displayFrame || fact.relation.frame);
  for (const frameId of governingFrames) {
    const frame = context.document.frames[frameId];
    if (!frame || frame.traits?.includes("importance")) continue;
    if (Array.isArray(frame.display?.lenses) && !frame.display.lenses.includes(context.session.currentLens())) return false;
  }
  const importanceFrames = context.engine.eventFrames(sourceId)
    .map((id) => context.document.frames[id])
    .filter((frame) => frame?.traits?.includes("importance"));
  if (!importanceFrames.length) return true;
  const lens = context.session.currentLens();
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
  if (source?.display?.color || fact.event.display?.color) return source?.display?.color || fact.event.display.color;
  if (fact.event.traits?.includes("celestial")) return "#6d63b8";
  const groupFrame = factGroupFrame(context, fact);
  if (groupFrame) return context.document.frames[groupFrame]?.color || "#2e8b57";
  return context.document.frames[fact.displayFrame || fact.relation?.frame]?.color || "#d4552d";
}

function factImportance(context, fact) {
  const pattern = context.document.patterns[fact.event.provenance?.pattern];
  const sourceId = pattern?.templateEvent || fact.event.id;
  const source = context.document.events[sourceId] || fact.event;
  if (source.traits?.includes("landmark")) return "landmark";
  if (source.traits?.includes("important")) return "important";
  const frame = context.engine.eventFrames(sourceId)
    .map((id) => context.document.frames[id])
    .find((candidate) => candidate?.traits?.includes("importance"));
  return frame?.display?.importance || "standard";
}

function queryFacts(context, frame, startDays, endDays, limit = 800) {
  const { engine } = context;
  const frames = layeredCalendarFrames(context, frame);
  const sources = new Map(frames.map((frameValue) => [frameValue.id, { frame: frameValue, filterGroups: null }]));
  const base = context.document.frames[frame];
  for (const [groupId, mode] of Object.entries(base?.display?.groupModes || {})) {
    if (mode !== "show") continue;
    for (const relation of engine.relationsByFrame.get(groupId) || []) {
      const calendarId = engine.eventCalendarFrame(relation.event);
      const calendar = context.document.frames[calendarId];
      if (!calendar || sources.get(calendarId)?.filterGroups === null) continue;
      const source = sources.get(calendarId) || { frame: calendar, filterGroups: new Set() };
      source.filterGroups.add(groupId);
      sources.set(calendarId, source);
    }
  }
  const perFrameLimit = Math.max(80, Math.ceil(limit / Math.max(1, sources.size)) + 24);
  const results = [...sources.values()].map((source) => ({
    frame: source.frame,
    filterGroups: source.filterGroups,
    result: engine.queryFacts({
      frame: source.frame.id,
      start: daysToCivilCoordinate(startDays),
      end: daysToCivilCoordinate(endDays),
      limit: perFrameLimit,
      includeOverlaps: true
    })
  }));
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
    start: daysToCivilCoordinate(startDays),
    end: daysToCivilCoordinate(endDays),
    facts,
    errors: results.flatMap(({ result }) => result.errors || []),
    truncated: facts.length >= limit || results.some(({ result }) => result.truncated)
  };
}

function factsByDay(facts, visibleStart, visibleEnd) {
  const map = new Map();
  for (const fact of facts) {
    const start = Rational.parse(fact.day);
    const duration = Rational.parse(String(durationMinutes(fact.event))).div(1440);
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
        : day === end.floor() ? minuteOfDay(end) : 1440;
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
  return value.sub(value.floor()).mul(1440).toNumber();
}

function durationMinutes(event) {
  const factors = { week: 10080, day: 1440, hour: 60, minute: 1, second: 1 / 60 };
  let total = 0;
  for (const part of event?.magnitudes?.duration?.value?.levels || []) {
    if (factors[part.level] !== undefined) total += Number(part.value) * factors[part.level];
  }
  return Number.isFinite(total) ? Math.max(0, total) : 0;
}

function clockLabel(minutes) {
  const whole = Math.max(0, Math.floor(minutes));
  const hour = Math.floor(whole / 60) % 24;
  const minute = whole % 60;
  const suffix = hour < 12 ? "a" : "p";
  const displayHour = hour % 12 || 12;
  return `${displayHour}${minute ? `:${String(minute).padStart(2, "0")}` : ""}${suffix}`;
}

function bindFact(node, fact) {
  node.dataset.eventId = fact.event.id;
  node.dataset.factDay = fact.day;
  if (fact.virtualId) node.dataset.virtualId = fact.virtualId;
  else if (fact.relation?.id) node.dataset.relationId = fact.relation.id;
  return node;
}

function eventChip(context, fact, compact = false) {
  const spanning = durationMinutes(fact.event) >= 1440;
  const lens = context.session.currentLens();
  const zone = Boolean(context.session[`${lens}ZoneFill`]) && spanning;
  const zoneClass = !zone ? "" : fact.continuation
    ? fact.continuesAfter ? " zone-fill zone-middle" : " zone-fill zone-end"
    : fact.continuesAfter ? " zone-fill zone-start" : " zone-fill";
  const chip = element("button", `event-chip${compact ? " compact" : ""}${zoneClass}`);
  chip.type = "button";
  bindFact(chip, fact);
  chip.style.setProperty("--event-color", factColor(context, fact));
  chip.textContent = fact.event.payload?.title || "(untitled)";
  chip.title = `${chip.textContent} · ${formatCivil(fact.coordinate, true)}`;
  return chip;
}

function applyZoneDay(context, cell, facts, labelTarget = null) {
  const lens = context.session.currentLens();
  if (!context.session[`${lens}ZoneFill`]) return null;
  const fact = facts.find((item) => durationMinutes(item.event) >= 1440);
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
  const focus = context.session.currentFocus();
  const firstDay = focus.floor() - BigInt(context.session.intimateBack);
  const dayCount = context.session.intimateBack + context.session.intimateForward + 1;
  const lastDay = firstDay + BigInt(dayCount - 1);
  const hourPixels = context.session.intimateHourPixels;
  const visibleHours = Math.max(1, (target.clientHeight - 70) / hourPixels);
  const bufferDays = BigInt(Math.max(1, Math.ceil(visibleHours / 48)));
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
    const civil = civilFromDays(day);
    const weekday = Number(floorMod(day + 4n, 7n));
    const dayHeader = element("div", `intimate-dayhead${day === today ? " today" : ""}`);
    dayHeader.dataset.createDay = day.toString();
    const allDay = (byDay.get(day.toString()) || []).filter((fact) => fact.relation.parameters?.dateOnly
      || (context.session.intimateZoneFill && durationMinutes(fact.event) >= 1440));
    dayHeader.append(element("strong", "", `${WEEKDAYS[weekday]} ${civil.month}/${civil.day}`));
    const allDayLane = element("div", "intimate-all-day-lane");
    const zoneFact = applyZoneDay(context, dayHeader, allDay, allDayLane);
    for (const fact of allDay.filter((item) => item !== zoneFact).slice(0, 2)) allDayLane.append(eventChip(context, fact, true));
    dayHeader.append(allDayLane);
    if (allDay.length) dayHeader.title = `${allDay.length} all-day event${allDay.length === 1 ? "" : "s"}`;
    header.append(dayHeader);
  }
  const railDays = Number(bufferDays * 2n + 1n);
  const railHours = railDays * 24;
  const railHeight = railHours * hourPixels;
  const scroll = element("div", "intimate-scroll");
  scroll.dataset.scrollKey = "intimate";
  scroll.dataset.bufferHours = String(Number(bufferDays) * 24);
  scroll.dataset.hourPixels = String(hourPixels);
  scroll.dataset.headerPixels = "70";
  scroll.dataset.initialHour = String((context.session.intimateStartHour + context.session.intimateEndHour) / 2);
  const body = element("div", "intimate-body");
  const gutter = element("div", "intimate-gutter");
  gutter.style.height = `${railHeight}px`;
  for (let hour = 0; hour < railHours; hour += 1) {
    const label = element("span", "intimate-hour-label", clockLabel((hour % 24) * 60));
    label.style.top = `${hour * hourPixels}px`;
    gutter.append(label);
  }
  for (let boundary = 1; boundary < railDays; boundary += 1) {
    const line = element("div", "intimate-midnight-line");
    line.style.top = `${boundary * hourPixels}px`;
    gutter.append(line);
  }
  body.append(gutter);
  for (let day = firstDay; day <= lastDay; day += 1n) {
    const column = element("div", `intimate-day-column${day === today ? " today" : ""}`);
    column.style.height = `${railHeight}px`;
    column.style.setProperty("--grain-px", `${hourPixels * context.session.intimateGrain / 60}px`);
    column.dataset.createDay = day.toString();
    column.dataset.timelineStart = (day - bufferDays).toString();
    column.dataset.timelineHours = String(railHours);
    const timed = [];
    for (let offset = -Number(bufferDays); offset <= Number(bufferDays); offset += 1) {
      const segmentDay = day + BigInt(offset);
      const segmentIndex = offset + Number(bufferDays);
      const dayFacts = byDay.get(segmentDay.toString()) || [];
      const spanning = dayFacts.find((fact) => context.session.intimateZoneFill && durationMinutes(fact.event) >= 1440);
      if (spanning) {
        const fill = element("div", "intimate-zone-segment");
        fill.style.top = `${segmentIndex * 24 * hourPixels}px`;
        fill.style.height = `${24 * hourPixels}px`;
        fill.style.setProperty("--zone-color", factColor(context, spanning));
        column.append(fill);
      }
      timed.push(...dayFacts
        .filter((fact) => !fact.relation.parameters?.dateOnly
          && !(context.session.intimateZoneFill && durationMinutes(fact.event) >= 1440))
        .map((fact) => {
          const start = segmentIndex * 1440 + Math.max(0, fact.segmentStartMinute);
          const end = segmentIndex * 1440 + Math.min(1440, Math.max(
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
    assignLanes(timed.filter((item) => item.fact.displayLayer !== "included"));
    assignLanes(timed.filter((item) => item.fact.displayLayer === "included"));
    for (const item of timed.slice(0, 80)) {
      const included = item.fact.displayLayer === "included";
      const important = factImportance(context, item.fact) !== "standard";
      const continuation = item.fact.continuation && durationMinutes(item.fact.event) < 1440;
      const button = element("button", `intimate-event${included ? " included-event" : ""}${important ? " important-event" : ""}${continuation ? " continuation-event" : ""}`);
      button.type = "button";
      bindFact(button, item.fact);
      button.style.setProperty("--event-color", factColor(context, item.fact));
      button.style.top = `${item.start / 60 * hourPixels}px`;
      button.style.height = `${Math.max(13, (item.end - item.start) / 60 * hourPixels)}px`;
      if (included) {
        button.style.right = `${3 + item.lane * 9}px`;
        button.style.width = `${Math.max(18, 36 - item.lane * 5)}%`;
      } else {
        button.style.left = `${item.lane / item.laneCount * 100}%`;
        button.style.width = `calc(${100 / item.laneCount}% - 3px)`;
      }
      button.append(
        element("strong", "", `${continuation ? "↳ " : ""}${item.fact.event.payload?.title || "(untitled)"}${continuation ? " · continued" : ""}`),
        element("time", "", clockLabel(item.start % 1440)),
        ...(item.fact.event.payload?.location && item.end - item.start >= 30
          ? [element("span", "event-location", item.fact.event.payload.location)]
          : [])
      );
      column.append(button);
    }
    for (let boundary = 1; boundary < railDays; boundary += 1) {
      const boundaryDay = day - bufferDays + BigInt(boundary);
      const previousCivil = civilFromDays(boundaryDay - 1n);
      const nextCivil = civilFromDays(boundaryDay);
      const marker = element("div", "intimate-midnight-marker");
      marker.style.top = `${boundary * 24 * hourPixels}px`;
      marker.append(
        element("span", "midnight-before", `${previousCivil.month}/${previousCivil.day}`),
        element("strong", "", "MIDNIGHT"),
        element("span", "midnight-after", `${nextCivil.month}/${nextCivil.day}`)
      );
      column.append(marker);
    }
    if (today >= day - bufferDays && today <= day + bufferDays) {
      const line = element("div", "intimate-now");
      const nowMinute = now.getHours() * 60 + now.getMinutes();
      const segmentIndex = Number(today - (day - bufferDays));
      line.style.top = `${(segmentIndex * 1440 + nowMinute) / 60 * hourPixels}px`;
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
  const important = fact.event.traits?.some((trait) => ["important", "milestone", "deadline"].includes(trait))
    || fact.event.payload?.categories?.some((category) => /important|milestone|deadline/i.test(category));
  const pattern = context.document.patterns[fact.event.provenance?.pattern];
  const frequency = String(pattern?.rrule?.FREQ || "").toUpperCase();
  if (context.session.strategicMode === "blocks") return duration >= 240 ? "name" : "none";
  if (context.session.strategicMode === "all") return duration >= 240 || important ? "name" : "pip";
  if (duration >= 240 || important || ["MONTHLY", "YEARLY"].includes(frequency)) return "name";
  if (frequency === "WEEKLY") return "pip";
  return "none";
}

function renderTactical(target, context) {
  const focusDay = context.session.currentFocus().floor();
  const total = context.session.tacticalRows * context.session.tacticalColumns;
  const start = focusDay - BigInt(Math.floor(total / 2));
  const result = queryFacts(context, context.session.activeFrame, new Rational(start), new Rational(start + BigInt(total)), 600);
  const byDay = factsByDay(result.facts, start, start + BigInt(total));
  const grid = element("div", "tactical-grid");
  grid.style.setProperty("--rows", String(context.session.tacticalRows));
  grid.style.setProperty("--columns", String(context.session.tacticalColumns));
  for (let offset = 0n; offset < BigInt(total); offset += 1n) {
    const day = start + offset;
    const civil = civilFromDays(day);
    const weekday = Number(floorMod(day + 4n, 7n));
    const cell = element("section", `tactical-day${weekday === 0 || weekday === 6 ? " weekend" : ""}`);
    cell.dataset.createDay = day.toString();
    const header = element("header", "day-heading");
    header.append(
      element("span", "weekday", WEEKDAYS[weekday]),
      element("strong", "", `${civil.month}/${civil.day}`),
      element("small", "", civil.year.toString())
    );
    cell.append(header);
    const dayFacts = byDay.get(day.toString()) || [];
    const zoneFact = applyZoneDay(context, cell, dayFacts, header);
    const displayFacts = dayFacts.filter((item) => item !== zoneFact
      && !(item.continuation && durationMinutes(item.event) < 1440));
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
    element("strong", "", MONTHS[Number(month) - 1]),
    element("span", "", year.toString())
  );
  card.append(heading);
  const weekdays = element("div", "month-weekdays");
  for (const name of ["M", "T", "W", "T", "F", "S", "S"]) weekdays.append(element("span", "", name));
  card.append(weekdays);
  const grid = element("div", "month-days");
  const first = daysFromCivil(year, month, 1n);
  const now = new Date();
  const today = daysFromCivil(BigInt(now.getFullYear()), BigInt(now.getMonth() + 1), BigInt(now.getDate()));
  const lead = Number(floorMod(first + 3n, 7n));
  for (let index = 0; index < lead; index += 1) grid.append(element("div", "month-pad"));
  const totalDays = daysInMonth(year, month);
  for (let day = 1; day <= totalDays; day += 1) {
    const ordinal = daysFromCivil(year, month, BigInt(day));
    const cell = element("div", "month-day");
    if (context.session.wallRecordSlashes && ordinal < today) cell.classList.add("record-slash");
    cell.dataset.createDay = ordinal.toString();
    const dayLabel = element("b", "month-number", String(day));
    cell.append(dayLabel);
    const entries = (facts.get(ordinal.toString()) || [])
      .filter((item) => !(item.continuation && durationMinutes(item.event) < 1440));
    const zoneFact = applyZoneDay(context, cell, entries, dayLabel);
    if (detailed) {
      for (const fact of entries.filter((item) => item !== zoneFact).slice(0, 4)) cell.append(eventChip(context, fact, true));
    } else {
      const pips = element("div", "event-pips");
      for (const fact of entries.slice(0, 8)) {
        const pip = element("button", "event-pip");
        pip.type = "button";
        bindFact(pip, fact);
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

function renderStrategic(target, context) {
  const focusCivil = civilFromDays(context.session.currentFocus().floor());
  const monthCount = context.session.strategicMonths;
  const firstMonth = addMonths(focusCivil.year, focusCivil.month, -Math.floor(monthCount / 2));
  const lastMonth = addMonths(firstMonth.year, firstMonth.month, monthCount);
  const start = daysFromCivil(firstMonth.year, firstMonth.month, 1n);
  const end = daysFromCivil(lastMonth.year, lastMonth.month, 1n);
  const result = queryFacts(context, context.session.activeFrame, new Rational(start), new Rational(end), 800);
  const byDay = factsByDay(result.facts, start, end);
  const path = element("div", "strategic-path");
  path.dataset.scrollKey = "strategic";
  path.style.setProperty("--strategic-months", String(monthCount));
  const now = new Date();
  const today = daysFromCivil(BigInt(now.getFullYear()), BigInt(now.getMonth() + 1), BigInt(now.getDate()));
  for (let index = 0; index < monthCount; index += 1) {
    const current = addMonths(firstMonth.year, firstMonth.month, index);
    const row = element("section", "strategic-row");
    const label = element("header", "strategic-label", MONTHS[Number(current.month) - 1].slice(0, 3));
    label.append(element("small", "", current.year.toString()));
    row.append(label);
    const monthLength = daysInMonth(current.year, current.month);
    for (let day = 1; day <= 31; day += 1) {
      if (day > monthLength) {
        row.append(element("div", "strategic-day pad"));
        continue;
      }
      const ordinal = daysFromCivil(current.year, current.month, BigInt(day));
      const weekday = Number(floorMod(ordinal + 4n, 7n));
      const classes = ["strategic-day"];
      if (weekday === 0 || weekday === 6) classes.push("weekend");
      if (ordinal < today) classes.push("past");
      if (ordinal === today) classes.push("today");
      if (context.session.strategicRecordSlashes && ordinal < today) classes.push("record-slash");
      const cell = element("div", classes.join(" "));
      cell.dataset.createDay = ordinal.toString();
      cell.append(element("div", "strategic-day-number", `${day} ${WEEKDAYS[weekday].slice(0, 1)}`));
      const facts = (byDay.get(ordinal.toString()) || [])
        .filter((item) => !(item.continuation && durationMinutes(item.event) < 1440));
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
          pip.style.background = factColor(context, fact);
          pip.title = fact.event.payload?.title || "(untitled)";
          pips.append(pip);
        }
        cell.append(pips);
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

function renderLines(target, context) {
  const frames = calendarFrames(context.document);
  const prime = context.document.frames[context.session.activeFrame] || frames[0];
  const ordered = [prime, ...frames.filter((frame) => frame.id !== prime?.id)].filter(Boolean);
  const window = context.session.window();
  const width = 1200;
  const height = 620;
  const rowY = (index) => ordered.length <= 1
    ? height / 2
    : 70 + index * ((height - 140) / (ordered.length - 1));
  const svg = svgElement("svg", {
    class: "lines-svg",
    viewBox: `0 0 ${width} ${height}`,
    role: "img",
    "aria-label": "Calendar and timeline topology"
  });
  svg.dataset.dropStart = window.start.toJSON();
  svg.dataset.dropEnd = window.end.toJSON();
  svg.dataset.dropKind = "linear";
  const span = window.end.sub(window.start);
  const positions = new Map();
  const errors = [];

  ordered.forEach((frame, index) => {
    const y = rowY(index);
    const color = index === 0 ? "#d4552d" : frame.color || ["#2e8b57", "#497bc1", "#8a63c9"][index % 3];
    const line = svgElement("path", {
      d: index === 0
        ? `M 145 ${y} L 1140 ${y}`
        : `M 145 ${y} C 340 ${y}, 360 ${y - 12}, 480 ${y - 12} S 760 ${y + 10}, 1140 ${y}`,
      fill: "none",
      stroke: color,
      "stroke-width": index === 0 ? 5 : 3,
      "stroke-linecap": "round"
    });
    svg.append(line);
    const label = svgElement("text", { x: 24, y: y + 5, fill: color, class: "line-label" });
    label.textContent = `${index === 0 ? "PRIME · " : ""}${frame.title}`;
    svg.append(label);

    const result = queryFacts(context, frame.id, window.start, window.end, 300);
    errors.push(...(result.errors || []));
    for (const fact of result.facts) {
      const x = fact.day
        ? 145 + Rational.parse(fact.day).sub(window.start).div(span).toNumber() * 995
        : 145;
      if (x < 140 || x > 1145) continue;
      const stem = svgElement("line", {
        x1: x, y1: y, x2: x, y2: y - 22,
        stroke: factColor(context, fact),
        "stroke-width": 1.5
      });
      const dot = svgElement("circle", {
        cx: x, cy: y, r: 6,
        fill: factColor(context, fact),
        class: "line-event",
        tabindex: 0
      });
      bindFact(dot, fact);
      const title = svgElement("title");
      title.textContent = fact.event.payload?.title || "(untitled)";
      dot.append(title);
      svg.append(stem, dot);
      const prior = positions.get(fact.event.id);
      if (prior) {
        svg.append(svgElement("path", {
          d: `M ${prior.x} ${prior.y} C ${prior.x} ${(prior.y + y) / 2}, ${x} ${(prior.y + y) / 2}, ${x} ${y}`,
          fill: "none",
          stroke: "#51483d",
          "stroke-width": 1.5,
          "stroke-dasharray": "4 4"
        }));
      } else {
        positions.set(fact.event.id, { x, y });
      }
    }
  });

  for (const relation of Object.values(context.document.relations).filter(
    (item) => item.type === "composition"
  )) {
    const parentIndex = ordered.findIndex((frame) => frame.id === relation.parent);
    const childIndex = ordered.findIndex((frame) => frame.id === relation.child);
    if (parentIndex < 0 || childIndex < 0) continue;
    const y1 = rowY(parentIndex);
    const y2 = rowY(childIndex);
    svg.append(svgElement("path", {
      d: `M 430 ${y1} C 455 ${y1}, 455 ${y2}, 480 ${y2}`,
      fill: "none",
      stroke: "#51483d",
      "stroke-width": 2
    }));
  }
  target.append(svg);
  renderErrors(target, { errors });
}

function legacyRenderSimpleLines(target, context) {
  const window = context.session.window();
  const width = 1200;
  const height = 620;
  const primeY = height / 2;
  const calendar = context.document.frames[context.session.activeFrame];
  const groups = groupFrames(context.document).slice(0, 8);
  const lanes = [
    { id: null, title: `Prime Â· ${calendar?.title || "Calendar"}`, color: "#d4552d", y: primeY },
    ...groups.map((group, index) => ({
      id: group.id,
      title: group.title,
      color: group.color || ["#2e8b57", "#497bc1", "#8a63c9"][index % 3],
      y: groups.length === 1 ? 130 : 70 + index * (180 / Math.max(1, groups.length - 1))
    }))
  ];
  const svg = svgElement("svg", {
    class: "lines-svg",
    viewBox: `0 0 ${width} ${height}`,
    role: "img",
    "aria-label": "Prime timeline with group side lines"
  });
  svg.dataset.dropStart = window.start.toJSON();
  svg.dataset.dropEnd = window.end.toJSON();
  svg.dataset.dropKind = "linear";
  const span = window.end.sub(window.start);
  const result = queryFacts(context, context.session.activeFrame, window.start, window.end, 450);
  const byLane = new Map(lanes.map((lane) => [lane.id, []]));
  for (const fact of result.facts) {
    const groupId = factGroupFrame(context, fact);
    (byLane.get(byLane.has(groupId) ? groupId : null) || byLane.get(null)).push(fact);
  }

  for (let index = 0; index < 5; index += 1) {
    const progress = index / 4;
    const x = 145 + progress * 995;
    const day = window.start.add(span.mul(String(progress)));
    svg.append(svgElement("line", { x1: x, y1: 42, x2: x, y2: 572, class: "line-tick" }));
    const label = svgElement("text", {
      x, y: 596,
      "text-anchor": index === 0 ? "start" : index === 4 ? "end" : "middle",
      class: "minimap-label"
    });
    label.textContent = formatCivil(daysToCivilCoordinate(day)).replace(/ 00:00:00$/, "");
    svg.append(label);
  }

  lanes.forEach((lane, index) => {
    const line = svgElement("path", {
      d: index === 0
        ? `M 145 ${lane.y} L 1140 ${lane.y}`
        : `M 145 ${primeY} C 220 ${primeY}, 245 ${lane.y}, 330 ${lane.y} C 560 ${lane.y}, 760 ${lane.y}, 940 ${lane.y} C 1040 ${lane.y}, 1070 ${primeY}, 1140 ${primeY}`,
      fill: "none",
      stroke: lane.color,
      "stroke-width": index === 0 ? 5 : 3,
      "stroke-linecap": "round"
    });
    svg.append(line);
    const label = svgElement("text", {
      x: index === 0 ? 24 : 345,
      y: index === 0 ? lane.y + 5 : lane.y - 10,
      fill: lane.color,
      class: "line-label"
    });
    label.textContent = lane.title;
    svg.append(label);

    const buckets = new Map();
    for (const fact of byLane.get(lane.id) || []) {
      const progress = Rational.parse(fact.day).sub(window.start).div(span).toNumber();
      if (progress < 0 || progress > 1) continue;
      const key = Math.min(179, Math.max(0, Math.floor(progress * 180)));
      const bucket = buckets.get(key) || { facts: [], progress };
      bucket.facts.push(fact);
      buckets.set(key, bucket);
    }
    for (const bucket of buckets.values()) {
      const fact = bucket.facts[0];
      const x = 145 + bucket.progress * 995;
      const count = bucket.facts.length;
      const dot = svgElement("circle", {
        cx: x, cy: lane.y, r: Math.min(10, 5 + Math.log2(count)),
        fill: lane.color,
        class: "line-event",
        tabindex: 0
      });
      bindFact(dot, fact);
      const title = svgElement("title");
      title.textContent = count === 1
        ? fact.event.payload?.title || "(untitled)"
        : `${count} events near ${formatCivil(fact.coordinate)}`;
      dot.append(title);
      svg.append(svgElement("line", {
        x1: x, y1: lane.y, x2: x, y2: lane.y - Math.min(28, 16 + count),
        stroke: lane.color, "stroke-width": 1.5
      }), dot);
    }
  });
  target.append(svg);
  renderErrors(target, result);
}

function renderSimpleLines(target, context) {
  const window = context.session.window();
  const width = 1200;
  const height = 620;
  const primeY = height / 2;
  const xFor = (day) => 145 + lineProgress(day, window.start, window.end) * 995;
  const plan = lineFramePlan(context.document, context.session.activeFrame);
  const prime = plan.leading;
  const secondaryFrames = plan.companions;
  const directQuery = (frame, limit) => context.engine.queryFacts({
    frame: frame.id,
    start: daysToCivilCoordinate(window.start),
    end: daysToCivilCoordinate(window.end),
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
    label.textContent = formatCivil(daysToCivilCoordinate(day)).replace(/ 00:00:00$/, "");
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
  for (const fact of primeResult.facts) {
    const x = xFor(fact.day);
    if (x < 145 || x > 1140) continue;
    const dot = svgElement("circle", { cx: x, cy: primeY, r: 5, fill: factColor(context, fact), class: "line-event", tabindex: 0 });
    bindFact(dot, fact);
    const title = svgElement("title");
    title.textContent = fact.event.payload?.title || "(untitled)";
    dot.append(title);
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
    for (const fact of result.facts) {
      const x = xFor(fact.day);
      if (x < firstX || x > lastX) continue;
      const p = lastX === firstX ? 0.5 : (x - firstX) / (lastX - firstX);
      const y = primeY + (apexY - primeY) * Math.sin(Math.PI * p);
      const shared = primeEvents.has(fact.event.id);
      if (shared) svg.append(svgElement("line", { x1: x, y1: primeY, x2: x, y2: y, stroke: "#51483d", "stroke-width": 1.5, "stroke-dasharray": "3 3" }));
      const dot = svgElement("circle", { cx: x, cy: y, r: shared ? 7 : 4.5, fill: frame.color || "#497bc1", stroke: shared ? "#2a2620" : "none", "stroke-width": 2, class: "line-event", tabindex: 0 });
      bindFact(dot, fact);
      const title = svgElement("title");
      title.textContent = `${fact.event.payload?.title || "(untitled)"}${shared ? " · staple" : ""}`;
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

function polar(cx, cy, radius, angle) {
  return [cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius];
}

function arcPath(cx, cy, radius, startAngle, endAngle) {
  const [x1, y1] = polar(cx, cy, radius, startAngle);
  const [x2, y2] = polar(cx, cy, radius, endAngle);
  const large = endAngle - startAngle > Math.PI ? 1 : 0;
  return `M ${x1.toFixed(2)} ${y1.toFixed(2)} A ${radius.toFixed(2)} ${radius.toFixed(2)} 0 ${large} 1 ${x2.toFixed(2)} ${y2.toFixed(2)}`;
}

function radialEventPath(fact, attributes) {
  const path = svgElement("path", { class: "radial-event-arc", tabindex: 0, pathLength: 1, ...attributes });
  bindFact(path, fact);
  const title = svgElement("title");
  title.textContent = fact.event.payload?.title || "(untitled)";
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

function currentDays() {
  const now = new Date();
  return new Rational(daysFromCivil(
    BigInt(now.getFullYear()), BigInt(now.getMonth() + 1), BigInt(now.getDate())
  )).add(Rational.parse(now.getHours()).div(24))
    .add(Rational.parse(now.getMinutes()).div(1440))
    .add(Rational.parse(now.getSeconds()).div(86400));
}

function radialNowLine(svg, start, end, turns = 1) {
  const now = currentDays();
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
  const cycle = session.radialCycle;
  const start = session.radialMode === "spiral"
    ? session.currentFocus().sub(cycle.mul(session.radialPast + 0.5))
    : session.currentFocus().sub(cycle.div(2));
  const end = session.radialMode === "spiral"
    ? session.currentFocus().add(cycle.mul(session.radialFuture + 0.5))
    : session.currentFocus().add(cycle.div(2));
  const result = queryFacts(context, session.activeFrame, start, end, 350);
  const renderState = radialRenderState(result.facts.length, result.truncated);
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
  svg.dataset.radialState = renderState;
  svg.append(svgElement("circle", {
    cx, cy, r: 54, fill: "#f5efe2", stroke: "#bdb19e", "stroke-width": 2
  }));
  const centerLabel = svgElement("text", {
    x: cx, y: cy + 4, "text-anchor": "middle", class: "radial-center"
  });
  centerLabel.textContent = formatCivil(daysToCivilCoordinate(session.currentFocus()));
  svg.append(centerLabel);
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
        : elapsedDays < 1 ? `+${(elapsedDays * 24).toFixed(1)}h` : `+${elapsedDays.toFixed(1)}d`;
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
    let path = "";
    for (let index = 0; index <= samples; index += 1) {
      const progress = index / samples;
      const angle = -Math.PI / 2 + progress * turns * Math.PI * 2;
      const radius = inner + progress * turns * spacing;
      const [x, y] = polar(cx, cy, radius, angle);
      path += `${index ? "L" : "M"}${x.toFixed(2)} ${y.toFixed(2)} `;
    }
    const backingColor = context.document.frames[session.activeFrame]?.color || "#84735d";
    svg.append(svgElement("path", {
      d: path, fill: "none", stroke: backingColor, opacity: 0.16,
      "stroke-width": Math.max(34, spacing * 0.9),
      "stroke-linecap": "round"
    }));
    svg.append(svgElement("path", {
      d: path, fill: "none", stroke: backingColor, opacity: 0.28,
      "stroke-width": 1.4, "stroke-linecap": "round"
    }));
    radialNowLine(svg, start, end, turns);
    const items = result.facts.map((fact) => {
      const progress = Rational.parse(fact.day).sub(start).div(end.sub(start)).toNumber();
      const duration = Math.max(durationMinutes(fact.event) / 1440 / end.sub(start).toNumber(), 0.0025);
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
      let eventPath = "";
      const samples = Math.max(2, Math.ceil((endProgress - startProgress) * turns * 80));
      for (let sample = 0; sample <= samples; sample += 1) {
        const progress = startProgress + (endProgress - startProgress) * sample / samples;
        const angle = -Math.PI / 2 + progress * turns * Math.PI * 2;
        const radius = inner + progress * turns * spacing + laneOffset;
        const [x, y] = polar(cx, cy, radius, angle);
        eventPath += `${sample ? "L" : "M"}${x.toFixed(2)} ${y.toFixed(2)} `;
      }
      svg.append(radialEventPath(fact, {
        d: eventPath,
        stroke: factColor(context, fact),
        "stroke-width": durationMinutes(fact.event)
          ? Math.min(factImportance(context, fact) === "landmark" ? 11 : 8, Math.max(3, laneStep * 0.72))
          : 4
      }));
      if (session.radialLabels && radialLabels.length < 24) {
        const middleProgress = (startProgress + endProgress) / 2;
        const angle = -Math.PI / 2 + middleProgress * turns * Math.PI * 2;
        const radius = inner + middleProgress * turns * spacing + laneOffset;
        const [x, y] = polar(cx, cy, radius + 8, angle);
        radialEventLabel(labelLayer, fact, x, y, radialLabels, Math.cos(angle) < 0 ? "end" : "start");
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
        const duration = Math.max(durationMinutes(fact.event) / 1440 / cycle.toNumber(), 0.004);
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
        svg.append(radialEventPath(item.fact, {
          d: arcPath(cx, cy, radius, startAngle, endAngle),
          stroke: factColor(context, item.fact),
          "stroke-width": Math.max(factImportance(context, item.fact) === "landmark" ? 5 : 3, laneStep * 0.72)
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

export function renderProjection(target, context) {
  target.replaceChildren();
  target.dataset.projection = context.session.projection;
  if (context.session.projection === "calendar") renderCalendar(target, context);
  else if (context.session.projection === "wall") renderWall(target, context);
  else if (context.session.projection === "lines") renderSimpleLines(target, context);
  else renderRadial(target, context);
}

export function renderMinimap(target, context) {
  target.replaceChildren();
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
  // The minimap is navigation chrome, so it must never trigger a second
  // recurrence expansion. Explicit placements are already indexed and give a
  // useful density trace at essentially constant cost; recurring detail remains
  // in the primary lens where its result is bounded.
  const facts = [];
  for (const frame of layeredCalendarFrames(context, context.session.activeFrame)) {
    const indexed = context.engine.indexedExplicitFacts(frame.id);
    let low = 0;
    let high = indexed.length;
    while (low < high) {
      const middle = (low + high) >>> 1;
      if (indexed[middle].day.compare(outerStart) < 0) low = middle + 1;
      else high = middle;
    }
    for (let index = low; index < indexed.length && facts.length < 1200; index += 1) {
      if (indexed[index].day.compare(outerEnd) > 0) break;
      facts.push({ ...indexed[index].fact, displayFrame: frame.id });
    }
  }
  const svg = svgElement("svg", {
    viewBox: "0 0 1000 120",
    preserveAspectRatio: "none",
    role: "img",
    "aria-label": "Time minimap"
  });
  svg.dataset.minimapStart = outerStart.toJSON();
  svg.dataset.minimapEnd = outerEnd.toJSON();
  svg.append(svgElement("line", { x1: 20, y1: 60, x2: 980, y2: 60, class: "minimap-center-line" }));
  for (let index = 0; index <= 7; index += 1) {
    const fraction = index / 7;
    const tickX = 20 + fraction * 960;
    const tickDay = outerStart.add(outerEnd.sub(outerStart).mul(String(fraction)));
    svg.append(svgElement("line", {
      x1: tickX, y1: 14, x2: tickX, y2: 106, class: "minimap-tick"
    }));
    const label = svgElement("text", {
      x: tickX,
      y: 11,
      "text-anchor": index === 0 ? "start" : index === 7 ? "end" : "middle",
      class: "minimap-label"
    });
    label.textContent = formatCivil(daysToCivilCoordinate(tickDay)).replace(/ 00:00:00$/, "");
    svg.append(label);
  }
  const binCount = 140;
  const densityLayers = new Map();
  for (const fact of facts) {
    const fraction = Rational.parse(fact.day).sub(outerStart).div(outerEnd.sub(outerStart)).toNumber();
    const bin = Math.max(0, Math.min(binCount - 1, Math.floor(fraction * binCount)));
    const color = factColor(context, fact);
    const bins = densityLayers.get(color) || new Uint16Array(binCount);
    bins[bin] += 1;
    densityLayers.set(color, bins);
  }
  const totals = new Uint16Array(binCount);
  for (const bins of densityLayers.values()) {
    for (let bin = 0; bin < binCount; bin += 1) totals[bin] += bins[bin];
  }
  const peak = Math.max(1, ...totals);
  const stacked = new Float32Array(binCount);
  for (const [color, bins] of densityLayers) {
    let d = "";
    for (let bin = 0; bin < binCount; bin += 1) {
      if (!bins[bin]) continue;
      const height = Math.max(1, Math.round(bins[bin] / peak * 35));
      const x = 20 + (bin + 0.5) / binCount * 960;
      for (let dot = 0; dot < height; dot += 1) {
        const offset = stacked[bin] + dot * 1.35 + .8;
        d += `M${x.toFixed(2)} ${(60 - offset).toFixed(2)}h.01M${x.toFixed(2)} ${(60 + offset).toFixed(2)}h.01`;
      }
      stacked[bin] += height * 1.35;
    }
    const layer = svgElement("path", {
      d, fill: "none", stroke: color, "stroke-width": 1.45, "stroke-linecap": "round", opacity: 0.82,
      class: "minimap-density-layer"
    });
    const title = svgElement("title");
    title.textContent = "Event density; color identifies its frame or group";
    layer.append(title);
    svg.append(layer);
  }
  const viewportStart = context.session.currentFocus().sub(span.div(2));
  const x = 20 + viewportStart.sub(outerStart).div(outerEnd.sub(outerStart)).toNumber() * 960;
  const width = span.div(outerEnd.sub(outerStart)).toNumber() * 960;
  svg.append(svgElement("rect", {
    x, y: 17, width, height: 86, rx: 2,
    fill: "rgba(255,253,247,.10)", stroke: "#2a2620", "stroke-width": 1.25,
    class: "minimap-window"
  }));
  const focusX = 20 + focus.sub(outerStart).div(outerEnd.sub(outerStart)).toNumber() * 960;
  svg.append(svgElement("line", {
    x1: focusX, y1: 12, x2: focusX, y2: 108,
    class: "minimap-focus-line"
  }));
  const now = currentDays();
  if (now.compare(outerStart) >= 0 && now.compare(outerEnd) <= 0) {
    const nowX = 20 + now.sub(outerStart).div(outerEnd.sub(outerStart)).toNumber() * 960;
    svg.append(svgElement("line", { x1: nowX, y1: 8, x2: nowX, y2: 112, class: "minimap-now-line" }));
  }
  target.append(svg);
}

export { calendarFrames, groupFrames };
