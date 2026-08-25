// Falloff math (src/falloff.js): where an object lives (its home, the exact
// day range its connections span) and how strongly it registers from a
// distance. Pure and exact -- no lens is wired here; the lens build consumes
// these next.
import assert from "node:assert/strict";
import test from "node:test";
import { ChronologEngine } from "../src/engine.js";
import { Rational, daysFromCivil } from "../src/exact.js";
import { apparentMagnitude, distanceFromHome, objectHome } from "../src/falloff.js";
import { addEvent, addRelation, durationMagnitude } from "../src/model.js";
import { createStructuralDocument } from "./helpers/sample-document.js";

function fixture() {
  const document = createStructuralDocument();
  document.frames["calendar:personal"] = {
    id: "calendar:personal",
    title: "Personal",
    traits: ["set", "calendar"],
    basis: "frame:wall-time"
  };
  const civil = (day) => ({
    levels: [{ level: "year", value: "2026" }, { level: "month", value: "8" }, { level: "day", value: String(day) }]
  });
  const todo = addEvent(document, {
    id: "event:permit",
    traits: ["event", "task", "todo"],
    magnitudes: { duration: durationMagnitude("0") },
    payload: { title: "Renew the parking permit" }
  });
  addRelation(document, {
    id: "relation:permit-observed",
    type: "attachment",
    event: todo.id,
    frame: "calendar:personal",
    role: "observed",
    coordinate: civil(15)
  });
  const float = addEvent(document, {
    id: "event:someday",
    traits: ["event", "task", "todo"],
    magnitudes: { duration: durationMagnitude("0") },
    payload: { title: "Someday idea" }
  });
  return { document, todoId: todo.id, floatId: float.id, civil };
}

test("home: a zero-staple object has no home, a single staple is a zero-width one", () => {
  const { document, todoId, floatId } = fixture();
  const engine = new ChronologEngine(document);
  assert.equal(objectHome(document, engine, floatId), null, "no fabricated date for an unstapled float");
  const home = objectHome(document, engine, todoId);
  const day = new Rational(daysFromCivil(2026n, 8n, 15n));
  assert.equal(home.startDays.compare(day), 0);
  assert.equal(home.endDays.compare(day), 0, "one staple, zero width");
});

test("home: the range spans every resolved staple coordinate, exactly", () => {
  const { document, todoId, civil } = fixture();
  // A completion end staple three days later widens the home to a range.
  addRelation(document, {
    id: "relation:permit-completed-at",
    type: "staple",
    kind: "end",
    ends: [{ object: todoId, point: "end" }, { frame: "calendar:personal", coordinate: civil(18) }]
  });
  const engine = new ChronologEngine(document);
  const home = objectHome(document, engine, todoId);
  assert.equal(home.startDays.compare(new Rational(daysFromCivil(2026n, 8n, 15n))), 0);
  assert.equal(home.endDays.compare(new Rational(daysFromCivil(2026n, 8n, 18n))), 0);

  // Distance is zero anywhere INSIDE the home, and the exact gap outside it.
  const inside = new Rational(daysFromCivil(2026n, 8n, 16n)).add(Rational.parse("1/3"));
  assert.equal(distanceFromHome(home, inside).compare(0), 0);
  const before = new Rational(daysFromCivil(2026n, 8n, 13n));
  assert.equal(distanceFromHome(home, before).compare(2), 0);
  const after = new Rational(daysFromCivil(2026n, 8n, 20n)).add(Rational.parse("1/4"));
  assert.equal(distanceFromHome(home, after).toJSON(), "9/4");
  assert.equal(distanceFromHome(null, before), null, "no home, no distance to report");
});

test("apparentMagnitude is exact, full at home, half at the half-distance, and monotone", () => {
  // magnitude * 1 / (1 + distance/halfDistanceDays): at distance 0 the base is
  // untouched, at the half distance it is exactly half, and it decreases
  // monotonically without ever reaching zero.
  assert.equal(apparentMagnitude("1.5", "0").toJSON(), "3/2");
  assert.equal(apparentMagnitude("1.5", "7").toJSON(), "3/4");
  assert.equal(apparentMagnitude(1, 7, { halfDistanceDays: 7 }).toJSON(), "1/2");
  assert.equal(apparentMagnitude(1, "1/3", { halfDistanceDays: "1/3" }).toJSON(), "1/2");
  assert.equal(apparentMagnitude(2, "21").toJSON(), "1/2", "three half-distances quarter the weight");
  let previous = null;
  for (const distance of ["0", "1/2", "1", "7", "30", "365", "100000"]) {
    const value = apparentMagnitude(1, distance);
    if (previous) assert.ok(value.compare(previous) < 0, `still falling at ${distance}`);
    assert.ok(value.compare(0) > 0, "never reaches zero -- a float lapses from prominence, not from truth");
    previous = value;
  }
});

test("apparentMagnitude edges: negative distance reads as its magnitude, a degenerate scale is refused", () => {
  assert.equal(apparentMagnitude(1, "-7").compare(apparentMagnitude(1, "7")), 0);
  assert.throws(() => apparentMagnitude(1, 1, { halfDistanceDays: 0 }), RangeError);
  assert.throws(() => apparentMagnitude(1, 1, { halfDistanceDays: "-2" }), RangeError);
});
