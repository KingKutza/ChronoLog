import assert from "node:assert/strict";
import test from "node:test";
import { ChronologEngine } from "../src/engine.js";
import { Rational, daysFromCivil } from "../src/exact.js";
import { daysToCivilCoordinate } from "../src/coordinate-law.js";
import { importICS } from "../src/ics.js";
import { clearSeriesEndStaple, createId, setSeriesEndStaple, validateDocument } from "../src/model.js";
import { applyOps } from "../src/ops.js";
import {
  applySeriesHeal,
  overrideHealDecision,
  planSeriesHeal,
  projectedOccurrence,
  revertSeriesHeal
} from "../src/series-heal.js";
import { createStructuralDocument } from "./helpers/sample-document.js";

// The convergence invariant (owner ruling, 8.19): "Any time that overriding event
// matches the pattern, the event is removed and the projection reasserts. The
// series of events leading up to the heal are irrelevant."
//
// So these tests never simulate a user journey. Each one puts the document into a
// state and asks the invariant what it thinks. That is the whole claim: a no-op
// close, an edit reverted by hand, and a delete-then-recreate are the same case
// because only the state is examined.
//
// The series comes from real ICS import rather than being hand-built, so every
// record carries exactly the fields the app gives it — which matters more here
// than anywhere, because the bug this module can most easily have is comparing
// two representations of the same value and calling them different.

function documentWithSeries({ withGroup = false } = {}) {
  const chronologDocument = createStructuralDocument();
  const source = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Test//EN",
    "BEGIN:VEVENT",
    "UID:standing@example.test",
    "DTSTART:20260105T090000Z",
    "RRULE:FREQ=WEEKLY",
    "SUMMARY:Standing meeting",
    "DURATION:PT1H",
    "END:VEVENT",
    "END:VCALENDAR",
    ""
  ].join("\r\n");
  const imported = importICS(source, chronologDocument, { label: "Calendar" });
  const frame = chronologDocument.frames[imported.frames[0]];
  const pattern = Object.values(chronologDocument.patterns).find((item) => item.kind === "ics-rrule");

  if (withGroup) {
    chronologDocument.frames["frame:group-work"] = {
      id: "frame:group-work",
      title: "Work",
      traits: ["set", "group"],
      color: "#2e8b57"
    };
    const attachment = {
      id: createId("relation"),
      type: "attachment",
      role: "placed",
      event: pattern.templateEvent,
      frame: "frame:group-work"
    };
    chronologDocument.relations[attachment.id] = attachment;
  }

  return { document: chronologDocument, frame, pattern, templateId: pattern.templateEvent };
}

function engineFor(chronologDocument) {
  return new ChronologEngine(chronologDocument);
}

function projectedFacts(chronologDocument, frame) {
  return engineFor(chronologDocument).queryFacts({
    frame: frame.id,
    start: daysToCivilCoordinate(daysFromCivil(2026n, 1n, 1n).toString()),
    end: daysToCivilCoordinate(daysFromCivil(2026n, 2n, 15n).toString()),
    limit: 80,
    applyOverrides: false
  }).facts;
}

