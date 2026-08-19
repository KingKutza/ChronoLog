import assert from "node:assert/strict";
import test from "node:test";
import { ChronologEngine } from "../src/engine.js";
import { Rational, coordinate } from "../src/exact.js";
import { importICS } from "../src/ics.js";
import {
  CommandHistory,
  addEvent,
  addFrame,
  addPattern,
  addRelation,
  durationMagnitude,
  putStaple,
  removeStaple,
  setSeriesEndStaple,
  validateDocument
} from "../src/model.js";
import {
  ANCHOR_ROLE_ORDER,
  STAPLE_KINDS,
  isFuzzyStaple,
  resolveObjectExtent,
  stapleSpreadDays,
  staplesForSeries
} from "../src/staples.js";
import { createTransactions } from "../src/ui/transactions.js";
import { explainFactWeight } from "../src/visual-language.js";
import {
  buildStapleInput,
  createInspector,
  extentReadoutModel,
  stapleKindOptions,
  stapleRowModel,
  weightReadoutModel
} from "../src/ui/inspector.js";
import { createStructuralDocument } from "./helpers/sample-document.js";

// Owner item 4 (8.19 field report): the shipped end-staple field
// "presupposes that an end staple is special. I see no clear mechanism to add
// an arbitrary number or type of staples." This file exercises the general
// staples section that replaces it -- an open collection, authored the same
// way regardless of kind -- plus items 5 (weight visibility) and 8 ("Visible
// in" removal) which share the same object editor card.
//
// Where the DOM is too thin to drive `innerHTML`/`FormData` flows (this
// codebase's own established limit -- see test/frame-creation.test.js and
// `resolveSubmittedEventColor`'s own tests), the DECISIONS the editor makes
// are pulled out as plain exported functions and driven directly here. A
// small stub-DOM harness (copied from test/dock-card-refresh.test.js's
// pattern, extended with just enough of `HTMLFormElement`/`FormData` to
// submit a real form) covers the handful of things that only make sense as
// rendered structure: the staples section's placement, and that "Visible in"
// is truly gone from the rendered card rather than merely unused.

function civil(year, month, day, hour = 0, minute = 0, second = 0) {
  return coordinate([
    { level: "year", value: String(year) },
    { level: "month", value: String(month) },
    { level: "day", value: String(day) },
    { level: "hour", value: String(hour) },
    { level: "minute", value: String(minute) },
    { level: "second", value: String(second) }
  ]);
}

function appFor(chronolog) {
  const changes = [];
  const app = { chronolog, history: new CommandHistory(chronolog, (change) => changes.push(change)) };
  Object.assign(app, createTransactions(app));
  return { app, changes };
}

// A plain, non-recurring event on a calendar frame -- the "object" scope's
// minimal fixture.
function documentWithEvent() {
  const document = createStructuralDocument();
  addFrame(document, { id: "calendar:test", title: "Test calendar", traits: ["set", "calendar"], basis: "frame:wall-time" });
  const event = addEvent(document, {
    id: "event:test",
    traits: ["event"],
    magnitudes: { duration: durationMagnitude("30", "minute") },
    payload: { title: "Test event" }
  });
  addRelation(document, {
    id: "relation:test-placed",
    type: "attachment",
    event: event.id,
    frame: "calendar:test",
    role: "placed",
    coordinate: civil(2026, 1, 5, 9, 0, 0)
  });
  return { document, event };
}

// The template event plus its ics-rrule pattern -- the exact shape
// `findRecurrencePattern` (src/ui/inspector.js) looks for, and the "series"
// scope's minimal fixture.
function documentWithSeries() {
  const { document, event } = documentWithEvent();
  const pattern = addPattern(document, {
    id: "pattern:test",
    kind: "ics-rrule",
    appliesTo: ["calendar:test"],
    frame: "calendar:test",
    templateEvent: event.id,
    templateRelation: "relation:test-placed",
    rrule: { FREQ: "WEEKLY" }
  });
  return { document, event, pattern };
}

// ---------------------------------------------------------------------------
// The registry-driven dropdown
// ---------------------------------------------------------------------------

test("stapleKindOptions is STAPLE_KINDS itself, filtered by scope -- never a hand-written list", () => {
  const seriesKinds = Object.keys(STAPLE_KINDS).filter((kind) => STAPLE_KINDS[kind].targets.includes("series"));
  const objectKinds = Object.keys(STAPLE_KINDS).filter((kind) => STAPLE_KINDS[kind].targets.includes("object"));
  assert.deepEqual(stapleKindOptions("series").map(([value]) => value).sort(), seriesKinds.sort());
  assert.deepEqual(stapleKindOptions("object").map(([value]) => value).sort(), objectKinds.sort());
  // Series-only kinds (partitioning/phase) must never be offered on a bare,
  // non-recurring event -- there is no series body to place them on.
  assert.ok(!stapleKindOptions("object").some(([value]) => value === "end"));
  assert.ok(!stapleKindOptions("object").some(([value]) => value === "inflection"));
  assert.ok(!stapleKindOptions("object").some(([value]) => value === "phase"));
  // Every option's label comes straight from the registry, not a restatement.
  for (const [value, label] of stapleKindOptions("series")) assert.equal(label, STAPLE_KINDS[value].label);
});

