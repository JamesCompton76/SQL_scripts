SELECT TOP 10
    total_worker_time / 1000000 AS [Total_CPU_Sec],
    execution_count AS [Execution_Count],
    (total_worker_time / execution_count) / 1000 AS [Avg_CPU_Ms],
    total_logical_reads AS [Total_Logical_Reads],
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1, 
        ((CASE qs.statement_end_offset 
            WHEN -1 THEN DATALENGTH(st.text) 
            ELSE qs.statement_end_offset END 
        - qs.statement_start_offset)/2) + 1) AS [Query_Text],
    qp.query_plan AS [Graphical_Execution_Plan]
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
ORDER BY total_worker_time DESC;