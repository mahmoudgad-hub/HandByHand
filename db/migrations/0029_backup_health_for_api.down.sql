-- Hand By Hand (new) - migration 0029 DOWN. Development only.
DROP FUNCTION IF EXISTS hbh.backup_health();
DELETE FROM hbh.schema_migrations WHERE version = '0029';
