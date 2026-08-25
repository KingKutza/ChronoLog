import { eventComponentKey, residualEventComponent } from "./ics.js";
import { clone, migrateDocument, overridePatternId, validateDocument } from "./model.js";
import { DONE_STATE_FRAME_ID, ensureStateFrame } from "./object-kinds.js";
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

// An override whose series no longer exists cannot ever match a fact again, so
// it is unreachable data rather than a decision worth keeping. Deleting a pattern
// used not to cascade to its overrides, so a document could be journaled into a
// state that `validateDocument` refuses — and because validation runs only at
// load, the failure surfaced as a whole document declining to open long after the
// edit that caused it.
//
// This is a repair, not a relaxation: `validateDocument` stays strict, and the
// sweep happens in the parse path ahead of it, exactly like the two recoveries
// above. The repaired state persists on the next journal append or compaction.
function recoverOrphanedVirtualOverrides(document, report) {
  const overrides = document?.overrides;
  if (!overrides) return document;
  let dropped = 0;
  for (const [id, override] of Object.entries(overrides)) {
    if (!override || typeof override !== "object") continue;
    const patternId = overridePatternId(override);
    if (patternId && document.patterns?.[patternId]) continue;
    delete overrides[id];
    dropped += 1;
  }
  if (dropped) {
    addRepair(report, {
      kind: "orphaned-virtual-overrides",
      count: dropped,
      message: `Swept ${dropped} leftover exception${dropped === 1 ? "" : "s"} from repeating series that no longer exist.`
    });
  }
  return document;
}

// Repairs are reported through a caller-supplied collector rather than a field on
// the document, so nothing a repair notices can ever end up in serialized output.
function addRepair(report, entry) {
  if (Array.isArray(report)) report.push(entry);
  else if (report && typeof report === "object") (report.repairs ||= []).push(entry);
}

// The early ICS import shape gave every event its own full copy of the ICS
// node it came from, at `foreign.ics.component` -- which is what let one
// owner's real work calendar make the document balloon to roughly double the
// size of the .ics being imported. The current importer instead
// keeps one shared, de-duplicated copy per source
// (`document.foreign.ics.sources[id].components`, keyed by
// `eventComponentKey`) and gives each event only a `{source, key}`
// reference. This sweep converts a legacy inline copy into the shared form
// wherever a home for it still exists, exactly the same way the other
// recoveries above convert an old shape into the current one. It is a repair,
// not a relaxation: `validateDocument` never had an opinion about
// `foreign.ics.component` either way, so there is nothing to keep strict here
// -- only bytes to stop duplicating.
function slimOneICSReference(document, container) {
  const ics = container?.foreign?.ics;
  if (!ics || !ics.component || !ics.source) return false;
  const source = document?.foreign?.ics?.sources?.[ics.source];
  if (!source) return false; // No shared home to dedupe into; leave the copy rather than lose it.
  source.components ||= {};
  const key = ics.key || eventComponentKey(ics.component);
  source.components[key] ||= residualEventComponent(ics.component);
  container.foreign.ics = { source: ics.source, key };
  return true;
}

function slimRetainedICSPayload(document, report) {
  let slimmed = 0;
  for (const event of Object.values(document?.events || {})) {
    if (!event || typeof event !== "object") continue;
    if (slimOneICSReference(document, event)) slimmed += 1;
    for (const staple of event.foreign?.stapled || []) {
      if (slimOneICSReference(document, staple)) slimmed += 1;
    }
  }
  if (slimmed) {
    addRepair(report, {
      kind: "slimmed-ics-payload",
      count: slimmed,
      message: `Deduplicated ${slimmed} retained ICS event cop${slimmed === 1 ? "y" : "ies"} into shared per-source storage.`
    });
  }
  return document;
}

