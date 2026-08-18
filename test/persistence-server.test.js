import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { applyOps, createJournalStore, parseJournal, serializeEntry } from "../tools/journal.js";

function startServer(root, extraEnvironment = {}) {
  const child = spawn(process.execPath, ["tools/serve.js"], {
    cwd: process.cwd(),
    env: { ...process.env, CHRONOLOG_DATA_DIR: root, CHRONOLOG_PORT: "0", ...extraEnvironment },
    // stdin is a pipe so tests can request the same clean shutdown the
    // launcher does; see the shutdown test below.
    stdio: ["pipe", "pipe", "pipe"]
  });
  return new Promise((resolve, reject) => {
    let output = "";
    child.stdout.on("data", (chunk) => {
      output += chunk;
      const match = output.match(/127\.0\.0\.1:(\d+)/);
      if (match) resolve({ child, url: `http://127.0.0.1:${match[1]}`, output: () => output });
    });
    child.once("error", reject);
    child.stderr.on("data", (chunk) => { output += chunk; });
    child.once("exit", (code) => reject(new Error(`server exited (${code}): ${output}`)));
  });
}

async function stopServer(running, signal = "SIGKILL") {
  if (!running || running.child.exitCode !== null) return;
  const stopped = once(running.child, "exit");
  running.child.kill(signal);
  await stopped;
}

async function withServer(prefix, run, extraEnvironment = {}) {
  const root = await mkdtemp(join(tmpdir(), prefix));
  let running = null;
  try {
    running = await startServer(root, extraEnvironment);
    await run({ root, running });
  } finally {
    await stopServer(running);
    await rm(root, { recursive: true, force: true });
  }
}

const BASE_DOCUMENT = { schema: "chronolog/1", events: {}, frames: {}, patterns: {}, relations: {}, overrides: {}, meta: {}, foreign: {} };

function baseDocument() {
  return JSON.parse(JSON.stringify(BASE_DOCUMENT));
}

async function putSnapshot(url, document = baseDocument()) {
  const response = await fetch(`${url}/api/snapshot`, {
    method: "PUT",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(document)
  });
  assert.equal(response.status, 200);
  return (await response.json()).seq;
}

async function postJournal(url, baseSeq, entries) {
  const response = await fetch(`${url}/api/journal`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ baseSeq, entries })
  });
  return { status: response.status, value: await response.json() };
}

async function getDocument(url) {
  const response = await fetch(`${url}/api/document`, { cache: "no-store" });
  assert.equal(response.status, 200);
  return {
    seq: Number(response.headers.get("x-chronolog-seq")),
    document: JSON.parse(await response.text())
  };
}

// --- the op engine: domain-free record assignment ---------------------------

// The server applies ops without knowing what any record means. That is the
// property that lets it compact the journal on the owner's behalf, so it is
// worth asserting directly rather than only through the HTTP surface.
test("ops are applied as uniform record assignment across every map", () => {
  const document = baseDocument();
  applyOps(document, [
    { op: "put", map: "events", id: "event:1", value: { id: "event:1", payload: { title: "a" } } },
    { op: "put", map: "frames", id: "frame:1", value: { id: "frame:1", traits: ["line"] } },
    { op: "put", map: "patterns", id: "pattern:1", value: { id: "pattern:1" } },
    { op: "put", map: "relations", id: "relation:1", value: { id: "relation:1", event: "event:1" } },
    { op: "put", map: "overrides", id: "override:1", value: { suppress: true } },
    // meta and foreign are records keyed by their own top-level property name.
    { op: "put", map: "meta", id: "modified", value: "2026-08-18T00:00:00.000Z" },
    { op: "put", map: "foreign", id: "ics", value: { sources: {} } }
  ]);
  assert.equal(document.events["event:1"].payload.title, "a");
  assert.deepEqual(document.frames["frame:1"].traits, ["line"]);
  assert.ok(document.patterns["pattern:1"]);
  assert.equal(document.relations["relation:1"].event, "event:1");
  assert.equal(document.overrides["override:1"].suppress, true);
  assert.equal(document.meta.modified, "2026-08-18T00:00:00.000Z");
  assert.deepEqual(document.foreign.ics, { sources: {} });

  applyOps(document, [
    { op: "del", map: "events", id: "event:1" },
    { op: "del", map: "foreign", id: "ics" }
  ]);
  assert.equal(document.events["event:1"], undefined);
  assert.equal(document.foreign.ics, undefined);
});

