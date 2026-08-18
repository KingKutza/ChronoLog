import assert from "node:assert/strict";
import test from "node:test";
import { PANEL_MARGIN, panelPlacement } from "../src/panel-flip.js";

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
