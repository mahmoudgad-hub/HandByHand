-- =====================================================================
-- Hand By Hand (new) - migration 0011 DOWN
-- Development convenience only. View and table before functions.
-- =====================================================================

DROP VIEW  IF EXISTS hbh.v_maintenance_health;
DROP TABLE IF EXISTS hbh.maintenance_runs;

DROP FUNCTION IF EXISTS hbh.run_maintenance();
DROP FUNCTION IF EXISTS hbh.verify_password(text, text);
DROP FUNCTION IF EXISTS hbh.set_password(integer, text);

ALTER TABLE hbh.users DROP CONSTRAINT IF EXISTS ck_users_password_stamp;
ALTER TABLE hbh.users DROP CONSTRAINT IF EXISTS ck_users_password;
DROP INDEX IF EXISTS hbh.ix_users_locked;
ALTER TABLE hbh.users
  DROP COLUMN IF EXISTS locked_until,
  DROP COLUMN IF EXISTS failed_login_cnt,
  DROP COLUMN IF EXISTS password_set_at,
  DROP COLUMN IF EXISTS password_hash;

DELETE FROM hbh.convention_exemptions WHERE table_name = 'maintenance_runs';
DELETE FROM hbh.sys_params WHERE param_code IN
  ('MIN_PASSWORD_LENGTH','LOGIN_MAX_ATTEMPTS','LOGIN_LOCK_MINUTES','MAINTENANCE_MAX_AGE_MIN');

DELETE FROM hbh.schema_migrations WHERE version = '0011';
