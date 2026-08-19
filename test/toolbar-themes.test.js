import assert from "node:assert/strict";
import test from "node:test";
import {
  normalizeNamedThemes,
  removeNamedTheme,
  upsertNamedTheme
} from "../src/ui/toolbar.js";
import { THEME_PRESETS } from "../src/visual-language.js";

// Owner item 13: "Color Themes ... when I save I can not save as a new named
// theme but must override an existing theme." Named themes are a plain
// name -> 8-field-palette map, kept separate from THEME_PRESETS' two
// built-ins and from the single "currently applied" theme
// (chronolog:color-theme:1). These are the pure, DOM-free storage-shape
// functions toolbar.js's localStorage wrappers call through.

test("saving under an unused name adds a new theme rather than replacing one", () => {
  let themes = upsertNamedTheme({}, "Dusk trail", THEME_PRESETS.night);
  assert.deepEqual(Object.keys(themes), ["Dusk trail"]);
  themes = upsertNamedTheme(themes, "Morning glare", THEME_PRESETS.paper);
  assert.deepEqual(Object.keys(themes).sort(), ["Dusk trail", "Morning glare"], "the first theme survives — saving as new never overwrites another");
});

test("saving under a name already in use overwrites only that entry", () => {
  let themes = upsertNamedTheme({}, "Dusk trail", THEME_PRESETS.night);
  themes = upsertNamedTheme(themes, "Morning glare", THEME_PRESETS.paper);
  const edited = { ...THEME_PRESETS.night, primary: "#123456" };
  themes = upsertNamedTheme(themes, "Dusk trail", edited);
  assert.equal(themes["Dusk trail"].primary, "#123456", "the named theme took the new palette");
  assert.equal(themes["Morning glare"].primary, THEME_PRESETS.paper.primary, "the other saved theme is untouched");
});

test("a blank or whitespace-only name is refused rather than saved under an empty key", () => {
  assert.deepEqual(upsertNamedTheme({}, "", THEME_PRESETS.paper), {});
  assert.deepEqual(upsertNamedTheme({}, "   ", THEME_PRESETS.paper), {});
});

test("a saved theme is normalized to the full 8-field palette, filling in fallbacks for garbage fields", () => {
  const themes = upsertNamedTheme({}, "Half-authored", { primary: "#ff0000", secondary: "not-a-color" });
  const saved = themes["Half-authored"];
  assert.equal(saved.primary, "#ff0000");
  assert.equal(saved.secondary, THEME_PRESETS.paper.secondary, "an invalid field falls back rather than persisting garbage");
  assert.ok(saved.ground && saved.surface && saved.paper && saved.ink && saved.muted && saved.accent, "every one of the 8 fields is present");
});

test("removing a saved theme drops only that name", () => {
  let themes = upsertNamedTheme({}, "Dusk trail", THEME_PRESETS.night);
  themes = upsertNamedTheme(themes, "Morning glare", THEME_PRESETS.paper);
  themes = removeNamedTheme(themes, "Dusk trail");
  assert.deepEqual(Object.keys(themes), ["Morning glare"]);
  // Removing an unknown name is a no-op, not an error.
  assert.deepEqual(removeNamedTheme(themes, "Never saved"), themes);
});

test("normalizeNamedThemes drops blank-named entries and tolerates garbage input", () => {
  assert.deepEqual(normalizeNamedThemes(null), {});
  assert.deepEqual(normalizeNamedThemes("not an object"), {});
  const normalized = normalizeNamedThemes({ "": THEME_PRESETS.paper, "  ": THEME_PRESETS.paper, "Real name": THEME_PRESETS.night });
  assert.deepEqual(Object.keys(normalized), ["Real name"]);
});
