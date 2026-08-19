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
  putStaple,
  stableVirtualId,
  suppressVirtual,
  touch
} from "./model.js";
import { recurrenceEndMode, recurrenceUntilForCoordinate } from "./recurrence-end.js";
import { resolveObjectExtent, seriesSegments, staplesForObject } from "./staples.js";

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
//
// X-CHRONOLOG-ANCHOR/-SPREAD join this set for the same reason: they are
// ChronoLog's own reserved namespace (not a foreign calendar's data), and
// `applyAnchorAnnotations` always clears and rebuilds them fresh from
// `staplesForObject` on every export -- so retaining a stale copy from a
// prior import would be pure duplication too, same as UID/SUMMARY above.
const RECONSTRUCTED_PROPERTY_NAMES = new Set([
  "UID",
  "SUMMARY",
  "DESCRIPTION",
  "LOCATION",
  "X-CHRONOLOG-ANCHOR",
  "X-CHRONOLOG-SPREAD"
]);

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

// One derivation of an entry's duration in seconds, shared by a primary
// event/task (`eventFromEntry`) and a following segment's own magnitude
// (`importFollowingSegmentStaple`) -- both read DTSTART/DTEND or DURATION off
// a raw component the same way, so this is the one place that comparison
// lives rather than a second copy of it.
function entryDurationSeconds(entry, warnings) {
  if (entry.start && entry.end) {
    if (!entry.start.dateOnly && !entry.end.dateOnly && !sameTimeTyping(entry.start, entry.end)) {
      warnings.push(
        `Event ${entry.uid}: DTSTART and DTEND use different time zones; duration is their wall-clock difference`
      );
    }
    return civilCoordinateToDays(entry.end.coordinate)
      .sub(civilCoordinateToDays(entry.start.coordinate))
      .mul(86400);
  }
  return parseDuration(property(entry.component, "DURATION")?.value) || Rational.parse(0);
}

// A day-fraction magnitude, exact throughout (Rational text, never a float) --
// the reconstruction target for an anchor's OFFSET param and a staple's
// SPREAD BEFORE/AFTER params (see `applyAnchorAnnotations`, the export side).
// ICS has no native concept of src/staples.js's nested-level magnitude shape,
// so this collapses to a single "day" level; the VALUE it resolves to
// (via `durationMagnitudeDays`) is exact and identical either way, which is
// what a fuzziness/offset amount actually is for -- the level breakdown
// (e.g. authored as "2 hours" vs "1/12 day") is not preserved, only the
// resolved magnitude, and that is a documented limitation of the encoding.
function dayFractionMagnitude(text) {
  return { frame: "measure:human-time", value: { levels: [{ level: "day", value: text }] } };
}

// Reconstructs the object-anchor staples an export wrote as X-CHRONOLOG-ANCHOR
// / X-CHRONOLOG-SPREAD properties (see `applyAnchorAnnotations`). A calendar
// with none of these properties -- any calendar that is not a ChronoLog
// re-import -- gets no staples invented: MEANING IS AUTHORED, NEVER INFERRED,
// so this only ever reconstructs what an earlier ChronoLog export explicitly
// wrote, never a guess from a title, a category, or a duration.
//
// Anchors are reconstructed against THIS import's own calendar frame, not
// whatever frame id the export happened to carry -- a fresh import always
// mints a fresh frame (see `addFrame` below), so a raw foreign frame id could
// never resolve anyway. The exact wall-clock instant round-trips regardless,
// because the encoding is an ICS timestamp, not a frame-relative value.
function importAnchorStaples(document, component, objectId, calendarFrameId) {
  const anchorProps = properties(component, "X-CHRONOLOG-ANCHOR");
  if (!anchorProps.length) return;
  const spreadById = new Map();
  for (const prop of properties(component, "X-CHRONOLOG-SPREAD")) {
    const id = parameter(prop, "ID");
    if (!id) continue;
    const before = parameter(prop, "BEFORE");
    const after = parameter(prop, "AFTER");
    if (!before && !after) continue;
    spreadById.set(id, {
      ...(before ? { before: dayFractionMagnitude(before) } : {}),
      ...(after ? { after: dayFractionMagnitude(after) } : {})
    });
  }
  for (const prop of anchorProps) {
    const parsed = parseICSDate(prop);
    if (!parsed) continue;
    const role = parameter(prop, "ROLE") || "start";
    const offset = parameter(prop, "OFFSET");
    const id = parameter(prop, "ID");
    const spread = id ? spreadById.get(id) : null;
    putStaple(document, {
      object: objectId,
      kind: "anchor",
      role,
      frame: calendarFrameId,
      coordinate: parsed.coordinate,
      ...(offset ? { payload: { offset: dayFractionMagnitude(offset) } } : {}),
      ...(spread ? { spread } : {})
    });
  }
}

