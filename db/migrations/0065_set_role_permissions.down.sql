\set ON_ERROR_STOP on
DROP FUNCTION IF EXISTS hbh.set_role_permissions(text, text[]);
DELETE FROM hbh.schema_migrations WHERE version = '0065';
