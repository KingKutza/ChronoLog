# Fixtures

Test data is **generated, never committed** — the repo stores code and repo
stuff, not data. `*.ics` is universally gitignored, no exceptions.

```sh
node fixtures/gen-celestial.js     # writes fixtures/celestial.ics (stays untracked)
node fixtures/verify-celestial.js  # sanity-checks the output
```

`celestial.ics` — 126 synthetic celestial events, 2025–2027: new moons
(UTC-timed; radial cycle anchors), full moons, actual eclipses,
solstices/equinoxes, meteor shower peaks, perihelion/aphelion. No RRULEs —
every occurrence explicit, so cycles have honest variable lengths.
CATEGORIES per type (Lunar/Solar/Meteor/Eclipse/Orbit) exercise group
seeding from a second calendar.

Personal calendar exports also live untracked in the working directory —
same rule protects them.
