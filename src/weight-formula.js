// The owner's ruling on display weight (LEXICON.md, the field report behind
// item #5): "there is no support for additive or subtractive values ... if I
// can describe with basic algebra how membership should alter a member, than
// I should be able to do that." This module is the model/derivation layer of
// that ruling -- a weight formula is a bare `chronolog-formula/1` expression
// (see `src/formula/runtime.js`'s `evaluateExpression`), evaluated with one
// bound variable, the incoming weight, and expected to hand back the weight
// this frame passes onward. No DOM, no document/engine reach-in -- callers
// (`src/visual-language.js`'s `factImportanceWeight`/`explainFactWeight`,
// the Frames-panel authoring form) supply everything this needs as plain
// values.
import { FormulaRuntime } from "./formula.js";

// The one name a weight formula can read: the weight arriving from the base
// verdict or from every prior frame's contribution, in application order
// (see `weightContributionOrder` below). Exported so every caller that
// builds or displays a formula -- the authoring form's field note included
// -- names it the same way instead of restating the string literal.
export const WEIGHT_VARIABLE = "w";

const PLAIN_NUMBER = /^[+-]?(?:\d+(?:\.\d+)?|\.\d+)$/;

// THE SUGAR RULE, and the migration it exists for: every `display.weight`
// shipped before formulas existed is a plain number `n`, and its meaning was
// always "multiply the incoming weight by n". Turning that same number into
// the formula `w * n` reproduces that meaning exactly -- no document is
// rewritten, no record needs to change shape, and a frame nobody has touched
// keeps composing exactly as it always did. A non-numeric string is assumed
// to already be an authored formula and is used verbatim. Nothing authored
// (`undefined`, `null`, an empty string) is the identity formula `w` --
// composing with it changes nothing, which is also what a missing knob has
// always meant here.
export function normalizeWeightFormula(value) {
  if (value === undefined || value === null) return WEIGHT_VARIABLE;
  if (typeof value === "number") {
    return Number.isFinite(value) ? `${WEIGHT_VARIABLE} * (${value})` : WEIGHT_VARIABLE;
  }
  const trimmed = String(value).trim();
  if (!trimmed) return WEIGHT_VARIABLE;
  if (PLAIN_NUMBER.test(trimmed)) return `${WEIGHT_VARIABLE} * (${trimmed})`;
  return trimmed;
}

// Evaluates one frame's authored weight value (raw -- a number, a formula
// string, or nothing) against the weight arriving into it, and returns the
// weight this frame hands onward.
//
// "A broken knob must never silently change what renders" (meaning is
// authored, never inferred; a parse error is not a meaning): an unparseable
// formula, an unknown name, a fuel/limit breach, or a finite-but-negative or
// non-finite result all fall back to `incomingWeight` unchanged -- the same
// no-op a frame with no `display.weight` at all has always produced. This is
// deliberately silent at this layer; `validateWeightFormula` is the place a
// caller asks "is this actually valid" so it can tell a user *before* the
// formula ever reaches this identity fallback.
export function applyWeightFormula(runtime, formulaSource, incomingWeight) {
  const source = normalizeWeightFormula(formulaSource);
  try {
    const result = runtime.evaluateExpression(source, { [WEIGHT_VARIABLE]: incomingWeight });
    if (typeof result !== "number" || !Number.isFinite(result) || result < 0) return incomingWeight;
    return result;
  } catch {
    return incomingWeight;
  }
}

// Authoring-time validation: parses and evaluates the formula a user just
// typed (sugar included) against a placeholder weight, so a bad formula gets
// a real error message at submit time instead of silently doing nothing the
// next time a fact renders. `w = 1` is an arbitrary but harmless probe value
// -- this checks that the formula *runs*, not that it behaves for every
// possible incoming weight (a formula can be well-formed and still divide by
// zero for some specific `w`; that is a runtime concern `applyWeightFormula`
// already guards, not an authoring-time one).
export function validateWeightFormula(runtime, source) {
  try {
    runtime.evaluateExpression(normalizeWeightFormula(source), { [WEIGHT_VARIABLE]: 1 });
    return { valid: true, error: null };
  } catch (error) {
    return { valid: false, error: error.message };
  }
}

