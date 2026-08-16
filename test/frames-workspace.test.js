import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const fixture = JSON.parse(await readFile("fixtures/frames-workspace-contract.json", "utf8"));

test("Frames workspace fixture keeps leading coordinates, display companions, and groups distinct", () => {
  assert.equal(fixture.leading, "calendar:earth");
  assert.ok(fixture.companions.every((id) => /^(calendar|line):/.test(id)));
  assert.ok(fixture.groups.every((id) => id.startsWith("group:")));
  assert.deepEqual(fixture.invariants, [
    "groups are not coordinate systems",
    "companions are display selections, not coordinate mappings",
    "frame capabilities compose rather than replace existing traits"
  ]);
});

test("Frames workspace UI makes the hierarchy and advanced boundary explicit", async () => {
  const [app, css] = await Promise.all([
    readFile("src/app.js", "utf8"),
    readFile("src/app.css", "utf8")
  ]);
  assert.match(app, /Leading frame — primary coordinates/);
  assert.match(app, /Companions projected with/);
  assert.match(app, /Groups in this workspace/);
  assert.match(app, /groups organise event membership and never become temporal coordinates/i);
  assert.match(app, /coordinate definition names positions inside this frame/i);
  assert.match(app, /This adds a capability; it never removes/);
  assert.match(app, /Frame definitions and organisational objects/);
  assert.match(css, /\.frame-object-guide/);
  assert.match(css, /\.coordinate-definition-note/);
});
