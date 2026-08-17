# Roadmap

This is direction, not commitment. ChronoLog is exploratory and any ruling
below can change; see [CHRONOLOG_LEXICON.md](CHRONOLOG_LEXICON.md) for how
unsettled the founding ideas still are.

Distribution direction: today that's `npm start` / `npm run dev` from a
source checkout plus portable Linux/Windows bundles (`npm run
build:portable`). The stated end-state is compiled native binaries, not an
npm-registry package.

Only two network contexts matter: **Local** (this machine, `127.0.0.1` only)
and **WAN** (real sync between instances across the internet, future work —
see b3). There is deliberately no LAN tier in between; the owner's ruling is
that LAN mode should never have been added.

## Ratified next

These are approved designs, not yet implemented.

### Journal + snapshot persistence

`chronolog.chronolog` becomes a load-time snapshot rather than the live
document. Every committed edit appends one JSONL operation line to a new
`chronolog.journal` file. Loading a workspace means: read the snapshot, then
replay the journal on top of it. Compaction rewrites the snapshot atomically
on clean shutdown, plus on a periodic timer whose period is user-settable
(see the settings window below). Conflict detection moves from a
whole-document hash CAS (the current ETag `If-Match` contract) to per-append
sequence numbers: a writer appends against the sequence number it last read,
and a gap or mismatch is the new conflict signal. Saves become journal
updates, never whole-document overwrites.

This design replaces, not supplements, today's recovery and conflict
machinery: the rolling `.chronolog-recovery.chronolog` copy goes away because
recovery becomes journal replay, and the download/reload keep-both conflict
flow goes away because conflicts become per-op sequence collisions instead
of whole-document collisions.

### Settings window

A window for Theme and Defaults control (issue G). Planned contents: theme
selection, workspace defaults, and the snapshot-compaction period that the
journal design above needs a control surface for.

## Don's current issues

Absorbed from `8.17.26_Issues.md`, keeping his lettering. That file is not
deleted — Don retires items from it himself.

**b2 is high priority**: real two-way sync with popular calendar apps,
Outlook first. An earlier attempt used the Microsoft Graph API directly and
was, in the owner's words, "a spectacularly bad way to implement it" — the
goal stands, only that implementation was wrong. The intended path is
ICS-compatible semantics (import/export), not a provider REST API, and it
stays gated on real conflict resolution, which the ratified journal design
above is meant to lay the foundation for.

- **A** — Minimap dots are too large, and require too many events to register.
- **b** — Figure out and test web calendar sync.
- **b1** — Add Google Calendar and other popular calendars to the sync list.
  These connect the same way Outlook does today: through a published,
  per-provider ICS URL. No provider API integration is planned (see Design
  frontiers below).
- **b2** — **High priority.** Make calendar sync two-way, Outlook first.
  Write-back goes through ICS-compatible semantics (import/export), never a
  provider REST API, and stays gated on real conflict resolution — see the
  callout above and field-level merge below.
- **b3** — The WAN story: make sure two ChronoLog instances can sync across
  the web. This is real internet sync, not the (removed) LAN tier, and it
  builds on the same journal / per-op foundation as the high-priority
  two-way calendar sync in b2.
- **C** — *RESOLVED.* Was the AppData question; the per-OS data-directory
  system has been removed. Data lives in the app's own directory by default,
  in both dev and installed/portable mode; `--data-dir` relocates it.
- **D** — Look at a mobile app version.
- **E** — Make control bars less ugly.
- **F** — New-item dropdown renders behind control bars.
- **G** — Still lacks a settings window for theme and defaults control — see
  Ratified next above.
- **H** — No TODO or Notes implementation.
- **I** — Horizontal lines for the base increment in the Intimate lens are
  not visible inside colored zones.
- **J** — "Jump to today" and "reset lens" should be in reverse order.
- **K** — (open)
- **L** — Design a new, better logo. The original mark was deleted outright
  ("kill that stupid logo"); the app is plain text until a better one earns
  its place.

## Design frontiers

Undesigned or open questions, not yet ratified:

- **Super-strategic band** — a lens beyond Strategic; undesigned. Strategic
  currently caps at 18 months where this band would need to cut in.
- **Field-level merge** — the current conflict policy is deterministic
  keep-both (see AGENTS.md's persistence contract). A real field-level merge
  model is future work, and the ratified journal + snapshot design above
  (per-append sequence numbers) is its foundation.
- **Provider write-back gating** — ICS-compatible write-back (b2, high
  priority, Outlook first) stays disabled until conflict resolution for
  recurring/edited events is designed.
- **Notes don't round-trip ICS** — VJOURNAL is unimplemented, so authored
  Notes have no ICS export/import path yet.
- **Platform question** — single-file HTML/webapp vs. a native app (Android,
  Windows) remains open, per the lexicon's "severance doctrine" stance:
  keep the renderer body and the internal data model swappable rather than
  rule on this now.

## Test direction

Test suite direction going forward: behavioral tests over source-text
assertions.
