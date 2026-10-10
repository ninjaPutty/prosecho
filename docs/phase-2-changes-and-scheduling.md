# Phase 2: scheduled refreshes and discovered changes

## Schedule

Administrators configure automatic all-campus refreshes at `/admin/sync_schedule`, linked from
administration. The daily GMT time defaults to **00:00**. The configuration starts disabled; saving
it enabled records the current administrator as the import operator.

Solid Queue checks the persisted schedule every minute. The dispatcher itself performs no Rock
requests; it queues the existing directory job when the selected GMT time is due. A refresh that
finishes after its scheduled time waits for the next day's occurrence. Existing work is never
overlapped. A failed all-campus run pauses automatic replacement until an administrator
reviews/retries it or completes a new manual refresh.

The operator must remain active, unlocked, and an administrator. Confirmed data decisions, the
runtime Rock key, and the campus catalog are required. Viewing grants do not restrict ingestion.
The campus catalog remains separately administered: fetch it when Rock adds campuses. Schedule
health, next due time, last check, and safe blocker codes appear in administration; a last successful
refresh older than two days is stale, including while another run is processing.

Disabling the schedule prevents new automatic imports but does not cancel an already running import.
The local process-only Rock key still needs to be supplied after a server/container restart.

## Baselines and comparison

The next successful publication establishes an initial comparison snapshot for each person and
creates no history events for that person. Existing Phase 1 profiles are not retroactively treated
as verified history baselines. Later completed imports compare connection status, the structured
primary Home address, and observed household member/role facts.

Profiles, snapshots, events, retention cleanup, and successful run status commit in the same database
transaction. An interrupted read or failed publication advances none of them. Events have a unique
run/GUID/type key and are immutable through normal model operations; successful publication and
checkpoint recovery remain idempotent. A policy revision establishes a new quiet baseline and hides
events recorded under older revisions.

Home-address comparisons exclude coordinates so geocoding changes cannot be mistaken for moves.
Unknown or ambiguous address transitions are described as availability changes, not proven moves.
The discovery timestamp is the UTC publication/comparison time, not Rock's modification time or a
claim about when a life event occurred.

## Household evidence

Newly observed members, changes to an observed member's role, and changes to the primary household
reference are factual differences. They are never labeled as births, marriage, divorce, or death.
The current Rock adapter returns scoped, incomplete rosters. Disappearing members are therefore
not reported as removals, and a later return of an already observed identity is not a new addition.
Only two explicitly complete, same-scope rosters could establish a removal. A changed catalog scope
rebaselines household comparison to avoid treating access/scope changes as family events.

## Changes view and permissions

The Changes tab requires the account's explicit history permission plus active campus access. It
supports discovery windows of 1 week, 2 weeks, 30 days, and 90 days, combined with the current
directory's campus, connection-status, age, town, and name filters. Filters live in the encrypted
session; public URLs contain pagination only. The optional discovery-window filter is also
available in the People view to find people with recent visible changes.

Every event requires current access to the person and to both its recorded current and previous
campus. Precise historical/current address details additionally require location permission.
Household member facts are redacted to the viewer's currently granted member campuses, and events
with no visible member difference or household-reference change are hidden. Draft/changed policy,
revoked permissions, inactive campuses, and departed people cannot expose stale history through
the feed. Access is audited with identifiers only.

Snapshots/events contain bounded normalized comparison values, not raw API responses or excluded
attributes. HTTP parameter, SQL-bind, and model-inspection filtering redact snapshot/event values.
Successful imports prune events older than the agreed history retention period. Expired profile
deletion removes its current snapshot but preserves retained event facts until their separate
history expiry; events without a currently visible profile are not displayed.

## Local operation

Run checks and migrations in the dev container. Development Puma manages the directory worker and
Solid Queue scheduler. Production continues to require its separate job role and runtime Rock key.
No production rollout or credential provisioning is implied by the local implementation.

Use deterministic Changes and schedule previews in Lookbook to inspect empty/populated states.
Regression tests use synthetic source records and never call Rock.

## Verification

The rebuilt development container passed `bin/check`: 185 tests, 1,210 assertions, no failures or
errors. Coverage includes quiet baselines, idempotent comparison, transactional rollback after event
insertion, source-policy/catalog changes, incomplete roster disappearance/return, complete-roster
removals, immutable events, history retention, address/member redaction, discovery filters, SQL-log
privacy, scheduling overlap/cadence/blockers, and configuration revision handling.

Populated/empty Changes previews, the 24-hour schedule preview, and `/ready` returned HTTP 200.
The recurring dispatcher is installed and the directory worker is online. The persisted schedule is
currently disabled; no full import was started by this implementation. There are no live comparison
snapshots/events yet. The next successful import creates the quiet baseline, and later successful
imports can create real discovered changes. Browser visual review and production rollout remain
unverified.
