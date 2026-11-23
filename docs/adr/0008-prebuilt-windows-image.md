# ADR-0008: A pre-built Windows image, made with Packer

**Status:** Accepted (template written in Phase 3.3)

## Context

The legacy server needs Windows Server 2022, IIS, ASP.NET 4.8, SQL Server 2019 Developer with the replication
feature, and the Systems Manager agent. Installing all of that at boot downloads gigabytes from Microsoft and
adds time to every session.

## Decision

Build the image with Packer (`infra/image`, `make image`) and rebuild only when its definition changes. The platform
layer finds it by tag (`Project=purchasedesk`, `Layer=image`).

- **Base:** AWS's latest Windows Server 2022 Base image, which AWS patches monthly.
- **SQL Server:** 2019 Developer, engine and replication, SQL Server Agent automatic, TCP enabled, updated in the same
  setup run to 15.0.4510.2 (KB5132745, [ADR-0003](0003-sql-server-2019-cu32-everywhere.md)). Windows authentication
  only: no password is baked in; SQL logins are created at boot from Parameter Store.
- **Supply chain:** both Microsoft installers must carry a valid Microsoft signature, and the update must also match the
  SHA-256 published on Microsoft's KB page. The update comes from the Microsoft Update Catalog.
- **Verified before saving:** the build fails unless SQL Server reports 15.0.4510.2 and Developer edition, the
  replication agents are installed, Agent is automatic and running, IIS is running with ASP.NET 4.8, and the SSM agent
  is running.
- **No sysprep.** Sysprep gives each instance a new computer name, which leaves SQL Server's `@@SERVERNAME` stale, and
  replication (and so DMS) depends on it. There is only ever one legacy instance, so unique machine identities are not
  needed. Instances launched from the image keep the build's computer name and local Administrator password; they are
  administered through Systems Manager, never RDP.
- **Build connection:** WinRM over HTTPS with a self-signed certificate, reachable only from the builder's public IP
  through Packer's temporary security group. A one-shot task removes the listener, certificate and firewall rule on an
  instance's first start. Session Manager would avoid the open port entirely, but HashiCorp documents it for SSH, not
  WinRM.
- **One image at a time:** `make image` deregisters older images and deletes their snapshots after a successful build.

At boot, the instance only fetches the release artifacts, creates the logins, creates and seeds the database, and
configures IIS and the scheduled task (Phase 4).

## Consequences

- `make up` does not depend on Microsoft's download servers or on a long install.
- A build takes about an hour on a Windows `t3.large` and costs a few tens of cents.
- Storage cost: EBS snapshots at $0.05 per GB-month of used blocks (list price, 2026-11-21), about $1.25-1.75
  a month for 25-35 GB.
- A broken image build blocks Phase 4; the fallback is install-at-boot from installer media cached in the
  artifact bucket.
- The legacy instance uses unlimited CPU credits. Surplus T3 credits on Windows cost $0.096 per vCPU-hour, but a
  session repays most of the boot burst from credits earned while idle; the worst case is a few cents a session.

**Correction (Phase 4.2).** This record first said the legacy instance would use standard credits, to avoid surplus
charges. A new T3 in standard mode starts with no credits (T3 instances get no launch credits), so every boot would
run at the 20% baseline, several times slower. The instance uses unlimited credits instead (ADR-0012), and the first
session records `CPUSurplusCreditsCharged`.

## Alternatives considered

- **Install everything at boot:** no storage cost, but roughly 15 minutes slower per session and dependent on
  external downloads.
- **AWS-provided SQL Server AMIs:** licence-included editions cost far more per hour; the free Express AMI cannot
  be a DMS source.
- **Sysprep with SQL Server's image preparation (PrepareImage/CompleteImage):** the supported way to generalise
  SQL Server, but it adds a completion step at every boot for a single instance that never needs a new identity.
