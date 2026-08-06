#!/usr/bin/env node
/**
 * gen-celestial.js
 *
 * Generates fixtures/celestial.ics — a synthetic RFC 5545 test fixture
 * containing ONLY celestial cycles/events spanning 2025-01-01 through
 * 2027-12-31. Intended to exercise:
 *   (a) event-defined cycles in a radial calendar view
 *       (e.g. new-moon -> new-moon = one lunar month), and
 *   (b) multi-calendar loading.
 *
 * All VEVENTs are computed/listed explicitly — no RRULE is used, because
 * lunar cycles are not fixed-length (the synodic month varies slightly
 * cycle to cycle; here we use the constant mean value, which is why the
 * events are annotated as approximate mean-cycle computations).
 *
 * Re-run with: node fixtures/gen-celestial.js
 */

'use strict';

const fs = require('fs');
const path = require('path');

const OUT_PATH = path.join(__dirname, 'celestial.ics');

// ---------------------------------------------------------------------------
// Range of interest
// ---------------------------------------------------------------------------
const RANGE_START = Date.UTC(2025, 0, 1, 0, 0, 0);
const RANGE_END = Date.UTC(2027, 11, 31, 23, 59, 59);

// A single DTSTAMP used for every VEVENT (generation time of this fixture).
const GENERATED_AT = new Date();

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------
function pad(n, len) {
  len = len || 2;
  return String(n).padStart(len, '0');
}

function formatDateTimeUTC(date) {
  return (
    date.getUTCFullYear() +
    pad(date.getUTCMonth() + 1) +
    pad(date.getUTCDate()) +
    'T' +
    pad(date.getUTCHours()) +
    pad(date.getUTCMinutes()) +
    pad(date.getUTCSeconds()) +
    'Z'
  );
}

function formatDateOnly(date) {
  return date.getUTCFullYear() + pad(date.getUTCMonth() + 1) + pad(date.getUTCDate());
}

function addDaysUTC(date, days) {
  return new Date(date.getTime() + days * 86400000);
}

// Escape text per RFC 5545 (comma, semicolon, backslash, newline).
function escapeText(text) {
  return String(text)
    .replace(/\\/g, '\\\\')
    .replace(/;/g, '\\;')
    .replace(/,/g, '\\,')
    .replace(/\n/g, '\\n');
}

// Fold a single logical content line to a max of 75 octets per physical
// line, per RFC 5545 section 3.1. Continuation lines are prefixed with a
// single space, which itself counts toward the 75-octet limit. All fixture
// text is ASCII, so character count == byte count here.
function foldLine(line) {
  const LIMIT = 75;
  if (Buffer.byteLength(line, 'utf8') <= LIMIT) return line;

  const out = [];
  let rest = line;
  out.push(rest.slice(0, LIMIT));
  rest = rest.slice(LIMIT);
  while (rest.length > 0) {
    const chunk = rest.slice(0, LIMIT - 1); // -1 for the leading space
    out.push(' ' + chunk);
    rest = rest.slice(LIMIT - 1);
  }
  return out.join('\r\n');
}

let uidCounter = 0;
function makeLines(ev) {
  // ev: { uid, dtstartLine, dtendLine?, summary, categories, description?, comment? }
  const lines = [];
  lines.push('BEGIN:VEVENT');
  lines.push('UID:' + ev.uid);
  lines.push('DTSTAMP:' + formatDateTimeUTC(GENERATED_AT));
  lines.push(ev.dtstartLine);
  if (ev.dtendLine) lines.push(ev.dtendLine);
  lines.push('SUMMARY:' + escapeText(ev.summary));
  lines.push('CATEGORIES:' + ev.categories);
  if (ev.description) lines.push('DESCRIPTION:' + escapeText(ev.description));
  if (ev.comment) lines.push('COMMENT:' + escapeText(ev.comment));
  lines.push('END:VEVENT');
  return lines;
}

// ---------------------------------------------------------------------------
// 1. Lunar cycle: new moons & full moons (computed, no RRULE)
// ---------------------------------------------------------------------------
// Anchor: New Moon 2025-01-29 12:36 UTC (matches published almanac value for
// the first new moon of 2025, so the mean-cycle projection stays close to
// reality across the +/- ~1.5 year span used here).
const SYNODIC_MONTH_DAYS = 29.530588853;
const SYNODIC_MONTH_MS = SYNODIC_MONTH_DAYS * 86400000;
const NEW_MOON_ANCHOR = Date.UTC(2025, 0, 29, 12, 36, 0);

const MOON_NOTE =
  'Approximate: computed from the mean synodic month (29.530588853 days) ' +
  'projected from the 2025-01-29 12:36 UTC new moon anchor. Actual time may ' +
  'differ by a few hours due to orbital eccentricity.';

