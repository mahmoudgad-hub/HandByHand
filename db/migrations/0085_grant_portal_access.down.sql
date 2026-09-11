-- Hand By Hand (new) - migration 0085 DOWN. Development only.
-- Accounts already granted are NOT unwound: a family that can log in
-- today should not lose that because a migration was rolled back.
DROP VIEW     IF EXISTS hbh.v_guardian_portal_status;
DROP FUNCTION IF EXISTS hbh.grant_portal_access(integer);
DELETE FROM hbh.schema_migrations WHERE version = '0085';
