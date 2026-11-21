-- Tests for the seven procedures, against the seed data. Run with: legacy/database/dev.sh test
--
-- Each case runs in its own transaction and is rolled back: a procedure that throws with XACT_ABORT dooms the
-- whole transaction, so cases cannot share one. Results go into a table variable, which a rollback does not undo.
-- Expected and actual are compared with a binary collation, so 'approved' does not pass for 'Approved'.
-- usp_GetPurchaseOrder returns two result sets, which INSERT ... EXEC cannot capture; here only its shape is
-- checked, and the characterization tests (Phase 1.6) cover its behaviour.
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @r TABLE (Ord int IDENTITY(1, 1), Name varchar(60), Expected nvarchar(100), Actual nvarchar(100));

CREATE TABLE #sup (Seq int IDENTITY(1, 1), Id int, Code varchar(20), Name nvarchar(200), Email varchar(254), IsActive bit);
CREATE TABLE #sup1 (Id int, Code varchar(20), Name nvarchar(200), Email varchar(254), IsActive bit, CreatedAt datetime);
CREATE TABLE #search (Seq int IDENTITY(1, 1), Id int, OrderNumber varchar(20), SupplierId int, SupplierName nvarchar(200),
                      Status varchar(10), OrderDate datetime, RequiredBy date, TotalAmount money, LineCount int);
CREATE TABLE #created (Id int, OrderNumber varchar(20));
CREATE TABLE #status (Id int, Status varchar(10), RowVer binary(8));
CREATE TABLE #export (Seq int IDENTITY(1, 1), OrderNumber varchar(20), SupplierCode varchar(20), SupplierName nvarchar(200),
                      ApprovedAt datetime, ApprovedBy nvarchar(100), LineNumber smallint, Sku varchar(40),
                      Description nvarchar(200), Quantity int, UnitPrice money, DiscountPercent decimal(5, 2),
                      LineAmount money, OrderTotal money);

DECLARE @total int, @e int, @id int, @rv binary(8), @n int, @expected nvarchar(100);
DECLARE @lines dbo.PurchaseOrderLineInput;

