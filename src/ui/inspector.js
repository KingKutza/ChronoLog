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
  eventRelations,
  putStaple,
  removeStaple
} from "../model.js";
import { OBJECT_KINDS, normalizeObjectKind, objectKindForEvent, traitsForObjectKind } from "../object-kinds.js";
import { delOp, putOp } from "../ops.js";
import { calendarFrames, groupFrames } from "../projections.js";
import {
  applyRecurrenceEnd,
  recurrenceEndMode,
  recurrenceUntilDate
} from "../recurrence-end.js";
import {
  ANCHOR_ROLE_ORDER,
  isFuzzyStaple,
  resolveObjectExtent,
  STAPLE_KINDS,
  stapleKind,
  staplesForObject,
  staplesForSeries
} from "../staples.js";
import { explainFactWeight } from "../visual-language.js";
import { byId, escapeHTML } from "./dom-helpers.js";

// Whether the event-color field on submit should become the object's own
// explicit color, or be removed entirely so the color cascade falls through
// to inheritance (AGENTS.md's "Object color inheritance", step 1: "an
// explicit color on the object overrides everything else"). There is no
// separate "override" toggle any more — a color <input> always holds *some*
// hex value, so "explicit" has to be tracked alongside it (the field's own
// `data-explicit` attribute) rather than inferred from the value being
// non-empty. Exported so this precedence rule is directly testable without a
// DOM harness.
export function resolveSubmittedEventColor(explicit, colorValue, fallback = "#d4552d") {
  return explicit ? String(colorValue || fallback) : null;
}

// Parses the editor's own "year-month-day[ hour:minute[:second]]" date/time
// text into a coordinate. Pure (no `app` reach-in), so it is shared by the
// main placement fields, the Completed field, and the staples section's Add
// control without duplicating the grammar three times.
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

// A relation's (or a staple's -- same `coordinate`/`parameters.dateOnly`
// shape) date/time split into the two text fields the editor's date and time
// inputs hold. Pure, so the staples list can format a row without a DOM.
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

// The registry-driven dropdown source the owner's ruling requires (STAPLE_KINDS
// in src/staples.js is the one place a staple kind is added), filtered to the
// scope actually being authored -- a series-only kind ("end"/"inflection"/
// "phase") never appears while adding a staple to a bare, non-recurring event.
export function stapleKindOptions(scope) {
  return Object.entries(STAPLE_KINDS)
    .filter(([, definition]) => definition.targets.includes(scope))
    .map(([value, definition]) => [value, definition.label]);
}

const CUSTOM_ANCHOR_ROLE = "__custom__";

function magnitudeOrNull(amount, unit) {
  const text = String(amount ?? "").trim();
  if (!text) return null;
  return durationMagnitude(text, unit || "minute");
}

// The staples section's Add control, as a decision pulled out of the DOM --
// the same mitigation `resolveSubmittedEventColor` and
// test/frame-creation.test.js already use, because a form this data-rich
// cannot be driven through FormData in the repo's stub-DOM harness. Builds
// exactly the record `putStaple` expects (minus `id`, which the caller
// assigns so a single-record transaction can name it up front), given plain
// field values already read off the (possibly stubbed) form. Throws a
// user-facing message on anything unresolvable, same as `parseDateText`.
export function buildStapleInput({
  scope,
  targetId,
  kind,
  role = "start",
  roleName = "",
  dateText = "",
  timeText = "",
  frame,
  fuzzy = false,
  spreadBeforeAmount = "",
  spreadBeforeUnit = "minute",
  spreadAfterAmount = "",
  spreadAfterUnit = "minute",
  offsetAmount = "",
  offsetUnit = "minute",
  ruleRepeat = "",
  ruleInterval = "1",
  ruleDateText = "",
  ruleTimeText = "",
  ruleDurationAmount = "",
  ruleDurationUnit = "minute"
} = {}) {
  const definition = stapleKind(kind);
  if (!definition) throw new Error("Choose a staple kind.");
  if (!definition.targets.includes(scope)) {
    throw new Error(`${definition.label} cannot be placed on ${scope === "series" ? "a series" : "an event"}.`);
  }
  if (!targetId) throw new Error(scope === "series" ? "This event has no series to staple yet." : "Nothing to staple this to.");
  const dateValue = String(dateText || "").trim();
  if (!dateValue) throw new Error("A staple needs a date.");
  const timeValue = String(timeText || "").trim();
  // The "end" kind alone keeps the shipped end-staple's own default: a bare
  // date means through the end of that day (LEXICON's "the staple's own
  // occurrence survives; nothing after it projects"), exactly what
  // `setSeriesEndStaple` always did. Every other kind follows the "no time
  // means midnight" convention the Start date field already uses -- nothing
  // in any other kind's meaning calls for an end-of-day default.
  const timeForCoordinate = timeValue || (kind === "end" ? "23:59:59" : "00:00");
  const coordinateValue = parseDateText(`${dateValue} ${timeForCoordinate}`);
  const input = {
    ...(scope === "series" ? { series: targetId } : { object: targetId }),
    kind,
    frame,
    coordinate: coordinateValue
  };
  if (!timeValue) input.parameters = { dateOnly: true };
  if (definition.anchors) {
    const isCustom = role === CUSTOM_ANCHOR_ROLE;
    const resolvedRole = isCustom ? String(roleName || "").trim() : role;
    if (!resolvedRole) throw new Error("Name this anchor's role.");
    input.role = resolvedRole;
    // A named point's distance from the object's start ("magnitude pairing"
    // -- src/staples.js's `namedOffsetDays`); start/end/midpoint derive their
    // magnitude from a second anchor or the object's own duration instead, so
    // an offset only means something for a role outside that fixed set.
    if (isCustom) {
      const offset = magnitudeOrNull(offsetAmount, offsetUnit);
      if (offset) input.payload = { ...(input.payload || {}), offset };
    }
  }
  if (fuzzy) {
    // Asymmetric on purpose (src/staples.js's own note): "about 5ish" and a
    // hard ceiling are different shapes, so before/after are two independent
    // fields, never one +/-.
    input.spread = {
      before: magnitudeOrNull(spreadBeforeAmount, spreadBeforeUnit) || durationMagnitude("0", "minute"),
      after: magnitudeOrNull(spreadAfterAmount, spreadAfterUnit) || durationMagnitude("0", "minute")
    };
  }
  // The following rule, for a kind that can carry one. This is the second half
  // of LEXICON's Rob-and-John ruling -- "then either define a new rule
  // post-staple or a new series, on preference" -- and leaving it out would
  // reproduce the exact objection this substrate answers: a staple that can
  // only ever terminate. Blank repeat IS the other preference: the staple
  // partitions and nothing follows, which is what an end staple is.
  const repeatChoice = String(ruleRepeat || "").trim();
  if (definition.carriesRule && repeatChoice) {
    const frequency = repeatChoice === "WEEKDAYS" ? "WEEKLY" : repeatChoice;
    const interval = Math.max(1, Math.min(999, Number(ruleInterval) || 1));
    const rrule = { FREQ: frequency, INTERVAL: String(interval) };
    if (repeatChoice === "WEEKDAYS") rrule.BYDAY = "MO,TU,WE,TH,FR";
    const head = { rrule };
    // The following rule's own start. Without it the new rule would inherit the
    // staple's instant as its base, and since a partitioning staple opens its
    // segment EXCLUSIVELY (src/staples.js's boundary convention) the first
    // occurrence would land a whole cycle later than the user meant. Rob-and-John
    // needs it regardless: the new meeting is a Thursday lunch, not the old
    // Monday 6:15.
    const ruleDate = String(ruleDateText || "").trim();
    if (ruleDate) {
      head.coordinate = parseDateText(`${ruleDate} ${String(ruleTimeText || "").trim() || "00:00"}`);
      head.frame = frame;
    }
    const magnitude = magnitudeOrNull(ruleDurationAmount, ruleDurationUnit);
    if (magnitude) head.magnitude = magnitude;
    input.payload = { ...(input.payload || {}), rule: head };
  }
  return input;
}

