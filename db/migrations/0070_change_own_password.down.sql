\set ON_ERROR_STOP on
DROP FUNCTION IF EXISTS hbh.change_own_password(text, text);
DELETE FROM hbh.schema_migrations WHERE version = '0070';
