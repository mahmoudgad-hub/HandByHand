-- =====================================================================
-- Hand By Hand (new) - migration 0036 rollback
--
-- Rolling this back closes user administration entirely: no creating a
-- user, no granting a role, and an administrator can no longer see who
-- holds what. That is the state it was found in.
--
-- THE GRANT RECORDS ARE LOST WITH THE COLUMNS. Who granted whom which
-- role, and when, goes with granted_by and granted_at. Copy them first
-- if that history matters - it is the answer to the first question
-- asked after something goes wrong.
-- =====================================================================

DROP FUNCTION IF EXISTS hbh.set_user_roles(integer, text[]);
DROP FUNCTION IF EXISTS hbh.archive_user(integer, boolean);
DROP FUNCTION IF EXISTS hbh.update_user(integer, text, text, text, boolean);
DROP FUNCTION IF EXISTS hbh.create_user(text, text, text, text, integer);

DROP POLICY IF EXISTS p_users_select_admin ON hbh.users;
DROP POLICY IF EXISTS p_user_roles_select_admin ON hbh.user_roles;

DROP INDEX IF EXISTS hbh.ix_ur_granted_by;

ALTER TABLE hbh.user_roles
  DROP COLUMN IF EXISTS granted_at,
  DROP COLUMN IF EXISTS granted_by;

DELETE FROM hbh.schema_migrations WHERE version = '0036';
