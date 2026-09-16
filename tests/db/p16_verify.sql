-- =====================================================================
-- Hand By Hand (new) - PHASE 16 acceptance suite: WhatsApp delivery
--
-- Must print:  PHASE 16 ACCEPTED
--
-- Migrations 0109, 0110 and 0111. Four claims:
--
--   1. THE OUTBOX CARRIES THE VALUES AND NOT ONLY THE SENTENCE. WhatsApp
--      will not deliver a sentence this service composed; it takes an
--      approved template and the values that go into it. body_ar stays
--      exactly what an SMS provider wants, and template_vars is the same
--      information taken apart.
--   2. AND A LOGIN CODE MAY NEVER BE AMONG THEM. The code IS the
--      variable, so an OTP row that carried one would be the plaintext at
--      rest that hbh.otp_codes exists to prevent. ck_sms_body has kept
--      body_ar NULL there since 0094; ck_sms_vars_otp closes the same
--      hole in the new shape.
--   3. THE FAMILY WHO APPLIED IS TOLD WHEN THE FIRST INTERVIEW IS. They
--      have no user account, so hbh.notifications cannot reach them and
--      notify_guardians would write nothing AND SAY NOTHING. And a status
--      claiming a booking now has to say when it is, or the message it
--      exists to send cannot be written.
--   4. AND THE CHANNEL DECIDES WHICH CONSENT IS ASKED FOR. Agreeing to
--      be texted is not agreeing to be messaged on WhatsApp, and a
--      consent row standing for a permission nobody gave is the worst
--      possible thing to find in the most truthful part of the schema.
--
-- EVERY REFUSAL HERE IS FOLLOWED BY THE ACCEPTANCE THAT PROVES IT WAS
-- CONDITIONAL. The photograph gate in this project asked for a consent
-- type the schema never had: it refused every upload for a fortnight
-- while its "without consent it is refused" check stayed green. A gate
-- with no key passes the first half of that pair and fails nothing.
--
-- EVERY NEGATIVE CHECK NAMES ITS SQLSTATE, because "did it fail" is not
-- the question - a check constraint and a missing fixture look identical
-- to a harness that only asks whether something was raised.
--
-- THIS SUITE BUILDS ITS OWN CENTRE, and that is not tidiness. Claim 4 is
-- tested by changing NOTIFY_CHANNEL, and that parameter read at centre
-- level governs every message that centre sends. Flipping it on the
-- shared HBH centre would, for as long as this file runs, decide which
-- consent a completely unrelated session's notification is gated on. A
-- suite is not allowed to reach into a neighbour's answers.
-- =====================================================================

\set ON_ERROR_STOP off
\pset pager off

DROP SCHEMA IF EXISTS hbh_test CASCADE;
CREATE SCHEMA hbh_test;

CREATE TABLE hbh_test.run (started timestamptz NOT NULL DEFAULT now());
INSERT INTO hbh_test.run DEFAULT VALUES;

CREATE TABLE hbh_test.results (
  seq integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  grp text NOT NULL, name text NOT NULL, ok boolean NOT NULL, detail text);
CREATE TABLE hbh_test.fx (k text PRIMARY KEY, v integer);

CREATE PROCEDURE hbh_test.chk(p_grp text, p_name text, p_sql text)
LANGUAGE plpgsql AS $$
DECLARE v_ok boolean;
BEGIN
  BEGIN
    EXECUTE p_sql INTO v_ok;
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, coalesce(v_ok, false),
            CASE WHEN coalesce(v_ok, false) THEN 'ok'
                 WHEN v_ok IS NULL THEN 'returned NULL' ELSE 'returned false' END);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, false, SQLSTATE || ' ' || SQLERRM);
  END;
END $$;

CREATE PROCEDURE hbh_test.chk_raises(p_grp text, p_name text, p_sql text, p_sqlstate text)
LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, false, 'expected ' || p_sqlstate || ', THE CALL SUCCEEDED');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, SQLSTATE = p_sqlstate,
            'expected ' || p_sqlstate || ', got ' || SQLSTATE || ' ' || left(SQLERRM, 60));
  END;
END $$;

GRANT USAGE ON SCHEMA hbh_test TO hbh_app;
GRANT INSERT, SELECT ON hbh_test.results TO hbh_app;
GRANT SELECT ON hbh_test.fx TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh_test TO hbh_app;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA hbh_test TO hbh_app;

