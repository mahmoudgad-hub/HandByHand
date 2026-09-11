-- =====================================================================
-- 0046 down - allow half a consent again
--
-- The constraints go; the trigger bodies are restored to the version
-- 0043 and 0045 installed, which stamp only on the transition. A row
-- with a date and no person becomes writable again, and unrepairable
-- again, which is the state this migration existed to end.
--
-- Rows already cleared by the up migration are not restored: a date with
-- no person was never evidence of a consent, and there is nothing to put
-- back.
-- =====================================================================

\set ON_ERROR_STOP on

ALTER TABLE hbh.site_team    DROP CONSTRAINT IF EXISTS ck_st_consent_pair;
ALTER TABLE hbh.site_reviews DROP CONSTRAINT IF EXISTS ck_sr_consent_pair;
ALTER TABLE hbh.site_reviews DROP CONSTRAINT IF EXISTS ck_sr_review_pair;

CREATE OR REPLACE FUNCTION hbh.trg_site_consent_stamp()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
BEGIN
  IF NEW.consent_given_at IS NOT NULL THEN
    IF TG_OP = 'INSERT' OR OLD.consent_given_at IS NULL THEN
      NEW.consent_given_at    := now();
      NEW.consent_obtained_by := hbh.current_user_id();
    ELSE
      NEW.consent_given_at    := OLD.consent_given_at;
      NEW.consent_obtained_by := OLD.consent_obtained_by;
    END IF;
  ELSE
    NEW.consent_obtained_by := NULL;
  END IF;
  RETURN NEW;
END;
$fn$;

CREATE OR REPLACE FUNCTION hbh.trg_site_text_review_stamp()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
BEGIN
  IF NEW.text_reviewed_at IS NOT NULL THEN
    IF TG_OP = 'INSERT' OR OLD.text_reviewed_at IS NULL THEN
      NEW.text_reviewed_at := now();
      NEW.text_reviewed_by := hbh.current_user_id();
    ELSE
      NEW.text_reviewed_at := OLD.text_reviewed_at;
      NEW.text_reviewed_by := OLD.text_reviewed_by;
    END IF;
  ELSE
    NEW.text_reviewed_by := NULL;
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.body_ar IS DISTINCT FROM OLD.body_ar THEN
    NEW.text_reviewed_at := NULL;
    NEW.text_reviewed_by := NULL;
  END IF;
  RETURN NEW;
END;
$fn$;

DELETE FROM hbh.schema_migrations WHERE version = '0046';
