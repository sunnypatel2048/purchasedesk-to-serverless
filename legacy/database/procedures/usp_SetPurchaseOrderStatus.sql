USE PurchaseDesk;
GO

-- POST /api/purchase-orders/{id}/approve and /reject. Returns the new Status and RowVer.
-- Checks, in order: the order exists (50002), RowVer matches (50003), it is still Pending (50004),
-- and for approval only, the total is within @ApprovalLimit (50005). Rejection ignores the limit.
-- The limit comes from the app's Web.config, not from the database.
CREATE OR ALTER PROCEDURE dbo.usp_SetPurchaseOrderStatus
    @Id             int,
    @NewStatus      varchar(10),
    @DecidedBy      nvarchar(100),
    @ApprovalLimit  money,
    @RowVer         binary(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- The collation would let 'approved' through and store it as typed, so store the canonical spelling.
    SET @NewStatus = CASE @NewStatus WHEN 'Approved' THEN 'Approved' WHEN 'Rejected' THEN 'Rejected' END;

    IF @NewStatus IS NULL
        THROW 50001, N'NewStatus must be Approved or Rejected.', 1;
    IF NULLIF(LTRIM(RTRIM(@DecidedBy)), N'') IS NULL
        THROW 50001, N'DecidedBy is required.', 1;

    BEGIN TRANSACTION;

    DECLARE @CurrentRowVer binary(8), @Status varchar(10), @Total money;

    SELECT @CurrentRowVer = RowVer, @Status = Status, @Total = TotalAmount
    FROM dbo.PurchaseOrders WITH (UPDLOCK, ROWLOCK)
    WHERE Id = @Id;

    IF @@ROWCOUNT = 0
        THROW 50002, N'Purchase order not found.', 1;
    IF @CurrentRowVer <> @RowVer
        THROW 50003, N'The purchase order was changed by someone else. Reload it and try again.', 1;
    IF @Status <> 'Pending'
        THROW 50004, N'Only a Pending purchase order can be approved or rejected.', 1;
    IF @NewStatus = 'Approved' AND @Total > @ApprovalLimit
        THROW 50005, N'The order total is over the approval limit.', 1;

    UPDATE dbo.PurchaseOrders
    SET Status = @NewStatus, DecidedBy = @DecidedBy, DecidedAt = GETDATE()
    WHERE Id = @Id;

    INSERT dbo.AuditLog (Action, PurchaseOrderId, Actor, Detail)
    SELECT CASE @NewStatus WHEN 'Approved' THEN 'OrderApproved' ELSE 'OrderRejected' END,
           Id, @DecidedBy, CONCAT(Status, N' ', OrderNumber)
    FROM dbo.PurchaseOrders
    WHERE Id = @Id;

    COMMIT TRANSACTION;

    SELECT Id, Status, RowVer
    FROM dbo.PurchaseOrders
    WHERE Id = @Id;
END
GO
