# Durable local persistence and synchronization

Chronolog JSON (`chronolog/1`) is the canonical domain document. The document
contains authored frames, events, relations, patterns, overrides, imported
source components, and their provenance. View focus, lens settings, and theme
are browser-local preferences: they are never silently placed in a document or
synchronized with it.

## Local ownership and recovery

The supported local launcher (#18) owns one workspace file in the user data
directory: `chronolog.chronolog`. A successful write is staged, flushed, and
atomically renamed. Before replacing an existing workspace, the launcher keeps
the immediately preceding valid document as `.chronolog-recovery.chronolog`.
An interrupted write therefore leaves either the last complete workspace or a
complete replacement, never a partially-written JSON file. The recovery copy is
available at `GET /api/document/recovery` for diagnosis and future recovery UI.

Chronolog validates JSON before it becomes a workspace document. A failed save
leaves the editor dirty and visibly reports failure; it never reports "saved".
The user may always download a portable `.chronolog` copy. Downloading a copy
does not clear the unsaved state.

## Revision and conflict contract

The local transport is provider-neutral: a document resource has an opaque
revision (currently a quoted SHA-256 ETag), `GET` returns it, and `PUT` sends it
as `If-Match`; a first write instead uses `If-None-Match: *`. A transport must reject a stale write with `409 Conflict` and
the current revision. It must not use silent last-write-wins.

When two windows edit the same local workspace, the second writer enters the
visible **Conflict** state. Its edits remain in memory and can be downloaded as
a conflict copy. The user can then reload the latest workspace; Chronolog never
silently merges or discards either version. This deterministic keep-both policy
is deliberately conservative until a field-level merge model is designed.

The status indicator has these exact meanings:

- **Autosaved** — a complete local workspace write acknowledged at the current
  revision; it does not claim cloud synchronization.
- **Autosave pending / Saving** — local edits exist and have not yet received
  that acknowledgement.
- **Save failed** — no save acknowledgement; the in-memory document remains
  dirty and export is available.
- **Conflict** — another writer changed the workspace; this window's edits are
  preserved locally and require download/reload resolution.

## Imports, export, migration, privacy

ICS remains imported source data under `foreign.ics`; authored overlays,
suppression records, and explicit replacements remain separate domain records.
Imports never overwrite matching identities automatically. Chronolog export is
a round-trip adapter; a `.chronolog` export is the complete canonical portable
document.

Legacy `chronolog.json` is read once by the launcher and migrated on the next
successful save to `chronolog.chronolog`. Existing browser file handles continue
to save only after the user grants them. No network endpoint, account, cloud
provider, credential, telemetry, or background upload is introduced by this
design. A future sync provider must implement the revision contract above and
make its account/security boundary explicit in its own UI.
