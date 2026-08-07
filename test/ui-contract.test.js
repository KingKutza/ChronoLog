import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

test("application shell keeps data, session, projections, and page scrolling separate", async () => {
  const [html, css, app, projections] = await Promise.all([
    readFile("pocket-instrument.html", "utf8"),
    readFile("src/app.css", "utf8"),
    readFile("src/app.js", "utf8"),
    readFile("src/projections.js", "utf8")
  ]);
  assert.match(html, /id="scale-rail"/);
  assert.match(html, /id="projection-dial"/);
  assert.match(html, /id="minimap"/);
  assert.match(css, /html,\s*\nbody,\s*\n#app[\s\S]*overflow: hidden/);
  assert.match(css, /grid-template-rows: repeat\(3, minmax\(0, 1fr\)\)/);
  assert.match(app, /sharedFocus/);
  assert.match(app, /session\.projection === "radial"/);
  assert.match(projections, /radialPast/);
  assert.doesNotMatch(app, /localStorage/);
});
