# Phase 0 foundations

## Implemented decisions

- Staff accounts are managed in the browser at `/admin`, not publicly registered. Devise
  authenticates Argon2id password hashes using `argon2`'s RFC 9106 low-memory profile. Passwords
  require 8–128 characters. There is no public reset, registration or remember-me endpoint. `/admin`
  offers one-time setup only while no accounts exist; that form creates and signs in the first
  administrator.
- After setup, `/admin` and all account/campus forms require an active, unlocked administrator.
  Setup submission is closed even if an old form remains open. A database lock prevents two
  concurrent setup submissions from creating two first accounts. Account edits cannot remove the
  last active administrator.
- The dashboard creates/edits accounts, resets passwords, changes roles and pastoral permissions,
  and assigns campus access. Fetch campuses from Rock imports names, Rock IDs, and active status
  through GET requests. Local edits can change names, optional parents, and active status; source
  IDs are fixed. Parent relationships organize campuses without inheriting access. Inactive campuses
  grant no pastoral access. None of these actions change Rock.
- Five failed attempts lock an account for 30 minutes. Sessions expire after 30 minutes of
  inactivity. A password change invalidates prior sessions. Disabled accounts and revoked campus
  grants lose access on their next request.
- The sign-in and foundation pages use small app-owned Phlex compositions. The shared Menlo UI
  README was not publicly accessible during this work; no shared component contract or private-gem
  access was assumed.
- Staff need explicit campus grants. Photos, change history, and precise locations are separate
  opt-in permissions. Administrator status is for access management and does not grant pastoral
  scope.
- The authenticated `/dashboard` is a foundation page only. It displays assigned campuses and no
  Rock records. Responses are private/no-store. Successful and denied dashboard access are audited
  using user/resource IDs, without PII.
- ActiveJob uses Solid Queue in development and production, with PostgreSQL as the single app/queue
  database. Tests normally use ActiveJob's test adapter; a separate test verifies persistence in
  Solid Queue. Queue schema follows upstream bigint identifiers; application models use UUIDs.
- A four-hour recurring `FoundationReadinessJob` records configuration blockers locally. It performs
  no network requests and never queues live sync work. The production job role runs `ruby bin/jobs`
  separately from Puma. Nothing has been deployed or activated on production.
- Self-hosted OSM-derived tiles and Nominatim are the selected map architecture. Hostnames and
  provisioned services are pending. Existing valid Rock coordinates should be preferred before
  geocoding an address again.

See [Rock mapping discovery](phase-0-rock-discovery.md) for the limited sample's address and
household findings. Routine imports will not expand all attributes; the initial custom-attribute
allowlist is empty.

## Local operation

Run commands inside the Prosecho development container with the local database profile active.
Install the frozen bundle and prepare the local database:

```sh
bundle install
bin/rails db:prepare
bin/check
ruby bin/jobs check
bin/rails pastoral:readiness
```

Run `ruby bin/jobs` in a separate process when exercising the local durable queue. The readiness job
remains network-free even if a Rock key exists in the process environment. No development-container
credential mounts were added.

## Browser account administration

1. Visit `/admin`. If no accounts exist, enter an email, password, and password confirmation to
   create the first administrator. The form never lets visitors choose the first account's role or
   campus grants.
2. After setup, sign in to access the account administration dashboard. Accounts with the
   administrator role land here after sign-in, even without pastoral campus access.
3. Click **Fetch campuses from Rock** to load the catalog without manual entry. Optional parent
   relationships describe the local organization only.
4. Use Create account and Edit account to set staff email/password, active status, role, campus
   assignments, and explicit photo/history/location access. Leaving the edit form's password blank
   preserves the current password.
5. Deactivate accounts or campuses to remove access without deleting records. Create another active
   administrator before demoting/deactivating the last one.

Forms require CSRF tokens, use private/no-store responses, and do not render passwords back into
fields. Administration access and account/campus changes are audited using actor/resource IDs. CLI
maintenance tasks remain optional; they are not required for ordinary account or campus
administration.

