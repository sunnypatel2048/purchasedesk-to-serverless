-- PurchaseDesk seed data: 50 suppliers, 2,000 orders, their lines and audit rows.
--
-- Deterministic: loading it twice, on any SQL Server, gives byte-identical data. The parity tests depend on that.
--   * Randomness comes from SHA2_256 of a fixed key per row ('order:417'), sliced into integers. No RAND or NEWID.
--   * Ids are inserted explicitly (IDENTITY_INSERT), so they are 1..N by design.
--   * Dates are offsets from fixed base dates. No GETDATE.
--   * The file is pure ASCII (accented letters use NCHAR), so no client code page can change it.
--
-- Some rows are planted so each legacy trait shows up in the data: half-cent line amounts for T-SQL ROUND,
-- supplier names that differ only by case, accented names, NULL RequiredBy dates, datetime milliseconds.
-- Run once, after 01-schema.sql, against an empty database.
USE PurchaseDesk;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF EXISTS (SELECT 1 FROM dbo.Suppliers)
BEGIN
    RAISERROR(N'Seed data already exists. Recreate the database to seed it again.', 16, 1);
    SET NOEXEC ON;
END
GO

BEGIN TRANSACTION;

-- Numbers 1..10000.
CREATE TABLE #n (n int NOT NULL PRIMARY KEY);
INSERT #n (n)
SELECT a.d + 10 * b.d + 100 * c.d + 1000 * e.d + 1
FROM (VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9)) a (d)
CROSS JOIN (VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9)) b (d)
CROSS JOIN (VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9)) c (d)
CROSS JOIN (VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9)) e (d);

-- ---------------------------------------------------------------- Suppliers (50)
-- 1-44 generated; 45-50 planted: a case-only pair, accented names, a lowercase first letter.
DECLARE @SupplierBase datetime = '2025-06-02T09:00:00';

SET IDENTITY_INSERT dbo.Suppliers ON;
INSERT dbo.Suppliers (Id, Code, Name, Email, IsActive, CreatedAt)
SELECT
    n.n,
    CONCAT('S', RIGHT(CONCAT('000', n.n), 3)),
    CASE n.n
        WHEN 45 THEN N'Northwind Traders'
        WHEN 46 THEN N'northwind traders'
        WHEN 47 THEN N'M' + NCHAR(252) + N'ller GmbH'                              -- Mueller with u-umlaut
        WHEN 48 THEN N'Soci' + NCHAR(233) + N't' + NCHAR(233) + N' Fournitures'    -- e-acute
        WHEN 49 THEN NCHAR(197) + N'ngstr' + NCHAR(246) + N'm Labs'                -- A-ring, o-umlaut
        WHEN 50 THEN N'zeta Components'
        ELSE CONCAT(
            CHOOSE(r.r1 % 10 + 1, N'Atlas', N'Beacon', N'Cedar', N'Delta', N'Evergreen',
                                  N'Falcon', N'Granite', N'Harbor', N'Ironwood', N'Juniper'),
            N' ',
            CHOOSE(r.r2 % 8 + 1, N'Industrial', N'Office', N'Packaging', N'Electrical',
                                 N'Safety', N'Tools', N'Logistics', N'Chemicals'),
            N' ',
            CHOOSE(r.r3 % 4 + 1, N'Ltd', N'Supply Co', N'Inc', N'Partners'))
    END,
    CASE WHEN n.n >= 45 OR r.r4 % 100 >= 15
         THEN CONCAT('s', RIGHT(CONCAT('000', n.n), 3), '@example.com') END,
    CASE WHEN n.n < 45 AND r.r5 % 100 < 10 THEN 0 ELSE 1 END,
    DATEADD(day, 3 * n.n, @SupplierBase)
FROM #n n
CROSS APPLY (SELECT h = HASHBYTES('SHA2_256', CONCAT('supplier:', n.n))) x
CROSS APPLY (SELECT
    r1 = CAST(SUBSTRING(x.h, 1, 4) AS int) & 2147483647,
    r2 = CAST(SUBSTRING(x.h, 5, 4) AS int) & 2147483647,
    r3 = CAST(SUBSTRING(x.h, 9, 4) AS int) & 2147483647,
    r4 = CAST(SUBSTRING(x.h, 13, 4) AS int) & 2147483647,
    r5 = CAST(SUBSTRING(x.h, 17, 4) AS int) & 2147483647) r
WHERE n.n <= 50;
SET IDENTITY_INSERT dbo.Suppliers OFF;

