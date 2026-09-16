-- =====================================================================
-- Hand By Hand (new) - PHASE 18 acceptance suite: the appointment reminder
--
-- Must print:  PHASE 18 ACCEPTED
--
-- Migration 0148. Four claims:
--
--   1. A REMINDER SAYS WHOSE SESSION IT IS AND WHEN, IN THE CENTRE'S TIME.
--      The child, the day in Arabic, the date and a 12-hour time with its
--      Arabic period - converted from UTC to hbh.centers.time_zone, never
--      printed as stored.
--   2. A MOVED SESSION SAYS IT WAS MOVED, AND FROM WHICH DAY. Under its
--      own template code, because WhatsApp refuses a blank variable and an
--      ordinary reminder has nothing to put in that slot.
--   3. NOTHING ELSE CHANGED. Every other notification kind still reaches
--      the phone as its title and a pointer to the portal, and consent
--      still decides who is told. The branch is for reminders; a check
--      that only looked at reminders could not see it leak.
--   4. AND WHAT CANNOT BE BUILT FALLS BACK, RATHER THAN SENDING NOTHING.
--      A reminder with no appointment to read still sends the title a
--      family received before this migration.
--
-- WHAT IT DOES NOT CARRY is part of the decision (D-42): no amount, no
-- offer, no policy numbers, no "session N of M". The variable counts are
-- asserted exactly, so a fifth or sixth value added later has to come
-- with a change to this file.
--
-- THIS SUITE BUILDS ITS OWN CENTRE, for p16's reason and one of its own:
-- the reminder prints the centre's time zone, and a fixture borrowing the
-- shared centre would pass or fail on how that centre happens to be set.
-- It does NOT call hbh.queue_appointment_reminders: that reads a GLOBAL
-- parameter and walks every centre's appointments. It calls
-- notify_guardians with exactly the arguments the queue passes, which is
-- the path under test.
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

GRANT USAGE ON SCHEMA hbh_test TO hbh_app;
GRANT INSERT, SELECT ON hbh_test.results TO hbh_app;
GRANT SELECT ON hbh_test.fx TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh_test TO hbh_app;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA hbh_test TO hbh_app;

-- =====================================================================
-- FIXTURE
--
-- Mobile block +2015 9996 xxxx: p15 holds 9999, p16 holds 9997. Codes are
-- P18-. Cleanup deletes by the keys recorded here, never by resemblance.
--
-- The times are written in Cairo and stored as timestamptz, so the fixture
-- itself states the local hour the family must be shown. The ordinary
-- session is a Tuesday at 17:00; the moved one a Sunday at 17:00 standing
-- in for it; the morning one exists to prove the period is not constant.
-- =====================================================================
INSERT INTO hbh.centers (code, name_ar, time_zone)
VALUES ('P18', 'مركز هاند باي هاند للمهارات', 'Africa/Cairo')
ON CONFLICT (code) DO NOTHING;
INSERT INTO hbh_test.fx (k, v) SELECT 'center', center_id FROM hbh.centers WHERE code = 'P18';

INSERT INTO hbh.branches (center_id, code, name_ar)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), 'P18-MAIN', 'الفرع الرئيسي'
WHERE NOT EXISTS (SELECT 1 FROM hbh.branches WHERE code = 'P18-MAIN');
INSERT INTO hbh_test.fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'P18-MAIN';

INSERT INTO hbh.therapists (center_id, full_name_ar)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), 'p18 أخصائية'
WHERE NOT EXISTS (SELECT 1 FROM hbh.therapists
                   WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center'));
INSERT INTO hbh_test.fx (k, v)
SELECT 'therapist', therapist_id FROM hbh.therapists
WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center');

INSERT INTO hbh.services (center_id, code, name_ar, kind_code)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), 'P18-SPEECH', 'تخاطب', 'SPEECH'
WHERE NOT EXISTS (SELECT 1 FROM hbh.services WHERE code = 'P18-SPEECH');
INSERT INTO hbh_test.fx (k, v) SELECT 'service', service_id FROM hbh.services WHERE code = 'P18-SPEECH';

