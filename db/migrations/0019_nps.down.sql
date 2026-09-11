-- Hand By Hand (new) - migration 0019 DOWN. Development only.
DROP VIEW     IF EXISTS hbh.v_nps_summary;
DROP TABLE    IF EXISTS hbh.nps_responses;
DROP TABLE    IF EXISTS hbh.nps_surveys;
DROP FUNCTION IF EXISTS hbh.skip_nps(integer, text, integer);
DROP FUNCTION IF EXISTS hbh.submit_nps(integer, smallint, text, text, integer, inet);
DROP FUNCTION IF EXISTS hbh.nps_due();
DELETE FROM hbh.schema_migrations WHERE version = '0019';
