# Rulings wanted

Open questions, most blocking first. Each carries what is being asked, what
turns on it, the options, and a recommendation. Write under **Answer:** in
whatever form suits; an answered question moves to ISSUES.md or ROADMAP.md as a
ruling and leaves here.

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
