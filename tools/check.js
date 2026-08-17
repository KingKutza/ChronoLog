#!/usr/bin/env node

import { readdir } from "node:fs/promises";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const run = promisify(execFile);
const root = dirname(dirname(fileURLToPath(import.meta.url)));

const targets = [];
for (const folder of ["bin", "src", "tools", "fixtures", "test"]) {
  const entries = await readdir(join(root, folder), { withFileTypes: true, recursive: true });
  for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    if (entry.isFile() && entry.name.endsWith(".js")) {
      targets.push(join(entry.parentPath ?? entry.path, entry.name));
    }
  }
}

let failed = false;
for (const file of targets) {
  try {
    await run(process.execPath, ["--check", file]);
  } catch (error) {
    failed = true;
    process.stderr.write(`${file}\n${error.stderr || error.message}\n`);
  }
}

process.stdout.write(`Checked ${targets.length} files${failed ? ", with failures" : ""}\n`);
process.exit(failed ? 1 : 0);
