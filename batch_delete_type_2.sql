-- 1. Use NOLOCK safely on the READ side to grab targets without fighting the shop floor
SELECT id 
INTO #TargetsToPurge
FROM yellow_taxi WITH (NOLOCK)
WHERE tpep_pickup_datetime < '2025-01-01';

-- Create a quick index on your temp table for speed
CREATE CLUSTERED INDEX IX_Temp_ID ON #TargetsToPurge(id);

-- 2. Run your clean batch loop off the isolated temp table
DECLARE @RowsDeleted INT = 1;

WHILE @RowsDeleted > 0
BEGIN
    BEGIN TRANSACTION;

    DELETE TOP (4999) FROM yellow_taxi
    WHERE id IN (SELECT id FROM #TargetsToPurge);

    SET @RowsDeleted = @@ROWCOUNT;

    -- Also prune your temp table so the next subquery pass stays fast
    DELETE TOP (4999) FROM #TargetsToPurge;

    COMMIT TRANSACTION;
END