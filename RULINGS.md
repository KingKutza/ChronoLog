# Rulings wanted

Open questions, most blocking first. Each carries what is being asked, what
turns on it, the options, and a recommendation. Write under **Answer:** in
whatever form suits; an answered question leaves this file, its answer stated
as engineering law in AGENTS.md or as vocabulary in LEXICON.md.

---

## 4. Bare numbers in a time entry

Ruled: what is absent *below* the typed run is precision; what is absent *above*
it comes from now. So a bare year is a year, a day is all day, a time is today.

Open: which ladder level a bare number attaches to. `26` must mean the day and
`2026` the year, and a digit-count test ("four digits means year") is a
Gregorian hardcode that cannot survive an 8×8×8 calendar.

- **(a) Deepest legal suffix.** A bare run binds as the deepest suffix of the
  ladder whose every value is legal in its own level's range, and the row echoes
  its reading back in prose ("26 Aug 2026, all day") before Save.
- **(b) Ask when ambiguous** — the row offers both readings and the person picks.
- **(c) A level prefix** — `d26`, `y2026`. Unambiguous, and nobody will type it.

**Recommendation: (a)** with the echo, since the echo is what makes a wrong
guess cost one glance instead of a wrong record.

**Answer:**

---

**What the tests found, 9.3 — this question cannot be answered by shape.**

`app/test/core/bare_number_entry_test.dart` was authored against this section
and could not pin any Gregorian time of day. The shipped ladder carries minute
and second BOTH at radix 60, plus a continuous `subsecond` tail, so `17:30` is
legally hour:minute, and minute:second, and second.subsecond — three readings
with no range to separate them. The same cut lands on the example in this
section: `26 3:15` read as "today at 3:15" is equally legal as year 26, March
15.

So there is no disambiguation-by-shape available and no digit-count test that
is not a Gregorian hardcode. The binding has to be ruled, not derived. The test
asserts only what every candidate answer agrees on — a run legal at exactly one
alignment binds there, above from now, below absent, depth is the deepest
typed — and quantifies that over invented tail-less ladders and the 8x8x8 law,
leaving Gregorian time of day to this ruling.

---

## 6. Twelve superseded tests

Wave one's rulings turned twelve existing assertions into statements of pre-9.2
behaviour. Two are mechanical and I will just fix them unless told otherwise:
`rrule_test`'s `_unimplementedParts` must shrink now that BYSETPOS and WKST
generate, and `projection_test:835` needs an example part that is still missing
(`BYWEEKNO`).

Three are reversals and want your word, because retiring a test is retiring an
intent:

- **`membership_melt_test:236`** (×5 seeds) expects `extent.unresolved` to
  contain "whole of this object". The affiliation-silence ruling says a
  whole-ended staple claims no point and so cannot fail to resolve one.
  `affiliation_silence_test` is its replacement.
- **`coordinate_field_test`** — two tests assert the per-keystroke commit that
  the commit-on-Enter ruling replaced.
- **`todo_shape_test`** — encodes the done/closed enum the Done melt retired.

**Recommendation:** retire all three against the rulings that superseded them,
by a Fable authoring pass rather than by hand, so the replacement states the new
law rather than merely deleting the old.

**Answer:**
I don't know now and need to take a tour of the test to give a real verdict.
---

## 10. Calendar as a synthesis of frames — ratifying the distinction

Parked to ROADMAP #5 for consideration, so this is not urgent. What would help
is ratifying (or rejecting) the distinction the analysis rests on, since the
cycle unification is being designed against it:

- A **cycle contribution** — period, epoch anchor, names — composes freely and
  is order-independent, because two cycles never read each other.
- A **structure contribution** — levels, radices, intercalation — may be owned
  by exactly one frame, and an overlap is a refusal in prose, never a precedence
  rule, because a precedence rule is an encoded right way.

The hard edge to design against, not to discover later: lunisolar, where the
month depends on observation and the year's month-count depends on the moon.
That is a fixed point, not a stack.

**Answer:**

---

## 11. What the distance between two staples means — SETTLED, residues at 13 and 14

A named anchor point's relationship to a second anchor derives no magnitude
today, and that is deliberate rather than missing: the two points are said to
be points, and nothing claims to know how far apart they are.

But the pile is a graph and the graph is projectable, so the distance between
two anchors on the same basis is computable wherever both resolve. The question
is whether it should be a value the model offers — a derived magnitude a
sentence can read and a lens can draw — or whether offering it would be the
engine deciding a meaning nobody authored.