-- =====================================================================
-- FIXTURE
--
-- Its own centre, on a mobile block no other suite in this tree uses
-- (+2015 9997 xxxx; phase 15 holds 9999 and this file holds 9997).
-- Cleanup at the bottom deletes BY THE KEYS RECORDED HERE and never by
-- resemblance: a LIKE '015000000%' in phase 5 once matched a
-- neighbouring session's row, died on a foreign key, rolled its own
-- cleanup back with it, and cost the next round twenty-one failures
-- that had nothing to do with anything.
--
-- The time zone is deliberately NOT UTC. A message that prints a moment
-- has to print it where the family lives, and a fixture in UTC would let
-- a function that never converts anything pass every check in here.
-- =====================================================================
INSERT INTO hbh.centers (code, name_ar, time_zone)
VALUES ('P16', 'مركز اختبار المرحلة ١٦', 'Africa/Cairo')
ON CONFLICT (code) DO NOTHING;
INSERT INTO hbh_test.fx (k, v) SELECT 'center', center_id FROM hbh.centers WHERE code = 'P16';

INSERT INTO hbh.branches (center_id, code, name_ar)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), 'P16-MAIN', 'الفرع الرئيسي'
WHERE NOT EXISTS (SELECT 1 FROM hbh.branches WHERE code = 'P16-MAIN');
INSERT INTO hbh_test.fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'P16-MAIN';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile, status)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
       'p16.parent', 'p16 ولي أمر', 'GUARDIAN', '+201599970001', 'ACTIVE'
WHERE NOT EXISTS (SELECT 1 FROM hbh.users WHERE username = 'p16.parent');
INSERT INTO hbh_test.fx (k, v) SELECT 'user', user_id FROM hbh.users WHERE username = 'p16.parent';

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
SELECT u.center_id, u.branch_id, u.user_id, 'p16 ولي أمر', u.mobile
FROM   hbh.users u WHERE u.username = 'p16.parent'
AND NOT EXISTS (SELECT 1 FROM hbh.guardians g WHERE g.user_id = u.user_id);
INSERT INTO hbh_test.fx (k, v)
SELECT 'guardian', g.guardian_id FROM hbh.guardians g
JOIN hbh.users u ON u.user_id = g.user_id WHERE u.username = 'p16.parent';

INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
       'P16-CH1', 'p16 طفل', date '2019-03-01', 'M'
WHERE NOT EXISTS (SELECT 1 FROM hbh.children WHERE child_no = 'P16-CH1');
INSERT INTO hbh_test.fx (k, v) SELECT 'child', child_id FROM hbh.children WHERE child_no = 'P16-CH1';

INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code)
SELECT (SELECT v FROM hbh_test.fx WHERE k='guardian'), (SELECT v FROM hbh_test.fx WHERE k='child'), 'FATHER'
WHERE NOT EXISTS (SELECT 1 FROM hbh.guardian_children
                   WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='guardian')
                   AND   child_id    = (SELECT v FROM hbh_test.fx WHERE k='child'));

-- The consent the default channel asks for. Inserted directly rather
-- than through hbh.grant_consent: the product function writes an event
-- into hbh.consent_events, which is append-only, so a fixture calling it
-- on every run leaves a record saying this family granted the same
-- permission twenty times. The state is what is needed; the history is
-- not this suite's to write.
INSERT INTO hbh.consents (center_id, guardian_id, consent_type, granted_flg, granted_at)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='guardian'),
       'SMS_NOTIFY', true, now()
WHERE NOT EXISTS (SELECT 1 FROM hbh.consents
                   WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='guardian')
                   AND   consent_type = 'SMS_NOTIFY');

INSERT INTO hbh.enrolment_applications
  (center_id, branch_id, application_no, parent_name_ar, parent_mobile,
   child_name_ar, child_birth_date, child_gender, status)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
       'P16-APP-1', 'p16 مقدّم الطلب', '+201599970002',
       'p16 طفل الطلب', date '2020-06-15', 'F', 'NEW'
WHERE NOT EXISTS (SELECT 1 FROM hbh.enrolment_applications WHERE application_no = 'P16-APP-1');
INSERT INTO hbh_test.fx (k, v)
SELECT 'app', application_id FROM hbh.enrolment_applications WHERE application_no = 'P16-APP-1';