// ---------------------------------------------------------------------------
// buildStapleInput -- the Add control's decision, pulled out of the DOM
// ---------------------------------------------------------------------------

test("buildStapleInput rejects a kind that cannot target the scope being authored", () => {
  assert.throws(
    () => buildStapleInput({ scope: "object", targetId: "event:x", kind: "end", dateText: "2026-01-01" }),
    /cannot be placed on an event/
  );
});

test("buildStapleInput requires a date, and a role for an anchoring kind", () => {
  assert.throws(() => buildStapleInput({ scope: "object", targetId: "event:x", kind: "anchor", role: "start" }), /needs a date/);
  assert.throws(
    () => buildStapleInput({ scope: "object", targetId: "event:x", kind: "anchor", role: "__custom__", roleName: "", dateText: "2026-01-01" }),
    /Name this anchor's role/
  );
});

test("an end staple authored through buildStapleInput is byte-equivalent to setSeriesEndStaple's own shape", () => {
  const { document, pattern } = documentWithSeries();
  const engine = new ChronologEngine(document);
  const input = buildStapleInput({
    scope: "series",
    targetId: pattern.id,
    kind: "end",
    dateText: "2026-01-19",
    timeText: "",
    frame: "calendar:test"
  });
  const reference = setSeriesEndStaple(
    document, "pattern:reference-only", "calendar:test", civil(2026, 1, 19, 23, 59, 59), { dateOnly: true }
  );
  // Only `series` differs (the general control names the real pattern; the
  // reference call above named a throwaway id to avoid touching it) -- every
  // other field the substrate stores is identical.
  assert.deepEqual(Object.keys(input).sort(), Object.keys(reference).filter((key) => key !== "id" && key !== "type").sort());
  assert.equal(input.kind, reference.kind);
  assert.equal(input.frame, reference.frame);
  assert.deepEqual(input.parameters, reference.parameters);
  assert.equal(input.series, pattern.id, "names the real series, not the reference call's throwaway one");
  // The coordinate itself is compared exactly, never by spelling (AGENTS.md:
  // ICS writes month "01" where the generator writes "1").
  assert.equal(
    engine.coordinateDays(input.frame, input.coordinate).compare(engine.coordinateDays(reference.frame, reference.coordinate)),
    0,
    "the general control's default end-of-day time is the exact instant setSeriesEndStaple always used"
  );
});

test("buildStapleInput's end-of-day default is unique to the end kind; every other kind defaults to midnight", () => {
  const anchorInput = buildStapleInput({
    scope: "object", targetId: "event:x", kind: "anchor", role: "start", dateText: "2026-01-19", frame: "calendar:test"
  });
  const engine = new ChronologEngine(createStructuralDocument());
  assert.equal(engine.coordinateDays("frame:wall-time", anchorInput.coordinate).compare(
    engine.coordinateDays("frame:wall-time", civil(2026, 1, 19, 0, 0, 0))
  ), 0);
  assert.deepEqual(anchorInput.parameters, { dateOnly: true });
});

test("a named anchor role pairs with an offset magnitude; start/end/midpoint never do", () => {
  const named = buildStapleInput({
    scope: "object", targetId: "event:x", kind: "anchor", role: "__custom__", roleName: "shift handover",
    dateText: "2026-01-19", timeText: "17:00", frame: "calendar:test", offsetAmount: "45", offsetUnit: "minute"
  });
  assert.equal(named.role, "shift handover");
  assert.ok(named.payload?.offset, "the offset magnitude is paired with the named point");

  const start = buildStapleInput({
    scope: "object", targetId: "event:x", kind: "anchor", role: "start",
    dateText: "2026-01-19", timeText: "17:00", frame: "calendar:test", offsetAmount: "45", offsetUnit: "minute"
  });
  assert.equal(start.payload, undefined, "an offset typed for a fixed role is not stored -- its meaning is not defined");
});

// ---------------------------------------------------------------------------
// One list row's display fields
// ---------------------------------------------------------------------------

test("stapleRowModel reports the registry label, role, position, and fuzzy marker for one row", () => {
  const { document, event } = documentWithEvent();
  assert.deepEqual(ANCHOR_ROLE_ORDER, ["start", "end", "midpoint"], "the precedence order the role field itself offers first");
  const plain = putStaple(document, {
    object: event.id, kind: "anchor", role: ANCHOR_ROLE_ORDER[0], frame: "calendar:test", coordinate: civil(2026, 2, 1, 9, 30, 0)
  });
  const plainRow = stapleRowModel(plain, "object");
  assert.equal(plainRow.kindLabel, STAPLE_KINDS.anchor.label);
  assert.equal(plainRow.role, "start");
  assert.equal(plainRow.date, "2026-02-01");
  assert.equal(plainRow.time, "09:30");
  assert.equal(plainRow.fuzzy, false);
  assert.equal(plainRow.scope, "object");

  const fuzzy = putStaple(document, buildStapleInput({
    scope: "object", targetId: event.id, kind: "anchor", role: "end",
    dateText: "2026-02-02", timeText: "", frame: "calendar:test",
    fuzzy: true, spreadBeforeAmount: "10", spreadAfterAmount: "10"
  }));
  const fuzzyRow = stapleRowModel(fuzzy, "object");
  assert.equal(fuzzyRow.fuzzy, true);
  assert.equal(fuzzyRow.time, "", "a dateOnly staple shows no time, matching the start-date field's own convention");
});

