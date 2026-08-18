# Agent notes

ChronoLog is a local-first timeline instrument, pre-alpha and exploratory:
timelines are first-class objects, events staple onto them (sometimes onto
more than one), and seven lenses project one shared `chronolog/1` document.
Read [LEXICON.md](LEXICON.md) for vocabulary and the
founding ideas before naming anything new — it is the owner's own voice and
brainstorm space. Meaning is authored by the user: color and semantics come
from the user's own grouping and frame choices, never inferred (not from
UID hashes, not from imported categories). Keep the lexicon's vocabulary and
character when you touch adjacent code or docs.

## Architecture map

### `src/`

- `app.js` — the bootstrap: constructs the document/session/store/history,
  wires every `src/ui/` module onto the shared `app` object, and kicks the
  first render.
- `ui/` — the UI modules `app.js` wires together, each receiving `app`
  explicitly and reading its current fields at call time:
  - `inspector.js` — the Inspector panel: open/close chrome, the
    provisional-draft lifecycle, the event/object-kind form, and
    generated-fact materialization.
  - `frames-panel.js` — the Frames workspace: frame/group/pattern authoring
    forms and the Frames/pattern browsers that share an "object browser"
    shell.
  - `toolbar.js` — the lens bar, document menu, history controls, create
    menu, theme editor, and lens-workspace configuration dialog.
  - `drag.js` — pointer/wheel/drag mapping onto the lens surfaces: pan/zoom,
    drag-to-move, drag-to-create, Intimate rail rebasing, minimap scrubbing.
  - `calendar-sync-panel.js` — the ICS feed UI: file import/export, staple
    suggestions, and the read-only HTTPS calendar-feed subscription panel.
  - `dock.js` — the dock: the handle rail, the transform-only card pager, the
    width drag and the side swap. It holds no rules of its own — it measures,
    asks `src/dock-layout.js`, and applies the answer — because it is the part
    that cannot run outside a browser.
  - `workspace.js` — the render loop and minimap wiring.
  - `transactions.js` — document-mutation-with-undo helpers shared by the
    inspector and Frames panel.
  - `dom-helpers.js` — `byId`/`escapeHTML`, the two DOM utilities shared
    across the `ui/` modules.
- `model.js` — the `chronolog/1` document shape, validation, and mutation
  helpers.
- `engine.js` — queries over the document (facts, occurrences, indices).
- `store.js` — the autosave/revision client: talks to the server's document
  API, tracks dirty/saving/conflict state.
- `session.js` — `LENS_CATALOG`, lens defaults, and other view-only state
  (`ViewSession`).
- `projections.js` — rendering for every lens; the shared sigil/mark
  application lives here.
- `lines.js`, `radial.js`, `minimap.js`, `strategic-density.js` — per-lens
  math (topology layout, spiral/concentric geometry, minimap magnitude,
  density budgeting). `minimap.js` owns the whole dot-field contract —
  magnitude, the coarse scale ladder that keeps busy/free contrast readable at
  every document density, field geometry, and per-lens label granularity — so
  `renderMinimap` only draws what it decides.
- `intimate-pan.js` — the Intimate rail's free two-axis pan arithmetic.
  Horizontal motion spends the rail's own scroll slack first and becomes
  whole-day window steps once it is pinned, which is the only thing that works
  on a window wide enough that `1fr` day columns leave no horizontal overflow
  at all.
- `calendar-structure.js`, `calendar-projection.js`, `event-cycle.js` — the
  frame model: fixed nested-calendar authoring/validation, read-only
  projection helpers for that schema, and event-defined (observed-boundary)
  cycle resolution.
- `dock-layout.js` — the dock's DOM-free logic: width clamping and snap points,
  the pager's retarget-don't-queue state machine, and the append-only card order
  that only a user drag reorders.
- `panel-flip.js` — where a dropdown panel goes so it stays inside the window.
  Panels are placed from measurement; pinning one to an edge in CSS is what sent
  the lens Options panel off-screen once the context bar became the left third.
