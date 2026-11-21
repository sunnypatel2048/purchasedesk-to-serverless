USE PurchaseDesk;
GO

-- GET /api/suppliers. The app caches this in memory for 10 minutes.
-- Sorted by Name under the case-insensitive collation; Id breaks ties ('Northwind Traders' = 'northwind traders').
CREATE OR ALTER PROCEDURE dbo.usp_ListSuppliers
    @IncludeInactive bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Code, Name, Email, IsActive
    FROM dbo.Suppliers
    WHERE IsActive = 1 OR @IncludeInactive = 1
    ORDER BY Name, Id;
END
GO
