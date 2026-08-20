import assert from "node:assert/strict";
import test from "node:test";
import { Rational, coordinate } from "../src/exact.js";
import { coordinateLaw, invalidateCoordinateLaws } from "../src/coordinate-law.js";
import { eraChain, eraChainFrames, frameEraContext, isCountableEra } from "../src/era-chain.js";
import { addEvent, addRelation, createDocument } from "../src/model.js";

// Owner ruling: eras are FRAMES STAPLED TOGETHER. An era owns its year numbering
// and extent, inherits its month/day ladder from a basis, and the boundary
// between two consecutive eras is a `succession` staple whose roles carry the
// whole of its meaning. A coordinate on an era frame is a plain year -- the
// frame it is attached to is which era it means.

const TAMRIEL_MONTHS = [
  "Morning Star", "Sun's Dawn", "First Seed", "Rain's Hand",
  "Second Seed", "Midyear", "Sun's Height", "Last Seed",
  "Hearthfire", "Frostfall", "Sun's Dusk", "Evening Star"
];

// The eras, oldest first. Dawn has no year axis at all.
const ERAS = [
  { id: "era:dawn", title: "Dawn Era", era: { key: "Dawn", name: "Dawn Era", countable: false } },
  { id: "era:merethic", title: "Merethic Era", era: { key: "ME", name: "Merethic Era", direction: "descending", firstYear: "1", years: "open" } },
  { id: "era:first", title: "First Era", era: { key: "1E", name: "First Era", direction: "ascending", firstYear: "1", years: "2920", anchor: { year: "1", properYear: "1" } } },
  { id: "era:second", title: "Second Era", era: { key: "2E", name: "Second Era", direction: "ascending", firstYear: "1", years: "896" } },
  { id: "era:third", title: "Third Era", era: { key: "3E", name: "Third Era", direction: "ascending", firstYear: "1", years: "433" } },
  { id: "era:fourth", title: "Fourth Era", era: { key: "4E", name: "Fourth Era", direction: "ascending", firstYear: "1", years: "open" } }
];

function tamrielDocument() {
  const document = createDocument("Tamriel");
  // The spanning calendar is a GROUP frame over the chain, and it carries the
  // year ladder every era inherits. `clock: false` because an authored origin on
  // a fictional calendar is a stated convention, not a claim about this world.
  document.frames["frame:tamriel-calendar"] = {
    id: "frame:tamriel-calendar",
    title: "Tamrielic calendar",
    traits: ["line", "temporal", "calendar", "group"],
    coordinate: {
      kind: "nested",
      origin: { days: "0" },
      clock: false,
      levels: [
        { name: "year" },
        { name: "month", within: "year", transition: "gregorian.months", names: TAMRIEL_MONTHS },
        { name: "day", within: "month", transition: "gregorian.days" },
        { name: "hour", within: "day", radix: "24" },
        { name: "minute", within: "hour", radix: "60" },
        { name: "second", within: "minute", radix: "60" }
      ]
    }
  };
  for (const entry of ERAS) {
    document.frames[entry.id] = {
      id: entry.id,
      title: entry.title,
      traits: ["line", "temporal", "era"],
      // Dawn inherits nothing: it has no ladder, which is what makes it
      // uncountable in executable terms as well as in its declaration.
      ...(entry.era.countable === false ? {} : { basis: "frame:tamriel-calendar" }),
      // Cloned: a test that deletes or re-pins an anchor must not reach back
      // into the shared table and poison every document built after it.
      era: JSON.parse(JSON.stringify(entry.era))
    };
    addRelation(document, {
      id: `membership:${entry.id}`,
      type: "membership",
      group: "frame:tamriel-calendar",
      member: entry.id
    });
  }
  for (const [index, entry] of ERAS.slice(0, -1).entries()) {
    addRelation(document, {
      id: `succession:${entry.id}`,
      type: "staple",
      kind: "succession",
      ends: [
        { frame: entry.id, role: "end" },
        { frame: ERAS[index + 1].id, role: "start" }
      ]
    });
  }
  return document;
}

function at(law, year, month = 1, day = 1, hour = 0) {
  return law.toDays(coordinate([
    { level: "year", value: String(year) },
    { level: "month", value: String(month) },
    { level: "day", value: String(day) },
    { level: "hour", value: String(hour) }
  ]));
}

