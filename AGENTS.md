# Agent notes

ChronoLog is a local-first timeline instrument, pre-alpha and exploratory:
timelines are first-class objects, events staple onto them (sometimes onto
more than one), and nine lenses project one shared `chronolog/1` document.
Read [LEXICON.md](LEXICON.md) for vocabulary and the
founding ideas before naming anything new — it is the owner's own voice and
brainstorm space. Meaning is authored by the user: color and semantics come
from the user's own grouping and frame choices, never inferred (not from
UID hashes, not from imported categories). Keep the lexicon's vocabulary and
character when you touch adjacent code or docs.

## Architecture map

### `src/`

- `coordinate-law.js` — the single coordinate-arithmetic engine: the transition
  registry, the registered CLDR calendar families, and the `CoordinateLaw` that
  answers every unit question from a frame's own declaration. See the
  "Coordinate law" contract.
- `eras.js` — the era table: ordered named eras with per-era numbering direction,
  converting an era-qualified year to the proper year the year ladder counts in,
  and refusing a table it cannot resolve. Pure and document-free.
- `calendar-structure.js` — the authoring side of that declaration: the regular
  fixed-hierarchy builder, the editable level/cycle/era rows, and the one parser
  and one count check for every authored name list.
- `coordinate-entry.js` — the variable-precision coordinate field's substrate:
  one text entry parsed and formatted at whatever depth the author typed, plus
  the zoomable picker's rung ladder. Every level name, order, radix and value
  name comes from the governing frame's law, so a custom calendar's field parses
  in its own units. Entry depth is **precision, never uncertainty** — fuzziness
  is authored separately, on the staple.
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
  - `roster.js` — the ToDo and Notes dock cards: every object of one kind plus a
    "new" affordance that anchors to now, and the state toggle
    (`toggleStateAffiliation`) that writes a state-frame membership plus the
    terminal end staple. The todo lifecycle model is ROADMAP #2 and ruled —
    see "ToDo state and containment" below.
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
- `staples.js` — the staple substrate: a staple is a two-ended **connection**,
  and this holds the open `STAPLE_KINDS` registry, the end accessors every other
  module reads structure through, and every derivation over the connections a
  thing participates in (anchoring and derived magnitudes, event-to-event chains,
  frame-to-frame correspondence, series rule segments, per-staple fuzziness,
  occurrence phase, live exclusion references). DOM-free and pure over
  `{document, engine}`, so the whole substrate is a testable contract. Nothing
  else may hand-read a staple's fields. See "Staples" below.
- `weight-formula.js` — a frame's display-weight handling as a formula over the
  incoming weight `w`, plus the canonical order contributing frames apply in.
  See "Display weight" below.
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
`importance`, `state`, ...) and unfamiliar traits remain valid data. A
**state frame** carries both `group` and `state` (a bare `state` trait is
formula state and never collides); `frame:state-done` ("Done") is minted
lazily by the first completion toggle, never seeded. Four concepts
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

### Coordinate law

A frame's `coordinate` declaration is the **executed law**, not documentation of
one. `src/coordinate-law.js` is the single coordinate-arithmetic engine: every
unit relationship in the program — how many hours are in a day, how long a month
is, what a duration magnitude is worth, how a nested coordinate becomes a day
ordinal — is computed from the governing frame's own declared ladder. Nothing
else may carry a unit relationship as a literal. Setting hours-per-day to 23 on a
frame changes engine occurrence math, projection layout, minimap strides,
duration magnitudes, drag snapping, and the editor's own fields, because all of
them ask the same object.

A declaration is a list of **levels** plus optional **cycles**:

```
coordinate: {
  kind: "gregorian" | "nested",
  levels: [ { name, within?, radix? | transition?, names? } ],
  cycles: [ { name, radix, offset?, names? } ],
  fixed?: { ... }          // src/calendar-structure.js's regular-hierarchy builder
}
```

**Authored depth is data, and it survives.** A coordinate whose `levels` stop
early is a partial coordinate — the author said `1973` and nothing finer.
`toDays` supplies the missing levels from the family's defaults, and `fromDays`
returns every level filled in, at which point the result is indistinguishable
from an authored January 1st midnight: the depth was supplied by the law, not by
the author. So depth is never inferred back out of a resolved instant. It is read
from the **source** coordinate — `coordinateEntryDepth` — and travels on the fact
as `precision`, so display can honour what was actually said. Precision is
**never** fuzziness: entry depth says how finely the author spoke, a spread says
how uncertain they were, and only the second is a claim about the world.

A level declares **exactly one** of `radix` (a constant count of children) or
`transition` (a named rule for a count that varies); the root declares neither,
and a trailing level may declare neither, which makes it its parent subdivided
continuously (`subsecond`). `names` on a level names its children one apiece.