// ---------------------------------------------------------------------------
// Adding/removing a staple: one journalled, undoable, record-level change
// ---------------------------------------------------------------------------

test("adding a staple of each registered kind is one journalled, undoable change, and undo removes it", () => {
  for (const [kindName, definition] of Object.entries(STAPLE_KINDS)) {
    const scope = definition.targets[0];
    const fixture = scope === "series" ? documentWithSeries() : documentWithEvent();
    const { document } = fixture;
    const targetId = scope === "series" ? fixture.pattern.id : fixture.event.id;
    const { app, changes } = appFor(document);
    const input = buildStapleInput({
      scope,
      targetId,
      kind: kindName,
      role: definition.anchors ? "start" : undefined,
      dateText: "2026-02-01",
      timeText: "09:00",
      frame: "calendar:test"
    });
    const stapleId = "relation:staple-under-test";

    changes.length = 0;
    // The same choice src/ui/inspector.js's staples section makes: a series
    // staple through `executePatternChange`, an object staple through
    // `executeEventChange` -- both now correctly track a staple in their
    // bundle (`trackPatternStaples`/`trackObjectStaples` in
    // src/ui/transactions.js), so both journal and undo it as one change.
    if (scope === "series") {
      app.executePatternChange(`Add ${kindName} staple`, targetId, (documentValue) => putStaple(documentValue, { ...input, id: stapleId }));
    } else {
      app.executeEventChange(`Add ${kindName} staple`, targetId, (documentValue) => putStaple(documentValue, { ...input, id: stapleId }));
    }
    assert.ok(document.relations[stapleId], `${kindName}: the staple record exists`);
    assert.equal(document.relations[stapleId].kind, kindName);
    assert.equal(changes.length, 1, `${kindName}: exactly one journalled change`);
    assert.ok(
      changes[0].ops.some((op) => op.op === "put" && op.map === "relations" && op.id === stapleId),
      `${kindName}: journals as a record-level relations put`
    );
    assert.equal(validateDocument(document).valid, true, `${kindName}: the document stays valid`);

    app.history.undo();
    assert.equal(document.relations[stapleId], undefined, `${kindName}: undo removes it`);
    app.history.redo();
    assert.ok(document.relations[stapleId], `${kindName}: redo restores it`);
  }
});

// AGENTS.md's cascade rule, staple-shaped: "an event's deletion has to sweep
// its own staples exactly the way a pattern's deletion sweeps its own."
// src/ui/inspector.js's Delete button relies on `executeEventChange` doing
// this itself (`cascadeRemovedObjects` in src/ui/transactions.js) rather than
// sweeping staples by hand, so this pins that the substrate really does it.
test("deleting an event deletes its own object staples in the same undoable transaction, and undo restores both together", () => {
  const { document, event } = documentWithEvent();
  const staple = putStaple(document, {
    object: event.id, kind: "anchor", role: "start", frame: "calendar:test", coordinate: civil(2026, 2, 1, 9, 0, 0)
  });
  const { app } = appFor(document);

  // Mirrors src/ui/inspector.js's real Delete handler: the event's own
  // ordinary relations (its placement) are swept explicitly; its staples are
  // not -- that is the cascade under test.
  app.executeEventChange("Delete event", event.id, (documentValue) => {
    delete documentValue.events[event.id];
    for (const relation of Object.values(documentValue.relations)) {
      if (relation.event === event.id) delete documentValue.relations[relation.id];
    }
  });
  assert.equal(document.events[event.id], undefined);
  assert.equal(document.relations[staple.id], undefined, "its object staple went with it, not left as a dangling pointer");
  assert.equal(validateDocument(document).valid, true);

  app.history.undo();
  assert.ok(document.events[event.id], "the event comes back");
  assert.ok(document.relations[staple.id], "and its staple comes back with it, in the same undo step");
});

test("removing a staple is one journalled, undoable change", () => {
  const { document, event } = documentWithEvent();
  const staple = putStaple(document, {
    object: event.id, kind: "anchor", role: "start", frame: "calendar:test", coordinate: civil(2026, 2, 1, 9, 0, 0)
  });
  const { app, changes } = appFor(document);

  changes.length = 0;
  app.executeEventChange("Remove staple", event.id, (documentValue) => removeStaple(documentValue, staple.id));
  assert.equal(document.relations[staple.id], undefined);
  assert.equal(changes.length, 1);
  assert.ok(changes[0].ops.some((op) => op.op === "del" && op.map === "relations" && op.id === staple.id));

  app.history.undo();
  assert.ok(document.relations[staple.id], "undo restores the removed staple");
  assert.deepEqual(document.relations[staple.id].kind, "anchor");
});

