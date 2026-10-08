# Pastoral Dashboard: First-Release Implementation Plan

## Outcome

Deliver a private, read-only pastoral dashboard with the campus, connection status, age, town, and
change-window filters; people and map views; Rock photos where available; and a reliable history of
discovered connection, address, and household changes. Rock remains the source of truth.
ChurchFunnels, communications, automated pastoral recommendations, and Rock writes are not in this
release.

## Phase 0 — Resolve access and data decisions

- Choose and test Prosecho's sign-in strategy. Add user identity and server-side authorization
  before live person data is available.
- Define role and campus boundaries for directory, change history, exact map pins, and profile
  images.
- Provide browser first-account setup at `/admin`, then administrator-only account and local campus
  management. No command-line administration is required.
- Confirm with Chapel data owners the primary home-address source, household membership/roles,
  intended meaning of any `FamilyStatus` attribute, allowed Rock attributes, and retention period.
- Record these decisions through the administrator's Data decisions page; incomplete work can be
  saved as a draft, and complete agreed choices are attributed and validated on the server.
- Configure the runtime-only Rock REST key and enforce reads in Prosecho's adapter; Rock keys cannot
  be relied on for read-only restrictions.
- Select a persistent ActiveJob queue adapter and recurring-task runner for production; evaluate
  Solid Queue within the actual deployment topology.
- Choose the private OSM-derived tile and geocoding approach. Do not send member addresses to public
  OSM services.

**Gate:** no live sync until authentication, authorization, data allowlist, and address/privacy
decisions are approved and tested.

**Phase 0 status:** sign-in, campus authorization, durable job scheduling, configuration checks, a
browser administration dashboard, a tested GET-only Rock adapter, and read-only mapping discovery
are implemented locally. The decision-entry page is implemented and the saved data decisions are
confirmed, with no data-policy blockers. Phase 0 is complete for local Phase 1 development.
Private-map service provisioning belongs to the map phase; production rollout and durable
runtime-secret provisioning remain operational work. Directory readiness is independent of map
hosting. See [Phase 0 foundations](phase-0-foundations.md) for verification and operation.

## Phase 1 — Read-only people directory

**Projection/workspace status:** local profiles, an administrator-only all-campus refresh,
session-backed filters, portrait proxy, and people/detail views are implemented. Viewing remains
campus-scoped. See
[pastoral workspace](phase-1-pastoral-workspace.md). Map and Changes currently show the real setup
state for their later-phase services/events.

**First-step status:** the scoped, policy-gated paginated reads and normalized person mapper are
implemented and verified. See [person-read pipeline](phase-1-person-pipeline.md). Local person
persistence and the filtered directory consume this pipeline in the workspace described above.

- Extend the Rock v1 GET-only client and add the normalized mapper. Use the verified
  `Authorization-Token` header and keep Rock JSON out of views.
- Resolve a structured primary home address and family-member relationships; do not parse formatted
  HTML from person-picker results.
- Create UUID-keyed local projections for person, household, address, and Rock sync state. Enforce
  uniqueness by source and Rock GUID.
- Import only the agreed profile allowlist. Do not retrieve all expanded person attributes.
- Build the authenticated people list, profile drawer, authorized Rock photo proxy, and shared
  filters for campus, connection status, age range, and town.
- Show data freshness and useful empty, stale, and error states.

**Acceptance:** authorized staff can filter and view the intended local projection; an anonymous
request is denied; no browser request contains the Rock credential; adapter tests prove read-only
behavior.

**Remaining Phase 1 verification:** complete and publish one all-campus import (the successful live
imports so far were campus-restricted), then walk through combined filters, profiles, portrait
fallbacks, and current campus/permission boundaries in the browser. Review desktop/mobile layouts,
keyboard interaction, and empty/stale/error states. Automated regressions cover these contracts;
live preview HTTP checks do not establish browser acceptance. Durable runtime-key provisioning and
production rollout remain operational follow-ups.

## Phase 2 — Scheduled sync and pastoral changes

- Implement ActiveJob sync jobs and the persistent recurring schedule.
- Add run records, pagination/checkpoints, idempotent retries, overlap prevention, and
  failure/staleness monitoring.
- Establish an initial baseline without emitting change events.
- Compare connection status, structured primary address, and household/member relationships for each
  Rock GUID.
- Persist immutable change events with previous/current normalized values, source references,
  sync-run ID, and UTC `discovered_at`.
- Add the 1-week, 2-week, 30-day, and 90-day discovery windows and the user-facing change feed.
- Use factual household-change language; do not infer marriage, divorce, or birth without supporting
  Rock data.

**Acceptance:** repeated runs produce no duplicate events; a failed/incomplete run does not advance
snapshots or infer deletions; first sync is quiet; time-window filters use discovery time and UI
copy does not imply exact event time.

## Phase 3 — Private map

- Set up the selected self-hosted or approved OSM-derived tile service and private geocoder.
- Geocode only approved structured primary addresses and cache results locally.
- Add pins and heatmap modes, clustering at wide zoom, person detail on selection, and town/campus
  aggregate fallback.
- Keep exact address pins limited to authorized users. Display OSM attribution and comply with the
  selected provider policy.

**Acceptance:** filters synchronize map and list results; no address or exact coordinate is sent to
public OSM endpoints; map remains usable when a person has no photo or geocoded address; attribution
is visible.

## Phase 4 — Review and first-release readiness

- Complete Minitest coverage with fixtures for identity mapping, unknown/missing fields,
  authorization, filters, sync retries, snapshots, deltas, event windows, photo access, and map
  privacy.
- Stub Rock, geocoder, and map services in tests; no test makes an external request or accesses
  production records.
- Add deterministic Lookbook previews for populated, empty, stale, error, desktop, and mobile
  states.
- Review accessibility, responsive behavior, secrets handling, logging, retention, backup access,
  and operational runbooks.
- Pilot with authorized staff and synthetic or approved test records before enabling a broad live
  sync.

**Definition of done:** all user-facing filters and views work from normalized local data; scheduled
change detection is idempotent and observable; security gates pass; all Rock operations remain
read-only; Chapel owners approve the field allowlist, retention, and map-provider configuration.

## Explicitly later

- Pastoral next-step suggestions, with explainable evidence and human review.
- ChurchFunnels or other integrations and communications.
- Rock writes, which require a separately approved feature, disabled-by-default write adapter,
  preview of exact changes, and explicit per-operation user confirmation.

## Project conventions

Use Rails 8.1 / Ruby 3.4, UUID primary keys, Phlex 2 in `app/components/`, Tailwind CSS 4, Lucide,
Minitest fixtures, and Lookbook previews. Use named Minitest filters (`-n`), not `-v`. Keep
production helper scripts under `bin/prod/`. Run app commands in the development container as
documented by Prosecho; never mount OpenCode secrets into ordinary development containers.

See the [implementation technologies](pastoral-dashboard-implementation.md),
[security and data governance](pastoral-dashboard-security.md), and
[user experience](pastoral-dashboard-ux.md) documents for detailed contracts.