INSERT INTO hbh.rooms (center_id, branch_id, code, name_ar)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
       'P18-R1', 'غرفة'
WHERE NOT EXISTS (SELECT 1 FROM hbh.rooms WHERE code = 'P18-R1');
INSERT INTO hbh_test.fx (k, v) SELECT 'room', room_id FROM hbh.rooms WHERE code = 'P18-R1';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile, status)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
       'p18.parent', 'p18 ولي أمر', 'GUARDIAN', '+201599960001', 'ACTIVE'
WHERE NOT EXISTS (SELECT 1 FROM hbh.users WHERE username = 'p18.parent');
INSERT INTO hbh_test.fx (k, v) SELECT 'user', user_id FROM hbh.users WHERE username = 'p18.parent';

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
SELECT u.center_id, u.branch_id, u.user_id, 'p18 ولي أمر', u.mobile
FROM   hbh.users u WHERE u.username = 'p18.parent'
AND NOT EXISTS (SELECT 1 FROM hbh.guardians g WHERE g.user_id = u.user_id);
INSERT INTO hbh_test.fx (k, v)
SELECT 'guardian', g.guardian_id FROM hbh.guardians g
JOIN hbh.users u ON u.user_id = g.user_id WHERE u.username = 'p18.parent';

INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
       'P18-CH1', 'p18 طفل', date '2019-03-01', 'M'
WHERE NOT EXISTS (SELECT 1 FROM hbh.children WHERE child_no = 'P18-CH1');
INSERT INTO hbh_test.fx (k, v) SELECT 'child', child_id FROM hbh.children WHERE child_no = 'P18-CH1';

INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code)
SELECT (SELECT v FROM hbh_test.fx WHERE k='guardian'), (SELECT v FROM hbh_test.fx WHERE k='child'), 'FATHER'
WHERE NOT EXISTS (SELECT 1 FROM hbh.guardian_children
                   WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='guardian'));

-- Direct, not through grant_consent: the product function writes an
-- append-only event, and a fixture must not leave twenty of them.
INSERT INTO hbh.consents (center_id, guardian_id, consent_type, granted_flg, granted_at)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='guardian'),
       'SMS_NOTIFY', true, now()
WHERE NOT EXISTS (SELECT 1 FROM hbh.consents
                   WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='guardian'));

-- Direct inserts with explicit numbers, so no number series is needed for
-- a centre that exists only for the length of this file.
INSERT INTO hbh.appointments (center_id, branch_id, appointment_no, child_id, therapist_id,
                              service_id, room_id, starts_at, ends_at)
SELECT f.center, f.branch, 'P18-A-TUE', f.child, f.therapist, f.service, f.room,
       timestamptz '2026-10-06 17:00:00 Africa/Cairo', timestamptz '2026-10-06 18:00:00 Africa/Cairo'
FROM (SELECT (SELECT v FROM hbh_test.fx WHERE k='center')    AS center,
             (SELECT v FROM hbh_test.fx WHERE k='branch')    AS branch,
             (SELECT v FROM hbh_test.fx WHERE k='child')     AS child,
             (SELECT v FROM hbh_test.fx WHERE k='therapist') AS therapist,
             (SELECT v FROM hbh_test.fx WHERE k='service')   AS service,
             (SELECT v FROM hbh_test.fx WHERE k='room')      AS room) f
WHERE NOT EXISTS (SELECT 1 FROM hbh.appointments WHERE appointment_no = 'P18-A-TUE');
INSERT INTO hbh_test.fx (k, v) SELECT 'appt_tue', appointment_id FROM hbh.appointments WHERE appointment_no = 'P18-A-TUE';

INSERT INTO hbh.appointments (center_id, branch_id, appointment_no, child_id, therapist_id,
                              service_id, room_id, starts_at, ends_at, rescheduled_from_appointment_id)
