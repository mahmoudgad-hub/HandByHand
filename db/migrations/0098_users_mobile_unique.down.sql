-- =====================================================================
-- 0098 down - two accounts may share a number again
--
-- And the consequence returns with it: hbh.request_otp keeps its
-- `ORDER BY user_id LIMIT 1`, so the oldest account takes every login
-- code and the newest can never sign in. Nothing raises. The function
-- is NOT changed here - it was written to survive duplicates before the
-- index existed, and it still does.
-- =====================================================================

\set ON_ERROR_STOP on

DROP INDEX IF EXISTS hbh.uix_users_mobile_active;

DELETE FROM hbh.schema_migrations WHERE version = '0098';
