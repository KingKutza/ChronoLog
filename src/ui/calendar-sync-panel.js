import { daysToCivilCoordinate } from "../exact.js";
import { applyICSSnapshot, calendarSyncConnections } from "../calendar-sync.js";
import { exportICS, importICS } from "../ics.js";
import { clone, stapleEvents } from "../model.js";
import { downloadText } from "../store.js";
import { byId, escapeHTML } from "./dom-helpers.js";

const IMPORT_MAPS = ["frames", "events", "patterns", "relations", "overrides"];

// The ICS feed UI: file import/export, staple suggestions surfaced after an
// import, and the read-only HTTPS calendar-feed subscription panel. `app`
// carries the live document/engine/session/history plus the cross-module
// calls into the toolbar (`app.closeDocumentMenu`) and the Frames panel
// (`app.selectLeadingFrame`) that a successful import triggers.
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
    let additions = null;
    let addedSources = null;
    let result = null;

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

    const apply = (documentValue) => {
      if (additions) {
        for (const name of IMPORT_MAPS) Object.assign(documentValue[name], additions[name]);
        documentValue.foreign.ics ||= { sources: {} };
        documentValue.foreign.ics.sources ||= {};
        Object.assign(documentValue.foreign.ics.sources, addedSources);
        return;
      }
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
    };

    history.executeDelta(
      `Import ${label}`,
      apply,
      (documentValue) => removeNewEntries(documentValue)
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

  function executeCalendarSync(label, options) {
    const { chronolog, history } = app;
    const before = clone(chronolog);
    let after = null;
    let result = null;
    const restore = (documentValue, snapshot) => {
      for (const key of Object.keys(documentValue)) delete documentValue[key];
      Object.assign(documentValue, clone(snapshot));
    };
    history.executeDelta(label, (documentValue) => {
      if (after) restore(documentValue, after);
      else {
        result = applyICSSnapshot(documentValue, options);
        after = clone(documentValue);
      }
    }, (documentValue) => restore(documentValue, before));
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
    <p class="field-note">Subscribe to an HTTPS ICS address published by Outlook, Google Calendar, Apple Calendar, or another calendar service. Refresh is explicit and read-only: ChronoLog never writes back or stores the secret feed URL in your document.</p>
    <form class="calendar-feed-form">
      <label class="field"><span>Name</span><input name="label" placeholder="Work calendar" required></label>
      <label class="field"><span>Secret HTTPS ICS address</span><input name="url" type="url" inputmode="url" autocomplete="off" placeholder="https://…/calendar.ics" required><small>Stored only by this local launcher with owner-only file permissions.</small></label>
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
    app.closeDocumentMenu();
    openCalendarSyncInspector();
  });

  byId("import-ics").addEventListener("click", () => {
    app.closeDocumentMenu();
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
    app.closeDocumentMenu();
    try {
      const window = session.window();
      const text = exportICS(chronolog, {
        frame: session.activeFrame,
        start: daysToCivilCoordinate(window.start),
        end: daysToCivilCoordinate(window.end),
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
