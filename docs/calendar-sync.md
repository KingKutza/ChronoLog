# Calendar and task synchronization

ChronoLog has two explicit, read-only web adapters. A sync never implies that
local edits were written back to a provider. Each successful pull is one
undoable document change, retains provider provenance, and advances its source
revision only after the incoming snapshot parses successfully.

## HTTPS ICS subscriptions

Open **Document → Sync web calendars**, enter a label and the secret HTTPS ICS
address published by Outlook, Google Calendar, Apple Calendar, or another
calendar service, then choose **Sync now** whenever you want to refresh it.

The launcher stores the full feed address in
`.chronolog-calendar-connections.json` under the ChronoLog user-data directory
with owner-only permissions. The portable document receives only an opaque
connection ID, source provenance, the acknowledged HTTP revision, and imported
calendar data. Feed requests accept ETag and Last-Modified validators, limit
redirects and response size, pin validated public DNS results, and reject local,
private, link-local, documentation, multicast, and reserved targets.

Forgetting a connection removes its secret address but intentionally leaves the
last imported snapshot in the document. Remote refreshes update stable imported
events in place. A disappeared remote record is removed, while an explicitly
stapled authored event remains and merely loses or updates its remote source
copy.

## Microsoft Outlook and To Do

Native Microsoft sync uses the [Microsoft identity platform device authorization
flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-device-code)
and Microsoft Graph v1.0. First create an Entra application registration:

1. Choose the account types the ChronoLog users of this installation need.
2. Under Authentication, enable the public-client/device-code flow.
3. Add delegated Microsoft Graph permissions `Calendars.Read` and
   `Tasks.ReadWrite`.
4. Copy the public Application (client) ID—not a client secret—into the
   Microsoft section of **Sync web calendars**.

The Microsoft To Do API currently names `Tasks.ReadWrite` as its least
privileged delegated permission even for delta/list access; ChronoLog makes only
GET requests to To Do and does not perform writes. See Microsoft's official
[calendar event API](https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0)
and [To Do task delta permissions](https://learn.microsoft.com/en-us/graph/api/todotask-delta?view=graph-rest-1.0).

As an alternative to entering the client ID in the UI, launch with
`CHRONOLOG_MICROSOFT_CLIENT_ID` set. The environment value takes precedence.
Device codes remain in server memory. Access and refresh tokens are stored in
`.chronolog-microsoft-credentials.json` in the user-data directory with
owner-only permissions and are deleted by **Disconnect**. Neither file is
served as a static asset or included in a `.chronolog` document.

Outlook pulls all accessible calendars for a fixed rolling window from January
1 two years before the current year through January 1 six years after it. To Do
pulls every accessible task list. Both are complete read-only snapshots with
stable Graph IDs, pagination limits, source-specific revisions, and explicit
removal handling. Write-back remains disabled until ChronoLog has provider-level
conflict resolution for organizer/attendee semantics and task revisions.

## Failure and offline behavior

The local document stays canonical. A failed authentication, timeout,
throttling response, invalid ICS body, unsafe feed target, or interrupted page
sequence leaves the previous provider snapshot and revision untouched. The UI
reports **Sync failed · local changes safe** and a later explicit sync retries
from that known state. **Synced** is shown only after the complete snapshot has
been parsed and committed locally.
