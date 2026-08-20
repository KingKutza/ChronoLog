import test from "node:test";
import assert from "node:assert/strict";
import {
  Rational,
  coordinate,
  daysFromCivil,
  nowDays,
  sinExact,
  sqrtExact
} from "../src/exact.js";
import { civilCoordinateToDays, daysToCivilCoordinate } from "../src/coordinate-law.js";

test("arbitrary-year civil coordinates retain a quarter millisecond exactly", () => {
  const input = coordinate([
    { level: "year", value: "3222026" },
    { level: "month", value: "8" },
    { level: "day", value: "6" },
    { level: "hour", value: "12" },
    { level: "minute", value: "1" },
    { level: "second", value: "2" },
    { level: "subsecond", value: "0.00025" }
  ]);
  const output = daysToCivilCoordinate(civilCoordinateToDays(input));
  assert.deepEqual(output, input);
});

test("Gregorian conversion is reversible across the required horizon", () => {
  for (const year of [-100_000_000n, -1n, 0n, 1026n, 3026n, 100_000_000n]) {
    const day = daysFromCivil(year, 2n, 17n);
    const output = daysToCivilCoordinate(new Rational(day));
    assert.equal(output.levels[0].value, year.toString());
    assert.equal(output.levels[1].value, "2");
    assert.equal(output.levels[2].value, "17");
  }
});

// nowDays is the single sanctioned "current moment as an exact day ordinal"
// helper (formerly forked three ways across session.js/roster.js/projections.js
// at minute and second precision). It accepts an injected clock so this is
// pinned without mocking the global Date, and second precision is checked
// explicitly since that is the canonical behavior the melt chose.
test("nowDays converts an injected clock to a local-civil day ordinal at second precision", () => {
  const clock = new Date(2026, 7, 19, 13, 45, 30); // 2026-08-19 13:45:30 local
  const expected = new Rational(daysFromCivil(2026n, 8n, 19n))
    .add(Rational.parse(13).div(24))
    .add(Rational.parse(45).div(1440))
    .add(Rational.parse(30).div(86400));
  assert.equal(nowDays(clock).compare(expected), 0);

  // A non-zero seconds component must survive: this is exactly the precision
  // that distinguished the old finer helper (projections.js's currentDays)
  // from the two coarser ones (session.js/roster.js) it was melted with.
  const withoutSeconds = new Date(2026, 7, 19, 13, 45, 0);
  assert.notEqual(nowDays(clock).compare(nowDays(withoutSeconds)), 0);
});

test("Rational decimal parsing and deterministic trig are stable", () => {
  assert.equal(Rational.parse("0.00025").toJSON(), "1/4000");
  const first = sinExact(Rational.parse("123456789012345.125"), 32).toJSON();
  const second = sinExact(Rational.parse("123456789012345.125"), 32).toJSON();
  assert.equal(first, second);
});

test("sqrtExact is accurate and deterministic without host floats", () => {
  const two = sqrtExact(Rational.parse("2"), 30);
  assert.equal(two.mul(two).sub(2).abs().compare(Rational.parse("1e-29")) < 0, true);
  assert.equal(two.toJSON(), sqrtExact(Rational.parse("2"), 30).toJSON());
  assert.equal(sqrtExact(Rational.parse("2.25"), 30).toJSON(), "3/2");
});

test("sqrtExact handles magnitudes beyond double range quickly", () => {
  const started = Date.now();
  const tiny = sqrtExact(Rational.parse("1e-330"), 30);
  assert.equal(tiny.toJSON(), "0");
  const huge = sqrtExact(Rational.parse("1e309"), 30);
  const residual = huge.mul(huge).sub(Rational.parse("1e309")).abs();
  assert.equal(residual.compare(Rational.parse("1e130")) < 0, true);
  assert.equal(huge.toJSON(), sqrtExact(Rational.parse("1e309"), 30).toJSON());
  assert.equal(Date.now() - started < 5000, true);
});

test("sqrtExact rejects negatives and preserves exact zero", () => {
  assert.equal(sqrtExact(Rational.parse("0")).toJSON(), "0");
  assert.throws(() => sqrtExact(Rational.parse("-4")), /negative/);
});
