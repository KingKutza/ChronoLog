import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

test("responsive workspace keeps every toolbar action reachable without minimap overlap", async () => {
  const [html, css, app] = await Promise.all([
    readFile("pocket-instrument.html", "utf8"),
    readFile("src/app.css", "utf8"),
    readFile("src/app.js", "utf8")
  ]);

  assert.match(css, /--workspace-control-edge:\s*min\(720px, 50%\)/);
  assert.match(css, /width:\s*calc\(var\(--workspace-control-edge\) - var\(--workspace-outer\) - var\(--workspace-inner-half\)\)/);
  assert.match(css, /@media \(max-width: 1400px\)[\s\S]*#save-status[\s\S]*font-size:\s*0/);
  assert.match(css, /@media \(max-width: 1000px\)[\s\S]*#minimap \{ left: var\(--workspace-outer\); right: var\(--workspace-outer\); \}/);
  assert.match(css, /@media \(max-width: 520px\)[\s\S]*\.responsive-label-short \{ display: inline; \}/);

  assert.match(html, /id="manage-frames"[^>]*aria-controls="inspector"/);
  assert.match(html, /id="create-menu"[\s\S]*id="new-todo"[\s\S]*id="new-note"/);
  assert.match(css, /#create-menu > summary[\s\S]*width: 34px/);
  assert.match(html, /data-lens="strategic" aria-label="Strategic"/);
  assert.match(app, /toggleFramesBrowser\(returnTarget\)/);
  assert.match(app, /framesReturnTarget/);
  assert.match(app, /Save status: \$\{status\.message\}/);
});