const lunarEvents = [];
// k=0 is the anchor cycle; walk both directions far enough to cover the
// full 2025-01-01..2027-12-31 range with margin.
for (let k = -3; k <= 42; k++) {
  const newMoonMs = NEW_MOON_ANCHOR + k * SYNODIC_MONTH_MS;
  const fullMoonMs = newMoonMs + SYNODIC_MONTH_MS / 2;

  const newMoonDate = new Date(newMoonMs);
  if (newMoonMs >= RANGE_START && newMoonMs <= RANGE_END) {
    lunarEvents.push({
      uid: 'newmoon-' + formatDateOnly(newMoonDate) + '@celestial.chronolog',
      dtstartLine: 'DTSTART:' + formatDateTimeUTC(newMoonDate),
      summary: 'New Moon',
      categories: 'Lunar',
      description: 'Cycle anchor event for radial lunar-month view. ' + MOON_NOTE,
      comment: MOON_NOTE,
    });
  }

  const fullMoonDate = new Date(fullMoonMs);
  if (fullMoonMs >= RANGE_START && fullMoonMs <= RANGE_END) {
    lunarEvents.push({
      uid: 'fullmoon-' + formatDateOnly(fullMoonDate) + '@celestial.chronolog',
      dtstartLine: 'DTSTART;VALUE=DATE:' + formatDateOnly(fullMoonDate),
      dtendLine: 'DTEND;VALUE=DATE:' + formatDateOnly(addDaysUTC(fullMoonDate, 1)),
      summary: 'Full Moon',
      categories: 'Lunar',
      description: MOON_NOTE,
      comment: MOON_NOTE,
    });
  }
}

// ---------------------------------------------------------------------------
// 2. Solstices & equinoxes (approximate UTC times), 12 total across 3 years
// ---------------------------------------------------------------------------
// Approximate published UTC instants (date-level accurate, time accurate to
// within roughly an hour); annotated as approximate.
const solsticeEquinoxRaw = [
  ['2025-03-20T09:01:00Z', 'March Equinox'],
  ['2025-06-21T02:42:00Z', 'June Solstice'],
  ['2025-09-22T18:19:00Z', 'September Equinox'],
  ['2025-12-21T15:03:00Z', 'December Solstice'],

  ['2026-03-20T14:46:00Z', 'March Equinox'],
  ['2026-06-21T08:25:00Z', 'June Solstice'],
  ['2026-09-23T00:05:00Z', 'September Equinox'],
  ['2026-12-21T20:50:00Z', 'December Solstice'],

  ['2027-03-20T20:25:00Z', 'March Equinox'],
  ['2027-06-21T14:11:00Z', 'June Solstice'],
  ['2027-09-23T05:02:00Z', 'September Equinox'],
  ['2027-12-22T02:43:00Z', 'December Solstice'],
];

const SOLAR_NOTE = 'Approximate UTC instant for this seasonal marker (mean/almanac estimate).';

const solarEvents = solsticeEquinoxRaw.map(([iso, summary]) => {
  const d = new Date(iso);
  const y = d.getUTCFullYear();
  return {
    uid: 'solar-' + summary.toLowerCase().replace(/\s+/g, '-') + '-' + y + '@celestial.chronolog',
    dtstartLine: 'DTSTART:' + formatDateTimeUTC(d),
    summary,
    categories: 'Solar',
    description: SOLAR_NOTE,
  };
});

// ---------------------------------------------------------------------------
// 3. Major meteor shower peaks (all-day), 7 showers x 3 years = 21 events
// ---------------------------------------------------------------------------
const meteorShowerPeaksByMonthDay = [
  ['Quadrantids', 1, 3],
  ['Lyrids', 4, 22],
  ['Eta Aquariids', 5, 6],
  ['Perseids', 8, 12],
  ['Orionids', 10, 21],
  ['Leonids', 11, 17],
  ['Geminids', 12, 14],
];

const METEOR_NOTE = 'Approximate typical peak date for this annual shower; actual peak night can shift by a day.';

const meteorEvents = [];
for (const year of [2025, 2026, 2027]) {
  for (const [name, month, day] of meteorShowerPeaksByMonthDay) {
    const d = new Date(Date.UTC(year, month - 1, day));
    meteorEvents.push({
      uid: 'meteor-' + name.toLowerCase().replace(/\s+/g, '') + '-' + year + '@celestial.chronolog',
      dtstartLine: 'DTSTART;VALUE=DATE:' + formatDateOnly(d),
      dtendLine: 'DTEND;VALUE=DATE:' + formatDateOnly(addDaysUTC(d, 1)),
      summary: name + ' Peak',
      categories: 'Meteor',
      description: METEOR_NOTE,
    });
  }
}

