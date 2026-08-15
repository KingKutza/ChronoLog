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

export function preservedFrameSchema(previous = {}, coordinateText = "", periodText = "") {
  return {
    coordinate: String(coordinateText).trim() ? JSON.parse(String(coordinateText)) : previous.coordinate,
    period: String(periodText).trim() ? JSON.parse(String(periodText)) : previous.period
  };
}
