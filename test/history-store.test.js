import test from "node:test";
import assert from "node:assert/strict";
import { createSampleDocument } from "./helpers/sample-document.js";
import {
  CommandHistory,
  addEvent,
  addFrame,
  addPattern,
  createDocument,
  createId,
  stableVirtualId,
  validateDocument
} from "../src/model.js";
import { JournalStore, parseDocument, serializeDocument } from "../src/store.js";

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

function fakeHandle(name, log) {
  const handle = {
    name,
    gates: [],
    creations: 0,
    async createWritable() {
      handle.creations += 1;
      const gate = handle.gates.shift();
      if (gate) await gate.promise;
      let text = "";
      return {
        async write(chunk) {
          text = chunk;
        },
        async close() {
          log.push({ handle: name, text });
        }
      };
    }
  };
  return handle;
}

test("loading repairs recurrence selectors stripped by the legacy event form", () => {
  const document = createSampleDocument({ includeEvents: false });
  const frame = document.frames["calendar:personal"];
  const event = addEvent(document, { payload: { title: "Lunch" } });
  const pattern = addPattern(document, {
    title: "Lunch recurrence",
    kind: "ics-rrule",
    frame: frame.id,
    appliesTo: [frame.id],
    templateEvent: event.id,
    rrule: { FREQ: "WEEKLY", INTERVAL: "1", COUNT: "259" },
    rawRule: { name: "RRULE", params: [], value: "FREQ=WEEKLY;COUNT=259;BYDAY=MO,TU,WE,TH,FR" },
    source: "export fn state(ctx) = {}; export fn facts(ctx) = [];",
    exports: { state: "state", facts: "facts" }
  });
  const loaded = parseDocument(JSON.stringify(document));
  assert.equal(loaded.patterns[pattern.id].rrule.BYDAY, "MO,TU,WE,TH,FR");
});

test("loading preserves a suppressed occurrence while pruning a deleted replacement", () => {
  const document = createSampleDocument({ includeEvents: false });
  const frame = document.frames["calendar:personal"];
  const event = addEvent(document, { payload: { title: "Series" } });
  const pattern = addPattern(document, {
    title: "Series recurrence",
    kind: "ics-rrule",
    frame: frame.id,
    appliesTo: [frame.id],
    templateEvent: event.id,
    rrule: { FREQ: "DAILY" },
    source: "export fn state(ctx) = {}; export fn facts(ctx) = [];",
    exports: { state: "state", facts: "facts" }
  });
  document.overrides["override:deleted-replacement"] = {
    id: "override:deleted-replacement",
    virtual: stableVirtualId(pattern.id, "occurrence"),
    suppress: true,
    replacements: ["event:already-deleted"]
  };
  const loaded = parseDocument(JSON.stringify(document));
  assert.deepEqual(loaded.overrides["override:deleted-replacement"].replacements, []);
  assert.equal(loaded.overrides["override:deleted-replacement"].suppress, true);
});

function measuredDocument(title) {
  const document = createDocument(title);
  addFrame(document, { id: "measure:human-time", title: "Human time", traits: ["measure"] });
  return document;
}

function putEvent(id, title) {
  return [{ op: "put", map: "events", id, value: { id, payload: { title } } }];
}

// A File System Access handle has no journal to append to, so that path still
// writes the whole document. These cases cover it; the journal cases are
// further down.
test("attach drops the previous file handle so a new document never writes to it", async () => {
  const log = [];
  const statuses = [];
  const store = new JournalStore({ delay: 5, onStatus: (status) => statuses.push(status) });
  const docA = createDocument("Document A");
  store.attach(docA);
  store.handle = fakeHandle("file-a", log);
  assert.equal(await store.save(true), true);
  assert.equal(log.length, 1);

  const docB = createDocument("Document B");
  store.attach(docB);
  assert.equal(store.handle, null);
  assert.equal(store.pending, false, "attach drops the previous document's pending ops");
  assert.equal(store.seq, 0);
  store.collect("Edit", putEvent("event:b", "B"));
  assert.equal(await store.save(), false);
  await new Promise((resolve) => setTimeout(resolve, 20));
  assert.equal(log.length, 1);
  assert.equal(log[0].handle, "file-a");
  assert.equal(log[0].text, serializeDocument(docA));
  const last = statuses.at(-1);
  assert.equal(last.state, "dirty");
  assert.equal(last.dirty, true);
});

