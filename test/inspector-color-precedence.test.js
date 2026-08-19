import assert from "node:assert/strict";
import test from "node:test";
import { resolveSubmittedEventColor } from "../src/ui/inspector.js";

// The owner's ruling (8.19 field report, item 9): "a color set directly on
// the event has the highest precedence, if a color is set override,
// otherwise don't." The separate "Override inherited color" checkbox is
// gone; this pure precedence rule is what replaces it, so it is tested
// directly rather than through a DOM harness.

test("an explicit color is kept as the event's own override", () => {
  assert.equal(resolveSubmittedEventColor(true, "#123456"), "#123456");
});

test("a color field with no value still overrides when explicit, using the fallback", () => {
  assert.equal(resolveSubmittedEventColor(true, ""), "#d4552d");
  assert.equal(resolveSubmittedEventColor(true, null), "#d4552d");
});

test("an unexplicit color is null, not an empty string — the cascade must see nothing here", () => {
  assert.equal(resolveSubmittedEventColor(false, "#123456"), null, "even if the picker still holds a value");
  assert.equal(resolveSubmittedEventColor(false, ""), null);
});
