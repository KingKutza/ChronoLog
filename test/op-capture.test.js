// Behavioral tests proving each transaction helper emits exactly the
// record-level ops the journal needs to replay the edit -- no more, no less.
// See src/ops.js for the op shape and src/ui/transactions.js for the four
// helpers under test.
import test from "node:test";
import assert from "node:assert/strict";
import { createSampleDocument } from "./helpers/sample-document.js";
import {
  CommandHistory,
  addEvent,
  addFrame,
  addPattern,
  addRelation,
  clone,
  createId,
  stableVirtualId
} from "../src/model.js";
import { applyOps } from "../src/ops.js";
import { createTransactions } from "../src/ui/transactions.js";

// createTransactions(app) only reaches into app.chronolog and app.history, so
// no DOM is needed to exercise it.
function harness(document) {
  const changes = [];
  const app = { chronolog: document };
  app.history = new CommandHistory(document, (change) => changes.push(change));
  Object.assign(app, createTransactions(app));
  return { app, changes, last: () => changes.at(-1) };
}

function opKey(op) {
  return `${op.op} ${op.map}/${op.id}`;
}

// Order-independent by design: the transaction helpers walk RECORD_MAPS
// internally, and callers of the journal must not care about op ordering
// within a single commit.
function assertExactOps(ops, expectedKeys, message) {
  assert.equal(
    ops.length,
    expectedKeys.length,
    `${message || "op count mismatch"}: got ${JSON.stringify(ops.map(opKey))}`
  );
  assert.deepEqual(new Set(ops.map(opKey)), new Set(expectedKeys), message);
}

test("executeRecordChange creating a frame emits exactly put frames/<id>, undo deletes it, redo recreates it", () => {
  const document = createSampleDocument();
  const { app, changes } = harness(document);
  const frameId = createId("frame");

  app.executeRecordChange("Create frame", "frames", frameId, (documentValue) => {
    documentValue.frames[frameId] = { id: frameId, title: "New frame", traits: ["set"] };
  });

  const created = changes.at(-1);
  assertExactOps(created.ops, [`put frames/${frameId}`, "put meta/modified"], "create");
  const putOp = created.ops.find((op) => op.map === "frames");
  assert.deepEqual(putOp.value, document.frames[frameId]);

  assert.equal(app.history.undo(), true);
  const undone = changes.at(-1);
  assertExactOps(undone.ops, [`del frames/${frameId}`, "put meta/modified"], "undo");

  assert.equal(app.history.redo(), true);
  const redone = changes.at(-1);
  assertExactOps(redone.ops, [`put frames/${frameId}`, "put meta/modified"], "redo");
});

test("executeRecordChange editing an existing frame emits one put, and undo puts back the original record", () => {
  const document = createSampleDocument();
  const { app, changes } = harness(document);
  const frameId = "group:sample";
  const original = clone(document.frames[frameId]);

  app.executeRecordChange("Recolor group", "frames", frameId, (documentValue) => {
    documentValue.frames[frameId].color = "#112233";
  });

  const edited = changes.at(-1);
  assertExactOps(edited.ops, [`put frames/${frameId}`, "put meta/modified"], "edit");
  const editedPut = edited.ops.find((op) => op.map === "frames");
  assert.equal(editedPut.value.color, "#112233");

  assert.equal(app.history.undo(), true);
  const undone = changes.at(-1);
  assertExactOps(undone.ops, [`put frames/${frameId}`, "put meta/modified"], "undo");
  const undonePut = undone.ops.find((op) => op.map === "frames");
  assert.equal(undonePut.op, "put", "the record existed before, so undo puts it back rather than deleting it");
  assert.deepEqual(undonePut.value, original);
});

test("executeRecordChange deleting a record emits a del, and undo restores it with a put", () => {
  const document = createSampleDocument();
  const frameId = "frame:standalone";
  addFrame(document, { id: frameId, title: "Standalone", traits: ["set"] });
  const original = clone(document.frames[frameId]);
  const { app, changes } = harness(document);

  app.executeRecordChange("Delete standalone frame", "frames", frameId, (documentValue) => {
    delete documentValue.frames[frameId];
  });

  const deleted = changes.at(-1);
  assertExactOps(deleted.ops, [`del frames/${frameId}`, "put meta/modified"], "delete");

  assert.equal(app.history.undo(), true);
  const undone = changes.at(-1);
  assertExactOps(undone.ops, [`put frames/${frameId}`, "put meta/modified"], "undo");
  const undonePut = undone.ops.find((op) => op.map === "frames");
  assert.deepEqual(undonePut.value, original);
});

