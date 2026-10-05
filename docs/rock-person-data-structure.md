# Rock Person Data Structure

This document describes Rock's person API representation without retaining personal record values in
source control. The live Chapel schema was inspected at `https://rock.chapel.org/api/v2/doc`; the
working read integration uses v1 and the `Authorization-Token` header. See
[Rock API access](rock-api-access.md).

## Identity and names

Rock people have a numeric ID, UUID GUID, and string ID key. GUID plus source identity is the stable
external key; numeric IDs are used for API requests. Alias IDs/GUIDs connect records that refer to a
person.

Name fields include first name, nickname, middle name, last name, title/suffix lookup IDs, full
name, and initials. The preferred display name may use the nickname rather than the legal first
name.

## Core person fields

- Contact: email, active email flag, email and communication preferences.
- Birth and age: day/month/year, derived birth date, age/classification/bracket, upcoming birthday,
  and related calculated values.
- Relationships: marital-status lookup ID, anniversary, primary family ID, child classification, and
  deceased status/date.
- Church connection: primary campus ID, connection-status lookup ID, record type/status/reason IDs,
  and photo ID.
- Audit and linkage: creation/modification timestamps, actor alias IDs, and foreign IDs/GUIDs/keys.

The API combines stored values, related-entity IDs, and calculated/display properties. A documented
field is not necessarily present or populated for every person. The v2 schema marks `isSystem` and
`gender` as required.

Other documented fields include giving references, signals, administrative notes, account-protection
flags, demographic lookups, and pronunciation overrides. Their existence does not authorize
importing them. The application uses the explicitly agreed field and attribute allowlists in Data
decisions.

## Addresses, phones, and households

The v2 person schema does not expose a reliable scalar home address or phone number. The v1
representation may include phone records and a formatted person-picker address, but formatted HTML
is not the canonical address source.

Use the person's primary family group to resolve Home-type group locations and their structured
`Location` records. Location fields include street components, city, state, country, postal code,
and optional coordinates. Mailing/mapped flags alone do not reliably distinguish Home from Previous
addresses.

Resolve household membership through group members and role metadata. Observed Adult/Child roles and
engagement-valued `FamilyStatus` attributes must not be treated as proof of marriage, divorce, or
birth. See [mapping discovery](phase-0-rock-discovery.md) for the structural findings.

## Extensible person attributes

Attributes are separate, site-specific definitions and values keyed by attribute key. The v2
attribute value bag contains:

- `value`: raw string value.
- `textValue` and `htmlValue`: formatted values.
- `condensedTextValue` and `condensedHtmlValue`: compact formatted values.

The v1 `loadAttributes` option accepts `simple` or `expanded`; `attributeKeys` limits loading to
specified keys. The inspected instance exposes hundreds of attributes, including potentially
sensitive HR, health, giving, and security values. Routine reads must use an explicit allowlist
rather than expand all attributes.

## Source references

- [Rock API Access Notes](rock-api-access.md)
- [Phase 0 mapping discovery](phase-0-rock-discovery.md)
- [Full original investigation on MP Drive][drive-investigation]

The original investigation includes a personal-record example and is retained on Drive and in an
ignored local copy under `docs/private/`. It is intentionally not part of this schema-only Git
document.

[drive-investigation]: https://drive.menloparking.com/documents/a6d58a8f-bbc8-4f06-ab75-7fd432f11cd6
