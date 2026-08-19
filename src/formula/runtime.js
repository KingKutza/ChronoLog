// Sandboxed evaluator for chronolog-formula/1: walks the AST produced by
// ./parser.js against exact rational values only. No `eval`/`Function`, no
// ambient host access — every name a formula can see comes from `builtins()`
// or its own module scope. Fuel, call-depth, parse-depth, and output-size
// limits bound every program the same way regardless of source.

import {
  Rational,
  ONE,
  PI,
  TAU,
  cosExact,
  sinExact,
  sqrtExact
} from "../exact.js";
import { Parser } from "./parser.js";

const MAX_CALL_DEPTH = 200;
const TRANSCENDENTAL_FUEL = 256;

class Environment {
  constructor(parent = null) {
    this.parent = parent;
    this.values = new Map();
  }

  define(name, value) {
    this.values.set(name, value);
  }

  get(name) {
    if (this.values.has(name)) return this.values.get(name);
    if (this.parent) return this.parent.get(name);
    throw new ReferenceError(`Unknown formula name: ${name}`);
  }
}

function isRational(value) {
  return value instanceof Rational;
}

function numeric(value) {
  if (isRational(value)) return value;
  if (typeof value === "bigint" || typeof value === "number") return Rational.parse(value);
  if (typeof value === "string" && /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?(?:\/\d+)?$/.test(value)) {
    return Rational.parse(value);
  }
  throw new TypeError(`Expected a number, received ${typeof value}`);
}

function truthy(value) {
  if (isRational(value)) return !value.isZero();
  return Boolean(value);
}

function equal(left, right) {
  if (isRational(left) || isRational(right)) {
    try {
      return numeric(left).compare(numeric(right)) === 0;
    } catch {
      return false;
    }
  }
  return left === right;
}

function stringify(value) {
  if (isRational(value)) return value.toJSON();
  if (value === null) return "null";
  if (typeof value === "object") return JSON.stringify(toPlain(value));
  return String(value);
}

function toPlain(value) {
  if (isRational(value)) return value.toJSON();
  if (Array.isArray(value)) return value.map(toPlain);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, toPlain(item)]));
  }
  return value;
}

function deepInput(value) {
  if (Array.isArray(value)) return value.map(deepInput);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, deepInput(item)]));
  }
  return value;
}

function safeMember(object, property) {
  const key = String(property);
  if (["__proto__", "prototype", "constructor"].includes(key)) {
    throw new TypeError(`Formula access to ${key} is forbidden`);
  }
  if (
    (typeof object !== "object" && typeof object !== "string")
    || object === null
    || !Object.prototype.hasOwnProperty.call(object, key)
  ) {
    throw new TypeError(`Formula value has no field ${key}`);
  }
  return object[key];
}

export class FormulaRuntime {
  constructor({
    fuel = 250_000,
    outputLimit = 20_000,
    precision = 30,
    maxIntegerDigits = 4096
  } = {}) {
    this.defaultFuel = fuel;
    this.outputLimit = outputLimit;
    this.precision = precision;
    this.maxIntegerDigits = maxIntegerDigits;
    this.cache = new Map();
    // A separate cache from `this.cache`: a module's source and a bare
    // expression's source are both plain strings, and the same text could in
    // principle be handed to both `compile()` and `compileExpression()` (a
    // lone name is a valid expression but not a valid module), so keying
    // them together would risk one call site handing the other a cached AST
    // of the wrong shape.
    this.expressionCache = new Map();
  }

  parse(source) {
    return new Parser(source).module();
  }

  compile(source) {
    if (this.cache.has(source)) return this.cache.get(source);
    const ast = this.parse(source);
    const module = this.instantiate(ast);
    this.cache.set(source, module);
    return module;
  }

