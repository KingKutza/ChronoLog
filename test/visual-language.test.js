import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { SIGIL_VOCABULARY, THEME_PRESETS, normalizeTheme, sigilForFact } from "../src/visual-language.js";

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

test("visual grammar documents all shipping lenses and contrast rule", async () => {
  const document = await readFile(new URL("../docs/visual-grammar.md", import.meta.url), "utf8");
  for (const lens of ["Intimate", "Tactical", "Strategic", "Wall", "Lines", "Spiral", "Radial"]) assert.match(document, new RegExp(lens));
  assert.match(document, /sole carrier/i);
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
