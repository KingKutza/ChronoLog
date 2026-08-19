import assert from "node:assert/strict";
import test from "node:test";
import { FormulaRuntime } from "../src/formula.js";
import {
  WEIGHT_VARIABLE,
  applyWeightFormula,
  defaultWeightForNewFrame,
  normalizeWeightFormula,
  resolveAuthoredWeight,
  validateWeightFormula,
  weightContributionOrder
} from "../src/weight-formula.js";

test("WEIGHT_VARIABLE is the canonical bound name", () => {
  assert.equal(WEIGHT_VARIABLE, "w");
});

test("normalizeWeightFormula: the sugar rule -- a number or numeric string n means w * n", () => {
  assert.equal(normalizeWeightFormula(4), "w * (4)");
  assert.equal(normalizeWeightFormula("4"), "w * (4)");
  assert.equal(normalizeWeightFormula(0.25), "w * (0.25)");
  assert.equal(normalizeWeightFormula("-2"), "w * (-2)");
});

test("normalizeWeightFormula: nothing authored is the identity formula", () => {
  assert.equal(normalizeWeightFormula(undefined), "w");
  assert.equal(normalizeWeightFormula(null), "w");
  assert.equal(normalizeWeightFormula(""), "w");
  assert.equal(normalizeWeightFormula("   "), "w");
});

test("normalizeWeightFormula: a non-numeric string is used verbatim", () => {
  assert.equal(normalizeWeightFormula("w + 0.5"), "w + 0.5");
  assert.equal(normalizeWeightFormula("(w + 1) * 2"), "(w + 1) * 2");
});

test("applyWeightFormula: sugar migration -- a plain numeric weight behaves exactly like w * n", () => {
  const runtime = new FormulaRuntime();
  assert.equal(applyWeightFormula(runtime, 4, 1), 4);
  assert.equal(applyWeightFormula(runtime, 0.25, 2), 0.5);
  assert.equal(applyWeightFormula(runtime, undefined, 7), 7, "no authored weight is the identity");
});

test("applyWeightFormula: additive and subtractive formulas work", () => {
  const runtime = new FormulaRuntime();
  assert.equal(applyWeightFormula(runtime, "w + 0.5", 1), 1.5);
  assert.equal(applyWeightFormula(runtime, "w - 0.5", 2), 1.5);
});

test("applyWeightFormula: PEMDAS is honored through the real parser, not a flattened evaluator", () => {
  const runtime = new FormulaRuntime();
  // If this fell back to naive left-to-right folding, w=2 would give
  // (2 + 1) * 2 = 6 instead of the correct precedence answer.
  assert.equal(applyWeightFormula(runtime, "w + 1 * 2", 2), 4);
  assert.equal(applyWeightFormula(runtime, "(w + 1) * 2", 2), 6);
});

test("applyWeightFormula: a broken formula contributes nothing -- it acts as identity, not a throw or a zero", () => {
  const runtime = new FormulaRuntime();
  assert.equal(applyWeightFormula(runtime, "w +", 5), 5, "unparseable formula");
  assert.equal(applyWeightFormula(runtime, "w * unknownName", 5), 5, "unresolvable name");
  assert.equal(applyWeightFormula(runtime, "w - 100", 5), 5, "a negative result falls back to identity");
  assert.equal(applyWeightFormula(runtime, "1 / 0 * w", 5), 5, "a division-by-zero formula falls back to identity");
});

test("applyWeightFormula: zero is a legitimate, non-identity result (a frame can demote to nothing)", () => {
  const runtime = new FormulaRuntime();
  assert.equal(applyWeightFormula(runtime, "w * 0", 5), 0);
});

test("validateWeightFormula: reports valid formulas and readable errors for invalid ones", () => {
  const runtime = new FormulaRuntime();
  assert.deepEqual(validateWeightFormula(runtime, "w * 1.5 + 0.5"), { valid: true, error: null });
  assert.deepEqual(validateWeightFormula(runtime, 4), { valid: true, error: null }, "sugar validates too");
  const invalid = validateWeightFormula(runtime, "w +");
  assert.equal(invalid.valid, false);
  assert.equal(typeof invalid.error, "string");
  assert.ok(invalid.error.length > 0);
});

test("resolveAuthoredWeight: identity input (blank, 1, or w) deletes the field", () => {
  const runtime = new FormulaRuntime();
  assert.equal(resolveAuthoredWeight(runtime, ""), undefined);
  assert.equal(resolveAuthoredWeight(runtime, "   "), undefined);
  assert.equal(resolveAuthoredWeight(runtime, "1"), undefined);
  assert.equal(resolveAuthoredWeight(runtime, "w"), undefined);
});

test("resolveAuthoredWeight: sugar stores a plain number, rejecting negatives with a readable message", () => {
  const runtime = new FormulaRuntime();
  assert.equal(resolveAuthoredWeight(runtime, "4"), 4);
  assert.equal(resolveAuthoredWeight(runtime, "0"), 0);
  assert.throws(() => resolveAuthoredWeight(runtime, "-2"), /zero or greater/);
});

