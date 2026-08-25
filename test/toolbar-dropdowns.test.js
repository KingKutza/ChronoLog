import assert from "node:assert/strict";
import test from "node:test";
import { createToolbar } from "../src/ui/toolbar.js";
import { ViewSession } from "../src/session.js";

// A1 in the 8.19 field report: "the Lenses Hamburger menu renders below the
// Context Bar ... correct flip on edge and z level should be properties of
// the class." toolbar.js now routes every bar dropdown through one registry
// (registerBarDropdown / dropdowns, exposed here as `barDropdowns`) instead
// of the hand-maintained placement list that omitted #hidden-lenses in the
// first place. This harness follows test/dock-dom.test.js's stub-DOM
// pattern, extended with the bits toolbar.js touches that dock.js does not:
// <details>/summary/panel trees, `querySelector`, `insertBefore` (the
// portal-home-and-back mechanics), and a selector matcher that understands
// `input[type="checkbox"]:checked` (the Frame drop's own change handler).
function matchesSimpleSelector(node, selector) {
  let sel = selector;
  let requireChecked = false;
  if (sel.endsWith(":checked")) {
    requireChecked = true;
    sel = sel.slice(0, -":checked".length);
  }
  if (sel.startsWith(".")) {
    return String(node.className).split(/\s+/).includes(sel.slice(1)) && (!requireChecked || node.checked);
  }
  const attrMatch = sel.match(/^([a-zA-Z-]*)\[([a-zA-Z-]+)="([^"]*)"\]$/);
  if (attrMatch) {
    const [, tag, attrName, attrValue] = attrMatch;
    if (tag && node.tagName !== tag.toUpperCase()) return false;
    const actual = attrName === "type" ? node.type : node.getAttribute(attrName);
    if (String(actual) !== attrValue) return false;
    return !requireChecked || node.checked;
  }
  if (/^[a-zA-Z-]+$/.test(sel)) return node.tagName === sel.toUpperCase() && (!requireChecked || node.checked);
  return false;
}

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

    insertBefore(node, reference) {
      if (node.parentElement) node.parentElement.children = node.parentElement.children.filter((child) => child !== node);
      node.parentElement = this;
      const index = reference ? this.children.indexOf(reference) : -1;
      if (index < 0) this.children.push(node);
      else this.children.splice(index, 0, node);
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
      const list = {
        // Real DOM classList.add() takes any number of names in one call
        // (toolbar.js's today/reset-view controls now do exactly that --
        // `.classList.add("today-target", "square")` -- so a single-name stub
        // would silently drop the second one).
        add(...names) {
          const set = new Set(String(self.className).split(/\s+/).filter(Boolean));
          for (const name of names) set.add(name);
          self.className = [...set].join(" ");
        },
        remove(name) {
          self.className = String(self.className).split(/\s+/).filter((token) => token && token !== name).join(" ");
        },
        toggle(name, force) {
          const has = String(self.className).split(/\s+/).includes(name);
          const want = force === undefined ? !has : Boolean(force);
          if (want) list.add(name); else list.remove(name);
          return want;
        },
        contains(name) { return String(self.className).split(/\s+/).includes(name); }
      };
      return list;
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
      // Text nodes (document.createTextNode) are plain objects, not
      // StubElements, and have no descendants of their own.
      return this.children.flatMap((child) => [child, ...(typeof child.descendants === "function" ? child.descendants() : [])]);
    }

    matches(selector) {
      return matchesSimpleSelector(this, selector);
    }

    contains(node) {
      let current = node;
      while (current) {
        if (current === this) return true;
        current = current.parentElement;
      }
      return false;
    }

    querySelectorAll(selector) {
      // toolbar.js's focusableElements() passes a real comma-separated
      // compound selector ("button, input, select, textarea, a[href]") — the
      // same string a browser would take — so the stub splits on comma
      // rather than asking every caller to pass one simple selector at a
      // time.
      const parts = selector.split(",").map((part) => part.trim());
      return this.descendants().filter((node) => parts.some((part) => matchesSimpleSelector(node, part)));
    }

    querySelector(selector) {
      return this.querySelectorAll(selector)[0] || null;
    }

    focus() { globalThis.document.activeElement = this; }
    blur() { if (globalThis.document.activeElement === this) globalThis.document.activeElement = null; }
    // The manage-frames-proxy delegation (bug 5) calls the real, permanently
    // hidden #manage-frames button's own .click() rather than reimplementing
    // its behavior, so the stub needs to support that exact call.
    click() { this.dispatch("click"); }
  }

  const elementsById = new Map();
  const byId = (id, tag) => {
    const node = new StubElement(tag);
    node.id = id;
    elementsById.set(id, node);
    return node;
  };

  // The chrome ids toolbar.js's top-level wiring reaches for unconditionally.
  // Anything not a dropdown is a bare stub — createToolbar only needs it to
  // exist and accept addEventListener/property writes without throwing.
  for (const id of [
    "shared-focus", "undo", "redo", "new-event", "new-todo", "new-note", "create-frame",
    "theme-settings", "lens-settings", "dock-side",
    "open-todos", "open-notes", "open-document", "document-file",
    "save-document", "save-as-document", "lens-bar", "lens-bar-tools",
    "manage-frames", "manage-frames-proxy", "new-pattern",
    "sync-calendars", "import-ics", "export-ics",
    "document-card-body", "snapshot-period-field", "snapshot-period"
  ]) byId(id);

  // Static dropdowns enroll by carrying `data-bar-dropdown` in the shell (the
  // same attribute pocket-instrument.html's three remaining static <details>
  // carry) — toolbar.js sweeps for it once at construction rather than being
  // handed a hand-kept list of ids and panel classes, so the panel is
  // discovered as "whichever child of the <details> is not its <summary>",
  // never a named class.
  function dropdown(id, panelClass) {
    const container = byId(id, "details");
    container.setAttribute("data-bar-dropdown", "");
    const summary = new StubElement("summary");
    const panel = new StubElement("div");
    panel.className = panelClass;
    container.append(summary, panel);
    return container;
  }

  const createMenu = dropdown("create-menu", "create-menu-panel");
  const hiddenLenses = dropdown("hidden-lenses", "hidden-lens-panel");
  const frameSelect = dropdown("frame-select", "frame-select-panel");
  // updateFrameSelect() writes the leading-frame summary into this span,
  // exactly as pocket-instrument.html nests it inside <summary>.
  const frameSelectSummaryValue = new StubElement("span");
  frameSelectSummaryValue.className = "frame-select-summary-value";
  frameSelect.querySelector("summary").append(frameSelectSummaryValue);
  // Bug 5: the document control is a <details> with only a <summary> child —
  // no panel, and no data-bar-dropdown — because it opens a dock card
  // (src/ui/toolbar.js's openDocumentCard) rather than a floating dropdown.
  // Its click handler calls preventDefault() itself, so the stub does not
  // need to model native <details> toggling for this one.
  const documentMenu = byId("document-menu", "details");
  const documentMenuSummary = new StubElement("summary");
  documentMenu.append(documentMenuSummary);
  const dropdownLayer = byId("dropdown-layer");
  const lensControls = new StubElement("section");
  const projection = new StubElement("div");

  // A minimal but real event target: toolbar.js's outside-interaction and
  // Escape/Tab contract listens on `document`/`window` directly (not on any
  // one dropdown's container), so the stub has to actually store and fire
  // handlers rather than swallow addEventListener like a no-op, or none of
  // that half of the contract would be exercisable at all.
  function eventTarget(base) {
    const handlers = new Map();
    return Object.assign(base, {
      addEventListener(type, handler) {
        if (!handlers.has(type)) handlers.set(type, []);
        handlers.get(type).push(handler);
      },
      dispatch(type, event = {}) {
        for (const handler of handlers.get(type) || []) {
          handler({ preventDefault() {}, defaultPrevented: false, ...event });
        }
      }
    });
  }

  const documentStub = eventTarget({
    createElement: (tag) => new StubElement(tag),
    createTextNode: (text) => ({ nodeType: 3, textContent: String(text), parentElement: null, className: "" }),
    getElementById: (id) => elementsById.get(id) || null,
    // The one selector toolbar.js's construction-time sweep actually issues
    // against `document` itself (as opposed to a container's own subtree,
    // which StubElement.querySelectorAll already covers).
    querySelectorAll: (selector) => selector === "[data-bar-dropdown]"
      ? [...elementsById.values()].filter((node) => node.getAttribute("data-bar-dropdown") !== null)
      : [],
    activeElement: null
  });
  const windowStub = eventTarget({
    innerWidth: 1400,
    innerHeight: 900
  });

  return {
    StubElement, elementsById, createMenu, documentMenu, documentMenuSummary, hiddenLenses, frameSelect,
    dropdownLayer, lensControls, projection, documentStub, windowStub
  };
}

