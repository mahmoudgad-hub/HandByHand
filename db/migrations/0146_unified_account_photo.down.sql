BEGIN;
DROP VIEW hbh.user_avatars;
ALTER TABLE hbh.user_avatars_legacy RENAME TO user_avatars;
GRANT SELECT,INSERT,UPDATE ON hbh.user_avatars TO hbh_app;
DELETE FROM hbh.schema_migrations WHERE version='0146';
COMMIT;
