# Phase 1 pastoral workspace and local projection

## Use the workspace

Open `/dashboard`, linked as Pastoral workspace from administration. The People view uses the saved
local projection with campus, connection-status, age, home-town, and name filters. Filters combine
and live in the encrypted session; names/towns are not exposed in URLs. Clear all resets them.
Pagination contains only page numbers.

Choosing a person opens approved details in the Turbo panel while keeping the filter state. Direct
profile URLs also work. Chapel-inspired teal, portrait or initial identity rows, freshness
summaries, and empty/error states prioritize people. Portrait failures fall back to initials.

Map and Changes navigation currently provides accurate setup views, not fake points/events. Private
map services and scheduled comparisons are later phases.

## Refresh and publication

Refresh people from Rock is a deliberate CSRF-protected POST. It creates a durable run and queues
PersonRefreshJob in the directory queue. The selected campus filter restricts the refresh; otherwise
the actor's active granted campuses are used. Administrator status does not bypass campus scope.

Person downloads default to 250 source rows per page. Set the server's process-only
`ROCK_PERSON_PAGE_SIZE=500` to use larger pages; supported sizes are 1–500. Address and household
queries remain separately bounded to 100 rows. Larger person pages reduce checkpoint overhead but
take longer to complete because related reads happen before the page commits. A changed page size
does not invalidate an ID checkpoint. Invalid configuration produces a specific failed-run diagnostic
before any person request.

The current published directory stays available while all pages are staged and validated. Successful
complete runs publish atomically by source-system/Rock GUID, preserving local UUIDs.
Failed/incomplete reads do not publish partial profiles or infer missing people. Access/policy
changes block publication. Only one queued/running run exists at once. Run state, progress,
completion counts, and safe error codes are stored. Each complete page commits its normalized
entries and next-page cursor in one transaction. New scans use the last observed numeric Rock ID
instead of a shifting offset: additions/removals earlier in the source cannot move the next page.
Legacy interrupted scans retain their saved offset for the first resumed page, then adopt an ID
cursor. This is an eventually consistent read, not an atomic snapshot of Rock; records changing
campus or fields behind the cursor are picked up by a later full refresh.

Sleep, worker exit, and transient Rock/DNS errors
preserve those checkpoints. Recovery resumes at the saved cursor, re-reading only an interrupted
page. A saved final-page marker allows interrupted publication to retry without reading Rock again.

The recovery job checks active runs every minute and replaces missing, failed, or stale-worker jobs.
Ready/scheduled jobs and live worker claims are retained. A PostgreSQL session lock prevents a
recovered worker from racing an older worker that wakes after sleep. The Resume/check refresh POST
uses the same dispatcher and existing run rather than creating duplicate work. Browser progress
updates every five seconds while the workspace is visible and reloads the directory on completion.

Transient read/configuration errors leave the run queued for retry with its staged pages intact.
Source-data and publication-validation failures retain completed staging and the cursor. The failed
page rolls back without replacing a saved version. The UI shows the failure stage, page, specific
reason, invalid field names, and a Rock record ID when available and still authorized. HTTP read
errors show the upstream status separately from network failures. Diagnostics contain no names,
addresses, credentials, upstream bodies, or exception messages.

Failed runs wait for an explicit **Retry from saved checkpoint**. Retry rechecks the original actor,
campus scope, and exact policy revision and cannot overlap another active run. A completed read
retries publication without downloading again. The last diagnostic context survives a retry for
investigation. Legacy failures whose staging was already deleted need a new refresh; their old page
count is not a usable checkpoint.

Policy/access failures invalidate staging and prevent retry; successful publication clears staging
atomically. No failed or incomplete run publishes partial profiles or infers absent people. Raw API
responses are not stored.

### Duplicate identity contract

Repeated Rock GUIDs within a page or across pages are expected, recoverable input. Staging contains
one normalized record per run/GUID; the latest observed occurrence replaces that staged value.
Repeated-entry counts, payload updates, and cursor advances commit together, so replaying an
interrupted page is safe. Pagination uses source rows rather than unique-person counts; duplicates
cannot cause early completion. A page that fails to advance its source ID cursor pauses with a
specific error instead of looping or silently dropping records. Invalid identities and records
outside the authorized population still fail visibly; they are never silently skipped.

## Projection access and retention

Every list, option, detail, and portrait endpoint rechecks current campus grants and the confirmed
policy revision. A changed/draft policy hides old cached rows until refreshed. Exact addresses and
photos require the corresponding account permissions. A guessed profile UUID cannot open another
campus's person.

Town-only refreshes clear a previous precise address when the Home identity is changed/unknown or
the policy revision differs. Household member campus IDs allow facts to be redacted to the viewer's
current scope. A scoped roster is still incomplete and does not establish life events.

Only complete successful runs mark absent records outside the population for their campus scope.
These are hidden, not immediately deleted. Later successful scoped refreshes remove inactive
profiles beyond the agreed profile-retention period. Backup/audit/history retention mechanisms are
separate operational work.

## Portrait boundary

Browsers use `/workspace/people/:id/photo`, never the Rock key. The authorized server fetches a
fixed GET image endpoint with a 160-pixel size bound and no redirects. JPEG/PNG/WebP/GIF are
allowed; SVG/HTML and images exceeding two megabytes are rejected. Responses are private/no-store. A
short server cache remains behind current policy/scope/photo authorization, not a public CDN.

## Runtime and verification

Development Puma starts Solid Queue through its `solid_queue` plugin. Directory workers follow the
web-server lifecycle and inherit its runtime Rock key, so queued refreshes do not depend on a
manually launched worker. The workspace shows a queued-work warning when no fresh worker
heartbeat covers the directory queue; stale registrations do not count as online workers.

The local server uses the explicitly approved process-only key without repository secrets or
OpenCode mounts. Recreating or restarting the container loses that runtime configuration; supply
the approved key to the server process again before requesting a refresh. Development Puma does
not persist the key. Production runs `ruby bin/jobs` separately from Puma, with a runtime Rock key
and the directory queue enabled, following the documented deployment workflow.

- Full checks after interruption recovery: 120 tests, 762 assertions, no failures/errors.
- Full checks after duplicate resilience, diagnostics, and larger pages: 144 tests, 958 assertions,
  no failures/errors. Live bounded requests returned the full requested 250 and 500 source rows;
  successive ID-cursor pages advanced without overlap. The failed-run preview and `/ready` returned
  HTTP 200. Browser visual/interaction review of the new retry state remains unverified.
- Standard Ruby, Tailwind, Solid Queue configuration, and eager loading passed.
- Tests cover visibility, session filters, combined queries, details/Turbo frames, portraits,
  policy/access changes, GUID upserts, failed pages, staging cleanup, address invalidation, and
  overlap guards, worker heartbeat/queue health, development-only managed workers, atomic checkpoints,
  interrupted reads/publication, stale-claim recovery, DNS errors, and the POST-to-reader workflow.
- Live synthetic previews and served CSS/Turbo/workspace assets returned 200. The local worker is
  running. Synthetic fixtures were not loaded into development/production; actual imports occur on
  user refresh.

See [the read pipeline](phase-1-person-pipeline.md) for projections and scope.