test("a save in flight during attach writes the old document and leaves the new state untouched", async () => {
  const log = [];
  const store = new JournalStore({ delay: 5, onStatus: () => {} });
  const docA = createDocument("Document A");
  store.attach(docA);
  const handleA = fakeHandle("file-a", log);
  const gate = deferred();
  handleA.gates.push(gate);
  store.handle = handleA;
  store.collect("Edit", putEvent("event:a", "A"));
  const pending = store.save();
  const docB = createDocument("Document B");
  store.attach(docB);
  gate.resolve();
  await pending;
  assert.equal(log.length, 1);
  assert.equal(log[0].handle, "file-a");
  assert.equal(log[0].text, serializeDocument(docA));
  assert.equal(store.handle, null);
  assert.equal(store.pending, false);
});

test("overlapping saves are serialized into one follow-up write", async () => {
  const log = [];
  const store = new JournalStore({ delay: 5, onStatus: () => {} });
  const doc = createDocument("Racing");
  store.attach(doc);
  const handle = fakeHandle("file", log);
  store.handle = handle;
  const gate = deferred();
  handle.gates.push(gate);
  store.collect("Edit", putEvent("event:1", "one"));
  const first = store.save();
  doc.meta.title = "Racing v2";
  store.collect("Edit", putEvent("event:2", "two"));
  const second = store.save();
  const third = store.save();
  assert.equal(second, third, "a third request joins the single queued follow-up");
  assert.equal(handle.creations, 1);
  gate.resolve();
  assert.equal(await first, true);
  assert.equal(await second, true);
  assert.equal(log.length, 2);
  assert.equal(JSON.parse(log[0].text).meta.title, "Racing");
  assert.equal(JSON.parse(log[1].text).meta.title, "Racing v2");
  assert.equal(store.pending, false);
});

test("download does not clear the dirty state", () => {
  const statuses = [];
  const store = new JournalStore({ onStatus: (status) => statuses.push(status) });
  store.attach(createDocument("Downloadable"));
  store.collect("Edit", putEvent("event:1", "one"));
  const originalDocument = globalThis.document;
  const originalCreate = URL.createObjectURL;
  const originalRevoke = URL.revokeObjectURL;
  globalThis.document = { createElement: () => ({ href: "", download: "", click() {} }) };
  URL.createObjectURL = () => "blob:fake";
  URL.revokeObjectURL = () => {};
  try {
    store.download("copy.json");
  } finally {
    globalThis.document = originalDocument;
    URL.createObjectURL = originalCreate;
    URL.revokeObjectURL = originalRevoke;
  }
  assert.equal(store.pending, true, "a downloaded copy is not a save");
  const last = statuses.at(-1);
  assert.equal(last.state, "downloaded");
  assert.equal(last.dirty, true);
});


test("a throwing command restores the document and records no undo entry", () => {
  const doc = createDocument("History");
  const before = JSON.parse(JSON.stringify(doc));
  const changes = [];
  const history = new CommandHistory(doc, (change) => changes.push(change));
  assert.throws(
    () => history.execute("explode", (target) => {
      target.events.partial = { id: "partial" };
      target.meta.title = "Mutated";
      throw new Error("boom");
    }),
    /boom/
  );
  assert.deepEqual(doc, before);
  assert.equal(history.undoStack.length, 0);
  assert.equal(changes.length, 0);
  assert.equal(history.undo(), false);
});

test("stableVirtualId keeps distinct keys distinct", () => {
  assert.notEqual(stableVirtualId("pattern:p", "review 1"), stableVirtualId("pattern:p", "review-1"));
  assert.notEqual(stableVirtualId("pattern:p", "a/b"), stableVirtualId("pattern:p", "a%2Fb"));
  assert.notEqual(stableVirtualId("pattern:p", "18999+3/8"), stableVirtualId("pattern:p", "18999-3-8"));
  assert.equal(stableVirtualId("pattern:p", "plain-key.1~x"), "pattern:p/plain-key.1~x");
});

