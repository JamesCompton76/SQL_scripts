SET NOCOUNT ON;

-- ===================================================================================
-- OBJECT NAME:    Text Sanitizer & Hidden Character Stripper Matrix
-- DESCRIPTION:    A multi-pattern toolkit demonstrating pre-flight diagnostic scanning,
--                 inline sanitization, and scale-protected batched string processing.
-- FLAVOR:         Microsoft SQL Server (T-SQL)
-- ===================================================================================

--------------------------------------------------------------------------------------
-- VARIATION 1: DIAGNOSTIC PRE-FLIGHT CHECK & SIDE-BY-SIDE PREVIEW
-- Use Case: Always execute this FIRST. It unmasks non-printable characters 
--           (Carriage Returns, Line Feeds, Tabs) by converting them into readable 
--           text tags, and shows you a live preview of the post-cleanup data state.
--------------------------------------------------------------------------------------

SELECT 
    id, -- Primary or Identifier Key
    repair_notes AS [Original_Raw_Text],
    
    -- Visual Anatomy Check: Swaps hidden anomalies for text tags so they stand out in SSMS grid results
    REPLACE(REPLACE(REPLACE(repair_notes, CHAR(13), '[CR]'), CHAR(10), '[LF]'), CHAR(9), '[TAB]') AS [Visual_Anatomy_Check],
    
    -- Sanitized Preview: Shows exactly what the column values will look like post-update
    REPLACE(REPLACE(REPLACE(repair_notes, CHAR(13), ' '), CHAR(10), ' '), CHAR(9), ' ') AS [Sanitized_Preview]
FROM yellow_taxi
WHERE repair_notes LIKE '%' + CHAR(13) + '%'
   OR repair_notes LIKE '%' + CHAR(10) + '%'
   OR repair_notes LIKE '%' + CHAR(9) + '%';

--------------------------------------------------------------------------------------
-- ----------------------------------------------------------------------------------
--------------------------------------------------------------------------------------

--------------------------------------------------------------------------------------
-- VARIATION 2: HIGH-VELOCITY INLINE SANITIZATION
-- Use Case: Applied when your Pre-Flight Check (Variation 1) surfaces a small-to-medium 
--           volume of affected rows (e.g., under 5,000). Executes instantly.
--------------------------------------------------------------------------------------

UPDATE yellow_taxi
SET repair_notes = REPLACE(REPLACE(REPLACE(repair_notes, CHAR(13), ' '), CHAR(10), ' '), CHAR(9), ' ')
WHERE repair_notes LIKE '%' + CHAR(13) + '%'
   OR repair_notes LIKE '%' + CHAR(10) + '%'
   OR repair_notes LIKE '%' + CHAR(9) + '%';

--------------------------------------------------------------------------------------
-- ----------------------------------------------------------------------------------
--------------------------------------------------------------------------------------

--------------------------------------------------------------------------------------
-- VARIATION 3: SCALE-PROTECTED CONCURRENCY-SAFE PROCESSING (THE BATCHED LOOP)
-- Use Case: Applied when Variation 1 returns a massive row count (e.g., millions of 
--           broken fields). It chips away at the dataset using explicit transactions,
--           preventing lock escalation and transaction log exhaustion.
--------------------------------------------------------------------------------------

DECLARE @RowsUpdated INT = 1;
DECLARE @TotalRowsUpdated BIGINT = 0;
DECLARE @BatchIteration INT = 1;

PRINT 'Starting scale-protected text sanitization loop...';

WHILE @RowsUpdated > 0
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Process up to 4,999 records per batch to slide safely under the lock escalation barrier
        UPDATE TOP (4999) yellow_taxi
        SET repair_notes = REPLACE(REPLACE(REPLACE(repair_notes, CHAR(13), ' '), CHAR(10), ' '), CHAR(9), ' ')
        WHERE repair_notes LIKE '%' + CHAR(13) + '%'
           OR repair_notes LIKE '%' + CHAR(10) + '%'
           OR repair_notes LIKE '%' + CHAR(9) + '%';

        SET @RowsUpdated = @@ROWCOUNT;
        SET @TotalRowsUpdated = @TotalRowsUpdated + @RowsUpdated;

        COMMIT TRANSACTION;

        -- Print progress status updates
        IF @BatchIteration % 10 = 0 AND @RowsUpdated > 0
        BEGIN
            RAISERROR('Iteration %d: Total text fields sanitized so far = %I64d', 0, 1, @BatchIteration, @TotalRowsUpdated) WITH NOWAIT;
        END

        SET @BatchIteration = @BatchIteration + 1;

        -- Optional Throttling Hook: Uncomment if running on highly active shopfloor databases
        -- WAITFOR DELAY '00:00:00.050';

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        DECLARE @SanitizeError NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR (@SanitizeError, 16, 1);
        BREAK;
    END CATCH
END

PRINT '===============================================================================';
RAISERROR('Text sanitization complete! Total records altered: %I64d', 0, 1, @TotalRowsUpdated) WITH NOWAIT;
PRINT '===============================================================================';