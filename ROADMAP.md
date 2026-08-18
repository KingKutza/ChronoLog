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
   anchored through the reflow.
2. **Settings window** — theme, workspace defaults, dock side, layout
   presets, and the snapshot-compaction period (server endpoint already
   live). Takes over the stage.
3. **Two-way calendar sync, Outlook first** — through ICS import/export
   semantics, never a provider API. The journal's per-op conflict
   foundation now exists; provider-side conflict semantics for
   recurring/edited events still need design.
4. **No-op instance edits fork the series** — opening an occurrence of a
   series for editing materializes it; closing without changes must revert
   it to a projection of its series instead of leaving a separate instance.
5. **Minimap tuning** — dots are too large and need too many events to
   register.
6. **Intimate lens legibility** — base-increment lines are invisible inside
   colored zones.
7. **Toolbar order** — swap "jump to today" and "reset lens".
8. **ToDo and Notes** — implement the staple/decay model (see LEXICON.md,
   2026-08-17/18 rulings): floats live at their staples, project forward
   for an importance-scaled keep-range, lapse from present view without
   deletion. Includes the sigils-and-zones display work and an ICS path
   (VJOURNAL) so Notes round-trip.
9. **Slim the retained ICS payload** — 93.8% of the owner's real document
   is a per-event duplicate of its own parsed ICS node
   (`events[*].foreign.ics.component`, ~154 MB of a 169 MB file). Keep
   round-trip fidelity while storing the source once, not per event.
10. **Control-bar aesthetics.**
11. **New logo** — plain text until a better mark earns the spot.
12. **More calendar subscriptions** — Google Calendar and other providers,
    each through its published ICS URL.
13. **Instance-to-instance WAN sync** — two ChronoLogs syncing across the
    web, built on the journal's per-op foundation.
14. **Mobile version** — Android first. The dock becomes a full-screen
    sheet under a width breakpoint; card paging becomes swipe gestures.
15. **Super-strategic band** — the lens beyond Strategic, which caps at 18
    months where this band would take over. Needs design.
16. **Field-level merge** — real merging on top of per-op sequencing. Needs
    design.
17. **Compiled native binaries** — the distribution end-state; the portable
    Node bundles are interim. Native shells may pop dock cards out into
    real second OS windows on desktop platforms.