test("validateDocument reports null map entries instead of crashing", () => {
  const doc = createDocument();
  doc.events.a = null;
  doc.frames.f = null;
  doc.patterns.p = null;
  doc.relations.r = null;
  doc.overrides.o = null;
  const validation = validateDocument(doc);
  assert.equal(validation.valid, false);
  for (const name of ["Event a", "Frame f", "Pattern p", "Relation r", "Override o"]) {
    assert.ok(validation.errors.some((entry) => entry.includes(name)), name);
  }
});

test("validateDocument checks override virtual and replacement references", () => {
  const doc = measuredDocument("Overrides");
  addPattern(doc, { id: "pattern:p", language: "chronolog-formula/1" });
  const event = addEvent(doc, {});
  doc.overrides["override:good"] = {
    id: "override:good",
    virtual: stableVirtualId("pattern:p", "occurrence-1"),
    suppress: true,
    replacements: [event.id]
  };
  const clean = validateDocument(doc);
  assert.equal(clean.valid, true, clean.errors.join("\n"));
  doc.overrides["override:bad"] = {
    id: "override:bad",
    virtual: "pattern:missing/occurrence-1",
    suppress: true,
    replacements: ["event:missing"]
  };
  const validation = validateDocument(doc);
  assert.equal(validation.valid, false);
  assert.ok(validation.errors.some((entry) => entry.includes("override:bad") && entry.includes("virtual")));
  assert.ok(validation.errors.some((entry) => entry.includes("override:bad") && entry.includes("replacement")));
});

test("validateDocument checks ics-rrule template references but stays permissive about extra fields", () => {
  const doc = measuredDocument("Recurrence");
  const event = addEvent(doc, {});
  doc.patterns["pattern:rule"] = {
    id: "pattern:rule",
    language: "chronolog-formula/1",
    kind: "ics-rrule",
    templateEvent: event.id,
    futureMetadata: { anything: true },
    anotherUnknownField: "keep"
  };
  const clean = validateDocument(doc);
  assert.equal(clean.valid, true, clean.errors.join("\n"));
  doc.patterns["pattern:rule"].templateEvent = "event:missing";
  doc.patterns["pattern:rule"].templateRelation = "relation:missing";
  const validation = validateDocument(doc);
  assert.equal(validation.valid, false);
  assert.ok(validation.errors.some((entry) => entry.includes("template event")));
  assert.ok(validation.errors.some((entry) => entry.includes("template relation")));
});

test("undo history is capped so old snapshots are dropped", () => {
  const doc = createDocument("Capped");
  const history = new CommandHistory(doc);
  assert.equal(history.limit, 200);
  for (let index = 0; index < 205; index += 1) {
    history.execute(`op ${index}`, (target) => {
      target.meta.counter = index;
    });
  }
  assert.equal(history.undoStack.length, 200);
  assert.equal(history.undoStack[0].label, "op 5");
  assert.equal(history.undoStack.at(-1).label, "op 204");
  assert.equal(history.undo(), true);
  assert.equal(doc.meta.counter, 203);
});

function jsonResponse(value, { ok = true, status = 200 } = {}) {
  return {
    ok,
    status,
    async json() { return value; },
    async text() { return JSON.stringify(value); }
  };
}

function recordingFetcher(responses) {
  const calls = [];
  const queue = [...responses];
  return {
    calls,
    fetcher: async (url, options) => {
      calls.push({ url, options, body: options?.body ? JSON.parse(options.body) : null });
      return queue.length > 1 ? queue.shift() : queue[0];
    }
  };
}

test("a server-attached document appends ops instead of writing the whole document", async () => {
  const statuses = [];
  const { calls, fetcher } = recordingFetcher([jsonResponse({ seq: 4 })]);
  const store = new JournalStore({ delay: 60_000, onStatus: (status) => statuses.push(status), fetcher });
  store.attach(measuredDocument("Journalled"), { api: "/api", filename: "chronolog.chronolog", seq: 3 });
  store.collect("Create event", putEvent("event:1", "one"));
  assert.equal(await store.save(), true);

  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "/api/journal");
  assert.equal(calls[0].options.method, "POST");
  assert.equal(calls[0].body.baseSeq, 3, "the append claims the sequence number this window last saw");
  assert.equal(calls[0].body.entries.length, 1);
  assert.equal(calls[0].body.entries[0].label, "Create event");
  assert.deepEqual(calls[0].body.entries[0].ops, putEvent("event:1", "one"));
  // The whole point: no document body crosses the wire during ordinary editing.
  assert.equal(calls[0].body.events, undefined);
  assert.equal(store.seq, 4, "the server's assigned sequence number is adopted");
  assert.equal(store.pending, false);
  assert.match(statuses.at(-1).message, /Autosaved.*chronolog\.chronolog/);
  clearTimeout(store.timer);
});