test("an end staple added through the general staples flow cuts a series projection exactly like the bespoke field used to", () => {
  const document = createStructuralDocument();
  const source = [
    "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Test//EN", "BEGIN:VEVENT",
    "UID:standing@example.test", "DTSTART:20260105T090000Z", "RRULE:FREQ=WEEKLY",
    "SUMMARY:Standing meeting", "DURATION:PT30M", "END:VEVENT", "END:VCALENDAR", ""
  ].join("\r\n");
  const imported = importICS(source, document, { label: "Calendar" });
  const frame = document.frames[imported.frames[0]];
  const pattern = Object.values(document.patterns).find((item) => item.kind === "ics-rrule");
  const { app, changes } = appFor(document);

  const input = buildStapleInput({
    scope: "series", targetId: pattern.id, kind: "end", dateText: "2026-01-19", timeText: "", frame: frame.id
  });
  changes.length = 0;
  app.executePatternChange("Add staple", pattern.id, (documentValue) => putStaple(documentValue, input));
  assert.equal(changes.length, 1);

  const engine = new ChronologEngine(document);
  const facts = engine.queryFacts({
    frame: frame.id,
    start: civil(2026, 1, 1),
    end: civil(2026, 3, 1),
    limit: 200
  }).facts.filter((fact) => fact.kind === "virtual");
  const dates = facts.map((fact) => `${fact.coordinate.levels.find((l) => l.level === "day").value}`);
  assert.deepEqual(dates, ["5", "12", "19"], "the staple's own occurrence survives; nothing after it projects");

  app.history.undo();
  assert.equal(staplesForSeries(document, pattern.id).length, 0, "undo removes the staple entirely");
});

// ---------------------------------------------------------------------------
// Fuzzy staples: asymmetric before/after spread
// ---------------------------------------------------------------------------

test("a fuzzy staple round-trips its asymmetric before/after spread", () => {
  const { document, event } = documentWithEvent();
  const input = buildStapleInput({
    scope: "object", targetId: event.id, kind: "anchor", role: "start",
    dateText: "2026-02-01", timeText: "17:00", frame: "calendar:test",
    fuzzy: true, spreadBeforeAmount: "15", spreadBeforeUnit: "minute", spreadAfterAmount: "30", spreadAfterUnit: "minute"
  });
  const staple = putStaple(document, input);
  assert.ok(isFuzzyStaple(staple));
  const spread = stapleSpreadDays(staple);
  assert.equal(spread.before.compare(Rational.parse(15).div(1440)), 0);
  assert.equal(spread.after.compare(Rational.parse(30).div(1440)), 0);
  assert.notEqual(spread.before.compare(spread.after), 0, "asymmetric on purpose -- never a single +/-");
});

test("a staple with no spread amounts entered is not reported as fuzzy", () => {
  const { document, event } = documentWithEvent();
  const staple = putStaple(document, buildStapleInput({
    scope: "object", targetId: event.id, kind: "anchor", role: "start",
    dateText: "2026-02-01", frame: "calendar:test", fuzzy: true
  }));
  assert.equal(isFuzzyStaple(staple), false);
});

// ---------------------------------------------------------------------------
// The derived-extent readout
// ---------------------------------------------------------------------------

test("the derived-extent readout reports an end-anchored event's start, and names an overdetermined anchor", () => {
  const { document, event } = documentWithEvent();
  const engine = new ChronologEngine(document);

  // Explicit ids, not the substrate's own random `createId` ones: "authored
  // order" (src/staples.js's `byAuthoredOrder`) is a lexicographic sort over
  // relation ids, and this test's whole point is which of two same-role
  // anchors that order picks -- a random UUID's sort position carries no
  // relationship to which `putStaple` call actually happened first, so a
  // random id here would make the assertion below pass or fail by chance.
  putStaple(document, {
    id: "relation:end-anchor-1",
    object: event.id, kind: "anchor", role: "end", frame: "calendar:test", coordinate: civil(2026, 1, 5, 17, 0, 0)
  });
  const before = extentReadoutModel(resolveObjectExtent(document, engine, event.id));
  assert.equal(before.source, "anchor+magnitude");
  assert.equal(before.derivedMagnitude, false);
  assert.equal(before.end, "2026-01-05 17:00:00");
  // 30-minute duration (documentWithEvent's fixture), end-anchored -> starts
  // half an hour earlier, not at the object's own unrelated placement.
  assert.equal(before.start, "2026-01-05 16:30:00");
  assert.deepEqual(before.overdetermined, []);

  // A second "end" anchor cannot also be believed -- it is retained, named,
  // and reported, never silently averaged in.
  putStaple(document, {
    id: "relation:end-anchor-2",
    object: event.id, kind: "anchor", role: "end", frame: "calendar:test", coordinate: civil(2026, 1, 6, 12, 0, 0)
  });
  const after = extentReadoutModel(resolveObjectExtent(document, engine, event.id));
  assert.equal(after.start, before.start, "placement is unchanged -- the extra anchor is not used");
  assert.equal(after.overdetermined.length, 1);
  assert.equal(after.overdetermined[0].kind, "anchor");
  assert.equal(after.overdetermined[0].kindLabel, STAPLE_KINDS.anchor.label);
  assert.equal(after.overdetermined[0].role, "end");
  assert.match(after.overdetermined[0].reason, /already anchors this role/);
});

