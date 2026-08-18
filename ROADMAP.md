# Roadmap

Ordered by priority.

1. **Dock system.** One multi-function dock hosts every editor as a
   full-bleed card, paged one at a time: handle strip (top in vertical
   axis, right in horizontal), shift/ctrl-scroll cycles card-to-card with a
   fast snap animation (220ms transform-only), click a handle to jump,
   keyboard cycling. Side is a setting (right by default); width defaults
   to a third, drags freely from 1/8 to 2/3 with snap points, and is
   remembered. The stage owns the chrome: document bar, view bar, and
   context bar stack on the left third with the minimap filling the right
   two-thirds at full stack height; the dock fills the main-window vertical
   below the chrome. The stage hosts views, the dock hosts editors;
   settings takes over the stage; no floating windows. Lens resize
   re-renders once at rest; whatever opened the panel stays visually
   anchored through the reflow. Chrome changes that ride with it: the
   document menu becomes a dock card; a Settings button joins the document
   bar; ToDo and Notes buttons live in the view bar (colored distinctly)
   and open their dock cards; lenses can be hidden via the lens
   configuration surface, with a right-side drop on the view bar for
   hidden ones.
2. **Chrome and stage polish.** No scrollbar on the stage's right edge —
   it scrolls and drags without a bar. The Autosaved chip becomes a small
   color indicator. Context bar: forward/back on the right, mirroring the
   today/reset buttons; blank space is fine, a time-span label spanning
   the bar is not. Option menus on Tactical open leftward and get cut by
   the window edge — panels must flip to stay inside the viewport.
3. **Settings window** — theme, workspace defaults, dock side, layout
   presets, lens hiding, and the snapshot-compaction period (server
   endpoint already live). Takes over the stage.
4. **Two-way calendar sync, Outlook first** — through ICS import/export
   semantics, never a provider API. The journal's per-op conflict
   foundation now exists; provider-side conflict semantics for
   recurring/edited events still need design.
5. **Series editing** — opening an occurrence of a series for editing
   materializes it; closing without changes must revert it to a projection
   of its series instead of leaving a separate instance. There is no clear
   way to stop a series propagating from a given point — truncating a
   series at "here" must exist as an alternative to deleting it. "Ends
   after" only accepts integer counts — it needs an end date too. The
   "completed at" field cannot be clicked.
6. **Minimap rebuild.** Dots are too big: go from 11 rows to 21–31 and at
   least triple the dot density. Everything counts for at least one dot
   and some things several — a busy day and a free day must look different
   at a glance, at every lens's granularity (multi-hour window, day, week,
   quarter). The current-time black bubble goes. Top labels become
   context-aware: no year in Intimate; Q1-26 / Q2-26 style in Strategic.
7. **Intimate lens interaction and legibility** — restore horizontal drag
   (drag is free, both axes at once), the forward/back one-day buttons,
   and horizontal scroll alongside vertical. Base-increment lines are
   invisible inside colored zones. Overlap must be indicated locally, not
   globally: a 30-minute collision currently lanes both events for their
   full height and roughs up the whole interface even where no text
   contends — narrow or mark only the actual overlapping interval, leave
   every non-contended element at full size. Placing an event inside an
   occupied span must not require dragging the occupant away and back
   (today's workaround; midnight-crossing drag made it survivable, but it
   is a bad operating mode) — create-in-place must work through an
   existing block.
8. **Toolbar order** — swap "jump to today" and "reset lens".
9. **ToDo and Notes** — implement the staple/decay model (see LEXICON.md,
   2026-08-17/18 rulings): floats live at their staples, project forward
   for a keep-range, lapse from present view without deletion. Importance
   levels are groups whose handling (keep-range, decay, display weight) is
   a group property — composable, addable, removable, including irregular
   levels; the fixed standard/important/landmark enum retires into that
   model. New notes and todos auto-anchor to now; notes and todos
   right-align in Intimate. Includes the sigils-and-zones display work and
   an ICS path (VJOURNAL) so Notes round-trip. Open questions remain —
   this is labeled as work, not settled design.
10. **Staple anchoring** (see LEXICON.md, staple anchoring entry) — retire
    the start-time-plus-duration assumption: a staple can anchor start,
    end, midpoint, or another named point of an event, paired with a
    magnitude; two or three staples derive the magnitude instead. Fuzzy
    staples ("about 5ish") make uncertainty per-staple data. Constraint
    bounds ("can't go later than 7:30") are adjacent and unruled. The
    authoring path must handle real cases like end-anchored work shifts
    and irregular night-shift cycles (event-defined periods already model
    the cycles; entry is the gap). Needs design.
11. **Slim the retained ICS payload** — 93.8% of the owner's real document
    is a per-event duplicate of its own parsed ICS node
    (`events[*].foreign.ics.component`, ~154 MB of a 169 MB file). Keep
    round-trip fidelity while storing the source once, not per event.
12. **Control-bar aesthetics.**
13. **New logo** — plain text until a better mark earns the spot.
14. **More calendar subscriptions** — Google Calendar and other providers,
    each through its published ICS URL.
15. **Instance-to-instance WAN sync** — two ChronoLogs syncing across the
    web, built on the journal's per-op foundation.
16. **Mobile version** — Android first. The dock becomes a full-screen
    sheet under a width breakpoint; card paging becomes swipe gestures.
17. **Super-strategic band** — the lens beyond Strategic, which caps at 18
    months where this band would take over. Needs design.
18. **Field-level merge** — real merging on top of per-op sequencing. Needs
    design.
19. **Compiled native binaries** — the distribution end-state; the portable
    Node bundles are interim. Native shells may pop dock cards out into
    real second OS windows on desktop platforms.
20. **The document's own timeline** — a lens over the journal itself:
    scroll back through what the document was, watch a deleted series
    vanish and return. The journal already records every op; this is the
    view it makes possible. The very far bottom, on purpose.
