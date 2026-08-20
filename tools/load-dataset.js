#!/usr/bin/env node
// Appends one declarative dataset file's records into a document, through the
// journal.
//
// A dataset file (`chronolog-dataset/0`, fixtures/datasets/) is deliberately
// close to nothing: document records, verbatim, in arrays named for the map
// they land in. There is exactly ONE expansion, for events, because an event is
// three records that always travel together (the event, its attachments, and
// its duration magnitude) and writing all three out longhand fifty times buries
// the data in punctuation:
//
//   {
//     "schema": "chronolog-dataset/0",
//     "dataset": "<stable slug>",
//     "title": "...",
//     "notes": ["constraints a reader of the data needs"],
//     "requires": ["frame:wall-time"],        ids that must already exist
//     "frames":    [ <frame record> ],        verbatim chronolog/1 records
//     "patterns":  [ <pattern record> ],      verbatim
//     "relations": [ <relation record> ],     verbatim
//     "overrides": [ <override record> ],     verbatim
//     "events":    [ { id, title, body?, traits?, duration?, on: [...] } ]
//   }
//
// An event expands as:
//   duration: { "minute": "20" }  ->  magnitudes.duration under MAGNITUDE_FRAME
//                                     (absent means zero)
//   on: [ { frame, role?, at: { "year": "1985", "month": "10" } } ]
//                                 ->  one attachment relation per entry, id
//                                     `relation:<event local>@<frame local>`
//   title / body                  ->  payload
//
// `at` and `duration` are level-name -> value maps, which is the same
// information as `{levels:[{level,value}]}` with less punctuation; the loader
// converts and nothing else interprets them. A derived attachment id is stable
// because it is derived from ids the dataset itself declares, which is what
// makes a second run a no-op.
//
// Idempotence is skip-if-present by record id, and a record whose id is already
// taken by DIFFERENT content is reported rather than merged: a dataset edited
// after it was loaded must not half-apply silently.
//
// The document is loaded and validated before anything is built and validated
// again before anything is appended. Nothing is written unless both pass,
// because validation runs at load time in this program and a document journaled
// into an invalid state fails long after the edit that caused it.
//
// Two targets, and picking the wrong one loses data. `--data-dir` appends to
// the journal FILE, which is only safe when nothing is serving that directory:
// a running server holds its own materialized document in memory and compacts
// from that, so an append it never saw is truncated away at the next
// compaction. `--server` posts the same ops to `POST /api/journal` instead, and
// that is the only correct target while a workspace is open. A conflicting
// baseSeq is reported and nothing is written -- rebasing is the store's job,
// not a one-shot loader's.
//
// Usage:
//   node tools/load-dataset.js <dataset.json> --server http://127.0.0.1:4173
//   node tools/load-dataset.js <dataset.json> [--data-dir <dir>] [--dry-run]

import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { coordinate } from "../src/exact.js";
import { addEvent, addFrame, addPattern, addRelation, clone, validateDocument } from "../src/model.js";
import { mapSnapshot, opsFromMaps } from "../src/ops.js";
import { createJournalStore } from "./journal.js";

const DATASET_SCHEMA = "chronolog-dataset/0";
const MAGNITUDE_FRAME = "measure:human-time";

// The maps a dataset may carry verbatim, each with the model helper that puts a
// record into it. `events` is absent on purpose -- it is the one expanded form.
const VERBATIM_MAPS = Object.freeze({
  frames: addFrame,
  patterns: addPattern,
  relations: addRelation
});

function localName(id) {
  const boundary = String(id).indexOf(":");
  return boundary < 0 ? String(id) : String(id).slice(boundary + 1);
}

function levelsFrom(map, subject) {
  const levels = Object.entries(map || {}).map(([level, value]) => ({ level, value: String(value) }));
  if (!levels.length) throw new Error(`${subject} names no levels`);
  return coordinate(levels);
}

function durationFrom(duration) {
  return {
    frame: MAGNITUDE_FRAME,
    value: duration && Object.keys(duration).length
      ? levelsFrom(duration, "duration")
      : coordinate([{ level: "second", value: "0" }])
  };
}

// One dataset event becomes its event record plus one attachment per `on`
// entry. Returned rather than written so the caller can skip what is already
// present without having half-built it.
function eventRecords(entry) {
  if (!entry?.id) throw new Error("a dataset event needs an id");
  const event = {
    id: entry.id,
    traits: entry.traits || ["event"],
    magnitudes: { duration: durationFrom(entry.duration) },
    payload: { title: entry.title || entry.id, ...(entry.body ? { body: entry.body } : {}) }
  };
  const attachments = (entry.on || []).map((placement) => {
    if (!placement?.frame) throw new Error(`event ${entry.id} has a placement with no frame`);
    return {
      id: `relation:${localName(entry.id)}@${localName(placement.frame)}`,
      type: "attachment",
      event: entry.id,
      frame: placement.frame,
      role: placement.role || "placed",
      // A placement with no `at` is deliberate in one dataset: an object the
      // author states has no position on the frame it belongs to. It stays a
      // record so the claim survives, and the engine simply never projects it.
      ...(placement.at ? { coordinate: levelsFrom(placement.at, `event ${entry.id} placement`) } : {})
    };
  });
  return [{ map: "events", record: event }, ...attachments.map((record) => ({ map: "relations", record }))];
}

function datasetRecords(dataset) {
  const records = [];
  for (const map of Object.keys(VERBATIM_MAPS)) {
    for (const record of dataset[map] || []) {
      if (!record?.id) throw new Error(`a dataset ${map} record needs an id`);
      records.push({ map, record });
    }
  }
  for (const entry of dataset.events || []) records.push(...eventRecords(entry));
  for (const record of dataset.overrides || []) {
    if (!record?.id) throw new Error("a dataset overrides record needs an id");
    records.push({ map: "overrides", record });
  }
  const seen = new Set();
  for (const { map, record } of records) {
    const key = `${map}/${record.id}`;
    if (seen.has(key)) throw new Error(`dataset declares ${key} twice`);
    seen.add(key);
  }
  return records;
}