-- =====================================================================
-- THE FIXTURE IS CONFIRMED BY NAME, BEFORE ANYTHING IS TESTED THROUGH IT
--
-- A missing piece found through a test appears fifty checks later as a
-- baffling refusal from code that is working perfectly.
-- =====================================================================
CALL hbh_test.chk('fixture', 'the centre, branch and its time zone exist',
  $q$ SELECT count(*) = 1 FROM hbh.centers c
      JOIN hbh_test.fx f ON f.k='center' AND f.v=c.center_id
      WHERE c.time_zone = 'Africa/Cairo' $q$);

CALL hbh_test.chk('fixture', 'the guardian has an account, a child and a consent',
  $q$ SELECT (SELECT count(*) FROM hbh_test.fx WHERE k IN ('user','guardian','child','app')) = 4
         AND EXISTS (SELECT 1 FROM hbh.guardian_children
                      WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='guardian'))
         AND hbh.has_consent((SELECT v FROM hbh_test.fx WHERE k='guardian'), 'SMS_NOTIFY') $q$);

CALL hbh_test.chk('fixture', 'and the channel starts at SMS, so the first claim tests the default',
  $q$ SELECT upper(trim(hbh.param((SELECT v FROM hbh_test.fx WHERE k='center'),
                                  'NOTIFY_CHANNEL', 'SMS'))) = 'SMS' $q$);

-- =====================================================================
-- CLAIM 1 - the outbox carries the values, not only the sentence
-- =====================================================================
DO $notify$
BEGIN
  -- NO LINK AT ALL, and ck_ntf_link is why: a link is a KIND and an ID
  -- together or it is neither, so naming the kind with nothing to point
  -- at is refused. The first draft of this fixture did exactly that, the
  -- notification was never written, and six checks below reported a
  -- working feature as broken.
  PERFORM hbh.notify_guardians((SELECT v FROM hbh_test.fx WHERE k='child'),
                               'APPOINTMENT_BOOKED', 'تم تأكيد موعد', NULL,
                               NULL, NULL);
END
$notify$;

INSERT INTO hbh_test.fx (k, v)
SELECT 'ntf', n.notification_id FROM hbh.notifications n
WHERE  n.user_id = (SELECT v FROM hbh_test.fx WHERE k='user')
ORDER  BY n.notification_id DESC LIMIT 1;

CALL hbh_test.chk('vars', 'the notification was raised with SMS intent',
  $q$ SELECT sms_pending_flg FROM hbh.notifications
      WHERE notification_id = (SELECT v FROM hbh_test.fx WHERE k='ntf') $q$);

CALL hbh_test.chk('vars', 'and it became exactly one outbox row',
  $q$ SELECT count(*) = 1 FROM hbh.sms_outbox
      WHERE dedupe_key = 'NTF:' || (SELECT v FROM hbh_test.fx WHERE k='ntf')::text $q$);

-- The sentence is unchanged. This is the check that fails the day
-- somebody decides the new column replaces the old one.
CALL hbh_test.chk('vars', 'the rendered Arabic an SMS provider wants is still there',
  $q$ SELECT body_ar LIKE 'تم تأكيد موعد%' FROM hbh.sms_outbox
      WHERE dedupe_key = 'NTF:' || (SELECT v FROM hbh_test.fx WHERE k='ntf')::text $q$);

CALL hbh_test.chk('vars', 'and the values a template needs are there beside it',
  $q$ SELECT jsonb_array_length(template_vars) = 1
         AND template_vars->>0 = 'تم تأكيد موعد'
      FROM hbh.sms_outbox
      WHERE dedupe_key = 'NTF:' || (SELECT v FROM hbh_test.fx WHERE k='ntf')::text $q$);

-- 0094 decided what reaches a phone: the title and where to look, never
-- the notification's own body, which may carry an invoice line or a
-- clinical decision. Restating it here means widening it later has to be
-- deliberate.
CALL hbh_test.chk('vars', 'and no clinical detail is among them',
  $q$ SELECT jsonb_array_length(template_vars) = 1 FROM hbh.sms_outbox
      WHERE dedupe_key = 'NTF:' || (SELECT v FROM hbh_test.fx WHERE k='ntf')::text $q$);

CALL hbh_test.chk('vars', 'the worker can claim it and sees both shapes',
  $q$ SELECT count(*) = 1 FROM hbh.claim_sms(50, 'p16')
      WHERE body_ar IS NOT NULL AND template_vars IS NOT NULL $q$);

