-- =====================================================================
-- 0045 down
--
-- Triggers before the function they call; the constraint on
-- site_reviews before the columns it names. The section codes go back to
-- the capitals 0040 wrote, which is the wrong value - it is what that
-- migration created, and a down migration restores the previous state
-- rather than a better one.
--
-- WHAT THIS REMOVES: the requirement that somebody read a testimonial
-- before it is published. The consent columns stay, but consent is a
-- different question from whether the text names a child - which is the
-- whole reason 0044 exists.
-- =====================================================================

\set ON_ERROR_STOP on

DROP TRIGGER IF EXISTS trg_site_reviews_textreview ON hbh.site_reviews;
DROP FUNCTION IF EXISTS hbh.trg_site_text_review_stamp();

DROP TABLE IF EXISTS hbh.site_team_facts;
DROP TABLE IF EXISTS hbh.site_programs;

ALTER TABLE hbh.site_reviews
  DROP CONSTRAINT IF EXISTS ck_sr_text_reviewed,
  DROP CONSTRAINT IF EXISTS ck_sr_rating,
  DROP CONSTRAINT IF EXISTS fk_sr_text_reviewer;
ALTER TABLE hbh.site_reviews
  DROP COLUMN IF EXISTS text_reviewed_at,
  DROP COLUMN IF EXISTS text_reviewed_by,
  DROP COLUMN IF EXISTS rating;

ALTER TABLE hbh.site_team
  DROP COLUMN IF EXISTS photo_path,
  DROP COLUMN IF EXISTS profile_href;

ALTER TABLE hbh.site_sections DROP CONSTRAINT ck_ss_code;
ALTER TABLE hbh.site_sections ADD CONSTRAINT ck_ss_code CHECK (
  code IN ('FAQ', 'TEAM', 'REVIEWS', 'CONTACT')
);

DELETE FROM hbh.schema_migrations WHERE version = '0045';
