import {
  Rational,
  civilCoordinateToDays,
  coordinate,
  daysToCivilCoordinate,
  levelValue
} from "./exact.js";
import { seriesEffectiveUntilDays } from "./engine.js";
import {
  addEvent,
  addFrame,
  addPattern,
  addRelation,
  createId,
  durationMagnitude,
  seriesEndStaple,
  stableVirtualId,
  suppressVirtual,
  touch
} from "./model.js";
import { recurrenceEndMode, recurrenceUntilForCoordinate } from "./recurrence-end.js";

function splitOutsideQuotes(value, separator) {
  const parts = [];
  let current = "";
  let quoted = false;
  for (const char of value) {
    if (char === '"') quoted = !quoted;
    if (char === separator && !quoted) {
      parts.push(current);
      current = "";
    } else {
      current += char;
    }
  }
  parts.push(current);
  return parts;
}

function stripQuotes(value) {
  return value.length >= 2 && value.startsWith('"') && value.endsWith('"')
    ? value.slice(1, -1)
    : value;
}

function colonIndex(line) {
  let quoted = false;
  for (let index = 0; index < line.length; index += 1) {
    if (line[index] === '"') quoted = !quoted;
    if (line[index] === ":" && !quoted) return index;
  }
  return -1;
}

export function unfoldICS(text) {
  return String(text)
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/\n[ \t]/g, "");
}

export function parseContentLine(line) {
  const colon = colonIndex(line);
  if (colon < 0) return { name: line.toUpperCase(), params: [], value: "", raw: line, verbatim: true };
  const head = line.slice(0, colon);
  const value = line.slice(colon + 1);
  const [rawName, ...rawParams] = splitOutsideQuotes(head, ";");
  const params = rawParams.map((parameter) => {
    const equals = parameter.indexOf("=");
    if (equals < 0) return { name: parameter.toUpperCase(), values: [""] };
    return {
      name: parameter.slice(0, equals).toUpperCase(),
      values: splitOutsideQuotes(parameter.slice(equals + 1), ",").map(stripQuotes)
    };
  });
  return { name: rawName.toUpperCase(), params, value, raw: line };
}

export function parseICSTree(text) {
  const root = { name: "ROOT", properties: [], components: [] };
  const stack = [root];
  for (const rawLine of unfoldICS(text).split("\n")) {
    if (!rawLine) continue;
    const property = parseContentLine(rawLine);
    if (property.name === "BEGIN") {
      const component = { name: property.value.toUpperCase(), properties: [], components: [] };
      stack.at(-1).components.push(component);
      stack.push(component);
    } else if (property.name === "END") {
      if (stack.length === 1 || stack.at(-1).name !== property.value.toUpperCase()) {
        throw new SyntaxError(`Mismatched END:${property.value}`);
      }
      stack.pop();
    } else {
      stack.at(-1).properties.push(property);
    }
  }
  if (stack.length !== 1) throw new SyntaxError(`Unclosed ${stack.at(-1).name}`);
  return root;
}

export function properties(component, name) {
  return component.properties.filter((property) => property.name === name.toUpperCase());
}

export function property(component, name) {
  return properties(component, name)[0] || null;
}

// A stable key for one imported VEVENT/VTODO within its source calendar --
// component kind plus UID plus RECURRENCE-ID (empty for a series master or a
// non-recurring event), which is exactly the identity RFC 5545 guarantees is
// unique within a calendar. `document.foreign.ics.sources[id].components` is
// keyed by this, and each event's `foreign.ics.key` names its own entry --
// so the key must be derivable from the raw component alone (import time and
// the legacy-migration repair both compute it before any event exists yet).
export function eventComponentKey(component) {
  const uid = property(component, "UID")?.value || "";
  const recurrence = property(component, "RECURRENCE-ID")?.value || "";
  return `${component?.name || "VEVENT"}\u0000${uid}\u0000${recurrence}`;
}

