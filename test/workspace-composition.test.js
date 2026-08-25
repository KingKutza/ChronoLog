import test from "node:test";
import assert from "node:assert/strict";
import { ViewSession, DEFAULT_LENS_ORDER, normalizeLensWorkspace } from "../src/session.js";
import { ChronologEngine } from "../src/engine.js";
import { addEvent, addFrame, addRelation, createDocument, daysToCoordinate, durationMagnitude, coordinateToDays, validateDocument } from "../src/model.js";
import { coordinate } from "../src/exact.js";

test("lens workspace persists a filtered order, restores defaults, and never loses a reachable lens", () => {
  // The constructor is the persisted-workspace path, where the catalog-growth
  // migration applies: a catalog lens the persisted order has never seen is
  // appended VISIBLE (a genuinely new lens must reach existing users), so a
  // fixture that wants only "lines" visible must persist the whole order and
  // hide the rest -- exactly what a real saved workspace does.
  const session = new ViewSession({
    lensOrder: ["lines", ...DEFAULT_LENS_ORDER.filter((lens) => lens !== "lines")],
    enabledLenses: ["lines"]
  });
  assert.deepEqual(session.availableLenses(), ["lines"]);
  session.setLens("intimate");
  assert.equal(session.currentLens(), "tactical", "disabled lenses cannot be selected");
  // Live reconfiguration never migrates: the caller's word is the whole
  // workspace, so an empty enabled set falls back to the first ordered lens.
  session.configureLenses({ lensOrder: ["radial", "lines"], enabledLenses: [] });
  assert.deepEqual(session.availableLenses(), ["radial"]);
  session.restoreDefaultLenses();
  assert.deepEqual(session.availableLenses(), DEFAULT_LENS_ORDER);
  assert.deepEqual(normalizeLensWorkspace({ lensOrder: ["bogus", "wall", "wall"] }).lensOrder.slice(0, 2), ["wall", "intimate"]);
});

test("terrestrial calendar sets share a coordinate definition without copying it", () => {
  const document = createDocument();
  addFrame(document, { id: "line:earth", title: "Earth", traits: ["line", "gregorian"], coordinate: { kind: "gregorian" } });
  addFrame(document, { id: "calendar:work", title: "Work", traits: ["set", "calendar"], coordinateDefinition: "line:earth" });
  addFrame(document, { id: "calendar:personal", title: "Personal", traits: ["set", "calendar"], coordinateDefinition: "line:earth" });
  const value = coordinate([{ level: "year", value: "2032" }, { level: "month", value: "2" }, { level: "day", value: "29" }]);
  assert.equal(coordinateToDays(document, "calendar:work", value).toJSON(), coordinateToDays(document, "calendar:personal", value).toJSON());
  assert.deepEqual(daysToCoordinate(document, "calendar:work", coordinateToDays(document, "line:earth", value)), value);
  assert.equal(validateDocument(document).valid, true);
});

test("group inclusion spans authored, query, and nested membership across companion calendars", () => {
  const document = createDocument();
  addFrame(document, { id: "line:earth", title: "Earth", traits: ["line", "gregorian"], coordinate: { kind: "gregorian" } });
  addFrame(document, { id: "calendar:work", title: "Work", traits: ["set", "calendar"], coordinateDefinition: "line:earth" });
  addFrame(document, { id: "calendar:personal", title: "Personal", traits: ["set", "calendar"], coordinateDefinition: "line:earth" });
  addFrame(document, { id: "group:project", title: "Project", traits: ["set", "group"] });
  addFrame(document, { id: "group:umbrella", title: "Umbrella", traits: ["set", "group"], query: { groups: ["group:project"] } });
  const event = addEvent(document, { id: "event:work", payload: { title: "A work thing" }, traits: [], magnitudes: { duration: durationMagnitude("1", "hour", "line:earth") } });
  addRelation(document, { id: "relation:time", type: "attachment", event: event.id, frame: "calendar:work", coordinate: coordinate([{ level: "year", value: "2030" }, { level: "month", value: "1" }, { level: "day", value: "1" }]) });
  addRelation(document, { id: "relation:member", type: "membership", group: "group:project", member: event.id });
  const engine = new ChronologEngine(document);
  assert.deepEqual(engine.groupEventMembers("group:umbrella"), [event.id]);
  assert.deepEqual(engine.eventCalendarFrames(event.id), ["calendar:work"]);
});
