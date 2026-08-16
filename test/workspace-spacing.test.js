import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

function cssBlock(css, selector) {
  const escaped = selector.replace(/[.#[\]"=-]/g, "\\$&");
  const match = css.match(new RegExp(`(?:^|\\n)${escaped}\\s*\\{[^}]*\\}`));
  assert.ok(match, `expected a CSS block for ${selector}`);
  return match[0];
}

test("workspace chrome uses centralized outer and inner spacing relationships", async () => {
  const css = await readFile("src/app.css", "utf8");
  const root = cssBlock(css, ":root");

  assert.match(root, /--workspace-outer:\s*12px/);
  assert.match(root, /--workspace-inner:\s*8px/);
  assert.match(root, /--workspace-stack-height:/);
  assert.match(root, /--workspace-projection-top:/);

  for (const selector of ["#hud", "#lens-bar", "#lens-controls"]) {
    const block = cssBlock(css, selector);
    assert.match(block, /var\(--workspace-outer\)/);
    assert.match(block, /var\(--workspace-(?:primary|control)-row\)/);
  }

  const viewport = cssBlock(css, "#viewport");
  assert.match(viewport, /padding:\s*var\(--workspace-projection-top\) var\(--workspace-outer\) var\(--workspace-outer\)/);

  const minimap = cssBlock(css, "#minimap");
  assert.match(minimap, /right:\s*var\(--workspace-outer\)/);
  assert.match(minimap, /top:\s*var\(--workspace-minimap-top\)/);
  assert.match(minimap, /height:\s*var\(--workspace-minimap-height\)/);

  assert.doesNotMatch(css, /#lens-controls\s*\{[^}]*top:\s*\d+px/);
  assert.doesNotMatch(css, /#minimap\s*\{[^}]*top:\s*\d+px/);
  assert.match(css, /@media \(max-width: 780px\)[\s\S]*--workspace-outer:\s*7px/);
  assert.match(css, /@media \(max-width: 780px\)[\s\S]*--workspace-inner:\s*6px/);
});