// The properties `eventComponent` (below) always regenerates from the model
// regardless of what the original component held -- UID and SUMMARY
// unconditionally, DESCRIPTION and LOCATION set-or-removed either way -- so
// keeping them in retained storage is pure duplication of data that already
// lives in `event.payload`. Stripping them here is what keeps the shared
// source close to the size of the imported ICS text instead of ~2x it:
// DESCRIPTION in particular can carry many kilobytes of HTML per event, and
// every other property (ATTENDEE, VALARM, CLASS, X-*, RECURRENCE-ID, DTSTART
// and friends, ...) is not reconstructible from the model and is kept
// verbatim as the event's irreducible round-trip delta.
const RECONSTRUCTED_PROPERTY_NAMES = new Set(["UID", "SUMMARY", "DESCRIPTION", "LOCATION"]);

export function residualEventComponent(component) {
  return {
    ...component,
    properties: (component.properties || []).filter(
      (item) => !RECONSTRUCTED_PROPERTY_NAMES.has(item.name)
    )
  };
}

function parameter(propertyValue, name) {
  return propertyValue?.params?.find((item) => item.name === name.toUpperCase())?.values?.[0] || null;
}

export function unescapeICSText(value = "") {
  return String(value).replace(/\\([\\;,nN])/g, (whole, escaped) =>
    escaped === "n" || escaped === "N" ? "\n" : escaped
  );
}

export function escapeICSText(value = "") {
  return String(value)
    .replace(/\\/g, "\\\\")
    .replace(/\n/g, "\\n")
    .replace(/,/g, "\\,")
    .replace(/;/g, "\\;");
}

export function parseICSDate(propertyValue) {
  if (!propertyValue) return null;
  const match = /^([+-]?\d{4,})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$/.exec(propertyValue.value);
  if (!match) return null;
  const dateOnly = !match[4] || parameter(propertyValue, "VALUE") === "DATE";
  const levels = [
    { level: "year", value: String(BigInt(match[1])) },
    { level: "month", value: match[2] },
    { level: "day", value: match[3] }
  ];
  if (!dateOnly) {
    levels.push(
      { level: "hour", value: match[4] },
      { level: "minute", value: match[5] },
      { level: "second", value: match[6] }
    );
  }
  return {
    coordinate: coordinate(levels),
    dateOnly,
    utc: Boolean(match[7]),
    timeZone: parameter(propertyValue, "TZID")
  };
}

function parseDuration(value) {
  const match = /^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$/.exec(value || "");
  if (!match) return null;
  const sign = match[1] === "-" ? -1 : 1;
  let seconds = Rational.parse(match[2] || 0).mul(7 * 86400)
    .add(Rational.parse(match[3] || 0).mul(86400))
    .add(Rational.parse(match[4] || 0).mul(3600))
    .add(Rational.parse(match[5] || 0).mul(60))
    .add(Rational.parse(match[6] || 0))
    .mul(sign);
  return seconds;
}

export function parseRRule(value = "") {
  return Object.fromEntries(
    value.split(";").filter(Boolean).map((part) => {
      const index = part.indexOf("=");
      return [part.slice(0, index).toUpperCase(), part.slice(index + 1)];
    })
  );
}

function recurrencePatternSource() {
  return `
// Native RFC 5545 recurrence data is evaluated by the ICS adapter.
export fn state(ctx) = {};
export fn facts(ctx) = [];
`.trim();
}

function componentEntries(calendar) {
  return calendar.components.filter((component) => ["VEVENT", "VTODO"].includes(component.name));
}

function normalizedEntry(component, calendarFrame, sourceId) {
  const uid = property(component, "UID")?.value || createId("ics-uid");
  const start = parseICSDate(property(component, "DTSTART"));
  const end = parseICSDate(property(component, "DTEND"));
  const completed = parseICSDate(property(component, "COMPLETED"));
  const observed = parseICSDate(property(component, "DTSTAMP"));
  const recurrenceId = parseICSDate(property(component, "RECURRENCE-ID"));
  const title = unescapeICSText(property(component, "SUMMARY")?.value || "(untitled)");
  const categories = property(component, "CATEGORIES")?.value
    ?.split(/(?<!\\),/)
    .map(unescapeICSText) || [];
  return {
    component,
    calendarFrame,
    sourceId,
    uid,
    start,
    end,
    completed,
    observed,
    recurrenceId,
    rrule: property(component, "RRULE"),
    exdates: properties(component, "EXDATE").flatMap((item) =>
      item.value.split(",").map((value) => parseICSDate({ ...item, value })).filter(Boolean)
    ),
    title,
    categories,
    task: component.name === "VTODO"
  };
}

