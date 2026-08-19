# Roadmap

Ordered by priority. Done items are removed, not archived — git history is
the archive.

1. **Chrome and stage polish** — the rolling bucket; it never empties, by
   nature. Current contents: edge-flip and z-level are properties of one
   shared dropdown class that every bar dropdown inherits; the lens bar
   puts its hamburger on the right edge and its options fill the bar;
   the dock-side toggle gets a label; the lens workspace compacts (name,
   checkbox, up/down on one line; descriptions with the tags; no
   scrolling); swap "jump to today" and "reset lens"; minimap dot
   tuning — more visibility into what counts as a dot and how dots
   accumulate. The stage-takeover settings window is cut: settings
   arrive incrementally in existing surfaces and dock cards (still
   pending exposure: series projection horizon, snapshot-compaction
   period — the server endpoint is live). Parked from the 8.19 wave:
   ToDo-tailored editor fields (recurrence rows, location, and
   calendar-vs-list framing are still event-shaped); exposing
   many-to-many event↔frame attachment in the editor (frame selection is
   one class with an explicit primary marker and every selected frame
   overlays; the editor side did not land); transaction-aware Apply for
   undo-tracked surfaces (the event editor and frame forms need more than
   a button). Frame overlay selection is session view state — a document
   authored before that change is bridged into the session once.
2. **ToDo and Notes** — implement the staple/decay model (see LEXICON.md,
   2026-08-17/18 rulings): floats live at their staples, project forward
   for a keep-range, lapse from present view without deletion. Importance
   levels are groups whose handling (keep-range, decay, display weight) is
   a group property — composable, addable, removable, including irregular
   levels; the fixed standard/important/landmark enum retires into that
   model (display-side unification shipped; the persisted migrations —
   legacy trait strings, additive kind-switching — remain). **The Notes
   default is Obsidian-shaped**: a name, properties and tags (groups)
   under a rolled-up section, and a big markdown text window that renders
   everything except the line under the cursor in edit mode. Staples
   occur naturally at creation and edit, can be typed inline
   ([8.19@7:22]) in the text, or entered as freeform fields/properties;
   the note appears wherever it is stapled, and which staples render in
   which lenses is configurable (per group or globally: every edit, only
   creation, only inline references, only properties, combinations).
   This generalizes: todos, events, and any future object carry
   arbitrarily many staples of arbitrary type, arbitrarily placed, and
   render accordingly. Advanced identity may build gestalt note-event
   hybrids, but that is not the default. Includes the sigils-and-zones
   display work and an ICS path (VJOURNAL). Labeled as work, not settled
   design.
3. **Obsidian integration** — ChronoLog works an Obsidian vault directly:
   settings take a path and naming scheme for a daily-notes folder and
   everything works back and forth effortlessly in both apps; same for
   meeting/event notes and for todos in linked folders. Markdown files
   are the interchange boundary for notes, as ICS is for calendars —
   severance doctrine, no plugin API coupling.
4. **Staple anchoring** (see LEXICON.md, staple anchoring entry) — retire
   the start-time-plus-duration assumption: a staple can anchor start,
   end, midpoint, or another named point of an event, paired with a
   magnitude; two or three staples derive the magnitude instead. Fuzzy
   staples ("about 5ish") make uncertainty per-staple data. Constraint
   bounds ("can't go later than 7:30") are adjacent and unruled. A series
   is an identity whose rules are segments partitioned by staples (the
   Rob-and-John scenario in LEXICON.md is the acceptance case): a staple
   at an inflection point ends the reigning rule, and a new rule may
   follow on the same series or a new series may begin, on preference.
   The series end-staple ships: a `staple` relation carrying
   `series`/`kind: "end"`/`frame`/`coordinate`, one shared derivation of
   the effective stop as the earlier of the rule's own extent and the
   staple, removal restoring the projection, ICS deriving UNTIL at
   serialization rather than storing it, and the whole thing composing
   with the healing invariant. Still open: start, midpoint and other
   named-point anchors; magnitudes derived from staples; fuzzy staples;
   an occurrence staple anchoring the cycle's phase; a new rule defined
   after the staple; an end-staple under a COUNT rule (RFC 5545 forbids
   COUNT with UNTIL); and exclusions as live references to another
   frame's events (skip holidays = events on frame xyz) rather than baked
   lists. Rule extent (indefinite) is distinct from projection horizon
   (bounded, default ~2 years, settable). The authoring path must handle
   end-anchored work shifts and irregular night-shift cycles; defining an
   event — as opposed to a series — by an end staple still has no path.
