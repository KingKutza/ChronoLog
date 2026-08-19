import assert from "node:assert/strict";
import test from "node:test";
import { PANEL_MARGIN, createDropdownRegistry, exclusiveOpenSet, outsideInteractionCloses, panelPlacement, wrapFocusIndex } from "../src/panel-flip.js";

const VIEWPORT = { width: 1400, height: 900 };

function anchor(left, top, width = 70, height = 32) {
  return { left, top, width, height };
}

test("a panel opens in the reading direction when there is room", () => {
  const placement = panelPlacement({
    anchor: anchor(200, 120),
    panel: { width: 300, height: 240 },
    viewport: VIEWPORT
  });
  assert.equal(placement.align, "start", "its start edge sits on the anchor's start edge");
  assert.equal(placement.left, 200);
  assert.equal(placement.placement, "below");
  assert.ok(placement.top > 120, "and it hangs below the anchor");
});

// The reported bug: the lens Options panel was pinned to open leftward, so from a
// button near the left edge it ran off the window. Flipping is chosen by the room
// available, so the same panel now opens whichever way fits.
test("a panel near the right edge flips to its other edge instead of overflowing", () => {
  const placement = panelPlacement({
    anchor: anchor(1290, 120),
    panel: { width: 300, height: 240 },
    viewport: VIEWPORT
  });
  assert.equal(placement.align, "end");
  assert.equal(placement.left, 1290 + 70 - 300, "the panel's end edge meets the anchor's end edge");
  assert.ok(placement.left + 300 <= VIEWPORT.width - PANEL_MARGIN, "and it stays inside the window");
});

test("a panel near the left edge does not flip off the left instead", () => {
  // This is the Tactical case: a narrow anchor close to the left edge. Opening
  // leftward would put the panel at a negative coordinate.
  const placement = panelPlacement({
    anchor: anchor(24, 140),
    panel: { width: 300, height: 240 },
    viewport: VIEWPORT
  });
  assert.equal(placement.left, 24, "it opens rightward, which is where the room is");
  assert.ok(placement.left >= PANEL_MARGIN);
});

test("a panel too wide to fit either way is clamped inside the window, not hidden", () => {
  const placement = panelPlacement({
    anchor: anchor(700, 140),
    panel: { width: 420, height: 200 },
    viewport: { width: 380, height: 900 }
  });
  assert.equal(placement.align, "clamped");
  assert.equal(placement.left, PANEL_MARGIN, "its start stays visible so its content is reachable");
});

test("a panel with no room below flips above its anchor", () => {
  const placement = panelPlacement({
    anchor: anchor(200, 820),
    panel: { width: 300, height: 400 },
    viewport: VIEWPORT
  });
  assert.equal(placement.placement, "above");
  assert.ok(placement.top < 820, "it sits above the anchor");
  assert.ok(placement.top >= PANEL_MARGIN);
});

test("a panel with no room on either side is clamped vertically rather than flipped off-screen", () => {
  const placement = panelPlacement({
    anchor: anchor(200, 300),
    panel: { width: 300, height: 880 },
    viewport: { width: 1400, height: 500 }
  });
  assert.match(placement.placement, /clamped$/);
  assert.equal(placement.top, PANEL_MARGIN);
});

test("placement reads an anchor given as edges or as a size", () => {
  const fromSize = panelPlacement({
    anchor: { left: 100, top: 50, width: 80, height: 30 },
    panel: { width: 200, height: 100 },
    viewport: VIEWPORT
  });
  const fromEdges = panelPlacement({
    anchor: { left: 100, top: 50, right: 180, bottom: 80 },
    panel: { width: 200, height: 100 },
    viewport: VIEWPORT
  });
  assert.deepEqual(fromSize, fromEdges, "a DOMRect and a plain edge object agree");
});

test("garbage measurements degrade to the window's own corner", () => {
  const placement = panelPlacement({});
  assert.equal(placement.left, PANEL_MARGIN);
  assert.equal(placement.top, PANEL_MARGIN);
});