-- ---------------------------------------------------------------- usp_ListSuppliers
BEGIN TRANSACTION;
INSERT #sup (Id, Code, Name, Email, IsActive) EXEC dbo.usp_ListSuppliers;
INSERT @r (Name, Expected, Actual) VALUES
    ('list-active-count', N'46', (SELECT CONVERT(nvarchar(100), COUNT(*)) FROM #sup)),
    -- Angstrom Labs (id 49) sorts first under the case-insensitive accent-aware collation.
    ('list-first-row-is-id-49', N'49', (SELECT CONVERT(nvarchar(100), Id) FROM #sup WHERE Seq = (SELECT MIN(Seq) FROM #sup))),
    ('list-northwind-pair-adjacent', N'1', (SELECT CONVERT(nvarchar(100), ABS(a.Seq - b.Seq)) FROM #sup a, #sup b
                                            WHERE a.Id = 45 AND b.Id = 46));
ROLLBACK TRANSACTION;

BEGIN TRANSACTION;
INSERT #sup (Id, Code, Name, Email, IsActive) EXEC dbo.usp_ListSuppliers @IncludeInactive = 1;
INSERT @r (Name, Expected, Actual) VALUES
    ('list-include-inactive-count', N'50', (SELECT CONVERT(nvarchar(100), COUNT(*)) FROM #sup));
ROLLBACK TRANSACTION;

-- ---------------------------------------------------------------- usp_GetSupplier
BEGIN TRANSACTION;
INSERT #sup1 EXEC dbo.usp_GetSupplier @Id = 47;
INSERT @r (Name, Expected, Actual) VALUES ('get-supplier-47-code', N'S047', (SELECT Code FROM #sup1));
ROLLBACK TRANSACTION;

BEGIN TRANSACTION;
INSERT #sup1 EXEC dbo.usp_GetSupplier @Id = 999;
INSERT @r (Name, Expected, Actual) VALUES ('get-supplier-missing-rows', N'0', (SELECT CONVERT(nvarchar(100), COUNT(*)) FROM #sup1));
ROLLBACK TRANSACTION;

-- ---------------------------------------------------------------- usp_SearchPurchaseOrders
BEGIN TRANSACTION;
INSERT #search (Id, OrderNumber, SupplierId, SupplierName, Status, OrderDate, RequiredBy, TotalAmount, LineCount)
EXEC dbo.usp_SearchPurchaseOrders @Status = 'Pending', @TotalCount = @total OUTPUT;
INSERT @r (Name, Expected, Actual) VALUES
    ('search-pending-total', N'518', CONVERT(nvarchar(100), @total)),
    ('search-default-page-size', N'25', (SELECT CONVERT(nvarchar(100), COUNT(*)) FROM #search)),
    ('search-pending-only', N'0', (SELECT CONVERT(nvarchar(100), COUNT(*)) FROM #search WHERE Status <> 'Pending'));
ROLLBACK TRANSACTION;

-- 'urgent' must match both 'Urgent: ...' and 'URGENT - ...'. Expected count computed case-sensitively.
SET @expected = (SELECT CONVERT(nvarchar(100), COUNT(*)) FROM dbo.PurchaseOrders
                 WHERE Notes COLLATE Latin1_General_CS_AS LIKE N'%Urgent%'
                    OR Notes COLLATE Latin1_General_CS_AS LIKE N'%URGENT%');
BEGIN TRANSACTION;
INSERT #search (Id, OrderNumber, SupplierId, SupplierName, Status, OrderDate, RequiredBy, TotalAmount, LineCount)
EXEC dbo.usp_SearchPurchaseOrders @Text = N'urgent', @TotalCount = @total OUTPUT;
INSERT @r (Name, Expected, Actual) VALUES ('search-text-case-insensitive', @expected, CONVERT(nvarchar(100), @total));
ROLLBACK TRANSACTION;

-- Lowercase 'asc' is accepted; NULL RequiredBy sorts first ascending, last descending.
BEGIN TRANSACTION;
INSERT #search (Id, OrderNumber, SupplierId, SupplierName, Status, OrderDate, RequiredBy, TotalAmount, LineCount)
EXEC dbo.usp_SearchPurchaseOrders @SortBy = 'RequiredBy', @SortDir = 'asc', @TotalCount = @total OUTPUT;
INSERT @r (Name, Expected, Actual) VALUES
    ('search-requiredby-asc-null-first', N'NULL',
     (SELECT ISNULL(CONVERT(nvarchar(100), RequiredBy), N'NULL') FROM #search WHERE Seq = (SELECT MIN(Seq) FROM #search)));
ROLLBACK TRANSACTION;

BEGIN TRANSACTION;
INSERT #search (Id, OrderNumber, SupplierId, SupplierName, Status, OrderDate, RequiredBy, TotalAmount, LineCount)
EXEC dbo.usp_SearchPurchaseOrders @SortBy = 'RequiredBy', @SortDir = 'DESC', @TotalCount = @total OUTPUT;
INSERT @r (Name, Expected, Actual) VALUES
    ('search-requiredby-desc-not-null-first', N'not null',
     (SELECT CASE WHEN RequiredBy IS NULL THEN N'NULL' ELSE N'not null' END FROM #search WHERE Seq = (SELECT MIN(Seq) FROM #search)));
ROLLBACK TRANSACTION;

BEGIN TRANSACTION;
INSERT #search (Id, OrderNumber, SupplierId, SupplierName, Status, OrderDate, RequiredBy, TotalAmount, LineCount)
EXEC dbo.usp_SearchPurchaseOrders @Page = 2, @PageSize = 25, @TotalCount = @total OUTPUT;
INSERT @r (Name, Expected, Actual) VALUES
    ('search-page-2-rows', N'25', (SELECT CONVERT(nvarchar(100), COUNT(*)) FROM #search)),
    ('search-all-total', N'2000', CONVERT(nvarchar(100), @total));
ROLLBACK TRANSACTION;

SET @e = 0;
BEGIN TRY EXEC dbo.usp_SearchPurchaseOrders @SortBy = 'Supplier'; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
INSERT @r (Name, Expected, Actual) VALUES ('search-bad-sort-error', N'50001', CONVERT(nvarchar(100), @e));

SET @e = 0;
BEGIN TRY EXEC dbo.usp_SearchPurchaseOrders @PageSize = 101; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
INSERT @r (Name, Expected, Actual) VALUES ('search-page-size-101-error', N'50001', CONVERT(nvarchar(100), @e));

-- ---------------------------------------------------------------- usp_GetPurchaseOrder (shape only)
INSERT @r (Name, Expected, Actual) VALUES
    ('get-order-header-columns', N'3',
     (SELECT CONVERT(nvarchar(100), COUNT(*))
      FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'dbo.usp_GetPurchaseOrder'), 0)
      WHERE name IN ('OrderNumber', 'SupplierName', 'RowVer')));

-- ---------------------------------------------------------------- usp_CreatePurchaseOrder
-- Line 1: 1 x 2.3450 = 2.345 -> 2.35 (T-SQL ROUND half away from zero; C# default would give 2.34).
-- Line 2: 3 x 1.6750 less 12.5% = 4.396875 -> 4.40. Total 6.75.
SELECT TOP 1 @id = Id FROM dbo.Suppliers WHERE IsActive = 1 ORDER BY Id;
DELETE @lines;
INSERT @lines (LineNumber, Sku, Description, Quantity, UnitPrice, DiscountPercent) VALUES
    (1, 'SKU-TEST-1', N'Half-cent test line', 1, 2.3450, 0),
    (2, 'SKU-TEST-2', N'Discounted test line', 3, 1.6750, 12.5);

BEGIN TRANSACTION;
INSERT #created EXEC dbo.usp_CreatePurchaseOrder @SupplierId = @id, @CreatedBy = N'test.user', @Lines = @lines;
SELECT @id = Id FROM #created;
INSERT @r (Name, Expected, Actual) VALUES
    ('create-line-half-cent-rounds-up', N'2.35',
     (SELECT CONVERT(nvarchar(100), LineAmount) FROM dbo.PurchaseOrderLines WHERE PurchaseOrderId = @id AND LineNumber = 1)),
    ('create-line-discounted', N'4.40',
     (SELECT CONVERT(nvarchar(100), LineAmount) FROM dbo.PurchaseOrderLines WHERE PurchaseOrderId = @id AND LineNumber = 2)),
    ('create-total', N'6.75', (SELECT CONVERT(nvarchar(100), TotalAmount) FROM dbo.PurchaseOrders WHERE Id = @id)),
    ('create-number-format', N'ok',
     (SELECT CASE WHEN OrderNumber = CONCAT('PO-', RIGHT(CONCAT('000000', Id), 6)) THEN N'ok' ELSE OrderNumber END
      FROM dbo.PurchaseOrders WHERE Id = @id)),
    ('create-status', N'Pending', (SELECT Status FROM dbo.PurchaseOrders WHERE Id = @id)),
    ('create-audit-row', N'1',
     (SELECT CONVERT(nvarchar(100), COUNT(*)) FROM dbo.AuditLog WHERE PurchaseOrderId = @id AND Action = 'OrderCreated'));
ROLLBACK TRANSACTION;

SELECT TOP 1 @id = Id FROM dbo.Suppliers WHERE IsActive = 0 ORDER BY Id;
SET @e = 0;
BEGIN TRANSACTION;
BEGIN TRY EXEC dbo.usp_CreatePurchaseOrder @SupplierId = @id, @CreatedBy = N'test.user', @Lines = @lines; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
INSERT @r (Name, Expected, Actual) VALUES ('create-inactive-supplier-error', N'50002', CONVERT(nvarchar(100), @e));

DELETE @lines;
SET @e = 0;
BEGIN TRANSACTION;
BEGIN TRY EXEC dbo.usp_CreatePurchaseOrder @SupplierId = 1, @CreatedBy = N'test.user', @Lines = @lines; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
INSERT @r (Name, Expected, Actual) VALUES ('create-no-lines-error', N'50001', CONVERT(nvarchar(100), @e));

-- ---------------------------------------------------------------- usp_SetPurchaseOrderStatus
-- Approve, passing lowercase 'approved': it must be stored as 'Approved'.
SELECT TOP 1 @id = Id, @rv = RowVer FROM dbo.PurchaseOrders WHERE Status = 'Pending' ORDER BY Id;
BEGIN TRANSACTION;
SELECT @n = COUNT(*) FROM dbo.AuditLog WHERE PurchaseOrderId = @id;
INSERT #status EXEC dbo.usp_SetPurchaseOrderStatus
    @Id = @id, @NewStatus = 'approved', @DecidedBy = N'test.approver', @ApprovalLimit = 1000000, @RowVer = @rv;
INSERT @r (Name, Expected, Actual) VALUES
    ('status-approve-stored-canonical', N'Approved', (SELECT Status FROM dbo.PurchaseOrders WHERE Id = @id)),
    ('status-approve-rowver-changed', N'changed',
     (SELECT CASE WHEN RowVer <> @rv THEN N'changed' ELSE N'unchanged' END FROM dbo.PurchaseOrders WHERE Id = @id)),
    ('status-approve-decision-recorded', N'yes',
     (SELECT CASE WHEN DecidedBy = N'test.approver' AND DecidedAt IS NOT NULL THEN N'yes' ELSE N'no' END
      FROM dbo.PurchaseOrders WHERE Id = @id)),
    ('status-approve-audit-row', N'1',
     (SELECT CONVERT(nvarchar(100), COUNT(*) - @n) FROM dbo.AuditLog WHERE PurchaseOrderId = @id));
ROLLBACK TRANSACTION;

SET @e = 0;
BEGIN TRANSACTION;
BEGIN TRY EXEC dbo.usp_SetPurchaseOrderStatus
    @Id = @id, @NewStatus = 'Approved', @DecidedBy = N'test.approver', @ApprovalLimit = 1000000, @RowVer = 0x0000000000000000;
END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
INSERT @r (Name, Expected, Actual) VALUES ('status-stale-rowver-error', N'50003', CONVERT(nvarchar(100), @e));

SET @e = 0;
BEGIN TRANSACTION;
BEGIN TRY EXEC dbo.usp_SetPurchaseOrderStatus
    @Id = @id, @NewStatus = 'Approved', @DecidedBy = N'test.approver', @ApprovalLimit = 0.01, @RowVer = @rv;
END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
INSERT @r (Name, Expected, Actual) VALUES ('status-over-limit-error', N'50005', CONVERT(nvarchar(100), @e));

BEGIN TRANSACTION;
INSERT #status EXEC dbo.usp_SetPurchaseOrderStatus
    @Id = @id, @NewStatus = 'Rejected', @DecidedBy = N'test.approver', @ApprovalLimit = 0.01, @RowVer = @rv;
INSERT @r (Name, Expected, Actual) VALUES
    ('status-reject-ignores-limit', N'Rejected', (SELECT Status FROM dbo.PurchaseOrders WHERE Id = @id));
ROLLBACK TRANSACTION;

SELECT TOP 1 @id = Id, @rv = RowVer FROM dbo.PurchaseOrders WHERE Status = 'Approved' ORDER BY Id;
SET @e = 0;
BEGIN TRANSACTION;
BEGIN TRY EXEC dbo.usp_SetPurchaseOrderStatus
    @Id = @id, @NewStatus = 'Approved', @DecidedBy = N'test.approver', @ApprovalLimit = 1000000, @RowVer = @rv;
END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
INSERT @r (Name, Expected, Actual) VALUES ('status-not-pending-error', N'50004', CONVERT(nvarchar(100), @e));

SET @e = 0;
BEGIN TRANSACTION;
BEGIN TRY EXEC dbo.usp_SetPurchaseOrderStatus
    @Id = 999999, @NewStatus = 'Approved', @DecidedBy = N'test.approver', @ApprovalLimit = 1000000, @RowVer = @rv;
END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
INSERT @r (Name, Expected, Actual) VALUES ('status-missing-order-error', N'50002', CONVERT(nvarchar(100), @e));

SET @e = 0;
BEGIN TRANSACTION;
BEGIN TRY EXEC dbo.usp_SetPurchaseOrderStatus
    @Id = @id, @NewStatus = 'Cancelled', @DecidedBy = N'test.approver', @ApprovalLimit = 1000000, @RowVer = @rv;
END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
INSERT @r (Name, Expected, Actual) VALUES ('status-bad-status-error', N'50001', CONVERT(nvarchar(100), @e));

-- ---------------------------------------------------------------- usp_ExportApprovedOrders
-- A fixed week inside the seed data. Expected rows computed independently from the tables.
SET @expected = (SELECT CONVERT(nvarchar(100), COUNT(*))
                 FROM dbo.PurchaseOrders o JOIN dbo.PurchaseOrderLines l ON l.PurchaseOrderId = o.Id
                 WHERE o.Status = 'Approved' AND o.DecidedAt >= '2026-03-02' AND o.DecidedAt < '2026-03-09');
BEGIN TRANSACTION;
INSERT #export (OrderNumber, SupplierCode, SupplierName, ApprovedAt, ApprovedBy, LineNumber, Sku, Description,
                Quantity, UnitPrice, DiscountPercent, LineAmount, OrderTotal)
EXEC dbo.usp_ExportApprovedOrders @From = '2026-03-02', @To = '2026-03-09';
INSERT @r (Name, Expected, Actual) VALUES
    ('export-row-count', @expected, (SELECT CONVERT(nvarchar(100), COUNT(*)) FROM #export)),
    ('export-window-not-empty', N'yes', (SELECT CASE WHEN COUNT(*) > 0 THEN N'yes' ELSE N'no' END FROM #export)),
    ('export-approved-only', N'0',
     (SELECT CONVERT(nvarchar(100), COUNT(*)) FROM #export e
      JOIN dbo.PurchaseOrders o ON o.OrderNumber = e.OrderNumber WHERE o.Status <> 'Approved')),
    ('export-first-row-is-lowest-order', N'yes',
     (SELECT CASE WHEN OrderNumber = (SELECT MIN(OrderNumber) FROM #export) AND LineNumber = 1 THEN N'yes' ELSE N'no' END
      FROM #export WHERE Seq = (SELECT MIN(Seq) FROM #export)));
ROLLBACK TRANSACTION;

SET @e = 0;
BEGIN TRY EXEC dbo.usp_ExportApprovedOrders @From = '2026-03-09', @To = '2026-03-02'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
INSERT @r (Name, Expected, Actual) VALUES ('export-reversed-window-error', N'50001', CONVERT(nvarchar(100), @e));

-- ---------------------------------------------------------------- results
SELECT CONCAT('RESULT ', Name, ' expected=', Expected, ' actual=', ISNULL(Actual, N'NULL'), ' status=',
              CASE WHEN Actual COLLATE Latin1_General_BIN2 = Expected COLLATE Latin1_General_BIN2 THEN 'PASS' ELSE 'FAIL' END)
FROM @r
ORDER BY Ord;

SELECT CONCAT('RESULT procedure-tests total=', COUNT(*), ' failed=',
              SUM(CASE WHEN Actual COLLATE Latin1_General_BIN2 = Expected COLLATE Latin1_General_BIN2 THEN 0 ELSE 1 END))
FROM @r;
