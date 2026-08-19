import assert from "node:assert/strict";
import test from "node:test";
import { ChronologEngine } from "../src/engine.js";
import { queryFactsForTest, strategicPresentationForTest } from "../src/projections.js";
import { factImportance, factImportanceWeight, resolveObjectColor, sigilForFact } from "../src/visual-language.js";
import { minimapEventMagnitude } from "../src/minimap.js";
import {
  CommandHistory,
  addEvent,
  addFrame,
  addRelation,
  coordinateToDays,
  createDocument,
  durationMagnitude
} from "../src/model.js";
import { createTransactions } from "../src/ui/transactions.js";
import { coordinate } from "../src/exact.js";
import { ViewSession } from "../src/session.js";
import { createStructuralDocument } from "./helpers/sample-document.js";

// A ToDo marked important did not render in Strategic at all — under either
// importance mechanism. Invisible data is the most dangerous kind of bug, so this
// pins the guarantee rather than the implementation: marking something important
// may change how prominently Strategic draws it, but may never make it vanish.
function scene() {
  const document = createStructuralDocument();
  const calendar = Object.values(document.frames).find((frame) => frame.traits?.includes("gregorian"));

  document.frames["frame:importance-high"] = {
    id: "frame:importance-high",
    title: "High",
    traits: ["set", "group", "importance"],
    color: "#663399",
    display: { importance: "important" }
  };
  document.frames["frame:group-plain"] = {
    id: "frame:group-plain",
    title: "Ordinary",
    traits: ["set", "group"],
    color: "#2e8b57"
  };
  // Item #5: a frame IS a group, so a plain calendar frame -- not an
  // "importance" frame, no importance trait anywhere -- can promote its own
  // events into Strategic wholesale purely through `display.weight`. This is
  // the owner's literal question ("How do I set a frame to auto promote all
  // events belonging to it in Strategic view?") made concrete: an imported
  // "US holidays" calendar given a weight promotes every one of its events.
  document.frames["frame:us-holidays"] = {
    id: "frame:us-holidays",
    title: "US holidays",
    traits: ["set", "calendar"],
    color: "#c9a227",
    display: { weight: 4 }
  };

  const cases = {};
  const place = (key, { traits, magnitudes, group }) => {
    const event = addEvent(document, {
      traits,
      magnitudes: magnitudes || { duration: durationMagnitude("0") },
      payload: { title: key }
    });
    addRelation(document, {
      type: "placement",
      event: event.id,
      frame: calendar.id,
      coordinate: {
        levels: [
          { level: "year", value: "2026" },
          { level: "month", value: "3" },
          { level: "day", value: "10" },
          { level: "hour", value: "9" }
        ]
      }
    });
    if (group) {
      addRelation(document, { type: "attachment", event: event.id, frame: group, role: "member" });
    }
    cases[key] = event.id;
    return event.id;
  };

  place("plain-todo", { traits: ["todo"] });
  place("legacy-important", { traits: ["todo", "important"] });
  place("legacy-landmark", { traits: ["todo", "landmark"] });
  place("group-important-todo", { traits: ["todo"], group: "frame:importance-high" });
  place("group-important-event", {
    traits: ["event"],
    magnitudes: { duration: durationMagnitude("1800") },
    group: "frame:importance-high"
  });
  place("ordinary-group-todo", { traits: ["todo"], group: "frame:group-plain" });
  place("weighted-calendar-todo", { traits: ["todo"], group: "frame:us-holidays" });
  place("weighted-calendar-event", { traits: ["event"], group: "frame:us-holidays" });

  const engine = new ChronologEngine(document);
  const session = new ViewSession({ activeFrame: calendar.id, projection: "calendar", scale: 2 });
  return { document, engine, session, cases, calendar };
}

function presentationFor(scenario, key) {
  const eventId = scenario.cases[key];
  const fact = {
    event: scenario.document.events[eventId],
    day: "0",
    relation: { frame: scenario.calendar.id }
  };
  return strategicPresentationForTest(
    { document: scenario.document, engine: scenario.engine, session: scenario.session },
    fact
  );
}

test("Strategic is on its default signal mode for these cases", () => {
  const scenario = scene();
  assert.equal(scenario.session.currentLens(), "strategic");
  assert.equal(scenario.session.strategicMode, "signal", "signal is the default, and the mode the bug appeared in");
});