test("the debounce batches several commits into one request, one entry per commit", async () => {
  const { calls, fetcher } = recordingFetcher([jsonResponse({ seq: 3 })]);
  const store = new JournalStore({ delay: 60_000, fetcher });
  store.attach(measuredDocument("Batched"), { api: "/api" });
  store.collect("Create event", putEvent("event:1", "one"));
  store.collect("Edit event", putEvent("event:1", "renamed"));
  store.collect("Create event", putEvent("event:2", "two"));
  assert.equal(await store.save(), true);

  assert.equal(calls.length, 1, "one request for the whole burst");
  const entries = calls[0].body.entries;
  assert.equal(entries.length, 3, "each commit keeps its own entry and label");
  assert.deepEqual(entries.map((entry) => entry.label), ["Create event", "Edit event", "Create event"]);
  assert.equal(entries[1].ops[0].value.payload.title, "renamed");
  clearTimeout(store.timer);
});

test("a stale sequence number rebases at record level and reposts against the new one", async () => {
  const rebased = [];
  const { calls, fetcher } = recordingFetcher([
    jsonResponse({
      currentSeq: 7,
      truncated: false,
      missed: [{
        seq: 7,
        label: "Another window",
        ops: [
          { op: "put", map: "events", id: "event:shared", value: { id: "event:shared", owner: "remote" } },
          { op: "put", map: "events", id: "event:theirs", value: { id: "event:theirs", owner: "remote" } }
        ]
      }]
    }, { ok: false, status: 409 }),
    jsonResponse({ seq: 8 })
  ]);
  const store = new JournalStore({
    delay: 60_000,
    fetcher,
    onRebase: (missed) => rebased.push(missed)
  });
  const document = measuredDocument("Rebasing");
  store.attach(document, { api: "/api", seq: 5 });
  store.collect("Local edit", [
    { op: "put", map: "events", id: "event:shared", value: { id: "event:shared", owner: "local" } },
    { op: "put", map: "events", id: "event:mine", value: { id: "event:mine", owner: "local" } }
  ]);
  assert.equal(await store.save(), true);

  assert.equal(calls.length, 2, "the rebased entries are reposted");
  assert.equal(calls[0].body.baseSeq, 5);
  assert.equal(calls[1].body.baseSeq, 7, "the repost claims the sequence number the server reported");
  assert.deepEqual(calls[1].body.entries, calls[0].body.entries, "the same local edit is reposted, not dropped");

  // Records only the other window touched survive untouched.
  assert.equal(document.events["event:theirs"].owner, "remote");
  // Records only this window touched survive too.
  assert.equal(document.events["event:mine"].owner, "local");
  // Where both touched the same record, the last writer wins — this window
  // replayed its op on top of the other window's.
  assert.equal(document.events["event:shared"].owner, "local");

  assert.equal(store.seq, 8);
  assert.equal(store.pending, false);
  assert.equal(rebased.length, 1, "the app is told to rebuild around the merged records");
  assert.equal(rebased[0][0].label, "Another window");
  clearTimeout(store.timer);
});

test("a conflict whose history was compacted away reports that the workspace was replaced", async () => {
  const statuses = [];
  const { fetcher } = recordingFetcher([
    jsonResponse({ currentSeq: 12, truncated: true, missed: [] }, { ok: false, status: 409 })
  ]);
  const store = new JournalStore({ delay: 60_000, onStatus: (status) => statuses.push(status), fetcher });
  store.attach(measuredDocument("Replaced"), { api: "/api", seq: 2 });
  store.collect("Local edit", putEvent("event:1", "one"));
  assert.equal(await store.save(), false);
  assert.equal(statuses.at(-1).state, "error");
  assert.match(statuses.at(-1).message, /replaced in another window/);
  // Nothing was lost: the ops are still pending and will go out on the next try.
  assert.equal(store.pending, true);
  clearTimeout(store.timer);
});

