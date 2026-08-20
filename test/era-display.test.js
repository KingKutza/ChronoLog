import assert from "node:assert/strict";
import test from "node:test";
import { Rational, daysFromCivil } from "../src/exact.js";
import { CoordinateLaw, GREGORIAN_LAW, coordinateLaw } from "../src/coordinate-law.js";
import { minimapLabelText, minimapLabelTicks } from "../src/minimap.js";
import { createToolbar } from "../src/ui/toolbar.js";
import { ViewSession } from "../src/session.js";

// Owner ruling: "Hard No. Epochs, true epochs no faking." This file pins the
// 8.20 Wave C display-honesty slice: a label built over a law with an era
// table shows the era-qualified year, a law without one is untouched, a day
// outside every declared era is omitted rather than given an invented year,
// and a Now-related control is disabled rather than lying about a "today"
// on a calendar that maps to no running clock.
//
// The two example laws are copied verbatim from test/eras.test.js's fixtures
// (per the wave brief -- copy, do not import, so this file stands alone).

// Gregorian with eras: BCE descending and open below, CE ascending and open
// above -- exercises the era-qualified year on an otherwise ordinary
// Gregorian month/day ladder.
const BCE_CE_DECLARATION = Object.freeze({
  kind: "gregorian",
  levels: Object.freeze([
    Object.freeze({ name: "era" }),
    Object.freeze({ name: "year", within: "era" }),
    Object.freeze({ name: "month", within: "year", transition: "gregorian.months" }),
    Object.freeze({ name: "day", within: "month", transition: "gregorian.days" }),
    Object.freeze({ name: "hour", within: "day", radix: "24" }),
    Object.freeze({ name: "minute", within: "hour", radix: "60" }),
    Object.freeze({ name: "second", within: "minute", radix: "60" })
  ]),
  eras: Object.freeze({
    anchor: { era: "Common Era", year: "1", properYear: "1" },
    entries: Object.freeze([
      Object.freeze({ name: "Before Common Era", abbrev: "BCE", direction: "descending", affix: "suffix" }),
      Object.freeze({ name: "Common Era", abbrev: "CE", direction: "ascending", affix: "suffix" })
    ])
  })
});

// Tamriel: a uniform 365-day year with no Gregorian month transition at all
// -- exercises the label ladder's honest degrade (no month/quarter rung a
// non-Gregorian calendar can place) independently of the era question.
const TAMRIEL_DECLARATION = Object.freeze({
  kind: "nested",
  origin: { days: "0" },
  baseLevel: "day",
  levels: Object.freeze([
    Object.freeze({ name: "era" }),
    Object.freeze({ name: "year", within: "era" }),
    Object.freeze({ name: "day", within: "year", radix: "365" }),
    Object.freeze({ name: "hour", within: "day", radix: "24" })
  ]),
  eras: Object.freeze({
    anchor: { era: "First Era", year: "1", properYear: "1" },
    entries: Object.freeze([
      Object.freeze({ name: "Merethic Era", abbrev: "ME", direction: "descending" }),
      Object.freeze({ name: "First Era", abbrev: "1E", direction: "ascending", years: "2920" }),
      Object.freeze({ name: "Second Era", abbrev: "2E", direction: "ascending", years: "896" }),
      Object.freeze({ name: "Third Era", abbrev: "3E", direction: "ascending", years: "433" }),
      Object.freeze({ name: "Fourth Era", abbrev: "4E", direction: "ascending" })
    ])
  })
});

// A calendar closed at BOTH ends -- the fixture the eras.test.js suite does
// not need but this one does: a day genuinely outside every declared era, so
// `formatYearAtDays` throws and the render path must omit rather than crash.
const CLOSED_ERA_DECLARATION = Object.freeze({
  kind: "gregorian",
  levels: Object.freeze([
    Object.freeze({ name: "era" }),
    Object.freeze({ name: "year", within: "era" }),
    Object.freeze({ name: "month", within: "year", transition: "gregorian.months" }),
    Object.freeze({ name: "day", within: "month", transition: "gregorian.days" })
  ]),
  eras: Object.freeze({
    anchor: { era: "Only Era", year: "1", properYear: "1" },
    entries: Object.freeze([
      Object.freeze({ name: "Only Era", abbrev: "OE", direction: "ascending", years: "5" })
    ])
  })
});