// The headline guarantee. Every one of these was invisible ("none") before the fix
// except the single legacy "important" trait.
test("importance never hides an object from Strategic, by either mechanism", () => {
  const scenario = scene();
  for (const key of [
    "legacy-important",
    "legacy-landmark",
    "group-important-todo",
    "group-important-event"
  ]) {
    assert.notEqual(presentationFor(scenario, key), "none", `${key} must not vanish from Strategic`);
  }
});

test("importance is read through the one shared precedence chain, frames included", () => {
  const scenario = scene();
  // A zero-duration, non-recurring ToDo has no other reason to earn a name, so
  // these assertions isolate importance as the cause.
  assert.equal(presentationFor(scenario, "legacy-landmark"), "name", "the legacy landmark trait counts");
  assert.equal(presentationFor(scenario, "group-important-todo"), "name", "so does importance by group affiliation");
  // A 30-minute Event is well under the 240-minute block threshold, so if it shows
  // a name it is because importance was seen — not because it was long enough.
  assert.equal(presentationFor(scenario, "group-important-event"), "name");
});

test("an object with no importance signal is still allowed to be quiet", () => {
  const scenario = scene();
  // The fix must not turn Strategic into "show everything" — that would defeat the
  // lens. An unremarkable short ToDo stays unpromoted.
  assert.equal(presentationFor(scenario, "plain-todo"), "none");
  assert.equal(presentationFor(scenario, "ordinary-group-todo"), "none", "an ordinary group is not an importance signal");
});

// Meaning is authored, never inferred — specifically not from imported categories.
// Strategic used to promote an object whose provider category merely matched
// /important|milestone|deadline/, which was the only such inference in the codebase.
test("an imported category never promotes an object on its own", () => {
  const scenario = scene();
  const eventId = scenario.cases["plain-todo"];
  scenario.document.events[eventId].payload.categories = ["Important", "Deadline"];
  assert.equal(
    presentationFor(scenario, "plain-todo"),
    "none",
    "a provider's category string is not an authored importance decision"
  );
});

// Stage D (ROADMAP #9's display-only half): every display consumer that used
// to be blind to group/importance-frame affiliation now reads the one shared
// `factImportance` verdict. This exercises color, sigil, and minimap weight
// together over the same real engine/document `presentationFor` already
// proved Strategic sees correctly, so all four consumers are pinned against
// one scenario.
test("color, sigil, and minimap weight all see importance the same way Strategic does", () => {
  const scenario = scene();
  const factFor = (key) => ({
    event: scenario.document.events[scenario.cases[key]],
    day: "0",
    relation: { frame: scenario.calendar.id }
  });
  const context = { document: scenario.document, engine: scenario.engine };

  // factImportance: legacy trait and group/importance-frame affiliation both
  // resolve to the same verdict, no legacy migration involved.
  assert.equal(factImportance(context, factFor("plain-todo")), "standard");
  assert.equal(factImportance(context, factFor("legacy-landmark")), "landmark");
  assert.equal(factImportance(context, factFor("group-important-todo")), "important");
  assert.equal(factImportance(context, factFor("group-important-event")), "important");
  assert.equal(factImportance(context, factFor("ordinary-group-todo")), "standard", "an ordinary group is not an importance signal");

  // Sigil: group-based importance earns the same milestone mark a legacy
  // trait would, so grayscale/no-color viewing still carries the meaning.
  // (ToDo-ness outranks importance in sigil selection either way -- that
  // precedence predates this stage and is untouched -- so this compares two
  // plain Events, one important by legacy trait, one by group affiliation.)
  const sigilFor = (key) => sigilForFact(factFor(key), 0, factImportance(context, factFor(key)));
  assert.equal(sigilForFact({ event: { traits: ["event", "landmark"] } }), "milestone", "legacy trait, unchanged baseline");
  assert.equal(sigilFor("group-important-event"), "milestone", "group affiliation earns the same mark");
  assert.equal(sigilFor("plain-todo"), "task", "an unremarkable ToDo keeps its ordinary task sigil");
  assert.equal(sigilFor("group-important-todo"), "task", "ToDo-ness still outranks importance in sigil selection, same as before this stage");

  // Color cascade step 2: the exact reported symptom -- an importance frame
  // colors its events the same as an ordinary group would.
  assert.equal(resolveObjectColor({
    document: scenario.document,
    engine: scenario.engine,
    object: scenario.document.events[scenario.cases["group-important-event"]],
    activeFrame: scenario.calendar.id
  }), "#663399");
  assert.equal(resolveObjectColor({
    document: scenario.document,
    engine: scenario.engine,
    object: scenario.document.events[scenario.cases["ordinary-group-todo"]],
    activeFrame: scenario.calendar.id
  }), "#2e8b57", "an ordinary group still colors its events exactly as before");

  // Minimap weight: importance lifts the same event's magnitude by the same
  // multiplier whether the signal came from a legacy trait or a group.
  const standardMagnitude = minimapEventMagnitude({ importance: factImportance(context, factFor("plain-todo")) });
  const legacyMagnitude = minimapEventMagnitude({ importance: factImportance(context, factFor("legacy-landmark")) });
  const groupMagnitude = minimapEventMagnitude({ importance: factImportance(context, factFor("group-important-todo")) });
  assert.ok(groupMagnitude > standardMagnitude, "group-based importance must weigh more than standard");
  assert.equal(legacyMagnitude, minimapEventMagnitude({ importance: "landmark" }));
  assert.equal(groupMagnitude, minimapEventMagnitude({ importance: "important" }));
});

