import test from "node:test";
import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { ChronologEngine } from "../src/engine.js";
import { createEmptyWorkspaceDocument, validateDocument } from "../src/model.js";
import { calendarFrames, groupFrames } from "../src/projections.js";
import { ViewSession, sanitizeSessionParameters } from "../src/session.js";
import { lineFramePlan, linesRenderState } from "../src/lines.js";
import { FIXED_RADIAL_CYCLES, resolveRadialCycle } from "../src/radial.js";
import { MINIMAP_BUCKETS, MINIMAP_GRID_ROWS, minimapDotGrid } from "../src/minimap.js";

const root = fileURLToPath(new URL("..", import.meta.url));

async function jsFiles(directory) {
  const found = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const full = join(directory, entry.name);
    if (entry.isDirectory()) found.push(...await jsFiles(full));
    else if (entry.name.endsWith(".js")) found.push(full);
  }
  return found.sort();
}

const IMPORT_PATTERN = /^import\s+([\s\S]*?)\bfrom\s*["']([^"']+)["']/gm;

function importedBindings(clause) {
  const names = [];
  const braces = clause.match(/\{([\s\S]*)\}/);
  if (braces) {
    for (const part of braces[1].split(",")) {
      const name = part.trim().split(/\s+as\s+/)[0].trim();
      if (name) names.push(name);
    }
  }
  const outside = clause.replace(/\{[\s\S]*\}/, "").replace(/(^\s*,)|(,\s*$)/g, "").trim();
  if (outside && !outside.startsWith("*")) names.push("default");
  return names;
}

// `npm run check` runs `node --check` on each file in isolation, so it cannot
// see a named import whose target module does not export that name. The
// mismatch is a link-time SyntaxError: it kills the entire module graph before
// a single statement runs, so the browser paints the static shell and no
// handler is ever attached. Every entry point is one `type="module"` script, so
// one bad specifier anywhere disables the whole app.
test("every static import resolves to a module that actually exports the named bindings", async () => {
  const files = (await Promise.all(["bin", "src", "tools"].map((dir) => jsFiles(join(root, dir))))).flat();
  assert.ok(files.length > 30, `expected the source tree, found ${files.length} files`);
  const namespaces = new Map();
  const failures = [];
  for (const file of files) {
    const source = (await readFile(file, "utf8")).replace(/\r\n/g, "\n");
    for (const [, clause, specifier] of source.matchAll(IMPORT_PATTERN)) {
      if (!specifier.startsWith(".")) continue;
      const target = resolve(join(file, ".."), specifier);
      const label = `${file.slice(root.length)} -> ${specifier}`;
      if (!namespaces.has(target)) {
        try {
          namespaces.set(target, await import(pathToFileURL(target).href));
        } catch (error) {
          namespaces.set(target, null);
          failures.push(`${label}: target failed to load (${error.message.split("\n")[0]})`);
          continue;
        }
      }
      const namespace = namespaces.get(target);
      if (!namespace) continue;
      for (const name of importedBindings(clause)) {
        if (!(name in namespace)) failures.push(`${label}: no export named "${name}"`);
      }
    }
  }
  assert.deepEqual(failures, []);
});

// The first-run document is empty by rule: structural frames only, no calendar
// frame to lead with. Nothing had ever exercised that state, because the old
// celestial sample always supplied frames.
test("the first-run empty workspace document drives the boot chain with no calendar frame", () => {
  const workspace = createEmptyWorkspaceDocument();
  assert.equal(validateDocument(workspace).valid, true);
  assert.deepEqual(calendarFrames(workspace), [], "a first-run document has no calendar frame");
  assert.deepEqual(groupFrames(workspace), []);
  assert.deepEqual(Object.keys(workspace.events), []);

  const engine = new ChronologEngine(workspace);
  assert.deepEqual(engine.indexedExplicitFacts(""), []);
  assert.deepEqual(sanitizeSessionParameters(new URLSearchParams(""), workspace), {});

  // app.js seeds the session from calendarFrames(...)[0]?.id || "", which is ""
  // here, and reconcileSession recomputes the same way on every change.
  const session = new ViewSession({
    activeFrame: calendarFrames(workspace)[0]?.id || "",
    projection: "calendar",
    scale: 1,
    radialMode: "spiral"
  });
  const leadingFrame = workspace.frames[session.activeFrame]
    ? session.activeFrame
    : calendarFrames(workspace)[0]?.id || "";
  assert.equal(leadingFrame, "", "there is no frame to lead with, so reconciliation clears the selection");
  session.setLeadingFrame(leadingFrame);
  // setLeadingFrame ignores a falsy id, so the constructor's placeholder default
  // survives and names a frame this document does not contain. Every consumer
  // must therefore tolerate an unresolvable activeFrame rather than assume it.
  assert.equal(workspace.frames[session.activeFrame], undefined);

  const plan = lineFramePlan(workspace, session.activeFrame);
  assert.equal(plan.supported, false);
  assert.equal(plan.leading, null);
  assert.deepEqual(plan.companions, []);
  assert.equal(linesRenderState({ supported: false }), "unsupported", "Lines reports its declared error state");

  const resolved = resolveRadialCycle(FIXED_RADIAL_CYCLES, session.activeCycle, session.currentFocus());
  assert.ok(resolved, "the radial cycle still resolves against the fixed catalog");
  assert.ok(resolved.period, "a resolved cycle carries a period the radial lenses can render");

  const grid = minimapDotGrid(new Float64Array(MINIMAP_BUCKETS), { rows: MINIMAP_GRID_ROWS });
  assert.equal(grid.rows, MINIMAP_GRID_ROWS);
  assert.equal(grid.columns, MINIMAP_BUCKETS);
  assert.equal(grid.cells.length, grid.rows * grid.columns);
  // An empty document still paints a baseline axis and nothing above it.
  assert.deepEqual([...grid.columnDots], new Array(MINIMAP_BUCKETS).fill(0));
});