// One staple list row's display fields, pure over the record and the scope it
// was fetched under ("series" or "object") -- so the list's markup is a dumb
// map over this, traceable by hand, and this decision is what a test drives
// directly instead of the DOM.
export function stapleRowModel(staple, scope) {
  const definition = stapleKind(staple?.kind);
  const parts = relationDateParts(staple);
  return {
    id: staple?.id || null,
    scope,
    kind: staple?.kind || null,
    kindLabel: definition?.label || staple?.kind || "Staple",
    role: staple?.role || null,
    date: parts.date,
    time: parts.time,
    fuzzy: isFuzzyStaple(staple)
  };
}

// The derived-extent readout's display fields, pure over `resolveObjectExtent`'s
// own result -- civil-date formatting and the overdetermined staples' kind
// labels are the only transformation the editor applies, so this is that
// transformation in one testable place.
export function extentReadoutModel(extent) {
  const civilText = (days) => (days === null || days === undefined ? null : formatCivil(daysToCivilCoordinate(days), true));
  return {
    start: civilText(extent?.startDays ?? null),
    end: civilText(extent?.endDays ?? null),
    source: extent?.source || "unstapled",
    derivedMagnitude: Boolean(extent?.derivedMagnitude),
    overdetermined: (extent?.overdetermined || []).map((item) => ({
      kind: item.staple?.kind || null,
      kindLabel: stapleKind(item.staple?.kind)?.label || item.staple?.kind || "Staple",
      role: item.role || null,
      reason: item.reason
    }))
  };
}

// The weight readout's display fields, pure over `explainFactWeight`'s own
// result. Almost a pass-through on purpose -- the owner's ask was visibility
// into an existing derivation, not a new one, so the editor invents nothing
// here; it names the fields the markup maps over one-for-one.
export function weightReadoutModel(explanation) {
  return {
    base: explanation.base,
    baseVerdict: explanation.baseVerdict,
    rows: (explanation.steps || []).map((step) => ({
      title: step.title,
      formula: step.formula,
      from: step.from,
      to: step.to
    })),
    final: explanation.final,
    verdict: explanation.verdict
  };
}

// The unit choices every duration-shaped field in this editor offers
// (Duration, a fuzzy staple's before/after spread, a named anchor's offset) --
// one list, so a new unit is one edit instead of three.
function magnitudeUnitOptions(selected = "minute") {
  return [["minute", "Minutes"], ["hour", "Hours"], ["day", "Days"], ["second", "Seconds"]]
    .map(([value, label]) => `<option value="${value}" ${value === selected ? "selected" : ""}>${label}</option>`)
    .join("");
}

// The three render helpers below are dumb maps over the pure `*Model`
// functions above -- traced by hand rather than driven through the DOM (the
// repo's stub-DOM harness cannot parse `innerHTML`/drive `FormData`; see
// `buildStapleInput`'s own note). Kept tiny and free of decisions on purpose:
// anything that looks like a choice belongs in the exported, tested model
// function instead of here.
function weightReadoutMarkup(model) {
  const rows = model.rows.map((row) => `<div class="weight-readout-row">
      <span class="weight-readout-title">${escapeHTML(row.title)}</span>
      <code class="weight-readout-formula">${escapeHTML(row.formula)}</code>
      <span class="weight-readout-values">${Number(row.from).toFixed(2)} → ${Number(row.to).toFixed(2)}</span>
    </div>`).join("");
  return `
    <p class="field-note weight-readout-base">Base weight <strong>${Number(model.base).toFixed(2)}</strong> (${escapeHTML(model.baseVerdict)})</p>
    ${rows}
    <p class="field-note weight-readout-final">Final weight <strong>${Number(model.final).toFixed(2)}</strong> — <strong>${escapeHTML(model.verdict)}</strong></p>`;
}

function stapleRowMarkup(row) {
  return `<li class="staple-row" data-staple-id="${escapeHTML(row.id)}" data-staple-scope="${row.scope}">
    <span class="staple-kind">${escapeHTML(row.kindLabel)}</span>
    ${row.role ? `<span class="staple-role">${escapeHTML(row.role)}</span>` : ""}
    <span class="staple-position">${escapeHTML(row.date)}${row.time ? ` ${escapeHTML(row.time)}` : ""}</span>
    ${row.fuzzy ? `<span class="staple-fuzzy" title="Fuzzy staple">~ fuzzy</span>` : ""}
    <span class="staple-scope-label">${row.scope === "series" ? "series" : "this event"}</span>
    <button class="instrument-button danger" type="button" data-remove-staple>Remove</button>
  </li>`;
}

