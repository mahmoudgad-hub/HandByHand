-- Down for 0062. Revoking every sequence would break every table, not
-- only the two 0061 added, so this narrows to those two - which is what
-- 0061 should have granted in the first place.
\set ON_ERROR_STOP on

REVOKE USAGE, SELECT ON SEQUENCE hbh.site_team_media_media_id_seq FROM hbh_app;
REVOKE USAGE, SELECT ON SEQUENCE hbh.site_team_specialties_specialty_id_seq FROM hbh_app;

DELETE FROM hbh.schema_migrations WHERE version = '0062';