5. **Pattern authoring beyond the RRULE dropdown** — the repeat control
   is a rigid list of common Gregorian periods. "Every odd day of every
   even month of every odd year, except where any of those numbers is
   prime" is a repeat pattern with no entry path — and the dropdown
   plays worse still with non-Gregorian calendars. The formula language
   exists for exactly this; the authoring surface doesn't. Needs design
   alongside #4.
6. **Custom calendars are first-class** — prerequisite stage: the frame's
   coordinate declaration becomes the executed law. Today the levels /
   radix / transition ladder on `frame:wall-time` is dead metadata: the
   engine dispatches on `kind: "gregorian"` to hardcoded civil functions
   in exact.js, the transition strings resolve to nothing, and ~50 call
   sites carry 24/1440/86400 (and a mean month length) as literals. Melt
   into one coordinate-arithmetic engine that reads the frame's
   declaration, with a transition registry (the exact.js civil functions
   become the registered Gregorian entries, not a bypass). Acceptance
   test: set hours-per-day to 23 and everything updates everywhere —
   until that edit works, no non-Gregorian calendar can. Then the
   surface work, with custom day/month/year names: the minimap must
   respect the new names; units must be addable/removable; Strategic
   must adapt (full months per line, weeks per line, custom month
   labels) and Wall the same; no artificial Now line on a calendar with
   no now-mapping; jump-to-date must exist. Epochs/ages need handling —
   BCE/CE, or first/second/third ages — as part of the same model.
7. **Intimate overlap and create-in-place** — overlap is indicated
   locally, not globally: a 30-minute collision must not lane both
   events full-height. Events stay rectangles — no key-shaped blocks.
   The overlap itself gets drawn (a zone marking the contended interval)
   rather than deforming the participants. Placing an event inside an
   occupied span must not require dragging the occupant away and back —
   create-in-place works through an existing block.
8. **Two-way calendar sync, Outlook first** — pushed down for difficulty,
   not priority of desire. Through ICS import/export semantics, never a
   provider API. The journal's per-op conflict foundation exists;
   provider-side conflict semantics for recurring/edited events still
   need design.
9. **Control-bar aesthetics.**
10. **New logo** — plain text until a better mark earns the spot.
11. **More calendar subscriptions** — Google Calendar and other providers,
    each through its published ICS URL.
12. **Instance-to-instance WAN sync** — two ChronoLogs syncing across the
    web, built on the journal's per-op foundation.
13. **Mobile version** — Android first. The dock becomes a full-screen
    sheet under a width breakpoint; card paging becomes swipe gestures.
14. **Super-strategic band** (naming candidate: the epoch view) — the
    lens beyond Strategic, which caps at 18 months where this band would
    take over: decades to centuries to millennia or longer. Needs design;
    pairs with #6's epochs/ages.
15. **Field-level merge** — real merging on top of per-op sequencing. Needs
    design.
16. **Compiled native binaries** — the distribution end-state; the portable
    Node bundles are interim. Native shells may pop dock cards out into
    real second OS windows on desktop platforms.
17. **The document's own timeline** — a lens over the journal itself:
    scroll back through what the document was, watch a deleted series
    vanish and return. The journal already records every op; this is the
    view it makes possible. The very far bottom, on purpose.
