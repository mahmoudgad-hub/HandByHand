-- Down for 0061. Tables before the columns they do not depend on, and
-- dropping a table takes its policies, triggers and indexes with it.
\set ON_ERROR_STOP on

DROP TABLE IF EXISTS hbh.site_team_media;
DROP TABLE IF EXISTS hbh.site_team_specialties;

ALTER TABLE hbh.site_team DROP CONSTRAINT IF EXISTS ck_st_bio;
ALTER TABLE hbh.site_team
  DROP COLUMN IF EXISTS org_ar,
  DROP COLUMN IF EXISTS org_en,
  DROP COLUMN IF EXISTS bio_ar,
  DROP COLUMN IF EXISTS bio_en;

DELETE FROM hbh.schema_migrations WHERE version = '0061';