function eventFromEntry(document, entry, warnings) {
  const duration = entryDurationSeconds(entry, warnings);
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
  importAnchorStaples(document, entry.component, event.id, entry.calendarFrame.id);
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

    // A following segment (a series' rule-change sibling VEVENT, carrying
    // X-CHRONOLOG-SERIES and X-CHRONOLOG-SEGMENT-INDEX -- see
    // `followingSegmentComponent`, the export side) is not a new event or
    // pattern: it is one inflection staple on the base series, reconstructed
    // below by `importFollowingSegmentStaple`. Excluded from `entries` here so
    // the ordinary event/pattern machinery below never sees it -- otherwise a
    // ChronoLog re-import would manufacture a spurious standalone event for
    // every following segment, alongside the staple that already reconstructs
    // it. A calendar missing either property is treated as an ordinary event:
    // only both together identify a ChronoLog-authored sibling.
    const allEntries = componentEntries(calendar).map((component) =>
      normalizedEntry(component, frame, sourceId)
    );
    const segmentEntries = allEntries.filter((entry) =>
      property(entry.component, "X-CHRONOLOG-SERIES") && property(entry.component, "X-CHRONOLOG-SEGMENT-INDEX"));
    const segmentEntrySet = new Set(segmentEntries);
    const entries = allEntries.filter((entry) => !segmentEntrySet.has(entry));
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

    for (const segmentEntry of segmentEntries) {
      const seriesUid = property(segmentEntry.component, "X-CHRONOLOG-SERIES")?.value;
      const basePatternEntry = entries.find((entry) => entry.uid === seriesUid && entry.pattern);
      if (!basePatternEntry) continue;
      importFollowingSegmentStaple(document, segmentEntry, basePatternEntry.pattern, frame, result.warnings);
    }
  }
  touch(document);
  return result;
}

