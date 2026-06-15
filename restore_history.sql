SELECT  
  [restore_date]
  ,LEAD(restore_date) OVER (PARTITION BY destination_database_name ORDER BY restore_date ASC) as next_date
      ,[destination_database_name]
      ,[user_name]
      ,[backup_set_id]
      ,[restore_type]
      ,[replace]
      ,[recovery]
      ,[restart]
  FROM [msdb].[dbo].[restorehistory]
