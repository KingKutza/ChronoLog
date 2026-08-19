import assert from "node:assert/strict";
import test from "node:test";
import { renderProjection } from "../src/projections.js";
import { createInspector } from "../src/ui/inspector.js";
import { ChronologEngine } from "../src/engine.js";
import { ViewSession } from "../src/session.js";
import { Rational, daysFromCivil } from "../src/exact.js";
import { importICS } from "../src/ics.js";
import { createStructuralDocument } from "./helpers/sample-document.js";

// The 8.19 field report's item 3, in the owner's words: "If I click on an
// instance of a series in the right day columns, of intimate view, I get a
// 'That generated fact is outside the current query window' error."
//
// Root cause: the click path (src/ui/drag.js's dblclick handler ->
// src/ui/inspector.js's openVirtualInspector -> findVisibleFact) resolved a
// clicked virtual fact by re-querying a *guessed* window
// (`session.window(1.25)`), symmetric around the focus day. But
// renderIntimate's actual render window is asymmetric (intimateBack and
// intimateForward differ, 2 and 7 by default) plus a render buffer beyond
// that -- so the rightmost visible day columns, and the buffer past them,
// fall well outside what the generic guess covers. Two independent
// derivations of "what is on screen" that were never guaranteed to agree.
//
// The fix: every fact node is already stamped with its own exact day
// (`dataset.factDay`, via `bindFact` in src/projections.js -- the one
// function every lens funnels its fact nodes through). The click handler now
// passes that exact day through to `findVisibleFact` instead of asking it to
// reconstruct a window, so resolution needs no second derivation of the
// render window at all, and holds for every lens bindFact covers.

class StubElement {
  constructor(tag) {
    this.tagName = String(tag).toUpperCase();
    this.className = "";
    this.textContent = "";
    this.dataset = {};
    this.children = [];
    this.parentElement = null;
    this.clientHeight = 900;
    const node = this;
    this.style = {
      setProperty(name, value) { this[name] = String(value); },
      getPropertyValue(name) { return this[name] ?? ""; }
    };
    this.classList = { add(cls) { node.className = node.className ? `${node.className} ${cls}` : cls; } };
  }

  append(...nodes) {
    for (const node of nodes) {
      node.parentElement = this;
      this.children.push(node);
    }
  }

  replaceChildren(...nodes) {
    this.children = [];
    this.append(...nodes);
  }

  setAttribute() {}
  getAttribute() { return null; }
  querySelector() { return null; }
}

function collect(node, out = []) {
  out.push(node);
  for (const child of node.children || []) collect(child, out);
  return out;
}

function documentWithWeeklySeries() {
  const chronologDocument = createStructuralDocument();
  const source = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Test//EN",
    "BEGIN:VEVENT",
    "UID:standing@example.test",
    "DTSTART:20260105T090000Z",
    "RRULE:FREQ=WEEKLY",
    "SUMMARY:Standing meeting",
    "DURATION:PT1H",
    "END:VEVENT",
    "END:VCALENDAR",
    ""
  ].join("\r\n");
  const imported = importICS(source, chronologDocument, { label: "Calendar" });
  return { chronologDocument, frame: chronologDocument.frames[imported.frames[0]] };
}

