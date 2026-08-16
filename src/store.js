import { clone, migrateDocument, validateDocument } from "./model.js";

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

export class AutosaveStore {
  constructor({ delay = 350, onStatus = () => {}, fetcher = globalThis.fetch?.bind(globalThis) } = {}) {
    this.delay = delay;
    this.onStatus = onStatus;
    this.handle = null;
    this.remoteUrl = null;
    this.filename = null;
    this.fetcher = fetcher;
    this.document = null;
    this.timer = null;
    this.revision = 0;
    this.savedRevision = 0;
    this.inFlight = null;
    this.queued = null;
    this.queuedForce = false;
    this.deferred = 0;
    this.remoteRevision = null;
    this.remoteHeaders = null;
    this.conflict = null;
  }

  attach(document, { handle = null, remoteUrl = null, filename = null, remoteRevision = null, remoteHeaders = null } = {}) {
    clearTimeout(this.timer);
    this.timer = null;
    this.handle = handle;
    this.remoteUrl = remoteUrl;
    this.filename = filename || handle?.name || null;
    this.document = document;
    this.revision = 0;
    this.savedRevision = 0;
    this.deferred = 0;
    this.remoteRevision = remoteRevision;
    this.remoteHeaders = remoteHeaders;
    this.conflict = null;
    this.status(
      this.handle || this.remoteUrl ? "clean" : "detached",
      this.handle || this.remoteUrl
        ? `Autosave ready · ${this.filename || "Chronolog document"}`
        : "No autosave target"
    );
  }

  status(state, message, error = null) {
    this.onStatus({ state, message, error, dirty: this.revision !== this.savedRevision, conflict: this.conflict });
  }

  markDirty() {
    this.revision += 1;
    const writable = this.handle || this.remoteUrl;
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
    if (this.deferred || this.revision === this.savedRevision) return;
    const writable = this.handle || this.remoteUrl;
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
    this.remoteUrl = null;
    this.filename = this.handle.name;
    await this.save(true);
    return true;
  }

  save(force = false) {
    if (this.inFlight) {
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
    if (!force && this.revision === this.savedRevision) return true;
    const handle = this.handle;
    const remoteUrl = this.remoteUrl;
    const attachedDocument = this.document;
    if (!handle && !remoteUrl) {
      this.status("dirty", "Choose Save as to enable autosave");
      return false;
    }
    const savingRevision = this.revision;
    const text = serializeDocument(this.document);
    this.status("saving", "Saving…");
    try {
      if (handle) {
        const writable = await handle.createWritable();
        await writable.write(text);
        await writable.close();
      } else {
        if (!this.fetcher) throw new Error("This browser cannot reach the local autosave service");
        const response = await this.fetcher(remoteUrl, {
          method: "PUT",
          headers: {
            "content-type": "application/x-chronolog",
            ...(this.remoteHeaders || {}),
            ...(this.remoteRevision ? { "if-match": this.remoteRevision } : { "if-none-match": "*" })
          },
          body: text
        });
        if (response.status === 409) {
          const currentRevision = response.headers?.get?.("etag") || null;
          this.conflict = { localRevision: this.remoteRevision, remoteRevision: currentRevision, text };
          this.status("conflict", "Conflict — local edits are safe; download a copy or reload latest");
          return false;
        }
        if (!response.ok) throw new Error(await response.text() || `Autosave returned ${response.status}`);
        this.remoteRevision = response.headers?.get?.("etag") || this.remoteRevision;
      }
      if (attachedDocument !== this.document || handle !== this.handle || remoteUrl !== this.remoteUrl) return true;
      if (savingRevision > this.savedRevision) this.savedRevision = savingRevision;
      this.status(
        this.savedRevision === this.revision ? "clean" : "dirty",
        this.savedRevision === this.revision
          ? `Autosaved · ${this.filename || "Chronolog document"}`
          : "New edits waiting…"
      );
      if (this.savedRevision !== this.revision && !this.deferred) {
        clearTimeout(this.timer);
        this.timer = setTimeout(() => this.save(), this.delay);
      }
      return true;
    } catch (error) {
      if (handle !== this.handle) return false;
      this.status("error", `Save failed: ${error.message}`, error);
      return false;
    }
  }

  async readRemote() {
    if (!this.remoteUrl || !this.fetcher) throw new Error("No local workspace is attached");
    const response = await this.fetcher(this.remoteUrl, {
      method: "GET", cache: "no-store", headers: this.remoteHeaders || {}
    });
    if (!response.ok) throw new Error(await response.text() || `Open returned ${response.status}`);
    return { text: await response.text(), remoteRevision: response.headers?.get?.("etag") || null };
  }

  clearConflict() {
    this.conflict = null;
  }

  download(filename = "chronolog.chronolog") {
    if (!this.document) return;
    downloadText(serializeDocument(this.document), filename);
    this.status(
      "downloaded",
      this.revision === this.savedRevision ? "Downloaded" : "Downloaded a copy — unsaved changes remain"
    );
  }

  snapshot() {
    return clone(this.document);
  }
}
