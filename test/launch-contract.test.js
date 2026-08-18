import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { DEFAULT_PORT, defaultDataDirectory, parseArguments } from "../bin/chronolog.js";

const root = fileURLToPath(new URL("..", import.meta.url));

test("package.json and tools/serve.js expose the documented launch contract", async () => {
  const packageInfo = JSON.parse(await readFile(join(root, "package.json"), "utf8"));
  assert.equal(packageInfo.scripts.dev, "node tools/serve.js");
  assert.equal(packageInfo.scripts.start, "node bin/chronolog.js");
  assert.match(await readFile(join(root, "tools", "serve.js"), "utf8"), /Chronolog: http:\/\/127\.0\.0\.1:\$\{activePort\}/);
});

test("parseArguments parses flags and rejects invalid values", () => {
  assert.deepEqual(parseArguments(["--no-open", "--port", "4312", "--data-dir", "./data"]), {
    open: false, port: 4312, dataDirectory: join(process.cwd(), "data")
  });
  assert.throws(() => parseArguments(["--port", "wat"]), /--port/);
});

test("parseArguments defaults to the same port as npm run dev, and keeps --port 0 available", () => {
  assert.equal(DEFAULT_PORT, 4173);
  assert.equal(parseArguments([]).port, 4173);
  assert.equal(parseArguments(["--port", "0"]).port, 0);
});

test("defaultDataDirectory defaults to the app's own root directory (portable, no per-OS profile dirs)", () => {
  assert.equal(defaultDataDirectory({}), resolve(root));
  assert.equal(defaultDataDirectory({ HOME: "/home/alex" }), resolve(root));
  assert.equal(defaultDataDirectory({ APPDATA: "C:\\Users\\alex\\AppData\\Roaming" }), resolve(root));
});

test("defaultDataDirectory honors CHRONOLOG_DATA_DIR as the only environment override", () => {
  assert.equal(defaultDataDirectory({ CHRONOLOG_DATA_DIR: "/custom/data" }), resolve("/custom/data"));
  assert.equal(defaultDataDirectory({ CHRONOLOG_DATA_DIR: "./relative-data" }), resolve("./relative-data"));
});

test("chronolog --help exits cleanly with usage text", () => {
  const help = spawnSync(process.execPath, [join(root, "bin/chronolog.js"), "--help"], { encoding: "utf8" });
  assert.equal(help.status, 0, help.stderr);
  assert.match(help.stdout, /Usage: chronolog/);
});
