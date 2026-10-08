# Pastoral Dashboard: Security and Data Governance

Pastoral records, household relationships, home locations, and profile images are private
information. Treat the dashboard and its local projections as a restricted church system, not a
public directory.

## Identity and access

Phase 0 provides browser-managed Devise/Argon2id sign-in, campus grants, and explicit
photo/history/location permissions. This boundary must be enforced on each new pastoral endpoint
before loading live Rock data. Anonymous users must never access people, map, change, sync, or photo
endpoints. See [Phase 0 foundations](phase-0-foundations.md) for current verification and gates.

`/admin` offers first-account setup only while no accounts exist. A database lock serializes setup.
Once the first administrator exists, all account/campus administration is restricted to active,
unlocked administrators. Setup stays closed, including stale submissions. CSRF-protected forms
manage roles, permissions, campus grants, and local campus organization. Parent campuses do not
confer inherited access, and the last active administrator cannot be removed.

Person refresh controls and their start/resume/status endpoints require an active administrator.
Imports cover the complete campus catalog, including inactive campuses, and use the agreed data
allowlist rather than the initiating administrator's viewing grants. This is import authority only:
pastoral lists, details, portraits, and precise addresses still enforce each viewer's current campus
and sensitive-data permissions. Revoked administrator status or changed policy blocks the import.

Campus fetching is an explicit, CSRF-protected administrator action. Upstream requests are GET-only;
only local campus projections change. New campuses have no account grants. The full catalog is
validated before an atomic import, and refreshes preserve existing grants and local parent
organization.

Apply authorization consistently to:

- Person search, profile details, and photos.
- Exact home address and map pins.
- Change history, including prior addresses and household membership.
- Exports, if introduced later.

Use least privilege. A campus-restricted user sees only people and events in their authorized scope.
Staff access to family history and exact locations must be explicitly granted. Audit successful and
denied access to sensitive views without copying the sensitive values into the audit log.

## Read-only Rock access

The Rock integration is GET-only by default. The normal client exposes named read operations, not
arbitrary HTTP requests or mutation verbs. Syncs, retries, previews, and dashboard interactions
cannot create or modify Rock data.

Rock keys do not provide read-only privileges. Prosecho must enforce read-only operation in its
adapter regardless of the key's authority. Some Rock GET actions mutate data; allow only known read
endpoints, validate identifiers, and never follow redirects with credentials. There is no enabled
write adapter or writable-mode setting. Key-permission verification is not a readiness gate.

Keep the Rock REST key in runtime secret configuration and send it only to the configured Rock host
using the documented `Authorization-Token` header. Never put it in source control, browser requests,
URLs, logs, Lookbook data, screenshots, or normal development-container mounts. Use stubs and
synthetic data in local and test environments.

If writes are proposed later, implement a separate disabled-by-default adapter. Require server-side
authorization, a preview of the exact person and before/after values, and a separate explicit
confirmation tied to a short-lived operation and payload. Log actor, target, operation summary, and
result. Background jobs and integrations never infer permission to write.

## Data minimization and sensitive fields

Administrators record policy decisions at `/admin/data_policy` through CSRF-protected forms.
Retention durations, interpretation rules, allowed person fields, and exact custom attribute keys
are persisted with the recording actor. Confirmation attribution and time cannot be supplied by the
browser. Drafts remain unconfirmed, and concurrent/stale edits cannot silently replace decisions.
Policy changes create an ID-only audit event. This form records configuration; it does not purge
data or activate live synchronization.

Import only the fields required for the dashboard: names, birth date for age, campus, connection
status, structured primary home address/locality, photo reference, primary family, and household
member/role facts. Use an explicit allowlist for Rock's site-specific person attributes. Do not
import all expanded attributes by default; they may include HR, health, giving, security, or other
sensitive information that this dashboard does not need.

Keep current data separate from immutable change history. Previous and current addresses and family
relationships increase the sensitivity of event records. Set an approved retention period before the
first sync; apply it consistently to the database, backups, logs, exports, and caches. Encrypt
transport and storage according to deployment standards. Never record API response bodies,
addresses, phone numbers, or tokens in routine logs.

Do not place personal filter values in public URLs, analytics, or third-party telemetry. Show
discovery timestamps as observed times, not as exact source change times.

## Address and map privacy

Exact residential locations are particularly sensitive. Do not submit home addresses or precise
person coordinates to public OSM Foundation tile or geocoding services. Use self-hosted OSM-derived
tiles and local/self-hosted Nominatim, or a provider explicitly approved for confidential address
data. Keep geocoding behind a provider interface, cache its results, and avoid sending the same
address repeatedly.

Prefer clusters or heatmap aggregation at wide zoom. Reveal exact pins only to authorized users and
only when needed. Do not put an address into an external URL or map click target. If a location
cannot be geocoded privately, preserve town-level filtering and show town/campus aggregate locations
rather than a guessed home point.

Any use of public OSM tiles requires a privacy review and current compliance with its usage policy,
visible attribution, HTTPS, client identification, caching, and no-prefetch requirements. The public
Nominatim service is not an acceptable scheduled bulk geocoder for member addresses.

## Photo handling

Use Rock photos only through a server-side host-allowlisted fetch/proxy. Never expose the Rock key
or private upstream URL to browser JavaScript. Keep caches private and appropriately short-lived;
support invalidation and initials fallback. Do not use public image-CDN caching for member
portraits.

## Sync integrity and operations

Use application-enforced, named Rock read operations. Store sync-run status and safe error metadata.
Failed or incomplete runs do not advance person snapshots or infer deletions. Prevent overlapping
full syncs and make retries idempotent. Alert on repeated failures and stale data without putting
person details in alert payloads.

Authorize change-event access as strictly as current person access. Audit administrative actions and
access-policy changes. A history event records what the application observed, its source references,
and `discovered_at`; it does not claim when the underlying event actually happened.

## Security release gates

- Authentication and role/campus authorization exist and are tested before any live sync is enabled.
- Rock adapter tests prove the ordinary path only makes GET requests.
- Credentials are supplied only at runtime and are absent from test fixtures, browser payloads,
  logs, and development previews.
- Attribute allowlists and event retention are reviewed by Chapel data owners.
- Map/geocoder deployment does not transmit home addresses or exact coordinates to public OSM
  services.
- Backups, logs, photos, and change history have documented access and retention controls.
