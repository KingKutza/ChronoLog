import { createCelestialDocument } from "./celestial.js";
import { ChronologEngine } from "./engine.js";
import {
  Rational,
  coordinate,
  daysFromCivil,
  daysToCivilCoordinate,
  formatCivil,
  levelValue
} from "./exact.js";
import { exportICS, importICS } from "./ics.js";
import {
  CommandHistory,
  addEvent,
  addFrame,
  addPattern,
  addRelation,
  clone,
  createId,
  durationMagnitude,
  eventRelations,
  stapleEvents,
  suppressVirtual,
  touch,
  validateDocument
} from "./model.js";
import {
  calendarFrames,
  groupFrames,
  renderMinimap,
  renderProjection
} from "./projections.js";
import { DETENTS, ViewSession } from "./session.js";
import {
  AutosaveStore,
  downloadText,
  parseDocument
} from "./store.js";

const byId = (id) => document.getElementById(id);
const projection = byId("projection");
const minimap = byId("minimap");
const inspector = byId("inspector");
const inspectorBody = byId("inspector-body");
const inspectorTitle = byId("inspector-title");
const toastNode = byId("toast");

let chronolog = createCelestialDocument();
let engine = new ChronologEngine(chronolog);
const initialParameters = new URLSearchParams(location.search);
const session = new ViewSession({
  activeFrame: initialParameters.get("frame") || "calendar:celestial",
  primeFrame: initialParameters.get("frame") || "calendar:celestial",
  projection: initialParameters.get("projection") || "calendar",
  scale: initialParameters.has("scale") ? Number(initialParameters.get("scale")) : 1,
  radialMode: initialParameters.get("radial") || "spiral"
});
let renderQueued = false;
let toastTimer = null;

const store = new AutosaveStore({
  onStatus(status) {
    const node = byId("save-status");
    node.dataset.state = status.state;
    node.textContent = status.message;
  }
});
store.attach(chronolog);

let history = makeHistory();

function makeHistory() {
  return new CommandHistory(chronolog, () => {
    engine.setDocument(chronolog);
    store.markDirty();
    scheduleRender();
  });
}

function replaceDocument(next) {
  chronolog = next;
  engine = new ChronologEngine(chronolog);
  history = makeHistory();
  store.attach(chronolog);
  const calendars = calendarFrames(chronolog);
  if (!chronolog.frames[session.activeFrame]) {
    session.activeFrame = calendars[0]?.id || "";
    session.primeFrame = session.activeFrame;
  }
  closeInspector();
  scheduleRender();
}

function context() {
  return { document: chronolog, engine, session };
}

function scheduleRender() {
  if (renderQueued) return;
  renderQueued = true;
  requestAnimationFrame(() => {
    renderQueued = false;
    render();
  });
}

function render() {
  updateCalendarSelect();
  updateChrome();
  renderProjection(projection, context());
  renderMinimap(minimap, context());
}

function updateCalendarSelect() {
  const select = byId("active-calendar");
  const frames = calendarFrames(chronolog);
  const currentOptions = [...select.options].map((option) => option.value).join("|");
  const nextOptions = frames.map((frame) => frame.id).join("|");
  if (currentOptions !== nextOptions) {
    select.replaceChildren();
    for (const frame of frames) {
      const option = document.createElement("option");
      option.value = frame.id;
      option.textContent = frame.title;
      select.append(option);
    }
  } else {
    frames.forEach((frame, index) => {
      if (select.options[index]) select.options[index].textContent = frame.title;
    });
  }
  select.value = session.activeFrame;
}

function updateChrome() {
  byId("scale").value = String(session.scale);
  byId("shared-focus").checked = session.sharedFocus;
  byId("focus-readout").textContent = formatCivil(daysToCivilCoordinate(session.currentFocus()), true);
  byId("undo").disabled = history.undoStack.length === 0;
  byId("redo").disabled = history.redoStack.length === 0;
  document.querySelectorAll("[data-projection]").forEach((button) => {
    button.classList.toggle("active", button.dataset.projection === session.projection);
  });
  document.querySelectorAll(".detent").forEach((button) => {
    button.classList.toggle("active", Math.abs(Number(button.dataset.scale) - session.scale) < 0.07);
  });
}