SELECT f.center, f.branch, 'P18-A-SUN', f.child, f.therapist, f.service, f.room,
       timestamptz '2026-10-04 17:00:00 Africa/Cairo', timestamptz '2026-10-04 18:00:00 Africa/Cairo',
       (SELECT v FROM hbh_test.fx WHERE k='appt_tue')
FROM (SELECT (SELECT v FROM hbh_test.fx WHERE k='center')    AS center,
             (SELECT v FROM hbh_test.fx WHERE k='branch')    AS branch,
             (SELECT v FROM hbh_test.fx WHERE k='child')     AS child,
             (SELECT v FROM hbh_test.fx WHERE k='therapist') AS therapist,
             (SELECT v FROM hbh_test.fx WHERE k='service')   AS service,
             (SELECT v FROM hbh_test.fx WHERE k='room')      AS room) f
WHERE NOT EXISTS (SELECT 1 FROM hbh.appointments WHERE appointment_no = 'P18-A-SUN');
INSERT INTO hbh_test.fx (k, v) SELECT 'appt_sun', appointment_id FROM hbh.appointments WHERE appointment_no = 'P18-A-SUN';

INSERT INTO hbh.appointments (center_id, branch_id, appointment_no, child_id, therapist_id,
                              service_id, room_id, starts_at, ends_at)
SELECT f.center, f.branch, 'P18-A-AM', f.child, f.therapist, f.service, f.room,
       timestamptz '2026-10-08 09:30:00 Africa/Cairo', timestamptz '2026-10-08 10:30:00 Africa/Cairo'
FROM (SELECT (SELECT v FROM hbh_test.fx WHERE k='center')    AS center,
             (SELECT v FROM hbh_test.fx WHERE k='branch')    AS branch,
             (SELECT v FROM hbh_test.fx WHERE k='child')     AS child,
             (SELECT v FROM hbh_test.fx WHERE k='therapist') AS therapist,
             (SELECT v FROM hbh_test.fx WHERE k='service')   AS service,
             (SELECT v FROM hbh_test.fx WHERE k='room')      AS room) f
WHERE NOT EXISTS (SELECT 1 FROM hbh.appointments WHERE appointment_no = 'P18-A-AM');
INSERT INTO hbh_test.fx (k, v) SELECT 'appt_am', appointment_id FROM hbh.appointments WHERE appointment_no = 'P18-A-AM';

-- =====================================================================
-- THE FIXTURE IS CONFIRMED BY NAME, BEFORE ANYTHING IS TESTED THROUGH IT
-- =====================================================================
CALL hbh_test.chk('fixture', 'every piece of the fixture was made',
  $q$ SELECT count(*) = 11 FROM hbh_test.fx
       WHERE k IN ('center','branch','therapist','service','room','user','guardian',
                   'child','appt_tue','appt_sun','appt_am') AND v IS NOT NULL $q$);

