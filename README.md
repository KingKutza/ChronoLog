# ChronoLog

ChronoLog is a local-first, pre-alpha timeline instrument. Timelines are
first-class objects — events staple onto them, sometimes onto more than one
at once — and one `chronolog/1` document is the whole workspace. Seven
lenses (Intimate, Tactical, Strategic, Wall, Lines, Spiral, Radial) look at
that same document from different scales and shapes; none of them owns the
data.

## Quick start

```sh
npm start        # run the installed/portable launcher
npm run dev       # run a source checkout at http://127.0.0.1:4173
npm test          # run the test suite
npm run check     # syntax-check every source file
```

`npm run build:portable` builds a self-contained bundle (embedded Node
runtime, no install step) for the current platform: `chronolog-linux-x64` or
`chronolog-windows-x64`.

`chronolog --help` lists launcher options, including `--data-dir` and
`--no-open`.

## Where data lives

ChronoLog is dependency-free ES modules served locally on `127.0.0.1` only;
no cloud service, account, or network connection is required. By default the
data directory *is* the application's own directory — dev mode and an
installed/portable bundle behave identically. `--data-dir` (or the
`CHRONOLOG_DATA_DIR` environment variable) relocates it. Deleting a portable
bundle deletes its data with it; keep the folder, or move data out with
`--data-dir` first.

The workspace document is `chronolog.chronolog`, saved by atomic temp file
and rename. A first run starts from an empty document — structural frames
only, nothing pre-populated.

## Calendar and task sync

Use **Document → Sync web calendars** for explicit, read-only refreshes from
a published HTTPS ICS address (the private feed URL that Outlook, Google
Calendar, Apple Calendar, and most other calendar services can publish).
Write-back is disabled: a sync only ever pulls. ICS file import/export is
also supported for one-off transfers. Feed addresses are stored in an
owner-only dot-file in the data directory — never inside the portable
document — protected by owner-only file permissions on POSIX and by NTFS
ACLs on Windows.

## Further reading

- [ROADMAP.md](ROADMAP.md) — the work list, in priority order
- [AGENTS.md](AGENTS.md) — architecture map and engineering contracts
- [LEXICON.md](LEXICON.md) — vocabulary and founding ideas
