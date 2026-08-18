import { clone, migrateDocument, validateDocument } from "./model.js";
import { OpLog, applyOps } from "./ops.js";

function parsedRRule(value = "") {
  return Object.fromEntries(String(value).split(";").filter(Boolean).map((part) => {
    const index = part.indexOf("=");
    return [part.slice(0, index).toUpperCase(), part.slice(index + 1)];
  }));
}

function recoverLegacyRecurrenceConstraints(document) {
  for (const pattern of Object.values(document?.patterns || {})) {
    if (pattern?.kind !== "ics-rrule" || !pattern.rawRule?.value) continue;
    const current = pattern.rrule || {};
    const original = parsedRRule(pattern.rawRule.value);
    if (!current.FREQ || current.FREQ !== original.FREQ) continue;
    // The early event form supported FREQ, INTERVAL, and COUNT but accidentally
    // discarded imported selectors when an unrelated field (such as Group) changed.
    // Recover only fields that form could not intentionally edit.
    for (const key of ["BYDAY", "BYMONTHDAY", "BYMONTH", "BYSETPOS", "UNTIL", "WKST"]) {
      if (current[key] === undefined && original[key] !== undefined) current[key] = original[key];
    }
    pattern.rrule = current;
  }
  return document;
}

function recoverDanglingOverrideReplacements(document) {
  for (const [id, override] of Object.entries(document?.overrides || {})) {
    if (!override || typeof override !== "object" || !Array.isArray(override.replacements)) continue;
    const replacements = override.replacements.filter((eventId) => Boolean(document.events?.[eventId]));
    if (replacements.length === override.replacements.length) continue;
    if (!replacements.length && override.suppress !== true) delete document.overrides[id];
    else override.replacements = replacements;
  }
  return document;
}

export function compactDocument(document) {
  migrateDocument(document);
  recoverLegacyRecurrenceConstraints(document);
  recoverDanglingOverrideReplacements(document);
  for (const source of Object.values(document?.foreign?.ics?.sources || {})) {
    const calendar = source?.component;
    if (!Array.isArray(calendar?.components)) continue;
    calendar.components = calendar.components.filter(
      (component) => !["VEVENT", "VTODO"].includes(component?.name)
    );
  }
  return document;
}

export function serializeDocument(document) {
  return JSON.stringify(compactDocument(document)) + "\n";
}

export function parseDocument(text) {
  const document = compactDocument(JSON.parse(text));
  const validation = validateDocument(document);
  if (!validation.valid) throw new Error(validation.errors.join("\n"));
  return document;
}

