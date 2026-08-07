# Chronolog Pocket Instrument

**Status:** model-first redesign, August 2026.

## Run and verify

The application is dependency-free ES modules served locally:

```sh
npm start
# open http://127.0.0.1:4173/

npm test
npm run check
node fixtures/verify-celestial.js
```

`pocket-instrument.html` is now the small application shell. Source lives in
`src/`; it must be served over HTTP because browsers do not consistently permit
module imports from `file:` URLs.

## Constitutional model

The saved `chronolog/1` JSON object has three domain nodes:

- **Event** — intrinsic traits, payload, and typed magnitudes.
- **Frame** — set, line, circle, graph, calendar, group, quantity system, or
  composed timeline context.
- **Pattern** — constants plus a pure `chronolog-formula/1` module.

Stable **Relation** records attach Events to Frames or compose Frames. Tasks and
terminators are zero-duration Events with traits and relation roles, not new
root types. Pattern output is virtual until a stable generated ID is suppressed
and explicitly replaced.

Coordinates are sparse nested level/value pairs with exact numeric strings.
Frames define their own nesting and may reference formula exports for conversion
and projection. Gregorian conversion uses arbitrary-size integers rather than
JavaScript `Date`.

Lens, scale, focus, minimap, and inspector state live in `ViewSession`, never in
the canonical document.

## Formula engine

`src/formula.js` parses and interprets a pure expression language. It never uses
`eval` or `Function`. Modules support constants, named functions, records,
lists, comprehensions, exact rationals, and deterministic transcendental math.
Host constructors, prototype access, ambient globals, network, filesystem,
clock, DOM, and randomness are inaccessible. Fuel and output limits bound each
query.

Patterns export:

```text
state(context) -> typed state values
facts(context) -> virtual frames, events, or relations
```

`fixtures/celestial.chronolog.json` is a compact Earth–Moon–Sun mean-orbit
pattern. It produces state and lunar phase facts at query time for remote and
negative years; no VEVENT horizon exists.

## ICS and saving

Chronolog JSON is canonical. The browser autosaves after the user grants a file
handle and shows dirty/saving/error state; download is the fallback.

ICS is an adapter:

- VCALENDAR becomes a calendar Frame.
- VEVENT becomes an Event and placement Relation.
- VTODO becomes a task Event with distinct observed/completed Relations.
- RRULE becomes a Pattern evaluated lazily.
- EXDATE and RECURRENCE-ID become suppressions and replacements.
- Unknown properties, components, VTIMEZONE, VALARM, and parameters survive
  export.

Imported VEVENT/VTODO components are stored once on their Event; the calendar
source retains only calendar-level properties and non-event children such as
VTIMEZONE. Opening older Chronolog JSON normalizes duplicate source-tree events
in memory, and the next save writes compact JSON. On the 2,717-event field-test
document this reduced the serialized form from 224.4 MiB to 80.4 MiB without
discarding round-trip data.

Matching UIDs produce staple suggestions but never merge identities. Formula
patterns export only over the visible/selected finite window, while unchanged
native RRULEs remain structural.

## Instrument interaction

The page is a fixed full-viewport canvas with no document scrolling:

- Six named lenses are always visible: Intimate, Tactical, Strategic, Wall,
  Lines, and Radial.
- Each lens has contextual window controls instead of an abstract scale slider.
- The minimap has dated gradations, surrounding facts, a focus playhead, and a
  draggable viewport.
- Shared focus is on by default; projection-local focus remains opt-in.

Intimate uses a scrollable full-day rail with 15/30/60-minute grain, overlap
lanes, and independent back/forward day counts. Tactical exposes rows and days
per row. Strategic restores the month-by-31-day path with glance/detail and
optional record slashes; Wall and Lines expose their own month windows. Radial
supports spiral and group-banded concentric forms, cycle selection, previous/
next cycle, and independent inward/outward turns.

Large documents are indexed by frame, day, pattern applicability, and event
group. UI queries are bounded and disclose dense-window truncation. Finite RRULE
series and open-ended 64-day windows use hard LRU fact budgets; pathological
COUNT values fail visibly instead of monopolizing the UI thread. Dense tactical
cells aggregate overflow. The minimap reads only the explicit day index, so
navigation chrome never performs a second recurrence query. Wheel navigation is
detented and coalesced in the responsive style of Pocket Instrument r2-r4.
Canonical engine queries remain unlimited unless a caller explicitly supplies a
limit.

Click or drag calendar space to create an Event. Ordinary calendar work uses a
plain-language inspector: Starts, Duration and Units, Calendar, Repeats,
Description, Location, and Groups. Formula traits and raw Patterns stay under
Advanced. Groups have a dedicated manager and can also be created while editing
an Event. Daily, weekly, monthly, and yearly RRULE Patterns are created directly
from the Event editor.

Drag an explicit Event or generated recurring occurrence to reschedule it in
any lens. Calendar-cell drops retain its time of day; Intimate drops snap to the
selected grain; Lines and Radial map the pointer back onto their continuous time
surfaces. Active drags show a live landing coordinate. Lens scroll positions and
the minimap's surrounding strip survive rerenders, preserving spatial motion.
Lines is one Prime calendar line with branching group side-lines, using one
bounded query. Drag, create, edit, delete, group, recurrence, and import actions
use scoped reversible deltas, so large imported documents are not copied and
warm recurrence caches survive lightweight edits. A moved virtual occurrence
becomes one explicit replacement with one suppression. Snapshot-style history
has a 32 MiB retention budget for remaining advanced operations.

## Important boundaries

- The celestial seed is exact to its stored model, not a physical ephemeris.
- Native desktop binaries and network synchronization are future shells around
  the browser-independent engine.
- The old baked `{events, settings}` HTML payload is not canonical. Reimport its
  original ICS source.
- Personal `*.ics` files and GUI reference images are user data; do not alter or
  commit them accidentally.
