import assert from "node:assert/strict";
import test from "node:test";
import { FormulaRuntime } from "../src/formula.js";

// Item (1) of the 8.19 weight-as-formula wave: `chronolog-formula/1` gains a
// bare-expression entry point (`evaluateExpression`) alongside its existing
// module (`const`/`fn`) entry point, for callers -- the weight-formula
// pipeline so far -- that just want one value back from one expression, not
// an exported module surface.

test("evaluateExpression evaluates a bare expression against supplied variables", () => {
  const runtime = new FormulaRuntime();
  assert.equal(runtime.evaluateExpression("w * 1.5 + 0.5", { w: 2 }), 3.5);
  assert.equal(runtime.evaluateExpression("(w + 1) * 2", { w: 3 }), 8);
});

test("evaluateExpression honors real operator precedence (PEMDAS), not left-to-right folding", () => {
  const runtime = new FormulaRuntime();
  // 2 + 3 * 4 = 14, not (2 + 3) * 4 = 20 -- proves the real parser's
  // precedence table is in effect, not some flattened left-to-right walk.
  assert.equal(runtime.evaluateExpression("2 + 3 * 4"), 14);
  assert.equal(runtime.evaluateExpression("(2 + 3) * 4"), 20);
  assert.equal(runtime.evaluateExpression("2 ^ 3 ^ 2"), 512, "^ is right-associative: 2^(3^2), not (2^3)^2");
});

test("evaluateExpression rejects trailing garbage instead of silently truncating", () => {
  const runtime = new FormulaRuntime();
  assert.throws(() => runtime.evaluateExpression("1 + 1) + 2"), SyntaxError);
  assert.throws(() => runtime.evaluateExpression("2 2"), SyntaxError);
  // A single valid expression with nothing left over still works.
  assert.equal(runtime.evaluateExpression("1 + 1"), 2);
});

test("evaluateExpression caches the compiled AST by source, keeping a per-call parse cost off the hot path", () => {
  const runtime = new FormulaRuntime();
  const source = "w * 2 + 1";
  const first = runtime.compileExpression(source);
  const second = runtime.compileExpression(source);
  assert.equal(first, second, "the same source string returns the identical cached AST object");
  assert.equal(runtime.evaluateExpression(source, { w: 5 }), 11);
});

test("a module cache entry and an expression cache entry never collide on the same source text", () => {
  const runtime = new FormulaRuntime();
  // "w" alone is a valid expression (a bare name) but not a valid module
  // (no top-level const/fn) -- exercising both entry points with the same
  // source string proves the two caches are independent.
  assert.throws(() => runtime.compile("w"), SyntaxError);
  assert.equal(runtime.evaluateExpression("w", { w: 9 }), 9);
});

test("evaluateExpression stays inside the sandbox: no ambient host access, same as module evaluation", () => {
  const runtime = new FormulaRuntime();
  assert.throws(() => runtime.evaluateExpression("window"), /Unknown formula name/);
  assert.throws(() => runtime.evaluateExpression("ctx.constructor", { ctx: {} }), /forbidden/);
});

test("evaluateExpression is bounded by the same fuel and numeric-size limits as a module call", () => {
  const bounded = new FormulaRuntime({ maxIntegerDigits: 24 });
  assert.throws(() => bounded.evaluateExpression("2 ^ 1000"), /limit/);
  const starved = new FormulaRuntime({ fuel: 1 });
  assert.throws(() => starved.evaluateExpression("1 + 1 + 1 + 1 + 1"), /fuel/);
});
