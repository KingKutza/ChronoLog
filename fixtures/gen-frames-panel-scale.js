#!/usr/bin/env node

import { writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const frames = [];
for (let index = 1; index <= 30; index += 1) {
  frames.push({
    id: `calendar:scale-${index}`,
    title: `Scale calendar ${String(index).padStart(2, "0")}`,
    traits: ["set", "calendar", "timeline"],
    color: "#2e8b57",
    display: index === 1 ? { overlays: [] } : {}
  });
}
for (let index = 1; index <= 50; index += 1) {
  frames.push({
    id: `group:scale-${index}`,
    title: `Scale group ${String(index).padStart(2, "0")} with a deliberately long descriptive label`,
    traits: ["set", "group"],
    color: "#4e6fa4",
    display: {}
  });
}
const fixture = { description: "Non-private 30-calendar / 50-group Frames panel scale fixture.", frames };
const target = join(here, "frames-panel-scale.json");
await writeFile(target, JSON.stringify(fixture, null, 2) + "\n", "utf8");
process.stdout.write(`Wrote ${target}\n`);
