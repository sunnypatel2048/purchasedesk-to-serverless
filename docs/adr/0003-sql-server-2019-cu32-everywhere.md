# ADR-0003: SQL Server 2019 CU32, Developer edition, everywhere

**Status:** Accepted (proven in Phase 0.4; corrected in Phase 3.3)

## Context

The legacy database runs in three places: Docker on an Apple Silicon Mac for developing T-SQL, GitHub's
Windows runners for tests, and the EC2 instance during migration sessions. AWS DMS supports ongoing
replication from Enterprise, Standard (2016 and later) and Developer editions, but not Express.
SQL Server 2019 images are amd64-only and have a reputation for instability under emulation on Apple Silicon.

## Decision

Use SQL Server 2019, Developer edition, on the CU32 servicing line everywhere. CU32 is SQL Server 2019's final
cumulative update; Microsoft now ships only security updates (GDRs) on top of it, which do not change T-SQL behaviour.

| Where | Build | How |
|---|---|---|
| EC2 (the migration source) | **15.0.4510.2**, CU32 + GDR, KB5132745 (November 10, 2026): the newest security build | Installed by the Packer image ([ADR-0008](0008-prebuilt-windows-image.md)); the image build fails on any other version |
| Docker on the Mac (T-SQL development) | 15.0.4470.1, CU32 + GDR, KB5090407 (May 12, 2026) | `mcr.microsoft.com/mssql/server:2019-CU32-GDR8-ubuntu-20.04`, pinned in the frozen `legacy/` folder |
| GitHub's Windows runners (tests, golden files) | 15.0.2000.5, RTM | Whatever the installer provides; aligned if a behaviour difference ever reaches a client |

**Correction (Phase 3.3).** This record first said GDR8 was "the latest security fix" and that one build would run
everywhere. Both were wrong: the image tags were compared as text, so `GDR10` to `GDR13` sorted before `GDR8`. The
newest tag, `GDR13`, is build 15.0.4510.2. The EC2 image uses that build. Local Docker stays on 15.0.4470.1 because its
compose file is part of the frozen legacy code, and the difference is security fixes only.

## Consequences

- Measured in Phase 0.4: three clean wipe-and-start cycles in a row, ready in 6-12 seconds; 20,000 stored
  procedure calls in about 2 seconds with no crash, no restart and 878 MiB of memory.
- The CU32 line will not drift: there will be no CU33.
- Developer edition is licensed for non-production use only, which fits a demo with synthetic data.
- CI still installs 2019 RTM. In Phase 1.6 RTM and CU32 differed once: creating an order whose line Sku is longer than
  its column failed on RTM with a deadlock (1205) and on CU32 with a truncation error (2629, with 8061). The API answers
  500 either way, so the golden files are unaffected. CI moves to CU32 if a difference ever reaches a client.

## Alternatives considered

- **SQL Server 2022:** more reliable under emulation by reputation, but 2019 proved stable here and is the more
  typical legacy version.
- **Express edition:** free for production, but DMS cannot replicate from it.
- **Floating tags such as `2019-latest`:** convenient, but the version could change between sessions.
