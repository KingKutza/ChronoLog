import assert from "node:assert/strict";
import test from "node:test";
import { CommandHistory, addFrame, createId } from "../src/model.js";
import { createTransactions } from "../src/ui/transactions.js";
import { createStructuralDocument } from "./helpers/sample-document.js";

// Owner item 3, "New Lacks a New Frame Option". The New menu's "Frame" entry
// (test/toolbar-dropdowns.test.js pins the menu wiring) hands off to
// src/ui/frames-panel.js's `createFrame`:
//
//   function createFrame() {
//     const frameId = createId("frame");
//     app.executeRecordChange("Create frame", "frames", frameId, (documentValue) => {
//       addFrame(documentValue, { id: frameId, title: "New frame" });
//     });
//     openFrameInspector(frameId);
//   }
//
// This test drives that same transaction body directly against the real
// `executeRecordChange` (transactions.js) and `addFrame` (model.js) rather
// than constructing `createFramesPanel` and clicking through it, for the same
// reason test/series-edit-flow.test.js drives the transaction layer instead
// of the DOM for materialization: `createFrame`'s follow-up,
// `openFrameInspector`, immediately opens the just-created frame in
// frames-panel.js's `frameForm`, an editing surface built with `innerHTML`
// and (for an existing record) unconditional `wrapper.querySelector(
// "#duplicate-object"/"#delete-object")` lookups — the repo's stub-DOM
// harness does not parse `innerHTML` into a real tree, so it cannot satisfy
// those lookups. The document contract this item is actually about — one
// undoable, journaled transaction that adds a plain frame record and nothing
// else — is fully exercised without a DOM at all.
function appFor(chronolog) {
  const changes = [];
  const app = { chronolog, history: new CommandHistory(chronolog, (change) => changes.push(change)) };
  Object.assign(app, createTransactions(app));
  return { app, changes };
}

test("creating a frame from the New menu's path adds one plain frame record via a single undoable, journaled transaction", () => {
  const chronolog = createStructuralDocument();
  const before = Object.keys(chronolog.frames).sort();
  const { app, changes } = appFor(chronolog);

  const frameId = createId("frame");
  app.executeRecordChange("Create frame", "frames", frameId, (documentValue) => {
    addFrame(documentValue, { id: frameId, title: "New frame" });
  });

  // Exactly one new record, nothing else touched.
  const after = Object.keys(chronolog.frames).sort();
  assert.deepEqual(after.filter((id) => !before.includes(id)), [frameId], "exactly one frame record was added");
  const frame = chronolog.frames[frameId];
  assert.equal(frame.title, "New frame", "a plain default title, not inferred from context");
  // `addFrame`'s own default, not anything guessed by the New-menu path —
  // meaning is authored later, in the frame's own editing form.
  assert.deepEqual(frame.traits, ["set"], "no kind or capability is guessed on the user's behalf");

  // One undo entry, and it actually undoes: the created frame is the only
  // thing that disappears.
  assert.equal(app.history.undoStack.length, 1);
  assert.equal(app.history.undoStack[0].label, "Create frame");
  assert.equal(app.history.undo(), true);
  assert.deepEqual(Object.keys(chronolog.frames).sort(), before, "undo removes exactly the created frame");

  // Redo restores it, still as the one record.
  assert.equal(app.history.redo(), true);
  assert.deepEqual(chronolog.frames[frameId], frame, "redo restores the same frame record");

  // The transaction journals: one change emitted per commit (create, undo,
  // redo), each carrying a "frames" op naming the record it affects.
  assert.equal(changes.length, 3, "create, undo, and redo each emit one journal-bound change");
  for (const change of changes) {
    assert.ok(change.ops.some((op) => op.map === "frames" && op.id === frameId), `${change.label} carries a "frames" op for the created record`);
  }
});
