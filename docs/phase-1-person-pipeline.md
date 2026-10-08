# Phase 1 person-read pipeline

The first Phase 1 step provides an in-memory, normalized read pipeline. It does not create a local
person projection, directory UI, change history, or a sync schedule. Rock remains read-only.

## Entry point

`Integrations::Rock::PeopleReader.new(actor: user).read_page(limit: 25, offset: 0)` returns an
immutable page of `PersonRecord` values, the possible next offset, policy revision, and observation
time. Pages are bounded to 1–500 people. Related address/member lists are bounded and paginated
separately.

Household campus filters are partitioned into groups of at most eight campuses to stay below Rock's
OData expression-node limit. Each partition is paginated independently before member identities are
combined, so expanding the import to all campuses does not truncate large household rosters.

For ordinary scoped reads, the actor must be active, unlocked, and have explicit active campus grants.
Administrator status alone grants no person access. The saved Data decisions must be confirmed and
valid before any
request. The actor, scope, sensitive permissions, and policy revision are checked again around
related requests and before returning a result. Revoked access or changed decisions discard the
page. Access is audited using actor/resource metadata without person payloads.

The administrative import supplies a persisted all-campus refresh run to the reader. That mode
requires the run's active administrator and confirmed policy, uses the captured campus catalog
(including inactive campuses), and reads all policy-approved fields regardless of the operator's
viewing grants or photo/location flags. Ordinary readers remain campus/permission scoped. Import
authorization is rechecked between requests and before publication; an administrator role alone
never expands the ordinary directory/detail/photo endpoints.

## Read contract

`PersonFields` maps the approved field groups to fixed Rock projections. The People query uses
campus-ID filters, stable numeric ID ordering, a bounded page, and excludes deceased/business
records. The Chapel person's record type ID is 1. The response is also checked against the
authorized population so an ignored or malformed upstream filter cannot expose an out-of-scope
record.

The reader supports a validated last-seen numeric person ID for keyset pagination. When that cursor
is supplied, the upstream skip offset is zero. Source-row counts determine whether another page is
needed even when multiple rows share a GUID. The mapper validates every row; the staged refresh
merges repeated identities rather than rejecting duplicates or silently skipping invalid records.

Rock IDs/GUIDs, campus identity, record classification, and source timestamps are system metadata.
Names, birth components, status, family/photo references, and related records are requested only for
the selected contract fields. Custom attributes are not expanded when the allowlist is empty;
otherwise only the approved exact keys are requested and retained.

Photo references additionally require the actor's photo permission. Precise addresses and
coordinates require location permission. Without it, address requests select only location identity
and city/state/country. Household reads are filtered by authorized member campuses and contain
identifiers/roles, not unapproved names, notes, or contact information.

## Normalization

`PersonMapper` produces stable lowercase GUIDs, local/source campus references, approved names and
preferred display name, complete birth date and calculated age, safe lookup values, optional photo
reference, address/household values, approved attributes, and issue codes. It does not trust Rock's
precomputed age. Partial, impossible, or future birth dates produce unknown age rather than a
guessed value. Missing/mismatched lookup labels remain unknown.

A valid person identity with no usable first name, last name, or approved nickname displays as
`Unnamed person (Rock #<id>)` and carries the `person_name_missing` issue. Missing source names do
not invalidate the person or block an entire publication. The projection also supplies this fallback
when publishing older retained checkpoints with blank names. Actual source-name fields remain
unknown, and a later refresh with a known name replaces the label and clears the issue.

Only active Home-type locations are eligible. Previous/mailing/mapped flags cannot substitute for a
Home location. Repeated references to the same location are deduplicated; multiple distinct Home
location IDs are ambiguous. Missing or ambiguous addresses have unset precise fields and an issue
code. No geocoding service is called.

Household output contains active, non-archived member GUIDs and role facts in authorized campuses.
It is marked `scope: authorized_campuses` and `complete: false`: a scoped roster is not proof of the
complete family. Membership does not imply birth, marriage, divorce, or death. Future history
comparisons must account for scope and completeness before inferring removals.

The mapping implements the conservative rules recorded in the agreed policy. Free-text policy
descriptions are documentation, not executable query/code instructions; alternative
source/interpretation strategies need explicit implementation and tests before use.

Normalized records do not contain raw API JSON or excluded values. Nested values are frozen, and
record/page inspection deliberately omits person values. The adapter exposes only named GET
operations, validates identifiers and projections, rejects redirects, and sanitizes errors.

## Rock v1 enum query finding

For `GroupMembers`, OData exposes `GroupMemberStatus` as `Edm.String`, while JSON serializes active
status as integer 1. The numeric predicate `eq 1` returns HTTP 400. Use the verified named predicate
`GroupMemberStatus eq 'Active'` and check the returned active/non-archived values when mapping.

## Verification

- Full container checks: 93 tests, 595 assertions, no failures/errors.
- Standard Ruby, Tailwind, and Rails eager loading passed.
- Synthetic JSON fixtures cover mapping, missing/ambiguous addresses, partial and invalid dates,
  unknown lookups, excluded fields/attributes, household scope, permissions, policy/access changes,
  and GET-only query construction.
- A bounded live read returned two scoped normalized records with known Home statuses. Only
  counts/status summaries were printed. No person values, raw payloads, or local person projections
  were persisted; Rock was not changed.

The [persisted pastoral workspace](phase-1-pastoral-workspace.md) consumes this contract for local
projections, refresh checkpoints, filtering, and explicit freshness/missing-data states.
