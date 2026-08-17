// Recursive-descent parser for chronolog-formula/1: turns a token stream
// into an AST of plain { type, ... } nodes. Purely syntactic — no formula
// value ever exists until the runtime evaluates a node.

import { Rational } from "../exact.js";
import { Tokenizer } from "./tokenizer.js";

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

const MAX_PARSE_DEPTH = 500;

export class Parser {
  constructor(source) {
    this.tokens = new Tokenizer(source);
    this.depth = 0;
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
    if (this.depth >= MAX_PARSE_DEPTH) {
      throw new SyntaxError("Formula expression too deeply nested");
    }
    this.depth += 1;
    try {
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
    } finally {
      this.depth -= 1;
    }
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
