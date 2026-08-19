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
    // Step 2's "group" is the display-side union of ordinary groups and
    // importance frames (`engine.isDisplayGroup`): an importance frame is
    // authored exactly like a group (same attachment/membership relation
    // shape), so it must be eligible to color its events the same way. This
    // does not change what "group" means anywhere the document is read or
    // written -- only which memberships the cascade is willing to look at.
    for (const membership of engine?.eventDisplayGroupMemberships?.(sourceId) || []) {
      if (!membership?.group || seenGroups.has(membership.group)) continue;
      seenGroups.add(membership.group);
      memberships.push({ id: membership.group, order: memberships.length });
    }
  }

  const activeGroupModes = document?.frames?.[activeFrame]?.display?.groupModes || {};
  const groupCandidates = memberships.map((membership) => {
    if (!groupSizes.has(membership.id)) {
      groupSizes.set(membership.id, engine?.displayGroupEventMembers?.(membership.id)?.length || 0);
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
 *
 * `importance` is the unified `factImportance` verdict ("standard",
 * "important", or "landmark"), passed in by the caller rather than resolved
 * here, so this function stays pure and DOM-free. It is optional and
 * defaults to "standard" so a caller with no engine/document at hand (or an
 * existing test) still gets the legacy-trait-only answer unchanged. Without
 * this, an event made important by group/importance-frame affiliation rather
 * than a legacy trait string would carry no sigil marking its role at all --
 * the shape-carries-meaning contract in AGENTS.md would be broken exactly
 * the way color alone breaking it would be.
 */
export function sigilForFact(fact, durationMinutes = 0, importance = "standard") {
  const event = fact?.event;
  if (durationMinutes >= 1440) return "span";
  if (hasTrait(event, "terminator")) return "terminator";
  if (hasTrait(event, "task", "todo", "float")) return "task";
  if (hasTrait(event, "note")) return "note";
  if (hasTrait(event, "celestial", "phase")) return "celestial";
  if (hasTrait(event, "landmark", "milestone", "deadline", "important") || importance !== "standard") return "milestone";
  if (fact?.virtualId || event?.provenance?.kind === "pattern") return "repeat";
  return "point";
}

export function sigilDescription(fact, durationMinutes = 0, importance = "standard") {
  return SIGIL_VOCABULARY[sigilForFact(fact, durationMinutes, importance)].label;
}

function importanceSource(context, fact) {
  const document = context?.document;
  const pattern = document?.patterns?.[fact?.event?.provenance?.pattern];
  const sourceId = pattern?.templateEvent || fact?.event?.id;
  const source = document?.events?.[sourceId] || fact?.event;
  return { sourceId, source };
}

// The base, pre-multiplier verdict: legacy trait strings on the event itself
// win first (unmodified, see `factImportance`'s own note on that), then an
// importance frame reached through `eventDisplayGroupMemberships` -- directly
// or through nested group membership, same as before this item. This is
// exactly the check `factImportance` used to make its whole decision with;
// `factImportanceWeight` now treats it as the seed a frame's `display.weight`
// multiplies rather than the final answer.
function baseImportanceVerdict(context, sourceId, source) {
  const document = context?.document;
  const engine = context?.engine;
  if (source?.traits?.includes("landmark")) return "landmark";
  if (source?.traits?.includes("important")) return "important";
  const importanceFrame = (engine?.eventDisplayGroupMemberships?.(sourceId) || [])
    .map(({ group }) => document?.frames?.[group])
    .find((candidate) => candidate?.traits?.includes("importance"));
  return importanceFrame?.display?.importance || "standard";
}

// LEXICON.md: "importances are just group affiliations; how members are
// handled is a property [of the group] ... derived from the event or set on
// it then modified by everything that touches it, such as a multiplier by
// its frame membership" (owner's field report, item #5). A frame IS a group,
// so `display.weight` is one handling property that lives uniformly on every
// frame -- calendar, group, or importance set -- and every consumer composes
// it through this one function rather than inventing a frame-specific path.
//
// The base weight and the promotion thresholds deliberately share one scale:
// a base verdict of "important"/"landmark" lands EXACTLY on its own
// threshold, so at the universal default weight of 1 (neutral, authored
// only, never inferred -- nothing here is guessed from a name or category)
// composing multiplies by 1 everywhere and reproduces the pre-existing
// three-way check exactly. That also means a frame weight alone, multiplying
// a "standard" base of 1, can carry an event across the same threshold an
// importance trait would -- literally "modified by everything that touches
// it, such as a multiplier by its frame membership."
const IMPORTANCE_BASE_WEIGHT = Object.freeze({ standard: 1, important: 2, landmark: 4 });
const IMPORTANCE_WEIGHT_THRESHOLD = Object.freeze({ important: 2, landmark: 4 });

/**
 * The composed display weight behind `factImportance`'s three-verdict
 * vocabulary: a base weight for the event's own trait/importance-frame
 * verdict, multiplied by the `display.weight` of every frame the event
 * belongs to. "Belongs to" is the union already used elsewhere for display
 * purposes -- the event's own direct frame attachments (`engine.eventFrames`,
 * which is how an imported calendar's own frame reaches its events) plus its
 * group/importance-frame memberships including nested groups
 * (`engine.eventDisplayGroupMemberships`, the same union the color cascade's
 * step 2 and `baseImportanceVerdict` both read) -- deduplicated, so a frame
 * reached both ways contributes its weight once, not twice. A frame with no
 * authored weight (or an invalid/negative one) contributes nothing, i.e. acts
 * as 1: meaning is authored, never inferred, and a missing knob must not
 * silently change anything.
 *
 * `context` is duck-typed as `{ document, engine }`, matching the shape every
 * lens renderer already threads through `src/projections.js`.
 */
export function factImportanceWeight(context, fact) {
  const document = context?.document;
  const engine = context?.engine;
  const { sourceId, source } = importanceSource(context, fact);
  const verdict = baseImportanceVerdict(context, sourceId, source);
  let weight = IMPORTANCE_BASE_WEIGHT[verdict] ?? IMPORTANCE_BASE_WEIGHT.standard;
  const frameIds = new Set([
    ...(engine?.eventFrames?.(sourceId) || []),
    ...(engine?.eventDisplayGroupMemberships?.(sourceId) || []).map(({ group }) => group)
  ]);
  for (const frameId of frameIds) {
    const frameWeight = Number(document?.frames?.[frameId]?.display?.weight);
    if (Number.isFinite(frameWeight) && frameWeight >= 0) weight *= frameWeight;
  }
  return weight;
}

/**
 * The one shared importance verdict every display consumer reads: the color
 * cascade (via group/importance-frame membership), sigil selection, minimap
 * weighting, and the Strategic gate. Legacy trait strings ("landmark",
 * "important" on the event itself) are checked first and still work
 * unmodified -- this item unifies display, not persisted data, and legacy
 * trait strings are ROADMAP #9's own wave, not this one. Group-based
 * importance is read through `eventDisplayGroupMemberships`, the same
 * display-side union step 2 of the color cascade reads, so an importance
 * frame reached directly *or* through nested group membership is seen here
 * too -- not just a direct attachment.
 *
 * The verdict itself is now derived from `factImportanceWeight` by threshold
 * (see that function for the frame-weight composition), so every existing
 * caller keeps its three-string answer unchanged while gaining strategic
 * promotion via frame membership for free. An explicit per-lens override
 * (e.g. a group's `display.strategic`) is a harder, separate signal that a
 * caller such as Strategic checks before ever asking this question -- see
 * `strategicPresentation` in `src/projections.js` -- so an authored show/hide
 * always wins over a derived weight, it does not compose with it.
 *
 * `context` is duck-typed as `{ document, engine }`, matching the shape every
 * lens renderer already threads through `src/projections.js`.
 */
export function factImportance(context, fact) {
  const weight = factImportanceWeight(context, fact);
  if (weight >= IMPORTANCE_WEIGHT_THRESHOLD.landmark) return "landmark";
  if (weight >= IMPORTANCE_WEIGHT_THRESHOLD.important) return "important";
  return "standard";
}

export function normalizeTheme(theme, fallback = THEME_PRESETS.paper) {
  const normalized = {};
  for (const name of Object.keys(THEME_FIELDS)) {
    const value = String(theme?.[name] || "").trim();
    normalized[name] = /^#[0-9a-f]{6}$/i.test(value) ? value : fallback[name];
  }
  return normalized;
}
