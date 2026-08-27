# app/tool

Uncounted tooling. Nothing under `lib/` imports anything here, and nothing here
ships in a build. **This directory is load-bearing: it is the only thing that
proves the Dart core still agrees with the JavaScript it was ported from. Do not
delete it as unused code — it has no callers by design.**

## Differential harness — the Dart port against the shipped JavaScript

```
cd app
dart run tool/diff_check.dart
```

`diff_gen.mjs` (Node, ESM) generates random declarations, coordinates, era
tables and refusal cases from a fixed seed, runs them through `src/exact.js`,
`src/coordinate-law.js` and `src/eras.js`, and emits every answer as an exact
string. `diff_check.dart` replays the same cases through
`lib/core/coordinate_law.dart` and `lib/core/eras.dart` and compares. Exit code
0 means no disagreement.

`diff_check.dart` shells out to `node` itself. To keep the generated cases for
inspection, redirect into `build/` (already ignored):

```
node tool/diff_gen.mjs > build/diff-cases.json
dart run tool/diff_check.dart build/diff-cases.json
```

Covered: `unitDays` / `unitAtoms` / `meanUnitDays` / `meanMonthDays`, the
`unitsPer` melt against all six wrappers it replaces, `toDays` / `fromDays` in
both directions, `magnitudeDays`, `formatYear` / `parseYear`, cycles, the
declaration and era-table refusal messages verbatim, and `EraTable` range
derivation, `toProperYear` / `fromProperYear`, `format` / `parse`,
`toDeclaration` and `summary`.

The harness reports **documented melt divergences** separately from failures: a
count of places where one of the six retired wrappers disagreed with
`unitsPer`'s single fallback policy. Those are expected, not defects — see the
report accompanying the port.

Expected result at the pinned seed (20260827): **2,002 cases · 126,803 checks ·
PASSED**, with 103 documented `daysPerWeek` divergences.

## Differential harness — the staple substrate and the era chain

```
cd app
dart run tool/staple_diff_check.dart
```

Same shape, second pair. `staple_diff_gen.mjs` generates random documents from a
fixed seed, runs every probe through `src/staples.js` and `src/era-chain.js`, and
emits each answer as an exact string. `staple_diff_check.dart` replays the same
cases through `lib/core/staples.dart` and `lib/core/era_chain.dart` and compares.
It shells out to `node` itself; to keep the generated cases for inspection:

```
node tool/staple_diff_gen.mjs > build/staple-diff-cases.json
dart run tool/staple_diff_check.dart build/staple-diff-cases.json
```

Covered: `resolveObjectExtent` in all of its terminal shapes (exact day strings,
derived magnitudes, spreads, anchors, and every overdetermined and unresolved
report with its own sentence), `describeCorrespondence` plus the enumeration
order and both sides' instants, `seriesSegments` closes including the
precision-aware `partitionCloseDays`, `seriesPhaseDays`, `liveExclusionDays`, and
`eraChainFrames` / `eraChain` / `frameEraContext` resolutions and refusal
messages verbatim.

**Ruled divergences, reported separately and never compared.** R4: a succession
staple with no `role` fields — `era-chain.js` sniffs `end.role`, the port reads
the ORDER of the ends, so the JavaScript sees no edge at all. R3: the end-scope
gate lives in `model.js`'s `validateDocument`, not in `staples.js`, so cases
carrying a pair the validator refuses stay in the parity set; the count says how
many of them the two derivations agreed on anyway.

Expected result at the pinned seed (20260827): **1,600 cases · 10,630
comparisons · 0 failures**, with 95 R4-divergent cases skipped by design and 45
validator-refused pairs agreeing anyway.

## Differential harness — the ICS boundary

```
cd app
dart run tool/ics_diff_check.dart
```

Same shape, third pair. `ics_diff_gen.mjs` generates random ICS FILES from its
own grammar at a fixed seed — random properties, parameters, canonical escapes,
arbitrary fold points, multi-byte text, foreign `X-` keys, subcomponents, signed
and long years, `RSCALE` scales both registered and not — runs each file through
`src/ics.js`'s import AND export, and emits both the file text and every answer
as an exact string. `ics_diff_check.dart` replays the same file text through
`lib/core/ics.dart` and compares. It shells out to `node` itself; to keep the
cases for inspection:

```
node tool/ics_diff_gen.mjs > build/ics-diff-cases.json
dart run tool/ics_diff_check.dart build/ics-diff-cases.json
```

**Every ICS input is a string the generator built.** Nothing in either half
reads a file from disk: `fixtures/` holds untracked personal calendar data, and
this harness must never touch it.

Covered on the import side: the frames, objects, placements (level by level,
with `dateOnly`/`utc`/`TZID` typing), exact duration days, patterns (tokenized
rule, raw rule text, exclusion days, and the per-value original EXDATE text with
its parameters), overrides by occurrence key with their replacements, staple
suggestions, and the warnings verbatim. On the export side: **byte comparison**
of the whole emitted file, with and without a window.

**Ruled divergences, reported separately and never compared.** D1: a file
carrying the `X-CHRONOLOG` dialect — the JavaScript reconstructs anchors and
spreads from it and re-emits all six properties, and `-SERIES`/`-SEGMENT-INDEX`
is the only way a generated file can make the JavaScript emit sibling segment
VEVENTs at all; the dialect is dead both directions here, so those files are
counted and skipped whole. D2: a file carrying a `VTODO` — the mapping is ruled
on hold, so the component is retained verbatim; the VEVENT semantics still
agree and are still compared, and only the bytes sit out, because the JavaScript
lifts the VTODO out of the calendar shell and re-emits it after every VEVENT.
D3: a malformed `RRULE` part with no `=` — the JavaScript's own slice arithmetic
eats its last character and the port keeps the part; a fixed defect, counted.

Expected result at the pinned seed (20260827): **1,500 files · 1,320 semantics
cases · 1,238 export byte comparisons · 9,158 comparisons · 0 failures**, with
155 D1 files skipped whole, 82 D2 files compared as semantics only, and 25 D3
files skipped whole.
