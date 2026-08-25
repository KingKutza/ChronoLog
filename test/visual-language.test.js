import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  SIGIL_VOCABULARY,
  THEME_PRESETS,
  explainFactWeight,
  factImportance,
  factImportanceWeight,
  normalizeTheme,
  resolveObjectColor,
  sigilAriaLabel,
  sigilForFact,
  todoStateForFact
} from "../src/visual-language.js";

function colorFixture({ groupModes = {} } = {}) {
  const document = {
    frames: {
      "calendar:active": { id: "calendar:active", traits: ["calendar"], color: "#111111", display: { groupModes } },
      "calendar:source": { id: "calendar:source", traits: ["calendar"], color: "#222222" },
      "group:small": { id: "group:small", traits: ["group"], color: "#333333" },
      "group:large": { id: "group:large", traits: ["group"], color: "#444444" },
      "group:active": { id: "group:active", traits: ["group"], color: "#555555" }
    }
  };
  const memberships = ["group:small", "group:large", "group:active"];
  const sizes = { "group:small": 2, "group:large": 12, "group:active": 1 };
  const engine = {
    // resolveObjectColor's step 2 reads the display-side union
    // (isDisplayGroup: ordinary groups plus importance frames), not the
    // persisted-only group index -- see src/engine.js.
    eventDisplayGroupMemberships: () => memberships.map((group) => ({ group })),
    displayGroupEventMembers: (group) => Array.from({ length: sizes[group] }),
    eventFrames: () => ["calendar:source", "calendar:active"]
  };
  return { document, engine };
}

test("visual grammar maps structural event roles to stable sigils", () => {
  assert.equal(sigilForFact({ event: { traits: ["event"] } }), "point");
  assert.equal(sigilForFact({ event: { traits: ["event", "milestone"] } }), "milestone");
  assert.equal(sigilForFact({ event: { traits: ["event", "task"] } }), "task");
  assert.equal(sigilForFact({ event: { traits: ["event", "note"] } }), "note");
  assert.equal(sigilForFact({ event: { traits: ["event", "terminator"] } }), "terminator");
  assert.equal(sigilForFact({ event: { traits: ["event", "celestial"] } }), "celestial");
  assert.equal(sigilForFact({ event: { traits: ["event"] }, virtualId: "repeat:1" }), "repeat");
  assert.equal(sigilForFact({ event: { traits: ["event"] } }, 1440), "span");
  assert.equal(SIGIL_VOCABULARY.milestone.glyph, "◆");
});

test("sigil selection is blind to legacy traits alone -- it also honors the unified importance verdict", () => {
  // Default `importance` is "standard", so every existing call site (and every
  // test above that omits the third argument) keeps its legacy-trait-only
  // answer unchanged.
  assert.equal(sigilForFact({ event: { traits: ["event"] } }), "point");
  // An event made important purely by group/importance-frame affiliation --
  // no legacy trait on the event itself -- must still earn the milestone
  // sigil, or shape stops carrying meaning for it (AGENTS.md's "never the
  // sole carrier" rule, which color alone breaking would violate the same way).
  assert.equal(sigilForFact({ event: { traits: ["event"] } }, 0, "important"), "milestone");
  assert.equal(sigilForFact({ event: { traits: ["event"] } }, 0, "landmark"), "milestone");
  // Legacy traits keep working unmodified, importance argument or not.
  assert.equal(sigilForFact({ event: { traits: ["event", "landmark"] } }), "milestone");
});

function importanceFixture() {
  const document = {
    events: {},
    patterns: {},
    frames: {
      "frame:important": {
        id: "frame:important", traits: ["set", "group", "importance"], display: { importance: "important" }
      },
      "frame:landmark": {
        id: "frame:landmark", traits: ["set", "group", "importance"], display: { importance: "landmark" }
      }
    }
  };
  const membershipsByEvent = {};
  const engine = {
    eventDisplayGroupMemberships: (eventId) => (membershipsByEvent[eventId] || []).map((group) => ({ group }))
  };
  return { document, engine, membershipsByEvent };
}

