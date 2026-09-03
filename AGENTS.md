# Agent notes

ChronoLog is a local-first timeline instrument, pre-alpha and exploratory:
timelines are first-class objects, events staple onto them (sometimes onto
more than one), and the lenses project one shared `chronolog/1` document (the
lens count is data in the catalog, never a fact a test may assert).
Read [LEXICON.md](LEXICON.md) for vocabulary and the
founding ideas before naming anything new — it is the owner's own voice and
brainstorm space. Meaning is authored by the user: color and semantics come
from the user's own grouping and frame choices, never inferred (not from
UID hashes, not from imported categories). Keep the lexicon's vocabulary and
character when you touch adjacent code or docs.

## Architecture map

### `app/lib/`

The Flutter program (the shipping build since 2026-08-28). `core/` and `store/`
are the proven model; everything else is the surface. Nothing under `core/` may
import Flutter. There are no Flutter plugins and there never will be: a Windows
plugin build needs symlink support this machine's policy forbids, so host
capabilities go through `dart:ffi` (`host/`).

- `main.dart` — the entry point and nothing else. What the program IS lives in
  `app.dart`, where every seam is a parameter and a spec stands the whole thing
  up in memory.
- `app.dart` — the assembly. `Workspace.open` takes the filesystem, the clock,
  the data root and the file picker, and returns store, editor, settings,
  session files, stage, chrome and card factory wired together. First-run
  honesty lives here: an empty root establishes an empty document, and a view
  tile projects the shipped wall-time frame rather than a seeded calendar. A
  card is an edit session, so a layout naming one from a previous run drops the
  leaf instead of leaving a hole.

#### `core/` — the model

- `coordinate_law.dart`, `eras.dart`, `era_chain.dart`, `calendar_structure.dart`,
  `coordinate_entry.dart` — the coordinate-arithmetic engine, the era table, the
  authoring side of a declaration, and the variable-precision entry field's
  substrate. Depth is precision, never uncertainty. See "Coordinate law".
- `records.dart`, `document.dart`, `ops.dart`, `validate.dart` — the
  `chronolog/1` document shape, record-level ops as the change representation,
  and the load-time validator. Changing a record shape means regenerating the
  `*.freezed.dart` beside them (`dart run build_runner build`); those are
  committed build products, and JSON codegen is deliberately absent because
  every codec here is hand-written to keep unknown fields and never throw. `createEmptyWorkspaceDocument` is what a first
  run establishes: two structural frames and nothing else.
- `projection.dart` — `ProjectionEngine`: fact queries, occurrence generation,
  the boolean-algebra `Projection` over connections, the weight chain's ring
  input (`modifyingFrames`), the whole connection graph (`connectionsOf`),
  cross-frame correspondence (`frameProjection` / `coordinateSpaceOf`), and the
  ONE reader for a group display property (`authoredHandling`) that zone fill,
  sigil and falloff half-distance all go through. See "Frames are groups".
- `indexes.dart`, `staples.dart`, `frame_projection.dart` — the index layer, the
  staple substrate (a staple says n points are one point; nothing else may
  hand-read one), and the ruling that cross-frame projection exists only through
  staples. See "Staples".
- `weight.dart`, `falloff.dart`, `strategic_density.dart` — `composeWeight` in
  the blessed order, apparent-magnitude falloff, and the per-day density budget.
  See "Display weight".
- `math.dart` — THE ONE MATH. `parse`/`evaluate`/`Env`/`MathRefusal`; every
  setting, weight formula, placement predicate and span formula is an
  expression in it.
- `exact.dart` — exact rational/BigInt arithmetic and `nowDays()`. No `DateTime`
  arithmetic in domain code.
- `object_kinds.dart`, `todo_shape.dart`, `series_heal.dart`,
  `recurrence_end.dart`, `rrule.dart`, `event_cycle.dart`,
  `frame_selection.dart` — object trait bundles, the ToDo derivation, the series
  convergence invariant, how an RRULE stops, recurrence expansion,
  observed-boundary cycles, and a plain frame selection.
- `ics.dart`, `ics_text.dart`, `ics_values.dart` — the ruled lossy ICS boundary.

#### `store/` — truth on disk

- `data_dir.dart` — where the data lives, and where it never lives: the app's
  own directory or an explicit path. No branch here can name a profile
  directory, and that absence IS the ruling. ONE exception, and it is not a
  profile directory: an executable under a `build` directory resolves to the
  parent of that build tree, because `flutter clean` deletes what `beside the
  exe` means there (ISSUES 9.2, hazard found live).
- `journal.dart`, `document_store.dart` — snapshot plus append-only journal,
  the 350ms autosave debounce, refcounted deferral, in-flight coalescing that
  carries force forward, and a failed write that hands the ops back.