-- =====================================================================
-- CLAIM 2 - and a login code may never be among them
--
-- THE REFUSAL APPLIES TO THE OWNER TOO, which is why these two run
-- without SET ROLE. A CHECK constraint is not a grant and not a policy:
-- it is the one kind of rule hbh_owner cannot walk through, and that is
-- exactly why the code being at rest is prevented by one.
-- =====================================================================
CALL hbh_test.chk_raises('otp', 'a login code may not store its own plaintext - 23514',
  $q$ INSERT INTO hbh.sms_outbox (center_id, purpose, template_code, destination,
                                  dedupe_key, template_vars)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'OTP_LOGIN', 'OTP',
              '+201599970001', 'P16-OTP-BAD', jsonb_build_array('123456')) $q$,
  '23514');

-- AND THE ACCEPTANCE THAT PROVES IT WAS CONDITIONAL. Without this, a
-- constraint that refused every OTP row for any reason would pass the
-- check above and nobody would find out until login stopped working.
CALL hbh_test.chk('otp', 'and the same row without them is accepted',
  $q$ WITH i AS (
        INSERT INTO hbh.sms_outbox (center_id, purpose, template_code, destination,
                                    dedupe_key, status, sent_at, provider_code)
        VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'OTP_LOGIN', 'OTP',
                '+201599970001', 'P16-OTP-OK', 'SENT', now(), 'p16')
        RETURNING 1)
      SELECT count(*) = 1 FROM i $q$);

CALL hbh_test.chk('otp', 'and nothing of the refused one was written',
  $q$ SELECT NOT EXISTS (SELECT 1 FROM hbh.sms_outbox WHERE dedupe_key = 'P16-OTP-BAD') $q$);

-- =====================================================================
-- CLAIM 3 - the family who applied is told when the first interview is
-- =====================================================================
CALL hbh_test.chk('enrol', 'the application is contacted first - the state machine allows no jump',
  $q$ WITH u AS (UPDATE hbh.enrolment_applications SET status = 'CONTACTED'
                  WHERE application_id = (SELECT v FROM hbh_test.fx WHERE k='app')
                  RETURNING 1)
      SELECT count(*) = 1 FROM u $q$);

-- A status asserting a booking the schema cannot describe is a status
-- that means less than it says - and the message this migration exists
-- to send cannot be written from it.
CALL hbh_test.chk_raises('enrol', 'a booking with no time is refused - 23514',
  $q$ UPDATE hbh.enrolment_applications SET status = 'ASSESSMENT_BOOKED'
       WHERE application_id = (SELECT v FROM hbh_test.fx WHERE k='app') $q$,
  '23514');

CALL hbh_test.chk('enrol', 'and the same transition with a time is accepted',
  $q$ WITH u AS (UPDATE hbh.enrolment_applications
                    SET status = 'ASSESSMENT_BOOKED',
                        assessment_at = timestamptz '2026-10-05 09:30:00+00'
                  WHERE application_id = (SELECT v FROM hbh_test.fx WHERE k='app')
                  RETURNING 1)
      SELECT count(*) = 1 FROM u $q$);

CALL hbh_test.chk('enrol', 'the applicant got exactly one message',
  $q$ SELECT count(*) = 1 FROM hbh.sms_outbox
      WHERE dedupe_key = 'ENR:' || (SELECT v FROM hbh_test.fx WHERE k='app')::text $q$);

-- An applicant has no user account, so there is no feed for this to
-- point at. notify_guardians would have matched no rows and said nothing.
CALL hbh_test.chk('enrol', 'and it belongs to no notification feed',
  $q$ SELECT notification_id IS NULL AND purpose = 'ENROLMENT_ASSESSMENT'
         AND body_ar IS NOT NULL
      FROM hbh.sms_outbox
      WHERE dedupe_key = 'ENR:' || (SELECT v FROM hbh_test.fx WHERE k='app')::text $q$);

CALL hbh_test.chk('enrol', 'it carries three values: the parent, the child and the time',
  $q$ SELECT jsonb_array_length(template_vars) = 3
         AND template_vars->>0 = 'p16 مقدّم الطلب'
         AND template_vars->>1 = 'p16 طفل الطلب'
      FROM hbh.sms_outbox
      WHERE dedupe_key = 'ENR:' || (SELECT v FROM hbh_test.fx WHERE k='app')::text $q$);

-- STORED UTC, PRINTED WHERE THE FAMILY LIVES. 09:30Z is 12:30 in Cairo,
-- and a function that forgot to convert would print 09:30 and pass every
-- other check in this group.
CALL hbh_test.chk('enrol', 'and the time is the centre''s own, not the server''s',
  $q$ SELECT template_vars->>2 = '05/10/2026 - 12:30'
         AND position('05/10/2026 - 12:30' in body_ar) > 0
      FROM hbh.sms_outbox
      WHERE dedupe_key = 'ENR:' || (SELECT v FROM hbh_test.fx WHERE k='app')::text $q$);

