import assert from "node:assert/strict";
import test from "node:test";
import {
  DONE_STATE_FRAME_ID,
  OBJECT_KINDS,
  ensureStateFrame,
  isStateFrame,
  objectKindForEvent,
  traitsForObjectKind
} from "../src/object-kinds.js";
import { createStructuralDocument } from "./helpers/sample-document.js";

test("object kinds expose event, ToDo, and note authoring semantics", () => {
  assert.equal(OBJECT_KINDS.event.zeroDuration, false);
  assert.equal(OBJECT_KINDS.todo.relationRole, "observed");
  assert.equal(OBJECT_KINDS.note.zeroDuration, true);
  assert.equal(objectKindForEvent({ traits: ["event", "task"] }), "todo");
  assert.equal(objectKindForEvent({ traits: ["event", "note"] }), "note");
});

// A state frame is a group with the "state" trait on top -- both traits are
// required, so the sample fixtures' formula-state frame (traits ["state",
// "generated"], no "group") is never mistaken for one.
test("state frames are group frames with the state trait, minted once and never re-seeded", () => {
  const document = createStructuralDocument();
  const minted = ensureStateFrame(document);
  assert.equal(minted.id, DONE_STATE_FRAME_ID);
  assert.equal(minted.title, "Done");
  assert.equal(isStateFrame(minted), true);
  assert.equal(isStateFrame({ traits: ["state", "generated"] }), false, "a pattern-state frame is not a state frame");
  assert.equal(isStateFrame({ traits: ["set", "group"] }), false);
  // A retitled frame survives every later ensure untouched.
  minted.title = "Finished";
  assert.equal(ensureStateFrame(document), minted);
  assert.equal(document.frames[DONE_STATE_FRAME_ID].title, "Finished");
});

test("changing object kind preserves unrelated advanced traits", () => {
  assert.deepEqual(
    traitsForObjectKind(["event", "task", "todo", "important", "custom"], "note"),
    ["event", "note", "important", "custom"]
  );
  assert.deepEqual(traitsForObjectKind(["event", "note"], "todo"), ["event", "task", "todo"]);
});
