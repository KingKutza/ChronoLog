// The ruled completion model: state is a frame, being in it is membership, the
// instant is the object's end staple. These tests pin the toggle's round trip
// (backdated instants included), the legal membership-with-no-instant shape,
// and the load-time repair that restates the legacy `role: "completed"`
// attachment -- idempotent, reported, and verdict-preserving through
// rosterEntries.
import assert from "node:assert/strict";
import test from "node:test";
import { ChronologEngine } from "../src/engine.js";
import { Rational, daysFromCivil } from "../src/exact.js";
import { coordinateLaw } from "../src/coordinate-law.js";
import { CommandHistory, addEvent, addRelation, clone, durationMagnitude, validateDocument } from "../src/model.js";
import {
  DONE_STATE_FRAME_ID,
  doneAffiliation,
  rosterEntries,
  stateAffiliations
} from "../src/object-kinds.js";
import { applyOps } from "../src/ops.js";
import { compactDocument } from "../src/store.js";
import { ViewSession } from "../src/session.js";
import { toggleStateAffiliation, toggleTodoCompletion } from "../src/ui/roster.js";
import { createTransactions } from "../src/ui/transactions.js";
import { createStructuralDocument } from "./helpers/sample-document.js";

function harness(document, activeFrame = "calendar:personal") {
  const changes = [];
  const app = { chronolog: document, session: new ViewSession({ activeFrame }) };
  app.history = new CommandHistory(document, (change) => changes.push(change));
  Object.assign(app, createTransactions(app));
  return { app, changes };
}

function documentWithTodo() {
  const document = createStructuralDocument();
  document.frames["calendar:personal"] = {
    id: "calendar:personal",
    title: "Personal",
    traits: ["set", "calendar"],
    basis: "frame:wall-time"
  };
  const todo = addEvent(document, {
    id: "event:permit",
    traits: ["event", "task", "todo"],
    magnitudes: { duration: durationMagnitude("0") },
    payload: { title: "Renew the parking permit" }
  });
  addRelation(document, {
    id: "relation:permit-observed",
    type: "attachment",
    event: todo.id,
    frame: "calendar:personal",
    role: "observed",
    coordinate: { levels: [{ level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "15" }] }
  });
  return { document, todoId: todo.id };
}

test("a backdated completion is nothing but the end staple's coordinate", () => {
  const { document, todoId } = documentWithTodo();
  const { app } = harness(document);
  // Done last Tuesday, recorded today: `at` IS the backdate.
  const backdate = new Rational(daysFromCivil(2026n, 8n, 11n));
  toggleStateAffiliation(app, todoId, { at: backdate });

  const affiliations = stateAffiliations(app.chronolog, todoId);
  assert.equal(affiliations.length, 1);
  assert.equal(affiliations[0].frame, DONE_STATE_FRAME_ID);
  assert.equal(affiliations[0].title, "Done");
  const at = affiliations[0].at;
  assert.ok(at, "the instant is stated");
  assert.equal(at.frame, "calendar:personal");
  assert.equal(
    coordinateLaw(app.chronolog, at.frame).toDays(at.coordinate).compare(backdate), 0,
    "the staple's coordinate resolves to exactly the backdated instant"
  );
  const entry = rosterEntries(app.chronolog, "todo").find((item) => item.id === todoId);
  assert.equal(entry.completed, true);
  assert.deepEqual(entry.completedAt, at.coordinate);
  assert.deepEqual(validateDocument(app.chronolog).errors, []);

  // Round trip: leaving the state removes membership and staple exactly.
  toggleStateAffiliation(app, todoId);
  assert.deepEqual(stateAffiliations(app.chronolog, todoId), []);
  assert.equal(rosterEntries(app.chronolog, "todo").find((item) => item.id === todoId).completed, false);
  assert.deepEqual(validateDocument(app.chronolog).errors, []);
});

test("a state affiliation with no staple is legal: done, instant unstated", () => {
  const { document, todoId } = documentWithTodo();
  document.frames[DONE_STATE_FRAME_ID] = {
    id: DONE_STATE_FRAME_ID,
    title: "Done",
    traits: ["set", "group", "state"]
  };
  addRelation(document, { type: "membership", group: DONE_STATE_FRAME_ID, member: todoId });

  assert.deepEqual(validateDocument(document).errors, []);
  const affiliation = doneAffiliation(document, todoId);
  assert.ok(affiliation, "membership alone IS the state");
  assert.equal(affiliation.at, null, "no instant is claimed for it");
  const entry = rosterEntries(document, "todo").find((item) => item.id === todoId);
  assert.equal(entry.completed, true);
  assert.equal(entry.completedAt, null);
});

