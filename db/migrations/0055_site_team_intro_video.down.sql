-- Down for 0055. Constraints before columns: a CHECK naming a column it
-- no longer has is not droppable, and the whole migration is one
-- transaction, so getting the order wrong reverts nothing at all and
-- leaves the schema looking untouched.
\set ON_ERROR_STOP on

ALTER TABLE hbh.site_team
  DROP CONSTRAINT IF EXISTS ck_st_video_consent_pair,
  DROP CONSTRAINT IF EXISTS ck_st_video_consent,
  DROP CONSTRAINT IF EXISTS ck_st_video_local,
  DROP CONSTRAINT IF EXISTS ck_st_photo_local;

ALTER TABLE hbh.site_team
  DROP COLUMN IF EXISTS intro_video_path,
  DROP COLUMN IF EXISTS intro_video_poster_path,
  DROP COLUMN IF EXISTS intro_video_caption_ar,
  DROP COLUMN IF EXISTS intro_video_caption_en,
  DROP COLUMN IF EXISTS video_consent_given_at,
  DROP COLUMN IF EXISTS video_consent_obtained_by;

DELETE FROM hbh.schema_migrations WHERE version = '0055';