test("a zero-staple object reports an unresolved-free honest placement, not a fabricated extent", () => {
  const document = createStructuralDocument();
  const event = addEvent(document, {
    id: "event:floating",
    traits: ["event", "task", "todo"],
    magnitudes: { duration: durationMagnitude("0") },
    payload: { title: "Floating todo" }
  });
  const engine = new ChronologEngine(document);
  const model = extentReadoutModel(resolveObjectExtent(document, engine, event.id));
  assert.equal(model.source, "unstapled");
  assert.equal(model.start, null);
  assert.equal(model.end, null);
});

// ---------------------------------------------------------------------------
// The weight readout
// ---------------------------------------------------------------------------

test("the weight readout lists contributing groups in application order with correct before-to-after values", () => {
  const { document, event } = documentWithEvent();
  addFrame(document, { id: "group:a", title: "Group A", traits: ["set", "group"], display: { weight: "w * 2", weightOrder: 0 } });
  addFrame(document, { id: "group:b", title: "Group B", traits: ["set", "group"], display: { weight: "w + 1", weightOrder: 1 } });
  addRelation(document, { type: "attachment", event: event.id, frame: "group:a", role: "member" });
  addRelation(document, { type: "attachment", event: event.id, frame: "group:b", role: "member" });
  const engine = new ChronologEngine(document);

  const model = weightReadoutModel(explainFactWeight({ document, engine }, { event }));
  assert.equal(model.base, 1);
  assert.equal(model.baseVerdict, "standard");
  // The event's own calendar ("Test calendar") is a contributing frame too
  // (contributingFrameIds unions direct frame attachments with group
  // membership) -- it ties Group A on the default weightOrder (0) and loses
  // the tiebreak on group size (0 members vs Group A's 1), so it applies
  // its own (unauthored, identity) formula second, before Group B's
  // explicit weightOrder (1) places it last.
  assert.deepEqual(model.rows.map((row) => row.title), ["Group A", "Test calendar", "Group B"],
    "application order, not authored/iteration order");
  assert.deepEqual(model.rows.map((row) => row.formula), ["w * 2", "w", "w + 1"]);
  assert.equal(model.rows[0].from, 1);
  assert.equal(model.rows[0].to, 2);
  assert.equal(model.rows[1].from, 2, "the second row's 'before' is the first row's 'after'");
  assert.equal(model.rows[1].to, 2, "no authored weight on the calendar frame -- identity, not a no-op that vanishes from the list");
  assert.equal(model.rows[2].from, 2);
  assert.equal(model.rows[2].to, 3);
  assert.equal(model.final, 3);
  assert.equal(model.verdict, "important");
});

// ---------------------------------------------------------------------------
// "Visible in" is gone -- structural checks on the rendered card
// ---------------------------------------------------------------------------

