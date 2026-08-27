// Differential harness for the staple substrate and the era chain, JavaScript
// side. Generates random documents from a fixed seed, runs every probe through
// the shipped `src/staples.js` and `src/era-chain.js`, and writes each answer as
// an exact string to stdout as one JSON document. `app/tool/staple_diff_check.dart`
// replays the same cases through `lib/core/staples.dart` and
// `lib/core/era_chain.dart` and compares.
//
// Nothing here is a test of the JavaScript. It is the ORACLE: any disagreement is
// either a port defect or a deliberate, documented deviation.
//
// THE RULED DIVERGENCE CLASSES, generated deliberately and marked `divergent`:
//
//   R4 -- `era-chain.js:63-64` derives succession direction from `end.role`, a
//         field nothing validates. The port reads the ORDER of the ends. A case
//         whose succession staples carry no roles therefore diverges by design:
//         the JavaScript sees no edges at all and reports each era as a chain of
//         one, while the port walks the chain. Such cases are counted, not
//         compared.
//
//   R3 -- the end-scope gate. It lives in `model.js`'s `validateDocument`, NOT in
//         staples.js, so the DERIVATIONS agree on a pair the validator would
//         refuse (an anchor to a series end resolves to nothing on both sides,
//         for the same stated reason). Those cases stay in the parity set and are
//         counted separately, because the divergence is at the validation layer
//         this harness does not run.
//
// Run, from app/:
//
//   dart run tool/staple_diff_check.dart
//
// which shells out to node itself. To keep the cases for inspection, redirect
// into app/build/ (already ignored):
//
//   node tool/staple_diff_gen.mjs > build/staple-diff-cases.json
//   dart run tool/staple_diff_check.dart build/staple-diff-cases.json

import { Rational } from "../../src/exact.js";
import {
  GREGORIAN_DECLARATION,
  invalidateCoordinateLaws
} from "../../src/coordinate-law.js";
import { coordinateToDays } from "../../src/model.js";
import {
  describeCorrespondence,
  frameCorrespondences,
  frameEndDays,
  liveExclusionDays,
  resolveObjectExtent,
  seriesPhaseDays,
  seriesSegments
} from "../../src/staples.js";
import { eraChain, eraChainFrames, frameEraContext } from "../../src/era-chain.js";

const SEED = 20260827;