export function downloadText(text, filename, type = "application/json") {
  const blob = new Blob([text], { type });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

const MAX_REBASE_ATTEMPTS = 5;

// The journal client. Saving is no longer "write the document"; it is "append
// the ops this window committed". A 350ms debounce batches the ops from a
// burst of edits into one request, one entry per committed edit, so the
// journal keeps each edit's own label.
//
// Two save targets exist and they behave differently on purpose:
//
//   * The server-backed workspace journals ops. Nothing whole-document ever
//     moves during ordinary editing.
//   * A File System Access handle (the owner picked a file with "Save as")
//     still writes the whole document, because a plain file has no journal to
//     append to.
export class JournalStore {
  constructor({ delay = 350, onStatus = () => {}, onRebase = () => {}, fetcher = globalThis.fetch?.bind(globalThis) } = {}) {
    this.delay = delay;
    this.onStatus = onStatus;
    // Invoked after another window's ops land in this document, so the app can
    // rebuild its engine and repaint.
    this.onRebase = onRebase;
    this.handle = null;
    this.api = null;
    this.filename = null;
    this.fetcher = fetcher;
    this.document = null;
    this.timer = null;
    this.log = new OpLog();
    this.seq = 0;
    this.deferred = 0;
    this.inFlight = null;
    this.queued = null;
    this.queuedForce = false;
    this.lastError = null;
  }

  attach(document, { handle = null, api = null, filename = null, seq = 0 } = {}) {
    clearTimeout(this.timer);
    this.timer = null;
    this.handle = handle;
    this.api = api;
    this.filename = filename || handle?.name || null;
    this.document = document;
    this.log.clear();
    this.seq = seq;
    this.deferred = 0;
    this.lastError = null;
    const writable = this.writable();
    this.status(
      writable ? "clean" : "detached",
      writable ? `Autosave ready · ${this.filename || "Chronolog document"}` : "No autosave target"
    );
  }

  writable() {
    return Boolean(this.handle || this.api);
  }

  get pending() {
    return this.log.length > 0;
  }

  status(state, message, error = null) {
    this.lastError = error;
    this.onStatus({ state, message, error, dirty: this.pending, seq: this.seq });
  }

  url(path) {
    return `${this.api}/${path}`;
  }

  // Called for every committed change, with the ops that produced it. This is
  // the only way a document mutation reaches the journal.
  collect(label, ops) {
    if (!Array.isArray(ops)) {
      // Every mutation path is required to report its ops. A change arriving
      // without them means a new bypass was added, and silently falling back
      // to a whole-document write is exactly the behavior this design removed.
      throw new Error(`Document change "${label}" reported no ops; every mutation must flow through op capture`);
    }
    this.log.collect(label, ops);
    if (!this.log.length) return;
    const writable = this.writable();
    if (this.deferred) {
      this.status("dirty", writable ? "Editing · autosave after close" : "Unsaved · choose Save as");
      clearTimeout(this.timer);
      this.timer = null;
      return;
    }
    this.status("dirty", writable ? "Autosave pending…" : "Unsaved · choose Save as");
    clearTimeout(this.timer);
    if (writable) this.timer = setTimeout(() => this.save(), this.delay);
  }

  beginDeferred() {
    this.deferred += 1;
    clearTimeout(this.timer);
    this.timer = null;
  }

  endDeferred() {
    this.deferred = Math.max(0, this.deferred - 1);
    if (this.deferred || !this.pending) return;
    const writable = this.writable();
    this.status("dirty", writable ? "Autosave pending…" : "Unsaved · choose Save as");
    if (writable) this.timer = setTimeout(() => this.save(), this.delay);
  }

  async chooseFile() {
    if (!globalThis.showSaveFilePicker) return false;
    this.handle = await globalThis.showSaveFilePicker({
      suggestedName: "chronolog.chronolog",
      types: [{
        description: "Chronolog document",
        accept: { "application/x-chronolog": [".chronolog"] }
      }]
    });
    this.api = null;
    this.filename = this.handle.name;
    await this.save(true);
    return true;
  }

  save(force = false) {
    if (this.inFlight) {
      // Several callers can pile up behind one in-flight save; they share a
      // single follow-up. If any of them asked for a forced save ("Save now",
      // or a draft closing), the follow-up must carry that force — otherwise
      // the explicit request is quietly downgraded to an ordinary autosave.
      this.queuedForce = this.queuedForce || force;
      if (!this.queued) {
        this.queued = this.inFlight.then(() => {
          const followUpForce = this.queuedForce;
          this.queued = null;
          this.queuedForce = false;
          return this.save(followUpForce);
        });
      }
      return this.queued;
    }
    const run = this.write(force).finally(() => {
      if (this.inFlight === run) this.inFlight = null;
    });
    this.inFlight = run;
    return run;
  }

  async write(force) {
    if (!this.document) return false;
    if (this.deferred && !force) return false;
    if (!this.writable()) {
      this.status("dirty", "Choose Save as to enable autosave");
      return false;
    }
    if (!this.pending && !force) return true;
    clearTimeout(this.timer);
    this.timer = null;
    try {
      if (this.handle) await this.writeHandle();
      else if (!await this.writeJournal()) return false;
    } catch (error) {
      this.status("error", `Save failed: ${error.message}`, error);
      return false;
    }
    this.status(
      this.pending ? "dirty" : "clean",
      this.pending ? "New edits waiting…" : `Autosaved · ${this.filename || "Chronolog document"}`
    );
    if (this.pending && !this.deferred) {
      clearTimeout(this.timer);
      this.timer = setTimeout(() => this.save(), this.delay);
    }
    return true;
  }

  // A plain file has no journal, so the handle path still writes the whole
  // document. The pending ops are already applied to it; draining them just
  // clears the dirty flag.
  async writeHandle() {
    // Drain and serialize as one step. An edit committed while the write is in
    // flight is NOT in this text, so clearing its pending op would report it
    // saved when it never reached the file — it has to stay pending for the
    // follow-up write.
    const entries = this.log.drain();
    const text = serializeDocument(this.document);
    this.status("saving", "Saving…");
    try {
      const writable = await this.handle.createWritable();
      await writable.write(text);
      await writable.close();
    } catch (error) {
      this.log.restore(entries);
      throw error;
    }
  }

  async writeJournal() {
    if (!this.fetcher) throw new Error("This browser cannot reach the local autosave service");
    let entries = this.log.drain();
    if (!entries.length) return true;
    this.status("saving", "Saving…");
    for (let attempt = 0; attempt < MAX_REBASE_ATTEMPTS; attempt += 1) {
      const response = await this.fetcher(this.url("journal"), {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ baseSeq: this.seq, entries })
      });
      if (response.status === 409) {
        const conflict = await response.json();
        if (conflict.truncated) {
          // The journal no longer reaches back to what this window last saw,
          // so there is nothing to rebase onto. Hand the ops back and say so.
          this.log.restore(entries);
          throw new Error("The workspace was replaced in another window; reopen it to continue");
        }
        entries = this.rebase(conflict, entries);
        continue;
      }
      if (!response.ok) {
        this.log.restore(entries);
        throw new Error(await response.text() || `Autosave returned ${response.status}`);
      }
      const result = await response.json();
      this.seq = result.seq;
      return true;
    }
    this.log.restore(entries);
    throw new Error("Could not settle concurrent edits after several attempts");
  }

  // Record-level rebase. The other window's entries land first, then this
  // window's own ops go on top — so where both touched the same record, the
  // last writer wins, and where they touched different records, both survive.
  rebase(conflict, entries) {
    this.status("conflict-rebasing", "Merging edits from another window…");
    for (const entry of conflict.missed || []) applyOps(this.document, entry.ops);
    for (const entry of entries) applyOps(this.document, entry.ops);
    this.seq = conflict.currentSeq;
    this.onRebase(conflict.missed || []);
    return entries;
  }

  // Whole-document upload. Two uses: establishing the snapshot on a data
  // directory that has none, and the owner deliberately opening a different
  // file into the workspace. Never part of autosave.
  async uploadSnapshot() {
    if (!this.api) throw new Error("No local workspace is attached");
    if (!this.fetcher) throw new Error("This browser cannot reach the local autosave service");
    this.status("saving", "Saving…");
    const response = await this.fetcher(this.url("snapshot"), {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: serializeDocument(this.document)
    });
    if (!response.ok) throw new Error(await response.text() || `Snapshot upload returned ${response.status}`);
    const result = await response.json();
    this.seq = result.seq;
    this.log.drain();
    this.status("clean", `Autosaved · ${this.filename || "Chronolog document"}`);
    return result.seq;
  }

  download(filename = "chronolog.chronolog") {
    if (!this.document) return;
    downloadText(serializeDocument(this.document), filename);
    this.status("downloaded", this.pending ? "Downloaded a copy — unsaved changes remain" : "Downloaded");
  }

  snapshot() {
    return clone(this.document);
  }
}
