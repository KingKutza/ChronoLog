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

## 11. Does the distance between two named anchors mean anything?

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