test("executeEventChange creating an event with a relation emits puts for both and nothing else, undo deletes both", () => {
  const document = createSampleDocument();
  const { app, changes } = harness(document);
  const eventId = createId("event");
  const relationId = createId("relation");

  app.executeEventChange("Create event", eventId, (documentValue) => {
    addEvent(documentValue, { id: eventId, traits: ["event"], payload: { title: "New event" } });
    addRelation(documentValue, {
      id: relationId,
      type: "attachment",
      event: eventId,
      frame: "calendar:personal",
      role: "placed",
      coordinate: { levels: [{ level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "15" }] }
    });
  });

  const created = changes.at(-1);
  assertExactOps(created.ops, [
    `put events/${eventId}`,
    `put relations/${relationId}`,
    "put meta/modified"
  ], "create with relation");

  assert.equal(app.history.undo(), true);
  const undone = changes.at(-1);
  assertExactOps(undone.ops, [
    `del events/${eventId}`,
    `del relations/${relationId}`,
    "put meta/modified"
  ], "undo create with relation");
});

test("executeEventChange deleting an event with relations and an override emits exactly those deletes", () => {
  const document = createSampleDocument();
  const taskId = "event:sample-task";
  const overrideId = "override:task-replaced";
  document.overrides[overrideId] = {
    id: overrideId,
    virtual: stableVirtualId("pattern:marker", "occurrence-1"),
    suppress: true,
    replacements: [taskId]
  };
  const { app, changes } = harness(document);

  app.executeEventChange("Delete task", taskId, (documentValue) => {
    delete documentValue.events[taskId];
    for (const [id, relation] of Object.entries(documentValue.relations)) {
      if (relation.event === taskId) delete documentValue.relations[id];
    }
    for (const [id, override] of Object.entries(documentValue.overrides)) {
      if (override.replacements?.includes(taskId)) delete documentValue.overrides[id];
    }
  });

  const deleted = changes.at(-1);
  assertExactOps(deleted.ops, [
    "del events/event:sample-task",
    "del relations/relation:sample-task-completed",
    `del overrides/${overrideId}`,
    "put meta/modified"
  ], "delete event with relations and override");
});

test("executeEventSetChange over two events emits puts for both and their relations, nothing for the untouched third", () => {
  const document = createSampleDocument();
  const standupId = "event:sample-standup";
  const appointmentId = "event:sample-appointment";
  const { app, changes } = harness(document);

  app.executeEventSetChange("Retitle two events", [standupId, appointmentId], (documentValue) => {
    documentValue.events[standupId].payload.title = "Standup v2";
    documentValue.events[appointmentId].payload.title = "Appointment v2";
  });

  const change = changes.at(-1);
  assertExactOps(change.ops, [
    `put events/${standupId}`,
    `put events/${appointmentId}`,
    "put relations/relation:sample-standup-placed",
    "put relations/relation:sample-appointment-placed",
    "put meta/modified"
  ], "event set change");
});

test("executeFrameChange removing a frame emits deletes for the frame plus its relations and patterns, nothing for unrelated frames", () => {
  const document = createSampleDocument();
  const targetId = "frame:test-target";
  const otherParentId = "frame:test-other-parent";
  const unrelatedId = "frame:test-unrelated";
  addFrame(document, { id: targetId, title: "Target", traits: ["set"] });
  addFrame(document, { id: otherParentId, title: "Other parent", traits: ["set"] });
  addFrame(document, { id: unrelatedId, title: "Unrelated", traits: ["set"] });
  addRelation(document, { id: "relation:test-target-link", type: "composition", parent: targetId, child: otherParentId });
  addPattern(document, { id: "pattern:test-target", language: "chronolog-formula/1", frame: targetId, appliesTo: [targetId] });
  addRelation(document, { id: "relation:test-unrelated-link", type: "composition", parent: unrelatedId, child: otherParentId });
  addPattern(document, { id: "pattern:test-unrelated", language: "chronolog-formula/1", frame: unrelatedId, appliesTo: [unrelatedId] });

  const { app, changes } = harness(document);

  app.executeFrameChange("Delete target frame", targetId, (documentValue) => {
    delete documentValue.frames[targetId];
    for (const [id, relation] of Object.entries(documentValue.relations)) {
      if (relation.frame === targetId || relation.parent === targetId || relation.child === targetId) delete documentValue.relations[id];
    }
    for (const [id, pattern] of Object.entries(documentValue.patterns)) {
      if (pattern.frame === targetId || pattern.appliesTo?.includes(targetId)) delete documentValue.patterns[id];
    }
  });

  const change = changes.at(-1);
  assertExactOps(change.ops, [
    `del frames/${targetId}`,
    "del relations/relation:test-target-link",
    "del patterns/pattern:test-target",
    "put meta/modified"
  ], "frame delete");
});

