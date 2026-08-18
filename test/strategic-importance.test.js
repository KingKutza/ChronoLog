import assert from "node:assert/strict";
import test from "node:test";
import { ChronologEngine } from "../src/engine.js";
import { strategicPresentationForTest } from "../src/projections.js";
import { addEvent, addRelation, durationMagnitude } from "../src/model.js";
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
