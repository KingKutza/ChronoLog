import { formatCivil, nowDays } from "../exact.js";
import { coordinateLaw, GREGORIAN_LAW } from "../coordinate-law.js";
import { addRelation, frameEnd, objectEnd, putStaple, removeStaple } from "../model.js";
import {
  DONE_STATE_FRAME_ID,
  DONE_STATE_TITLE,
  OBJECT_KINDS,
  ensureStateFrame,
  objectEndStaple,
  rosterEntries,
  stateAffiliations
} from "../object-kinds.js";
import { escapeHTML } from "./dom-helpers.js";

// Toggle an object's affiliation with a STATE frame -- done today, cancelled or
// postponed tomorrow, all through the one mechanism the owner ruled: state is a
// frame, being in it is group membership, and the instant (when stated) is the
// object's end staple ("the end of this todo abuts" the moment it finished).
// Entering the state writes membership plus an end staple at `at`; leaving it
// removes both. One `executeEventChange` bundle either way, so undo restores
// the exact prior records -- the lazily-minted state frame included, on the
// first toggle that created it. Nothing here deletes, hides, or otherwise
// touches the object's own record: a state is a fact about it, never a
// lifecycle rule (ROADMAP #2's staple/decay model stays unsettled).
export function toggleStateAffiliation(app, eventId, {
  stateFrame = DONE_STATE_FRAME_ID,
  title = DONE_STATE_TITLE,
  at = null
} = {}) {
  const { chronolog } = app;
  if (!chronolog.events[eventId]) return;
  const affiliated = stateAffiliations(chronolog, eventId, app.engine)
    .some((entry) => entry.frame === stateFrame);
  const label = affiliated ? `Leave state ${title}` : `Enter state ${title}`;
  app.executeEventChange(label, eventId, (documentValue) => {
    const existing = Object.values(documentValue.relations).find((relation) =>
      relation.type === "membership" && relation.group === stateFrame && relation.member === eventId);
    if (existing) {
      delete documentValue.relations[existing.id];
      // The instant goes with the state: un-doing a done is a claim that it did
      // not finish, so the staple that said when it finished cannot stand.
      const staple = objectEndStaple(documentValue, eventId);
      if (staple) removeStaple(documentValue, staple.id);
      return;
    }
    ensureStateFrame(documentValue, stateFrame, title);
    addRelation(documentValue, { type: "membership", group: stateFrame, member: eventId });
    // The end staple lands on the same calendar frame as whatever placement/
    // observed relation the object already has, so both facts agree on where
    // this object lives; an unstapled float falls back to the active frame,
    // the same default a brand-new float gets. One end staple per object: a
    // second state entered while an instant is already stated reuses it.
    if (objectEndStaple(documentValue, eventId)) return;
    const primary = Object.values(documentValue.relations).find(
      (relation) => relation.type === "attachment"
        && relation.event === eventId
        && relation.coordinate
    );
    const frame = primary?.frame || app.session.activeFrame;
    // The stored coordinate must be built under THIS frame's own law -- the
    // standard boundary would silently mean the wrong instant under an edited
    // law (src/coordinate-law.js). An unresolvable frame declaration must not
    // make "mark done" fail, so this falls back to the registered standard the
    // same way `displayLaw` does.
    let law;
    try {
      law = coordinateLaw(documentValue, frame);
    } catch {
      law = GREGORIAN_LAW;
    }
    putStaple(documentValue, {
      kind: "end",
      ends: [objectEnd(eventId, "end"), frameEnd(frame, law.fromDays(at ?? nowDays()))]
    });
  });
}

// The roster checkbox's own verb: done-ness, through the general state toggle
// above. Kept as a named export so the checkbox, the tests, and any future
// surface that means specifically "done" say it the same way.
export function toggleTodoCompletion(app, eventId) {
  toggleStateAffiliation(app, eventId);
}

