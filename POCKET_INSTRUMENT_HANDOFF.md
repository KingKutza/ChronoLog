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

Matching UIDs produce staple suggestions but never merge identities. Formula
patterns export only over the visible/selected finite window, while unchanged
native RRULEs remain structural.

## Instrument interaction

The page is a fixed full-viewport canvas with no document scrolling:

- Scale rail: continuous scale with Intimate, Tactical, and Strategic detents.
- Projection dial: calendar, wall, topology/lines, and radial.
- Minimap: surrounding facts, focus playhead, and draggable viewport.
- Shared focus: on by default; projection-local focus is opt-in.

Intimate wheel motion rolls through midnight. Tactical has three equal-height
rows. Strategic and Wall fill the viewport. Lines use calendar/timeline Frames
as the core lines; groups only annotate events. Radial defaults to one inward,
one current, and one outward turn; wheel motion travels time, previous/next
cycle buttons work in both variants, and past/future extent changes
independently.

Click or drag calendar space to create an Event. The responsive inspector edits
Events, Frames, and Patterns. All model changes use command-based undo/redo
before autosave.

## Important boundaries

- The celestial seed is exact to its stored model, not a physical ephemeris.
- Native desktop binaries and network synchronization are future shells around
  the browser-independent engine.
- The old baked `{events, settings}` HTML payload is not canonical. Reimport its
  original ICS source.
- Personal `*.ics` files and GUI reference images are user data; do not alter or
  commit them accidentally.
