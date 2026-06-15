SET NOCOUNT ON;

-- ===============================================================================
-- OBJECT NAME:    Global Schema & Column Finder
-- DESCRIPTION:    Searches the system catalog to isolate every table and schema
--                 containing a specific column name pattern.
-- ===============================================================================

DECLARE @ColumnToFind NVARCHAR(128) = '%passenger_count%'; -- Swap this out for your target

SELECT 
    s.name AS [Schema_Name],
    t.name AS [Table_Name],
    c.name AS [Column_Name],
    ty.name AS [Data_Type],
    c.max_length AS [Max_Length_Bytes],
    c.is_nullable AS [Is_Nullable]
FROM sys.columns c
JOIN sys.tables t ON c.object_id = t.object_id
JOIN sys.schemas s ON t.schema_id = s.schema_id
JOIN sys.types ty ON c.user_type_id = ty.user_type_id
WHERE c.name LIKE @ColumnToFind
ORDER BY s.name, t.name;