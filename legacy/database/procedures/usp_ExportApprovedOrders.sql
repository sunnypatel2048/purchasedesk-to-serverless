USE PurchaseDesk;
GO

-- The nightly export: approved orders decided in [@From, @To), one row per line.
-- With no arguments it exports yesterday, by the server's local clock.
CREATE OR ALTER PROCEDURE dbo.usp_ExportApprovedOrders
    @From  datetime = NULL,
    @To    datetime = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @From IS NULL
        SET @From = DATEADD(day, -1, CAST(CAST(GETDATE() AS date) AS datetime));
    IF @To IS NULL
        SET @To = DATEADD(day, 1, @From);
    IF @To <= @From
        THROW 50001, N'To must be later than From.', 1;

    SELECT
        o.OrderNumber,
        s.Code AS SupplierCode,
        s.Name AS SupplierName,
        o.DecidedAt AS ApprovedAt,
        o.DecidedBy AS ApprovedBy,
        l.LineNumber,
        l.Sku,
        l.Description,
        l.Quantity,
        l.UnitPrice,
        l.DiscountPercent,
        l.LineAmount,
        o.TotalAmount AS OrderTotal
    FROM dbo.PurchaseOrders o
    JOIN dbo.Suppliers s ON s.Id = o.SupplierId
    JOIN dbo.PurchaseOrderLines l ON l.PurchaseOrderId = o.Id
    WHERE o.Status = 'Approved'
      AND o.DecidedAt >= @From
      AND o.DecidedAt < @To
    ORDER BY o.OrderNumber, l.LineNumber;
END
GO