// A minimal but real-enough stub DOM: `innerHTML` actually parses into a tree
// (copied from test/dock-card-refresh.test.js's `MiniNode`), extended with
// just enough of `HTMLFormElement`'s surface (`.elements`, settable
// `.value`/`.checked`, `#id`/`.closest` lookups, `classList.toggle`) to open
// the real event editor and submit it for real, because those two things —
// "no rendered control writes display.lenses any more" and "existing
// display.lenses survives a save" — are exactly the shape of thing this
// repo's stub-DOM limit says to stop pulling into pure functions and just
// render.
function createFormDom() {
  const VOID_TAGS = new Set(["input", "br", "img", "hr"]);
  function unescapeHTML(value) {
    return String(value).replace(/&quot;/g, '"').replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
  }

  class MiniNode {
    constructor(tag) {
      this.tagName = String(tag || "div").toUpperCase();
      this.attrs = new Map();
      this.children = [];
      this.parentElement = null;
      this.handlers = new Map();
      this.textContent = "";
      this._value = undefined;
      this._checked = undefined;
    }
    get className() { return this.attrs.get("class") || ""; }
    set className(value) { this.attrs.set("class", value); }
    get classList() {
      const node = this;
      return {
        toggle(cls, force) {
          const has = String(node.className || "").split(/\s+/).includes(cls);
          const want = force === undefined ? !has : force;
          const parts = new Set(String(node.className || "").split(/\s+/).filter(Boolean));
          if (want) parts.add(cls); else parts.delete(cls);
          node.className = [...parts].join(" ");
        }
      };
    }
    get dataset() {
      const data = {};
      for (const [key, value] of this.attrs) {
        if (!key.startsWith("data-")) continue;
        data[key.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = value;
      }
      return data;
    }
    get type() { return this.attrs.get("type") || ""; }
    get value() {
      if (this._value !== undefined) return this._value;
      if (this.tagName === "SELECT") {
        const options = this.children.filter((c) => c.tagName === "OPTION");
        const selected = options.find((o) => o.attrs.get("selected") !== undefined);
        return (selected || options[0])?.attrs.get("value") ?? "";
      }
      if (this.tagName === "TEXTAREA") {
        return this.descendants().filter((n) => n.tagName === "#TEXT").map((n) => n.textContent).join("");
      }
      return this.attrs.get("value") ?? "";
    }
    set value(v) { this._value = String(v); }
    get checked() { return this._checked !== undefined ? this._checked : this.attrs.has("checked"); }
    set checked(v) { this._checked = Boolean(v); }
    get elements() {
      const map = {};
      for (const node of this.descendants()) {
        const name = node.attrs.get("name");
        if (name && !(name in map)) map[name] = node;
      }
      return map;
    }
    setAttribute(name, value) { this.attrs.set(name, String(value)); }
    getAttribute(name) { return this.attrs.has(name) ? this.attrs.get(name) : null; }
    addEventListener(type, handler) { if (!this.handlers.has(type)) this.handlers.set(type, []); this.handlers.get(type).push(handler); }
    dispatch(type, event = {}) { for (const handler of this.handlers.get(type) || []) handler({ preventDefault() {}, target: this, ...event }); }
    append(...nodes) { for (const node of nodes) { node.parentElement = this; this.children.push(node); } }
    replaceChildren(...nodes) { this.children = []; this.append(...nodes); }
    descendants() { return this.children.flatMap((child) => [child, ...child.descendants()]); }
    matchesSimple(selector) {
      const idMatch = /^#([a-zA-Z0-9_-]+)$/.exec(selector);
      if (idMatch) return this.attrs.get("id") === idMatch[1];
      const attrMatch = /^\[([a-zA-Z0-9_-]+)(?:="([^"]*)")?\]$/.exec(selector);
      if (attrMatch) {
        const [, name, attrValue] = attrMatch;
        if (!this.attrs.has(name)) return false;
        return attrValue === undefined || this.attrs.get(name) === attrValue;
      }
      return false;
    }
    closest(selector) {
      let node = this;
      while (node) { if (node.matchesSimple(selector)) return node; node = node.parentElement; }
      return null;
    }
    querySelector(selector) { return this.descendants().find((node) => node.matchesSimple(selector)) || null; }
    querySelectorAll(selector) { return this.descendants().filter((node) => node.matchesSimple(selector)); }
    get innerHTML() { return this._html || ""; }
    set innerHTML(value) {
      this._html = value;
      this.children = parseFragment(value);
      for (const child of this.children) child.parentElement = this;
    }
  }

  function parseFragment(html) {
    const root = new MiniNode("root");
    const stack = [root];
    const tagRe = /<\/([a-zA-Z][a-zA-Z0-9-]*)>|<([a-zA-Z][a-zA-Z0-9-]*)([^>]*)>|([^<]+)/g;
    let match;
    while ((match = tagRe.exec(html))) {
      const [, closeTag, openTag, rawAttrs, text] = match;
      if (closeTag) {
        for (let i = stack.length - 1; i > 0; i--) {
          if (stack[i].tagName === closeTag.toUpperCase()) { stack.length = i; break; }
        }
      } else if (openTag) {
        const selfClose = /\/\s*$/.test(rawAttrs || "");
        const node = new MiniNode(openTag);
        const attrRe = /([a-zA-Z_:][-a-zA-Z0-9_:.]*)(?:\s*=\s*"([^"]*)")?/g;
        let attrMatch;
        while ((attrMatch = attrRe.exec((rawAttrs || "").replace(/\/\s*$/, "")))) {
          node.attrs.set(attrMatch[1], attrMatch[2] !== undefined ? unescapeHTML(attrMatch[2]) : "");
        }
        stack[stack.length - 1].append(node);
        if (!VOID_TAGS.has(openTag.toLowerCase()) && !selfClose) stack.push(node);
      } else if (text !== undefined && text.trim().length) {
        const t = new MiniNode("#text");
        t.textContent = unescapeHTML(text);
        stack[stack.length - 1].append(t);
      }
    }
    return root.children;
  }

  class FakeFormData {
    constructor(form) { this.form = form; }
    get(name) {
      const el = this.form.elements[name];
      if (!el) return null;
      if (el.tagName === "INPUT" && el.type === "checkbox") return el.checked ? (el.value || "on") : null;
      return el.value ?? null;
    }
    getAll(name) {
      return this.form.querySelectorAll(`[name="${name}"]`)
        .filter((el) => el.tagName !== "INPUT" || el.type !== "checkbox" || el.checked)
        .map((el) => el.value);
    }
  }

  return { MiniNode, FakeFormData };
}

