// Containment without judgment: `{type: "contains", parent, child}` between
// event ids, multi-parent, any depth, no stored rank, and NO cycle refusal in
// validation -- the system passes no judgment on family-tree shape, so the
// derivations over it must survive whatever it admits: visit-set guards,
// report, never throw, never loop forever.
import assert from "node:assert/strict";
import test from "node:test";
import { ChronologEngine } from "../src/engine.js";
import { CommandHistory, addEvent, addRelation, durationMagnitude, validateDocument } from "../src/model.js";
import { DONE_STATE_FRAME_ID, containsSummary } from "../src/object-kinds.js";
import { ViewSession } from "../src/session.js";
import { createTransactions } from "../src/ui/transactions.js";
import { createStructuralDocument } from "./helpers/sample-document.js";

function baseDocument() {
  const document = createStructuralDocument();
  document.frames["calendar:personal"] = {
    id: "calendar:personal",
    title: "Personal",
    traits: ["set", "calendar"],
    basis: "frame:wall-time"
  };
  return document;
}

function object(document, id, title = id) {
  return addEvent(document, {
    id,
    traits: ["event", "task", "todo"],
    magnitudes: { duration: durationMagnitude("0") },
    payload: { title }
  });
}

function contains(document, parent, child, id = `contains:${parent}>${child}`) {
  return addRelation(document, { id, type: "contains", parent, child });
}

function markDone(document, memberId) {
  document.frames[DONE_STATE_FRAME_ID] ||= {
    id: DONE_STATE_FRAME_ID, title: "Done", traits: ["set", "group", "state"]
  };
  addRelation(document, { type: "membership", group: DONE_STATE_FRAME_ID, member: memberId });
}

test("validation refuses only self-containment and dangling ids -- never shape", () => {
  const document = baseDocument();
  object(document, "event:project");
  object(document, "event:step");
  object(document, "event:other");
  contains(document, "event:project", "event:step");
  // Multi-parent: the same child under a second parent is legal.
  contains(document, "event:other", "event:step");
  // A cycle is legal DATA -- derivations guard themselves.
  contains(document, "event:step", "event:project");
  assert.deepEqual(validateDocument(document).errors, [], "multi-parent and cyclic shapes pass");

  contains(document, "event:project", "event:project", "contains:self");
  contains(document, "event:project", "event:nowhere", "contains:dangling-child");
  contains(document, "event:nowhere", "event:step", "contains:dangling-parent");
  const errors = validateDocument(document).errors.join("\n");
  assert.match(errors, /contain itself/);
  assert.match(errors, /missing child/);
  assert.match(errors, /missing parent/);
});

test("the engine indexes containment from both ends, deterministically", () => {
  const document = baseDocument();
  object(document, "event:project");
  object(document, "event:b");
  object(document, "event:a");
  contains(document, "event:project", "event:b");
  contains(document, "event:project", "event:a");
  const engine = new ChronologEngine(document);
  assert.deepEqual(engine.containsByParent.get("event:project"), ["event:a", "event:b"]);
  assert.deepEqual(engine.parentsByChild.get("event:a"), ["event:project"]);
});

test("containsSummary reports direct, total, open, and done across depth and shared children", () => {
  const document = baseDocument();
  object(document, "event:project");
  object(document, "event:phase-1");
  object(document, "event:phase-2");
  object(document, "event:shared-step");
  object(document, "event:own-step");
  contains(document, "event:project", "event:phase-1");
  contains(document, "event:project", "event:phase-2");
  contains(document, "event:phase-1", "event:shared-step");
  // A diamond: the same step under both phases counts ONCE -- multi-parent is
  // not a cycle and not a double.
  contains(document, "event:phase-2", "event:shared-step");
  contains(document, "event:phase-2", "event:own-step");
  markDone(document, "event:shared-step");
  markDone(document, "event:phase-1");
  const engine = new ChronologEngine(document);
  const summary = containsSummary(document, engine, "event:project");
  assert.deepEqual(summary, { direct: 2, total: 4, open: 2, done: 2, cyclic: false });
  // Memoized per engine generation: the same object comes back as the same answer.
  assert.equal(containsSummary(document, engine, "event:project"), summary);
});

test("a deliberately cyclic document summarizes without hanging or throwing, and says so", () => {
  const document = baseDocument();
  object(document, "event:a");
  object(document, "event:b");
  object(document, "event:c");
  contains(document, "event:a", "event:b");
  contains(document, "event:b", "event:c");
  contains(document, "event:c", "event:a");
  markDone(document, "event:c");
  const engine = new ChronologEngine(document);
  const summary = containsSummary(document, engine, "event:a");
  assert.equal(summary.cyclic, true, "the loop is reported, not refused and not looped over");
  assert.equal(summary.direct, 1);
  assert.equal(summary.total, 2, "each object in the loop counts once, and never itself");
  assert.equal(summary.done, 1);
  assert.equal(summary.open, 1);
});

test("overscale smoke: a few hundred parents over a shared child stay exact and fast", () => {
  const document = baseDocument();
  object(document, "event:root");
  object(document, "event:leaf");
  markDone(document, "event:leaf");
  for (let index = 0; index < 300; index += 1) {
    const id = `event:parent-${String(index).padStart(3, "0")}`;
    object(document, id);
    contains(document, "event:root", id);
    contains(document, id, "event:leaf");
  }
  assert.deepEqual(validateDocument(document).errors, []);
  const engine = new ChronologEngine(document);
  const root = containsSummary(document, engine, "event:root");
  assert.deepEqual(root, { direct: 300, total: 301, open: 300, done: 1, cyclic: false });
  const leafParents = engine.parentsByChild.get("event:leaf");
  assert.equal(leafParents.length, 300, "multi-parent at scale is just data");
});

// A list/project is a container OBJECT: no list machinery, and deleting one is
// the same event deletion as any other -- the containment edges at BOTH ends
// travel in the same undoable transaction, and undo restores them exactly.
test("deleting an object cascades its containment edges both ways, and undo restores them", () => {
  const document = baseDocument();
  object(document, "event:project");
  object(document, "event:step");
  object(document, "event:substep");
  contains(document, "event:project", "event:step");
  contains(document, "event:step", "event:substep");

  const changes = [];
  const app = { chronolog: document, session: new ViewSession({ activeFrame: "calendar:personal" }) };
  app.history = new CommandHistory(document, (change) => changes.push(change));
  Object.assign(app, createTransactions(app));

  app.executeEventChange("Delete step", "event:step", (documentValue) => {
    delete documentValue.events["event:step"];
  });
  assert.equal(document.relations["contains:event:project>event:step"], undefined, "the child-end edge went with it");
  assert.equal(document.relations["contains:event:step>event:substep"], undefined, "the parent-end edge went with it");
  assert.deepEqual(validateDocument(document).errors, [], "no dangling containment survives the delete");
  const ops = new Set(changes.at(-1).ops.map((op) => `${op.op} ${op.map}/${op.id}`));
  assert.ok(ops.has("del relations/contains:event:project>event:step"));
  assert.ok(ops.has("del relations/contains:event:step>event:substep"));

  assert.equal(app.history.undo(), true);
  assert.ok(document.events["event:step"], "undo restores the object");
  assert.ok(document.relations["contains:event:project>event:step"], "and its child-end edge");
  assert.ok(document.relations["contains:event:step>event:substep"], "and its parent-end edge");
  assert.deepEqual(validateDocument(document).errors, []);
});
