import test from "node:test";
import assert from "node:assert/strict";
import { createStructuralDocument } from "./helpers/sample-document.js";
import { ChronologEngine } from "../src/engine.js";
import { addEvent, addFrame, addRelation, durationMagnitude, validateDocument } from "../src/model.js";

function group(document, id, query) {
  return addFrame(document, { id, title: id, traits: ["set", "group"], query });
}
function event(document, id, traits = ["event"]) {
  return addEvent(document, { id, traits, magnitudes: { duration: durationMagnitude("0") }, payload: { title: id } });
}
function member(document, id, groupId, memberId) {
  return addRelation(document, { id, type: "membership", group: groupId, member: memberId });
}
function attach(document, id, frameId, eventId) {
  return addRelation(document, { id, type: "attachment", event: eventId, frame: frameId, role: "member" });
}

test("group membership preserves authored, query, and union provenance", () => {
  const document = createStructuralDocument();
  const authored = event(document, "event:authored", ["event", "personal"]);
  const queried = event(document, "event:queried", ["event", "work"]);
  const both = event(document, "event:both", ["event", "work"]);
  const work = group(document, "group:work", { traitsAll: ["work"] });
  member(document, "membership:authored", work.id, authored.id);
  member(document, "membership:both", work.id, both.id);
  const engine = new ChronologEngine(document);
  const reasons = Object.fromEntries(engine.groupMembers(work.id).map((item) => [item.member, item.provenance.map((p) => p.kind).sort()]));
  assert.deepEqual(reasons[authored.id], ["authored"]);
  assert.deepEqual(reasons[queried.id], ["query"]);
  assert.deepEqual(reasons[both.id], ["authored", "query"]);
  assert.equal(engine.eventGroupFrame(both.id), work.id);
});

test("positive nested, self, mutual, and deeper group cycles terminate at the least fixed point", () => {
  const document = createStructuralDocument();
  const leaf = event(document, "event:leaf");
  const a = group(document, "group:a");
  const b = group(document, "group:b");
  const c = group(document, "group:c");
  member(document, "membership:a-leaf", a.id, leaf.id);
  member(document, "membership:a-self", a.id, a.id);
  member(document, "membership:b-a", b.id, a.id);
  member(document, "membership:c-b", c.id, b.id);
  member(document, "membership:a-c", a.id, c.id);
  const engine = new ChronologEngine(document);
  for (const id of [a.id, b.id, c.id]) assert.ok(engine.groupMembers(id).some((item) => item.member === leaf.id));
  assert.ok(engine.eventGroupMemberships(leaf.id).every((item) => [a.id, b.id, c.id].includes(item.group)));
  assert.equal(validateDocument(document).valid, true);
});

// Stage D (ROADMAP #9's display-only half): an importance frame is authored
// exactly like a group (attach an event to it the same way), but
// `isOrdinaryGroup` deliberately excludes it so persisted authoring/
// validation semantics never see the union. `isDisplayGroup` and its
// `eventDisplayGroupMemberships`/`displayGroupEventMembers` companions are
// the ONLY things that see it -- this pins that split.
test("isDisplayGroup unions importance frames into display membership without touching the persisted group index", () => {
  const document = createStructuralDocument();
  const plain = event(document, "event:plain");
  const importanceFrame = addFrame(document, {
    id: "frame:important", title: "Important", traits: ["set", "group", "importance"], color: "#663399"
  });
  attach(document, "attachment:plain", importanceFrame.id, plain.id);
  const engine = new ChronologEngine(document);

  // Persisted-facing: isOrdinaryGroup and everything built from it stay blind
  // to the importance frame, exactly as before this stage.
  assert.equal(engine.isOrdinaryGroup(importanceFrame.id), false);
  assert.equal(engine.eventGroupFrame(plain.id), null);
  assert.deepEqual(engine.eventGroupMemberships(plain.id), []);
  assert.deepEqual(engine.groupEventMembers(importanceFrame.id), []);

  // Display-facing: the union sees it.
  assert.equal(engine.isDisplayGroup(importanceFrame.id), true);
  assert.equal(engine.eventDisplayGroupFrame(plain.id), importanceFrame.id);
  assert.deepEqual(
    engine.eventDisplayGroupMemberships(plain.id).map((item) => item.group),
    [importanceFrame.id]
  );
  assert.deepEqual(engine.displayGroupEventMembers(importanceFrame.id), [plain.id]);
});

// The exact field-report symptom: converting a group's kind to importance is
// additive (frame-edit.js keeps the "group" trait), so the persisted
// attachment relation never changes -- only engine-side display bookkeeping
// used to drop it.
test("a group that gains the importance trait keeps its display membership (the field-report regression)", () => {
  const document = createStructuralDocument();
  const member1 = event(document, "event:member");
  const plainGroup = addFrame(document, { id: "frame:was-plain", title: "Was plain", traits: ["set", "group"], color: "#2e8b57" });
  attach(document, "attachment:member", plainGroup.id, member1.id);
  const engine = new ChronologEngine(document);
  assert.deepEqual(engine.displayGroupEventMembers(plainGroup.id), [member1.id]);
  assert.deepEqual(engine.groupEventMembers(plainGroup.id), [member1.id]);

  // Additive kind-switching: "importance" is added, "group" stays.
  document.frames[plainGroup.id].traits = ["set", "group", "importance"];
  engine.refreshFrame(plainGroup.id);

  assert.deepEqual(engine.groupEventMembers(plainGroup.id), [], "persisted-facing group index excludes it now, by design");
  assert.deepEqual(
    engine.displayGroupEventMembers(plainGroup.id),
    [member1.id],
    "display-facing index still has it -- this is what keeps it coloring its events"
  );
});

// This stage is display-only: no accessor added here may mutate the document,
// and validation must not change its mind about an importance frame just
// because display bookkeeping now looks at it differently.
test("the display-side unification changes no persisted document shape", () => {
  const document = createStructuralDocument();
  const member1 = event(document, "event:member");
  const importanceFrame = addFrame(document, {
    id: "frame:important2", title: "Important", traits: ["set", "group", "importance"]
  });
  attach(document, "attachment:member2", importanceFrame.id, member1.id);
  const before = structuredClone(document);
  const engine = new ChronologEngine(document);
  engine.isDisplayGroup(importanceFrame.id);
  engine.eventDisplayGroupMemberships(member1.id);
  engine.displayGroupEventMembers(importanceFrame.id);
  engine.eventDisplayGroupFrame(member1.id);
  assert.deepEqual(document, before, "reading the display-group accessors must not mutate the document");
  assert.equal(validateDocument(document).valid, true);
});

test("recursive negation is rejected instead of receiving order-dependent semantics", () => {
  const document = createStructuralDocument();
  const a = group(document, "group:a", { excludeGroups: ["group:b"] });
  const b = group(document, "group:b");
  member(document, "membership:b-a", b.id, a.id);
  member(document, "membership:nope", a.id, b.id);
  document.relations["membership:nope"].include = false;
  const errors = validateDocument(document).errors.join("\n");
  assert.match(errors, /recursive negation/);
  assert.match(errors, /negative group membership/);
  assert.equal(new ChronologEngine(document).groupMembers(a.id).length, 0);
});