- `plaintext_file.dart` — a named sidecar the app reads, writes atomically and
  polls for external edits, so hand-editing a file and using the GUI are one
  authoring path. The file is always a valid second path and never the only
  one: no feature may be reachable only by editing a file.
- `seams.dart` — the outside world, injected: every file call and the clock.

#### `edit/` — the one write door

- `editor.dart` — `Editor` over the store and the engine. The ops list IS the
  undo entry; undo and redo are FORWARD journal entries. Every door is one
  `transaction`, so cascades and the convergence invariant are laws rather than
  code paths. Notifications raised during a build are held to the end of the
  frame.
- `reach.dart`, `cascades.dart` — the reachable-record closure, settling, and
  the cascade a removal drags with it (including `duplicateFrame`'s deep copy
  with staple-end remap).
- `drafts.dart` — edit-session drafts keyed by object id; N cards hold N drafts;
  discard is its own undo entry.
- `gestures.dart` — the write side of pointer verbs: `createAt`, `moveFact`
  (with materialization and snap-back), `toggleState`, `setContains`, and their
  composable `withState`/`withContains` document forms, so two acts that are one
  act are one undo entry.
- `capture.dart`, `capture_grammar.dart` — quick-capture; a fuzzy `#group` miss
  ASKS before anything is committed.
- `weight_explain.dart` — the weight derivation, whole, for the card's explainer.

#### `session/` — what the surface is looking at

- `settings.dart` — every tunable as a named setting whose shipped default is an
  expression in the one math, plus text settings (key chords, theme name) which
  are deliberately not arithmetic. A refused expression keeps the last good
  value and says why. `exclusive` families (`keys.`, `pointer.`) admit no two
  keys saying the same thing; `resetUnder` puts a whole page back at once.
- `lens_catalog.dart` — `LensSpec`/`ControlSpec` and the shipped lenses as DATA.
  A lens declares its controls; the context bar renders the declaration and
  knows no lens by name.
- `view_state.dart` — per-view-tile lens, projection, focus and per-lens map,
  and the `ViewBook` that `chronolog.view` holds.
- `files.dart` — the plaintext sidecars (`chronolog.layout`, `.view`,
  `.settings`, `themes/*.json`), read once and then polled, written on a
  debounce, flushed on demand.

#### `stage/` — everything is a tile

- `layout_tree.dart` — the tiling tree: `split`/`tabs`/`dwindle` containers and
  tile leaves, JSON both ways, insert/close/move/split/tab, ratio snapping,
  directional focus.
- `placement_rules.dart` — where a new tile lands, as an ordered rule list
  matched in the one math. A full tab stack overflows BESIDE itself.
- `tile.dart` — `TileSpec` and `Stage`. Type is content; no tile kind has a
  special path, and closing asks nothing.
- `stage_widget.dart` — the tree as widgets: one divider service, one tab strip,
  the permanent hairline grip, drag-to-split and drag-to-tab.

#### `chrome/` — the three bars

- `controls.dart` — `Chrome` (what the chrome is looking at) and the designed
  control vocabulary every bar, menu and card is made of. No raw number field,
  no comma string, no bare record id. `fieldChrome` is the ONE decoration every
  text entry draws through, so a field looks like a field everywhere and a new
  field class cannot be born borderless.
- `document_bar.dart`, `view_bar.dart`, `context_bar.dart` — what the document
  is and the actions on the whole of it; which lens the focused view tile is;
  that lens's own declared controls. An unclaimed action is not rendered.
- `projection_control.dart` — which frames the focused view looks through, over
  the same row and the same selection the frames browser authors.
- `menus.dart` — the one menu class every drop and every right-click uses.
- `keyboard.dart` — one keyboard map; every binding is a setting. Two bindings
  naming one chord bind NEITHER: the conflict is a refusal in prose beside both
  rows, never a silent last-wins.
- `shell.dart` — `chronologSettings()` (EVERY area's defaults, composed — a key
  in no map is a refusal naming it), the shipped stage preset, and
  `ChronoSurface`.

#### `lens/` — the painting substrate and the lenses

- `tunables.dart`, `theme.dart`, `lens_painter.dart` — the settings seam; the
  8-field palette with three derived tones and two font roles; `LensScene` and
  `LensPainter`, where `project` and `unproject` sit side by side so the eye and
  the drop cannot disagree.
- `law_context.dart` — one law read per paint. There is no 24 and no 1440 in
  this layer.
- `facts.dart`, `capacity.dart`, `lanes.dart`, `zones.dart`, `now.dart` — the
  fact window with exact per-day segmentation; the ONE magnitude-driven capacity
  budget; one lane packer keyed on temporal overlap; the zone grammar as a group
  property; one now derivation, gated on `mapsToClock`.
- `marks.dart`, `color.dart`, `display_weight.dart` — the sigil vocabulary with
  its paint folded in; the authored 4-step colour cascade (no colour is ever
  inferred from a trait); the composed display weight with per-lens promotion
  and per-frame falloff. See "Visual grammar".