// Eras are FRAMES STAPLED TOGETHER, so a display test that needs an era law
// builds the chain the model actually executes rather than a declaration key.
// `entries` are oldest first; exactly one carries the pin.
function chainLaw(entries, ladder, eraId) {
  const frames = {
    "frame:chain-calendar": {
      id: "frame:chain-calendar",
      title: "Chain calendar",
      traits: ["line", "temporal", "calendar", "group"],
      coordinate: ladder
    }
  };
  const relations = {};
  for (const entry of entries) {
    frames[entry.id] = {
      id: entry.id,
      title: entry.era.name,
      traits: ["line", "temporal", "era"],
      basis: "frame:chain-calendar",
      era: entry.era
    };
  }
  for (const [index, entry] of entries.slice(0, -1).entries()) {
    relations[`succession:${entry.id}`] = {
      id: `succession:${entry.id}`,
      type: "staple",
      kind: "succession",
      ends: [
        { frame: entry.id, role: "end" },
        { frame: entries[index + 1].id, role: "start" }
      ]
    };
  }
  return coordinateLaw({ frames, relations }, eraId);
}

const PLAIN_GREGORIAN_LADDER = Object.freeze({
  kind: "gregorian",
  levels: Object.freeze([
    Object.freeze({ name: "year" }),
    Object.freeze({ name: "month", within: "year", transition: "gregorian.months" }),
    Object.freeze({ name: "day", within: "month", transition: "gregorian.days" }),
    Object.freeze({ name: "hour", within: "day", radix: "24" }),
    Object.freeze({ name: "minute", within: "hour", radix: "60" }),
    Object.freeze({ name: "second", within: "minute", radix: "60" })
  ])
});

const BCE_CE_CHAIN = Object.freeze([
  Object.freeze({ id: "era:bce", era: Object.freeze({ key: "BCE", name: "Before Common Era", direction: "descending", firstYear: "1", years: "open", affix: "suffix" }) }),
  Object.freeze({ id: "era:ce", era: Object.freeze({ key: "CE", name: "Common Era", direction: "ascending", firstYear: "1", years: "open", affix: "suffix", anchor: { year: "1", properYear: "1" } }) })
]);

const CLOSED_CHAIN = Object.freeze([
  Object.freeze({ id: "era:only", era: Object.freeze({ key: "OE", name: "Only Era", direction: "ascending", firstYear: "1", years: "5", anchor: { year: "1", properYear: "1" } }) })
]);

function lawFor(declaration, id = "calendar:test") {
  return coordinateLaw({
    frames: { [id]: { id, traits: declaration.kind === "gregorian" ? ["line", "gregorian"] : ["set", "calendar"], coordinate: declaration } }
  }, id);
}

const DAY_2026_08_20 = new Rational(daysFromCivil(2026n, 8n, 20n));

// --- minimap.js: era-qualified year in a label ------------------------------

test("a law with no era table renders a minimap label byte-identical to before eras existed", () => {
  assert.equal(minimapLabelText(DAY_2026_08_20, "month", GREGORIAN_LAW), "Aug '26");
  assert.equal(minimapLabelText(DAY_2026_08_20, "quarter", GREGORIAN_LAW), "Q3-26");
  // The default law argument takes the same path.
  assert.equal(minimapLabelText(DAY_2026_08_20, "month"), "Aug '26");
});