- `recurrence-end.js` — how an RRULE stops: COUNT/UNTIL mode detection, their
  mutual exclusion, and the UNTIL values for "ends on this date" (inclusive of
  the whole day) and "stop repeating here" (inclusive of that occurrence).
- `object-kinds.js` — trait bundles for Event/ToDo/Note-shaped objects.
- `visual-language.js` — the sigil vocabulary, theme fields, and the 4-step
  color cascade; contains no DOM code so it is testable as a pure contract.
- `ics.js` — ICS parsing and serialization.
- `calendar-sync.js` — reconciles an imported ICS source's frame/events into
  the document across repeated pulls (stable keys, source-owned records,
  reference rewrites).
- `exact.js` — exact rational/BigInt math; no `Date` arithmetic in domain
  code.
- `formula.js` — a thin barrel re-exporting the sandboxed
  `chronolog-formula/1` pattern language (no `eval`/`Function`, no ambient
  host access) from `formula/`: `tokenizer.js` (lexer), `parser.js` (AST),
  `runtime.js` (sandboxed evaluator + builtins). Preserves the historical
  import path for callers (`src/engine.js`, tests).
- `frame-edit.js` — frame-kind trait rules and authoring-capability flags
  used by the Frames editor.

### `tools/`

- `serve.js` — the local, localhost-only (`127.0.0.1`) HTTP server: static
  assets plus the ETag-CAS document API (`GET`/`PUT` with
  `If-Match`/`If-None-Match`, `409` on stale writes) and the calendar-feed
  API surface.
- `calendar-feed-service.js` — the HTTPS ICS subscription adapter: fetch
  with redirect/size limits, DNS pinning, and blocked private/reserved
  targets; owner-only connection-secrets file.
- `build-portable.js` — builds the self-contained Linux/Windows bundles
  (embedded runtime + app tree + launcher script).
- `test.js` — the test runner (imports every `test/*.test.js`).
- `check.js` — recursively syntax-checks every `.js` file under `bin/`,
  `src/`, `tools/`, `fixtures/`, and `test/` with `node --check`.

### Other entry points

- `bin/chronolog.js` — the CLI launcher: argument parsing, data-directory
  resolution (`--data-dir` / `CHRONOLOG_DATA_DIR`, defaulting to the app's
  own directory), spawns `tools/serve.js`, opens the browser, writes
  `logs/launch.log`.

### `test/` and `fixtures/`

Fixtures are acceptance anchors, not scratch data:

- `time-travel-taxonomy.chronolog.json` is the structural counterpart to
  `GUI_Mockup/bak.png` — a deliberately small graph that makes
  the model's unusual claims executable rather than tracing every film in
  the image. It asserts: a fork is a terminator stapled to an interior point
  of another line (lines never branch internally); one event can attach
  twice to the same line (repeated incidence, e.g. Primer/Harry Potter); two
  lines can share a bounded segment through common anchors without copying
  every intervening event (branching/looping/shared-segment lines); a
  displacement can record forward traveler time against reverse world
  direction as endpoints only, with no fabricated continuous conversion; a
  loop is two terminators stapling back to the same line; a sealed
  terminator persists a true ending; and `open` is projection state (absence
  of a rendered terminator at a viewport edge), never a stored claim that a
  line ends. It deliberately leaves segment-level existence/determinacy
  amplitude out of the core graph — that is an annotation problem, not
  license to add a second connectivity mechanism before its semantics are
  decided.
- `skyland-coordinate-mapping.chronolog.json` is the frame/mapping
  acceptance fixture: an 8×8×8 named non-Gregorian hierarchy and a
  discontinuous, forward mapping of five Earth hours to nine Skyland days,
  using authored Skyland units rather than terrestrial weekday assumptions.
- `frames-panel-scale.json` and its generator exercise Frames-panel scale
  behavior.
