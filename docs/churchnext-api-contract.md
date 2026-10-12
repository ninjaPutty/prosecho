# ChurchNext and Prosecho account-linking API contract

## Status and ownership

Prosecho's side is implemented locally. The ChurchNext functionality below is a specification for
future work, not an implemented or deployed ChurchNext feature. This contract connects ChurchNext
accounts to Prosecho's imported Rock person profiles, never Prosecho staff login accounts.

Linking establishes identity only. It confers no ChurchNext membership, leadership, pastoral-data,
reflection, or practice permissions. ChurchNext's account-sharing notice and eligibility checks must
make the administrative audience understandable and preserve existing contextual visibility rules.
Read ChurchNext's [domain architecture][domain] and [permissions guidance][permissions] before
implementing its side. No formation content is exchanged by this contract.

## Shared security and configuration

All requests are server-to-server over HTTPS. Never put integration credentials in browser code,
URLs, screenshots, logs, or source control. Provision separate random tokens of at least 32 bytes
through each application's approved runtime secret mechanism:

| Prosecho setting | Purpose |
| --- | --- |
| `CHURCHNEXT_API_TOKEN` | Authenticate ChurchNext submissions to Prosecho |
| `CHURCHNEXT_BASE_URL` | Approved ChurchNext HTTPS origin, without path/query/credentials |
| `CHURCHNEXT_CALLBACK_TOKEN` | Authenticate Prosecho callbacks and photo reads at ChurchNext |

ChurchNext holds the same inbound-submission token and validates the separate outbound token on
its two endpoints below. Do not reuse staff passwords or the Rock key. Supply a descriptive
`User-Agent`, `Authorization: Bearer <token>`, and appropriate content type. No endpoint follows
redirects with credentials. Credential provisioning and production activation are separate approvals.

## 1. ChurchNext submits an unlinked account

When a signed-in user reaches the ChurchNext homepage and their `prosecho_linked` flag is false,
ChurchNext's server submits their own stored account fields to:

```http
POST <prosecho-origin>/api/v1/churchnext/account_links
Authorization: Bearer <submission-token>
Content-Type: application/json
Accept: application/json
```

```json
{
  "church_next_user_id": "cn-101",
  "first_name": "Alex",
  "last_name": "Example",
  "email": "alex@example.test",
  "email_verified": true,
  "photo_available": true
}
```

The ChurchNext ID must be stable, unique, and opaque. It is a string of 1–128 characters: first
character alphanumeric, followed by letters, digits, `_`, `.`, `:`, or `-`. Names are nonblank strings
of at most 200 characters each. Email is a valid address of at most 254 bytes. `email_verified` must
be a JSON boolean representing ChurchNext's actual verification record, never a browser assertion.
`photo_available` is an optional JSON boolean, default false. Do not submit a photo URL or image bytes.
The payload is a flat object; unknown fields are rejected. Bodies are limited to 16 KiB.

Prosecho returns **200** for an established link:

```json
{"church_next_user_id":"cn-101","linked":true,"status":"linked"}
```

ChurchNext must verify that the returned ID is the submitted account and set `prosecho_linked=true`
only for `linked:true`. The response does not disclose directory names, emails, or candidate IDs.

**202** means accepted for manual review, including no plausible matches:

```json
{"church_next_user_id":"cn-101","linked":false,"status":"pending"}
```

Keep the flag false. Store a submission timestamp/status separately to avoid posting on every
homepage render while waiting for review. Debounce concurrent visits and use a background job rather
than blocking homepage rendering. Retrying a pending request refreshes suggestions, preserving all
rejections. Retrying a linked ID returns its existing link; changed profile fields do not reassign it.

Other responses contain `{"error":"<safe-code>"}`:

| HTTP status | Meaning and caller action |
| --- | --- |
| 401 | Invalid bearer credential; resolve configuration, do not retry rapidly |
| 413 | Body exceeds 16 KiB; fix payload |
| 415 | Content type must be `application/json` |
| 422 | Invalid JSON, unsupported fields, or invalid account values; fix payload |
| 429 | Limit exceeded: 60 requests per minute per source IP; back off |
| 503 | Integration unconfigured or confirmed email policy not ready; retry later |

