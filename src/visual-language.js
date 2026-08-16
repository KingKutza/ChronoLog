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
  note: Object.freeze({ glyph: "□", label: "Note" }),
  terminator: Object.freeze({ glyph: "⟐", label: "Timeline terminator" }),
  celestial: Object.freeze({ glyph: "✦", label: "Celestial event" }),
  span: Object.freeze({ glyph: "▬", label: "Time span or zone" })
});

function hasTrait(event, ...traits) {
  return traits.some((trait) => event?.traits?.includes(trait));
}

function authoredColor(value) {
  const color = String(value || "").trim();
  return color || null;
}

function frameColor(frame) {
  return authoredColor(frame?.color) || authoredColor(frame?.display?.color);
}

function unique(values) {
  return [...new Set(values.filter(Boolean))];
}

/**
 * Resolve authored object color consistently across every lens.
 *
 * Object overrides win. Group membership then overrides temporal frames;
 * groups explicitly shown by the active frame win before larger groups, with
 * authored membership order as the stable final tie-breaker. For objects
 * attached to multiple temporal frames, the active frame wins, followed by
 * the frame currently supplying the rendered fact.
 */
export function resolveObjectColor({
  document,
  engine,
  object,
  sourceObject = object,
  activeFrame = null,
  displayFrame = null,
  relationFrame = null,
  groupSizes = new Map(),
  fallback = "#d4552d"
}) {
  const override = authoredColor(sourceObject?.display?.color)
    || authoredColor(object?.display?.color);
  if (override) return override;

  const sourceIds = unique([sourceObject?.id, object?.id]);
  const memberships = [];
  const seenGroups = new Set();
  for (const sourceId of sourceIds) {
    for (const membership of engine?.eventGroupMemberships?.(sourceId) || []) {
      if (!membership?.group || seenGroups.has(membership.group)) continue;
      seenGroups.add(membership.group);
      memberships.push({ id: membership.group, order: memberships.length });
    }
  }

  const activeGroupModes = document?.frames?.[activeFrame]?.display?.groupModes || {};
  const groupCandidates = memberships.map((membership) => {
    if (!groupSizes.has(membership.id)) {
      groupSizes.set(membership.id, engine?.groupEventMembers?.(membership.id)?.length || 0);
    }
    return {
      ...membership,
      color: frameColor(document?.frames?.[membership.id]),
      active: membership.id === activeFrame || activeGroupModes[membership.id] === "show",
      size: groupSizes.get(membership.id)
    };
  }).filter((candidate) => candidate.color)
    .sort((left, right) => Number(right.active) - Number(left.active)
      || right.size - left.size
      || left.order - right.order
      || left.id.localeCompare(right.id));
  if (groupCandidates.length) return groupCandidates[0].color;

  const attachedFrameIds = [];
  for (const sourceId of sourceIds) {
    attachedFrameIds.push(...(engine?.eventFrames?.(sourceId) || []));
  }
  attachedFrameIds.push(displayFrame, relationFrame);
  const frameCandidates = unique(attachedFrameIds).map((id, order) => ({
    id,
    order,
    frame: document?.frames?.[id]
  })).filter(({ frame }) => frame && !frame.traits?.includes("group") && frameColor(frame))
    .sort((left, right) => {
      const leftRank = left.id === activeFrame ? 0 : left.id === displayFrame ? 1 : left.id === relationFrame ? 2 : 3;
      const rightRank = right.id === activeFrame ? 0 : right.id === displayFrame ? 1 : right.id === relationFrame ? 2 : 3;
      return leftRank - rightRank || left.order - right.order || left.id.localeCompare(right.id);
    });
  return frameCandidates.length ? frameColor(frameCandidates[0].frame) : fallback;
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
  if (hasTrait(event, "note")) return "note";
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