function toast(message, error = false) {
  clearTimeout(toastTimer);
  toastNode.textContent = message;
  toastNode.classList.toggle("error", error);
  toastNode.classList.add("show");
  toastTimer = setTimeout(() => toastNode.classList.remove("show"), 3600);
}

function closeInspector() {
  inspector.classList.remove("open");
  session.inspector = null;
}

function openInspector(title, body) {
  inspectorTitle.textContent = title;
  inspectorBody.replaceChildren();
  if (typeof body === "string") inspectorBody.innerHTML = body;
  else inspectorBody.append(body);
  inspector.classList.add("open");
}

function escapeHTML(value = "") {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function parseDateText(text) {
  const match = /^([+-]?\d+)-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2}(?:\.\d+)?))?)?$/.exec(
    String(text).trim()
  );
  if (!match) throw new Error("Use year-month-day and optional hour:minute:second");
  return coordinate([
    { level: "year", value: match[1] },
    { level: "month", value: match[2] },
    { level: "day", value: match[3] },
    { level: "hour", value: match[4] || "0" },
    { level: "minute", value: match[5] || "0" },
    { level: "second", value: match[6] || "0" }
  ]);
}

function magnitudeValue(event) {
  const first = event?.magnitudes?.duration?.value?.levels?.[0];
  return first || { level: "second", value: "0" };
}

function magnitudeDays(magnitude) {
  const factors = { week: "7", day: "1", hour: "1/24", minute: "1/1440", second: "1/86400" };
  let total = Rational.parse(0);
  for (const part of magnitude?.value?.levels || []) {
    if (factors[part.level] !== undefined) {
      total = total.add(Rational.parse(part.value).mul(String(factors[part.level])));
    }
  }
  return total;
}

function selectCycle(frameId) {
  const frame = chronolog.frames[frameId];
  if (!frame?.traits.includes("cycle")) return;
  const period = magnitudeDays(frame.period);
  if (period.compare(0) <= 0) {
    toast("A cycle period must be positive.", true);
    return;
  }
  session.activeCycle = frameId;
  session.radialCycle = period;
}

function temporalRelations(eventId) {
  return eventRelations(chronolog, eventId).filter(
    (relation) => chronolog.frames[relation.frame]?.traits.includes("calendar")
  );
}

function primaryRelation(eventId) {
  const all = temporalRelations(eventId);
  return all.find((relation) => relation.frame === session.activeFrame && relation.role !== "completed")
    || all.find((relation) => relation.role !== "completed")
    || null;
}

function relationDate(relation) {
  return relation?.coordinate ? formatCivil(relation.coordinate, true) : "";
}

function findVisibleFact(virtualId) {
  const window = session.window(1.25);
  return engine.queryFacts({
    frame: session.activeFrame,
    start: daysToCivilCoordinate(window.start),
    end: daysToCivilCoordinate(window.end)
  }).facts.find((fact) => fact.virtualId === virtualId);
}

function openVirtualInspector(virtualId) {
  const fact = findVisibleFact(virtualId);
  if (!fact) {
    toast("That generated fact is outside the current query window.", true);
    return;
  }
  const wrapper = document.createElement("div");
  wrapper.innerHTML = `
    <label class="field"><span>Generated by</span>
      <input value="${escapeHTML(fact.event.provenance?.pattern || "")}" readonly>
    </label>
    <label class="field"><span>Title</span>
      <input value="${escapeHTML(fact.event.payload?.title || "")}" readonly>
    </label>
    <label class="field"><span>Coordinate</span>
      <input value="${escapeHTML(formatCivil(fact.coordinate, true))}" readonly>
    </label>
    <p style="font:12px/1.5 var(--data);color:var(--muted)">
      Pattern facts stay virtual. Making this explicit suppresses only its stable virtual ID
      and creates an ordinary editable replacement.
    </p>
    <div class="inspector-actions">
      <button class="instrument-button primary" id="materialize" type="button">Make explicit</button>
    </div>`;
  openInspector(fact.event.payload?.title || "Generated fact", wrapper);
  byId("materialize").addEventListener("click", () => {
    let newEventId;
    history.execute("Make generated fact explicit", (documentValue) => {
      const explicitEvent = clone(fact.event);
      explicitEvent.id = createId("event");
      explicitEvent.traits = explicitEvent.traits.filter((trait) => trait !== "generated");
      explicitEvent.provenance = { kind: "explicit", replaces: virtualId };
      documentValue.events[explicitEvent.id] = explicitEvent;
      const explicitRelation = clone(fact.relation);
      explicitRelation.id = createId("relation");
      explicitRelation.event = explicitEvent.id;
      explicitRelation.provenance = { kind: "explicit", replaces: virtualId };
      documentValue.relations[explicitRelation.id] = explicitRelation;
      suppressVirtual(documentValue, virtualId, [explicitEvent.id]);
      newEventId = explicitEvent.id;
    });
    openEventInspector(newEventId);
  });
}