function mulberry32(seed) {
  return function next() {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const rnd = mulberry32(SEED);
const int = (bound) => Math.floor(rnd() * bound);
const pick = (items) => items[int(items.length)];

// --- The shared document shape ----------------------------------------------
//
// Written out rather than built through model.js, so the JSON the Dart side
// parses is byte-for-byte the JSON this side ran.

const HUMAN_TIME = {
  kind: "nested",
  levels: [
    { name: "year" },
    { name: "day", within: "year", transition: "gregorian.daysInYear" },
    { name: "hour", within: "day", radix: "24" },
    { name: "minute", within: "hour", radix: "60" },
    { name: "second", within: "minute", radix: "60" },
    { name: "subsecond", within: "second" }
  ]
};

const INVENTED = {
  kind: "nested",
  levels: [{ name: "stroke" }, { name: "step", within: "stroke", radix: "8" }]
};

function baseDocument() {
  return {
    schema: "chronolog/1",
    meta: {},
    frames: {
      "measure:human-time": {
        id: "measure:human-time",
        title: "Human time magnitude",
        traits: ["line", "measure", "duration"],
        coordinate: HUMAN_TIME
      },
      "frame:wall-time": {
        id: "frame:wall-time",
        title: "Wall time",
        traits: ["line", "temporal", "gregorian"],
        coordinate: JSON.parse(JSON.stringify(GREGORIAN_DECLARATION))
      },
      "calendar:work": {
        id: "calendar:work",
        title: "Work",
        traits: ["set", "calendar"],
        basis: "frame:wall-time"
      },
      "frame:invented": {
        id: "frame:invented",
        title: "A curve of handwriting",
        traits: ["line", "temporal"],
        coordinate: INVENTED
      }
    },
    events: {},
    patterns: {},
    relations: {},
    overrides: {},
    foreign: {}
  };
}

function civil(year, month, day, hour, minute, second) {
  const parts = [
    ["year", year],
    ["month", month],
    ["day", day],
    ["hour", hour],
    ["minute", minute],
    ["second", second]
  ];
  return {
    levels: parts
      .filter(([, value]) => value !== undefined && value !== null)
      .map(([level, value]) => ({ level, value: String(value) }))
  };
}

function strokeAt(stroke, step = 0) {
  return {
    levels: [
      { level: "stroke", value: String(stroke) },
      { level: "step", value: String(step) }
    ]
  };
}

function magnitude(value, unit = "minute") {
  return {
    frame: "measure:human-time",
    value: { levels: [{ level: unit, value: String(value) }] }
  };
}

class World {
  constructor() {
    this.document = baseDocument();
    this.minted = 0;
  }

  id(prefix) {
    this.minted += 1;
    return `${prefix}:${String(this.minted).padStart(3, "0")}`;
  }

  object({ duration = "0", unit = "minute", placedAt = null, frame = "calendar:work" } = {}) {
    const id = this.id("event");
    this.document.events[id] = {
      id,
      traits: ["event"],
      magnitudes: { duration: magnitude(duration, unit) },
      payload: {}
    };
    if (placedAt) {
      const relation = this.id("relation");
      this.document.relations[relation] = {
        id: relation,
        type: "attachment",
        event: id,
        frame,
        role: "placed",
        coordinate: placedAt
      };
    }
    return id;
  }

  pattern({ rrule = { FREQ: "WEEKLY" }, templateAt = null } = {}) {
    const id = this.id("pattern");
    let template = null;
    if (templateAt) {
      template = this.id("relation");
      this.document.relations[template] = {
        id: template,
        type: "attachment",
        frame: "calendar:work",
        role: "template",
        coordinate: templateAt
      };
    }
    this.document.patterns[id] = {
      id,
      language: "ics",
      kind: "ics-rrule",
      rrule,
      frame: "calendar:work",
      ...(template ? { templateRelation: template } : {})
    };
    return id;
  }

  staple(record) {
    const id = record.id || this.id("relation");
    this.document.relations[id] = { id, type: "staple", ...record };
    return this.document.relations[id];
  }

  era(id, era, after = null, roles = true) {
    this.document.frames[id] = {
      id,
      title: era.name,
      traits: ["line", "temporal", "era"],
      ...(era.countable === false ? {} : { basis: "frame:wall-time" }),
      era
    };
    if (after) {
      this.staple({
        kind: "succession",
        ends: roles
          ? [
              { frame: after, role: "end" },
              { frame: id, role: "start" }
            ]
          : [{ frame: after }, { frame: id }]
      });
    }
  }
}

function engineFor(document) {
  return {
    document,
    coordinateDays(frameId, value) {
      return coordinateToDays(document, frameId, value);
    },
    indexedExplicitFacts(frameId) {
      return Object.values(document.relations)
        .filter(
          (relation) =>
            relation.type === "attachment" &&
            relation.coordinate &&
            relation.frame === frameId
        )
        .map((relation) => ({
          day: coordinateToDays(document, frameId, relation.coordinate),
          fact: { event: document.events[relation.event] }
        }))
        .filter((entry) => entry.fact.event);
    }
  };
}

const text = (value) =>
  value === null || value === undefined ? null : value.toJSON();

// --- Probes -----------------------------------------------------------------

function extentAnswer(document, objectId) {
  invalidateCoordinateLaws();
  const engine = engineFor(document);
  const extent = resolveObjectExtent(document, engine, objectId);
  // The melt this harness checks on the way past: every shape the JavaScript
  // builds assigns the SAME spread to the start and to the end, which is why the
  // port carries one field. A case where they differ would show up here.
  const symmetric =
    text(extent.spread?.start?.before) === text(extent.spread?.end?.before) &&
    text(extent.spread?.start?.after) === text(extent.spread?.end?.after);
  return {
    source: extent.source,
    derivedMagnitude: extent.derivedMagnitude,
    startDays: text(extent.startDays),
    endDays: text(extent.endDays),
    magnitudeDays: text(extent.magnitudeDays),
    cyclic: extent.cyclic,
    frame: extent.frame ?? null,
    spreadBefore: text(extent.spread?.start?.before),
    spreadAfter: text(extent.spread?.start?.after),
    spreadSymmetric: symmetric,
    anchors: extent.anchors.map((anchor) => [anchor.role, text(anchor.days)]),
    overdetermined: extent.overdetermined.map((item) => [
      item.role,
      text(item.days),
      item.reason,
      item.staple ? "staple" : "relation"
    ]),
    unresolved: extent.unresolved.map((item) => [item.role, item.reason])
  };
}

function correspondenceAnswer(document, a, b) {
  invalidateCoordinateLaws();
  const engine = engineFor(document);
  const described = describeCorrespondence(document, a, b, engine);
  const entries = frameCorrespondences(document, a, b, engine);
  return {
    ...described,
    order: entries.map((entry) => entry.staple.id),
    from: entries.map((entry) => text(frameEndDays(engine, entry.from))),
    to: entries.map((entry) => text(frameEndDays(engine, entry.to)))
  };
}

function segmentAnswer(document, patternId) {
  invalidateCoordinateLaws();
  const engine = engineFor(document);
  const pattern = document.patterns[patternId];
  return {
    segments: seriesSegments(engine, pattern).map((segment) => [
      segment.index,
      text(segment.fromDays),
      text(segment.untilDays),
      segment.rrule?.FREQ ?? null,
      segment.closedBy?.id ?? null,
      segment.openedBy?.id ?? null
    ]),
    phase: text(seriesPhaseDays(engine, pattern))
  };
}

function exclusionAnswer(document, exclude, lower, upper) {
  invalidateCoordinateLaws();
  const engine = engineFor(document);
  const days = liveExclusionDays(engine, exclude, lower, upper);
  return { days: days === null ? null : [...days].sort() };
}

function eraAnswer(document, frameId) {
  invalidateCoordinateLaws();
  try {
    const ordered = eraChainFrames(document, frameId);
    const chain = eraChain(document, frameId);
    const context = frameEraContext(document, frameId);
    return {
      refusal: null,
      ordered,
      countable: chain ? chain.countable : [],
      pin: chain ? chain.pin : null,
      ranges: chain
        ? Object.fromEntries(
            [...chain.byFrame.entries()].map(([id, entry]) => [
              id,
              [
                entry.firstProper === null ? null : String(entry.firstProper),
                entry.lastProper === null ? null : String(entry.lastProper)
              ]
            ])
          )
        : {},
      context: context
        ? [context.countable, context.entry?.key ?? context.key ?? null]
        : null
    };
  } catch (error) {
    return { refusal: String(error.message ?? error) };
  }
}

// --- Case generators --------------------------------------------------------

const cases = [];
let divergentEraCases = 0;
let refusedPairCases = 0;

const ROLES = ["start", "end", "midpoint", "handover"];

function extentCase() {
  const world = new World();
  const duration = int(600);
  const placed = rnd() < 0.5;
  const objectId = world.object({
    duration: String(duration),
    placedAt: placed ? civil(2026, 1 + int(12), 1 + int(28), int(24), 0, 0) : null
  });
  const shape = int(10);
  let refusedPair = false;
  if (shape < 6) {
    // Anchors, one to three of them, at most one per role.
    const roles = [...ROLES].sort(() => rnd() - 0.5).slice(0, 1 + int(3));
    for (const role of roles) {
      const fuzzy = rnd() < 0.35;
      world.staple({
        kind: "anchor",
        ends: [
          { object: objectId, point: role },
          { frame: "calendar:work", coordinate: civil(2026, 8, 1 + int(20), int(24), 0, 0) }
        ],
        ...(fuzzy
          ? {
              spread: {
                before: magnitude(String(1 + int(30)), "second"),
                after: magnitude(String(1 + int(30)), "second")
              }
            }
          : {})
      });
    }
  } else if (shape < 8) {
    // A chain: this object follows another, which may itself be anchored.
    const upstream = world.object({
      duration: String(30 + int(120)),
      placedAt: civil(2026, 8, 1 + int(20), int(24), 0, 0)
    });
    world.staple({
      kind: "anchor",
      ends: [
        { object: objectId, point: pick(["start", "end"]) },
        { object: upstream, point: pick(["start", "end", "midpoint"]) }
      ]
    });
    if (rnd() < 0.4) {
      // Close the loop: neither side can be resolved, and both must say so.
      world.staple({
        kind: "anchor",
        ends: [
          { object: upstream, point: "start" },
          { object: objectId, point: "end" }
        ]
      });
    }
  } else if (shape === 8) {
    // R3's class: an anchor whose far end is a SERIES. `validateDocument` refuses
    // the pair; both derivations resolve it to nothing, for the same reason.
    refusedPair = true;
    const series = world.pattern({ templateAt: civil(2026, 1, 5, 9, 0, 0) });
    world.staple({
      kind: "anchor",
      ends: [{ object: objectId, point: pick(ROLES) }, { series }]
    });
  } else {
    // A kind that anchors nothing must not move the object.
    world.staple({
      kind: pick(["end", "phase", "correspondence", "succession"]),
      ends: [
        { object: objectId, point: pick(ROLES) },
        { frame: "calendar:work", coordinate: civil(2026, 8, 1 + int(20), int(24), 0, 0) }
      ]
    });
  }
  if (refusedPair) refusedPairCases += 1;
  cases.push({
    kind: "extent",
    document: world.document,
    object: objectId,
    refusedPair,
    expected: extentAnswer(world.document, objectId)
  });
}

function correspondenceCase() {
  const world = new World();
  const count = 1 + int(5);
  const selfLoop = rnd() < 0.2;
  for (let entry = 0; entry < count; entry += 1) {
    const form = int(6);
    const far =
      form === 0
        ? { frame: "calendar:work", void: true }
        : form === 1
          ? {
              frame: "calendar:work",
              selector: { cycle: "weekday", value: pick(["Tuesday", "Friday", "3"]) }
            }
          : form === 2
            ? {
                frame: "calendar:work",
                span: { from: civil(2026, 8, 1), to: civil(2026, 8, 20) }
              }
            : { frame: "calendar:work", coordinate: civil(2026, 8, 1 + int(27)) };
    world.staple({
      kind: "correspondence",
      ends: [
        { frame: "frame:invented", coordinate: strokeAt(1 + int(8), int(8)) },
        selfLoop
          ? { frame: "frame:invented", coordinate: strokeAt(9 + int(8), int(8)) }
          : far
      ]
    });
  }
  const counterpart = selfLoop ? "frame:invented" : "calendar:work";
  cases.push({
    kind: "correspondence",
    document: world.document,
    from: "frame:invented",
    to: counterpart,
    expected: correspondenceAnswer(world.document, "frame:invented", counterpart)
  });
}

function segmentCase() {
  const world = new World();
  const series = world.pattern({ templateAt: civil(2026, 1, 5, 9, 0, 0) });
  const count = 1 + int(3);
  const months = new Set();
  while (months.size < count) months.add(1 + int(12));
  for (const month of months) {
    const depth = int(4);
    const at =
      depth === 0
        ? civil(2026, month)
        : depth === 1
          ? civil(2026, month, 1 + int(28))
          : depth === 2
            ? civil(2026, month, 1 + int(28), int(24), 0, 0)
            : civil(2026);
    const carries = rnd() < 0.5;
    world.staple({
      kind: carries ? "inflection" : pick(["end", "inflection"]),
      ends: [{ series }, { frame: "calendar:work", coordinate: at }],
      ...(carries
        ? {
            payload: {
              rule: {
                rrule: { FREQ: pick(["DAILY", "MONTHLY"]) },
                coordinate: civil(2026, month, 16, 9, 0, 0)
              }
            }
          }
        : {})
    });
  }
  if (rnd() < 0.4) {
    world.staple({
      kind: "phase",
      ends: [
        { series },
        { frame: "calendar:work", coordinate: civil(2026, 3, 1 + int(27), 22, 0, 0) }
      ]
    });
  }
  cases.push({
    kind: "segments",
    document: world.document,
    pattern: series,
    expected: segmentAnswer(world.document, series)
  });
}

function exclusionCase() {
  const world = new World();
  world.document.frames["calendar:holidays"] = {
    id: "calendar:holidays",
    title: "Holidays",
    traits: ["set", "calendar"],
    basis: "frame:wall-time"
  };
  const count = 1 + int(4);
  for (let entry = 0; entry < count; entry += 1) {
    world.object({
      duration: String(int(4)),
      unit: "day",
      placedAt: civil(2026, 1 + int(12), 1 + int(27)),
      frame: "calendar:holidays"
    });
  }
  const exclude = rnd() < 0.5
    ? { frames: ["calendar:holidays"] }
    : { frame: "calendar:holidays" };
  const lower = Rational.parse(String(20400 + int(200)));
  const upper = lower.add(Rational.parse(String(30 + int(300))));
  cases.push({
    kind: "exclusions",
    document: world.document,
    exclude,
    lower: lower.toJSON(),
    upper: upper.toJSON(),
    expected: exclusionAnswer(world.document, exclude, lower, upper)
  });
}

function eraCase() {
  const world = new World();
  const roles = rnd() < 0.75;
  const length = 2 + int(6);
  const lengths = [];
  for (let era = 0; era < length; era += 1) lengths.push(1 + int(4000));
  const pin = int(length);
  const pinYear = 1 + int(lengths[pin]);
  const pinProper = -2000 + int(6000);
  const ids = [];
  for (let era = 0; era < length; era += 1) ids.push(`era:${era}`);
  for (let era = 0; era < length; era += 1) {
    world.era(
      ids[era],
      {
        key: `E${era}`,
        name: `The E${era} era`,
        direction: "ascending",
        years: String(lengths[era]),
        firstYear: "1",
        ...(era === pin
          ? { anchor: { year: String(pinYear), properYear: String(pinProper) } }
          : {})
      },
      era === 0 ? null : ids[era - 1],
      roles
    );
  }
  // Mutations, each of which must refuse with its own sentence.
  const mutation = int(6);
  if (mutation === 1) {
    world.staple({
      kind: "succession",
      ends: roles
        ? [
            { frame: ids[0], role: "end" },
            { frame: ids[length - 1], role: "start" }
          ]
        : [{ frame: ids[0] }, { frame: ids[length - 1] }]
    });
  } else if (mutation === 2) {
    world.staple({
      kind: "succession",
      ends: roles
        ? [
            { frame: ids[length - 1], role: "end" },
            { frame: ids[0], role: "start" }
          ]
        : [{ frame: ids[length - 1] }, { frame: ids[0] }]
    });
  } else if (mutation === 3) {
    const other = (pin + 1) % length;
    world.document.frames[ids[other]].era.anchor = { year: "1", properYear: "1" };
  } else if (mutation === 4) {
    delete world.document.frames[ids[pin]].era.anchor;
  } else if (mutation === 5) {
    world.document.frames[ids[int(length)]].era.countable = false;
  }
  const asked = ids[int(length)];
  if (!roles) divergentEraCases += 1;
  cases.push({
    kind: "era",
    document: world.document,
    frame: asked,
    divergent: !roles,
    expected: eraAnswer(world.document, asked)
  });
}

for (let i = 0; i < 500; i += 1) extentCase();
for (let i = 0; i < 300; i += 1) correspondenceCase();
for (let i = 0; i < 300; i += 1) segmentCase();
for (let i = 0; i < 150; i += 1) exclusionCase();
for (let i = 0; i < 350; i += 1) eraCase();

process.stdout.write(
  JSON.stringify(
    {
      seed: SEED,
      generated: cases.length,
      divergentEraCases,
      refusedPairCases,
      cases
    },
    null,
    0
  )
);