// Mirrors src/ui/inspector.js's prepareMaterialization: a clone of the projected
// occurrence with fresh ids, "generated" stripped, explicit provenance, the group
// attachments copied off the template, and a suppressing override pointing at it.
function materialize(chronologDocument, fact, pattern, { coordinate = null } = {}) {
  const event = structuredClone(fact.event);
  event.id = createId("event");
  event.traits = (event.traits || []).filter((trait) => trait !== "generated");
  event.provenance = {
    kind: "explicit",
    replaces: fact.virtualId,
    pattern: pattern.id,
    originalCoordinate: structuredClone(fact.relation.coordinate)
  };
  const relation = structuredClone(fact.relation);
  relation.id = createId("relation");
  relation.event = event.id;
  relation.coordinate = structuredClone(coordinate || fact.relation.coordinate);
  relation.provenance = { kind: "explicit", replaces: fact.virtualId };
  const override = {
    id: createId("override"),
    virtual: fact.virtualId,
    suppress: true,
    replacements: [event.id]
  };
  chronologDocument.events[event.id] = event;
  chronologDocument.relations[relation.id] = relation;
  chronologDocument.overrides[override.id] = override;

  const copied = [];
  for (const source of Object.values(chronologDocument.relations)) {
    if (source.type !== "attachment" || source.event !== pattern.templateEvent) continue;
    if (!chronologDocument.frames[source.frame]?.traits?.includes("group")) continue;
    const clone = { ...structuredClone(source), id: createId("relation"), event: event.id };
    chronologDocument.relations[clone.id] = clone;
    copied.push(clone);
  }
  return { event, relation, override, groupRelations: copied };
}

// One materialized occurrence sitting exactly on its slot: the state after
// "open an occurrence and change nothing".
function materializedFixture(options = {}) {
  const { document: chronologDocument, frame, pattern, templateId } = documentWithSeries(options);
  const facts = projectedFacts(chronologDocument, frame);
  assert.ok(facts.length >= 3, "the series projects several occurrences");
  const fact = facts[1];
  const parts = materialize(chronologDocument, fact, pattern, options);
  return { document: chronologDocument, frame, pattern, templateId, fact, ...parts };
}

function decisionFor(chronologDocument, override) {
  return overrideHealDecision(chronologDocument, engineFor(chronologDocument), override);
}

function planFor(chronologDocument) {
  return planSeriesHeal(chronologDocument, engineFor(chronologDocument));
}

function placementOf(chronologDocument, eventId) {
  return Object.values(chronologDocument.relations).find((relation) =>
    relation.type === "attachment"
    && relation.event === eventId
    && relation.coordinate);
}

// --- The heal fires -------------------------------------------------------

test("a materialized occurrence that changed nothing heals, and the projection reasserts", () => {
  const { document: chronologDocument, frame, override, event, relation } = materializedFixture();
  assert.equal(decisionFor(chronologDocument, override).healable, true);

  const plan = planFor(chronologDocument);
  assert.equal(plan.healed, 1);
  applySeriesHeal(chronologDocument, plan);

  assert.equal(chronologDocument.overrides[override.id], undefined, "the override is gone");
  assert.equal(chronologDocument.events[event.id], undefined, "the materialized event is gone");
  assert.equal(chronologDocument.relations[relation.id], undefined, "its relation is gone");
  assert.deepEqual(validateDocument(chronologDocument).errors, [], "the healed document is still valid");

  // The projection reasserting is the point of the whole exercise: with the
  // override removed the slot is projected again, by the series, as before.
  const restored = engineFor(chronologDocument).queryFacts({
    frame: frame.id,
    start: daysToCivilCoordinate(daysFromCivil(2026n, 1n, 1n).toString()),
    end: daysToCivilCoordinate(daysFromCivil(2026n, 2n, 15n).toString()),
    limit: 80
  }).facts;
  assert.ok(
    restored.some((fact) => fact.virtualId === override.virtual),
    "the slot the override was hiding is projected once more"
  );
});

