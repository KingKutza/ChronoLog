# Cross-lens visual grammar

This is the first stable, deliberately small vocabulary.  A renderer may omit
a mark when the scale cannot bear it, but it must not repurpose a mark to mean
something else.  Color identifies an authored frame/group/context; it is never
the sole carrier of an event's structural role.

## Semantic inventory

| Property | Core mark | Meaning |
| --- | --- | --- |
| ordinary scheduled event | `●` point | a temporal attachment |
| milestone, deadline, or important event | `◆` diamond | a marked commitment |
| generated recurrence | `↻` repeat | a pattern occurrence |
| task, todo, or float | `○` ring | a zero-duration or not-yet-stapled item |
| terminator | `⟐` split diamond | a line ending/fork boundary |
| celestial/phase event | `✦` star | an astronomical fact |
| all-day or multi-day event | `▬` span | a zone with duration |

`src/visual-language.js` is the executable source of this vocabulary and is
the place to add a new core sigil.  Lens-specific geometry is not a new
vocabulary.

## Lens treatment

| Lens | Treatment |
| --- | --- |
| Intimate | event blocks gain a left-edge sigil; long events remain zone fills. |
| Tactical | chips show the sigil before their label. |
| Strategic | named chips show sigils; compact pips retain shape as well as color. |
| Wall | detailed chips and compact pips use the same treatment as Strategic. |
| Lines | event marks carry the sigil as a data/accessible label until the topology renderer draws discrete shapes. |
| Spiral / Radial | paths carry the sigil class and accessible label; the path remains the duration geometry. |

Strategic is the density benchmark: label only selected events, retain compact
marks for the rest, and show bounded counts rather than silently dropping
information.  Other lenses use that same label/mark/aggregate ladder.

## Theme contract

Themes are a controlled eight-color palette: ground, surface, paper, ink,
muted ink, primary, secondary, and accent.  `primary`, `secondary`, and
`accent` are the authored anchors; CSS derives hover, hairline, and state tones
using `color-mix`, preserving a coherent palette instead of storing arbitrary
per-widget colors.  `paper` and `night` demonstrate light and dark themes.

Theme applies to instrument chrome and semantic states.  Frame/event colors
remain authored data and are reinforced by sigil shape.  Themes are a local
workspace preference (not calendar data), stored in local storage; this avoids
rewriting imported calendars while preserving the user's instrument treatment.

Every sigil has a text title/ARIA label, and the visible mark is paired with
shape, border, or label so a theme or grayscale display does not erase meaning.