// ROADMAP #9 point 6, bullet 2: "a group's per-lens display settings are lost
// when it converts to an importance frame." Additive kind-switching
// (frame-edit.js) never removes the "group" trait or touches `display`, so
// nothing is actually deleted -- the loss was purely `factGroupFrame` going
// blind to the frame once it also carried "importance". Routing it through
// the isDisplayGroup union (src/engine.js's `eventDisplayGroupFrame`) fixes
// this without any change to what gets persisted.
test("a group's Strategic display setting survives converting to an importance frame", () => {
  const scenario = scene();
  const plain = scenario.document.frames["frame:group-plain"];
  plain.display = { strategic: "show" };
  scenario.engine.refreshFrame(plain.id);
  assert.equal(presentationFor(scenario, "ordinary-group-todo"), "name", "an explicit 'promote' setting earns a name on its own");

  plain.traits = ["set", "group", "importance"];
  scenario.engine.refreshFrame(plain.id);
  assert.equal(
    presentationFor(scenario, "ordinary-group-todo"),
    "name",
    "the promote setting must not be lost just because the frame also became an importance frame"
  );
});

// ROADMAP #9 point 6, bullet 1: "the Frames panel's per-calendar presence
// control silently does nothing for importance frames." The panel already
// lists importance frames as ordinary groups (they carry the "group" trait);
// the "Include all" setting reaches across calendars by walking
// `engine.displayGroupEventMembers`, so it must include importance-frame
// members the same way it already includes ordinary-group members.
test("a calendar's 'Include all' presence setting reaches an importance frame's members from another calendar", () => {
  const document = createDocument();
  addFrame(document, { id: "line:earth", title: "Earth", traits: ["line", "gregorian"], coordinate: { kind: "gregorian" } });
  addFrame(document, {
    id: "calendar:active", title: "Active", traits: ["set", "calendar"], coordinateDefinition: "line:earth",
    display: { groupModes: { "frame:important": "show" } }
  });
  addFrame(document, { id: "calendar:other", title: "Other", traits: ["set", "calendar"], coordinateDefinition: "line:earth" });
  addFrame(document, { id: "frame:important", title: "Important", traits: ["set", "group", "importance"] });

  const event = addEvent(document, {
    traits: ["event"], magnitudes: { duration: durationMagnitude("0") }, payload: { title: "Elsewhere but important" }
  });
  const day = coordinate([{ level: "year", value: "2030" }, { level: "month", value: "6" }, { level: "day", value: "15" }]);
  addRelation(document, { type: "attachment", event: event.id, frame: "calendar:other", role: "placed", coordinate: day });
  addRelation(document, { type: "attachment", event: event.id, frame: "frame:important", role: "member" });

  const engine = new ChronologEngine(document);
  const session = new ViewSession({ activeFrame: "calendar:active", projection: "calendar", scale: 2 });
  const context = { document, engine, session };
  const dayValue = coordinateToDays(document, "calendar:other", day);
  const result = queryFactsForTest(context, "calendar:active", dayValue.sub(1), dayValue.add(1), 50);
  assert.ok(
    result.facts.some((fact) => fact.event.id === event.id),
    "the importance frame's 'Include all' presence setting must surface its members from other calendars"
  );
});