function harness() {
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

// Opens a registered dropdown the way a real click on its summary would (the
// browser toggles `.open` and fires "toggle" before this module's own
// listener runs).
function open(container) {
  container.open = true;
  container.dispatch("toggle");
}

function close(container) {
  container.open = false;
  container.dispatch("toggle");
}

test("every registered bar dropdown ends up in the shared layer, edge-flipped, when opened", () => {
  const h = harness();
  try {
    // Drive this off the registry, not a hand-written id list — a future
    // dropdown that calls registerBarDropdown is covered by this test with no
    // change here, which is the whole point of the class.
    const ids = h.toolbar.barDropdowns.ids();
    assert.ok(ids.includes("create-menu") && ids.includes("hidden-lenses") && ids.includes("frame-select"),
      "every static attachment point enrolled at construction");
    // The document control is deliberately not one of them any more (bug 5):
    // it opens a dock card, not a dropdown panel, so it carries no
    // data-bar-dropdown attribute and never registers here.
    assert.ok(!ids.includes("document-menu"), "the document control is a dock-card trigger now, not a bar dropdown");
    for (const id of ids) {
      const entry = h.toolbar.barDropdowns.get(id);
      assert.equal(entry.panel.parentElement, entry.container, `${id}'s panel starts at home, not already in the layer`);
      open(entry.container);
      assert.equal(entry.panel.parentElement, h.dropdownLayer, `${id}'s panel portals into #dropdown-layer on open`);
      // Placed by measurement (position: fixed, numeric left/top) rather than
      // left where CSS last pinned it — the edge-flip half of the fix.
      assert.equal(entry.panel.style.position, "fixed");
      assert.equal(typeof entry.panel.style.left, "string");
      assert.match(entry.panel.style.left, /^\d+px$/);
      assert.match(entry.panel.style.top, /^\d+px$/);
      close(entry.container);
      assert.equal(entry.panel.parentElement, entry.container, `${id}'s panel returns home on close`);
    }
  } finally {
    h.restore();
  }
});

// The exact regression: #hidden-lenses used to be absent from the hand-kept
// placement list, so opening it did nothing — it just sat under the CSS
// pin, which the context bar's equal z-index then painted over. Enrolling it
// (done once, at construction, in this file) is what makes it reachable
// through the very same mechanism as every other dropdown.
test("the hidden-lens hamburger reaches the shared layer like any other bar dropdown", () => {
  const h = harness();
  try {
    h.app.session.configureLenses({ enabledLenses: h.app.session.lensOrder.filter((lens) => lens !== "wall") });
    h.toolbar.updateChrome();
    const entry = h.toolbar.barDropdowns.get("hidden-lenses");
    assert.equal(h.hiddenLenses.hidden, false, "a hidden lens exists, so the drop is shown");
    open(entry.container);
    assert.equal(entry.panel.parentElement, h.dropdownLayer);
    assert.ok(entry.panel.children.length > 0, "the restore-this-lens buttons were built");
  } finally {
    h.restore();
  }
});

// The subtle part: updateLensControls() rebuilds a brand-new <details> and
// panel every time its signature changes. If the previous panel was open
// (portaled into the layer) when that happens, the old node must not linger
// in the layer forever once nothing points at it any more.
test("a rebuilt dropdown (lens-control Options) does not leak its old panel into the layer", () => {
  const h = harness();
  try {
    h.toolbar.updateLensControls();
    const findOptions = () => h.lensControls.children.find((child) => child.className === "lens-control-overflow");
    const first = findOptions();
    open(first);
    assert.equal(h.dropdownLayer.children.filter((child) => child.className === "lens-control-overflow-panel").length, 1);

    // Force a rebuild: any session field in updateLensControls' signature.
    h.app.session.tacticalRows = h.app.session.tacticalRows + 1;
    h.toolbar.updateLensControls();
    const second = findOptions();
    assert.notEqual(second, first, "a new <details> replaced the old one");

    const overflowPanelsInLayer = h.dropdownLayer.children.filter((child) => child.className === "lens-control-overflow-panel");
    assert.equal(overflowPanelsInLayer.length, 1, "exactly one overflow panel lives in the layer — the old one was swept, not merely joined by a new one");
    assert.equal(second.open, true, "the rebuilt dropdown preserves its open state across the rebuild");
    assert.equal(overflowPanelsInLayer[0].parentElement, h.dropdownLayer);
  } finally {
    h.restore();
  }
});

// renderHiddenLenses() used to look its panel up with
// `drop.querySelector(".hidden-lens-panel")`, which only finds it while the
// panel is still nested under <details id="hidden-lenses"> — exactly the
// place it is not while open and portaled. Rebuilding its contents (picking
// a different lens to hide) while the drop is open is the case that would
// have broken.
test("hidden-lens panel contents can be rebuilt while the drop is open and portaled", () => {
  const h = harness();
  try {
    const { session } = h.app;
    session.configureLenses({ enabledLenses: session.lensOrder.filter((lens) => lens !== "wall") });
    h.toolbar.updateChrome();
    const entry = h.toolbar.barDropdowns.get("hidden-lenses");
    open(entry.container);
    assert.equal(entry.panel.parentElement, h.dropdownLayer);

    // Hide a second lens while the drop is open and already portaled.
    session.configureLenses({ enabledLenses: session.lensOrder.filter((lens) => !["wall", "lines"].includes(lens)) });
    assert.doesNotThrow(() => h.toolbar.updateChrome(), "renderHiddenLenses must find its panel via the registry, not a DOM query rooted at #hidden-lenses");
    assert.equal(entry.panel.children.length, 2, "both hidden lenses now have a restore button");
  } finally {
    h.restore();
  }
});

// The ToDo lenses are ordinary catalog lenses, so every hidden-lens flow --
// the drop offering them, and restore-and-switch from it -- covers them with
// no lens-specific code anywhere in the toolbar.
test("the hidden-lens flows carry the ToDo lenses like any other catalog lens", () => {
  const h = harness();
  try {
    const { session } = h.app;
    session.configureLenses({ enabledLenses: session.lensOrder.filter((lens) => !["list", "board"].includes(lens)) });
    h.toolbar.updateChrome();
    const entry = h.toolbar.barDropdowns.get("hidden-lenses");
    assert.equal(h.hiddenLenses.hidden, false, "hiding the ToDo lenses shows the drop");
    open(entry.container);
    const titles = entry.panel.children.map((child) => child.textContent);
    assert.deepEqual(titles, ["List", "Board"], "both ToDo lenses offer their restore buttons");
    // Restoring from the drop re-enables and switches, same as any lens.
    entry.panel.children[0].dispatch("click");
    assert.ok(session.enabledLenses.includes("list"), "picking List restores it to the bar");
    assert.equal(session.currentLens(), "list", "and switches to it");
  } finally {
    h.restore();
  }
});

// A2/A7 smoke check riding along on the same harness: the Frame drop is a
// bar dropdown too (relabeled from "Active calendar"), and it enrolls and
// behaves exactly like the others — proof a *new* dropdown needs nothing
// extra from the placement code.
test("the Frame drop is a bar dropdown like any other, and reflects multi-selection", () => {
  const h = harness();
  try {
    h.app.chronolog.frames["calendar:work"] = { id: "calendar:work", title: "Work", traits: ["calendar"] };
    h.toolbar.updateCalendarSelect();
    const entry = h.toolbar.barDropdowns.get("frame-select");
    // The panel holds one <label class="check-chip"> per frame.
    const labels = entry.panel.children.filter((child) => child.className === "check-chip");
    assert.equal(labels.length, 2, "one checkbox per calendar frame");
    const personalCheckbox = labels.find((label) => label.children[0].value === "calendar:personal").children[0];
    const workCheckbox = labels.find((label) => label.children[0].value === "calendar:work").children[0];
    assert.equal(personalCheckbox.checked, true, "the leading frame starts checked");
    assert.equal(workCheckbox.checked, false);

    // Checking a second frame adds a companion without disturbing the leader.
    workCheckbox.checked = true;
    workCheckbox.dispatch("change");
    assert.equal(h.app.session.activeFrame, "calendar:personal", "leading frame unchanged");
    assert.deepEqual(h.app.session.companionFrames, ["calendar:work"]);

    open(entry.container);
    assert.equal(entry.panel.parentElement, h.dropdownLayer, "the Frame drop portals into the shared layer exactly like create/document menu");
  } finally {
    h.restore();
  }
});

// Owner item 1 (8.19 field report): every selected frame must overlay, from
// every surface, with one explicit primary marker — not just the frames
// dock's own checkboxes, which used to be the only place this worked. The
// Frame drop had no way at all to say which checked frame leads; this is
// that control.
test("the Frame drop carries an explicit primary marker per row, reassignable without losing the selection", () => {
  const h = harness();
  try {
    h.app.chronolog.frames["calendar:work"] = { id: "calendar:work", title: "Work", traits: ["calendar"] };
    // Stands in for the real app.selectLeadingFrame (src/ui/frames-panel.js),
    // which the marker routes through exactly like the leading select does.
    h.app.selectLeadingFrame = (frameId) => h.app.session.setLeadingFrame(frameId);
    h.toolbar.updateCalendarSelect();
    const entry = h.toolbar.barDropdowns.get("frame-select");
    const labels = entry.panel.children.filter((child) => child.className === "check-chip");
    const personalLabel = labels.find((label) => label.children[0].value === "calendar:personal");
    const workLabel = labels.find((label) => label.children[0].value === "calendar:work");
    const personalMarker = personalLabel.children[2];
    const workMarker = workLabel.children[2];
    const workCheckbox = workLabel.children[0];

    assert.ok(personalMarker.classList.contains("frame-primary-marker"));
    assert.equal(personalMarker.getAttribute("aria-pressed"), "true", "the leading frame starts as primary");
    assert.equal(personalMarker.disabled, true, "the current primary's own marker is not actionable");
    assert.equal(workMarker.getAttribute("aria-pressed"), "false");
    assert.equal(workMarker.disabled, true, "an unselected frame's marker is disabled until it is checked");

    workCheckbox.checked = true;
    workCheckbox.dispatch("change");
    h.toolbar.updateCalendarSelect();
    assert.equal(workMarker.disabled, false, "now selected, its marker becomes actionable");

    workMarker.dispatch("click");
    assert.equal(h.app.session.activeFrame, "calendar:work", "clicking the marker reassigns the primary");
    assert.deepEqual(h.app.session.companionFrames, ["calendar:personal"],
      "reassigning the primary must not drop the previous one from the selection — the reported regression");

    h.toolbar.updateCalendarSelect();
    assert.equal(workMarker.getAttribute("aria-pressed"), "true");
    assert.equal(personalMarker.getAttribute("aria-pressed"), "false");
    assert.equal(personalMarker.disabled, false, "the demoted frame is still selected, so its marker is actionable again");
  } finally {
    h.restore();
  }
});

// The widened contract, item by item — see the 8.19 field report's Stage A
// item 1. Every one of these used to be either absent, or a hand patch on
// one dropdown (create-menu's own `pointerdown` check) rather than a
// property every registrant gets. Deleting that patch and proving the
// generic version covers create-menu exactly as well is the point of the
// tests below, not just adding new coverage.

test("opening one bar dropdown closes every other bar dropdown that was open — a bar has one open drop at a time", () => {
  const h = harness();
  try {
    const ids = h.toolbar.barDropdowns.ids();
    assert.ok(ids.length >= 2, "need at least two dropdowns to prove exclusivity");
    for (const openerId of ids) {
      for (const victimId of ids) {
        if (victimId === openerId) continue;
        const victim = h.toolbar.barDropdowns.get(victimId);
        const opener = h.toolbar.barDropdowns.get(openerId);
        open(victim.container);
        assert.equal(victim.container.open, true, `${victimId} opened`);
        open(opener.container);
        assert.equal(opener.container.open, true, `${openerId} stays open — it is the one just opened`);
        assert.equal(victim.container.open, false,
          `${victimId} closed the instant ${openerId} opened, driven by exclusiveOpenSet in panel-flip.js, not a hand-paired listener naming these two specifically`);
        close(opener.container);
      }
    }
  } finally {
    h.restore();
  }
});

test("a press outside a registered dropdown closes it, portaled panel included, with no per-dropdown code", () => {
  const h = harness();
  try {
    const outsider = new h.StubElement("div");
    for (const id of h.toolbar.barDropdowns.ids()) {
      const entry = h.toolbar.barDropdowns.get(id);
      open(entry.container);
      assert.equal(entry.container.open, true);
      // Dispatched at `document`, exactly where toolbar.js's one generic
      // listener lives — not at the container, which a portaled panel is no
      // longer inside.
      h.documentStub.dispatch("pointerdown", { target: outsider });
      assert.equal(entry.container.open, false, `${id} closed on an outside press`);
      assert.equal(entry.panel.parentElement, entry.container, `${id}'s panel returned home`);
    }
  } finally {
    h.restore();
  }
});

// The exact case the first pass could only fix per-dropdown: a click on
// "Event"/"ToDo"/"Note" lands inside the portaled panel, not inside
// #create-menu, so `container.contains(event.target)` alone reads it as
// outside. outsideInteractionCloses checks container OR panel for every
// registrant, so create-menu needs no patch of its own any more — this test
// would fail exactly the way the original bug did if that patch were still
// the only thing covering it and had not been generalized.
test("a press inside a portaled panel's own content is not \"outside\" it", () => {
  const h = harness();
  try {
    const entry = h.toolbar.barDropdowns.get("create-menu");
    open(entry.container);
    assert.equal(entry.panel.parentElement, h.dropdownLayer, "portaled, no longer a descendant of #create-menu");
    h.documentStub.dispatch("pointerdown", { target: entry.panel });
    assert.equal(entry.container.open, true, "a click on the panel's own content must not close it");
  } finally {
    h.restore();
  }
});

test("Escape closes the open bar dropdown and returns focus to its anchor", () => {
  const h = harness();
  try {
    for (const id of h.toolbar.barDropdowns.ids()) {
      const entry = h.toolbar.barDropdowns.get(id);
      open(entry.container);
      assert.equal(entry.container.open, true);
      h.windowStub.dispatch("keydown", { key: "Escape" });
      assert.equal(entry.container.open, false, `${id} closed on Escape`);
      assert.equal(h.documentStub.activeElement, entry.anchor, `${id} returned focus to its anchor/summary`);
    }
  } finally {
    h.restore();
  }
});

// A portaled panel is no longer a DOM descendant of its anchor, so the
// browser's native tab order no longer runs summary -> panel -> next
// control — it runs summary -> ... -> wherever #dropdown-layer sits in the
// document. The Frame drop's checkboxes are real, ordered children in this
// harness (create/document menu's buttons live outside the stub DOM tree
// entirely, so they cannot exercise cycling here), which is why this test
// rides on it rather than create-menu.
test("Tab cycles within an open dropdown's panel instead of a broken portaled tab order", () => {
  const h = harness();
  try {
    h.app.chronolog.frames["calendar:work"] = { id: "calendar:work", title: "Work", traits: ["calendar"] };
    h.toolbar.updateCalendarSelect();
    const entry = h.toolbar.barDropdowns.get("frame-select");
    open(entry.container);
    const checkboxes = entry.panel.children.filter((child) => child.className === "check-chip").map((label) => label.children[0]);
    assert.equal(checkboxes.length, 2, "two checkboxes to cycle between");
    assert.equal(h.documentStub.activeElement, checkboxes[0], "opening focused the first control in the panel");
    h.windowStub.dispatch("keydown", { key: "Tab" });
    assert.equal(h.documentStub.activeElement, checkboxes[1], "Tab moved to the next control");
    h.windowStub.dispatch("keydown", { key: "Tab" });
    assert.equal(h.documentStub.activeElement, checkboxes[0], "Tab wraps back to the first control past the last");
    h.windowStub.dispatch("keydown", { key: "Tab", shiftKey: true });
    assert.equal(h.documentStub.activeElement, checkboxes[1], "Shift+Tab wraps to the last control from the first");
  } finally {
    h.restore();
  }
});

// The audit the field report asks for: enumerate the registry and assert
// every entry satisfies every contract property, so a dropdown added after
// this test is written is covered automatically rather than by someone
// remembering to add a case for it.
test("every registered dropdown satisfies the full bar-dropdown contract", () => {
  const h = harness();
  try {
    h.toolbar.updateLensControls();
    const ids = h.toolbar.barDropdowns.ids();
    // create-menu, hidden-lenses, frame-select are the remaining static
    // drops (bug 5 took the document control out of this set entirely —
    // it opens a dock card instead), plus the dynamic lens-control-overflow.
    assert.ok(ids.length >= 4, "the three static drops plus the dynamic lens-control-overflow are all enrolled");
    const outsider = new h.StubElement("div");
    for (const id of ids) {
      const entry = h.toolbar.barDropdowns.get(id);

      // Keyboard reachability: a native <summary> is focusable and
      // Enter/Space-operable with no extra wiring.
      assert.equal(entry.anchor.tagName, "SUMMARY", `${id}'s anchor is a native summary`);

      // ARIA correctness, independent of open state: the panel is
      // associated with its anchor even though a portal means it is not a
      // DOM descendant of it.
      assert.ok(entry.panel.id, `${id}'s panel has a stable id`);
      assert.equal(entry.anchor.getAttribute("aria-controls"), entry.panel.id, `${id} points aria-controls at its panel`);
      assert.equal(entry.anchor.getAttribute("aria-haspopup"), "true", `${id} declares that it opens a popup`);
      assert.equal(entry.anchor.getAttribute("aria-expanded"), "false", `${id} starts collapsed`);

      // Open: portal + edge-flip/z-level, aria-expanded tracking real state,
      // and focus moving into the panel (the uniform open-focus rule) rather
      // than staying on the anchor or landing wherever a broken tab order
      // would send it.
      open(entry.container);
      assert.equal(entry.panel.parentElement, h.dropdownLayer, `${id} portals on open`);
      assert.equal(entry.anchor.getAttribute("aria-expanded"), "true", `${id} tracks open state`);
      assert.ok(
        entry.panel === h.documentStub.activeElement || entry.panel.contains(h.documentStub.activeElement),
        `${id} moves focus into its panel on open`
      );

      // Outside interaction closes it, portaled panel included.
      h.documentStub.dispatch("pointerdown", { target: outsider });
      assert.equal(entry.container.open, false, `${id} closes on an outside press`);
      assert.equal(entry.anchor.getAttribute("aria-expanded"), "false", `${id}'s aria-expanded follows the close`);

      // Escape closes it and returns focus to the anchor.
      open(entry.container);
      h.windowStub.dispatch("keydown", { key: "Escape" });
      assert.equal(entry.container.open, false, `${id} closes on Escape`);
      assert.equal(h.documentStub.activeElement, entry.anchor, `${id} returns focus to its anchor on Escape`);
    }
  } finally {
    h.restore();
  }
});

// Owner item 13, generalized past the theme editor: an editing surface must
// be able to assert a change without closing. The lens workspace ("Configure
// lenses") previously only had Save (commits and closes) and Restore
// defaults (resets the draft, does not commit) — no way to see a reorder or
// a hide/show take effect while still looking at the dialog. Apply commits
// the same draft Save would, without calling dismissInspector.
test("the lens workspace's Apply button commits the draft without closing the dialog", () => {
  const h = harness();
  try {
    let inspectorNode = null;
    let dismissed = false;
    h.app.openInspector = (title, node) => { inspectorNode = node; };
    h.app.dismissInspector = () => { dismissed = true; };
    h.elementsById.get("lens-settings").dispatch("click");
    assert.ok(inspectorNode, "opening \"Configure lenses\" built a form");
    const originalFirstLens = h.app.session.lensOrder[0];
    const firstCheckbox = inspectorNode.querySelectorAll('input[type="checkbox"]')[0];
    firstCheckbox.checked = false;
    firstCheckbox.dispatch("change");
    const apply = inspectorNode.querySelectorAll("button").find((node) => node.id === "apply-lens-workspace");
    assert.ok(apply, "an Apply button exists on the lens workspace form");
    apply.dispatch("click");
    assert.equal(dismissed, false, "Apply does not close the dialog");
    assert.ok(!h.app.session.enabledLenses.includes(originalFirstLens), "the unchecked lens is hidden immediately, before Save");
  } finally {
    h.restore();
  }
});

// 8.19 Part Three, Track B: "nor in the lenses setting window is there a clear
// way to see or configure the threshold." The promotion thresholds used to be
// two module constants nobody could see, let alone set. They are now visible
// and editable per lens, on the lens's own row.
//
// The defaults matter as much as the control: they are exactly the constants
// that were hardcoded before (2 and 4), so a document that never touches this
// surface renders identically. That is the regression guard for the whole
// weight rework, asserted here at the UI seam.
test("the lens workspace exposes per-lens promotion thresholds, defaulted so nothing changes", () => {
  const h = harness();
  try {
    let inspectorNode = null;
    h.app.openInspector = (title, node) => { inspectorNode = node; };
    h.app.dismissInspector = () => {};
    h.elementsById.get("lens-settings").dispatch("click");
    assert.ok(inspectorNode, "opening \"Configure lenses\" built a form");

    const thresholdInputs = inspectorNode.querySelectorAll("input")
      .filter((node) => node.dataset?.tier);
    const lenses = new Set(thresholdInputs.map((node) => node.dataset.lens));
    assert.equal(
      lenses.size,
      h.app.session.lensOrder.length,
      "every lens on the workspace gets its own threshold controls"
    );
    for (const lens of lenses) {
      const forLens = thresholdInputs.filter((node) => node.dataset.lens === lens);
      assert.deepEqual(
        forLens.map((node) => node.dataset.tier).sort(),
        ["important", "landmark"],
        `${lens} exposes both promotion tiers`
      );
    }
    assert.deepEqual(
      thresholdInputs.filter((node) => node.dataset.tier === "important").map((node) => node.value),
      thresholdInputs.filter((node) => node.dataset.tier === "important").map(() => "2"),
      "the important threshold defaults to the previously-hardcoded 2"
    );
    assert.deepEqual(
      thresholdInputs.filter((node) => node.dataset.tier === "landmark").map((node) => node.value),
      thresholdInputs.filter((node) => node.dataset.tier === "landmark").map(() => "4"),
      "the landmark threshold defaults to the previously-hardcoded 4"
    );
  } finally {
    h.restore();
  }
});

// Editing a threshold has to actually reach the session, and it has to travel
// on the same Apply the rest of the workspace draft uses -- a control that
// looks live but commits nowhere is worse than no control.
test("editing a lens threshold commits to the session through Apply", () => {
  const h = harness();
  try {
    let inspectorNode = null;
    let dismissed = false;
    h.app.openInspector = (title, node) => { inspectorNode = node; };
    h.app.dismissInspector = () => { dismissed = true; };
    h.elementsById.get("lens-settings").dispatch("click");

    const target = inspectorNode.querySelectorAll("input")
      .find((node) => node.dataset?.tier === "landmark");
    assert.ok(target, "a landmark threshold input exists");
    const lens = target.dataset.lens;
    assert.equal(h.app.session.lensThresholds[lens].landmark, 4, "starts at the default");

    target.value = "7.5";
    target.dispatch("input");
    const apply = inspectorNode.querySelectorAll("button").find((node) => node.id === "apply-lens-workspace");
    apply.dispatch("click");

    assert.equal(dismissed, false, "Apply does not close the dialog");
    assert.equal(h.app.session.lensThresholds[lens].landmark, 7.5, "the edited threshold reached the session");
    assert.equal(
      h.app.session.lensThresholds[lens].important, 2,
      "the tier that was not edited keeps its default"
    );
    // View state, not document state -- so it has to survive the session's own
    // serialization (AGENTS.md's lens extension contract).
    assert.equal(h.app.session.toJSON().lensThresholds[lens].landmark, 7.5, "and it serializes");
  } finally {
    h.restore();
  }
});

// Owner item 3, "New Lacks a New Frame Option": the create-menu ("New") panel
// gained a fourth entry alongside Event/ToDo/Note. It is wired the same way
// those three are — close the menu, then hand off to the one place frame
// creation actually happens (src/ui/frames-panel.js's `createFrame`, exposed
// on `app` the same way `app.createEventAt` is). This only pins the menu
// wiring; test/frame-creation.test.js drives `createFrame`'s own document
// effect, since the frame it opens for editing is a real `innerHTML` form the
// stub DOM cannot render (see that file's header comment).
test("the New menu offers a Frame entry that closes the menu and hands off to createFrame", () => {
  const h = harness();
  try {
    let created = 0;
    h.app.createFrame = () => { created += 1; };
    open(h.createMenu);
    assert.equal(h.createMenu.open, true);
    const frameButton = h.elementsById.get("create-frame");
    assert.ok(frameButton, "a #create-frame control exists in the create menu");
    frameButton.dispatch("click");
    assert.equal(created, 1, "invoking the menu entry calls app.createFrame() exactly once");
    assert.equal(h.createMenu.open, false, "picking an entry closes the New menu, like Event/ToDo/Note do");
  } finally {
    h.restore();
  }
});

// 8.19 Part Three, bug 3: the reported defect (the lens bar hamburger is not
// full-height) is fixed at the .bar-control CLASS level in app.css, which a
// Node test cannot measure directly (there is no layout engine here). What
// this harness CAN verify is the other half of "fix the class, audit every
// sibling": every context-bar control that src/ui/toolbar.js itself builds
// (today/reset/Options-summary/lens-control/lens-readout instances) actually
// carries that class, the same way test/ui-contract.test.js checks the
// static document-bar/view-bar markup.
test("every dynamically-built context-bar control carries the shared bar-control class", () => {
  const h = harness();
  try {
    h.toolbar.updateLensControls();
    const controls = h.lensControls.descendants();
    const today = controls.find((node) => node.id === "today");
    const resetView = controls.find((node) => node.id === "reset-view");
    const optionsSummary = controls.find((node) => node.tagName === "SUMMARY");
    assert.ok(today.classList.contains("bar-control") && today.classList.contains("square"), "today is a full-height square");
    assert.ok(resetView.classList.contains("bar-control") && resetView.classList.contains("square"), "reset-view is a full-height square");
    assert.ok(optionsSummary.classList.contains("bar-control"), "the Options dropdown's summary is the same shape of control as #hidden-lenses");
    const readouts = controls.filter((node) => String(node.className).split(/\s+/).includes("lens-readout"));
    assert.ok(readouts.length > 0 && readouts.every((node) => node.classList.contains("bar-control")), "every lens-readout carries bar-control");
    const lensControlNodes = controls.filter((node) => String(node.className).split(/\s+/).includes("lens-control"));
    assert.ok(lensControlNodes.length > 0 && lensControlNodes.every((node) => node.classList.contains("bar-control")), "every lens-control carries bar-control");
  } finally {
    h.restore();
  }
});

// Bug 5: the document control opens a dock card instead of a floating
// dropdown panel, and a second click on it (while the card is open) closes
// the card again — the same toggle shape as the Frames browser trigger.
test("the document control opens the document/settings card as a dock card, and toggles it closed on a second click", () => {
  const h = harness();
  try {
    let openedTitle = null;
    let openedBody = null;
    let openedPanel = null;
    let closedId = null;
    let cardOpen = false;
    h.app.openInspector = (title, body, panel) => { openedTitle = title; openedBody = body; openedPanel = panel; cardOpen = true; };
    h.app.dockCardBody = (id) => (cardOpen && id === "panel:document-settings" ? openedBody : null);
    h.app.closeDockCard = (id) => { closedId = id; cardOpen = false; };

    h.documentMenuSummary.dispatch("click");
    assert.equal(openedTitle, "Document");
    assert.equal(openedPanel, "document-settings");
    assert.equal(openedBody, h.elementsById.get("document-card-body"), "the same persistent body node is reused, not a fresh one built per open");
    assert.equal(openedBody.hidden, false, "the body is unhidden once it is actually being shown in a card");

    h.documentMenuSummary.dispatch("click");
    assert.equal(closedId, "panel:document-settings", "a second click while open closes the card instead of reopening it");
  } finally {
    h.restore();
  }
});

// Bug 5's audit, item by item — which ids ended up nested inside
// #document-card-body versus relocated elsewhere, is a question about the
// real static markup's tree structure, which this stub (flat byId() stand-ins
// with no authored nesting) does not reproduce; test/ui-contract.test.js's
// "the document card holds the audited document/settings content..." test
// covers that against the actual pocket-instrument.html. What this harness
// adds is the retired "Settings" entry point no longer exists at all.
test("the standalone Settings control is gone — the document control is the only entry point", () => {
  const h = harness();
  try {
    assert.equal(h.elementsById.has("settings"), false, "no #settings id is looked up any more");
  } finally {
    h.restore();
  }
});

// The "Frames workspace" entry stays document-scoped, but its real trigger
// (#manage-frames) is permanently attached outside the dock so
// src/ui/frames-panel.js's repeated byId("manage-frames") lookups never go
// stale across the document card's own open/close cycles (see the comment on
// #manage-frames in pocket-instrument.html). The proxy on the card just
// clicks it.
test("the document card's Frames workspace proxy delegates to the real, permanently-attached manage-frames trigger", () => {
  const h = harness();
  try {
    let realClicks = 0;
    h.elementsById.get("manage-frames").addEventListener("click", () => { realClicks += 1; });
    h.elementsById.get("manage-frames-proxy").dispatch("click");
    assert.equal(realClicks, 1);
  } finally {
    h.restore();
  }
});

// ROADMAP #1's snapshot-compaction period: the field only means anything
// against the local server, so it stays hidden without a local workspace
// target (e.g. this stub harness, which passes LOCAL_WORKSPACE_TARGET: {}).
test("the snapshot period field stays hidden without a local workspace target", () => {
  const h = harness();
  try {
    h.app.openInspector = () => {};
    h.app.dockCardBody = () => null;
    h.app.closeDockCard = () => {};
    h.documentMenuSummary.dispatch("click");
    assert.equal(h.elementsById.get("snapshot-period-field").hidden, true);
  } finally {
    h.restore();
  }
});
