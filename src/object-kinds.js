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
// later have to be unwound.
export function rosterEntries(chronologDocument, requestedKind) {
  const kind = normalizeObjectKind(requestedKind);
  const events = Object.values(chronologDocument?.events || {})
    .filter((event) => objectKindForEvent(event) === kind);
  const placements = new Map();
  for (const relation of Object.values(chronologDocument?.relations || {})) {
    if (!relation?.event || placements.has(relation.event)) continue;
    if (relation.coordinate) placements.set(relation.event, relation);
  }
  return events
    .map((event) => {
      const relation = placements.get(event.id) || null;
      return {
        id: event.id,
        title: event.payload?.title || "(untitled)",
        coordinate: relation?.coordinate || null,
        frame: relation?.frame || null,
        // A roster row has to be able to say "this one has no staple yet" rather
        // than inventing a date for it.
        anchored: Boolean(relation?.coordinate)
      };
    })
    .sort((left, right) => left.title.localeCompare(right.title) || left.id.localeCompare(right.id));
}

export function traitsForObjectKind(existingTraits, requestedKind) {
  const kind = normalizeObjectKind(requestedKind);
  const extra = (existingTraits || []).filter((trait) => !CONTROLLED_TRAITS.has(trait));
  return [...new Set([...OBJECT_KINDS[kind].traits, ...extra])];
}
