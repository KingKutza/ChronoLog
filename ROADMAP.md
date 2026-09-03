# Roadmap

## The sentence, the set, and the column

The card says sentences that read as sentences and edit every term in them,
folded one at a time so a staple list is a page and not a scroll. A selection
is a set on every lens, taken by the same marquee and the same ctrl-click
whatever the lens draws, and one sentence is said over the whole set at once.
Doing X to EACH is what a mass edit means by default; doing it to all AS ONE —
the single N-ary staple — is the alt path, and the two are different sentences
rather than one guess. A board column is a projection and a tile, its
position authored and never derived from what it happens to hold, and the
projection language admits object ids and graph predicates as names rather than
frames only: `ProjectionEngine.termsOf` is the one call every column and every
lens makes, so "all todos stapled to that meeting" and "AI Team NOT Done" are
the same kind of sentence. A set of columns saved together is a named subtree
of the stage, entered deliberately by alt-drag and never by accident.

That last extension is what the rest of the surface is waiting on. Until an
object answers to every name it reaches, List and Board stay special cases with
their own grouping mechanism, mass edits have nothing to say themselves over,
and a filter can only be spelled against a frame. After it, the stapled pile is
one addressable graph and every surface reads it the same way.

The contracts this wave builds against are written before it builds against
them: a test that asserts nothing green-washes exactly like a skip.

Which ladder level does a bare number in a time entry bind to? `26` must be the
day and `2026` the year without a digit-count test, which is a Gregorian
hardcode an 8×8×8 calendar would break. The card's coordinate field cannot
settle until that does.

What structurally answers "does this staple anchor a point?" The kind table is
the last place in the engine where a WORD selects a derivation, which is what
"verbs carry zero engine meaning" forbids. Melting it needs that answer, and
the card's point vocabulary — which points an object offers, read off the
object rather than from a fixed list of three — sits behind the melt.

And which of three superseded intents retire against the rulings that
superseded them: the field that committed on every keystroke, the done/closed
enum, and the whole-ended staple that was expected to fail to resolve a point?
A wave whose deliverable is green lights cannot fully green while they stand.

## The hand never waits on a query

The same pass, seen from the field-test side rather than the authoring side;
neither half waits on the other.

One full projection query per day per paint, run inside the pointer handler, is
why Strategic chugs on open, why minimap drag is unusable and why a pan drags
white paper onto the screen. The rule is the one already stated as law: if it
is not usable at 500 calendars it is improperly built for 3. The query coarsens
with the cell — facts while a cell can draw them, density below that — one
windowed bucketed query stands in for the per-day sweep, and motion is never
gated on paint: two clocks, an incremental budgeted paint, a coarser rung as
the fallback, and nothing committed inside a pointer handler.

This is also what makes the pile findable. Staple-to search across fifty frames
and two thousand todos, and a search for the objects with no staples at all,
are the same budget seen from the other side. A budget bounds work, never data.

## The super-strategic band

Strategic is one row per month and one column per day of that month, so a
century is twelve hundred rows of thirty-one cells. Zooming it out to a century
is not Strategic running slow, it is Strategic running out. The band beyond it
reads decades to centuries to millennia, and a span is said as a unit and a
number so a century is typed rather than reached by holding an arrow — which is
also the missing way to say WHERE, since today a lens can only be told how far,
never to jump to a date.

It needs the coarsening query and the butter from the milestone above, and it
gets sharper later from cycle-native coordinates, because nothing below the year
is legible at that span.

## Notes, and the vault as the boundary

A note is Obsidian-shaped by default: a name, properties and tags under a
rolled-up section, and a big markdown window that renders everything except the
line under the cursor. Staples occur naturally at creation and edit, can be
typed inline in the text, or entered as freeform properties; the note appears
wherever it is stapled, and which staples render in which lenses is
configurable per group or globally. This generalizes — any object carries
arbitrarily many staples of arbitrary kind, arbitrarily placed, and renders
accordingly.

Then ChronoLog works a vault directly: a path and a naming scheme for daily
notes, and everything works back and forth in both apps, the same for meeting
notes and for todos in linked folders. Markdown files are the interchange
boundary for notes exactly as ICS is for calendars — severance doctrine, no
plugin API coupling.

## Drawing what the model already knows

Four display languages do not exist for data that does.

The warp: cross-frame projection exists only through staples, and multiple
staples between two frames pin the correspondence exactly at each stapled point
without averaging into an offset. Between those points the mapping stretches,
and that stretch is authored meaning — "we place 8 that is where Lines shows us
the warp." The substrate keeps every point exact and claims nothing about the
space between them. Drawing the stretch is Lines work and is undesigned.

Fuzziness reaches the renderer as data and is marked, but a spread wants sigils
and zones that read at a glance without piling information on the eye. The
apparent-magnitude falloff has the same problem, and the two want designing
together.

An overdetermined anchor is reported and never averaged. How a lens shows that
an authored staple is not being believed is undesigned.

Overlap is indicated locally, not globally: a thirty-minute collision must not
lane both events full height. Events stay rectangles — no key-shaped blocks —
and the contended interval itself gets drawn rather than the participants
deformed. Placing an event inside an occupied span works through the occupant
instead of requiring it dragged away and back.

What is a constraint bound? "Can't go later than like 7:30/8" is a bound
distinct from the fuzzy actual, and the kind registry stays deliberately
one entry short until the semantics are decided, because registering a kind
nobody has ruled is inventing meaning.

## Time travel authored

