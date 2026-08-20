const TRAITS_BY_KIND = {
  calendar: ["set", "calendar"],
  group: ["set", "group"],
  importance: ["set", "group", "importance"],
  cycle: ["circle", "cycle"],
  line: ["line", "timeline"],
  measure: ["measure"],
  other: []
};

export function additiveFrameTraits(kind, enteredTraits = [], existingTraits = []) {
  return [...new Set([
    ...existingTraits,
    ...enteredTraits,
    ...(TRAITS_BY_KIND[kind] || [])
  ].filter(Boolean))];
}

// A frame that OWNS a coordinate can author that coordinate's structure. The
// gate used to be `values.has("calendar")`, which withheld the whole
// calendar-structure surface from `frame:wall-time` -- traits `["line",
// "temporal", "gregorian"]`, so kind "line" -- even though Wall Time is the
// frame every derived calendar inherits its structure FROM. The owner's report:
// "When I go into wall time there is no section to definecalendar structure,
// which is weird as that is the frame defining the inherited calendar
// structure." Structure authoring now follows the coordinate capability, which
// is the thing it is actually about.
export function frameAuthoringCapabilities(kind, traits = []) {
  const values = new Set([kind, ...traits]);
  const temporal = ["calendar", "cycle", "line", "timeline", "measure", "other"].some((value) => values.has(value));
  return Object.freeze({
    basis: temporal,
    calendarStructure: temporal,
    fixedCalendar: temporal,
    observedBoundaries: values.has("calendar") || values.has("cycle"),
    coordinate: temporal,
    periodData: values.has("calendar") || values.has("cycle") || values.has("other")
  });
}

export function preservedFrameSchema(previous = {}, coordinateText = "", periodText = "") {
  return {
    coordinate: String(coordinateText).trim() ? JSON.parse(String(coordinateText)) : previous.coordinate,
    period: String(periodText).trim() ? JSON.parse(String(periodText)) : previous.period
  };
}