// The owner named this case explicitly: "if I edit then move back". It is also the
// case most likely to be broken by a lazy implementation, because a hand-reverted
// coordinate is numerically equal to the projected one but NOT textually equal:
// the ICS importer writes zero-padded levels ("01", "09") while the pattern
// generator writes bare ones ("1", "9"). A string comparison would never heal.
test("an occurrence edited away and moved back heals, even though the coordinate is written differently", () => {
  const { document: chronologDocument, override, event } = materializedFixture();
  const placement = placementOf(chronologDocument, event.id);
  const projectedCoordinate = structuredClone(placement.coordinate);

  // Move it: a genuine deviation.
  placement.coordinate = {
    levels: projectedCoordinate.levels.map((level) =>
      level.level === "day" ? { ...level, value: String(Number(level.value) + 2) } : level)
  };
  assert.equal(decisionFor(chronologDocument, override).healable, false, "while moved, it stays overridden");

  // Move it back by hand, in the OTHER textual form — zero-padded, the way the
  // importer writes the same instant.
  placement.coordinate = {
    levels: projectedCoordinate.levels.map((level) => ({
      ...level,
      value: level.level === "year" ? level.value : String(level.value).padStart(2, "0")
    }))
  };
  // The hour is where the two representations genuinely diverge: the pattern
  // generator writes "9", the importer writes "09". Same instant, different text.
  const projectedHour = projectedCoordinate.levels.find((level) => level.level === "hour").value;
  const revertedHour = placement.coordinate.levels.find((level) => level.level === "hour").value;
  assert.equal(projectedHour, "9", "the projection writes a bare hour");
  assert.equal(revertedHour, "09", "the reverted coordinate writes the same hour differently");
  assert.notEqual(projectedHour, revertedHour, "so a string comparison would call these different");

  const decision = decisionFor(chronologDocument, override);
  assert.equal(decision.healable, true, `reverting to the same instant heals (${decision.reason})`);
});

test("a duration written as 3600.0 still matches a projection of 3600 and heals", () => {
  const { document: chronologDocument, override, event } = materializedFixture();
  const levels = chronologDocument.events[event.id].magnitudes.duration.value.levels;
  levels[0] = { ...levels[0], value: "3600.0" };
  assert.equal(decisionFor(chronologDocument, override).healable, true, "exact equality, not string equality");
});

// "if I delete then create a new instance in the same place — it does not matter."
test("deleting a materialized occurrence and recreating a matching one in the same place heals", () => {
  const fixture = materializedFixture();
  const { document: chronologDocument, pattern, fact } = fixture;

  // Discard the whole materialization, override included.
  delete chronologDocument.events[fixture.event.id];
  delete chronologDocument.relations[fixture.relation.id];
  delete chronologDocument.overrides[fixture.override.id];
  for (const relation of fixture.groupRelations) delete chronologDocument.relations[relation.id];

  // Build a brand-new one over the same slot: different ids, same content.
  const remade = materialize(chronologDocument, fact, pattern);
  assert.notEqual(remade.event.id, fixture.event.id, "genuinely a different record");

  const decision = decisionFor(chronologDocument, remade.override);
  assert.equal(decision.healable, true, `the new instance matches the pattern, so it heals (${decision.reason})`);
});

test("an occurrence carrying the template's group attachments heals with them", () => {
  const { document: chronologDocument, override, groupRelations } = materializedFixture({ withGroup: true });
  assert.equal(groupRelations.length, 1, "the materialization copied the template's group attachment");
  const decision = decisionFor(chronologDocument, override);
  assert.equal(decision.healable, true, decision.reason);
  assert.ok(
    decision.relationIds.includes(groupRelations[0].id),
    "the copied group attachment is removed by the heal too, not orphaned"
  );
});

// --- The heal refuses, field by field ------------------------------------

