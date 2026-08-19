import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  SIGIL_VOCABULARY,
  THEME_PRESETS,
  factImportance,
  normalizeTheme,
  resolveObjectColor,
  sigilForFact
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
