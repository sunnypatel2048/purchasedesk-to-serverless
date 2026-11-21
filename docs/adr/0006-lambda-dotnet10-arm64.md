# ADR-0006: Lambda on the .NET 10 managed runtime, arm64, as the target compute

**Status:** Accepted

## Context

The legacy app is seven routes and one nightly job. The target should cost nothing when idle, need no servers
to patch, and let each slice of the API move independently. The team's language is C#.

## Decision

- Four functions, one per slice: `suppliers-read`, `orders-read`, `orders-write`, `export`.
- ASP.NET Core minimal APIs hosted with `Amazon.Lambda.AspNetCoreServer.Hosting`, so the same code runs
  locally with `dotnet run`. Data access with Npgsql and Dapper.
- Managed runtime `dotnet10`, arm64.
- Cold starts are measured, then SnapStart and Native AOT are evaluated; that choice gets its own record.

## Consequences

- Idle cost is zero; each function deploys and shifts on its own.
- Functions that reach the database run inside the VPC, with IAM database authentication and no NAT gateway.
- Cold starts on .NET are typically a second or more; they are recorded, not assumed away.
- Connection counts rise with concurrency; production would add RDS Proxy.

## Alternatives considered

- **ECS Fargate:** the right answer for long-running or steady traffic, and the "when not Lambda" answer already
  covered by Project 1's container platform. It bills while idle.
- **x86_64 Lambda:** no benefit here; arm64 is cheaper per millisecond.