// The ToDo and Notes dock cards: a roster of every object of one kind, plus a
// "new" affordance. Deliberately a flat list — the staple/decay model (floats
// living at their staples, projecting forward for a keep-range, lapsing from the
// present view without deletion) is ROADMAP #2 and is not settled, so this card
// invents no lifecycle rule that would later have to be unwound.
export function createRoster(app) {
  function render(kind) {
    const definition = OBJECT_KINDS[kind];
    const entries = rosterEntries(app.chronolog, kind);
    const wrapper = document.createElement("div");
    wrapper.className = "roster";
    wrapper.innerHTML = `
      <p class="field-note">Every ${escapeHTML(definition.label)} in this document. A new one anchors to now; open it to move or describe it.</p>
      <div class="object-create-row">
        <button class="instrument-button primary" data-roster-new type="button">New ${escapeHTML(definition.label)}</button>
      </div>
      <div class="roster-list" data-roster-kind="${kind}">
        ${entries.length
          ? entries.map((entry) => `
            <div class="roster-row" data-roster-completed="${entry.completed}">
              ${kind === "todo"
                ? `<input type="checkbox" class="roster-check" data-roster-check="${escapeHTML(entry.id)}"
                    ${entry.completed ? "checked" : ""}
                    aria-label="${entry.completed ? "Mark not done" : "Mark done"}">`
                : ""}
              <button class="roster-open" type="button" data-roster-open="${escapeHTML(entry.id)}">
                <strong>${escapeHTML(entry.title)}</strong>
                <small>${entry.anchored ? escapeHTML(formatCivil(entry.coordinate, true)) : "no staple yet"}</small>
              </button>
            </div>`).join("")
          : `<p class="field-note">Nothing yet.</p>`}
      </div>`;

    // New todos and notes auto-anchor to now: a float exists before it has been
    // scheduled, so making the user pick a date first is backwards. The staple is
    // editable the moment its editor card opens.
    wrapper.querySelector("[data-roster-new]").addEventListener("click", () => {
      const instant = nowDays();
      app.createEventAt(instant, instant, kind);
    });
    for (const row of wrapper.querySelectorAll("[data-roster-open]")) {
      row.addEventListener("click", () => app.openEventInspector(row.dataset.rosterOpen));
    }
    // The check control is its own click target, separate from the row's open
    // button, so ticking it off never also opens the editor -- and it is a real
    // checkbox rather than a styled button, so it reads unambiguously as the
    // "clear mechanism" the owner asked for. No confirm: completing a ToDo is
    // cheap and one undo away.
    for (const check of wrapper.querySelectorAll("[data-roster-check]")) {
      check.addEventListener("change", () => toggleTodoCompletion(app, check.dataset.rosterCheck));
    }
    return wrapper;
  }

  function cardId(kind) {
    return `panel:roster-${kind}`;
  }

  // The roster is a live list, so an open card is rebuilt in place when the
  // document changes underneath it rather than going stale until it is
  // reopened. This is registered per card at open time (the `refresh` handed to
  // `app.openInspector` below) rather than called by name from the render loop
  // -- `refreshAll` survives only as a convenience for anything that wants to
  // force both kinds at once.
  function refreshCard(kind) {
    const body = app.dockCardBody(cardId(kind));
    if (body) body.replaceChildren(render(kind));
  }

  function refreshAll() {
    for (const kind of ["todo", "note"]) refreshCard(kind);
  }

  function open(kind) {
    const definition = OBJECT_KINDS[kind];
    // A second press on the view-bar button closes the roster again, which makes
    // the button a toggle rather than a one-way trip into the dock.
    if (app.dockCardBody(cardId(kind))) {
      app.closeDockCard(cardId(kind));
      return;
    }
    app.openInspector(`${definition.label}s`, render(kind), `roster-${kind}`, null, () => refreshCard(kind));
  }

  return { openRoster: open, refreshRosters: refreshAll };
}
