SET NOCOUNT ON;

-- ===================================================================================
-- OBJECT NAME:    CTE-Based Record De-duplication Matrix
-- DESCRIPTION:    A multi-pattern toolkit demonstrating structural de-duplication
--                 and tagging via Transact-SQL Common Table Expressions (CTEs).
-- FLAVOR:         Microsoft SQL Server (T-SQL)
-- ===================================================================================

--------------------------------------------------------------------------------------
-- VARIATION 1: SURGICAL HARD-DELETE USING A PRIMARY KEY
-- Use Case: Elements are duplicates based on business data, but possess distinct
--           auto-incrementing or surrogate primary keys. This pattern allows you
--           to deterministically choose which record survives.
--------------------------------------------------------------------------------------

WITH cte_dedup_pk AS (
    SELECT 
        taxi_record_id, -- Surrogate Primary Key
        ROW_NUMBER() OVER (
            PARTITION BY vendor_id, tpep_pickup_datetime, passenger_count -- Business Keys
            ORDER BY taxi_record_id ASC                                  -- Keeps the OLDEST record (1)
        ) AS row_num
    FROM yellow_taxi
)
-- Shred rows marked as row_num > 1 (destroys the newer duplicates, protects the original)
DELETE FROM cte_dedup_pk
WHERE row_num > 1;

--------------------------------------------------------------------------------------
-- ----------------------------------------------------------------------------------
--------------------------------------------------------------------------------------

--------------------------------------------------------------------------------------
-- VARIATION 2: AUDIT-SAFE SOFT-DELETE / DATA TAGGING (UPDATE PATTERN)
-- Use Case: You want to maintain absolute data lineage in your OBT/Data Warehouse layer.
--           Instead of destroying records, this updates a status flag in the base
--           table via the CTE pointer map for downstream View filtering.
--------------------------------------------------------------------------------------

WITH cte_tag_duplicates AS (
    SELECT 
        is_duplicate, -- Physical BIT/INT column residing in the base table
        ROW_NUMBER() OVER (
            PARTITION BY vendor_id, tpep_pickup_datetime, passenger_count
            ORDER BY taxi_record_id ASC
        ) AS row_num
    FROM yellow_taxi
)
-- Execute an UPDATE directly against the CTE layout
-- CRITICAL GUARDRAIL: You can update base columns, but you can NEVER update "row_num"
UPDATE cte_tag_duplicates
SET is_duplicate = 1
WHERE row_num > 1;

--------------------------------------------------------------------------------------
-- ----------------------------------------------------------------------------------
--------------------------------------------------------------------------------------

--------------------------------------------------------------------------------------
-- VARIATION 3: HEAP TABLES / PURE FLAT OBT (NO PRIMARY KEYS)
-- Use Case: A flat staging or analytical table containing no unique identifiers where 
--           rows are complete mirror images of each other. Uses an execution-plan
--           optimization trick to strip sorting overhead.
--------------------------------------------------------------------------------------

WITH cte_dedup_heap AS (
    SELECT 
        ROW_NUMBER() OVER (
            PARTITION BY vendor_id, tpep_pickup_datetime, passenger_count, trip_distance, fare_amount -- Partition by ALL columns
            ORDER BY (SELECT NULL) -- Optimization: Bypasses CPU sort phase; tells the engine to number arbitrary page order
        ) AS row_num
    FROM yellow_taxi
)
DELETE FROM cte_dedup_heap
WHERE row_num > 1;