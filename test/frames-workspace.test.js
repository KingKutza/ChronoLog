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
