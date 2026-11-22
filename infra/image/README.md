# Windows image

The legacy server's image ([ADR-0008](../../docs/adr/0008-prebuilt-windows-image.md)): Windows Server 2022, IIS with
ASP.NET 4.8, SQL Server 2019 Developer at 15.0.4510.2, and the Systems Manager agent.

## Build

```bash
aws sso login --profile vibesense
AWS_PROFILE=vibesense make image
```

About an hour, a few tens of cents. The log goes to `logs/image-*.log`. The build:

1. launches a Windows `t3.large` from AWS's latest Windows Server 2022 Base image, reachable over WinRM HTTPS from this
   machine's IP only;
2. installs IIS (`scripts/install-iis.ps1`);
3. downloads Microsoft's SQL Server 2019 Developer installer and the KB5132745 security update, checks their Microsoft
   signatures and the update's published SHA-256, and installs both in one run (`scripts/install-sqlserver.ps1`);
4. restarts, then checks every requirement and fails if one is missing (`scripts/verify.ps1`, one `RESULT` line each);
5. deletes the installers and arranges for the build's WinRM listener to be removed on first start (`scripts/cleanup.ps1`);
6. saves the image, tagged `Project=purchasedesk`, `Layer=image`, `SqlServerBuild`, `GitCommit`.

Afterwards `make image` deregisters any older image of this project and deletes its snapshots.

## Change the SQL Server build

Update `sql_update_url`, `sql_update_sha256` and `sql_build` in `variables.pkr.hcl` together: the URL from the
Microsoft Update Catalog, the SHA-256 from the "File hash information" table on Microsoft's KB page, the build from
Microsoft's SQL Server 2019 build list. Then record the change in ADR-0003.