test("a succession chain orders its eras from one end, and refuses a fork or a loop", () => {
  const document = tamrielDocument();
  assert.deepEqual(
    eraChainFrames(document, "era:third"),
    ["era:dawn", "era:merethic", "era:first", "era:second", "era:third", "era:fourth"],
    "the chain is walked from its head, whichever era the caller names"
  );

  // A fork says two contradictory things about what follows what.
  const forked = tamrielDocument();
  addRelation(forked, {
    id: "succession:fork",
    type: "staple",
    kind: "succession",
    ends: [{ frame: "era:first", role: "end" }, { frame: "era:fourth", role: "start" }]
  });
  assert.throws(() => eraChainFrames(forked, "era:first"), /cannot fork/);

  // A chain with no head is a loop.
  const looped = tamrielDocument();
  addRelation(looped, {
    id: "succession:loop",
    type: "staple",
    kind: "succession",
    ends: [{ frame: "era:fourth", role: "end" }, { frame: "era:dawn", role: "start" }]
  });
  assert.throws(() => eraChainFrames(looped, "era:first"), /no beginning|loop/);
});

test("the chain derives every era's range from one authored pin", () => {
  const document = tamrielDocument();
  const chain = eraChain(document, "era:first");
  const range = (key) => {
    const entry = chain.table.era(key);
    return [entry.firstProper, entry.lastProper];
  };
  assert.deepEqual(range("1E"), [1n, 2920n]);
  assert.deepEqual(range("2E"), [2921n, 3816n]);
  assert.deepEqual(range("3E"), [3817n, 4249n]);
  assert.deepEqual(range("4E"), [4250n, null], "open above: the calendar has no last year");
  assert.deepEqual(range("ME"), [null, 0n], "open below, descending, abutting 1E 1");
  // Dawn is in the ORDER but not in the year arithmetic.
  assert.deepEqual(chain.countable, ["era:merethic", "era:first", "era:second", "era:third", "era:fourth"]);
  assert.equal(chain.pin, "era:first");

  // Exactly one pin, for the same reason a table takes one anchor.
  const unpinned = tamrielDocument();
  delete unpinned.frames["era:first"].era.anchor;
  assert.throws(() => eraChain(unpinned, "era:first"), /states nowhere that it sits/);
  const doublePinned = tamrielDocument();
  doublePinned.frames["era:third"] = {
    ...doublePinned.frames["era:third"],
    era: { ...doublePinned.frames["era:third"].era, anchor: { year: "1", properYear: "3817" } }
  };
  assert.throws(() => eraChain(doublePinned, "era:first"), /pinned 2 times/);
});

test("a Tamriel era frame round-trips 3E 433 exactly, and a coordinate on it is a plain year", () => {
  const document = tamrielDocument();
  const law = coordinateLaw(document, "era:third");
  assert.equal(law.hasEras(), true);
  assert.equal(law.eraKey(), "3E");

  const written = coordinate([
    { level: "year", value: "433" }, { level: "month", value: "1" }, { level: "day", value: "1" }
  ]);
  const days = law.toDays(written);
  const back = law.fromDays(days);
  // The frame is the era, so the coordinate carries no era level at all.
  assert.equal(back.levels.some((level) => level.level === "era"), false);
  assert.equal(back.levels.find((level) => level.level === "year").value, "433");
  assert.equal(law.toDays(back).compare(days), 0);
  assert.equal(law.formatYear(back), "3E 433", "the era comes from the frame's identity");
  assert.equal(law.formatYearAtDays(days), "3E 433");

  // Its month names are Tamrielic, inherited from the basis calendar.
  assert.equal(law.monthNames()[0], "Morning Star");
  // A fictional calendar states no relation to this world's clock.
  assert.equal(law.mapsToClock(), false);
});