test("a virtual fact rendered at the edge of the Intimate render buffer resolves without the 'outside the current query window' error", () => {
  const { chronologDocument, frame } = documentWithWeeklySeries();
  const engine = new ChronologEngine(chronologDocument);
  const focus = daysFromCivil(2026n, 1n, 5n); // the series' own DTSTART day
  // Default lens view settings (intimateBack: 2, intimateForward: 7) -- the
  // exact asymmetry the bug report exercises, left at their defaults on
  // purpose rather than tuned to make the case easier.
  const session = new ViewSession({
    projection: "calendar",
    scale: 0,
    activeFrame: frame.id,
    focusDays: focus.toString()
  });

  const target = new StubElement("div");
  const previousDocument = globalThis.document;
  globalThis.document = { createElement: (tag) => new StubElement(tag) };
  try {
    renderProjection(target, { document: chronologDocument, engine, session, loading: false });
  } finally {
    globalThis.document = previousDocument;
  }

  // The naive, generic window a caller used to guess instead of using the
  // rendered day. Kept here only to LOCATE the occurrences that exposed the
  // bug -- it is no longer a code path anything can fall back into.
  const guessedWindow = session.window(1.25);

  const virtualButtons = collect(target).filter((node) => node.dataset?.virtualId);
  assert.ok(virtualButtons.length > 0, "the series actually rendered some occurrences");

  // An occurrence genuinely on screen (rendered) but beyond the old generic
  // window -- the exact mismatch the bug report describes.
  const edgeButton = virtualButtons.find((node) => Rational.parse(node.dataset.factDay).compare(guessedWindow.end) > 0);
  assert.ok(edgeButton, "the series has an occurrence rendered past the generic window's own guess (the far, forward-weighted day columns)");

  const inspector = createInspector({ session, chronolog: chronologDocument, engine, toast() {} });

  // The fix: resolving against the fact's own rendered day finds it, however
  // far it sits from any window a caller might have guessed.
  const resolved = inspector.findVisibleFact(edgeButton.dataset.virtualId, edgeButton.dataset.factDay);
  assert.ok(resolved, "the occurrence resolves using the day it was actually rendered at");
  assert.equal(resolved.virtualId, edgeButton.dataset.virtualId);
});

// The class-level guarantee, which is the part that keeps this fixed. It is not
// enough that the one occurrence from the report resolves: EVERY fact the lens
// drew must resolve, because "rendered but unresolvable" is the whole bug. A
// test pinned to a single occurrence would pass again the moment a different
// window guess crept back in somewhere else.
test("every virtual fact the lens rendered resolves from its own stamped day", () => {
  const { chronologDocument, frame } = documentWithWeeklySeries();
  const engine = new ChronologEngine(chronologDocument);
  const session = new ViewSession({
    projection: "calendar",
    scale: 0,
    activeFrame: frame.id,
    focusDays: daysFromCivil(2026n, 1n, 5n).toString()
  });

  const target = new StubElement("div");
  const previousDocument = globalThis.document;
  globalThis.document = { createElement: (tag) => new StubElement(tag) };
  try {
    renderProjection(target, { document: chronologDocument, engine, session, loading: false });
  } finally {
    globalThis.document = previousDocument;
  }

  const inspector = createInspector({ session, chronolog: chronologDocument, engine, toast() {} });
  const virtualButtons = collect(target).filter((node) => node.dataset?.virtualId);
  assert.ok(virtualButtons.length > 0, "the series actually rendered some occurrences");

  for (const node of virtualButtons) {
    assert.ok(
      node.dataset.factDay,
      `every rendered virtual fact carries the day it was drawn at (${node.dataset.virtualId})`
    );
    assert.ok(
      inspector.findVisibleFact(node.dataset.virtualId, node.dataset.factDay),
      `rendered occurrence ${node.dataset.virtualId} resolves from its own day`
    );
  }
});

// The guessed window is gone, not deprecated. Asking to resolve a fact without
// saying where it was drawn is a programming error, and it fails loudly here
// rather than silently reporting "outside the current query window" to a user
// who is looking straight at the thing they clicked.
test("resolving a virtual fact without its rendered day is refused outright", () => {
  const { chronologDocument, frame } = documentWithWeeklySeries();
  const engine = new ChronologEngine(chronologDocument);
  const session = new ViewSession({
    projection: "calendar",
    scale: 0,
    activeFrame: frame.id,
    focusDays: daysFromCivil(2026n, 1n, 5n).toString()
  });
  const inspector = createInspector({ session, chronolog: chronologDocument, engine, toast() {} });
  assert.throws(
    () => inspector.findVisibleFact("pattern:whatever/occurrence-1"),
    TypeError,
    "no day means no resolution, loudly"
  );
});