// ---------------------------------------------------------------------------
// 4. Actual solar & lunar eclipses of 2025-2027 (date-level accuracy)
// ---------------------------------------------------------------------------
const eclipseRaw = [
  ['2025-03-14', 'Total Lunar Eclipse'],
  ['2025-03-29', 'Partial Solar Eclipse'],
  ['2025-09-07', 'Total Lunar Eclipse'],
  ['2025-09-21', 'Partial Solar Eclipse'],

  ['2026-02-17', 'Annular Solar Eclipse'],
  ['2026-03-03', 'Total Lunar Eclipse'],
  ['2026-08-12', 'Total Solar Eclipse'],
  ['2026-08-28', 'Partial Lunar Eclipse'],

  ['2027-01-26', 'Annular Solar Eclipse'],
  ['2027-02-20', 'Total Lunar Eclipse'],
  ['2027-07-18', 'Partial Solar Eclipse'],
  ['2027-08-02', 'Total Solar Eclipse'],
  ['2027-08-17', 'Partial Lunar Eclipse'],
];

const ECLIPSE_NOTE = 'Date reflects the (U)TC calendar day of the eclipse event; exact contact times omitted.';

const eclipseEvents = eclipseRaw.map(([isoDate, summary]) => {
  const [y, m, d] = isoDate.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  return {
    uid: 'eclipse-' + isoDate + '@celestial.chronolog',
    dtstartLine: 'DTSTART;VALUE=DATE:' + formatDateOnly(date),
    dtendLine: 'DTEND;VALUE=DATE:' + formatDateOnly(addDaysUTC(date, 1)),
    summary,
    categories: 'Eclipse',
    description: ECLIPSE_NOTE,
  };
});

// ---------------------------------------------------------------------------
// 5. Earth perihelion & aphelion (approximate dates), 2 x 3 years = 6 events
// ---------------------------------------------------------------------------
const orbitRaw = [
  ['2025-01-04', 'Earth Perihelion'],
  ['2025-07-03', 'Earth Aphelion'],
  ['2026-01-03', 'Earth Perihelion'],
  ['2026-07-06', 'Earth Aphelion'],
  ['2027-01-03', 'Earth Perihelion'],
  ['2027-07-05', 'Earth Aphelion'],
];

const ORBIT_NOTE = 'Approximate date of Earth\'s closest/farthest point from the Sun for this year.';

const orbitEvents = orbitRaw.map(([isoDate, summary]) => {
  const [y, m, d] = isoDate.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  return {
    uid: (summary.toLowerCase().includes('peri') ? 'perihelion-' : 'aphelion-') + y + '@celestial.chronolog',
    dtstartLine: 'DTSTART;VALUE=DATE:' + formatDateOnly(date),
    dtendLine: 'DTEND;VALUE=DATE:' + formatDateOnly(addDaysUTC(date, 1)),
    summary,
    categories: 'Orbit',
    description: ORBIT_NOTE,
  };
});

// ---------------------------------------------------------------------------
// Assemble
// ---------------------------------------------------------------------------
const allEvents = [
  ...lunarEvents,
  ...solarEvents,
  ...meteorEvents,
  ...eclipseEvents,
  ...orbitEvents,
];

// Sort chronologically by DTSTART value for readability.
function dtstartSortKey(ev) {
  const m = ev.dtstartLine.match(/:(\d{8})(T(\d{6})Z)?$/);
  return m[1] + (m[3] || '000000');
}
allEvents.sort((a, b) => (dtstartSortKey(a) < dtstartSortKey(b) ? -1 : 1));

const headerLines = [
  'BEGIN:VCALENDAR',
  'VERSION:2.0',
  'PRODID:-//ChronoLog//Celestial Test Fixture 1.0//EN',
  'CALSCALE:GREGORIAN',
  'X-WR-CALNAME:Celestial Events (Test Fixture)',
  'X-WR-TIMEZONE:UTC',
];

const footerLines = ['END:VCALENDAR'];

const bodyLines = [];
for (const ev of allEvents) {
  bodyLines.push(...makeLines(ev));
}

const logicalLines = [...headerLines, ...bodyLines, ...footerLines];
const foldedLines = logicalLines.map(foldLine);
const content = foldedLines.join('\r\n') + '\r\n';

fs.writeFileSync(OUT_PATH, content, { encoding: 'utf8' });

console.log('Wrote ' + OUT_PATH);
console.log('Total VEVENTs: ' + allEvents.length);
console.log('  Lunar: ' + lunarEvents.length);
console.log('  Solar: ' + solarEvents.length);
console.log('  Meteor: ' + meteorEvents.length);
console.log('  Eclipse: ' + eclipseEvents.length);
console.log('  Orbit: ' + orbitEvents.length);
