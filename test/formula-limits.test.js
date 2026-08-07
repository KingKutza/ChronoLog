import test from "node:test";
import assert from "node:assert/strict";
import { FormulaRuntime } from "../src/formula.js";

test("deeply nested source fails with a clean parse error, not a stack overflow", () => {
  const runtime = new FormulaRuntime();
  const source = `export const value = ${"(".repeat(100_000)}1${")".repeat(100_000)};`;
  assert.throws(() => runtime.compile(source), /deeply nested/);
});

test("moderate nesting stays below the parse depth cap", () => {
  const runtime = new FormulaRuntime();
  const module = runtime.compile(`export const value = ${"(".repeat(100)}1${")".repeat(100)};`);
  assert.equal(module.exports.value.toJSON(), "1");
});

test("runaway formula recursion stops at the call depth cap", () => {
  const runtime = new FormulaRuntime();
  const module = runtime.compile(`
    fn f(x) = f(x + 1);
    export fn state(ctx) = f(0);
  `);
  assert.throws(() => module.call("state", [{}]), /call depth/);
});

test("bounded recursion within the call depth cap still succeeds", () => {
  const runtime = new FormulaRuntime();
  const module = runtime.compile(`
    fn count(x) = x >= 150 ? x : count(x + 1);
    export fn state(ctx) = count(0);
  `);
  assert.deepEqual(module.call("state", [{}]), "150");
});

test("transcendental builtins burn fuel proportional to their real cost", () => {
  const runtime = new FormulaRuntime({ fuel: 4000 });
  const module = runtime.compile(`export fn facts(ctx) = [sqrt(k + 1) for k in range(0, 100)];`);
  assert.throws(() => module.call("facts", [{}]), /fuel limit/);
  const cheap = new FormulaRuntime({ fuel: 4000 })
    .compile(`export fn state(ctx) = { root: sqrt(2), sine: sin(1), cosine: cos(1) };`);
  assert.equal(typeof cheap.call("state", [{}]).root, "string");
});

test("comprehension output limit binds while cells are produced, not after", () => {
  const runtime = new FormulaRuntime({ outputLimit: 1000, fuel: 500 });
  const module = runtime.compile(`export fn facts(ctx) = [range(0, 1000) for k in range(0, 1000)];`);
  assert.throws(() => module.call("facts", [{}]), /output limit/);
});
