import assert from "node:assert/strict";
import test from "node:test";
import { addEvent, addRelation, durationMagnitude } from "../src/model.js";
import { rosterEntries } from "../src/object-kinds.js";
import { DEFAULT_LENS_ORDER, ViewSession } from "../src/session.js";
import { createStructuralDocument } from "./helpers/sample-document.js";

function documentWithFloats() {
  const document = createStructuralDocument();
  const calendar = Object.values(document.frames).find((frame) => frame.traits?.includes("gregorian"));
  const place = (traits, title, day = null) => {
    const event = addEvent(document, {
      traits,
      magnitudes: { duration: durationMagnitude("0") },
      payload: { title }
    });
    if (day !== null) {
      addRelation(document, {
        type: "placement",
        event: event.id,
        frame: calendar.id,
        coordinate: {
          levels: [
            { level: "year", value: "2026" },
            { level: "month", value: "8" },
            { level: "day", value: String(day) }
          ]
        }
      });
    }
    return event.id;
  };
  place(["event", "task", "todo"], "Water the plants", 18);
  place(["event", "task", "todo"], "Book the hall", 20);
  const unanchored = place(["event", "task", "todo"], "Someday idea");
  place(["event", "note"], "Rules of thumb", 19);
  place(["event"], "Design review", 18);
  return { document, unanchored };
}

test("a roster lists only its own kind", () => {
  const { document } = documentWithFloats();
  const todos = rosterEntries(document, "todo").map((entry) => entry.title);
  const notes = rosterEntries(document, "note").map((entry) => entry.title);
  assert.deepEqual(todos, ["Book the hall", "Someday idea", "Water the plants"]);
  assert.deepEqual(notes, ["Rules of thumb"]);
  // The plain Event belongs to neither roster.
  assert.ok(!todos.includes("Design review") && !notes.includes("Design review"));
});

// A float exists before it has been scheduled, so the roster has to be able to say
// "no staple yet" instead of inventing a date for it.
test("a roster reports an unanchored float honestly rather than inventing a date", () => {
  const { document } = documentWithFloats();
  const entries = rosterEntries(document, "todo");
  const someday = entries.find((entry) => entry.title === "Someday idea");
  assert.equal(someday.anchored, false);
  assert.equal(someday.coordinate, null);
  const anchored = entries.find((entry) => entry.title === "Water the plants");
  assert.equal(anchored.anchored, true);
  assert.ok(anchored.coordinate, "an anchored float carries the coordinate it is stapled at");
  assert.ok(anchored.frame, "and the frame it is stapled to");
});

test("a roster is stable and total on an empty or malformed document", () => {
  assert.deepEqual(rosterEntries(createStructuralDocument(), "todo"), []);
  assert.deepEqual(rosterEntries({}, "note"), []);
  assert.deepEqual(rosterEntries(undefined, "todo"), []);
  // An unknown kind falls back to events rather than throwing.
  assert.deepEqual(rosterEntries(createStructuralDocument(), "nonesuch"), []);
});

// The number keys used to index a hard-coded catalogue order. With a lens hidden
// or reordered, 4 could land on something that was not the fourth button — or on a
// hidden lens, where setLens refused and the key silently did nothing.
test("the number keys follow the visible bar order, not the catalogue", () => {
  const session = new ViewSession({});
  assert.deepEqual(session.availableLenses(), [...DEFAULT_LENS_ORDER]);

  // Hide Tactical: everything after it shifts up one position.
  session.configureLenses({
    enabledLenses: DEFAULT_LENS_ORDER.filter((lens) => lens !== "tactical")
  });
  const visible = session.availableLenses();
  assert.ok(!visible.includes("tactical"));
  assert.equal(visible[1], "strategic", "the second key now reaches the second visible lens");

  // Reordering changes what each key means, in the order the user actually sees.
  session.configureLenses({ lensOrder: ["wall", "lines", "intimate", "strategic", "spiral", "radial"] });
  assert.equal(session.availableLenses()[0], "wall");
});

test("hiding a lens keeps it reachable and never loses its settings", () => {
  const session = new ViewSession({ strategicMonths: 11, radialLabels: false });
  session.configureLenses({ enabledLenses: ["intimate", "tactical"] });

  // It is off the bar but still in the order, which is what the drop lists.
  assert.ok(!session.enabledLenses.includes("strategic"));
  assert.ok(session.lensOrder.includes("strategic"), "a hidden lens stays in the order, so the drop can offer it");
  assert.equal(session.strategicMonths, 11, "and keeps its own window setting");
  assert.equal(session.radialLabels, false);

  // Restoring it from the drop is exactly re-enabling it.
  session.configureLenses({ enabledLenses: [...session.enabledLenses, "strategic"] });
  session.setLens("strategic");
  assert.equal(session.currentLens(), "strategic");
  assert.equal(session.strategicMonths, 11);
});

test("hiding the lens in view moves to one that is still visible", () => {
  const session = new ViewSession({});
  session.setLens("radial");
  assert.equal(session.currentLens(), "radial");
  session.configureLenses({ enabledLenses: ["intimate", "tactical"] });
  // A workspace whose current lens just became unreachable must not be left
  // projecting something with no way back to it.
  assert.ok(session.enabledLenses.includes(session.currentLens()));
});

test("dock geometry and lens visibility both survive a session round trip", () => {
  const session = new ViewSession({});
  session.configureLenses({ enabledLenses: ["intimate", "wall"], lensOrder: ["wall", "intimate"] });
  const restored = new ViewSession(session.toJSON());
  assert.deepEqual(restored.availableLenses(), ["wall", "intimate"]);
  assert.ok(restored.lensOrder.includes("radial"), "a hidden lens is still remembered");
});
