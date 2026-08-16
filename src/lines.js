import { Rational } from "./exact.js";

export function lineFramePlan(documentValue, activeFrameId) {
  const leading = documentValue.frames?.[activeFrameId] || null;
  const isLine = leading?.traits?.includes("line") || leading?.traits?.includes("timeline");
  if (!leading?.traits?.includes("calendar") && !isLine) {
    return { supported: false, leading, companions: [], unsupportedCompanions: [] };
  }
  if (isLine) {
    const topology = lineTopologyPlan(documentValue, activeFrameId);
    return { supported: true, leading, companions: topology.frames.filter((frame) => frame.id !== leading.id), unsupportedCompanions: [], topology };
  }
  const selected = Array.isArray(leading.display?.overlays) ? leading.display.overlays : [];
  const companions = [];
  const unsupportedCompanions = [];
  const seen = new Set([leading.id]);
  for (const id of selected) {
    if (seen.has(id)) continue;
    seen.add(id);
    const frame = documentValue.frames?.[id];
    if (frame?.traits?.includes("calendar")) companions.push(frame);
    else unsupportedCompanions.push(id);
  }
  return { supported: true, leading, companions: companions.slice(0, 8), unsupportedCompanions };
}

export function linesRenderState({ loading = false, supported = true, factCount = 0, errorCount = 0, truncated = false } = {}) {
  if (loading) return "loading";
  if (!supported) return "unsupported";
  if (errorCount > 0) return "error";
  if (truncated) return "dense";
  return factCount > 0 ? "ordinary" : "empty";
}

export function lineProgress(day, start, end) {
  const lower = Rational.parse(start);
  const span = Rational.parse(end).sub(lower);
  if (span.compare(0) <= 0) return null;
  const progress = Rational.parse(day).sub(lower).div(span).toNumber();
  return Number.isFinite(progress) ? progress : null;
}

// Lines intentionally never invents a coordinate conversion between frames.
// A topology is renderable only from authored incidences (shared segments,
// displacement endpoints, and attachments), so unfamiliar units remain honest.
export function lineTopologyPlan(documentValue, activeFrameId, limit = 8) {
  const frames = documentValue.frames || {};
  const active = frames[activeFrameId];
  if (!active) return { frames: [], attachments: [], links: [] };
  const topologyRelations = Object.values(documentValue.relations || {}).filter((relation) =>
    relation.type === "shared-segment" || relation.type === "displacement"
  );
  const adjacent = new Map();
  const connect = (left, right) => {
    if (!adjacent.has(left)) adjacent.set(left, new Set());
    if (!adjacent.has(right)) adjacent.set(right, new Set());
    adjacent.get(left).add(right); adjacent.get(right).add(left);
  };
  for (const relation of topologyRelations) {
    if (relation.type === "shared-segment") {
      for (const line of relation.lines || []) for (const other of relation.lines || []) if (line !== other) connect(line, other);
    } else connect(relation.traveler, relation.world);
  }
  // A repeated event is an authored staple/incidence, and is enough to make
  // two lanes adjacent even when it is not part of a named segment.
  const incidence = new Map();
  for (const relation of Object.values(documentValue.relations || {})) {
    if (relation.type !== "attachment") continue;
    const lines = incidence.get(relation.event) || [];
    lines.push(relation.frame); incidence.set(relation.event, lines);
  }
  for (const lines of incidence.values()) {
    for (const line of lines) for (const other of lines) if (line !== other) connect(line, other);
  }
  const ids = [];
  const queued = [activeFrameId];
  const seen = new Set();
  while (queued.length && ids.length < limit) {
    const id = queued.shift();
    if (seen.has(id) || !frames[id]) continue;
    seen.add(id); ids.push(id);
    [...(adjacent.get(id) || [])].sort().forEach((next) => { if (!seen.has(next)) queued.push(next); });
  }
  const selected = new Set(ids);
  const attachments = Object.values(documentValue.relations || {})
    .filter((relation) => relation.type === "attachment" && selected.has(relation.frame))
    .sort((left, right) => `${left.event}\u0000${left.id}`.localeCompare(`${right.event}\u0000${right.id}`));
  const links = topologyRelations.filter((relation) =>
    relation.type === "shared-segment"
      ? (relation.lines || []).some((id) => selected.has(id))
      : selected.has(relation.traveler) || selected.has(relation.world)
  );
  return { frames: ids.map((id) => frames[id]), attachments, links };
}

export function lineUnitLabel(frame, earthDays) {
  const fixed = frame?.coordinate?.fixed;
  if (fixed?.schema === "chronolog/fixed-calendar/1" && Array.isArray(fixed.units)) {
    // Projection owns the exact calendar calculation; this label avoids
    // presenting an unmapped calendar as Gregorian before that calculation.
    return fixed.units.map((unit) => unit.name).filter(Boolean).join(" / ") || "calendar position";
  }
  if (frame?.traits?.includes("line") || frame?.traits?.includes("timeline")) return "topological order (unmapped units)";
  return earthDays == null ? "calendar position" : "mapped day";
}

export function aggregateLinePoints(points, { pixelSpan = 995, clusterPixels = 16, maxSpread = 18 } = {}) {
  const ordered = [...points].sort((left, right) =>
    left.x - right.x || String(left.eventId || "").localeCompare(String(right.eventId || "")) || String(left.id || "").localeCompare(String(right.id || ""))
  );
  const clusters = [];
  for (const point of ordered) {
    const previous = clusters.at(-1);
    if (previous && (point.x - previous.lastX) * pixelSpan <= clusterPixels) {
      previous.points.push(point); previous.lastX = point.x;
    } else clusters.push({ points: [point], lastX: point.x });
  }
  return clusters.map((cluster) => {
    const points = [...cluster.points].sort((left, right) =>
      String(left.eventId || "").localeCompare(String(right.eventId || "")) || String(left.id || "").localeCompare(String(right.id || ""))
    );
    const count = points.length;
    return points.map((point, index) => ({
      ...point,
      clusterSize: count,
      // A symmetric, capped fan keeps same-day events individually reachable.
      offset: count === 1 ? 0 : Math.max(-maxSpread, Math.min(maxSpread, (index - (count - 1) / 2) * 8))
    }));
  }).flat();
}
