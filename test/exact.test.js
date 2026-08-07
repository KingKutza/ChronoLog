import test from "node:test";
import assert from "node:assert/strict";
import {
  Rational,
  civilCoordinateToDays,
  coordinate,
  daysFromCivil,
  daysToCivilCoordinate,
  sinExact
} from "../src/exact.js";

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

test("Rational decimal parsing and deterministic trig are stable", () => {
  assert.equal(Rational.parse("0.00025").toJSON(), "1/4000");
  const first = sinExact(Rational.parse("123456789012345.125"), 32).toJSON();
  const second = sinExact(Rational.parse("123456789012345.125"), 32).toJSON();
  assert.equal(first, second);
});
