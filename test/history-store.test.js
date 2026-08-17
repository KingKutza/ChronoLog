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
import { AutosaveStore, parseDocument, serializeDocument } from "../src/store.js";

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

test("attach drops the previous file handle so a new document never writes to it", async () => {
  const log = [];
  const statuses = [];
  const store = new AutosaveStore({ delay: 5, onStatus: (status) => statuses.push(status) });
  const docA = createDocument("Document A");
  store.attach(docA);
  store.handle = fakeHandle("file-a", log);
  assert.equal(await store.save(true), true);
  assert.equal(log.length, 1);

  const docB = createDocument("Document B");
  store.attach(docB);
  assert.equal(store.handle, null);
  assert.equal(store.revision, 0);
  assert.equal(store.savedRevision, 0);
  store.markDirty();
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
  const store = new AutosaveStore({ delay: 5, onStatus: () => {} });
  const docA = createDocument("Document A");
  store.attach(docA);
  const handleA = fakeHandle("file-a", log);
  const gate = deferred();
  handleA.gates.push(gate);
  store.handle = handleA;
  store.markDirty();
  const pending = store.save();
  const docB = createDocument("Document B");
  store.attach(docB);
  gate.resolve();
  await pending;
  assert.equal(log.length, 1);
  assert.equal(log[0].handle, "file-a");
  assert.equal(log[0].text, serializeDocument(docA));
  assert.equal(store.handle, null);
  assert.equal(store.savedRevision, 0);
});

test("overlapping saves are serialized with one follow-up and savedRevision never regresses", async () => {
  const log = [];
  const store = new AutosaveStore({ delay: 5, onStatus: () => {} });
  const doc = createDocument("Racing");
  store.attach(doc);
  const handle = fakeHandle("file", log);
  store.handle = handle;
  const gate = deferred();
  handle.gates.push(gate);
  store.markDirty();
  const first = store.save();
  doc.meta.title = "Racing v2";
  store.markDirty();
  const second = store.save();
  const third = store.save();
  assert.equal(second, third);
  assert.equal(handle.creations, 1);
  gate.resolve();
  assert.equal(await first, true);
  assert.equal(await second, true);
  assert.equal(log.length, 2);
  assert.equal(JSON.parse(log[0].text).meta.title, "Racing");
  assert.equal(JSON.parse(log[1].text).meta.title, "Racing v2");
  assert.equal(store.revision, 2);
  assert.equal(store.savedRevision, 2);
});

