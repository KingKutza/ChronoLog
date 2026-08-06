# ChronoLog Lexicon

**What this is:** an inventory of ideas in circulation — vocabulary, sketches, and visual directions from every phase of the project. **Nothing here is a requirement or a settled decision.** The project is in a deliberate exploratory phase; documents from any single session (including this one) tend to overclaim settledness. This file exists so ideas survive artifact sweeps, not to bind future work.

**Provenance map:** the project has passed through at least four bodies: a .NET/C# incarnation (only fossil: dead `.vscode` configs, pre-git-history), the Java/JavaFX scaffold (swept from the working tree; lives at git tag of `main` history and branch `codex/implement-gui-mockup-for-tests` = local `pr-2-gui-mockup`, commit `a3c9bdb`), the concept mockups in `GUI_Mockup/`, and the current single-file HTML artifact (`pocket-instrument.html`, see `POCKET_INSTRUMENT_HANDOFF.md`).

---

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
