# ADR-0004: The front door is CloudFront, with a CloudFront Function reading weights from a KeyValueStore

**Status:** Accepted (measured in Phase 0.5)

## Context

During the migration one endpoint must serve both systems and decide per request which one answers: the
legacy server, which must stay private, or API Gateway. Weights change during the migration and must be
reversible. There is no custom domain, and nothing should bill by the hour when idle.

## Decision

- One CloudFront distribution on its default `cloudfront.net` domain, with two origins: the legacy EC2 instance
  through a **VPC origin** (private subnet, no public address) and the API Gateway HTTP API.
- A viewer-request **CloudFront Function** (runtime `cloudfront-js-2.0`) reads the route's weight from a
  **KeyValueStore** and calls `cf.selectRequestOriginById()`. A hash of an `X-Client-Id` header keeps each client
  on one side; a token-gated override header forces a side for parity tests.
- Caching is off for the API; the origin request policy forwards every viewer header except `Host`
  (API Gateway rejects a foreign `Host`).
- The legacy server's security group admits CloudFront's managed prefix list
  (`com.amazonaws.global.cloudfront.origin-facing`). The VPC needs an internet gateway attached, though the
  private subnet has no route to it.
- Weights are runtime state, changed by scripts. Terraform ignores them.
- Every function is checked with `aws cloudfront test-function` before it is published to `LIVE`.

## Consequences

Measured in Phase 0.5:

| What | Result |
|---|---|
| VPC origin create / delete | 8m14s / 7m23s |
| Distribution create / delete | 3m00s / 3m14s |
| Whole edge spike up / down | 11m36s / 12m07s |
| Weight change to fully applied at one edge location | about 75 s (first edge hosts at about 35 s) |
| 50% split, 200 clients | 92 new, 108 legacy |
| Function compute utilisation | 8% |

- **Rollback takes about 90 seconds, not seconds.** No CloudFront mechanism is faster than a KeyValueStore update.
- **The edge flag alone cannot guarantee single-writer.** For about 40 seconds during a change, some edge hosts
  still route writes the old way. At freeze, SQL Server is also set read-only. The freeze window target is set
  in Phase 8; about 2 minutes is realistic.
- About 11-12 minutes of each `make up` and `make down` is CloudFront, overlapping Aurora and DMS.
- A function with a syntax error the runtime rejects is still published, and fails at the edge as
  `FunctionThrottledError`. Hence the `test-function` check.

## Alternatives considered

- **Application Load Balancer with weighted target groups:** weight changes in seconds and about 3 minutes to
  create. But HTTP-only without a domain, billed hourly ($0.0225/h), and a public load balancer in front of the
  legacy server. Kept as the fallback.
- **Lambda@Edge for routing:** changes origins at the origin-request stage. It is slower to deploy, adds more
  latency and costs more per request than a CloudFront Function, and the routing logic needs none of its extra power.
- **Weights in Terraform:** every change would be an apply; weights are runtime state.
