-- Facts about the seed data, one "name value" line each, in a fixed order.
-- dev.sh check compares them with seed-expected.txt; CI does the same on Windows.
-- The fp_* values are the first 12 hex characters of a SHA-256 over every row in id order (FOR JSON).
-- RowVer is left out: rowversion values differ between databases by design.
SET NOCOUNT ON;

SELECT CONCAT(v.Name, ' ', v.Value)
FROM (VALUES
    (1,  'suppliers',             (SELECT CONVERT(varchar(30), COUNT(*)) FROM dbo.Suppliers)),
    (2,  'suppliers_inactive',    (SELECT CONVERT(varchar(30), COUNT(*)) FROM dbo.Suppliers WHERE IsActive = 0)),
    (3,  'suppliers_no_email',    (SELECT CONVERT(varchar(30), COUNT(*)) FROM dbo.Suppliers WHERE Email IS NULL)),
    (4,  'orders',                (SELECT CONVERT(varchar(30), COUNT(*)) FROM dbo.PurchaseOrders)),
    (5,  'orders_approved',       (SELECT CONVERT(varchar(30), COUNT(*)) FROM dbo.PurchaseOrders WHERE Status = 'Approved')),
    (6,  'orders_rejected',       (SELECT CONVERT(varchar(30), COUNT(*)) FROM dbo.PurchaseOrders WHERE Status = 'Rejected')),
    (7,  'orders_pending',        (SELECT CONVERT(varchar(30), COUNT(*)) FROM dbo.PurchaseOrders WHERE Status = 'Pending')),
    (8,  'lines',                 (SELECT CONVERT(varchar(30), COUNT(*)) FROM dbo.PurchaseOrderLines)),
    (9,  'audit_rows',            (SELECT CONVERT(varchar(30), COUNT(*)) FROM dbo.AuditLog)),
    (10, 'totals_mismatched',     (SELECT CONVERT(varchar(30), COUNT(*))
                                   FROM dbo.PurchaseOrders o
                                   WHERE o.TotalAmount <> (SELECT SUM(l.LineAmount) FROM dbo.PurchaseOrderLines l
                                                           WHERE l.PurchaseOrderId = o.Id))),
    (11, 'half_cent_lines',       (SELECT CONVERT(varchar(30), COUNT(*))
                                   FROM dbo.PurchaseOrderLines
                                   CROSS APPLY (SELECT x = Quantity * UnitPrice * (1 - DiscountPercent / 100) * 1000) a
                                   WHERE a.x = FLOOR(a.x) AND CAST(a.x AS bigint) % 10 = 5)),
    (12, 'null_required_by',      (SELECT CONVERT(varchar(30), COUNT(*)) FROM dbo.PurchaseOrders WHERE RequiredBy IS NULL)),
    (13, 'case_only_name_pairs',  (SELECT CONVERT(varchar(30), COUNT(*))
                                   FROM dbo.Suppliers a
                                   JOIN dbo.Suppliers b ON a.Id < b.Id AND a.Name = b.Name
                                   WHERE CAST(a.Name AS varbinary(400)) <> CAST(b.Name AS varbinary(400)))),
    (14, 'non_ascii_names',       (SELECT CONVERT(varchar(30), COUNT(*)) FROM dbo.Suppliers
                                   WHERE PATINDEX(N'%[^ -~]%' COLLATE Latin1_General_BIN, Name) > 0)),
    (15, 'orders_with_ms',        (SELECT CONVERT(varchar(30), COUNT(*)) FROM dbo.PurchaseOrders
                                   WHERE DATEPART(millisecond, OrderDate) <> 0)),
    (16, 'fp_suppliers',          (SELECT CONVERT(char(12), HASHBYTES('SHA2_256',
                                       (SELECT * FROM dbo.Suppliers ORDER BY Id FOR JSON PATH)), 2))),
    (17, 'fp_orders',             (SELECT CONVERT(char(12), HASHBYTES('SHA2_256',
                                       (SELECT Id, OrderNumber, SupplierId, Status, OrderDate, RequiredBy, Notes,
                                               TotalAmount, CreatedBy, DecidedBy, DecidedAt
                                        FROM dbo.PurchaseOrders ORDER BY Id FOR JSON PATH)), 2))),
    (18, 'fp_lines',              (SELECT CONVERT(char(12), HASHBYTES('SHA2_256',
                                       (SELECT * FROM dbo.PurchaseOrderLines ORDER BY Id FOR JSON PATH)), 2))),
    (19, 'fp_audit',              (SELECT CONVERT(char(12), HASHBYTES('SHA2_256',
                                       (SELECT * FROM dbo.AuditLog ORDER BY Id FOR JSON PATH)), 2)))
) v (Ord, Name, Value)
ORDER BY v.Ord;