  // A bare expression -- `w * 1.5 + 0.5`, not a `const`/`fn` module -- for
  // callers (the weight-formula pipeline, so far) that just want one value
  // back rather than an exported module surface. `expression()` only reads
  // as much as forms one expression; anything left over is trailing garbage
  // (`1 + 1)` or `2 2`) that would otherwise be silently discarded rather
  // than rejected, so the next token after the expression must be EOF or
  // parsing fails the same way a truncated program should.
  compileExpression(source) {
    if (this.expressionCache.has(source)) return this.expressionCache.get(source);
    const parser = new Parser(source);
    const ast = parser.expression();
    const trailing = parser.tokens.next();
    if (trailing.type !== "eof") {
      throw new SyntaxError(`Unexpected trailing input ${trailing.value || "token"} at ${trailing.start}`);
    }
    this.expressionCache.set(source, ast);
    return ast;
  }

  // Evaluates a bare expression against a supplied variable map, sandboxed
  // exactly like a module call: the same `builtins()`, the same fuel/depth/
  // output-size limits (`evaluate()`, `assertOutputSize()`), no ambient host
  // access. A weight formula runs once per contributing frame per fact per
  // render, so this is on a hot path -- `compileExpression` above is what
  // keeps repeated calls with the same source from re-parsing every time.
  //
  // Returns a plain JS value at the boundary rather than a `Rational`: a
  // numeric result is rounded through the usual `limitNumber` discipline and
  // converted with `toNumber()` so callers never have to know this runtime
  // deals in exact rationals internally; a non-numeric result (a string, a
  // boolean, a record) is unwrapped with the same `toPlain()` every module
  // call already returns.
  evaluateExpression(source, variables = {}) {
    const ast = this.compileExpression(source);
    const global = new Environment();
    for (const [name, value] of Object.entries(this.builtins())) global.define(name, value);
    for (const [name, value] of Object.entries(variables)) global.define(name, deepInput(value));
    const state = { fuel: this.defaultFuel, emitted: 0, depth: 0 };
    const result = this.evaluate(ast, global, state);
    this.assertOutputSize(result);
    return isRational(result) ? this.limitNumber(result).toNumber() : toPlain(result);
  }

  instantiate(ast) {
    const runtime = this;
    const global = new Environment();
    const builtins = this.builtins();
    for (const [name, value] of Object.entries(builtins)) global.define(name, value);
    const exports = {};
    const state = { fuel: this.defaultFuel, emitted: 0, depth: 0 };

    for (const declaration of ast.declarations) {
      if (declaration.type === "const") {
        const value = this.evaluate(declaration.value, global, state);
        global.define(declaration.name, value);
        if (declaration.exported) exports[declaration.name] = value;
      } else {
        const callable = {
          formulaFunction: true,
          name: declaration.name,
          parameters: declaration.parameters,
          body: declaration.body,
          closure: global
        };
        global.define(declaration.name, callable);
        if (declaration.exported) exports[declaration.name] = callable;
      }
    }
    return {
      exports,
      call(name, arguments_ = []) {
        const callable = exports[name];
        if (!callable) throw new Error(`Formula module does not export ${name}`);
        const callState = { fuel: runtime.defaultFuel, emitted: 0, depth: 0 };
        const result = runtime.invoke(callable, arguments_.map(deepInput), callState);
        runtime.assertOutputSize(result);
        return toPlain(result);
      }
    };
  }

  burn(state, amount = 1) {
    state.fuel -= amount;
    if (state.fuel < 0) throw new RangeError("Formula fuel limit exceeded");
  }

  limitNumber(value) {
    const result = numeric(value);
    if (
      result.n.toString().replace("-", "").length > this.maxIntegerDigits
      || result.d.toString().length > this.maxIntegerDigits
    ) {
      throw new RangeError("Formula numeric size limit exceeded");
    }
    return result;
  }

  countCells(value) {
    let count = 0;
    const stack = [value];
    while (stack.length) {
      const current = stack.pop();
      count += 1;
      if (count > this.outputLimit) return count;
      if (Array.isArray(current)) stack.push(...current);
      else if (current && typeof current === "object" && !isRational(current)) {
        stack.push(...Object.values(current));
      }
    }
    return count;
  }

