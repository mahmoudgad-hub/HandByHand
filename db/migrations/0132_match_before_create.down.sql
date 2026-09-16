-- Hand By Hand (new) - migration 0132 DOWN. Development only.
DROP FUNCTION IF EXISTS hbh.match_beneficiary(integer, text, date);
DROP FUNCTION IF EXISTS hbh.match_guardian(text);
DROP FUNCTION IF EXISTS hbh.find_beneficiary_matches(integer, text, date);
DROP FUNCTION IF EXISTS hbh.find_guardian_matches(integer, text);
DELETE FROM hbh.schema_migrations WHERE version = '0132';
