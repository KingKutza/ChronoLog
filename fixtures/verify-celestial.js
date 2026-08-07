#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { ChronologEngine } from "../src/engine.js";
import { coordinate } from "../src/exact.js";
import { validateDocument } from "../src/model.js";

const here = dirname(fileURLToPath(import.meta.url));
const document = JSON.parse(await readFile(join(here, "celestial.chronolog.json"), "utf8"));
const validation = validateDocument(document);
if (!validation.valid) throw new Error(validation.errors.join("\n"));

const engine = new ChronologEngine(document);
const years = ["1026", "3026", "100002026", "-99997974"];
for (const year of years) {
  const start = coordinate([
    { level: "year", value: year },
    { level: "month", value: "1" },
    { level: "day", value: "1" }
  ]);
  const end = coordinate([
    { level: "year", value: year },
    { level: "month", value: "2" },
    { level: "day", value: "1" }
  ]);
  const state = engine.queryState({ frame: "calendar:celestial", coordinate: start });
  const facts = engine.queryFacts({ frame: "calendar:celestial", start, end });
  if (state.errors.length || !state.values["pattern:celestial"]) {
    throw new Error(`No celestial state in ${year}: ${JSON.stringify(state.errors)}`);
  }
  if (facts.errors.length || facts.facts.length < 3) {
    throw new Error(`No celestial cycle in ${year}: ${JSON.stringify(facts.errors)}`);
  }
  process.stdout.write(`${year}: state + ${facts.facts.length} phase facts\n`);
}

const serialized = JSON.stringify(document);
if (serialized.includes("BEGIN:VEVENT")) throw new Error("Celestial fixture contains expanded VEVENTs");
process.stdout.write(`Compact fixture: ${Buffer.byteLength(serialized)} bytes\n`);