**Units are defined by composition from below.** Owner ruling: *"that is wrong, I
did not change the lenght of an hour I changed the length of a day. Day is
defined as a number of hours, which are themselves a number of minutes, ect."*
The finest declared unit is the **atom**, and every level's length is the product
of the radices beneath it. A radix says how many children fill one parent, which
makes it a statement about the **parent's** length: editing hour-within-day to 23
makes the *day* twenty-three standard hours long and leaves the hour untouched.
An edit is an edit to exactly the unit whose definition it touches. A level's own
edge therefore says nothing about its own length — only its child's edge does,
which is why `day` (carrying `gregorian.days`, "how many days in a month") is a
unit of fixed length while `month` is not.

The atom's own absolute length is the one thing composition cannot supply: it
comes from the registered standard for a unit of that name (a `second` is 1/86400
of a standard day wherever it appears) or is authored as `atomDays`. **The atom is
the shared denominator for absolute comparison** — two laws relate absolutely
exactly insofar as they share an atom, directly or through basis inheritance. Two
frames with no shared atom have **no automatic absolute relation**; that is what
connection staples are for, and inventing one would be the same fabrication as an
invented origin.

The **base level** is the level the family's whole-unit arithmetic counts in — the
"day" of this ladder. It is *not* "one standard day": its length is whatever its
own radices make it. It is the deepest level reached by a transition, or a `fixed`
block's finest level, or an explicitly authored `baseLevel` (which a uniform
ladder must state, having no transition to infer from), or the root.

**Midnight drift is the ruling, not a defect.** Because the day is the unit that
was shortened, successive day boundaries under a 23-hour law fall 23 standard
hours apart and the frame's day sequence slides against the standard calendar.
A civil coordinate under such a law names a position in **that frame's own day
sequence**, not the standard date of the same spelling. Durations follow the same
rule from the other side: "1 day" is the shortened thing, while "180 minutes" is
180 standard minutes whatever the day radix says. The running clock is absolute,
so Now lands where the atom arithmetic puts it and drifts across the frame's days.
ICS instants are standard-Gregorian absolutes and convert through the atom.

A **cycle** repeats over the base unit without nesting in anything. Weekdays are
a cycle, not a level: seven days run straight through month and year boundaries,
so a seven-name list belongs to a cycle whose `radix` is 7 and whose `offset` is
which name lands on day zero. Modelling a weekday as a level is what made a
seven-name weekday list get measured against the number of days in a month.

**Eras are true eras.** Owner ruling: *"Hard No. Epochs, true epochs no faking"* —
rejecting any linearization of eras onto a continuous year axis. An era is a
LEVEL OF THE COORDINATE, never a display label over a proleptic year. An
era-qualified coordinate stores the era and the year **within** that era (`"3E"`,
`433`) and never the linearized year (`4249`).

Two things make that load-bearing rather than pedantic. **Storage:** a record
holding `4249` plus a label would silently re-anchor every date the moment an
era's span were corrected, because the label is derived and the number is not.
**Direction:** an era may number its years DESCENDING — higher number is older —
and no single continuous axis can hold both conventions at once, since 2500 BCE
is older than 44 BCE while 44 CE is newer than 1 CE. Descending numbering is
first-class in `src/eras.js`, not a rendering trick over negative numbers.

An era table is **opt-in per frame declaration**. A declaration without `eras`
behaves exactly as before — the plain proleptic year axis remains the default.

```
coordinate: {
  levels: [ { name: "era" }, { name: "year", within: "era" }, … ],
  eras: {
    anchor:  { era: "First Era", year: "1", properYear: "1" },
    entries: [
      { name: "Merethic Era", abbrev: "ME", direction: "descending" },
      { name: "First Era",    abbrev: "1E", direction: "ascending", years: "2920" },
      { name: "Fourth Era",   abbrev: "4E", direction: "ascending" }
    ]
  },
  baseLevel: "day",          // which level is one day — required on a uniform ladder
  origin:    { days: "0" }   // which day the ladder's first unit begins on
}
```

The era level is the declaration's root and the level beneath it is the one whose
numbering restarts per era. The era level takes no `radix` and no `transition`:
the table governs it. The table is deliberately **not** part of the family's
ladder — it converts `(era, yearInEra)` to the PROPER YEAR the ladder already
counts in, and the family takes it from there. That composition is what keeps
eras first-class instead of cosmetic.

**One anchor, everything else derived.** The author states one alignment they
actually know — "this era's year N is proper year P" — and every era's range
falls out of it plus the bounded spans, propagated forward and backward. A
per-era offset table would be unverifiable by hand; this is not.

An era with no `years` is OPEN, and only one end of the table may be open in each
direction: a **descending** open era must be listed FIRST (its newest year abuts
the era after it; its oldest is unbounded) and an **ascending** open era LAST. An
ascending era open at the bottom would start at negative infinity and a
descending era open at the top would count down from infinity; both are refused
rather than clamped to something invented. Eras must meet exactly — no gap, no
overlap — and a table that contradicts itself is refused before it is stored.