-- =====================================================================
-- CLAIM 4 - the channel decides which consent is asked for
-- =====================================================================
CALL hbh_test.chk('channel', 'a guardian who agreed to SMS is messaged while the channel is SMS',
  $q$ SELECT sms_pending_flg FROM hbh.notifications
      WHERE notification_id = (SELECT v FROM hbh_test.fx WHERE k='ntf') $q$);

INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type, description_ar)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), 'NOTIFY_CHANNEL', 'WHATSAPP', 'STRING', 'p16'
ON CONFLICT (center_id, param_code) DO UPDATE SET param_value = 'WHATSAPP', active_flg = true;

DO $wa$
BEGIN
  PERFORM hbh.notify_guardians((SELECT v FROM hbh_test.fx WHERE k='child'),
                               'APPOINTMENT_BOOKED', 'تم تأكيد موعد - واتساب', NULL, NULL, NULL);
END
$wa$;

-- THE FAIL-CLOSED DIRECTION, and it is meant to look like an outage.
-- The family keeps the notification in the portal and stops being
-- messaged, because they agreed to one channel and not the other.
CALL hbh_test.chk('channel', 'the same guardian is NOT messaged once the channel is WhatsApp',
  $q$ SELECT NOT sms_pending_flg FROM hbh.notifications
      WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user')
      ORDER BY notification_id DESC LIMIT 1 $q$);

INSERT INTO hbh.consents (center_id, guardian_id, consent_type, granted_flg, granted_at)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='guardian'),
       'WHATSAPP_NOTIFY', true, now()
WHERE NOT EXISTS (SELECT 1 FROM hbh.consents
                   WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='guardian')
                   AND   consent_type = 'WHATSAPP_NOTIFY');

DO $wa2$
BEGIN
  PERFORM hbh.notify_guardians((SELECT v FROM hbh_test.fx WHERE k='child'),
                               'APPOINTMENT_BOOKED', 'تم تأكيد موعد - بعد الموافقة', NULL, NULL, NULL);
END
$wa2$;

-- AND THE ACCEPTANCE. Without this the refusal above would also pass on
-- a database where WHATSAPP_NOTIFY can never be granted at all - which
-- is precisely the shape the photograph gate had for a fortnight.
CALL hbh_test.chk('channel', 'and IS messaged once they agree to WhatsApp',
  $q$ SELECT sms_pending_flg FROM hbh.notifications
      WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user')
      ORDER BY notification_id DESC LIMIT 1 $q$);

CALL hbh_test.chk_raises('channel', 'being messaged is about the guardian, so it carries no child - 23514',
  $q$ INSERT INTO hbh.consents (center_id, guardian_id, child_id, consent_type, granted_flg, granted_at)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'),
              (SELECT v FROM hbh_test.fx WHERE k='guardian'),
              (SELECT v FROM hbh_test.fx WHERE k='child'), 'WHATSAPP_NOTIFY', true, now()) $q$,
  '23514');

-- 'WHATS_APP' AND NOT 'Whatsapp'. The first draft used the latter and the
-- check failed by PASSING: notify_guardians reads the parameter through
-- upper(trim(...)), so 'Whatsapp' is 'WHATSAPP' and perfectly valid. That
-- is the right behaviour - a centre manager typing a capital letter
-- differently should not stop a family being messaged - and it means a
-- test for the unreadable case has to supply something genuinely
-- unreadable rather than something merely untidy.
UPDATE hbh.sys_params SET param_value = 'WHATS_APP'
 WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center') AND param_code = 'NOTIFY_CHANNEL';

-- A MISSPELLING IS NOT A DEFAULT. Falling through to SMS_NOTIFY here
-- would message families on a channel the centre believed it had left,
-- and nothing anywhere would say so.
CALL hbh_test.chk_raises('channel', 'an unreadable channel raises rather than guessing - HB232',
  $q$ SELECT hbh.notify_guardians((SELECT v FROM hbh_test.fx WHERE k='child'),
                                  'APPOINTMENT_BOOKED', 'لن تُكتب', NULL, NULL, NULL) $q$,
  'HB232');

