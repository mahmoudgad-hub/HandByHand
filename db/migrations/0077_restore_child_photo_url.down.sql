\set ON_ERROR_STOP on
ALTER TABLE hbh.children DROP COLUMN IF EXISTS photo_url;
DELETE FROM hbh.schema_migrations WHERE version = '0077';
