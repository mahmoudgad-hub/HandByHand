-- =====================================================================
-- Hand By Hand (new) - migration 0033 rollback
--
-- Tables go before functions. A policy depends on the function it
-- calls, so dropping hbh.can_edit_therapist while its policies stand
-- fails - and the whole migration is one transaction, so NOTHING is
-- dropped, the rebuild silently reuses the old definitions, and a fix
-- written moments ago looks like it does not work.
--
-- Dropping the table takes its policies with it.
--
-- THE CONSENTS RECORDED ARE LOST WITH THE COLUMNS. Nothing can be done
-- about that here, and it is worth saying plainly: rolling this back
-- discards the record of who agreed to have their profile published.
-- Take a copy first if that matters.
-- =====================================================================

DROP TABLE IF EXISTS hbh.therapist_certificates;
DROP TABLE IF EXISTS hbh.therapist_qualifications;
DROP TABLE IF EXISTS hbh.therapist_languages;

DROP TRIGGER IF EXISTS trg_th_profile_status ON hbh.therapists;
DROP FUNCTION IF EXISTS hbh.trg_therapist_profile_status();

DROP FUNCTION IF EXISTS hbh.withdraw_therapist_consent(integer);
DROP FUNCTION IF EXISTS hbh.record_therapist_consent(integer, text);
DROP FUNCTION IF EXISTS hbh.publish_therapist_profile(integer);
DROP FUNCTION IF EXISTS hbh.can_edit_therapist(integer);

ALTER TABLE hbh.therapists
  DROP CONSTRAINT IF EXISTS ck_th_profile_status,
  DROP CONSTRAINT IF EXISTS ck_th_published,
  DROP CONSTRAINT IF EXISTS ck_th_consent,
  DROP CONSTRAINT IF EXISTS ck_th_practice_year,
  DROP CONSTRAINT IF EXISTS ck_th_age_range,
  DROP CONSTRAINT IF EXISTS ck_th_age_bounds;

ALTER TABLE hbh.therapists
  DROP COLUMN IF EXISTS consent_text_version,
  DROP COLUMN IF EXISTS consent_by,
  DROP COLUMN IF EXISTS consent_at,
  DROP COLUMN IF EXISTS published_by,
  DROP COLUMN IF EXISTS published_at,
  DROP COLUMN IF EXISTS profile_status,
  DROP COLUMN IF EXISTS age_to_mon,
  DROP COLUMN IF EXISTS age_from_mon,
  DROP COLUMN IF EXISTS practice_since_year,
  DROP COLUMN IF EXISTS bio_ar;

DELETE FROM hbh.schema_migrations WHERE version = '0033';