test("factImportance reads legacy traits first, then group/importance-frame membership", () => {
  const { document, engine, membershipsByEvent } = importanceFixture();
  document.events["event:standard"] = { id: "event:standard", traits: ["event"] };
  document.events["event:legacy-important"] = { id: "event:legacy-important", traits: ["event", "important"] };
  document.events["event:legacy-landmark"] = { id: "event:legacy-landmark", traits: ["event", "landmark"] };
  document.events["event:group-important"] = { id: "event:group-important", traits: ["event"] };
  membershipsByEvent["event:group-important"] = ["frame:important"];
  document.events["event:group-landmark"] = { id: "event:group-landmark", traits: ["event"] };
  membershipsByEvent["event:group-landmark"] = ["frame:landmark"];

  const context = { document, engine };
  const importanceOf = (eventId) => factImportance(context, { event: document.events[eventId] });
  assert.equal(importanceOf("event:standard"), "standard");
  assert.equal(importanceOf("event:legacy-important"), "important");
  assert.equal(importanceOf("event:legacy-landmark"), "landmark");
  // The headline regression: no legacy trait at all, importance carried
  // entirely by group/importance-frame membership.
  assert.equal(importanceOf("event:group-important"), "important");
  assert.equal(importanceOf("event:group-landmark"), "landmark");
});

// Item #5, "frames are groups": display weight is a handling property of the
// group/frame, composed multiplicatively into one weight that `factImportance`
// derives its verdict from by threshold. These fixtures stub `eventFrames`
// (direct attachment, how a calendar frame reaches its own events) alongside
// `eventDisplayGroupMemberships` (group/importance membership, nested
// included) exactly as `factImportanceWeight` reads them.
function weightFixture({ frames = {}, attachedFrames = [], memberships = [] } = {}) {
  const document = { events: {}, patterns: {}, frames };
  const engine = {
    eventFrames: () => attachedFrames,
    eventDisplayGroupMemberships: () => memberships.map((group) => ({ group }))
  };
  return { document, engine };
}

test("a frame weight of 1 is neutral -- it changes neither the composed weight nor the verdict", () => {
  const event = { id: "event:plain", traits: ["event"] };
  const { document, engine } = weightFixture({
    frames: { "calendar:weighted": { id: "calendar:weighted", traits: ["set", "calendar"], display: { weight: 1 } } },
    attachedFrames: ["calendar:weighted"]
  });
  const context = { document, engine };
  const fact = { event };
  assert.equal(factImportanceWeight(context, fact), 1, "base standard weight (1) times a neutral frame weight (1) is 1");
  assert.equal(factImportance(context, fact), "standard");
});

// The owner's literal question: setting a weight on a frame -- any frame, not
// only an "importance" one -- promotes every event that belongs to it,
// without any importance trait or importance-frame membership at all.
test("a plain frame's display weight alone promotes its member events, wholesale, with no importance trait involved", () => {
  const event = { id: "event:plain", traits: ["event"] };
  const { document, engine } = weightFixture({
    frames: { "calendar:us-holidays": { id: "calendar:us-holidays", traits: ["set", "calendar"], display: { weight: 4 } } },
    attachedFrames: ["calendar:us-holidays"]
  });
  const context = { document, engine };
  const fact = { event };
  assert.equal(factImportanceWeight(context, fact), 4, "1 (standard base) * 4 (frame weight)");
  assert.equal(factImportance(context, fact), "landmark");
});

// A weight below 1 demotes exactly the way a weight above 1 promotes --
// "modified by everything that touches it" cuts both directions.
test("a frame weight below 1 demotes an otherwise-important event", () => {
  const event = { id: "event:legacy-important", traits: ["event", "important"] };
  const { document, engine } = weightFixture({
    frames: { "group:muted": { id: "group:muted", traits: ["set", "group"], display: { weight: 0.25 } } },
    attachedFrames: ["group:muted"],
    memberships: ["group:muted"]
  });
  const context = { document, engine };
  const fact = { event };
  assert.equal(factImportanceWeight(context, fact), 0.5, "2 (legacy 'important' base) * 0.25 (frame weight)");
  assert.equal(factImportance(context, fact), "standard");
});