- `test/helpers/sample-document.js` is the standard test document. Tests
  must never depend on personal or local data (`src/celestial.js` and any
  personal `*.ics` file are untracked and machine-specific; the sample
  document exists so the suite never needs them).

GUI_Mockup images are live design references — never delete them.

## Engineering contracts

### Persistence

Journal + snapshot. `chronolog.chronolog` is a snapshot loaded at boot;
`chronolog.journal` is JSONL, one line per committed edit:
`{seq, ts, label, ops:[{op:"put"|"del", map, id, value?}]}`. Ops are
record-level and idempotent across all seven maps (`meta`/`foreign` keyed
by top-level property), so the server applies and compacts them with zero
domain knowledge. `src/ops.js` holds the one shared `applyOps` — client
rebase and server replay must never diverge. The server
(`tools/journal.js`, wired in `tools/serve.js`) keeps the materialized
document in memory with a lazily invalidated response buffer;
`.chronolog-journal-state.json` carries `currentSeq` across compaction,
and a truncated final journal line is discarded with a warning, never
fatal.

API: `GET /api/document` returns the materialized document.
`POST /api/journal` `{baseSeq, entries}` appends and returns `{seq}`; a
stale `baseSeq` gets `409 {currentSeq, missed, truncated}` — the client
rebases missed ops (record-level last-writer-wins) and reposts.
`GET /api/journal?since=N` serves the tail. `PUT /api/snapshot` is the
deliberate whole-document upload (first run, opening a different file) —
seq advances so lagging windows reload. `GET/PUT /api/settings` carries
`snapshotPeriodMinutes` (default 10) from `.chronolog-settings.json`.
Compaction (apply journal, atomic snapshot rewrite, truncate) runs at
boot, on the periodic timer, and on shutdown — SIGINT/SIGTERM on POSIX,
stdin-close on Windows, where signals cannot be delivered.

Referential cascades are the edit's job, not the loader's. An override names the
occurrence it acts on by a virtual id (`${patternId}/${encodedKey}`), so an
override belongs to its pattern the way a relation belongs to an event: deleting
a pattern must delete its overrides in the same undoable transaction. That
invariant lives in the bundle helpers (`src/ui/transactions.js` —
`executePatternChange` plus the event/event-set/frame bundles) and in the sync
reconciler, so undo restores pattern and overrides together and the journal
carries every removal. `removeOverridesForPatterns` and `overridePatternId` in
`src/model.js` are the single derivation every consumer shares.

Because validation runs only at load, a document journaled into an invalid state
fails long after the edit that caused it — and one bad pointer rejects the whole
file. So `compactDocument` repairs what it can before validation, counting each
repair into an optional caller-supplied report that `parseDocument` threads
through (never a field on the document, which would end up serialized). The
recoveries are siblings: legacy recurrence constraints, dangling override
replacements, and overrides orphaned from a deleted pattern. `validateDocument`
itself stays strict; repair belongs to the parse path alone.

Client: edits are captured as ops at the `src/ui/transactions.js` helpers
and the converted direct-delta sites; the store batches ops on the 350 ms
debounce into one journal post. Undo/redo post inverse ops. The File
System Access path (local file handle) still writes whole documents.
There is no recovery copy and no download/reload conflict flow — recovery
is journal replay, conflicts are per-op sequence collisions.
`calendar-sync.js`'s reconciler assigns or deletes whole records, never
mutates in place — the sync diff relies on that invariant.

### Frame model

Frames are open trait records, not a closed type enum — `traits` add
capabilities (`calendar`, `timeline`, `line`, `cycle`, `measure`, `group`,
`importance`, ...) and unfamiliar traits remain valid data. Four concepts
stay distinct and must not collapse into each other:

1. A **frame/line** owns temporal coordinates.
2. A **unit system** (`coordinate.kind: "nested"`) names and nests
   coordinate levels and their boundaries.
3. A **coordinate mapping** relation authors a relationship between
   positions/intervals in two frames, with explicit `continuity`
   (`continuous`/`discontinuous`) and direction — never an invented
   interpolation across a discontinuity.