// A false heal destroys authored data, so every projected field gets its own
// refusal test. These are the tests that stop this module eating real edits.
const DEVIATIONS = [
  ["a changed title", (chronologDocument, event) => {
    chronologDocument.events[event.id].payload.title = "Standing meeting (moved)";
  }],
  ["a changed description", (chronologDocument, event) => {
    chronologDocument.events[event.id].payload.description = "notes for just this one";
  }],
  ["a changed location", (chronologDocument, event) => {
    chronologDocument.events[event.id].payload.location = "Room 3";
  }],
  ["a changed duration", (chronologDocument, event) => {
    chronologDocument.events[event.id].magnitudes.duration.value.levels[0].value = "1800";
  }],
  ["an added trait", (chronologDocument, event) => {
    chronologDocument.events[event.id].traits = [...chronologDocument.events[event.id].traits, "important"];
  }],
  ["a colour set on this occurrence only", (chronologDocument, event) => {
    chronologDocument.events[event.id].display = { color: "#ff0000" };
  }],
  ["a moved coordinate", (chronologDocument, event, chronolog) => {
    const placement = placementOf(chronolog, event.id);
    placement.coordinate = {
      levels: placement.coordinate.levels.map((level) =>
        level.level === "hour" ? { ...level, value: "14" } : level)
    };
  }],
  ["a changed role", (chronologDocument, event, chronolog) => {
    placementOf(chronolog, event.id).role = "observed";
  }],
  ["a date-only placement where the series is timed", (chronologDocument, event, chronolog) => {
    const placement = placementOf(chronolog, event.id);
    placement.parameters = { ...placement.parameters, dateOnly: true };
  }],
  // These two matter for a live reason: the roster's done toggle writes exactly
  // these records against one occurrence. Completing (or otherwise state-ing)
  // one occurrence of a series is authored data and must never be healed away
  // -- the membership and the end staple each block healing on their own.
  ["a state membership recorded on this occurrence", (chronologDocument, event, chronolog) => {
    chronolog.frames["frame:state-done"] = { id: "frame:state-done", title: "Done", traits: ["set", "group", "state"] };
    const membership = {
      id: createId("relation"),
      type: "membership",
      group: "frame:state-done",
      member: event.id
    };
    chronolog.relations[membership.id] = membership;
  }],
  ["a completion end staple recorded on this occurrence", (chronologDocument, event, chronolog) => {
    const placement = placementOf(chronolog, event.id);
    const staple = {
      id: createId("relation"),
      type: "staple",
      kind: "end",
      ends: [
        { object: event.id, point: "end" },
        { frame: placement.frame, coordinate: structuredClone(placement.coordinate) }
      ]
    };
    chronolog.relations[staple.id] = staple;
  }]
];

for (const [label, deviate] of DEVIATIONS) {
  test(`the heal refuses an occurrence with ${label}`, () => {
    const { document: chronologDocument, override, event } = materializedFixture();
    deviate(chronologDocument, event, chronologDocument);
    const decision = decisionFor(chronologDocument, override);
    assert.equal(decision.healable, false, `${label} is a deviation and must persist`);
    const plan = planFor(chronologDocument);
    assert.equal(plan.healed, 0, "and nothing is removed");
    assert.ok(chronologDocument.events[event.id], "the authored occurrence survives");
  });
}

// Both directions of the state-affiliation rule, pinned together: writing a
// done membership plus its end staple against a materialized occurrence blocks
// healing, and removing them re-enables it purely because the state changed
// back -- the invariant is history-free, so nothing about HOW they were
// removed matters.
test("state affiliation blocks healing while present and re-enables it when removed", () => {
  const { document: chronologDocument, override, event } = materializedFixture();
  assert.equal(decisionFor(chronologDocument, override).healable, true, "healable before any state is written");

  chronologDocument.frames["frame:state-done"] = { id: "frame:state-done", title: "Done", traits: ["set", "group", "state"] };
  const placement = placementOf(chronologDocument, event.id);
  const membership = { id: createId("relation"), type: "membership", group: "frame:state-done", member: event.id };
  const staple = {
    id: createId("relation"),
    type: "staple",
    kind: "end",
    ends: [
      { object: event.id, point: "end" },
      { frame: placement.frame, coordinate: structuredClone(placement.coordinate) }
    ]
  };
  chronologDocument.relations[membership.id] = membership;
  chronologDocument.relations[staple.id] = staple;

  const blocked = decisionFor(chronologDocument, override);
  assert.equal(blocked.healable, false, "a done occurrence is authored data the heal must not destroy");
  assert.match(blocked.reason, /relations deviate/);
  assert.ok(chronologDocument.events[event.id], "the occurrence survives");

  delete chronologDocument.relations[membership.id];
  const stillBlocked = decisionFor(chronologDocument, override);
  assert.equal(stillBlocked.healable, false, "the end staple blocks on its own too");

  delete chronologDocument.relations[staple.id];
  assert.equal(decisionFor(chronologDocument, override).healable, true, "removing the state re-enables the heal");
});

