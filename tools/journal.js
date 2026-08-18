// The journal + snapshot persistence engine.
//
// `chronolog.chronolog` is a snapshot: a plain serialized document. Every
// committed edit appends one JSONL line to `chronolog.journal` in the same
// data directory. Loading is snapshot-plus-replay; compaction folds the
// journal back into the snapshot and truncates it.
//
// This module holds ZERO domain knowledge. An op names a map and a record id
// and either assigns a JSON value or deletes it — `document[map][id] = value`
// or `delete document[map][id]`, uniformly for all seven maps. `meta` and
// `foreign` are records keyed by their own top-level property name, which is
// exactly why no map needs special handling here. That uniformity is what
// makes server-side compaction possible without teaching the server what an
// event, a frame, or an ICS source is.

import { open, readFile, rename, unlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { RECORD_MAPS, applyOps } from "../src/ops.js";

// What an op means is defined once, in src/ops.js, and imported by both sides.
// The client replays a conflicting window's ops with the same function the
// server replays the journal with; two implementations that drifted apart
// would corrupt documents quietly.
export { applyOps };
export const OP_MAPS = RECORD_MAPS;
const OP_MAP_SET = new Set(OP_MAPS);
export const DEFAULT_SNAPSHOT_PERIOD_MINUTES = 10;

export function validateEntryOps(ops) {
  if (!Array.isArray(ops)) throw new TypeError("entry.ops must be an array");
  for (const op of ops) {
    if (!op || typeof op !== "object") throw new TypeError("journal op must be an object");
    if (!OP_MAP_SET.has(op.map)) throw new RangeError(`unknown journal map "${op.map}"`);
    if (typeof op.id !== "string" || !op.id) throw new TypeError("journal op needs a record id");
    if (op.op === "put") {
      if (op.value === undefined) throw new TypeError(`put op for ${op.map}/${op.id} carries no value`);
    } else if (op.op !== "del") {
      throw new RangeError(`unknown journal op "${op.op}"`);
    }
  }
  return ops;
}

// Parses a journal buffer into entries. A process killed between `write` and
// `fsync` can leave a partial final line; that line is discarded with a
// warning and the healthy byte length is reported so the caller can truncate
// the file back to it. A damaged interior line is skipped with a warning too —
// losing one edit is bad, but refusing to open the document is worse.
export function parseJournal(text) {
  const entries = [];
  const warnings = [];
  let healthyBytes = 0;
  const lines = text.split("\n");
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    const isLast = index === lines.length - 1;
    if (!line) {
      if (!isLast) healthyBytes += 1;
      continue;
    }
    let entry = null;
    try {
      entry = JSON.parse(line);
    } catch {
      warnings.push(isLast
        ? `discarded a truncated final journal line (${line.length} bytes); the last append did not complete`
        : `skipped an unreadable journal line at line ${index + 1}`);
      if (!isLast) healthyBytes += Buffer.byteLength(line) + 1;
      continue;
    }
    if (!entry || typeof entry !== "object" || !Number.isInteger(entry.seq) || !Array.isArray(entry.ops)) {
      warnings.push(`skipped a malformed journal entry at line ${index + 1}`);
      if (!isLast) healthyBytes += Buffer.byteLength(line) + 1;
      continue;
    }
    entries.push(entry);
    healthyBytes += Buffer.byteLength(line) + (isLast ? 0 : 1);
  }
  return { entries, warnings, healthyBytes };
}

export function serializeEntry(entry) {
  return JSON.stringify(entry) + "\n";
}

export class JournalConflict extends Error {
  constructor(currentSeq, missed, truncated) {
    super(`journal is at seq ${currentSeq}`);
    this.name = "JournalConflict";
    this.currentSeq = currentSeq;
    this.missed = missed;
    this.truncated = truncated;
  }
}

async function atomicWrite(dataRoot, file, body) {
  const temporary = join(
    dataRoot,
    `.chronolog-save-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}.tmp`
  );
  const descriptor = await open(temporary, "wx", 0o600);
  try {
    await descriptor.writeFile(body);
    await descriptor.sync();
  } finally {
    await descriptor.close();
  }
  try {
    await rename(temporary, file);
  } finally {
    await unlink(temporary).catch(() => {});
  }
}

