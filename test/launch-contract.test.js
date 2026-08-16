import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { join, win32 } from "node:path";
import { fileURLToPath } from "node:url";
import { defaultDataDirectory, parseArguments } from "../bin/chronolog.js";

const root = fileURLToPath(new URL("..", import.meta.url));
const packageInfo = JSON.parse(await readFile(join(root, "package.json"), "utf8"));

assert.equal(packageInfo.bin.chronolog, "bin/chronolog.js");
assert.equal(packageInfo.scripts.dev, "node tools/serve.js");
assert.equal(packageInfo.scripts.start, "node bin/chronolog.js");
assert.match(await readFile(join(root, "tools", "serve.js"), "utf8"), /Chronolog \(\$\{mode\}\):/);
assert.deepEqual(parseArguments(["--no-open", "--port", "4312", "--data-dir", "./data"]), {
  open: false, port: 4312, dataDirectory: join(process.cwd(), "data"), lan: false, lanToken: null
});
assert.deepEqual(parseArguments(["--lan", "--lan-token", "a-long-enough-lan-token"]), {
  open: true, port: 0, dataDirectory: null, lan: true, lanToken: "a-long-enough-lan-token"
});
assert.throws(() => parseArguments(["--lan-token", "short"]), /at least 16/);
assert.throws(() => parseArguments(["--port", "wat"]), /--port/);
assert.equal(defaultDataDirectory({ HOME: "/home/alex" }, "linux"), "/home/alex/.local/share/chronolog");
assert.equal(defaultDataDirectory({ XDG_DATA_HOME: "/data" }, "linux"), "/data/chronolog");
assert.equal(defaultDataDirectory({ HOME: "/Users/alex" }, "darwin"), "/Users/alex/Library/Application Support/ChronoLog");
assert.equal(defaultDataDirectory({ APPDATA: "C:\\Users\\alex\\AppData\\Roaming" }, "win32"), win32.resolve("C:\\Users\\alex\\AppData\\Roaming", "ChronoLog"));
const help = spawnSync(process.execPath, [join(root, "bin/chronolog.js"), "--help"], { encoding: "utf8" });
assert.equal(help.status, 0, help.stderr);
assert.match(help.stdout, /Usage: chronolog/);