The case for offering it: "three weeks after the sundering" is exactly that
distance, and refusing to derive it makes the person restate what the staples
already say. The case against: two anchors on DIFFERENT bases have no distance
at all unless a staple relates them, so a magnitude that appears for one pair
and refuses for another is a surface that lies about what it knows.

**Answer:**
Language is important Staples not anchors. Further Staples don't have names, only the things the attach do. Here there is a difference between derived and authored values, If a staple is attached to a frame with time that is when all things attached by that staple happen, if it connects more than one frame with time then that is when all things attached happen in each frame. If one object is stapled at multiple points to one time berring frame than its duration is the distance between the staples. either as a single differentce or as a peicewise distance. That applies to each time bearing frame that an object has multiple staples to. If an object has multiple time berring frames that it has one staple to each then there is no way to compute duration and that is fine. we can honestly say in a graph we know this is connected to that via the other, without claming a onemath projection. All of the above deal with a derived value wich is calculated at projection time. Additionaly events and time berring frames can have duration, This is recorded in the save file and in the precense of a single staple or one per time berring frame (for an object) can be used to project the object on any attached frame and to creat a onemath projectable path between two time berring frames that each single staple to an object. The value would also display on an unstapled object. For a n>1 stappled object where the authored and computed time agree, all is good, where they disagree, It depends on projection, if you porject the object and time relative to it, time warps to the difference, if you project the Frame and the object on it, then it is the staple derived time, and if you project the frame and the object relative to it the object warps to around the frame. Also for n>2 staples the excess or missing duration should be distributed equaly along the length of the object so that each peicewise part gets an amount proportional to the fraction of the total computed duration that that part represents. Finaly for two time berring frames joined by n>1 staples where the duration calculated along fram f1, f2, fn differ on the same basis, the frame being projected as primary wins and all other frames and there objects if carried into the projection warp according to that difference, as projected to the full length of the frame. For n>2 staples this is done peicewise for each segement and the tails per continuing projection of the last segment. For frames with a disimilar basis, the staples bridge creating a onemath rout to projecting one onto the other, if n=2 staples the frames are scaled to match per a continous projection if n>3 and all staples don't agree then the non-primary frame is scaled peicwise with the tails obeying a projection of the last segment.

---

## 12. Right-clicking a reading that names several frames

A frame's verbs belong on every surface that names that frame -- one
`frameMenu`, never a per-surface list. That much is settled by the trinity.

What is not settled is the joined case. The view bar's projection reading can
say `A or B or C`, and a right-click on it has two honest answers: rows for
each frame it names, or the verbs of the reading itself -- the drop, the
expression field, negate-the-whole.

The pull each way: per-frame rows are what the hand expects when it right-clicks
a word it can see, but a reading is one sentence and its terms are not
separately clickable when the expression is `not (A and B)`. Offering per-frame
rows there would be the surface inventing a decomposition the math does not
have.

**Answer:**

**Settled, 9.3:**

Language first: staples, not anchors. A staple has no name; only the things it
attaches do.

THE PRIMARY OF A PROJECTION NEVER WARPS; EVERYTHING ELSE WARPS TO IT. Project
the object and time bends around it. Project the frame with the object on it and
the staples win. Project the frame with the object relative to it and the object
bends. Frame against frame is the same sentence again. Four cases, one rule.

Under it: a derived value is computed at projection time, an authored value is
recorded in the file, and where they disagree the PROJECTION decides which
yields, never a precedence rule in the model.

What derives. A staple on a time-bearing frame is when everything it attaches
happens; on several such frames, when they happen in each. One object stapled at
several points to ONE time-bearing frame has a duration: the distance between
the staples, a single difference at two and piecewise from three, one segment
per adjacent pair. An object with one staple to each of several time-bearing
frames has no computable duration and that is fine -- the graph still honestly
says this is connected to that via the other, without claiming a one-math
projection.

What is authored. Events and time-bearing frames carry a duration in the save
file. With one staple, or one per time-bearing frame, it projects the object onto
any attached frame, builds a one-math path between two frames that each single-
staple to it, and displays on an object stapled to nothing at all.

Where authored and derived disagree at n>1, the primary rule decides. At n>2 the
excess or shortfall is distributed along the object in proportion to each
piecewise part's share of the total computed duration. Between two frames whose
durations differ on the same basis, the frame projected as primary wins and
every other frame -- with whatever objects the projection carries -- warps to
that difference across the frame's full length, piecewise per segment from three
staples up, the tails continuing the last segment's projection. Frames of
DISSIMILAR basis are bridged by their staples into a one-math route: two staples
scale the non-primary continuously, three or more that disagree scale it
piecewise under the same tail rule.

