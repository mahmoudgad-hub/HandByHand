-- Hand By Hand (new) - migration 0088 DOWN. Development only.
CREATE OR REPLACE FUNCTION hbh.trg_plan_status()
RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NOT hbh.legal_plan_transition(OLD.status, NEW.status) THEN
    RAISE EXCEPTION 'plan % cannot go from % to %', OLD.plan_id, OLD.status, NEW.status
      USING ERRCODE = 'HB030';
  END IF;
  RETURN NEW;
END
$f$;
ALTER TABLE hbh.appointments DROP CONSTRAINT IF EXISTS ck_appt_reschedule_self;
ALTER TABLE hbh.appointments DROP CONSTRAINT IF EXISTS fk_appt_rescheduled_from;
DROP INDEX IF EXISTS hbh.ix_appt_rescheduled_from;
ALTER TABLE hbh.appointments DROP COLUMN IF EXISTS rescheduled_from_appointment_id;
ALTER TABLE hbh.treatment_plans DROP CONSTRAINT IF EXISTS ck_plans_active_approved;
ALTER TABLE hbh.treatment_plans DROP CONSTRAINT IF EXISTS ck_plans_approval;
ALTER TABLE hbh.treatment_plans DROP CONSTRAINT IF EXISTS fk_plans_assessment;
ALTER TABLE hbh.treatment_plans DROP CONSTRAINT IF EXISTS fk_plans_approver;
DROP INDEX IF EXISTS hbh.ix_plans_assessment;
DROP INDEX IF EXISTS hbh.ix_plans_approver;
ALTER TABLE hbh.treatment_plans
  DROP COLUMN IF EXISTS assessment_id,
  DROP COLUMN IF EXISTS approved_at,
  DROP COLUMN IF EXISTS approved_by;
DELETE FROM hbh.schema_migrations WHERE version = '0088';
