-- =====================================================================
-- Hand By Hand (new) - migration 0026 rollback
--
-- Restores hbh.trg_enrolment_status to its migration 0018 body: the
-- legality check without the transition stamps.
--
-- The stamps ALREADY WRITTEN are left alone. They record when something
-- really happened, and rolling back a trigger is not a reason to forget
-- that a family was telephoned on a Tuesday.
-- =====================================================================

CREATE OR REPLACE FUNCTION hbh.trg_enrolment_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NOT hbh.legal_enrolment_transition(OLD.status, NEW.status) THEN
    RAISE EXCEPTION 'application % cannot go from % to %',
                    OLD.application_id, OLD.status, NEW.status
      USING ERRCODE = 'HB090';
  END IF;
  RETURN NEW;
END
$$;

COMMENT ON FUNCTION hbh.trg_enrolment_status() IS NULL;

DELETE FROM hbh.schema_migrations WHERE version = '0026';
