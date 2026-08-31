# Sentences

The edit card speaks sentences. Every sentence is one record the model holds; every record the model holds is speakable. The notation, used the same way everywhere: ***starred*** is a dropdown slot, `$words` are typed by the user, **bold** is a filled-in value in an example, plain words are the sentence itself. Events, ToDos and Notes speak the same sentences — only the noun changes.

## The sentence is one math

A sentence is the readable rendering of a one-math expression, and nothing else. Anything one math can express, the sentences can say; anything it cannot, they cannot. The grammar is formal: one sentence has one parse and one denotation, never an ambiguity — a sentence that does not parse is refused with the part named, never guessed at.

Three ways in, one truth: build the sentence from its dropdowns, type the sentence, or type the one math. Hover any sentence to see its one math. What you said and what it means can never drift, because the math is always in view.

The math holds both functions and equations. A function computes toward a designated output — x = A∪B/11 — and that is what paints: weight, falloff, warp. An equation asserts a relation with no privileged side — A = B + 21 — and that is what a sentence is: a staple identifies its points as one point, which is why one record renders from either end. Reading where an object sits is solving its system of equations; an overdetermined or unsolvable system is reported, never averaged.

One record renders from either end:

> Lunch begins at 11:30 on My calendar. **=** My calendar contains Lunch, beginning at 11:30 Friday 9.4.26.

> Lunch marks the beginning of My calendar. **=** My calendar begins at Lunch. — weird, and supported.

> Lunch staples to My calendar and to James's calendar at 11:30 on 8.3.26. — one staple, three pages, one breath.

> Lunch staples to My calendar at 11:30 on Fridays between 8.1.26 and 9.1.27. — the dot of the i; the one math shows which clause binds what.

## What a staple is

The word staple is deliberate. What a staple says, every time: **this point right here is also that point right there.** Attaching an event to a calendar, the end of an era to the beginning of the next, a point to the midpoint of its own object, a todo to an event — anything else. One saying.

The physical picture: a staple is a piece of metal existing in a third dimension that pierces one or more pages (objects and frames) at zero or more points, causing all of said points to be bound together through that third dimension.

The formal statement: **n points on objects or frames are one point** — n ≥ 0, where a point has a size: 0, all, or any one-math value between. An instant is a size-0 point, a span is a sized point, a scattered selection is a point with a scattered measure. Two points is the common case, never the definition. Direction is the authored order, never a stored type — there is no start-staple and no due-staple.

"Is also" already lives in the sentences: `$name` is also placed at ***place*** is the definition verbatim, and every staple sentence can be read that way — Standup's beginning is also Work at 9:00.

## The header

> ***EVENT*** `$name` — ***DESCRIPTION*** `$description` — **+**

- ***EVENT*** · ***TODO*** · ***NOTE*** — click the noun to change what it is. Nothing else about the object changes.
- Properties start at name, description, color, location. **+** adds:
  - a stock property from the contract,
  - a custom property — one field names it, one fills it, a third drops down its type (int, float, bool, string, …),
  - a magnitude — `$name` lasts ***Magnitude*** is a property, not a staple; duration, apparent magnitude, any named magnitude. When both the beginning and the end are stapled, duration is derived and this property reports rather than rules,
  - a display handling — how the object draws: mark, zone, … — defaulted by noun, definable in sentence arbitrarily.
- **The contract**: one file carries the default properties, the offered options, the display handlings, and the offered verbs. Import one to define the objects of your instance; export yours from settings for another user. The dropdowns read the contract; nothing below is hardcoded. Secrets: far down the roadmap, one more contract entry.

## The staple sentence

One template carries every connection:

> `$name` ***verb*** ***its point*** to ***the other end*** at ***place***.

### The verb — an authored word

One definition, shared by every verb: **a staple says its n points are one point.** The solver reads the identification and never the verb. The verb is a word on the claim — data, like color: projections include by it, sort by it, style by it, and any meaning beyond the identification is authored there, never interpreted per-verb by the engine. A mapping from verbs to meanings would be an enum in a costume; there is no mapping.

Correspondence, succession, placement are not kinds — they are names for particular identifications:

