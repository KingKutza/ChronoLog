import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { clone, renderTerminatorState, validateDocument } from "../src/model.js";

const fixturePath = fileURLToPath(new URL("../fixtures/time-travel-taxonomy.chronolog.json", import.meta.url));
const fixture = JSON.parse(await readFile(fixturePath, "utf8"));

test("time-travel taxonomy fixture is structurally valid and uses stable IDs", () => {
  assert.equal(validateDocument(fixture).valid, true, validateDocument(fixture).errors.join("\n"));
  assert.equal(fixture.events["event:fork"].id, "event:fork");
  assert.equal(fixture.relations["displacement:backward-earth"].id, "displacement:backward-earth");
});

test("fixture preserves multi-line and repeated same-line event incidence", () => {
  const relations = Object.values(fixture.relations).filter((relation) => relation.type === "attachment");
  const forkLines = relations.filter((relation) => relation.event === "event:fork").map((relation) => relation.frame);
  assert.deepEqual(new Set(forkLines), new Set(["line:earth", "line:fork"]));
  const repeats = relations.filter((relation) => relation.event === "event:repeated-incidence");
  assert.deepEqual(repeats.map((relation) => relation.frame), ["line:earth", "line:earth"]);
  assert.notDeepEqual(repeats[0].coordinate, repeats[1].coordinate);
});

test("fixture represents shared segments, fork terminators, and a closed loop without line branching", () => {
  const shared = fixture.relations["segment:earth-traveler-shared"];
  assert.deepEqual(shared.lines, ["line:earth", "line:traveler"]);
  assert.equal(fixture.relations[shared.anchors["line:earth"].start].event, "event:shared-start");
  assert.equal(fixture.relations[shared.anchors["line:traveler"].end].event, "event:shared-end");
  assert.equal(fixture.relations["termination:fork-start"].state, "stapled");
  assert.equal(fixture.relations["termination:loop-start"].state, "stapled");
  assert.equal(fixture.relations["termination:loop-end"].state, "stapled");
  assert.equal(Object.values(fixture.relations).some((relation) => relation.type === "composition"), false);
});

test("fixture keeps reverse world displacement separate from forward traveler proper time", () => {
  const jump = fixture.relations["displacement:backward-earth"];
  assert.equal(jump.properDirection, "forward");
  assert.equal(jump.worldDirection, "reverse");
  assert.equal(fixture.relations[jump.origin.traveler].frame, "line:traveler");
  assert.equal(fixture.relations[jump.destination.world].frame, "line:earth");
  assert.equal(fixture.relations[jump.origin.world].coordinate.levels[0].value, "1985");
  assert.equal(fixture.relations[jump.destination.world].coordinate.levels[0].value, "1955");
});

test("Groundhog replication, sealed ends, and projection-open edges remain distinct", () => {
  const pattern = fixture.patterns["pattern:groundhog-loop-days"];
  assert.deepEqual(pattern.copies, ["line:loop-day-1", "line:loop-day-2"]);
  assert.equal(fixture.relations["termination:sealed-fork"].state, "sealed");
  assert.equal(renderTerminatorState(fixture, "line:fork", "attachment:sealed-fork"), "sealed");
  assert.equal(renderTerminatorState(fixture, "line:loop-day-1", "attachment:groundhog-end-day-1"), "open");
});

test("topology validation rejects broken anchors, false stapling, and backward proper time", () => {
  const brokenShared = clone(fixture);
  brokenShared.relations["segment:earth-traveler-shared"].anchors["line:traveler"].end = "attachment:shared-end-earth";
  assert.match(validateDocument(brokenShared).errors.join("\n"), /no end anchor on line:traveler/);

  const falseStaple = clone(fixture);
  falseStaple.relations["termination:fork-start"].terminator = "attachment:sealed-fork";
  assert.match(validateDocument(falseStaple).errors.join("\n"), /must attach to another line/);

  const backwardTraveler = clone(fixture);
  backwardTraveler.relations["displacement:backward-earth"].properDirection = "reverse";
  assert.match(validateDocument(backwardTraveler).errors.join("\n"), /proper time forward/);

  const selfSharedCycle = clone(fixture);
  selfSharedCycle.relations["segment:earth-traveler-shared"].lines = ["line:earth", "line:earth"];
  assert.match(validateDocument(selfSharedCycle).errors.join("\n"), /at least two distinct lines/);

  const persistedOpen = clone(fixture);
  persistedOpen.relations["termination:sealed-fork"].state = "open";
  assert.match(validateDocument(persistedOpen).errors.join("\n"), /open is a rendering state/);
});
