-- =====================================================================
-- Hand By Hand (new) - migration 0031 rollback
--
-- Rolling this back removes the mask the API applies to a therapist's
-- mobile number and a room's internal note. Do not roll it back while a
-- build that calls it is running: the queries would fail, which is the
-- safe direction, but the fix is to deploy the older build first.
-- =====================================================================

DROP FUNCTION IF EXISTS hbh.current_user_is_staff();

DELETE FROM hbh.schema_migrations WHERE version = '0031';
