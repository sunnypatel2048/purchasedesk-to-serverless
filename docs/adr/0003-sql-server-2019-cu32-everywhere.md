# ADR-0003: SQL Server 2019 CU32 GDR, Developer edition, everywhere

**Status:** Accepted (proven in Phase 0.4)

## Context

The legacy database runs in three places: Docker on an Apple Silicon Mac for developing T-SQL, GitHub's
Windows runners for tests, and the EC2 instance during migration sessions. AWS DMS supports ongoing
replication from Enterprise, Standard (2016 and later) and Developer editions, but not Express.
SQL Server 2019 images are amd64-only and have a reputation for instability under emulation on Apple Silicon.

## Decision

Use SQL Server 2019, Developer edition, at build 15.0.4470.1 (CU32 GDR, KB5090407) everywhere:

- Locally: `mcr.microsoft.com/mssql/server:2019-CU32-GDR8-ubuntu-20.04`, pinned, under Rosetta.
- On EC2: the Windows image installs the same build.
- In CI: currently whatever the installer provides (2019 RTM, 15.0.2000.5); aligned to CU32 if behaviour
  ever differs.

## Consequences

- Measured in Phase 0.4: three clean wipe-and-start cycles in a row, ready in 6-12 seconds; 20,000 stored
  procedure calls in about 2 seconds with no crash, no restart and 878 MiB of memory.
- CU32 is SQL Server 2019's final cumulative update, so the pin will not drift.
- Developer edition is licensed for non-production use only, which fits a demo with synthetic data.
- One version means a behaviour difference found locally is the same one DMS and the parity tests see.
- CI still installs 2019 RTM. In Phase 1.6 the two builds differed once: creating an order whose line Sku is longer
  than its column failed on RTM with a deadlock (1205) and on CU32 with a truncation error (2629, with 8061). The API
  answers 500 either way, so the golden files are unaffected. CI moves to CU32 if a difference ever reaches a client.

## Alternatives considered

- **SQL Server 2022:** more reliable under emulation by reputation, but 2019 proved stable here and is the more
  typical legacy version.
- **Express edition:** free for production, but DMS cannot replicate from it.
- **Floating tags such as `2019-latest`:** convenient, but the version could change between sessions.