test("editing one event among many never emits ops for an unrelated event", () => {
  const document = createSampleDocument();
  const standupId = "event:sample-standup";
  const { app, changes } = harness(document);

  app.executeEventChange("Retitle standup", standupId, (documentValue) => {
    documentValue.events[standupId].payload.title = "Standup renamed";
  });

  const change = changes.at(-1);
  const eventIds = new Set(change.ops.filter((op) => op.map === "events").map((op) => op.id));
  assert.deepEqual(eventIds, new Set([standupId]), "only the edited event's id should appear");
  for (const otherId of ["event:sample-appointment", "event:sample-task"]) {
    assert.ok(!change.ops.some((op) => op.id === otherId), `${otherId} must not appear in the op list`);
  }
});

test("every committed change carries a trailing put meta/modified matching the document's meta.modified", () => {
  const document = createSampleDocument();
  const { app, changes } = harness(document);
  const frameId = createId("frame");

  app.executeRecordChange("Create frame", "frames", frameId, (documentValue) => {
    documentValue.frames[frameId] = { id: frameId, title: "New frame", traits: ["set"] };
  });

  const change = changes.at(-1);
  assert.deepEqual(change.ops.at(-1), {
    op: "put",
    map: "meta",
    id: "modified",
    value: document.meta.modified
  });
});

test("ops round-trip through applyOps: replaying them onto a pre-edit copy reproduces the edited document exactly", () => {
  // Case 1: a create.
  {
    const document = createSampleDocument();
    const before = clone(document);
    const { app, changes } = harness(document);
    const frameId = createId("frame");
    app.executeRecordChange("Create frame", "frames", frameId, (documentValue) => {
      documentValue.frames[frameId] = { id: frameId, title: "New frame", traits: ["set"] };
    });
    const copy = clone(before);
    applyOps(copy, changes.at(-1).ops);
    assert.deepEqual(copy, document, "replayed create should reproduce the document");
  }

  // Case 2: an edit of an existing record.
  {
    const document = createSampleDocument();
    const before = clone(document);
    const { app, changes } = harness(document);
    app.executeRecordChange("Recolor group", "frames", "group:sample", (documentValue) => {
      documentValue.frames["group:sample"].color = "#445566";
    });
    const copy = clone(before);
    applyOps(copy, changes.at(-1).ops);
    assert.deepEqual(copy, document, "replayed edit should reproduce the document");
  }

  // Case 3: a delete with relations and an override.
  {
    const document = createSampleDocument();
    const taskId = "event:sample-task";
    const overrideId = "override:task-replaced";
    document.overrides[overrideId] = {
      id: overrideId,
      virtual: stableVirtualId("pattern:marker", "occurrence-1"),
      suppress: true,
      replacements: [taskId]
    };
    const before = clone(document);
    const { app, changes } = harness(document);
    app.executeEventChange("Delete task", taskId, (documentValue) => {
      delete documentValue.events[taskId];
      for (const [id, relation] of Object.entries(documentValue.relations)) {
        if (relation.event === taskId) delete documentValue.relations[id];
      }
      for (const [id, override] of Object.entries(documentValue.overrides)) {
        if (override.replacements?.includes(taskId)) delete documentValue.overrides[id];
      }
    });
    const copy = clone(before);
    applyOps(copy, changes.at(-1).ops);
    assert.deepEqual(copy, document, "replayed delete-with-relations should reproduce the document");
  }
});