function openEventInspector(eventId) {
  const event = chronolog.events[eventId];
  if (!event) return;
  session.inspector = { type: "event", id: eventId };
  const relation = primaryRelation(eventId);
  const completed = temporalRelations(eventId).find((item) => item.role === "completed");
  const magnitude = magnitudeValue(event);
  const calendars = calendarFrames(chronolog);
  const groups = groupFrames(chronolog);
  const memberships = new Set(
    eventRelations(chronolog, eventId)
      .filter((item) => chronolog.frames[item.frame]?.traits.includes("group"))
      .map((item) => item.frame)
  );
  const isTask = event.traits.includes("task");
  const wrapper = document.createElement("form");
  wrapper.innerHTML = `
    <label class="field"><span>Title</span>
      <input name="title" value="${escapeHTML(event.payload?.title || "")}" required>
    </label>
    <label class="field"><span>Traits</span>
      <input name="traits" value="${escapeHTML(event.traits.join(", "))}">
    </label>
    <div class="form-row">
      <label class="field"><span>Intrinsic duration</span>
        <input name="duration" value="${escapeHTML(magnitude.value)}">
      </label>
      <label class="field"><span>Unit level</span>
        <input name="unit" value="${escapeHTML(magnitude.level)}">
      </label>
    </div>
    <label class="field"><span>${isTask ? "Observed at" : "Placed at"}</span>
      <input name="date" value="${escapeHTML(relationDate(relation))}"
        placeholder="+3220000-01-01 00:00:00">
    </label>
    <label class="field"><span>Calendar frame</span>
      <select name="frame">
        ${calendars.map((frame) => `<option value="${escapeHTML(frame.id)}"
          ${frame.id === relation?.frame ? "selected" : ""}>${escapeHTML(frame.title)}</option>`).join("")}
      </select>
    </label>
    ${isTask ? `<label class="field"><span>Completed at (optional)</span>
      <input name="completed" value="${escapeHTML(relationDate(completed))}">
    </label>` : ""}
    <label class="field"><span>Description</span>
      <textarea name="description">${escapeHTML(event.payload?.description || "")}</textarea>
    </label>
    <label class="field"><span>Location</span>
      <input name="location" value="${escapeHTML(event.payload?.location || "")}">
    </label>
    <div class="field"><span>Group membership</span>
      <div class="check-row">
        ${groups.map((frame) => `<label class="check-chip">
          <input type="checkbox" name="groups" value="${escapeHTML(frame.id)}"
            ${memberships.has(frame.id) ? "checked" : ""}>${escapeHTML(frame.title)}
        </label>`).join("") || `<span style="color:var(--faint);font:11px var(--data)">No group frames yet.</span>`}
      </div>
    </div>
    <div class="inspector-actions">
      <button class="instrument-button primary" type="submit">Apply</button>
      <button class="instrument-button danger" id="delete-object" type="button">Delete</button>
    </div>`;
  openInspector(event.payload?.title || "Event", wrapper);

  wrapper.addEventListener("submit", (inputEvent) => {
    inputEvent.preventDefault();
    const data = new FormData(wrapper);
    try {
      const nextCoordinate = data.get("date") ? parseDateText(data.get("date")) : null;
      const completedCoordinate = isTask && data.get("completed")
        ? parseDateText(data.get("completed"))
        : null;
      history.execute("Edit event", (documentValue) => {
        const target = documentValue.events[eventId];
        target.payload ||= {};
        target.payload.title = String(data.get("title") || "(untitled)");
        target.payload.description = String(data.get("description") || "");
        target.payload.location = String(data.get("location") || "");
        target.traits = String(data.get("traits") || "event")
          .split(",").map((item) => item.trim()).filter(Boolean);
        if (!target.traits.includes("event")) target.traits.unshift("event");
        target.magnitudes ||= {};
        const requiresZero = target.traits.includes("task") || target.traits.includes("terminator");
        target.magnitudes.duration = durationMagnitude(
          requiresZero ? "0" : String(data.get("duration") || "0"),
          String(data.get("unit") || "second")
        );
        const chosenFrame = String(data.get("frame") || session.activeFrame);
        const existing = Object.values(documentValue.relations).find(
          (item) => item.type === "attachment"
            && item.event === eventId
            && documentValue.frames[item.frame]?.traits.includes("calendar")
            && item.role !== "completed"
        );
        if (nextCoordinate) {
          if (existing) {
            existing.frame = chosenFrame;
            existing.coordinate = nextCoordinate;
            existing.role = target.traits.includes("task") ? "observed" : "placed";
          } else {
            addRelation(documentValue, {
              type: "attachment",
              event: eventId,
              frame: chosenFrame,
              role: target.traits.includes("task") ? "observed" : "placed",
              coordinate: nextCoordinate
            });
          }
        } else if (existing) {
          delete documentValue.relations[existing.id];
        }
        const existingCompleted = Object.values(documentValue.relations).find(
          (item) => item.type === "attachment" && item.event === eventId && item.role === "completed"
        );
        if (completedCoordinate) {
          if (existingCompleted) {
            existingCompleted.coordinate = completedCoordinate;
            existingCompleted.frame = chosenFrame;
          } else {
            addRelation(documentValue, {
              type: "attachment",
              event: eventId,
              frame: chosenFrame,
              role: "completed",
              coordinate: completedCoordinate
            });
          }
        } else if (existingCompleted) {
          delete documentValue.relations[existingCompleted.id];
        }
        const selectedGroups = new Set(data.getAll("groups").map(String));
        for (const relationValue of Object.values(documentValue.relations)) {
          if (
            relationValue.type === "attachment"
            && relationValue.event === eventId
            && documentValue.frames[relationValue.frame]?.traits.includes("group")
            && !selectedGroups.has(relationValue.frame)
          ) delete documentValue.relations[relationValue.id];
        }
        for (const frameId of selectedGroups) {
          const exists = Object.values(documentValue.relations).some(
            (item) => item.type === "attachment" && item.event === eventId && item.frame === frameId
          );
          if (!exists) addRelation(documentValue, {
            type: "attachment", event: eventId, frame: frameId, role: "member"
          });
        }
      });
      openEventInspector(eventId);
    } catch (error) {
      toast(error.message, true);
    }
  });

  wrapper.querySelector("#delete-object").addEventListener("click", () => {
    history.execute("Delete event", (documentValue) => {
      delete documentValue.events[eventId];
      for (const relationValue of Object.values(documentValue.relations)) {
        if (relationValue.event === eventId) delete documentValue.relations[relationValue.id];
      }
      for (const pattern of Object.values(documentValue.patterns)) {
        if (pattern.templateEvent === eventId) delete documentValue.patterns[pattern.id];
      }
    });
    closeInspector();
  });
}

