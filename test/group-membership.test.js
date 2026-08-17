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
