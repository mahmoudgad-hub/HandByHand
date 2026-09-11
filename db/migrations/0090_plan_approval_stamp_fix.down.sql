-- Hand By Hand (new) - migration 0090 DOWN. Development only.
-- Does NOT restore 0088's constraint: it refused ordinary inserts.
DROP TRIGGER IF EXISTS trg_plan_status_ins ON hbh.treatment_plans;
DELETE FROM hbh.schema_migrations WHERE version = '0090';
