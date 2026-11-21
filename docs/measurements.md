# Measurements

Every number the project claims, recorded on the day it was measured, with how it was taken. Nothing here is
estimated or rounded to look tidy; estimates are labelled as such. Later phases add rows; earlier rows are not
rewritten.

## Phase 0: proving the setup (2026-11-16 to 2026-11-21)

| Measurement | Value | How | Evidence |
|---|---|---|---|
| `net48` Web API 2 project built on macOS (Apple Silicon) | 0 warnings, 0 errors | `dotnet build`, .NET SDK 10.0.400, after a stub for the missing web targets ([ADR-0002](adr/0002-real-net-framework-legacy.md)) | spike, PR #1 |
| SQL Server 2019 install on GitHub's `windows-2022` runner | 3m17s and 3m54s | Step duration, two runs | [43924180581](https://github.com/sunnypatel2048/purchasedesk-to-serverless/actions/runs/43924180581), [43925410342](https://github.com/sunnypatel2048/purchasedesk-to-serverless/actions/runs/43925410342) |
| SQL Server 2019 CU32 in Docker on Apple Silicon (Rosetta): clean cycles | 3 of 3 passed; ready in 12 s, 6 s, 6 s | Wipe, start, load, check, three times in a row | spike, PR #3 ([ADR-0003](adr/0003-sql-server-2019-cu32-everywhere.md)) |
| Same container under a burst | 20,000 procedure calls in about 2 s, all correct; no restart, no OOM; 878 MiB | One T-SQL loop; `docker inspect`, `docker stats` | spike, PR #3 |
| CloudFront VPC origin, create / delete | 8m14s / 7m23s | Terraform "complete after" | spike, PR #4 ([ADR-0004](adr/0004-cloudfront-function-front-door.md)) |
| CloudFront distribution, create / delete | 3m00s / 3m14s | Terraform "complete after" | spike, PR #4 |
| Whole edge spike, `up` / `down` | 11m36s / 12m07s | Script timer | spike, PR #4 |
| KeyValueStore weight change, 0 to 100, fully applied at one edge location | about 75 s (first edge hosts at about 35 s) | 50 requests every 10 s from one client until all reached the new origin; then 650 in a row did | spike, PR #4 |
| 50% weight, 200 distinct client ids | 92 new, 108 legacy | Split test | spike, PR #4 |
| CloudFront Function compute utilisation | 8% | `aws cloudfront test-function` | spike, PR #4 |
| Leftovers after the edge spike's teardown | 0 of 11 resource checks | Leftovers script by tag and name | spike, PR #4 |

## Phase 1: the legacy application (2026-11-21)

| Measurement | Value | How | Evidence |
|---|---|---|---|
| Seed data | 50 suppliers, 2,000 orders, 8,109 lines, 3,482 audit rows; 288 half-cent lines, 403 NULL `RequiredBy` | `checks/seed-facts.sql`, pinned in `seed-expected.txt` | [seed-expected.txt](../legacy/database/seed-expected.txt) |
| Seed determinism, Docker on macOS vs Windows runner | Identical on all 19 facts, including 4 SHA-256 fingerprints | Same check in both places | [44932112917](https://github.com/sunnypatel2048/purchasedesk-to-serverless/actions/runs/44932112917) |
| Local load from nothing (schema, seed, procedures) | about 21 s | `dev.sh reset` | local |
| Stored procedure tests | 40 of 40 | `checks/procedure-tests.sql`, each case rolled back | [44936669346](https://github.com/sunnypatel2048/purchasedesk-to-serverless/actions/runs/44936669346) |
| Mutation check on the procedure tests | 3 failures with truncating `ROUND`, 0 restored | Deliberately broken procedure | local |
| API and export tests | 17 of 17 (11 smoke, 6 export) | `dotnet test` on `windows-2022` | [44936669346](https://github.com/sunnypatel2048/purchasedesk-to-serverless/actions/runs/44936669346) |
| Golden files | 40 recorded (38 API responses, 2 export files); 40 of 40 match | Characterization test on a fresh database ([ADR-0009](adr/0009-golden-files-define-equivalent.md)) | [44936669346](https://github.com/sunnypatel2048/purchasedesk-to-serverless/actions/runs/44936669346) |
| Legacy CI test job duration | 4m30s to 4m45s | Job duration, several runs | runs above |
| T-SQL to retire | 249 lines | Non-blank, non-comment lines in `legacy/database/procedures/` | `legacy-v1` |
| Legacy C# | about 800 lines | Non-blank, non-comment lines in `PurchaseDesk.Web` and `PurchaseDesk.Export` | `legacy-v1` |

## Behaviour differences caught

| Found | Behaviour | Legacy | New system |
|---|---|---|---|
| Phase 1.6 | Order line Sku longer than 40 characters | 500 "An error has occurred." (SQL Server 2629 on CU32; deadlock 1205 on RTM) | 400 (planned) |

## List prices checked (not measurements)

AWS Price List API, us-east-1, 2026-11-21: Windows `t3.medium` $0.060/h; gp3 $0.08/GB-month; Aurora Serverless v2
PostgreSQL $0.12 per capacity-unit hour (I/O-Optimized $0.16); DMS `t3.small` single-AZ $0.0372/h; interface endpoint
$0.01/h per zone; EBS snapshot $0.05/GB-month; S3 Standard $0.023/GB-month; ALB $0.0225/h; T3 surplus CPU credits
$0.05 (Linux) / $0.096 (Windows) per vCPU-hour.