A year outside every declared era has **no name**, and `fromProperYear` refuses
rather than inventing one: a calendar closed at both ends genuinely has no year
there. A coordinate on an era calendar must name its era; a bare year is
ambiguous, and defaulting it to whichever era the anchor sits in would be exactly
the invented meaning this model refuses.

Era names and abbreviations are authored, and each era authors its own affix —
`"3E 433"` versus `"44 BCE"`. Parsing accepts either on either side of the number
and resolves by the authored names, not by shape: an abbreviation may itself
contain digits, so `"3E433"` is only readable because `3E` is an era and `3E4` is
not. A purely numeric name is refused — a number alone cannot be told apart from
a year. Two eras matching the same text is refused, never resolved by precedence.

`law.hasEras()`, `law.eras()`, `law.formatYear(value)`,
`law.formatYearAtDays(days)` and `law.parseYear(text)` are how a surface asks.
Wherever a year renders under a law with an era table, it renders era-qualified.

**The uniform positional family.** A ladder whose levels above the base all count
a CONSTANT number of children is executed by the registered `uniform` family — a
wholly invented calendar converts through the same seam Gregorian does. It has no
transition to infer a day from, so such a declaration states `baseLevel`
outright, and it becomes positional only once `origin.days` says which day its
first unit begins on. Without an origin nothing states where the calendar starts,
and anchoring at day zero by default would place every date by an invented
convention. `uniform` names no CLDR calendar scale, so `calendarScale()` reports
null and a series counting in it is not ICS-expressible as a rule.

**Positionality is a property of the ladder and the registry, never of a kind
string or a trait.** A declaration is positional when a registered family can
actually execute its ladder. `kind: "gregorian"` survives only as shorthand for
"use the registered ladder when none is authored"; it is never the answer to
whether coordinates are positions. Deciding by label placed 2026-08-20 at day
ordinal 20 — off by fifty-six years, silently — for any declaration that spelled
its kind differently. The one semantic marker that remains is `measure` (or
`duration`), and it is not a label for arithmetic: it says what the frame IS. A
measure frame's coordinate is a magnitude, so its levels are counts and no family
may reinterpret them as a date.

**A value naming levels a law does not declare is not a value in that law.** A
`{year, month, day}` coordinate handed to a family-less law whose base level
happened to be `day` placed 1973-03-15 at day 15. A magnitude of "15 days" and
the fifteenth of March are not the same number, so the law refuses rather than
reads. A law declaring no levels at all is a bare day axis and keeps the
permissive read — there is nothing there to contradict.

**Inheriting the standard is not the same as declaring none.** `monthNames()` and
`weekdayNames()` return the registered names for a law that COUNTS in the
registered calendar and merely left a level unnamed, and **null** for a law that
has no such concept — a world with no week has no weekday names, and handing it
seven Gregorian ones invents a fact. `hasMonths()` / `hasWeekdays()` ask
directly; a surface that draws a month grid must handle null by not drawing one.

**A broken frame must not blank the stage, and must not take down a query
either.** `displayLaw` already catches for that reason; `coordinateDaysOrNull` is
the query path's counterpart, returning null so a caller skips the record and
collects the reason instead of aborting. `coordinateLawError` (per frame) and
`coordinateValueError` (per coordinate) are how validation asks — the
refuse-before-store discipline extends to `validateDocument`, because a document
whose coordinates only fail at query time is not a valid document.

**Cross-frame projection exists only through staples.** Owner ruling: *"For
Tamriel, there is no staple between earth and Tamriel, thus no way to project one
to the other. The moment we place a staple, wherever it is everything projects
around that, we place 8 that is where lines shows us the warp."*

Three claims, separate, and none implying another:

| claim | asked by | means |
| --- | --- | --- |
| units are comparable in LENGTH | `law.sharesStandardAtom()` | a Tamrielic hour and an Earth hour are both hours |
| the frame has a now at all | `law.mapsToClock()` | a Now line may be drawn |
| positions CORRESPOND | a staple path (`src/frame-projection.js`) | one frame may be drawn on the other's axis |

An authored `origin` is **chain-internal**: it anchors a calendar's own eras
relative to each other so the chain resolves exact internal ordinals, and it
makes no claim on any shared axis. With no staple path between two frames,
neither projects onto the other — an overlay renders **nothing** of the far frame
and reports why. It must never place that frame's events at origin-derived day
ordinals; dropping Tamriel's Third Era beside 1970 because both count from an
internal zero is a correspondence nobody authored, which is the class of error
this program refuses everywhere else.

`framesProject(document, from, onto)` answers it: same frame, same coordinate
space (every era frame of one calendar), or a chain of frame-to-frame staples.
`projectableFrames` returns the drawable set plus the refusals, and a refusal is
reported rather than dropped — a frame that renders nothing because nothing
relates it to the view is a fact the author needs told.

