SELECT 
    r.session_id AS [Blocked_SPID],
    r.blocking_session_id AS [Blocking_SPID],
    s.host_name AS [Client_Machine],
    s.program_name AS [Application],
    s.login_name AS [User_Login],
    DB_NAME(r.database_id) AS [DatabaseName],
    r.wait_time / 1000 AS [Wait_Time_Sec],
    r.wait_type AS [Wait_Reason],
    st.text AS [Blocked_SQL_Text],
    bst.text AS [Blocking_SQL_Text]
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) st
LEFT JOIN sys.dm_exec_requests br ON r.blocking_session_id = br.session_id
OUTER APPLY sys.dm_exec_sql_text(br.sql_handle) bst
WHERE r.blocking_session_id <> 0;