  assertOutputSize(value) {
    if (this.countCells(value) > this.outputLimit) {
      throw new RangeError("Formula output limit exceeded");
    }
  }

  evaluate(node, environment, state) {
    this.burn(state);
    switch (node.type) {
      case "literal":
        return isRational(node.value) ? this.limitNumber(node.value) : node.value;
      case "name":
        return environment.get(node.name);
      case "array":
        return node.items.map((item) => this.evaluate(item, environment, state));
      case "record":
        return Object.fromEntries(
          node.entries.map(([key, value]) => [key, this.evaluate(value, environment, state)])
        );
      case "unary": {
        const value = this.evaluate(node.value, environment, state);
        if (node.operator === "!") return !truthy(value);
        if (node.operator === "-") return this.limitNumber(numeric(value).neg());
        return this.limitNumber(value);
      }
      case "binary":
        return this.binary(node, environment, state);
      case "conditional":
        return this.evaluate(
          truthy(this.evaluate(node.condition, environment, state)) ? node.yes : node.no,
          environment,
          state
        );
      case "member": {
        const object = this.evaluate(node.object, environment, state);
        if (object === null || object === undefined) throw new TypeError(`Cannot read ${node.property}`);
        return safeMember(object, node.property);
      }
      case "index": {
        const object = this.evaluate(node.object, environment, state);
        const indexValue = this.evaluate(node.index, environment, state);
        const index = isRational(indexValue) && indexValue.d === 1n ? Number(indexValue.n) : indexValue;
        return safeMember(object, index);
      }
      case "call": {
        const callable = this.evaluate(node.callee, environment, state);
        const arguments_ = node.arguments.map((argument) => this.evaluate(argument, environment, state));
        return this.invoke(callable, arguments_, state);
      }
      case "comprehension": {
        const iterable = this.evaluate(node.iterable, environment, state);
        if (!Array.isArray(iterable)) throw new TypeError("A comprehension source must be a list");
        const output = [];
        for (const item of iterable) {
          this.burn(state);
          const scope = new Environment(environment);
          scope.define(node.name, item);
          if (node.filter && !truthy(this.evaluate(node.filter, scope, state))) continue;
          const produced = this.evaluate(node.value, scope, state);
          output.push(produced);
          state.emitted += this.countCells(produced);
          if (state.emitted > this.outputLimit) throw new RangeError("Formula output limit exceeded");
        }
        return output;
      }
      default:
        throw new Error(`Unknown AST node ${node.type}`);
    }
  }

  binary(node, environment, state) {
    if (node.operator === "&&") {
      const left = this.evaluate(node.left, environment, state);
      return truthy(left) ? this.evaluate(node.right, environment, state) : left;
    }
    if (node.operator === "||") {
      const left = this.evaluate(node.left, environment, state);
      return truthy(left) ? left : this.evaluate(node.right, environment, state);
    }
    const left = this.evaluate(node.left, environment, state);
    const right = this.evaluate(node.right, environment, state);
    switch (node.operator) {
      case "+":
        if (typeof left === "string" || typeof right === "string") return stringify(left) + stringify(right);
        return this.limitNumber(numeric(left).add(numeric(right)));
      case "-":
        return this.limitNumber(numeric(left).sub(numeric(right)));
      case "*":
        return this.limitNumber(numeric(left).mul(numeric(right)));
      case "/":
        return this.limitNumber(numeric(left).div(numeric(right)));
      case "%":
        return this.limitNumber(numeric(left).mod(numeric(right)));
      case "^": {
        const exponent = numeric(right);
        if (exponent.d !== 1n) throw new TypeError("Exponent must be an integer");
        if (exponent.n > BigInt(this.maxIntegerDigits * 4) || exponent.n < BigInt(-this.maxIntegerDigits * 4)) {
          throw new RangeError("Formula exponent limit exceeded");
        }
        return this.limitNumber(numeric(left).pow(exponent.n));
      }
      case "==":
        return equal(left, right);
      case "!=":
        return !equal(left, right);
      case "<":
        return numeric(left).compare(numeric(right)) < 0;
      case "<=":
        return numeric(left).compare(numeric(right)) <= 0;
      case ">":
        return numeric(left).compare(numeric(right)) > 0;
      case ">=":
        return numeric(left).compare(numeric(right)) >= 0;
      default:
        throw new Error(`Unknown operator ${node.operator}`);
    }
  }