test("a minimap label on an era law carries the era-qualified year, not a two-digit civil one", () => {
  // Two era FRAMES, stapled: the frame is which era a coordinate means, so the
  // law is asked for per era rather than switching on a level value.
  const bceLaw = chainLaw(BCE_CE_CHAIN, PLAIN_GREGORIAN_LADDER, "era:bce");
  const ceLaw = chainLaw(BCE_CE_CHAIN, PLAIN_GREGORIAN_LADDER, "era:ce");
  const at = (law, year, month, day) => law.toDays({
    levels: [
      { level: "year", value: String(year) },
      { level: "month", value: String(month) },
      { level: "day", value: String(day) }
    ]
  });
  const bce = bceLaw;
  // 44 BCE, March 15 -- month and quarter labels both carry the suffix affix
  // this era authored ("44 BCE"), never a bare two-digit year.
  const bceDays = at(bceLaw, 44, 3, 15);
  assert.equal(minimapLabelText(bceDays, "month", bce), "Mar 44 BCE");
  assert.equal(minimapLabelText(bceDays, "quarter", bce), "Q1-44 BCE");
  assert.doesNotMatch(minimapLabelText(bceDays, "month", bce), /'\d\d$/, "never the two-digit civil form");

  // 2026 CE crosses the era boundary going the other way.
  const ceDays = at(ceLaw, 2026, 8, 20);
  assert.equal(minimapLabelText(ceDays, "month", ceLaw), "Aug 2026 CE");
  assert.equal(minimapLabelText(ceDays, "quarter", ceLaw), "Q3-2026 CE");
});

test("a day outside every declared era omits its label instead of throwing", () => {
  const closed = chainLaw(CLOSED_CHAIN, PLAIN_GREGORIAN_LADDER, "era:only");
  // Inside the one declared era (proper years 1..5): a real label comes back.
  const inside = new Rational(daysFromCivil(3n, 6n, 15n));
  assert.doesNotThrow(() => closed.formatYearAtDays(inside));
  assert.notEqual(minimapLabelText(inside, "month", closed), "");

  // Far outside it: the underlying law genuinely throws (asserted directly,
  // since that throw is the contract minimapLabelText must be defending
  // against) -- and the label function swallows it into an omission. Only
  // the fact of the throw is pinned, not its message: the era model beneath
  // `formatYearAtDays` is being reworked (eras as stapled frames rather than
  // a table), and that accessor is the stable display contract this test
  // means to exercise, not the wording underneath it.
  const outside = DAY_2026_08_20;
  assert.throws(() => closed.formatYearAtDays(outside));
  assert.equal(minimapLabelText(outside, "month", closed), "");
  assert.equal(minimapLabelText(outside, "quarter", closed), "");

  // The tick pipeline never crashes over a range straddling both, and never
  // lets an empty-text tick through.
  const ticks = minimapLabelTicks(inside, outside, "month", 0, closed);
  assert.ok(Array.isArray(ticks));
  for (const tick of ticks) assert.notEqual(tick.text, "");
});

// --- minimap.js: honest ladder degrade on a non-Gregorian month ladder -----

test("the label ladder degrades to day/hour rungs on a law with no Gregorian month, and never emits one it cannot place", () => {
  const tamriel = lawFor(TAMRIEL_DECLARATION);
  const start = Rational.parse(0);

  // Month and quarter granularity have NO rung this law can execute (its
  // ladder carries no `gregorian.months` transition at all) -- honest
  // omission, not a guessed civil month boundary.
  assert.deepEqual(minimapLabelTicks(start, start.add(3000), "month", 0, tamriel), []);
  assert.deepEqual(minimapLabelTicks(start, start.add(3000), "quarter", 0, tamriel), []);

  // Day granularity still works: it falls back to the day rungs it CAN
  // compute once the month rungs are filtered out of its own ladder.
  const dayTicks = minimapLabelTicks(start, start.add(1000), "day", 0, tamriel);
  assert.ok(dayTicks.length > 0, "day granularity still produces ticks");
  for (const tick of dayTicks) assert.equal(tick.format, "day", "no month-format tick sneaks in");

  // A plain Gregorian law is untouched: month rungs remain usable.
  const gregorianTicks = minimapLabelTicks(start, start.add(1000), "day", 0, GREGORIAN_LAW);
  assert.ok(gregorianTicks.some((tick) => tick.format === "month"), "Gregorian's day ladder still reaches its month rung");
});

// --- toolbar.js: Now-related control gated on mapsToClock() ----------------
//
// A trimmed copy of test/toolbar-dropdowns.test.js's stub DOM: just enough
// for createToolbar's construction-time wiring and updateLensControls() to
// run without throwing, since exercising the real disabled-button behaviour
// needs the real DOM-building code path, not a hand-summarized assertion.
function createStubDom() {
  class StubElement {
    constructor(tag = "div") {
      this.tagName = tag.toUpperCase();
      this.children = [];
      this.parentElement = null;
      this.dataset = {};
      this.attributes = new Map();
      this.handlers = new Map();
      this.style = {
        values: new Map(),
        setProperty(name, value) { this.values.set(name, value); },
        getPropertyValue(name) { return this.values.get(name) ?? ""; }
      };
      this.hidden = false;
      this.disabled = false;
      this.checked = false;
      this.open = false;
      this.value = "";
      this.textContent = "";
      this.className = "";
      this.rect = { left: 0, top: 0, width: 120, height: 32 };
    }

    get nextSibling() {
      if (!this.parentElement) return null;
      const index = this.parentElement.children.indexOf(this);
      return index < 0 ? null : this.parentElement.children[index + 1] || null;
    }

    append(...nodes) {
      for (const node of nodes) {
        if (node.parentElement) node.parentElement.children = node.parentElement.children.filter((child) => child !== node);
        node.parentElement = this;
        this.children.push(node);
      }
    }

    replaceChildren(...nodes) {
      for (const child of this.children) child.parentElement = null;
      this.children = [];
      this.append(...nodes);
    }

    remove() {
      if (!this.parentElement) return;
      this.parentElement.children = this.parentElement.children.filter((child) => child !== this);
      this.parentElement = null;
    }

    setAttribute(name, value) { this.attributes.set(name, String(value)); }
    getAttribute(name) { return this.attributes.get(name) ?? null; }

    get classList() {
      const self = this;
      return {
        add(...names) {
          const set = new Set(String(self.className).split(/\s+/).filter(Boolean));
          for (const name of names) set.add(name);
          self.className = [...set].join(" ");
        },
        remove(name) {
          self.className = String(self.className).split(/\s+/).filter((token) => token && token !== name).join(" ");
        },
        toggle() {},
        contains(name) { return String(self.className).split(/\s+/).includes(name); }
      };
    }

    addEventListener(type, handler) {
      if (!this.handlers.has(type)) this.handlers.set(type, []);
      this.handlers.get(type).push(handler);
    }

    dispatch(type, event = {}) {
      for (const handler of this.handlers.get(type) || []) handler({ preventDefault() {}, currentTarget: this, target: this, ...event });
    }

    getBoundingClientRect() { return this.rect; }

    descendants() {
      return this.children.flatMap((child) => [child, ...(typeof child.descendants === "function" ? child.descendants() : [])]);
    }

    querySelectorAll() { return []; }
    querySelector() { return null; }
    contains(node) {
      let current = node;
      while (current) {
        if (current === this) return true;
        current = current.parentElement;
      }
      return false;
    }
    focus() {}
    blur() {}
    click() { this.dispatch("click"); }
  }

  const elementsById = new Map();
  const byId = (id, tag) => {
    const node = new StubElement(tag);
    node.id = id;
    elementsById.set(id, node);
    return node;
  };

  for (const id of [
    "shared-focus", "undo", "redo", "new-event", "new-todo", "new-note", "create-frame",
    "theme-settings", "lens-settings", "dock-side",
    "open-todos", "open-notes", "open-document", "document-file",
    "save-document", "save-as-document", "lens-bar", "lens-bar-tools",
    "manage-frames", "manage-frames-proxy", "new-pattern",
    "sync-calendars", "import-ics", "export-ics",
    "document-card-body", "snapshot-period-field", "snapshot-period"
  ]) byId(id);

  function dropdown(id, panelClass) {
    const container = byId(id, "details");
    container.setAttribute("data-bar-dropdown", "");
    const summary = new StubElement("summary");
    const panel = new StubElement("div");
    panel.className = panelClass;
    container.append(summary, panel);
    container.querySelector = (selector) => selector === "summary" ? summary : null;
    return container;
  }

  const createMenu = dropdown("create-menu", "create-menu-panel");
  const hiddenLenses = dropdown("hidden-lenses", "hidden-lens-panel");
  const frameSelect = dropdown("frame-select", "frame-select-panel");
  const frameSelectSummaryValue = new StubElement("span");
  frameSelectSummaryValue.className = "frame-select-summary-value";
  frameSelect.querySelector("summary").append(frameSelectSummaryValue);
  frameSelect.querySelector = (selector) => selector === ".frame-select-summary-value"
    ? frameSelectSummaryValue
    : selector === "summary" ? frameSelect.children[0] : null;
  const documentMenu = byId("document-menu", "details");
  const documentMenuSummary = new StubElement("summary");
  documentMenu.append(documentMenuSummary);
  documentMenu.querySelector = () => documentMenuSummary;
  const dropdownLayer = byId("dropdown-layer");
  const lensControls = new StubElement("section");
  const projection = new StubElement("div");

  function eventTarget(base) {
    const handlers = new Map();
    return Object.assign(base, {
      addEventListener(type, handler) {
        if (!handlers.has(type)) handlers.set(type, []);
        handlers.get(type).push(handler);
      },
      dispatch(type, event = {}) {
        for (const handler of handlers.get(type) || []) handler({ preventDefault() {}, defaultPrevented: false, ...event });
      }
    });
  }

  const documentStub = eventTarget({
    createElement: (tag) => new StubElement(tag),
    createTextNode: (text) => ({ nodeType: 3, textContent: String(text), parentElement: null, className: "" }),
    getElementById: (id) => elementsById.get(id) || null,
    querySelectorAll: (selector) => selector === "[data-bar-dropdown]"
      ? [...elementsById.values()].filter((node) => node.getAttribute("data-bar-dropdown") !== null)
      : [],
    activeElement: null
  });
  const windowStub = eventTarget({ innerWidth: 1400, innerHeight: 900 });

  return { StubElement, elementsById, dropdownLayer, lensControls, projection, documentStub, windowStub };
}

function toolbarHarness() {
  const stub = createStubDom();
  const previous = { document: globalThis.document, window: globalThis.window };
  globalThis.document = stub.documentStub;
  globalThis.window = stub.windowStub;
  const chronolog = { frames: { "calendar:personal": { id: "calendar:personal", title: "Personal", traits: ["calendar"] } } };
  const app = {
    chronolog,
    session: new ViewSession({}),
    history: { undoStack: [], redoStack: [] },
    scheduleRender() {},
    toast() {}
  };
  const toolbar = createToolbar(app, { projection: stub.projection, lensControls: stub.lensControls, LOCAL_WORKSPACE_TARGET: {} });
  const restore = () => Object.assign(globalThis, previous);
  return { ...stub, app, toolbar, restore };
}

function findById(root, id) {
  for (const node of root.descendants()) {
    if (node.id === id) return node;
  }
  return null;
}

test("the today control stays enabled under the standard, clock-mapping law", () => {
  const h = toolbarHarness();
  try {
    assert.equal(h.app.session.law.mapsToClock(), true, "the registered standard maps to the running clock");
    h.toolbar.updateLensControls();
    const today = findById(h.lensControls, "today");
    assert.ok(today, "the today control was built");
    assert.equal(today.disabled, false);
  } finally {
    h.restore();
  }
});

test("the today control is disabled with an honest reason on a law with no now-mapping", () => {
  const h = toolbarHarness();
  try {
    // `clock: false` is the author's own declaration that this calendar has
    // no relation to the running clock -- the owner's field note: "no
    // artificial Now line on a calendar with no now-mapping."
    const noClock = new CoordinateLaw({ ...TAMRIEL_DECLARATION, clock: false });
    assert.equal(noClock.mapsToClock(), false);
    h.app.session.setCoordinateLaw(noClock);
    h.toolbar.updateLensControls();
    const today = findById(h.lensControls, "today");
    assert.ok(today, "the today control was built");
    assert.equal(today.disabled, true, "an honest refusal, not a fabricated civil today");
    assert.match(today.title, /no now-mapping|no today/i);
  } finally {
    h.restore();
  }
});