test("an importance frame's base verdict and a frame weight compose multiplicatively through the one shared function", () => {
  const event = { id: "event:one", traits: ["event"] };
  const { document, engine } = weightFixture({
    frames: {
      "frame:important": {
        id: "frame:important", traits: ["set", "group", "importance"], display: { importance: "important", weight: 2.5 }
      }
    },
    memberships: ["frame:important"]
  });
  const context = { document, engine };
  const fact = { event };
  // 2 (the "important" base weight) * 2.5 (that same frame's own display
  // weight) = 5, which crosses the landmark threshold (4) even though the
  // frame only ever declared "important".
  assert.equal(factImportanceWeight(context, fact), 5);
  assert.equal(factImportance(context, fact), "landmark");
});

// A frame reached both as a direct attachment (`eventFrames`) and as a
// display-group membership (`eventDisplayGroupMemberships`, e.g. an
// importance frame the event is also attached to) must contribute its
// weight exactly once, not twice.
test("a frame reached through both eventFrames and display-group membership contributes its weight once, not twice", () => {
  const event = { id: "event:one", traits: ["event"] };
  const { document, engine } = weightFixture({
    frames: { "frame:double": { id: "frame:double", traits: ["set", "group"], display: { weight: 3 } } },
    attachedFrames: ["frame:double"],
    memberships: ["frame:double"]
  });
  const context = { document, engine };
  const fact = { event };
  assert.equal(factImportanceWeight(context, fact), 3, "1 (standard base) * 3 (frame weight), counted once");
});

// A frame with no authored weight, or a nonsensical one, contributes nothing
// -- meaning is authored, never inferred, so a missing or invalid knob must
// not silently change the answer.
test("a frame with no display.weight, or an invalid one, does not affect the composed weight", () => {
  const event = { id: "event:one", traits: ["event"] };
  const { document, engine } = weightFixture({
    frames: {
      "calendar:unweighted": { id: "calendar:unweighted", traits: ["set", "calendar"] },
      "group:negative": { id: "group:negative", traits: ["set", "group"], display: { weight: -3 } },
      "group:nan": { id: "group:nan", traits: ["set", "group"], display: { weight: "not-a-number" } }
    },
    attachedFrames: ["calendar:unweighted", "group:negative", "group:nan"]
  });
  const context = { document, engine };
  const fact = { event };
  assert.equal(factImportanceWeight(context, fact), 1);
  assert.equal(factImportance(context, fact), "standard");
});

// The cross-lens ToDo state vocabulary: done (Done-frame affiliation),
// closed (any other state frame), sparse (title-only capture), open = null.
// Pure over {document, engine}, so the whole grammar pins without a DOM.
function todoStateFixture() {
  const document = {
    events: {},
    relations: {},
    frames: {
      "frame:state-done": { id: "frame:state-done", title: "Done", traits: ["set", "group", "state"] },
      "frame:state-postponed": { id: "frame:state-postponed", title: "Postponed", traits: ["set", "group", "state"] },
      "group:home": { id: "group:home", title: "Home", traits: ["set", "group"] }
    }
  };
  const membershipsByEvent = {};
  const staplesByEvent = {};
  const engine = {
    eventDisplayGroupMemberships: (id) => (membershipsByEvent[id] || []).map((group) => ({ group })),
    staplesByObject: new Map()
  };
  return { document, engine, membershipsByEvent, staplesByEvent };
}