function frameForm(frame = null) {
  const isNew = !frame;
  const value = frame || {
    id: "",
    title: "New group",
    traits: ["set", "group"],
    basis: "",
    color: "#2e8b57",
    coordinate: null,
    period: null
  };
  const wrapper = document.createElement("form");
  wrapper.innerHTML = `
    <label class="field"><span>Title</span>
      <input name="title" value="${escapeHTML(value.title)}" required>
    </label>
    <label class="field"><span>Traits</span>
      <input name="traits" value="${escapeHTML(value.traits.join(", "))}">
    </label>
    <label class="field"><span>Basis frame</span>
      <select name="basis">
        <option value="">None</option>
        ${Object.values(chronolog.frames).filter((item) => item.id !== value.id)
          .map((item) => `<option value="${escapeHTML(item.id)}"
            ${item.id === value.basis ? "selected" : ""}>${escapeHTML(item.title)}</option>`).join("")}
      </select>
    </label>
    <label class="field"><span>Color</span>
      <input name="color" type="color" value="${escapeHTML(value.color || "#2e8b57")}">
    </label>
    <label class="field"><span>Cycle period in days (when trait includes cycle)</span>
      <input name="period" value="${escapeHTML(
        value.period?.value?.levels?.find((part) => part.level === "day")?.value || ""
      )}">
    </label>
    <label class="field"><span>Coordinate nesting (JSON)</span>
      <textarea name="coordinate" class="code">${escapeHTML(
        value.coordinate ? JSON.stringify(value.coordinate, null, 2) : ""
      )}</textarea>
    </label>
    <div class="inspector-actions">
      <button class="instrument-button primary" type="submit">${isNew ? "Create" : "Apply"}</button>
      ${isNew ? "" : `<button class="instrument-button danger" id="delete-object" type="button">Delete</button>`}
    </div>`;
  wrapper.addEventListener("submit", (event) => {
    event.preventDefault();
    const data = new FormData(wrapper);
    try {
      const coordinateSchema = data.get("coordinate")
        ? JSON.parse(String(data.get("coordinate")))
        : undefined;
      let id = value.id;
      history.execute(isNew ? "Create frame" : "Edit frame", (documentValue) => {
        const payload = {
          id: isNew ? undefined : id,
          title: String(data.get("title")),
          traits: String(data.get("traits")).split(",").map((item) => item.trim()).filter(Boolean),
          basis: String(data.get("basis") || "") || undefined,
          color: String(data.get("color") || "#2e8b57"),
          coordinate: coordinateSchema,
          period: data.get("period")
            ? {
                frame: "measure:human-time",
                value: coordinate([{ level: "day", value: String(data.get("period")) }])
              }
            : undefined
        };
        if (isNew) id = addFrame(documentValue, payload).id;
        else Object.assign(documentValue.frames[id], payload);
      });
      openFrameInspector(id);
    } catch (error) {
      toast(error.message, true);
    }
  });
  if (!isNew) wrapper.querySelector("#delete-object").addEventListener("click", () => {
    const referenced = Object.values(chronolog.relations).some(
      (relation) => relation.frame === value.id || relation.parent === value.id || relation.child === value.id
    );
    if (referenced) {
      toast("Remove this frame's attachments and compositions before deleting it.", true);
      return;
    }
    history.execute("Delete frame", (documentValue) => delete documentValue.frames[value.id]);
    openObjectBrowser("frame");
  });
  return wrapper;
}