**Multiple staples define the correspondence exactly at each stapled point** and
are never averaged, never reconciled into a single rigid offset — the same rule
overdetermined anchors follow, for the same reason: an average of two true
answers is a third answer nobody authored. Between two stapled points the mapping
**stretches**, and that stretch is authored meaning — the warp. Drawing it is the
Lines lens's work (ROADMAP #4); the substrate's job is to keep every stapled point
exact and to claim nothing about the space between them.

**No artificial Now.** `law.mapsToClock()` is false for a law that places nothing
on the running clock — a non-positional law, or one whose declaration says
`clock: false`. A lens must not draw a Now line on a calendar with no
now-mapping.

**The transition registry.** A `transition` string resolves through
`registerTransition`; a transition belongs to a **calendar family**, which is
also a CLDR calendar scale, and a family owns the closed-form conversion for the
whole-unit part of its ladder. `daysFromCivil`/`civilFromDays`/`daysInMonth`/
`isLeapYear` in `src/exact.js` are the registered Gregorian family's whole-day
kernel. **Coordinate conversion reaches them only through the family** — never as
a bypass. The remaining direct importers are the places that still walk Gregorian
month/year *boundaries* rather than convert coordinates (the minimap's label
strides, Radial's month windows, the toolbar's date fields) plus RFC 5545's own
recurrence machinery in the engine; each carries a comment saying so, and the
first group is what ROADMAP #6's positional-conversion stage removes. Gregorian
is the first entry, not a privileged branch: adding
Hebrew, Islamic, Indian or any other CLDR calendar is one
`registerCalendarFamily` call plus its transitions, and nothing else in the
program changes.

**An unresolvable declaration is an error surfaced to the author.** A transition
string nothing implements, a radix that is not a positive whole number, a level
nesting inside a level that does not exist, a ladder no family can execute — each
throws with the frame and the offending name in the message. `coordinateLawError`
is how a surface asks; `app.js` reports it on reconcile and the frame editor shows
it in place. A law that quietly means something other than what is written is
unauditable, and silence is what let a dead ladder look alive.

**How a call site asks for arithmetic.**

- `coordinateLaw(document, frameId)` — the law governing that frame, memoized per
  document. Resolution follows `coordinateDefinition`, then the `gregorian`
  kind/trait, then `basis`: a calendar whose basis is Wall Time inherits Wall
  Time's law, including a radix edited there, without restating the ladder.
- `displayLaw(document, session)` — the **primary** frame's law (see the frame
  model: the explicit primary marker owns axis, labels, and coordinate law).
  `session.law` carries it, assigned on every reconcile; a render pass reads that
  rather than re-deriving per helper.
- `law.unitDays(name)` for an exact unit length, `null` when it varies;
  `law.meanUnitDays(name)` for the exact mean, defined for every level;
  `law.unitsPerDay(name)` for "how many minutes in a day". The named
  conveniences — `hoursPerDay`, `minutesPerDay`, `secondsPerDay`,
  `minutesPerHour`, `secondsPerMinute`, `daysPerWeek`, `meanMonthDays` — resolve
  through the declaration and fall back to the registered standard only for a
  level this calendar never authored.
- `law.magnitudeDays(magnitude)` / `durationMagnitudeDays(magnitude, governing)`
  for a duration's worth in days. `governing` is a document (the magnitude's own
  `frame` names the law) or a law. **A call site that has the document passes
  it**; the standard fallback exists for genuinely law-free contexts, not as a
  convenience.
- `law.toDays` / `law.fromDays` for conversion; `law.monthNames`,
  `law.weekdayNames`, `law.weekdayLabel`, `law.cycleIndex`, `law.namesFor` for
  authored names.

Everything is exact (`Rational`, BigInt). Pixels and layout may be floats; unit
law may not. A memoized law is dropped when its declaration changes — by object
identity on every lookup, and by the explicit `invalidateCoordinateLaws` the edit
path calls, because identity alone misses an in-place mutation and the explicit
call alone misses an undo that swaps whole records. Both together are what make
an applied ladder edit live on the next render.

**Boundaries that deliberately stay civil.** Three things speak the outside
world's standard civil Gregorian and convert once, at the edge:
`nowDays`'s host `Date` read; RFC 5545's own wire units and RRULE evaluation; and
`setCivilFocus`'s "go to this calendar date" entry. Each carries a comment saying
so. `civilCoordinateToDays`/`daysToCivilCoordinate` are the named aliases for the
registered-standard conversion, and the name is the assertion.

**ICS is an explicitly lossy boundary.** The contract:

1. **Import** is always parsed as standard civil Gregorian, mapped through the
   registered Gregorian entries. An edited or custom coordinate law never
   reinterprets an incoming ICS time. Additionally, RFC 7529 `RSCALE` recurrence
   rules import: `RSCALE` changes only the calendar the recurrence *counts* in,
   never the concrete times (which RFC 7529 keeps Gregorian), so it is exactly a
   registry lookup — `lawForCalendar(id)`, which returns null for a calendar
   nothing implements.
