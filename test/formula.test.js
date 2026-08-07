import test from "node:test";
import assert from "node:assert/strict";
import { FormulaRuntime } from "../src/formula.js";

test("pure modules expose state and bounded fact comprehensions", () => {
  const runtime = new FormulaRuntime();
  const module = runtime.compile(`
    fn square(x) = x * x;
    export fn state(ctx) = { answer: square(num(ctx.value)) };
    export fn facts(ctx) = [
      { key: "n-" + str(k), value: square(k) }
      for k in range(0, 4)
    ];
  `);
  assert.deepEqual(module.call("state", [{ value: "7/2" }]), { answer: "49/4" });
  assert.deepEqual(module.call("facts", [{}]).map((item) => item.value), ["0", "1", "4", "9"]);
});

test("formula modules cannot reach host constructors or ambient globals", () => {
  const runtime = new FormulaRuntime();
  const module = runtime.compile(`export fn state(ctx) = ctx.constructor;`);
  assert.throws(() => module.call("state", [{}]), /forbidden/);
  assert.throws(() => runtime.compile(`export fn state(ctx) = window;`).call("state", [{}]), /Unknown formula name/);
});

test("fuel and output limits stop unbounded work", () => {
  const runtime = new FormulaRuntime({ outputLimit: 5 });
  const module = runtime.compile(`export fn facts(ctx) = [k for k in range(0, 9)];`);
  assert.throws(() => module.call("facts", [{}]), /output limit/);
  const numeric = new FormulaRuntime({ maxIntegerDigits: 24 })
    .compile(`export fn state(ctx) = 2 ^ 1000;`);
  assert.throws(() => numeric.call("state", [{}]), /limit/);
});
