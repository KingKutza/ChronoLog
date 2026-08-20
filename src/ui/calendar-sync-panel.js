import { coordinateLaw } from "../coordinate-law.js";
import { applyICSSnapshot, calendarSyncConnections } from "../calendar-sync.js";
import { exportICS, importICS } from "../ics.js";
import { clone, stapleEvents } from "../model.js";
import { delOp, mapSnapshot, opsFromMaps, putOp } from "../ops.js";
import { downloadText } from "../store.js";
import { byId, escapeHTML } from "./dom-helpers.js";

const IMPORT_MAPS = ["frames", "events", "patterns", "relations", "overrides"];

// The ICS feed UI: file import/export, staple suggestions surfaced after an
// import, and the read-only HTTPS calendar-feed subscription panel. `app`
// carries the live document/engine/session/history plus the cross-module
// call into the Frames panel (`app.selectLeadingFrame`) that a successful
// import triggers.
export function createCalendarSyncPanel(app) {
  function openStapleSuggestions(suggestions) {
    const { chronolog } = app;
    const grouped = new Map();
    for (const suggestion of suggestions) {
      const existing = grouped.get(suggestion.uid) || new Set();
      suggestion.events.forEach((id) => existing.add(id));
      grouped.set(suggestion.uid, existing);
    }
    const wrapper = document.createElement("div");
    const note = document.createElement("p");
    note.style.cssText = "font:12px/1.5 var(--data);color:var(--muted)";
    note.textContent = "Matching ICS UIDs remain distinct. Stapling is explicit and makes one Event carry every attachment.";
    wrapper.append(note);
    for (const [uid, ids] of grouped) {
      const card = document.createElement("section");
      card.style.cssText = "padding:10px 0;border-top:1px solid var(--hair)";
      const title = document.createElement("strong");
      title.style.cssText = "display:block;font:700 11px/1.4 var(--data)";
      title.textContent = uid;
      const detail = document.createElement("div");
      detail.style.cssText = "margin:4px 0 8px;color:var(--muted);font:11px/1.4 var(--data)";
      detail.textContent = [...ids]
        .map((id) => chronolog.events[id]?.payload?.title || id)
        .join(" · ");
      const button = document.createElement("button");
      button.type = "button";
      button.className = "instrument-button";
      button.textContent = "Staple these identities";
      button.addEventListener("click", () => {
        const eventIds = [...ids].filter((id) => chronolog.events[id]);
        if (eventIds.length < 2) {
          card.remove();
          return;
        }
        app.executeEventSetChange("Staple matching ICS identities", eventIds, (documentValue) => {
          stapleEvents(documentValue, eventIds);
        });
        card.remove();
        app.toast("Stapled matching identities.");
      });
      card.append(title, detail, button);
      wrapper.append(card);
    }
    app.openInspector("Staple suggestions", wrapper);
  }

  function importCalendar(text, label) {
    const { chronolog, history } = app;
    const beforeIds = Object.fromEntries(
      IMPORT_MAPS.map((name) => [name, new Set(Object.keys(chronolog[name]))])
    );
    const hadIcs = Object.prototype.hasOwnProperty.call(chronolog.foreign, "ics");
    const beforeSourceIds = new Set(Object.keys(chronolog.foreign.ics?.sources || {}));
    // The import mutates `foreign.ics.sources` in place when the key already
    // existed, so the live object can't be trusted to still hold its own
    // "before" value once the import has run — this one clone up front is
    // what gives the inverse op something real to carry. It costs one pass
    // over every already-retained source's shared ICS data (see ics.js's
    // `eventComponentKey`/`residualEventComponent`), not per event, so it
    // scales with how much calendar content this document already holds,
    // not with the size of the import underway.
    const beforeIcsValue = hadIcs ? clone(chronolog.foreign.ics) : undefined;
    const before = mapSnapshot(chronolog);
    let additions = null;
    let addedSources = null;
    let result = null;
    const metadata = {};

    const removeNewEntries = (documentValue) => {
      for (const name of IMPORT_MAPS) {
        const ids = additions ? Object.keys(additions[name]) : Object.keys(documentValue[name])
          .filter((id) => !beforeIds[name].has(id));
        for (const id of ids) delete documentValue[name][id];
      }
      const sourceIds = addedSources ? Object.keys(addedSources) : Object.keys(
        documentValue.foreign.ics?.sources || {}
      ).filter((id) => !beforeSourceIds.has(id));
      for (const id of sourceIds) delete documentValue.foreign.ics?.sources?.[id];
      if (!hadIcs && !Object.keys(documentValue.foreign.ics?.sources || {}).length) {
        delete documentValue.foreign.ics;
      }
    };

    // `mapSnapshot`/`opsFromMaps` diff `foreign` by identity, but the import
    // assigns into `foreign.ics.sources` rather than replacing `foreign.ics`
    // whenever that key already existed, so a source being added or removed
    // is otherwise invisible to the identity diff. Detect that case (identity
    // unchanged, source set changed) and push the op by hand; when the key's
    // identity DID change (first-ever ics import, or the retry/removal path
    // deleting it outright) opsFromMaps already captured it, so skip to avoid
    // a duplicate.
    const captureIcsOps = (documentValue, ops, inverseOps) => {
      if (before.foreign.ics !== documentValue.foreign.ics) return;
      const afterHasIcs = Object.prototype.hasOwnProperty.call(documentValue.foreign, "ics");
      const afterSourceIds = new Set(Object.keys(documentValue.foreign.ics?.sources || {}));
      const sourcesChanged = afterSourceIds.size !== beforeSourceIds.size
        || [...afterSourceIds].some((id) => !beforeSourceIds.has(id))
        || [...beforeSourceIds].some((id) => !afterSourceIds.has(id));
      if (!sourcesChanged) return;
      ops.push(afterHasIcs ? putOp("foreign", "ics", documentValue.foreign.ics) : delOp("foreign", "ics"));
      inverseOps.push(hadIcs ? putOp("foreign", "ics", beforeIcsValue) : delOp("foreign", "ics"));
    };

    const captureOps = (documentValue) => {
      const after = mapSnapshot(documentValue);
      const ops = opsFromMaps(before, after);
      const inverseOps = opsFromMaps(after, before);
      captureIcsOps(documentValue, ops, inverseOps);
      Object.assign(metadata, { ops, inverseOps });
    };

    const apply = (documentValue) => {
      if (additions) {
        for (const name of IMPORT_MAPS) Object.assign(documentValue[name], additions[name]);
        documentValue.foreign.ics ||= { sources: {} };
        documentValue.foreign.ics.sources ||= {};
        Object.assign(documentValue.foreign.ics.sources, addedSources);
      } else {
        try {
          result = importICS(text, documentValue, { label });
          additions = Object.fromEntries(IMPORT_MAPS.map((name) => [
            name,
            Object.fromEntries(Object.entries(documentValue[name]).filter(([id]) => !beforeIds[name].has(id)))
          ]));
          addedSources = Object.fromEntries(Object.entries(documentValue.foreign.ics?.sources || {})
            .filter(([id]) => !beforeSourceIds.has(id)));
        } catch (error) {
          removeNewEntries(documentValue);
          throw error;
        }
      }
      captureOps(documentValue);
    };

    history.executeDelta(
      `Import ${label}`,
      apply,
      (documentValue) => removeNewEntries(documentValue),
      metadata
    );
    return result;
  }

  async function calendarSyncRequest(path, options = {}) {
    const response = await fetch(path, {
      ...options,
      headers: {
        ...(options.body ? { "content-type": "application/json" } : {}),
        ...(options.headers || {})
      }
    });
    const text = await response.text();
    let value = null;
    try { value = text ? JSON.parse(text) : null; } catch {}
    if (!response.ok) throw new Error(value?.error || text || `Calendar sync returned ${response.status}`);
    return value;
  }

  // Applies a captured op list to a live document: puts assign the whole
  // record, deletes remove it. Used for both the undo (inverse ops) and redo
  // (forward ops) paths below, so a sync pull never needs a second full
  // document clone just to be reversible.
  function applyOps(documentValue, ops) {
    if (!ops) return;
    for (const op of ops) {
      const map = documentValue[op.map];
      if (!map) continue;
      if (op.op === "put") map[op.id] = op.value;
      else delete map[op.id];
    }
  }

  function executeCalendarSync(label, options) {
    const { chronolog, history } = app;
    const before = mapSnapshot(chronolog);
    const hadIcs = Object.prototype.hasOwnProperty.call(chronolog.foreign || {}, "ics");
    // See the identical note in `importCalendar`: `applyICSSnapshot` mutates
    // `foreign.ics.sources` in place when a connection is already known
    // (i.e. on every sync pull after the first), so `foreign.ics` keeps its
    // identity and the record diff below would otherwise miss the change.
    const beforeIcsValue = hadIcs ? clone(chronolog.foreign.ics) : undefined;
    const beforeSourceIds = new Set(Object.keys(chronolog.foreign?.ics?.sources || {}));
    let ops = null;
    let inverseOps = null;
    let result = null;
    const metadata = {};
    history.executeDelta(label, (documentValue) => {
      if (ops) {
        applyOps(documentValue, ops);
        return;
      }
      result = applyICSSnapshot(documentValue, options);
      const after = mapSnapshot(documentValue);
      ops = opsFromMaps(before, after);
      inverseOps = opsFromMaps(after, before);
      if (before.foreign.ics === documentValue.foreign.ics) {
        const afterHasIcs = Object.prototype.hasOwnProperty.call(documentValue.foreign, "ics");
        const afterSourceIds = new Set(Object.keys(documentValue.foreign.ics?.sources || {}));
        const sourcesChanged = afterSourceIds.size !== beforeSourceIds.size
          || [...afterSourceIds].some((id) => !beforeSourceIds.has(id))
          || [...beforeSourceIds].some((id) => !afterSourceIds.has(id));
        if (sourcesChanged) {
          ops.push(afterHasIcs ? putOp("foreign", "ics", documentValue.foreign.ics) : delOp("foreign", "ics"));
          inverseOps.push(hadIcs ? putOp("foreign", "ics", beforeIcsValue) : delOp("foreign", "ics"));
        }
      }
      Object.assign(metadata, { ops, inverseOps });
    }, (documentValue) => applyOps(documentValue, inverseOps), metadata);
    return result;
  }

  async function pullCalendarConnection(connection, status) {
    const current = calendarSyncConnections(app.chronolog).find((item) => item.id === connection.id);
    status.textContent = `Syncing ${connection.label}…`;
    const pulled = await calendarSyncRequest(`/api/sync/feeds/${encodeURIComponent(connection.id)}/pull`, {
      method: "POST",
      body: JSON.stringify({ revision: current?.revision || null })
    });
    if (pulled.notModified) {
      status.textContent = `${connection.label} is already current.`;
      return null;
    }
    const result = executeCalendarSync(`Sync ${connection.label}`, {
      connectionId: connection.id,
      text: pulled.text,
      label: connection.label,
      provider: connection.provider,
      revision: pulled.revision
    });
    status.textContent = `Synced ${result.events} item${result.events === 1 ? "" : "s"} from ${connection.label}.`;
    app.toast(status.textContent);
    return result;
  }

  async function openCalendarSyncInspector() {
    const wrapper = document.createElement("section");
    wrapper.className = "calendar-sync-panel";
    wrapper.innerHTML = `
    <p class="field-note">Subscribe to an HTTPS or webcal ICS address published by Outlook, Google Calendar, Apple Calendar, or another calendar service — a "webcal://" or "webcals://" link works too and is treated the same as HTTPS. Refresh is explicit and read-only: ChronoLog never writes back or stores the secret feed URL in your document.</p>
    <form class="calendar-feed-form">
      <label class="field"><span>Name</span><input name="label" placeholder="Work calendar" required></label>
      <label class="field"><span>Secret ICS address</span><input name="url" type="url" inputmode="url" autocomplete="off" placeholder="https://…/calendar.ics or webcal://…/calendar.ics" required><small>Stored only by this local launcher with owner-only file permissions.</small></label>
      <button class="instrument-button primary" type="submit">Add and sync</button>
    </form>
    <p class="calendar-sync-status" role="status" aria-live="polite">Loading connections…</p>
    <div class="calendar-sync-list"></div>`;
    app.openInspector("Web calendar sync", wrapper);
    const form = wrapper.querySelector(".calendar-feed-form");
    const list = wrapper.querySelector(".calendar-sync-list");
    const status = wrapper.querySelector(".calendar-sync-status");

    async function paint() {
      try {
        const remote = await calendarSyncRequest("/api/sync/connections");
        const local = new Map(calendarSyncConnections(app.chronolog).map((item) => [item.id, item]));
        list.replaceChildren();
        for (const connection of remote.feeds || []) {
          const synced = local.get(connection.id);
          const row = document.createElement("article");
          row.className = "calendar-sync-row";
          const details = document.createElement("div");
          details.innerHTML = `<strong>${escapeHTML(connection.label)}</strong><small>${escapeHTML(connection.urlHint)}</small><small>${synced?.fetchedAt ? `Last synced ${escapeHTML(new Date(synced.fetchedAt).toLocaleString())}` : "Not synced yet"}</small>`;
          const actions = document.createElement("div");
          actions.className = "calendar-sync-actions";
          const sync = document.createElement("button");
          sync.type = "button";
          sync.className = "instrument-button primary";
          sync.textContent = "Sync now";
          sync.addEventListener("click", async () => {
            sync.disabled = true;
            try { await pullCalendarConnection(connection, status); await paint(); }
            catch (error) { status.textContent = `Sync failed · local changes safe: ${error.message}`; app.toast(error.message, true); }
            finally { sync.disabled = false; }
          });
          const remove = document.createElement("button");
          remove.type = "button";
          remove.className = "instrument-button";
          remove.textContent = "Forget";
          remove.title = "Forget the remote address; keep the last imported snapshot";
          remove.addEventListener("click", async () => {
            try {
              await calendarSyncRequest(`/api/sync/feeds/${encodeURIComponent(connection.id)}`, { method: "DELETE" });
              status.textContent = `Forgot ${connection.label}. Its last imported snapshot remains in this document.`;
              await paint();
            } catch (error) { status.textContent = error.message; app.toast(error.message, true); }
          });
          actions.append(sync, remove);
          row.append(details, actions);
          list.append(row);
        }
        if (!remote.feeds?.length) {
          const empty = document.createElement("p");
          empty.className = "field-note calendar-sync-empty";
          empty.textContent = "No web calendar is connected yet.";
          list.append(empty);
        }
        if (status.textContent === "Loading connections…") status.textContent = "Ready.";
      } catch (error) {
        status.textContent = `Sync unavailable: ${error.message}`;
      }
    }

    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      const submit = form.querySelector('[type="submit"]');
      submit.disabled = true;
      try {
        const data = new FormData(form);
        const connection = await calendarSyncRequest("/api/sync/feeds", {
          method: "POST",
          body: JSON.stringify({ label: String(data.get("label")), url: String(data.get("url")) })
        });
        await pullCalendarConnection(connection, status);
        form.reset();
        await paint();
      } catch (error) {
        status.textContent = `Sync failed · local changes safe: ${error.message}`;
        app.toast(error.message, true);
      } finally {
        submit.disabled = false;
      }
    });
    await paint();
  }

  byId("sync-calendars").addEventListener("click", () => {
    openCalendarSyncInspector();
  });

  byId("import-ics").addEventListener("click", () => {
    byId("ics-file").click();
  });
  byId("ics-file").addEventListener("change", async (event) => {
    for (const file of event.target.files || []) {
      try {
        const text = await file.text();
        const result = importCalendar(text, file.name.replace(/\.ics$/i, ""));
        app.selectLeadingFrame(result.frames[0] || app.session.activeFrame);
        app.toast(
          `Imported ${result.events.length} items from ${file.name}`
          + (result.suggestions.length ? ` · ${result.suggestions.length} staple suggestion(s)` : "")
          + (result.warnings.length ? ` · ${result.warnings.length} warning(s): ${result.warnings[0]}` : "")
        );
        if (result.suggestions.length) openStapleSuggestions(result.suggestions);
      } catch (error) {
        app.toast(`${file.name}: ${error.message}`, true);
      }
    }
    event.target.value = "";
    app.scheduleRender();
  });

  byId("export-ics").addEventListener("click", () => {
    const { chronolog, session, engine } = app;
    try {
      const window = session.window();
      // The export window bounds are a document-side query over `frame`'s own
      // relations (src/ics.js's `exportICS` resolves them via
      // `coordinateLaw(document, frame).toDays`), not wire data -- ICS's wire
      // format stays civil, but these bounds must be built under the SAME law
      // `exportICS` will read them back through.
      const frameLaw = coordinateLaw(chronolog, session.activeFrame);
      const text = exportICS(chronolog, {
        frame: session.activeFrame,
        start: frameLaw.fromDays(window.start),
        end: frameLaw.fromDays(window.end),
        engine
      });
      const title = chronolog.frames[session.activeFrame]?.title || "calendar";
      downloadText(text, `${title.replace(/[^\w.-]+/g, "-")}.ics`, "text/calendar");
      app.toast("Exported the visible calendar window.");
    } catch (error) {
      app.toast(error.message, true);
    }
  });
}
