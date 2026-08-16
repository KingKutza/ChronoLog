import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  SIGIL_VOCABULARY,
  THEME_PRESETS,
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
    eventGroupMemberships: () => memberships.map((group) => ({ group })),
    groupEventMembers: (group) => Array.from({ length: sizes[group] }),
    eventFrames: () => ["calendar:source", "calendar:active"]
  };
  return { document, engine };
}

test("visual grammar maps structural event roles to stable sigils", () => {
  assert.equal(sigilForFact({ event: { traits: ["event"] } }), "point");
  assert.equal(sigilForFact({ event: { traits: ["event", "milestone"] } }), "milestone");
  assert.equal(sigilForFact({ event: { traits: ["event", "task"] } }), "task");
  assert.equal(sigilForFact({ event: { traits: ["event", "terminator"] } }), "terminator");
  assert.equal(sigilForFact({ event: { traits: ["event", "celestial"] } }), "celestial");
  assert.equal(sigilForFact({ event: { traits: ["event"] }, virtualId: "repeat:1" }), "repeat");
  assert.equal(sigilForFact({ event: { traits: ["event"] } }, 1440), "span");
  assert.equal(SIGIL_VOCABULARY.milestone.glyph, "◆");
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

test("active and rendered temporal frames provide ordered fallbacks", () => {
  const { document, engine } = colorFixture();
  engine.eventGroupMemberships = () => [];
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

test("visual grammar documents all shipping lenses and contrast rule", async () => {
  const document = await readFile(new URL("../docs/visual-grammar.md", import.meta.url), "utf8");
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
