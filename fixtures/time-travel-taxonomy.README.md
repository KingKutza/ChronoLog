# Time-travel taxonomy acceptance fixture

`time-travel-taxonomy.chronolog.json` is canonical, non-private model data for
issue #23. It is a deliberately small structural counterpart to
`GUI_Mockup/bak.png`, not an attempt to trace every named film in that image.
The fixture exists to make the model's unusual claims executable.

| Fixture item | `bak.png` concept | Structural assertion |
| --- | --- | --- |
| `event:fork` / `termination:fork-start` | gray fork | A line begins at a terminator stapled to an interior point of another line; no line branches internally. |
| `event:repeated-incidence` | repeated crossings (for example, Primer/Harry Potter) | One event has two attachments to distinct coordinates on `line:earth`. |
| `segment:earth-traveler-shared` | common past | Two lines share a bounded segment through common event anchors, without copying all intervening events. |
| `displacement:backward-earth` | traveler moves into a world's past | Traveler proper time is explicitly forward while world direction is reverse. This records endpoints only; it does **not** fabricate a continuous conversion. |
| `line:loop` | closed loop | Its two terminators staple back to the same line at opposite coordinates. |
| `pattern:groundhog-loop-days` | Groundhog Day repeated days | Template/copy identity is explicit, loop days start at the same staple, and Phil remains a separate continuous line. |
| `termination:sealed-fork` | true ending | A persisted terminator seals the fork line. |
| `renderTerminatorState(..., unknownBoundary)` | crop at a viewport edge | `open` is projection state: absence of a rendered terminator, never a stored claim that the line ends. |

The fixture intentionally leaves segment-level existence/determinacy amplitude
out of the core graph. That is an annotation problem, not an excuse to add a
second connectivity mechanism before its semantics are decided.
