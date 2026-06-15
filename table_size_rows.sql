SELECT	t.name AS TableName,
		s.name AS SchemaName,
		SUM(ps.row_count) AS ActualRowCounts, 
		CAST(ROUND(((SUM(ps.reserved_page_count) * 8) / 1024.00), 2) AS NUMERIC(36, 2)) AS TotalReservedSpaceMB,
		CAST(ROUND(((SUM(ps.used_page_count) * 8) / 1024.00), 2) AS NUMERIC(36, 2)) AS UsedSpaceMB,
		'WIP - still testing' as note
FROM	DBWV2J9900.sys.tables t
		JOIN	DBWV2J9900.sys.schemas s ON t.schema_id = s.schema_id
		JOIN	DBWV2J9900.sys.dm_db_partition_stats ps ON t.object_id = ps.object_id
WHERE	t.is_ms_shipped = 0 -- Exclude system objects
		AND ps.index_id IN (0, 1) -- Only consider the main data structure (Heap or Clustered Index) for counting/sizing
GROUP BY t.object_id, t.name, s.name