test("era order is day order across the whole chain", () => {
  const document = tamrielDocument();
  const me = coordinateLaw(document, "era:merethic");
  const first = coordinateLaw(document, "era:first");
  const second = coordinateLaw(document, "era:second");
  const chain = [
    at(me, 2500), at(me, 1), at(first, 1), at(first, 2920), at(second, 1)
  ];
  for (const [index, value] of chain.slice(1).entries()) {
    assert.equal(chain[index].compare(value) < 0, true, `${chain[index]} < ${value}`);
  }
  // Merethic counts DOWN: its higher number is the older year.
  assert.equal(at(me, 2500).compare(at(me, 1000)) < 0, true);
  // Adjacent eras meet with no gap: 1E's last year and 2E's first are
  // consecutive PROPER years. Asserted on the chain rather than as a day count,
  // because the day count is whatever that particular year's length happens to
  // be -- proper year 2920 is a leap year, so it is 366 and not 365, and pinning
  // the literal would be pinning the leap rule by accident.
  const table = eraChain(document, "era:first").table;
  assert.equal(table.era("1E").lastProper + 1n, table.era("2E").firstProper);
  const gap = at(second, 1).sub(at(first, 2920)).toNumber();
  assert.equal(gap === 365 || gap === 366, true, "exactly one year, of whatever length that year is");
});

test("an ordinal outside an era's own range refuses rather than renumbering into its neighbour", () => {
  const document = tamrielDocument();
  const third = coordinateLaw(document, "era:third");
  const fourth = coordinateLaw(document, "era:fourth");
  // A position that genuinely belongs to the Fourth Era, read through the Third.
  const inFourth = at(fourth, 5);
  assert.throws(() => third.fromDays(inFourth), /falls in Fourth Era, not Third Era/);
  // And a year past this era's stated length is refused on the way in.
  assert.throws(() => at(third, 434), /only 433 years long/);
});

test("the Dawn Era is ordered and connected and never acquires day ordinals", () => {
  const document = tamrielDocument();
  assert.equal(isCountableEra(document.frames["era:dawn"]), false);
  // It is in the chain -- that is the whole of what it claims.
  assert.equal(eraChainFrames(document, "era:dawn")[0], "era:dawn");
  assert.equal(frameEraContext(document, "era:dawn").countable, false);

  const law = coordinateLaw(document, "era:dawn");
  assert.equal(law.positional, false);
  assert.equal(law.mapsToClock(), false, "no year axis means no now");
  const anywhere = coordinate([{ level: "year", value: "1" }]);
  assert.throws(() => law.toDays(anywhere), /has no year axis, so nothing in it has a date/);
  assert.throws(() => law.fromDays(0), /no position in it has a date/);

  // Events still attach to it, and the document stays valid: ordering is real
  // even where dating is not.
  const event = addEvent(document, { traits: ["event"], payload: { title: "Before time behaved" } });
  addRelation(document, { type: "attachment", role: "placed", event: event.id, frame: "era:dawn" });
  assert.equal(Object.values(document.relations).some((relation) =>
    relation.type === "attachment" && relation.frame === "era:dawn"), true);
});

test("re-pinning the chain re-derives every era, and the memoized law notices", () => {
  const document = tamrielDocument();
  assert.equal(coordinateLaw(document, "era:third").formatYearAtDays(at(coordinateLaw(document, "era:third"), 433)), "3E 433");

  // Move the pin: 1E 1 is now proper year 1001 rather than 1.
  document.frames["era:first"] = {
    ...document.frames["era:first"],
    era: { ...document.frames["era:first"].era, anchor: { year: "1", properYear: "1001" } }
  };
  invalidateCoordinateLaws(document);
  const chain = eraChain(document, "era:first");
  assert.deepEqual([chain.table.era("1E").firstProper, chain.table.era("3E").firstProper], [1001n, 4817n]);
  // The same era-local coordinate now resolves a thousand years later.
  const third = coordinateLaw(document, "era:third");
  assert.equal(third.formatYear(coordinate([{ level: "year", value: "433" }])), "3E 433");
  assert.equal(
    at(third, 433).sub(Rational.parse(0)).compare(Rational.parse(0)) > 0, true,
    "the chain re-derived rather than serving a stale law"
  );
});

test("a group frame over the chain is not itself an era", () => {
  const document = tamrielDocument();
  assert.equal(frameEraContext(document, "frame:tamriel-calendar"), null);
  const law = coordinateLaw(document, "frame:tamriel-calendar");
  assert.equal(law.hasEras(), false);
  // It still carries the ladder every era reads, which is why the eras inherit
  // their months from it.
  assert.equal(law.monthNames()[11], "Evening Star");
});