2. An `RSCALE` naming an **unregistered** calendar preserves the rule verbatim in
   the pattern/residuals and **refuses projection honestly**, surfaced to the
   author. It is never silently computed as though it were Gregorian.
3. **Export** of anything standard ICS can express — Gregorian rules,
   `UNTIL`/`COUNT` — exports as rules and round-trips. A series whose coordinate
   law counts in a registered CLDR calendar exports as a spec-correct `RSCALE`
   rule. Gregorian is `RSCALE`'s default, so a Gregorian rule omits the
   parameter entirely and every existing byte is unchanged.
4. **Export** of anything ICS cannot express — a series under a truly custom or
   user-defined law, arbitrary-unit durations — exports as **projections**:
   concrete occurrences, correct in wall time, rule discarded. There is no
   X-CHRONOLOG semantic dialect for it; foreign-residual preservation is
   unaffected. A series whose law ICS cannot express must never export its
   coordinates as if they were Gregorian.
5. Durations cross in **wall seconds**. A document magnitude converts to exact
   days under its own frame's law, then to seconds through the registered
   standard, and back the same way — so a wall hour stays a wall hour, and under
   the registered standard law the conversion is byte-identical to what it always
   was. `law.calendarScale()` is the question the boundary asks: it stays
   `gregory` for a frame that merely redefined its hours (`RSCALE` governs the
   date ladder and nothing below the base unit), and is null for a law counting in
   no registered calendar.

Positional conversion for a fully custom ladder — a `fixed`-block calendar
converting its own year/month/day to a day ordinal — is the next stage of
ROADMAP #6, not something to guess at. A non-positional law reads its base
level's value as a count of days, which is what a measure frame means.

### Staples

**A staple is an edge, not an attribute.** It connects exactly two things at one
point: `{type: "staple", kind, ends: [endA, endB], spread?, payload?}`. An end
names one thing plus where on that thing the touch point is, and is exactly one
of:

- `{frame, <position>, parameters?}` — a **position in a coordinate space**. The
  frame's own declared law is what makes the position mean anything, so the frame
  travels with it rather than being looked up.
- `{object, point, offset?}` — a named point of an object's extent: `start`,
  `end`, `midpoint`, or a point the user named, which carries its own `offset`
  magnitude from that object's start.
- `{series}` — a whole pattern, positioned by the other end.

A frame end declares **exactly one** of four position forms — more than one is
two claims wearing one record, none is a frame named without saying where on it:

| form | shape | means |
| --- | --- | --- |
| `coordinate` | a nested coordinate | one point |
| `selector` | `{cycle, value}` or `{level, value}` | every instant satisfying it |
| `span` | `{from, to}` coordinates | a region |
| `void` | `void: true` | explicitly nothing |

A **selector** reads the frame's *own* declared cycles and levels, so
`{cycle: "weekday", value: "Tuesday"}` means whatever that frame's declaration
says a weekday is — a frame that renamed its seven-name cycle matches its own
names and not the registered ones, and a selector naming a cycle or level the
frame never declared is refused rather than silently matching nothing forever.
"Tuesdays" is not one coordinate, and writing it as one would pick an arbitrary
Tuesday and call it the answer. Only a `coordinate` position is one instant:
`frameEndDays` returns `null` for the other three, and `frameEndMatches` is the
membership question they answer instead. A partial coordinate and a selector are
different claims — a partial coordinate is one instant at coarse precision, a
selector is every instant that satisfies it.

An authored **void** is a positive claim and a different claim from an absent
staple: it says the author looked and there is no correspondence here, while
absence says only that nobody has said yet. Reading them as the same thing is how
a gap becomes an invitation to interpolate. A void keeps the two-end shape — both
things are still named — so it enumerates as a statement in the correspondence
rather than a hole in it.

**Set-level claims are derived, never stored.** Cardinality, monotonicity and
coverage are properties of the correspondence between two frames, not of any one
staple, so `describeCorrespondence` computes them from the enumerated staples.
Storing them would put one claim in two places — an authored `monotonic: false`
beside a provably monotone set is an editor accepting an edit and ignoring it,
and denormalizing onto every staple means N copies that drift the moment one is
added. `monotonic` is `null`, not `true`, when it cannot be decided: a set
carrying any many-valued or void position has no single ordering to be monotone
against, and a confident answer there is one the data does not support.

The substrate does not care what the two things are, only that each end can
answer "where is your touch point". That is what lets event ↔ event run on the
same machinery as event ↔ frame, and what leaves todos and notes needing no new
mechanism. Ends are in authored order and **no derivation treats index 0 as the
source**: direction is not stored, because it is not authored — an instant known
at one end propagates to the other, and which end is known is a fact about the
document rather than about the staple. `A.end ↔ B.start` and `B.start ↔ A.end`
are therefore the same connection.

