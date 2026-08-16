import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { clone, createDocument, migrateDocument, validateDocument } from "../src/model.js";
import { parseDocument } from "../src/store.js";

const fixture = JSON.parse(await readFile(new URL("../fixtures/skyland-coordinate-mapping.chronolog.json", import.meta.url), "utf8"));

test("Skyland mapping records five Earth hours to nine Skyland days as an authored discontinuity", () => {
  const validation = validateDocument(fixture);
  assert.equal(validation.valid, true, validation.errors.join("\n"));
  const mapping = fixture.relations["mapping:earth-to-skyland-storm"];
  const anchor = mapping.anchors[0];
  assert.equal(mapping.direction, "forward");
  assert.equal(anchor.continuity, "discontinuous");
  assert.equal(anchor.from.interval.end.levels.at(-1).value, "17");
  assert.equal(anchor.from.interval.start.levels.at(-1).value, "12");
  assert.equal(anchor.to.interval.end.levels.at(-1).value, "81");
  assert.equal(anchor.to.interval.start.levels.at(-1).value, "72");
  assert.deepEqual(fixture.frames["line:skyland"].traits, ["line", "timeline", "calendar"]);
});

test("coordinate mappings require real frames, anchors, nested coordinates, and declared continuity", () => {
  const broken = clone(fixture);
  const mapping = broken.relations["mapping:earth-to-skyland-storm"];
  mapping.anchors[0].to.frame = "line:missing";
  mapping.anchors[0].continuity = "teleport";
  mapping.anchors[0].from.interval.start = { levels: [{ level: "hour", value: 12 }] };
  const errors = validateDocument(broken).errors.join("\n");
  assert.match(errors, /missing frame/);
  assert.match(errors, /target frame must match to/);
  assert.match(errors, /invalid continuity/);
  assert.match(errors, /interval start must use nested levels/);
});

test("prototype frame descriptors migrate loss-minimizingly on parse", () => {
  const legacy = createDocument("Legacy frame");
  legacy.frames["measure:human-time"] = { id: "measure:human-time", title: "Time", traits: ["measure"] };
  legacy.frames["frame:old"] = {
    id: "frame:old",
    title: "Old Skyland",
    traits: ["calendar"],
    basisFrame: "measure:human-time",
    coordinate: [{ name: "sky-day" }],
    cyclePeriodDays: "512"
  };
  const migrated = migrateDocument(legacy);
  assert.equal(migrated.frames["frame:old"].basis, "measure:human-time");
  assert.deepEqual(migrated.frames["frame:old"].coordinate, { kind: "nested", levels: [{ name: "sky-day" }] });
  assert.equal(migrated.frames["frame:old"].period.provenance.kind, "approximation");
  assert.equal(parseDocument(JSON.stringify(legacy)).frames["frame:old"].period.value.levels[0].value, "512");
});
