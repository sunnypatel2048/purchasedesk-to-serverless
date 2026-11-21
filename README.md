# PurchaseDesk to Serverless

**A live migration of a legacy .NET Framework and SQL Server application to AWS serverless, with every step measured.**

PurchaseDesk is a small purchase-order application built the way many real ones
still run: ASP.NET Web API 2 on .NET Framework 4.8, hosted in IIS on Windows
Server, with its business rules in SQL Server stored procedures. This repository
migrates it to AWS Lambda, Amazon API Gateway and Amazon Aurora PostgreSQL while
traffic keeps flowing.

> **Status:** Phase 1 complete. The legacy application is built, tested on Windows
> on every change, and frozen at the `legacy-v1` tag. The migration itself has not
> started yet.

## The migration, in order

1. **Assess** the legacy system and choose a strategy for each component.
2. **Pin the behaviour** by recording what the legacy API returns.
3. **Replicate the data** from SQL Server to Aurora PostgreSQL with AWS DMS.
4. **Move reads first**, route by route and by percentage, with rollback in about 90 seconds.
5. **Cut over writes once**, with a short, measured write freeze.
6. **Decommission** the Windows server and compare cost before and after.

## What's here so far

| Folder | Contents |
|---|---|
| [`legacy/`](legacy) | The "before" system, frozen: the ASP.NET Web API 2 app, the nightly CSV export, the SQL Server schema, deterministic seed data and seven stored procedures, and their tests |
| [`golden/`](golden) | What the legacy system actually returns, recorded on Windows: 38 API responses and 2 export files. The definition of "equivalent" for the new system ([ADR-0009](docs/adr/0009-golden-files-define-equivalent.md)) |
| [`docs/assessment.md`](docs/assessment.md) | The migration assessment: current state, risks, strategy per component, target architecture, sequence and rollback |
| [`docs/sqlserver-to-postgresql.md`](docs/sqlserver-to-postgresql.md) | Column-by-column type map and the behaviour differences between the two engines |
| [`docs/measurements.md`](docs/measurements.md) | Every measured number, with how and when it was taken |
| [`docs/adr/`](docs/adr) | Decision records: why the migration is built the way it is |

The legacy app targets .NET Framework 4.8 and compiles on a Mac with `dotnet build`; it runs and is tested on
GitHub's Windows runners against SQL Server 2019 ([`legacy.yml`](.github/workflows/legacy.yml)).

## License

[MIT](LICENSE)
