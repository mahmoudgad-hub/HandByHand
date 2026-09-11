-- =====================================================================
-- Hand By Hand (new) - migration 0010 DOWN
-- Development convenience only.
--
-- validate_slot is NOT restored to its earlier body here. Dropping the
-- blocks table while a validate_slot that reads it is still installed
-- would leave the function broken, so the function is dropped too and
-- migration 0005 re-creates it on the way back up.
-- =====================================================================

DROP FUNCTION IF EXISTS hbh.block_conflicts(integer);
DROP TABLE    IF EXISTS hbh.schedule_blocks CASCADE;
DROP FUNCTION IF EXISTS hbh.validate_slot(integer, integer, integer, integer, integer, timestamptz, timestamptz, integer);

DELETE FROM hbh.schema_migrations WHERE version = '0010';
