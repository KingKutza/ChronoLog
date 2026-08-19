export const OBJECT_KINDS = Object.freeze({
  event: Object.freeze({
    label: "Event",
    newTitle: "New event",
    traits: Object.freeze(["event"]),
    relationRole: "placed",
    zeroDuration: false
  }),
  todo: Object.freeze({
    label: "ToDo",
    newTitle: "New ToDo",
    traits: Object.freeze(["event", "task", "todo"]),
    relationRole: "observed",
    zeroDuration: true
  }),
  note: Object.freeze({
    label: "Note",
    newTitle: "New note",
    traits: Object.freeze(["event", "note"]),
    relationRole: "placed",
    zeroDuration: true
  })
});

const CONTROLLED_TRAITS = new Set(["event", "task", "todo", "note"]);

export function normalizeObjectKind(value) {
  return Object.hasOwn(OBJECT_KINDS, value) ? value : "event";
}

export function objectKindForEvent(event) {
  if (event?.traits?.some((trait) => trait === "task" || trait === "todo")) return "todo";
  if (event?.traits?.includes("note")) return "note";
  return "event";
}

// The ToDo and Notes roster: every object of one kind, newest first, with the
// coordinate it is stapled at. Pure over the document so the roster's contents
// and ordering are testable without a DOM.
//
// This is deliberately a flat roster, not the staple/decay model. Floats living
// at their staples, projecting forward for a keep-range and lapsing from the
// present view is ROADMAP #9 and is not decided yet; showing every object of a
// kind is the honest placeholder, because it invents no lifecycle rule that would
// later have to be unwound. A completed ToDo is still one of these entries --
// completion is a fact about the object, never a reason to stop listing it.
export function rosterEntries(chronologDocument, requestedKind) {
  const kind = normalizeObjectKind(requestedKind);
  const events = Object.values(chronologDocument?.events || {})
    .filter((event) => objectKindForEvent(event) === kind);
  const placements = new Map();
  const completions = new Map();
  for (const relation of Object.values(chronologDocument?.relations || {})) {
    if (!relation?.event) continue;
    // A "completed" relation marks when the object was finished, not where it is
    // stapled -- it must never stand in for the scheduled/observed placement a
    // row displays, so the two are tracked separately from the same pass.
    if (relation.role === "completed") {
      if (relation.coordinate && !completions.has(relation.event)) completions.set(relation.event, relation);
      continue;
    }
    if (relation.coordinate && !placements.has(relation.event)) placements.set(relation.event, relation);
  }
  return events
    .map((event) => {
      const relation = placements.get(event.id) || null;
      const completion = completions.get(event.id) || null;
      return {
        id: event.id,
        title: event.payload?.title || "(untitled)",
        coordinate: relation?.coordinate || null,
        frame: relation?.frame || null,
        // A roster row has to be able to say "this one has no staple yet" rather
        // than inventing a date for it.
        anchored: Boolean(relation?.coordinate),
        // Whether a "completed" temporal attachment relation exists for this
        // object, and the coordinate it carries -- the same relation shape the
        // inspector's Completed date field reads and writes, so the roster's
        // checkbox and the editor's field are two views of one fact.
        completed: Boolean(completion),
        completedAt: completion?.coordinate || null
      };
    })
    .sort((left, right) => left.title.localeCompare(right.title) || left.id.localeCompare(right.id));
}

export function traitsForObjectKind(existingTraits, requestedKind) {
  const kind = normalizeObjectKind(requestedKind);
  const extra = (existingTraits || []).filter((trait) => !CONTROLLED_TRAITS.has(trait));
  return [...new Set([...OBJECT_KINDS[kind].traits, ...extra])];
}
