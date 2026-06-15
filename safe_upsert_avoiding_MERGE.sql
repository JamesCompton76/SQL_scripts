SET NOCOUNT ON;

-- ===============================================================================
-- OBJECT NAME:    Concurrency-Safe Idempotent Upsert Pattern
-- DESCRIPTION:    Safely executes an incremental "Update or Insert" pipeline
--                 without the concurrency hazards or deadlock bugs of MERGE.
-- ===============================================================================

BEGIN TRY
    BEGIN TRANSACTION;

    -- Phase 1: Update rows that already exist in the target OBT layer.
    -- UPDLOCK + SERIALIZABLE forces competing threads to queue up nicely.
    UPDATE target_obt WITH (UPDLOCK, SERIALIZABLE)
    SET target_obt.tool_status = staging.tool_status,
        target_obt.last_modified = staging.last_modified
    FROM target_obt
    JOIN staging_shopfloor_records staging ON target_obt.tool_id = staging.tool_id;

    -- Phase 2: Insert rows that don't exist yet.
    INSERT INTO target_obt (tool_id, tool_status, last_modified)
    SELECT 
        staging.tool_id,
        staging.tool_status,
        staging.last_modified
    FROM staging_shopfloor_records staging
    WHERE NOT EXISTS (
        SELECT 1 
        FROM target_obt target
        WHERE target.tool_id = staging.tool_id
    );

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    
    DECLARE @UpsertError NVARCHAR(4000) = ERROR_MESSAGE();
    RAISERROR (@UpsertError, 16, 1);
END CATCH