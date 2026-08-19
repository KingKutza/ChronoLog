import test from "node:test";
import assert from "node:assert/strict";
import { FrameSelection } from "../src/frame-selection.js";
import { ViewSession } from "../src/session.js";
import { layeredCalendarFramesForTest } from "../src/projections.js";

// Direct unit coverage of the class session.js now delegates to. Every
// frame-selection surface (the settings-bar Frame dropdown, the Frames
// panel/dock's leading select and companion checkboxes) reads and writes
// one of these instead of parallel state.

test("a fresh selection defaults its primary to the first id given", () => {
  const selection = new FrameSelection(["calendar:personal", "calendar:work"]);
  assert.equal(selection.primary(), "calendar:personal");
  assert.deepEqual(selection.selected(), ["calendar:personal", "calendar:work"]);
  assert.ok(selection.isPrimary("calendar:personal"));
  assert.ok(!selection.isPrimary("calendar:work"));
});

test("an explicit primary argument wins over the first id, when it is a member", () => {
  const selection = new FrameSelection(["calendar:personal", "calendar:work"], "calendar:work");
  assert.equal(selection.primary(), "calendar:work");
  assert.deepEqual(selection.selected(), ["calendar:work", "calendar:personal"], "primary sorts first");
});

test("a primary argument that is not a member of the ids is ignored", () => {
  const selection = new FrameSelection(["calendar:personal"], "calendar:nowhere");
  assert.equal(selection.primary(), "calendar:personal");
});

test("toggle adds an unselected id and removes a selected one", () => {
  const selection = new FrameSelection(["calendar:personal"]);
  selection.toggle("calendar:work");
  assert.ok(selection.isSelected("calendar:work"));
  assert.equal(selection.primary(), "calendar:personal", "adding a companion never moves the primary");
  selection.toggle("calendar:work");
  assert.ok(!selection.isSelected("calendar:work"));
});

test("toggle refuses to remove the last remaining id", () => {
  const selection = new FrameSelection(["calendar:personal"]);
  selection.toggle("calendar:personal");
  assert.deepEqual(selection.selected(), ["calendar:personal"]);
});

test("toggling the primary out promotes the next selected id, never leaving the selection empty", () => {
  const selection = new FrameSelection(["calendar:a", "calendar:b", "calendar:c"]);
  selection.toggle("calendar:a");
  assert.equal(selection.primary(), "calendar:b", "the id that followed the removed primary is promoted");
  assert.deepEqual(new Set(selection.selected()), new Set(["calendar:b", "calendar:c"]));
});

test("toggling out the last-positioned primary wraps to the new first id", () => {
  const selection = new FrameSelection(["calendar:a", "calendar:b"], "calendar:b");
  selection.toggle("calendar:b");
  assert.equal(selection.primary(), "calendar:a");
});

test("setPrimary reassigns the marker without changing membership — the 8.19 regression, at the class level", () => {
  const selection = new FrameSelection(["calendar:personal", "calendar:work", "calendar:family"]);
  selection.setPrimary("calendar:family");
  assert.equal(selection.primary(), "calendar:family");
  assert.deepEqual(new Set(selection.selected()), new Set(["calendar:personal", "calendar:work", "calendar:family"]),
    "reassigning the primary must not drop any previously selected frame");
});

test("setPrimary on an id outside the selection adds it rather than replacing the selection", () => {
  const selection = new FrameSelection(["calendar:personal"]);
  selection.setPrimary("calendar:work");
  assert.equal(selection.primary(), "calendar:work");
  assert.ok(selection.isSelected("calendar:personal"), "the previous primary is demoted, not dropped");
});

test("setSelection bulk-replaces, keeping the previous primary when it survives", () => {
  const selection = new FrameSelection(["calendar:personal"]);
  selection.setSelection(["calendar:work", "calendar:personal", "calendar:family"]);
  assert.equal(selection.primary(), "calendar:personal");
  selection.setSelection(["calendar:work", "calendar:family"]);
  assert.equal(selection.primary(), "calendar:work", "the previous primary dropped out, so the first offered id leads");
});

test("setSelection refuses an empty list", () => {
  const selection = new FrameSelection(["calendar:personal"]);
  selection.setSelection([]);
  assert.deepEqual(selection.selected(), ["calendar:personal"]);
});

test("prune drops ids that no longer exist and reassigns a stale primary", () => {
  const selection = new FrameSelection(["calendar:personal", "calendar:work", "calendar:family"]);
  selection.prune(["calendar:work", "calendar:family"]);
  assert.equal(selection.primary(), "calendar:work");
  assert.deepEqual(new Set(selection.selected()), new Set(["calendar:work", "calendar:family"]));
});

test("prune falls back to an arbitrary valid id when nothing of the old selection survives", () => {
  const selection = new FrameSelection(["calendar:personal"]);
  selection.prune(["calendar:work", "calendar:family"]);
  assert.equal(selection.primary(), "calendar:work");
});

test("prune against an empty valid set leaves the selection untouched", () => {
  const selection = new FrameSelection(["calendar:personal"]);
  selection.prune([]);
  assert.deepEqual(selection.selected(), ["calendar:personal"], "no frames loaded yet is not proof the selection is wrong");
});

// The actual regression, at the render boundary: layeredCalendarFrames used
// to read only frames[leading].display.overlays, so checking a companion in
// the toolbar's Frame dropdown or the Frames panel wrote session state the
// renderer never consumed — "the highest frame selected acts as the view
// frame, lower selected frames do not overlay." This test fails against the
// pre-fix implementation and passes now that the projection reads the one
// selection.
test("every selected frame overlays in the calendar projection, primary first", () => {
  const document = {
    frames: {
      "calendar:personal": { id: "calendar:personal", title: "Personal", traits: ["calendar"] },
      "calendar:work": { id: "calendar:work", title: "Work", traits: ["calendar"] },
      "calendar:family": { id: "calendar:family", title: "Family", traits: ["calendar"] }
    }
  };
  const session = new ViewSession({ activeFrame: "calendar:personal" });
  session.setFrameSelection(["calendar:personal", "calendar:work", "calendar:family"]);
  const layered = layeredCalendarFramesForTest({ document, session }, session.activeFrame);
  assert.deepEqual(layered.map((frame) => frame.id), ["calendar:personal", "calendar:work", "calendar:family"]);
});

test("display.overlays plays no role in the projection any more", () => {
  const document = {
    frames: {
      "calendar:personal": { id: "calendar:personal", title: "Personal", traits: ["calendar"], display: { overlays: ["calendar:family"] } },
      "calendar:family": { id: "calendar:family", title: "Family", traits: ["calendar"] }
    }
  };
  const session = new ViewSession({ activeFrame: "calendar:personal" });
  const layered = layeredCalendarFramesForTest({ document, session }, session.activeFrame);
  assert.deepEqual(layered.map((frame) => frame.id), ["calendar:personal"],
    "a stale display.overlays entry that was never selected must not appear");
});

test("requesting a non-primary frame explicitly renders it alone", () => {
  const document = {
    frames: {
      "calendar:personal": { id: "calendar:personal", title: "Personal", traits: ["calendar"] },
      "calendar:work": { id: "calendar:work", title: "Work", traits: ["calendar"] }
    }
  };
  const session = new ViewSession({ activeFrame: "calendar:personal" });
  session.setFrameSelection(["calendar:personal", "calendar:work"]);
  const layered = layeredCalendarFramesForTest({ document, session }, "calendar:work");
  assert.deepEqual(layered.map((frame) => frame.id), ["calendar:work"]);
});
