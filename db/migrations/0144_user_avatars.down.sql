BEGIN;
DROP TABLE hbh.user_avatars;
DROP FUNCTION hbh.can_view_avatar(integer);
DELETE FROM hbh.schema_migrations WHERE version='0144';
COMMIT;
