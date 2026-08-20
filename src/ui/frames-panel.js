import { Rational } from "../exact.js";
import { coordinateLaw } from "../coordinate-law.js";
import {
  buildCoordinateStructure,
  buildFixedCalendarStructure,
  coordinateStructureSummary,
  editableCoordinateStructure,
  editableFixedCalendarStructure,
  transitionChoices
} from "../calendar-structure.js";
import { additiveFrameTraits, frameAuthoringCapabilities, preservedFrameSchema } from "../frame-edit.js";
import { addFrame, addPattern, clone, createId } from "../model.js";
import { mapSnapshot, opsFromMaps } from "../ops.js";
import { stapleReferencesId, withRemappedEnds } from "../staples.js";
import { calendarFrames, groupFrames } from "../projections.js";
import { defaultWeightForNewFrame, resolveAuthoredWeight } from "../weight-formula.js";
import { byId, escapeHTML } from "./dom-helpers.js";

// The Frames workspace: the frame/group/pattern authoring forms, the Frames
// browser (leading frame, companion frames, groups) and the advanced pattern
// browser that share its "object browser" shell. `app` carries the live
// document/session/engine/history plus `framesReturnTarget` (the toolbar
// element to refocus when this panel closes), which `dismissInspector` in
// inspector.js also reads and clears.
export function createFramesPanel(app) {
  // The Frames browser refreshes itself in place, so it reaches for its own card
  // body rather than the single drawer body every panel used to take turns with.
  // A null body simply means that card is not open.
  const framesBody = () => app.dockCardBody("panel:frames-browser");

  function frameKind(frame) {
    if (frame?.traits?.includes("calendar")) return "calendar";
    if (frame?.traits?.includes("importance")) return "importance";
    if (frame?.traits?.includes("group")) return "group";
    if (frame?.traits?.includes("cycle")) return "cycle";
    if (frame?.traits?.includes("line") || frame?.traits?.includes("timeline")) return "line";
    if (frame?.traits?.includes("measure")) return "measure";
    return "other";
  }

  function frameKindTraits(kind, existing = []) {
    return additiveFrameTraits(kind, [], existing);
  }

  function duplicateFrame(frameId) {
    const { chronolog, history } = app;
    const source = chronolog.frames[frameId];
    if (!source) return;
    const nextId = createId("frame");
    const nextFrame = {
      ...clone(source),
      id: nextId,
      title: `${source.title} copy`,
      display: { ...(source.display || {}), mode: "standalone", order: Number(source.display?.order || 0) + 1 }
    };
    const relationMap = new Map();
    const relations = [];
    for (const relation of Object.values(chronolog.relations)) {
      // A staple names its frames on its ENDS, so it is invisible to the three
      // field checks below and has to be asked for directly -- otherwise the copy
      // silently loses every connection into the frame it was copied from.
      const isStaple = relation.type === "staple" && stapleReferencesId(relation, frameId);
      if (!isStaple && relation.frame !== frameId && relation.parent !== frameId && relation.child !== frameId) continue;
      const id = createId("relation");
      relationMap.set(relation.id, id);
      if (isStaple) {
        relations.push({ ...clone(withRemappedEnds(relation, new Map([[frameId, nextId]]))), id });
        continue;
      }
      relations.push({
        ...clone(relation), id,
        frame: relation.frame === frameId ? nextId : relation.frame,
        parent: relation.parent === frameId ? nextId : relation.parent,
        child: relation.child === frameId ? nextId : relation.child
      });
    }
    const patterns = Object.values(chronolog.patterns).filter((pattern) =>
      pattern.frame === frameId || pattern.appliesTo?.includes(frameId)
    ).map((pattern) => ({
      ...clone(pattern),
      id: createId("pattern"),
      title: `${pattern.title || "Pattern"} copy`,
      frame: pattern.frame === frameId ? nextId : pattern.frame,
      appliesTo: pattern.appliesTo?.map((id) => id === frameId ? nextId : id),
      templateRelation: relationMap.get(pattern.templateRelation) || pattern.templateRelation
    }));
    // The set of records a duplicate creates depends on how many relations and
    // patterns reference the source frame, so an identity diff over the maps
    // is more robust here than enumerating explicit ops by hand.
    const before = mapSnapshot(chronolog);
    const metadata = {};
    history.executeDelta("Duplicate frame", (documentValue) => {
      documentValue.frames[nextId] = clone(nextFrame);
      for (const relation of relations) documentValue.relations[relation.id] = clone(relation);
      for (const pattern of patterns) documentValue.patterns[pattern.id] = clone(pattern);
      const after = mapSnapshot(documentValue);
      Object.assign(metadata, { ops: opsFromMaps(before, after), inverseOps: opsFromMaps(after, before) });
    }, (documentValue) => {
      delete documentValue.frames[nextId];
      for (const relation of relations) delete documentValue.relations[relation.id];
      for (const pattern of patterns) delete documentValue.patterns[pattern.id];
    }, metadata);
    openFrameInspector(nextId);
  }

  function observedBoundaryId(label, index = 0) {
    const normalized = String(label || "").trim().toLowerCase()
      .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
    return normalized || `boundary-${Number(index) + 1}`;
  }

  function observedBoundaryRow(boundary = {}, index = 0) {
    const label = String(boundary.label || boundary.id || "");
    return `<div class="observed-boundary-row" data-observed-boundary>
    <input aria-label="Boundary ${index + 1} coordinate" name="observedBoundaryAt" value="${escapeHTML(boundary.at || "")}" placeholder="Exact coordinate, e.g. 29.530588853">
    <input aria-label="Boundary ${index + 1} label" name="observedBoundaryLabel" value="${escapeHTML(label)}" placeholder="New moon">
    <input aria-label="Boundary ${index + 1} event ID" name="observedBoundaryEvent" value="${escapeHTML(boundary.event || "")}" placeholder="Optional event ID">
    <span class="observed-boundary-buttons"><button type="button" aria-label="Move boundary ${index + 1} earlier" title="Move earlier" data-move-observed-up>↑</button><button type="button" aria-label="Move boundary ${index + 1} later" title="Move later" data-move-observed-down>↓</button><button type="button" aria-label="Remove boundary ${index + 1}" title="Remove" data-remove-observed-boundary>×</button></span>
  </div>`;
  }

  function validateEventDefinedBoundaryDraft(boundaries) {
    if (boundaries.length < 2) throw new Error("An observed series needs at least two boundaries.");
    const ids = new Set();
    let prior = null;
    for (const boundary of boundaries) {
      if (!boundary.id) throw new Error("Every observed boundary needs a label or ID.");
      if (ids.has(boundary.id)) throw new Error(`Boundary labels/IDs must be unique (${boundary.id}).`);
      ids.add(boundary.id);
      let current;
      try { current = Rational.parse(boundary.at); }
      catch { throw new Error(`Boundary ${boundary.id} needs an exact finite coordinate.`); }
      if (prior && current.compare(prior) <= 0) throw new Error("Observed boundaries must be in strictly increasing order.");
      prior = current;
    }
  }

  // --- The calendar-structure section ---------------------------------------
  //
  // Levels, radices, transitions, names and cycles, edited as the DECLARATION
  // the coordinate engine executes (src/coordinate-law.js). Wall Time gets this
  // section because Wall Time is what every derived calendar inherits, and a
  // frame that only inherits gets it too -- behind an explicit override toggle,
  // so opening the form on a derived calendar never silently detaches it from
  // its basis.
  function structureLevelRow(level = {}, index = 0, choices = []) {
    const transition = String(level.transition || "");
    return `<div class="structure-level-row" data-structure-level>
      <input aria-label="Level ${index + 1} name" name="structureLevelName" value="${escapeHTML(level.name || "")}" placeholder="hour">
      ${index === 0
        ? "<span class=\"calendar-root-note\">top-level unit</span>"
        : `<select aria-label="${escapeHTML(level.name || `Level ${index + 1}`)} counting rule" name="structureLevelTransition">${choices.map((choice) =>
            `<option value="${escapeHTML(choice.value)}" ${choice.value === transition ? "selected" : ""}>${escapeHTML(choice.label)}</option>`).join("")}</select>`}
      ${index === 0 ? "" : `<input aria-label="${escapeHTML(level.name || `Level ${index + 1}`)} count" name="structureLevelCount" inputmode="numeric" value="${escapeHTML(level.count || "")}" placeholder="24">`}
      <input aria-label="${escapeHTML(level.name || `Level ${index + 1}`)} names" name="structureLevelNames" value="${escapeHTML(level.names || "")}" placeholder="Optional names, comma-separated">
      <span class="structure-row-buttons"><button type="button" aria-label="Move level ${index + 1} up" title="Move up" data-move-level-up>↑</button><button type="button" aria-label="Move level ${index + 1} down" title="Move down" data-move-level-down>↓</button><button type="button" aria-label="Remove level ${index + 1}" title="Remove" data-remove-level>×</button></span>
    </div>`;
  }

  function structureCycleRow(cycle = {}, index = 0) {
    return `<div class="structure-cycle-row" data-structure-cycle>
      <input aria-label="Cycle ${index + 1} name" name="structureCycleName" value="${escapeHTML(cycle.name || "")}" placeholder="weekday">
      <input aria-label="Cycle ${index + 1} length" name="structureCycleLength" inputmode="numeric" value="${escapeHTML(cycle.length || "")}" placeholder="7">
      <input aria-label="Cycle ${index + 1} phase" name="structureCyclePhase" inputmode="numeric" value="${escapeHTML(cycle.phase ?? "0")}" placeholder="0">
      <input aria-label="Cycle ${index + 1} names" name="structureCycleNames" value="${escapeHTML(cycle.names || "")}" placeholder="Sunday, Monday, …">
      <span class="structure-row-buttons"><button type="button" aria-label="Remove cycle ${index + 1}" title="Remove" data-remove-cycle>×</button></span>
    </div>`;
  }

  function frameForm(frame = null, presetKind = "group", embedded = false) {
    const { chronolog } = app;
    const isNew = !frame;
    // A newly created group or importance frame defaults to a `w * 1.5`
    // promotion (LEXICON.md: "Groups should probably default to a ... *1.5
    // ... so events that cross more frames default to being more
    // prominent") -- see `defaultWeightForNewFrame`'s own note on why this
    // is deliberately narrower than a blanket default for every frame kind.
    // This only ever seeds a fresh form's initial value; an existing record
    // (`frame` truthy) never reaches this branch at all.
    const newFrameWeight = defaultWeightForNewFrame(presetKind);
    const value = frame || {
      id: "", title: `New ${presetKind}`, traits: frameKindTraits(presetKind),
      basis: "", color: "#2e8b57", coordinate: null, period: null,
      display: newFrameWeight === undefined ? {} : { weight: newFrameWeight }
    };
    const recordId = value.id || createId("frame");
    const kind = isNew ? presetKind : frameKind(value);
    const capabilities = frameAuthoringCapabilities(kind, value.traits);
    const frameLenses = ["intimate", "tactical", "strategic", "wall", "lines", "spiral", "radial"];
    const visibleFrameLenses = new Set(value.display?.lenses || frameLenses);
    const fixedCalendar = editableFixedCalendarStructure(value);
    const observedCalendar = value.period?.kind === "event-defined" ? value.period : null;
    // The law in force, whether written on this frame or inherited through its
    // basis, plus whether this frame authored it. Showing the effective values
    // is the point: an author overriding weekday names needs to see the names
    // actually in use, not an empty grid.
    const ownsStructure = Array.isArray(value.coordinate?.levels) && value.coordinate.levels.length > 0;
    let structureLaw = null;
    let structureError = null;
    try {
      structureLaw = value.id && chronolog.frames[value.id]
        ? coordinateLaw(chronolog, value.id)
        : null;
    } catch (error) {
      structureError = error.message;
    }
    const structure = structureLaw ? editableCoordinateStructure(structureLaw) : null;
    const structureChoices = transitionChoices();
    const calendarUnits = fixedCalendar?.units || [
      { name: "year" }, { name: "month", perParent: "12" }, { name: "week", perParent: "4" }, { name: "day", perParent: "7" }
    ];
    const fixedRows = calendarUnits.map((unit, index) => `<div class="calendar-unit-row">
      <input aria-label="Unit ${index + 1} name" name="calendarUnitName" value="${escapeHTML(unit.name)}">
      ${index === 0 ? "<span class=\"calendar-root-note\">top-level cycle</span>" : `<input aria-label="${escapeHTML(unit.name)} per parent" name="calendarUnitRadix" inputmode="numeric" value="${escapeHTML(unit.perParent)}"><input aria-label="${escapeHTML(unit.name)} names" name="calendarUnitLabels" value="${escapeHTML(unit.labels || "")}" placeholder="Optional names, comma-separated">`}
    </div>`).join("");
    const observedRows = (observedCalendar?.boundaries || [
      { id: "boundary-1", at: "0", label: "Start" },
      { id: "boundary-2", at: "1", label: "Next boundary" }
    ]).map((boundary, index) => observedBoundaryRow(boundary, index)).join("");
    const wrapper = document.createElement("form");
    wrapper.className = "frame-form";
    const options = (items, selected) => items.map(([id, label]) =>
      `<option value="${id}" ${id === selected ? "selected" : ""}>${label}</option>`).join("");
    wrapper.innerHTML = `
    <div class="frame-type-banner"><strong>${escapeHTML(value.title)}</strong><span>${kind}</span></div>
    <label class="field"><span>Title</span><input name="title" value="${escapeHTML(value.title)}" required></label>
    <div class="form-row">
      <label class="field"><span>Frame type / add capability</span><select name="kind">${options([
        ["calendar", "Calendar / timeline"], ["group", "Group"], ["importance", "Importance"], ["cycle", "Cycle"],
        ["line", "Line"], ["measure", "Measure"], ["other", "Other"]
      ], kind)}</select><small>This adds a capability; it never removes the frame's existing traits.</small></label>
      <label class="field"><span>Color</span><input name="color" type="color" value="${escapeHTML(value.color || "#2e8b57")}"></label>
    </div>
    <div class="form-row">
      <label class="field"><span>Display weight</span><input name="displayWeight" type="text" inputmode="decimal" value="${escapeHTML(String(value.display?.weight ?? 1))}" placeholder="1"></label>
    </div>
    <p class="field-note">A frame is a group: this reshapes the derived Strategic-promotion/importance weight of every event that belongs to it -- calendars, groups, and importance sets alike -- through a formula written in one variable, <code>w</code>, the weight arriving from everything else the event belongs to. A plain number <code>n</code> is shorthand for <code>w * n</code>; 1 (or <code>w</code>, or blank) is neutral and changes nothing. A formula may use <code>+ - * / ^</code>, parentheses, and standard precedence: <code>w + 0.5</code> adds a fixed bonus, <code>w * 1.5</code> scales it, <code>(w + 1) * 2</code> groups explicitly. Every frame the event belongs to applies its own formula in turn, including nested group membership; an invalid formula changes nothing.</p>
    ${kind === "group" ? `<div class="form-row">
      <label class="field"><span>Strategic</span><select name="strategic">${options([
        ["auto", "Automatic"], ["show", "Promote to name"], ["hide", "Demote / hide"]
      ], value.display?.strategic || "auto")}</select></label>
    </div>` : ""}
    ${kind === "importance" ? `<div class="form-row">
      <label class="field"><span>Level</span><select name="importanceLevel">${options([
        ["important", "Important"], ["landmark", "Landmark"], ["standard", "Standard"]
      ], value.display?.importance || "important")}</select></label>
      <label class="field"><span>Smallest radial cycle (days)</span><input name="radialMinDays" type="number" min="0" step="0.25" value="${escapeHTML(value.display?.radialMinDays ?? "")}" placeholder="Any"></label>
      <label class="field"><span>Largest radial cycle (days)</span><input name="radialMaxDays" type="number" min="0" step="0.25" value="${escapeHTML(value.display?.radialMaxDays ?? "")}" placeholder="Any"></label>
    </div>` : ""}
    <div class="field"><span>Visible in lenses</span><div class="check-row frame-lens-checks">
      ${frameLenses.map((lens) => `<label class="check-chip"><input type="checkbox" name="frameLenses" value="${lens}" ${visibleFrameLenses.has(lens) ? "checked" : ""}>${lens}</label>`).join("")}
    </div><small>Unchecked lenses hide events governed by this frame.</small></div>
    <p class="field-note">Choose what appears together from Frames while viewing a calendar. This editor changes the frame itself; group membership and cross-frame mappings are separate authored objects.</p>
    ${capabilities.basis ? `<label class="field"><span>Basis frame</span><select name="basis"><option value="">None</option>${Object.values(chronolog.frames)
      .filter((item) => item.id !== value.id).map((item) => `<option value="${escapeHTML(item.id)}" ${item.id === value.basis ? "selected" : ""}>${escapeHTML(item.title)} · ${frameKind(item)}</option>`).join("")}</select></label>` : `<p class="field-note capability-boundary-note">Groups and importance sets organize membership and display priority; they do not own coordinates, basis frames, or cycle periods.</p>`}
    ${capabilities.calendarStructure ? `<details class="calendar-structure coordinate-structure" ${ownsStructure || structureError ? "open" : ""}>
      <summary>Calendar structure</summary>
      <p class="field-note">The levels, counting rules, names and cycles below <em>are</em> the coordinate law: this is what the engine executes, so an hour count changed here changes how long an hour is everywhere. A level counts a fixed number of its children, or defers to a named transition for a count that varies. Names are optional and go one per child.</p>
      ${structureError ? `<output class="calendar-period-preview structure-error">${escapeHTML(structureError)}</output>` : ""}
      ${ownsStructure ? "" : `<label class="check-chip calendar-structure-toggle"><input type="checkbox" name="useOwnStructure">Author this structure on this frame</label>
      <small>${value.basis ? `This frame inherits its structure. Turning this on copies the inherited law onto this frame so it can be changed here; the frame keeps its basis for everything else.` : "This frame has no structure of its own yet."}</small>`}
      <div class="structure-fields" data-structure-fields>
        <div class="structure-level-heading"><span>Level</span><span>Counting rule</span><span>Count</span><span>Names of each child</span><span></span></div>
        <div class="structure-levels" data-structure-levels>${(structure?.levels || []).map((level, index) => structureLevelRow(level, index, structureChoices)).join("")}</div>
        <div class="inline-actions"><button class="instrument-button" type="button" data-add-level>Add level</button></div>
        <p class="field-note">A <strong>cycle</strong> repeats over the base unit without nesting in anything: seven weekdays run straight through month and year boundaries, so weekday names belong here rather than on a level. <em>Phase</em> is which name lands on day zero.</p>
        <div class="structure-cycle-heading"><span>Cycle</span><span>Length</span><span>Phase</span><span>Names in order</span><span></span></div>
        <div class="structure-cycles" data-structure-cycles>${(structure?.cycles || []).map((cycle, index) => structureCycleRow(cycle, index)).join("")}</div>
        <div class="inline-actions"><button class="instrument-button" type="button" data-add-cycle>Add cycle</button></div>
        <div class="form-row structure-uniform-fields">
          <label class="field"><span>Base unit</span><select name="structureBaseLevel" data-structure-base-level><option value="">Infer automatically</option></select></label>
          <label class="field"><span>Origin (exact day ordinal)</span><input name="structureOrigin" value="${escapeHTML(structure?.origin || "")}" placeholder="0"></label>
        </div>
        <p class="field-note">Only needed for a wholly invented, uniform ladder that no registered calendar family recognizes: <strong>base unit</strong> says which level above is one day, and <strong>origin</strong> says the exact day ordinal its first unit begins on. Leave both blank for an ordinary calendar built from a registered transition (Gregorian months/days, and the like).</p>
        <output class="calendar-period-preview" data-structure-preview></output>
      </div>
    </details>` : ""}
    ${capabilities.fixedCalendar ? `<details class="calendar-structure" ${fixedCalendar ? "open" : ""}>
      <summary>Fixed calendar structure</summary>
      <label class="check-chip calendar-structure-toggle"><input type="checkbox" name="useFixedCalendar" ${fixedCalendar ? "checked" : ""}>Use a regular unit hierarchy</label>
      <small>For ordinary calendars with a constant number of units at every level. This writes exact values; leave it off to retain an unusual or rule-driven coordinate system.</small>
      <div class="calendar-units" data-fixed-calendar-fields>
        <div class="calendar-unit-heading"><span>Unit name</span><span>Count</span><span>Names within parent</span></div>
        ${fixedRows}
        <label class="field"><span>Smallest unit length in Earth days</span><input name="smallestUnitDays" value="${escapeHTML(fixedCalendar?.smallestUnitDays || "1")}" placeholder="1"></label>
        <label class="field"><span>Epoch in Earth days</span><input name="fixedCalendarEpoch" value="${escapeHTML(fixedCalendar?.epochDays || "0")}" placeholder="0"></label>
        <output class="calendar-period-preview" data-fixed-calendar-preview>${fixedCalendar ? `One ${escapeHTML(fixedCalendar.units[0].name)} = ${escapeHTML(fixedCalendar.totalDays)} Earth days.` : "Turn this on to replace the coordinate JSON with a regular hierarchy."}</output>
      </div>
    </details>` : ""}
    ${capabilities.observedBoundaries ? `<details class="calendar-structure observed-calendar-structure" ${observedCalendar ? "open" : ""}>
      <summary>Observed boundary series</summary>
      <p class="field-note">Defines a cycle whose length is <em>measured</em>, not computed — for example a lunar month, authored from a series of observed new moons, rather than a fixed 29.5-day approximation. Each authored boundary marks where one interval ends and the next begins; there is no cycle outside this series.</p>
      <label class="check-chip calendar-structure-toggle"><input type="checkbox" name="useObservedCalendar" ${observedCalendar ? "checked" : ""}>Use explicitly observed boundaries</label>
      <small>For irregular cycles such as lunar observations or story-time jumps. Each adjacent pair is one authored interval, in strictly increasing order. ChronoLog never averages, fills gaps, or extrapolates past the last authored boundary.</small>
      <div class="observed-calendar-fields" data-observed-calendar-fields>
        <label class="field"><span>Boundary measurement frame</span><select name="observedBoundaryFrame">
          ${Object.values(chronolog.frames).filter((item) => item.id !== recordId).map((item) => `<option value="${escapeHTML(item.id)}" ${item.id === observedCalendar?.frame ? "selected" : ""}>${escapeHTML(item.title)} · ${frameKind(item)}</option>`).join("")}
        </select></label>
        <div class="observed-boundary-heading"><span>Coordinate</span><span>Label / ID</span><span>Observed event ID (optional)</span><span></span></div>
        <div class="observed-boundaries" data-observed-boundaries>${observedRows}</div>
        <div class="inline-actions observed-boundary-actions"><button class="instrument-button" type="button" data-add-observed-boundary>Add boundary</button><button class="instrument-button" type="button" data-import-observed-boundaries>Import timestamps</button></div>
        <label class="field observed-import"><span>Import text</span><textarea name="observedImport" placeholder="One boundary per line: coordinate, label (optional), event ID (optional)"></textarea></label>
        <output class="calendar-period-preview" data-observed-calendar-preview></output>
      </div>
    </details>` : ""}
    ${capabilities.coordinate ? `<p class="field-note coordinate-definition-note">A coordinate definition names positions inside this frame. It does not establish a conversion to another frame; author those relationships as mappings.</p>` : ""}
    <details class="advanced-fields"><summary>Advanced frame data</summary>
      ${capabilities.periodData ? `<label class="field"><span>Cycle period data (JSON)</span><textarea name="period" class="code" placeholder="Leave blank to preserve existing period">${escapeHTML(value.period ? JSON.stringify(value.period, null, 2) : "")}</textarea></label>` : ""}
      <label class="field"><span>Traits</span><input name="traits" value="${escapeHTML(value.traits.join(", "))}"></label>
      ${capabilities.coordinate ? `<label class="field"><span>Coordinate nesting (JSON)</span><textarea name="coordinate" class="code">${escapeHTML(value.coordinate ? JSON.stringify(value.coordinate, null, 2) : "")}</textarea><small>The escape hatch for shapes the Calendar structure grid cannot express. Typing here overrides the grid on apply.</small></label>` : ""}
    </details>
    <div class="inspector-actions"><button class="instrument-button primary" type="submit">${isNew ? "Create" : "Apply"}</button>
      ${isNew ? "" : `<button class="instrument-button" id="duplicate-object" type="button">Duplicate</button><button class="instrument-button danger" id="delete-object" type="button">Remove</button>`}</div>`;
    const initialCoordinateText = value.coordinate ? JSON.stringify(value.coordinate, null, 2) : "";
    function coordinateTextEdited(data) {
      return String(data.get("coordinate") ?? "").trim() !== initialCoordinateText.trim();
    }
    const structureFields = wrapper.querySelector("[data-structure-fields]");
    const structureLevels = wrapper.querySelector("[data-structure-levels]");
    const structureCycles = wrapper.querySelector("[data-structure-cycles]");
    const structurePreview = wrapper.querySelector("[data-structure-preview]");
    const ownStructureToggle = wrapper.elements.useOwnStructure;
    function readRows(container, selector, fields) {
      if (!container) return [];
      return [...container.querySelectorAll(selector)].map((row) => Object.fromEntries(
        Object.entries(fields).map(([key, name]) => [key, String(row.querySelector(`[name="${name}"]`)?.value ?? "").trim()])
      ));
    }
    function structureDraft() {
      return {
        kind: value.coordinate?.kind || (value.traits?.includes("gregorian") ? "gregorian" : "nested"),
        previous: value.coordinate || null,
        levels: readRows(structureLevels, "[data-structure-level]", {
          name: "structureLevelName",
          transition: "structureLevelTransition",
          count: "structureLevelCount",
          names: "structureLevelNames"
        }),
        cycles: readRows(structureCycles, "[data-structure-cycle]", {
          name: "structureCycleName",
          length: "structureCycleLength",
          phase: "structureCyclePhase",
          names: "structureCycleNames"
        }),
        baseLevel: String(wrapper.elements.structureBaseLevel?.value || "").trim(),
        origin: String(wrapper.elements.structureOrigin?.value || "").trim()
      };
    }
    // Authoring the structure is only in force when this frame owns it, so a
    // derived calendar whose form was merely opened is never silently detached
    // from its basis.
    function structureAuthored() {
      return Boolean(structureFields) && (ownsStructure || Boolean(ownStructureToggle?.checked));
    }
    // The base-unit choices are the CURRENTLY TYPED level names, not the law's
    // levels at open time: renaming or reordering a level while authoring must
    // be reflected here immediately, or the select silently offers a name that
    // no longer exists. The one exception is the value an author is mid-edit
    // toward -- kept as a trailing option rather than dropped -- so picking a
    // base level is never undone by a keystroke in an unrelated field.
    function refreshBaseLevelOptions() {
      const select = wrapper.elements.structureBaseLevel;
      if (!select) return;
      const current = select.options.length ? select.value : (structure?.baseLevel || "");
      const names = [...structureLevels.querySelectorAll('[name="structureLevelName"]')]
        .map((input) => String(input.value || "").trim())
        .filter(Boolean);
      select.innerHTML = `<option value="">Infer automatically</option>`
        + names.map((name) => `<option value="${escapeHTML(name)}" ${name === current ? "selected" : ""}>${escapeHTML(name)}</option>`).join("")
        + (current && !names.includes(current)
          ? `<option value="${escapeHTML(current)}" selected>${escapeHTML(current)} (not a current level)</option>`
          : "");
    }
    function refreshStructurePreview() {
      if (!structureFields || !structurePreview) return;
      refreshBaseLevelOptions();
      const enabled = structureAuthored();
      for (const field of structureFields.querySelectorAll("input, select, button")) field.disabled = !enabled;
      if (!enabled) {
        structurePreview.textContent = "This frame inherits the structure shown above. Turn on authoring to change it here.";
        return;
      }
      try {
        structurePreview.textContent = coordinateStructureSummary(buildCoordinateStructure(structureDraft()));
      } catch (error) {
        structurePreview.textContent = error.message;
      }
    }
    ownStructureToggle?.addEventListener("change", refreshStructurePreview);
    structureFields?.addEventListener("input", refreshStructurePreview);
    structureFields?.addEventListener("change", refreshStructurePreview);
    structureLevels?.addEventListener("click", (click) => {
      const row = click.target.closest("[data-structure-level]");
      if (!row) return;
      if (click.target.matches("[data-remove-level]")) row.remove();
      if (click.target.matches("[data-move-level-up]") && row.previousElementSibling) structureLevels.insertBefore(row, row.previousElementSibling);
      if (click.target.matches("[data-move-level-down]") && row.nextElementSibling) structureLevels.insertBefore(row.nextElementSibling, row);
      refreshStructurePreview();
    });
    structureCycles?.addEventListener("click", (click) => {
      const row = click.target.closest("[data-structure-cycle]");
      if (row && click.target.matches("[data-remove-cycle]")) row.remove();
      refreshStructurePreview();
    });
    wrapper.querySelector("[data-add-level]")?.addEventListener("click", () => {
      structureLevels?.insertAdjacentHTML("beforeend", structureLevelRow({}, structureLevels.children.length, structureChoices));
      refreshStructurePreview();
    });
    wrapper.querySelector("[data-add-cycle]")?.addEventListener("click", () => {
      structureCycles?.insertAdjacentHTML("beforeend", structureCycleRow({}, structureCycles.children.length));
      refreshStructurePreview();
    });
    refreshStructurePreview();
    const fixedCalendarToggle = wrapper.elements.useFixedCalendar;
    const fixedCalendarFields = wrapper.querySelector("[data-fixed-calendar-fields]");
    // Addressed by its own data key, not by the shared preview class: three
    // sections now render a `.calendar-period-preview`, and a class selector
    // would silently bind whichever one happens to come first in the markup.
    const fixedCalendarPreview = wrapper.querySelector("[data-fixed-calendar-preview]");
    function fixedCalendarDraft(data = new FormData(wrapper)) {
      const names = data.getAll("calendarUnitName");
      const radices = data.getAll("calendarUnitRadix");
      const labels = data.getAll("calendarUnitLabels");
      return {
        units: names.map((name, index) => ({
          name: String(name),
          perParent: index ? String(radices[index - 1] || "") : undefined,
          labels: index ? String(labels[index - 1] || "") : ""
        })),
        smallestUnitDays: String(data.get("smallestUnitDays") || ""),
        epochDays: String(data.get("fixedCalendarEpoch") || "0"),
        periodFrame: (chronolog.frames[recordId] || value).period?.frame || "measure:human-time"
      };
    }
    function refreshFixedCalendarPreview() {
      if (!fixedCalendarToggle || !fixedCalendarFields || !fixedCalendarPreview) return;
      const enabled = fixedCalendarToggle.checked;
      for (const input of fixedCalendarFields.querySelectorAll("input")) input.disabled = !enabled;
      if (!enabled) {
        fixedCalendarPreview.textContent = "Leave this off to retain the existing coordinate and period data.";
        return;
      }
      try {
        const built = buildFixedCalendarStructure(fixedCalendarDraft());
        fixedCalendarPreview.textContent = `One ${built.coordinate.fixed.units[0].name} = ${built.totalDays} Earth days (exact).`;
      } catch (error) {
        fixedCalendarPreview.textContent = error.message;
      }
    }
    fixedCalendarToggle?.addEventListener("change", refreshFixedCalendarPreview);
    fixedCalendarFields?.addEventListener("input", refreshFixedCalendarPreview);
    refreshFixedCalendarPreview();
    const observedCalendarToggle = wrapper.elements.useObservedCalendar;
    const observedCalendarFields = wrapper.querySelector("[data-observed-calendar-fields]");
    const observedBoundaries = wrapper.querySelector("[data-observed-boundaries]");
    const observedPreview = wrapper.querySelector("[data-observed-calendar-preview]");
    function observedBoundaryDraft() {
      if (!observedBoundaries) return [];
      return [...observedBoundaries.querySelectorAll("[data-observed-boundary]")].map((row, index) => ({
        label: String(row.querySelector('[name="observedBoundaryLabel"]')?.value || "").trim(),
        id: observedBoundaryId(String(row.querySelector('[name="observedBoundaryLabel"]')?.value || ""), index),
        at: String(row.querySelector('[name="observedBoundaryAt"]')?.value || "").trim(),
        event: String(row.querySelector('[name="observedBoundaryEvent"]')?.value || "").trim() || undefined
      }));
    }
    function refreshObservedCalendarPreview() {
      if (!observedCalendarToggle || !observedCalendarFields || !observedPreview) return;
      const enabled = observedCalendarToggle.checked;
      for (const input of observedCalendarFields.querySelectorAll("input, select, textarea, button")) input.disabled = !enabled;
      if (!enabled) { observedPreview.textContent = "Leave this off to preserve existing period data or use a regular hierarchy."; return; }
      try {
        const boundaries = observedBoundaryDraft();
        if (boundaries.length < 2) throw new Error("Add at least two boundaries.");
        const seen = new Set();
        let prior = null;
        for (const boundary of boundaries) {
          if (!boundary.at) throw new Error("Every boundary needs an exact coordinate.");
          if (seen.has(boundary.id)) throw new Error(`Boundary labels/IDs must be unique (${boundary.id}).`);
          seen.add(boundary.id);
          const current = Rational.parse(boundary.at);
          if (prior && current.compare(prior) <= 0) throw new Error("Boundaries must be in strictly increasing order. Reorder or correct them.");
          prior = current;
        }
        observedPreview.textContent = `${boundaries.length} authored boundaries define ${boundaries.length - 1} finite intervals. No interval exists outside this range.`;
      } catch (error) { observedPreview.textContent = error.message; }
    }
    function appendObservedBoundary(boundary = {}) {
      if (!observedBoundaries) return;
      observedBoundaries.insertAdjacentHTML("beforeend", observedBoundaryRow(boundary, observedBoundaries.children.length));
      refreshObservedCalendarPreview();
    }
    observedCalendarToggle?.addEventListener("change", () => {
      if (observedCalendarToggle.checked && fixedCalendarToggle) fixedCalendarToggle.checked = false;
      refreshFixedCalendarPreview(); refreshObservedCalendarPreview();
    });
    fixedCalendarToggle?.addEventListener("change", () => {
      if (fixedCalendarToggle.checked && observedCalendarToggle) observedCalendarToggle.checked = false;
      refreshObservedCalendarPreview();
    });
    observedBoundaries?.addEventListener("input", refreshObservedCalendarPreview);
    observedBoundaries?.addEventListener("click", (click) => {
      const row = click.target.closest("[data-observed-boundary]");
      if (!row) return;
      if (click.target.matches("[data-remove-observed-boundary]")) row.remove();
      if (click.target.matches("[data-move-observed-up]") && row.previousElementSibling) observedBoundaries.insertBefore(row, row.previousElementSibling);
      if (click.target.matches("[data-move-observed-down]") && row.nextElementSibling) observedBoundaries.insertBefore(row.nextElementSibling, row);
      refreshObservedCalendarPreview();
    });
    wrapper.querySelector("[data-add-observed-boundary]")?.addEventListener("click", () => appendObservedBoundary());
    wrapper.querySelector("[data-import-observed-boundaries]")?.addEventListener("click", () => {
      const lines = String(wrapper.elements.observedImport.value || "").split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
      if (!lines.length) { app.toast("Enter one timestamp per line to import.", true); return; }
      observedBoundaries.innerHTML = "";
      for (const [index, line] of lines.entries()) {
        const [at = "", label = "", event = ""] = line.split(",").map((part) => part.trim());
        appendObservedBoundary({ at, label, id: observedBoundaryId(label, index), event });
      }
      refreshObservedCalendarPreview();
    });
    refreshObservedCalendarPreview();
    wrapper.addEventListener("submit", (event) => {
      event.preventDefault();
      const data = new FormData(wrapper);
      try {
        app.executeRecordChange(isNew ? "Create frame" : "Edit frame", "frames", recordId, (documentValue) => {
          const selectedKind = String(data.get("kind") || "other");
          const priorDisplay = documentValue.frames[recordId]?.display || {};
          const display = { ...priorDisplay, ...(data.has("strategic") ? { strategic: String(data.get("strategic") || "auto") } : {}) };
          const selectedLenses = data.getAll("frameLenses").map(String);
          if (selectedLenses.length === frameLenses.length) delete display.lenses;
          else display.lenses = selectedLenses;
          // Sugar (a plain number) or a full `chronolog-formula/1` formula --
          // `resolveAuthoredWeight` is the one place that decision is made
          // and validated, including the storage-economy rule that identity
          // input deletes the field rather than storing a no-op formula.
          const resolvedWeight = resolveAuthoredWeight(app.engine.runtime, data.get("displayWeight"));
          if (resolvedWeight === undefined) delete display.weight;
          else display.weight = resolvedWeight;
          if (data.has("importanceLevel")) {
            display.importance = String(data.get("importanceLevel") || "important");
            if (String(data.get("radialMinDays") || "").trim()) display.radialMinDays = Number(data.get("radialMinDays"));
            else delete display.radialMinDays;
            if (String(data.get("radialMaxDays") || "").trim()) display.radialMaxDays = Number(data.get("radialMaxDays"));
            else delete display.radialMaxDays;
          }
          const existing = documentValue.frames[recordId] || {};
          const schema = !capabilities.coordinate
            ? { coordinate: undefined, period: undefined }
            : data.has("useObservedCalendar")
            ? (() => {
                const boundaries = observedBoundaryDraft().map((boundary) => ({
                  id: boundary.id, at: boundary.at, ...(boundary.label ? { label: boundary.label } : {}),
                  ...(boundary.event ? { event: boundary.event } : {})
                }));
                // Validate before storing so a malformed series never replaces a valid one.
                validateEventDefinedBoundaryDraft(boundaries);
                const boundaryFrame = String(data.get("observedBoundaryFrame") || "");
                if (!boundaryFrame) throw new Error("Choose the frame that measures observed boundaries.");
                return { coordinate: existing.coordinate, period: { kind: "event-defined", frame: boundaryFrame, boundaries } };
              })()
            : data.has("useFixedCalendar")
            ? (() => {
                const built = buildFixedCalendarStructure({ ...fixedCalendarDraft(data), periodFrame: existing.period?.frame || "measure:human-time" });
                return { coordinate: built.coordinate, period: built.period };
              })()
            // A hand edit to the raw JSON escape hatch outranks the structure
            // grid: the grid cannot express a formula law or a builder block, so
            // whoever typed JSON meant it. Without this the grid would silently
            // discard the typed text, which is the same class of failure as an
            // editor that accepts an edit and ignores it.
            : coordinateTextEdited(data)
            ? preservedFrameSchema(existing, data.get("coordinate"), data.get("period"))
            : structureAuthored()
            ? {
                // Validated before it is stored, so a malformed ladder never
                // replaces a working one, and the period is left exactly as it
                // was -- editing how a day divides says nothing about a cycle's
                // length.
                coordinate: buildCoordinateStructure({ ...structureDraft(), previous: existing.coordinate || null }),
                period: preservedFrameSchema(existing, "", data.get("period")).period
              }
            : preservedFrameSchema(existing, data.get("coordinate"), data.get("period"));
          const payload = {
            ...existing, id: recordId,
            title: String(data.get("title") || "Untitled frame"),
            traits: additiveFrameTraits(
              selectedKind,
              String(data.get("traits") || "").split(",").map((item) => item.trim()).filter(Boolean),
              existing.traits || []
            ),
            basis: capabilities.basis ? String(data.get("basis") || "") || undefined : undefined,
            color: String(data.get("color") || "#2e8b57"),
            display,
            ...schema
          };
          if (isNew) addFrame(documentValue, payload);
          else Object.assign(documentValue.frames[recordId], payload);
        });
        if (embedded) app.toast(`Saved ${String(data.get("title") || "frame")}`);
        else app.closeInspector();
      } catch (error) {
        app.toast(error.message, true);
      }
    });
    if (!isNew) {
      wrapper.querySelector("#duplicate-object").addEventListener("click", () => duplicateFrame(value.id));
      // Removal acts immediately and is one undoable step, like every other
      // change: undo is the safety net, and a modal that asks the same question
      // twice is not one.
      wrapper.querySelector("#delete-object").addEventListener("click", () => {
        app.executeFrameChange("Remove frame", value.id, (documentValue) => {
          delete documentValue.frames[value.id];
          for (const [id, relation] of Object.entries(documentValue.relations)) {
            // Both a staple's ends count: a connection into this frame keeps a
            // coordinate in a space that is about to stop existing, and one bad
            // pointer takes the whole file offline at its next load.
            if (relation.frame === value.id || relation.parent === value.id || relation.child === value.id
              || (relation.type === "staple" && stapleReferencesId(relation, value.id))) {
              delete documentValue.relations[id];
            }
          }
          for (const [id, pattern] of Object.entries(documentValue.patterns)) {
            if (pattern.frame === value.id || pattern.appliesTo?.includes(value.id)) delete documentValue.patterns[id];
          }
        });
        openObjectBrowser("frame");
      });
    }
    return wrapper;
  }

  function openFrameInspector(frameId = null, presetKind = "group") {
    const { chronolog, session } = app;
    if (!app.resolveProvisionalDraft()) return;
    const frame = frameId ? chronolog.frames[frameId] : null;
    session.inspector = { type: "frame", id: frameId };
    app.openInspector(frame?.title || `New ${presetKind}`, frameForm(frame, presetKind));
  }

  // The New menu's "Frame" entry, mirroring the create-then-edit order the
  // create-menu's Event/ToDo/Note entries already use (create the real record
  // first, then open it for editing) rather than the Frames workspace's own
  // "+ Calendar"/"+ Group" buttons, which open a blank form and create nothing
  // until it is submitted. This still creates through the same two primitives
  // that form's submit handler uses — `addFrame` (model.js) inside one
  // `executeRecordChange` transaction (transactions.js) — so there is no second
  // frame-creation mechanism, only a second caller of the shared one. The
  // payload is deliberately bare: a plain default title and whatever traits
  // `addFrame` itself defaults to, so nothing about the frame's kind or
  // meaning is guessed on the user's behalf — that is authored afterward, in
  // the same frame-editing form every other frame goes through.
  function createFrame() {
    const frameId = createId("frame");
    app.executeRecordChange("Create frame", "frames", frameId, (documentValue) => {
      addFrame(documentValue, { id: frameId, title: "New frame" });
    });
    openFrameInspector(frameId);
  }

  function patternForm(pattern = null) {
    const { chronolog, engine, session } = app;
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
    const recordId = value.id || createId("pattern");
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
        app.executeRecordChange(isNew ? "Create pattern" : "Edit pattern", "patterns", recordId, (documentValue) => {
          const payload = {
            id: recordId,
            title: String(data.get("title")),
            language: "chronolog-formula/1",
            appliesTo: [String(data.get("frame"))],
            frame: String(data.get("frame")),
            constants,
            source,
            exports: { state: "state", facts: "facts" }
          };
          if (isNew) addPattern(documentValue, payload);
          else Object.assign(documentValue.patterns[recordId], payload);
        });
        openPatternInspector(recordId);
      } catch (error) {
        app.toast(error.message, true);
      }
    });
    if (!isNew) wrapper.querySelector("#delete-object").addEventListener("click", () => {
      // A pattern bundle, not a single record: the overrides that suppress or
      // replace this series' occurrences have to go with it, and come back with it
      // on undo. This is the path the owner took when deleting a series left six
      // orphaned overrides behind.
      app.executePatternChange("Delete pattern", value.id, (documentValue) => {
        delete documentValue.patterns[value.id];
      });
      openObjectBrowser("pattern");
    });
    return wrapper;
  }

  function openPatternInspector(patternId = null) {
    const { chronolog, session } = app;
    if (!app.resolveProvisionalDraft()) return;
    const pattern = patternId ? chronolog.patterns[patternId] : null;
    session.inspector = { type: "pattern", id: patternId };
    app.openInspector(pattern?.title || "New pattern", patternForm(pattern));
  }

  const objectBrowserScope = { frame: "all", pattern: "current" };
  // The Frames drawer can comfortably hold a handful of records, but the model
  // deliberately has no such limit. Keep the view controls separate from the
  // document so filtering and folded sections never mutate frame data.
  const framesPanelState = {
    query: "",
    sections: { leading: true, companions: true, groups: true, objects: true }
  };

  function patternRelevantToLens(pattern) {
    const { session, engine } = app;
    const window = session.window();
    if (pattern.kind === "ics-rrule") {
      try {
        return engine.recurrenceFacts(pattern, window.start, window.end, 1).length > 0;
      } catch {
        return true;
      }
    }
    return !pattern.appliesTo?.length || pattern.appliesTo.includes(session.activeFrame);
  }

  function frameRelevantToLens(frame) {
    const { chronolog, session, engine } = app;
    if (!frame.traits.includes("calendar")) return true;
    // The primary and every companion are one selection now (src/frame-
    // selection.js) — frames[leading].display.overlays is retired.
    if (session.frameSelection.isSelected(frame.id)) return true;
    const window = session.window();
    if (engine.indexedExplicitFacts(frame.id).some((entry) =>
      entry.day.compare(window.start) >= 0 && entry.day.compare(window.end) <= 0
    )) return true;
    return Object.values(chronolog.patterns).some((pattern) =>
      (pattern.frame === frame.id || pattern.appliesTo?.includes(frame.id)) && patternRelevantToLens(pattern)
    );
  }

  function frameViewCard() {
    const { chronolog, session } = app;
    const activeFrameId = session.activeFrame;
    const active = chronolog.frames[activeFrameId];
    const leadingFrames = calendarFrames(chronolog);
    const display = active?.display || {};
    const viewCard = document.createElement("section");
    viewCard.className = "frame-view-card";
    const normalizedQuery = framesPanelState.query.trim().toLocaleLowerCase();
    const matches = (frame) => !normalizedQuery || `${frame.title || frame.id} ${frameKind(frame)} ${(frame.traits || []).join(" ")}`
      .toLocaleLowerCase().includes(normalizedQuery);
    const section = (id, label, content) => {
      const details = document.createElement("details");
      details.className = "frame-view-section";
      details.open = framesPanelState.sections[id];
      const summary = document.createElement("summary");
      summary.textContent = label;
      details.append(summary, content);
      details.addEventListener("toggle", () => { framesPanelState.sections[id] = details.open; });
      return details;
    };
    const filter = document.createElement("input");
    filter.id = "frame-view-filter";
    filter.type = "search";
    filter.placeholder = "Filter companion frames and groups";
    filter.value = framesPanelState.query;
    filter.setAttribute("aria-label", "Filter companion frames and groups");
    filter.addEventListener("input", () => {
      framesPanelState.query = filter.value;
      refreshFramesPanel();
    });
    const toolbar = document.createElement("div");
    toolbar.className = "frame-view-toolbar";
    toolbar.append(filter);
    const leading = document.createElement("label");
    leading.className = "field";
    const leadingLabel = document.createElement("span");
    leadingLabel.textContent = "Leading frame — primary coordinates";
    const leadingSelect = document.createElement("select");
    leadingSelect.id = "frame-leading-select";
    for (const frame of leadingFrames) {
      const option = document.createElement("option");
      option.value = frame.id;
      option.textContent = frame.title;
      option.selected = frame.id === activeFrameId;
      leadingSelect.append(option);
    }
    if (!leadingFrames.length) {
      const option = document.createElement("option");
      option.textContent = "No calendar frames yet";
      leadingSelect.append(option);
      leadingSelect.disabled = true;
    }
    leadingSelect.addEventListener("change", () => selectLeadingFrame(leadingSelect.value));
    leading.append(leadingLabel, leadingSelect);
    const heading = document.createElement("h3");
    heading.textContent = active ? `Workspace for ${active.title}` : "No leading frame";
    heading.title = active ? `Shown with ${active.title}` : "Create a calendar to establish primary coordinates";
    const note = document.createElement("p");
    note.className = "field-note";
    note.textContent = active
      ? "The leading frame supplies the primary coordinates. Companions are projected with it; groups organise event membership and never become temporal coordinates."
      : "This document has no calendar frame. Create one to establish primary coordinates; groups remain available as non-temporal organization.";
    const leadingHint = document.createElement("p");
    leadingHint.className = "field-note";
    leadingHint.textContent = active
      ? "Changing this selection updates the toolbar and every open projection immediately."
      : "Calendar creation is the only step required to make this workspace projectable.";
    const leadingContent = document.createElement("div");
    leadingContent.className = "frame-view-section-content";
    leadingContent.append(leading, leadingHint);
    if (!active) {
      const create = document.createElement("button");
      create.type = "button";
      create.className = "instrument-button primary";
      create.textContent = "Create first calendar";
      create.addEventListener("click", () => openFrameInspector(null, "calendar"));
      leadingContent.append(create);
    }
    viewCard.append(toolbar, heading, note, section("leading", "Leading frame", leadingContent));
    // Companion membership lives in session.frameSelection now, not
    // frames[activeFrameId].display.overlays — overlay configuration is view
    // state, exactly like the leading frame itself, not a document edit.
    // This was the one surface that used to write the field the renderer
    // actually read (the 8.19 field report: "the only way to overlay frames
    // is to use the frame dock active frame window"); every surface now
    // reads and writes the same selection instead.
    const included = new Set(session.frameSelection.selected());
    const related = active ? Object.values(chronolog.frames).filter((frame) => frame.id !== activeFrameId
      && (frame.traits.includes("calendar") || frame.traits.includes("line") || frame.traits.includes("timeline"))) : [];
    {
      const choices = document.createElement("div");
      choices.className = "frame-view-grid";
      const matchingRelated = related.filter(matches).sort((left, right) => left.title.localeCompare(right.title));
      for (const frame of matchingRelated) {
        const choice = document.createElement("label");
        choice.className = "check-chip";
        const input = document.createElement("input");
        input.id = `frame-companion-${frame.id}`;
        input.type = "checkbox";
        input.checked = included.has(frame.id);
        input.addEventListener("change", () => {
          session.toggleFrameSelection(frame.id);
          refreshFramesPanel();
          app.scheduleRender();
        });
        const name = document.createElement("span");
        name.className = "frame-choice-name";
        name.title = `${frame.title} · ${frameKind(frame)}`;
        name.textContent = `${frame.title} · ${frameKind(frame)}`;
        choice.append(input, name);
        choices.append(choice);
      }
      if (!matchingRelated.length) {
        const empty = document.createElement("p");
        empty.className = "field-note";
        empty.textContent = related.length
          ? "No companion calendars or lines match this filter."
          : active ? "This is the only calendar or line; there are no companion frames to include yet."
            : "Create a leading calendar before adding companion frames.";
        choices.append(empty);
      }
      const content = document.createElement("div");
      content.className = "frame-view-section-content";
      content.append(choices);
      const selectedCount = related.filter((frame) => included.has(frame.id)).length;
      const companionNote = document.createElement("p");
      companionNote.className = "field-note";
      companionNote.textContent = "These are subordinate display companions only. Their coordinates are not converted or inferred.";
      content.prepend(companionNote);
      const companionLabel = `Include calendars and lines (${related.length})`;
      viewCard.append(section("companions", `Companions projected with ${active?.title || "leading frame"} (${selectedCount}/${related.length}) — ${companionLabel}`, content));
    }
    const groups = groupFrames(chronolog);
    {
      const groupList = document.createElement("div");
      groupList.className = "frame-group-list";
      const matchingGroups = groups.filter(matches);
      for (const group of matchingGroups) {
        const row = document.createElement("div");
        row.className = "frame-group-row";
        const name = document.createElement("strong");
        name.textContent = group.title;
        name.style.setProperty("--group-color", group.color || "#2e8b57");
        const presence = document.createElement("select");
        presence.id = `frame-group-mode-${group.id}`;
        presence.title = `${group.title} in ${active?.title || "this calendar"}`;
        presence.disabled = !active;
        for (const [value, text] of [["auto", "Automatic"], ["show", "Include all"], ["hide", "Hide here"]]) {
          const option = document.createElement("option");
          option.value = value;
          option.textContent = text;
          option.selected = (display.groupModes?.[group.id] || "auto") === value;
          presence.append(option);
        }
        presence.addEventListener("change", () => {
          app.executeRecordChange("Change group visibility", "frames", activeFrameId, (documentValue) => {
            const target = documentValue.frames[activeFrameId];
            const groupModes = { ...(target.display?.groupModes || {}) };
            if (presence.value === "auto") delete groupModes[group.id];
            else groupModes[group.id] = presence.value;
            target.display = { ...(target.display || {}), groupModes };
          }, { viewOnly: true });
        });
        const strategic = document.createElement("select");
        strategic.id = `frame-group-strategic-${group.id}`;
        strategic.title = `${group.title} in Strategic`;
        for (const [value, text] of [["auto", "Strategic: automatic"], ["show", "Strategic: promote"], ["hide", "Strategic: demote"]]) {
          const option = document.createElement("option");
          option.value = value;
          option.textContent = text;
          option.selected = (group.display?.strategic || "auto") === value;
          strategic.append(option);
        }
        strategic.addEventListener("change", () => {
          app.executeRecordChange("Change strategic priority", "frames", group.id, (documentValue) => {
            const target = documentValue.frames[group.id];
            target.display = { ...(target.display || {}), strategic: strategic.value };
          }, { viewOnly: true });
        });
        row.append(name, presence, strategic);
        groupList.append(row);
      }
      if (!matchingGroups.length) {
        const empty = document.createElement("p");
        empty.className = "field-note";
        empty.textContent = groups.length
          ? "No groups match this filter."
          : "No groups exist yet. Create one below when the workspace needs membership or priority organization.";
        groupList.append(empty);
      }
      const content = document.createElement("div");
      content.className = "frame-view-section-content";
      content.append(groupList);
      const groupNote = document.createElement("p");
      groupNote.className = "field-note";
      groupNote.textContent = "Groups organise memberships. Visibility affects this workspace; strategic priority is a group-wide display choice.";
      content.prepend(groupNote);
      const groupLabel = `Groups in this view (${groups.length})`;
      viewCard.append(section("groups", `Groups in this workspace (${groups.length}) — ${groupLabel}`, content));
    }
    return viewCard;
  }

  function openObjectBrowser(kind) {
    const { chronolog } = app;
    if (!app.resolveProvisionalDraft()) return;
    const wrapper = document.createElement("div");
    wrapper.className = "object-browser";
    const toolbar = document.createElement("div");
    toolbar.className = "object-browser-toolbar";
    const search = document.createElement("input");
    search.type = "search";
    search.placeholder = "Filter by name or type";
    const scope = document.createElement("select");
    for (const [value, label] of [["current", "Current lens"], ["all", "All"]]) {
      const option = document.createElement("option");
      option.value = value;
      option.textContent = label;
      option.selected = objectBrowserScope[kind] === value;
      scope.append(option);
    }
    toolbar.append(search, scope);
    wrapper.append(toolbar);
    if (kind === "frame") {
      wrapper.append(frameViewCard());
      const objects = document.createElement("section");
      objects.className = "frame-object-guide";
      objects.innerHTML = "<h3>Frame definitions and organisational objects</h3><p class=\"field-note\">Edit a frame's coordinate definition and capabilities below. Groups are organisational objects; mappings and other advanced structures remain explicit rather than being inferred from group membership.</p>";
      wrapper.append(objects);
      const createRow = document.createElement("div");
      createRow.className = "object-create-row";
      for (const [value, label] of [["calendar", "+ Calendar"], ["group", "+ Group"], ["importance", "+ Importance"], ["cycle", "+ Cycle"], ["line", "+ Line"]]) {
        const create = document.createElement("button");
        create.type = "button";
        create.className = `instrument-button${value === "group" ? " primary" : ""}`;
        create.textContent = label;
        create.addEventListener("click", () => openFrameInspector(null, value));
        createRow.append(create);
      }
      wrapper.append(createRow);
    } else {
      const create = document.createElement("button");
      create.type = "button";
      create.className = "instrument-button primary";
      create.textContent = "Create advanced pattern";
      create.addEventListener("click", () => openPatternInspector());
      wrapper.append(create);
    }
    const list = document.createElement("div");
    list.className = "object-list";
    wrapper.append(list);
    const paint = () => {
      objectBrowserScope[kind] = scope.value;
      const query = search.value.trim().toLowerCase();
      let records = kind === "frame" ? Object.values(chronolog.frames) : Object.values(chronolog.patterns);
      if (scope.value === "current") records = records.filter(kind === "frame" ? frameRelevantToLens : patternRelevantToLens);
      records = records.filter((record) => `${record.title || record.id} ${(record.traits || [record.language]).join(" ")}`.toLowerCase().includes(query));
      if (kind === "frame") records.sort((left, right) => frameKind(left).localeCompare(frameKind(right)) || left.title.localeCompare(right.title));
      list.replaceChildren();
      for (const record of records) {
        const row = document.createElement(kind === "frame" ? "details" : "div");
        row.className = `object-row${kind === "frame" ? " frame-expander" : ""}`;
        const edit = document.createElement("button");
        if (kind !== "frame") edit.type = "button";
        edit.className = "object-row-main";
        const type = kind === "frame" ? frameKind(record) : record.kind || "pattern";
        edit.innerHTML = `<span class="object-type">${escapeHTML(type)}</span><strong>${escapeHTML(record.title || record.id)}</strong><small>${escapeHTML(record.id)}</small>`;
        if (kind === "frame") {
          const summary = document.createElement("summary");
          summary.className = "object-row-main";
          summary.innerHTML = edit.innerHTML;
          row.append(summary, frameForm(record, frameKind(record), true));
        } else {
          edit.addEventListener("click", () => openPatternInspector(record.id));
          row.append(edit);
        }
        list.append(row);
      }
      if (!records.length) {
        const empty = document.createElement("p");
        empty.className = "field-note";
        empty.textContent = "Nothing matches this scope.";
        list.append(empty);
      }
    };
    search.addEventListener("input", paint);
    scope.addEventListener("change", paint);
    paint();
    const isFramesBrowser = kind === "frame";
    // This is the card the owner's field report named: a frame added elsewhere
    // (import, sync pull) has to show up here as a selectable row without the
    // card being closed and reopened. `refreshObjectBrowser` is this card's own
    // registration with the dock's card-refresh mechanism (src/ui/dock.js), not
    // a bespoke hook in the render loop -- see AGENTS.md/the dock refresh note.
    //
    // The list is rebuilt by the same `paint()` the search/scope controls
    // already call on every keystroke, so this causes no new class of loss: an
    // embedded frame editor (a `<details>` row's inline form, opened from this
    // same list) holds live typed values with no dirty-tracking of its own, and
    // that risk already exists today -- typing in the filter box while one is
    // expanded already discards it. The one thing this guard adds is declining
    // the rebuild while focus is actually inside that inline form, so a refresh
    // triggered by an unrelated document change (not the user's own typing)
    // never interrupts a keystroke.
    function refreshObjectBrowser() {
      if (kind === "frame") refreshFramesPanel();
      const active = document.activeElement;
      if (active && list.contains(active) && active.closest(".frame-form")) return;
      const scrollTop = list.scrollTop;
      paint();
      list.scrollTop = scrollTop;
    }
    app.openInspector(
      kind === "frame" ? "Frames" : "Patterns",
      wrapper,
      isFramesBrowser ? "frames-browser" : "object-browser",
      null,
      refreshObjectBrowser
    );
    if (isFramesBrowser) {
      for (const id of ["new-frame", "manage-frames"]) byId(id).setAttribute("aria-expanded", "true");
      // Opening Frames is intentionally passive for the workspace.  Focusing
      // the filter remains useful for keyboard users, but must not ask the
      // browser to scroll the projection or its focused timeline into view.
      search.focus({ preventScroll: true });
    }
  }

  function refreshFramesPanel() {
    const inspectorBody = framesBody();
    if (inspectorBody) {
      const current = inspectorBody.querySelector(".frame-view-card");
      if (!current) return;
      const scrollTop = inspectorBody.scrollTop;
      const active = document.activeElement;
      const focusId = current.contains(active) ? active.id : "";
      const selection = focusId && typeof active.selectionStart === "number"
        ? [active.selectionStart, active.selectionEnd] : null;
      current.replaceWith(frameViewCard());
      inspectorBody.scrollTop = scrollTop;
      if (focusId) {
        const next = document.getElementById(focusId);
        if (next) {
          next.focus({ preventScroll: true });
          if (selection && typeof next.setSelectionRange === "function") next.setSelectionRange(...selection);
        }
      }
    }
  }

  // The one place a frame becomes primary from a UI action — the leading
  // select here, the toolbar Frame drop's per-row marker, and the ICS-import
  // call site all route through this (or `session.setLeadingFrame`
  // directly), so cycle-matching and the panel refresh happen exactly once
  // regardless of which surface triggered the reassignment.
  function selectLeadingFrame(frameId) {
    const { chronolog, session } = app;
    if (!calendarFrames(chronolog).some((frame) => frame.id === frameId)) return;
    session.setLeadingFrame(frameId);
    const matchingCycle = Object.values(chronolog.frames).find(
      (frame) => frame.traits.includes("cycle") && frame.calendar === session.activeFrame
    );
    if (matchingCycle) app.selectCycle(matchingCycle.id);
    refreshFramesPanel();
    app.scheduleRender();
  }

  function toggleFramesBrowser(returnTarget) {
    // The trigger is a toggle: if its own card is already open, the second press
    // closes it rather than re-rendering the same surface.
    if (framesBody()) {
      app.closeDockCard("panel:frames-browser");
      return;
    }
    app.framesReturnTarget = returnTarget;
    openObjectBrowser("frame");
  }

  byId("new-frame").addEventListener("click", () => {
    toggleFramesBrowser(byId("new-frame"));
  });
  byId("manage-frames").addEventListener("click", () => {
    const returnTarget = byId("document-menu").querySelector("summary");
    toggleFramesBrowser(returnTarget);
  });
  byId("new-pattern").addEventListener("click", () => openObjectBrowser("pattern"));

  return { openFrameInspector, openObjectBrowser, selectLeadingFrame, createFrame };
}