test("a failed append hands the ops back so no edit is lost", async () => {
  const store = new JournalStore({
    delay: 60_000,
    onStatus: () => {},
    fetcher: async () => ({ ok: false, status: 500, async text() { return "disk on fire"; } })
  });
  store.attach(measuredDocument("Failing"), { api: "/api", seq: 1 });
  store.collect("Create event", putEvent("event:1", "one"));
  assert.equal(await store.save(), false);
  assert.equal(store.pending, true, "the pending ops survive a failed append");
  assert.equal(store.seq, 1, "and the sequence number does not advance");
  clearTimeout(store.timer);
});

test("draft deferral holds ops until the editor resolves", async () => {
  const { calls, fetcher } = recordingFetcher([jsonResponse({ seq: 1 })]);
  const store = new JournalStore({ delay: 60_000, fetcher });
  store.attach(measuredDocument("Deferred draft"), { api: "/api" });
  store.beginDeferred();
  store.collect("Draft edit", putEvent("event:1", "draft"));
  assert.equal(await store.save(), false);
  assert.equal(calls.length, 0, "a draft in progress appends nothing");
  assert.equal(store.pending, true);
  store.endDeferred();
  assert.equal(await store.save(), true);
  assert.equal(calls.length, 1, "the accumulated ops go out on commit");
  clearTimeout(store.timer);
});

test("a cancelled draft releases autosave exactly once even when close paths repeat", async () => {
  const { calls, fetcher } = recordingFetcher([jsonResponse({ seq: 1 })]);
  const store = new JournalStore({ delay: 60_000, fetcher });
  store.attach(measuredDocument("Cancelled draft"), { api: "/api" });
  store.beginDeferred();
  store.collect("Draft edit", putEvent("event:1", "draft"));
  store.endDeferred(); // Cancel resolves the transaction.
  store.endDeferred(); // Escape/click-away after cancel is harmless.
  assert.equal(store.deferred, 0);
  assert.equal(await store.save(), true);
  assert.equal(calls.length, 1);
  clearTimeout(store.timer);
});

test("uploadSnapshot replaces the whole document and clears pending ops", async () => {
  const { calls, fetcher } = recordingFetcher([jsonResponse({ seq: 9 })]);
  const store = new JournalStore({ delay: 60_000, fetcher });
  store.attach(measuredDocument("Opened elsewhere"), { api: "/api", seq: 4 });
  store.collect("Local edit", putEvent("event:1", "one"));
  assert.equal(await store.uploadSnapshot(), 9);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "/api/snapshot");
  assert.equal(calls[0].options.method, "PUT");
  assert.equal(calls[0].body.meta.title, "Opened elsewhere", "the whole document is uploaded");
  assert.equal(store.seq, 9);
  assert.equal(store.pending, false, "ops describing the replaced document are dropped");
  clearTimeout(store.timer);
});

// The assertion that keeps a newly added mutation path from quietly bypassing
// the journal: there is no whole-document fallback to silently rescue it.
test("a committed change that reports no ops is refused rather than silently dropped", () => {
  const store = new JournalStore({ delay: 60_000, onStatus: () => {}, fetcher: async () => jsonResponse({ seq: 1 }) });
  store.attach(measuredDocument("Strict"), { api: "/api" });
  assert.throws(() => store.collect("Mystery mutation", undefined), /must flow through op capture/);
  assert.equal(store.pending, false);
});

