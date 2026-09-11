-- Puts back 0074's version, wrong consent type and all. A down
-- migration restores the previous state; it is not the place to keep a
-- correction the up migration made.
\set ON_ERROR_STOP on
CREATE OR REPLACE FUNCTION hbh.trg_child_photo_needs_consent()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
BEGIN
  IF NEW.purpose IS DISTINCT FROM 'PROFILE_PHOTO'
     OR (TG_OP = 'UPDATE' AND OLD.purpose IS NOT DISTINCT FROM 'PROFILE_PHOTO') THEN
    RETURN NEW;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM hbh.consents c
    JOIN hbh.guardian_children gc ON gc.guardian_id = c.guardian_id
                                 AND gc.child_id    = c.child_id
    WHERE c.child_id = NEW.child_id AND c.consent_type = 'PHOTO'
      AND c.granted_flg AND c.active_flg AND c.withdrawn_at IS NULL
      AND gc.active_flg
  ) THEN
    RAISE EXCEPTION 'a photograph of child % needs a recorded PHOTO consent', NEW.child_id
      USING ERRCODE = 'HB123';
  END IF;
  RETURN NEW;
END;
$fn$;
DELETE FROM hbh.schema_migrations WHERE version = '0076';