function sameTimeTyping(left, right) {
  return Boolean(left?.utc) === Boolean(right?.utc)
    && (left?.timeZone || null) === (right?.timeZone || null);
}

function timedTypingMismatch(date, start) {
  if (!date || !start || date.dateOnly || start.dateOnly) return false;
  return !sameTimeTyping(date, start);
}

function occurrenceKey(date, start) {
  const day = civilCoordinateToDays(date.coordinate);
  if (date.dateOnly && start && !start.dateOnly) {
    const startDay = civilCoordinateToDays(start.coordinate);
    return day.add(startDay.sub(startDay.floor()));
  }
  return day;
}

function eventFromEntry(document, entry, warnings) {
  let duration = Rational.parse(0);
  if (entry.start && entry.end) {
    if (!entry.start.dateOnly && !entry.end.dateOnly && !sameTimeTyping(entry.start, entry.end)) {
      warnings.push(
        `Event ${entry.uid}: DTSTART and DTEND use different time zones; duration is their wall-clock difference`
      );
    }
    duration = civilCoordinateToDays(entry.end.coordinate)
      .sub(civilCoordinateToDays(entry.start.coordinate))
      .mul(86400);
  } else {
    duration = parseDuration(property(entry.component, "DURATION")?.value) || Rational.parse(0);
  }
  const event = addEvent(document, {
    traits: ["event", ...(entry.task ? ["task"] : [])],
    magnitudes: {
      duration: durationMagnitude(duration.toJSON(), "second")
    },
    payload: {
      title: entry.title,
      description: unescapeICSText(property(entry.component, "DESCRIPTION")?.value || ""),
      location: unescapeICSText(property(entry.component, "LOCATION")?.value || ""),
      status: property(entry.component, "STATUS")?.value || "",
      categories: entry.categories,
      uid: entry.uid
    },
    foreign: {
      ics: {
        source: entry.sourceId,
        key: eventComponentKey(entry.component)
      }
    }
  });
  entry.event = event;
  if (entry.start) {
    entry.relation = addRelation(document, {
      type: "attachment",
      event: event.id,
      frame: entry.calendarFrame.id,
      role: entry.task ? "observed" : "placed",
      coordinate: entry.start.coordinate,
      parameters: {
        dateOnly: entry.start.dateOnly,
        utc: entry.start.utc,
        timeZone: entry.start.timeZone
      },
      provenance: { kind: "ics", source: entry.sourceId }
    });
  }
  if (entry.task && entry.observed && !entry.start) {
    addRelation(document, {
      type: "attachment",
      event: event.id,
      frame: entry.calendarFrame.id,
      role: "observed",
      coordinate: entry.observed.coordinate,
      parameters: { utc: entry.observed.utc, timeZone: entry.observed.timeZone, stamp: true },
      provenance: { kind: "ics", source: entry.sourceId }
    });
  }
  if (entry.task && entry.completed) {
    addRelation(document, {
      type: "attachment",
      event: event.id,
      frame: entry.calendarFrame.id,
      role: "completed",
      coordinate: entry.completed.coordinate,
      parameters: { utc: entry.completed.utc, timeZone: entry.completed.timeZone },
      provenance: { kind: "ics", source: entry.sourceId }
    });
  }
  return event;
}

