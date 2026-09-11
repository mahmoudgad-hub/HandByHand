-- =====================================================================
-- Hand By Hand (new) - migration 0026: an enrolment records WHEN it moved
--
-- WHAT WAS MISSING. hbh.enrolment_applications carries contacted_at,
-- decided_by and decided_at, and nothing filled the first one. An
-- application moved to CONTACTED and the queue screen showed a family
-- as contacted with no date beside it - which is worse than no column,
-- because it reads as "we called them, at no particular time".
--
-- hbh.convert_enrolment already stamps decided_by and decided_at on its
-- way to ENROLLED, so half of the bookkeeping was there and half was
-- not. This closes the other half.
--
-- WHY IT IS A TRIGGER AND NOT A COLUMN THE API SETS.
--
-- Rule 5: a status is a state machine, and the time a transition
-- happened is part of the transition, not a field a caller supplies. An
-- API that sent contacted_at could send yesterday's date, could forget
-- it on the one path that mattered, and would have to be corrected in
-- every client that ever writes this table. The machine that already
-- refuses an illegal move is the right place to record a legal one.
--
-- WHAT IT DOES NOT DO. It never overwrites a stamp that is already
-- there. Re-entering a state does not rewrite the history of when it
-- was first entered, and hbh.convert_enrolment's own decided_at survives
-- untouched.
--
-- The body of the legality check is unchanged from migration 0018.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0026') THEN
    RAISE EXCEPTION 'migration 0026 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0018') THEN
    RAISE EXCEPTION 'migration 0018 must be applied first';
  END IF;
END
$guard$;

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

  -- ADDED IN 0026. coalesce, not assignment: the first time the family
  -- was reached is the fact worth keeping, and a later edit of the note
  -- must not move it.
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status = 'CONTACTED' THEN
      NEW.contacted_at := coalesce(NEW.contacted_at, now());
    ELSIF NEW.status IN ('REJECTED', 'DUPLICATE', 'ENROLLED') THEN
      NEW.decided_at := coalesce(NEW.decided_at, now());
      NEW.decided_by := coalesce(NEW.decided_by, hbh.current_user_id());
    END IF;
  END IF;

  RETURN NEW;
END
$$;

COMMENT ON FUNCTION hbh.trg_enrolment_status() IS
  'Refuses an illegal enrolment transition (HB090) and stamps when a legal one happened (0026).';

INSERT INTO hbh.schema_migrations (version) VALUES ('0026');
