-- Hand By Hand (new) - migration 0089 DOWN. Development only.
DROP TRIGGER IF EXISTS trg_caseload_notify   ON hbh.caseload;
DROP TRIGGER IF EXISTS trg_appt_notify_booked ON hbh.appointments;
DROP FUNCTION IF EXISTS hbh.trg_notify_assigned();
DROP FUNCTION IF EXISTS hbh.trg_notify_booked();
DROP FUNCTION IF EXISTS hbh.notify_role(text, text, text, integer, text, integer);
DROP FUNCTION IF EXISTS hbh.notify_staff(integer[], text, text, integer, text, integer);
-- Rows written under the new kinds would violate the old constraint, so
-- they go before it comes back. Notifications are not a clinical record.
DELETE FROM hbh.notifications WHERE kind_code LIKE 'STAFF\_%'
   OR kind_code IN ('APPOINTMENT_BOOKED','APPOINTMENT_RESCHEDULED','APPOINTMENT_REMINDER');
ALTER TABLE hbh.notifications DROP CONSTRAINT IF EXISTS ck_ntf_audience;
ALTER TABLE hbh.notifications DROP CONSTRAINT IF EXISTS ck_ntf_kind;
ALTER TABLE hbh.notifications ADD CONSTRAINT ck_ntf_kind CHECK (kind_code IN (
  'REPORT_PUBLISHED','NOTE_PUBLISHED','REQUEST_DECIDED','INVOICE_ISSUED',
  'APPOINTMENT_CANCELLED','SESSION_STARTED','ASSESSMENT_PUBLISHED'));
DELETE FROM hbh.schema_migrations WHERE version = '0089';
