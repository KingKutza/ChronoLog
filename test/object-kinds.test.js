import assert from "node:assert/strict";
import test from "node:test";
import { OBJECT_KINDS, objectKindForEvent, traitsForObjectKind } from "../src/object-kinds.js";

test("object kinds expose event, ToDo, and note authoring semantics", () => {
  assert.equal(OBJECT_KINDS.event.zeroDuration, false);
  assert.equal(OBJECT_KINDS.todo.relationRole, "observed");
  assert.equal(OBJECT_KINDS.note.zeroDuration, true);
  assert.equal(objectKindForEvent({ traits: ["event", "task"] }), "todo");
  assert.equal(objectKindForEvent({ traits: ["event", "note"] }), "note");
});

test("changing object kind preserves unrelated advanced traits", () => {
  assert.deepEqual(
    traitsForObjectKind(["event", "task", "todo", "important", "custom"], "note"),
    ["event", "note", "important", "custom"]
  );
  assert.deepEqual(traitsForObjectKind(["event", "note"], "todo"), ["event", "task", "todo"]);
});
