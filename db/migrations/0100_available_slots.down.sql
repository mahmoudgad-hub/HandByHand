-- Reverses 0100. Nothing depends on this function - no policy calls it,
-- no view reads it - so it drops on its own.
DROP FUNCTION IF EXISTS hbh.available_slots(integer, integer, integer, date, integer);

DELETE FROM hbh.schema_migrations WHERE version = '0100';
