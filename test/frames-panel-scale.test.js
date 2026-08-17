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
