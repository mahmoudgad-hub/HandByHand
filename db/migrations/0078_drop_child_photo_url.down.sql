-- Puts the column back, empty. It cannot restore what was in it, and
-- nothing wrote to it after 0077 - the readers were removed before this
-- migration ran, so a rollback returns an unused column rather than a
-- working feature. The photographs themselves are in hbh.attachments
-- and are untouched by either direction.
\set ON_ERROR_STOP on
ALTER TABLE hbh.children ADD COLUMN IF NOT EXISTS photo_url text;
DELETE FROM hbh.schema_migrations WHERE version = '0078';
