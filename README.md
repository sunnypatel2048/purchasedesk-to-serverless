# PurchaseDesk to Serverless

**A live migration of a legacy .NET Framework and SQL Server application to AWS serverless, with every step measured.**

PurchaseDesk is a small purchase-order application built the way many real ones
still run: ASP.NET Web API 2 on .NET Framework 4.8, hosted in IIS on Windows
Server, with its business rules in SQL Server stored procedures. This repository
migrates it to AWS Lambda, Amazon API Gateway and Amazon Aurora PostgreSQL while
traffic keeps flowing.

> **Status:** work in progress, Phase 0 (proving the setup). Nothing below is
> built yet.

## The migration, in order

1. **Assess** the legacy system and choose a strategy for each component.
2. **Pin the behaviour** by recording what the legacy API returns.
3. **Replicate the data** from SQL Server to Aurora PostgreSQL with AWS DMS.
4. **Move reads first**, route by route and by percentage, with instant rollback.
5. **Cut over writes once**, with a short, measured write freeze.
6. **Decommission** the Windows server and compare cost before and after.

## License

[MIT](LICENSE)
