# Durable local persistence and synchronization

Chronolog JSON (`chronolog/1`) is the canonical domain document. The document
contains authored frames, events, relations, patterns, overrides, imported
source components, and their provenance. View focus, lens settings, and theme
are browser-local preferences: they are never silently placed in a document or
synchronized with it.

The schema name versions the portable data model. Each acknowledged store write
also has an opaque resource revision, which versions the complete document at
that location without pretending to be a domain timestamp. Undo/redo snapshots
are bounded, in-memory editing aids; they are neither durable document data nor
part of synchronization. The ownership boundary is therefore:

| Data | Canonical owner | Portable | Synchronized |
| --- | --- | --- | --- |
| Frames, events, mappings, patterns, overrides, and source provenance | `chronolog/1` document | Yes | As one revision-guarded document |
| Focus, lens layout/settings, and theme | This browser profile | No | No |
| Undo/redo history and open inspector state | This running tab | No | No |
| Provider credentials and refresh tokens | Provider adapter/OS credential boundary | No | Never inside a document |

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

A network adapter may add these states without changing the local meanings:

- **Offline · local changes safe** — the canonical local document accepted the
  edit, but the provider is unreachable. A retry is pending and "Synced" must
  not be shown.
- **Syncing** — a provider exchange is in flight from a known local revision.
- **Synced** — the provider acknowledged that exact local revision and no newer
  local edit exists. It never means merely "Autosaved".
- **Sync failed · local changes safe** — the provider rejected or could not
  complete an exchange. The last provider cursor and the local document remain
  intact for an idempotent retry.

Offline editing always targets the canonical local document first. A provider
cursor advances only after its entire response has been parsed, validated, and
committed locally. Closing the application before local autosave completes can
still lose the in-memory edit; the pending/failed status and before-unload guard
are the visible warning. Reconnecting retries from the last acknowledged
provider cursor. It does not infer success, discard a local edit, or advance a
cursor after a partial response.

## Provider-neutral boundary

Domain code exchanges complete validated documents with a document transport
and imported calendar records with a calendar adapter. The minimum contracts
are deliberately small:

```text
DocumentTransport.read() -> { documentText, revision }
DocumentTransport.create(documentText) -> { revision }       // create-only
DocumentTransport.write(documentText, expectedRevision) -> { revision }

CalendarAdapter.pull(cursor?) -> { sources, nextCursor }
CalendarAdapter.push(changes, expectedRevision?) -> { acknowledgements, nextCursor }
```

Transport revisions and calendar cursors are opaque. An adapter maps its wire
format into `foreign.<provider>` source records and normal ChronoLog events; it
does not leak provider objects into frames, mappings, projections, or history.
Pull is committed as one undoable document change. Push is limited to records
that explicitly retain writable provider provenance; imported source records
remain read-only unless the user promotes or links them. Adapters must be safe
to retry and must surface authentication, throttling, validation, and revision
conflicts distinctly.

Interrupted pulls retain the previous cursor and source snapshot. Interrupted
pushes reconcile the provider's stable identifiers before retrying so that a
timeout cannot create duplicates. A provider conflict keeps the local authored
record and the new remote record as distinct versions until the user chooses a
resolution; silent last-write-wins is forbidden.

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

## Opt-in LAN transport

The bundled launcher can act as a small LAN document provider with
`chronolog --lan`. It remains bound to `127.0.0.1` unless that flag is present.
LAN mode binds to all interfaces and creates a high-entropy bearer token (or
uses an explicit `--lan-token`). The startup link places the token in a URL
fragment so it is not transmitted as part of the page request. The application
keeps it in session storage only and removes it from the visible URL.

Every `/api/` request in LAN mode requires that bearer token. Browser API calls
also require an Origin equal to the serving ChronoLog origin; no CORS permission
is granted to other origins. Command-line diagnostics can use the token without
an Origin header. This is an intentional simple LAN boundary, not encryption:
use trusted networks only. The server never falls back to unauthenticated
last-write-wins; its existing ETag CAS contract and recovery copy apply equally
to LAN clients.
