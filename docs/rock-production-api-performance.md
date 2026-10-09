# Rock API timing from production

## Finding

The measured bottleneck is serial request fan-out and repeated HTTPS connection setup, not slow
bulk person queries or observed rate limiting. This is a bounded observation, not proof that the
Chapel installation has no custom rate limits.

This report records the original reader behavior. The subsequent
[implementation and production-origin comparison](rock-reader-optimization.md) demonstrate
persistent connections, bounded bulk family reads, and cross-page caching.

Measured on 2026-10-09 at approximately 21:44 UTC from the production web container, revision
`5ad0450`, on the same guest/network used by the sync worker. The job container was cross-checked
separately. Measurements were made while the real all-campus import was already running.

## Documentation and rate-limit evidence

The official [REST API guide][rest] describes token authentication, `$top`/`$skip` pagination,
and `$select`/`$expand` projections. It does not publish a numeric requests-per-second/minute quota,
a throttle budget, or a rate-limit-header contract. The developer [security page][security] and
[performance guidance][performance] likewise did not identify an API request-rate quota.

Some older developer-documentation slugs returned "Article was not found"; they are not evidence
for or against a limit. This is not an exhaustive statement about every Rock release or plugin.
An installation-specific IIS/reverse-proxy/CDN rule could exist independently of the public guide.

All 51 instrumented requests returned HTTP 200 with valid JSON. None returned HTTP 429 or any of
the checked rate-limit/Retry-After headers. Four additional job-role adapter reads succeeded.
The probe stopped at a bounded request/time budget and would have stopped on a 429 response;
it did not attempt to exhaust a quota or establish a maximum sustainable request rate.

The current import had no active error. Its retained previous failure was `invalid_json`, which
means the adapter received a successful 2xx HTTP response but could not parse it as JSON. No body
or content type was retained for that historical failure, so its cause cannot be determined from
the run record. It could have been an upstream/proxy/transient response; it is not evidence of 429
throttling. The earlier OData node-limit HTTP 400 was query-complexity enforcement, not request-rate
limiting.

## Method

- Used the existing named read-only adapter and the running import's authorized campus scope and
  confirmed field policy. Twelve campuses and the actual approved profile fields were selected;
  the custom attribute allowlist was empty.
- Used the runtime key already present in production. It was not retrieved to the client or printed.
- Recorded response status, content type, aggregate byte/row counts, selected rate headers, and
  monotonic timings. No names, addresses, source IDs, queries, response bodies, or tokens were
  output.
- Compared fresh HTTPS connections against a serial persistent connection to the same fixed host.
- Tested 50/250/500-person queries, small family-related reads, and a five-person normalized page.
- Rolled back the normalized-reader audit transaction. The diagnostic did not publish/stage people,
  enqueue a new import, or alter the existing checkpoint. No production code was changed.

Connection timing includes DNS/TCP/TLS setup. Waiting for response headers includes network RTT
and upstream processing, so it is not a direct measurement of Rock database execution time.
These are small samples, repeated reads can benefit from caches, and the running sync also
contributed traffic. Treat the numbers as a bottleneck diagnosis, not a capacity benchmark.

## Measurements

| Operation | Samples | Mean total |
| --- | ---: | ---: |
| One campus, fresh HTTPS connection | 5 | 205 ms |
| One campus, warm persistent connection | 4 | 57 ms |
| 50 people, approved fields | 2 | 282 ms |
| 250 people, approved fields | 2 | 475 ms |
| 500 people, approved fields | 2 | 634 ms |
| 250 people, minimum fields | 1 | 442 ms |
| Home locations, fresh connection | 3 | 193 ms |
| Household partition 1, fresh connection | 3 | 198 ms |
| Household partition 2, fresh connection | 3 | 200 ms |
| Home locations, warm connection | 2 | 57 ms |
| Household partition 1, warm connection | 3 | 62 ms |
| Household partition 2, warm connection | 3 | 62 ms |

The first home-location request on the persistent session included its cold connection cost
(185 ms); the warm home-location row above excludes that first request.

Connection setup consistently cost approximately 126–139 ms. The larger 250-person response
was about 124 KB, and 500 people about 248 KB. JSON parsing was below 1 ms in these measurements.
Reducing the selected fields nearly halved the 250-person payload but only changed total latency
from about 475 to 442 ms in this small sample.

The actual job container returned:

- Fresh campus request timings: 200, 189, and 196 ms.
- 250 people with the real selected fields: 485 ms, returning all 250 people.