function extentReadoutMarkup(model) {
  const magnitudeNote = model.source === "anchors" ? "magnitude derived from anchors"
    : model.source === "anchor+magnitude" ? "an anchor plus this object's own duration"
      : model.source === "placement" ? "its own placement and duration"
        : model.source === "unresolved" ? "its placement could not be resolved"
          : "not stapled yet";
  const overdetermined = model.overdetermined.map((item) => `<li>${escapeHTML(item.kindLabel)}${item.role ? ` (${escapeHTML(item.role)})` : ""} — not used: ${escapeHTML(item.reason)}</li>`).join("");
  return `
    <p class="field-note staple-extent-note">Resolved extent: <strong>${model.start ? escapeHTML(model.start) : "unresolved"}</strong> to <strong>${model.end ? escapeHTML(model.end) : "unresolved"}</strong> (${escapeHTML(magnitudeNote)}).</p>
    ${overdetermined ? `<p class="field-note staple-extent-warning">Authored but not used for placement:</p><ul class="staple-overdetermined">${overdetermined}</ul>` : ""}`;
}

// The Inspector panel: generic open/close chrome, the provisional-draft
// lifecycle (a just-created event that autosave defers until it is saved or
// discarded), the event/object-kind form, and generated-fact materialization.
// `app` carries the live document/engine/session/history/store plus the
// small `framesReturnTarget` focus-return slot that the Frames panel also
// writes when it reopens this same panel.
export function createInspector(app) {
  // Provisional drafts, keyed by event id. This is a Map rather than a single
  // slot because several event editors can be open at once now, each holding its
  // own unsaved draft. The store's deferral is already refcounted, so N open
  // drafts hold autosave off exactly N times and the last one to resolve releases
  // it.
  const drafts = new Map();
  // Which singleton panel the editor last opened, so `dismissInspector` knows
  // which card to close. Object cards are closed by id instead, because "the"
  // object card no longer exists.
  let lastPanel = "object";

  // Every editor in the app funnels through `openInspector`, which is why the
  // drawer could become the dock without touching a single form: this one
  // function is the seam. The `panel` argument becomes the card's identity, so
  // the object editor, the Frames workspace and the calendar-sync panel are
  // separate cards rather than one surface they take turns overwriting.
  //
  // `key` makes the card's identity per-object. Without it every event editor
  // shared one card, so clicking a second meeting replaced the first instead of
  // adding to the dock. With it, "open this object" is idempotent per object:
  // the same object focuses its existing card, a different object gets its own.
  function objectCardId(objectId) {
    return `object:${objectId}`;
  }

  // `refresh`, if given, is threaded straight to the dock's card-refresh
  // registry (src/ui/dock.js's `openDockCard`/`refreshDockCards`): the card
  // opts into staying live by handing over its own reconciler here, once, at
  // open time. Omitting it (every caller that edits one specific record with a
  // live form) leaves the card exactly as stale as it always was, which is the
  // safe default for a surface that cannot be rebuilt out from under an
  // in-progress edit.
  function openInspector(title, body, panel = "object", key = null, refresh = null) {
    const cardId = key ? objectCardId(key) : `panel:${panel}`;
    if (!key) lastPanel = panel;
    app.openDockCard({
      id: cardId,
      title,
      body,
      onClose: () => handleCardClosed(panel, key),
      refresh
    });
  }

  // The dock closed a card on its own (its handle was clicked). Anything the
  // editor was holding for that surface has to be released, or a discarded draft
  // would linger in a card nobody can see. Only this card's draft is discarded —
  // closing one editor must not touch another card's unsaved work.
  function handleCardClosed(panel, key) {
    if (key) {
      discardProvisionalDraft(key);
      if (app.session.inspector?.id === key) app.session.inspector = null;
    }
    if (!app.dockIsOpen()) restoreFramesFocus(panel);
  }

  function restoreFramesFocus(panel) {
    const returnTarget = app.framesReturnTarget;
    app.framesReturnTarget = null;
    if (panel !== "frames-browser") return;
    const visibleToolbarTrigger = byId("new-frame").getClientRects().length ? byId("new-frame") : null;
    (returnTarget || visibleToolbarTrigger || byId("document-menu").querySelector("summary"))?.focus();
  }

  function dismissInspector() {
    const { session } = app;
    const panel = lastPanel;
    session.inspector = null;
    app.closeDockCard(`panel:${panel}`);
    restoreFramesFocus(panel);
  }

  // Closing one object's editor. Its own draft goes with it and every other open
  // card is left exactly as it was.
  //
  // Closing is also where a materialized occurrence gets asked whether it still
  // deviates from its series. If it does not — the user opened it, changed nothing or
  // changed something back — the convergence invariant retires it and the projection
  // reasserts, which is ROADMAP #5's rule that closing without changes must not leave
  // a separate instance behind. It is the same invariant that runs inside every edit,
  // not a special close-time rule, and it commits nothing when the occurrence really
  // does differ.
  function dismissObjectCard(objectId) {
    if (app.session.inspector?.id === objectId) app.session.inspector = null;
    app.closeDockCard(objectCardId(objectId));
    app.convergeSeriesOccurrence?.(objectId);
  }

  function closeInspector() {
    dismissInspector();
  }

  function hasProvisionalDraft() {
    return drafts.size > 0;
  }

  // Used only when the whole document is being replaced wholesale (a fresh
  // open, or reloading after a conflict): the draft belongs to a document
  // that is about to stop existing, so there is nothing to discard through
  // an undo transaction — just forget it.
  function clearProvisionalDraft() {
    drafts.clear();
  }

  // Discard one specific draft. It used to mean "discard the draft, unless it is
  // the one being opened next", because there could only be one; now it is
  // explicitly scoped, so opening a second editor never disturbs the first.
  function discardProvisionalDraft(eventId) {
    if (!eventId || !drafts.has(eventId)) return false;
    drafts.delete(eventId);
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

  // Opening an editor no longer has to settle anyone else's unsaved work: cards
  // are plural, so a second draft is a second card rather than a replacement. The
  // hook stays so callers keep a single place to ask "may I open?".
  function resolveProvisionalDraft() {
    return true;
  }

  function commitProvisionalDraft(eventId) {
    if (!drafts.has(eventId)) return false;
    drafts.delete(eventId);
    app.store.endDeferred();
    return true;
  }

  function focusInspectorEditor(eventId) {
    requestAnimationFrame(() => {
      if (app.session.inspector?.type !== "event" || app.session.inspector.id !== eventId) return;
      const body = app.dockCardBody(objectCardId(eventId));
      const title = body?.querySelector('input[name="title"]');
      if (!(title instanceof HTMLInputElement)) return;
      title.focus({ preventScroll: true });
      title.select();
    });
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

  // The one place that finds "the series this event is the template of", read
  // fresh every time (rather than captured once at open time) so the staples
  // section stays correct across its own live-edited card lifetime.
  function findRecurrencePattern(chronologDocument, eventId) {
    return Object.values(chronologDocument.patterns).find(
      (pattern) => pattern.kind === "ics-rrule" && pattern.templateEvent === eventId
    ) || null;
  }

  // A pattern carries its rule twice: the parsed `rrule` the engine reads and the
  // `rawRule` property ICS export re-serializes. Writing one without the other is
  // how a rule change survives a render and then vanishes on export, so both are
  // written together, and the verbatim copy of the old text is dropped because it
  // no longer describes this rule.
  function writePatternRule(pattern, rrule) {
    pattern.rrule = rrule;
    if (!pattern.rawRule) return;
    pattern.rawRule = {
      ...pattern.rawRule,
      value: Object.entries(rrule).map(([key, value]) => `${key}=${value}`).join(";")
    };
    delete pattern.rawRule.raw;
    delete pattern.rawRule.verbatim;
  }

  // There is deliberately no "stop repeating here" command. Ending a series is
  // not an imperative act on an occurrence — it is placing an end-staple on the
  // series' body, at its beginning, its end, or any other reference point
  // (ROADMAP staple anchoring). A button that truncated the rule from whichever
  // occurrence happened to be open contradicted that model, so it is gone rather
  // than kept as a shortcut. The UNTIL arithmetic it used survives in
  // src/recurrence-end.js, where the "Ends on a date" control and the eventual
  // staple model both need it.

  // Resolving a clicked virtual fact needs the day it was ACTUALLY RENDERED
  // AT, which every fact node already carries: `bindFact` (src/projections.js)
  // stamps `dataset.factDay` unconditionally, and only ever adds
  // `dataset.virtualId` to a node it has also stamped a day on. So the day is
  // required here, not optional.
  //
  // It used to be optional, falling back to `session.window(1.25)` -- a
  // symmetric guess at what was on screen. That guess was the 8.19 field
  // report's "That generated fact is outside the current query window": a
  // second, independent derivation of the render window, disagreeing with what
  // the lens had actually drawn (Intimate's back/forward span is asymmetric,
  // 2 and 7 by default, and carries a scroll buffer past it). Keeping the
  // guess as a fallback would leave the bug one forgotten argument away from
  // returning, so it is deleted rather than deprecated. There is now exactly
  // one derivation of "where was this drawn", it comes from the drawn fact
  // itself, and it cannot disagree with the renderer because it IS the
  // renderer's own answer.
  function findVisibleFact(virtualId, nearDay) {
    const { session, engine } = app;
    if (nearDay === null || nearDay === undefined || nearDay === "") {
      throw new TypeError(
        "findVisibleFact requires the day the fact was rendered at (a fact node's dataset.factDay)"
      );
    }
    const day = Rational.parse(nearDay);
    const slack = Rational.parse(1).div(86400);
    return engine.queryFacts({
      frame: session.activeFrame,
      start: daysToCivilCoordinate(day.sub(slack)),
      end: daysToCivilCoordinate(day.add(slack)),
      limit: 5000
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

  // Opening an occurrence of a series edits the SERIES by default (ROADMAP #1's
  // ruling), with a toggle at the top to swap to this-occurrence and back. This
  // inverts the old flow, which put a chooser in the way and materialized the moment
  // you picked "Edit this occurrence" — before you had actually changed anything.
  //
  // Series is the default because it is the answer that needs no cleanup: editing the
  // rule leaves no per-occurrence record behind. Materialization is deferred to the
  // moment the user asks for occurrence mode, and if they then change nothing, the
  // convergence invariant retires it on close (see `dismissObjectCard`) — so the
  // no-op-fork rule holds without the editor having to track dirtiness.
  // `nearDay`, when given, is the exact day (`fact.day`, via the clicked
  // node's own `dataset.factDay` -- every fact node carries it, stamped once
  // by `bindFact` in src/projections.js) that the caller actually rendered
  // this occurrence at. Resolving against that exact day rather than a
  // generic window guess is the fix for the 8.19 field report's item 3:
  // "click an instance of a series in the right day columns, get 'outside the
  // current query window'". The Intimate rail pre-renders a buffer of days
  // past what its own back/forward span implies (see renderIntimate's
  // `bufferDays`), so a fact genuinely on screen could sit outside any
  // window this function guessed independently -- two derivations of "what
  // was rendered" that could only ever coincidentally agree. Deriving the
  // resolution window from the rendered fact's own day instead of
  // reconstructing the render window needs no second derivation, and holds
  // for every surface `bindFact` covers (Intimate, Tactical, Strategic, Wall,
  // Lines, Spiral, Radial), not only the one that exposed it.
  function openVirtualInspector(virtualId, nearDay) {
    const { chronolog } = app;
    const fact = findVisibleFact(virtualId, nearDay);
    if (!fact) {
      app.toast("That generated fact is outside the current query window.", true);
      return;
    }
    const pattern = chronolog.patterns[fact.event.provenance?.pattern];
    if (!pattern?.templateEvent) {
      app.toast("That occurrence's series is missing, so there is nothing to edit.", true);
      return;
    }
    openEventInspector(pattern.templateEvent, { occurrence: fact });
  }

  // Swap an already-open editor into occurrence mode. This is the one place a
  // materialization is created, and it is created because the user explicitly asked
  // to edit this occurrence alone — not as a side effect of opening anything.
  function editThisOccurrence(fact) {
    const { history } = app;
    const prepared = prepareMaterialization(fact);
    history.executeDelta(
      "Edit one occurrence",
      (documentValue) => applyMaterialization(documentValue, prepared),
      (documentValue) => revertMaterialization(documentValue, prepared),
      { preserveRecurrence: true, ...materializationOps(prepared) }
    );
    openEventInspector(prepared.event.id);
  }

  // The mode toggle. It is deliberately two buttons rather than a checkbox: the two
  // modes edit two different objects, and a checkbox would imply one object with a
  // property. There is no stop-repeating affordance on either side — ending a series
  // is an end-staple on its body (staple anchoring), not a command on whichever
  // occurrence happened to be open.
  function seriesModeToggle(mode, occurrenceLabel) {
    const series = mode === "series";
    return `
    <div class="series-mode-toggle" role="group" aria-label="What this edit changes">
      <button class="instrument-button${series ? " primary" : ""}" id="mode-series" type="button"
        aria-pressed="${series}">Whole series</button>
      <button class="instrument-button${series ? "" : " primary"}" id="mode-occurrence" type="button"
        aria-pressed="${!series}">${escapeHTML(occurrenceLabel)}</button>
    </div>`;
  }

  function openEventInspector(eventId, { occurrence = null } = {}) {
    const { chronolog, engine, session } = app;
    if (!resolveProvisionalDraft(eventId)) return false;
    const event = chronolog.events[eventId];
    if (!event) return false;
    session.inspector = { type: "event", id: eventId };
    const relation = primaryRelation(eventId);
    const completed = temporalRelations(eventId).find((item) => item.role === "completed");
    const duration = friendlyDuration(event);
    const calendars = calendarFrames(chronolog);
    // Importance frames appear WITH ordinary groups now (ROADMAP #9: the split
    // dropdown is the bad semantics this item deletes) -- an importance frame
    // is authored exactly like a group already (its base traits always
    // include "group"; frame-edit.js's kind-switching is additive), so the
    // Groups checkboxes are the one membership surface for both. There is no
    // separate "Visible in" control any more (owner item 8: "Visible in
    // dropdown on Events is terrible and clunky, and should be removed,
    // Display weight, and frame membership are the dials on that control") --
    // Groups membership plus the weight readout below are the two remaining
    // dials, and `event.display.lenses` (an existing document's authored data)
    // is read by src/projections.js untouched; nothing here writes it any more.
    const allGroups = groupFrames(chronolog);
    const recurrence = findRecurrencePattern(chronolog, eventId);
    const originalRecurrenceChoice = recurrenceFormChoice(recurrence);
    const recurrenceEnd = recurrenceEndMode(recurrence?.rrule);
    const completedParts = relationDateParts(completed);
    // The display-side union (engine.isDisplayGroup) already includes
    // importance-frame membership, direct or nested, so the manual union this
    // used to build by hand from `eventRelations` is gone -- this is the
    // shape it was hinting at.
    const membershipReasons = new Map(engine.eventDisplayGroupMemberships(eventId)
      .map(({ group, provenance }) => [group, provenance]));
    const memberships = new Set(membershipReasons.keys());
    const membershipExplanation = (groupId) => (membershipReasons.get(groupId) || [])
      .map((reason) => reason.kind === "authored" ? "authored membership"
        : reason.kind === "query" ? "live query"
          : `nested through ${reason.via}`)
      .join("; ");
    const objectKind = objectKindForEvent(event);
    const startParts = relationDateParts(relation);
    // The weight readout (owner item 8's other half): "there is no clarity
    // into how or what ... no clear way to see the display weight either base
    // or modified." `explainFactWeight` already derives the full base ->
    // per-group -> final chain (src/visual-language.js); the editor only
    // renders it, read-only -- the formula itself is authored on the frame
    // (Frames panel), not here.
    const weightReadout = weightReadoutModel(explainFactWeight({ document: chronolog, engine }, { event }));
    const wrapper = document.createElement("form");
    wrapper.className = "event-form";
    // Which object is this form actually editing? Three cases: the template of a
    // series opened from one of its occurrences (series mode, with a live occurrence
    // to swap to); a materialized occurrence (occurrence mode, able to swap back to
    // its series); or an ordinary event, which gets no toggle at all.
    const seriesMode = occurrence
      ? "series"
      : event.provenance?.kind === "explicit" && event.provenance?.pattern ? "occurrence" : null;
    const occurrenceLabel = occurrence
      ? `Only ${formatCivil(occurrence.coordinate, true)}`
      : "Only this occurrence";
    wrapper.innerHTML = `
    ${seriesMode ? seriesModeToggle(seriesMode, occurrenceLabel) : ""}
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
    <div class="form-row recurrence-row" data-recurrence-row>
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
    <div class="form-row recurrence-options">
      <label class="field"><span>Ends</span>
        <select name="endMode">
          ${[["never", "Never"], ["count", "After a number of times"], ["until", "On a date"]]
            .map(([value, label]) => `<option value="${value}" ${recurrenceEnd === value ? "selected" : ""}>${label}</option>`).join("")}
        </select>
      </label>
      <label class="field" data-end-count><span>Times</span>
        <input name="count" type="number" min="1" max="10000" value="${escapeHTML(recurrence?.rrule?.COUNT || "")}">
      </label>
      <label class="field" data-end-until><span>Last date</span>
        <input name="until" type="date" value="${escapeHTML(recurrenceUntilDate(recurrence?.rrule?.UNTIL))}">
      </label>
    </div>
    <div class="form-row" data-completed-field>
      <label class="field"><span>Completed date (optional)</span>
        <input name="completedDate" type="date" value="${escapeHTML(completedParts.date)}">
      </label>
      <label class="field"><span>Completed time</span>
        <input name="completedTime" type="time" step="60" value="${escapeHTML(completedParts.time)}">
      </label>
    </div>
    <label class="field"><span>Description</span>
      <textarea name="description">${escapeHTML(event.payload?.description || "")}</textarea>
    </label>
    <label class="field"><span>Location or meeting link</span>
      <input name="location" value="${escapeHTML(event.payload?.location || "")}" placeholder="Room, address, Teams, Zoomâ€¦">
    </label>
    <div class="form-row event-color-row">
      <label class="field"><span>Event color</span><input name="eventColor" type="color" value="${escapeHTML(event.display?.color || "#d4552d")}" data-explicit="${event.display?.color ? "true" : "false"}"></label>
      <button class="instrument-button" id="inherit-event-color" type="button" title="Remove this event's own color; it goes back to inheriting from its frame or group">Inherit color</button>
    </div>
    <div class="weight-readout" data-weight-readout>${weightReadoutMarkup(weightReadout)}</div>
    <div class="field staples-section" data-staples-section>
      <span>Staples</span>
      <ul class="staple-list" data-staple-list></ul>
      <div class="staple-extent" data-staple-extent></div>
      <div class="staple-add-row">
        ${recurrence ? `<label class="field"><span>Applies to</span>
          <select name="stapleScope">
            <option value="series">This series</option>
            <option value="object">This event</option>
          </select>
        </label>` : ""}
        <label class="field"><span>Kind</span>
          <select name="stapleKind" data-staple-kind></select>
        </label>
        <label class="field" data-staple-role-field hidden><span>Anchors</span>
          <select name="stapleRole" data-staple-role>
            ${ANCHOR_ROLE_ORDER.map((role) => `<option value="${role}">${role}</option>`).join("")}
            <option value="${CUSTOM_ANCHOR_ROLE}">Named point…</option>
          </select>
        </label>
        <label class="field" data-staple-role-name-field hidden><span>Point name</span>
          <input name="stapleRoleName" placeholder="e.g. shift handover">
        </label>
        <div class="form-row">
          <label class="field"><span>Date</span><input name="stapleDate" type="date"></label>
          <label class="field"><span>Time (optional)</span><input name="stapleTime" type="time" step="60"></label>
        </div>
        <label class="check-chip"><input type="checkbox" name="stapleFuzzy" data-staple-fuzzy> Fuzzy</label>
        <div class="form-row" data-staple-spread-fields hidden>
          <label class="field"><span>Before</span>
            <input name="stapleSpreadBeforeAmount" inputmode="decimal" placeholder="0">
            <select name="stapleSpreadBeforeUnit">${magnitudeUnitOptions()}</select>
          </label>
          <label class="field"><span>After</span>
            <input name="stapleSpreadAfterAmount" inputmode="decimal" placeholder="0">
            <select name="stapleSpreadAfterUnit">${magnitudeUnitOptions()}</select>
          </label>
        </div>
        <div class="form-row" data-staple-offset-field hidden>
          <label class="field"><span>Offset from start</span>
            <input name="stapleOffsetAmount" inputmode="decimal" placeholder="0">
            <select name="stapleOffsetUnit">${magnitudeUnitOptions()}</select>
          </label>
        </div>
        <div class="staple-rule-fields" data-staple-rule-fields hidden>
          <div class="form-row">
            <label class="field"><span>Then repeats</span>
              <select name="stapleRuleRepeat" data-staple-rule-repeat>
                ${[["", "Nothing follows (ends here)"], ["DAILY", "Daily"], ["WEEKDAYS", "Weekdays (Mon–Fri)"], ["WEEKLY", "Weekly"], ["MONTHLY", "Monthly"], ["YEARLY", "Yearly"]]
                  .map(([value, label]) => `<option value="${value}">${label}</option>`).join("")}
              </select>
            </label>
            <label class="field"><span>Every</span>
              <input name="stapleRuleInterval" type="number" min="1" max="999" value="1">
            </label>
          </div>
          <div class="form-row">
            <label class="field"><span>New rule starts</span><input name="stapleRuleDate" type="date"></label>
            <label class="field"><span>At</span><input name="stapleRuleTime" type="time" step="60"></label>
          </div>
          <div class="form-row">
            <label class="field"><span>New duration</span>
              <input name="stapleRuleDurationAmount" inputmode="decimal" placeholder="0">
              <select name="stapleRuleDurationUnit">${magnitudeUnitOptions()}</select>
            </label>
          </div>
        </div>
        <button class="instrument-button" type="button" data-add-staple>Add staple</button>
      </div>
      <p class="field-note">An open collection -- add as many staples as this ${recurrence ? "event or its series" : "event"} needs, of any kind above (owner ruling: an end staple is one registered kind, not a special case). An end staple stops a series' projection there without changing what "Ends" above says; other kinds anchor a start, end, midpoint, or named point, alone or fuzzed, and combine to derive a magnitude. A rule-change staple partitions the series and carries the rule that follows it -- leave "Then repeats" blank and it simply ends there instead, which is the same choice as starting a separate series. Add/remove act immediately, each its own undoable step. Removing a staple restores whatever it was authored over.</p>
    </div>
    <div class="field" data-groups-field><span>Groups</span>
      <div class="check-row">
        ${allGroups.map((frame) => `<label class="check-chip" title="${escapeHTML(membershipExplanation(frame.id))}" style="--group-color:${escapeHTML(frame.color || "#2e8b57")}">
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
      ${drafts.has(eventId) ? `<button class="instrument-button" id="cancel-draft" type="button">Cancel</button>` : ""}
      <button class="instrument-button danger" id="delete-object" type="button">Delete</button>
    </div>`;
    const syncRecurrenceFields = () => {
      wrapper.classList.toggle("has-recurrence", Boolean(wrapper.elements.repeat.value));
      // COUNT and UNTIL are mutually exclusive in RFC 5545, so only the chosen
      // one is offered — and the unused input is disabled as well as hidden, so a
      // stale value cannot be submitted from a field nobody can see.
      const mode = wrapper.elements.endMode.value;
      wrapper.querySelector("[data-end-count]").hidden = mode !== "count";
      wrapper.querySelector("[data-end-until]").hidden = mode !== "until";
      wrapper.elements.count.disabled = mode !== "count";
      wrapper.elements.until.disabled = mode !== "until";
    };
    const syncObjectKind = () => {
      const kind = normalizeObjectKind(wrapper.elements.objectKind.value);
      const definition = OBJECT_KINDS[kind];
      wrapper.querySelector("[data-object-date-label]").textContent = kind === "todo" ? "Observed date" : kind === "note" ? "Pinned date" : "Start date";
      wrapper.querySelector("[data-object-time-label]").textContent = kind === "todo" ? "Observed time" : kind === "note" ? "Pinned time" : "Start time";
      wrapper.querySelector("[data-duration-row]").hidden = definition.zeroDuration;
      wrapper.elements.duration.disabled = definition.zeroDuration;
      wrapper.elements.unit.disabled = definition.zeroDuration;
      wrapper.querySelector("[data-completed-field]").hidden = kind !== "todo";
      wrapper.elements.completedDate.disabled = kind !== "todo";
      wrapper.elements.completedTime.disabled = kind !== "todo";
    };
    wrapper.elements.repeat.addEventListener("change", syncRecurrenceFields);
    wrapper.elements.endMode.addEventListener("change", syncRecurrenceFields);
    wrapper.elements.objectKind.addEventListener("change", syncObjectKind);
    // The color field itself carries whether it is "set" — no separate toggle
    // to fall out of sync with it. Picking a color makes it explicit; Inherit
    // color is the one way back to unset, since a color <input> always holds
    // some hex value and so cannot represent "no color" on its own.
    wrapper.elements.eventColor.addEventListener("input", () => {
      wrapper.elements.eventColor.dataset.explicit = "true";
    });
    wrapper.querySelector("#inherit-event-color").addEventListener("click", () => {
      wrapper.elements.eventColor.dataset.explicit = "false";
    });
    syncRecurrenceFields();
    syncObjectKind();

    // The staples section: an open collection, not the bespoke end-staple
    // field it replaces (owner item 4: "I see no clear mechanism to add an
    // arbitrary number or type of staples"). Add/remove act immediately, each
    // its own undoable transaction, independent of this form's own Save --
    // so a staple placed a moment ago survives Cancel/Delete acting on
    // everything else, and vice versa.
    const stapleSection = wrapper.querySelector("[data-staples-section]");
    const stapleList = stapleSection.querySelector("[data-staple-list]");
    const stapleExtent = stapleSection.querySelector("[data-staple-extent]");
    const stapleScopeField = wrapper.elements.stapleScope || null;
    const stapleKindField = stapleSection.querySelector("[data-staple-kind]");
    const stapleRoleFieldWrap = stapleSection.querySelector("[data-staple-role-field]");
    const stapleRoleField = stapleSection.querySelector("[data-staple-role]");
    const stapleRoleNameFieldWrap = stapleSection.querySelector("[data-staple-role-name-field]");
    const stapleFuzzyField = stapleSection.querySelector("[data-staple-fuzzy]");
    const stapleSpreadFieldsWrap = stapleSection.querySelector("[data-staple-spread-fields]");
    const stapleOffsetFieldWrap = stapleSection.querySelector("[data-staple-offset-field]");
    const stapleRuleFieldsWrap = stapleSection.querySelector("[data-staple-rule-fields]");

    function currentStapleScope() {
      return stapleScopeField ? stapleScopeField.value : "object";
    }

    // The registry-driven dropdown, refreshed whenever the scope toggle
    // changes -- a series-only kind must not be offered while adding a
    // staple straight to a bare, non-recurring event.
    function syncStapleKindOptions() {
      const scope = currentStapleScope();
      const options = stapleKindOptions(scope);
      const previous = stapleKindField.value;
      stapleKindField.innerHTML = options.map(([value, label]) => `<option value="${value}">${escapeHTML(label)}</option>`).join("");
      stapleKindField.value = options.some(([value]) => value === previous) ? previous : (options[0]?.[0] || "");
      syncStapleRoleVisibility();
    }

    function syncStapleRoleVisibility() {
      const definition = stapleKind(stapleKindField.value);
      const anchors = Boolean(definition?.anchors);
      stapleRoleFieldWrap.hidden = !anchors;
      const named = anchors && stapleRoleField.value === CUSTOM_ANCHOR_ROLE;
      stapleRoleNameFieldWrap.hidden = !named;
      stapleOffsetFieldWrap.hidden = !named;
      // Only a kind that can carry a following rule offers one. The registry
      // says which (`carriesRule`), so adding a future kind that partitions a
      // series gets this sub-editor without a second list of kind names here.
      stapleRuleFieldsWrap.hidden = !definition?.carriesRule;
    }

    stapleScopeField?.addEventListener("change", syncStapleKindOptions);
    stapleKindField.addEventListener("change", syncStapleRoleVisibility);
    stapleRoleField.addEventListener("change", syncStapleRoleVisibility);
    stapleFuzzyField.addEventListener("change", () => {
      stapleSpreadFieldsWrap.hidden = !stapleFuzzyField.checked;
    });

    // Both the series' own staples (when this event is a series template) and
    // the event's own object staples render together, in one list -- an end
    // staple is one row among them, not a sibling control. Re-derived fresh
    // (not captured once at open time) so the list and the derived-extent
    // readout stay correct across this card's own live-edited lifetime.
    function refreshStaplesSection() {
      const pattern = findRecurrencePattern(chronolog, eventId);
      const rows = [
        ...(pattern ? staplesForSeries(chronolog, pattern.id).map((staple) => stapleRowModel(staple, "series")) : []),
        ...staplesForObject(chronolog, eventId).map((staple) => stapleRowModel(staple, "object"))
      ];
      stapleList.innerHTML = rows.map(stapleRowMarkup).join("") || `<li class="staple-list-empty">No staples yet.</li>`;
      stapleExtent.innerHTML = extentReadoutMarkup(extentReadoutModel(resolveObjectExtent(chronolog, engine, eventId)));
    }

    stapleSection.querySelector("[data-add-staple]").addEventListener("click", () => {
      try {
        const scope = currentStapleScope();
        const pattern = findRecurrencePattern(chronolog, eventId);
        const targetId = scope === "series" ? pattern?.id : eventId;
        const input = buildStapleInput({
          scope,
          targetId,
          kind: stapleKindField.value,
          role: stapleRoleField.value,
          roleName: wrapper.elements.stapleRoleName?.value,
          dateText: wrapper.elements.stapleDate.value,
          timeText: wrapper.elements.stapleTime.value,
          frame: wrapper.elements.frame.value,
          fuzzy: stapleFuzzyField.checked,
          spreadBeforeAmount: wrapper.elements.stapleSpreadBeforeAmount.value,
          spreadBeforeUnit: wrapper.elements.stapleSpreadBeforeUnit.value,
          spreadAfterAmount: wrapper.elements.stapleSpreadAfterAmount.value,
          spreadAfterUnit: wrapper.elements.stapleSpreadAfterUnit.value,
          offsetAmount: wrapper.elements.stapleOffsetAmount.value,
          offsetUnit: wrapper.elements.stapleOffsetUnit.value,
          ruleRepeat: wrapper.elements.stapleRuleRepeat?.value,
          ruleInterval: wrapper.elements.stapleRuleInterval?.value,
          ruleDateText: wrapper.elements.stapleRuleDate?.value,
          ruleTimeText: wrapper.elements.stapleRuleTime?.value,
          ruleDurationAmount: wrapper.elements.stapleRuleDurationAmount?.value,
          ruleDurationUnit: wrapper.elements.stapleRuleDurationUnit?.value
        });
        const stapleId = createId("relation");
        if (scope === "series") {
          app.executePatternChange("Add staple", targetId, (documentValue) => putStaple(documentValue, { ...input, id: stapleId }));
        } else {
          app.executeEventChange("Add staple", eventId, (documentValue) => putStaple(documentValue, { ...input, id: stapleId }));
        }
        wrapper.elements.stapleDate.value = "";
        wrapper.elements.stapleTime.value = "";
        refreshStaplesSection();
      } catch (error) {
        app.toast(error.message, true);
      }
    });

    stapleList.addEventListener("click", (clickEvent) => {
      const button = clickEvent.target.closest?.("[data-remove-staple]");
      if (!button) return;
      const row = button.closest("[data-staple-id]");
      const stapleId = row?.dataset.stapleId;
      if (!stapleId) return;
      if (row.dataset.stapleScope === "series") {
        const pattern = findRecurrencePattern(chronolog, eventId);
        if (pattern) app.executePatternChange("Remove staple", pattern.id, (documentValue) => removeStaple(documentValue, stapleId));
      } else {
        app.executeEventChange("Remove staple", eventId, (documentValue) => removeStaple(documentValue, stapleId));
      }
      refreshStaplesSection();
    });

    syncStapleKindOptions();
    refreshStaplesSection();

    const draft = drafts.get(eventId);
    if (draft) {
      draft.form = wrapper;
      const markDirty = () => { const live = drafts.get(eventId); if (live) live.dirty = true; };
      wrapper.addEventListener("input", markDirty);
      wrapper.addEventListener("change", markDirty);
    }
    openInspector(event.payload?.title || "Event", wrapper, "object", eventId);
    if (drafts.has(eventId)) focusInspectorEditor(eventId);

    wrapper.querySelector("#edit-series")?.addEventListener("click", () => {
      const pattern = chronolog.patterns[event.provenance?.pattern];
      if (pattern?.templateEvent) openEventInspector(pattern.templateEvent);
    });

    // Swapping to occurrence mode is what creates the materialization, and only then.
    wrapper.querySelector("#mode-occurrence")?.addEventListener("click", () => {
      if (!occurrence) return;
      editThisOccurrence(occurrence);
    });

    // Swapping back to the series. From a materialized occurrence this closes the
    // occurrence's card first, so that if nothing was changed the convergence
    // invariant retires it instead of leaving a fork the user cannot see.
    wrapper.querySelector("#mode-series")?.addEventListener("click", () => {
      if (occurrence) return;
      const pattern = chronolog.patterns[event.provenance?.pattern];
      if (!pattern?.templateEvent) return;
      dismissObjectCard(eventId);
      openEventInspector(pattern.templateEvent);
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
        const completedCoordinate = objectKindChoice === "todo" && data.get("completedDate")
          ? parseDateText(`${data.get("completedDate")} ${data.get("completedTime") || "00:00"}`)
          : null;
        const repeatChoice = String(data.get("repeat") || "");
        const repeat = repeatChoice === "WEEKDAYS" ? "WEEKLY" : repeatChoice;
        const interval = Math.max(1, Math.min(999, Number(data.get("interval")) || 1));
        const endMode = String(data.get("endMode") || "never");
        if (endMode === "until" && !String(data.get("until") || "").trim()) {
          throw new Error("Choose the date the series ends on, or set Ends to Never.");
        }
        if (endMode === "count" && !String(data.get("count") || "").trim()) {
          throw new Error("Choose how many times the series repeats, or set Ends to Never.");
        }
        if (repeat && !nextCoordinate) throw new Error("A repeating event needs a start date.");
        // Importance frames are just entries in "groups" now (the checkbox
        // list includes them directly), so there is no separate importance
        // selection to fold in here any more.
        const selectedGroups = new Set(data.getAll("groups").map(String));
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
          // There is no separate importance control any more, so a legacy
          // "important"/"landmark" trait is neither stripped nor reasserted
          // here -- it is just one of the traits the Advanced "Traits" field
          // already carries (traitsForObjectKind only ever touches the
          // kind-controlled traits), so it round-trips like any other
          // authored trait unless a user edits it there directly.
          target.traits = traitsForObjectKind(
            String(data.get("traits") || "event").split(",").map((item) => item.trim()).filter(Boolean),
            objectKindChoice
          );
          if (!target.traits.includes("event")) target.traits.unshift("event");
          // There is no "Visible in" control any more (owner item 8) -- an
          // event's `display.lenses`, if any document ever authored one, is
          // left exactly as it is here. `target.display` is still copied
          // shallowly so the color write below never mutates the original
          // object's `display` reference in place.
          target.display = { ...(target.display || {}) };
          const submittedColor = resolveSubmittedEventColor(
            wrapper.elements.eventColor.dataset.explicit === "true",
            data.get("eventColor")
          );
          // Precedence is the whole rule (AGENTS.md's color cascade, step 1):
          // set = override, unset = inherit. Deleting the field — not leaving
          // an empty string — is what lets resolveObjectColor's cascade see
          // "nothing here" and fall through to group/frame/fallback.
          if (submittedColor) target.display.color = submittedColor;
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
          // Series staples (the end-staple among them) are no longer written
          // from this submit handler at all -- they are the staples section's
          // own, separately committed, immediate transactions (see
          // `refreshStaplesSection` and its Add/Remove handlers above), so
          // there is no `activePatternId` to thread through here any more.
          if (!repeat && existingPattern) {
            delete documentValue.patterns[existingPattern.id];
          } else if (repeat) {
            let rrule = { ...(existingPattern?.rrule || {}), FREQ: repeat, INTERVAL: String(interval) };
            if (repeatChoice !== originalRecurrenceChoice) {
              delete rrule.BYDAY;
              delete rrule.BYMONTHDAY;
              delete rrule.BYMONTH;
            }
            if (repeatChoice === "WEEKDAYS") rrule.BYDAY = "MO,TU,WE,TH,FR";
            rrule = applyRecurrenceEnd(rrule, {
              mode: endMode,
              count: data.get("count"),
              until: data.get("until")
            });
            if (existingPattern) {
              writePatternRule(existingPattern, rrule);
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
        // Saving closes this object's card only. Any other editor the user left open
        // stays open with its own draft intact.
        dismissObjectCard(eventId);
      } catch (error) {
        app.toast(error.message, true);
      }
    });

    wrapper.querySelector("#delete-object").addEventListener("click", () => {
      const wasProvisional = drafts.has(eventId);
      if (wasProvisional) drafts.delete(eventId);
      // The event's own object-scoped staples travel with it in this same
      // transaction (src/ui/transactions.js's `cascadeRemovedObjects`, the
      // object-keyed sibling of the series' `cascadeRemovedPatterns`) -- no
      // separate sweep needed here.
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
      dismissObjectCard(eventId);
    });

    wrapper.querySelector("#cancel-draft")?.addEventListener("click", () => {
      if (discardProvisionalDraft(eventId)) dismissObjectCard(eventId);
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
      drafts.set(eventId, { id: eventId, dirty: false, form: null });
      if (!openEventInspector(eventId)) {
        discardProvisionalDraft(eventId);
        dismissObjectCard(eventId);
      }
    } catch (error) {
      // Creating the draft deferred autosave before this failed. Either the draft
      // cleanup releases that deferral or this does — never neither, or the
      // document stays permanently unsaveable.
      if (!discardProvisionalDraft(eventId)) app.store.endDeferred();
      app.toast(`Could not create event: ${error.message}`, true);
    }
  }

  // The drawer had one close button in its header. A card is closed from its own
  // handle in the rail, which the dock owns, so there is no global close control
  // to wire here any more.

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
