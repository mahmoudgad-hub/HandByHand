-- =====================================================================
-- Hand By Hand (new) - migration 0021 DOWN
--
-- A no-op, for the reason given in 0017's down migration: reverting
-- would break payment recording and put nothing right.
-- =====================================================================

DELETE FROM hbh.schema_migrations WHERE version = '0021';