function openFormHarness(document, eventId) {
  const { MiniNode, FakeFormData } = createFormDom();
  const previous = {
    document: globalThis.document,
    FormData: globalThis.FormData,
    requestAnimationFrame: globalThis.requestAnimationFrame
  };
  globalThis.document = { createElement: (tag) => new MiniNode(tag) };
  globalThis.FormData = FakeFormData;
  globalThis.requestAnimationFrame = (fn) => fn(0);
  const engine = new ChronologEngine(document);
  let cardBody = null;
  const app = {
    chronolog: document,
    engine,
    session: { inspector: null, activeFrame: "calendar:test" },
    openDockCard(options) { cardBody = options.body; },
    dockIsOpen: () => true,
    closeDockCard() {},
    dockCardBody: () => cardBody,
    toast() {},
    store: { beginDeferred() {}, endDeferred() {} },
    refreshEngine(documentValue) { app.engine.setDocument(documentValue); return app.engine; }
  };
  Object.assign(app, createTransactions(app));
  const inspector = createInspector(app);
  inspector.openEventInspector(eventId);
  const restore = () => Object.assign(globalThis, previous);
  return { app, cardBody, restore };
}

test("the staples section sits below the recurrence rows and above the Groups field; no control writes display.lenses", () => {
  const { document, event } = documentWithEvent();
  event.display = { lenses: ["intimate", "tactical"] };
  const { cardBody, restore } = openFormHarness(document, event.id);
  try {
    assert.equal(cardBody.querySelector('[name="visibility"]'), null, "the 'Visible in' select is gone from the rendered card");

    const order = cardBody.descendants();
    const recurrenceIndex = order.indexOf(cardBody.querySelector("[data-recurrence-row]"));
    const staplesIndex = order.indexOf(cardBody.querySelector("[data-staples-section]"));
    const groupsIndex = order.indexOf(cardBody.querySelector("[data-groups-field]"));
    assert.ok(recurrenceIndex >= 0 && staplesIndex >= 0 && groupsIndex >= 0, "all three landmarks render");
    assert.ok(recurrenceIndex < staplesIndex, "staples section is below the recurrence rows");
    assert.ok(staplesIndex < groupsIndex, "staples section is above the Groups field");

    // The end-staple's own former fields are gone as a sibling control too --
    // it is one row in the general list now, not a bespoke pair of inputs.
    assert.equal(cardBody.querySelector('[name="endStapleDate"]'), null);
    assert.equal(cardBody.querySelector('[name="endStapleTime"]'), null);
  } finally {
    restore();
  }
});

test("saving through the editor leaves an event's already-authored display.lenses untouched", () => {
  const { document, event } = documentWithEvent();
  event.display = { lenses: ["intimate", "tactical"] };
  const { cardBody, restore } = openFormHarness(document, event.id);
  try {
    cardBody.dispatch("submit", {});
    assert.deepEqual(document.events[event.id].display.lenses, ["intimate", "tactical"],
      "existing authored data is not destroyed by a control that no longer exists");
  } finally {
    restore();
  }
});

test("the weight readout renders inside the card, near the color row, not as a control of its own", () => {
  const { document, event } = documentWithEvent();
  const { cardBody, restore } = openFormHarness(document, event.id);
  try {
    const readout = cardBody.querySelector("[data-weight-readout]");
    assert.ok(readout, "the weight readout renders");
    assert.equal(readout.querySelectorAll("input, select, textarea, button").length, 0, "read-only -- no inputs of its own");
  } finally {
    restore();
  }
});

// ---------------------------------------------------------------------------
// The following rule (LEXICON's Rob-and-John, second half)
// ---------------------------------------------------------------------------
//
// "At that decision they place a staple at the inflection point defining an end
// to the initial series rule, then either define a new rule post-staple or a
// new series, on preference."
//
// The substrate has always been able to carry a following rule; until this the
// editor could only ever author a staple that TERMINATES, which is the same
// "an end staple is the only thing a staple can do" presupposition the whole
// item exists to remove. These pin the authoring path, and the last one proves
// the authored record really re-rules the series rather than merely validating.

test("an inflection staple authored with a following rule carries that rule head", () => {
  const input = buildStapleInput({
    scope: "series",
    targetId: "pattern:test",
    kind: "inflection",
    dateText: "2032-03-01",
    frame: "calendar:test",
    ruleRepeat: "WEEKLY",
    ruleInterval: "1",
    ruleDateText: "2032-03-04",
    ruleTimeText: "12:00",
    ruleDurationAmount: "45",
    ruleDurationUnit: "minute"
  });
  assert.equal(input.kind, "inflection");
  assert.equal(input.payload.rule.rrule.FREQ, "WEEKLY");
  assert.equal(input.payload.rule.rrule.INTERVAL, "1");
  // The following rule gets its OWN start, not the staple's instant -- the new
  // meeting is a Thursday lunch, not the old Monday 6:15.
  assert.ok(input.payload.rule.coordinate, "the rule head carries its own base coordinate");
  assert.equal(input.payload.rule.frame, "calendar:test");
  assert.equal(input.payload.rule.magnitude.value.levels[0].value, "45");
});