If a setup form's session expires or its cookie is lost, the submission is rejected without creating
an account. The page rotates the session and displays a fresh setup form with a clear message; enter
the account details again. This does not bypass CSRF or automatically retry submitted passwords. If
setup has already completed, an unverified submission cannot reopen it.

## Campus catalog import

The administrator-only, CSRF-protected fetch action reads `Id`, `Name`, and `IsActive` in stable ID
order. It validates all pages before one local transaction upserts records by Rock ID. Failed pages
or invalid/duplicate records apply no partial changes. Repeating the import reports added, updated,
and unchanged counts.

Refreshes retain local UUIDs, parent organization, and staff grants. Missing source rows do not
delete local records or infer inactivity. New campuses grant no account access. Names and active
status are refreshed from Rock. The manual creation route/button was replaced by fetching; source
Rock IDs are not editable.

The verified Chapel campus API is a flat catalog with no parent-campus field. Local parents remain
optional and are never inferred from unrelated Rock groups.

The user explicitly authorized a process-only local integration profile on 2026-10-04. The saved
Rock key was supplied through stdin to the Prosecho server runtime, not stored in the repository,
image, or Docker's configured environment. No OpenCode credential files were mounted. Trusted server
code and its children can use that key, whose authority is restricted by the application's named
GET-only adapter. A newly started server without key injection requires `ROCK_API_KEY` again.

## Readiness and unresolved gates

Enter retention and data-contract decisions at `/admin/data_policy`, linked as **Data decisions** on
the administration dashboard. Saved `DataPolicy` records are authoritative; YAML source descriptions
are only initial form suggestions. Mapping evidence is not automatically marked as organizational
approval. The saved decisions are now confirmed and the data-policy blocker list is empty. Phase 0
is complete for local Phase 1 development. Private tile/geocoder service provisioning remains
map-phase work; production deployment and durable runtime secret provisioning remain operational
work. Individual policy values live in the application database and are not exported into source
control.

The form covers retention for profiles after leaving the synchronized population, change history,
access/audit logs, and backups. It records address and household sources and
ambiguity/interpretation rules, FamilyStatus meaning, the initial person-field allowlist, and
optional exact custom attribute keys. Rock IDs/GUIDs and synchronization timestamps remain system
metadata.

You may save incomplete drafts. Recording agreed decisions requires positive whole-day retention
periods, complete source/handling descriptions, and the minimum identification/campus fields. The
server records the administrator and confirmation time. Reverting to draft clears confirmation and
blocks data readiness. Revision checks prevent stale browser forms from overwriting another
administrator's changes. Policy edits are audited using actor/resource IDs.

New forms start with editable retention suggestions: 90 days for profiles after leaving the
population, 365 days for change history, 90 days for audit logs, and 30 days for backups. Suggested
rules leave missing/ambiguous Home addresses unknown and treat scoped household membership as
incomplete facts, not evidence of life events. All supported profile fields start selected; custom
attributes start empty. Draft forms suggest values for unanswered retention/source/handling fields
without changing saved choices or saving on page load. Review, edit, and save the form to adopt them;
confirmation remains an explicit administrator choice.

Data-policy readiness, directory readiness (data decisions plus a runtime Rock connection), and map
readiness are evaluated separately. Missing map hosts do not block directory readiness. No saved
decision enables live synchronization, writes Rock, deletes records, or configures a backup
provider; later jobs and integrations must consume and enforce this policy.

The runtime interface accepts `ROCK_API_KEY` and `ROCK_BASE_URL` (the latter must be exactly
`https://rock.chapel.org`). Private map endpoint configuration uses `PASTORAL_GEOCODER_URL` and
`PASTORAL_TILE_URL`; endpoints must be HTTPS, have no embedded credentials, and match approved
hostnames. Public OSM hosts are rejected. These values are not read from OpenCode secrets by the
app.

Rock keys cannot enforce read-only access. Prosecho's `Integrations::Rock::ReadClient` enforces it:
named GET-only person, campus, household-member, and home-location operations; fixed host; validated
IDs and bounded pagination; no arbitrary request paths or mutation verbs. It never follows redirects
and sanitizes upstream failures. GET actions with side effects are not exposed. There is no
permission switch that enables writes.

