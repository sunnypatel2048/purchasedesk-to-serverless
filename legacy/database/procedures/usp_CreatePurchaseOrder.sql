USE PurchaseDesk;
GO

-- POST /api/purchase-orders. One transaction: validate, insert the header, number it, insert the lines,
-- total them, write the audit row. Returns the new Id and OrderNumber.
-- Legacy behaviour the migration must keep or consciously change:
--   * LineAmount = ROUND(Quantity * UnitPrice * (1 - DiscountPercent / 100), 2): T-SQL ROUND, half away from zero.
--     The seed uses the identical expression.
--   * OrderDate and the audit time come from GETDATE(), the server's local clock.
--   * No idempotency: submitting the same order twice creates two orders.
--   * The number is assigned from the new identity via a placeholder, inside the same transaction.
CREATE OR ALTER PROCEDURE dbo.usp_CreatePurchaseOrder
    @SupplierId  int,
    @RequiredBy  date          = NULL,
    @Notes       nvarchar(500) = NULL,
    @CreatedBy   nvarchar(100),
    @Lines       dbo.PurchaseOrderLineInput READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NULLIF(LTRIM(RTRIM(@CreatedBy)), N'') IS NULL
        THROW 50001, N'CreatedBy is required.', 1;
    IF NOT EXISTS (SELECT 1 FROM @Lines)
        THROW 50001, N'An order needs at least one line.', 1;
    IF (SELECT COUNT(*) FROM @Lines) > 50
        THROW 50001, N'An order can have at most 50 lines.', 1;
    IF EXISTS (SELECT 1 FROM @Lines
               WHERE Quantity <= 0 OR UnitPrice < 0 OR DiscountPercent < 0 OR DiscountPercent > 100)
        THROW 50001, N'Each line needs a positive quantity, a price of zero or more and a discount from 0 to 100.', 1;

    BEGIN TRANSACTION;

    IF NOT EXISTS (SELECT 1 FROM dbo.Suppliers WHERE Id = @SupplierId AND IsActive = 1)
        THROW 50002, N'Supplier not found or inactive.', 1;

    DECLARE @Id int;

    -- The placeholder is unique per connection; it is replaced before the transaction commits.
    INSERT dbo.PurchaseOrders (OrderNumber, SupplierId, RequiredBy, Notes, CreatedBy)
    VALUES (CONCAT('PO-NEW-', @@SPID), @SupplierId, @RequiredBy, @Notes, @CreatedBy);

    SET @Id = SCOPE_IDENTITY();

    UPDATE dbo.PurchaseOrders
    SET OrderNumber = CONCAT('PO-', RIGHT(CONCAT('000000', @Id), 6))
    WHERE Id = @Id;

    INSERT dbo.PurchaseOrderLines
        (PurchaseOrderId, LineNumber, Sku, Description, Quantity, UnitPrice, DiscountPercent, LineAmount)
    SELECT @Id, LineNumber, Sku, Description, Quantity, UnitPrice, DiscountPercent,
           ROUND(Quantity * UnitPrice * (1 - DiscountPercent / 100), 2)
    FROM @Lines;

    UPDATE dbo.PurchaseOrders
    SET TotalAmount = (SELECT SUM(LineAmount) FROM dbo.PurchaseOrderLines WHERE PurchaseOrderId = @Id)
    WHERE Id = @Id;

    INSERT dbo.AuditLog (Action, PurchaseOrderId, Actor, Detail)
    SELECT 'OrderCreated', Id, CreatedBy,
           CONCAT(N'Created ', OrderNumber, N' for ', CONVERT(varchar(30), TotalAmount, 0))
    FROM dbo.PurchaseOrders
    WHERE Id = @Id;

    COMMIT TRANSACTION;

    SELECT Id, OrderNumber
    FROM dbo.PurchaseOrders
    WHERE Id = @Id;
END
GO
