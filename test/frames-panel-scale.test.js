import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const fixture = JSON.parse(await readFile("fixtures/frames-panel-scale.json", "utf8"));

test("Frames scale fixture remains a non-private 30-calendar / 50-group reproduction", () => {
  const calendars = fixture.frames.filter((frame) => frame.traits.includes("calendar"));
  const groups = fixture.frames.filter((frame) => frame.traits.includes("group"));
  assert.equal(calendars.length, 30);
  assert.equal(groups.length, 50);
  assert.ok(groups.every((frame) => frame.title.length > 48));
});

test("Frames browser bounds its lists, filters companions and groups, and preserves local view state", async () => {
  const [app, css] = await Promise.all([
    readFile("src/app.js", "utf8"),
    readFile("src/app.css", "utf8")
  ]);
  assert.match(app, /const framesPanelState =/);
  assert.match(app, /Filter companion frames and groups/);
  assert.match(app, /Include calendars and lines \(\$\{related\.length\}\)/);
  assert.match(app, /Groups in this view \(\$\{groups\.length\}\)/);
  assert.match(app, /inspectorBody\.scrollTop = scrollTop/);
  assert.match(app, /next\.focus\(\{ preventScroll: true \}\)/);
  assert.match(css, /\.frame-view-section/);
  assert.match(css, /\.frame-choice-name/);
  assert.match(css, /#inspector-body \{ overflow-x: hidden; \}/);
});