- `gestures.dart`, `view_tile.dart`, `context_menu.dart`, `drag_ghost.dart` —
  THE one pointer table, the view tile that hosts a lens and owns it, the app's
  own right-click surface, and the drag ghost that names the live coordinate.
- `minimap/` — magnitude accumulation with hysteresis, the boundary label ladder,
  the particle-field painter, and the tile that scrubs the focused view.
- `painters/` — `intimate`, `tactical`, `strategic`, `wall` over one parameterised
  `month_grid`; `lines`, `spiral`, `radial`.
- `radial/`, `lines/` — cycle resolution and polar geometry; Lines' warp plan
  (N staples = warp, and Lines draws it).
- `todo/`, `tree/` — the two roster lenses over one row and one capture bar, and
  the connection graph, which renders a GRAPH and never a strict tree.

#### `cards/` — the editors

- `card_factory.dart` — the one door onto every card. A card IS a tile, idempotent
  by id; bodies are registered per class and an unregistered class renders a
  stated gap. `CardHost` carries the factory above every tile.
- `card_chrome.dart` — the shared card frame: header, short primary path, ONE
  fold, footer. Plus the shared instruments (field, chips, links, compose,
  colour, menu) so no site spells a control's shape — and `Refusal`, the one
  interactive refusal every surface shows: click selects, double-click copies
  the text with what it is about, right-click offers Copy / Copy all / Dismiss
  for this session, hover shows the whole of a truncated line.
- `coordinate_field.dart`, `staple_editor.dart`, `connection_picker.dart`,
  `state_control.dart`, `weight_explainer.dart`, `object_card.dart` — the
  variable-precision coordinate field; THE placement interface, where no staple
  is special and both ends of every connection are navigable; windowed typeahead
  that never enumerates; state as a chooser over state frames; the weight
  derivation shown ring by ring; the object card itself.
- `frame_card.dart`, `law_editor.dart`, `boundary_series_editor.dart`,
  `frames_browser.dart` — a frame's identity and its GROUP display handling,
  with basis guidance; the calendar structure as the coordinate law; observed
  boundary series; the one frames surface.
- `document_card.dart`, `settings_card.dart`, `theme_card.dart` — the document,
  its ICS boundary and its layout presets; every tunable as a designed control;
  the palette, with Apply and Save as separate verbs.

#### `host/`

- `file_picker.dart` — the host's file dialog with NO PLUGIN and no package:
  `dart:ffi` into `comdlg32` on Windows, a stated refusal elsewhere.

#### `app/tool/` and `app/test/`

`tool/` holds `screenshot.ps1`, which captures the running window to a PNG.
Nothing under `lib/` imports anything there and nothing there ships in a build.
`test/` is the spec: generative properties at `specSeed = 20260827` over the
seeded record graphs in `test/core/corpus.dart`, documents authored through the
builders in `test/helpers/` (`Scene` for a lens or projection spec, `World` for
cross-law staples and era chains — both seeded from
`createEmptyWorkspaceDocument`, so a test and a first run start from identical
bytes), and widget tests over in-memory fakes (`test/store/harness.dart`), never
real file I/O inside `testWidgets`.

`core/` and `store/` were proven against the reference build at the 2026-08-27
boundary; the 2026-08-31 record melt then moved the model past what that build
expressed, and the polar geometry that comparison still covered is carried by
affirmative properties in `test/lens/radial_geometry_test.dart`.

### `fixtures/`

Fixtures are acceptance anchors, not scratch data:

- `time-travel-taxonomy.chronolog.json` is the structural counterpart to
  `local/GUI_Mockup/bak.png` — a deliberately small graph that makes
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
- `irregular-event-cycle.json` is the observed-boundary acceptance fixture: a
  lunar-like series whose every gap is a different exact observation, so no mean
  synodic month can stand in for any one of them and an authored interval cannot
  be mistaken for a computed one.

`app/test/core/fixtures_test.dart` reads the first two and
`app/test/core/event_cycle_test.dart` the third. Nothing else in the suite reads
a fixture: tests must never depend on
personal or local data, so a spec authors its own document through the
`app/test/helpers/` builders or the seeded graphs in `app/test/core/corpus.dart`,
and an untracked machine-specific file is never something the suite needs.

The design references in `local/GUI_Mockup/` (untracked, not in the repo) are live — never delete them.

## Engineering contracts

### Persistence

Journal + snapshot. `chronolog.chronolog` is a snapshot loaded at boot;
`chronolog.journal` is JSONL, one line per committed edit:
`{seq, ts, label, ops:[{op:"put"|"del", map, id, value?}]}`. Ops are
record-level and idempotent across all seven maps (`meta`/`foreign` keyed
by top-level property), so a journal folds into a snapshot with zero domain
knowledge. `applyOps` in `app/lib/core/ops.dart` is THE one, and it is also the
gate: `journal.dart` replays an entry through it before the
entry reaches the file, so an op this build cannot replay is refused rather than
persisted as a poison line.