The taxonomy is executable in the model — a fork is a terminator stapled to an
interior point, a loop is two terminators stapling back, a displacement records
forward traveler time against reverse world direction as endpoints only with no
fabricated conversion, and `open` is projection state rather than a stored claim
that a line ends. What has no authoring path is any of it. A basis is any valid
expression in the one math — linear, non-linear, piecewise, an all-point, a
loop, a list — plus its unit breakdown, and an era is a frame stapled to
another. What it waits on is the frame card saying sentences the way the object
card does, so it follows the wave; what it delivers is real time-travel frames
in the live document — appended as one journal transaction like any other edit,
and undoable — which is how the model gets nailed down against something other
than a fixture. Lines and Tree are where the branches and loops get drawn.

## One cycle idea

A recurring event, a cycle, and every repeating structure beside them are ONE
object, and today they are three mechanisms: a rule that generates occurrences,
something the coordinate law declares, and an authored group over a cycle. Same
idea said three ways, which is the trinity's own complaint. The one object is a
period, an epoch anchor, and names — nothing else — and all three are that
object with different numbers in it.

The half that makes this more than tidying: a coordinate must be authorable
natively on an attached cycle, so "third Monday" is a valid coordinate rather
than a recurrence special case. That is an ordinal selection over a cycle
position within a containing level, and it subsumes what ICS spells `BYDAY=3MO`
and `BYSETPOS` — those become a translation at the calendar boundary, never the
mechanism. An occurrence stops being something a rule generates and becomes
something a coordinate names, read through the same path every other coordinate
takes.

A weekend is what this makes ordinary: a cultural assertion over the law's own
cycle, authored as an object, never a belief a lens holds — and once one can be
authored, a library of them is adoptable, holidays and sabbath and business
hours and a shift rotation, none of them seeded and none of them offered until
the cycle exists to hang them on.

This is a change to the substrate every surface reads, so it shares a wave with
no surface work: "so we have time to give more consideration, before we blunder
in and turn 7 heads to 14." Lunisolar is the hard edge to design against rather
than discover later — the month depends on observation and the year's month
count depends on the moon, which is a fixed point, not a stack.

Does a calendar synthesize from frames? A cycle contribution — period,
epoch, names — would compose freely and order-independently, because two cycles
never read each other; a structure contribution — levels, radices,
intercalation — would be owned by exactly one frame, and an overlap would be a
refusal in prose rather than a precedence rule, since a precedence rule is an
encoded right way. Is that distinction the law?

## Patterns authored, not picked

The repeat control is a rigid list of common Gregorian periods, and its own note
admits a complex pattern is authored elsewhere. "Every odd day of every even
month of every odd year, except where any of those numbers is prime" is a repeat
pattern with no entry path, and the dropdown plays worse still against a
non-Gregorian calendar. The math exists for exactly this; the authoring surface
does not. Cycle-native coordinates are what make the surface expressible without
a second mechanism, which is why this follows them.

## Custom calendars all the way down

The law executes: one coordinate engine reads the levels, radices and
transitions, Gregorian is a registered entry rather than a bypass, a wholly
invented uniform ladder converts through the registry, eras are a level of the
coordinate with per-era numbering direction so BCE and Merethic both count down,
and a frame with no now-mapping refuses a Now line instead of faking one.

What is still Gregorian is the drawing. The minimap's month-boundary walk is the
registered Gregorian ladder's own, and the month sheet assumes a Gregorian week.
Custom day, month and year names have to reach the ticks and the labels; units
must be addable and removable; Strategic and Wall must adapt to full months per
line or weeks per line under whatever the law says a month holds.

Observed boundaries ride — a lunar series whose every gap is a different exact
observation, with no mean synodic month allowed to stand in for any one of them.
The computed sibling does not: a cycle derived from formula or ephemeris, the
moon by Newton, with observation as the override rather than the definition.

## Write-back, and Outlook both ways

ICS reads a file and writes a file; what is disabled is write-back — carrying
an edit made here into the calendar it came from. Opening that direction
delivers two-way sync with Outlook, which is high priority and sits here for
difficulty rather than for want of it, through ICS semantics and never a
provider API. The contract is already ruled and lossy on purpose: Gregorian and
RSCALE come in; a rule goes out as a rule where ICS can say it and as
materialized instants where it cannot; and there is no private `X-` dialect in
either direction, so object anchors, fuzzy spreads and segmented series
identity do not round-trip. The journal's record-level ops are the foundation
the reconcile stands on.

What are the conflict semantics when a recurring event is edited on both
sides, and how does a timezone travel? That design does not exist yet, and it is
what gates the whole direction.

## Subscriptions

Google Calendar and any other provider, each through its published ICS URL and
the same reconcile write-back builds. A provider connects the way every provider
connects, or it does not connect.

## The other platforms

Windows is the build. arm64 Ubuntu under Wayland only is the cross-test that
keeps the surface honest, and Android is near-term. There are no Flutter plugins
and there never will be — this machine's policy forbids the symlink support a
plugin build needs — so anything the host has to answer goes through FFI.

## Two ChronoLogs

Instance-to-instance sync across the web on the journal's per-op foundation,
then real field-level merge on top of the sequencing. One master isolate owns
the document today and that is why there is no conflict type, no rebase loop and
no merge; WAN is what puts those questions back on the table, and merge needs
design before either lands.

## The document's own timeline

A lens over the journal itself: scroll back through what the document was, watch
a deleted series vanish and return. Every op is already recorded. This is the
view that record makes possible, and it is the very bottom on purpose.
