import {
  Rational,
  coordinate,
  formatCivil,
  levelValue
} from "../exact.js";
import { GREGORIAN_LAW, coordinateLaw, magnitudeLaw } from "../coordinate-law.js";
import {
  coordinateEntryPlaceholder,
  coordinatePickerLadder,
  formatCoordinateEntry,
  parseCoordinateEntry
} from "../coordinate-entry.js";
import {
  addEvent,
  addPattern,
  addRelation,
  clone,
  createId,
  durationMagnitude,
  eventRelations,
  frameEnd,
  objectEnd,
  putStaple,
  removeStaple,
  seriesEnd
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
  DEFAULT_POINT,
  EXTENT_POINTS,
  effectiveObjectStaples,
  endScope,
  endScopePair,
  isFuzzyStaple,
  placementRelation,
  resolveObjectExtent,
  STAPLE_KINDS,
  stapleEndFor,
  stapleKind,
  stapleKindScopes,
  stapleOtherEnd,
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

// Parses the Completed field's own "year-month-day[ hour:minute]" text into a
// coordinate. This is the ONE date/time-shaped field left in the card — a
// todo's completion names a distinct instant (when it was finished), never
// where the object sits, so it is not a placement staple and stays outside
// the variable-precision coordinate-entry field the staple rows use.
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

// A relation's date/time split into the two text fields the Completed field
// alone still holds. Pure, so that field can format its value without a DOM.
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
// scope actually being authored ("object" -- this event's own connections --
// or "series" -- the series' own body). `correspondence` is a frame-to-frame
// concept (AGENTS.md's four-frame-concepts seam) and never belongs on an
// object/series editor even though its own scope set happens not to include
// either -- excluded explicitly rather than relying on that coincidence.
export function stapleKindOptions(scope) {
  return Object.entries(STAPLE_KINDS)
    .filter(([kindName]) => kindName !== "correspondence" && stapleKindScopes(kindName).includes(scope))
    .map(([value, definition]) => [value, definition.label]);
}

// The sentinel for "a point the user named" in the near/far point selects,
// shared by both ends because both ask the identical question: which point of
// this thing does the connection touch.
export const CUSTOM_POINT = "__custom__";

function magnitudeOrNull(amount, unit) {
  const text = String(amount ?? "").trim();
  if (!text) return null;
  return durationMagnitude(text, unit || "minute");
}

// One end's point plus its optional named-point offset -- the same choice
// asked of the near end (which point of THIS object is anchored) and the far
// end (which point of the OTHER object the connection touches), so it is
// resolved once rather than twice.
function resolvePointEnd(builder, id, point, pointName, offsetAmount, offsetUnit) {
  const isCustom = point === CUSTOM_POINT;
  const resolved = isCustom ? String(pointName || "").trim() : (String(point || "").trim() || DEFAULT_POINT);
  if (isCustom && !resolved) throw new Error("Name this point.");
  const offset = isCustom ? magnitudeOrNull(offsetAmount, offsetUnit) : null;
  return builder(id, resolved, offset);
}

// The staple row's own decision, pulled out of the DOM exactly as
// `resolveSubmittedEventColor` and test/frame-creation.test.js's pattern
// establish (this form is too data-rich for the repo's stub-DOM/FormData
// harness). Builds the two-ended record `putStaple` expects: `scope`/
// `targetId` name the NEAR end (this event or this series), `farScope`/
// `farId` name the OTHER thing the connection touches -- a calendar frame
// (needing `coordinateText` parsed under that frame's own law, the owner's
// single variable-precision field) or another object (needing only a point).
// Throws a user-facing message on anything unresolvable.
export function buildStapleInput({
  scope,
  targetId,
  kind,
  nearPoint = DEFAULT_POINT,
  nearPointName = "",
  nearOffsetAmount = "",
  nearOffsetUnit = "minute",
  farScope = "frame",
  farId,
  farPoint = DEFAULT_POINT,
  farPointName = "",
  farOffsetAmount = "",
  farOffsetUnit = "minute",
  coordinateText = "",
  law = null,
  fuzzy = false,
  spreadBeforeAmount = "",
  spreadBeforeUnit = "minute",
  spreadAfterAmount = "",
  spreadAfterUnit = "minute",
  ruleRepeat = "",
  ruleInterval = "1",
  ruleCoordinateText = "",
  ruleLaw = null,
  ruleDurationAmount = "",
  ruleDurationUnit = "minute"
} = {}) {
  const definition = stapleKind(kind);
  if (!definition) throw new Error("Choose a staple kind.");
  if (!targetId) throw new Error(scope === "series" ? "This event has no series to staple yet." : "Nothing to staple this to.");

  const near = scope === "series"
    ? seriesEnd(targetId)
    : resolvePointEnd(objectEnd, targetId, nearPoint, nearPointName, nearOffsetAmount, nearOffsetUnit);

  // A series' rules are cut by instants, never by another object -- the
  // registry's own `connects` says so (every series-carrying kind pairs only
  // with "frame") -- so the far end is always a frame once the near end is a
  // series, regardless of what the far-scope control happens to hold.
  const effectiveFarScope = scope === "series" ? "frame" : farScope;
  let far;
  if (effectiveFarScope === "frame") {
    if (!farId) throw new Error("Choose the calendar frame this staple connects to.");
    if (!law) throw new Error("That frame declares no coordinate law to enter a position under.");
    const text = String(coordinateText || "").trim();
    if (!text) throw new Error("A staple needs a coordinate.");
    far = frameEnd(farId, parseCoordinateEntry(text, law).coordinate);
  } else if (effectiveFarScope === "object") {
    if (!farId) throw new Error("Choose the other object this staple connects to.");
    far = resolvePointEnd(objectEnd, farId, farPoint, farPointName, farOffsetAmount, farOffsetUnit);
  } else {
    throw new Error("Choose what this staple connects to.");
  }

  // A kind is defined by the PAIR of scopes it may join (src/staples.js), so
  // the check is one canonical-key lookup rather than a hand-written list of
  // which kinds go where -- the owner's own ruling for `stapleKindOptions`,
  // applied again here because a stale dropdown or a direct caller must not
  // be able to author a connection the registry does not recognize.
  const pair = endScopePair(scope === "series" ? "series" : "object", effectiveFarScope);
  if (!definition.connects.includes(pair)) {
    throw new Error(
      `${definition.label} cannot connect ${scope === "series" ? "a series" : "an event"} to `
      + `${effectiveFarScope === "frame" ? "a calendar frame" : "another object"}.`
    );
  }

  const input = { kind, ends: [near, far] };
  if (fuzzy) {
    // Asymmetric on purpose (src/staples.js's own note): "about 5ish" and a
    // hard ceiling are different shapes, so before/after are two independent
    // fields, never one +/-. Fuzziness is authored here and ONLY here --
    // never inferred from how deep the coordinate above was typed.
    input.spread = {
      before: magnitudeOrNull(spreadBeforeAmount, spreadBeforeUnit) || durationMagnitude("0", "minute"),
      after: magnitudeOrNull(spreadAfterAmount, spreadAfterUnit) || durationMagnitude("0", "minute")
    };
  }
  // The following rule, for a kind that can carry one (LEXICON's Rob-and-John:
  // "then either define a new rule post-staple or a new series, on
  // preference"). Blank repeat IS the other preference: the staple partitions
  // and nothing follows, which is what an end staple is.
  const repeatChoice = String(ruleRepeat || "").trim();
  if (definition.carriesRule && repeatChoice) {
    const frequency = repeatChoice === "WEEKDAYS" ? "WEEKLY" : repeatChoice;
    const interval = Math.max(1, Math.min(999, Number(ruleInterval) || 1));
    const rrule = { FREQ: frequency, INTERVAL: String(interval) };
    if (repeatChoice === "WEEKDAYS") rrule.BYDAY = "MO,TU,WE,TH,FR";
    const head = { rrule };
    const ruleText = String(ruleCoordinateText || "").trim();
    if (ruleText) {
      head.coordinate = parseCoordinateEntry(ruleText, ruleLaw || law).coordinate;
      head.frame = farId;
    }
    const magnitude = magnitudeOrNull(ruleDurationAmount, ruleDurationUnit);
    if (magnitude) head.magnitude = magnitude;
    input.payload = { ...(input.payload || {}), rule: head };
  }
  return input;
}

// The series' own staples, wrapped in the same {implicit,relation,staple,
// kind,near,far} row shape `effectiveObjectStaples` returns for an object --
// so one row model and one row markup function serve both lists, and an end
// staple really is one row among them rather than a sibling control.
function seriesStapleRow(staple, patternId) {
  const near = stapleEndFor(staple, patternId) || seriesEnd(patternId);
  return { implicit: false, relation: null, staple, kind: staple.kind, near, far: stapleOtherEnd(staple, near) };
}

// A magnitude's amount/unit in whatever unit divides it evenly, read through
// `governing`'s own law -- the one derivation `friendlyDuration` (an event's
// duration) and a staple's fuzzy spread both need, so it lives once. A day is
// still 86400 seconds under an unedited law; an edited human-time law
// (Hour:Day:23) changes what "1" in a given unit means, which is why this
// asks the law rather than a fixed {day,hour,minute,second} table.
function friendlyMagnitudeAmount(magnitude, governing) {
  if (!magnitude) return { amount: "", unit: "minute" };
  const law = magnitudeLaw(magnitude, governing);
  const days = law.magnitudeDays(magnitude);
  if (days.compare(0) <= 0) return { amount: "0", unit: "minute" };
  for (const unit of ["day", "hour", "minute"]) {
    const perDay = law.unitsPerDay(unit);
    if (perDay === null) continue;
    const amount = days.mul(perDay);
    if (amount.d === 1n) return { amount: amount.toJSON(), unit };
  }
  const totalSeconds = days.mul(law.secondsPerDay()).add(new Rational(1n, 2n)).floor();
  return { amount: totalSeconds.toString(), unit: "second" };
}

// One list row's display fields, pure over a row from `effectiveObjectStaples`
// (or `seriesStapleRow`, the series-scoped sibling) -- so the list's markup is
// a dumb map over this, and it is what a test drives directly instead of the
// DOM. EVERY row -- implicit or authored, object-scoped or series-scoped --
// comes out this same shape: one `coordinateText` (never a date/time pair),
// the near point, and what the far end names. An implicit row's `id` names
// the ATTACHMENT RELATION it reads (there is no staple to name), which is
// what keeps an edit to it from minting a second, contradicting record.
export function stapleRowModel(row, chronolog) {
  const definition = stapleKind(row.kind);
  const near = row.near || {};
  const nearScope = endScope(near);
  const far = row.far || null;
  const farScope = far ? endScope(far) : null;
  let coordinateText = "";
  let coordinatePlaceholder = "";
  let farLabel = null;
  let farPoint = null;
  if (farScope === "frame") {
    const law = coordinateLaw(chronolog, far.frame);
    coordinateText = formatCoordinateEntry(far.coordinate, law);
    coordinatePlaceholder = coordinateEntryPlaceholder(law);
    farLabel = chronolog?.frames?.[far.frame]?.title || far.frame;
  } else if (farScope === "object") {
    farPoint = far.point || DEFAULT_POINT;
    farLabel = chronolog?.events?.[far.object]?.payload?.title || far.object;
  } else if (farScope === "series") {
    farLabel = chronolog?.patterns?.[far.series]?.title || far.series;
  }
  const beforeFriendly = friendlyMagnitudeAmount(row.staple?.spread?.before || null, chronolog);
  const afterFriendly = friendlyMagnitudeAmount(row.staple?.spread?.after || null, chronolog);
  return {
    id: row.implicit ? (row.relation?.id || null) : (row.staple?.id || null),
    implicit: Boolean(row.implicit),
    scope: nearScope === "series" ? "series" : "object",
    targetId: nearScope === "series" ? near.series : near.object,
    kind: row.kind || null,
    kindLabel: definition?.label || row.kind || "Staple",
    nearPoint: nearScope === "object" ? (near.point || DEFAULT_POINT) : null,
    farScope,
    farId: farScope === "frame" ? far.frame : farScope === "object" ? far.object : farScope === "series" ? far.series : null,
    farLabel,
    farPoint,
    coordinateText,
    coordinatePlaceholder,
    fuzzy: row.implicit ? false : isFuzzyStaple(row.staple, chronolog),
    spreadBeforeAmount: beforeFriendly.amount,
    spreadBeforeUnit: beforeFriendly.unit,
    spreadAfterAmount: afterFriendly.amount,
    spreadAfterUnit: afterFriendly.unit
  };
}

// The implicit placement row's own edit: an attachment relation carries no
// `kind`, no `near`/`far` shape of its own, so its edit is patched directly
// rather than turned into a staple -- which is what keeps "no staple should
// be special" true for a row the user never explicitly created. Returns null
// for a blank field, which the caller reads as "clear the coordinate" (the
// same action `data-remove-staple` performs on this row).
export function implicitPlacementEdit(text, law) {
  const trimmed = String(text || "").trim();
  if (!trimmed) return null;
  const { coordinate: coordinateValue, depth } = parseCoordinateEntry(trimmed, law);
  return { coordinate: coordinateValue, parameters: { dateOnly: isDateOnlyDepth(law, depth) } };
}

// Whether a coordinate typed to this depth carries no time-of-day at all --
// derived from the law's own above/below-base split (AGENTS.md's coordinate
// law contract), never from a hardcoded "day" name, so a custom calendar's
// own date/time boundary is read the same way.
export function isDateOnlyDepth(law, depthName) {
  if (!depthName) return true;
  const baseIndex = law.levels.findIndex((level) => level.name === law.baseLevel);
  const depthIndex = law.levels.findIndex((level) => level.name === depthName);
  if (baseIndex === -1 || depthIndex === -1) return true;
  return depthIndex <= baseIndex;
}

// The combined "connects to" selection -- one flat option list rather than a
// scope select plus an id select, because the id ALREADY carries its own
// colon (`calendar:test`) and a "frame:"/"object:" prefix on top of that is
// unambiguous to split on the first colon.
function parseFarSelection(value) {
  const raw = String(value || "");
  const separator = raw.indexOf(":");
  if (separator <= 0) return { scope: null, id: null };
  const scope = raw.slice(0, separator);
  const id = raw.slice(separator + 1);
  return (scope === "frame" || scope === "object") && id ? { scope, id } : { scope: null, id: null };
}

function farConnectionOptions(chronologDocument, excludeObjectId) {
  const frames = calendarFrames(chronologDocument).map((frame) => ({ value: `frame:${frame.id}`, label: `Calendar: ${frame.title}` }));
  const objects = Object.values(chronologDocument.events || {})
    .filter((event) => event.id !== excludeObjectId)
    .map((event) => ({ value: `object:${event.id}`, label: `Event: ${event.payload?.title || "(untitled)"}` }))
    .sort((left, right) => left.label.localeCompare(right.label));
  return { frames, objects };
}

// The law the extent's own coordinate space is read under, falling back to the
// registered standard when there is no document or the frame's declaration cannot
// be resolved -- a broken frame must not blank the readout, the same direction
// `displayLaw` takes.
function extentLaw(extent, governing) {
  const frameId = extent?.frame || null;
  if (!governing || !frameId || !governing.frames?.[frameId]) return GREGORIAN_LAW;
  try {
    return coordinateLaw(governing, frameId);
  } catch {
    return GREGORIAN_LAW;
  }
}

// The derived-extent readout's display fields, pure over `resolveObjectExtent`'s
// own result -- civil-date formatting and the overdetermined/unresolved
// staples' kind labels are the only transformation the editor applies, so
// this is that transformation in one testable place. `unresolved` is
// surfaced the same way `overdetermined` already is (owner item: a
// connection that could not resolve must be visible, not silent) -- never
// averaged, never hidden.
// `governing`, optional and trailing, is the document whose law the resolved
// instants should be READ BACK under. The extent reports its own coordinate space
// (`extent.frame`, propagated along a connection chain), so a readout that
// formatted through the registered standard would print an edited law's hours as
// though they were standard ones -- the same class of silent wrongness
// src/coordinate-law.js exists to remove. Absent, this reads the registered
// standard, which is the honest answer for a caller that has no document.
export function extentReadoutModel(extent, governing = null) {
  const law = extentLaw(extent, governing);
  const civilText = (days) => (days === null || days === undefined ? null : formatCivil(law.fromDays(days), true));
  const describeItem = (item) => ({
    kind: item.staple?.kind || null,
    kindLabel: stapleKind(item.staple?.kind)?.label || item.staple?.kind || "Staple",
    role: item.role || null,
    reason: item.reason
  });
  return {
    start: civilText(extent?.startDays ?? null),
    end: civilText(extent?.endDays ?? null),
    source: extent?.source || "unstapled",
    derivedMagnitude: Boolean(extent?.derivedMagnitude),
    overdetermined: (extent?.overdetermined || []).map(describeItem),
    unresolved: (extent?.unresolved || []).map(describeItem)
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
// (Duration, a fuzzy staple's before/after spread, a named point's offset) --
// one list, so a new unit is one edit instead of three.
function magnitudeUnitOptions(selected = "minute") {
  return [["minute", "Minutes"], ["hour", "Hours"], ["day", "Days"], ["second", "Seconds"]]
    .map(([value, label]) => `<option value="${value}" ${value === selected ? "selected" : ""}>${label}</option>`)
    .join("");
}

// The render helpers below are dumb maps over the pure `*Model` functions
// above -- traced by hand rather than driven through the DOM (the repo's
// stub-DOM harness cannot parse `innerHTML`/drive `FormData`; see
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

function stapleRowMarkup(model) {
  const coordinateField = model.farScope === "frame" ? `
    <span class="staple-coordinate-wrap">
      <input class="staple-coordinate-input" data-row-coordinate value="${escapeHTML(model.coordinateText)}" placeholder="${escapeHTML(model.coordinatePlaceholder)}">
      <button class="instrument-button" type="button" data-row-picker-toggle>Zoom…</button>
      <div class="staple-picker" data-row-picker hidden></div>
    </span>` : "";
  const farText = model.farLabel === null ? "" : `${escapeHTML(model.farLabel)}${model.farPoint ? ` (${escapeHTML(model.farPoint)})` : ""}`;
  const fuzzyControls = model.implicit ? "" : `
    <label class="check-chip"><input type="checkbox" data-row-fuzzy ${model.fuzzy ? "checked" : ""}> Fuzzy</label>
    <div class="form-row" data-row-spread ${model.fuzzy ? "" : "hidden"}>
      <label class="field"><span>Before</span>
        <input data-row-spread-before-amount inputmode="decimal" placeholder="0" value="${escapeHTML(model.spreadBeforeAmount)}">
        <select data-row-spread-before-unit>${magnitudeUnitOptions(model.spreadBeforeUnit)}</select>
      </label>
      <label class="field"><span>After</span>
        <input data-row-spread-after-amount inputmode="decimal" placeholder="0" value="${escapeHTML(model.spreadAfterAmount)}">
        <select data-row-spread-after-unit>${magnitudeUnitOptions(model.spreadAfterUnit)}</select>
      </label>
    </div>`;
  return `<li class="staple-row" data-staple-row
      data-implicit="${model.implicit}"
      data-staple-id="${escapeHTML(model.id || "")}"
      data-staple-scope="${model.scope}"
      data-target-id="${escapeHTML(model.targetId || "")}"
      data-far-frame="${escapeHTML(model.farScope === "frame" ? model.farId : "")}">
    <span class="staple-kind">${escapeHTML(model.kindLabel)}</span>
    ${model.nearPoint ? `<span class="staple-near">${escapeHTML(model.nearPoint)}</span>` : ""}
    <span class="staple-arrow">to</span>
    <span class="staple-far-label">${farText}</span>
    ${coordinateField}
    ${fuzzyControls}
    <button class="instrument-button danger" type="button" data-remove-staple>Remove</button>
  </li>`;
}

function extentReadoutMarkup(model) {
  const magnitudeNote = model.source === "anchors" ? "magnitude derived from anchors"
    : model.source === "anchor+magnitude" ? "an anchor plus this object's own duration"
      : model.source === "placement" ? "its own placement and duration"
        : model.source === "unresolved" ? "its placement could not be resolved"
          : "not stapled yet";
  const itemMarkup = (item) => `<li>${escapeHTML(item.kindLabel)}${item.role ? ` (${escapeHTML(item.role)})` : ""} — ${escapeHTML(item.reason)}</li>`;
  const overdetermined = model.overdetermined.map(itemMarkup).join("");
  const unresolved = model.unresolved.map(itemMarkup).join("");
  return `
    <p class="field-note staple-extent-note">Resolved extent: <strong>${model.start ? escapeHTML(model.start) : "unresolved"}</strong> to <strong>${model.end ? escapeHTML(model.end) : "unresolved"}</strong> (${escapeHTML(magnitudeNote)}).</p>
    ${overdetermined ? `<p class="field-note staple-extent-warning">Authored but not used for placement:</p><ul class="staple-overdetermined">${overdetermined}</ul>` : ""}
    ${unresolved ? `<p class="field-note staple-extent-warning">Could not resolve:</p><ul class="staple-unresolved">${unresolved}</ul>` : ""}`;
}

function fireChange(node) {
  if (typeof node.dispatch === "function") node.dispatch("change");
  else if (typeof node.dispatchEvent === "function") node.dispatchEvent(new Event("change"));
}

// The zoomable picker's markup for one rung. An unbounded rung (the root, or
// the continuous tail) NEVER materializes an option list -- the same
// overscale doctrine that keeps a 500-calendar document from paying for a
// document-wide enumeration at any one lookup.
function pickerRungMarkup(rung) {
  if (!rung.bounded) {
    return `<div class="staple-picker-rung">
      <span class="staple-picker-level">${escapeHTML(rung.label)}</span>
      <input type="text" inputmode="numeric" data-picker-field="${escapeHTML(rung.level)}" value="${rung.chosen !== null && rung.chosen !== undefined ? escapeHTML(String(rung.chosen)) : ""}">
    </div>`;
  }
  return `<div class="staple-picker-rung">
    <span class="staple-picker-level">${escapeHTML(rung.label)}</span>
    <select data-picker-field="${escapeHTML(rung.level)}">
      <option value="">—</option>
      ${rung.options.map((option) => `<option value="${escapeHTML(option.value)}" ${rung.chosen !== null && String(rung.chosen) === option.value ? "selected" : ""}>${escapeHTML(option.label)}</option>`).join("")}
    </select>
  </div>`;
}

// Drills coarse to fine off `coordinatePickerLadder`: picking a rung's value
// sets that level and reveals the next one, and stopping partway leaves the
// coordinate at exactly that depth. Writes through the SAME text field
// `parseCoordinateEntry` reads (via a plain "change" dispatch), so there is
// exactly one parser for both entry paths rather than a second one duplicated
// for the picker.
function renderPicker(container, input, getLaw) {
  const law = getLaw();
  if (!law) { container.innerHTML = ""; return; }
  let current = null;
  try { current = parseCoordinateEntry(input.value, law).coordinate; } catch { current = null; }
  container.innerHTML = coordinatePickerLadder(law, current).map(pickerRungMarkup).join("");
  for (const field of container.querySelectorAll("[data-picker-field]")) {
    field.addEventListener("change", () => {
      const levelName = field.dataset.pickerField;
      const levelIndex = law.levels.findIndex((level) => level.name === levelName);
      const tailIndex = law.levels.length - 1;
      const entries = [];
      for (let index = 0; index < levelIndex; index += 1) {
        const value = current?.levels?.find((entry) => entry.level === law.levels[index].name)?.value;
        if (value === undefined) break;
        entries.push({ level: law.levels[index].name, value });
      }
      const raw = String(field.value || "").trim();
      if (raw !== "") {
        entries.push({ level: levelName, value: levelIndex === tailIndex && tailIndex > 0 ? `0.${raw}` : raw });
      }
      input.value = entries.length ? formatCoordinateEntry(coordinate(entries), law) : "";
      fireChange(input);
      renderPicker(container, input, getLaw);
    });
  }
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

  // What the user typed as "90 minutes" must mean 90 of THIS EVENT's OWN
  // frame's minutes (normally `measure:human-time`, whose law an edit to
  // Hour:Day:23 changes) -- so the whole/fractional check reads through
  // `friendlyMagnitudeAmount`'s own law lookup, not a fixed
  // {day:86400,hour:3600,minute:60} table. Under an unedited law this is
  // byte-identical to before: a day is still 86400 seconds, an hour 3600.
  function friendlyDuration(event) {
    return friendlyMagnitudeAmount(event?.magnitudes?.duration, app.chronolog);
  }

  // Every duration this editor freshly authors defaults to `measure:human-time`
  // (`durationMagnitude`'s own default frame), so a newly created event's
  // duration must round-trip through THAT frame's own law -- an edited
  // human-time law (the owner's Hour:Day:23) has to apply to a value computed
  // here, not only to display. `magnitudeLaw`'s own missing-frame fallback
  // (the registered standard) keeps this safe for a document that has not
  // authored the frame at all.
  function humanTimeLaw() {
    return magnitudeLaw({ frame: "measure:human-time" }, app.chronolog);
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
    // One nominal second of slack either side of the rendered day, under the
    // SESSION's own display law (`app.session.law`, set by app.js) rather than
    // a bare 86400 -- a query window built from the standard assumption would
    // itself be the class of silent mismatch this fact-lookup exists to avoid.
    const slack = Rational.parse(1).div(app.session.law.secondsPerDay());
    return engine.queryFacts({
      frame: session.activeFrame,
      // The window is resolved BY the frame being queried, so it has to be
      // written in that frame's own law -- a standard-civil window handed to a
      // frame with edited hours names a different span than it reads as.
      start: app.session.law.fromDays(day.sub(slack)),
      end: app.session.law.fromDays(day.add(slack)),
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
  // node's own `dataset.factDay` -- every fact node already carries it, stamped once
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
          <select name="stapleScope" data-staple-scope>
            <option value="object">This event</option>
            <option value="series">This series</option>
          </select>
        </label>` : ""}
        <label class="field"><span>Kind</span>
          <select name="stapleKind" data-staple-kind></select>
        </label>
        <label class="field" data-staple-near-point-field><span>Anchors this event's</span>
          <select name="stapleNearPoint" data-staple-near-point>
            ${EXTENT_POINTS.map((point) => `<option value="${point}">${point}</option>`).join("")}
            <option value="${CUSTOM_POINT}">Named point…</option>
          </select>
        </label>
        <label class="field" data-staple-near-point-name-field hidden><span>Point name</span>
          <input name="stapleNearPointName" placeholder="e.g. shift handover">
        </label>
        <div class="form-row" data-staple-near-offset-field hidden>
          <label class="field"><span>Offset from this event's start</span>
            <input name="stapleNearOffsetAmount" inputmode="decimal" placeholder="0">
            <select name="stapleNearOffsetUnit">${magnitudeUnitOptions()}</select>
          </label>
        </div>
        <label class="field"><span>Connects to</span>
          <select name="stapleFar" data-staple-far></select>
        </label>
        <label class="field" data-staple-far-point-field hidden><span>At its</span>
          <select name="stapleFarPoint" data-staple-far-point>
            ${EXTENT_POINTS.map((point) => `<option value="${point}">${point}</option>`).join("")}
            <option value="${CUSTOM_POINT}">Named point…</option>
          </select>
        </label>
        <label class="field" data-staple-far-point-name-field hidden><span>Point name</span>
          <input name="stapleFarPointName" placeholder="e.g. shift handover">
        </label>
        <div class="form-row" data-staple-far-offset-field hidden>
          <label class="field"><span>Offset from that object's start</span>
            <input name="stapleFarOffsetAmount" inputmode="decimal" placeholder="0">
            <select name="stapleFarOffsetUnit">${magnitudeUnitOptions()}</select>
          </label>
        </div>
        <div class="field staple-coordinate-field" data-staple-coordinate-field>
          <span>Position</span>
          <span class="staple-coordinate-wrap">
            <input name="stapleCoordinate" data-staple-coordinate>
            <button class="instrument-button" type="button" data-staple-picker-toggle>Zoom…</button>
          </span>
          <div class="staple-picker" data-staple-picker hidden></div>
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
          <label class="field"><span>New rule starts</span>
            <input name="stapleRuleCoordinate" data-staple-rule-coordinate>
          </label>
          <div class="form-row">
            <label class="field"><span>New duration</span>
              <input name="stapleRuleDurationAmount" inputmode="decimal" placeholder="0">
              <select name="stapleRuleDurationUnit">${magnitudeUnitOptions()}</select>
            </label>
          </div>
        </div>
        <button class="instrument-button" type="button" data-add-staple>Add staple</button>
      </div>
      <p class="field-note">The staple list IS the placement interface (owner ruling: no staple is special, "Start time" included) -- every row, implicit or authored, carries the same kind/point/connection/coordinate shape. The first row is this ${recurrence ? "event's" : "object's"} own attachment, read as its default start staple; editing or removing it changes that attachment directly rather than minting a second, contradicting record. Add/remove/edit act immediately, each its own undoable step.</p>
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

    // The staples section: the whole placement interface (owner ruling: no
    // staple is special, "Start time" included). Add/remove/edit act
    // immediately, each its own undoable transaction, independent of this
    // form's own Save -- so a staple placed a moment ago survives
    // Cancel/Delete acting on everything else, and vice versa.
    const stapleSection = wrapper.querySelector("[data-staples-section]");
    const stapleList = stapleSection.querySelector("[data-staple-list]");
    const stapleExtent = stapleSection.querySelector("[data-staple-extent]");
    const stapleScopeField = wrapper.elements.stapleScope || null;
    const stapleKindField = stapleSection.querySelector("[data-staple-kind]");
    const stapleNearPointFieldWrap = stapleSection.querySelector("[data-staple-near-point-field]");
    const stapleNearPointField = stapleSection.querySelector("[data-staple-near-point]");
    const stapleNearPointNameFieldWrap = stapleSection.querySelector("[data-staple-near-point-name-field]");
    const stapleNearOffsetFieldWrap = stapleSection.querySelector("[data-staple-near-offset-field]");
    const stapleFarField = stapleSection.querySelector("[data-staple-far]");
    const stapleFarPointFieldWrap = stapleSection.querySelector("[data-staple-far-point-field]");
    const stapleFarPointField = stapleSection.querySelector("[data-staple-far-point]");
    const stapleFarPointNameFieldWrap = stapleSection.querySelector("[data-staple-far-point-name-field]");
    const stapleFarOffsetFieldWrap = stapleSection.querySelector("[data-staple-far-offset-field]");
    const stapleCoordinateFieldWrap = stapleSection.querySelector("[data-staple-coordinate-field]");
    const stapleCoordinateField = stapleSection.querySelector("[data-staple-coordinate]");
    const stapleFuzzyField = stapleSection.querySelector("[data-staple-fuzzy]");
    const stapleSpreadFieldsWrap = stapleSection.querySelector("[data-staple-spread-fields]");
    const stapleRuleFieldsWrap = stapleSection.querySelector("[data-staple-rule-fields]");

    function currentStapleScope() {
      return stapleScopeField ? stapleScopeField.value : "object";
    }

    // The registry-driven dropdown, refreshed whenever the scope toggle
    // changes -- a series-only kind must not be offered while adding a
    // staple straight to a bare, non-recurring event, and `correspondence`
    // (frame-to-frame) never appears on this card at all.
    function syncStapleKindOptions() {
      const scope = currentStapleScope();
      const options = stapleKindOptions(scope);
      const previous = stapleKindField.value;
      stapleKindField.innerHTML = options.map(([value, label]) => `<option value="${value}">${escapeHTML(label)}</option>`).join("");
      stapleKindField.value = options.some(([value]) => value === previous) ? previous : (options[0]?.[0] || "");
      syncStapleRuleVisibility();
    }

    // "Connects to": frames only for a series row (its every kind connects
    // only to a frame -- src/staples.js's `connects`), frames plus every
    // other object for an event row (an anchor may name a calendar frame OR
    // another object -- "the staple is not interfacing with the frame, or
    // another event or other object", the half the owner said was missing).
    function syncStapleFarOptions() {
      const scope = currentStapleScope();
      const { frames, objects } = farConnectionOptions(chronolog, eventId);
      const options = scope === "series" ? frames : [...frames, ...objects];
      const previous = stapleFarField.value || `frame:${wrapper.elements.frame.value}`;
      stapleFarField.innerHTML = options.map((option) => `<option value="${escapeHTML(option.value)}">${escapeHTML(option.label)}</option>`).join("");
      stapleFarField.value = options.some((option) => option.value === previous) ? previous : (options[0]?.value || "");
      syncStapleFarVisibility();
    }

    function syncStapleNearVisibility() {
      const isSeries = currentStapleScope() === "series";
      stapleNearPointFieldWrap.hidden = isSeries;
      const named = !isSeries && stapleNearPointField.value === CUSTOM_POINT;
      stapleNearPointNameFieldWrap.hidden = !named;
      stapleNearOffsetFieldWrap.hidden = !named;
    }

    function syncStapleFarVisibility() {
      const selection = parseFarSelection(stapleFarField.value);
      stapleFarPointFieldWrap.hidden = selection.scope !== "object";
      const named = selection.scope === "object" && stapleFarPointField.value === CUSTOM_POINT;
      stapleFarPointNameFieldWrap.hidden = !named;
      stapleFarOffsetFieldWrap.hidden = !named;
      stapleCoordinateFieldWrap.hidden = selection.scope !== "frame";
      if (selection.scope === "frame") {
        const law = coordinateLaw(chronolog, selection.id);
        stapleCoordinateField.placeholder = coordinateEntryPlaceholder(law);
      }
    }

    function syncStapleRuleVisibility() {
      const definition = stapleKind(stapleKindField.value);
      // Only a kind that can carry a following rule offers one. The registry
      // says which (`carriesRule`), so adding a future kind that partitions a
      // series gets this sub-editor without a second list of kind names here.
      stapleRuleFieldsWrap.hidden = !definition?.carriesRule;
    }

    stapleScopeField?.addEventListener("change", () => {
      syncStapleKindOptions();
      syncStapleFarOptions();
      syncStapleNearVisibility();
    });
    stapleKindField.addEventListener("change", syncStapleRuleVisibility);
    stapleNearPointField.addEventListener("change", syncStapleNearVisibility);
    stapleFarField.addEventListener("change", syncStapleFarVisibility);
    stapleFarPointField.addEventListener("change", syncStapleFarVisibility);
    stapleFuzzyField.addEventListener("change", () => {
      stapleSpreadFieldsWrap.hidden = !stapleFuzzyField.checked;
    });

    const addPickerToggle = stapleSection.querySelector("[data-staple-picker-toggle]");
    const addPicker = stapleSection.querySelector("[data-staple-picker]");
    addPickerToggle.addEventListener("click", () => {
      if (addPicker.hidden) {
        addPicker.hidden = false;
        renderPicker(addPicker, stapleCoordinateField, () => {
          const selection = parseFarSelection(stapleFarField.value);
          return selection.scope === "frame" ? coordinateLaw(chronolog, selection.id) : null;
        });
      } else {
        addPicker.hidden = true;
      }
    });

    // Both the series' own staples (when this event is a series template) and
    // the object's own effective staples -- its implicit placement row FIRST,
    // then every authored staple -- render together, in one list. Re-derived
    // fresh (not captured once at open time) so the list and the
    // derived-extent readout stay correct across this card's own
    // live-edited lifetime.
    function refreshStaplesSection() {
      const pattern = findRecurrencePattern(chronolog, eventId);
      const rows = [
        ...(pattern ? staplesForSeries(chronolog, pattern.id).map((staple) => seriesStapleRow(staple, pattern.id)) : []),
        ...effectiveObjectStaples(chronolog, eventId, engine)
      ];
      const models = rows.map((row) => stapleRowModel(row, chronolog));
      stapleList.innerHTML = models.map(stapleRowMarkup).join("") || `<li class="staple-list-empty">No staples yet.</li>`;
      stapleExtent.innerHTML = extentReadoutMarkup(extentReadoutModel(resolveObjectExtent(chronolog, engine, eventId), chronolog));
    }

    // An existing row's own edit: the implicit row patches the attachment
    // relation directly (`implicitPlacementEdit`) -- minting a staple beside
    // it would leave two records contradicting each other -- while an
    // authored row's coordinate rewrites that staple's frame end in place.
    function commitRowCoordinateFromInput(row, input) {
      const implicit = row.dataset.implicit === "true";
      const text = input.value;
      try {
        if (implicit) {
          app.executeEventChange("Edit placement", eventId, (documentValue) => {
            const target = placementRelation(documentValue, eventId)
              || Object.values(documentValue.relations).find((item) => item.type === "attachment"
                && item.event === eventId
                && documentValue.frames[item.frame]?.traits.includes("calendar")
                && item.role !== "completed");
            if (!target) return;
            const law = coordinateLaw(documentValue, target.frame);
            const patch = implicitPlacementEdit(text, law);
            if (patch) {
              target.coordinate = patch.coordinate;
              target.parameters = { ...(target.parameters || {}), ...patch.parameters };
            } else {
              delete target.coordinate;
              delete target.parameters;
            }
          });
        } else {
          const stapleId = row.dataset.stapleId;
          const scope = row.dataset.stapleScope;
          const targetId = row.dataset.targetId;
          const farFrame = row.dataset.farFrame;
          const trimmed = String(text || "").trim();
          if (!trimmed) throw new Error("A staple needs a coordinate.");
          const law = coordinateLaw(chronolog, farFrame);
          const coordinateValue = parseCoordinateEntry(trimmed, law).coordinate;
          const commit = (documentValue) => {
            const staple = documentValue.relations[stapleId];
            if (!staple) return;
            staple.ends = staple.ends.map((end) => (end.frame === farFrame ? { ...end, coordinate: coordinateValue } : end));
          };
          if (scope === "series") app.executePatternChange("Edit staple", targetId, commit);
          else app.executeEventChange("Edit staple", eventId, commit);
        }
      } catch (error) {
        app.toast(error.message, true);
      }
      refreshStaplesSection();
    }

    // Removing the implicit row deletes the placement COORDINATE, leaving the
    // attachment (frame membership) alone -- the object is then placed by its
    // remaining explicit staples, exactly as the engine's coordinate-less
    // membership placement (src/engine.js) expects. Removing an authored row
    // removes that staple as before.
    function commitRowRemove(row) {
      if (row.dataset.implicit === "true") {
        app.executeEventChange("Remove placement", eventId, (documentValue) => {
          const target = placementRelation(documentValue, eventId);
          if (target) { delete target.coordinate; delete target.parameters; }
        });
      } else {
        const stapleId = row.dataset.stapleId;
        const scope = row.dataset.stapleScope;
        const targetId = row.dataset.targetId;
        if (scope === "series") app.executePatternChange("Remove staple", targetId, (documentValue) => removeStaple(documentValue, stapleId));
        else app.executeEventChange("Remove staple", eventId, (documentValue) => removeStaple(documentValue, stapleId));
      }
      refreshStaplesSection();
    }

    // The fuzzy checkbox is the ONLY thing that ever writes a spread -- entry
    // depth never does (src/coordinate-entry.js's own contract). An implicit
    // row carries no staple to be fuzzy, so it has no such control at all.
    function commitRowFuzzy(row) {
      if (row.dataset.implicit === "true") return;
      const stapleId = row.dataset.stapleId;
      const scope = row.dataset.stapleScope;
      const targetId = row.dataset.targetId;
      const checkbox = row.querySelector("[data-row-fuzzy]");
      const spreadWrap = row.querySelector("[data-row-spread]");
      if (spreadWrap) spreadWrap.hidden = !checkbox.checked;
      const commit = (documentValue) => {
        const staple = documentValue.relations[stapleId];
        if (!staple) return;
        if (checkbox.checked) {
          const beforeAmount = row.querySelector("[data-row-spread-before-amount]").value;
          const beforeUnit = row.querySelector("[data-row-spread-before-unit]").value;
          const afterAmount = row.querySelector("[data-row-spread-after-amount]").value;
          const afterUnit = row.querySelector("[data-row-spread-after-unit]").value;
          staple.spread = {
            before: magnitudeOrNull(beforeAmount, beforeUnit) || durationMagnitude("0", "minute"),
            after: magnitudeOrNull(afterAmount, afterUnit) || durationMagnitude("0", "minute")
          };
        } else {
          delete staple.spread;
        }
      };
      if (scope === "series") app.executePatternChange("Edit staple fuzziness", targetId, commit);
      else app.executeEventChange("Edit staple fuzziness", eventId, commit);
      refreshStaplesSection();
    }

    stapleSection.querySelector("[data-add-staple]").addEventListener("click", () => {
      try {
        const scope = currentStapleScope();
        const pattern = findRecurrencePattern(chronolog, eventId);
        const targetId = scope === "series" ? pattern?.id : eventId;
        const farSelection = parseFarSelection(stapleFarField.value);
        const law = farSelection.scope === "frame" ? coordinateLaw(chronolog, farSelection.id) : null;
        const input = buildStapleInput({
          scope,
          targetId,
          kind: stapleKindField.value,
          nearPoint: stapleNearPointField.value,
          nearPointName: wrapper.elements.stapleNearPointName?.value,
          nearOffsetAmount: wrapper.elements.stapleNearOffsetAmount?.value,
          nearOffsetUnit: wrapper.elements.stapleNearOffsetUnit?.value,
          farScope: farSelection.scope,
          farId: farSelection.id,
          farPoint: stapleFarPointField.value,
          farPointName: wrapper.elements.stapleFarPointName?.value,
          farOffsetAmount: wrapper.elements.stapleFarOffsetAmount?.value,
          farOffsetUnit: wrapper.elements.stapleFarOffsetUnit?.value,
          coordinateText: stapleCoordinateField.value,
          law,
          fuzzy: stapleFuzzyField.checked,
          spreadBeforeAmount: wrapper.elements.stapleSpreadBeforeAmount.value,
          spreadBeforeUnit: wrapper.elements.stapleSpreadBeforeUnit.value,
          spreadAfterAmount: wrapper.elements.stapleSpreadAfterAmount.value,
          spreadAfterUnit: wrapper.elements.stapleSpreadAfterUnit.value,
          ruleRepeat: wrapper.elements.stapleRuleRepeat?.value,
          ruleInterval: wrapper.elements.stapleRuleInterval?.value,
          ruleCoordinateText: wrapper.elements.stapleRuleCoordinate?.value,
          ruleLaw: law,
          ruleDurationAmount: wrapper.elements.stapleRuleDurationAmount?.value,
          ruleDurationUnit: wrapper.elements.stapleRuleDurationUnit?.value
        });
        const stapleId = createId("relation");
        if (scope === "series") {
          app.executePatternChange("Add staple", targetId, (documentValue) => putStaple(documentValue, { ...input, id: stapleId }));
        } else {
          app.executeEventChange("Add staple", eventId, (documentValue) => putStaple(documentValue, { ...input, id: stapleId }));
        }
        stapleCoordinateField.value = "";
        refreshStaplesSection();
      } catch (error) {
        app.toast(error.message, true);
      }
    });

    stapleList.addEventListener("click", (clickEvent) => {
      const removeButton = clickEvent.target.closest?.("[data-remove-staple]");
      if (removeButton) {
        commitRowRemove(removeButton.closest("[data-staple-row]"));
        return;
      }
      const pickerToggle = clickEvent.target.closest?.("[data-row-picker-toggle]");
      if (pickerToggle) {
        const row = pickerToggle.closest("[data-staple-row]");
        const wrap = pickerToggle.parentElement;
        const picker = wrap.querySelector("[data-row-picker]");
        const input = wrap.querySelector("[data-row-coordinate]");
        if (picker.hidden) {
          picker.hidden = false;
          renderPicker(picker, input, () => coordinateLaw(chronolog, row.dataset.farFrame));
        } else {
          picker.hidden = true;
        }
      }
    });

    stapleList.addEventListener("change", (changeEvent) => {
      const row = changeEvent.target.closest?.("[data-staple-row]");
      if (!row) return;
      if (changeEvent.target.closest("[data-row-coordinate]") === changeEvent.target) {
        commitRowCoordinateFromInput(row, changeEvent.target);
      } else if (
        changeEvent.target.closest("[data-row-fuzzy]") === changeEvent.target
        || changeEvent.target.closest("[data-row-spread]")
      ) {
        commitRowFuzzy(row);
      }
    });

    syncStapleKindOptions();
    syncStapleFarOptions();
    syncStapleNearVisibility();
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
        // There is no start-coordinate requirement here any more (the owner's
        // bug, as a rule): placement comes from the staple list -- the
        // implicit row plus whatever else is authored -- never from a field
        // this form owns. A repeating series still needs a base coordinate
        // for its generator to count cycles from, but that is derived below
        // from wherever the event's own connections place it, not required
        // as typed input.
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
          // The attachment relation is FRAME MEMBERSHIP -- "this object
          // belongs to this calendar" -- and it is kept regardless of
          // whether it carries a coordinate. Deleting it because no start was
          // typed is exactly the old bug ("no event appears... error that
          // start time is null"): the coordinate, if any, is the staple
          // list's own immediately-committed fact (the implicit row), never
          // written here, so this only ever changes which frame/role the
          // membership names.
          if (existing) {
            existing.frame = chosenFrame;
            existing.role = target.traits.includes("task") ? "observed" : "placed";
          } else {
            existing = addRelation(documentValue, {
              type: "attachment",
              event: eventId,
              frame: chosenFrame,
              role: target.traits.includes("task") ? "observed" : "placed"
            });
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
          // `refreshStaplesSection` and its Add/Remove/edit handlers above),
          // so there is no `activePatternId` to thread through here any more.
          if (!repeat && existingPattern) {
            delete documentValue.patterns[existingPattern.id];
          } else if (repeat) {
            // A repeating series' generator counts cycles from its
            // `templateRelation`'s own coordinate, so it genuinely needs a
            // base coordinate -- but it does NOT need the user to have typed
            // one. Derived from wherever this event's own connections
            // already place it (its staples plus this same membership), never
            // invented independently; refused, in staple terms, only when
            // the staple set places the object nowhere at all.
            if (!existing.coordinate) {
              const liveEngine = app.refreshEngine ? app.refreshEngine(documentValue) : app.engine;
              const extent = resolveObjectExtent(documentValue, liveEngine, eventId);
              if (extent.startDays === null) {
                throw new Error("This repeating event has no staple placing it anywhere yet -- add one before it can repeat.");
              }
              existing.coordinate = coordinateLaw(documentValue, chosenFrame).fromDays(extent.startDays);
            }
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
              existingPattern.templateRelation = existing.id;
            } else {
              addPattern(documentValue, {
                title: `${target.payload.title} recurrence`,
                language: "chronolog-formula/1",
                kind: "ics-rrule",
                appliesTo: [chosenFrame],
                frame: chosenFrame,
                templateEvent: eventId,
                templateRelation: existing.id,
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
        ? Rational.parse(session.intimateGrain).div(app.session.law.minutesPerDay())
        : 1);
    }
    try {
      app.executeEventChange(`Create ${definition.label}`, eventId, (documentValue) => {
        const event = addEvent(documentValue, {
          id: eventId,
          traits: traitsForObjectKind([], objectKind),
          magnitudes: {
            duration: durationMagnitude(
              definition.zeroDuration ? "0" : orderedEnd.sub(orderedStart).mul(humanTimeLaw().secondsPerDay()).toJSON(),
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
          // `orderedStart` is a universal day ordinal off the drag surfaces
          // (src/ui/drag.js's `destinationForDrop`) or `session.currentFocus()`
          // -- both law-free -- so it is resolved into a coordinate under THIS
          // frame's own law, never the standard boundary.
          coordinate: coordinateLaw(documentValue, session.activeFrame).fromDays(orderedStart)
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
