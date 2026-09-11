-- Hand By Hand (new) - migration 0018 DOWN. Development only.
DROP TABLE    IF EXISTS hbh.enrolment_applications;
DROP FUNCTION IF EXISTS hbh.convert_enrolment(integer, text);
DROP FUNCTION IF EXISTS hbh.submit_enrolment(text, text, text, text, date, char, text, text, text, integer, text, text, text, text, inet);
DROP FUNCTION IF EXISTS hbh.trg_enrolment_status();
DROP FUNCTION IF EXISTS hbh.legal_enrolment_transition(text, text);
DELETE FROM hbh.sys_params WHERE param_code IN
  ('ENROLMENT_MAX_PER_MOBILE_DAY','ENROLMENT_MAX_PER_IP_HOUR');
DELETE FROM hbh.schema_migrations WHERE version = '0018';
