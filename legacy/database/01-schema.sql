-- PurchaseDesk legacy schema: four tables, written the way a small line-of-business app usually is.
-- Several choices here are deliberate legacy traits that the migration to PostgreSQL has to handle:
--   money amounts, datetime without a time zone, GETDATE() defaults, IDENTITY keys, a rowversion token,
--   a nullable sortable date, and uniqueness that relies on the case-insensitive collation.
-- Run once, against an empty PurchaseDesk database.
USE PurchaseDesk;
GO

SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'dbo.Suppliers', N'U') IS NOT NULL
BEGIN
    RAISERROR(N'The schema already exists. Recreate the database to load it again.', 16, 1);
    SET NOEXEC ON; -- skip the rest of the script
END
GO

BEGIN TRANSACTION;
GO

CREATE TABLE dbo.Suppliers
(
    Id          int            IDENTITY(1, 1) NOT NULL,
    Code        varchar(20)    NOT NULL,  -- unique case-insensitively: 'ACME' and 'acme' collide
    Name        nvarchar(200)  NOT NULL,
    Email       varchar(254)   NULL,
    IsActive    bit            NOT NULL CONSTRAINT DF_Suppliers_IsActive DEFAULT (1),
    CreatedAt   datetime       NOT NULL CONSTRAINT DF_Suppliers_CreatedAt DEFAULT (GETDATE()),

    CONSTRAINT PK_Suppliers PRIMARY KEY CLUSTERED (Id),
    CONSTRAINT UQ_Suppliers_Code UNIQUE (Code)
);
GO

CREATE TABLE dbo.PurchaseOrders
(
    Id           int            IDENTITY(1, 1) NOT NULL,
    OrderNumber  varchar(20)    NOT NULL,  -- assigned by usp_CreatePurchaseOrder
    SupplierId   int            NOT NULL,
    Status       varchar(10)    NOT NULL CONSTRAINT DF_PurchaseOrders_Status DEFAULT ('Pending'),
    OrderDate    datetime       NOT NULL CONSTRAINT DF_PurchaseOrders_OrderDate DEFAULT (GETDATE()),
    RequiredBy   date           NULL,      -- sortable in search; SQL Server sorts NULL first
    Notes        nvarchar(500)  NULL,
    TotalAmount  money          NOT NULL CONSTRAINT DF_PurchaseOrders_TotalAmount DEFAULT (0),
    CreatedBy    nvarchar(100)  NOT NULL,
    DecidedBy    nvarchar(100)  NULL,
    DecidedAt    datetime       NULL,
    RowVer       rowversion     NOT NULL,  -- concurrency token for approve and reject

    CONSTRAINT PK_PurchaseOrders PRIMARY KEY CLUSTERED (Id),
    CONSTRAINT UQ_PurchaseOrders_OrderNumber UNIQUE (OrderNumber),
    CONSTRAINT FK_PurchaseOrders_Suppliers FOREIGN KEY (SupplierId) REFERENCES dbo.Suppliers (Id),
    CONSTRAINT CK_PurchaseOrders_Status CHECK (Status IN ('Pending', 'Approved', 'Rejected')),
    CONSTRAINT CK_PurchaseOrders_TotalAmount CHECK (TotalAmount >= 0),
    CONSTRAINT CK_PurchaseOrders_Decision CHECK (
        (Status = 'Pending' AND DecidedBy IS NULL AND DecidedAt IS NULL)
        OR (Status IN ('Approved', 'Rejected') AND DecidedBy IS NOT NULL AND DecidedAt IS NOT NULL))
);
GO

CREATE INDEX IX_PurchaseOrders_SupplierId ON dbo.PurchaseOrders (SupplierId);
CREATE INDEX IX_PurchaseOrders_Status_OrderDate ON dbo.PurchaseOrders (Status, OrderDate);
GO

CREATE TABLE dbo.PurchaseOrderLines
(
    Id               int            IDENTITY(1, 1) NOT NULL,
    PurchaseOrderId  int            NOT NULL,
    LineNumber       smallint       NOT NULL,
    Sku              varchar(40)    NOT NULL,
    Description      nvarchar(200)  NOT NULL,
    Quantity         int            NOT NULL,
    UnitPrice        money          NOT NULL,
    DiscountPercent  decimal(5, 2)  NOT NULL CONSTRAINT DF_PurchaseOrderLines_DiscountPercent DEFAULT (0),
    LineAmount       money          NOT NULL,  -- computed by usp_CreatePurchaseOrder with T-SQL ROUND

    CONSTRAINT PK_PurchaseOrderLines PRIMARY KEY CLUSTERED (Id),
    -- Also serves as the index for finding an order's lines (PurchaseOrderId leads).
    CONSTRAINT UQ_PurchaseOrderLines_Order_Line UNIQUE (PurchaseOrderId, LineNumber),
    CONSTRAINT FK_PurchaseOrderLines_PurchaseOrders FOREIGN KEY (PurchaseOrderId) REFERENCES dbo.PurchaseOrders (Id),
    CONSTRAINT CK_PurchaseOrderLines_Quantity CHECK (Quantity > 0),
    CONSTRAINT CK_PurchaseOrderLines_UnitPrice CHECK (UnitPrice >= 0),
    CONSTRAINT CK_PurchaseOrderLines_DiscountPercent CHECK (DiscountPercent BETWEEN 0 AND 100)
);
GO

CREATE TABLE dbo.AuditLog
(
    Id               bigint          IDENTITY(1, 1) NOT NULL,
    OccurredAt       datetime        NOT NULL CONSTRAINT DF_AuditLog_OccurredAt DEFAULT (GETDATE()),  -- server local time
    Action           varchar(30)     NOT NULL,
    PurchaseOrderId  int             NULL,  -- no foreign key: audit rows outlive what they describe
    Actor            nvarchar(100)   NOT NULL,
    Detail           nvarchar(1000)  NULL,

    CONSTRAINT PK_AuditLog PRIMARY KEY CLUSTERED (Id)
);
GO

COMMIT TRANSACTION;
GO

SET NOEXEC OFF;
GO