Use exponential backoff with jitter for temporary failures. Rate limiting uses Prosecho's configured
cache; deployments with multiple web instances must use a shared rate-limit cache. ChurchNext should
also apply its own global submission budget. Do not infer a link from any error or timeout.

## 2. ChurchNext receives a confirmed link

Implement this authenticated ChurchNext endpoint:

```http
POST <churchnext-origin>/api/v1/prosecho/account_links
Authorization: Bearer <callback-token>
Content-Type: application/json
Accept: application/json
```

Prosecho sends the same event for automatic email links and administrator-approved links:

```json
{
  "event_id": "00000000-0000-4000-8000-000000000001",
  "church_next_user_id": "cn-101",
  "prosecho_person_id": "00000000-0000-4000-8000-000000000101",
  "linked": true
}
```

Validate the token and payload, find the account by its stored ID, and atomically store the mapping,
set `prosecho_linked=true`, and record `event_id`. Enforce one-to-one mapping. Never create an account
for an unknown ID or overwrite a conflicting person mapping. Persist before acknowledging. A repeat
of the same event/mapping must succeed without additional effects, including when the flag was
already set from the synchronous submission response. Use this **200** acknowledgement:

```json
{
  "event_id": "00000000-0000-4000-8000-000000000001",
  "church_next_user_id": "cn-101",
  "linked": true
}
```

Prosecho requires this matching acknowledgement; a generic 200, 202, or 204 is insufficient. A missing
account should return 404 and a conflicting mapping 409 without mutation. Prosecho's durable outbox
retries failed/ambiguous deliveries with the same event ID, starting after one minute and backing
off to at most an hour. Missing configuration defers delivery for five minutes. Repeated jobs cannot
send another callback after a recorded success. A recovery job scans due events each minute.

ChurchNext callback responses must be at most 16 KiB. Prosecho retains safe failure codes and keeps
the established local link while callback delivery is pending. Expose operational alerts for prolonged
failures; retrying is not a substitute for resolving an unknown account or configuration conflict.

## 3. ChurchNext serves a private account portrait

For submitted accounts with `photo_available:true`, implement:

```http
GET <churchnext-origin>/api/v1/prosecho/accounts/<church_next_user_id>/photo
Authorization: Bearer <callback-token>
```

Authenticate the integration and return the account's permitted portrait, or 404 when unavailable.
Decode the ID as a single path segment; explicitly support the documented punctuation rather than
treating dots in an account ID as a Rails response format.
Return a genuine raster image with `Content-Type` of `image/jpeg`, `image/png`, `image/webp`, or
`image/gif`, no redirects, and at most 2 MiB. Prefer a small portrait suitable for a 160-pixel display.
Do not accept arbitrary upstream URLs. Prosecho fetches only this fixed endpoint on its configured
ChurchNext origin and exposes a separate private/no-store administrator proxy. Portrait viewing
requires photo permission. The server cache expires after ten minutes and remains behind current
authorization; failed reads display initials. Never expose tokens or ChurchNext private URLs in HTML.

## Matching and operational prerequisites

Only a unique verified email can auto-link. Shared or unverified emails, name similarity, and existing
link conflicts require administrator review. Similarity uses approved first/last/nicknames; it never
uses facial recognition or an external AI service. A rejected pair remains rejected even if a later
submission matches that person's email. Established links cannot be reassigned by submitting new data.

Before enabling the integration, migrate Prosecho, ensure PostgreSQL supports the trusted `pg_trgm`
extension, approve email in Data decisions, refresh the directory, provision both tokens and the
approved ChurchNext origin, and run Prosecho workers plus its recurring delivery-recovery task.
The existing saved policy and production runtime are not changed automatically by this feature.

Test unique/duplicate/unverified emails, unknown identities, typo/nickname suggestions, remembered
rejections, repeated homepage visits, callback retries and duplicate events, conflicting mappings,
revoked reviewer permissions, and unavailable photos. Use synthetic accounts and stub HTTP in tests.

Unmatching, relinking, deletion propagation, and automatic expiry are not part of this version. Agree
on their retention/correction contract before implementing them; a removed local person projection
must not silently release a ChurchNext identity for reuse.

[domain]: https://drive.menloparking.com/documents/ef1d804e-e8d6-487c-9cf7-aa9add65ec90
[permissions]: https://drive.menloparking.com/documents/ba185083-505d-4e8e-9543-25aec5490f5b
