# Architecture decision records

Why PurchaseDesk is migrated the way it is. Each record states the context, the decision, its consequences,
and the alternatives that were rejected and why.
Format: [Michael Nygard's ADR template](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions).

| ADR | Decision |
| --- | --- |
| [0001](0001-staged-migration.md) | Migrate in stages: replicate data, move reads by percentage, cut writes over once |
| [0002](0002-real-net-framework-legacy.md) | A real .NET Framework 4.8 legacy app, built without a Windows machine |
| [0003](0003-sql-server-2019-cu32-everywhere.md) | SQL Server 2019 CU32 GDR, Developer edition, everywhere |
| [0004](0004-cloudfront-function-front-door.md) | The front door is CloudFront, with a CloudFront Function reading weights from a KeyValueStore |
| [0005](0005-aurora-postgresql-serverless-v2.md) | Aurora PostgreSQL Serverless v2 as the target database |
| [0006](0006-lambda-dotnet10-arm64.md) | Lambda on the .NET 10 managed runtime, arm64, as the target compute |
| [0007](0007-terraform-three-layers.md) | Terraform in three layers: bootstrap, image and platform |
| [0008](0008-prebuilt-windows-image.md) | A pre-built Windows image, made with Packer |