test("every committed change through the history reports the records it touched", () => {
  const document = measuredDocument("Op capture");
  const changes = [];
  const history = new CommandHistory(document, (change) => changes.push(change));
  const frameId = "calendar:capture";
  history.executeDelta(
    "Create frame",
    (value) => { value.frames[frameId] = { id: frameId, title: "Captured", traits: ["calendar"] }; },
    (value) => { delete value.frames[frameId]; },
    {
      ops: [{ op: "put", map: "frames", id: frameId, value: { id: frameId, title: "Captured", traits: ["calendar"] } }],
      inverseOps: [{ op: "del", map: "frames", id: frameId }]
    }
  );
  assert.equal(changes.length, 1);
  const forward = changes[0].ops;
  assert.equal(forward[0].map, "frames");
  assert.equal(forward[0].id, frameId);
  // `touch` stamps meta.modified on every commit, so replaying the entry has to
  // reproduce that record too or the server's document drifts from this one.
  const meta = forward.at(-1);
  assert.equal(meta.op, "put");
  assert.equal(meta.map, "meta");
  assert.equal(meta.id, "modified");
  assert.equal(meta.value, document.meta.modified);

  // Undo is a new committed edit carrying the inverse ops, not a file rewind.
  assert.equal(history.undo(), true);
  const undone = changes.at(-1).ops;
  assert.equal(undone[0].op, "del");
  assert.equal(undone[0].map, "frames");
  assert.equal(undone[0].id, frameId);
  assert.equal(undone.at(-1).map, "meta");

  assert.equal(history.redo(), true);
  assert.equal(changes.at(-1).ops[0].op, "put");
  assert.equal(changes.at(-1).ops[0].id, frameId);
});


test("delta commands remain undoable without whole-document snapshots", () => {
  const doc = createDocument("Delta history");
  doc.foreign.counter = 0;
  const history = new CommandHistory(doc);
  history.executeDelta(
    "Increment",
    (documentValue) => { documentValue.foreign.counter += 1; },
    (documentValue) => { documentValue.foreign.counter -= 1; }
  );
  assert.equal(doc.foreign.counter, 1);
  assert.equal(history.undoStack[0].before, undefined);
  history.undo();
  assert.equal(doc.foreign.counter, 0);
  history.redo();
  assert.equal(doc.foreign.counter, 1);
});

test("delta metadata survives apply, undo, and redo", () => {
  const changes = [];
  const doc = createDocument("Metadata");
  const history = new CommandHistory(doc, (change) => changes.push(change));
  history.executeDelta(
    "Light edit",
    (documentValue) => { documentValue.foreign.value = true; },
    (documentValue) => { delete documentValue.foreign.value; },
    { preserveRecurrence: true }
  );
  history.undo();
  history.redo();
  assert.deepEqual(changes.map((change) => change.preserveRecurrence), [true, true, true]);
});

test("snapshot history has a byte budget and reports an operation too large to retain", () => {
  const changes = [];
  const doc = createDocument("Budgeted history");
  doc.foreign.payload = "x".repeat(8_000);
  const history = new CommandHistory(doc, (change) => changes.push(change), 200, 4_000);
  history.execute("Large edit", (documentValue) => {
    documentValue.meta.title = "Changed";
  });
  assert.equal(doc.meta.title, "Changed");
  assert.equal(history.undoStack.length, 0);
  assert.equal(changes.at(-1).historyLimited, true);
});

test("snapshot history evicts old commands to stay within its byte budget", () => {
  const doc = createDocument("Bounded bytes");
  doc.foreign.payload = "x".repeat(400);
  const history = new CommandHistory(doc, () => {}, 200, 12_000);
  for (let index = 0; index < 30; index += 1) {
    history.execute(`edit ${index}`, (documentValue) => {
      documentValue.meta.counter = index;
    });
  }
  assert.ok(history.undoStack.length < 30);
  assert.ok(history.retainedBytes() <= 12_000);
});

test("createId fallback uses random bits instead of Date.now", () => {
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, "crypto");
  try {
    Object.defineProperty(globalThis, "crypto", { value: undefined, configurable: true });
    const first = createId("item");
    const second = createId("item");
    assert.match(first, /^item:[0-9a-f]{32}$/);
    assert.match(second, /^item:[0-9a-f]{32}$/);
    assert.notEqual(first, second);
    Object.defineProperty(globalThis, "crypto", {
      value: {
        getRandomValues(array) {
          array.fill(0xab);
          return array;
        }
      },
      configurable: true
    });
    assert.equal(createId("item"), `item:${"ab".repeat(16)}`);
  } finally {
    Object.defineProperty(globalThis, "crypto", descriptor);
  }
});