// The BCE/CE crossing, on the chain model. Two era frames stapled at the epoch:
// BCE descending and open below, CE ascending and open above. No year zero
// exists because none is declared -- 1 BCE and 1 CE are adjacent proper years,
// so the absence is structural rather than a special case anyone codes around.
function bceCeDocument() {
  const document = createDocument("History");
  document.frames["frame:civil"] = {
    id: "frame:civil",
    title: "Civil calendar",
    traits: ["line", "temporal", "calendar", "group"],
    coordinate: {
      kind: "gregorian",
      levels: [
        { name: "year" },
        { name: "month", within: "year", transition: "gregorian.months" },
        { name: "day", within: "month", transition: "gregorian.days" },
        { name: "hour", within: "day", radix: "24" },
        { name: "minute", within: "hour", radix: "60" },
        { name: "second", within: "minute", radix: "60" }
      ]
    }
  };
  const eras = [
    { id: "era:bce", era: { key: "BCE", name: "Before Common Era", direction: "descending", firstYear: "1", years: "open", affix: "suffix" } },
    { id: "era:ce", era: { key: "CE", name: "Common Era", direction: "ascending", firstYear: "1", years: "open", affix: "suffix", anchor: { year: "1", properYear: "1" } } }
  ];
  for (const entry of eras) {
    document.frames[entry.id] = {
      id: entry.id, title: entry.era.name, traits: ["line", "temporal", "era"],
      basis: "frame:civil", era: entry.era
    };
  }
  addRelation(document, {
    id: "succession:bce-ce", type: "staple", kind: "succession",
    ends: [{ frame: "era:bce", role: "end" }, { frame: "era:ce", role: "start" }]
  });
  return document;
}

test("BCE crosses to CE with no year zero, on the stapled chain", () => {
  const document = bceCeDocument();
  const bce = coordinateLaw(document, "era:bce");
  const ce = coordinateLaw(document, "era:ce");
  const table = eraChain(document, "era:ce").table;

  // Structural adjacency: 1 BCE is proper year 0 and 1 CE is proper year 1.
  assert.equal(table.toProperYear("BCE", "1"), 0n);
  assert.equal(table.toProperYear("CE", "1"), 1n);
  assert.equal(table.toProperYear("BCE", "1") + 1n, table.toProperYear("CE", "1"));
  // 44 BCE is proper year -43 -- the fencepost, stated once and derived here.
  assert.equal(table.toProperYear("BCE", "44"), -43n);

  // In days: 1 BCE runs straight into 1 CE. That one year is 366 days, because
  // proleptic year 0 is divisible by 400 and so is a leap year -- asserting 366
  // rather than 365 is the point, since an off-by-one-year error shows up here.
  const oneBce = at(bce, 1);
  const oneCe = at(ce, 1);
  assert.equal(oneBce.compare(oneCe) < 0, true);
  assert.equal(oneCe.sub(oneBce).toJSON(), "366");

  // Descending: an older BCE year is a smaller ordinal, and the affix each era
  // authored is what renders.
  assert.equal(at(bce, 44).compare(at(bce, 1)) < 0, true);
  assert.equal(bce.formatYear(coordinate([{ level: "year", value: "44" }])), "44 BCE");
  assert.equal(ce.formatYear(coordinate([{ level: "year", value: "2026" }])), "2026 CE");

  // Round trip both sides, era-local years throughout.
  for (const [law, year] of [[bce, 44], [bce, 1], [ce, 1], [ce, 2026]]) {
    const days = at(law, year, 3, 15);
    const back = law.fromDays(days);
    assert.equal(back.levels.find((level) => level.level === "year").value, String(year));
    assert.equal(law.toDays(back).compare(days), 0);
  }

  // A CE ordinal read through the BCE frame is refused, not renumbered.
  assert.throws(() => bce.fromDays(at(ce, 2026)), /falls in Common Era, not Before Common Era/);
});

