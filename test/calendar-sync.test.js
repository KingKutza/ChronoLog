import test from "node:test";
import assert from "node:assert/strict";
import { applyICSSnapshot, calendarSyncConnections } from "../src/calendar-sync.js";
import { createSampleDocument } from "./helpers/sample-document.js";
import { addEvent, addRelation, stapleEvents, validateDocument } from "../src/model.js";

function calendar(...components) {
  return [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//ChronoLog tests//EN",
    "X-WR-CALNAME:Web calendar",
    ...components,
    "END:VCALENDAR",
    ""
  ].join("\r\n");
}

function event(uid, title, start = "20260816T120000Z") {
  return ["BEGIN:VEVENT", `UID:${uid}`, `SUMMARY:${title}`, `DTSTART:${start}`, "DTEND:20260816T130000Z", "END:VEVENT"].join("\r\n");
}

function sourceCalendar(sourceId, title, component) {
  return ["BEGIN:VCALENDAR", "VERSION:2.0", `X-WR-CALNAME:${title}`, `X-CHRONOLOG-SOURCE-ID:${sourceId}`, component, "END:VCALENDAR"].join("\r\n");
}

test("an ICS snapshot refresh updates stable source records and removes remote deletions", () => {
  const document = createSampleDocument({ includeEvents: false });
  const first = applyICSSnapshot(document, {
    connectionId: "feed:work", text: calendar(event("one", "First"), event("two", "Second")), revision: "v1"
  });
  assert.equal(first.events, 2);
  const firstId = Object.values(document.events).find((item) => item.payload?.uid === "one").id;
  const deletedId = Object.values(document.events).find((item) => item.payload?.uid === "two").id;
  const frameId = first.frames[0];

  const second = applyICSSnapshot(document, {
    connectionId: "feed:work", text: calendar(event("one", "First updated")), revision: "v2"
  });
  assert.equal(second.frames[0], frameId);
  assert.equal(document.events[firstId].payload.title, "First updated");
  assert.equal(document.events[deletedId], undefined);
  assert.equal(calendarSyncConnections(document)[0].revision, "v2");
  const validation = validateDocument(document);
  assert.equal(validation.valid, true, validation.errors.join("\n"));
});

test("refreshing a stapled remote event updates its source copy without replacing the authored event", () => {
  const document = createSampleDocument({ includeEvents: false });
  const synced = applyICSSnapshot(document, {
    connectionId: "feed:shared", text: calendar(event("shared", "Remote title"))
  });
  const imported = Object.values(document.events).find((item) => item.payload?.uid === "shared");
  const authored = addEvent(document, { payload: { title: "My overlay", uid: "local-shared" } });
  addRelation(document, {
    type: "attachment", event: authored.id, frame: "calendar:personal", role: "placed",
    coordinate: { levels: [{ level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: "16" }] }
  });
  stapleEvents(document, [authored.id, imported.id]);

  applyICSSnapshot(document, {
    connectionId: "feed:shared", text: calendar(event("shared", "Remote title changed"))
  });
  assert.equal(document.events[authored.id].payload.title, "My overlay");
  assert.equal(document.events[authored.id].foreign.stapled[0].payload.title, "Remote title changed");
  assert.ok(Object.values(document.relations).some((relation) =>
    relation.event === authored.id && relation.frame === synced.frames[0] && relation.provenance?.kind === "ics"
  ));
  const validation = validateDocument(document);
  assert.equal(validation.valid, true, validation.errors.join("\n"));
});

test("repeated pulls of an unchanged feed do not accumulate duplicate shared ICS sources or components", () => {
  const document = createSampleDocument({ includeEvents: false });
  const text = calendar(event("one", "First"), event("two", "Second"));
  applyICSSnapshot(document, { connectionId: "feed:steady", text, revision: "v1" });
  const sourceId = Object.keys(document.foreign.ics.sources)[0];
  const componentsAfterFirst = Object.keys(document.foreign.ics.sources[sourceId].components).length;

  // Ten repeats of the exact same feed content -- the reconciler's whole-record
  // replace-or-delete invariant (src/calendar-sync.js) means each pull assigns
  // a brand-new source object wholesale rather than merging into the old one,
  // so nothing here should ever accumulate.
  for (let i = 0; i < 10; i += 1) {
    applyICSSnapshot(document, { connectionId: "feed:steady", text, revision: `v${i + 2}` });
  }

  assert.equal(Object.keys(document.foreign.ics.sources).length, 1, "still exactly one shared source");
  // The reconciler keeps the source id stable across pulls (that stability is
  // what lets frames/patterns survive a refresh) -- what must not happen is a
  // second source id appearing alongside it, or its component bucket growing.
  assert.ok(document.foreign.ics.sources[sourceId], "the same source id is reused, not replaced by a new one");
  assert.equal(
    Object.keys(document.foreign.ics.sources[sourceId].components).length,
    componentsAfterFirst,
    "the shared component bucket holds exactly one entry per event, not one per pull"
  );
  assert.equal(Object.keys(document.events).length, 2, "no duplicate events either");
  const validation = validateDocument(document);
  assert.equal(validation.valid, true, validation.errors.join("\n"));
});

test("a snapshot that fails to parse leaves the source revision and shared components untouched", () => {
  const document = createSampleDocument({ includeEvents: false });
  applyICSSnapshot(document, {
    connectionId: "feed:flaky", text: calendar(event("one", "First")), revision: "v1"
  });
  const before = JSON.parse(JSON.stringify(document.foreign.ics));
  assert.throws(() => applyICSSnapshot(document, {
    connectionId: "feed:flaky", text: "not an ICS payload at all", revision: "v2"
  }));
  assert.deepEqual(document.foreign.ics, before, "a failed parse commits nothing -- revision only advances after a successful parse");
});

test("provider calendar IDs keep frames stable when a multi-calendar response changes order", () => {
  const document = createSampleDocument({ includeEvents: false });
  applyICSSnapshot(document, {
    connectionId: "feed:multi-calendar",
    text: `${sourceCalendar("calendar-a", "A", event("a", "A event"))}\r\n${sourceCalendar("calendar-b", "B", event("b", "B event"))}\r\n`
  });
  const sourceA = Object.values(document.foreign.ics.sources).find((source) => source.sync.calendarKey === "calendar-a");
  const frameA = Object.values(document.frames).find((frame) => frame.foreign?.ics?.source === sourceA.id);
  const eventA = Object.values(document.events).find((item) => item.payload?.uid === "a");
  applyICSSnapshot(document, {
    connectionId: "feed:multi-calendar",
    text: `${sourceCalendar("calendar-b", "B", event("b", "B event"))}\r\n${sourceCalendar("calendar-a", "A", event("a", "A event updated"))}\r\n`
  });
  assert.equal(Object.values(document.frames).find((frame) => frame.foreign?.ics?.source === sourceA.id).id, frameA.id);
  assert.equal(document.events[eventA.id].payload.title, "A event updated");
  const validation = validateDocument(document);
  assert.equal(validation.valid, true, validation.errors.join("\n"));
});