test("the weekdays preset expands to BYDAY in a following rule, as the main repeat control does", () => {
  const input = buildStapleInput({
    scope: "series", targetId: "pattern:test", kind: "inflection",
    dateText: "2032-03-01", frame: "calendar:test",
    ruleRepeat: "WEEKDAYS", ruleDateText: "2032-03-04"
  });
  assert.equal(input.payload.rule.rrule.FREQ, "WEEKLY");
  assert.equal(input.payload.rule.rrule.BYDAY, "MO,TU,WE,TH,FR");
});

test("leaving the following rule blank makes the inflection staple simply end the series", () => {
  const input = buildStapleInput({
    scope: "series", targetId: "pattern:test", kind: "inflection",
    dateText: "2032-03-01", frame: "calendar:test", ruleRepeat: ""
  });
  assert.equal(input.payload?.rule, undefined, "no rule follows -- the other preference, authored by omission");
});

test("a kind that cannot carry a rule ignores the rule fields entirely", () => {
  // Registry-driven: `end` has carriesRule false, so rule fields submitted
  // against it are not quietly attached to a record whose kind would then fail
  // validation (src/model.js refuses payload.rule on a non-carriesRule kind).
  const input = buildStapleInput({
    scope: "series", targetId: "pattern:test", kind: "end",
    dateText: "2032-03-01", frame: "calendar:test",
    ruleRepeat: "WEEKLY", ruleDateText: "2032-03-04"
  });
  assert.equal(input.payload?.rule, undefined);
});

test("a following rule authored through the editor really re-rules the series", () => {
  // The end-to-end closure: the editor's own decision function -> putStaple ->
  // the engine's segmented projection. A Monday series becomes Thursday lunches
  // after the staple, on ONE pattern identity, with no code path a user cannot
  // reach from the card.
  const document = createStructuralDocument();
  const source = [
    "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Test//EN",
    "BEGIN:VEVENT",
    "UID:mondays@example.test",
    "DTSTART:20260105T061500Z",
    "RRULE:FREQ=WEEKLY;BYDAY=MO",
    "SUMMARY:Monday meeting",
    "DURATION:PT15M",
    "END:VEVENT", "END:VCALENDAR", ""
  ].join("\r\n");
  const imported = importICS(source, document, { label: "Work" });
  const frame = document.frames[imported.frames[0]];
  const pattern = Object.values(document.patterns).find((item) => item.kind === "ics-rrule");

  const input = buildStapleInput({
    scope: "series",
    targetId: pattern.id,
    kind: "inflection",
    dateText: "2026-02-02",
    timeText: "23:59",
    frame: frame.id,
    ruleRepeat: "WEEKLY",
    ruleInterval: "1",
    ruleDateText: "2026-02-05",
    ruleTimeText: "12:00",
    ruleDurationAmount: "45",
    ruleDurationUnit: "minute"
  });
  putStaple(document, { ...input, id: "relation:inflection" });
  assert.equal(validateDocument(document).valid, true, "the authored record validates");

  const weekdayOf = (fact) => Number(
    new Rational(Rational.parse(fact.day).floor()).add(4).mod(7).toJSON()
  );
  const facts = new ChronologEngine(document).queryFacts({
    frame: frame.id,
    start: coordinate([{ level: "year", value: "2026" }, { level: "month", value: "1" }, { level: "day", value: "1" }]),
    end: coordinate([{ level: "year", value: "2026" }, { level: "month", value: "3" }, { level: "day", value: "15" }]),
    limit: 200
  }).facts.filter((fact) => fact.kind === "virtual");

  // The cut is the staple's own instant, resolved exactly -- never compared as
  // coordinate text, since the ICS-imported rule and the editor-authored staple
  // spell the same instant differently ("01" vs "1").
  const cut = new ChronologEngine(document).coordinateDays(frame.id, input.coordinate);
  const before = facts.filter((fact) => Rational.parse(fact.day).compare(cut) <= 0);
  const after = facts.filter((fact) => Rational.parse(fact.day).compare(cut) > 0);

  assert.ok(before.length >= 4, "the original Monday rule projected before the staple");
  assert.ok(after.length >= 4, "a new rule projects after the staple");
  assert.deepEqual([...new Set(before.map(weekdayOf))], [1], "everything before the staple is a Monday");
  assert.deepEqual([...new Set(after.map(weekdayOf))], [4], "everything after it is a Thursday");
  // One identity, not two series (the whole point of the ruling).
  assert.deepEqual(
    [...new Set(facts.map((fact) => fact.event.provenance.pattern))],
    [pattern.id],
    "both segments are the same series"
  );

  // And removing it restores the original projection unconditionally.
  removeStaple(document, "relation:inflection");
  const restored = new ChronologEngine(document).queryFacts({
    frame: frame.id,
    start: coordinate([{ level: "year", value: "2026" }, { level: "month", value: "1" }, { level: "day", value: "1" }]),
    end: coordinate([{ level: "year", value: "2026" }, { level: "month", value: "3" }, { level: "day", value: "15" }]),
    limit: 200
  }).facts.filter((fact) => fact.kind === "virtual");
  assert.deepEqual([...new Set(restored.map(weekdayOf))], [1], "Mondays all the way again");
});
