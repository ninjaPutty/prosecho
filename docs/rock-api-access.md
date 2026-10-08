# Rock API Access Notes

These notes record the working, read-only method used to inspect person data from the Rock instance
at `https://rock.chapel.org`. They contain no API key or person record values.

## API versions and documentation

- The v2 reference UI is `https://rock.chapel.org/api/v2/docs/index`.
- The v2 OpenAPI document is `https://rock.chapel.org/api/v2/doc`.
- The legacy v1 Swagger UI is `https://rock.chapel.org/api/docs`.
- Rock's [REST API guide][rock-rest-api] shows REST-key authentication with an `Authorization-Token`
  request header.

The v2 schema identifies read endpoints such as `GET /api/v2/models/people/{id}` and
`GET /api/v2/models/people/{id}/attributevalues`. Its search operation is a `POST` that performs a
search. V2 controllers have separate read permissions; Rock's [API security guide][rock-secure-api]
documents `Execute Read` and `Execute Unrestricted Read` access.

## Verified v1 person reads

The working v1 pattern was:

```http
GET /api/People/Search?name=Putty%20Putman&includeDetails=true&includeDeceased=false
Authorization-Token: <Rock REST key>
Accept: application/json
```

This returned a person-picker summary and an ID for the match. The person record, including phone
and person attributes, was then read with:

```http
GET /api/People/<person-id>?loadAttributes=expanded
Authorization-Token: <Rock REST key>
Accept: application/json
```

`loadAttributes` accepts `simple` or `expanded`. The person endpoint can also take `attributeKeys`
to restrict which attributes are returned. Use a specific person ID and requested attribute keys
where practical to avoid retrieving unneeded personal information.

Both requests are GET operations. The inspected workflow used GET only and did not modify Rock data.
Do not use person-creation, update, delete, or other write endpoints when inspecting records.

## Authentication attempts and outcomes

The Chapel v1 `GroupLocations` query returns HTTP 500 when projecting
`Location/Latitude,Location/Longitude`. The same scoped page succeeds with street, postal code,
town, and active-location fields. Home-address reads omit those coordinate projections so directory
refreshes can complete; coordinates remain unset pending a verified map-phase read path. Do not
exclude address rows merely because coordinates are unavailable.

Rock v1 enum predicates need attention: `GroupMemberStatus eq 1` fails with incompatible
`Edm.String`/`Edm.Int32` operand types, even though JSON returns active status as integer 1. The
verified read query uses `GroupMemberStatus eq 'Active'`. See
[Phase 1 pipeline](phase-1-person-pipeline.md) for the minimal scoped projections.

Use `Authorization-Token` for the legacy v1 REST-key flow demonstrated in Rock's guide. These
alternative forms did not yield a usable read in the checks documented here:

- `Authorization: Bearer <key>` on v2 person reads returned HTTP 500.
- `Authorization: ApiKey <key>` on v1/v2 reads returned HTTP 500.
- The v1 Swagger UI's advertised `api_key` query parameter returned HTTP 401 on the attempted person
  search.
- The v2 person GET and search requests tried before switching to v1 returned HTTP 500 with a
  generic error.

These results show why the exact Rock example matters: a REST key is sent in the
`Authorization-Token` header for the verified legacy workflow. They do not establish that v2 is
unavailable or explain its HTTP 500 responses. If v2 is needed, check the Rock server error log and
the People controller's v2 permissions before diagnosing further. Rock documents v2 controllers as
locked down by default; `Execute Read` is the read permission, with `Execute Unrestricted Read`
bypassing entity-level checks.

## Credential handling

Rock keys do not provide read-only restrictions for this integration. Enforce reads in Prosecho's
adapter regardless of the key's authority. The adapter exposes only named, tested GET endpoints,
validates IDs, bounds pagination, and never follows redirects. Do not expose arbitrary HTTP requests
or Rock GET actions that can mutate data. Future writes need a separate disabled-by-default adapter
and explicit confirmation of the user's exact intended change.

- Load the Rock REST key from the approved OpenCode secret only when making a Rock request.
- Send it only to `https://rock.chapel.org` in the `Authorization-Token` header.
- Never print, log, commit, or include the key in documentation or a URL.
- Do not use the key for a different Rock host.

[rock-rest-api]: https://community.rockrms.com/developer/303---blast-off/the-rock-rest-api
[rock-secure-api]:
  https://community.rockrms.com/documentation/supporting-rock/data/api/secure-the-api
