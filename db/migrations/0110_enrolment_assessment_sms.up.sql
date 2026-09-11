-- =====================================================================
-- Hand By Hand (new) - migration 0110: the family who applied is told
-- when the first interview is.
--
-- THE API GOES FIRST. ck_sms_purpose gains a value the transport layer
-- has never seen. A worker that switches on purpose and has no arm for
-- ENROLMENT_ASSESSMENT does not fail loudly - it does nothing - so the
-- API deploys first, as 0053, 0058, 0059, 0083 and 0094 each say.
--
-- WHY THIS COULD NOT BE A NOTIFICATION, and it is the same reason a
-- login code could not be one. hbh.notifications is a logged-in
-- person's feed: it names a user_id and its policy is
-- user_id = current_user_id(). An applicant HAS NO USER. They are a row
-- in hbh.enrolment_applications with a mobile number they typed, and
-- hbh.notify_guardians would write nothing for them - silently, because
-- its INSERT ... SELECT joins through guardian_children and simply
-- matches no rows. That is the same shape of silence as the seeds that
-- "succeeded" and inserted nothing.
--
-- SO THE OUTBOX GETS A THIRD PURPOSE, alongside OTP_LOGIN (no
-- notification, no body) and NOTIFICATION (both). This one has a body
-- and no notification, and ck_sms_body already says exactly that for
-- everything that is not OTP_LOGIN, so it needs no new rule.
--
-- ON CONSENT, because it is the question a reader should ask.
-- D-38 gates a guardian's messages on their own SMS_NOTIFY consent, and
-- this message is gated on nothing. That is not an oversight and not an
-- exception carved for convenience:
--   * a consent row belongs to a GUARDIAN, and an applicant is not one
--     yet - there is no row that could carry the answer;
--   * the number was typed into a form whose purpose is to be called
--     back about this application, by the person asking to be called;
--   * and the message says nothing about a child's condition. It names
--     the child the family named, the application number the centre
--     gave them, and a time. It is a reply to their own request.
-- The moment they become a guardian, D-38 governs everything after, and
-- this path stops applying because its status is passed through once.
--
-- WHY assessment_at IS ADDED HERE AND WHY THE STATUS NOW REQUIRES IT.
-- ASSESSMENT_BOOKED has existed since 0018 with nowhere to record WHEN,
-- so the status asserted a booking the schema could not describe - and a
-- message confirming an appointment cannot be written from it. Adding
-- the column without the constraint would leave the same hole open for
-- the next row. The constraint is NOT VALID on purpose: applications
-- that reached this status before today are left alone rather than
-- rewritten with a time nobody chose, and every transition from now on
-- is checked. A grandfathered row never reaches the trigger, because the
-- trigger fires on ENTERING the status and they entered it already.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0110') THEN
    RAISE EXCEPTION 'migration 0110 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0109') THEN
    RAISE EXCEPTION 'migration 0109 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- WHEN THE FIRST INTERVIEW IS
-- =====================================================================
ALTER TABLE hbh.enrolment_applications
  ADD COLUMN IF NOT EXISTS assessment_at timestamptz;

-- timestamptz, not timestamp. The centre is in Africa/Cairo and the
-- server need not be; a column without a zone is the defect that
-- disabled account lockout and expired every code at issue.
ALTER TABLE hbh.enrolment_applications
  ADD CONSTRAINT ck_enr_assessment_when
  CHECK (status <> 'ASSESSMENT_BOOKED' OR assessment_at IS NOT NULL)
  NOT VALID;

COMMENT ON COLUMN hbh.enrolment_applications.assessment_at IS
  'When the first interview is, in UTC. Required by ck_enr_assessment_when '
  'once the application reaches ASSESSMENT_BOOKED. Displayed in the centre''s '
  'own time zone (hbh.centers.time_zone) and never stored in it.';

-- =====================================================================
-- A THIRD PURPOSE
-- =====================================================================
ALTER TABLE hbh.sms_outbox DROP CONSTRAINT ck_sms_purpose;
ALTER TABLE hbh.sms_outbox
  ADD CONSTRAINT ck_sms_purpose
  CHECK (purpose IN ('OTP_LOGIN','NOTIFICATION','ENROLMENT_ASSESSMENT'));

-- =====================================================================
-- THE MESSAGE
--
-- A TRIGGER, for D-38's reason: the family is told because the booking
-- HAPPENED, not because whoever booked it remembered. Reception moves
-- the status from one screen today and from another next year, and
-- neither has to know this exists.
--
-- THE DEDUPE KEY IS THE APPLICATION, so the enqueue is exactly once and
-- stays exactly once no matter how the status is written. The state
-- machine in 0018 admits CONTACTED -> ASSESSMENT_BOOKED and no way back
-- in, so one message per application is not a guess about behaviour, it
-- is a property of the transitions.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.trg_sms_assessment_booked()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_tz    text;
  l_when  text;
  l_body  text;
BEGIN
  -- The centre's own zone, from the row, never a literal. Egypt is a
  -- parameter in this project and not a fact written into code.
  SELECT c.time_zone INTO l_tz
  FROM   hbh.centers c
  WHERE  c.center_id = NEW.center_id;

  -- Stored UTC, compared UTC, converted only to be read. Gregorian and
  -- 24-hour, matching every other date this centre prints.
  l_when := to_char(NEW.assessment_at AT TIME ZONE coalesce(l_tz, 'Africa/Cairo'),
                    'DD/MM/YYYY - HH24:MI');

  l_body := 'أهلًا ' || NEW.parent_name_ar || E'\n'
         || 'تم تحديد موعد المقابلة الأولى لـ' || NEW.child_name_ar || ' في '
         || l_when || '.' || E'\n'
         || 'رقم الطلب: ' || NEW.application_no;

  -- The array is the same three values, apart, for a transport that
  -- assembles the sentence from an approved template instead of being
  -- handed one. Positions are the contract: {{1}} parent, {{2}} child,
  -- {{3}} when. The application number rides in the template's own
  -- fixed text, so it is not a variable and cannot drift out of step.
  PERFORM hbh.enqueue_sms(
    NEW.center_id,
    'ENROLMENT_ASSESSMENT',
    'ENROLMENT_ASSESSMENT',
    NEW.parent_mobile,
    'ENR:' || NEW.application_id::text,
    l_body,
    NULL,
    'PENDING',
    jsonb_build_array(NEW.parent_name_ar, NEW.child_name_ar, l_when));

  RETURN NULL;
END
$$;

CREATE TRIGGER trg_enr_sms_assessment_booked
  AFTER UPDATE ON hbh.enrolment_applications
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status
        AND NEW.status = 'ASSESSMENT_BOOKED'
        AND NEW.assessment_at IS NOT NULL)
  EXECUTE FUNCTION hbh.trg_sms_assessment_booked();

INSERT INTO hbh.schema_migrations (version) VALUES ('0110');