  invoke(callable, arguments_, state) {
    this.burn(state, callable?.formulaCost ?? 2);
    if (typeof callable === "function" && callable.formulaBuiltin) return callable(...arguments_);
    if (!callable?.formulaFunction) throw new TypeError("Value is not callable");
    if (state.depth >= MAX_CALL_DEPTH) throw new RangeError("Formula call depth limit exceeded");
    state.depth += 1;
    try {
      const scope = new Environment(callable.closure);
      callable.parameters.forEach((name, index) => scope.define(name, arguments_[index] ?? null));
      return this.evaluate(callable.body, scope, state);
    } finally {
      state.depth -= 1;
    }
  }

  builtins() {
    const limited = (value) => this.limitNumber(value);
    const boundedRange = (startValue, endValue, stepValue = ONE) => {
      const start = numeric(startValue);
      const end = numeric(endValue);
      const step = numeric(stepValue);
      if (start.d !== 1n || end.d !== 1n || step.d !== 1n || step.isZero()) {
        throw new TypeError("range requires integer arguments and a nonzero step");
      }
      const count = Number((end.n - start.n) / step.n);
      if (!Number.isSafeInteger(count) || Math.abs(count) > this.outputLimit) {
        throw new RangeError("range exceeds output limit");
      }
      const output = [];
      if (step.n > 0n) {
        for (let value = start.n; value < end.n; value += step.n) output.push(new Rational(value));
      } else {
        for (let value = start.n; value > end.n; value += step.n) output.push(new Rational(value));
      }
      return output;
    };

    const builtins = {
      pi: PI,
      tau: TAU,
      true: true,
      false: false,
      num: limited,
      str: stringify,
      floor: (value) => limited(new Rational(numeric(value).floor())),
      ceil: (value) => limited(new Rational(numeric(value).ceil())),
      abs: (value) => limited(numeric(value).abs()),
      mod: (value, divisor) => limited(numeric(value).mod(numeric(divisor))),
      min: (...values) => limited(values.map(numeric).reduce((a, b) => a.compare(b) <= 0 ? a : b)),
      max: (...values) => limited(values.map(numeric).reduce((a, b) => a.compare(b) >= 0 ? a : b)),
      sin: (value) => limited(sinExact(numeric(value), this.precision)),
      cos: (value) => limited(cosExact(numeric(value), this.precision)),
      sqrt: (value) => limited(sqrtExact(numeric(value), this.precision)),
      len: (value) => new Rational(BigInt(value?.length ?? Object.keys(value || {}).length)),
      concat: (...values) => values.flat(Infinity),
      range: boundedRange,
      rangeCycles: (fromValue, toValue, epochValue, periodValue) => {
        const from = numeric(fromValue);
        const to = numeric(toValue);
        const epoch = numeric(epochValue);
        const period = numeric(periodValue);
        const first = from.sub(epoch).div(period).floor() - 1n;
        const last = to.sub(epoch).div(period).ceil() + 2n;
        return boundedRange(new Rational(first), new Rational(last));
      }
    };
    for (const value of Object.values(builtins)) {
      if (typeof value === "function") {
        Object.defineProperty(value, "formulaBuiltin", { value: true });
      }
    }
    for (const name of ["sin", "cos", "sqrt"]) {
      Object.defineProperty(builtins[name], "formulaCost", { value: TRANSCENDENTAL_FUEL });
    }
    return builtins;
  }
}
