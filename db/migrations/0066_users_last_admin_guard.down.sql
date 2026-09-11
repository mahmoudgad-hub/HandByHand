\set ON_ERROR_STOP on
DROP TRIGGER IF EXISTS trg_users_last_admin ON hbh.users;
DELETE FROM hbh.schema_migrations WHERE version = '0066';
