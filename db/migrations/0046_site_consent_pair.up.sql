-- =====================================================================
-- 0046 - a consent is a pair, and half of one is not a consent
--
-- 0043's trigger stamps consent_obtained_by from the session when
-- consent_given_at goes from null to a value. If there is no session
-- identity - a seed script run straight against the database as the
-- owner - hbh.current_user_id() is null, and the row lands with a DATE
-- AND NO PERSON.
--
-- And then it cannot be repaired. The trigger only stamps on the
-- transition, so a later request setting consent_given_at again takes
-- the `else` branch and keeps the old values, null person included. The
-- row is stuck: a consent nobody can be shown to have taken, on a table
-- whose whole purpose is that somebody can.
--
-- Found by seeding rows to check the exporter's shape, not by reading
-- 0043 back. The same class as this project's own note on NULLs in a
-- unique index: a half pair is a shape nobody meant to allow, so the
-- table has to refuse it rather than every writer having to remember.
--
-- TWO CHANGES:
--
--   A CHECK per pair, so a date without a person cannot be written by
--   anything - trigger, seed, or owner. Structural, like ck_npsr_context
--   on the satisfaction table.
--
--   The trigger stamps when EITHER half is missing, not only on the
--   transition, so a row that somehow has a date and no person is
--   repaired the next time somebody records the consent rather than
--   staying broken forever.
-- =====================================================================

\set ON_ERROR_STOP on

-- Any half pair that already exists is cleared, not guessed at. A date
-- with no person is not evidence that anybody consented, and inventing
-- the person would be worse than losing the date.
UPDATE hbh.site_team
   SET consent_given_at = NULL, consent_obtained_by = NULL
 WHERE (consent_given_at IS NULL) <> (consent_obtained_by IS NULL);

UPDATE hbh.site_reviews
   SET consent_given_at = NULL, consent_obtained_by = NULL
 WHERE (consent_given_at IS NULL) <> (consent_obtained_by IS NULL);

UPDATE hbh.site_reviews
   SET text_reviewed_at = NULL, text_reviewed_by = NULL
 WHERE (text_reviewed_at IS NULL) <> (text_reviewed_by IS NULL);

ALTER TABLE hbh.site_team
  ADD CONSTRAINT ck_st_consent_pair CHECK (
    (consent_given_at IS NULL) = (consent_obtained_by IS NULL)
  );

ALTER TABLE hbh.site_reviews
  ADD CONSTRAINT ck_sr_consent_pair CHECK (
    (consent_given_at IS NULL) = (consent_obtained_by IS NULL)
  ),
  ADD CONSTRAINT ck_sr_review_pair CHECK (
    (text_reviewed_at IS NULL) = (text_reviewed_by IS NULL)
  );

-- Stamp when either half is missing, so an incomplete row can be
-- repaired instead of being stuck. An existing COMPLETE consent is still
-- never overwritten: the date a family agreed does not move because
-- somebody fixed a typo afterwards.
CREATE OR REPLACE FUNCTION hbh.trg_site_consent_stamp()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
BEGIN
  IF NEW.consent_given_at IS NOT NULL THEN
    IF TG_OP = 'INSERT'
       OR OLD.consent_given_at IS NULL
       OR OLD.consent_obtained_by IS NULL THEN
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
    IF TG_OP = 'INSERT'
       OR OLD.text_reviewed_at IS NULL
       OR OLD.text_reviewed_by IS NULL THEN
      NEW.text_reviewed_at := now();
      NEW.text_reviewed_by := hbh.current_user_id();
    ELSE
      NEW.text_reviewed_at := OLD.text_reviewed_at;
      NEW.text_reviewed_by := OLD.text_reviewed_by;
    END IF;
  ELSE
    NEW.text_reviewed_by := NULL;
  END IF;

  -- Changing the words retracts the reading: somebody attested to a
  -- particular sentence, and a different sentence has been read by
  -- nobody.
  IF TG_OP = 'UPDATE' AND NEW.body_ar IS DISTINCT FROM OLD.body_ar THEN
    NEW.text_reviewed_at := NULL;
    NEW.text_reviewed_by := NULL;
  END IF;

  RETURN NEW;
END;
$fn$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0046');
