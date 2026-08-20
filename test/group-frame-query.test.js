import assert from "node:assert/strict";
import test from "node:test";
import { Rational, coordinate } from "../src/exact.js";
import { ChronologEngine } from "../src/engine.js";
import { addEvent, addFrame, addRelation, createEmptyWorkspaceDocument, durationMagnitude } from "../src/model.js";

// Field-measured defect: `queryFacts` on a GROUP frame returned zero facts while
// `groupEventMembers` on the same group returned them all. Don's live document
// has this on the Back-to-the-Future parent frame, whose members carry the
// attachments -- so the parent looked empty while every child had events.
//
// A group frame is not a coordinate space (AGENTS.md's frame model keeps the four
// concepts distinct), so it contributes MEMBERSHIP and ORDER and no arithmetic:
// each member's facts resolve under that member's OWN law and are unioned.

function civil(year, month, day, hour = 0) {
  return coordinate([
    { level: "year", value: String(year) },
    { level: "month", value: String(month) },
    { level: "day", value: String(day) },
    { level: "hour", value: String(hour) }
  ]);
}

function calendar(document, id, extra = {}) {
  return addFrame(document, {
    id, title: id, traits: ["set", "calendar"], basis: "frame:wall-time", ...extra
  });
}

function group(document, id, members, traits = ["set", "group"]) {
  addFrame(document, { id, title: id, traits });
  for (const member of members) {
    addRelation(document, {
      id: `membership:${member}@${id}`, type: "membership", group: id, member
    });
  }
}

function place(document, frameId, title, at) {
  const event = addEvent(document, {
    traits: ["event"],
    magnitudes: { duration: durationMagnitude("30", "minute") },
    payload: { title }
  });
  addRelation(document, {
    type: "attachment", role: "placed", event: event.id, frame: frameId, coordinate: at
  });
  return event;
}

function query(engine, frameId) {
  return engine.queryFacts({
    frame: frameId,
    start: civil(1950, 1, 1),
    end: civil(2030, 1, 1),
    limit: 500
  });
}

test("a parent group frame returns its members' facts, which is what the BTTF frame could not do", () => {
  const document = createEmptyWorkspaceDocument("BTTF");
  calendar(document, "calendar:1955");
  calendar(document, "calendar:1985");
  group(document, "frame:bttf", ["calendar:1955", "calendar:1985"]);
  place(document, "calendar:1955", "Lightning strikes the clock tower", civil(1955, 11, 12, 22));
  place(document, "calendar:1985", "The DeLorean hits 88", civil(1985, 10, 26, 1));

  const engine = new ChronologEngine(document);
  // The parent used to answer zero here while its children answered one each.
  const titles = query(engine, "frame:bttf").facts.map((fact) => fact.event.payload.title).sort();
  assert.deepEqual(titles, ["Lightning strikes the clock tower", "The DeLorean hits 88"]);

  // And every fact's day is exactly what a direct query on its own member gives.
  const byTitle = new Map(query(engine, "frame:bttf").facts.map((fact) => [fact.event.payload.title, fact.day]));
  for (const member of ["calendar:1955", "calendar:1985"]) {
    for (const fact of query(engine, member).facts) {
      assert.equal(
        Rational.parse(byTitle.get(fact.event.payload.title)).compare(Rational.parse(fact.day)), 0,
        "the group re-resolves nothing; it unions what each member already resolved"
      );
    }
  }
});

test("each member resolves under its OWN law, and the group imposes none", () => {
  const document = createEmptyWorkspaceDocument("Laws");
  calendar(document, "calendar:standard");
  // A member whose day is 23 standard hours long. Under bottom-up composition
  // its whole day sequence drifts, so the same calendar date is a different
  // absolute instant on it than on the standard member.
  const shortened = JSON.parse(JSON.stringify(document.frames["frame:wall-time"].coordinate));
  shortened.levels.find((level) => level.name === "hour").radix = "23";
  addFrame(document, {
    id: "calendar:shortened", title: "Shortened", traits: ["set", "calendar"], coordinate: shortened
  });
  group(document, "frame:both", ["calendar:standard", "calendar:shortened"]);
  place(document, "calendar:standard", "Standard noon", civil(2026, 8, 20, 12));
  place(document, "calendar:shortened", "Shortened noon", civil(2026, 8, 20, 12));

  const engine = new ChronologEngine(document);
  const days = new Map(query(engine, "frame:both").facts.map((fact) => [fact.event.payload.title, Rational.parse(fact.day)]));
  assert.equal(days.size, 2);
  assert.notEqual(
    days.get("Standard noon").compare(days.get("Shortened noon")), 0,
    "two laws, two answers -- the group flattens neither into the other"
  );
});

test("nested groups union transitively, and a group containing itself stops and reports", () => {
  const document = createEmptyWorkspaceDocument("Nested");
  calendar(document, "calendar:leaf");
  group(document, "frame:inner", ["calendar:leaf"]);
  group(document, "frame:outer", ["frame:inner"]);
  place(document, "calendar:leaf", "Deep event", civil(2026, 3, 4));

  const engine = new ChronologEngine(document);
  assert.equal(query(engine, "frame:outer").facts.length, 1, "reached through two levels of group");

  // A cycle terminates rather than unioning forever, and says so.
  const looped = createEmptyWorkspaceDocument("Loop");
  calendar(looped, "calendar:leaf");
  group(looped, "frame:a", ["calendar:leaf", "frame:b"]);
  group(looped, "frame:b", ["frame:a"]);
  place(looped, "calendar:leaf", "Reachable", civil(2026, 3, 4));
  const loopEngine = new ChronologEngine(looped);
  const result = query(loopEngine, "frame:a");
  assert.equal(result.facts.length, 1, "the reachable fact still comes back");
  assert.ok(
    result.errors.some((entry) => /contains itself/.test(entry.message)),
    "the cycle is reported, not silently swallowed"
  );
});

