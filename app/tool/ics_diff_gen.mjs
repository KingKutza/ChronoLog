// Differential harness for the ICS boundary, JavaScript side. Generates random
// ICS files from a fixed seed, runs each one through the shipped `src/ics.js`
// import AND export, and writes every answer as an exact string to stdout as one
// JSON document. `app/tool/ics_diff_check.dart` replays the SAME FILE TEXT
// through `lib/core/ics.dart` and compares.
//
// Nothing here is a test of the JavaScript. It is the ORACLE: any disagreement is
// either a port defect or a deliberate, documented deviation.
//
// EVERY ICS INPUT IS A STRING THIS FILE BUILT. No fixture on disk is read, and
// nothing here reaches for a `.ics` file -- the fixtures directory holds
// untracked personal calendar data and this harness must never touch it.
//
// THE RULED DIVERGENCE CLASSES, generated deliberately and marked:
//
//   D1 -- the X-CHRONOLOG dialect. `importICS` reconstructs object anchors from
//         `X-CHRONOLOG-ANCHOR`/`-SPREAD` and a segmented series from
//         `-SERIES`/`-SEGMENT-INDEX`/`-INFLECTION`, and `exportICS` writes all six
//         back. The dialect is DEAD in the port both directions: those properties
//         are somebody's X- properties now and ride through verbatim, so a
//         dialect-bearing file diverges BY DESIGN in both semantics and bytes.
//         Counted, never compared. Split below into the anchor carrier and the
//         SERIES carrier, because the second is also the whole of how the
//         JavaScript export produces sibling segment VEVENTs -- a generated ICS
//         file has no other way to make a segmented series.
//
//   D2 -- VTODO. The mapping is ruled ON HOLD, so the port retains a VTODO
//         verbatim (like VJOURNAL) instead of minting a task. The VEVENT
//         semantics still agree and are still compared; only the EXPORT diverges,
//         because the JavaScript lifts the VTODO out of the calendar shell and
//         re-emits it after every VEVENT while the port leaves it where the file
//         put it. Export counted, semantics compared.
//
//   D3 -- a malformed RRULE part with no `=` at all. `parseRRule` in the
//         JavaScript keys it on `part.slice(0, -1)` and values it on the whole
//         part, eating the last character; the port keeps the part under its own
//         name with an empty value. A fixed defect, not a port defect. Counted.
//
// Run, from app/:
//
//   dart run tool/ics_diff_check.dart
//
// which shells out to node itself. To keep the cases for inspection, redirect
// into app/build/ (already ignored):
//
//   node tool/ics_diff_gen.mjs > build/ics-diff-cases.json
//   dart run tool/ics_diff_check.dart build/ics-diff-cases.json

import { ChronologEngine } from "../../src/engine.js";
import { coordinate } from "../../src/exact.js";
import { durationMagnitudeDays } from "../../src/coordinate-law.js";
import { exportICS, importICS } from "../../src/ics.js";
import { createStructuralDocument } from "../../test/helpers/sample-document.js";

const SEED = 20260827;
const NOW = new Date(Date.UTC(2026, 7, 7, 12, 0, 0));
const PRODUCT_ID = "-//Chronolog//Diff//EN";