4. A **lens** projects a leading frame and optional companions; selecting
   or displaying a frame never creates a mapping.

Event-defined periods (`period.kind: "event-defined"`) resolve exactly
against their authored, strictly ordered boundary series — no averaging and
no extrapolation past the series. Approximate fixed periods must carry
`provenance.kind: "approximation"` and are never presented as observed or
computed.

### Visual grammar

One fixed sigil vocabulary (point/diamond/repeat/ring/square/split-diamond/
span — see `src/visual-language.js`) applies across all seven lenses
(Intimate, Tactical, Strategic, Wall, Lines, Spiral, Radial); a lens may
omit a mark it cannot render at scale, but must not repurpose one to mean
something else. Color identifies an authored frame/group/context; it is
never the sole carrier of an event's structural role — that is always paired
with sigil shape, so a theme or grayscale display does not erase meaning.
Themes are an 8-field palette (ground, surface, paper, ink, muted ink,
primary, secondary, accent); only primary/secondary/accent are authored,
everything else derives via `color-mix`.

Object color inheritance is a 4-step cascade, implemented once in
`src/visual-language.js` — lens renderers must not choose colors
independently:

1. An explicit color on the object overrides everything else.
2. A group color overrides temporal-frame color. When an object belongs to
   several groups, a group explicitly shown by the active frame wins;
   otherwise the group with the most event members wins, with authored
   membership order as the tie-breaker.
3. The active temporal frame wins when the object belongs to several
   frames, then the frame supplying the rendered fact, then its other
   authored frame attachments.
4. A semantic fallback applies only when none of the above has a color.

### Calendar sync

The one sync interface is read-only HTTPS ICS subscriptions
(`tools/calendar-feed-service.js`), plus ICS file import/export. A pull is
one undoable document change; a source's revision advances only after its
snapshot parses successfully. Feed secrets (the full subscription URL) live
in `.chronolog-calendar-connections.json` in the data directory,
owner-only on POSIX and relying on NTFS ACLs on Windows; the document
itself only ever gets an opaque connection ID, provenance, and the
acknowledged revision. Write-back is disabled — see ROADMAP.md's
provider-write-back-gating frontier.

Provider-specific API integrations are out of scope (severance doctrine):
ICS is the interchange boundary. Do not add a provider SDK or API client —
a new provider connects the same way Outlook/Google/Apple do today, through
a published ICS URL.

### Lens extension contract

To add a lens: one `LENS_CATALOG` entry in `src/session.js` (title, backing
projection, declared capabilities), a renderer in `src/projections.js`, and
serializable settings via `ViewSession.toJSON()`. A newly registered lens is
placed after a user's persisted ordering without resetting it. A renderer
that cannot support the current document must use the projection's explicit
visible error state — it must not break other lenses or invent a coordinate
conversion.

## Standing rules

- This is a **public repo** — never commit calendar data or other personal
  files. `*.ics`, `*.chronolog`, and `local/` are gitignored by rule, and
  `local/` is untracked free space for whatever an individual keeps there.
  `.gitignore` holds generic rules only — never name or describe specific
  personal filenames in it or in docs.
- Only two network contexts matter: **Local** (this machine, `127.0.0.1`
  only) and **WAN** (real sync between instances, future work — see
  ROADMAP.md). There is no LAN tier; don't reintroduce one.
- Pure Node, zero external dependencies. Keep it that way.
- Pre-alpha: break compatibility rather than accrete legacy shims.
- `LEXICON.md` is the owner's voice — agents never edit it unprompted, even
  when it references something that has since moved or been deleted.
  Additions happen only at the owner's direction, in his words.
- `GUI_Mockup/` images are live design references — never delete them.
- The doc set is exactly four files: this file, `README.md`,
  `ROADMAP.md`, and `LEXICON.md`. Don't create new `.md` files.
- Prefer behavioral tests over source-text string assertions.
- Run `npm test` and `npm run check` before finishing work.