function sameRecord(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

// Adds through the model helpers rather than assigning into the maps, so a
// dataset record picks up the same defaults an authored one does.
//
// A staple is the exception, and deliberately: `addRelation`'s defaults are an
// attachment's (`role: "member"`, an explicit provenance), and a staple has no
// top-level role at all -- it is an edge whose roles live on its two ends.
// Letting it inherit them writes a field that means nothing onto every
// connection the loader creates.
function put(document, map, record) {
  if (map === "events") return addEvent(document, record);
  if (map === "overrides" || (map === "relations" && record.type === "staple")) {
    document[map][record.id] = clone(record);
    return document[map][record.id];
  }
  return VERBATIM_MAPS[map](document, record);
}

export function applyDataset(document, dataset) {
  if (dataset?.schema !== DATASET_SCHEMA) {
    throw new Error(`dataset schema must be ${DATASET_SCHEMA}, not ${dataset?.schema || "(missing)"}`);
  }
  const missing = [MAGNITUDE_FRAME, ...(dataset.requires || [])]
    .filter((id) => !document.frames?.[id]);
  if (missing.length) throw new Error(`document is missing required frames: ${missing.join(", ")}`);

  const added = [];
  const present = [];
  const differs = [];
  for (const { map, record } of datasetRecords(dataset)) {
    const existing = document[map]?.[record.id];
    if (existing) {
      (sameRecord(existing, put({ [map]: {} }, map, record)) ? present : differs).push(`${map}/${record.id}`);
      continue;
    }
    put(document, map, record);
    added.push(`${map}/${record.id}`);
  }
  return { added, present, differs };
}

// The two targets behind one shape: read the document and its seq, then commit
// one labelled entry of ops onto that seq.
function fileTarget(dataRoot) {
  const store = createJournalStore({ dataRoot, warn: (message) => console.warn(`warning: ${message}`) });
  return {
    label: dataRoot,
    async read() {
      const loaded = await store.load();
      return loaded.present ? { document: store.document, seq: store.seq } : null;
    },
    commit: (baseSeq, entry) => store.append(baseSeq, [entry])
  };
}

function serverTarget(origin) {
  const ask = async (path, init) => {
    const response = await fetch(new URL(path, origin), init);
    if (response.status === 409) throw new Error(`the workspace moved on: ${JSON.stringify(await response.json())}`);
    if (!response.ok) throw new Error(`${path} answered ${response.status}: ${await response.text()}`);
    return response;
  };
  return {
    label: origin,
    async read() {
      const { currentSeq } = await (await ask("/api/journal?since=0")).json();
      const text = await (await ask("/api/document")).text();
      return { document: JSON.parse(text), seq: currentSeq };
    },
    commit: async (baseSeq, entry) => (await ask("/api/journal", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ baseSeq, entries: [entry] })
    })).json()
  };
}

async function main(argv) {
  const positional = [];
  let dataRoot = null;
  let origin = null;
  let dryRun = false;
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === "--data-dir") dataRoot = argv[index += 1];
    else if (argv[index] === "--server") origin = argv[index += 1];
    else if (argv[index] === "--dry-run") dryRun = true;
    else positional.push(argv[index]);
  }
  const [datasetPath] = positional;
  if (!datasetPath || (dataRoot && origin)) {
    console.error("usage: node tools/load-dataset.js <dataset.json> (--server <origin> | --data-dir <dir>) [--dry-run]");
    return 2;
  }

  const dataset = JSON.parse(await readFile(resolve(datasetPath), "utf8"));
  const target = origin ? serverTarget(origin) : fileTarget(resolve(dataRoot || process.cwd()));
  const loaded = await target.read();
  if (!loaded) {
    console.error(`no document at ${target.label}`);
    return 1;
  }
  const { document, seq } = loaded;
  const before = validateDocument(document);
  if (!before.valid) {
    console.error(`refusing to load: the document does not validate\n${before.errors.slice(0, 20).join("\n")}`);
    return 1;
  }
  const counts = (value) => Object.fromEntries(
    ["frames", "events", "patterns", "relations", "overrides"].map((map) => [map, Object.keys(value[map] || {}).length])
  );
  const priorCounts = counts(document);

  const snapshot = mapSnapshot(document);
  const result = applyDataset(document, dataset);
  const after = validateDocument(document);
  if (!after.valid) {
    console.error(`refusing to append: the dataset would invalidate the document\n${after.errors.slice(0, 20).join("\n")}`);
    return 1;
  }
  const ops = opsFromMaps(snapshot, mapSnapshot(document));

  console.log(`dataset ${dataset.dataset} -> ${target.label} (seq ${seq})`);
  console.log(`${result.added.length} added, ${result.present.length} already present, ${result.differs.length} differ`);
  for (const id of result.differs) console.log(`  differs: ${id}`);
  console.log(`before ${JSON.stringify(priorCounts)}`);
  console.log(`after  ${JSON.stringify(counts(document))}`);
  if (dryRun) {
    console.log(`dry run: ${ops.length} ops not appended`);
    return 0;
  }
  if (!ops.length) {
    console.log("nothing to append");
    return 0;
  }
  const appended = await target.commit(seq, { label: `Load dataset ${dataset.dataset}`, ops });
  console.log(`appended ${ops.length} ops at seq ${appended.seq}`);
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = await main(process.argv.slice(2));
}