function mulberry32(seed) {
  return function next() {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const random = mulberry32(SEED);
const int = (bound) => Math.floor(random() * bound);
const pick = (list) => list[int(list.length)];
const coin = () => random() < 0.5;
const chance = (odds) => random() < odds;

// --- The grammar ------------------------------------------------------------
//
// Text values draw only CANONICAL escapes -- `\\`, `\;`, `\,`, `\n` -- because a
// stray backslash before any other character is preserved by both sides
// identically but is not a fixed point of escape/unescape, and mixing the two
// would blur a parity failure into a round-trip observation.

const WORDS = ["status", "sync", "review", "Ops", "1:1", "planning", "hand-off", "retro"];
const EXOTIC = ["café", "naïve", "日本の予定", "Ωμέγα", "🌍 planet", "ключ", "a\u0301bc"];
const ZONES = ["Test/Zone", "Europe/Berlin", "America/New_York", "GMT Standard Time"];

function text(depth = 0) {
  const parts = [pick(WORDS)];
  if (chance(0.3)) parts.push(pick(EXOTIC));
  if (chance(0.25)) parts.push("a\\, b");
  if (chance(0.2)) parts.push("semi\\; colon");
  if (chance(0.2)) parts.push("C:\\\\new folder");
  if (chance(0.15)) parts.push("line\\nbreak");
  if (chance(0.1) && depth < 1) parts.push(text(depth + 1));
  return parts.join(" ");
}

function longText() {
  const body = [];
  for (let i = 0; i < 3 + int(6); i += 1) body.push(text());
  return body.join(" and then ");
}

// A year drawn to exercise the deliberate RFC deviation: mostly ordinary, and
// sometimes signed or longer than four digits.
function year(recurring) {
  if (recurring || chance(0.75)) return String(2020 + int(11));
  return pick(["-0044", "-1", "0001", "100002026", "12345"]);
}

function stamp(recurring, dateOnly) {
  const y = year(recurring);
  const signed = y.startsWith("-");
  const magnitude = signed ? y.slice(1) : y;
  const padded = (signed ? "-" : "") + magnitude.padStart(4, "0");
  const month = String(1 + int(12)).padStart(2, "0");
  const day = String(1 + int(28)).padStart(2, "0");
  if (dateOnly) return `${padded}${month}${day}`;
  const hour = String(int(24)).padStart(2, "0");
  const minute = String(int(60)).padStart(2, "0");
  return `${padded}${month}${day}T${hour}${minute}00`;
}

function shiftStamp(value, hours) {
  // Only ever asked of a timed, ordinary-year stamp, so the arithmetic stays in
  // the host's own Date and never touches a value the model reads.
  const at = Date.UTC(
    Number(value.slice(0, 4)),
    Number(value.slice(4, 6)) - 1,
    Number(value.slice(6, 8)),
    Number(value.slice(9, 11)) + hours,
    Number(value.slice(11, 13)),
    0
  );
  const date = new Date(at);
  const pad = (n, w = 2) => String(n).padStart(w, "0");
  return (
    `${pad(date.getUTCFullYear(), 4)}${pad(date.getUTCMonth() + 1)}${pad(date.getUTCDate())}` +
    `T${pad(date.getUTCHours())}${pad(date.getUTCMinutes())}00`
  );
}

const FREQUENCIES = ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"];
const BYDAYS = ["MO", "TU,TH", "2TU", "-1FR", "SA,SU"];

function ruleText(flags) {
  const parts = [];
  if (chance(0.12)) parts.push(`RSCALE=${pick(["GREGORIAN", "HEBREW", "CHINESE", "islamic-civil"])}`);
  parts.push(`FREQ=${pick(FREQUENCIES)}`);
  if (chance(0.4)) parts.push(`INTERVAL=${1 + int(3)}`);
  if (chance(0.5)) parts.push(`COUNT=${1 + int(8)}`);
  else if (chance(0.4)) parts.push(`UNTIL=2027${String(1 + int(12)).padStart(2, "0")}15T235959Z`);
  if (chance(0.3)) parts.push(`BYDAY=${pick(BYDAYS)}`);
  if (chance(0.2)) parts.push(`BYMONTHDAY=${pick(["1", "15", "-1", "10,20"])}`);
  if (chance(0.15)) parts.push(`BYMONTH=${pick(["1", "6", "3,9"])}`);
  // D3: a part with no `=` at all.
  if (chance(0.02)) {
    parts.push(pick(["X-BROKEN", "NONSENSE"]));
    flags.malformedRule = true;
  }
  return parts.join(";");
}

/// Folds a line at ARBITRARY character boundaries, not at 75 bytes, so the
/// unfolder is exercised on continuations no emitter would have produced.
function refold(line) {
  const characters = [...line];
  if (characters.length < 12) return line;
  const out = [];
  let index = 0;
  while (index < characters.length) {
    const span = 6 + int(20);
    out.push(characters.slice(index, index + span).join(""));
    index += span;
  }
  return out.map((chunk, position) => (position ? ` ${chunk}` : chunk)).join("\r\n");
}

function eventLines(index, flags, shared) {
  const uid = shared?.uid ?? `event-${index}@diff.test`;
  const recurring = shared?.recurring ?? (!shared && chance(0.45));
  const dateOnly = chance(0.2);
  const start = stamp(recurring, dateOnly);
  const timed = start.includes("T");
  const zone = !dateOnly && timed && chance(0.3) ? pick(ZONES) : null;
  const startParams = dateOnly ? ";VALUE=DATE" : zone ? `;TZID=${zone}` : "";
  const lines = ["BEGIN:VEVENT", `UID:${uid}`];
  if (shared?.recurrenceId) {
    lines.push(`RECURRENCE-ID${shared.recurrenceParams}:${shared.recurrenceId}`);
  }
  lines.push(`DTSTART${startParams}:${start}`);
  if (chance(0.65)) {
    // A cross-zone DTEND is one of the three warnings, so it is generated on
    // purpose rather than avoided.
    const crossZone = zone && chance(0.25);
    const endParams = dateOnly ? ";VALUE=DATE" : crossZone ? "" : zone ? `;TZID=${zone}` : "";
    const end = dateOnly
      ? String(Number(start) + 1)
      : timed
        ? shiftStamp(start, 1 + int(3)) + (crossZone ? "Z" : "")
        : start;
    if (!dateOnly || Number.isFinite(Number(start))) lines.push(`DTEND${endParams}:${end}`);
  } else if (chance(0.3)) {
    lines.push(`DURATION:PT${1 + int(4)}H${pick(["", "30M"])}`);
  }
  if (recurring) {
    lines.push(`RRULE:${ruleText(flags)}`);
    if (chance(0.35) && timed) {
      const params = chance(0.4) ? ";VALUE=DATE" : zone ? `;TZID=${zone}` : "";
      const value =
        params === ";VALUE=DATE" ? start.slice(0, start.indexOf("T")) : shiftStamp(start, 24);
      lines.push(`EXDATE${params}:${value}`);
      if (chance(0.4)) lines.push(`EXDATE${params}:${value}`);
    }
  }
  lines.push(`SUMMARY:${text()}`);
  if (chance(0.5)) lines.push(`DESCRIPTION:${longText()}`);
  if (chance(0.35)) lines.push(`LOCATION:${pick(WORDS)} room`);
  if (chance(0.3)) lines.push(`STATUS:${pick(["CONFIRMED", "TENTATIVE", "CANCELLED"])}`);
  if (chance(0.3)) lines.push(`CATEGORIES:${pick(WORDS)},${pick(WORDS)}`);
  if (chance(0.3)) lines.push(`ATTENDEE;CN="Doe, John":mailto:john@diff.test`);
  if (chance(0.3)) lines.push(`X-FOREIGN-${index}:${pick(WORDS)}`);
  if (chance(0.1)) lines.push("X-EVENT-MALFORMED-MARKER");
  if (chance(0.25)) {
    lines.push("BEGIN:VALARM", "ACTION:DISPLAY", "TRIGGER:-PT15M", "DESCRIPTION:Reminder", "END:VALARM");
  }
  // D1: the dead dialect, in both of its carriers.
  if (chance(0.03)) {
    lines.push(`X-CHRONOLOG-ANCHOR;ID=r1;ROLE=start:${stamp(true, false)}`);
    flags.anchorDialect = true;
  }
  if (recurring && chance(0.03)) {
    lines.push(`X-CHRONOLOG-SERIES:${uid}`, "X-CHRONOLOG-SEGMENT-INDEX:1");
    flags.seriesDialect = true;
  }
  lines.push("END:VEVENT");
  return { lines, uid, recurring, start, timed, zone, dateOnly };
}

function calendarText() {
  const flags = {};
  const lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Diff//EN"];
  if (chance(0.6)) lines.push(`X-WR-CALNAME:${text()}`);
  else if (chance(0.4)) lines.push(`NAME:${text()}`);
  if (chance(0.25)) lines.push(`X-UNUSUAL-CALENDAR:${pick(WORDS)}`);
  if (chance(0.1)) lines.push("X-CALENDAR-MALFORMED-MARKER");
  // Non-VEVENT subcomponents come FIRST, which is where the calendar shell keeps
  // them, so a file that survives a round trip does so for a stated reason.
  if (chance(0.3)) {
    lines.push("BEGIN:VTIMEZONE", `TZID:${pick(ZONES)}`, "X-TZ-DETAIL:keep", "END:VTIMEZONE");
  }
  if (chance(0.2)) {
    lines.push("BEGIN:VJOURNAL", "UID:journal@diff.test", `SUMMARY:${text()}`, "END:VJOURNAL");
  }
  if (chance(0.15)) lines.push("BEGIN:X-CUSTOM-COMP", "X-FIELD:keep", "END:X-CUSTOM-COMP");
  if (chance(0.15)) {
    lines.push("BEGIN:VFREEBUSY", "UID:fb@diff.test", "FREEBUSY:20260806T090000Z/PT1H", "END:VFREEBUSY");
  }
  // D2.
  if (chance(0.06)) {
    lines.push(
      "BEGIN:VTODO",
      "UID:todo@diff.test",
      `SUMMARY:${text()}`,
      "DTSTAMP:20260807T010000Z",
      ...(coin() ? ["COMPLETED:20260806T230000Z"] : []),
      "END:VTODO"
    );
    flags.vtodo = true;
  }

  const count = 1 + int(4);
  let master = null;
  for (let index = 0; index < count; index += 1) {
    const event = eventLines(index, flags);
    lines.push(...event.lines);
    if (event.recurring && event.timed && !master) master = event;
  }
  // A RECURRENCE-ID sibling of a real master, which is the only way an override
  // is ever minted. Its time form is drawn independently so the mismatch warning
  // is generated as often as the clean case.
  if (master && chance(0.4)) {
    const useDate = chance(0.35);
    const useUtc = !useDate && chance(0.35);
    const exception = eventLines(count, flags, {
      uid: master.uid,
      recurring: false,
      recurrenceId: useDate
        ? master.start.slice(0, master.start.indexOf("T"))
        : shiftStamp(master.start, 24) + (useUtc ? "Z" : ""),
      recurrenceParams: useDate ? ";VALUE=DATE" : useUtc || !master.zone ? "" : `;TZID=${master.zone}`
    });
    lines.push(...exception.lines);
  }
  // A duplicate UID with no series and no exception, which is what makes a
  // staple SUGGESTION.
  if (chance(0.12)) {
    const twin = eventLines(count + 1, flags, { uid: `event-0@diff.test`, recurring: false });
    lines.push(...twin.lines);
  }
  lines.push("END:VCALENDAR", "");
  const folded = lines.map((line) => (line && chance(0.12) ? refold(line) : line));
  return { text: folded.join("\r\n"), flags };
}

// --- The oracle's answers ---------------------------------------------------

// A deterministic total order over one answer row -- the row's own values,
// joined -- rather than a re-encoded document, so the two sides cannot disagree
// about how a map serializes.
const rowKey = (row) =>
  Object.values(row).map((value) => (Array.isArray(value) ? value.join(",") : String(value))).join("|");
const byRow = (left, right) => (rowKey(left) < rowKey(right) ? -1 : rowKey(left) > rowKey(right) ? 1 : 0);

function placementAnswer(document, eventId) {
  const relation = Object.values(document.relations).find(
    (item) => item.type === "attachment" && item.event === eventId
  );
  if (!relation) return null;
  return {
    role: relation.role,
    levels: relation.coordinate.levels.map((level) => [level.level, level.value]),
    dateOnly: relation.parameters?.dateOnly ?? null,
    utc: relation.parameters?.utc ?? null,
    timeZone: relation.parameters?.timeZone ?? null
  };
}

function semantics(document, result) {
  const events = {};
  for (const id of result.events) {
    const event = document.events[id];
    // D2: a VTODO-derived task exists only on this side, so it is not offered
    // for comparison at all.
    if (event.traits.includes("task")) continue;
    events[event.payload.uid] = {
      title: event.payload.title,
      description: event.payload.description,
      location: event.payload.location,
      status: event.payload.status,
      categories: event.payload.categories,
      durationDays: durationMagnitudeDays(event.magnitudes.duration, document).toJSON(),
      traits: [...event.traits].sort(),
      placement: placementAnswer(document, id)
    };
  }
  const patterns = {};
  for (const id of result.patterns) {
    const pattern = document.patterns[id];
    patterns[pattern.provenance.uid] = {
      kind: pattern.kind,
      rrule: pattern.rrule,
      rawRule: pattern.rawRule?.value ?? null,
      exdates: [...(pattern.exdates || [])].sort(),
      exdateProperties: (pattern.exdateProperties || []).map((row) => ({
        params: (row.params || []).map((param) => [param.name, param.values]),
        values: row.values.map((item) => [item.value, item.day])
      })),
      templateEventUid: document.events[pattern.templateEvent]?.payload?.uid ?? null,
      hasTemplateRelation: Boolean(pattern.templateRelation),
      appliesTo: (pattern.appliesTo || []).length
    };
  }
  return {
    frames: result.frames.map((id) => ({
      title: document.frames[id].title,
      traits: [...document.frames[id].traits].sort()
    })),
    events,
    patterns,
    overrides: Object.values(document.overrides)
      .map((override) => ({
        key: override.virtual.slice(override.virtual.lastIndexOf("/") + 1),
        suppress: Boolean(override.suppress),
        replacements: (override.replacements || [])
          .map((id) => document.events[id]?.payload?.uid ?? id)
          .sort()
      }))
      .sort(byRow),
    suggestions: result.suggestions
      .map((item) => ({ kind: item.kind, uid: item.uid, count: item.events.length }))
      .sort(byRow),
    warnings: [...result.warnings].sort()
  };
}

const WINDOW = {
  start: [
    ["year", "2026"],
    ["month", "1"],
    ["day", "1"]
  ],
  end: [
    ["year", "2027"],
    ["month", "12"],
    ["day", "31"]
  ]
};

function asCoordinate(levels) {
  return coordinate(levels.map(([level, value]) => ({ level, value })));
}

const cases = [];
const counts = { anchorDialect: 0, seriesDialect: 0, vtodo: 0, malformedRule: 0, exported: 0 };

for (let index = 0; index < 1500; index += 1) {
  const { text: source, flags } = calendarText();
  const dialect = Boolean(flags.anchorDialect || flags.seriesDialect);
  if (flags.anchorDialect) counts.anchorDialect += 1;
  if (flags.seriesDialect) counts.seriesDialect += 1;
  if (flags.vtodo) counts.vtodo += 1;
  if (flags.malformedRule) counts.malformedRule += 1;
  const useWindow = chance(0.45);
  const document = createStructuralDocument();
  let imported;
  let exported = null;
  let failure = null;
  try {
    imported = importICS(source, document, { label: "Diff" });
    const engine = new ChronologEngine(document);
    exported = exportICS(document, {
      frame: imported.frames[0],
      engine,
      now: NOW,
      productId: PRODUCT_ID,
      ...(useWindow
        ? { start: asCoordinate(WINDOW.start), end: asCoordinate(WINDOW.end) }
        : {})
    });
  } catch (error) {
    failure = String(error && error.message ? error.message : error);
  }
  // Semantics are compared unless the dead dialect or a fixed parse defect is in
  // play; bytes additionally sit out for a VTODO, whose position moves.
  const compareExport = !dialect && !flags.malformedRule && !flags.vtodo && !failure;
  if (compareExport) counts.exported += 1;
  cases.push({
    source,
    window: useWindow ? WINDOW : null,
    dialect,
    malformedRule: Boolean(flags.malformedRule),
    vtodo: Boolean(flags.vtodo),
    failure,
    expected: dialect || flags.malformedRule || failure ? null : semantics(document, imported),
    export: compareExport ? exported : null
  });
}

process.stdout.write(
  JSON.stringify({ seed: SEED, generated: cases.length, counts, cases }, null, 0)
);
