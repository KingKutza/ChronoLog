import assert from "node:assert/strict";
import test from "node:test";
import { ChronologEngine } from "../src/engine.js";
import { queryFactsForTest, strategicPresentationForTest } from "../src/projections.js";
import { factImportance, resolveObjectColor, sigilForFact } from "../src/visual-language.js";
import { minimapEventMagnitude } from "../src/minimap.js";
import {
  addEvent,
  addFrame,
  addRelation,
  coordinateToDays,
  createDocument,
  durationMagnitude
} from "../src/model.js";
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
