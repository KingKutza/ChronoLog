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
   accumulate. Bar controls derive their height from their bar through
   one shared class rather than hand-picked pixel values. The
   stage-takeover settings window is cut: settings arrive incrementally
   in existing surfaces and dock cards — the document control opens a
   document/settings card carrying the snapshot-compaction period, and
   the series projection horizon is the one setting still unexposed,
   because it is a literal in the engine with no field to bind to. Parked from the 8.19 wave:
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
   model (display-side unification shipped, and display weight is now a
   formula over the incoming weight with per-lens promotion thresholds —
   see AGENTS.md, "Display weight"; keep-range and decay remain unbuilt
   group properties, as do the persisted migrations — legacy trait
   strings, additive kind-switching). **The Notes
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
4. **Staple display and constraint staples** — the substrate ships (see
   AGENTS.md, "Staples"): staples are an open collection on any object,
   `kind` is validated against a registry rather than hardcoded, and the
   derivations cover anchoring with derived magnitudes, series rule
   segments, per-staple fuzziness, occurrence phase, and exclusions as
   live references to another frame's events. The Rob-and-John scenario
   passes beat by beat, end-anchored events place from where they stop,
   and the editor authors the whole collection including the rule that
   follows an inflection. What remains is display and one unruled
   shape. **The warp**: cross-frame projection exists only through staples,
   and multiple staples between two frames define the correspondence exactly at
   each stapled point without ever averaging into a rigid offset (see AGENTS.md,
   "Coordinate law"). Between stapled points the mapping stretches, and that
   stretch is authored meaning — "we place 8 that is where lines shows us the
   warp." The substrate keeps every point exact and claims nothing about the
   space between them; DRAWING the stretch is Lines-lens work and is undesigned.
   **Fuzzy rendering**: uncertainty reaches the renderer as data
   and is marked, but the display language for it is undesigned — a
   spread wants sigils and zones that read at a glance without piling
   information on the eye, the same problem #2's decay work faces, and
   the two should be designed together. **Overdetermined anchors** are
   reported and never averaged; how a lens should *show* that an
   authored staple is not being believed is undesigned. **Constraint
   bounds** ("can't go later than like 7:30/8") stay unruled — LEXICON.md
   reads them as a bound distinct from the fuzzy actual, and the kind
   registry is a one-entry path once the semantics are decided.
   A named anchor point's relationship to a second anchor derives no
   magnitude on purpose; whether it should is unruled. Rule extent
   (indefinite) is distinct from projection horizon (bounded, ~2 years) —
   the horizon is still a literal in the engine rather than a setting,
   and exposing it is the last piece of #1's settings work.
5. **Pattern authoring beyond the RRULE dropdown** — the repeat control
   is a rigid list of common Gregorian periods. "Every odd day of every
   even month of every odd year, except where any of those numbers is
   prime" is a repeat pattern with no entry path — and the dropdown
   plays worse still with non-Gregorian calendars. The formula language
   exists for exactly this; the authoring surface doesn't. Needs design
   alongside #4.
6. **Custom calendars are first-class** — the prerequisite stage has
   shipped: the frame's coordinate declaration is the executed law. One
   coordinate-arithmetic engine (`src/coordinate-law.js`, and AGENTS.md's
   "Coordinate law") reads the levels / radix / transition ladder, the
   exact.js civil functions are the registered Gregorian entries rather
   than a bypass, calendar families are CLDR calendar scales so a new
   calendar is one registration, and the ~50 call sites that carried
   24/1440/86400 and a float mean month now ask the governing frame.
   Setting hours-per-day to 23 moves engine occurrence math, projection
   layout, minimap strides, duration magnitudes, drag snapping and the
   editor together. The frame editor authors that declaration directly —
   levels, radices, transitions, names, and cycles, with weekday names as
   a cycle rather than a level — on Wall Time, which is the frame every
   derived calendar inherits from. ICS is a lossy boundary with a settled
   contract, including RFC 7529 `RSCALE` import/export.
   What remains. **Positional conversion for a fully custom ladder**: a
   `fixed`-block calendar still reads its base level as a day count
   rather than converting its own year/month/day to a day ordinal, and
   the Gregorian month-boundary walks in the minimap and Radial are
   still the registered ladder's own. **Projection export** of a series
   ICS cannot express. Then the surface work, with custom
   day/month/year names: the minimap must respect the new names; units
   must be addable/removable; Strategic must adapt (full months per
   line, weeks per line, custom month labels) and Wall the same; no
   artificial Now line on a calendar with no now-mapping; jump-to-date
   must exist. **Epochs shipped as true eras** (ruling: "Hard No. Epochs,
   true epochs no faking"): an era is a level of the coordinate, not a
   label over a linearized year, per-era numbering direction is
   first-class so BCE and Merethic both count down, one authored anchor
   derives every era's range, and a table that contradicts itself is
   refused before it is stored — see AGENTS.md, "Coordinate law". Era
   tables are opt-in per declaration, so a document without one is
   unchanged. The uniform positional family landed with them, so a wholly
   invented calendar converts through the registry. What remains of the
   era work: the Now-line guard is written but not yet applied at the
   three `src/projections.js` sites, and the era-qualified year has not
   reached the event editor's own fields. Observed-boundary cycles need a
   computed sibling: a cycle derived from formula or ephemeris — the moon
   by Newton, not by a list of observations — with observation as the
   override, not the definition.
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
