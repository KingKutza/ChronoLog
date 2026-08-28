// Differential generator for the quick-capture grammar.
//
// Random capture lines and date words from a fixed seed, run through the
// shipped `src/ui/todo-capture.js`, emitted as exact strings. The Dart side
// (`capture_diff_check.dart`) replays the same cases through
// `lib/edit/capture.dart` and compares.
//
// Nothing here reads a file: every line is text this generator built.

import { parseQuickTodo, quickDateDays } from "../../src/ui/todo-capture.js";

const SEED = 20260827;

// One deterministic 32-bit PRNG, so the case set is reproducible on any host.
let state = SEED >>> 0;
function next() {
  state ^= state << 13; state >>>= 0;
  state ^= state >>> 17;
  state ^= state << 5; state >>>= 0;
  return state / 0x100000000;
}
const pick = (list) => list[Math.floor(next() * list.length)];
const int = (lo, hi) => lo + Math.floor(next() * (hi - lo + 1));

const WORDS = ["call", "plumber", "the", "milk", "#", "@", "buy", "réservé", "日本", "a", ">"];
const GROUPS = ["#Home", "#Work", "#", "#Groceries", "#a b", "#Ünïcode"];
const DATES = [
  "@today", "@tomorrow", "@+1", "@+14d", "@+0", "@2026-08-03", "@2026-8-3",
  "@8/3", "@8/3/2026", "@8/3/26", "@2026-13-40", "@whenever", "@", "@TODAY",
];
const NOTES = ["", " > ring twice", " > a > b", " > "];

function line() {
  const parts = [];
  for (let index = 0, count = int(0, 5); index < count; index += 1) parts.push(pick(WORDS));
  if (next() < 0.6) parts.splice(int(0, parts.length), 0, pick(GROUPS));
  if (next() < 0.6) parts.splice(int(0, parts.length), 0, pick(DATES));
  if (next() < 0.15) parts.splice(int(0, parts.length), 0, pick(GROUPS));
  const spacing = next() < 0.2 ? "  " : " ";
  return (next() < 0.1 ? "  " : "") + parts.join(spacing) + pick(NOTES);
}

const cases = [];
for (let index = 0; index < 1200; index += 1) {
  const text = line();
  const parsed = parseQuickTodo(text);
  cases.push({ kind: "parse", text, parsed: parsed ?? null });
}

// The date words on their own, against a fixed "today" so the clock never
// enters the comparison.
const TODAY = "20000";
for (const word of DATES) {
  for (const today of [TODAY, "0", "-1000", "739000"]) {
    const value = word.slice(1);
    let days = null;
    try {
      const answer = quickDateDays(value, today);
      days = answer === null ? null : answer.toJSON();
    } catch {
      days = null;
    }
    cases.push({ kind: "date", text: value, today, days });
  }
}

process.stdout.write(JSON.stringify({ seed: SEED, cases }));