export function importICS(text, document, { label = "Imported calendar" } = {}) {
  const tree = parseICSTree(text);
  const calendars = tree.components.filter((component) => component.name === "VCALENDAR");
  if (!calendars.length) throw new Error("No VCALENDAR component found");
  document.foreign.ics ||= { sources: {} };
  const result = { frames: [], events: [], patterns: [], relations: [], suggestions: [], warnings: [] };
  const existingByUid = new Map();
  for (const event of Object.values(document.events)) {
    const uid = event.payload?.uid;
    if (!uid) continue;
    const ids = existingByUid.get(uid) || [];
    ids.push(event.id);
    existingByUid.set(uid, ids);
  }

  for (const calendar of calendars) {
    const sourceId = createId("ics-source");
    const calendarName = unescapeICSText(
      property(calendar, "X-WR-CALNAME")?.value
      || property(calendar, "NAME")?.value
      || label
    );
    const frame = addFrame(document, {
      title: calendarName,
      traits: ["set", "calendar"],
      basis: "frame:wall-time",
      codec: { kind: "ics", source: sourceId },
      foreign: { ics: { source: sourceId } }
    });
    result.frames.push(frame.id);
    document.foreign.ics.sources[sourceId] = {
      id: sourceId,
      label: calendarName,
      component: {
        ...calendar,
        components: calendar.components.filter(
          (component) => !["VEVENT", "VTODO"].includes(component.name)
        )
      }
    };

    const entries = componentEntries(calendar).map((component) =>
      normalizedEntry(component, frame, sourceId)
    );
    // The shared, once-per-source home for every event's retained ICS data --
    // keyed by `eventComponentKey` so `eventComponent` (export) and the sync
    // reconciler's `sourceEventKey` can find an event's component without
    // either of them holding their own copy of it.
    document.foreign.ics.sources[sourceId].components = Object.fromEntries(
      entries.map((entry) => [eventComponentKey(entry.component), residualEventComponent(entry.component)])
    );
    const uidOccurrences = new Map();
    for (const entry of entries) {
      eventFromEntry(document, entry, result.warnings);
      result.events.push(entry.event.id);
      if (entry.relation) result.relations.push(entry.relation.id);
      if (existingByUid.has(entry.uid)) {
        result.suggestions.push({
          kind: "staple",
          uid: entry.uid,
          events: [...existingByUid.get(entry.uid), entry.event.id]
        });
      }
      const list = uidOccurrences.get(entry.uid) || [];
      list.push(entry);
      uidOccurrences.set(entry.uid, list);
    }

    for (const entry of entries.filter((item) => item.rrule)) {
      for (const date of entry.exdates) {
        if (timedTypingMismatch(date, entry.start)) {
          result.warnings.push(
            `EXDATE for ${entry.uid} uses a different time form than DTSTART; the exclusion may not match any occurrence`
          );
        }
      }
      const pattern = addPattern(document, {
        title: `${entry.title} recurrence`,
        language: "chronolog-formula/1",
        kind: "ics-rrule",
        appliesTo: [frame.id],
        frame: frame.id,
        templateEvent: entry.event.id,
        templateRelation: entry.relation?.id,
        rrule: parseRRule(entry.rrule.value),
        rawRule: entry.rrule,
        exdates: entry.exdates.map((date) => occurrenceKey(date, entry.start).toJSON()),
        exdateProperties: properties(entry.component, "EXDATE").map((item) => ({
          params: item.params,
          values: item.value.split(",").map((value) => {
            const date = parseICSDate({ ...item, value });
            return { value, day: date ? occurrenceKey(date, entry.start).toJSON() : null };
          })
        })),
        source: recurrencePatternSource(),
        exports: { state: "state", facts: "facts" },
        provenance: { kind: "ics", source: sourceId, uid: entry.uid }
      });
      entry.pattern = pattern;
      result.patterns.push(pattern.id);
    }

    for (const [uid, matching] of uidOccurrences) {
      const bases = matching.filter((entry) => entry.pattern);
      const exceptions = matching.filter((entry) => entry.recurrenceId);
      for (const exception of exceptions) {
        const base = bases[0];
        if (!base) continue;
        if (timedTypingMismatch(exception.recurrenceId, base.start)) {
          result.warnings.push(
            `RECURRENCE-ID for ${uid} uses a different time form than DTSTART; the override may not match any occurrence`
          );
        }
        const occurrenceDay = occurrenceKey(exception.recurrenceId, base.start).toJSON();
        const virtualId = stableVirtualId(base.pattern.id, `occurrence-${occurrenceDay}`);
        const override = suppressVirtual(document, virtualId, [exception.event.id]);
        override.provenance = { kind: "ics", source: sourceId, uid };
      }
      if (matching.length > 1 && !bases.length && !exceptions.length) {
        result.suggestions.push({
          kind: "staple",
          uid,
          events: matching.map((entry) => entry.event.id)
        });
      }
    }
    for (const entry of entries) {
      const ids = existingByUid.get(entry.uid) || [];
      ids.push(entry.event.id);
      existingByUid.set(entry.uid, ids);
    }
  }
  touch(document);
  return result;
}

