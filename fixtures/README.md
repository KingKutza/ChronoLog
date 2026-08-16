# Fixtures

Chronolog fixtures are compact model documents. They are not pre-expanded bags
of calendar occurrences.

```sh
node fixtures/gen-celestial.js
node fixtures/verify-celestial.js
```

`celestial.chronolog.json` contains a small Earth–Moon–Sun mean-orbit pattern.
The same constants and formula answer state queries and emit lunar phase facts
for any requested window, including remote and negative years. The fixture is
exact to its stored model; it is intentionally not a physical ephemeris.

Personal `*.ics` exports remain untracked. The legacy generated
`fixtures/celestial.ics` is no longer used.