Staples remain an **open collection**: a series, an event, a todo, a note, or any
future object participates in arbitrarily many connections of arbitrary kind,
arbitrarily placed. Nothing about ending a series is structural; `kind: "end"` is
one registry entry whose interpretation happens to be "terminate, with no rule
following".

A frame and a series never interchange — the same discipline that keeps a
`termination` relation's `line` (a frame) distinct from a staple's series end. A
staple reaches at most one series, because a series' rules are cut by instants
rather than by another object's extent.

`kind` is validated against `STAPLE_KINDS` in `src/staples.js`, not hardcoded.
Adding a kind is one registry entry plus its interpretation. This is
deliberately stricter than frame traits, which stay valid data when
unfamiliar: a trait is a capability claim a renderer may ignore harmlessly,
while a kind *selects a derivation*, and a kind nothing honours would silently
move things on screen — or silently fail to. A kind declares `connects`: the
canonical sorted end-scope pairs it may join, which is the whole of what it is
allowed to connect. Registered kinds are `end` and `inflection`
(`frame+series`, both partition a series' rules; only `inflection` may carry a
following rule), `phase` (`frame+series`), `anchor` (`frame+object`,
`object+object`, `frame+series`), and `correspondence` (`frame+frame`).
Constraint bounds ("can't go later than 7:30") are deliberately **not**
registered — LEXICON.md marks them unruled, and registering a kind whose
semantics nobody has decided would be inventing meaning.

**Placement is not a property an object has.** It is derived from the
connections the object participates in, and the start-time-plus-duration shape
is that derivation's zero-connection degenerate case. An object's plain
attachment relation IS an implicit start connection to the frame it is attached
to, so a document authored before connections existed is governed by them with
no record moving — `effectiveObjectStaples` exposes that same reading to an
authoring surface, which is why "Start time" is one row in the staple list and
not a control of its own. `src/store.js`'s `compactDocument` restates a legacy
flat staple as a connection on load; the conversion preserves the instant, the
point name, and a named point's offset exactly, and is idempotent.

A coordinate-less attachment relation is bare **membership** — "this object
belongs to this frame" — and membership alone has never placed anything. The
engine places such a relation only when the object's own connections resolve an
extent *in that same frame's coordinate space*; the frame identity check is
load-bearing, not defensive, because group attachments are coordinate-less too
and without it every anchored event would also draw itself on each of its groups.

**Correspondence between two frames is many-valued, partial, and non-monotonic.**
A `correspondence` staple joins two frame ends, each coordinate under its own
frame's law, and a set of them is a correspondence between those frames. The
substrate must not assume it is monotonic, total, or one-to-one: one point on
frame A may correspond to many disjoint points on frame B, and a stretch of A may
correspond to nothing at all. `frameCorrespondences` therefore **enumerates and
resolves nothing else** — it does not sort by position, collapse duplicates, pick
a nearest match, or report a range. Multiple correspondences project as multiple;
an empty result is a fact about the correspondence, never licence to interpolate
one from the neighbours. A frame may correspond to *itself* at two different
coordinates, which is a nonlinear line crossing its own path. This is distinct
from a `coordinate-mapping` relation and never a replacement for it: a mapping
declares a relationship between positions or intervals with explicit continuity
and direction, and may be read across its own span, while a correspondence staple
declares one bare touch point and claims nothing about the space beside it. The
four frame concepts must not collapse into each other, and this is the seam.

`src/staples.js` holds every derivation, DOM-free and pure over
`{document, engine}`:

1. **Anchoring.** `resolveObjectExtent` retires start-time-plus-duration as the
   only shape. Role precedence is fixed — `start` > `end` > `midpoint` >
   named. Zero anchors means the placement relation plus the object's own
   duration, bit-identical to a document authored before staples existed. One
   anchor plus a magnitude places the object, so an event can be *defined by
   where it stops* — and that same case is the seamless pair, where the
   downstream event's start IS the upstream event's end, so moving the upstream
   event moves this one through the connection. Chains compose, and the
   coordinate space propagates along them. A connection whose other end resolves
   back through the object it places is **reported, never iterated to a fixed
   point** (`cyclic`, plus the connection in `unresolved`): there is no instant to
   report and guessing one would place an object nobody positioned. Two anchors
   fully determine the extent and the magnitude is
   **derived**, with the object's own duration ignored rather than fought with;
   the extent is placed from the highest-precedence anchor, which is not always
   the earlier one (an `end`+`midpoint` pair starts at `2·mid − end`, earlier
   than either anchor). Three or more anchors let the two highest-precedence
   roles win, and every remaining anchor is reported in `overdetermined` and
   **never averaged in** — an average of contradictory anchors is an invented
   value, the same thing forbidden for coordinate mappings across a
   discontinuity.