- two frame points made one is what we call a correspondence
- Heisei.begin made one with Showa.end is what we call a succession, and nothing about it is special: both are plain points each basis has the power to define — the end of 1 could as easily staple three weeks into 2, and where a basis cannot label a point along the line the staple connects inclusively: the end of 1 staples to all of 2
- the identification the creation gesture writes is what we call the placement; "is placed on" is its default wording
- a rule change is not the staple's doing at all: the series' rule is an authored one-math function, piecewise on a point a staple identifies — the staple carries no payload

The contract carries wording only: which verbs the dropdowns offer, the default word per gesture ("is placed on", a ToDo's "was observed at"), styling. Zero semantics. Type any verb; it is as legal as the offered ones, and it means what every staple means — these points are one point — plus whatever your projections make of the word.

### Its point — which point of this object the staple touches

1. **the beginning** — the default; a sentence that says nothing about the point means this
2. **the end**
3. **the midpoint**
4. **an expression…** — one math over the object's extent: a point 45 minutes in, two points, seven, the region from 1/3 to 3/5, any arbitrary point-set. And, Or, Not compose here — never as canned combinations in the dropdown.
5. any point may carry give or take ***Magnitude*** — fuzz belongs to the staple, not the object. Asymmetric when wanted: "about 5ish" spreads both ways, "working early to 5ish" spreads one.

A magnitude is a quantity in a named frame's units — absolute, never relative to the object's own size. Unsaid, the frame is the one this end touches. Crossing to a frame on another time scale, it projects through the correspondence like every coordinate does.

### The other end — what it pierces

1. ***Frame*** at ***place*** — typing a name that does not exist offers **create "$name"…**, which opens that frame's own card
2. ***Object*** at ***its point*** — same point vocabulary, same **create** offer for a name that does not exist
3. ***Series*** — the whole pattern, positioned by this end
4. **… and *another end*** — the staple pierces another page; every added end binds its point into the same staple

The object picker is a search surface: typed text narrows by name, rows disambiguate by kind, frame and place, a series is one row that unfolds to its instances. Proven at stratospheric counts with seeded name collisions, never at demo counts.

### Place — where on a frame

1. **a time** — one instant, picked or typed
2. **every time that matches** — a selector, read against the frame's OWN declared cycles: "Tuesdays" means whatever that frame says a Tuesday is. The named selectors are sugar; a one-math predicate authors any the sugar cannot say
3. **a span** — from one time to another; each bound speaks this whole place vocabulary
4. *no at-clause* — when there is nothing to say, the sentence says nothing: an object end's point already sits where its object sits, a succession's boundary is where the earlier era runs out, and the authored claim of nothing-here is spelled by deliberately clearing the at — never by "at Nowhere"

Every literal in a sentence already IS one math; a typed one-math block may replace any of them, and never has to.

## The kinship sentences

Same section, same shapes:

1. `$name` is stapled to `$other` — the blank association, no judgment
2. `$name` contains `$other` / `$name` is inside `$other`
3. `$name` is a member of ***Frame*** — state lives here: done is membership in the Done frame
4. `$name` is a member of ***Frame*** at ***place*** — the membership plus an end staple at that place ("done, as of Tuesday 5:00")
5. `$name` is also placed at ***place*** — a second placement of the one object: the one happening, present at two coordinates; two marks, one identity, never a copy and never a repeat

Exclusions are a property of the frame, written in one math and authored once at frame setup — never on the object, never again per membership: ToDo/Done carries `for every O: not(member(O, ToDo) and member(O, Done))`, and every membership write honors it, the card writing the removal beside the membership.

## Worked cards

**Event** — *EVENT* Standup — *DESCRIPTION* daily sync — lasts **15 minutes**
> Standup is placed on **Work** at **9:00 Mon Jan 5**.

**ToDo** — *TODO* Fix the gutter
> Fix the gutter was observed at **Sat Mar 14**. Fix the gutter staples **the end** to **Spring cleaning** at **its beginning**. Fix the gutter is a member of **Done** at **Mar 21, 4:30**.

**Note** — *NOTE* D&D availability
> D&D availability is placed on **Personal** at **Thu Feb 12**. D&D availability is inside **Campaign planning**. D&D availability staples **the beginning** to **Rob's schedule** at **every time that matches: Mondays**, give or take **an hour**.

**Twice-placed** — *EVENT* Recon mission
> Recon mission is placed on **SGC** at **Mar 3, 0800**. Recon mission is also placed at **P3X-451, day 40** — the frames run on different scales, and the correspondence puts the one mission at two coordinates. One event, two marks, one edit. A dinner that happens again next week is a series or a second event, never a second placement.

## The math, worked

Every sentence beside its expansion. Syntax illustrative; the shape is the claim.

### Claims — identifications: n points are one point

> Standup is placed on Work at 9:00 Mon Jan 5.

    Standup.begin = Work@(Mon Jan 5, 9:00)

> Fix the gutter staples the end to Spring cleaning at its beginning.

    Gutter.end = SpringCleaning.begin

Knowing either side answers the other — the solver propagates. A second claim on an already-anchored point is reported, never averaged.

> Lunch staples to My calendar and to James's calendar at 11:30 on 8.3.26.

    Lunch.begin = MyCal@(8.3.26, 11:30) = JamesCal@(8.3.26, 11:30)

One staple, one equation chain, three pages.

> Recon mission is placed on SGC at Mar 3, 0800. Recon mission is also placed at P3X-451, day 40.

    Recon.begin = SGC@(Mar 3, 0800)
    Recon.begin = P3X@(day 40)

Both true of the one point. The pair entails the warp Lines draws.

> Showa precedes Heisei.

    Heisei.begin = Showa.end

No literal anywhere: the boundary is where the earlier era runs out, and authoring a coordinate would create a second fact that can disagree.

> SGC at Mar 3 corresponds to P3X-451 at day 40.

    SGC@(Mar 3) = P3X@(day 40)

Many of these are the correspondence — never assumed monotone, total, or one-to-one.

> Lunch begins at 11:30 on My calendar, give or take 15 minutes.

    Lunch.begin = MyCal@11:30 ± 15min(MyCal)

Asymmetric when wanted: "working early to 5ish" is `spread(before: 60min, after: 0)`. The unit names its frame; crossing a correspondence it projects like every coordinate.

> The series' rule changes at Jun 1 to weekly.

    cut = Cal@(Jun 1)                              — the staple: one identified point
    rule(Series, t) = R1 where t < cut, R2 after   — the rule: an authored function on the series, never staple content

### Points — expressions over an extent

    the beginning                O.begin
    the end                      O.end
    the midpoint                 O.begin + O.length/2
    45 minutes in                O.begin + 45min
    the beginning AND the end    {O.begin, O.end}          — one staple, one page, two points
    from 1/3 to 3/5              O.begin + O.length * [1/3 .. 3/5]

### Places — coordinates, predicates, spans

    at 9:00 Mon Jan 5                     Work@(2026-01-05, 9:00)
    every time that matches Tuesdays      Work@{t : t.weekday = "Tuesday"}
    11:30 Fridays, 8.1.26 to 9.1.27       MyCal@{t : t.time = 11:30 and t.weekday = "Friday" and 8.1.26 <= t <= 9.1.27}
    a span                                Work@[9:00 .. 17:00]
    nowhere on purpose                    the at deliberately cleared — the end pierces the page and matches no instant

### Includes — booleans with O in scope

    member(O, F)   := any s in O.staples: s.verb = "member" and F in s.pages
    contains(A, B) := any s in A.staples: s.verb = "contains" and B in s.pages
    done(O)        := member(O, Done)

    include O where member(O, Work) or (O.color = "red" and not done(O))

Membership is a definition, not a primitive. Union is `or`, filters are authored as `not`.

### Keys and weights — functions, a designated output

    sort by duration      key(O) = O.magnitudes.duration
    group staples by verb key(s) = s.verb
    weight                w(O) = O.weight * 1.5
    apparent magnitude    apparent(O) = O.magnitude * falloff(distance)

### Constraints — the partition

State declares its children a partition:

    for every O: not (member(O, ToDo) and member(O, Done))

The card honors the `not` by writing the removal when it writes the membership; the solver never holds both.

### The day zone

> Day is placed on My calendar at every t: 06:30 <= t.time <= 22:00. Day displays as a zone.

An authored object, not a setting — and `sunrise(t)` is one math away when wanted.

A named point is not a primitive: a point is an expression, a name is only a label on one, and a staple identifying a single point (n = 1) is a pin that gives a point identity to reference. Fuzz lives in one math — give or take is an interval term, its units named the way any term's are. The ToDo/Done exclusion is an authored not-claim like any sentence — for every O: not(member(O, ToDo) and member(O, Done)) — and the card honors it by writing the removal beside the membership. A completion instant lives on the membership claim, so an end staple identifies like every staple; nothing records without binding.