// A staple is an edge with two ends (src/staples.js). The flat shape that
// preceded it -- one target plus a bare `frame`/`coordinate`/`role` -- said the
// same thing with the connection left implicit, so the conversion is a
// RESTATEMENT and not a reinterpretation: the target becomes the end whose point
// the `role` named, and the frame plus its coordinate become the end that
// supplied the coordinate space. Every authored value survives at exactly the
// instant it named, including a named point's offset, which moves onto the end
// it describes because both ends of a connection can now be named points and
// each needs its own.
//
// A record already carrying `ends` is left untouched, so compaction is
// idempotent and a document saved by this build round-trips unchanged.
function migrateStapleConnections(document, report = null) {
  let converted = 0;
  for (const relation of Object.values(document?.relations || {})) {
    if (relation?.type !== "staple" || Array.isArray(relation.ends)) continue;
    const target = relation.series
      ? { series: relation.series }
      : relation.object
        ? {
          object: relation.object,
          point: String(relation.role || "").trim() || "start",
          ...(relation.payload?.offset ? { offset: relation.payload.offset } : {})
        }
        : null;
    if (!target) continue;
    const far = {
      frame: relation.frame,
      coordinate: relation.coordinate,
      ...(relation.parameters ? { parameters: relation.parameters } : {})
    };
    relation.ends = [target, far];
    delete relation.series;
    delete relation.object;
    delete relation.role;
    delete relation.frame;
    delete relation.coordinate;
    delete relation.parameters;
    if (relation.payload) {
      const payload = { ...relation.payload };
      delete payload.offset;
      if (Object.keys(payload).length) relation.payload = payload;
      else delete relation.payload;
    }
    converted += 1;
  }
  if (converted) {
    addRepair(report, {
      kind: "staple-connections",
      count: converted,
      message: `Restated ${converted} staple${converted === 1 ? "" : "s"} as a connection between two things.`
    });
  }
  return document;
}

// Completion used to be its own attachment relation (`role: "completed"`,
// coordinate = the instant). The ruled shape stores the same two facts where
// they belong: done is membership in the Done state frame (state is a frame,
// not a property) and the instant is an `end`-kind staple -- the object's own
// `end` point abutting a frame coordinate. A RESTATEMENT, like the staple
// conversion above: the coordinate survives at exactly the instant it named
// (a relation without one becomes membership only -- done, instant unstated),
// and the legacy record is REPLACED, never kept alongside.
//
// Idempotent by trigger: the legacy shape itself is what fires this, and the
// rewrite removes it. The membership reuses the relation's own id and the
// staple's id derives from it, so repeated loads of one legacy file converge
// on identical records rather than minting fresh ids per window.
function migrateCompletedRelations(document, report = null) {
  let converted = 0;
  for (const relation of Object.values(document?.relations || {})) {
    if (relation?.type !== "attachment" || relation.role !== "completed") continue;
    ensureStateFrame(document, DONE_STATE_FRAME_ID);
    const { event, frame, coordinate, parameters } = relation;
    if (coordinate) {
      const stapleId = `${relation.id}:completed-at`;
      document.relations[stapleId] = {
        id: stapleId,
        type: "staple",
        kind: "end",
        ends: [
          { object: event, point: "end" },
          { frame, coordinate, ...(parameters ? { parameters } : {}) }
        ],
        ...(relation.provenance ? { provenance: clone(relation.provenance) } : {})
      };
    }
    for (const key of Object.keys(relation)) {
      if (key !== "id" && key !== "provenance") delete relation[key];
    }
    relation.type = "membership";
    relation.group = DONE_STATE_FRAME_ID;
    relation.member = event;
    converted += 1;
  }
  if (converted) {
    addRepair(report, {
      kind: "completed-state",
      count: converted,
      message: `Restated ${converted} completion${converted === 1 ? "" : "s"} as Done-state membership with an end staple.`
    });
  }
  return document;
}

export function compactDocument(document, report = null) {
  migrateDocument(document);
  migrateStapleConnections(document, report);
  migrateCompletedRelations(document, report);
  recoverLegacyRecurrenceConstraints(document);
  recoverDanglingOverrideReplacements(document);
  recoverOrphanedVirtualOverrides(document, report);
  slimRetainedICSPayload(document, report);
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

// `report` is optional and write-only: pass an array or an object to collect the
// repairs compaction had to make, so a caller can warn about them without the
// load itself failing.
export function parseDocument(text, report = null) {
  const document = compactDocument(JSON.parse(text), report);
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