function openFrameInspector(frameId = null) {
  const frame = frameId ? chronolog.frames[frameId] : null;
  session.inspector = { type: "frame", id: frameId };
  openInspector(frame?.title || "New frame", frameForm(frame));
}

function patternForm(pattern = null) {
  const isNew = !pattern;
  const value = pattern || {
    id: "",
    title: "New pattern",
    language: "chronolog-formula/1",
    appliesTo: [session.activeFrame],
    frame: session.activeFrame,
    constants: {},
    source: "export fn state(ctx) = {};\nexport fn facts(ctx) = [];\n",
    exports: { state: "state", facts: "facts" }
  };
  const wrapper = document.createElement("form");
  wrapper.innerHTML = `
    <label class="field"><span>Title</span>
      <input name="title" value="${escapeHTML(value.title)}" required>
    </label>
    <label class="field"><span>Applies to frame</span>
      <select name="frame">
        ${Object.values(chronolog.frames).map((frame) => `<option value="${escapeHTML(frame.id)}"
          ${value.appliesTo?.includes(frame.id) ? "selected" : ""}>${escapeHTML(frame.title)}</option>`).join("")}
      </select>
    </label>
    <label class="field"><span>Constants (JSON)</span>
      <textarea name="constants" class="code">${escapeHTML(JSON.stringify(value.constants || {}, null, 2))}</textarea>
    </label>
    <label class="field"><span>chronolog-formula/1 source</span>
      <textarea name="source" class="code">${escapeHTML(value.source)}</textarea>
    </label>
    <div id="pattern-output" style="font:11px/1.4 var(--data);white-space:pre-wrap;color:var(--muted)"></div>
    <div class="inspector-actions">
      <button class="instrument-button" id="test-pattern" type="button">Test query</button>
      <button class="instrument-button primary" type="submit">${isNew ? "Create" : "Apply"}</button>
      ${isNew ? "" : `<button class="instrument-button danger" id="delete-object" type="button">Delete</button>`}
    </div>`;
  const test = () => {
    const output = wrapper.querySelector("#pattern-output");
    try {
      const source = String(new FormData(wrapper).get("source"));
      const module = engine.runtime.compile(source);
      const data = new FormData(wrapper);
      const constants = JSON.parse(String(data.get("constants") || "{}"));
      const at = session.currentFocus().toJSON();
      const state = module.call("state", [{
        frame: String(data.get("frame")),
        atDays: at,
        fromDays: session.window().start.toJSON(),
        toDays: session.window().end.toJSON(),
        constants
      }]);
      output.textContent = `Valid.\n${JSON.stringify(state, null, 2).slice(0, 1800)}`;
      output.style.color = "var(--green)";
    } catch (error) {
      output.textContent = error.message;
      output.style.color = "var(--now)";
    }
  };
  wrapper.querySelector("#test-pattern").addEventListener("click", test);
  wrapper.addEventListener("submit", (event) => {
    event.preventDefault();
    const data = new FormData(wrapper);
    try {
      const source = String(data.get("source"));
      engine.runtime.compile(source);
      const constants = JSON.parse(String(data.get("constants") || "{}"));
      let id = value.id;
      history.execute(isNew ? "Create pattern" : "Edit pattern", (documentValue) => {
        const payload = {
          id: isNew ? undefined : id,
          title: String(data.get("title")),
          language: "chronolog-formula/1",
          appliesTo: [String(data.get("frame"))],
          frame: String(data.get("frame")),
          constants,
          source,
          exports: { state: "state", facts: "facts" }
        };
        if (isNew) id = addPattern(documentValue, payload).id;
        else Object.assign(documentValue.patterns[id], payload);
      });
      openPatternInspector(id);
    } catch (error) {
      toast(error.message, true);
    }
  });
  if (!isNew) wrapper.querySelector("#delete-object").addEventListener("click", () => {
    history.execute("Delete pattern", (documentValue) => delete documentValue.patterns[value.id]);
    openObjectBrowser("pattern");
  });
  return wrapper;
}

