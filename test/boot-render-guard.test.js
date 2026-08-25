import assert from "node:assert/strict";
import test from "node:test";
import { CommandHistory, createEmptyWorkspaceDocument, validateDocument } from "../src/model.js";
import { ChronologEngine } from "../src/engine.js";
import { ViewSession } from "../src/session.js";
import { toggleTodoCompletion } from "../src/ui/roster.js";
import { createTransactions } from "../src/ui/transactions.js";
import { findByClass, renderWithStubDom } from "./helpers/render-dom.js";

// Field finding (2026-08-25 smoke run): a fresh empty workspace has no
// calendar frame, so the session constructor's legacy "calendar:personal"
// fallback pointed the first render at a frame the document does not hold.
// renderCalendar threw straight through app.js's top-level boot, which
// aborted the module before the store ever attached -- a first-run user's
// captures were never persisted. The lens contract is the rule being pinned:
// a renderer that cannot support the current document uses the explicit
// visible error state; it must not throw.

test("unknown lead frame renders the projection error state, never throws", () => {
  const chronologDocument = createEmptyWorkspaceDocument();
  const engine = new ChronologEngine(chronologDocument);
  for (const projection of ["calendar", "wall", "lines", "radial"]) {
    const session = new ViewSession({ projection, scale: 1 });
    assert.equal(session.activeFrame, "calendar:personal");
    const target = renderWithStubDom({ document: chronologDocument, engine, session, loading: false });
    const errors = findByClass(target, "projection-error");
    assert.equal(errors.length, 1, `${projection} must surface the error state`);
    assert.match(errors[0].textContent, /not in the document/);
  }
});

// The write half of the same field finding: the drive's captured todo carried
// an attachment and an end staple pointing at the phantom frame, and the
// persisted document then refused to load. The rule being pinned: a write
// helper must never fabricate a reference to a frame the document does not
// hold. With no real frame, capture makes a bare null-frame todo, and marking
// it done records membership only -- done, instant unstated.
test("capture and done on an empty workspace never reference a phantom frame", () => {
  const chronologDocument = createEmptyWorkspaceDocument();
  const app = { chronolog: chronologDocument, session: new ViewSession({}) };
  app.history = new CommandHistory(chronologDocument, () => {});
  Object.assign(app, createTransactions(app));
  assert.equal(app.session.activeFrame, "calendar:personal");

  const created = app.createQuickTodo({ title: "First capture" });
  assert.ok(created?.id);
  const attachments = Object.values(chronologDocument.relations)
    .filter((relation) => relation.type === "attachment" && relation.event === created.id);
  assert.equal(attachments.length, 0, "no attachment to a frame the document does not hold");

  toggleTodoCompletion(app, created.id);
  const memberships = Object.values(chronologDocument.relations)
    .filter((relation) => relation.type === "membership" && relation.member === created.id);
  assert.equal(memberships.length, 1, "done is recorded as state membership");
  const staples = Object.values(chronologDocument.relations)
    .filter((relation) => relation.type === "staple");
  assert.equal(staples.length, 0, "no instant staple without a real frame to pin it to");

  const validation = validateDocument(chronologDocument);
  assert.deepEqual(validation.errors || [], [], "the document must load back");
  assert.ok(validation.valid);
});

test("the ToDo lenses render on a document with no calendar frames at all", () => {
  const chronologDocument = createEmptyWorkspaceDocument();
  const engine = new ChronologEngine(chronologDocument);
  for (const projection of ["list", "board"]) {
    const session = new ViewSession({ projection, scale: 1 });
    const target = renderWithStubDom({ document: chronologDocument, engine, session, loading: false });
    assert.equal(findByClass(target, "projection-error").length, 0);
    assert.ok(target.children.length, `${projection} must render its surface`);
  }
});
