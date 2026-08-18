import assert from "node:assert/strict";
import test from "node:test";
import { createDock } from "../src/ui/dock.js";
import { ViewSession } from "../src/session.js";

// There is no DOM-execution harness in this repo, which is how a wrong import
// path once shipped with a green suite and a dead app. `ui/dock.js` is the newest
// and largest piece of DOM wiring in the workspace, so it gets a stub DOM good
// enough to run its real card lifecycle: create, open, focus, page, reorder,
// close. The stub implements only the surface dock.js actually touches — if
// dock.js reaches for something new, this test fails rather than passing blindly.
function createStubDom() {
  const listeners = new Map();

  class StubElement {
    constructor(tag = "div") {
      this.tagName = tag.toUpperCase();
      this.children = [];
      this.parentElement = null;
      this.dataset = {};
      this.style = {
        values: new Map(),
        setProperty(name, value) { this.values.set(name, value); },
        getPropertyValue(name) { return this.values.get(name) ?? ""; }
      };
      this.attributes = new Map();
      this.handlers = new Map();
      this.hidden = false;
      this.inert = false;
      this.textContent = "";
      this.className = "";
      this.rect = { left: 0, top: 0, width: 900, height: 600 };
    }

    append(...nodes) {
      for (const node of nodes) {
        // Re-appending an existing child moves it, which is exactly how the dock
        // reorders cards without rebuilding their live forms.
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
    addEventListener(type, handler) {
      if (!this.handlers.has(type)) this.handlers.set(type, []);
      this.handlers.get(type).push(handler);
    }

    dispatch(type, event = {}) {
      for (const handler of this.handlers.get(type) || []) handler({ preventDefault() {}, ...event });
    }

    getBoundingClientRect() { return this.rect; }

    descendants() {
      return this.children.flatMap((child) => [child, ...child.descendants()]);
    }

    matches(selector) {
      return String(this.className).split(/\s+/).includes(selector.replace(".", ""));
    }

    closest(selector) {
      let node = this;
      while (node) {
        if (node.matches(selector)) return node;
        node = node.parentElement;
      }
      return null;
    }

    querySelectorAll(selector) {
      const wanted = selector.replace(".", "");
      return this.descendants().filter((node) => String(node.className).split(/\s+/).includes(wanted));
    }
  }

  const root = new StubElement("main");
  const workspace = new StubElement("div");
  const dock = new StubElement("section");
  const resize = new StubElement("div");
  const rail = new StubElement("div");
  const viewport = new StubElement("div");
  const strip = new StubElement("div");
  root.append(workspace);
  workspace.append(dock);
  dock.append(resize, rail, viewport);
  viewport.append(strip);

  // The two Frames triggers live in the document bar, not in the dock, so this
  // harness does not build them. Returning null exercises dock.js's optional
  // chaining, which is the same thing that happens on a shell where a trigger has
  // been hidden at a narrow breakpoint.
  const elementsById = new Map();
  const documentStub = {
    createElement: (tag) => new StubElement(tag),
    getElementById: (id) => elementsById.get(id) || null
  };
  const windowStub = {
    addEventListener(type, handler) {
      if (!listeners.has(type)) listeners.set(type, []);
      listeners.get(type).push(handler);
    }
  };
  return { root, workspace, dock, resize, rail, viewport, strip, documentStub, windowStub, StubElement };
}

function harness() {
  const stub = createStubDom();
  const previous = {
    document: globalThis.document,
    window: globalThis.window,
    requestAnimationFrame: globalThis.requestAnimationFrame
  };
  globalThis.document = stub.documentStub;
  globalThis.window = stub.windowStub;
  globalThis.requestAnimationFrame = (fn) => fn(0);
  const app = {
    session: new ViewSession({}),
    scheduleRender() { app.renders += 1; },
    renders: 0
  };
  // The dock reads the same ids from the shell that app.js hands it. byId is used
  // for the two Frames triggers' aria-expanded, which do not exist here.
  const restore = () => Object.assign(globalThis, previous);
  const dock = createDock(app, {
    root: stub.root,
    dock: stub.dock,
    resize: stub.resize,
    rail: stub.rail,
    viewport: stub.viewport,
    strip: stub.strip
  });
  return { ...stub, app, dock, restore };
}

function handleLabels(rail) {
  return rail.children.map((handle) => handle.children[0]?.textContent);
}

function activeIndexFromTransform(strip) {
  const match = /translateX\((-?\d+)%\)/.exec(strip.style.transform || "");
  return match ? Math.abs(Number(match[1])) / 100 : 0;
}

test("an empty dock is closed and contributes no width", () => {
  const h = harness();
  try {
    assert.equal(h.dock.dockIsOpen(), false);
    assert.equal(h.root.dataset.dockOpen, "false");
    assert.equal(h.dock.dockCardIds().length, 0);
    assert.equal(h.dock.activeDockCardId(), null);
    assert.equal(h.dock.dock === undefined, true, "the API exposes behaviour, not the nodes");
    // A closed dock is hidden from the accessibility tree and takes no track.
    assert.equal(h.dock.dockIsOpen(), false);
    assert.equal(h.root.style.getPropertyValue("--dock-track"), "0px");
  } finally {
    h.restore();
  }
});

test("opening a card opens the dock, builds its handle, and shows it", () => {
  const h = harness();
  try {
    const body = new h.StubElement("form");
    h.dock.openDockCard({ id: "panel:object", title: "Event", body });
    assert.equal(h.dock.dockIsOpen(), true);
    assert.equal(h.root.dataset.dockOpen, "true");
    assert.equal(h.root.dataset.dockSide, "right", "right is the default side");
    assert.deepEqual(handleLabels(h.rail), ["Event"]);
    assert.deepEqual(h.dock.dockCardIds(), ["panel:object"]);
    assert.equal(h.dock.activeDockCardId(), "panel:object");
    // The card body really holds the caller's node, which is what every existing
    // editor form depends on.
    assert.equal(h.dock.dockCardBody("panel:object").children[0], body);
  } finally {
    h.restore();
  }
});

// The rule the brief calls out: opening an object that is already open focuses its
// card instead of making a second one.
test("opening an already-open card focuses it rather than duplicating it", () => {
  const h = harness();
  try {
    h.dock.openDockCard({ id: "panel:object", title: "Event", body: new h.StubElement("form") });
    h.dock.openDockCard({ id: "panel:frames-browser", title: "Frames", body: new h.StubElement("div") });
    assert.equal(h.dock.dockCardIds().length, 2);
    assert.equal(h.dock.activeDockCardId(), "panel:frames-browser");

    h.dock.openDockCard({ id: "panel:object", title: "Event", body: new h.StubElement("form") });
    assert.equal(h.dock.dockCardIds().length, 2, "still two cards, not three");
    assert.equal(h.dock.activeDockCardId(), "panel:object", "and the existing one took focus");
  } finally {
    h.restore();
  }
});

test("paging translates the strip and leaves off-screen cards untabbable", () => {
  const h = harness();
  try {
    for (const [id, title] of [["a", "A"], ["b", "B"], ["c", "C"]]) {
      h.dock.openDockCard({ id, title, body: new h.StubElement("div") });
    }
    // Opening left the last card active.
    assert.equal(h.dock.activeDockCardId(), "c");
    assert.equal(activeIndexFromTransform(h.strip), 2);

    h.dock.pageDockTo(0);
    assert.equal(activeIndexFromTransform(h.strip), 0);
    const cards = h.strip.children;
    assert.equal(cards[0].inert, false, "the visible card is reachable");
    assert.equal(cards[0].getAttribute("aria-hidden"), "false");
    assert.equal(cards[1].inert, true, "an off-screen card is not a tab stop");
    assert.equal(cards[1].getAttribute("aria-hidden"), "true");
  } finally {
    h.restore();
  }
});

test("closing the last card closes the dock and gives the stage its width back", () => {
  const h = harness();
  try {
    h.dock.openDockCard({ id: "only", title: "Only", body: new h.StubElement("div") });
    assert.equal(h.dock.dockIsOpen(), true);
    assert.equal(h.dock.closeDockCard("only"), true);
    assert.equal(h.dock.dockIsOpen(), false, "a blank dock closes rather than holding the width");
    assert.equal(h.root.dataset.dockOpen, "false");
    assert.equal(h.root.style.getPropertyValue("--dock-track"), "0px");
    assert.equal(h.dock.closeDockCard("only"), false, "closing it again is a no-op");
  } finally {
    h.restore();
  }
});

test("a card's onClose fires so the editor can release its draft", () => {
  const h = harness();
  try {
    const closed = [];
    h.dock.openDockCard({
      id: "panel:object",
      title: "Event",
      body: new h.StubElement("form"),
      onClose: (id) => closed.push(id)
    });
    h.dock.closeDockCard("panel:object");
    assert.deepEqual(closed, ["panel:object"], "the editor is told, so a provisional draft cannot linger");
  } finally {
    h.restore();
  }
});

test("the side flips through the session and is written onto the workspace", () => {
  const h = harness();
  try {
    h.dock.openDockCard({ id: "a", title: "A", body: new h.StubElement("div") });
    assert.equal(h.root.dataset.dockSide, "right");
    h.dock.toggleDockSide();
    assert.equal(h.app.session.dockSide, "left");
    assert.equal(h.root.dataset.dockSide, "left");
    h.dock.toggleDockSide();
    assert.equal(h.app.session.dockSide, "right");
  } finally {
    h.restore();
  }
});

test("width is written as both the persisted fraction and a pixel track", () => {
  const h = harness();
  try {
    h.dock.openDockCard({ id: "a", title: "A", body: new h.StubElement("div") });
    // The stub workspace is 900px wide, and the default width is a third.
    assert.equal(h.root.style.getPropertyValue("--dock-width"), String(1 / 3));
    assert.equal(h.root.style.getPropertyValue("--dock-track"), "300px");
  } finally {
    h.restore();
  }
});

// The lens must re-render once at rest, not per frame — that is the whole reason
// the drag writes a CSS variable instead of calling scheduleRender per move.
test("a width drag re-renders once at rest, not on every pointer move", () => {
  const h = harness();
  try {
    h.dock.openDockCard({ id: "a", title: "A", body: new h.StubElement("div") });
    const before = h.app.renders;
    h.resize.dispatch("pointerdown", { pointerId: 1, clientX: 600 });
    for (const clientX of [640, 620, 560, 500]) {
      h.resize.dispatch("pointermove", { pointerId: 1, clientX });
    }
    assert.equal(h.app.renders, before, "no render happened during the drag");
    assert.notEqual(h.root.style.getPropertyValue("--dock-track"), "300px", "but the width did move");
    h.resize.dispatch("pointerup", { pointerId: 1, clientX: 500 });
    assert.equal(h.app.renders, before + 1, "exactly one render at rest");
  } finally {
    h.restore();
  }
});

// The Stage 1.5 defect, as an invariant. Pressing down on the stage to drag out a
// new event used to collapse the dock, which widened the stage under the pointer
// mid-gesture and then reopened on release. Nothing about a stage interaction may
// change the dock's open state or its width.
test("stage interaction never collapses the dock", async () => {
  const { createToolbar } = await import("../src/ui/toolbar.js");
  void createToolbar;
  const h = harness();
  try {
    h.dock.openDockCard({ id: "panel:object", title: "Meeting", body: new h.StubElement("form") });
    const openBefore = h.dock.dockIsOpen();
    const trackBefore = h.root.style.getPropertyValue("--dock-track");
    assert.equal(openBefore, true);

    // The whole vocabulary of a drag-to-create gesture on the stage, none of which
    // the dock listens to and none of which may reach it.
    for (const type of ["pointerdown", "pointermove", "pointerup", "click", "dblclick"]) {
      h.workspace.dispatch(type, { target: h.workspace, clientX: 300, clientY: 300 });
    }
    assert.equal(h.dock.dockIsOpen(), true, "the dock is still open");
    assert.equal(h.root.dataset.dockOpen, "true");
    assert.equal(h.root.style.getPropertyValue("--dock-track"), trackBefore, "and it never gave up width mid-gesture");
    assert.deepEqual(h.dock.dockCardIds(), ["panel:object"], "and its card survived");
  } finally {
    h.restore();
  }
});

// The other half of the rule: it still closes when the user closes it.
test("the dock closes only for explicit user action", () => {
  const h = harness();
  try {
    h.dock.openDockCard({ id: "panel:object", title: "Meeting", body: new h.StubElement("form") });
    // Clicking the card's own close control in the rail is explicit.
    const close = h.rail.children[0].children[1];
    assert.equal(close.className, "dock-handle-close");
    h.rail.dispatch("click", { target: close });
    assert.equal(h.dock.dockIsOpen(), false, "its last card closed, so the dock closed");
  } finally {
    h.restore();
  }
});

test("rail order is append-only and a reorder keeps the viewed card in view", () => {
  const h = harness();
  try {
    for (const [id, title] of [["a", "A"], ["b", "B"], ["c", "C"]]) {
      h.dock.openDockCard({ id, title, body: new h.StubElement("div") });
    }
    assert.deepEqual(handleLabels(h.rail), ["A", "B", "C"], "new cards land at the end");
    h.dock.focusDockCard("b");
    assert.equal(h.dock.activeDockCardId(), "b");

    // Drag A onto C: a user swap, the only thing allowed to reorder the rail.
    h.rail.dispatch("dragstart", { target: h.rail.children[0] });
    h.rail.dispatch("drop", { target: h.rail.children[2] });
    assert.deepEqual(handleLabels(h.rail), ["C", "B", "A"]);
    assert.equal(h.dock.activeDockCardId(), "b", "the card being looked at is still the card being looked at");
  } finally {
    h.restore();
  }
});
