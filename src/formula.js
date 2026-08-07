import {
  Rational,
  ZERO,
  ONE,
  PI,
  TAU,
  cosExact,
  sinExact,
  sqrtExact
} from "./exact.js";

class Tokenizer {
  constructor(source) {
    this.source = String(source);
    this.index = 0;
    this.current = null;
  }

  skipSpace() {
    while (this.index < this.source.length) {
      if (/\s/.test(this.source[this.index])) {
        this.index += 1;
        continue;
      }
      if (this.source.startsWith("//", this.index)) {
        const end = this.source.indexOf("\n", this.index + 2);
        this.index = end < 0 ? this.source.length : end + 1;
        continue;
      }
      if (this.source.startsWith("/*", this.index)) {
        const end = this.source.indexOf("*/", this.index + 2);
        if (end < 0) throw new SyntaxError("Unclosed block comment");
        this.index = end + 2;
        continue;
      }
      break;
    }
  }

  read() {
    this.skipSpace();
    const start = this.index;
    if (start >= this.source.length) return { type: "eof", value: "", start, end: start };
    const rest = this.source.slice(start);

    const number = /^(?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?/.exec(rest);
    if (number) {
      this.index += number[0].length;
      return { type: "number", value: number[0], start, end: this.index };
    }

    const identifier = /^[A-Za-z_][A-Za-z0-9_]*/.exec(rest);
    if (identifier) {
      this.index += identifier[0].length;
      return { type: "identifier", value: identifier[0], start, end: this.index };
    }

    const quote = this.source[start];
    if (quote === '"' || quote === "'") {
      this.index += 1;
      let value = "";
      while (this.index < this.source.length) {
        const char = this.source[this.index++];
        if (char === quote) return { type: "string", value, start, end: this.index };
        if (char === "\\") {
          const escaped = this.source[this.index++];
          const escapes = { n: "\n", r: "\r", t: "\t", "\\": "\\", '"': '"', "'": "'" };
          value += escapes[escaped] ?? escaped;
        } else {
          value += char;
        }
      }
      throw new SyntaxError(`Unclosed string at ${start}`);
    }

    for (const operator of ["==", "!=", "<=", ">=", "&&", "||", "=>"]) {
      if (rest.startsWith(operator)) {
        this.index += operator.length;
        return { type: "operator", value: operator, start, end: this.index };
      }
    }
    if ("+-*/%^<>=!?:.,;()[]{}".includes(quote)) {
      this.index += 1;
      return { type: "operator", value: quote, start, end: this.index };
    }
    throw new SyntaxError(`Unexpected character ${JSON.stringify(quote)} at ${start}`);
  }

  peek() {
    this.current ||= this.read();
    return this.current;
  }

  next() {
    const token = this.peek();
    this.current = null;
    return token;
  }
}

const PRECEDENCE = {
  "||": 1,
  "&&": 2,
  "==": 3,
  "!=": 3,
  "<": 4,
  "<=": 4,
  ">": 4,
  ">=": 4,
  "+": 5,
  "-": 5,
  "*": 6,
  "/": 6,
  "%": 6,
  "^": 7
};

class Parser {
  constructor(source) {
    this.tokens = new Tokenizer(source);
  }

  match(value) {
    if (this.tokens.peek().value !== value) return false;
    this.tokens.next();
    return true;
  }

  expect(value) {
    const token = this.tokens.next();
    if (token.value !== value) {
      throw new SyntaxError(`Expected ${value} at ${token.start}, found ${token.value || "end of source"}`);
    }
    return token;
  }

  identifier() {
    const token = this.tokens.next();
    if (token.type !== "identifier") throw new SyntaxError(`Expected a name at ${token.start}`);
    return token.value;
  }

  module() {
    const declarations = [];
    while (this.tokens.peek().type !== "eof") {
      const exported = this.match("export");
      if (this.match("const")) {
        const name = this.identifier();
        this.expect("=");
        const value = this.expression();
        this.match(";");
        declarations.push({ type: "const", name, value, exported });
        continue;
      }
      if (this.match("fn")) {
        const name = this.identifier();
        this.expect("(");
        const parameters = [];
        if (!this.match(")")) {
          do parameters.push(this.identifier()); while (this.match(","));
          this.expect(")");
        }
        this.expect("=");
        const body = this.expression();
        this.match(";");
        declarations.push({ type: "fn", name, parameters, body, exported });
        continue;
      }
      const token = this.tokens.peek();
      throw new SyntaxError(`Expected const or fn at ${token.start}`);
    }
    return { type: "module", declarations };
  }