test("download does not clear the dirty state", () => {
  const statuses = [];
  const store = new AutosaveStore({ onStatus: (status) => statuses.push(status) });
  store.attach(createDocument("Downloadable"));
  store.markDirty();
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
  assert.equal(store.revision, 1);
  assert.equal(store.savedRevision, 0);
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

test("a server-attached document autosaves through the local document endpoint", async () => {
  const writes = [];
  const statuses = [];
  const store = new AutosaveStore({
    delay: 60_000,
    onStatus: (status) => statuses.push(status),
    fetcher: async (url, options) => {
      writes.push({ url, options });
      return { ok: true, status: 204, async text() { return ""; } };
    }
  });
  const document = measuredDocument("Remote autosave");
  store.attach(document, { remoteUrl: "/api/document", filename: "chronolog.chronolog" });
  store.markDirty();
  assert.equal(await store.save(), true);
  assert.equal(writes.length, 1);
  assert.equal(writes[0].url, "/api/document");
  assert.equal(writes[0].options.method, "PUT");
  assert.equal(JSON.parse(writes[0].options.body).meta.title, "Remote autosave");
  assert.equal(store.savedRevision, 1);
  assert.match(statuses.at(-1).message, /Autosaved.*chronolog\.chronolog/);
  clearTimeout(store.timer);
});

test("a remote revision is sent with each local workspace write", async () => {
  const writes = [];
  const store = new AutosaveStore({
    delay: 60_000,
    fetcher: async (url, options) => {
      writes.push({ url, options });
      return { ok: true, status: 204, headers: { get: () => '"next"' }, async text() { return ""; } };
    }
  });
  store.attach(measuredDocument("Versioned"), {
    remoteUrl: "/api/document", filename: "chronolog.chronolog", remoteRevision: '"base"',
    remoteHeaders: { authorization: "Bearer lan-token" }
  });
  store.markDirty();
  assert.equal(await store.save(), true);
  assert.equal(writes[0].options.headers["if-match"], '"base"');
  assert.equal(writes[0].options.headers.authorization, "Bearer lan-token");
  assert.equal(store.remoteRevision, '"next"');
  clearTimeout(store.timer);
});

test("a new workspace uses create-only save so another first writer cannot be overwritten", async () => {
  const store = new AutosaveStore({
    delay: 60_000,
    fetcher: async (url, options) => {
      assert.equal(options.headers["if-none-match"], "*");
      return { ok: true, status: 204, headers: { get: () => '"first"' }, async text() { return ""; } };
    }
  });
  store.attach(measuredDocument("First write"), { remoteUrl: "/api/document" });
  store.markDirty();
  assert.equal(await store.save(), true);
  clearTimeout(store.timer);
});

test("a stale local workspace write becomes an explicit keep-both conflict", async () => {
  const statuses = [];
  const store = new AutosaveStore({
    delay: 60_000,
    onStatus: (status) => statuses.push(status),
    fetcher: async () => ({
      ok: false, status: 409, headers: { get: (name) => name === "etag" ? '"remote"' : null },
      async text() { return "Workspace changed"; }
    })
  });
  const document = measuredDocument("Conflicting local edit");
  store.attach(document, { remoteUrl: "/api/document", remoteRevision: '"base"' });
  store.markDirty();
  assert.equal(await store.save(), false);
  assert.equal(store.savedRevision, 0);
  assert.equal(store.revision, 1);
  assert.equal(store.conflict.remoteRevision, '"remote"');
  assert.match(statuses.at(-1).message, /local edits are safe/);
  clearTimeout(store.timer);
});

test("readRemote returns the current body and opaque revision without replacing local edits", async () => {
  const store = new AutosaveStore({
    fetcher: async () => ({
      ok: true, headers: { get: () => '"remote"' }, async text() { return '{"schema":"chronolog/1"}'; }
    })
  });
  store.attach(measuredDocument("Local"), { remoteUrl: "/api/document", remoteRevision: '"base"' });
  store.markDirty();
  const remote = await store.readRemote();
  assert.equal(remote.remoteRevision, '"remote"');
  assert.equal(remote.text, '{"schema":"chronolog/1"}');
  assert.equal(store.revision, 1);
  clearTimeout(store.timer);
});

test("draft deferral prevents whole-document serialization until the editor resolves", async () => {
  const writes = [];
  const store = new AutosaveStore({
    delay: 60_000,
    fetcher: async (url, options) => {
      writes.push({ url, options });
      return { ok: true, status: 204, async text() { return ""; } };
    }
  });
  store.attach(measuredDocument("Deferred draft"), { remoteUrl: "/api/document" });
  store.beginDeferred();
  store.markDirty();
  assert.equal(await store.save(), false);
  assert.equal(writes.length, 0);
  store.endDeferred();
  assert.equal(await store.save(), true);
  assert.equal(writes.length, 1);
  clearTimeout(store.timer);
});

test("a cancelled draft releases autosave exactly once even when close paths repeat", async () => {
  const writes = [];
  const store = new AutosaveStore({
    delay: 60_000,
    fetcher: async (url, options) => {
      writes.push({ url, options });
      return { ok: true, status: 204, async text() { return ""; } };
    }
  });
  store.attach(measuredDocument("Cancelled draft"), { remoteUrl: "/api/document" });
  store.beginDeferred();
  store.markDirty();
  store.endDeferred(); // Cancel resolves the transaction.
  store.endDeferred(); // Escape/click-away after cancel is harmless.
  assert.equal(store.deferred, 0);
  assert.equal(await store.save(), true);
  assert.equal(writes.length, 1);
  clearTimeout(store.timer);
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
