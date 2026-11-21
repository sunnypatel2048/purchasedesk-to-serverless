USE PurchaseDesk;
GO

-- GET /api/purchase-orders/{id}. Two result sets: the header (no row means 404), then its lines.
-- RowVer is the concurrency token the client sends back to approve or reject.
CREATE OR ALTER PROCEDURE dbo.usp_GetPurchaseOrder
    @Id int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        o.Id,
        o.OrderNumber,
        o.SupplierId,
        s.Code AS SupplierCode,
        s.Name AS SupplierName,
        o.Status,
        o.OrderDate,
        o.RequiredBy,
        o.Notes,
        o.TotalAmount,
        o.CreatedBy,
        o.DecidedBy,
        o.DecidedAt,
        o.RowVer
    FROM dbo.PurchaseOrders o
    JOIN dbo.Suppliers s ON s.Id = o.SupplierId
    WHERE o.Id = @Id;

    SELECT LineNumber, Sku, Description, Quantity, UnitPrice, DiscountPercent, LineAmount
    FROM dbo.PurchaseOrderLines
    WHERE PurchaseOrderId = @Id
    ORDER BY LineNumber;
END
GO