  expression(minimum = 0) {
    let left = this.prefix();
    while (true) {
      const token = this.tokens.peek();
      if (token.value === "?") {
        if (minimum > 0) break;
        this.tokens.next();
        const yes = this.expression();
        this.expect(":");
        const no = this.expression();
        left = { type: "conditional", condition: left, yes, no };
        continue;
      }
      const precedence = PRECEDENCE[token.value];
      if (!precedence || precedence < minimum) break;
      this.tokens.next();
      const right = this.expression(precedence + (token.value === "^" ? 0 : 1));
      left = { type: "binary", operator: token.value, left, right };
    }
    return left;
  }

  prefix() {
    const token = this.tokens.next();
    let node;
    if (token.type === "number") {
      node = { type: "literal", value: Rational.parse(token.value) };
    } else if (token.type === "string") {
      node = { type: "literal", value: token.value };
    } else if (token.value === "true" || token.value === "false") {
      node = { type: "literal", value: token.value === "true" };
    } else if (token.value === "null") {
      node = { type: "literal", value: null };
    } else if (token.value === "if") {
      this.expect("(");
      const condition = this.expression();
      this.expect(")");
      const yes = this.expression();
      this.expect("else");
      const no = this.expression();
      node = { type: "conditional", condition, yes, no };
    } else if (token.value === "-" || token.value === "+" || token.value === "!") {
      node = { type: "unary", operator: token.value, value: this.expression(8) };
    } else if (token.value === "(") {
      node = this.expression();
      this.expect(")");
    } else if (token.value === "[") {
      node = this.array();
    } else if (token.value === "{") {
      node = this.record();
    } else if (token.type === "identifier") {
      node = { type: "name", name: token.value };
    } else {
      throw new SyntaxError(`Unexpected token ${token.value || "end of source"} at ${token.start}`);
    }
    return this.postfix(node);
  }

  postfix(node) {
    while (true) {
      if (this.match("(")) {
        const arguments_ = [];
        if (!this.match(")")) {
          do arguments_.push(this.expression()); while (this.match(","));
          this.expect(")");
        }
        node = { type: "call", callee: node, arguments: arguments_ };
      } else if (this.match(".")) {
        node = { type: "member", object: node, property: this.identifier() };
      } else if (this.match("[")) {
        const index = this.expression();
        this.expect("]");
        node = { type: "index", object: node, index };
      } else {
        break;
      }
    }
    return node;
  }

  array() {
    if (this.match("]")) return { type: "array", items: [] };
    const first = this.expression();
    if (this.match("for")) {
      const name = this.identifier();
      this.expect("in");
      const iterable = this.expression();
      const filter = this.match("if") ? this.expression() : null;
      this.expect("]");
      return { type: "comprehension", value: first, name, iterable, filter };
    }
    const items = [first];
    while (this.match(",")) {
      if (this.tokens.peek().value === "]") break;
      items.push(this.expression());
    }
    this.expect("]");
    return { type: "array", items };
  }

  record() {
    const entries = [];
    if (this.match("}")) return { type: "record", entries };
    do {
      const token = this.tokens.next();
      if (!["identifier", "string"].includes(token.type)) {
        throw new SyntaxError(`Expected a record key at ${token.start}`);
      }
      this.expect(":");
      entries.push([token.value, this.expression()]);
    } while (this.match(",") && this.tokens.peek().value !== "}");
    this.expect("}");
    return { type: "record", entries };
  }
}

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

  instantiate(ast) {
    const runtime = this;
    const global = new Environment();
    const builtins = this.builtins();
    for (const [name, value] of Object.entries(builtins)) global.define(name, value);
    const exports = {};
    const state = { fuel: this.defaultFuel, emitted: 0 };

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
        const callState = { fuel: runtime.defaultFuel, emitted: 0 };
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

  assertOutputSize(value) {
    let count = 0;
    const stack = [value];
    while (stack.length) {
      const current = stack.pop();
      count += 1;
      if (count > this.outputLimit) throw new RangeError("Formula output limit exceeded");
      if (Array.isArray(current)) stack.push(...current);
      else if (current && typeof current === "object" && !isRational(current)) {
        stack.push(...Object.values(current));
      }
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
          output.push(this.evaluate(node.value, scope, state));
          state.emitted += 1;
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
    this.burn(state, 2);
    if (typeof callable === "function" && callable.formulaBuiltin) return callable(...arguments_);
    if (!callable?.formulaFunction) throw new TypeError("Value is not callable");
    const scope = new Environment(callable.closure);
    callable.parameters.forEach((name, index) => scope.define(name, arguments_[index] ?? null));
    return this.evaluate(callable.body, scope, state);
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
    return builtins;
  }
}

export function parseFormula(source) {
  return new Parser(source).module();
}

export function executeFormula(source, exportName, context, options) {
  return new FormulaRuntime(options).compile(source).call(exportName, [context]);
}
