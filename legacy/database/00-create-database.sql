-- PurchaseDesk legacy database.
-- The collation is SQL Server's usual default, stated explicitly so every environment (Docker on a Mac,
-- GitHub's Windows runners, the EC2 server) compares text case-insensitively in exactly the same way.
IF DB_ID(N'PurchaseDesk') IS NULL
    CREATE DATABASE PurchaseDesk COLLATE SQL_Latin1_General_CP1_CI_AS;
GO