**Saves are updates, not overwrites.** Ordinary editing never rewrites the
document, it appends the ops that changed it. The whole document is written on
exactly three occasions — establishing a file that does not exist yet,
compaction, and the owner deliberately replacing the document, which is also how
a move to a chosen location writes its first snapshot — and none of them is
autosave. Compaction folds the journal back into the snapshot and empties it;
`.chronolog-journal-state.json` carries the sequence number across it. Both
sources are authoritative in different crash windows — the sidecar survives a
truncated journal and the journal survives a lost sidecar — so a torn final line
is discarded into the load's report, never fatal.

**Single writer.** One master isolate owns the document and the journal, so
there is no sequence CAS, no conflict type, no rebase loop and no multi-window
merge. `SaveState` is five states (`loading`, `clean`, `dirty`, `saving`,
`error`) and the words a person reads are the chrome's to write.

`document_store.dart` is the autosave flow: a 350 ms debounce batches a burst of
edits into one write, one entry per commit, so the journal keeps every edit's own
label. Three behaviours there are load-bearing. Refcounted deferral — N open
drafts hold autosave off exactly N times, and the count cannot be driven below
zero, so a `finally` that runs twice is harmless and one that runs once can never
leave autosave stuck off. In-flight coalescing that carries force forward — if
any caller piled up behind one in-flight save asked for a forced save, the
follow-up carries that force rather than quietly downgrading it. And a failed
write hands the ops back, so a failure costs a retry and never an edit.

**A load reports.** Migrations are dead by ruling: nothing on the load path
rewrites the file to suit this build. Loading is snapshot plus replay, and
`validateDocument`'s findings, the refusals a replay met and a torn tail all come
back as reports the owner is shown — what a load owes the owner is the findings,
not a document that declines to open.

Referential cascades are the edit's job, not the loader's. An override names the
occurrence it acts on by a virtual id (`patternId/encodedKey`), so an override
belongs to its pattern the way a relation belongs to an event: deleting a pattern
must delete its overrides in the same undoable transaction. `overridePatternId`
in `app/lib/core/document.dart` is the single derivation every consumer shares.

**One reference graph, asked in one direction.** `app/lib/edit/reach.dart` asks
it — which records name this id (`namedBy`) — and that is the only place the
graph is declared for edits, so no caller writes a sweep of its own.
`unsupported` collects the records that are pure pointer and say nothing once
what they name is gone (`relations`, `overrides`, `patterns`); events and frames
are CONTENT and are never removed by a cascade, because deleting a magnitude
frame must not delete the objects measured in it. `dangling` refuses outright an
edit that would leave a reference pointing at nothing. `settle` in
`app/lib/edit/cascades.dart` runs both plus the series convergence heal on every
transaction, so an edit and everything that could not survive it are one
document, one undo entry and one journal entry. Undo needs no captured bundle at
all: an immutable document's identity diff reports the forward ops and the same
diff read backwards reports the inverse, which is why undo and redo are FORWARD
entries — a journal is a history and history does not rewind.

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
3. A **correspondence** between two frames is authored as staples and read
   through the one math — never an invented interpolation across a gap.
   `coordinate-mapping`, `shared-segment`, `termination` and `displacement`
   records stay perfectly legal data, round-trip untouched, and are checked
   against no hardcoded shape: time travel is a native first-class capability,
   re-founded on the one math — author the function and the one projector
   projects it — and hardcoding four shapes would preclude the rest.
4. A **lens** projects a leading frame and optional companions; selecting
   or displaying a frame never creates a correspondence.

Event-defined periods (`period.kind: "event-defined"`) resolve exactly
against their authored, strictly ordered boundary series — no averaging and
no extrapolation past the series. Approximate fixed periods must carry
`provenance.kind: "approximation"` and are never presented as observed or
computed.

### Coordinate law

A frame's `coordinate` declaration is the **executed law**, not documentation of
one. `app/lib/core/coordinate_law.dart` is the single coordinate-arithmetic
engine: every unit relationship in the program — how many hours are in a day,
how long a month is, what a duration magnitude is worth, how a nested coordinate
becomes a day ordinal — is computed from the governing frame's own declared
ladder. Nothing else may carry a unit relationship as a literal. Setting
hours-per-day to 23 on a frame changes engine occurrence math, projection
layout, minimap strides, duration magnitudes, drag snapping, and the editor's
own fields, because all of them ask the same object.

A declaration is a list of **levels** plus optional **cycles**:

```
coordinate: {
  kind: "gregorian" | "nested",
  levels: [ { name, within?, radix? | transition?, names? } ],
  cycles: [ { name, radix, offset?, names? } ],
  fixed?: { ... }          // calendar_structure.dart's regular-hierarchy builder
}
```

