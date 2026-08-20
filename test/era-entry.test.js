import assert from "node:assert/strict";
import test from "node:test";
import { coordinate, nowDays } from "../src/exact.js";
import { CoordinateLaw, GREGORIAN_LAW, coordinateLaw } from "../src/coordinate-law.js";
import {
  coordinateEntryPlaceholder,
  coordinatePickerLadder,
  formatCoordinateEntry,
  parseCoordinateEntry
} from "../src/coordinate-entry.js";
import { ChronologEngine } from "../src/engine.js";
import { createEmptyWorkspaceDocument } from "../src/model.js";
import { ViewSession } from "../src/session.js";
import { findByClass, renderWithStubDom } from "./helpers/render-dom.js";

// Owner ruling: eras are FRAMES STAPLED TOGETHER, so the placement field's YEAR
// position is what carries the era -- written bare ("433") or qualified with the
// era frame's own key ("3E 433"). The era is never a level: choosing an era is
// choosing which frame to place on, which happens before this field.
const LADDER = Object.freeze({
  kind: "gregorian",
  levels: Object.freeze([
    Object.freeze({ name: "year" }),
    Object.freeze({ name: "month", within: "year", transition: "gregorian.months" }),
    Object.freeze({ name: "day", within: "month", transition: "gregorian.days" }),
    Object.freeze({ name: "hour", within: "day", radix: "24" }),
    Object.freeze({ name: "minute", within: "hour", radix: "60" }),
    Object.freeze({ name: "second", within: "minute", radix: "60" }),
    Object.freeze({ name: "subsecond", within: "second" })
  ])
});

function chainLaw(entries, eraId) {
  const frames = {
    "frame:chain": {
      id: "frame:chain", title: "Chain calendar",
      traits: ["line", "temporal", "calendar", "group"], coordinate: LADDER
    }
  };
  const relations = {};
  for (const entry of entries) {
    frames[entry.id] = {
      id: entry.id, title: entry.era.name, traits: ["line", "temporal", "era"],
      basis: "frame:chain", era: entry.era
    };
  }
  for (const [index, entry] of entries.slice(0, -1).entries()) {
    relations[`succession:${entry.id}`] = {
      id: `succession:${entry.id}`, type: "staple", kind: "succession",
      ends: [{ frame: entry.id, role: "end" }, { frame: entries[index + 1].id, role: "start" }]
    };
  }
  return coordinateLaw({ frames, relations }, eraId);
}

const BCE_CE = Object.freeze([
  Object.freeze({ id: "era:bce", era: Object.freeze({ key: "BCE", name: "Before Common Era", direction: "descending", firstYear: "1", years: "open", affix: "suffix" }) }),
  Object.freeze({ id: "era:ce", era: Object.freeze({ key: "CE", name: "Common Era", direction: "ascending", firstYear: "1", years: "open", affix: "suffix", anchor: { year: "1", properYear: "1" } }) })
]);

const TAMRIEL = Object.freeze([
  Object.freeze({ id: "era:third", era: Object.freeze({ key: "3E", name: "Third Era", direction: "ascending", firstYear: "1", years: "433", anchor: { year: "1", properYear: "3817" } }) }),
  Object.freeze({ id: "era:fourth", era: Object.freeze({ key: "4E", name: "Fourth Era", direction: "ascending", firstYear: "1", years: "open" }) })
]);

test("an era-qualified year parses and round-trips through formatCoordinateEntry", () => {
  const law = chainLaw(TAMRIEL, "era:third");
  const { coordinate: parsed, depth } = parseCoordinateEntry("3E 433 8 20", law);
  assert.equal(depth, "day");
  // Only the year is stored: the frame is already the era.
  assert.equal(parsed.levels.find((level) => level.level === "year").value, "433");
  assert.equal(parsed.levels.some((level) => level.level === "era"), false);
  assert.equal(law.formatYear(parsed), "3E 433");
  // The field shows what was typed, and reading it back gives the same value.
  const text = formatCoordinateEntry(parsed, law);
  assert.match(text, /^3E 433/);
  assert.deepEqual(parseCoordinateEntry(text, law).coordinate, parsed);
  // A bare year means the same thing, because the frame fixes the era.
  assert.deepEqual(parseCoordinateEntry("433 8 20", law).coordinate, parsed);
});

test("a suffix-affix era ('44 BCE') parses as readily as a prefix one", () => {
  const bce = chainLaw(BCE_CE, "era:bce");
  const parsed = parseCoordinateEntry("44 BCE 3 15", bce).coordinate;
  assert.equal(parsed.levels.find((level) => level.level === "year").value, "44");
  assert.equal(bce.formatYear(parsed), "44 BCE");
  assert.match(formatCoordinateEntry(parsed, bce), /^44 BCE/);
  // The other order is the same date.
  assert.deepEqual(parseCoordinateEntry("BCE 44 3 15", bce).coordinate, parsed);
});

test("a qualifier naming a different era is refused, never retargeted onto another frame", () => {
  const third = chainLaw(TAMRIEL, "era:third");
  // "4E 5" is a real position -- in a different era. This field cannot move a
  // coordinate to another frame, so it refuses rather than silently mislabelling.
  assert.throws(() => parseCoordinateEntry("4E 5 1 1", third), Error);
  // And a year past this era's own extent is refused too.
  assert.throws(() => parseCoordinateEntry("3E 434 1 1", third), Error);
});

test("text naming an unknown era is refused with the law's own help message, never read as a number", () => {
  const law = chainLaw(TAMRIEL, "era:third");
  assert.throws(() => parseCoordinateEntry("9Z 12 1 1", law), Error);
  // The placeholder advertises the era position honestly.
  assert.match(coordinateEntryPlaceholder(law), /3E/);
  // And a law with no eras is untouched.
  assert.equal(coordinateEntryPlaceholder(GREGORIAN_LAW), "year-month-day hour:minute:second:subsecond");
  assert.deepEqual(
    parseCoordinateEntry("2026-08-20", GREGORIAN_LAW).coordinate,
    coordinate([
      { level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "20" }
    ])
  );
  assert.equal(formatCoordinateEntry(coordinate([
    { level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "20" }
  ]), GREGORIAN_LAW), "2026-08-20");
  // No era rung: choosing an era is choosing a frame, not a value in this field.
  const rungs = coordinatePickerLadder(law, coordinate([]));
  assert.equal(rungs[0].level, "year");
});
