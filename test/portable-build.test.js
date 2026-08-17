import assert from "node:assert/strict";
import { access, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { buildPortable, portableArguments } from "../tools/build-portable.js";

const root = new URL("..", import.meta.url);

test("portable arguments select explicit Linux and Windows targets", () => {
  const parsed = portableArguments(["--platform", "win32", "--runtime", process.execPath, "--output", "./dist/test"]);
  assert.equal(parsed.platform, "win32");
  assert.equal(parsed.runtime, process.execPath);
  assert.match(parsed.output, /dist[/\\]test$/);
  assert.throws(() => portableArguments(["--platform", "darwin"]), /linux or win32/);
});

test("portable build embeds a runtime, launcher, and release-only app tree", async () => {
  const temporary = await mkdtemp(join(tmpdir(), "chronolog-portable-test-"));
  const output = join(temporary, "bundle");
  try {
    const runtime = join(temporary, "stub-runtime");
    await writeFile(runtime, "#!/bin/sh\nexit 0\n", "utf8");
    const result = await buildPortable({ output, runtime, platform: "linux" });
    assert.equal(result.output, output);
    await Promise.all([
      access(join(output, "chronolog")),
      access(join(output, "runtime", "node")),
      access(join(output, "app", "bin", "chronolog.js")),
      access(join(output, "app", "pocket-instrument.html")),
      access(join(output, "README.txt"))
    ]);
    assert.match(await readFile(join(output, "chronolog"), "utf8"), /runtime\/node/);
    await assert.rejects(access(join(output, "app", "test")));
    await assert.rejects(access(join(output, "app", "chronolog.chronolog")));
  } finally {
    // Best-effort: endpoint protection briefly holds fresh files, and fs.rm's
    // retry loop can wedge on them; a leftover temp dir must not fail the test.
    await rm(temporary, { recursive: true, force: true }).catch(() => {});
  }
});

test("package and release workflow expose both portable targets", async () => {
  const packageInfo = JSON.parse(await readFile(new URL("package.json", root), "utf8"));
  const workflow = await readFile(new URL(".github/workflows/portable-builds.yml", root), "utf8");
  assert.equal(packageInfo.scripts["build:portable"], "node tools/build-portable.js");
  assert.match(workflow, /platform: linux/);
  assert.match(workflow, /platform: win32/);
  assert.match(workflow, /gh release create/);
});