CALL hbh_test.chk('fixture', 'the centre is in Cairo and the guardian has agreed to messages',
  $q$ SELECT (SELECT time_zone FROM hbh.centers
               WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center')) = 'Africa/Cairo'
         AND hbh.has_consent((SELECT v FROM hbh_test.fx WHERE k='guardian'), 'SMS_NOTIFY') $q$);

-- 17:00 in Cairo is 14:00 UTC. If this is not what is stored, every time
-- check below is measuring the fixture and not the function.
CALL hbh_test.chk('fixture', 'the Tuesday session is stored in UTC, three hours behind Cairo',
  $q$ SELECT starts_at = timestamptz '2026-10-06 14:00:00+00' FROM hbh.appointments
      WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_tue') $q$);

CALL hbh_test.chk('fixture', 'the channel is SMS, so the consent above is the one asked for',
  $q$ SELECT upper(trim(hbh.param((SELECT v FROM hbh_test.fx WHERE k='center'),
                                  'NOTIFY_CHANNEL', 'SMS'))) = 'SMS' $q$);

-- =====================================================================
-- CLAIM 1 - whose session, and when, in the centre's time
-- =====================================================================
CALL hbh_test.chk('message', 'an ordinary session is an ordinary reminder with exactly four values',
  $q$ SELECT template_code = 'APPOINTMENT_REMINDER'
         AND jsonb_array_length(template_vars) = 4
      FROM hbh.appointment_reminder_message((SELECT v FROM hbh_test.fx WHERE k='appt_tue')) $q$);

CALL hbh_test.chk('message', 'in the template''s order: child, day, date, time',
  $q$ SELECT template_vars = jsonb_build_array('p18 طفل', 'الثلاثاء', '06/10/2026', '5:00 مساءً')
      FROM hbh.appointment_reminder_message((SELECT v FROM hbh_test.fx WHERE k='appt_tue')) $q$);

-- The acceptance beside the one above: if the period were a constant, the
-- evening check passes and this one does not.
CALL hbh_test.chk('message', 'a morning session is marked as morning',
  $q$ SELECT template_vars->>1 = 'الخميس' AND template_vars->>3 = '9:30 صباحًا'
      FROM hbh.appointment_reminder_message((SELECT v FROM hbh_test.fx WHERE k='appt_am')) $q$);

CALL hbh_test.chk('message', 'the SMS text names the centre, the child and the same moment',
  $q$ SELECT body_ar = 'مركز هاند باي هاند للمهارات: تذكير بموعد جلسة p18 طفل يوم الثلاثاء 06/10/2026 الساعة 5:00 مساءً.'
      FROM hbh.appointment_reminder_message((SELECT v FROM hbh_test.fx WHERE k='appt_tue')) $q$);

-- D-42: no amount and no "session N of M". Asserted on the text, because a
-- value can be added to the body without touching the variable count.
CALL hbh_test.chk('message', 'and no amount, offer or session count is in it',
  $q$ SELECT body_ar !~ '(جم|جنيه|EGP|مصاريف|عرض|جلسة رقم| من [0-9]+)'
      FROM hbh.appointment_reminder_message((SELECT v FROM hbh_test.fx WHERE k='appt_tue')) $q$);

-- =====================================================================
-- CLAIM 2 - a moved session says it was moved, and from which day
-- =====================================================================
CALL hbh_test.chk('moved', 'a moved session uses its own template code, with five values',
  $q$ SELECT template_code = 'APPOINTMENT_REMINDER_RESCHEDULED'
         AND jsonb_array_length(template_vars) = 5
      FROM hbh.appointment_reminder_message((SELECT v FROM hbh_test.fx WHERE k='appt_sun')) $q$);

CALL hbh_test.chk('moved', 'the fifth is the day it stands in for, and the rest are its own',
  $q$ SELECT template_vars = jsonb_build_array('p18 طفل', 'الأحد', '04/10/2026', '5:00 مساءً', 'الثلاثاء')
      FROM hbh.appointment_reminder_message((SELECT v FROM hbh_test.fx WHERE k='appt_sun')) $q$);

CALL hbh_test.chk('moved', 'and the SMS text says the regular slots stand',
  $q$ SELECT body_ar LIKE '%(موعد مؤقت بدلًا من يوم الثلاثاء، ومواعيدكم الأصلية كما هي.)'
      FROM hbh.appointment_reminder_message((SELECT v FROM hbh_test.fx WHERE k='appt_sun')) $q$);

-- =====================================================================
-- THROUGH THE REAL PATH - notify_guardians with the queue's own arguments
-- =====================================================================
DO $send$
BEGIN
  PERFORM hbh.notify_guardians((SELECT v FROM hbh_test.fx WHERE k='child'),
    'APPOINTMENT_REMINDER', 'تذكير بموعد قادم', NULL,
    'APPOINTMENT', (SELECT v FROM hbh_test.fx WHERE k='appt_sun'));
END
$send$;
INSERT INTO hbh_test.fx (k, v)
SELECT 'ntf_reminder', max(notification_id) FROM hbh.notifications
WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user')
AND   kind_code = 'APPOINTMENT_REMINDER'
AND   link_id = (SELECT v FROM hbh_test.fx WHERE k='appt_sun');

CALL hbh_test.chk('outbox', 'the reminder reached the outbox under the moved-session code',
  $q$ SELECT template_code = 'APPOINTMENT_REMINDER_RESCHEDULED' AND status = 'PENDING'
         AND destination = '+201599960001'
      FROM hbh.sms_outbox
      WHERE dedupe_key = 'NTF:' || (SELECT v FROM hbh_test.fx WHERE k='ntf_reminder')::text $q$);

CALL hbh_test.chk('outbox', 'carrying exactly what the message function built',
  $q$ SELECT o.template_vars = m.template_vars AND o.body_ar = m.body_ar
      FROM hbh.sms_outbox o,
           hbh.appointment_reminder_message((SELECT v FROM hbh_test.fx WHERE k='appt_sun')) m
      WHERE o.dedupe_key = 'NTF:' || (SELECT v FROM hbh_test.fx WHERE k='ntf_reminder')::text $q$);

-- The portal still shows the short title; only the phone got the detail.
CALL hbh_test.chk('outbox', 'and the portal row is still the plain title',
  $q$ SELECT title_ar = 'تذكير بموعد قادم' FROM hbh.notifications
      WHERE notification_id = (SELECT v FROM hbh_test.fx WHERE k='ntf_reminder') $q$);

-- =====================================================================
-- CLAIM 3 - nothing else changed
-- =====================================================================
DO $other$
BEGIN
  PERFORM hbh.notify_guardians((SELECT v FROM hbh_test.fx WHERE k='child'),
    'APPOINTMENT_BOOKED', 'p18 عنوان آخر', NULL,
    'APPOINTMENT', (SELECT v FROM hbh_test.fx WHERE k='appt_tue'));
END
$other$;
INSERT INTO hbh_test.fx (k, v)
SELECT 'ntf_other', max(notification_id) FROM hbh.notifications
WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user') AND title_ar = 'p18 عنوان آخر';

-- Same appointment link, different kind: the branch must not fire. This is
-- the check that sees the rule on names leak beyond reminders.
CALL hbh_test.chk('others', 'another kind linked to the same appointment still sends only its title',
  $q$ SELECT template_code = 'APPOINTMENT_BOOKED'
         AND template_vars = jsonb_build_array('p18 عنوان آخر')
         AND body_ar = 'p18 عنوان آخر — تابع التفاصيل من بوّابة ولي الأمر.'
         AND position('p18 طفل' in body_ar) = 0
      FROM hbh.sms_outbox
      WHERE dedupe_key = 'NTF:' || (SELECT v FROM hbh_test.fx WHERE k='ntf_other')::text $q$);

UPDATE hbh.consents SET granted_flg = false
 WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='guardian') AND consent_type = 'SMS_NOTIFY';

DO $noconsent$
BEGIN
  PERFORM hbh.notify_guardians((SELECT v FROM hbh_test.fx WHERE k='child'),
    'APPOINTMENT_REMINDER', 'تذكير بموعد قادم', NULL,
    'APPOINTMENT', (SELECT v FROM hbh_test.fx WHERE k='appt_tue'));
END
$noconsent$;

-- Consent still decides who is told. The portal row is written; the phone
-- is not reached. Paired with the outbox checks above, which prove the
-- same call reaches it while consent is granted.
CALL hbh_test.chk('others', 'without consent the reminder is in the portal and not on the phone',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.notifications n
                      WHERE n.user_id = (SELECT v FROM hbh_test.fx WHERE k='user')
                      AND   n.kind_code = 'APPOINTMENT_REMINDER'
                      AND   n.link_id = (SELECT v FROM hbh_test.fx WHERE k='appt_tue')
                      AND   NOT n.sms_pending_flg)
         AND NOT EXISTS (SELECT 1 FROM hbh.sms_outbox o JOIN hbh.notifications n USING (notification_id)
                          WHERE n.user_id = (SELECT v FROM hbh_test.fx WHERE k='user')
                          AND   n.kind_code = 'APPOINTMENT_REMINDER'
                          AND   n.link_id = (SELECT v FROM hbh_test.fx WHERE k='appt_tue')) $q$);