**Authored depth is data, and it survives.** A coordinate whose `levels` stop
early is a partial coordinate — the author said `1973` and nothing finer.
`toDays` supplies the missing levels from the family's defaults, and `fromDays`
returns every level filled in, at which point the result is indistinguishable
from an authored January 1st midnight: the depth was supplied by the law, not by
the author. So depth is never inferred back out of a resolved instant. It is read
from the **source** coordinate — `authoredDepth` in
`app/lib/core/coordinate_entry.dart`, injected into the engine as `precisionOf`
so a projection asks without importing the entry layer — and travels on the fact
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
first-class in `app/lib/core/eras.dart`, not a rendering trick over negative
numbers.

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
either.** `CoordinateLaws.display` falls back to the registered standard for that
reason; `daysOrNull` is the query path's counterpart, returning null so a caller
skips the record and collects the reason instead of aborting. `lawError` (per
frame) and `valueError` (per coordinate) are how validation asks — the
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
| positions CORRESPOND | a staple path (`app/lib/core/frame_projection.dart`) | one frame may be drawn on the other's axis |

An authored `origin` is **chain-internal**: it anchors a calendar's own eras
relative to each other so the chain resolves exact internal ordinals, and it
makes no claim on any shared axis. With no staple path between two frames,
neither projects onto the other — an overlay renders **nothing** of the far frame
and reports why. It must never place that frame's events at origin-derived day
ordinals; dropping Tamriel's Third Era beside 1970 because both count from an
internal zero is a correspondence nobody authored, which is the class of error
this program refuses everywhere else.

`FrameProjection.framesProject(from, onto)` answers it: same frame, same coordinate
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
`isLeapYear` in `app/lib/core/exact.dart` are the registered Gregorian family's
whole-day kernel. **Coordinate conversion reaches them only through the family**
— never as a bypass. The remaining direct importers are the places that still
walk Gregorian month/year *boundaries* rather than convert coordinates (the
minimap's label strides in `app/lib/lens/minimap/labels.dart` and Radial's month
windows in `app/lib/lens/radial/cycles.dart`) plus RFC 5545's own recurrence
machinery in `app/lib/core/rrule.dart`; each carries a comment saying so, and
the first group is what ROADMAP #6's positional-conversion stage removes.
Gregorian is the first entry, not a privileged branch: adding Hebrew, Islamic,
Indian or any other CLDR calendar is one `registerCalendarFamily` call plus its
transitions, and nothing else in the program changes.

**An unresolvable declaration is an error surfaced to the author.** A transition
string nothing implements, a radix that is not a positive whole number, a level
nesting inside a level that does not exist, a ladder no family can execute — each
throws with the frame and the offending name in the message. `lawError`
is how a surface asks, and `app/lib/cards/law_editor.dart` shows a refused
declaration in place rather than letting it fail silently at render time. A law
that quietly means something other than what is written is unauditable, and
silence is what let a dead ladder look alive.

**How a call site asks for arithmetic.**

`CoordinateLaws` in `app/lib/core/coordinate_law.dart` is the seam every call
site goes through.

- `CoordinateLaws.of(document, frameId)` — the law governing that frame, memoized
  per document. Resolution follows `coordinateDefinition`, then the `gregorian`
  kind/trait, then `basis`: a calendar whose basis is Wall Time inherits Wall
  Time's law, including a radix edited there, without restating the ladder.
- `CoordinateLaws.display(document, frameId)` — the **primary** frame's law (see
  the frame model: the explicit primary marker owns axis, labels, and coordinate
  law). `LawContext` in `app/lib/lens/law_context.dart` holds it as a value for
  one paint and every lens helper reads it from there rather than re-deriving
  per helper.
- `law.unitDays(name)` for an exact unit length, `null` when it varies;
  `law.meanUnitDays(name)` for the exact mean, defined for every level; and ONE
  ratio accessor, `law.unitsPer(name, [per])`, for "how many minutes in a day"
  or in an hour. There are no named per-unit wrappers: one uniform policy
  resolves through the declaration and falls back to the registered standard
  table only for a level this calendar never authored, and it differs from a
  wrapper in exactly the place that matters — a law whose base unit has no
  constant length answers with that unit's exact mean, where a retired
  `daysPerWeek` substituted the atom and reported seconds per week as days per
  week. `law.meanMonthDays()` is the one that stays named, because a month is
  the level that has no constant length to ask for. A lens reads these once per
  paint through `LawContext`, never per helper.
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
identity on every lookup, and by the explicit `CoordinateLaws.invalidate` the
edit path calls on every committed change, because identity alone misses an
in-place mutation and the explicit
call alone misses an undo that swaps whole records. Both together are what make
an applied ladder edit live on the next render.