test("two placements of one event are two facts; one event reached twice is one", () => {
  const document = createEmptyWorkspaceDocument("Dedupe");
  calendar(document, "calendar:a");
  calendar(document, "calendar:b");
  group(document, "frame:union", ["calendar:a", "calendar:b"]);

  // Genuinely two placements: two attachment relations, two different days.
  const event = addEvent(document, {
    traits: ["event"], magnitudes: { duration: durationMagnitude("0") }, payload: { title: "Twice placed" }
  });
  addRelation(document, { type: "attachment", role: "placed", event: event.id, frame: "calendar:a", coordinate: civil(2026, 1, 1) });
  addRelation(document, { type: "attachment", role: "placed", event: event.id, frame: "calendar:b", coordinate: civil(2026, 6, 1) });

  const engine = new ChronologEngine(document);
  assert.equal(query(engine, "frame:union").facts.length, 2, "two authored placements survive as two");

  // One event reachable by two paths is ONE fact: dedupe is on the placement's
  // identity (its relation), not on the event id.
  const diamond = createEmptyWorkspaceDocument("Diamond");
  calendar(diamond, "calendar:shared");
  group(diamond, "frame:left", ["calendar:shared"]);
  group(diamond, "frame:right", ["calendar:shared"]);
  group(diamond, "frame:top", ["frame:left", "frame:right"]);
  place(diamond, "calendar:shared", "Reached twice", civil(2026, 5, 5));
  assert.equal(query(new ChronologEngine(diamond), "frame:top").facts.length, 1);
});

test("an importance group is not unioned, and a limit still bounds a group query", () => {
  const document = createEmptyWorkspaceDocument("Bounds");
  calendar(document, "calendar:many");
  group(document, "frame:plain", ["calendar:many"]);
  group(document, "frame:important", ["calendar:many"], ["set", "group", "importance"]);
  for (let index = 0; index < 12; index += 1) {
    place(document, "calendar:many", `Event ${index}`, civil(2026, 1, 1 + index));
  }
  const engine = new ChronologEngine(document);
  assert.equal(query(engine, "frame:plain").facts.length, 12);
  // An importance group organizes display weight, not placement, so it unions
  // nothing -- the same rule `refreshFrame` already applies.
  assert.equal(query(engine, "frame:important").facts.length, 0);

  const bounded = engine.queryFacts({
    frame: "frame:plain", start: civil(2026, 1, 1), end: civil(2026, 12, 31), limit: 5
  });
  assert.equal(bounded.facts.length, 5);
});

test("a member whose coordinates cannot resolve is skipped, the rest survive, and the frame is named once", () => {
  const document = createEmptyWorkspaceDocument("Broken");
  calendar(document, "calendar:good");
  // A declaration whose transition nothing implements: every coordinate on it
  // is unresolvable, and one such record used to abort the whole projection.
  addFrame(document, {
    id: "calendar:broken", title: "Broken", traits: ["set", "calendar"],
    coordinate: {
      kind: "nested",
      levels: [{ name: "year" }, { name: "month", within: "year", transition: "invented.months" }]
    }
  });
  group(document, "frame:mixed", ["calendar:good", "calendar:broken"]);
  place(document, "calendar:good", "Survivor", civil(2026, 2, 2));
  for (let index = 0; index < 4; index += 1) {
    place(document, "calendar:broken", `Lost ${index}`, civil(2026, 2, 2));
  }

  const engine = new ChronologEngine(document);
  const result = query(engine, "frame:mixed");
  assert.deepEqual(result.facts.map((fact) => fact.event.payload.title), ["Survivor"]);
  // `queryFacts` reports every per-source reason through one channel, keyed by
  // whatever produced it -- a pattern id for a pattern, a frame id for a frame.
  const named = result.errors.filter((entry) => entry.pattern === "calendar:broken");
  assert.equal(named.length, 1, "one reason per frame, not one per record -- four events must not flood the stage");
  assert.match(named[0].message, /invented\.months|nothing implements/);
});

test("the union leans on each member's own index rather than rebuilding it", () => {
  // Overscale doctrine: 500-member groups are the design point, so a group query
  // must not re-derive its members' facts. Each ordinary member keeps its own
  // cached entry; only the union's merge is redone.
  const document = createEmptyWorkspaceDocument("Scale");
  const members = [];
  for (let index = 0; index < 60; index += 1) {
    const id = `calendar:m${index}`;
    calendar(document, id);
    place(document, id, `Event ${index}`, civil(2026, 1, 1 + (index % 28)));
    members.push(id);
  }
  group(document, "frame:big", members);
  const engine = new ChronologEngine(document);

  assert.equal(query(engine, "frame:big").facts.length, 60);
  // Every member is individually indexed and cached after the group query, which
  // is what keeps the second query cheap.
  for (const member of members) {
    assert.equal(engine.explicitFactsByFrame.has(member), true, `${member} kept its own index`);
  }
  // Asking again is stable and does not multiply facts.
  assert.equal(query(engine, "frame:big").facts.length, 60);
});
