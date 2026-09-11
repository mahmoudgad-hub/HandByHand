-- Hand By Hand (new) - migration 0023 DOWN. Development only.
DROP TABLE    IF EXISTS hbh.assessment_item_scores;
DROP TABLE    IF EXISTS hbh.assessments;
DROP TABLE    IF EXISTS hbh.assessment_items;
DROP TABLE    IF EXISTS hbh.assessment_instruments;
DROP FUNCTION IF EXISTS hbh.publish_assessment(integer);
DROP FUNCTION IF EXISTS hbh.record_assessment(integer, integer, integer, date, integer, text);
DROP FUNCTION IF EXISTS hbh.trg_assessment_total();
DROP FUNCTION IF EXISTS hbh.trg_assessment_score_guard();
DROP FUNCTION IF EXISTS hbh.trg_assessment_guard();
DROP FUNCTION IF EXISTS hbh.legal_assessment_transition(text, text);
ALTER TABLE hbh.notifications DROP CONSTRAINT IF EXISTS ck_ntf_kind;
ALTER TABLE hbh.notifications ADD CONSTRAINT ck_ntf_kind CHECK (kind_code IN
  ('REPORT_PUBLISHED','NOTE_PUBLISHED','REQUEST_DECIDED','INVOICE_ISSUED',
   'APPOINTMENT_CANCELLED','SESSION_STARTED'));
DELETE FROM hbh.schema_migrations WHERE version = '0023';