**Boundaries that deliberately stay civil.** Two things speak the outside
world's standard civil Gregorian and convert once, at the edge:
`nowDays`'s host clock read and RFC 5545's own wire units and RRULE evaluation.
Each carries a comment saying so.
`civilCoordinateToDays`/`daysToCivilCoordinate` are the named aliases for the
registered-standard conversion, and the name is the assertion. `formatCivil` is
display and not arithmetic — nothing in the model may read a value back out of
that string.

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

**A staple is an edge, not an attribute.** It says n points are one point, and
the two-ended shape below is that at n = 2:
`{type: "staple", kind, ends: [endA, endB], spread?, payload?}`. An end names one
thing plus where on that thing the touch point is, and is exactly one of:

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

`kind` is validated against `stapleKinds` in `app/lib/core/staples.dart`, not
hardcoded. Adding a kind is one registry entry plus its interpretation. This is
deliberately stricter than frame traits, which stay valid data when unfamiliar:
a trait is a capability claim a renderer may ignore harmlessly, while a kind
*selects a derivation*, and a kind nothing honours would silently move things on
screen — or silently fail to. What a kind declares is what its own derivation
needs and nothing more: `partitions` (it cuts a series' rules), `carriesRule`
(its segment may open with a rule of its own), and `anchors` (it may place an
extent). There is **no scope gate** — nothing decides which things a connection
may join, because a staple says n points are one point and that is true of any
two things that can name a point. Registered kinds are `end` and `inflection`
(both partition; only `inflection` may carry a following rule), `phase`,
`anchor` (the only kind that anchors, which is one of the four facts a placement needs), `correspondence`, and `succession`, which
is a LABEL and not a case: an era boundary is a plain point staple, so nothing
selects a derivation from the word and an existing record spelled `succession`
keeps its meaning and round-trips byte for byte. Constraint bounds ("can't go
later than 7:30") are deliberately **not** registered — LEXICON.md marks them
unruled, and registering a kind whose semantics nobody has decided would be
inventing meaning.

**Placement is not a property an object has.** It is derived from the
connections the object participates in, and the start-time-plus-duration shape
is that derivation's zero-connection degenerate case. An object's plain
attachment relation IS an implicit start connection to the frame it is attached
to, so a document authored before connections existed is governed by them with
no record moving — `effectiveObjectStaples` exposes that same reading to an
authoring surface, which is why "Start time" is one row in the staple list and
not a control of its own.

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

`Staples` in `app/lib/core/staples.dart` holds every derivation, pure over the
document and an optional engine:

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
   says. This is the same ruling `recurrence_end.dart` states for "ends on a date"
   ("the last second of the date, not its midnight… the kind of off-by-one a user
   reads as a bug"), applied one layer up, and it is generic rather than
   kind-special: the line falls where `recurrenceUntilForCoordinate`
   (`app/lib/core/recurrence_end.dart`) already puts
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
`rrule.UNTIL`; a segment carries its `untilDays` and the projector and the
serializer each intersect it with the rule's own written extent at read time,
which is what makes removing a staple restore the full projection for free.
Every comparison is exact `Rational` days through `coordinateDays` — never
string equality, because ICS writes month `"01"` where the generator writes
`"1"`.

Staples cascade like overrides, and **both ends count**: a connection between two
events is as much the downstream event's record as the upstream one's, and a
connection into a frame must not outlive that frame. No sweep is written per
caller. `namedBy` in `app/lib/edit/reach.dart` reports both ends as ids this
record names, so `unsupported` carries a staple out with whichever end died, and
`settle` runs inside the same transaction as the record it belongs to — undo
restores a deleted event, pattern or frame together with its staples, and the
journal carries every removal.

Overscale doctrine: `resolveObjectExtent` runs once per event during fact
indexing and follows connection chains, so the engine builds
one id-keyed `Indexes.staplesOf` in its own reindex — where every other index
lives — and `Staples` reads it when handed the engine, falling back to a document
scan only for a law-free or direct-test caller.

Staples cross the ICS boundary like this:

- **Segment 0** exports as one VEVENT with UNTIL (or a truncated COUNT) derived
  at serialization from the segment's own `untilDays`. The staple is never
  written into the rule. The gate is `seriesSegments(...)[0].untilDays != null`, not
  `seriesIsSegmented` — a lone end-staple leaves exactly one segment, so the
  broader guard would silently stop truncating end-staples.
- **Following segments** export as plain sibling VEVENTs with correct times.
  Any calendar sees the real meetings; the series IDENTITY is not emitted, so a
  reimport reads them as separate events rather than rejoining them.
- **Anchors and spreads have no ICS carrier at all** and are not emitted. The
  *derived* extent still rides as ordinary DTSTART/DTEND, so every other
  calendar shows correct times.
- A fresh import of an exported file therefore gets correct times and ZERO
  staples. Meaning is authored: a foreign calendar invents no connections, and
  an anchor role is never guessed from a title, category, or duration.
- **There is no X-CHRONOLOG dialect in either direction.** A foreign `X-`
  property is somebody else's dialect and rides through verbatim, which is the
  opposite of emitting our own. Round-trip fidelity is residual retention, not
  re-derivation: every property the export regenerates from the model is
  stripped on the way in, and everything else is kept as that event's
  irreducible delta, once per source in a shared bucket, with each event
  carrying only `{source, key}`.
- **VTODO is not mapped** — that mapping is ruled on hold, so a VTODO component
  is retained verbatim exactly as VJOURNAL, VFREEBUSY, VALARM and VTIMEZONE
  are: it survives a round trip untouched and is never turned into an object.

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
  object. `ObjectFacts.stateAffiliations`/`doneAffiliation` in
  `app/lib/core/object_kinds.dart` are the one derivation; nothing else may
  read state.
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
- **Apparent magnitude, not keep-range.** `app/lib/core/falloff.dart` is pure:
  `objectHome` (the day range an object's resolvable staples span, null when
  nothing resolves), `distanceFromHome` (zero anywhere inside that range), and
  `apparentMagnitude(base, distance, {halfDistance})` = base·h/(h+|d|).
  Lenses fade unresolved todos by distance from home; done/closed objects
  never fade. Data never changes — falloff is projection only.
- **No migration.** Nothing rewrites a record to suit this build. ICS VTODO
  COMPLETED reads and writes through the derivation; new ICS todo mapping (DUE,
  STATUS, PRIORITY) is held until the model settles.

### Display weight

A frame's weight handling is a **formula** in the one math
(`app/lib/core/math.dart`), evaluated with the incoming weight bound to `w` —
"if I can describe with basic algebra how membership should alter a member, then
I should be able to do that". A
plain number `n` is sugar for `w * n`, which is what migrates every shipped
`display.weight` number with no record rewriting and no change in what it
means. An absent, unparseable, or non-finite-result formula contributes
nothing and acts as identity: a broken knob must never silently change what
renders.

Because mixed `+` and `×` do not commute, the fold order is part of the
contract. `composeWeight` in `app/lib/core/weight.dart` owns it — THE BLESSED
CHAIN, nesting inside out: the object's own authored math; then the connected
modifying frames by **increasing graph distance**, nearest first, ties at equal
distance broken on stable id; then the projecting frame or expression **last**
among frames, because uniform monotone math applied last cannot reorder the view,
which is exactly what "matters least" requires; then apparent-magnitude falloff
as the projector's own closing step, multiplicatively. Weight is
projection-relative by design: the same object weighs differently seen from
different projectors, and that is the point. No graph is walked there —
`composeWeight` takes rings that already know their distance and owns the sort,
the fold and the closing step, so a caller supplies distances and never order.

`factDisplayWeight` in `app/lib/lens/display_weight.dart` composes the weight for
a fact and `promotionOf` thresholds it into `standard`/`important`/`landmark`;
`Editor.explainWeight` (`app/lib/edit/weight_explain.dart`) returns the whole
derivation, one row per ring, so the card can *show* how a weight was reached.
Promotion thresholds are **settings, per lens** — `<lens>.importantAt` and
`<lens>.landmarkAt`, falling back to `weight.importantAt` and `weight.landmarkAt`
— so a lens that wants a busier landmark bar says so in the settings file instead
of in code.

`defaultWeightForNewFrame` gives newly created **group** and **importance**
frames a `w * 1.5` boost so an object crossing more frames reads as more
prominent. Calendars do not, and imported calendar frames do not: every event has
a calendar, so a uniform calendar boost promotes nothing relative to anything
while pushing everything toward the landmark threshold. It is a blank authoring
form's initial value only — never applied to, or migrated onto, a frame that
already exists.

### Visual grammar

One fixed sigil vocabulary — `point`, `milestone`, `repeat`, `task`, `note`,
`terminator`, `celestial`, `span`, in `sigilGlyphs` in `app/lib/lens/marks.dart`,
plus `overflowSigil` for a budget that ran out, which is a LOWER BOUND drawn as
its own mark rather than a truncated list — applies across every lens in the
catalog. No lens carries an integer cap on what it may draw: capacity is one
derived budget of screen space and apparent magnitude, and what the budget
cannot seat is said by the overflow sigil rather than silently dropped. A lens may omit a mark it cannot render at scale, but must not repurpose
one to mean something else. The sigil an object shows is derived from what its
author actually wrote (`sigilFor`): an authored `display.sigil` on the object or
its frame names one outright, and otherwise a mark covering a whole day under
this law is a span, a succession end is a terminator, the authored kind gives
task and note, a generated occurrence repeats, a promoted weight is a milestone,
and everything else is a point.

Color identifies an authored frame/group/context; it is never the sole carrier
of an event's structural role — that is always paired with sigil shape, so a
theme or grayscale display does not erase meaning.
Themes are an 8-field palette, all eight authored (`themeFields` in
`app/lib/lens/theme.dart`: ground, surface, paper, ink, muted, primary,
secondary, accent). The three surfaces are ELEVATION, not decoration — `ground`
is the desk the stage sits on and shows between tiles, `surface` is what chrome
is made of, `paper` is the sheet a lens or a card is drawn on. Three tones derive
from them — the hairline, the tone secondary text reads in, and the faintest —
each carried from paper toward ink until it holds its own CONTRAST RATIO, not a
fixed mix, because a fixed mix on a light ground and the same mix on a dark one
are not the same legibility.

Object color inheritance is a 4-step cascade, implemented once in `ColorCascade`
in `app/lib/lens/color.dart` — lens renderers must not choose colors
independently:

1. An explicit color on the object overrides everything else.
2. A group color overrides temporal-frame color. When an object belongs to
   several groups, a group the projection explicitly shows wins; otherwise the
   group with the most members wins, then authored membership order, then frame
   id — so the answer is total and identical across reload.
3. The active temporal frame wins when the object belongs to several
   frames, then the frame supplying the rendered fact, then its other
   authored frame attachments.
4. The theme's neutral ink applies when none of the above has a color: an
   unauthored record is never given an inferred one.

### Calendar sync

The ICS boundary is file import and file export, and nothing else: no feed
client, no subscription service, no poller. `importIcs` is one undoable document
change and mints its own source, so a second import of the same calendar adds a
second source rather than rewriting the first; what it raises against what is
already there is staple **suggestions**, never a reference it rewrites on the
author's behalf. Foreign residuals ride under `foreign.ics.sources` so a
round-trip preserves what this program does not model. Write-back is disabled —
see ROADMAP.md, "Write-back, and Outlook both ways".

Provider-specific API integrations are out of scope (severance doctrine):
ICS is the interchange boundary. Do not add a provider SDK or API client.
There is no network code in `app/lib` and a provider is reached through ICS
semantics, not its own protocol; a subscription that reads a published ICS
address is a later milestone and arrives as one, not as a provider client.

### Lens extension contract

To add a lens: one `LensSpec` in `app/lib/session/lens_catalog.dart` (title,
description, `isTimeSurface`, declared `ControlSpec`s whose keys are settings,
`spanUnit`/`spanFormula`, optional `scaleKey`), a `LensPainter` (or a widget
lens) registered through `registerLensPainter`/`registerLensWidget` in
`app/lib/lens/view_tile.dart`, and its defaults map composed into
`chronologSettings()`. Every number the lens draws with is a named setting. A
newly registered lens is placed after a user's persisted ordering without
resetting it. Zoom never swaps one lens for another: a tile IS a lens, its
span changes under it, and nothing crosses a threshold and silently becomes a
different lens. A lens that cannot support the current document paints the
explicit refusal in the law's vocabulary — it must not break other lenses or
invent a coordinate conversion.

## Standing rules

- This is a **public repo** — never commit calendar data or other personal
  files. `*.ics`, `*.chronolog`, and `local/` are gitignored by rule, and
  `local/` is untracked free space for whatever an individual keeps there.
  `.gitignore` holds generic rules only — never name or describe specific
  personal filenames in it or in docs.
- Only two network contexts matter: **Local** (this machine) and **WAN** (real
  sync between instances, future work — see ROADMAP.md). There is no LAN tier;
  don't reintroduce one.
- Flutter/Dart, one binary, no server. `lib/core/` is pure Dart. Zero Flutter
  plugins, ever (see `app/lib/` above); host capabilities go through
  `dart:ffi`. The Flutter SDK lives at `~/.flutter/flutter/bin` and is on the
  cmd PATH only — prefix it in any other shell.
- Everything is a tile; every tunable is a named setting whose value is an
  expression in the one math; no confirmation dialogs — every operation is
  undoable instead.
- Pre-alpha: break compatibility rather than accrete legacy shims. Code that
  is not used is not used and is removed — no dead export, no no-op kept for
  company.
- No enums, no special cases, no hard-coded values.
- `LEXICON.md` is the owner's voice — agents never edit it unprompted, even
  when it references something that has since moved or been deleted.
  Additions happen only at the owner's direction, in his words.
- The images in `local/GUI_Mockup/` (untracked, not in the repo) are live design references — never delete them.
- The doc set is this file, `README.md`, `ROADMAP.md`, `LEXICON.md`,
  `SENTENCES.md`, `ISSUES.md` (the living tracker — items carry date tags and
  are resolved in place; never mint dated issue files) and `RULINGS.md` (open
  questions, most blocking first). Don't create new `.md` files without the
  owner's direction.
- Prefer behavioral tests over source-text string assertions; tests are
  generative properties at `specSeed`, never pinned arbitrary facts.
- Run `flutter analyze` and `flutter test` in `app/` before finishing work.
  Nothing in the repo needs node.
