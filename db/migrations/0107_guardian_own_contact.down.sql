-- Reverses 0107. Nothing depends on this function - no policy calls it,
-- no view reads it - so it drops on its own.
DROP FUNCTION IF EXISTS hbh.update_own_guardian_contact(text, text);

DELETE FROM hbh.schema_migrations WHERE version = '0107';
