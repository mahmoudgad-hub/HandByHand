\set ON_ERROR_STOP on
DROP TRIGGER IF EXISTS trg_site_team_media_consent ON hbh.site_team_media;
DELETE FROM hbh.schema_migrations WHERE version = '0063';
