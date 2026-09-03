# ChronoLog

A local-first timeline instrument, pre-alpha. Timelines are first-class
objects and events staple onto them, sometimes onto more than one at once.
One document is the whole workspace; seven lenses — Intimate, Tactical,
Strategic, Wall, Lines, Spiral, Radial — look at that same document at
different scales and shapes, and none of them owns the data.

Nothing in the model encodes a right way to read time. A staple says n
points are one point; what a connection means, what a colour means, and
which unit a coordinate speaks are authored, not inferred.

## Build and run

The app is a Flutter application in `app/`. Windows is the primary target;
arm64 Linux (Wayland) and Android follow.

```sh
cd app
flutter run -d windows     # run it
flutter test               # the suite
flutter analyze            # the analyzer
flutter build windows      # a release build
```

Node 20 is required for one test: `test/lens/geometry_diff_test.dart` runs
`tool/lens_diff_gen.mjs` as a differential oracle against the previous
JavaScript implementation in `src/`, proving the Dart geometry matches it
case for case. That is what `src/`, `fixtures/` and the root `package.json`
are still here for.

Generative tests take a seed from `CHRONOLOG_SEED`; a failure prints the
seed it ran with.

## Where data lives

The document, the layout, the settings and the view are written beside the
application itself — no user-profile directory, no cloud service, no
account, no network connection. `document.saveAt` relocates the document.
A first run starts empty: structural frames only, nothing pre-populated.

Two-way sync with Outlook goes through ICS semantics rather than provider
APIs. ICS is a deliberately lossy boundary: Gregorian and RSCALE come in,
rules and projections go out as materialized instants, and no private
`X-` dialect is minted.

## Documents

- [ROADMAP.md](ROADMAP.md) — the work, in priority order
- [ISSUES.md](ISSUES.md) — the living tracker: field reports, verdicts, rulings
- [RULINGS.md](RULINGS.md) — open questions, most blocking first
- [AGENTS.md](AGENTS.md) — architecture map and engineering contracts
- [SENTENCES.md](SENTENCES.md) — the sentences the edit card speaks
- [LEXICON.md](LEXICON.md) — vocabulary and founding ideas
- [WHAT_RIDES.md](WHAT_RIDES.md) — what carries forward, and its cost
- [GUI_Mockup/](GUI_Mockup) — live design references

## License

MIT. See [LICENSE](LICENSE).