test("states beyond done ride the same mechanism: a named frame, a membership", () => {
  const { document, todoId } = documentWithTodo();
  const { app } = harness(document);
  toggleStateAffiliation(app, todoId, { stateFrame: "frame:state-cancelled", title: "Cancelled" });
  const cancelled = app.chronolog.frames["frame:state-cancelled"];
  assert.equal(cancelled.title, "Cancelled");
  assert.ok(cancelled.traits.includes("state") && cancelled.traits.includes("group"));
  const affiliations = stateAffiliations(app.chronolog, todoId);
  assert.deepEqual(affiliations.map((entry) => entry.frame), ["frame:state-cancelled"]);
  // Cancelled is not done: the roster's completed verdict keys on the Done frame.
  assert.equal(rosterEntries(app.chronolog, "todo").find((item) => item.id === todoId).completed, false);
  assert.deepEqual(validateDocument(app.chronolog).errors, []);
});

test("the minting toggle's journal ops replay to the same document, undo included", () => {
  const { document, todoId } = documentWithTodo();
  const before = clone(document);
  const { app, changes } = harness(document);
  toggleTodoCompletion(app, todoId);

  // The Done frame was minted inside this transaction, so the frame put must
  // be in the ops -- a replay that lacked it would fail validation at load.
  const change = changes.at(-1);
  assert.ok(change.ops.some((op) => op.op === "put" && op.map === "frames" && op.id === DONE_STATE_FRAME_ID));
  const replayed = clone(before);
  applyOps(replayed, change.ops);
  assert.deepEqual(replayed, app.chronolog, "replaying the ops reproduces the toggled document");

  assert.equal(app.history.undo(), true);
  const undone = changes.at(-1);
  assert.ok(undone.ops.some((op) => op.op === "del" && op.map === "frames" && op.id === DONE_STATE_FRAME_ID));
  assert.deepEqual(app.chronolog.frames[DONE_STATE_FRAME_ID], undefined);
  assert.deepEqual(validateDocument(app.chronolog).errors, []);
});

test("bulk-skip materializes past occurrences into a named state, one undoable transaction", () => {
  const { document } = documentWithTodo();
  const template = addEvent(document, {
    id: "event:watering",
    traits: ["event", "task", "todo"],
    magnitudes: { duration: durationMagnitude("0") },
    payload: { title: "Water the plants" }
  });
  const templateRelation = addRelation(document, {
    id: "relation:watering-observed",
    type: "attachment",
    event: template.id,
    frame: "calendar:personal",
    role: "observed",
    coordinate: { levels: [{ level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "1" }] }
  });
  document.patterns["pattern:watering"] = {
    id: "pattern:watering",
    language: "chronolog-formula/1",
    kind: "ics-rrule",
    frame: "calendar:personal",
    appliesTo: ["calendar:personal"],
    templateEvent: template.id,
    templateRelation: templateRelation.id,
    rrule: { FREQ: "DAILY" },
    source: "export fn state(ctx) = {};\nexport fn facts(ctx) = [];",
    exports: { state: "state", facts: "facts" }
  };
  const before = clone(document);
  const { app, changes } = harness(document);
  const keys = [
    `occurrence-${daysFromCivil(2026n, 8n, 2n)}`,
    `occurrence-${daysFromCivil(2026n, 8n, 3n)}`
  ];
  const skipped = app.bulkSkipOccurrences("pattern:watering", keys, {
    stateFrame: "frame:state-skipped",
    title: "Skipped"
  });
  assert.equal(skipped, 2);

  const skippedFrame = app.chronolog.frames["frame:state-skipped"];
  assert.equal(skippedFrame.title, "Skipped");
  assert.ok(skippedFrame.traits.includes("state"));
  const overrides = Object.values(app.chronolog.overrides);
  assert.equal(overrides.length, 2, "each skipped slot is suppressed");
  for (const override of overrides) {
    assert.equal(override.suppress, true);
    const [materialized] = override.replacements;
    const event = app.chronolog.events[materialized];
    assert.equal(event.provenance.kind, "explicit");
    assert.equal(event.provenance.pattern, "pattern:watering");
    const affiliations = stateAffiliations(app.chronolog, materialized);
    assert.deepEqual(affiliations.map((entry) => entry.frame), ["frame:state-skipped"]);
    assert.equal(affiliations[0].at, null, "a skip states no instant");
  }
  assert.deepEqual(validateDocument(app.chronolog).errors, []);

  // One transaction: the journal replays it whole, and ONE undo removes it whole.
  const replayed = clone(before);
  applyOps(replayed, changes.at(-1).ops);
  assert.deepEqual(replayed, app.chronolog);
  assert.equal(app.history.undo(), true);
  assert.deepEqual(Object.keys(app.chronolog.overrides), []);
  assert.equal(app.chronolog.frames["frame:state-skipped"], undefined, "undo removes the frame this transaction minted");
  assert.deepEqual(validateDocument(app.chronolog).errors, []);
});