TIME-BEARING IS DERIVED, NEVER DECLARED. A frame is time-bearing if it has a
time rule, or a basis with a time rule. It is answered at projection time like
every other projection question: no type, no flag, no special case. A frame has
a basis or an authored time rule, never both.

LOOPS. Staples terminal on the primary make a loop outright. Staples that are
non-terminal warp into a loop on the primary -- in Lines, the primary draws
straight and the others loop back over it.

NEIGHBOURHOOD IS A DISTANCE, AND THE DISTANCE IS AUTHORED. What is stapled here
means every node reachable within a distance, default one -- direct staples
only -- and the distance is a value the person sets on the surface, two or
eleven or whatever they ask for. Not a closure the query decides for them.

---

## 13. Are staples sized, or is a staple's point nullable?

Points have size -- 0, all, or any one-math measure (8.31). So the distance
between two sized points is not a scalar, and "duration is the distance between
the staples" does not say what it returns when either end is sized.

Don's sharper form of it: do we support SIZED STAPLES -- a staple carrying a
location and a magnitude per connected frame or object -- or does a staple have
a point where NULL is a valid answer, with null read as "all" in a wording way
but not a math way?

These are different models. A sized staple makes size a property of the
CONNECTION, so one object can be attached loosely to one frame and exactly to
another. A nullable point makes size a property of the POINT, and "all" is then
a reading a surface gives an absent value rather than a measure the math
carries.

What turns on it: whether a fuzzy distance is a fuzzy magnitude the engine
computes with, or whether fuzziness never enters the arithmetic at all and only
describes what the arithmetic declined to pin.

**Answer:**

---

## 14. Negative duration, and how a journey backwards is projected

An object whose end resolves EARLIER on a frame than its start. Don's own
reasoning, kept because the shape of the problem is in it:

> "So yes an idiot like me would author it that way, the correct data model is
> to build an inverse frame that runs the same time backwards. The event lives
> on that frame and only staples to the main frame at its terminal points.
> except no that is stupid because there is no special case to say wich frame
> the object lives on if two staples hit both ends on both frames, that is three
> points per staple, and no reason to prefer an intrpretation. So maybe maybe
> the idiot me is right and it dose have negative duration."

> "here I wonder about the projection of the event absent frame, how do we
> distinguish between an event that ocurs in the reverse order of time, and one
> that reverses negates time in its duration. Like imagine that in the year 1072
> there is a great blip, caused by the then raging wizarding war on a distant
> continent. The event created a pocket of negative time, like a congradualations
> everyone it is monday agin. but then that would be an event forcing math on a
> frame wich seems a bad idea."

> "Okay so lets go to the what is time dimention, here we could say wibbly
> wobbly ball, or we could say each observers personal experience of entropy, or
> probably some other bullshit too. Now frames (frames of reference) would
> represent one* observer / observation and or length of whatever weird yarn
> David Tenant used. So then here I guess we could say that negative time would
> constitued a sort of reverse entropy wich comes down in a way to determanism,
> if time the thing we are representing contains a random element then negative
> time is a thing that can exist and we could do like a time anti-time reactor
> end cause all sorts of causality problems and if not then it would mutualy
> anlialte in a perfect one to one fasion that means it is never projected and
> thus never renderd and thus might as well not exist for data simplicity sake.
> But I retain that nagging feeling that there is a valid interpretaion of
> negative time we should be able to project."

> "also none of this awnsers how we represent Anna got in a time machine primed
> it with a bag of doritos and whent back 20 years. an event Anna's time machine
> ride started in 2026 and ended in 2006. but then do we render that event as
> being 20 years long, there is a case where she spend 20 years in the box (I
> hope she packed more than one bag of doritos) and one where she spends 20
> minutes in the box (1 bag aught to be plenty) if we are looking at the
> calendar though her trip would take up an imense amount of space, and from her
> perspective she is still moving forward. which brings me back to two frames."

Three things are tangled here, and separating them may be most of the answer:
the SIGN of a duration between two staples; whether an object may impose math on
a frame it is merely attached to (the 1072 blip); and whether Anna's ride is one
object of negative extent or one object on its own forward frame stapled to wall
time at both ends, where the twenty minutes she experiences and the twenty years
the calendar spends are two frames' readings of one journey.

The sign reaches the arithmetic settled in 11 regardless: distributing a
shortfall proportionally across piecewise segments does something strange across
a sign change.

**Answer:**
