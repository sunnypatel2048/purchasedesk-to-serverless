# ADR-0008: A pre-built Windows image, made with Packer

**Status:** Accepted

## Context

The legacy server needs Windows Server 2022, IIS, ASP.NET 4.8, SQL Server 2019 Developer with the replication
feature, and the Systems Manager agent. Installing all of that at boot downloads gigabytes from Microsoft and
adds time to every session.

## Decision

Build the image once with Packer (`make image`) and rebuild only when its definition changes. It installs
SQL Server 2019 at build 15.0.4470.1 (CU32 GDR, ADR-0003). The platform layer references it by tag. At boot,
the instance only fetches the release artifacts, creates and seeds the database, and configures IIS and the
scheduled task.

## Consequences

- `make up` does not depend on Microsoft's download servers or on a long install.
- Storage cost: EBS snapshots at $0.05 per GB-month of used blocks (list price, 2026-11-21), about $1.25-1.75
  a month for 25-35 GB.
- A broken image build blocks Phase 4; the fallback is install-at-boot from installer media cached in the
  artifact bucket.
- The instance uses standard CPU credits: surplus T3 credits on Windows cost $0.096 per vCPU-hour, which a busy
  boot could turn into a doubled session cost.

## Alternatives considered

- **Install everything at boot:** no storage cost, but roughly 15 minutes slower per session and dependent on
  external downloads.
- **AWS-provided SQL Server AMIs:** licence-included editions cost far more per hour; the free Express AMI cannot
  be a DMS source.
