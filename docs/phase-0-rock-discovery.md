# Phase 0 Rock mapping discovery

Read-only API sample on 2026-09-30: four person records and four primary-family groups. No personal
values, raw responses, names, home addresses, coordinates, or credentials are stored here. This is
mapping evidence, not a representative statistical sample or a Chapel retention policy.

## Structured home address

`Person.PrimaryFamilyId` references the family group. Query `GroupLocations` for that group and
expand `Location` and `GroupLocationTypeValue`. The observed location types included `Home` and
`Previous`.

Do not select a home solely by `IsMappedLocation` or `IsMailingLocation`: one sample had a Previous
address with both flags true while its Home address had `IsMappedLocation=false`. Select by the
site's Home defined value, then use flags/order only within Home locations. Missing and multiple
plausible homes need explicit unknown/ambiguous handling rather than a guessed selection.

The structured `Location` contains `Street1`, `Street2`, `City`, `State`, `Country`, `PostalCode`,
and latitude/longitude. Existing Rock coordinates can be reused after validation; missing
coordinates can later use the selected self-hosted Nominatim service. A family without an address
was also observed.

## Household membership

Query `GroupMembers` by the primary-family group, expand `GroupRole`, and exclude archived/inactive
memberships. In the sample the family group type was 10, member status was 1, and role labels were
Adult or Child. Resolve these through site metadata instead of hard-coding IDs globally. Membership
changes establish facts about a household, not necessarily a birth, marriage, or divorce.

## FamilyStatus

The site's person attribute `FamilyStatus` has an empty description and string values including
`Nominally Involved` and `Inactive` in this sample. This is evidence of an engagement
classification, not civil/marital status. Exclude it from the initial attribute allowlist and do not
use it to infer life events.

## Decisions that records cannot establish

- A data-retention period, including backups and access logs.
- Which staff should see exact locations or relationship history.

These remain explicit readiness gates. The user selected self-hosted OSM-derived tiles and
Nominatim; their actual hosts remain to be provisioned.

## Read-only enforcement clarification

Rock does not provide read-only keys for this integration. Prosecho must enforce the read-only
boundary in its own adapter. Do not require or infer read-only key privileges from these samples.
Use only named, tested read operations; some Rock GET actions can have side effects and must not be
exposed.