UPDATE hbh.consents SET granted_flg = true
 WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='guardian') AND consent_type = 'SMS_NOTIFY';

-- =====================================================================
-- CLAIM 4 - what cannot be built falls back
-- =====================================================================
DO $nolink$
BEGIN
  PERFORM hbh.notify_guardians((SELECT v FROM hbh_test.fx WHERE k='child'),
    'APPOINTMENT_REMINDER', 'p18 تذكير بلا رابط', NULL, NULL, NULL);
END
$nolink$;
INSERT INTO hbh_test.fx (k, v)
SELECT 'ntf_nolink', max(notification_id) FROM hbh.notifications
WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user') AND title_ar = 'p18 تذكير بلا رابط';

CALL hbh_test.chk('fallback', 'a reminder with no appointment to read still sends its title',
  $q$ SELECT template_code = 'APPOINTMENT_REMINDER'
         AND template_vars = jsonb_build_array('p18 تذكير بلا رابط')
         AND status = 'PENDING'
      FROM hbh.sms_outbox
      WHERE dedupe_key = 'NTF:' || (SELECT v FROM hbh_test.fx WHERE k='ntf_nolink')::text $q$);

CALL hbh_test.chk('fallback', 'and an appointment that does not exist builds nothing',
  $q$ SELECT NOT EXISTS (SELECT 1 FROM hbh.appointment_reminder_message(
                           (SELECT coalesce(max(appointment_id), 0) + 1000000 FROM hbh.appointments))) $q$);

