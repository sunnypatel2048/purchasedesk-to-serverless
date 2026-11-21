USE PurchaseDesk;
GO

-- GET /api/suppliers/{id}. No row means 404. Inactive suppliers are returned too.
CREATE OR ALTER PROCEDURE dbo.usp_GetSupplier
    @Id int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Code, Name, Email, IsActive, CreatedAt
    FROM dbo.Suppliers
    WHERE Id = @Id;
END
GO
