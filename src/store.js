import { clone, validateDocument } from "./model.js";

export function serializeDocument(document) {
  return JSON.stringify(document, null, 2) + "\n";
}

export function parseDocument(text) {
  const document = JSON.parse(text);
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
  constructor({ delay = 350, onStatus = () => {} } = {}) {
    this.delay = delay;
    this.onStatus = onStatus;
    this.handle = null;
    this.document = null;
    this.timer = null;
    this.revision = 0;
    this.savedRevision = 0;
  }

  attach(document) {
    this.document = document;
    this.revision = 0;
    this.savedRevision = 0;
    this.status("clean", "Saved");
  }

  status(state, message, error = null) {
    this.onStatus({ state, message, error, dirty: this.revision !== this.savedRevision });
  }

  markDirty() {
    this.revision += 1;
    this.status("dirty", this.handle ? "Waiting to save…" : "Unsaved");
    clearTimeout(this.timer);
    if (this.handle) this.timer = setTimeout(() => this.save(), this.delay);
  }

  async chooseFile() {
    if (!globalThis.showSaveFilePicker) return false;
    this.handle = await globalThis.showSaveFilePicker({
      suggestedName: "chronolog.json",
      types: [{
        description: "Chronolog document",
        accept: { "application/json": [".json", ".chronolog.json"] }
      }]
    });
    await this.save(true);
    return true;
  }

  async save(force = false) {
    if (!this.document) return false;
    if (!force && this.revision === this.savedRevision) return true;
    if (!this.handle) {
      this.status("dirty", "Choose Save As to enable autosave");
      return false;
    }
    const savingRevision = this.revision;
    this.status("saving", "Saving…");
    try {
      const writable = await this.handle.createWritable();
      await writable.write(serializeDocument(this.document));
      await writable.close();
      this.savedRevision = savingRevision;
      this.status(
        this.savedRevision === this.revision ? "clean" : "dirty",
        this.savedRevision === this.revision ? "Saved" : "New edits waiting…"
      );
      if (this.savedRevision !== this.revision) {
        clearTimeout(this.timer);
        this.timer = setTimeout(() => this.save(), this.delay);
      }
      return true;
    } catch (error) {
      this.status("error", `Save failed: ${error.message}`, error);
      return false;
    }
  }

  download(filename = "chronolog.json") {
    if (!this.document) return;
    downloadText(serializeDocument(this.document), filename);
    this.savedRevision = this.revision;
    this.status("downloaded", "Downloaded");
  }

  snapshot() {
    return clone(this.document);
  }
}