test("the heal refuses an occurrence whose group membership was changed for this instance only", () => {
  const { document: chronologDocument, override, groupRelations } = materializedFixture({ withGroup: true });
  delete chronologDocument.relations[groupRelations[0].id];
  const decision = decisionFor(chronologDocument, override);
  assert.equal(decision.healable, false, "dropping a group on one occurrence is a real deviation");
});

// --- Shapes the module must not touch -----------------------------------

test("a plain suppression with no replacement is never healed", () => {
  const { document: chronologDocument, frame, pattern } = documentWithSeries();
  const fact = projectedFacts(chronologDocument, frame)[1];
  const override = {
    id: createId("override"),
    virtual: fact.virtualId,
    suppress: true,
    replacements: []
  };
  chronologDocument.overrides[override.id] = override;
  // A deliberate "skip this occurrence" is authored intent, not an unhealed fork.
  assert.equal(decisionFor(chronologDocument, override).healable, false);
  assert.equal(planFor(chronologDocument).healed, 0);
  assert.ok(chronologDocument.overrides[override.id], "the suppression survives");
});

// LEXICON's staple anchoring / Rob-and-John scenario, composed with the
// healing invariant. Placing an end-staple is a second, independent bound on
// the series (src/engine.js's `seriesEffectiveUntilDays`) -- the rule itself
// (`pattern.rrule`) is never rewritten. So once a staple retires a slot, this
// looks to the invariant exactly like the pattern-is-gone case just above:
// `projectedOccurrence` finds nothing, and the module must refuse rather than
// destroy the authored event the override replaced. That is the safe,
// deliberately asymmetric direction the module is built around -- a false
// heal destroys data, a missed heal only leaves an extra record.
test("an end-staple placed before a materialized occurrence's slot leaves its override in place -- the invariant refuses rather than destroys it", () => {
  const { document: chronologDocument, frame, pattern, fact, override, event } = materializedFixture();
  assert.equal(decisionFor(chronologDocument, override).healable, true, "healable before the staple exists");

  // Staple the series one day before this occurrence's own slot. The rule
  // itself is untouched -- still FREQ=WEEKLY, still indefinite -- this is a
  // second, independent bound intersected with it at projection time.
  const stapleDay = Rational.parse(fact.day).sub(1);
  setSeriesEndStaple(chronologDocument, pattern.id, frame.id, daysToCivilCoordinate(stapleDay));

  const decision = decisionFor(chronologDocument, override);
  assert.equal(decision.healable, false, "the staple retired this slot; healing now would destroy the authored event");
  assert.match(decision.reason, /projects nothing/i);
  assert.ok(chronologDocument.events[event.id], "the authored occurrence the override replaced is untouched");

  // Removing the staple resumes the projection; the override, unchanged this
  // whole time, is healable again purely because the state changed back.
  clearSeriesEndStaple(chronologDocument, pattern.id);
  assert.equal(decisionFor(chronologDocument, override).healable, true, "healable again once the staple is gone");
});

test("an override whose pattern is gone is left for the repair path, not healed", () => {
  const { document: chronologDocument, override, pattern } = materializedFixture();
  delete chronologDocument.patterns[pattern.id];
  const decision = decisionFor(chronologDocument, override);
  assert.equal(decision.healable, false);
  assert.match(decision.reason, /projects nothing|missing/i);
});

