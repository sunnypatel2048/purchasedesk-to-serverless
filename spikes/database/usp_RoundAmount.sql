-- Phase 0.3 spike: the smallest stored procedure that shows a real SQL Server behaviour.
-- T-SQL ROUND rounds half away from zero (2.5 -> 3); C# Math.Round rounds half to even (2.5 -> 2).
CREATE OR ALTER PROCEDURE dbo.usp_RoundAmount
    @Amount decimal(19, 4)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ROUND(@Amount, 0) AS Rounded;
END