// Replaying an entry that is already folded into the snapshot must be a no-op.
// Compaction depends on it: if the process dies after the new snapshot lands
// but before the journal is truncated, boot replays those entries again.
test("record-level ops are idempotent, so replaying folded entries changes nothing", () => {
  const ops = [
    { op: "put", map: "events", id: "event:1", value: { id: "event:1", n: 1 } },
    { op: "del", map: "events", id: "event:2" }
  ];
  const once_ = baseDocument();
  applyOps(once_, ops);
  const twice = baseDocument();
  applyOps(twice, ops);
  applyOps(twice, ops);
  assert.deepEqual(twice, once_);
});

test("ops naming an unknown map or verb are rejected", () => {
  assert.throws(() => applyOps(baseDocument(), [{ op: "put", map: "sessions", id: "a", value: 1 }]), RangeError);
  assert.throws(() => applyOps(baseDocument(), [{ op: "merge", map: "events", id: "a", value: 1 }]), RangeError);
  assert.throws(() => applyOps(baseDocument(), [{ op: "put", map: "events", id: "a" }]), TypeError);
});

// --- crash tolerance -------------------------------------------------------

test("a truncated final journal line is discarded with a warning, never fatally", () => {
  const good = serializeEntry({ seq: 1, ts: "t", label: "one", ops: [] })
    + serializeEntry({ seq: 2, ts: "t", label: "two", ops: [] });
  const partial = '{"seq":3,"ts":"t","label":"thr';
  const parsed = parseJournal(good + partial);
  assert.deepEqual(parsed.entries.map((entry) => entry.seq), [1, 2]);
  assert.equal(parsed.warnings.length, 1);
  assert.match(parsed.warnings[0], /truncated final journal line/);
  // The healthy prefix ends exactly where the last complete line ended, so the
  // file can be truncated back to it before the next append.
  assert.equal(parsed.healthyBytes, Buffer.byteLength(good));
});