// The Frames-panel weight field accepts a plain number (sugar) or a formula
// string, typed into one text input. This is the single place that decides
// what gets stored for a given piece of typed input, so the field's submit
// handler and any future authoring surface make the same call for the same
// text -- including the storage-economy rule that an input meaning identity
// (blank, `1`, or `w` itself) deletes `display.weight` rather than keeping a
// redundant no-op record field.
//
// Returns the value to assign to `display.weight`, or `undefined` when the
// field should be deleted. Throws a plain `Error` with a message meant to be
// shown to the user (the same way the field's old "Display weight must be
// zero or greater." message always has) when the input cannot be stored:
// sugar with a negative or non-finite number, or a formula that fails
// `validateWeightFormula`.
export function resolveAuthoredWeight(runtime, rawInput) {
  const input = String(rawInput ?? "").trim();
  if (!input || input === "1" || input === WEIGHT_VARIABLE) return undefined;
  if (PLAIN_NUMBER.test(input)) {
    const numeric = Number(input);
    if (!Number.isFinite(numeric) || numeric < 0) {
      throw new Error("Display weight must be zero or greater.");
    }
    return numeric;
  }
  const validation = validateWeightFormula(runtime, input);
  if (!validation.valid) {
    throw new Error(`Display weight formula is invalid: ${validation.error}`);
  }
  return input;
}

// The owner asked for groups to default to a promotion ("a +.5 or *1.5 or
// some such so events that cross more frames default to being more
// prominent"). The lead's ruling narrows this to newly created GROUP and
// IMPORTANCE frames only, never calendars: every event already belongs to a
// calendar, so boosting every calendar uniformly promotes nothing relative
// to anything else -- it would just push every event toward the landmark
// threshold and make the thresholds meaningless. `*1.5` (not `+.5`) is the
// chosen form, matching the owner's own alternative phrasing.
//
// This is the one place the default lives, so every creation path that opens
// a blank frame-authoring form agrees on it; it feeds a form's *initial*
// field value only; it is never applied to, or migrated onto, a frame that
// already exists.
export function defaultWeightForNewFrame(kind) {
  return kind === "group" || kind === "importance" ? 1.5 : undefined;
}

// APPLICATION ORDER, ruled and fixed: mixed `+` and `*` do not commute
// (`(w + 1) * 2` is not `w * 2 + 1`), so which order contributing frames
// apply their formulas in is part of the contract, not an implementation
// detail free to vary with iteration order over a `Set`. Given the pool of
// frame ids a fact draws its weight from (an event's direct frame
// attachments union its group/importance-frame memberships -- see
// `factImportanceWeight`), this returns them in the fold order the base
// weight is threaded through, left to right:
//
//   1. Ascending by the frame's authored `display.weightOrder` (absent = 0)
//      -- an explicit, opt-in knob for the rare case the default ordering
//      below is not what an author wants, checked first because an explicit
//      instruction should outrank an inferred one.
//   2. Then by group size, DESCENDING -- the same size signal
//      `resolveObjectColor`'s color-cascade step 2 already uses to prefer
//      the more specific group over the broader one (see
//      `src/visual-language.js`), reused rather than reinvented: a large
//      membership (a whole imported calendar, say) applies its formula
//      first, so a narrower, more specific group's formula is the last
//      thing adjusting the weight -- the specific affiliation gets the
//      final word over the general one, not the other way around.
//   3. Then by frame id, lexicographically -- two frames tied on both of the
//      above still need one fixed answer every time, not whichever order a
//      `Set` or object happened to iterate in.
export function weightContributionOrder(context, frameIds) {
  const document = context?.document;
  const engine = context?.engine;
  const ordered = [...new Set(frameIds)].map((id) => {
    const order = Number(document?.frames?.[id]?.display?.weightOrder);
    return {
      id,
      order: Number.isFinite(order) ? order : 0,
      size: engine?.displayGroupEventMembers?.(id)?.length || 0
    };
  });
  ordered.sort((left, right) => left.order - right.order || right.size - left.size || left.id.localeCompare(right.id));
  return ordered.map((entry) => entry.id);
}

// A lazily-created runtime for callers that have no reason to own one --
// mirrors how `src/engine.js` defaults its own `runtime` option. Kept here,
// not in `src/visual-language.js`, so every consumer of the weight-formula
// model (display weight today, any future formula-driven surface) shares one
// default instance and one compiled-expression cache rather than each
// growing its own.
let sharedRuntime = null;
export function defaultWeightRuntime() {
  if (!sharedRuntime) sharedRuntime = new FormulaRuntime();
  return sharedRuntime;
}
