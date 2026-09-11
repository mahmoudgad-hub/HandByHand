-- Down for 0064. The triggers before the function they call, and the
-- grant last: a policy that outlives its grant is harmless, a grant that
-- outlives its policy is an open door.
\set ON_ERROR_STOP on

DROP TRIGGER IF EXISTS trg_role_permissions_last_admin ON hbh.role_permissions;
DROP TRIGGER IF EXISTS trg_user_roles_last_admin ON hbh.user_roles;
DROP FUNCTION IF EXISTS hbh.guard_last_admin();

DROP POLICY IF EXISTS p_role_permissions_insert ON hbh.role_permissions;
DROP POLICY IF EXISTS p_role_permissions_update ON hbh.role_permissions;
DROP POLICY IF EXISTS p_role_permissions_select_all ON hbh.role_permissions;

REVOKE INSERT, UPDATE ON hbh.role_permissions FROM hbh_app;

DELETE FROM hbh.schema_migrations WHERE version = '0064';