-- ---------------------------------------------------------------- Purchase orders (2,000)
-- Spread over about 290 days from @OrderBase. About 60% Approved, 15% Rejected, 25% Pending.
-- Every 250th order gets 2 ms (stored as .003) and every 250th from 125 gets 998 ms (stored as .997):
-- datetime keeps 1/300 s, which the move to timestamptz must preserve exactly.
DECLARE @OrderBase datetime = '2026-01-05T08:00:00';

SET IDENTITY_INSERT dbo.PurchaseOrders ON;
INSERT dbo.PurchaseOrders
    (Id, OrderNumber, SupplierId, Status, OrderDate, RequiredBy, Notes, TotalAmount, CreatedBy, DecidedBy, DecidedAt)
SELECT
    o.Id,
    CONCAT('PO-', RIGHT(CONCAT('000000', o.Id), 6)),
    o.SupplierId,
    o.Status,
    o.OrderDate,
    CASE WHEN o.r4 % 100 < 20 THEN NULL ELSE CAST(DATEADD(day, 7 + o.r4 % 45, o.OrderDate) AS date) END,
    CASE o.r6 % 20
        WHEN 0 THEN N'Urgent: line stoppage'
        WHEN 1 THEN N'URGENT - deliver to dock 4'
        WHEN 2 THEN N'Partial delivery accepted'
    END,
    0,  -- set from the lines below
    CHOOSE(o.r7 % 5 + 1, N'j.smith', N'A.Kumar', N'l.garcia', N'T.Nguyen', N'p.oconnor'),
    CASE WHEN o.Status <> 'Pending' THEN CHOOSE(o.r8 % 3 + 1, N'm.chen', N'R.Okafor', N's.weber') END,
    CASE WHEN o.Status <> 'Pending' THEN DATEADD(minute, 30 + o.r8 % 4320, o.OrderDate) END
FROM (
    SELECT
        n.n AS Id,
        r.r4, r.r6, r.r7, r.r8,
        r.r1 % 50 + 1 AS SupplierId,
        CASE WHEN r.r5 % 100 < 60 THEN 'Approved'
             WHEN r.r5 % 100 < 75 THEN 'Rejected'
             ELSE 'Pending' END AS Status,
        DATEADD(millisecond, CASE n.n % 250 WHEN 0 THEN 2 WHEN 125 THEN 998 ELSE 0 END,
            DATEADD(second, r.r3 % 60,
                DATEADD(minute, n.n * 210 + r.r2 % 180, @OrderBase))) AS OrderDate
    FROM #n n
    CROSS APPLY (SELECT h = HASHBYTES('SHA2_256', CONCAT('order:', n.n))) x
    CROSS APPLY (SELECT
        r1 = CAST(SUBSTRING(x.h, 1, 4) AS int) & 2147483647,
        r2 = CAST(SUBSTRING(x.h, 5, 4) AS int) & 2147483647,
        r3 = CAST(SUBSTRING(x.h, 9, 4) AS int) & 2147483647,
        r4 = CAST(SUBSTRING(x.h, 13, 4) AS int) & 2147483647,
        r5 = CAST(SUBSTRING(x.h, 17, 4) AS int) & 2147483647,
        r6 = CAST(SUBSTRING(x.h, 21, 4) AS int) & 2147483647,
        r7 = CAST(SUBSTRING(x.h, 25, 4) AS int) & 2147483647,
        r8 = CAST(SUBSTRING(x.h, 29, 4) AS int) & 2147483647) r
    WHERE n.n <= 2000
) o;
SET IDENTITY_INSERT dbo.PurchaseOrders OFF;

-- ---------------------------------------------------------------- Purchase order lines (1-7 per order)
-- LineAmount uses exactly the expression usp_CreatePurchaseOrder will use. T-SQL ROUND goes half away from zero.
-- Planted: every line where (order * 7 + line) % 101 = 0 has quantity 1, no discount and a price ending in
-- half a cent, so its amount lands exactly on .xx5.
SET IDENTITY_INSERT dbo.PurchaseOrderLines ON;
INSERT dbo.PurchaseOrderLines
    (Id, PurchaseOrderId, LineNumber, Sku, Description, Quantity, UnitPrice, DiscountPercent, LineAmount)
