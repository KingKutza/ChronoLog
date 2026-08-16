import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { tmpdir } from "node:os";
import { join } from "node:path";

function startServer(root, extraEnvironment = {}) {
  const child = spawn(process.execPath, ["tools/serve.js"], {
    cwd: process.cwd(),
    env: { ...process.env, CHRONOLOG_DATA_DIR: root, CHRONOLOG_PORT: "0", ...extraEnvironment },
    stdio: ["ignore", "pipe", "pipe"]
  });
  return new Promise((resolve, reject) => {
    let output = "";
    child.stdout.on("data", (chunk) => {
      output += chunk;
      const match = output.match(/127\.0\.0\.1:(\d+)/);
      if (match) resolve({ child, url: `http://127.0.0.1:${match[1]}` });
    });
    child.once("error", reject);
    child.stderr.on("data", (chunk) => { output += chunk; });
    child.once("exit", (code) => reject(new Error(`server exited (${code}): ${output}`)));
  });
}

test("local workspace saves are atomic, revision-guarded, and retain one recovery copy", async () => {
  const root = await mkdtemp(join(tmpdir(), "chronolog-persistence-"));
  let running;
  try {
    running = await startServer(root);
    const first = '{"schema":"chronolog/1","version":1}\n';
    const initial = await fetch(`${running.url}/api/document`, { method: "PUT", body: first });
    assert.equal(initial.status, 204);
    const firstRevision = initial.headers.get("etag");
    assert.ok(firstRevision);

    const second = '{"schema":"chronolog/1","version":2}\n';
    const replacement = await fetch(`${running.url}/api/document`, {
      method: "PUT", headers: { "if-match": firstRevision }, body: second
    });
    assert.equal(replacement.status, 204);
    assert.notEqual(replacement.headers.get("etag"), firstRevision);
    assert.equal(await (await fetch(`${running.url}/api/document/recovery`)).text(), first);

    const stale = await fetch(`${running.url}/api/document`, {
      method: "PUT", headers: { "if-match": firstRevision }, body: '{"schema":"chronolog/1","version":3}\n'
    });
    assert.equal(stale.status, 409);
    assert.equal(await (await fetch(`${running.url}/api/document`)).text(), second);
    assert.equal(await readFile(join(root, "chronolog.chronolog"), "utf8"), second);
  } finally {
    if (running?.child.exitCode === null) {
      const stopped = once(running.child, "exit");
      running.child.kill();
      await stopped;
    }
    await rm(root, { recursive: true, force: true });
  }
});

test("LAN sync requires its bearer token, preserves both clients on conflict, and rejects cross-origin browsers", async () => {
  const root = await mkdtemp(join(tmpdir(), "chronolog-lan-"));
  let running;
  try {
    running = await startServer(root, { CHRONOLOG_LAN: "1", CHRONOLOG_LAN_TOKEN: "a-tested-lan-token-with-entropy" });
    const first = '{"schema":"chronolog/1","client":"A"}\n';
    const denied = await fetch(`${running.url}/api/document`, { method: "PUT", body: first });
    assert.equal(denied.status, 403);

    const authenticated = { authorization: "Bearer a-tested-lan-token-with-entropy" };
    const writeA = await fetch(`${running.url}/api/document`, { method: "PUT", headers: authenticated, body: first });
    assert.equal(writeA.status, 204);
    const revisionA = writeA.headers.get("etag");

    const second = '{"schema":"chronolog/1","client":"B"}\n';
    const writeB = await fetch(`${running.url}/api/document`, {
      method: "PUT", headers: { ...authenticated, "if-match": revisionA }, body: second
    });
    assert.equal(writeB.status, 204);
    const staleA = await fetch(`${running.url}/api/document`, {
      method: "PUT", headers: { ...authenticated, "if-match": revisionA }, body: '{"schema":"chronolog/1","client":"A-conflict"}\n'
    });
    assert.equal(staleA.status, 409);
    assert.equal(await (await fetch(`${running.url}/api/document`, { headers: authenticated })).text(), second);
    assert.equal(await (await fetch(`${running.url}/api/document/recovery`, { headers: authenticated })).text(), first);

    const crossOrigin = await fetch(`${running.url}/api/document`, {
      headers: { ...authenticated, origin: "http://untrusted.example" }
    });
    assert.equal(crossOrigin.status, 403);
    assert.equal(crossOrigin.headers.get("access-control-allow-origin"), null);
  } finally {
    if (running?.child.exitCode === null) {
      const stopped = once(running.child, "exit");
      running.child.kill();
      await stopped;
    }
    await rm(root, { recursive: true, force: true });
  }
});
