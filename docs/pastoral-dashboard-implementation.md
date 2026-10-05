# Pastoral Dashboard: Implementation Technologies

## Application baseline and conventions

Prosecho is a Rails 8.1.3.1, Ruby 3.4.7, PostgreSQL, Phlex 2, and Tailwind CSS 4 starter. Phase 0
now provides browser-managed Devise/Argon2id sign-in, campus-scoped users, a private foundation
dashboard, and Solid Queue-backed ActiveJob readiness scheduling and a tested GET-only Rock adapter.
It has no live synchronization or map library. Menlo UI is not installed. See
[Phase 0 foundations](phase-0-foundations.md) for the implemented boundary and unresolved data
decisions.

Follow the shared Rails guidance and existing Prosecho conventions:

- Use UUID primary keys for new Active Record models.
- Build views with Phlex 2 components in `app/components/` and `view_template`.
- Use Tailwind CSS 4 and Lucide; prefer a fitting Menlo UI component after reviewing its documented
  API and compatibility.
- Use Minitest and fixtures rather than FactoryBot. Add deterministic Lookbook previews. Tests stub
  external APIs and do not access production data.

## Rock integration boundary

Keep Rock API details out of controllers, jobs, and views:

- `Integrations::Rock::ReadClient` owns host validation, runtime authentication, timeouts, bounded
  pagination, and safe error translation. It exposes named GET-only person, campus,
  household-member, and home-location operations. Rock keys cannot enforce read-only access; this
  adapter enforces it in the application. It exposes no arbitrary paths or mutation verbs and does
  not follow redirects. Side-effectful GET actions are excluded. Authentication uses the verified v1
  `Authorization-Token` header. Additional named read operations, such as photos or lookups, require
  explicit implementation/tests.
- `Integrations::Rock::PersonMapper` converts API responses into internal person, household, and
  address values. Views consume those normalized values, not Rock JSON.

`Integrations::Rock::CampusImporter` fetches the complete, minimally selected catalog in stable ID
order before an authorized local transaction. It upserts by Rock ID, preserves UUIDs, parents, and
staff grants, and does not delete missing rows. The verified API has no campus-parent field. This
metadata import is separate from the gated future synchronization of person records.

Rock v2 `Person` exposes names, birth/age, email, status/campus IDs, family and alias references,
timestamps, and computed values. Addresses and phone numbers are related data, not dependable scalar
v2 Person fields. The working v1 person response can include phone numbers and a formatted address.
Implementation must resolve the structured primary home address from the appropriate Rock
location/household relationship; do not parse the formatted HTML address.

Use Rock GUID plus source-system identity as the stable external key; retain numeric Rock IDs for
requests. Map only approved data: preferred/name fields, birth date, connection status, campus,
structured home address/locality, photo reference, primary family, and household members/roles. Use
an explicit allowlist for site-specific attributes. Do not pull all expanded attributes by default.

Treat a custom `FamilyStatus` attribute as separate from marital status and family membership until
Chapel staff confirm its meaning and allowed values.

## Suggested local domain model

Phase 0 also persists a singleton, UUID-keyed `DataPolicy` record for admin retention/data-contract
decisions. The form supports drafts and complete agreed decisions; actor/time attribution belongs to
the server. A revision token, optimistic locking, and the administration transaction lock prevent
stale overwrites. YAML only seeds suggested source descriptions. Configuration reads the saved
policy and distinguishes data, directory, and map readiness.

Keep a read projection rather than mirroring the entire Rock schema:

- `PersonProfile`: Rock GUID/ID, names, birth date, connection status, campus, primary family
  reference, photo reference, and sync timestamps.
- `Household`: source family/group identity and its normalized membership.
- `HomeAddress`: structured home address, locality, and optional coordinates.
- `PersonSnapshot`: last successfully compared connection, address, and family values.
- `PersonChangeEvent`: event type, previous/current normalized values, `discovered_at`, source IDs,
  and sync-run reference.
- `RockSyncRun`: run state, timestamps, cursor/checkpoint, counts, and safe error details.

Index and enforce uniqueness for source plus Rock GUID. Keep event history immutable. Use typed
columns or constrained JSONB for snapshots, not an unbounded copy of all API responses.

## ActiveJob scheduling and sync

Define scheduled sync work as Rails ActiveJob jobs. ActiveJob is the job interface; production also
requires a persistent queue adapter and a recurring schedule runner. Phase 0 selects Solid Queue and
its recurring-task support, using the existing PostgreSQL database and a separate job role. The
first recurring job checks local readiness only; no live sync exists yet. Do not use the in-process
async adapter for production synchronization.

Start with a configurable four-hour cadence. Each run pages through the authorized population,
fetches only approved fields/relationships, maps the response, and compares it to the last
successful snapshot. Commit the updated projection and detected events atomically. First import
establishes a baseline and creates no change events. Incomplete runs do not infer deletions or
advance comparison state. Prevent overlapping runs, keep retries idempotent, and report stale syncs.

Compare connection-status ID/value, structured primary address/locality, and household member
IDs/roles. Record one event per meaningful difference: `connection_status_changed`,
`home_address_changed`, or `family_composition_changed`. Record spouse/member additions or removals
when the data supports them. Use factual labels instead of inferring marriage, divorce, or birth
from a changed membership alone.

Store `discovered_at` in UTC. The 1-week, 2-week, 30-day, and 90-day views are relative to
discovery, not an asserted source-event time. Failed runs do not alter history.

## Map and photo technology

Use a swappable OSM-derived map layer and a separate geocoding provider. Keep map UI and
provider-specific behavior behind an application adapter. Home addresses must not be sent to public
OSM Foundation services; use self-hosted OSM-derived tiles and local/self-hosted Nominatim, or an
approved provider with appropriate privacy terms. Cache coordinates locally and fall back to town or
campus aggregation if precise geocoding is unavailable.

Show the required OSM attribution. For any approved public tile use, follow its current HTTPS,
attribution, identifiable client, cache, and no-prefetch rules. Do not use public Nominatim for
scheduled bulk home-address geocoding.

Serve Rock images through a server-side, host-allowlisted image client/proxy. Do not send Rock
credentials to the browser; use private caching and initials fallbacks.

## Future integrations

Keep future systems separate under namespaces such as `Integrations::ChurchFunnels`. Define identity
mapping and data sharing per integration. Suggestions and communications are later capabilities and
do not belong in the first read-only release.

## References

- [Rock Person Data Structure](rock-person-data-structure.md)
- [Rock API Access Notes](rock-api-access.md)
- [Rails and Views Preferences for Agents][rails-guidance]
- [OSM tile policy][osm-tiles] and [Nominatim policy][nominatim]

[rails-guidance]: https://drive.menloparking.com/documents/a9984b46-c400-4dc0-8bd0-28c597cd9b33
[osm-tiles]: https://operations.osmfoundation.org/policies/tiles/
[nominatim]: https://operations.osmfoundation.org/policies/nominatim/