// Item #5, "strategic promotion via frames-are-groups": display weight is a
// handling property of the group/frame (LEXICON.md's "importance is a group
// affiliation, not a property"), composed through the one shared
// `factImportanceWeight`/`factImportance` path -- no frame-specific one-off
// field, no parallel gate. These tests exercise that composition against the
// real `ChronologEngine`, the same object every renderer threads through.
test("a frame's display weight alone promotes its member events into the Strategic gate, wholesale, with no importance trait involved", () => {
  const scenario = scene();
  const context = { document: scenario.document, engine: scenario.engine };
  const verdict = factImportance(context, { event: scenario.document.events[scenario.cases["weighted-calendar-todo"]] });
  // 1 (standard base, no legacy trait, no importance-frame membership) * 4
  // ("frame:us-holidays"'s own display.weight) crosses the landmark threshold.
  assert.equal(verdict, "landmark");
  assert.equal(
    presentationFor(scenario, "weighted-calendar-todo"),
    "name",
    "Strategic must promote a plain calendar's weighted member the same way an importance trait would"
  );
});

// A weight of 1 -- the universal, authored-only default -- must be a true
// no-op: this is the regression guard for every existing frame nobody has
// touched the new knob on.
test("a frame weight of 1 changes nothing about Strategic's presentation", () => {
  const scenario = scene();
  scenario.document.frames["frame:us-holidays"].display.weight = 1;
  scenario.engine.refreshFrame("frame:us-holidays");
  const context = { document: scenario.document, engine: scenario.engine };
  assert.equal(
    factImportance(context, { event: scenario.document.events[scenario.cases["weighted-calendar-todo"]] }),
    "standard"
  );
  assert.equal(presentationFor(scenario, "weighted-calendar-todo"), "none");
});

// The composed, frame-weight-driven verdict must drive color, sigil, and
// minimap magnitude exactly as consistently as a legacy trait or an
// importance-frame membership already does (see the equivalent test above
// for those two mechanisms) -- one verdict, every consumer agrees.
test("a frame-weight-driven verdict drives color, sigil, and minimap magnitude consistently", () => {
  const scenario = scene();
  const factFor = (key) => ({
    event: scenario.document.events[scenario.cases[key]],
    day: "0",
    relation: { frame: scenario.calendar.id }
  });
  const context = { document: scenario.document, engine: scenario.engine };
  const verdict = factImportance(context, factFor("weighted-calendar-event"));
  assert.equal(verdict, "landmark");

  // Sigil: the same milestone mark a legacy landmark trait earns, comparing
  // two plain Events so ToDo-ness's own precedence (proven elsewhere) never
  // enters into it.
  assert.equal(
    sigilForFact(factFor("weighted-calendar-event"), 0, verdict),
    sigilForFact({ event: { traits: ["event", "landmark"] } }),
    "a frame-weight verdict earns the same sigil a legacy landmark trait would"
  );

  // Color: "frame:us-holidays" colors its own events through the ordinary
  // cascade exactly as before -- the weight knob and the color cascade are
  // independent properties of the same frame, and neither depends on the other.
  assert.equal(resolveObjectColor({
    document: scenario.document,
    engine: scenario.engine,
    object: scenario.document.events[scenario.cases["weighted-calendar-event"]],
    activeFrame: scenario.calendar.id
  }), "#c9a227");

  // Minimap: the composed "landmark" verdict weighs exactly as much as any
  // other landmark verdict, regardless of what produced it.
  assert.equal(
    minimapEventMagnitude({ importance: verdict }),
    minimapEventMagnitude({ importance: "landmark" })
  );
});