CALL hbh_test.chk('channel', 'and it wrote nothing on its way out',
  $q$ SELECT NOT EXISTS (SELECT 1 FROM hbh.notifications
                          WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user')
                          AND   title_ar = 'لن تُكتب') $q$);

-- =====================================================================
-- CLEANUP
--
-- BY IDENTITY, NEVER BY RESEMBLANCE, and children before parents: several
-- data-modifying CTEs in one statement have no ordering between them, so
-- one statement per level.
-- =====================================================================
CALL hbh_test.chk('cleanup', 'the outbox rows this suite made are gone',
  $q$ WITH d AS (DELETE FROM hbh.sms_outbox
                  WHERE dedupe_key IN ('P16-OTP-OK',
                                       'ENR:' || (SELECT v FROM hbh_test.fx WHERE k='app')::text)
                     OR notification_id IN (SELECT notification_id FROM hbh.notifications
                                             WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user'))
                  RETURNING 1)
      SELECT count(*) >= 2 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the notifications are gone',
  $q$ WITH d AS (DELETE FROM hbh.notifications
                  WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user') RETURNING 1)
      SELECT count(*) >= 3 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the application is gone',
  $q$ WITH d AS (DELETE FROM hbh.enrolment_applications
                  WHERE application_id = (SELECT v FROM hbh_test.fx WHERE k='app') RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the consents are gone',
  $q$ WITH d AS (DELETE FROM hbh.consents
                  WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='guardian') RETURNING 1)
      SELECT count(*) >= 2 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the family link is gone',
  $q$ WITH d AS (DELETE FROM hbh.guardian_children
                  WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='guardian') RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the child is gone',
  $q$ WITH d AS (DELETE FROM hbh.children
                  WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child') RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the guardian is gone',
  $q$ WITH d AS (DELETE FROM hbh.guardians
                  WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='guardian') RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the account is gone',
  $q$ WITH d AS (DELETE FROM hbh.users
                  WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user') RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the parameter this suite set is gone',
  $q$ WITH d AS (DELETE FROM hbh.sys_params
                  WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center')
                  RETURNING 1)
      SELECT count(*) >= 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the branch and the centre are gone',
  $q$ WITH b AS (DELETE FROM hbh.branches
                  WHERE branch_id = (SELECT v FROM hbh_test.fx WHERE k='branch') RETURNING 1)
      SELECT count(*) = 1 FROM b $q$);

CALL hbh_test.chk('cleanup', 'and the centre itself',
  $q$ WITH c AS (DELETE FROM hbh.centers
                  WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center') RETURNING 1)
      SELECT count(*) = 1 FROM c $q$);

-- "At least one, then nothing left" - the property is that this suite
-- left no trace, not that a particular run's arithmetic came out. Ids are
-- reused after a hard delete, so a fixed count breaks the day a number
-- comes round again carrying rows from a previous life.
CALL hbh_test.chk('cleanup', 'and nothing of this suite is left behind',
  $q$ SELECT NOT EXISTS (SELECT 1 FROM hbh.users    WHERE username = 'p16.parent')
         AND NOT EXISTS (SELECT 1 FROM hbh.centers  WHERE code = 'P16')
         AND NOT EXISTS (SELECT 1 FROM hbh.children WHERE child_no = 'P16-CH1')
         AND NOT EXISTS (SELECT 1 FROM hbh.enrolment_applications WHERE application_no = 'P16-APP-1')
         AND NOT EXISTS (SELECT 1 FROM hbh.sms_outbox WHERE provider_code = 'p16') $q$);

-- =====================================================================
-- VERDICT
-- =====================================================================
\echo ''
SELECT grp AS "المجموعة", count(*) AS "اختبارات",
       count(*) FILTER (WHERE NOT ok) AS "فشل"
FROM hbh_test.results GROUP BY grp ORDER BY min(seq);

\echo ''
SELECT seq, grp, name, detail FROM hbh_test.results WHERE NOT ok ORDER BY seq;

DO $verdict$
DECLARE v_total integer; v_fail integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE NOT ok) INTO v_total, v_fail FROM hbh_test.results;
  RAISE NOTICE '';
  RAISE NOTICE '--------------------------------------------------';
  RAISE NOTICE '  % checks, % failed', v_total, v_fail;
  IF v_fail = 0 AND v_total > 0 THEN RAISE NOTICE '  PHASE 16 ACCEPTED';
  ELSE RAISE NOTICE '  *** PHASE 16 NOT ACCEPTED'; END IF;
  RAISE NOTICE '--------------------------------------------------';
END
$verdict$;
