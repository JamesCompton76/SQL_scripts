SELECT 
    OBJECT_NAME(ips.object_id) AS [TableName],
    i.name AS [IndexName],
    ips.index_type_desc AS [IndexType],
    CAST(ips.avg_fragmentation_in_percent AS NUMERIC(5,2)) AS [Fragmentation_%],
    ips.page_count AS [Total_Pages],
    CASE 
        WHEN ips.avg_fragmentation_in_percent > 30 THEN 'ALTER INDEX ALL ON ' + OBJECT_NAME(ips.object_id) + ' REBUILD;'
        WHEN ips.avg_fragmentation_in_percent BETWEEN 10 AND 30 THEN 'ALTER INDEX ALL ON ' + OBJECT_NAME(ips.object_id) + ' REORGANIZE;'
        ELSE 'Healthy'
    END AS [Recommended_Action]
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.avg_fragmentation_in_percent > 10 -- Only show indexes needing attention
  AND ips.page_count > 1000                 -- Ignore tiny tables where fragmentation doesn't matter
ORDER BY ips.avg_fragmentation_in_percent DESC;