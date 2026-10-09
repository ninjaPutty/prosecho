# Rock reader performance implementation

## Changes

The reader now uses one adapter across pages, with a persistent HTTPS connection to the fixed
Chapel host. Named API GETs retain the existing TLS verification, open/read/write timeouts, and
redirect rejection. Net::HTTP can reconnect once for a dropped idle connection; HTTP error statuses
are not retried inside the adapter. Failed/invalid responses close the session before normal
checkpoint recovery. Owned connections are closed at the end of a refresh or campus catalog import.

Family lookups are prefetched in bounded batches rather than inside the person loop:

- Home locations: at most **12 families** per query.
- Household members: at most **4 families** per query and **8 campuses** per partition.
- Related pages remain bounded to 100 rows, ordered by `GroupId,Id`.
- Every batch/partition is fully paginated and routed by the explicitly selected `GroupId`.
- Unexpected family identities, malformed pages, or excessive per-family results raise sanitized
  read errors; incomplete results do not enter the cache.

The batch sizes were verified against production. Twelve-family Home queries succeeded; sixteen
and larger failed Rock's OData complexity validation. Four-family household queries succeeded
with both the eight-campus and four-campus partitions. The implementation does not relax campus
filters to bypass this limit or discard empty partitions.

Two reader-scoped LRU caches retain complete Home and household results across person pages.
Each is bounded to **1,024 families and 10,000 related rows**, including a family-count bound for
empty results. Oversized entries are used for the current page but not cached. Page-local references
remain valid even if later insertions evict an earlier family. Cached projections are immutable
private copies and their inspection output contains counts only.

Cache context includes actor identity, policy revision, campus scope, selected field groups, and
precise-location mode. Changed context clears both caches. Authorization/policy checks still run
before network batches and before returning a page, including when cached values satisfy all
related reads. The caches are in memory only and cleared when the reader closes; a restarted job
rebuilds them while resuming the durable source cursor.

Publication, change-history comparison, duplicate staging, and durable checkpoint behavior are
unchanged. No progressive publication or unbounded/concurrent request pool was added.

## Production-origin comparison

Temporary optimized classes were streamed into a separate production Rails runner, leaving the
running worker's classes unchanged. The existing authorized import scope/field policy was used.
Reader audit writes were rolled back; source responses, personal fields, credentials, and source
queries were never printed. These were bounded serial read-only probes, not a load test.

For the same 25-person source sample:

| Reader | HTTP requests | Total time |
| --- | ---: | ---: |
| Existing production reader | 70 | 14.472 s |
| Optimized reader, empty family cache | 15 | 1.516 s |
| Optimized reader, same sample cached | 1 | 0.116 s |

The initial comparison is approximately **9.5 times faster**. The repeat is a best-case cache-hit
measurement, not a claim that real consecutive pages have a 100% cache hit rate.

A 250-person read took **8.870 seconds and 118 requests** after the first 25 records' family
facts were cached. A separate 250-person read with an empty family cache took **8.554 seconds
and 106 requests**, including 7.706 seconds in HTTP. These samples used different cursor positions;
family density and related pagination influence the number of requests. Do not compare those
250-person results as a controlled cold-versus-warm pair.

See [the original production timing report](rock-production-api-performance.md) for baseline
connection costs and why the old 250-person page could require hundreds of serial requests.

## Verification

Regression coverage includes connection reuse/closure/reconnect, credential host restrictions,
minimal batch projections, complete partition pagination, unexpected group rejection, negative
caching, context invalidation, revoked grants, retry after incomplete batches, LRU/row bounds,
immutability, and routing despite cache eviction. Existing refresh/history publication regressions
continue to verify complete-page checkpoint and atomic publication behavior.