function openPatternInspector(patternId = null) {
  const pattern = patternId ? chronolog.patterns[patternId] : null;
  session.inspector = { type: "pattern", id: patternId };
  openInspector(pattern?.title || "New pattern", patternForm(pattern));
}

function openObjectBrowser(kind) {
  const records = kind === "frame" ? Object.values(chronolog.frames) : Object.values(chronolog.patterns);
  const wrapper = document.createElement("div");
  const create = document.createElement("button");
  create.type = "button";
  create.className = "instrument-button primary";
  create.textContent = kind === "frame" ? "Create frame" : "Create pattern";
  create.addEventListener("click", () => kind === "frame" ? openFrameInspector() : openPatternInspector());
  wrapper.append(create, document.createElement("hr"));
  for (const record of records) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "event-chip";
    button.textContent = `${record.title || record.id} · ${(record.traits || [record.language]).join(", ")}`;
    button.addEventListener("click", () =>
      kind === "frame" ? openFrameInspector(record.id) : openPatternInspector(record.id)
    );
    wrapper.append(button);
  }
  openInspector(kind === "frame" ? "Frames" : "Patterns", wrapper);
}

function openStapleSuggestions(suggestions) {
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
      history.execute("Staple matching ICS identities", (documentValue) => {
        stapleEvents(documentValue, eventIds);
      });
      card.remove();
      toast("Stapled matching identities.");
    });
    card.append(title, detail, button);
    wrapper.append(card);
  }
  openInspector("Staple suggestions", wrapper);
}

function createEventAt(startDay, endDay = startDay) {
  let eventId;
  const start = Rational.parse(startDay);
  const end = Rational.parse(endDay);
  const orderedStart = start.compare(end) <= 0 ? start : end;
  const orderedEnd = start.compare(end) <= 0 ? end : start;
  history.execute("Create event", (documentValue) => {
    const event = addEvent(documentValue, {
      traits: ["event"],
      magnitudes: {
        duration: durationMagnitude(orderedEnd.sub(orderedStart).mul(86400).toJSON(), "second")
      },
      payload: { title: "New event", description: "", location: "" }
    });
    eventId = event.id;
    addRelation(documentValue, {
      type: "attachment",
      event: event.id,
      frame: session.activeFrame,
      role: "placed",
      coordinate: daysToCivilCoordinate(orderedStart)
    });
  });
  openEventInspector(eventId);
}