Phase 0 has no live sync implementation. `live_sync_enabled?` remains false, including when
`ROCK_SYNC_ENABLED=true` is supplied. Phase 1 must build the directory/mapper around this adapter
and enforce reviewed data readiness before fetching live records. Read-only key evidence is not a
readiness gate. Current deployment credential tooling still accepts only its existing four
deployment secrets; runtime integration-key injection is not configured yet.

Schema dumps are stored in `config/schema.rb` per MP guidance. Production migrations, runtime-key
provisioning, and service starts require the existing explicit deployment workflow; none were
performed in this work.

## Verification — 2026-09-30

- Fresh Prosecho development-container image on macOS/OrbStack (Linux arm64): frozen bundle install,
  `bin/check`, and `ruby bin/jobs check` passed. The full suite completed 47 tests and 256
  assertions with no failures or errors.
- Covered actual sign-in/sign-out, Argon2id hash verification, account lockout, CSRF rejection,
  session expiry/password revocation, campus access/revocation, audited account provisioning, and
  readiness gates.
- ActiveJob enqueued a readiness job into PostgreSQL; a bounded local `ruby bin/jobs` worker
  consumed it and recorded blocked readiness.
- Tailwind build and Rails eager-load check passed. Phlex forms render via integration tests;
  browser visual/accessibility review is still pending.
- Built the production image on arm64 and verified native Argon2id hash/verify with networking
  disabled. The packaged job entrypoint exists. This is not a deployment or a production worker
  validation claim.

The pre-existing running development container lacks `psql`. A fresh one-off Compose container from
the repository's dev image ran the complete checks; the running app container was not replaced.
Rebuild that container when ready to use its updated toolchain for the normal development workflow.

## Verification — 2026-10-01

- Browser setup and administration changes passed the full container check: 59 tests, 347
  assertions, no failures/errors. Standard Ruby, Solid Queue configuration validation, Tailwind
  build, and Rails eager loading passed.
- Integration tests cover first-account setup, closed/stale setup submissions, invalid setup,
  administrator-only access, CSRF, account/campus changes, atomic grant validation,
  last-administrator protection, and campus cycles.
- Stubbed adapter tests cover named GET requests, runtime authentication, invalid IDs/pagination, no
  writable-mode switch, fixed host, redirect rejection, and sanitized errors. No live Rock requests
  were made by these tests.
- The live development `/admin` page returned HTTP 200 with the first-account setup form and
  password confirmation after restarting its stale route table. No administrator account was created
  during this read-only page check.
- Browser visual/accessibility review and production deployment remain pending.

## Setup CSRF recovery — 2026-10-03

The reported exception was reproduced using a form token after losing its session cookie. Added
CSRF-enabled tests for the full `localhost:3100` browser GET/form-submit flow, stale-session
recovery and resubmission, and closed setup. The live stale-session check returned a fresh form, and
the retry passed CSRF validation. Live checks used invalid account details and created no account.
The full container check passed: 62 tests, 379 assertions, no failures/errors.

## Campus fetch verification — 2026-10-04

Full checks passed: 71 tests, 442 assertions, no failures/errors; Standard Ruby, Tailwind, and Rails
eager loading passed. Integration tests cover authenticated CSRF-protected import and errors.
Service tests cover pagination, repeated refreshes, full-source validation, and grant/parent
preservation.

The live read-only adapter returned 12 Rock campuses (10 active, 2 inactive) without changing local
records or Rock. The live development preview renders the fetch button and no manual-add button.
Signed-in import behavior is covered by integration tests; users can now trigger the real import
from `/admin`.

## Data-decision page verification — 2026-10-05

Full container checks passed: 80 tests, 508 assertions, no failures/errors; Standard Ruby, Tailwind,
and eager loading passed. Tests cover draft and confirmed decisions, retention/allowlist validation,
server-owned attribution, CSRF and administrator access, stale edits, draft reversion, singleton
storage, and independent directory/map readiness. The live development preview renders the four
retention inputs and Save decisions control. No actual policy choices were made on behalf of the
user during these checks.
