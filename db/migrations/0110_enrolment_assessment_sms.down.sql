-- =====================================================================
-- 0110 down - the applicant stops being told, and the rows stay.
--
-- THE OUTBOX ROWS ARE NOT DELETED and the purpose constraint is not
-- narrowed back. A row saying a message went to a number is a record
-- that it went, and withdrawing the trigger does not make it untrue -
-- D-30's rule, and the practical half is that narrowing ck_sms_purpose
-- would fail against those very rows and take the whole migration with
-- it, leaving nothing dropped and a reversal that looks like it did not
-- run.
--
-- assessment_at IS KEPT for the same reason: it holds times somebody
-- chose and families were told. The CONSTRAINT goes, because it is this
-- migration's rule rather than anybody's data.
-- =====================================================================

DROP TRIGGER IF EXISTS trg_enr_sms_assessment_booked ON hbh.enrolment_applications;
DROP FUNCTION IF EXISTS hbh.trg_sms_assessment_booked();

ALTER TABLE hbh.enrolment_applications
  DROP CONSTRAINT IF EXISTS ck_enr_assessment_when;

DELETE FROM hbh.schema_migrations WHERE version = '0110';