2. **Series partitioning.** A series is one identity whose rules are segments
   partitioned by staples (`seriesSegments`). A partitioning staple **closes
   its segment inclusively and opens the next exclusively** — inclusive close
   is the shipped end-staple's behavior, and given that, exclusive open is the
   only choice that does not project the staple instant twice. The close is
   **precision-aware**: a partitioning staple closes at the end of the unit the
   author *named*, so a bare date closes at that day's last instant, a bare month
   at that month's, and a coordinate carrying clock levels closes exactly where it
   says. This is the same ruling `recurrence-end.js` states for "ends on a date"
   ("the last second of the date, not its midnight… the kind of off-by-one a user
   reads as a bug"), applied one layer up, and it is generic rather than
   kind-special: the line falls where `recurrenceUntilForCoordinate` already puts
   it — at or above the base unit names a **period**, below it names an
   **instant**. The end-of-unit boundary is computed by incrementing the authored
   level and carrying through each level's own declared child count, so the day
   after the 31st is the 1st and no calendar is hardcoded. The inclusive close and
   the following segment's exclusive open are the **same** instant, or the
   boundary day would project in both. A staple
   carrying `payload.rule` (a rule head: `{rrule, coordinate?, frame?,
   magnitude?, exdates?, exclude?}`) opens a following segment with its own
   base coordinate; a partitioning staple with no following rule terminates the
   series, which is exactly the degenerate one-staple case. COUNT counts
   *within* a segment. Every segment's facts carry the same pattern provenance,
   because a segmented series is still one identity.
3. **Fuzzy staples.** `spread: {before, after}` is per-staple uncertainty,
   asymmetric on purpose — "about 5ish" and a hard ceiling are different
   shapes, and a single ± would flatten the distinction. Spreads **add** when a
   magnitude is derived from two fuzzy anchors; independent uncertainties do
   not cancel. The data and the derivation are the contract; fuzzy *rendering*
   is a marker only, because the display language for uncertainty is not
   designed and inventing one would be meaning inferred.
4. **Occurrence phase.** A `phase` staple supplies the generator's base instant
   without rewriting the template, so removing it restores the original phase
   for free.
5. **Exclusions as live references.** `exclude: {frames: [...]}` drops
   occurrences colliding with events on the referenced frames, resolved **at
   projection time**, never baked into `exdates`. Matched by whole day, not by
   instant: a holiday is all-day, so a 6:15 meeting on that date must be
   skipped. Adding a holiday to the referenced calendar changes the series with
   no edit to the series.

The rule keeps saying what it says. A staple is never written into
`rrule.UNTIL`; `seriesEffectiveUntilDays` intersects the rule's own written
extent with the staple at read time, which is what makes removing a staple
restore the full projection for free. Every comparison is exact `Rational`
days through `coordinateDays` — never string equality, because ICS writes
month `"01"` where the generator writes `"1"`.

Staples cascade like overrides, and **both ends count**: `stapleTouchesAny` is
the one predicate every sweep asks, because a connection between two events is as
much the downstream event's record as the upstream one's, and a connection into a
frame must not outlive that frame. `removeStaplesForPatterns` and
`removeStaplesForObjects` (both `removeStaplesReferencing`) run inside the same
undoable transaction as the record they belong to, so undo restores a deleted
event, pattern or frame together with its staples and the journal carries every
removal. Every bundle helper in `src/ui/transactions.js` that can delete an event,
a pattern or a frame sweeps staples, and so do `calendar-sync.js`'s
`removeDanglingEventReferences` and `removeSourceOwnedRecords` — the reconciler
can delete records too, so it needs the same sweep rather than a loader-side
repair.

Overscale doctrine: `resolveObjectExtent` runs once per event during fact
indexing and follows connection chains, so the engine builds
`staplesByObject`/`staplesBySeries`/`staplesByFrame` in its own reindex — where
every other index lives — and `src/staples.js` reads them when handed the engine,
falling back to a document scan only for a law-free or direct-test caller.

Staples cross the ICS boundary like this:

- **Segment 0** exports as one VEVENT with UNTIL (or a truncated COUNT) derived
  at serialization from `seriesEffectiveUntilDays`. The staple is never written
  into the rule. The gate is `seriesSegments(...)[0].untilDays != null`, not
  `seriesIsSegmented` — a lone end-staple leaves exactly one segment, so the
  broader guard would silently stop truncating end-staples.
- **Following segments** export as sibling VEVENTs with a deterministic UID
  (`<baseUid>.chronolog-segment-<n>`, byte-identical on re-export) carrying
  `X-CHRONOLOG-SERIES`, `X-CHRONOLOG-SEGMENT-INDEX`, and
  `X-CHRONOLOG-INFLECTION` (the partitioning staple's own coordinate, which is
  authored separately from the following rule's first occurrence). Import
  rejoins them into one `inflection` staple on the base pattern — one identity,
  not a second series. A calendar that has never heard of ChronoLog still sees
  the real meetings, which is why the later segments are exported at all rather
  than hidden.
- **Anchors and spreads** are ChronoLog-native. The *derived* extent exports as
  ordinary DTSTART/DTEND so every other calendar shows correct times, and the
  intent rides as one `X-CHRONOLOG-ANCHOR` / optional `X-CHRONOLOG-SPREAD` pair
  per staple, correlated by an `ID` parameter. Magnitudes are exact `Rational`
  day-fraction text (`"1/24"`), never a float. ICS has no nested-level
  magnitudes, so a spread round-trips as an exact value collapsed to one level
  rather than its authored level shape — a stated limitation, not a rounding.
- An unanchored object exports byte-identically to before staples existed, and a
  foreign ICS with none of these properties invents no staples. Meaning is
  authored: an anchor role is never guessed from a title, category, or duration.
- On reimport, staples resolve against the reimporting document's **own** frame,
  because a fresh import always mints a new frame id; the exported `FRAME`
  parameter is informational only.

### ToDo state and containment

There is no resolution property and no lifecycle enum — "there is no
resolution, there is a state, and there is a staple" (LEXICON.md,
2026-08-25). The parts compose:

- **State is a frame.** Done — and any state the user authors — is a frame
  with `group` + `state` traits; an object in that state holds an ordinary
  membership relation to it. Controlling which state frames project does
  everything a filter would; no surface may grow a show/hide-by-state knob or
  a filterable status property.
- **The instant is a terminal staple.** Completion time is an `end`-kind
  staple — the object's `end` point abutting a frame coordinate. Backdating
  edits that coordinate; a membership with no staple is legal ("done, instant
  unstated"). The `end` kind is `anchors: false`: it never relocates the
  object. `stateAffiliations`/`doneAffiliation` in `src/object-kinds.js` are
  the one derivation; nothing else may read state.
- **Staples stay directional, not typed.** No "due" kind exists. A staple
  ahead of the view's now reads as due, behind it as past — the reading comes
  from the arrow of time at projection, never from a kind string. Reconciling
  the kind registry with this ruling is a flagged later pass.
- **Containment passes no judgment.** `{type:"contains", parent, child}`
  connects any objects; validation refuses only dangling ids and
  parent = child. Multi-parent and cyclic shapes are legal data; derivations
  are cycle-safe (`containsSummary` reports `cyclic`, never throws) and a
  parent's state is never inferred from its children. Rank is not stored. A
  list or project is a container object, never a group frame.
- **Apparent magnitude, not keep-range.** `src/falloff.js` is pure:
  `objectHome` (the day range an object's staples span), `distanceFromHome`,
  `apparentMagnitude(base, distance, {halfDistanceDays})` = base·h/(h+|d|).
  Lenses fade unresolved todos by distance from home; done/closed objects
  never fade. Data never changes — falloff is projection only.
- **Migration.** `migrateCompletedRelations` in `compactDocument` restates
  every legacy `role:"completed"` attachment as membership + end staple,
  idempotently, minting the Done frame only when legacy records exist. ICS
  VTODO COMPLETED reads and writes through the derivation; new ICS todo
  mapping (DUE, STATUS, PRIORITY) is held until the model settles.

### Display weight

A frame's weight handling is a **formula** in `chronolog-formula/1`, evaluated
with the incoming weight bound to `w` — "if I can describe with basic algebra
how membership should alter a member, then I should be able to do that". A
plain number `n` is sugar for `w * n`, which is what migrates every shipped
`display.weight` number with no record rewriting and no change in what it
means. An absent, unparseable, or non-finite-result formula contributes
nothing and acts as identity: a broken knob must never silently change what
renders.

Because mixed `+` and `×` do not commute, the fold order is part of the
contract. Contributing frames apply in this order, folded left from the base
weight: ascending `display.weightOrder` (absent = 0), then **group size
descending** so the narrowest, most specific affiliation has the last word,
then frame id as the final deterministic tie-break. Group size is already the
color cascade's ordering signal, which is why it is reused here rather than a
new one being invented.

`factImportanceWeight` composes the weight and `factImportance` thresholds it;
`explainFactWeight` returns the whole derivation (base, one step per
contributing frame, final, verdict) so the editor can *show* how a weight was
reached. Promotion thresholds are **per lens**, visible and editable on each
lens's row in the lens workspace, defaulting to the 2 and 4 that were
previously hardcoded so an untouched document renders identically.
`IMPORTANCE_WEIGHT_THRESHOLD` in `src/visual-language.js` stays the one place
those numbers live.

Newly created **groups** default to a `w * 1.5` boost so an event crossing more
frames is more prominent by default. Calendars do not, and imported calendar
frames do not: every event has a calendar, so a uniform calendar boost promotes
nothing relative to anything while pushing everything toward the landmark
threshold. Existing records are never migrated.

### Visual grammar

One fixed sigil vocabulary (point/diamond/repeat/ring/square/split-diamond/
span — see `src/visual-language.js`) applies across all nine lenses
(Intimate, Tactical, Strategic, Wall, Lines, Spiral, Radial, List, Board);
a lens may
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