test("todoStateForFact speaks the four-state vocabulary and answers null for non-todos and virtuals", () => {
  const { document, engine, membershipsByEvent } = todoStateFixture();
  const todo = (id, payload = {}) => {
    document.events[id] = { id, traits: ["event", "task", "todo"], payload };
    return { event: document.events[id] };
  };
  const context = { document, engine };

  membershipsByEvent["event:done"] = ["frame:state-done"];
  assert.equal(todoStateForFact(context, todo("event:done")), "done");

  membershipsByEvent["event:postponed"] = ["frame:state-postponed"];
  assert.equal(todoStateForFact(context, todo("event:postponed")), "closed", "any non-Done state frame reads closed");

  // Done wins the stamp when both affiliations exist -- one stamp per mark.
  membershipsByEvent["event:both"] = ["frame:state-postponed", "frame:state-done"];
  assert.equal(todoStateForFact(context, todo("event:both")), "done");

  // Title-only capture: no state, no membership, no description, no
  // authored staple beyond the creation placement.
  assert.equal(todoStateForFact(context, todo("event:bare")), "sparse");

  // Anything the capture said beyond the title lifts sparse: a description...
  assert.equal(todoStateForFact(context, todo("event:described", { description: "call first" })), null);
  // ...or a group membership of any kind...
  membershipsByEvent["event:grouped"] = ["group:home"];
  assert.equal(todoStateForFact(context, todo("event:grouped")), null);
  // ...or an authored staple.
  const stapled = todo("event:stapled");
  engine.staplesByObject.set("event:stapled", [{
    id: "relation:staple",
    type: "staple",
    kind: "anchor",
    ends: [{ object: "event:stapled", point: "start" }, { frame: "calendar:personal", coordinate: { levels: [] } }]
  }]);
  assert.equal(todoStateForFact(context, stapled), null);

  // Not a todo: no stamp, whatever its memberships.
  document.events["event:plain"] = { id: "event:plain", traits: ["event"] };
  membershipsByEvent["event:plain"] = ["frame:state-done"];
  assert.equal(todoStateForFact(context, { event: document.events["event:plain"] }), null);

  // A generated occurrence carries no authored state of its own.
  assert.equal(todoStateForFact(context, { ...todo("event:virtual"), virtualId: "occurrence-1" }), null);
});

test("aria labels compose the sigil and the state through one composer", () => {
  assert.equal(sigilAriaLabel("task", "done", "Water the plants"), "Task or float, done: Water the plants");
  assert.equal(sigilAriaLabel("task", null, "Water the plants"), "Task or float: Water the plants");
  assert.equal(sigilAriaLabel("task", "sparse", ""), "Task or float, sparse: untitled");
});

test("controlled themes always produce a complete valid palette", () => {
  const theme = normalizeTheme({ primary: "#abcdef", accent: "not-a-color" }, THEME_PRESETS.night);
  assert.equal(theme.primary, "#abcdef");
  assert.equal(theme.accent, THEME_PRESETS.night.accent);
  assert.deepEqual(Object.keys(theme), ["ground", "surface", "paper", "ink", "muted", "primary", "secondary", "accent"]);
});

test("object color overrides every inherited source", () => {
  const { document, engine } = colorFixture({ groupModes: { "group:active": "show" } });
  assert.equal(resolveObjectColor({
    document,
    engine,
    object: { id: "event:todo", traits: ["todo"], display: { color: "#abcdef" } },
    activeFrame: "calendar:active"
  }), "#abcdef");
});

test("an active group overrides a larger group", () => {
  const { document, engine } = colorFixture({ groupModes: { "group:active": "show" } });
  assert.equal(resolveObjectColor({
    document,
    engine,
    object: { id: "event:note", traits: ["note"] },
    activeFrame: "calendar:active"
  }), "#555555");
});

test("the largest group wins when no group is active", () => {
  const { document, engine } = colorFixture();
  assert.equal(resolveObjectColor({
    document,
    engine,
    object: { id: "event:one" },
    activeFrame: "calendar:active"
  }), "#444444");
});

// The exact field-report symptom: "converting a group named 'important' to
// the legacy importance kind ... stops it coloring its events." Step 2 of the
// cascade must see an importance frame's membership the same way it sees any
// other group's.
test("an importance frame colors its events, same as an ordinary group", () => {
  const { document, engine } = colorFixture();
  document.frames["frame:importance-high"] = {
    id: "frame:importance-high", traits: ["set", "group", "importance"], color: "#663399"
  };
  engine.eventDisplayGroupMemberships = () => [{ group: "frame:importance-high" }];
  engine.displayGroupEventMembers = (groupId) => groupId === "frame:importance-high" ? [1] : [];
  assert.equal(resolveObjectColor({
    document,
    engine,
    object: { id: "event:one" },
    activeFrame: "calendar:active"
  }), "#663399");
});