function serializeParams(params = []) {
  return params.map((item) => `;${item.name}=${item.values.map((value) =>
    /[;:,]/.test(value) ? `"${value}"` : value
  ).join(",")}`).join("");
}

function foldLine(line) {
  const bytes = new TextEncoder().encode(line);
  if (bytes.length <= 75) return line;
  const chunks = [];
  let current = "";
  let currentBytes = 0;
  for (const char of line) {
    const length = new TextEncoder().encode(char).length;
    const limit = chunks.length ? 74 : 75;
    if (currentBytes + length > limit) {
      chunks.push(current);
      current = char;
      currentBytes = length;
    } else {
      current += char;
      currentBytes += length;
    }
  }
  if (current) chunks.push(current);
  return chunks.map((chunk, index) => index ? ` ${chunk}` : chunk).join("\r\n");
}

export function serializeComponent(component) {
  const lines = [`BEGIN:${component.name}`];
  for (const item of component.properties || []) {
    lines.push(foldLine(item.verbatim ? item.raw : `${item.name}${serializeParams(item.params)}:${item.value}`));
  }
  for (const child of component.components || []) lines.push(serializeComponent(child));
  lines.push(`END:${component.name}`);
  return lines.join("\r\n");
}

function setProperty(component, name, value, params = []) {
  const existing = component.properties.find((item) => item.name === name);
  const next = { name, params, value };
  if (existing) {
    delete existing.verbatim;
    Object.assign(existing, next);
  } else {
    component.properties.push(next);
  }
}

function removeProperty(component, name) {
  component.properties = component.properties.filter((item) => item.name !== name);
}

function coordinateToICS(value, dateOnly = false, utc = false) {
  // Signed years beyond 0000-9999 deliberately deviate from RFC 5545 so remote dates round-trip.
  const yearValue = BigInt(levelValue(value, "year"));
  const magnitude = yearValue < 0n ? -yearValue : yearValue;
  const year = `${yearValue < 0n ? "-" : ""}${magnitude.toString().padStart(4, "0")}`;
  const month = levelValue(value, "month", "1").padStart(2, "0");
  const day = levelValue(value, "day", "1").padStart(2, "0");
  if (dateOnly) return `${year}${month}${day}`;
  const hour = levelValue(value, "hour", "0").padStart(2, "0");
  const minute = levelValue(value, "minute", "0").padStart(2, "0");
  const second = levelValue(value, "second", "0").padStart(2, "0");
  return `${year}${month}${day}T${hour}${minute}${second}${utc ? "Z" : ""}`;
}

function magnitudeSeconds(event) {
  const levels = event?.magnitudes?.duration?.value?.levels || [];
  let seconds = Rational.parse(0);
  const factors = {
    week: 604800,
    day: 86400,
    hour: 3600,
    minute: 60,
    second: 1,
    subsecond: 1
  };
  for (const level of levels) {
    if (factors[level.level] !== undefined) {
      seconds = seconds.add(Rational.parse(level.value).mul(factors[level.level]));
    }
  }
  return seconds;
}

function startParams(relation) {
  if (relation?.parameters?.dateOnly) return [{ name: "VALUE", values: ["DATE"] }];
  if (relation?.parameters?.timeZone) return [{ name: "TZID", values: [relation.parameters.timeZone] }];
  return [];
}

function icsTimestamp(date) {
  const pad = (value, length = 2) => String(value).padStart(length, "0");
  return `${pad(date.getUTCFullYear(), 4)}${pad(date.getUTCMonth() + 1)}${pad(date.getUTCDate())}`
    + `T${pad(date.getUTCHours())}${pad(date.getUTCMinutes())}${pad(date.getUTCSeconds())}Z`;
}

