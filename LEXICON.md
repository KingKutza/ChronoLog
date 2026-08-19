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

Rulings and additions (Don, 2026-08-17/18, KISS pass + dock/floats design):
- **The staple axiom**: "there is no such thing as a time-native object, only
  objects better or worse stapled to time." Ruled while rejecting a proposed
  float gutter for todos/notes — a separate band "creates a false distinction
  between time native and time non-native objects." Everything renders in the
  one lens field; sigils and zones carry the differentiation.
- **Floats live at their staples**: staples come from acts — date added, date
  edited, date done, a due cycle, an event attached to. "If that staple is
  date added, cool, that is where it lives." An object edited every day for
  eleven days belongs to that span. Zero-staple objects are possible; most
  carry one or more.
- **Projection decays, data never does**: the deadliest documented todo
  failure mode is "the build up of unimportant nonurgent todos — they cluster
  around now and never resolve, only blocking window space. I don't want to
  delete all the things I wrote down and never did, but I also can not afford
  to keep them up." Resolution: unresolved todos/notes project forward from
  their staple for an importance-scaled keep-range (high priority ≈ three
  weeks, standard ≈ one week), then lapse from the present view while
  remaining at their historical staple. Display work needed "in sigils and
  zones to make that intuitive and informative without piling too much
  information on the eye — but I think it is doable."
- **Importance is a group affiliation, not a property**: "importances are
  just group affiliations; how members are handled is a property [of the
  group]. This makes importance composable — I can add and remove levels,
  including ones of an irregular nature." The keep-range/decay behavior
  above lives on the importance group, not on the object and not in a fixed
  tier enum.
- **Spiral and Radial are separate lenses** — supersedes r4's "Radial has two
  variants." Seven lenses total: Intimate, Tactical, Strategic, Wall, Lines,
  Spiral, Radial.
- **Chrome vocabulary**: the three command bars are the **document bar**
  (logo, save status, document actions), the **view bar** (navigation among
  views — the lenses, and future views), and the **context bar** (controls of
  the active view); together the **chrome stack**, one third wide, with the
  minimap holding the other two thirds at full stack height.
- **The dock**: one multi-function dock hosts editors as full-bleed cards,
  paged one at a time — "switch and swap fast, without looking at the point I
  am clicking on, by the 10th time." The stage hosts views; the dock hosts
  editors; settings takes over the stage. No floating windows in the webapp;
  the final native app may host persistent second windows on non-mobile
  platforms.
- **ICS is the interchange boundary** (partial answer to the r3 platform
  question): the Graph API integration was stripped — "a spectacularly bad
  way to implement" calendar sync; two-way sync with popular calendars,
  Outlook first, remains a high-priority goal via ICS semantics. Provider
  API clients are out.
- **Staple anchoring** (from entering a friend's work schedule for D&D
  planning — "working early to 5ish," "can't go later than like 7:30/8,"
  irregular night-shift cycles): the system is "built under a start time
  duration assumption," and that assumption must go. "We should be able to
  place a staple — start, end, midpoint, etc. — and a magnitude; or two or
  three staples and calculate magnitude. Also a fuzzy staple, e.g. 'about
  5ish,' would be good too." Fuzziness becomes per-staple, not per-object —
  the staple axiom made concrete. Adjacent, unruled: "can't go later than
  7:30" reads as a bound — a constraint staple distinct from the fuzzy
  actual. Series staple the same way: "the goal is to be able to staple a
  series at the beginning, the end, or any other arbitrary point we can
  use as reference to the location of its body" — ending a series is an
  end-staple, not a command (a shipped "stop repeating here" button was
  ruled "the most broken backward way to do what I said while undermining
  what I meant" and removed); stapling an arbitrary occurrence anchors the
  cycle's phase.
- **The healing invariant** (series semantics, stated after weeks of
  circling it): "any time we have a pattern we save the pattern and
  project. Any time we have a deviation from the pattern, we override the
  instance with an event. Any time that overriding event matches the
  pattern, the event is removed and the projection reasserts. The series
  of events leading up to the heal are irrelevant." Not fork-prevention —
  convergence: the issue was never that a fork occurred but that it was
  not healed. No-op edits, edit-then-revert, delete-then-recreate-in-place
  are all the same case; redundant overrides are removed the moment they
  stop deviating, regardless of history.
- **The Rob-and-John scenario** (the correct usage pattern series stapling
  exists to support): Rob says "let's do Monday meetings — you always get
  in early on Mondays." John adds a Monday meeting, 6:15 to 6:30, repeat
  every Monday, skip holidays (events on frame xyz), run indefinite
  (projected up to 2 years into the future; default settable in
  settings). Six years later John has a kid, doesn't get in till 8:00,
  and after some conversation they move to a Thursday lunch meeting. At
  that decision they place a staple at the inflection point defining an
  end to the initial series rule, then either define a new rule
  post-staple or a new series, on preference. What this pins: a series is
  an identity whose rules are segments partitioned by staples; holiday
  exclusion is a live reference to another frame's events, not a baked
  list; the rule's extent (indefinite) and the projection horizon
  (bounded, settable) are different things; and the inflection staple
  records where life changed the schedule.

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
