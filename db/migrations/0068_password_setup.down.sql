\set ON_ERROR_STOP on
DROP FUNCTION IF EXISTS hbh.redeem_password_setup(text, text, text);
DROP FUNCTION IF EXISTS hbh.issue_password_setup(integer);
DROP TABLE IF EXISTS hbh.password_setups;
DELETE FROM hbh.convention_exemptions WHERE table_name = 'password_setups';
DELETE FROM hbh.schema_migrations WHERE version = '0068';