test("boot replays the journal over the snapshot and heals a partial tail", async () => {
  const root = await mkdtemp(join(tmpdir(), "chronolog-replay-"));
  try {
    const snapshot = baseDocument();
    snapshot.events["event:kept"] = { id: "event:kept", payload: { title: "from snapshot" } };
    await writeFile(join(root, "chronolog.chronolog"), JSON.stringify(snapshot) + "\n");
    const complete = serializeEntry({
      seq: 1, ts: "t", label: "Edit event",
      ops: [{ op: "put", map: "events", id: "event:kept", value: { id: "event:kept", payload: { title: "from journal" } } }]
    }) + serializeEntry({
      seq: 2, ts: "t", label: "Create event",
      ops: [{ op: "put", map: "events", id: "event:new", value: { id: "event:new" } }]
    });
    await writeFile(join(root, "chronolog.journal"), complete + '{"seq":3,"ops":[{"op":"pu');

    const warnings = [];
    const store = createJournalStore({ dataRoot: root, warn: (message) => warnings.push(message) });
    const boot = await store.load();
    assert.equal(boot.present, true);
    assert.equal(boot.replayed, 2, "both complete entries replay");
    assert.equal(store.seq, 2, "the truncated line never claimed a sequence number");
    assert.equal(store.document.events["event:kept"].payload.title, "from journal", "journal wins over snapshot");
    assert.ok(store.document.events["event:new"], "later entries replay too");
    assert.equal(warnings.length, 1);
    // Healed on disk, so the next append cannot land after a partial line.
    assert.equal(await readFile(join(root, "chronolog.journal"), "utf8"), complete);

    // And an append onto the healed file is readable by a fresh load.
    await store.append(2, [{ label: "After heal", ops: [{ op: "put", map: "events", id: "event:third", value: { id: "event:third" } }] }]);
    store.stop();
    const reopened = createJournalStore({ dataRoot: root, warn: () => {} });
    await reopened.load();
    assert.equal(reopened.seq, 3);
    assert.ok(reopened.document.events["event:third"]);
    reopened.stop();
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("compaction folds the journal into the snapshot and leaves the document identical", async () => {
  const root = await mkdtemp(join(tmpdir(), "chronolog-compact-"));
  try {
    await writeFile(join(root, "chronolog.chronolog"), JSON.stringify(baseDocument()) + "\n");
    const store = createJournalStore({ dataRoot: root, warn: () => {} });
    await store.load();
    await store.append(0, [
      { label: "a", ops: [{ op: "put", map: "events", id: "event:1", value: { id: "event:1", n: 1 } }] },
      { label: "b", ops: [{ op: "put", map: "events", id: "event:2", value: { id: "event:2", n: 2 } }] }
    ]);
    await store.append(2, [
      { label: "c", ops: [{ op: "del", map: "events", id: "event:1" }] }
    ]);
    const before = JSON.parse(JSON.stringify(store.document));
    assert.equal(store.seq, 3);

    const result = await store.compact();
    assert.equal(result.compacted, true);
    assert.equal(result.folded, 3);
    assert.equal(await readFile(join(root, "chronolog.journal"), "utf8"), "", "the journal is truncated");
    // The compacted snapshot alone must reproduce the materialized document,
    // including the deletion — a fold that only replayed puts would resurrect
    // event:1 here.
    const snapshot = JSON.parse(await readFile(join(root, "chronolog.chronolog"), "utf8"));
    assert.deepEqual(snapshot, before);
    assert.equal(snapshot.events["event:1"], undefined);
    assert.ok(snapshot.events["event:2"]);
    store.stop();

    // Sequence numbers survive compaction, so a client that reconnects with
    // its last known seq is still recognised as current.
    const reopened = createJournalStore({ dataRoot: root, warn: () => {} });
    await reopened.load();
    assert.equal(reopened.seq, 3, "seq is not reset by compaction");
    assert.deepEqual(reopened.document, before);
    // History below the fold cannot be replayed as ops any more, so a lagging
    // client is told to reload rather than handed a silent gap.
    assert.equal(reopened.since(1).truncated, true);
    assert.deepEqual(reopened.since(3).entries, []);
    reopened.stop();
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("a crash after the compacted snapshot but before truncation still loads correctly", async () => {
  const root = await mkdtemp(join(tmpdir(), "chronolog-crash-compact-"));
  try {
    // Exactly the window between atomicWrite(snapshot) and truncate(journal):
    // the snapshot already contains the entries the journal still describes.
    const folded = baseDocument();
    folded.events["event:1"] = { id: "event:1", n: 1 };
    await writeFile(join(root, "chronolog.chronolog"), JSON.stringify(folded) + "\n");
    await writeFile(join(root, "chronolog.journal"), serializeEntry({
      seq: 1, ts: "t", label: "a",
      ops: [{ op: "put", map: "events", id: "event:1", value: { id: "event:1", n: 1 } }]
    }));
    await writeFile(join(root, ".chronolog-journal-state.json"), JSON.stringify({ seq: 1, base: 0 }) + "\n");

    const store = createJournalStore({ dataRoot: root, warn: () => {} });
    await store.load();
    assert.equal(store.seq, 1);
    assert.deepEqual(store.document, folded, "replaying an already-folded entry is a no-op");
    store.stop();
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

// --- the HTTP surface ------------------------------------------------------

test("journal appends assign sequence numbers and materialize into GET /api/document", async () => {
  await withServer("chronolog-journal-http-", async ({ root, running }) => {
    assert.equal((await fetch(`${running.url}/api/document`)).status, 404, "a fresh data directory has no document");
    assert.equal(await putSnapshot(running.url), 1);

    const first = await postJournal(running.url, 1, [{
      label: "Create event",
      ops: [{ op: "put", map: "events", id: "event:1", value: { id: "event:1", payload: { title: "first" } } }]
    }]);
    assert.equal(first.status, 200);
    assert.equal(first.value.seq, 2);

    const second = await postJournal(running.url, 2, [
      { label: "Edit event", ops: [{ op: "put", map: "events", id: "event:1", value: { id: "event:1", payload: { title: "edited" } } }] },
      { label: "Bump", ops: [{ op: "put", map: "meta", id: "modified", value: "2026-08-18T00:00:00.000Z" }] }
    ]);
    assert.equal(second.status, 200);
    assert.equal(second.value.seq, 4, "each entry in a batch takes its own sequence number");

    const materialized = await getDocument(running.url);
    assert.equal(materialized.seq, 4);
    assert.equal(materialized.document.events["event:1"].payload.title, "edited");
    assert.equal(materialized.document.meta.modified, "2026-08-18T00:00:00.000Z");

    // The journal on disk is JSONL, one line per committed edit.
    const lines = (await readFile(join(root, "chronolog.journal"), "utf8")).split("\n").filter(Boolean);
    assert.equal(lines.length, 3);
    assert.deepEqual(lines.map((line) => JSON.parse(line).seq), [2, 3, 4]);
    assert.deepEqual(lines.map((line) => JSON.parse(line).label), ["Create event", "Edit event", "Bump"]);
    // The owner's snapshot is untouched until compaction runs.
    assert.deepEqual(JSON.parse(await readFile(join(root, "chronolog.chronolog"), "utf8")).events, {});
  });
});

test("a stale baseSeq is rejected with the entries the client missed", async () => {
  await withServer("chronolog-journal-cas-", async ({ running }) => {
    const seq = await putSnapshot(running.url);

    // Client A commits first.
    const writeA = await postJournal(running.url, seq, [{
      label: "A edit",
      ops: [{ op: "put", map: "events", id: "event:a", value: { id: "event:a", owner: "A" } }]
    }]);
    assert.equal(writeA.status, 200);

    // Client B still believes it is current at the pre-A sequence number.
    const writeB = await postJournal(running.url, seq, [{
      label: "B edit",
      ops: [{ op: "put", map: "events", id: "event:b", value: { id: "event:b", owner: "B" } }]
    }]);
    assert.equal(writeB.status, 409);
    assert.equal(writeB.value.currentSeq, writeA.value.seq);
    assert.equal(writeB.value.truncated, false);
    assert.equal(writeB.value.missed.length, 1, "the response carries what B has to rebase onto");
    assert.equal(writeB.value.missed[0].label, "A edit");
    assert.deepEqual(writeB.value.missed[0].ops[0], {
      op: "put", map: "events", id: "event:a", value: { id: "event:a", owner: "A" }
    });

    // B's own edit was not written.
    const afterConflict = await getDocument(running.url);
    assert.ok(afterConflict.document.events["event:a"]);
    assert.equal(afterConflict.document.events["event:b"], undefined);

    // Rebased onto the reported sequence number, B commits.
    const rebased = await postJournal(running.url, writeB.value.currentSeq, [{
      label: "B edit",
      ops: [{ op: "put", map: "events", id: "event:b", value: { id: "event:b", owner: "B" } }]
    }]);
    assert.equal(rebased.status, 200);
    const settled = await getDocument(running.url);
    assert.ok(settled.document.events["event:a"], "A's record survives the rebase");
    assert.ok(settled.document.events["event:b"], "and B's lands beside it");
  });
});

test("GET /api/journal?since serves the tail a lagging client needs", async () => {
  await withServer("chronolog-journal-since-", async ({ running }) => {
    const seq = await putSnapshot(running.url);
    await postJournal(running.url, seq, [
      { label: "one", ops: [{ op: "put", map: "events", id: "event:1", value: { id: "event:1" } }] },
      { label: "two", ops: [{ op: "put", map: "events", id: "event:2", value: { id: "event:2" } }] }
    ]);

    const all = await (await fetch(`${running.url}/api/journal?since=${seq}`)).json();
    assert.equal(all.currentSeq, seq + 2);
    assert.equal(all.truncated, false);
    assert.deepEqual(all.entries.map((entry) => entry.label), ["one", "two"]);

    const tail = await (await fetch(`${running.url}/api/journal?since=${seq + 1}`)).json();
    assert.deepEqual(tail.entries.map((entry) => entry.label), ["two"]);

    const current = await (await fetch(`${running.url}/api/journal?since=${seq + 2}`)).json();
    assert.deepEqual(current.entries, []);
  });
});

test("a snapshot upload replaces the whole document, drops the journal, and advances seq", async () => {
  await withServer("chronolog-snapshot-put-", async ({ root, running }) => {
    const seq = await putSnapshot(running.url);
    await postJournal(running.url, seq, [{
      label: "Create event",
      ops: [{ op: "put", map: "events", id: "event:old", value: { id: "event:old" } }]
    }]);

    const replacement = baseDocument();
    replacement.events["event:opened"] = { id: "event:opened", payload: { title: "another file" } };
    const uploadedSeq = await putSnapshot(running.url, replacement);
    assert.ok(uploadedSeq > seq + 1, "seq advances rather than resetting, so other windows go stale");

    const materialized = await getDocument(running.url);
    assert.equal(materialized.seq, uploadedSeq);
    assert.equal(materialized.document.events["event:old"], undefined, "the previous document is gone");
    assert.ok(materialized.document.events["event:opened"]);
    assert.equal(await readFile(join(root, "chronolog.journal"), "utf8"), "", "ops describing the old document are dropped");

    // A window still holding the pre-upload sequence number cannot rebase onto
    // a document that no longer exists, so it is told to reload instead.
    const stale = await postJournal(running.url, seq, [{
      label: "stale",
      ops: [{ op: "put", map: "events", id: "event:stale", value: { id: "event:stale" } }]
    }]);
    assert.equal(stale.status, 409);
    assert.equal(stale.value.truncated, true);
    assert.deepEqual(stale.value.missed, []);
  });
});

test("the snapshot period is readable and writable for the settings UI", async () => {
  await withServer("chronolog-settings-", async ({ root, running }) => {
    const initial = await (await fetch(`${running.url}/api/settings`)).json();
    assert.equal(initial.snapshotPeriodMinutes, 10, "the default period");

    const updated = await fetch(`${running.url}/api/settings`, {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ snapshotPeriodMinutes: 3 })
    });
    assert.equal(updated.status, 200);
    assert.equal((await updated.json()).snapshotPeriodMinutes, 3);
    assert.equal((await (await fetch(`${running.url}/api/settings`)).json()).snapshotPeriodMinutes, 3);
    assert.equal(JSON.parse(await readFile(join(root, ".chronolog-settings.json"), "utf8")).snapshotPeriodMinutes, 3);

    const rejected = await fetch(`${running.url}/api/settings`, {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ snapshotPeriodMinutes: 0 })
    });
    assert.equal(rejected.status, 400);
    assert.equal((await (await fetch(`${running.url}/api/settings`)).json()).snapshotPeriodMinutes, 3, "a rejected write changes nothing");
  });
});

test("a clean shutdown compacts, and the next boot needs no replay", async () => {
  const root = await mkdtemp(join(tmpdir(), "chronolog-shutdown-"));
  let running = null;
  try {
    running = await startServer(root);
    const seq = await putSnapshot(running.url);
    await postJournal(running.url, seq, [{
      label: "Create event",
      ops: [{ op: "put", map: "events", id: "event:1", value: { id: "event:1", payload: { title: "kept" } } }]
    }]);

    // Closing stdin is the portable "please shut down cleanly" request: on
    // Windows a killed child never runs a signal handler, so this is the only
    // path that behaves the same on both target platforms.
    const stopped = once(running.child, "exit");
    running.child.stdin.end();
    await stopped;
    running = null;

    // The clean shutdown left a current snapshot and an empty journal.
    assert.equal(await readFile(join(root, "chronolog.journal"), "utf8"), "");
    const snapshot = JSON.parse(await readFile(join(root, "chronolog.chronolog"), "utf8"));
    assert.equal(snapshot.events["event:1"].payload.title, "kept");

    running = await startServer(root);
    const reloaded = await getDocument(running.url);
    assert.equal(reloaded.seq, seq + 1, "the sequence number survived the restart");
    assert.equal(reloaded.document.events["event:1"].payload.title, "kept");
  } finally {
    await stopServer(running);
    await rm(root, { recursive: true, force: true });
  }
});

test("an unclean shutdown recovers by replaying the journal at boot", async () => {
  const root = await mkdtemp(join(tmpdir(), "chronolog-recover-"));
  let running = null;
  try {
    running = await startServer(root);
    const seq = await putSnapshot(running.url);
    await postJournal(running.url, seq, [{
      label: "Create event",
      ops: [{ op: "put", map: "events", id: "event:1", value: { id: "event:1", payload: { title: "survives" } } }]
    }]);
    // Killed outright: no shutdown compaction runs, so the edit exists only in
    // the journal. Recovery is replay, which is what replaced the old rolling
    // recovery copy.
    await stopServer(running, "SIGKILL");
    running = null;
    assert.notEqual(await readFile(join(root, "chronolog.journal"), "utf8"), "");
    assert.deepEqual(JSON.parse(await readFile(join(root, "chronolog.chronolog"), "utf8")).events, {});

    running = await startServer(root);
    const recovered = await getDocument(running.url);
    assert.equal(recovered.document.events["event:1"].payload.title, "survives", "the committed edit came back");
    assert.equal(recovered.seq, seq + 1);
    // Boot folded it in, so the next start has nothing to replay.
    assert.equal(await readFile(join(root, "chronolog.journal"), "utf8"), "");
  } finally {
    await stopServer(running);
    await rm(root, { recursive: true, force: true });
  }
});

test("the deleted whole-document write and recovery endpoints are gone", async () => {
  await withServer("chronolog-removed-", async ({ running }) => {
    await putSnapshot(running.url);
    const put = await fetch(`${running.url}/api/document`, {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(baseDocument())
    });
    assert.equal(put.status, 405, "autosave no longer overwrites the whole document");
    assert.equal(put.headers.get("allow"), "GET, HEAD");
    assert.equal((await fetch(`${running.url}/api/document/recovery`)).status, 404, "the rolling recovery copy is gone");
  });
});

test("workspace files stay unreachable through the static file route", async () => {
  await withServer("chronolog-static-guard-", async ({ root, running }) => {
    await putSnapshot(running.url);
    assert.equal((await fetch(`${running.url}/chronolog.chronolog`)).status, 403);
    assert.equal((await fetch(`${running.url}/chronolog.journal`)).status, 403);
    assert.equal((await fetch(`${running.url}/.chronolog-journal-state.json`)).status, 403);
    assert.equal((await fetch(`${running.url}/.chronolog-settings.json`)).status, 403);
    assert.ok(root);
  });
});

test("sync configuration is reachable only through the API and never through static files", async () => {
  const root = await mkdtemp(join(tmpdir(), "chronolog-sync-config-"));
  let running;
  try {
    await writeFile(join(root, "pocket-instrument.html"), "<!doctype html><title>test</title>");
    running = await startServer(root, { CHRONOLOG_APP_ROOT: root });
    const created = await fetch(`${running.url}/api/sync/feeds`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ label: "Secret feed", url: "https://calendar.example/feed.ics?token=private" })
    });
    assert.equal(created.status, 201);
    assert.doesNotMatch(await created.text(), /private/);
    const listed = await fetch(`${running.url}/api/sync/connections`);
    assert.equal(listed.status, 200);
    assert.doesNotMatch(await listed.text(), /private/);
    const staticCredential = await fetch(`${running.url}/.chronolog-calendar-connections.json`);
    assert.equal(staticCredential.status, 403);
  } finally {
    await stopServer(running);
    await rm(root, { recursive: true, force: true });
  }
});
