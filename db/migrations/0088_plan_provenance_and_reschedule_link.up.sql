-- =====================================================================
-- Hand By Hand (new) - migration 0088
-- three questions the schema could not answer
--
-- From the lifecycle gap analysis (LC-06 · LC-09 · LC-10). Each of these
-- is the same shape: the data to answer exists, and the column that
-- would carry the answer does not.
--
-- LC-09 · WHO APPROVED THIS PLAN
--
--   A plan becomes ACTIVE and nothing records who decided that.
--   updated_by is the LAST PERSON TO TOUCH the row, which is a
--   different fact and drifts further from the answer with every edit.
--   Six months on, "who approved this course of treatment" has no
--   answer at all - and that is the question asked when a plan is
--   disputed.
--
--   AND IT IS STAMPED BY THE TRIGGER, NOT DEMANDED FROM THE CALLER.
--   trg_plan_status is already the machine that refuses illegitimate
--   transitions, so it is where the legitimate one gets recorded - the
--   same reasoning 0026 used for contacted_at. Demanding approved_by
--   from callers instead would break every existing activate-plan
--   UPDATE the moment this lands, which is the "code waits / schema
--   waits" failure written up in CLAUDE.md: whichever moves first falls.
--
--   coalesce, not assignment: re-entering ACTIVE does not rewrite who
--   approved it the first time.
--
-- LC-10 · WHICH ASSESSMENT THIS PLAN CAME FROM
--
--   assessments and treatment_plans have no link. A plan exists, an
--   assessment exists, and "what evidence produced this plan" is
--   answerable only by matching dates and hoping.
--
-- LC-06 · WHAT THIS APPOINTMENT WAS MOVED FROM
--
--   A reschedule is deliberately two rows - 0007 says so, and that is
--   right: the cancelled slot happened and must stay visible. But
--   nothing joins them, so a timeline says "cancelled" and then
--   "booked" and can never say "MOVED from Sunday to Tuesday" - which
--   is the sentence a family actually asks about.
--
-- WHAT THIS MIGRATION DOES NOT DO: split PLAN.MANAGE.
--
-- The analysis is right that the owner distinguishes three acts - the
-- clinician PROPOSES, the manager APPROVES, reception picks from who is
-- available and decides no speciality - and that one permission serving
-- all three silently decides which of them it ignores. That is the
-- lesson already in CLAUDE.md about two rights needing two gates.
--
-- But splitting it changes who may do what in a service that is running
-- mid-sprint, and a migration is the wrong place to find that out. The
-- columns below make the FACT recordable today; who is permitted to
-- create it is a separate change with the back end in the room.
--
-- Error classes added here:
--   HB210  a plan cannot be activated without an identity to credit
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0088') THEN
    RAISE EXCEPTION 'migration 0088 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0087') THEN
    RAISE EXCEPTION 'migration 0087 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- LC-09 + LC-10 - the plan says where it came from and who approved it
-- =====================================================================
ALTER TABLE hbh.treatment_plans
  ADD COLUMN approved_by   integer,
  ADD COLUMN approved_at   timestamptz,
  ADD COLUMN assessment_id integer;

ALTER TABLE hbh.treatment_plans
  ADD CONSTRAINT fk_plans_approver   FOREIGN KEY (approved_by)   REFERENCES hbh.users (user_id),
  ADD CONSTRAINT fk_plans_assessment FOREIGN KEY (assessment_id) REFERENCES hbh.assessments (assessment_id);

CREATE INDEX ix_plans_approver   ON hbh.treatment_plans (approved_by);
CREATE INDEX ix_plans_assessment ON hbh.treatment_plans (assessment_id);

-- Both halves of the signature or neither. Half a signature is worse
-- than none, because it reads as a record.
ALTER TABLE hbh.treatment_plans
  ADD CONSTRAINT ck_plans_approval CHECK ((approved_by IS NULL) = (approved_at IS NULL));

-- NOT VALID on purpose. One ACTIVE plan already exists from before this
-- rule, and inventing an approver for it would be the schema stating a
-- fact nobody established. The constraint binds every row written from
-- now on; the old row stays visibly unsigned, which is the truth.
ALTER TABLE hbh.treatment_plans
  ADD CONSTRAINT ck_plans_active_approved
  CHECK (status <> 'ACTIVE' OR approved_by IS NOT NULL) NOT VALID;

-- ---------------------------------------------------------------------
-- The transition machine records the transition
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.trg_plan_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NOT hbh.legal_plan_transition(OLD.status, NEW.status) THEN
    RAISE EXCEPTION 'plan % cannot go from % to %', OLD.plan_id, OLD.status, NEW.status
      USING ERRCODE = 'HB030';
  END IF;

  -- Entering ACTIVE is the approval. Stamped here so no caller has to
  -- remember, and coalesced so re-entering does not rewrite the first
  -- decision with the name of whoever happened to touch it later.
  IF NEW.status = 'ACTIVE' AND OLD.status IS DISTINCT FROM 'ACTIVE' THEN
    IF hbh.current_user_id() IS NULL AND NEW.approved_by IS NULL THEN
      RAISE EXCEPTION 'plan % cannot be activated with no identity to credit', OLD.plan_id
        USING ERRCODE = 'HB210';
    END IF;
    NEW.approved_by := coalesce(NEW.approved_by, OLD.approved_by, hbh.current_user_id());
    NEW.approved_at := coalesce(NEW.approved_at, OLD.approved_at, now());
  END IF;

  RETURN NEW;
END
$$;

COMMENT ON COLUMN hbh.treatment_plans.approved_by IS
  'Who activated this plan. Stamped by trg_plan_status on entry to ACTIVE - not updated_by, which is merely the last person to touch the row.';
COMMENT ON COLUMN hbh.treatment_plans.assessment_id IS
  'The assessment this plan was built from, when there was one. Optional: a plan may predate the instrument that would have produced it.';

-- =====================================================================
-- LC-06 - the two rows of a reschedule know about each other
-- =====================================================================
ALTER TABLE hbh.appointments
  ADD COLUMN rescheduled_from_appointment_id integer;

ALTER TABLE hbh.appointments
  ADD CONSTRAINT fk_appt_rescheduled_from
  FOREIGN KEY (rescheduled_from_appointment_id) REFERENCES hbh.appointments (appointment_id);

CREATE INDEX ix_appt_rescheduled_from ON hbh.appointments (rescheduled_from_appointment_id);

-- An appointment moved from itself is a loop that would make any
-- timeline walking the chain hang.
ALTER TABLE hbh.appointments
  ADD CONSTRAINT ck_appt_reschedule_self
  CHECK (rescheduled_from_appointment_id IS DISTINCT FROM appointment_id);

COMMENT ON COLUMN hbh.appointments.rescheduled_from_appointment_id IS
  'The appointment this one replaces. A reschedule stays two rows - the cancelled slot happened - and this is what lets a timeline say "moved from" rather than "cancelled" then "booked".';

INSERT INTO hbh.schema_migrations (version) VALUES ('0088');