-- =====================================================================
-- CLEANUP - by identity, children before parents, one statement a level
-- =====================================================================
CALL hbh_test.chk('cleanup', 'the outbox rows are gone',
  $q$ WITH d AS (DELETE FROM hbh.sms_outbox
                  WHERE notification_id IN (SELECT notification_id FROM hbh.notifications
                                             WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user'))
                  RETURNING 1)
      SELECT count(*) >= 3 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the notifications are gone',
  $q$ WITH d AS (DELETE FROM hbh.notifications
                  WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user') RETURNING 1)
      SELECT count(*) >= 4 FROM d $q$);

-- The status history is append-only (HB001), so its guard is switched off
-- for this one delete, as p10, p11 and p13 do - and switched back on
-- immediately, and then CHECKED to be on. A cleanup that leaves an
-- append-only table writable has quietly removed the one guarantee that
-- table exists to give, for every session on this database.
--
-- ">= 1", not ">= 0": a delete that may remove nothing is a check that
-- can never fail. Whether every row went is asserted at the end.
ALTER TABLE hbh.appointment_status_history DISABLE TRIGGER trg_ash_append_only;
CALL hbh_test.chk('cleanup', 'the appointments'' status history is gone',
  $q$ WITH d AS (DELETE FROM hbh.appointment_status_history
                  WHERE appointment_id IN (SELECT v FROM hbh_test.fx
                                            WHERE k IN ('appt_tue','appt_sun','appt_am'))
                  RETURNING 1)
      SELECT count(*) >= 1 FROM d $q$);
ALTER TABLE hbh.appointment_status_history ENABLE TRIGGER trg_ash_append_only;

CALL hbh_test.chk('cleanup', 'and the append-only guard on that history is back on',
  $q$ SELECT tgenabled = 'O' FROM pg_trigger
      WHERE tgrelid = 'hbh.appointment_status_history'::regclass
      AND   tgname = 'trg_ash_append_only' $q$);

-- The moved session references the original, so it goes first.
CALL hbh_test.chk('cleanup', 'the moved session is gone',
  $q$ WITH d AS (DELETE FROM hbh.appointments
                  WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_sun') RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the other sessions are gone',
  $q$ WITH d AS (DELETE FROM hbh.appointments
                  WHERE appointment_id IN (SELECT v FROM hbh_test.fx WHERE k IN ('appt_tue','appt_am'))
                  RETURNING 1)
      SELECT count(*) = 2 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the consent is gone',
  $q$ WITH d AS (DELETE FROM hbh.consents
                  WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='guardian') RETURNING 1)
      SELECT count(*) >= 1 FROM d $q$);

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

CALL hbh_test.chk('cleanup', 'the room is gone',
  $q$ WITH d AS (DELETE FROM hbh.rooms
                  WHERE room_id = (SELECT v FROM hbh_test.fx WHERE k='room') RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the service is gone',
  $q$ WITH d AS (DELETE FROM hbh.services
                  WHERE service_id = (SELECT v FROM hbh_test.fx WHERE k='service') RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the therapist is gone',
  $q$ WITH d AS (DELETE FROM hbh.therapists
                  WHERE therapist_id = (SELECT v FROM hbh_test.fx WHERE k='therapist') RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

-- ROWS THIS SUITE NEVER WROTE, AND THEY STILL BELONG TO IT. scripts/db.sh
-- migrate runs the seed files after the migrations, and the seeds give
-- every centre that exists at that moment its number series, profile
-- rules and payment plans. The first run of this file left its centre
-- behind, a migrate ran two minutes later, and the next cleanup died on
-- fk_pfr_center with every check above it green. Any session's migrate
-- landing while this file runs does the same. They are deleted by this
-- centre's id - which exists only for this file - and the last check
-- below asserts none remain, so these plain statements cannot fail
-- silently.
--
-- The seeded plans are ACTIVE, and trg_ppi_frozen refuses to change an
-- active plan's instalments. It is switched off for this one delete, as
-- p17 does, and checked to be back on straight after.
ALTER TABLE hbh.payment_plan_installments DISABLE TRIGGER trg_ppi_frozen;
DELETE FROM hbh.payment_plan_installments WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center');
ALTER TABLE hbh.payment_plan_installments ENABLE TRIGGER trg_ppi_frozen;

CALL hbh_test.chk('cleanup', 'and the frozen-instalments guard is back on',
  $q$ SELECT tgenabled = 'O' FROM pg_trigger
      WHERE tgrelid = 'hbh.payment_plan_installments'::regclass
      AND   tgname = 'trg_ppi_frozen' $q$);

DELETE FROM hbh.payment_plans             WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center');
DELETE FROM hbh.profile_field_rules       WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center');
DELETE FROM hbh.number_series             WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center');

CALL hbh_test.chk('cleanup', 'the branch is gone',
  $q$ WITH d AS (DELETE FROM hbh.branches
                  WHERE branch_id = (SELECT v FROM hbh_test.fx WHERE k='branch') RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the centre is gone',
  $q$ WITH d AS (DELETE FROM hbh.centers
                  WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center') RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'and nothing of this suite is left behind',
  $q$ SELECT NOT EXISTS (SELECT 1 FROM hbh.profile_field_rules
                          WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center'))
         AND NOT EXISTS (SELECT 1 FROM hbh.number_series
                          WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center'))
         AND NOT EXISTS (SELECT 1 FROM hbh.payment_plans
                          WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center'))
         AND NOT EXISTS (SELECT 1 FROM hbh.centers      WHERE code = 'P18')
         AND NOT EXISTS (SELECT 1 FROM hbh.users        WHERE username = 'p18.parent')
         AND NOT EXISTS (SELECT 1 FROM hbh.children     WHERE child_no = 'P18-CH1')
         AND NOT EXISTS (SELECT 1 FROM hbh.appointments WHERE appointment_no LIKE 'P18-A-%')
         AND NOT EXISTS (SELECT 1 FROM hbh.appointment_status_history h
                          WHERE h.appointment_id IN (SELECT v FROM hbh_test.fx
                                                      WHERE k IN ('appt_tue','appt_sun','appt_am'))) $q$);

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
  IF v_fail = 0 AND v_total > 0 THEN RAISE NOTICE '  PHASE 18 ACCEPTED';
  ELSE RAISE NOTICE '  *** PHASE 18 NOT ACCEPTED'; END IF;
  RAISE NOTICE '--------------------------------------------------';
END
$verdict$;