SELECT
    ROW_NUMBER() OVER (ORDER BY l.PurchaseOrderId, l.LineNumber),
    l.PurchaseOrderId,
    l.LineNumber,
    l.Sku,
    l.Description,
    l.Quantity,
    l.UnitPrice,
    l.DiscountPercent,
    ROUND(l.Quantity * l.UnitPrice * (1 - l.DiscountPercent / 100), 2)
FROM (
    SELECT
        o.Id AS PurchaseOrderId,
        k.n AS LineNumber,
        CONCAT('SKU-', RIGHT(CONCAT('0000', r.r1 % 400 + 1), 4)) AS Sku,
        CONCAT(
            CHOOSE(r.r1 % 10 + 1, N'Hex bolts M8', N'Copy paper A4', N'Nitrile gloves', N'Cable ties', N'Pallet wrap',
                                  N'Safety glasses', N'Drill bits', N'Label rolls', N'Fuse 10A', N'Degreaser 5L'),
            N', pack of ', 5 * (r.r2 % 10 + 1)) AS Description,
        CASE WHEN p.Planted = 1 THEN 1 ELSE 1 + r.r3 % 40 END AS Quantity,
        CAST((100 + r.r4 % 25000) / 100.0 + CASE WHEN p.Planted = 1 THEN 0.005 ELSE 0 END AS money) AS UnitPrice,
        CAST(CASE WHEN p.Planted = 1 OR r.r5 % 100 < 70 THEN 0
                  ELSE CHOOSE(r.r6 % 6 + 1, 2.5, 5, 7.5, 10, 12.5, 15) END AS decimal(5, 2)) AS DiscountPercent
    FROM dbo.PurchaseOrders o
    CROSS APPLY (SELECT LineCount =
        CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT('order-lines:', o.Id)), 1, 4) AS int) & 2147483647) c
    JOIN #n k ON k.n <= c.LineCount % 7 + 1
    CROSS APPLY (SELECT Planted = CASE WHEN (o.Id * 7 + k.n) % 101 = 0 THEN 1 ELSE 0 END) p
    CROSS APPLY (SELECT h = HASHBYTES('SHA2_256', CONCAT('line:', o.Id, ':', k.n))) x
    CROSS APPLY (SELECT
        r1 = CAST(SUBSTRING(x.h, 1, 4) AS int) & 2147483647,
        r2 = CAST(SUBSTRING(x.h, 5, 4) AS int) & 2147483647,
        r3 = CAST(SUBSTRING(x.h, 9, 4) AS int) & 2147483647,
        r4 = CAST(SUBSTRING(x.h, 13, 4) AS int) & 2147483647,
        r5 = CAST(SUBSTRING(x.h, 17, 4) AS int) & 2147483647,
        r6 = CAST(SUBSTRING(x.h, 21, 4) AS int) & 2147483647) r
) l;
SET IDENTITY_INSERT dbo.PurchaseOrderLines OFF;

UPDATE o
SET TotalAmount = t.Total
FROM dbo.PurchaseOrders o
JOIN (SELECT PurchaseOrderId, SUM(LineAmount) AS Total
      FROM dbo.PurchaseOrderLines
      GROUP BY PurchaseOrderId) t ON t.PurchaseOrderId = o.Id;

-- ---------------------------------------------------------------- Audit log
-- One row per creation and one per decision, numbered in time order.
SET IDENTITY_INSERT dbo.AuditLog ON;
INSERT dbo.AuditLog (Id, OccurredAt, Action, PurchaseOrderId, Actor, Detail)
SELECT
    ROW_NUMBER() OVER (ORDER BY a.OccurredAt, a.PurchaseOrderId, a.Step),
    a.OccurredAt, a.Action, a.PurchaseOrderId, a.Actor, a.Detail
FROM (
    SELECT OrderDate AS OccurredAt, 'OrderCreated' AS Action, Id AS PurchaseOrderId, CreatedBy AS Actor,
           CONCAT(N'Created ', OrderNumber, N' for ', CONVERT(varchar(30), TotalAmount, 0)) AS Detail, 1 AS Step
    FROM dbo.PurchaseOrders
    UNION ALL
    SELECT DecidedAt, CASE Status WHEN 'Approved' THEN 'OrderApproved' ELSE 'OrderRejected' END, Id, DecidedBy,
           CONCAT(Status, N' ', OrderNumber), 2
    FROM dbo.PurchaseOrders
    WHERE Status <> 'Pending'
) a;
SET IDENTITY_INSERT dbo.AuditLog OFF;

DROP TABLE #n;

COMMIT TRANSACTION;
GO

SET NOEXEC OFF;
GO
