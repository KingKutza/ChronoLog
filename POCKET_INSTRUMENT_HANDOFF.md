# Pocket Instrument — Handoff
**Status:** r1, working, shipped under deadline 2026-08-06. Companion file: `pocket-instrument.html` (single file, no dependencies, offline after load).
**Lineage:** Field expedient descended from the Attention Instrument (canon at r2, `DESIGN_THESIS.md`, chat "Multi-scale calendar visualization design"). This is **not** the instrument. It is the first artifact in the project where ontology and renderer are actually separate layers, which makes it the instrument's proving ground, not its demo.
**Reading key (inherited):** RATIFIED is settled. PROVISIONAL ships but awaits a ruling. OPEN is undesigned.

---

## 1. Origin and diagnosis

Don's physical year-wall ran out of room; he folded it, patched it with printed month sheets, and — leaving for a week OOO — photographed it, because the photo beat Outlook mobile. Two failed responses preceded r1 and their failure modes are doctrine now:

1. **Transcription is forbidden.** An early build hand-transcribed the wall photo into an events array. Low fidelity, sacralized accidents of laminate inventory, replaced a photo with a worse photo. Dead.
2. **The defect is severance, not display.** The problem was never that the photo doesn't work; it's that a photo was *necessary*. Outlook holds the data with an unusable projection; the wall held the projection with no data feed. RATIFIED: **data from the system of record, projection as a setting, transcription abolished.** The renderer eats ICS; fidelity is Outlook's problem.

## 2. Constitutional rulings from this session (Chronolog material — feeds canon, not just this file)

This session reopened the Chronolog vs. Binary Grid substrate debate and produced rulings that belong in the main canon's next revision:

- **Mindset assignment (PROVISIONAL, leaning ratify):** Chronolog constitution in the ontology; KISS constitution in the renderer. Restates the July 30 ruling "one frame rendered well, all frames representable" as a layer assignment. Under this, the Binary Grid demotes from constitutional axiom (C3) to *one quantization setting of the wall-time lens*. Nothing is lost; the 128 becomes a saved game.
- **The fundamental object (PROVISIONAL):** not an n-dimensional space — a **directed metric multigraph**. Vertices, edges, optional edge lengths, quotients and gluings permitted, no isometry requirement. Line = path; circle = quotient; cut/unwrap = universal cover; variable time-flow = second measure on edges. **No acyclicity axiom** — Don's ruling, conceded: cycles permitted in data, detected in view (a schema that can't hold a deadlock can't show one).
- **The two-anchor bond = nontrivial holonomy (RATIFIED as insight):** gluing lines A and B at two anchor pairs with unequal separations creates a cycle whose arcs disagree; duration becomes path-dependent. This *is* the cross-timezone handshake: each party's sane rendering is their own arc; the disagreement is holonomy, rendered honestly, not a bug. Chronolog reached its handshake math in this session.
- **The embedding law (PROVISIONAL):** "settings-not-code" holds exactly as far as the view stays inside a canonical-embedding regime (path, cycle); crossing regimes is honest code. Consistency, faithfulness, and *renderability* are three separate requirements; Chronolog v1 died at the third.
- **Empirical inventory (from the wall photo):** every view Don demonstrably lives with daily is path or cycle — a cut or a wrap of one metric line. The tension flow (todos / float space, a poset/graph, no canonical embedding) was entirely **undrawn** on the wall. Open question standing: is that the poset admitting it doesn't belong on a time instrument, or the largest unserved use case in the design?

## 3. Architecture of r1

One HTML file, three layers, deliberately severable:

```
ICS text ──▶ parseICS() ──▶ normalized events ──▶ expand(events, window) ──▶ {isoDay → [instances]}
                                                                                    │
                                                              lens renderers ◀──────┘
                                                   (intimate | tactical | strategic[path|cycle-wrap])
```

**Normalized event:** `{uid, title, start{y,mo,d,h,mi,dateOnly}, end, dateOnly, dur(min), rrule, exdates:Set<iso>, recurrenceId, status}`. Naive local clock time throughout — TZID params are stripped, clock time taken as written. Adequate for one-timezone life; it is exactly the assumption holonomy support will have to remove (§6).

**expand()** projects events onto a day-indexed map within a window. Instances carry `{title, dateOnly, first, cancelled, h, mi, dur}` — clock time only on first day. Doctrine honored: RECURRENCE-ID overrides suppress the generated instance and stand as their own events (**actuals over defaults**); EXDATEs excluded; CANCELLED rendered struck-through, not hidden (a cancellation is a fact, not an absence).

**Lens state is a flat object** — `{lens, iDate, tStart, tDays, sFromY, sFromM, sSpan, sWrap, slashes, events}` — every view difference is a state difference. This is the settings-not-code claim made literal; guard it.

## 4. Lens ladder as implemented

