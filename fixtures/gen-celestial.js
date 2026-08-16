#!/usr/bin/env node

import { writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createCelestialDocument } from "../src/celestial.js";

const here = dirname(fileURLToPath(import.meta.url));
const target = join(here, "celestial.chronolog.json");
await writeFile(target, JSON.stringify(createCelestialDocument(), null, 2) + "\n", "utf8");
process.stdout.write(`Wrote ${target}\n`);
