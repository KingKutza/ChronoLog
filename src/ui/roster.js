import { formatCivil, nowDays } from "../exact.js";
import { coordinateLaw, GREGORIAN_LAW } from "../coordinate-law.js";
import { addRelation } from "../model.js";
import { OBJECT_KINDS, rosterEntries } from "../object-kinds.js";
import { escapeHTML } from "./dom-helpers.js";

// A ToDo's completed relation, if it has one -- the same "temporal attachment
// with role completed" shape the inspector's Completed date field reads and
// writes (src/ui/inspector.js's `temporalRelations`/completed lookup), so this
// finds exactly what that field would find.
function findCompletedRelation(documentValue, eventId) {
  return Object.values(documentValue.relations).find(
    (relation) => relation.type === "attachment" && relation.event === eventId && relation.role === "completed"
  );
}

// Mark or clear a ToDo's completion straight from its roster row: a clear
// mechanism the owner asked for, that writes exactly the fact the inspector's
// Completed date field already writes -- a temporal attachment relation with
// role "completed", anchored to now the same way a new float anchors to now.
// Routed through `executeEventChange` so the toggle is one undoable step and
// unchecking restores the exact prior state, including the removed relation.
// Marking done never deletes, hides, or otherwise touches the ToDo's own
// record -- ROADMAP #9's staple/decay model is unsettled, so this invents no
// lifecycle rule beyond the one fact the owner asked for.
export function toggleTodoCompletion(app, eventId) {
  const { chronolog } = app;
  if (!chronolog.events[eventId]) return;
  const alreadyCompleted = Boolean(findCompletedRelation(chronolog, eventId));
  app.executeEventChange(alreadyCompleted ? "Mark ToDo not done" : "Mark ToDo done", eventId, (documentValue) => {
    const existing = findCompletedRelation(documentValue, eventId);
    if (existing) {
      delete documentValue.relations[existing.id];
      return;
    }
    // The completed relation lands on the same calendar frame as whatever
    // placement/observed relation the ToDo already has, so both facts agree on
    // where this object lives; an unstapled float falls back to the active frame,
    // the same default a brand-new float gets.
    const primary = Object.values(documentValue.relations).find(
      (relation) => relation.type === "attachment"
        && relation.event === eventId
        && relation.role !== "completed"
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
    addRelation(documentValue, {
      type: "attachment",
      event: eventId,
      frame,
      role: "completed",
      coordinate: law.fromDays(nowDays())
    });
  });
}

// The ToDo and Notes dock cards: a roster of every object of one kind, plus a
// "new" affordance. Deliberately a flat list — the staple/decay model (floats
// living at their staples, projecting forward for a keep-range, lapsing from the
// present view without deletion) is ROADMAP #9 and is not settled, so this card
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
