// Lexer for chronolog-formula/1 source text: turns raw characters into a
// stream of { type, value, start, end } tokens. No knowledge of grammar or
// semantics lives here — that is the parser's and runtime's job.

export class Tokenizer {
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

    for (const operator of ["==", "!=", "<=", ">=", "&&", "||"]) {
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