// Reconstructs one following segment's inflection staple from a sibling
// VEVENT the export side wrote (`followingSegmentComponent`). X-CHRONOLOG-
// INFLECTION carries the partitioning staple's OWN coordinate and frame --
// the exact instant the reigning rule stops -- as its own property rather
// than being derived from the sibling's DTSTART, because those are two
// independently authored values (LEXICON's Rob-and-John scenario: the
// inflection point and the new rule's own first occurrence need not be the
// same weekday, time, or even the same day). Missing that property means
// nothing to anchor the partition to, so this reconstructs nothing rather
// than guess.
function importFollowingSegmentStaple(document, segmentEntry, pattern, frame, warnings) {
  const inflectionProperty = property(segmentEntry.component, "X-CHRONOLOG-INFLECTION");
  const inflectionDate = inflectionProperty ? parseICSDate(inflectionProperty) : null;
  if (!inflectionDate) return;
  const seconds = entryDurationSeconds(segmentEntry, warnings);
  // Reconstructed against THIS import's own calendar frame, not whatever
  // frame id the export happened to carry in the FRAME param -- a fresh
  // import always mints a fresh frame (see `addFrame` above), so a raw
  // foreign frame id could never resolve anyway. Same reasoning as
  // `importAnchorStaples`: the exact wall-clock instant round-trips
  // regardless, because the encoding is an ICS timestamp, not a
  // frame-relative value.
  putStaple(document, {
    series: pattern.id,
    kind: "inflection",
    frame: frame.id,
    coordinate: inflectionDate.coordinate,
    payload: {
      rule: {
        rrule: segmentEntry.rrule ? parseRRule(segmentEntry.rrule.value) : {},
        coordinate: segmentEntry.start?.coordinate,
        frame: frame.id,
        magnitude: durationMagnitude(seconds.toJSON(), "second"),
        exdates: segmentEntry.exdates.map((date) => occurrenceKey(date, segmentEntry.start).toJSON())
      }
    }
  });
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

// Unlike `setProperty`, always adds a new property line rather than replacing
// one of the same name -- RFC 5545 allows repeating an X-property, and that
// repetition is exactly how multiple object staples (one X-CHRONOLOG-ANCHOR /
// X-CHRONOLOG-SPREAD pair per staple) are represented on a single VEVENT.
function appendProperty(component, name, value, params = []) {
  component.properties.push({ name, params, value });
}

// A coordinate with no time-of-day levels at all is date-only, the same test
// `parseICSDate` uses on import (`!match[4]`) -- a structural fact about the
// coordinate's own level list, not a guess about what it means.
function coordinateIsDateOnly(value) {
  return !(value?.levels || []).some((level) => level.level === "hour");
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

function magnitudeSecondsFromMagnitude(magnitude) {
  const levels = magnitude?.value?.levels || [];
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

function magnitudeSeconds(event) {
  return magnitudeSecondsFromMagnitude(event?.magnitudes?.duration);
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

// Anchors, magnitudes, and spreads are ChronoLog-native (LEXICON's staple
// anchoring): every other calendar needs the DERIVED extent as ordinary
// DTSTART/DTEND, so an end-anchored shift does not export as a broken event,
// while a ChronoLog re-import needs the AUTHORED INTENT losslessly. This
// carries both: it overwrites DTSTART/DTEND with `resolveObjectExtent`'s
// resolved days only when the object actually carries an anchor (an
// unstapled object resolves identically to its own placement relation, per
// src/staples.js's own doc comment, so leaving the untouched code path alone
// for that overwhelmingly common case keeps a re-export of an unchanged
// document byte-identical), and appends one X-CHRONOLOG-ANCHOR / optional
// X-CHRONOLOG-SPREAD pair per staple on the object, stale copies cleared
// first so a changed staple set never leaves an orphaned property behind.
//
// Encoding: X-CHRONOLOG-ANCHOR;ID=<staple id>;ROLE=<role>[;OFFSET=<exact day
// fraction>]:<ICS timestamp of the staple's own coordinate, always full
// precision, never VALUE=DATE>. X-CHRONOLOG-SPREAD;ID=<staple id>
// [;BEFORE=<exact day fraction>][;AFTER=<exact day fraction>]:<role, for a
// human reading the file>. Every magnitude is an exact Rational day-fraction
// TEXT (`Rational.toJSON`), never a float -- `dayFractionMagnitude` parses it
// straight back with no rounding. ID correlates an ANCHOR/SPREAD pair (and
// disambiguates the rare overdetermined case of two anchors sharing a role);
// it is ChronoLog's own internal relation id, meaningless to any other
// calendar, which is exactly what an X-property is for.
function applyAnchorAnnotations(component, document, engine, event) {
  if (!engine || !event?.id) return;
  const staples = staplesForObject(document, event.id);
  removeProperty(component, "X-CHRONOLOG-ANCHOR");
  removeProperty(component, "X-CHRONOLOG-SPREAD");
  if (!staples.length) return;
  const extent = resolveObjectExtent(document, engine, event.id);
  if (extent.anchors.length && extent.frame && extent.startDays !== null && extent.endDays !== null) {
    try {
      const startCoordinate = engine.daysCoordinate(extent.frame, extent.startDays);
      setProperty(component, "DTSTART", coordinateToICS(startCoordinate, false, false));
      const durationDays = extent.endDays.sub(extent.startDays);
      if (durationDays.compare(0) > 0) {
        setProperty(component, "DTEND", coordinateToICS(engine.daysCoordinate(extent.frame, extent.endDays), false, false));
      } else {
        removeProperty(component, "DTEND");
      }
    } catch {
      // Leave the placement-derived DTSTART/DTEND from `eventComponent` as-is
      // rather than export a broken time from an unresolvable frame.
    }
  }
  for (const staple of staples) {
    appendProperty(
      component,
      "X-CHRONOLOG-ANCHOR",
      coordinateToICS(staple.coordinate, false, false),
      [
        { name: "ID", values: [staple.id] },
        { name: "ROLE", values: [staple.role || "start"] },
        ...(staple.payload?.offset
          ? [{ name: "OFFSET", values: [durationMagnitudeSecondsAsDays(staple.payload.offset)] }]
          : [])
      ]
    );
    if (staple.spread) {
      const before = staple.spread.before ? durationMagnitudeSecondsAsDays(staple.spread.before) : null;
      const after = staple.spread.after ? durationMagnitudeSecondsAsDays(staple.spread.after) : null;
      if (before || after) {
        appendProperty(component, "X-CHRONOLOG-SPREAD", staple.role || "start", [
          { name: "ID", values: [staple.id] },
          ...(before ? [{ name: "BEFORE", values: [before] }] : []),
          ...(after ? [{ name: "AFTER", values: [after] }] : [])
        ]);
      }
    }
  }
}

// The exact day-fraction text a magnitude resolves to (`Rational.toJSON`,
// never a float) -- what `dayFractionMagnitude` on the import side parses
// straight back with no rounding.
function durationMagnitudeSecondsAsDays(magnitude) {
  return magnitudeSecondsFromMagnitude(magnitude).div(86400).toJSON();
}

// The ICS text an RRULE's own UNTIL parses to, in exact Rational days -- the
// same regex `engine.js`'s private `compactIcsDay` uses, reimplemented here
// only because that one is not exported (only the whole-pattern
// `seriesEffectiveUntilDays`, segment 0's cutoff, is). Reuses this file's own
// `parseICSDate` rather than a second date parser.
function icsRuleUntilDays(rrule) {
  const until = rrule?.UNTIL;
  if (!until) return null;
  const parsed = parseICSDate({ value: until });
  return parsed ? civilCoordinateToDays(parsed.coordinate) : null;
}

// A following segment's own effective stop: the earlier of its own written
// RRULE UNTIL and the staple that closes it (`segment.untilDays`, null for a
// series' final segment). Mirrors src/engine.js's private
// `segmentEffectiveUntilDays` exactly (same two-value Rational minimum) --
// that function only serves segment 0 under the exported name
// `seriesEffectiveUntilDays`, which this file keeps using unchanged; segment
// 1 and beyond have no existing export to reuse, so this is the equivalent
// arithmetic for them, in exact Rational days throughout, never a string
// comparison.
function segmentUntilDaysLocal(segment) {
  const ruleUntil = icsRuleUntilDays(segment?.rrule);
  const stapleUntil = segment?.untilDays ?? null;
  if (!stapleUntil) return ruleUntil;
  if (!ruleUntil) return stapleUntil;
  return ruleUntil.compare(stapleUntil) <= 0 ? ruleUntil : stapleUntil;
}

// How many occurrences of THIS segment's rule actually survive through the
// staple that closes it -- the truncated COUNT that keeps a COUNT-based rule
// legal (RFC 5545 forbids COUNT and UNTIL together) without silently
// dropping the COUNT semantics or the staple. `engine.queryFacts` already
// enforces this exact segment's own COUNT and its closing staple's UNTIL
// together when it generates occurrenceFacts (src/engine.js), so counting
// the virtual facts it returns for exactly this segment's window IS the
// truncated count; no RRULE math is re-derived here, only asked of the one
// authority that already computes it.
function truncatedSegmentCount(engine, pattern, segment) {
  if (!engine || segment?.untilDays == null) return null;
  const frame = pattern.frame;
  if (!frame) return null;
  let lowerDays = segment.fromDays;
  if (lowerDays === null) {
    const relation = engine.document.relations[pattern.templateRelation];
    if (!relation?.coordinate) return null;
    try {
      lowerDays = engine.coordinateDays(relation.frame, relation.coordinate);
    } catch {
      return null;
    }
  }
  let windowStart, windowEnd;
  try {
    windowStart = engine.daysCoordinate(frame, lowerDays);
    windowEnd = engine.daysCoordinate(frame, segment.untilDays);
  } catch {
    return null;
  }
  let facts;
  try {
    facts = engine.queryFacts({
      frame,
      start: windowStart,
      end: windowEnd,
      limit: Infinity,
      applyOverrides: false
    }).facts;
  } catch {
    return null;
  }
  return facts.filter((fact) => fact.kind === "virtual" && fact.virtualId.startsWith(`${pattern.id}/`)).length;
}

// Fresh EXDATE properties for a following segment's own exclusions
// (`segment.exdates`, day-JSON Rational strings) -- there is no "original ICS
// text" to preserve here the way segment 0's `exdateProperties` preserves an
// import's own formatting, because a following segment's exdates are
// ChronoLog-authored data with no prior ICS representation at all.
function exdatePropertiesForSegment(segment, dateOnly, utc, params) {
  const days = segment.exdates || [];
  if (!days.length) return [];
  const value = days
    .map((day) => coordinateToICS(daysToCivilCoordinate(Rational.parse(day)), dateOnly, utc))
    .join(",");
  return [{ name: "EXDATE", params, value }];
}

// The RRULE text for one following segment, applying the same COUNT-vs-UNTIL
// legality rule segment 0 gets (see the COUNT branch in `exportICS`, and
// `truncatedSegmentCount`/`segmentUntilDaysLocal` above).
function followingSegmentRuleText(engine, pattern, segment) {
  let rrule = segment.rrule || {};
  if (recurrenceEndMode(rrule) === "count") {
    if (segment.untilDays != null) {
      const truncated = truncatedSegmentCount(engine, pattern, segment);
      if (truncated !== null) {
        rrule = { ...rrule };
        delete rrule.UNTIL;
        rrule.COUNT = String(truncated);
      }
    }
  } else {
    const effectiveDays = segmentUntilDaysLocal(segment);
    if (effectiveDays) {
      try {
        rrule = {
          ...rrule,
          UNTIL: recurrenceUntilForCoordinate(engine.daysCoordinate(segment.frame || pattern.frame, effectiveDays))
        };
      } catch {
        // Leave the segment's own authored UNTIL (or none) as-is.
      }
    }
  }
  return Object.keys(rrule).length ? Object.entries(rrule).map(([key, value]) => `${key}=${value}`).join(";") : "";
}

// One following segment's sibling VEVENT. A following segment has no VEVENT
// of its own anywhere in the document -- it is staple payload
// (src/staples.js's `seriesSegments`), not a materialized record -- so this
// builds the component fresh on every export rather than reading/writing a
// retained copy the way `eventComponent` does for a real event.
function followingSegmentComponent(document, engine, pattern, segment, index, baseUid, now) {
  if (!segment?.baseCoordinate || !baseUid) return null;
  const templateEvent = document.events[pattern.templateEvent];
  const templateRelation = document.relations[pattern.templateRelation];
  const component = { name: "VEVENT", properties: [], components: [] };
  // A deterministic, stable UID derived from the base UID plus the segment
  // index -- a re-export of an unchanged document must produce byte-identical
  // UIDs, never a random one, or every sync would churn.
  setProperty(component, "UID", `${baseUid}.chronolog-segment-${index}`);
  setProperty(component, "SUMMARY", escapeICSText(templateEvent?.payload?.title || "(untitled)"));
  if (templateEvent?.payload?.description) {
    setProperty(component, "DESCRIPTION", escapeICSText(templateEvent.payload.description));
  }
  if (templateEvent?.payload?.location) {
    setProperty(component, "LOCATION", escapeICSText(templateEvent.payload.location));
  }
  const dateOnly = coordinateIsDateOnly(segment.baseCoordinate);
  const utc = Boolean(templateRelation?.parameters?.utc);
  const params = dateOnly
    ? [{ name: "VALUE", values: ["DATE"] }]
    : templateRelation?.parameters?.timeZone
      ? [{ name: "TZID", values: [templateRelation.parameters.timeZone] }]
      : [];
  setProperty(component, "DTSTART", coordinateToICS(segment.baseCoordinate, dateOnly, utc), params);
  const magnitude = segment.magnitude || templateEvent?.magnitudes?.duration;
  const seconds = magnitudeSecondsFromMagnitude(magnitude);
  if (seconds.compare(0) > 0) {
    const startDays = civilCoordinateToDays(segment.baseCoordinate);
    const endDays = startDays.add(seconds.div(86400));
    setProperty(component, "DTEND", coordinateToICS(daysToCivilCoordinate(endDays), dateOnly, utc), params);
  }
  setProperty(component, "RRULE", followingSegmentRuleText(engine, pattern, segment));
  for (const exdate of exdatePropertiesForSegment(segment, dateOnly, utc, params)) {
    component.properties.push(exdate);
  }
  setProperty(component, "X-CHRONOLOG-SERIES", baseUid);
  setProperty(component, "X-CHRONOLOG-SEGMENT-INDEX", String(index));
  // The partitioning staple's OWN coordinate/frame -- the exact inflection
  // point, independent of this segment's own DTSTART (LEXICON's Rob-and-John
  // scenario: the inflection point and the new rule's first occurrence are
  // two separately authored values, not the same instant in general).
  const opener = segment.openedBy;
  if (opener?.frame && opener?.coordinate) {
    setProperty(
      component,
      "X-CHRONOLOG-INFLECTION",
      coordinateToICS(opener.coordinate, false, false),
      [{ name: "FRAME", values: [opener.frame] }]
    );
  }
  setProperty(component, "DTSTAMP", icsTimestamp(now || new Date()));
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
    applyAnchorAnnotations(component, document, engine, event);
    const pattern = nativePatterns.find((item) => item.templateRelation === relation.id);
    if (pattern) {
      // An end/inflection staple is separate authored data, never written
      // into `pattern.rrule.UNTIL` (LEXICON's staple anchoring / Rob-and-John
      // scenario: the rule keeps saying what it says). So the effective stop
      // is derived here, at export time, and never persisted back onto the
      // pattern. Guarded by segment 0's own `untilDays` -- NOT `seriesIsSegmented`,
      // which asks "does this series have more than one ACTIVE rule segment"
      // and is deliberately false for a plain end-staple (no following rule,
      // by src/staples.js's own doc comment: "one staple with no following
      // rule yields ... a bounded segment 0 and nothing after it"). Segment 0
      // can be bounded without the series being segmented, so this checks the
      // bound directly -- an unstapled series' rule text stays untouched (a
      // re-export of an unchanged document stays byte-identical) because only
      // an ACTUAL partitioning staple sets `untilDays` at all.
      let effectiveRrule = pattern.rrule;
      const segment0 = engine ? seriesSegments(engine, pattern)[0] : null;
      if (segment0?.untilDays != null) {
        if (recurrenceEndMode(pattern.rrule) === "count") {
          // RFC 5545 forbids COUNT and UNTIL in the same rule. ROADMAP #4's
          // open item: rather than write an illegal UNTIL alongside COUNT (or
          // silently drop the staple), the emitted set is truncated by
          // shrinking COUNT itself to however many occurrences the engine's
          // own projection -- which already enforces this segment's COUNT and
          // its closing staple together -- actually produces through the
          // staple. No RRULE math is re-derived here; the engine is the one
          // authority for "how many occurrences actually happen".
          const truncated = truncatedSegmentCount(engine, pattern, segment0);
          if (truncated !== null) {
            effectiveRrule = { ...(pattern.rrule || {}) };
            delete effectiveRrule.UNTIL;
            effectiveRrule.COUNT = String(truncated);
          }
        } else {
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
    // A series whose rule changes part-way through cannot be one VEVENT --
    // RFC 5545 has no concept of it. Every segment after segment 0 (already
    // above, as `component`) becomes its own sibling VEVENT with its own
    // DTSTART/DURATION/RRULE, carrying X-CHRONOLOG-SERIES so a ChronoLog
    // re-import rejoins them into one identity while any other calendar
    // simply sees the real meetings -- hiding them would be data loss.
    if (pattern && engine) {
      const baseUid = property(component, "UID")?.value;
      const segments = seriesSegments(engine, pattern);
      for (let index = 1; index < segments.length; index += 1) {
        const sibling = followingSegmentComponent(document, engine, pattern, segments[index], index, baseUid, now);
        if (sibling) calendar.components.push(sibling);
      }
    }
  }

  if (engine && start && end) {
    const generated = engine.queryFacts({ frame, start, end }).facts.filter(
      (fact) => fact.kind === "virtual"
        && !nativePatterns.some((pattern) => fact.virtualId.startsWith(`${pattern.id}/`))
    );
    for (const fact of generated) {
      const generatedComponent = eventComponent(document, fact.event, fact.relation, now);
      applyAnchorAnnotations(generatedComponent, document, engine, fact.event);
      calendar.components.push(generatedComponent);
    }
  }

  return serializeComponent(calendar) + "\r\n";
}