// Nested group membership must contribute an ancestor group's weight even
// though the event is only ever directly attached to the descendant -- the
// same union `eventDisplayGroupMemberships` already resolves for color and
// sigil, reused rather than re-derived.
test("nested group membership contributes its ancestor group's weight to the composed verdict", () => {
  const document = createDocument();
  addFrame(document, { id: "line:earth", title: "Earth", traits: ["line", "gregorian"], coordinate: { kind: "gregorian" } });
  addFrame(document, { id: "calendar:active", title: "Active", traits: ["set", "calendar"], coordinateDefinition: "line:earth" });
  addFrame(document, { id: "group:parent", title: "Parent group", traits: ["set", "group"], display: { weight: 3 } });
  addFrame(document, { id: "group:child", title: "Child group", traits: ["set", "group"] });

  const event = addEvent(document, {
    traits: ["event"], magnitudes: { duration: durationMagnitude("0") }, payload: { title: "Nested member" }
  });
  const day = coordinate([{ level: "year", value: "2030" }, { level: "month", value: "6" }, { level: "day", value: "15" }]);
  addRelation(document, { type: "attachment", event: event.id, frame: "calendar:active", role: "placed", coordinate: day });
  addRelation(document, { type: "attachment", event: event.id, frame: "group:child", role: "member" });
  addRelation(document, { id: "membership:child-in-parent", type: "membership", group: "group:parent", member: "group:child" });

  const engine = new ChronologEngine(document);
  const context = { document, engine };

  const memberships = engine.eventDisplayGroupMemberships(event.id).map(({ group }) => group).sort();
  assert.deepEqual(memberships, ["group:child", "group:parent"], "the engine's own nested-membership union must surface the ancestor");
  assert.equal(
    factImportanceWeight(context, { event }),
    3,
    "1 (standard base) * 3 (the ancestor's weight, reached only through nesting, not a direct attachment)"
  );
  assert.equal(factImportance(context, { event }), "important");
});

// The knob in the frame editor (src/ui/frames-panel.js's "Display weight"
// field) writes through `app.executeRecordChange`, the same shared undoable
// transaction helper every other frame edit uses -- never a direct mutation.
// This proves that write path end to end: one journaled `put frames/<id>`
// op, and an undo that is a real document change the composed verdict
// reacts to, not merely a UI-visible one.
test("the display-weight knob's write path journals one frame put and is fully undoable", () => {
  const document = createDocument();
  addFrame(document, { id: "line:earth", title: "Earth", traits: ["line", "gregorian"], coordinate: { kind: "gregorian" } });
  addFrame(document, { id: "calendar:active", title: "Active", traits: ["set", "calendar"], coordinateDefinition: "line:earth" });
  addFrame(document, { id: "frame:us-holidays", title: "US holidays", traits: ["set", "calendar"] });
  const event = addEvent(document, {
    traits: ["event"], magnitudes: { duration: durationMagnitude("0") }, payload: { title: "Independence Day" }
  });
  addRelation(document, { type: "attachment", event: event.id, frame: "frame:us-holidays", role: "member" });

  const changes = [];
  const app = { chronolog: document };
  app.history = new CommandHistory(document, (change) => changes.push(change));
  Object.assign(app, createTransactions(app));

  const engine = new ChronologEngine(document);
  const context = { document, engine };
  assert.equal(factImportance(context, { event }), "standard", "no weight authored yet");

  // This mirrors exactly what the frame form's submit handler does with the
  // "Display weight" field's value -- mutate `display` inside
  // `executeRecordChange`, never assign to the record directly.
  app.executeRecordChange("Edit frame", "frames", "frame:us-holidays", (documentValue) => {
    documentValue.frames["frame:us-holidays"].display = {
      ...(documentValue.frames["frame:us-holidays"].display || {}), weight: 4
    };
  });

  const applied = changes.at(-1);
  assert.deepEqual(
    new Set(applied.ops.map((op) => `${op.op} ${op.map}/${op.id}`)),
    new Set(["put frames/frame:us-holidays", "put meta/modified"]),
    "the weight edit journals as exactly one frame put, nothing else"
  );
  assert.equal(document.frames["frame:us-holidays"].display.weight, 4);
  assert.equal(factImportance(context, { event }), "landmark", "the composed verdict reacts to the freshly-authored weight");

  assert.equal(app.history.undo(), true);
  assert.equal(
    document.frames["frame:us-holidays"].display?.weight,
    undefined,
    "undo restores the pre-edit record, which never had a weight"
  );
  assert.equal(factImportance(context, { event }), "standard", "undo is a real document change -- the verdict reverts with it");

  assert.equal(app.history.redo(), true);
  assert.equal(document.frames["frame:us-holidays"].display.weight, 4, "redo re-applies the authored weight");
  assert.equal(factImportance(context, { event }), "landmark");
});
