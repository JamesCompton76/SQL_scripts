SET NOCOUNT ON;

-- ===============================================================================
-- OBJECT NAME:    Batched Delete for yellow_taxi
-- DESCRIPTION:    Deletes data in chunks of 4,999 rows to prevent lock escalation
--                 and control transaction log growth.
-- ===============================================================================

DECLARE @BatchSize INT = 4999;
DECLARE @RowsDeleted INT = 1;
DECLARE @TotalRowsDeleted BIGINT = 0;
DECLARE @Iteration INT = 1;

-- Optional: Adjust this to drop a safe condition placeholder 
-- (e.g., deleting data older than a certain date)
PRINT 'Starting batched delete operation on [yellow_taxi]...';

WHILE @RowsDeleted > 0
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Force set-based delete capped exactly at the 4,999 safety threshold
        DELETE TOP (@BatchSize)
        FROM yellow_taxi
        WHERE tpep_pickup_datetime < '2025-01-01'; -- <-- CHANGE THIS CONDITION TO MATCH YOUR BUSINESS LOGIC

        -- Capture the number of rows affected in this specific pass
        SET @RowsDeleted = @@ROWCOUNT;
        SET @TotalRowsDeleted = @TotalRowsDeleted + @RowsDeleted;

        COMMIT TRANSACTION;

        -- Progress monitoring: Print status every 10 iterations to prevent SSMS buffer bloat
        IF @Iteration % 10 = 0 AND @RowsDeleted > 0
        BEGIN
            RAISERROR('Iteration %d: Total rows deleted so far = %I64d', 0, 1, @Iteration, @TotalRowsDeleted) WITH NOWAIT;
        END

        SET @Iteration = @Iteration + 1;

        -- Optional Throttling Guardrail: 
        -- If running on a live production cluster during business hours, uncomment the line below 
        -- to give the storage engine a 100-millisecond breather between disk writes.
        -- WAITFOR DELAY '00:00:00.100';

    END TRY
    BEGIN CATCH
        -- Defensive Rollback: If an individual batch fails (e.g., deadlock victim), 
        -- roll back the active transaction safely without corrupting prior batches.
        IF @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        -- Surface the exact engine error and terminate gracefully
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        
        RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
        BREAK;
    END CATCH
END

PRINT '===============================================================================';
RAISERROR('Deletion complete! Total iterations: %d | Total records removed: %I64d', 0, 1, @Iteration, @TotalRowsDeleted) WITH NOWAIT;
PRINT '===============================================================================';