# ChronoLog Lexicon

**What this is:** an inventory of ideas in circulation — vocabulary, sketches, and visual directions from every phase of the project. **Nothing here is a requirement or a settled decision.** The project is in a deliberate exploratory phase; documents from any single session (including this one) tend to overclaim settledness. This file exists so ideas survive artifact sweeps, not to bind future work.

**Current implementation note (August 2026):** the model-first redesign in
`POCKET_INSTRUMENT_HANDOFF.md` supersedes r4 storage, finite celestial fixtures,
and tab-based lens mechanics. The historical entries below remain an idea and
provenance inventory.

**Provenance map:** the project has passed through at least four bodies: a .NET/C# incarnation (only fossil: dead `.vscode` configs, pre-git-history), the Java/JavaFX scaffold (swept from the working tree; lives at git tag of `main` history and branch `codex/implement-gui-mockup-for-tests` = local `pr-2-gui-mockup`, commit `a3c9bdb`), the concept mockups in `GUI_Mockup/`, and the current single-file HTML artifact (`pocket-instrument.html`, see `POCKET_INSTRUMENT_HANDOFF.md`).

---

## The founding conception (Don, stated directly, 2026-08-06 session)

The original concession: there are **timelines**, each internally consistent to some function of time (a person's personal perception of time, a world's collective perception, etc.). There are **events**, which attach to **0 or more** lines; an event attached to multiple lines **staples** them together at that point. Render the view for any one line and see its events along it, with other lines weaving in and out. The robustness target: display every relationship in the time-travel-movies diagram (`GUI_Mockup/bak.png`).