function panFromWheel(event) {
  event.preventDefault();
  if (event.ctrlKey || event.metaKey) {
    session.scale = Math.max(0, Math.min(2, session.scale + event.deltaY / 700));
  } else if (session.projection === "radial") {
    session.move(session.radialCycle.mul(event.deltaY / 850));
  } else if (session.projection === "calendar" && session.scale < 0.55) {
    session.move(Rational.parse(event.deltaY / 110).div(24));
  } else {
    const rate = session.visibleSpan() / 18;
    session.move(Rational.parse(String(event.deltaY / 120 * rate)));
  }
  scheduleRender();
}

function handleRadialAction(action) {
  if (action === "previous-cycle") session.move(session.radialCycle.neg());
  else if (action === "next-cycle") session.move(session.radialCycle);
  else if (action === "toggle-radial") {
    session.radialMode = session.radialMode === "spiral" ? "concentric" : "spiral";
  } else if (action === "past-more") session.radialPast += 1;
  else if (action === "past-less") session.radialPast = Math.max(0, session.radialPast - 1);
  else if (action === "future-more") session.radialFuture += 1;
  else if (action === "future-less") session.radialFuture = Math.max(0, session.radialFuture - 1);
  scheduleRender();
}

document.querySelectorAll("[data-projection]").forEach((button) => {
  button.addEventListener("click", () => {
    session.setProjection(button.dataset.projection);
    scheduleRender();
  });
});

document.querySelectorAll(".detent").forEach((button) => {
  button.addEventListener("click", () => {
    session.scale = Number(button.dataset.scale);
    scheduleRender();
  });
});

byId("scale").addEventListener("input", (event) => {
  session.scale = Number(event.target.value);
  scheduleRender();
});

byId("active-calendar").addEventListener("change", (event) => {
  session.activeFrame = event.target.value;
  session.primeFrame = session.activeFrame;
  const matchingCycle = Object.values(chronolog.frames).find(
    (frame) => frame.traits.includes("cycle") && frame.calendar === session.activeFrame
  );
  if (matchingCycle) selectCycle(matchingCycle.id);
  scheduleRender();
});

byId("shared-focus").addEventListener("change", (event) => {
  session.toggleShared(event.target.checked);
  scheduleRender();
});

byId("today").addEventListener("click", () => {
  const now = new Date();
  session.setFocus(new Rational(daysFromCivil(
    BigInt(now.getFullYear()), BigInt(now.getMonth() + 1), BigInt(now.getDate())
  )));
  scheduleRender();
});

byId("undo").addEventListener("click", () => history.undo());
byId("redo").addEventListener("click", () => history.redo());
byId("close-inspector").addEventListener("click", closeInspector);
byId("new-event").addEventListener("click", () => createEventAt(session.currentFocus()));
byId("new-frame").addEventListener("click", () => openObjectBrowser("frame"));
byId("new-pattern").addEventListener("click", () => openObjectBrowser("pattern"));

projection.addEventListener("wheel", panFromWheel, { passive: false });

let createStart = null;
projection.addEventListener("pointerdown", (event) => {
  if (event.target.closest("[data-event-id],button")) return;
  const cell = event.target.closest("[data-create-day]");
  if (cell) createStart = cell.dataset.createDay;
});
projection.addEventListener("pointerup", (event) => {
  if (!createStart) return;
  const cell = event.target.closest("[data-create-day]");
  const start = createStart;
  createStart = null;
  if (cell) createEventAt(start, cell.dataset.createDay);
});

projection.addEventListener("click", (event) => {
  const action = event.target.closest("[data-action]")?.dataset.action;
  if (action) {
    handleRadialAction(action);
    return;
  }
  const item = event.target.closest("[data-event-id]");
  if (!item) return;
  event.stopPropagation();
  if (item.dataset.virtualId) openVirtualInspector(item.dataset.virtualId);
  else openEventInspector(item.dataset.eventId);
});