test("scope limits which overrides are even considered", () => {
  const { document: chronologDocument, override, event } = materializedFixture();
  const engine = engineFor(chronologDocument);
  assert.equal(planSeriesHeal(chronologDocument, engine, { eventIds: [event.id] }).healed, 1);
  assert.equal(planSeriesHeal(chronologDocument, engine, { eventIds: ["event:unrelated"] }).healed, 0);
  assert.equal(planSeriesHeal(chronologDocument, engine, { overrideIds: [override.id] }).healed, 1);
  assert.equal(planSeriesHeal(chronologDocument, engine, { overrideIds: ["override:nope"] }).healed, 0);
});

// --- Undo stays bundle-clean --------------------------------------------

test("the heal's ops and inverse ops round-trip the document exactly", () => {
  const { document: chronologDocument } = materializedFixture({ withGroup: true });
  const before = structuredClone(chronologDocument);
  const plan = planFor(chronologDocument);
  assert.equal(plan.healed, 1);

  // The ops are the journal's account of the heal, so they must produce exactly
  // what the in-place mutation produces — client and server must not diverge.
  const viaOps = structuredClone(chronologDocument);
  applyOps(viaOps, plan.ops);
  applySeriesHeal(chronologDocument, plan);
  assert.deepEqual(viaOps.events, chronologDocument.events, "ops and mutation agree on events");
  assert.deepEqual(viaOps.relations, chronologDocument.relations, "ops and mutation agree on relations");
  assert.deepEqual(viaOps.overrides, chronologDocument.overrides, "ops and mutation agree on overrides");

  // Undo restores the override and everything it replaced, together.
  applyOps(viaOps, plan.inverseOps);
  assert.deepEqual(viaOps.events, before.events, "undo restores every event");
  assert.deepEqual(viaOps.relations, before.relations, "undo restores every relation");
  assert.deepEqual(viaOps.overrides, before.overrides, "undo restores the override");

  revertSeriesHeal(chronologDocument, plan);
  assert.deepEqual(chronologDocument.overrides, before.overrides, "the in-place revert agrees too");
  assert.deepEqual(chronologDocument.events, before.events);
  assert.deepEqual(chronologDocument.relations, before.relations);
  assert.deepEqual(validateDocument(chronologDocument).errors, [], "the restored document is valid");
});

test("healing twice is a no-op, because the second pass finds nothing to heal", () => {
  const { document: chronologDocument } = materializedFixture();
  applySeriesHeal(chronologDocument, planFor(chronologDocument));
  const second = planFor(chronologDocument);
  assert.equal(second.healed, 0, "the invariant is idempotent");
});

test("a refusal explains itself so a missed heal is diagnosable", () => {
  const { document: chronologDocument, override, event } = materializedFixture();
  chronologDocument.events[event.id].payload.title = "changed";
  const plan = planFor(chronologDocument);
  const refusal = plan.refusals.find((item) => item.override === override.id);
  assert.ok(refusal, "the plan records why it declined");
  assert.match(refusal.reason, /deviates/);
});

test("the projection for an overridden slot is reachable even though the override hides it", () => {
  const { document: chronologDocument, override, event } = materializedFixture();
  const engine = engineFor(chronologDocument);
  // The ordinary query must NOT show the suppressed slot...
  const visible = engine.queryFacts({
    frame: chronologDocument.relations[placementOf(chronologDocument, event.id).id].frame,
    start: daysToCivilCoordinate(daysFromCivil(2026n, 1n, 1n).toString()),
    end: daysToCivilCoordinate(daysFromCivil(2026n, 2n, 15n).toString()),
    limit: 80
  }).facts;
  assert.ok(!visible.some((fact) => fact.virtualId === override.virtual), "the override hides its slot");
  // ...while the heal can still see what the series would project there.
  const projected = projectedOccurrence(chronologDocument, engine, override, chronologDocument.events[event.id]);
  assert.ok(projected, "the heal can reconstruct the hidden slot");
  assert.equal(projected.virtualId, override.virtual);
});