test("resolveAuthoredWeight: a formula string is stored verbatim when valid, rejected with a readable message otherwise", () => {
  const runtime = new FormulaRuntime();
  assert.equal(resolveAuthoredWeight(runtime, "w + 0.5"), "w + 0.5");
  assert.throws(() => resolveAuthoredWeight(runtime, "w +"), /invalid/i);
});

test("defaultWeightForNewFrame: boosts only newly created groups and importance frames", () => {
  assert.equal(defaultWeightForNewFrame("group"), 1.5);
  assert.equal(defaultWeightForNewFrame("importance"), 1.5);
  assert.equal(defaultWeightForNewFrame("calendar"), undefined, "calendars are never boosted");
  assert.equal(defaultWeightForNewFrame("cycle"), undefined);
  assert.equal(defaultWeightForNewFrame("line"), undefined);
  assert.equal(defaultWeightForNewFrame("measure"), undefined);
  assert.equal(defaultWeightForNewFrame("other"), undefined);
});

// Application order: the ruled fold order is (1) ascending weightOrder,
// (2) descending group size, (3) frame id lexicographic tie-break.
function orderFixture({ frames = {}, sizes = {} } = {}) {
  const document = { frames };
  const engine = { displayGroupEventMembers: (id) => Array.from({ length: sizes[id] || 0 }) };
  return { document, engine };
}

test("weightContributionOrder: explicit weightOrder wins first, ascending", () => {
  const { document, engine } = orderFixture({
    frames: {
      "frame:b": { display: { weightOrder: 2 } },
      "frame:a": { display: { weightOrder: 1 } },
      "frame:c": { display: {} } // absent = 0, sorts before both
    }
  });
  assert.deepEqual(
    weightContributionOrder({ document, engine }, ["frame:b", "frame:a", "frame:c"]),
    ["frame:c", "frame:a", "frame:b"]
  );
});

test("weightContributionOrder: without an authored order, larger group membership applies first", () => {
  const { document, engine } = orderFixture({
    frames: { "frame:small": {}, "frame:large": {} },
    sizes: { "frame:small": 2, "frame:large": 12 }
  });
  assert.deepEqual(
    weightContributionOrder({ document, engine }, ["frame:small", "frame:large"]),
    ["frame:large", "frame:small"],
    "the larger group goes first, so the smaller/more specific group has the last word"
  );
});

test("weightContributionOrder: frame id is the final, deterministic tie-break", () => {
  const { document, engine } = orderFixture({ frames: { "frame:z": {}, "frame:a": {} } });
  assert.deepEqual(weightContributionOrder({ document, engine }, ["frame:z", "frame:a"]), ["frame:a", "frame:z"]);
});

test("weightContributionOrder: order is real -- mixed +/x formulas applied in the two possible orders give different answers", () => {
  const runtime = new FormulaRuntime();
  // frame:add applies "w + 1" (large group, applies first); frame:mul
  // applies "w * 2" (small group, applies last -- gets the final word).
  const largeFirst = orderFixture({
    frames: {
      "frame:add": { display: { weight: "w + 1" } },
      "frame:mul": { display: { weight: "w * 2" } }
    },
    sizes: { "frame:add": 10, "frame:mul": 1 }
  });
  const order = weightContributionOrder(largeFirst, ["frame:add", "frame:mul"]);
  assert.deepEqual(order, ["frame:add", "frame:mul"]);

  const fold = (context, ids, base) => {
    let weight = base;
    for (const id of weightContributionOrder(context, ids)) {
      weight = applyWeightFormula(runtime, context.document.frames[id].display.weight, weight);
    }
    return weight;
  };

  // Ruled order: (1 + 1) * 2 = 4.
  assert.equal(fold(largeFirst, ["frame:add", "frame:mul"], 1), 4);

  // The reversed order would give the other answer: 1 * 2 + 1 = 3 -- proving
  // the two orders are not interchangeable, i.e. order is a real, observable
  // part of the contract, not incidental.
  const reversed = { document: largeFirst.document, engine: { displayGroupEventMembers: () => [] } };
  let manualReversed = 1;
  for (const id of ["frame:mul", "frame:add"]) {
    manualReversed = applyWeightFormula(runtime, reversed.document.frames[id].display.weight, manualReversed);
  }
  assert.equal(manualReversed, 3);
  assert.notEqual(manualReversed, fold(largeFirst, ["frame:add", "frame:mul"], 1));
});

test("weightContributionOrder deduplicates its input", () => {
  const { document, engine } = orderFixture({ frames: { "frame:a": {} } });
  assert.deepEqual(weightContributionOrder({ document, engine }, ["frame:a", "frame:a"]), ["frame:a"]);
});
