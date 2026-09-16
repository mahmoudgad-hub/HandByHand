-- Hand By Hand (new) - migration 0128 DOWN. Development only.
-- Restores the shape that freezes a legacy row beyond repair. Any row
-- retired while 0128 was in force stays retired - a rollback is not a
-- reason to make history writable again.
ALTER TABLE hbh.enrolment_applications DROP CONSTRAINT IF EXISTS ck_enr_mobile_e164;
ALTER TABLE hbh.enrolment_applications
  ADD CONSTRAINT ck_enr_mobile_e164 CHECK (parent_mobile ~ '^\+[1-9][0-9]{7,14}$') NOT VALID;
ALTER TABLE hbh.therapists DROP CONSTRAINT IF EXISTS ck_therapists_mobile_e164;
ALTER TABLE hbh.therapists
  ADD CONSTRAINT ck_therapists_mobile_e164
  CHECK (mobile IS NULL OR mobile ~ '^\+[1-9][0-9]{7,14}$') NOT VALID;
ALTER TABLE hbh.users DROP CONSTRAINT IF EXISTS ck_users_mobile_e164;
ALTER TABLE hbh.users
  ADD CONSTRAINT ck_users_mobile_e164
  CHECK (mobile IS NULL OR mobile ~ '^\+[1-9][0-9]{7,14}$') NOT VALID;
ALTER TABLE hbh.guardians DROP CONSTRAINT IF EXISTS ck_guardians_mobile_e164;
ALTER TABLE hbh.guardians
  ADD CONSTRAINT ck_guardians_mobile_e164 CHECK (mobile ~ '^\+[1-9][0-9]{7,14}$') NOT VALID;
DELETE FROM hbh.schema_migrations WHERE version = '0128';
