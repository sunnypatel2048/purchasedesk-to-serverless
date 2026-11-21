-- Table-valued parameter for passing order lines to usp_CreatePurchaseOrder (ADO.NET SqlDbType.Structured).
-- Rerunnable. A type cannot be altered in place: changing it means dropping the procedures that use it first.
USE PurchaseDesk;
GO

IF TYPE_ID(N'dbo.PurchaseOrderLineInput') IS NULL
    CREATE TYPE dbo.PurchaseOrderLineInput AS TABLE
    (
        LineNumber       smallint       NOT NULL PRIMARY KEY,
        Sku              varchar(40)    NOT NULL,
        Description      nvarchar(200)  NOT NULL,
        Quantity         int            NOT NULL,
        UnitPrice        money          NOT NULL,
        DiscountPercent  decimal(5, 2)  NOT NULL DEFAULT (0)
    );
GO
