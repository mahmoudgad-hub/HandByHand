\set ON_ERROR_STOP on
REVOKE USAGE, SELECT ON SEQUENCE hbh.password_setups_setup_id_seq FROM hbh_app;
DELETE FROM hbh.schema_migrations WHERE version = '0069';
