SET NOCOUNT ON;

-- ===============================================================================
-- OBJECT NAME:    Database Role & Permission Auditor
-- DESCRIPTION:    Maps database user accounts to their assigned roles and system-level
--                 logins. Essential for tracking data visibility and access control.
-- ===============================================================================

SELECT 
    dp.name AS [Database_User],
    dp.type_desc AS [User_Type],
    sp.name AS [Server_Login],
    p.name AS [Assigned_Role]
FROM sys.database_principals dp
JOIN sys.database_role_members drm ON dp.principal_id = drm.member_principal_id
JOIN sys.database_principals p ON drm.role_principal_id = p.principal_id
LEFT JOIN sys.server_principals sp ON dp.sid = sp.sid
WHERE dp.is_fixed_role = 0 -- Exclude fixed system roles themselves
  AND dp.name NOT IN ('dbo', 'sys', 'INFORMATION_SCHEMA', 'guest') -- Filter core system aliases
ORDER BY dp.name, p.name;