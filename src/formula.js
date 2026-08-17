// Public entry point for the sandboxed chronolog-formula/1 pattern language
// (no `eval`/`Function`, no ambient host access). Implementation is split by
// natural seam under ./formula/: tokenizer (lexer), parser (AST), runtime
// (sandboxed evaluator + builtins). This file preserves the historical
// import path and export surface for callers (src/engine.js, tests).

export { FormulaRuntime } from "./formula/runtime.js";
