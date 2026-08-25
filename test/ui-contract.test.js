import test from "node:test";
import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { join } from "node:path";

async function readSource(path) {
  return (await readFile(path, "utf8")).replace(/\r\n/g, "\n");
}

async function jsFiles(directory) {
  const found = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const full = join(directory, entry.name);
    if (entry.isDirectory()) found.push(...await jsFiles(full));
    else if (entry.name.endsWith(".js")) found.push(full);
  }
  return found.sort();
}

// boot-contract.test.js catches a broken import graph; this catches a broken DOM
// graph, which fails the same way — silently, with a green suite and an app that
// throws on its first render because `byId(...)` returned null. Removing a node
// from the shell while a module still reaches for it is the exact shape of that
// mistake.
test("every element a module looks up by id exists in the shell or is created in source", async () => {
  const html = await readSource("pocket-instrument.html");
  const files = await jsFiles("src");
  const available = new Set([...html.matchAll(/\bid="([^"]+)"/g)].map((match) => match[1]));
  const lookups = new Map();
  for (const file of files) {
    const source = await readSource(file);
    // Ids the source creates itself, in markup strings or by assignment, are as
    // real as the ones in the shell.
    for (const [, id] of source.matchAll(/\bid="([^"]+)"/g)) available.add(id);
    for (const [, id] of source.matchAll(/\.id = "([^"]+)"/g)) available.add(id);
    for (const [, , id] of source.matchAll(/\b(byId|getElementById)\("([^"]+)"\)/g)) {
      if (!lookups.has(id)) lookups.set(id, file);
    }
  }
  assert.ok(lookups.size > 20, `expected the UI's id lookups, found ${lookups.size}`);
  const missing = [...lookups]
    .filter(([id]) => !available.has(id))
    .map(([id, file]) => `${file} looks up #${id}, which nothing creates`);
  assert.deepEqual(missing, []);
});

test("lens bar exposes nine explicit lenses with a minimap and a lens configuration entry point", async () => {
  const html = await readSource("pocket-instrument.html");
  assert.match(html, /id="lens-bar"/);
  assert.match(html, /id="lens-controls"/);
  for (const lens of ["intimate", "tactical", "strategic", "wall", "lines", "spiral", "radial", "list", "board"]) {
    assert.match(html, new RegExp(`data-lens="${lens}"`));
  }
  assert.match(html, /id="minimap"/);
  assert.match(html, /id="lens-settings"/);
});

test("save status is an accessible status badge", async () => {
  const html = await readSource("pocket-instrument.html");
  assert.match(html, /id="save-status"[^>]*role="status"/);
  assert.match(html, /id="save-status"[^>]*aria-live="polite"/);
});

// The whole-document conflict flow is gone: concurrent edits collide per
// record and merge in place, so there is no keep-both choice to offer and no
// control for making it.
test("the whole-document conflict recovery controls are gone", async () => {
  const html = await readSource("pocket-instrument.html");
  assert.doesNotMatch(html, /id="download-conflict"/);
  assert.doesNotMatch(html, /id="reload-latest"/);
});

test("primary toolbar exposes undo/redo and a document menu with its actions", async () => {
  const html = await readSource("pocket-instrument.html");
  assert.match(html, /id="undo"/);
  assert.match(html, /id="redo"/);
  for (const id of ["open-document", "save-document", "save-as-document", "import-ics", "export-ics"]) {
    assert.match(html, new RegExp(`id="${id}"`));
  }
});

// Both Frames triggers point at the dock now: the drawer they used to control is
// gone, and an aria-controls naming a node that no longer exists is worse than
// none at all.
test("Frames triggers are accessible toggles for the dock", async () => {
  const html = await readSource("pocket-instrument.html");
  assert.match(html, /id="new-frame"[^>]*aria-controls="dock"[^>]*aria-expanded="false"/);
  assert.match(html, /id="manage-frames"[^>]*aria-controls="dock"[^>]*aria-expanded="false"/);
  assert.doesNotMatch(html, /id="inspector"/, "the inspector drawer is gone, not hidden");
});

test("the view bar carries the ToDo lenses, the Notes card trigger, and a hidden-lens drop", async () => {
  const html = await readSource("pocket-instrument.html");
  // The old #open-todos card trigger became the List lens, and Board is a
  // normal catalog lens beside it: they change what the stage projects, so
  // they sit in the lens group as data-lens buttons, not card triggers.
  assert.doesNotMatch(html, /id="open-todos"/, "the ToDo card trigger is gone -- List is a lens now");
  assert.match(html, /id="open-notes"[^>]*aria-controls="dock"/);
  assert.match(html, /id="hidden-lenses"/);

  const start = html.indexOf('<nav id="lens-bar"');
  const end = html.indexOf("</nav>", start);
  assert.ok(start >= 0 && end > start, "the view bar exists");
  const bar = html.slice(start, end);
  for (const id of ["open-notes", "hidden-lenses"]) {
    assert.ok(bar.includes(`id="${id}"`), `#${id} is in the view bar, not somewhere else`);
  }
  // The ToDo lenses order with the lenses -- after Radial, before the Notes
  // card trigger, matching DEFAULT_LENS_ORDER's catalog order.
  assert.ok(bar.indexOf('data-lens="radial"') < bar.indexOf('data-lens="list"'));
  assert.ok(bar.indexOf('data-lens="list"') < bar.indexOf('data-lens="board"'));
  assert.ok(bar.indexOf('data-lens="board"') < bar.indexOf('id="open-notes"'));
  // Distinct styling is a requirement, not a nicety: Notes is not a lens.
  assert.match(bar, /class="[^"]*\bview-bar-card\b[^"]*"[^>]*id="open-notes"/);
  // The lens buttons carry no view-bar-card class -- they ARE lenses.
  assert.doesNotMatch(bar, /view-bar-card[^>]*data-lens="list"/);
  assert.doesNotMatch(bar, /view-bar-card[^>]*data-lens="board"/);
});

// Bug 5 (8.19 Part Three): the standalone "Settings" button is gone — the
// document control itself opens the settings/document dock card directly, so
// a second entry point one click further in the same menu was redundant, not
// a distinct destination.
test("the document control is the settings entry point, not a separate Settings button", async () => {
  const html = await readSource("pocket-instrument.html");
  assert.match(html, /id="document-menu"/);
  assert.doesNotMatch(html, /id="settings"/);
});

// Bug 3: the lens bar's hamburger (#hidden-lenses) is the reported case, but
// the generalized rule is that every bar control — on any of the three bars —
// reaches its bar's full height as a property of the shared .bar-control
// class, not a hand-picked min-height that happens to be close. This checks
// every static bar control across the document bar and view bar carries it;
// test/toolbar-dropdowns.test.js covers the dynamically-built context bar.
test("every static bar control on the document bar and view bar carries the shared bar-control class", async () => {
  const html = await readSource("pocket-instrument.html");
  const hudStart = html.indexOf('<header id="hud"');
  const hudEnd = html.indexOf("</header>", hudStart);
  const hud = html.slice(hudStart, hudEnd);
  const lensBarStart = html.indexOf('<nav id="lens-bar"');
  const lensBarEnd = html.indexOf("</nav>", lensBarStart);
  const lensBar = html.slice(lensBarStart, lensBarEnd);
  // create-menu, frame-select, and document-menu are <details> whose actual
  // clickable control is the child <summary>; new-frame is a plain button.
  assert.match(hud, /<details id="create-menu"[^>]*>\s*<summary class="bar-control"/, "#create-menu's summary carries bar-control");
  assert.match(hud, /<button class="[^"]*\bbar-control\b[^"]*" id="new-frame"/, "#new-frame carries bar-control");
  assert.match(hud, /<details id="frame-select"[^>]*>\s*<summary class="bar-control"/, "#frame-select's summary carries bar-control");
  assert.match(hud, /<details id="document-menu">\s*<summary class="bar-control"/, "#document-menu's summary carries bar-control");
  for (const lens of ["intimate", "tactical", "strategic", "wall", "lines", "spiral", "radial", "list", "board"]) {
    assert.match(lensBar, new RegExp(`class="bar-control"[^>]*data-lens="${lens}"`), `the ${lens} lens button carries bar-control`);
  }
  for (const id of ["open-notes", "lens-settings"]) {
    assert.match(lensBar, new RegExp(`class="[^"]*\\bbar-control\\b[^"]*"[^>]*id="${id}"`), `#${id} carries bar-control`);
  }
  // The reported defect: the hamburger itself, sized as a full-height square
  // instead of collapsing to its dashed border's content size.
  assert.match(lensBar, /<summary class="bar-control square"[^>]*>⋯<\/summary>/, "#hidden-lenses's summary is a full-height square, the exact reported defect");
});

// Bug 4: Undo, the deliberate save, and Redo as one cluster at the right of
// the document bar, immediately before the document control.
test("the history controls are ordered Undo, Save, Redo and sit at the right of the document bar", async () => {
  const html = await readSource("pocket-instrument.html");
  const start = html.indexOf('<div class="history-controls"');
  const end = html.indexOf("</div>", start);
  assert.ok(start >= 0 && end > start, "the history-controls group exists");
  const group = html.slice(start, end);
  const order = [...group.matchAll(/id="(undo|save-document|redo)"/g)].map((match) => match[1]);
  assert.deepEqual(order, ["undo", "save-document", "redo"], "Undo, save state, Do (redo) — the owner's literal ordering");
  // "On the right of the bar": the history cluster comes after the frame
  // select and save-status, and immediately precedes the document control,
  // which is the bar's own rightmost, hamburger-like trigger.
  const hudStart = html.indexOf('<header id="hud"');
  const hud = html.slice(hudStart, html.indexOf("</header>", hudStart));
  assert.ok(hud.indexOf('id="frame-select"') < hud.indexOf('class="history-controls"'));
  assert.ok(hud.indexOf('id="save-status"') < hud.indexOf('class="history-controls"'));
  assert.ok(hud.indexOf('class="history-controls"') < hud.indexOf('id="document-menu"'));
});

// Bug 5's audit, item by item: the document dropdown became a dock card
// (#document-card-body) holding only genuinely document-scoped actions and
// genuine settings; view-scoped items (Configure lenses, shared date) moved
// to the view bar instead of staying nested under a "Documents" label.
test("the document card holds the audited document/settings content, not the relocated view-bar items", async () => {
  const html = await readSource("pocket-instrument.html");
  const start = html.indexOf('<div id="document-card-body"');
  const end = html.indexOf('<button id="manage-frames"', start);
  assert.ok(start >= 0 && end > start, "the document card body exists");
  const card = html.slice(start, end);
  for (const id of [
    "open-document", "save-as-document", "manage-frames-proxy", "new-pattern",
    "sync-calendars", "import-ics", "export-ics", "theme-settings", "dock-side", "snapshot-period"
  ]) {
    assert.ok(card.includes(`id="${id}"`), `#${id} is on the document/settings card`);
  }
  // Relocated to the view bar, not left nested here under the document card.
  for (const id of ["lens-settings", "shared-focus", "settings"]) {
    assert.ok(!card.includes(`id="${id}"`), `#${id} is not on the document card any more`);
  }
  // Moved into the history-controls cluster, not the document card.
  assert.ok(!card.includes('id="save-document"'), "Save now moved to the history-controls cluster");
  // No redundant "Documents" label — the card's own title already says
  // "Document"; only the internal Settings/actions split is named.
  assert.doesNotMatch(card, />Documents</);
});

test("Configure lenses and shared date live on the view bar, not the document card", async () => {
  const html = await readSource("pocket-instrument.html");
  const lensBarStart = html.indexOf('<nav id="lens-bar"');
  const lensBar = html.slice(lensBarStart, html.indexOf("</nav>", lensBarStart));
  assert.ok(lensBar.includes('id="lens-settings"'));
  assert.ok(lensBar.includes('id="shared-focus"'));
});

test("the shell provides the dock's rail, pager strip, and resize separator", async () => {
  const html = await readSource("pocket-instrument.html");
  for (const id of ["workspace", "dock", "dock-resize", "dock-rail", "dock-viewport", "dock-strip"]) {
    assert.match(html, new RegExp(`id="${id}"`), `#${id} exists`);
  }
  // The resize grip has to be reachable without a pointer.
  assert.match(html, /id="dock-resize"[^>]*role="separator"/);
  assert.match(html, /id="dock-resize"[^>]*tabindex="0"/);
});

test("create menu exposes todo and note controls", async () => {
  const html = await readSource("pocket-instrument.html");
  assert.match(html, /id="create-menu"/);
  assert.match(html, /id="new-todo"/);
  assert.match(html, /id="new-note"/);
});

test("calendar sync and theme settings entry points exist", async () => {
  const html = await readSource("pocket-instrument.html");
  assert.match(html, /id="sync-calendars"/);
  assert.match(html, /id="theme-settings"/);
});
