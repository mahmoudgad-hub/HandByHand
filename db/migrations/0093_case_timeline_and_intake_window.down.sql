-- Hand By Hand (new) - migration 0093 DOWN. Development only.
DROP VIEW IF EXISTS hbh.v_case_timeline;
ALTER TABLE hbh.enrolment_applications
  DROP CONSTRAINT IF EXISTS ck_enrol_time_order,
  DROP CONSTRAINT IF EXISTS ck_enrol_time_window,
  DROP CONSTRAINT IF EXISTS ck_enrol_weekdays;
ALTER TABLE hbh.enrolment_applications
  DROP COLUMN IF EXISTS preferred_time_to,
  DROP COLUMN IF EXISTS preferred_time_from,
  DROP COLUMN IF EXISTS preferred_weekdays;
DELETE FROM hbh.schema_migrations WHERE version = '0093';