// Looks up the retained round-trip delta for one event's ICS origin from the
// shared per-source bucket `importICS` populated -- the event itself only
// ever carries `{source, key}`, never its own copy of the component.
function retainedComponent(document, event) {
  const ics = event.foreign?.ics;
  if (!ics?.source || !ics?.key) return null;
  return document?.foreign?.ics?.sources?.[ics.source]?.components?.[ics.key] || null;
}

function eventComponent(document, event, relation, now, componentName = "VEVENT") {
  const original = retainedComponent(document, event);
  const component = original
    ? structuredClone(original)
    : { name: componentName, properties: [], components: [] };
  component.name = event.traits.includes("task") ? "VTODO" : componentName;
  setProperty(component, "UID", event.payload?.uid || event.id);
  setProperty(component, "SUMMARY", escapeICSText(event.payload?.title || "(untitled)"));
  if (event.payload?.description) setProperty(component, "DESCRIPTION", escapeICSText(event.payload.description));
  else removeProperty(component, "DESCRIPTION");
  if (event.payload?.location) setProperty(component, "LOCATION", escapeICSText(event.payload.location));
  else removeProperty(component, "LOCATION");
  if (event.payload?.status) setProperty(component, "STATUS", event.payload.status);
  if (event.payload?.categories?.length) {
    setProperty(component, "CATEGORIES", event.payload.categories.map(escapeICSText).join(","));
  }
  if (event.traits.includes("task")) {
    const taskRelations = Object.values(document.relations).filter(
      (item) => item.type === "attachment" && item.event === event.id
    );
    const observed = taskRelations.find((item) => item.role === "observed") || relation;
    const completed = taskRelations.find((item) => item.role === "completed");
    if (observed?.coordinate) {
      if (observed.parameters?.stamp) {
        setProperty(component, "DTSTAMP", coordinateToICS(observed.coordinate, false, true));
      } else {
        setProperty(
          component,
          "DTSTART",
          coordinateToICS(
            observed.coordinate,
            Boolean(observed.parameters?.dateOnly),
            Boolean(observed.parameters?.utc)
          ),
          startParams(observed)
        );
      }
    }
    if (completed?.coordinate) {
      setProperty(
        component,
        "COMPLETED",
        coordinateToICS(completed.coordinate, false, completed.parameters?.utc !== false)
      );
    } else {
      removeProperty(component, "COMPLETED");
    }
  } else if (relation?.coordinate) {
    const dateOnly = Boolean(relation.parameters?.dateOnly);
    const utc = Boolean(relation.parameters?.utc);
    const params = startParams(relation);
    setProperty(component, "DTSTART", coordinateToICS(relation.coordinate, dateOnly, utc), params);
    const seconds = magnitudeSeconds(event);
    if (seconds.compare(0) > 0) {
      const end = civilCoordinateToDays(relation.coordinate).add(seconds.div(86400));
      setProperty(component, "DTEND", coordinateToICS(daysToCivilCoordinate(end), dateOnly, utc), params);
      removeProperty(component, "DURATION");
    }
  }
  if (!property(component, "DTSTAMP")) {
    setProperty(component, "DTSTAMP", icsTimestamp(now || new Date()));
  }
  return component;
}

