USE PurchaseDesk;
GO

-- GET /api/purchase-orders: filter, sort and page. The total match count comes back in @TotalCount.
-- Legacy behaviour the migration must keep or consciously change:
--   * @Text matches order number or notes case-insensitively ('urgent' finds 'URGENT'), via the collation.
--     It is not escaped, so % and _ in the text act as wildcards.
--   * Sorting by RequiredBy puts NULL first ascending and last descending (PostgreSQL does the opposite).
--   * Enum-like arguments are compared case-insensitively ('desc' works).
--   * Id breaks ties so paging is stable.
CREATE OR ALTER PROCEDURE dbo.usp_SearchPurchaseOrders
    @SupplierId  int           = NULL,
    @Status      varchar(10)   = NULL,
    @FromDate    datetime      = NULL,  -- inclusive, on OrderDate
    @ToDate      datetime      = NULL,  -- exclusive, on OrderDate
    @Text        nvarchar(100) = NULL,
    @SortBy      varchar(20)   = 'OrderDate',
    @SortDir     varchar(4)    = 'DESC',
    @Page        int           = 1,
    @PageSize    int           = 25,
    @TotalCount  int           = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF @SortBy NOT IN ('OrderDate', 'RequiredBy', 'TotalAmount', 'OrderNumber')
        THROW 50001, N'SortBy must be OrderDate, RequiredBy, TotalAmount or OrderNumber.', 1;
    IF @SortDir NOT IN ('ASC', 'DESC')
        THROW 50001, N'SortDir must be ASC or DESC.', 1;
    IF @Status IS NOT NULL AND @Status NOT IN ('Pending', 'Approved', 'Rejected')
        THROW 50001, N'Status must be Pending, Approved or Rejected.', 1;
    IF @Page IS NULL OR @Page < 1 OR @PageSize IS NULL OR @PageSize < 1 OR @PageSize > 100
        THROW 50001, N'Page must be 1 or more and PageSize from 1 to 100.', 1;

    DECLARE @Pattern nvarchar(102) =
        CASE WHEN NULLIF(@Text, N'') IS NULL THEN NULL ELSE N'%' + @Text + N'%' END;

    SELECT o.Id
    INTO #matches
    FROM dbo.PurchaseOrders o
    WHERE (@SupplierId IS NULL OR o.SupplierId = @SupplierId)
      AND (@Status IS NULL OR o.Status = @Status)
      AND (@FromDate IS NULL OR o.OrderDate >= @FromDate)
      AND (@ToDate IS NULL OR o.OrderDate < @ToDate)
      AND (@Pattern IS NULL OR o.OrderNumber LIKE @Pattern OR o.Notes LIKE @Pattern);

    SET @TotalCount = @@ROWCOUNT;

    SELECT
        o.Id,
        o.OrderNumber,
        o.SupplierId,
        s.Name AS SupplierName,
        o.Status,
        o.OrderDate,
        o.RequiredBy,
        o.TotalAmount,
        (SELECT COUNT(*) FROM dbo.PurchaseOrderLines l WHERE l.PurchaseOrderId = o.Id) AS LineCount
    FROM #matches m
    JOIN dbo.PurchaseOrders o ON o.Id = m.Id
    JOIN dbo.Suppliers s ON s.Id = o.SupplierId
    ORDER BY
        CASE WHEN @SortBy = 'OrderDate'   AND @SortDir = 'ASC'  THEN o.OrderDate   END ASC,
        CASE WHEN @SortBy = 'OrderDate'   AND @SortDir = 'DESC' THEN o.OrderDate   END DESC,
        CASE WHEN @SortBy = 'RequiredBy'  AND @SortDir = 'ASC'  THEN o.RequiredBy  END ASC,
        CASE WHEN @SortBy = 'RequiredBy'  AND @SortDir = 'DESC' THEN o.RequiredBy  END DESC,
        CASE WHEN @SortBy = 'TotalAmount' AND @SortDir = 'ASC'  THEN o.TotalAmount END ASC,
        CASE WHEN @SortBy = 'TotalAmount' AND @SortDir = 'DESC' THEN o.TotalAmount END DESC,
        CASE WHEN @SortBy = 'OrderNumber' AND @SortDir = 'ASC'  THEN o.OrderNumber END ASC,
        CASE WHEN @SortBy = 'OrderNumber' AND @SortDir = 'DESC' THEN o.OrderNumber END DESC,
        o.Id ASC
    OFFSET (@Page - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;
END
GO
