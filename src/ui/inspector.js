import {
  Rational,
  coordinate,
  daysToCivilCoordinate,
  formatCivil,
  levelValue
} from "../exact.js";
import {
  addEvent,
  addPattern,
  addRelation,
  clone,
  createId,
  durationMagnitude,
  durationMagnitudeDays,
  eventRelations
} from "../model.js";
import { OBJECT_KINDS, normalizeObjectKind, objectKindForEvent, traitsForObjectKind } from "../object-kinds.js";
import { delOp, putOp } from "../ops.js";
import { calendarFrames, groupFrames } from "../projections.js";
import { byId, escapeHTML } from "./dom-helpers.js";

// The Inspector panel: generic open/close chrome, the provisional-draft
// lifecycle (a just-created event that autosave defers until it is saved or
// discarded), the event/object-kind form, and generated-fact materialization.
// `app` carries the live document/engine/session/history/store plus the
// small `framesReturnTarget` focus-return slot that the Frames panel also
// writes when it reopens this same panel.
export function createInspector(app, dom) {
  const { inspector, inspectorBody, inspectorTitle } = dom;
  let provisionalEvent = null;

  function openInspector(title, body, panel = "object") {
    inspectorTitle.textContent = title;
    inspectorBody.replaceChildren(body);
    inspector.dataset.panel = panel;
    inspector.classList.add("open");
  }

  function dismissInspector() {
    const { session } = app;
    const wasFramesBrowser = inspector.dataset.panel === "frames-browser";
    const returnTarget = app.framesReturnTarget;
    inspector.classList.remove("open");
    delete inspector.dataset.panel;
    session.inspector = null;
    for (const id of ["new-frame", "manage-frames"]) byId(id).setAttribute("aria-expanded", "false");
    app.framesReturnTarget = null;
    if (wasFramesBrowser) {
      const visibleToolbarTrigger = byId("new-frame").getClientRects().length ? byId("new-frame") : null;
      (returnTarget || visibleToolbarTrigger || byId("document-menu").querySelector("summary")).focus();
    }
  }

  function closeInspector() {
    discardProvisionalDraft();
    dismissInspector();
  }

  function hasProvisionalDraft() {
    return Boolean(provisionalEvent);
  }

  // Used only when the whole document is being replaced wholesale (a fresh
  // open, or reloading after a conflict): the draft belongs to a document
  // that is about to stop existing, so there is nothing to discard through
  // an undo transaction — just forget it.
  function clearProvisionalDraft() {
    provisionalEvent = null;
  }

  function discardProvisionalDraft(nextEventId = null) {
    if (!provisionalEvent || provisionalEvent.id === nextEventId) return false;
    const eventId = provisionalEvent.id;
    provisionalEvent = null;
    try {
      app.executeEventChange("Discard provisional draft", eventId, (documentValue) => {
        delete documentValue.events[eventId];
        for (const [id, relation] of Object.entries(documentValue.relations)) {
          if (relation.event === eventId) delete documentValue.relations[id];
        }
      }, true);
    } finally {
      // A close or validation failure must never leave the document permanently
      // deferred. The draft is a transaction, not an autosave lock.
      app.store.endDeferred();
    }
    return true;
  }

  function resolveProvisionalDraft(nextEventId = null) {
    if (!provisionalEvent || provisionalEvent.id === nextEventId) return true;
    discardProvisionalDraft();
    return true;
  }

  function commitProvisionalDraft(eventId) {
    if (!provisionalEvent || provisionalEvent.id !== eventId) return false;
    provisionalEvent = null;
    app.store.endDeferred();
    return true;
  }

  function focusInspectorEditor(eventId) {
    requestAnimationFrame(() => {
      if (app.session.inspector?.type !== "event" || app.session.inspector.id !== eventId) return;
      const title = inspectorBody.querySelector('input[name="title"]');
      if (!(title instanceof HTMLInputElement)) return;
      title.focus({ preventScroll: true });
      title.select();
    });
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

  function friendlyDuration(event) {
    const seconds = durationMagnitudeDays(event?.magnitudes?.duration).mul(86400).toNumber();
    if (!Number.isFinite(seconds) || seconds <= 0) return { amount: "0", unit: "minute" };
    for (const [unit, factor] of [["day", 86400], ["hour", 3600], ["minute", 60]]) {
      const amount = seconds / factor;
      if (Number.isInteger(amount)) return { amount: String(amount), unit };
    }
    return { amount: String(Math.round(seconds)), unit: "second" };
  }

  function temporalRelations(eventId) {
    const { chronolog } = app;
    return eventRelations(chronolog, eventId).filter(
      (relation) => chronolog.frames[relation.frame]?.traits.includes("calendar")
    );
  }

  function primaryRelation(eventId) {
    const { session } = app;
    const all = temporalRelations(eventId);
    return all.find((relation) => relation.frame === session.activeFrame && relation.role !== "completed")
      || all.find((relation) => relation.role !== "completed")
      || null;
  }

  function relationDate(relation) {
    return relation?.coordinate ? formatCivil(relation.coordinate, true) : "";
  }

  function relationDateParts(relation) {
    if (!relation?.coordinate) return { date: "", time: "" };
    const value = relation.coordinate;
    const year = levelValue(value, "year", 0n).toString().padStart(4, "0");
    const month = levelValue(value, "month", 1n).toString().padStart(2, "0");
    const day = levelValue(value, "day", 1n).toString().padStart(2, "0");
    const hour = levelValue(value, "hour", 0n).toString().padStart(2, "0");
    const minute = levelValue(value, "minute", 0n).toString().padStart(2, "0");
    return { date: `${year}-${month}-${day}`, time: relation.parameters?.dateOnly ? "" : `${hour}:${minute}` };
  }

  function findVisibleFact(virtualId, nearDay = null) {
    const { session, engine } = app;
    const window = nearDay === null
      ? session.window(1.25)
      : {
          start: Rational.parse(nearDay).sub(Rational.parse(1).div(86400)),
          end: Rational.parse(nearDay).add(Rational.parse(1).div(86400))
        };
    return engine.queryFacts({
      frame: session.activeFrame,
      start: daysToCivilCoordinate(window.start),
      end: daysToCivilCoordinate(window.end),
      limit: nearDay === null ? 1600 : 5000
    }).facts.find((fact) => fact.virtualId === virtualId);
  }

  function recurrenceFormChoice(pattern) {
    const frequency = String(pattern?.rrule?.FREQ || "").toUpperCase();
    const byDay = String(pattern?.rrule?.BYDAY || "").toUpperCase().split(",")
      .map((value) => value.trim()).filter(Boolean).sort().join(",");
    return frequency === "WEEKLY" && byDay === "FR,MO,TH,TU,WE" ? "WEEKDAYS" : frequency;
  }

  function prepareMaterialization(fact, coordinateValue = fact.relation.coordinate) {
    const { chronolog } = app;
    const explicitEvent = clone(fact.event);
    explicitEvent.id = createId("event");
    explicitEvent.traits = explicitEvent.traits.filter((trait) => trait !== "generated");
    const patternId = fact.event.provenance?.pattern;
    explicitEvent.provenance = {
      kind: "explicit",
      replaces: fact.virtualId,
      pattern: patternId,
      originalCoordinate: clone(fact.relation.coordinate)
    };
    const explicitRelation = clone(fact.relation);
    explicitRelation.id = createId("relation");
    explicitRelation.event = explicitEvent.id;
    explicitRelation.coordinate = clone(coordinateValue);
    explicitRelation.provenance = { kind: "explicit", replaces: fact.virtualId };
    const override = {
      id: createId("override"),
      virtual: fact.virtualId,
      suppress: true,
      replacements: [explicitEvent.id]
    };
    const templateEventId = chronolog.patterns[patternId]?.templateEvent;
    const relations = templateEventId ? eventRelations(chronolog, templateEventId)
      .filter((relation) => relation.type === "attachment"
        && chronolog.frames[relation.frame]?.traits.includes("group"))
      .map((relation) => ({ ...clone(relation), id: createId("relation"), event: explicitEvent.id })) : [];
    return { event: explicitEvent, relation: explicitRelation, relations, override };
  }

  function applyMaterialization(documentValue, prepared) {
    documentValue.events[prepared.event.id] = prepared.event;
    documentValue.relations[prepared.relation.id] = prepared.relation;
    for (const relation of prepared.relations || []) documentValue.relations[relation.id] = relation;
    documentValue.overrides[prepared.override.id] = prepared.override;
  }

  function revertMaterialization(documentValue, prepared) {
    delete documentValue.overrides[prepared.override.id];
    delete documentValue.relations[prepared.relation.id];
    for (const relation of prepared.relations || []) delete documentValue.relations[relation.id];
    delete documentValue.events[prepared.event.id];
  }

  // `prepared` is computed once, before the delta runs, and does not change
  // across redo/undo, so the ops it implies are equally static — no need for
  // the mutable-metadata capture the record-level helpers use elsewhere.
  function materializationOps(prepared) {
    const extraRelations = prepared.relations || [];
    return {
      ops: [
        putOp("events", prepared.event.id, prepared.event),
        putOp("relations", prepared.relation.id, prepared.relation),
        ...extraRelations.map((relation) => putOp("relations", relation.id, relation)),
        putOp("overrides", prepared.override.id, prepared.override)
      ],
      inverseOps: [
        delOp("overrides", prepared.override.id),
        ...[...extraRelations].reverse().map((relation) => delOp("relations", relation.id)),
        delOp("relations", prepared.relation.id),
        delOp("events", prepared.event.id)
      ]
    };
  }

  function openVirtualInspector(virtualId) {
    const { chronolog, history } = app;
    const fact = findVisibleFact(virtualId);
    if (!fact) {
      app.toast("That generated fact is outside the current query window.", true);
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
    <label class="field"><span>Occurs</span>
      <input value="${escapeHTML(formatCivil(fact.coordinate, true))}" readonly>
    </label>
    <p style="font:12px/1.5 var(--data);color:var(--muted)">
      Edit only this occurrence, or edit the repeating series that produced it.
    </p>
    <div class="inspector-actions">
      <button class="instrument-button primary" id="materialize" type="button">Edit this occurrence</button>
      <button class="instrument-button" id="edit-series" type="button">Edit series</button>
    </div>`;
    openInspector(fact.event.payload?.title || "Generated fact", wrapper);
    byId("materialize").addEventListener("click", () => {
      const prepared = prepareMaterialization(fact);
      history.executeDelta(
        "Make generated fact explicit",
        (documentValue) => applyMaterialization(documentValue, prepared),
        (documentValue) => revertMaterialization(documentValue, prepared),
        { preserveRecurrence: true, ...materializationOps(prepared) }
      );
      openEventInspector(prepared.event.id);
    });
    byId("edit-series").addEventListener("click", () => {
      const pattern = chronolog.patterns[fact.event.provenance?.pattern];
      if (pattern?.templateEvent) openEventInspector(pattern.templateEvent);
    });
  }

  function openEventInspector(eventId) {
    const { chronolog, engine, session } = app;
    if (!resolveProvisionalDraft(eventId)) return false;
    const event = chronolog.events[eventId];
    if (!event) return false;
    session.inspector = { type: "event", id: eventId };
    const relation = primaryRelation(eventId);
    const completed = temporalRelations(eventId).find((item) => item.role === "completed");
    const duration = friendlyDuration(event);
    const calendars = calendarFrames(chronolog);
    const allGroups = groupFrames(chronolog);
    const importanceFrames = allGroups.filter((frame) => frame.traits.includes("importance"));
    const groups = allGroups.filter((frame) => !frame.traits.includes("importance"));
    const recurrence = Object.values(chronolog.patterns).find(
      (pattern) => pattern.kind === "ics-rrule" && pattern.templateEvent === eventId
    );
    const originalRecurrenceChoice = recurrenceFormChoice(recurrence);
    const membershipReasons = new Map(engine.eventGroupMemberships(eventId)
      .map(({ group, provenance }) => [group, provenance]));
    const memberships = new Set([
      ...membershipReasons.keys(),
      ...eventRelations(chronolog, eventId)
        .filter((item) => chronolog.frames[item.frame]?.traits.includes("importance"))
        .map((item) => item.frame)
    ]);
    const membershipExplanation = (groupId) => (membershipReasons.get(groupId) || [])
      .map((reason) => reason.kind === "authored" ? "authored membership"
        : reason.kind === "query" ? "live query"
          : `nested through ${reason.via}`)
      .join("; ");
    const objectKind = objectKindForEvent(event);
    const startParts = relationDateParts(relation);
    const attachedImportance = importanceFrames.find((frame) => memberships.has(frame.id));
    const importance = attachedImportance?.id || (event.traits.includes("landmark") ? "landmark"
      : event.traits.includes("important") ? "important" : "standard");
    const lensScope = event.display?.lenses || null;
    const visibility = attachedImportance ? "importance-frame" : !lensScope ? "everywhere"
      : ["intimate", "spiral", "radial"].every((lens) => lensScope.includes(lens)) && lensScope.length === 3
        ? "time-signal"
        : ["strategic", "wall", "radial"].every((lens) => lensScope.includes(lens)) && lensScope.length === 3
          ? "planning"
          : "close";
    const wrapper = document.createElement("form");
    wrapper.className = "event-form";
    wrapper.innerHTML = `
    <label class="field"><span>Kind</span>
      <select name="objectKind">
        ${Object.entries(OBJECT_KINDS).map(([value, definition]) => `<option value="${value}" ${objectKind === value ? "selected" : ""}>${definition.label}</option>`).join("")}
      </select>
    </label>
    <label class="field"><span>Title</span>
      <input name="title" value="${escapeHTML(event.payload?.title || "")}" required>
    </label>
    <div class="form-row">
      <label class="field"><span data-object-date-label>Start date</span>
        <input name="startDate" type="date" value="${escapeHTML(startParts.date)}">
      </label>
      <label class="field"><span data-object-time-label>Start time</span>
        <input name="startTime" type="time" step="60" value="${escapeHTML(startParts.time)}">
      </label>
    </div>
    <div class="form-row" data-duration-row>
      <label class="field"><span>Duration</span>
        <input name="duration" inputmode="decimal" value="${escapeHTML(duration.amount)}">
      </label>
      <label class="field"><span>Units</span>
        <select name="unit">
          ${[["minute", "Minutes"], ["hour", "Hours"], ["day", "Days"], ["second", "Seconds"]]
            .map(([value, label]) => `<option value="${value}" ${duration.unit === value ? "selected" : ""}>${label}</option>`).join("")}
        </select>
      </label>
    </div>
    <label class="field"><span>Calendar</span>
      <select name="frame">
        ${calendars.map((frame) => `<option value="${escapeHTML(frame.id)}"
          ${frame.id === relation?.frame ? "selected" : ""}>${escapeHTML(frame.title)}</option>`).join("")}
      </select>
    </label>
    <div class="form-row recurrence-row">
      <label class="field"><span>Repeats</span>
        <select name="repeat">
          ${[["", "Does not repeat"], ["DAILY", "Daily"], ["WEEKDAYS", "Weekdays (Mon–Fri)"], ["WEEKLY", "Weekly"], ["MONTHLY", "Monthly"], ["YEARLY", "Yearly"]]
            .map(([value, label]) => `<option value="${value}" ${originalRecurrenceChoice === value ? "selected" : ""}>${label}</option>`).join("")}
        </select>
      </label>
      <label class="field recurrence-options"><span>Every</span>
        <input name="interval" type="number" min="1" max="999" value="${escapeHTML(recurrence?.rrule?.INTERVAL || "1")}">
      </label>
    </div>
    <label class="field recurrence-options"><span>Ends after</span>
      <input name="count" type="number" min="1" max="10000" value="${escapeHTML(recurrence?.rrule?.COUNT || "")}" placeholder="Leave blank to continue">
    </label>
    <label class="field" data-completed-field><span>Completed at (optional)</span>
      <input name="completed" value="${escapeHTML(relationDate(completed))}">
    </label>
    <label class="field"><span>Description</span>
      <textarea name="description">${escapeHTML(event.payload?.description || "")}</textarea>
    </label>
    <label class="field"><span>Location or meeting link</span>
      <input name="location" value="${escapeHTML(event.payload?.location || "")}" placeholder="Room, address, Teams, Zoomâ€¦">
    </label>
    <div class="form-row">
      <label class="field"><span>Importance</span><select name="importance">
        ${[["standard", "Standard"], ["important", "Important (legacy)"], ["landmark", "Landmark (legacy)"],
          ...importanceFrames.map((frame) => [frame.id, frame.title])]
          .map(([value, label]) => `<option value="${value}" ${importance === value ? "selected" : ""}>${label}</option>`).join("")}
      </select></label>
      <label class="field"><span>Visible in</span><select name="visibility">
        ${[...(importanceFrames.length ? [["importance-frame", "Use importance frame"]] : []),
          ["everywhere", "Every lens"], ["time-signal", "Intimate + Spiral + Radial"], ["planning", "Strategic + Wall + Radial"], ["close", "Intimate + Tactical"]]
          .map(([value, label]) => `<option value="${value}" ${visibility === value ? "selected" : ""}>${label}</option>`).join("")}
      </select></label>
    </div>
    <div class="form-row event-color-row">
      <label class="check-chip"><input type="checkbox" name="useColor" ${event.display?.color ? "checked" : ""}>Override inherited color</label>
      <label class="field"><span>Event color</span><input name="eventColor" type="color" value="${escapeHTML(event.display?.color || "#d4552d")}"></label>
    </div>
    <div class="field"><span>Groups</span>
      <div class="check-row">
        ${groups.map((frame) => `<label class="check-chip" title="${escapeHTML(membershipExplanation(frame.id))}" style="--group-color:${escapeHTML(frame.color || "#2e8b57")}">
          <input type="checkbox" name="groups" value="${escapeHTML(frame.id)}"
            ${memberships.has(frame.id) ? "checked" : ""}>${escapeHTML(frame.title)}
        </label>`).join("") || `<span style="color:var(--faint);font:11px var(--data)">No groups yet.</span>`}
      </div>
      <div class="inline-create">
        <input name="newGroup" placeholder="New group (created on Apply)">
        <input name="newGroupColor" type="color" value="#2e8b57" title="New group color">
      </div>
    </div>
    <details class="advanced-fields">
      <summary>Advanced identity</summary>
      <label class="field"><span>Traits</span>
        <input name="traits" value="${escapeHTML(event.traits.join(", "))}">
      </label>
    </details>
    <div class="inspector-actions">
      <button class="instrument-button primary" type="submit">Save</button>
      ${event.provenance?.pattern ? `<button class="instrument-button" id="edit-series" type="button">Edit series</button>` : ""}
      ${provisionalEvent?.id === eventId ? `<button class="instrument-button" id="cancel-draft" type="button">Cancel</button>` : ""}
      <button class="instrument-button danger" id="delete-object" type="button">Delete</button>
    </div>`;
    const syncRecurrenceFields = () => wrapper.classList.toggle(
      "has-recurrence",
      Boolean(wrapper.elements.repeat.value)
    );
    const syncObjectKind = () => {
      const kind = normalizeObjectKind(wrapper.elements.objectKind.value);
      const definition = OBJECT_KINDS[kind];
      wrapper.querySelector("[data-object-date-label]").textContent = kind === "todo" ? "Observed date" : kind === "note" ? "Pinned date" : "Start date";
      wrapper.querySelector("[data-object-time-label]").textContent = kind === "todo" ? "Observed time" : kind === "note" ? "Pinned time" : "Start time";
      wrapper.querySelector("[data-duration-row]").hidden = definition.zeroDuration;
      wrapper.elements.duration.disabled = definition.zeroDuration;
      wrapper.elements.unit.disabled = definition.zeroDuration;
      wrapper.querySelector("[data-completed-field]").hidden = kind !== "todo";
      wrapper.elements.completed.disabled = kind !== "todo";
    };
    wrapper.elements.repeat.addEventListener("change", syncRecurrenceFields);
    wrapper.elements.objectKind.addEventListener("change", syncObjectKind);
    syncRecurrenceFields();
    syncObjectKind();
    if (provisionalEvent?.id === eventId) {
      provisionalEvent.form = wrapper;
      wrapper.addEventListener("input", () => { if (provisionalEvent?.id === eventId) provisionalEvent.dirty = true; });
      wrapper.addEventListener("change", () => { if (provisionalEvent?.id === eventId) provisionalEvent.dirty = true; });
    }
    openInspector(event.payload?.title || "Event", wrapper);
    if (provisionalEvent?.id === eventId) focusInspectorEditor(eventId);

    wrapper.querySelector("#edit-series")?.addEventListener("click", () => {
      const pattern = chronolog.patterns[event.provenance?.pattern];
      if (pattern?.templateEvent) openEventInspector(pattern.templateEvent);
    });

    wrapper.addEventListener("submit", (inputEvent) => {
      inputEvent.preventDefault();
      const data = new FormData(wrapper);
      try {
        const nextCoordinate = data.get("startDate")
          ? parseDateText(`${data.get("startDate")} ${data.get("startTime") || "00:00"}`)
          : null;
        const dateOnly = !String(data.get("startTime") || "");
        const objectKindChoice = normalizeObjectKind(data.get("objectKind"));
        const completedCoordinate = objectKindChoice === "todo" && data.get("completed")
          ? parseDateText(data.get("completed"))
          : null;
        const repeatChoice = String(data.get("repeat") || "");
        const repeat = repeatChoice === "WEEKDAYS" ? "WEEKLY" : repeatChoice;
        const interval = Math.max(1, Math.min(999, Number(data.get("interval")) || 1));
        const count = String(data.get("count") || "").trim();
        if (repeat && !nextCoordinate) throw new Error("A repeating event needs a start date.");
        const selectedGroups = new Set(data.getAll("groups").map(String));
        const selectedImportance = String(data.get("importance") || "standard");
        if (importanceFrames.some((frame) => frame.id === selectedImportance)) selectedGroups.add(selectedImportance);
        const newGroupTitle = String(data.get("newGroup") || "").trim();
        if (newGroupTitle) {
          const groupId = createId("frame");
          app.executeRecordChange("Create group", "frames", groupId, (documentValue) => {
            documentValue.frames[groupId] = {
              id: groupId,
              title: newGroupTitle,
              traits: ["set", "group"],
              color: String(data.get("newGroupColor") || "#2e8b57")
            };
          });
          selectedGroups.add(groupId);
        }
        app.executeEventChange("Edit event", eventId, (documentValue) => {
          const target = documentValue.events[eventId];
          target.payload ||= {};
          target.payload.title = String(data.get("title") || "(untitled)");
          target.payload.description = String(data.get("description") || "");
          target.payload.location = String(data.get("location") || "");
          target.traits = traitsForObjectKind(
            String(data.get("traits") || "event").split(",").map((item) => item.trim()).filter(Boolean),
            objectKindChoice
          );
          target.traits = target.traits.filter((trait) => !["important", "landmark"].includes(trait));
          const importanceChoice = String(data.get("importance") || "standard");
          if (["important", "landmark"].includes(importanceChoice)) target.traits.push(importanceChoice);
          if (!target.traits.includes("event")) target.traits.unshift("event");
          const visibilityChoice = String(data.get("visibility") || "everywhere");
          const lensSets = {
            "time-signal": ["intimate", "spiral", "radial"],
            planning: ["strategic", "wall", "radial"],
            close: ["intimate", "tactical"]
          };
          target.display = { ...(target.display || {}) };
          if (["everywhere", "importance-frame"].includes(visibilityChoice)) delete target.display.lenses;
          else target.display.lenses = lensSets[visibilityChoice];
          if (data.get("useColor")) target.display.color = String(data.get("eventColor") || "#d4552d");
          else delete target.display.color;
          target.magnitudes ||= {};
          const requiresZero = OBJECT_KINDS[objectKindChoice].zeroDuration || target.traits.includes("terminator");
          target.magnitudes.duration = durationMagnitude(
            requiresZero ? "0" : String(data.get("duration") || "0"),
            String(data.get("unit") || "second")
          );
          const chosenFrame = String(data.get("frame") || session.activeFrame);
          let existing = Object.values(documentValue.relations).find(
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
              existing.parameters = { ...(existing.parameters || {}), dateOnly };
            } else {
              existing = addRelation(documentValue, {
                type: "attachment",
                event: eventId,
                frame: chosenFrame,
                role: target.traits.includes("task") ? "observed" : "placed",
                coordinate: nextCoordinate,
                parameters: { dateOnly }
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
          const existingPattern = Object.values(documentValue.patterns).find(
            (pattern) => pattern.kind === "ics-rrule" && pattern.templateEvent === eventId
          );
          if (!repeat && existingPattern) {
            delete documentValue.patterns[existingPattern.id];
          } else if (repeat) {
            const rrule = { ...(existingPattern?.rrule || {}), FREQ: repeat, INTERVAL: String(interval) };
            if (repeatChoice !== originalRecurrenceChoice) {
              delete rrule.BYDAY;
              delete rrule.BYMONTHDAY;
              delete rrule.BYMONTH;
            }
            if (repeatChoice === "WEEKDAYS") rrule.BYDAY = "MO,TU,WE,TH,FR";
            if (count) rrule.COUNT = String(Math.max(1, Math.min(10000, Number(count) || 1)));
            else delete rrule.COUNT;
            if (existingPattern) {
              existingPattern.rrule = rrule;
              if (existingPattern.rawRule) {
                existingPattern.rawRule = {
                  ...existingPattern.rawRule,
                  value: Object.entries(rrule).map(([key, value]) => `${key}=${value}`).join(";")
                };
                delete existingPattern.rawRule.raw;
                delete existingPattern.rawRule.verbatim;
              }
              existingPattern.appliesTo = [chosenFrame];
              existingPattern.frame = chosenFrame;
              existingPattern.templateRelation = existing?.id;
            } else {
              addPattern(documentValue, {
                title: `${target.payload.title} recurrence`,
                language: "chronolog-formula/1",
                kind: "ics-rrule",
                appliesTo: [chosenFrame],
                frame: chosenFrame,
                templateEvent: eventId,
                templateRelation: existing?.id,
                rrule,
                source: "export fn state(ctx) = {};\nexport fn facts(ctx) = [];",
                exports: { state: "state", facts: "facts" }
              });
            }
          }
        });
        commitProvisionalDraft(eventId);
        dismissInspector();
      } catch (error) {
        app.toast(error.message, true);
      }
    });

    wrapper.querySelector("#delete-object").addEventListener("click", () => {
      const wasProvisional = provisionalEvent?.id === eventId;
      if (wasProvisional) provisionalEvent = null;
      app.executeEventChange("Delete event", eventId, (documentValue) => {
        delete documentValue.events[eventId];
        for (const relationValue of Object.values(documentValue.relations)) {
          if (relationValue.event === eventId) delete documentValue.relations[relationValue.id];
        }
        for (const pattern of Object.values(documentValue.patterns)) {
          if (pattern.templateEvent === eventId) delete documentValue.patterns[pattern.id];
        }
        for (const [id, override] of Object.entries(documentValue.overrides)) {
          if (!override.replacements?.includes(eventId)) continue;
          override.replacements = override.replacements.filter((replacement) => replacement !== eventId);
          if (!override.replacements.length && override.suppress !== true) delete documentValue.overrides[id];
        }
      });
      if (wasProvisional) app.store.endDeferred();
      dismissInspector();
    });

    wrapper.querySelector("#cancel-draft")?.addEventListener("click", () => {
      if (discardProvisionalDraft()) dismissInspector();
    });
    return true;
  }

  function createEventAt(startDay, endDay = startDay, requestedKind = "event") {
    const { session, store } = app;
    resolveProvisionalDraft();
    store.beginDeferred();
    const objectKind = normalizeObjectKind(requestedKind);
    const definition = OBJECT_KINDS[objectKind];
    const eventId = createId("event");
    const relationId = createId("relation");
    const start = Rational.parse(startDay);
    const end = Rational.parse(endDay);
    const orderedStart = start.compare(end) <= 0 ? start : end;
    let orderedEnd = start.compare(end) <= 0 ? end : start;
    if (!definition.zeroDuration && orderedEnd.compare(orderedStart) === 0) {
      orderedEnd = orderedStart.add(session.currentLens() === "intimate"
        ? Rational.parse(session.intimateGrain).div(1440)
        : 1);
    }
    try {
      app.executeEventChange(`Create ${definition.label}`, eventId, (documentValue) => {
        const event = addEvent(documentValue, {
          id: eventId,
          traits: traitsForObjectKind([], objectKind),
          magnitudes: {
            duration: durationMagnitude(
              definition.zeroDuration ? "0" : orderedEnd.sub(orderedStart).mul(86400).toJSON(),
              "second"
            )
          },
          payload: { title: definition.newTitle, description: "", location: "" }
        });
        addRelation(documentValue, {
          id: relationId,
          type: "attachment",
          event: event.id,
          frame: session.activeFrame,
          role: definition.relationRole,
          coordinate: daysToCivilCoordinate(orderedStart)
        });
      }, true);
      provisionalEvent = { id: eventId, dirty: false, form: null };
      if (!openEventInspector(eventId)) {
        discardProvisionalDraft();
        dismissInspector();
      }
    } catch (error) {
      if (provisionalEvent?.id === eventId) discardProvisionalDraft();
      else store.endDeferred();
      app.toast(`Could not create event: ${error.message}`, true);
    }
  }

  byId("close-inspector").addEventListener("click", () => closeInspector());

  return {
    openInspector,
    closeInspector,
    dismissInspector,
    hasProvisionalDraft,
    clearProvisionalDraft,
    resolveProvisionalDraft,
    focusInspectorEditor,
    findVisibleFact,
    prepareMaterialization,
    applyMaterialization,
    revertMaterialization,
    materializationOps,
    openVirtualInspector,
    openEventInspector,
    createEventAt
  };
}
