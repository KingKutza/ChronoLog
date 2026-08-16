#!/usr/bin/env node

import { readdir } from "node:fs/promises";
import { pathToFileURL, fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const folder = join(root, "test");
const files = (await readdir(folder))
  .filter((entry) => entry.endsWith(".test.js"))
  .sort();

for (const file of files) await import(pathToFileURL(join(folder, file)));