// --- The load-time repair --------------------------------------------------

function legacyDocument() {
  const { document, todoId } = documentWithTodo();
  const legacyCoordinate = {
    levels: [{ level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "9" }]
  };
  document.relations["relation:permit-completed"] = {
    id: "relation:permit-completed",
    type: "attachment",
    event: todoId,
    frame: "calendar:personal",
    role: "completed",
    coordinate: legacyCoordinate,
    parameters: { utc: true }
  };
  // A second legacy completion that never carried a coordinate: done, instant
  // unstated, which the repair restates as membership only.
  const bare = addEvent(document, {
    id: "event:someday",
    traits: ["event", "task", "todo"],
    magnitudes: { duration: durationMagnitude("0") },
    payload: { title: "Someday idea" }
  });
  document.relations["relation:someday-completed"] = {
    id: "relation:someday-completed",
    type: "attachment",
    event: bare.id,
    frame: "calendar:personal",
    role: "completed"
  };
  return { document, todoId, bareId: bare.id, legacyCoordinate };
}

test("migrateCompletedRelations restates the legacy shape, reported and counted, verdict intact", () => {
  const { document, todoId, bareId, legacyCoordinate } = legacyDocument();
  const report = [];
  compactDocument(document, report);

  const repair = report.find((entry) => entry.kind === "completed-state");
  assert.ok(repair, "the repair reports itself");
  assert.equal(repair.count, 2);
  assert.match(repair.message, /2 completions/);

  assert.ok(document.frames[DONE_STATE_FRAME_ID], "the deterministic Done frame exists because legacy relations did");
  assert.ok(
    !Object.values(document.relations).some((relation) => relation.role === "completed"),
    "the legacy record is REPLACED, never kept alongside"
  );
  assert.deepEqual(validateDocument(document).errors, [], "the migrated document is valid");

  // The verdict through rosterEntries is exactly what the legacy relation
  // claimed: completed, at the same coordinate (or with none stated).
  const entries = rosterEntries(document, "todo");
  const dated = entries.find((entry) => entry.id === todoId);
  assert.equal(dated.completed, true);
  assert.deepEqual(dated.completedAt, legacyCoordinate);
  const bare = entries.find((entry) => entry.id === bareId);
  assert.equal(bare.completed, true, "a coordinate-less legacy completion is still done");
  assert.equal(bare.completedAt, null, "with its instant honestly unstated");

  // The staple carries the legacy time typing so ICS export restates it.
  const at = doneAffiliation(document, todoId).at;
  assert.deepEqual(at.parameters, { utc: true });
});

test("the repair is idempotent: a second compaction changes nothing and reports nothing", () => {
  const { document } = legacyDocument();
  compactDocument(document, []);
  const settled = clone(document);
  const report = [];
  compactDocument(document, report);
  assert.deepEqual(document, settled, "a migrated document round-trips compaction unchanged");
  assert.ok(!report.some((entry) => entry.kind === "completed-state"), "and the repair stays silent");
});

test("the engine's group index sees the migrated state membership", () => {
  const { document, todoId } = legacyDocument();
  compactDocument(document, []);
  const engine = new ChronologEngine(document);
  assert.ok(
    engine.groupMembers(DONE_STATE_FRAME_ID).some((entry) => entry.member === todoId),
    "the Done frame answers as a group -- frames are groups, states are frames"
  );
});
