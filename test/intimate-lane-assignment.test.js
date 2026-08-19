import assert from "node:assert/strict";
import test from "node:test";
import { renderProjection } from "../src/projections.js";
import { ChronologEngine } from "../src/engine.js";
import { ViewSession } from "../src/session.js";
import { addEvent, addFrame, addRelation, durationMagnitude } from "../src/model.js";
import { daysFromCivil } from "../src/exact.js";
import { createStructuralDocument } from "./helpers/sample-document.js";

// The 8.19 field report's item 2, in the owner's words: "When swapping primary
// frames between my work calendar and the US Holidays calendar, if I let
// holidays be primary, all work events would overlap at the right of the day
// column. Swapping between Moon/Astro and Work, moon Astro piles half width on
// the right of the day column when it is not primary."
//
// Root cause: renderIntimate's day-column lane assignment (src/projections.js)
// keyed a fact's lane group on `displayLayer` ("base" for the primary frame,
// "included" for every companion) rather than on overlap alone. Companion
// facts got their own, independent `assignLanes` pass and a fixed
// shrinking-width formula (`right: 3 + lane*9px`, `width: max(18, 36 -
// lane*5)%`) that never consulted what the primary's facts actually occupied
// -- so a companion frame's events piled into one narrow strip regardless of
// how many of them there were, and swapping which frame is primary moved an
// event between that strip and the ordinary proportional layout even though
// nothing about its temporal overlap changed. Every selected frame overlays
// equally (src/frame-selection.js), so lane assignment must be frame-agnostic
// and depend only on temporal overlap -- this is the regression pin for that
// rule.

// A stub DOM element good enough to run renderIntimate: plain property
// assignment stands in for CSSStyleDeclaration (renderIntimate never reads a
// style property back, only ever writes `.style.foo = ...`, so a plain object
// round-trips it fine), plus the dataset/children/classList surface Intimate
// actually touches.
class StubElement {
  constructor(tag) {
    this.tagName = String(tag).toUpperCase();
    this.className = "";
    this.textContent = "";
    this.dataset = {};
    this.children = [];
    this.parentElement = null;
    this.clientHeight = 900;
    const node = this;
    this.style = {
      setProperty(name, value) { this[name] = String(value); },
      getPropertyValue(name) { return this[name] ?? ""; }
    };
    this.classList = { add(cls) { node.className = node.className ? `${node.className} ${cls}` : cls; } };
  }

  append(...nodes) {
    for (const node of nodes) {
      node.parentElement = this;
      this.children.push(node);
    }
  }

  replaceChildren(...nodes) {
    this.children = [];
    this.append(...nodes);
  }

  setAttribute() {}
  getAttribute() { return null; }
  querySelector() { return null; }
}

function collect(node, out = []) {
  out.push(node);
  for (const child of node.children || []) collect(child, out);
  return out;
}

function buildDocument() {
  const chronologDocument = createStructuralDocument();
  addFrame(chronologDocument, {
    id: "calendar:work", title: "Work", traits: ["set", "calendar"], basis: "frame:wall-time"
  });
  addFrame(chronologDocument, {
    id: "calendar:holidays", title: "US Holidays", traits: ["set", "calendar"], basis: "frame:wall-time"
  });
  const day = daysFromCivil(2026n, 8n, 19n);
  const work = addEvent(chronologDocument, {
    id: "event:work-meeting",
    traits: ["event", "work"],
    magnitudes: { duration: durationMagnitude("60", "minute") },
    payload: { title: "Work meeting" }
  });
  addRelation(chronologDocument, {
    id: "relation:work-meeting",
    type: "attachment",
    event: work.id,
    frame: "calendar:work",
    role: "placed",
    coordinate: {
      levels: [
        { level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "19" },
        { level: "hour", value: "9" }, { level: "minute", value: "0" }
      ]
    }
  });
  const holiday = addEvent(chronologDocument, {
    id: "event:holiday-thing",
    traits: ["event"],
    magnitudes: { duration: durationMagnitude("60", "minute") },
    payload: { title: "Holiday overlap" }
  });
  addRelation(chronologDocument, {
    id: "relation:holiday-thing",
    type: "attachment",
    event: holiday.id,
    frame: "calendar:holidays",
    role: "placed",
    coordinate: {
      levels: [
        { level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "19" },
        { level: "hour", value: "9" }, { level: "minute", value: "30" }
      ]
    }
  });
  return { chronologDocument, day, workId: work.id, holidayId: holiday.id };
}

function renderIntimateLaneButtons({ chronologDocument, day, primary, companion }) {
  const engine = new ChronologEngine(chronologDocument);
  const session = new ViewSession({
    projection: "calendar",
    scale: 0,
    activeFrame: primary,
    companionFrames: [companion],
    intimateBack: 0,
    intimateForward: 0,
    focusDays: day.toString()
  });
  const target = new StubElement("div");
  const previousDocument = globalThis.document;
  globalThis.document = { createElement: (tag) => new StubElement(tag) };
  try {
    renderProjection(target, { document: chronologDocument, engine, session, loading: false });
  } finally {
    globalThis.document = previousDocument;
  }
  const byEvent = new Map();
  for (const node of collect(target)) {
    if (node.dataset?.eventId) byEvent.set(node.dataset.eventId, node);
  }
  return byEvent;
}

test("Intimate lane assignment does not depend on which selected frame is primary", () => {
  const { chronologDocument, day, workId, holidayId } = buildDocument();

  const workPrimary = renderIntimateLaneButtons({
    chronologDocument, day, primary: "calendar:work", companion: "calendar:holidays"
  });
  const holidayPrimary = renderIntimateLaneButtons({
    chronologDocument, day, primary: "calendar:holidays", companion: "calendar:work"
  });

  const workAsPrimary = workPrimary.get(workId);
  const holidayAsCompanion = workPrimary.get(holidayId);
  const workAsCompanion = holidayPrimary.get(workId);
  const holidayAsPrimary = holidayPrimary.get(holidayId);

  assert.ok(workAsPrimary && holidayAsCompanion && workAsCompanion && holidayAsPrimary, "both events render in both arrangements");

  // The whole claim: the same fact gets the same lane geometry whether it
  // came from the primary frame or a companion.
  assert.equal(workAsPrimary.style.left, workAsCompanion.style.left,
    "the work event's lane position is unchanged by whether it is primary");
  assert.equal(workAsPrimary.style.width, workAsCompanion.style.width);
  assert.equal(holidayAsCompanion.style.left, holidayAsPrimary.style.left,
    "the holiday event's lane position is unchanged by whether it is primary");
  assert.equal(holidayAsCompanion.style.width, holidayAsPrimary.style.width);

  // Neither ever falls into the old right-anchored companion strip.
  for (const button of [workAsPrimary, holidayAsCompanion, workAsCompanion, holidayAsPrimary]) {
    assert.equal(button.style.right, undefined, "a timed event is never right-anchored by displayLayer alone");
  }

  // And overlap is actually honoured: two overlapping timed events split the
  // column into two lanes, not stacked on top of each other.
  assert.equal(workAsPrimary.style.left, "0%");
  assert.equal(holidayAsCompanion.style.left, "50%");
  assert.equal(workAsPrimary.style.width, "calc(50% - 3px)");
  assert.equal(holidayAsCompanion.style.width, "calc(50% - 3px)");
});