export function exportICS(document, {
  frame,
  start,
  end,
  engine,
  now = new Date(),
  productId = "-//Chronolog//Chronolog 1//EN"
}) {
  const calendarFrame = document.frames[frame];
  if (!calendarFrame) throw new Error(`Unknown calendar frame ${frame}`);
  const sourceId = calendarFrame.foreign?.ics?.source;
  const source = sourceId && document.foreign.ics?.sources?.[sourceId];
  const original = source?.component;
  const calendar = {
    name: "VCALENDAR",
    properties: original
      ? structuredClone(original.properties)
      : [
          { name: "VERSION", params: [], value: "2.0" },
          { name: "PRODID", params: [], value: productId },
          { name: "CALSCALE", params: [], value: "GREGORIAN" }
        ],
    components: original
      ? structuredClone(original.components.filter((item) => !["VEVENT", "VTODO"].includes(item.name)))
      : []
  };
  setProperty(calendar, "X-WR-CALNAME", escapeICSText(calendarFrame.title));

  const nativePatterns = Object.values(document.patterns).filter(
    (pattern) => pattern.kind === "ics-rrule" && pattern.frame === frame
  );
  const templateRelations = new Set(nativePatterns.map((pattern) => pattern.templateRelation));
  const windowStart = start ? civilCoordinateToDays(start) : null;
  const windowEnd = end ? civilCoordinateToDays(end) : null;
  const attachments = Object.values(document.relations).filter((relation) => {
    if (relation.type !== "attachment" || relation.frame !== frame) return false;
    if (templateRelations.has(relation.id)) return true;
    if (!windowStart || !windowEnd || !relation.coordinate) return true;
    const day = civilCoordinateToDays(relation.coordinate);
    return day.compare(windowStart) >= 0 && day.compare(windowEnd) <= 0;
  });

  const exportedTasks = new Set();
  for (const relation of attachments) {
    const event = document.events[relation.event];
    if (!event) continue;
    if (event.traits.includes("task")) {
      if (relation.role === "completed" || exportedTasks.has(event.id)) continue;
      exportedTasks.add(event.id);
    }
    const component = eventComponent(document, event, relation, now);
    const pattern = nativePatterns.find((item) => item.templateRelation === relation.id);
    if (pattern) {
      // An end-staple is separate authored data, never written into
      // `pattern.rrule.UNTIL` (LEXICON's staple anchoring / Rob-and-John
      // scenario: the rule keeps saying what it says). So the effective stop
      // is derived here, at export time, and never persisted back onto the
      // pattern. COUNT and an end-staple both bound the series, but RFC 5545
      // forbids exporting COUNT and UNTIL together -- deriving a combined
      // UNTIL would silently drop the COUNT semantics on round-trip, so a
      // staple on a COUNT-based rule is left as authored (a later wave's
      // problem) rather than guessed at here.
      let effectiveRrule = pattern.rrule;
      if (engine && seriesEndStaple(document, pattern.id) && recurrenceEndMode(pattern.rrule) !== "count") {
        const effectiveDays = seriesEffectiveUntilDays(engine, pattern);
        if (effectiveDays) {
          try {
            effectiveRrule = {
              ...(pattern.rrule || {}),
              UNTIL: recurrenceUntilForCoordinate(engine.daysCoordinate(pattern.frame, effectiveDays))
            };
          } catch {
            effectiveRrule = pattern.rrule;
          }
        }
      }
      const rule = effectiveRrule && Object.keys(effectiveRrule).length
        ? Object.entries(effectiveRrule).map(([key, value]) => `${key}=${value}`).join(";")
        : pattern.rawRule?.value || "";
      setProperty(component, "RRULE", rule);
      const exdateIndex = component.properties.findIndex((item) => item.name === "EXDATE");
      removeProperty(component, "EXDATE");
      const exdateProperties = [];
      const remaining = new Set(pattern.exdates || []);
      for (const stored of pattern.exdateProperties || []) {
        const kept = stored.values.filter((item) => item.day === null || remaining.has(item.day));
        for (const item of kept) remaining.delete(item.day);
        if (kept.length) {
          exdateProperties.push({
            name: "EXDATE",
            params: stored.params || [],
            value: kept.map((item) => item.value).join(",")
          });
        }
      }
      if (remaining.size) {
        exdateProperties.push({
          name: "EXDATE",
          params: startParams(relation),
          value: [...remaining].map((day) => coordinateToICS(
            daysToCivilCoordinate(day),
            Boolean(relation.parameters?.dateOnly),
            Boolean(relation.parameters?.utc)
          )).join(",")
        });
      }
      if (exdateIndex >= 0) component.properties.splice(exdateIndex, 0, ...exdateProperties);
      else component.properties.push(...exdateProperties);
    }
    calendar.components.push(component);
  }

  if (engine && start && end) {
    const generated = engine.queryFacts({ frame, start, end }).facts.filter(
      (fact) => fact.kind === "virtual"
        && !nativePatterns.some((pattern) => fact.virtualId.startsWith(`${pattern.id}/`))
    );
    for (const fact of generated) {
      calendar.components.push(eventComponent(document, fact.event, fact.relation, now));
    }
  }

  return serializeComponent(calendar) + "\r\n";
}