// The acceptance fixture, through the sanctioned loader. `applyDataset` is the
// one expansion path (tools/load-dataset.js), so this exercises the same code a
// real load runs rather than a second interpretation of the dataset shape.
test("the elder-scrolls dataset loads, validates, and queries across its era chain", async () => {
  const { readFile } = await import("node:fs/promises");
  const { applyDataset } = await import("../tools/load-dataset.js");
  const { ChronologEngine } = await import("../src/engine.js");
  const { createEmptyWorkspaceDocument, validateDocument } = await import("../src/model.js");

  const dataset = JSON.parse(await readFile(new URL("../fixtures/datasets/elder-scrolls.json", import.meta.url), "utf8"));
  const document = createEmptyWorkspaceDocument("Tamriel");
  applyDataset(document, dataset);
  assert.equal(validateDocument(document).valid, true, validateDocument(document).errors.join(" · "));

  // The chain is the whole ladder, Dawn included, ordered oldest first.
  assert.deepEqual(eraChainFrames(document, "era:tamriel-third"), [
    "era:tamriel-dawn", "era:tamriel-merethic", "era:tamriel-first",
    "era:tamriel-second", "era:tamriel-third", "era:tamriel-fourth"
  ]);

  // Its month names are Tamrielic and its arithmetic is the Gregorian family's.
  const third = coordinateLaw(document, "era:tamriel-third");
  assert.equal(third.monthNames()[0], "Morning Star");
  assert.equal(third.calendarScale(), "gregory");
  assert.equal(third.mapsToClock(), false, "clock: false -- no artificial Now on Tamriel");
  assert.equal(third.formatYear(coordinate([{ level: "year", value: "433" }])), "3E 433");

  // Events land in their own eras, and era order is day order across the chain.
  const engine = new ChronologEngine(document);
  const dayOf = (frameId) => engine.indexedExplicitFacts(frameId).map((entry) => entry.day);
  const merethic = dayOf("era:tamriel-merethic");
  const fourth = dayOf("era:tamriel-fourth");
  assert.ok(merethic.length >= 4, "Merethic holds its own events");
  assert.ok(fourth.length >= 1);
  const maxMerethic = merethic.reduce((a, b) => (a.compare(b) >= 0 ? a : b));
  const minFourth = fourth.reduce((a, b) => (a.compare(b) <= 0 ? a : b));
  assert.equal(maxMerethic.compare(minFourth) < 0, true, "every Merethic event precedes every Fourth Era one");

  // Dawn is in the chain and holds no dated facts: ordered, never dated.
  assert.equal(coordinateLaw(document, "era:tamriel-dawn").positional, false);
  assert.equal(engine.indexedExplicitFacts("era:tamriel-dawn").length, 0);
});

// Don's field note: no artificial Now line on a calendar with no now-mapping.
// The three markers (`intimate-now-line`, `radial-now-line`, `minimap-now-line`)
// are guarded on the governing law, so a Tamriel frame -- which declares
// `clock: false` -- draws none of them while wall time still does.
test("a calendar with no now-mapping draws no Now line, and one with a clock still does", async () => {
  const { ViewSession } = await import("../src/session.js");
  const { ChronologEngine } = await import("../src/engine.js");
  const { createEmptyWorkspaceDocument } = await import("../src/model.js");
  const { findByClass, renderWithStubDom } = await import("./helpers/render-dom.js");
  const { nowDays } = await import("../src/exact.js");

  const clocked = createEmptyWorkspaceDocument("Clocked");
  clocked.frames["calendar:personal"] = {
    id: "calendar:personal", title: "Personal", traits: ["set", "calendar"], basis: "frame:wall-time"
  };
  const clockedSession = new ViewSession({
    projection: "calendar", scale: 0, activeFrame: "calendar:personal",
    intimateBack: 0, intimateForward: 0, focusDays: nowDays().toJSON()
  });
  clockedSession.setCoordinateLaw(coordinateLaw(clocked, "calendar:personal"));
  const clockedTarget = renderWithStubDom({
    document: clocked, engine: new ChronologEngine(clocked), session: clockedSession
  });
  assert.equal(findByClass(clockedTarget, "intimate-now").length > 0, true, "wall time has a now");

  // The same lens over an era frame whose calendar declares `clock: false`.
  const tamriel = tamrielDocument();
  const law = coordinateLaw(tamriel, "era:third");
  assert.equal(law.mapsToClock(), false);
  const eraSession = new ViewSession({
    projection: "calendar", scale: 0, activeFrame: "era:third",
    // Focused inside the Third Era's own extent: a day outside it genuinely
    // belongs to a different era, and the law says so rather than renumbering.
    intimateBack: 0, intimateForward: 0, focusDays: at(law, 100).toJSON()
  });
  eraSession.setCoordinateLaw(law);
  const eraTarget = renderWithStubDom({
    document: tamriel, engine: new ChronologEngine(tamriel), session: eraSession
  });
  assert.equal(findByClass(eraTarget, "intimate-now").length, 0, "no artificial Now on Tamriel");
});
