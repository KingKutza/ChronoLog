import { Rational, daysFromCivil, formatCivil } from "../exact.js";
import { OBJECT_KINDS, rosterEntries } from "../object-kinds.js";
import { escapeHTML } from "./dom-helpers.js";

// The ToDo and Notes dock cards: a roster of every object of one kind, plus a
// "new" affordance. Deliberately a flat list — the staple/decay model (floats
// living at their staples, projecting forward for a keep-range, lapsing from the
// present view without deletion) is ROADMAP #9 and is not settled, so this card
// invents no lifecycle rule that would later have to be unwound.
export function createRoster(app) {
  // Now, as an ordinal day in the same local-civil terms the rest of the
  // workspace uses. Computed from the local calendar date rather than a UTC
  // timestamp so a float anchored "now" lands where the user is looking instead
  // of hours away.
  function nowOrdinal() {
    const now = new Date();
    return new Rational(daysFromCivil(
      BigInt(now.getFullYear()),
      BigInt(now.getMonth() + 1),
      BigInt(now.getDate())
    ))
      .add(Rational.parse(now.getHours()).div(24))
      .add(Rational.parse(now.getMinutes()).div(1440));
  }

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
      <div class="roster-list">
        ${entries.length
          ? entries.map((entry) => `
            <button class="roster-row" type="button" data-roster-open="${escapeHTML(entry.id)}">
              <strong>${escapeHTML(entry.title)}</strong>
              <small>${entry.anchored ? escapeHTML(formatCivil(entry.coordinate, true)) : "no staple yet"}</small>
            </button>`).join("")
          : `<p class="field-note">Nothing yet.</p>`}
      </div>`;

    // New todos and notes auto-anchor to now: a float exists before it has been
    // scheduled, so making the user pick a date first is backwards. The staple is
    // editable the moment its editor card opens.
    wrapper.querySelector("[data-roster-new]").addEventListener("click", () => {
      const instant = nowOrdinal();
      app.createEventAt(instant, instant, kind);
    });
    for (const row of wrapper.querySelectorAll("[data-roster-open]")) {
      row.addEventListener("click", () => app.openEventInspector(row.dataset.rosterOpen));
    }
    return wrapper;
  }

  function cardId(kind) {
    return `panel:roster-${kind}`;
  }

  // The roster is a live list, so an open card is rebuilt in place when the
  // document changes underneath it rather than going stale until it is reopened.
  function refreshAll() {
    for (const kind of ["todo", "note"]) {
      const body = app.dockCardBody(cardId(kind));
      if (body) body.replaceChildren(render(kind));
    }
  }

  function open(kind) {
    const definition = OBJECT_KINDS[kind];
    // A second press on the view-bar button closes the roster again, which makes
    // the button a toggle rather than a one-way trip into the dock.
    if (app.dockCardBody(cardId(kind))) {
      app.closeDockCard(cardId(kind));
      return;
    }
    app.openInspector(`${definition.label}s`, render(kind), `roster-${kind}`);
  }

  return { openRoster: open, refreshRosters: refreshAll };
}