// AGENTS.md's step 2 tie-breaks (explicitly-shown group wins, then most
// members, then authored order) must hold exactly the same way once an
// importance frame is one of the candidates in the pool -- it is not a
// special case the cascade treats differently.
test("the documented tie-breaks hold with an importance frame in the pool", () => {
  const { document, engine } = colorFixture({ groupModes: { "group:active": "show" } });
  document.frames["frame:importance-mid"] = {
    id: "frame:importance-mid", traits: ["set", "group", "importance"], color: "#a0522d"
  };
  const memberships = ["group:small", "frame:importance-mid", "group:large", "group:active"];
  const sizes = { "group:small": 2, "frame:importance-mid": 7, "group:large": 12, "group:active": 1 };
  engine.eventDisplayGroupMemberships = () => memberships.map((group) => ({ group }));
  engine.displayGroupEventMembers = (group) => Array.from({ length: sizes[group] });

  // An explicitly-shown group still wins over every other candidate,
  // importance frame included.
  assert.equal(resolveObjectColor({
    document, engine, object: { id: "event:note" }, activeFrame: "calendar:active"
  }), "#555555");

  // With nothing explicitly shown, the largest membership wins -- here that is
  // the ordinary group, not the importance frame, which must not be favored
  // just for being an importance frame.
  const { document: plainDocument, engine: plainEngine } = colorFixture();
  plainDocument.frames["frame:importance-mid"] = document.frames["frame:importance-mid"];
  plainEngine.eventDisplayGroupMemberships = () => memberships.map((group) => ({ group }));
  plainEngine.displayGroupEventMembers = (group) => Array.from({ length: sizes[group] });
  assert.equal(resolveObjectColor({
    document: plainDocument, engine: plainEngine, object: { id: "event:one" }, activeFrame: "calendar:active"
  }), "#444444", "the largest group still wins even though an importance frame is among the candidates");
});

test("active and rendered temporal frames provide ordered fallbacks", () => {
  const { document, engine } = colorFixture();
  engine.eventDisplayGroupMemberships = () => [];
  assert.equal(resolveObjectColor({
    document,
    engine,
    object: { id: "event:one" },
    activeFrame: "calendar:active",
    displayFrame: "calendar:source"
  }), "#111111");

  engine.eventFrames = () => ["calendar:source"];
  assert.equal(resolveObjectColor({
    document,
    engine,
    object: { id: "event:one" },
    activeFrame: "calendar:active",
    displayFrame: "calendar:source"
  }), "#222222");
});

test("AGENTS.md documents all shipping lenses and the contrast rule", async () => {
  const document = await readFile(new URL("../AGENTS.md", import.meta.url), "utf8");
  for (const lens of ["Intimate", "Tactical", "Strategic", "Wall", "Lines", "Spiral", "Radial"]) assert.match(document, new RegExp(lens));
  assert.match(document, /sole carrier/i);
  assert.match(document, /Object color inheritance/);
  assert.match(document, /group with the most event members wins/i);
});