Observations in circulation about this conception (candidate refinements, not rulings):
- Lines never touch except through events — a bipartite lines×events incidence structure; the handoff's directed metric multigraph *emerges* from it (two staples with unequal separations = the two-anchor bond / holonomy).
- 0-incidence events are floats/todos — the "tension flow" may already have a slot in the primitive: scheduling = stapling to a line.
- Renderer freedom is delimited: prime line straightened; other lines pinned **only at staple points**; between staples the drawn weave is honest interpolation.
- The diagram forces multi-incidence: the same event may attach to two different points of the *same* line (Harry Potter, Primer).
- Branching (every gray fork in bak.png): open choice between lines-that-fork vs. new-line-sharing-a-prefix (needs a shared-segment relation). Groundhog Day poses the twin question: one world-line re-entered vs. many identical copies — schema should likely permit both readings.
- Outside the primitive as stated: segment-level existence amplitude (Back to the Future's fading photograph) — annotation on a line segment, not connectivity.

Extensions (Don, same session):
- **Common segments** — two lines can share a segment outright (no event-by-event stapling of a shared past).
- **Terminators** — lines have terminators; a terminator staples 0 or more lines. Observed states: *stapled* (continues into something), *sealed* (truly ends), *open-for-this-rendering* (truncated, not dead — a view-level state, not a data-level one). A **fork** = a start-terminator stapled to a mid-point of another line; lines never branch internally.
- **Groundhog Day, encoded**: Earth line to Feb 2 6:00a (segment shared with Phil); n replicated 24h world-lines, each start-terminator stapled to Earth's endpoint, each sharing Phil's continuous line, far ends open; future-Earth's start-terminator staples to the final loop-day only.
- **Bulk discipline** — replication must be recorded pickily: template line + references + per-copy deltas ("Timeline Duplication" from ReadMe.txt). Precedent: ICS RRULE (template+rule) / EXDATE (deleted copies) / RECURRENCE-ID (per-copy patches).
- **TODO variant** — zero-length, 0-anchor event, attachable later; needs *cycle* (cf. VTODO+RRULE) and *predeterminacy* — a spectrum: free float → deadline-bound → appointment → closed-loop predestination (Harry Potter events are maximally predetermined). Possibly the same axis as segment existence-amplitude, signed (determinacy of future vs existence of past).

Rulings and additions from browser testing (Don, 2026-08-06, r3):
- **Cyclic is its own lens**, not a wrap option inside Strategic — Don's ruling, superseding the handoff's "cycle as an option, never primary." It shows density patterns and cyclic events far better than the path. (Proper name still open; "Cyclic" is the placeholder detent.)
- **Meaning in color must be user-authored** ("No, Grouping") — not inferred from UID hashes or Outlook CATEGORIES (census: only 388/2,710 events categorized, dominated by resource-booking noise). r3 implements groups: user assigns series → group, group → ink color; legend chips cycle normal → lift (render as text) → hide. Assignments are annotation state, baked into copies, never written back to the calendar — **the instrument is read-only of calendar data** (Don, explicit).
- **Spiral-wheel scroll intuition** for intimate (days entering bands from top/bottom as you scroll) — Don flags it "probably a bad idea, or maybe a convoluted good one." It is the **roll law** (handoff §7.2) resurfacing in tactile form. Parked, not dismissed.
- **Radial view experiment** shipped in r3: arbitrary cycle length in days, events spiral outward one ring per cycle, angle = position in cycle. The circle-as-quotient made into a control: the cycle length is *a setting*, not a fixed week/month.
- Wishlist, parked: **multiple-calendar rendering** (n ICS feeds — the first honestly multi-line data the project would hold), **ChronoLog classic view** (Prime Line + Side Lines rendering; grouping is its prerequisite and now exists), **tasks** (VTODO ingestion), **super-strategic band** (still undesigned; strategic caps at 18 months where it would cut in).
- Open platform question (Don): is single-file HTML the best renderer body vs Android/Windows app/webapp+VPS? And is ICS the right *internal* structure vs interchange-only? Current stance: severance doctrine keeps both swappable; no ruling.
- The original feature vocabulary has *character* that Don considers necessary to making the app work — preserve voice, not just content, when transcribing.

Rulings and additions (Don, 2026-08-06, r4):
- **Detent, properly defined**: a stable stop state of a smooth motion — an integer quantity of the atomic unit for a scale; the next integer is the next detent. Animation may pass through fractional states but can only *rest* at detents. NOT a synonym for the lens buttons (earlier misuse, now renamed in code).
- **Wall**: the month-sheets view "is just a normal wall calendar" — renamed from Cyclic. Lives at **3 months (quarter) or 1** per view; **strategic lives and breathes at 9 months**. Each keeps its own span.
- **Radial cycle is pickable, not unit-based**: one cycle = recurring-item-to-recurring-item (lunch-to-lunch, new-moon-to-new-moon). Cycles therefore have **variable lengths** — the "second measure on edges" made visible in a renderer. Anchor selection is by *title-family* (covers both RRULE series and explicitly repeated events). Want lunar months? Load a calendar of new moons: `fixtures/celestial.ics` (126 synthetic celestial events, 2025–27, committed).
- **Radial has two variants**: *spiral* (each cycle one ring outward; natural units as discrete ticks; events as arcs stretching across units) and *concentric* (ONE cycle; one band per group; events as arcs stretching to length, overlapping).
- **Multiple calendars**: loads accumulate as named sources (removable); CATEGORIES from any source seed the groups.
- **Roll, first dose** (intimate, toggle): drag the header / horizontal wheel slides the window continuously; on release it settles at the nearest whole-day detent. The spiral-wheel intuition, testable.
- **Lines view, first attempt**: horizontal time, Prime line (ungrouped) + one line per group, glyphs on lines. Tried per Don ("good to try even if we don't think it will work"); no weaving yet.
- **Editing ruling (supersedes r3's read-only note)**: "saving changes live to an ICS seems a core necessity, also the ability to create and update events." Not yet built. **Architectural prerequisite**: lossless round-trip — the parser currently keeps ~10 fields and discards the rest (ATTENDEE, DESCRIPTION, VALARM…), so writing back today would destroy data. Editing requires raw-property passthrough in the normalized model, an ICS serializer, and a live-save channel (File System Access API on Chromium; download fallback elsewhere). Grouping annotations remain view-state (baked), distinct from calendar edits (written to ICS).

Empirical scale findings (Don, r4 field testing, intimate lens with free back/fwd):
- No settled scale — and **the adjustability itself is the win** (settings-not-code, validated in the field).
- Legibility by window width: **1–3 and 5–9 good, 7/14/21 good (living at 21), 43 legible, 61 cursed**. These sweet spots are *empirically located detents* on what is evidently one continuous zoom — the intimate window at 14–21 days does tactical's job, at 43 it brushes strategic. Candidate reading: the lens ladder is one scale with named rests, per the handoff's unbuilt roll-law-with-detents.
- The 61-day curse is renderer arithmetic (column width below legibility), not time structure — scale limits belong to the renderer layer.

Instrument-side findings against the real export (2026-08-06): ~90% of the 34MB file is ATTENDEE noise; events carry hand-assigned CATEGORIES usable for honest color-coding; VTIMEZONE encodes DST as RRULEs anchored in 1601. **Diagnosed and fixed in r2:** 854 VEVENTs (31%) were silently dropped for lacking SUMMARY — 851 were Outlook recurrence *overrides* (moved/modified instances) that inherit their title from the parent series by UID; dropping them made moved meetings render at their default times (doctrine violation: those are the actuals). Fix: title inheritance + Z-stamp (UTC) → viewer-local conversion. All 2,710 now parse; 941 overrides live (was 90). Full TZID math remains open per the handoff.

## Vocabulary (time-traveler framing, from ReadMe.txt and the pr-2 mockup)

- **Prime Line / PrimeLine** — the canonical timeline; the one currently displayed as primary.
- **Party Lines** — competing candidate timelines: "each of these is a timeline that can be displayed as prime." Any line can be promoted.
- **TimeLines** — timelines as first-class objects: *Timeline Duplication*, a shared *Datastructure*, and *Interesting TimeLines* ("setting different constant values") — i.e., timelines as parameterized variants of a base structure.
- **Twice in a Lifetime Events** — (paired with) **Parallel Universe Scheduling**.
- **Time Capsules** — deferred payloads addressed to a future point.
- **Quantum Annotations** — per the pr-2 mockup: an "event inspector for timeline branches, loops, traveler notes, and capsules."
- **Traveler's Log** — journal of the person moving along the line.
- **Temporal Topography** — density/load of time rendered as terrain (flagged "Possible Feature" originally; the concept mockup draws it as a month-long elevation strip; empirically validated 2026-08-06 when the strategic lens first made planned-density falloff visible over future months).
- **Secondary Archive, Loop Candidate, Capsule Fork** — line names from the pr-2 canvas mockup's list view.
- **Super-strategic band** — a lens beyond strategic; the reason the strategic span caps at 18 months. Undesigned.

## Information architecture sketches

- **pr-2 JavaFX shell (June 2026):** 4-pane layout — top bar (New Event / Duplicate Timeline / Prime Line), left view-switcher (PrimeLine, TimeLines, Events, Notes, Journals) + Party Lines list + legend, center canvas ("Parallel Universe Scheduler"), right inspector ("Quantum Annotation" + Time Capsules). The canvas actually draws branching timelines: quadratic-curve branches off a prime line, arced time-loops, drop-lines to a date strip. The only drawn rendering of a branching/looping timeline in the project.
- **Concept image (`GUI_Mockup/ChatGPT Image Jun 16, 2026…png`):** horizontal Prime Line spine across a month with event glyphs hanging off it; parallel color-coded Side Lines per context; glyph vocabulary (event ●, milestone, recurring ‖, decision ◇, note, journal, deadline ⚑); Topography strip; filters; lens detents DAY/WEEK/MONTH/QUARTER/YEAR.
- **`GUI_Mockup/bak.png`:** the time-travel-movies timeline taxonomy — visual intuition for timelines as a directed graph with branches and loops.
- **Pocket instrument lens ladder:** intimate / tactical / strategic (+ cycle wrap), see handoff doc.

## Visual language candidates

- **Dark cockpit (pr-2 `styles.css`):** near-black grounds `#10131a`/`#171b25`/`#151a23`, cream text `#f7f3e8`, gold headers `#f0c66a`, orange prime `#e75b3c`/`#ff8a66`, green secondary-archive `#45f0ae`, purple/yellow loop annotations `#d889ff`/`#ffd166`.
- **Warm paper & ink (concept image; adopted by pocket instrument r2):** cream paper ground, dark warm ink, red prime/now, per-context ink palette (red/green/blue/purple/orange/pink/teal/gold), hand-annotated feel.

## Data-layer notes

- ICS (RFC 5545) is the interchange floor: universal (Outlook/Google/Apple/CalDAV), already carries recurrence, busy-status amplitude (`X-MICROSOFT-CDO-BUSYSTATUS`: BUSY/FREE/TENTATIVE/OOF/WORKINGELSEWHERE), and has native component types beyond events — `VTODO` (float/tension items) and `VJOURNAL` (Traveler's Log) — but models a flat event set, not a timeline graph. Branches/loops/prime-line would be a layer above; ICS remains ingest/egress.
