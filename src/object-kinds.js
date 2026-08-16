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

export function traitsForObjectKind(existingTraits, requestedKind) {
  const kind = normalizeObjectKind(requestedKind);
  const extra = (existingTraits || []).filter((trait) => !CONTROLLED_TRAITS.has(trait));
  return [...new Set([...OBJECT_KINDS[kind].traits, ...extra])];
}