// The 8.19 weight-as-formula wave rewired `factImportanceWeight` from an
// unordered Set-of-frames multiplication into a canonical-order fold of each
// contributing frame's weight *formula*. This is the headline regression
// guard for that rewrite: a document nobody has authored a formula on --
// plain numbers or nothing at all, exactly what every existing document
// contains -- must produce the bit-identical weight and the bit-identical
// three-string verdict it always has.
test("REGRESSION GUARD: plain numeric weights (and absent weights) compose to the exact same weight and verdict as before formulas existed", () => {
  const event = { id: "event:multi", traits: ["event"] };
  const { document, engine } = weightFixture({
    frames: {
      "frame:a": { id: "frame:a", traits: ["set", "group"], display: { weight: 2 } },
      "frame:b": { id: "frame:b", traits: ["set", "group"], display: { weight: 0.5 } },
      "frame:c": { id: "frame:c", traits: ["set", "group"] } // no display.weight authored at all
    },
    memberships: ["frame:a", "frame:b", "frame:c"]
  });
  const context = { document, engine };
  const fact = { event };
  // 1 (standard base) * 2 * 0.5 * 1 (unauthored -> identity) = 1, the exact
  // product the old unordered multiplicative model produced -- multiplication
  // commutes, so canonical ordering changes nothing here, which is the point.
  assert.equal(factImportanceWeight(context, fact), 1);
  assert.equal(factImportance(context, fact), "standard");

  // The three-string verdict space itself: legacy trait strings still take
  // the same base weight they always have, unaffected by the formula rewrite.
  const legacy = { id: "event:legacy", traits: ["event", "landmark"] };
  assert.equal(factImportance({ document: { frames: {} }, engine: { eventFrames: () => [], eventDisplayGroupMemberships: () => [] } }, { event: legacy }), "landmark");
});

test("explainFactWeight: steps appear in canonical order with correct intermediate values, and the order is provably real", () => {
  const event = { id: "event:one", traits: ["event"] };
  const { document, engine } = weightFixture({
    frames: {
      "frame:add": { id: "frame:add", traits: ["set", "group"], title: "Additive", display: { weight: "w + 1" } },
      "frame:mul": { id: "frame:mul", traits: ["set", "group"], title: "Multiplier", display: { weight: "w * 2" } }
    },
    memberships: ["frame:add", "frame:mul"]
  });
  // frame:add has the larger membership, so canonical order (larger group
  // applies first, see src/weight-formula.js's weightContributionOrder)
  // applies frame:add's "+1" before frame:mul's "*2".
  engine.displayGroupEventMembers = (id) => Array.from({ length: id === "frame:add" ? 10 : 1 });
  const context = { document, engine };
  const explanation = explainFactWeight(context, { event });
  assert.equal(explanation.base, 1);
  assert.equal(explanation.baseVerdict, "standard");
  assert.deepEqual(explanation.steps.map((step) => step.frame), ["frame:add", "frame:mul"]);
  assert.equal(explanation.steps[0].title, "Additive");
  assert.equal(explanation.steps[0].from, 1);
  assert.equal(explanation.steps[0].to, 2, "1 + 1 = 2");
  assert.equal(explanation.steps[1].title, "Multiplier");
  assert.equal(explanation.steps[1].from, 2);
  assert.equal(explanation.steps[1].to, 4, "2 * 2 = 4");
  assert.equal(explanation.final, 4);
  assert.equal(explanation.verdict, "landmark");
  assert.equal(factImportanceWeight(context, { event }), 4, "factImportanceWeight agrees with explainFactWeight's final value");

  // Prove order is real, not incidental: making frame:mul the larger group
  // instead reverses the fold order and produces the OTHER answer these same
  // two formulas can give -- mixed +/x genuinely does not commute.
  engine.displayGroupEventMembers = (id) => Array.from({ length: id === "frame:mul" ? 10 : 1 });
  const reordered = explainFactWeight(context, { event });
  assert.deepEqual(reordered.steps.map((step) => step.frame), ["frame:mul", "frame:add"]);
  assert.equal(reordered.final, 3, "1 * 2 + 1 = 3, the other answer, proving the fold order is not commutative");
  assert.notEqual(reordered.final, explanation.final);
});

test("renderers apply the shared sigil data contract to block, pip, line, and radial marks", async () => {
  const [renderers, css] = await Promise.all([
    readFile(new URL("../src/projections.js", import.meta.url), "utf8"),
    readFile(new URL("../src/app.css", import.meta.url), "utf8")
  ]);
  assert.match(renderers, /function applySigil/);
  assert.match(renderers, /node\.dataset\.sigil = sigil/);
  assert.match(renderers, /radial-event-arc.*sigil/s);
  assert.match(css, /\.event-pip\[data-sigil="milestone"\]/);
  assert.match(css, /\.line-event\[data-sigil="repeat"\]/);
});
