-- =====================================================================
-- Hand By Hand (new) - migration 0090: 0088 was too strict in one place
-- and not thorough enough in another. Its own suites caught both.
--
-- 0088 added ck_plans_active_approved - every ACTIVE plan must name an
-- approver - and stamped that approver in trg_plan_status. Three
-- acceptance suites went red, and the failures say exactly what was
-- wrong:
--
--   plan | DRAFT to ACTIVE is accepted
--        | HB210 plan 300 cannot be activated with no identity to credit
--   plan | a second ACTIVE plan for the same child is refused
--        | expected 23505, got 23514 ... ck_plans_active_approved
--
-- TWO DISTINCT MISTAKES.
--
-- 1. trg_plan_status is BEFORE UPDATE. A row INSERTED with status
--    'ACTIVE' never passes through it, so nothing stamped the approver
--    and the CHECK refused a perfectly ordinary insert. The guarantee
--    was enforced on one of the two doors into the state.
--
-- 2. HB210 refused a transition that worked before this migration. That
--    is the "code waits / schema waits" failure: the schema moved and
--    everything already calling it fell. A new rule may not retire a
--    working path on its way in.
--
-- AND THE SECOND FAILURE ABOVE IS THE WORSE ONE, though it looks
-- milder. A check asserting a UNIQUE index refuses duplicates now fails
-- with a CHECK violation instead - so it is green about nothing. The
-- lesson is already in CLAUDE.md: assert the error code, because a
-- refusal for another reason proves nothing and still looks like a
-- refusal.
--
-- THE RESOLUTION, AND WHY IT LOSES NOTHING
--
-- The presence constraint goes; the stamp stays and now fires on INSERT
-- as well as UPDATE. Every path the APPLICATION can take carries an
-- identity - hbh_app fails closed without one, everywhere in this
-- schema - so every plan the application activates still names its
-- approver. What the constraint actually blocked was owner-role scripts
-- and fixtures, which is not the population it was written for.
--
-- The pairing constraint stays: approved_by and approved_at are both
-- present or both absent. Half a signature reads as a record.
--
-- HB210 is retired and not reused.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0090') THEN
    RAISE EXCEPTION 'migration 0090 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0089') THEN
    RAISE EXCEPTION 'migration 0089 must be applied first';
  END IF;
END
$guard$;

ALTER TABLE hbh.treatment_plans DROP CONSTRAINT IF EXISTS ck_plans_active_approved;

-- ---------------------------------------------------------------------
-- Both doors into ACTIVE
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.trg_plan_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'UPDATE'
     AND NEW.status IS DISTINCT FROM OLD.status
     AND NOT hbh.legal_plan_transition(OLD.status, NEW.status) THEN
    RAISE EXCEPTION 'plan % cannot go from % to %', OLD.plan_id, OLD.status, NEW.status
      USING ERRCODE = 'HB030';
  END IF;

  -- Entering ACTIVE is the approval, whichever door it came through.
  -- No refusal when there is no identity: a maintenance script may
  -- legitimately activate a plan, and an unsigned row states that
  -- honestly where a raised exception would just stop the work.
  IF NEW.status = 'ACTIVE'
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'ACTIVE') THEN
    NEW.approved_by := coalesce(NEW.approved_by,
                                CASE WHEN TG_OP = 'UPDATE' THEN OLD.approved_by END,
                                hbh.current_user_id());
    -- Only stamp the time if there is somebody to stamp it for, or
    -- ck_plans_approval - both halves or neither - would refuse the row.
    IF NEW.approved_by IS NOT NULL THEN
      NEW.approved_at := coalesce(NEW.approved_at,
                                  CASE WHEN TG_OP = 'UPDATE' THEN OLD.approved_at END,
                                  now());
    END IF;
  END IF;

  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS trg_plan_status_ins ON hbh.treatment_plans;
CREATE TRIGGER trg_plan_status_ins
  BEFORE INSERT ON hbh.treatment_plans
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_plan_status();

COMMENT ON COLUMN hbh.treatment_plans.approved_by IS
  'Who activated this plan, stamped by trg_plan_status on entry to ACTIVE through either door. Null only where no identity was set - a maintenance script - and that absence is itself the honest answer.';

INSERT INTO hbh.schema_migrations (version) VALUES ('0090');
