-- =====================================================================
-- Hand By Hand (new) - migration 0020 DOWN. Development only.
--
-- run_maintenance is left as this migration defined it. Restoring the
-- earlier body would mean copying it here, and a second copy of a
-- function is how the two drift apart - migration 0011 re-creates it on
-- the way back up.
-- =====================================================================
DROP VIEW     IF EXISTS hbh.v_user_activity;
DROP VIEW     IF EXISTS hbh.v_recent_errors;
DROP VIEW     IF EXISTS hbh.v_api_health;
DROP TABLE    IF EXISTS hbh.request_log;
DROP FUNCTION IF EXISTS hbh.log_request(text, text, smallint, integer, text, text, inet, text, text, text, jsonb);
DELETE FROM hbh.convention_exemptions WHERE table_name = 'request_log';
DELETE FROM hbh.sys_params WHERE param_code = 'REQUEST_LOG_RETENTION_DAYS';
DELETE FROM hbh.schema_migrations WHERE version = '0020';