projection.addEventListener("change", (event) => {
  const selector = event.target.closest("[data-cycle-select]");
  if (!selector) return;
  selectCycle(selector.value);
  scheduleRender();
});

minimap.addEventListener("pointerdown", (event) => {
  const svg = minimap.querySelector("svg");
  if (!svg) return;
  const bounds = minimap.getBoundingClientRect();
  const fraction = Math.max(0, Math.min(1, (event.clientX - bounds.left) / bounds.width));
  const start = Rational.parse(svg.dataset.minimapStart);
  const end = Rational.parse(svg.dataset.minimapEnd);
  session.setFocus(start.add(end.sub(start).mul(String(fraction))));
  minimap.setPointerCapture?.(event.pointerId);
  scheduleRender();
});

minimap.addEventListener("pointermove", (event) => {
  if (!minimap.hasPointerCapture?.(event.pointerId)) return;
  const svg = minimap.querySelector("svg");
  const bounds = minimap.getBoundingClientRect();
  const fraction = Math.max(0, Math.min(1, (event.clientX - bounds.left) / bounds.width));
  const start = Rational.parse(svg.dataset.minimapStart);
  const end = Rational.parse(svg.dataset.minimapEnd);
  session.setFocus(start.add(end.sub(start).mul(String(fraction))));
  scheduleRender();
});

byId("open-document").addEventListener("click", () => byId("document-file").click());
byId("document-file").addEventListener("change", async (event) => {
  const file = event.target.files?.[0];
  if (!file) return;
  try {
    replaceDocument(parseDocument(await file.text()));
    toast(`Opened ${file.name}`);
  } catch (error) {
    toast(error.message, true);
  } finally {
    event.target.value = "";
  }
});

byId("save-document").addEventListener("click", async () => {
  try {
    if (globalThis.showSaveFilePicker) await store.chooseFile();
    else store.download("chronolog.json");
  } catch (error) {
    if (error.name !== "AbortError") toast(error.message, true);
  }
});

byId("import-ics").addEventListener("click", () => byId("ics-file").click());
byId("ics-file").addEventListener("change", async (event) => {
  for (const file of event.target.files || []) {
    try {
      const text = await file.text();
      let result;
      history.execute(`Import ${file.name}`, (documentValue) => {
        result = importICS(text, documentValue, { label: file.name.replace(/\.ics$/i, "") });
      });
      session.activeFrame = result.frames[0] || session.activeFrame;
      session.primeFrame = session.activeFrame;
      toast(
        `Imported ${result.events.length} items from ${file.name}`
        + (result.suggestions.length ? ` · ${result.suggestions.length} staple suggestion(s)` : "")
      );
      if (result.suggestions.length) openStapleSuggestions(result.suggestions);
    } catch (error) {
      toast(`${file.name}: ${error.message}`, true);
    }
  }
  event.target.value = "";
  scheduleRender();
});

byId("export-ics").addEventListener("click", () => {
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
    toast("Exported the visible calendar window.");
  } catch (error) {
    toast(error.message, true);
  }
});

window.addEventListener("keydown", (event) => {
  const editing = /^(INPUT|TEXTAREA|SELECT)$/.test(event.target.tagName);
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "z") {
    event.preventDefault();
    if (event.shiftKey) history.redo();
    else history.undo();
    return;
  }
  if (editing) return;
  if (event.key === "ArrowLeft") session.move(Rational.parse(-session.visibleSpan() / 8));
  else if (event.key === "ArrowRight") session.move(Rational.parse(session.visibleSpan() / 8));
  else if (event.key === "+" || event.key === "=") session.scale = Math.max(0, session.scale - 0.15);
  else if (event.key === "-") session.scale = Math.min(2, session.scale + 0.15);
  else if (event.key.toLowerCase() === "n") {
    createEventAt(session.currentFocus());
    return;
  } else if (/^[1-4]$/.test(event.key)) {
    session.setProjection(["calendar", "wall", "lines", "radial"][Number(event.key) - 1]);
  } else return;
  event.preventDefault();
  scheduleRender();
});

window.addEventListener("beforeunload", (event) => {
  if (store.revision !== store.savedRevision) {
    event.preventDefault();
    event.returnValue = "";
  }
});

const validation = validateDocument(chronolog);
if (!validation.valid) toast(validation.errors.join(" · "), true);
render();
