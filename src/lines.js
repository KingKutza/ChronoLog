import { Rational } from "./exact.js";

export function lineFramePlan(documentValue, activeFrameId) {
  const leading = documentValue.frames?.[activeFrameId] || null;
  if (!leading?.traits?.includes("calendar")) {
    return { supported: false, leading, companions: [], unsupportedCompanions: [] };
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
