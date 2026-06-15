SET NOCOUNT ON;

-- ===============================================================================
-- OBJECT NAME:    Safe Type-Casting & Data Quality Audit
-- DESCRIPTION:    Identifies corrupt or non-conformant alphanumeric strings that 
--                 will crash downstream analytical type conversions.
-- ===============================================================================

-- Step 1: Scan for data that fails Numeric/Decimal conversion rules
SELECT 
    id,
    raw_measurement AS [Corrupt_Value],
    'Failed Numeric Conversion' AS [Violation_Reason]
FROM staging_warehouse_logs
WHERE TRY_CAST(raw_measurement AS NUMERIC(18,4)) IS NULL 
  AND raw_measurement IS NOT NULL;

-- Step 2: Scan for data that fails chronological/ISO Date conversion rules
SELECT 
    id,
    raw_timestamp_string AS [Corrupt_Value],
    'Failed Date Conversion' AS [Violation_Reason]
FROM staging_warehouse_logs
WHERE TRY_CAST(raw_timestamp_string AS DATETIME2) IS NULL 
  AND raw_timestamp_string IS NOT NULL;