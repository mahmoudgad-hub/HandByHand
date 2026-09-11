-- Down for 0067. Dropping a table takes its policies, triggers and
-- indexes with it, so the tables are enough.
\set ON_ERROR_STOP on

DROP TABLE IF EXISTS hbh.staff_documents;
DROP TABLE IF EXISTS hbh.staff_profiles;

DELETE FROM hbh.schema_migrations WHERE version = '0067';