// The registry is the "class, not the instance" half of the fix: a UI module
// enumerates it to place and z-level every bar dropdown uniformly, instead of
// hand-listing container ids (the bug's actual cause — #hidden-lenses was
// simply absent from that list). The registry itself is opaque to DOM: it
// only has to remember what is enrolled.
test("a dropdown registry enrolls, enumerates, and forgets attachment points", () => {
  const registry = createDropdownRegistry();
  assert.deepEqual(registry.ids(), [], "nothing registered yet");
  registry.register("create-menu", { note: "a" });
  registry.register("hidden-lenses", { note: "b" });
  assert.deepEqual(registry.ids().sort(), ["create-menu", "hidden-lenses"]);
  assert.deepEqual(registry.values().map((entry) => entry.note).sort(), ["a", "b"]);
  assert.equal(registry.has("create-menu"), true);
  assert.equal(registry.get("hidden-lenses").note, "b");
  registry.unregister("create-menu");
  assert.equal(registry.has("create-menu"), false);
  assert.deepEqual(registry.ids(), ["hidden-lenses"]);
});

test("re-registering an id replaces its entry rather than accumulating", () => {
  const registry = createDropdownRegistry();
  registry.register("lens-control-overflow", { generation: 1 });
  registry.register("lens-control-overflow", { generation: 2 });
  assert.deepEqual(registry.ids(), ["lens-control-overflow"], "still one entry, not two");
  assert.equal(registry.get("lens-control-overflow").generation, 2, "the newest wins");
});

// The full bar-dropdown contract (8.19 field report Stage A item 1) widens
// the class past placement/z-level to close-on-outside-interaction, Escape,
// mutual exclusion and keyboard focus. The decidable part of each of those
// rules is a pure function here; toolbar.js only measures/observes DOM state
// and applies the answer.

test("exclusiveOpenSet keeps the just-opened dropdown and names every other open one to close", () => {
  assert.deepEqual(exclusiveOpenSet(["create-menu"], "create-menu"), [], "opening the only open dropdown closes nothing");
  assert.deepEqual(exclusiveOpenSet(["create-menu", "document-menu"], "document-menu"), ["create-menu"]);
  assert.deepEqual(
    exclusiveOpenSet(["create-menu", "document-menu", "hidden-lenses"], "hidden-lenses").sort(),
    ["create-menu", "document-menu"],
    "every other open dropdown closes, not just one hand-paired sibling"
  );
  assert.deepEqual(exclusiveOpenSet([], "create-menu"), [], "nothing else was open");
});

test("outsideInteractionCloses closes every open dropdown a press did not hit, and only those", () => {
  assert.deepEqual(
    outsideInteractionCloses([
      { id: "create-menu", open: true, hit: false },
      { id: "document-menu", open: false, hit: false },
      { id: "hidden-lenses", open: true, hit: true }
    ]),
    ["create-menu"],
    "a closed dropdown never needs closing, and a hit dropdown (container OR its portaled panel) stays open"
  );
  assert.deepEqual(outsideInteractionCloses([]), []);
  assert.deepEqual(
    outsideInteractionCloses([{ id: "create-menu", open: true, hit: true }]),
    [],
    "a press on the dropdown's own portaled panel is not \"outside\" it — this is the create-menu regression the class exists to close off generically"
  );
});

test("wrapFocusIndex cycles forward and backward with wraparound at both ends", () => {
  assert.equal(wrapFocusIndex(0, 1, 3), 1);
  assert.equal(wrapFocusIndex(1, 1, 3), 2);
  assert.equal(wrapFocusIndex(2, 1, 3), 0, "Tab from the last control wraps to the first");
  assert.equal(wrapFocusIndex(0, -1, 3), 2, "Shift+Tab from the first control wraps to the last");
  assert.equal(wrapFocusIndex(1, -1, 3), 0);
  assert.equal(wrapFocusIndex(0, 1, 1), 0, "a single-control panel loops onto itself rather than throwing");
  assert.equal(wrapFocusIndex(0, 1, 0), -1, "an empty panel has nowhere to send focus");
});
