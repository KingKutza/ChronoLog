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

test("lens bar exposes seven explicit lenses with a minimap and a lens configuration entry point", async () => {
  const html = await readSource("pocket-instrument.html");
  assert.match(html, /id="lens-bar"/);
  assert.match(html, /id="lens-controls"/);
  for (const lens of ["intimate", "tactical", "strategic", "wall", "lines", "spiral", "radial"]) {
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

test("Frames triggers are accessible toggles for the same panel", async () => {
  const html = await readSource("pocket-instrument.html");
  assert.match(html, /id="new-frame"[^>]*aria-controls="inspector"[^>]*aria-expanded="false"/);
  assert.match(html, /id="manage-frames"[^>]*aria-controls="inspector"[^>]*aria-expanded="false"/);
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