| Lens | Straight view | Grain | Navigation | Notes |
|---|---|---|---|---|
| **Intimate** | one day, vertical hour rail | hour/minute | ‹day / date / day› / today | Waking focus 7–21 as *focus not domain* — rail auto-extends to cover actual claims. Timed events: position = clock, height = duration (min 26px). Overlaps: greedy lane assignment, equal split. All-day claims in a band above the rail. Live coral now-line when viewing today. |
| **Tactical** | 7 or 14 day columns | day, time-ordered within | ‹week / this week / week› | Past days **dimmed, not slashed** — ruling: the slash is a strategic-grain record mark; at tactical grain a spent day stays legible. |
| **Strategic** | the path: months as rows × 31 day columns | day | from-month + span (1–18) | Weekend banding, today outline, auto record-slashes on past days (toggle). **Cycle is a wrap option inside Strategic** (`sWrap`), per Don's ruling this session: same window quotiented by 7, Monday-start; useful as an option, never primary. |

Not implemented, on purpose: the roll law (these are fixed windows, not a lattice with pans), warp/skew within a lens, detents between the named lenses, amplitude, density, groups. r1 is **detents without the warp** — three straight views. That's the honest gap to the real instrument.

## 5. Parser status and test record

Tested in Node against synthetic Outlook-style exports before shipping (this session's transcript has the harness; recreate as `parser.js` + `test.js` by extracting the script block).

**Covered and verified:** line unfolding (CRLF + leading whitespace); VEVENT extraction; DTSTART/DTEND in DATE and DATE-TIME forms with or without TZID/Z; SUMMARY unescaping; all-day spans with exclusive DTEND (Aug 10 → DTEND Aug 15 renders Aug 10–14); multi-day timed spans; RRULE FREQ=WEEKLY with INTERVAL + BYDAY (the biweekly-Monday case), DAILY, MONTHLY (BYMONTHDAY or DTSTART's day), YEARLY; UNTIL and COUNT; EXDATE (comma lists); RECURRENCE-ID override replacing its generated instance; window clipping including first-occurrence-at-window-edge.

**Two bugs found and fixed in testing — do not reintroduce:** (1) first occurrence skipped when comparing loop day (midnight) against DTSTART (clock time) — compare at day granularity (`s0`); (2) recurring pushes not clipped to window start — `push()` takes the date and range-checks.

**Known parser gaps (OPEN, roughly priority order):**
- BYDAY with ordinals (`2MO` = second Monday) — parsed as plain `MO`; monthly-by-weekday patterns will land on the wrong day. Most likely real-world failure. Fix in `parseRRule` + MONTHLY branch.
- BYSETPOS, WKST, BYMONTH, RDATE — unhandled.
- COUNT semantics approximate: overrides/exdates increment `made`, matching common Outlook behavior but not audited against RFC 5545 edge cases.
- True timezone handling: TZID stripped everywhere. A meeting entered in another zone renders at its foreign clock time.
- VTIMEZONE blocks ignored (harmless — they contain no events).
- Multi-day *recurring* events emit first day only.

## 6. Bake mechanism

`Bake static copy` serializes `{events, settings}` as JSON into the `/*DATA*/…/*ENDDATA*/` markers via regex on `document.documentElement.outerHTML`, downloads as `pocket-wall-baked.html`. Baked copy boots from `EMBEDDED`, hides the feed panel, opens at the lens/anchors it was baked with. `</script` in payload is escaped. **If you rename or reformat the DATA markers, update the bake regex or baking silently breaks.** No localStorage anywhere — state lives in the file or in memory, nothing else. Keep it that way; it's what makes the artifact durable and inspectable.

## 7. Next steps (proposed order)

1. **Ordinal BYDAY** (`2MO`, `-1FR`) — the highest-probability real-Outlook breakage.
2. **Roll law, minimal form:** convert each lens's fixed window into a pan over the continuous day-line (swipe/drag = translate anchor; detents = named rests). This is the single biggest step from "three views" toward "one instrument."
3. **Test against a real Outlook export.** Synthetic coverage is good; Outlook's actual emissions (X- properties, folding habits, VTIMEZONE bulk, attendee noise) are the truth. Expect SUMMARY prefixes like "Canceled:" as text rather than STATUS in some paths.
4. **Refresh ergonomics:** a "re-feed" affordance on baked copies (unhide feed panel) so a stale bake updates in two actions.
5. **Amplitude, first dose:** even a single-bit `busy/tentative` → render-weight mapping would let the strategic path stop rendering all claims equal. TRANSP/X-MICROSOFT-CDO-BUSYSTATUS are already in the ICS, currently discarded.
6. **The tension flow decision** (§2, last bullet) — whether float/todo items enter this artifact at all. If yes, they are the first non-metric citizens and force the first hand-built layout, per the embedding law. Do not let them in casually.

## 8. Invariants — violate knowingly or not at all

- No transcription. If data enters this system by a human retyping a display, the design has failed again.
- Data layer never assumes one master timeline (schema-level Chronolog peerage), even while every shipped renderer is wall-time-first.
- Actuals over defaults; jitter is information; cancellations render, they don't vanish.
- Settings-not-code within an embedding regime; honest code at regime seams.
- Single file, zero dependencies, fully offline. The artifact must survive an airplane.
