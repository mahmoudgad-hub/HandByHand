-- =====================================================================
-- Hand By Hand (new) - migration 0004 DOWN
--
-- Development convenience only.
-- =====================================================================

DROP FUNCTION IF EXISTS hbh.migration_applied(text);

DELETE FROM hbh.schema_migrations WHERE version = '0004';
