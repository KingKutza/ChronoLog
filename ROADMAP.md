# Roadmap

Ordered by priority.

1. **Journal + snapshot persistence.** The document file becomes a load-time
   snapshot; each committed edit appends one JSONL operation to
   `chronolog.journal`; loading replays the journal over the snapshot.
   Compaction rewrites the snapshot atomically on clean shutdown and on a
   user-settable period. Per-append sequence numbers replace the
   whole-document ETag CAS; the rolling recovery copy and the
   download/reload conflict flow are deleted with it — recovery becomes
   journal replay, conflicts become per-op collisions. Design settled, not
   yet built.
2. **Settings window** — theme, workspace defaults, and the
   snapshot-compaction period.
3. **Two-way calendar sync, Outlook first** — through ICS import/export
   semantics, never a provider API. Needs the per-op conflict resolution
   that the journal work provides.
4. **Dropdown z-order bug** — the new-item dropdown renders behind the
   control bars.
5. **Minimap tuning** — dots are too large and need too many events to
   register.
6. **Intimate lens legibility** — base-increment lines are invisible inside
   colored zones.
7. **Toolbar order** — swap "jump to today" and "reset lens".
8. **ToDo and Notes** — make both genuinely usable in the instrument, and
   give Notes an ICS path (VJOURNAL) so they round-trip like everything
   else.
9. **Control-bar aesthetics.**
10. **New logo** — plain text until a better mark earns the spot.
11. **More calendar subscriptions** — Google Calendar and other providers,
    each through its published ICS URL.
12. **Instance-to-instance WAN sync** — two ChronoLogs syncing across the
    web, built on the journal's per-op foundation.
13. **Mobile version** — Android first.
14. **Super-strategic band** — the lens beyond Strategic, which caps at 18
    months where this band would take over. Needs design.
15. **Field-level merge** — real merging on top of per-op sequencing. Needs
    design.
16. **Compiled native binaries** — the distribution end-state; the portable
    Node bundles are interim.
