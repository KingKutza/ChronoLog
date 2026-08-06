#!/usr/bin/env node
/**
 * verify-celestial.js
 *
 * Sanity-checks fixtures/celestial.ics:
 *   - CRLF line endings, BEGIN/END balance
 *   - no physical line exceeds a reasonable octet length
 *   - every VEVENT has UID, DTSTART, SUMMARY, CATEGORIES
 *   - tallies event count per CATEGORIES value
 *   - prints the first 3 New Moon datetimes for sanity
 *
 * Run with: node fixtures/verify-celestial.js
 */

'use strict';

const fs = require('fs');
const path = require('path');

const ICS_PATH = path.join(__dirname, 'celestial.ics');
const raw = fs.readFileSync(ICS_PATH, 'utf8');

let failures = 0;
function check(label, ok, detail) {
  const status = ok ? 'OK  ' : 'FAIL';
  console.log(`[${status}] ${label}${detail ? ' - ' + detail : ''}`);
  if (!ok) failures++;
}

// --- Line ending check -------------------------------------------------
const hasCRLF = raw.includes('\r\n');
const hasBareLF = /[^\r]\n/.test(raw);
check('Uses CRLF line endings', hasCRLF && !hasBareLF, hasBareLF ? 'found a bare LF not preceded by CR' : '');

// Split into physical lines (drop trailing empty line from final CRLF).
const physicalLines = raw.split('\r\n').filter((_, i, arr) => !(i === arr.length - 1 && arr[i] === ''));

// --- Line length check ---------------------------------------------------
const MAX_OCTETS = 75;
let longLine = null;
for (const line of physicalLines) {
  if (Buffer.byteLength(line, 'utf8') > MAX_OCTETS) {
    longLine = line;
    break;
  }
}
check(`No physical line exceeds ${MAX_OCTETS} octets`, longLine === null, longLine ? `offending: ${longLine.slice(0, 40)}...` : '');

// --- Unfold logical lines (continuation lines start with space/tab) ------
const logicalLines = [];
for (const line of physicalLines) {
  if ((line.startsWith(' ') || line.startsWith('\t')) && logicalLines.length > 0) {
    logicalLines[logicalLines.length - 1] += line.slice(1);
  } else {
    logicalLines.push(line);
  }
}

// --- BEGIN/END balance ----------------------------------------------------
const beginCount = logicalLines.filter((l) => l.startsWith('BEGIN:')).length;
const endCount = logicalLines.filter((l) => l.startsWith('END:')).length;
check('BEGIN/END counts balance', beginCount === endCount, `BEGIN=${beginCount} END=${endCount}`);

check('Starts with BEGIN:VCALENDAR', logicalLines[0] === 'BEGIN:VCALENDAR');
check('Ends with END:VCALENDAR', logicalLines[logicalLines.length - 1] === 'END:VCALENDAR');
check('Has VERSION:2.0', logicalLines.includes('VERSION:2.0'));
check('Has PRODID', logicalLines.some((l) => l.startsWith('PRODID:')));

// --- Parse VEVENTs ---------------------------------------------------------
const events = [];
let current = null;
for (const line of logicalLines) {
  if (line === 'BEGIN:VEVENT') {
    current = { lines: [] };
  } else if (line === 'END:VEVENT') {
    if (current) events.push(current);
    current = null;
  } else if (current) {
    current.lines.push(line);
  }
}

check('At least one VEVENT parsed', events.length > 0, `count=${events.length}`);

function getProp(ev, name) {
  const re = new RegExp('^' + name + '([;:])');
  return ev.lines.find((l) => re.test(l));
}

let missingRequired = 0;
const categoryCounts = {};
const newMoonDates = [];

for (const ev of events) {
  const uid = getProp(ev, 'UID');
  const dtstart = getProp(ev, 'DTSTART');
  const summary = getProp(ev, 'SUMMARY');
  const categories = getProp(ev, 'CATEGORIES');
  const dtstamp = getProp(ev, 'DTSTAMP');

  if (!uid || !dtstart || !summary || !categories || !dtstamp) {
    missingRequired++;
    console.log('  Missing required property in event: ' + JSON.stringify(ev.lines.slice(0, 3)));
    continue;
  }

  const catValue = categories.split(':').slice(1).join(':').trim();
  categoryCounts[catValue] = (categoryCounts[catValue] || 0) + 1;

  if (summary === 'SUMMARY:New Moon' || summary.endsWith('New Moon')) {
    const m = dtstart.match(/DTSTART:(\d{8}T\d{6}Z)/);
    if (m) newMoonDates.push(m[1]);
  }
}

check(
  'Every VEVENT has UID/DTSTART/SUMMARY/CATEGORIES/DTSTAMP',
  missingRequired === 0,
  `missing in ${missingRequired} of ${events.length} events`
);

// --- Unique UID check -------------------------------------------------
const uids = events.map((ev) => getProp(ev, 'UID')).filter(Boolean);
const uniqueUids = new Set(uids);
check('All UIDs are unique', uniqueUids.size === uids.length, `${uniqueUids.size}/${uids.length} unique`);

// --- Date range check ---------------------------------------------------
const RANGE_START = '20250101';
const RANGE_END = '20271231';
let outOfRange = 0;
for (const ev of events) {
  const dtstart = getProp(ev, 'DTSTART');
  const m = dtstart.match(/(\d{8})/);
  if (m) {
    const d = m[1];
    if (d < RANGE_START || d > RANGE_END) outOfRange++;
  }
}
check('All events fall within 2025-01-01..2027-12-31', outOfRange === 0, `${outOfRange} out of range`);

newMoonDates.sort();

console.log('\n--- Category counts ---');
for (const [cat, count] of Object.entries(categoryCounts).sort()) {
  console.log(`  ${cat}: ${count}`);
}
console.log(`  TOTAL: ${events.length}`);

console.log('\n--- First 3 New Moon datetimes (UTC) ---');
for (const d of newMoonDates.slice(0, 3)) {
  console.log('  ' + d);
}

console.log('\n' + (failures === 0 ? 'ALL CHECKS PASSED' : `${failures} CHECK(S) FAILED`));
process.exit(failures === 0 ? 0 : 1);