That agrees with the web-container measurements; the result is not explained by testing from a
different developer workstation or a different container role.

## Why a nominal 250-person page takes minutes

The sampled 250 people referenced **220 distinct primary families**. For each family, the current
reader performs:

1. One Home location request.
2. One household request for the first eight campuses.
3. One household request for the remaining four campuses.

Thus the minimum request count for this page is:

```text
1 people query + 220 families * 3 related queries = 661 HTTP requests
```

This excludes any additional related pagination. The measured second household partition returned
zero members for each of the three sampled families, but those requests still cost around 200 ms
each. It cannot simply be removed: members in those campuses must still be included securely.

Using the sampled endpoint means, the page's serial network cost is approximately:

```text
0.475 + 220 * (0.193 + 0.198 + 0.200) = 130.5 seconds
```

The five-person normalized reader made **16 HTTP requests** and took **3.416 seconds**:

- Measured HTTP time: 3.191 seconds, or **93.4%** of the total.
- Other reader/database/normalization overhead: approximately 0.225 seconds.

During the investigation the real import had saved 43,250 rows across 173 pages over about
20,970 checkpoint-elapsed seconds: approximately **2.06 people/second**. That is consistent with
hundreds of ~200-ms serial requests per page, even though a bulk people request is under one second.
The elapsed run figure also includes any interruptions/retries and is not a pure network benchmark.

## Improvements, in recommended order

### 1. Reuse HTTPS connections

`ReadClient#perform_get` currently wraps every GET in a new `Net::HTTP.start`. The measured warm
campus request was 3.6 times faster than the fresh mean; family-related requests fell from about
193–200 ms to 57–62 ms. Roughly two-thirds of each small fresh request was connection setup.

The same 661-request page would have roughly 40 seconds of network cost at the sampled warm
latencies, versus 130 seconds today. That is an estimate, not a measured complete optimized page,
and reader/database overhead and transient reconnects remain. A 2–3x overall improvement is more
credible than promising that every page will be 3.6x faster.

Use a job/reader-scoped connection with lazy reconnect and bounded timeouts. Keep fixed-host
authentication and redirect rejection. Do not share a `Net::HTTP` connection concurrently between
threads. The reader should also retain its client across pages; it currently creates a local client
on each page when no injected client is supplied.

### 2. Reduce the number of related requests

Introduce named, tested bulk family-location/member reads if the Chapel API supports the required
projections. Batch family identities within the known OData complexity limits, retain exact campus
scope and approved fields, and fully paginate related results. This attacks the 660 related calls
rather than the single people call. Rock's own performance guide recommends pre-fetching rather
than repeated queries inside loops, although its RockContext advice concerns server-side .NET
contexts and must not be confused with client HTTP connection reuse.

### 3. Use a bounded run-scoped family cache

The current `addresses` and `households` caches reset at each `read_page`. A family appearing on
multiple pages is fetched again. A bounded run-scoped cache could avoid that repetition; its hit
rate needs measurement. Key/invalidate it by family, policy revision, campus scope, and
precise-field mode, and preserve authorization checks before returning cached data.

### 4. Consider small bounded concurrency after those changes

Only after reducing redundant work, measure a small request pool rather than unbounded parallel
fetches. Unknown site policy still matters. Preserve backpressure, each thread's own connection,
authorization/policy checks, retry/checkpoint behavior, and explicit handling of 429/Retry-After.

### 5. Record safe operational request metrics

Record endpoint category, status, duration, connection mode, request count per page, content type,
and relevant rate headers when a request fails. For invalid JSON, retain status/content type/byte
count, not the response body. These distinguish throttling, HTML/proxy responses, timeouts, and
slow request amplification without putting personal data or credentials in logs.

Increasing the person page size alone is not the main fix. The 500-person query is efficient, but
it still requires the per-family lookups; larger pages mainly reduce the already-cheap top-level
people calls and may increase the amount of work replayed after an interrupted page.

## Relevant implementation

- `lib/integrations/rock/read_client.rb`: `perform_get` opens a new connection for each request.
- `lib/integrations/rock/people_reader.rb`: serial family reads, campus partitions, per-page caches.
- `lib/directory/refresh.rb`: complete-page checkpoints and automatic transient retries.

[rest]: https://community.rockrms.com/developer/303---blast-off/the-rock-rest-api
[security]: https://community.rockrms.com/developer/303---blast-off/rock-security
[performance]: https://community.rockrms.com/developer/303---blast-off/performance-related-considerations
