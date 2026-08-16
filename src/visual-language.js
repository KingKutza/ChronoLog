// ChronoLog's small, cross-lens visual vocabulary.  A lens is free to choose
// its geometry, but it must not silently give one of these marks a different
// meaning.  This module deliberately contains no DOM code so it can be tested
// as part of the model-facing renderer contract.

export const THEME_FIELDS = Object.freeze({
  ground: "Ground",
  surface: "Surface",
  paper: "Paper",
  ink: "Ink",
  muted: "Muted ink",
  primary: "Primary",
  secondary: "Secondary",
  accent: "Accent"
});

export const THEME_PRESETS = Object.freeze({
  paper: Object.freeze({
    ground: "#ece5d8", surface: "#f7f1e6", paper: "#fffdf7", ink: "#2a2620",
    muted: "#716657", primary: "#b33b27", secondary: "#2e8b57", accent: "#497bc1"
  }),
  night: Object.freeze({
    ground: "#10131a", surface: "#171b25", paper: "#202735", ink: "#f7f3e8",
    muted: "#b9b2a6", primary: "#ff8a66", secondary: "#45f0ae", accent: "#d889ff"
  })
});

export const SIGIL_VOCABULARY = Object.freeze({
  point: Object.freeze({ glyph: "●", label: "Scheduled event" }),
  milestone: Object.freeze({ glyph: "◆", label: "Milestone" }),
  repeat: Object.freeze({ glyph: "↻", label: "Recurring occurrence" }),
  task: Object.freeze({ glyph: "○", label: "Task or float" }),
  terminator: Object.freeze({ glyph: "⟐", label: "Timeline terminator" }),
  celestial: Object.freeze({ glyph: "✦", label: "Celestial event" }),
  span: Object.freeze({ glyph: "▬", label: "Time span or zone" })
});

function hasTrait(event, ...traits) {
  return traits.some((trait) => event?.traits?.includes(trait));
}

/**
 * Select one primary mark.  Color remains authored grouping/context; this
 * answer conveys the event's structural role so it stays useful in grayscale.
 */
export function sigilForFact(fact, durationMinutes = 0) {
  const event = fact?.event;
  if (durationMinutes >= 1440) return "span";
  if (hasTrait(event, "terminator")) return "terminator";
  if (hasTrait(event, "task", "todo", "float")) return "task";
  if (hasTrait(event, "celestial", "phase")) return "celestial";
  if (hasTrait(event, "landmark", "milestone", "deadline", "important")) return "milestone";
  if (fact?.virtualId || event?.provenance?.kind === "pattern") return "repeat";
  return "point";
}

export function sigilDescription(fact, durationMinutes = 0) {
  return SIGIL_VOCABULARY[sigilForFact(fact, durationMinutes)].label;
}

export function normalizeTheme(theme, fallback = THEME_PRESETS.paper) {
  const normalized = {};
  for (const name of Object.keys(THEME_FIELDS)) {
    const value = String(theme?.[name] || "").trim();
    normalized[name] = /^#[0-9a-f]{6}$/i.test(value) ? value : fallback[name];
  }
  return normalized;
}