export function createJournalStore({ dataRoot, warn = () => {} }) {
  const snapshotFile = join(dataRoot, "chronolog.chronolog");
  const journalFile = join(dataRoot, "chronolog.journal");
  const stateFile = join(dataRoot, ".chronolog-journal-state.json");
  const settingsFile = join(dataRoot, ".chronolog-settings.json");

  let document = null;
  let currentSeq = 0;
  // Entries still in the journal file, kept so a lagging client can rebase.
  // Compaction clears this; `journalBase` then records the seq below which
  // history is no longer reconstructible and a full reload is required.
  let entries = [];
  let journalBase = 0;
  let serialized = null;
  let writes = Promise.resolve();
  let periodic = null;

  function invalidate() {
    serialized = null;
  }

  async function readSidecarSeq() {
    try {
      const parsed = JSON.parse(await readFile(stateFile, "utf8"));
      return {
        seq: Number.isInteger(parsed?.seq) ? parsed.seq : 0,
        base: Number.isInteger(parsed?.base) ? parsed.base : 0
      };
    } catch (error) {
      if (error?.code !== "ENOENT") warn(`journal state unreadable: ${error.message}`);
      return { seq: 0, base: 0 };
    }
  }

  async function load() {
    let snapshotText = null;
    try {
      snapshotText = await readFile(snapshotFile, "utf8");
    } catch (error) {
      if (error?.code !== "ENOENT") throw error;
    }
    let journalText = "";
    let journalPresent = false;
    try {
      journalText = await readFile(journalFile, "utf8");
      journalPresent = true;
    } catch (error) {
      if (error?.code !== "ENOENT") throw error;
    }
    if (snapshotText === null && !journalPresent) {
      document = null;
      currentSeq = 0;
      entries = [];
      journalBase = 0;
      invalidate();
      return { present: false, replayed: 0, warnings: [] };
    }

    const sidecar = await readSidecarSeq();
    const parsedJournal = parseJournal(journalText);
    for (const message of parsedJournal.warnings) warn(message);
    if (journalPresent && parsedJournal.healthyBytes !== Buffer.byteLength(journalText)) {
      // Heal the file so the next append does not build on a partial line.
      const handle = await open(journalFile, "r+");
      try {
        await handle.truncate(parsedJournal.healthyBytes);
        await handle.sync();
      } finally {
        await handle.close();
      }
    }

    if (snapshotText === null) {
      warn("no snapshot found; replaying the journal onto an empty document");
      document = {};
    } else {
      document = JSON.parse(snapshotText);
    }

    entries = parsedJournal.entries;
    let replayed = 0;
    for (const entry of entries) {
      applyOps(document, entry.ops);
      replayed += 1;
    }
    const lastJournalSeq = entries.length ? entries[entries.length - 1].seq : 0;
    // Both sources are authoritative in different crash windows: the sidecar
    // survives a truncated journal, the journal survives a lost sidecar.
    currentSeq = Math.max(sidecar.seq, lastJournalSeq);
    journalBase = entries.length ? entries[0].seq - 1 : Math.max(sidecar.base, currentSeq);
    invalidate();
    return { present: true, replayed, warnings: parsedJournal.warnings };
  }

  async function writeState() {
    await atomicWrite(dataRoot, stateFile, JSON.stringify({ seq: currentSeq, base: journalBase }) + "\n");
  }

  // Appends are serialized through one promise chain so seq assignment and
  // byte order can never interleave, and each append is fsynced before the
  // caller is told it committed.
  function append(baseSeq, incoming) {
    const run = writes.then(async () => {
      if (baseSeq !== currentSeq) {
        const missed = entries.filter((entry) => entry.seq > baseSeq);
        // History below journalBase was folded into the snapshot, so it can no
        // longer be replayed as ops; the client must reload instead.
        throw new JournalConflict(currentSeq, missed, baseSeq < journalBase);
      }
      for (const entry of incoming) validateEntryOps(entry?.ops);
      const stamped = [];
      let body = "";
      const timestamp = new Date().toISOString();
      let seq = currentSeq;
      for (const entry of incoming) {
        seq += 1;
        const line = { seq, ts: timestamp, label: String(entry.label ?? ""), ops: entry.ops };
        stamped.push(line);
        body += serializeEntry(line);
      }
      if (stamped.length) {
        const handle = await open(journalFile, "a", 0o600);
        try {
          await handle.writeFile(body);
          await handle.sync();
        } finally {
          await handle.close();
        }
        for (const entry of stamped) {
          applyOps(document, entry.ops);
          entries.push(entry);
        }
        currentSeq = seq;
        invalidate();
        await writeState();
      }
      return { seq: currentSeq };
    });
    writes = run.catch(() => {});
    return run;
  }

  function since(seq) {
    return {
      currentSeq,
      truncated: seq < journalBase,
      entries: entries.filter((entry) => entry.seq > seq)
    };
  }

  function body() {
    if (document === null) return null;
    // Rebuilt only when a GET actually arrives. Appends merely invalidate, so
    // a burst of edits costs no serialization at all.
    serialized ||= Buffer.from(JSON.stringify(document));
    return serialized;
  }

  // Compaction is the whole point of domain-free ops: fold the journal into
  // the snapshot, then truncate. Order matters — the snapshot must be durable
  // before the journal is dropped, and because ops are idempotent a crash
  // between the two simply replays entries that are already folded in.
  function compact({ force = false } = {}) {
    const run = writes.then(async () => {
      if (document === null) return { compacted: false, folded: 0 };
      if (!entries.length && !force) return { compacted: false, folded: 0 };
      const folded = entries.length;
      await atomicWrite(dataRoot, snapshotFile, JSON.stringify(document) + "\n");
      journalBase = currentSeq;
      await writeState();
      const handle = await open(journalFile, "w", 0o600);
      try {
        await handle.sync();
      } finally {
        await handle.close();
      }
      entries = [];
      return { compacted: true, folded };
    });
    writes = run.catch(() => {});
    return run;
  }

  // Whole-document replacement: the owner opening a different file. There is
  // no CAS here — it is an explicit, deliberate act, not an autosave. The
  // journal is dropped because its ops describe a document that no longer
  // exists, and seq advances rather than resetting so any other window's
  // baseSeq goes stale and it reloads instead of appending onto the wrong
  // document.
  function replaceSnapshot(nextDocument) {
    const run = writes.then(async () => {
      document = nextDocument;
      currentSeq += 1;
      journalBase = currentSeq;
      await atomicWrite(dataRoot, snapshotFile, JSON.stringify(document) + "\n");
      await writeState();
      const handle = await open(journalFile, "w", 0o600);
      try {
        await handle.sync();
      } finally {
        await handle.close();
      }
      entries = [];
      invalidate();
      return { seq: currentSeq };
    });
    writes = run.catch(() => {});
    return run;
  }

  async function readSettings() {
    try {
      const parsed = JSON.parse(await readFile(settingsFile, "utf8"));
      const minutes = Number(parsed?.snapshotPeriodMinutes);
      return {
        snapshotPeriodMinutes: Number.isFinite(minutes) && minutes > 0
          ? minutes
          : DEFAULT_SNAPSHOT_PERIOD_MINUTES
      };
    } catch (error) {
      if (error?.code !== "ENOENT") warn(`settings unreadable: ${error.message}`);
      return { snapshotPeriodMinutes: DEFAULT_SNAPSHOT_PERIOD_MINUTES };
    }
  }

  async function writeSettings(next) {
    const minutes = Number(next?.snapshotPeriodMinutes);
    if (!Number.isFinite(minutes) || minutes <= 0) throw new RangeError("snapshotPeriodMinutes must be a positive number");
    const settings = { snapshotPeriodMinutes: minutes };
    await writeFile(settingsFile, JSON.stringify(settings) + "\n", { mode: 0o600 });
    await schedule();
    return settings;
  }

  async function schedule() {
    if (periodic) clearInterval(periodic);
    const { snapshotPeriodMinutes } = await readSettings();
    periodic = setInterval(() => {
      compact().catch((error) => warn(`periodic compaction failed: ${error.message}`));
    }, snapshotPeriodMinutes * 60 * 1000);
    periodic.unref?.();
    return snapshotPeriodMinutes;
  }

  function stop() {
    if (periodic) clearInterval(periodic);
    periodic = null;
  }

  return {
    load,
    append,
    since,
    compact,
    replaceSnapshot,
    body,
    readSettings,
    writeSettings,
    schedule,
    stop,
    get document() { return document; },
    get seq() { return currentSeq; },
    get journalBase() { return journalBase; },
    get entryCount() { return entries.length; },
    get present() { return document !== null; }
  };
}
