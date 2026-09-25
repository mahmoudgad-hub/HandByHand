-- Hand By Hand (new) - migration 0131 DOWN. Development only.
DROP FUNCTION IF EXISTS hbh.record_verification_delivery(integer, text, text, text, text, text);
DROP FUNCTION IF EXISTS hbh.verify_mobile(bigint, text);
DROP FUNCTION IF EXISTS hbh.request_mobile_verification(text, text, text, inet);
-- Delivery rows under the new purpose would violate the old constraint.
DELETE FROM hbh.sms_outbox WHERE purpose = 'OTP_VERIFY';
ALTER TABLE hbh.sms_outbox DROP CONSTRAINT IF EXISTS ck_sms_vars_otp;
ALTER TABLE hbh.sms_outbox ADD CONSTRAINT ck_sms_vars_otp
  CHECK (NOT (purpose = 'OTP_LOGIN' AND template_vars IS NOT NULL));
ALTER TABLE hbh.sms_outbox DROP CONSTRAINT IF EXISTS ck_sms_body;
ALTER TABLE hbh.sms_outbox ADD CONSTRAINT ck_sms_body CHECK ((purpose = 'OTP_LOGIN') = (body_ar IS NULL));
ALTER TABLE hbh.sms_outbox DROP CONSTRAINT IF EXISTS ck_sms_purpose;
ALTER TABLE hbh.sms_outbox ADD CONSTRAINT ck_sms_purpose
  CHECK (purpose IN ('OTP_LOGIN', 'NOTIFICATION', 'ENROLMENT_ASSESSMENT'));
DELETE FROM hbh.convention_exemptions WHERE table_name = 'mobile_verifications';
DROP TABLE IF EXISTS hbh.mobile_verifications;
DELETE FROM hbh.schema_migrations WHERE version = '0131';
