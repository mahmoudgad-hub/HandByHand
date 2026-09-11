-- Drops the table, and its policies and triggers with it. The function
-- goes after the trigger that uses it - a policy or trigger still
-- pointing at a dropped function fails, and the whole migration is one
-- transaction, so nothing at all would be dropped and the rebuild would
-- silently reuse the old definitions.
\set ON_ERROR_STOP on
DROP TABLE IF EXISTS hbh.site_texts;
DROP FUNCTION IF EXISTS hbh.guard_site_text_locked();
DELETE FROM hbh.schema_migrations WHERE version = '0092';
