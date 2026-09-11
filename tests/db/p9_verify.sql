-- =====================================================================
-- Hand By Hand (new) - PHASE 9 acceptance suite
--
-- Must print:  PHASE 9 ACCEPTED
--
-- Two claims, and the first is the one that would be read out in a
-- complaint six months later:
--
--   1. permission to watch a child, and permission to use a child's
--      photograph, exist only as a RECORD - who agreed, when, and to
--      which wording. The operational flag cannot be moved by any
--      other route.
--   2. a family is told because something HAPPENED, not because a
--      handler remembered. And the text message is opt-in per guardian:
--      one parent may have agreed to be texted and the other not.
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
CREATE TABLE hbh_test.fx  (k text PRIMARY KEY, v integer);
CREATE TABLE hbh_test.fxb (k text PRIMARY KEY, v bigint);
CREATE TABLE hbh_test.fxt (k text PRIMARY KEY, v timestamptz);

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
    VALUES (p_grp, p_name, false, 'expected ' || p_sqlstate || ', statement succeeded');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, SQLSTATE = p_sqlstate,
            'expected ' || p_sqlstate || ', got ' || SQLSTATE || ' ' || SQLERRM);
  END;
END $$;

GRANT USAGE ON SCHEMA hbh_test TO hbh_app;
GRANT INSERT, SELECT ON hbh_test.results TO hbh_app;
GRANT SELECT ON hbh_test.fx, hbh_test.fxb, hbh_test.fxt TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh_test TO hbh_app;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA hbh_test TO hbh_app;

-- =====================================================================
-- FIXTURE
--
-- One child with TWO guardians. That is the minimum shape that can show
-- a per-guardian consent doing anything: with one parent there is
-- nobody to treat differently.
-- =====================================================================
INSERT INTO hbh_test.fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO hbh_test.fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

INSERT INTO hbh_test.fxt (k, v) VALUES
  ('slot_start', (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '7 days' + interval '10 hours') AT TIME ZONE 'Africa/Cairo'),
  ('slot_end',   (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '7 days' + interval '10 hours 45 minutes') AT TIME ZONE 'Africa/Cairo'),
  ('slot2_start',(date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '7 days' + interval '14 hours') AT TIME ZONE 'Africa/Cairo'),
  ('slot2_end',  (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '7 days' + interval '14 hours 45 minutes') AT TIME ZONE 'Africa/Cairo');

INSERT INTO hbh.services (center_id, branch_id, code, name_ar, kind_code)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P9-SPEECH', 'تخاطب — اختبار ٩', 'SPEECH');
INSERT INTO hbh_test.fx (k, v) SELECT 'svc', service_id FROM hbh.services WHERE code='P9-SPEECH';

INSERT INTO hbh.rooms (center_id, branch_id, code, name_ar)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P9-R1', 'غرفة اختبار ٩');
INSERT INTO hbh_test.fx (k, v) SELECT 'room', room_id FROM hbh.rooms WHERE code='P9-R1';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
       u.username, u.name, u.utype, u.mobile
FROM (VALUES
       ('p9.therapist', 'أخصائي اختبار ٩',   'THERAPIST', '+201900000001'),
       ('p9.father',    'الأب — يقبل الرسائل','GUARDIAN',  '+201900000002'),
       ('p9.mother',    'الأم — ترفض الرسائل','GUARDIAN',  '+201900000003'),
       ('p9.stranger',  'ولي أمر طفل آخر',    'GUARDIAN',  '+201900000004')
     ) AS u(username, name, utype, mobile);

INSERT INTO hbh_test.fx (k, v) SELECT 'user_th',  user_id FROM hbh.users WHERE username='p9.therapist';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_fa',  user_id FROM hbh.users WHERE username='p9.father';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_mo',  user_id FROM hbh.users WHERE username='p9.mother';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_st',  user_id FROM hbh.users WHERE username='p9.stranger';

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT f.v, r.role_id
FROM   hbh_test.fx f
JOIN   hbh.roles r ON r.center_id = (SELECT v FROM hbh_test.fx WHERE k='center')
WHERE  (f.k = 'user_th' AND r.code = 'THERAPIST')
   OR  (f.k IN ('user_fa','user_mo','user_st') AND r.code = 'GUARDIAN');

INSERT INTO hbh.therapists (center_id, branch_id, user_id, full_name_ar)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_th'), 'أخصائي اختبار ٩');
INSERT INTO hbh_test.fx (k, v) SELECT 'th', therapist_id FROM hbh.therapists WHERE full_name_ar='أخصائي اختبار ٩';

INSERT INTO hbh.therapist_services (therapist_id, service_id)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='svc'));

INSERT INTO hbh.therapist_working_hours (center_id, therapist_id, weekday, start_time, end_time)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='th'),
       d, TIME '09:00', TIME '17:00'
FROM unnest(ARRAY[7,1,2,3,4]::smallint[]) AS d;

INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P9-A', 'طفل اختبار ٩', DATE '2020-09-09', 'M'),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P9-B', 'طفل عائلة أخرى', DATE '2021-03-03', 'F');
INSERT INTO hbh_test.fx (k, v) SELECT 'child',   child_id FROM hbh.children WHERE child_no='P9-A';
INSERT INTO hbh_test.fx (k, v) SELECT 'child_b', child_id FROM hbh.children WHERE child_no='P9-B';

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_fa'), 'الأب — يقبل الرسائل', '+201900000002'),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_mo'), 'الأم — ترفض الرسائل', '+201900000003'),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_st'), 'ولي أمر طفل آخر',    '+201900000004');
INSERT INTO hbh_test.fx (k, v) SELECT 'gd_fa', guardian_id FROM hbh.guardians WHERE mobile='+201900000002';
INSERT INTO hbh_test.fx (k, v) SELECT 'gd_mo', guardian_id FROM hbh.guardians WHERE mobile='+201900000003';
INSERT INTO hbh_test.fx (k, v) SELECT 'gd_st', guardian_id FROM hbh.guardians WHERE mobile='+201900000004';

INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='gd_fa'), (SELECT v FROM hbh_test.fx WHERE k='child'),   'FATHER', true),
       ((SELECT v FROM hbh_test.fx WHERE k='gd_mo'), (SELECT v FROM hbh_test.fx WHERE k='child'),   'MOTHER', false),
       ((SELECT v FROM hbh_test.fx WHERE k='gd_st'), (SELECT v FROM hbh_test.fx WHERE k='child_b'), 'FATHER', true);

INSERT INTO hbh.caseload (center_id, therapist_id, child_id, service_id)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='th'),
        (SELECT v FROM hbh_test.fx WHERE k='child'), (SELECT v FROM hbh_test.fx WHERE k='svc'));

INSERT INTO hbh_test.fx (k, v)
SELECT 'appt', hbh.book_appointment(
  (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
  (SELECT v FROM hbh_test.fx WHERE k='child'), (SELECT v FROM hbh_test.fx WHERE k='th'),
  (SELECT v FROM hbh_test.fx WHERE k='room'), (SELECT v FROM hbh_test.fx WHERE k='svc'),
  (SELECT v FROM hbh_test.fxt WHERE k='slot_start'), (SELECT v FROM hbh_test.fxt WHERE k='slot_end'));

UPDATE hbh.appointments SET status = 'CONFIRMED'  WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt');
UPDATE hbh.appointments SET status = 'CHECKED_IN' WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt');

-- As the therapist who owns it. Migration 0087 gave hbh.start_session
-- the authorization it shipped without - SESSION.START, and whose
-- appointment this is - so a call with no identity now fails closed with
-- HB028 and this fixture would build no session at all.
SET hbh.user_id = 'p9.therapist';

INSERT INTO hbh_test.fx (k, v)
SELECT 'sess', hbh.start_session((SELECT v FROM hbh_test.fx WHERE k='appt'));

RESET hbh.user_id;

-- A second appointment, kept BOOKED, so a cancellation has something
-- to cancel without disturbing the session.
INSERT INTO hbh_test.fx (k, v)
SELECT 'appt2', hbh.book_appointment(
  (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
  (SELECT v FROM hbh_test.fx WHERE k='child'), (SELECT v FROM hbh_test.fx WHERE k='th'),
  (SELECT v FROM hbh_test.fx WHERE k='room'), (SELECT v FROM hbh_test.fx WHERE k='svc'),
  (SELECT v FROM hbh_test.fxt WHERE k='slot2_start'), (SELECT v FROM hbh_test.fxt WHERE k='slot2_end'));

INSERT INTO hbh.treatment_plans (center_id, branch_id, child_id, service_id, therapist_id, title_ar, status)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='child'), (SELECT v FROM hbh_test.fx WHERE k='svc'),
        (SELECT v FROM hbh_test.fx WHERE k='th'), 'خطة اختبار ٩', 'ACTIVE');
INSERT INTO hbh_test.fx (k, v) SELECT 'plan', plan_id FROM hbh.treatment_plans WHERE title_ar='خطة اختبار ٩';

-- ---------------------------------------------------------------------
CALL hbh_test.chk('fixture', 'migration 0015 recorded',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0015') $q$);

CALL hbh_test.chk('fixture', 'the child has two guardians',
  $q$ SELECT count(*) = 2 FROM hbh.guardian_children
      WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child') $q$);

CALL hbh_test.chk('fixture', 'neither can watch yet - no consent exists',
  $q$ SELECT count(*) = 0 FROM hbh.guardian_children
      WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child') AND can_view_live_flg $q$);

CALL hbh_test.chk('fixture', 'and no consent row exists at all',
  $q$ SELECT count(*) = 0 FROM hbh.consents WHERE guardian_id IN
      (SELECT v FROM hbh_test.fx WHERE k IN ('gd_fa','gd_mo')) $q$);

CALL hbh_test.chk('fixture', 'a live session and a booked appointment both exist',
  $q$ SELECT (SELECT status FROM hbh.therapy_sessions
              WHERE session_id = (SELECT v FROM hbh_test.fx WHERE k='sess')) = 'IN_PROGRESS'
         AND (SELECT status FROM hbh.appointments
              WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt2')) = 'BOOKED' $q$);

-- =====================================================================
-- 1. THE FLAG HAS ONE ROUTE
-- =====================================================================
CALL hbh_test.chk_raises('route', 'the flag cannot be raised by a direct UPDATE - HB081',
  $q$ UPDATE hbh.guardian_children SET can_view_live_flg = true
      WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='gd_fa')
        AND child_id = (SELECT v FROM hbh_test.fx WHERE k='child') $q$, 'HB081');

-- The INSERT case matters most: setting a family up for the first time
-- is exactly the occasion on which the record would be bypassed.
CALL hbh_test.chk_raises('route', 'nor by INSERTING a new link with it already true',
  $q$ INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, can_view_live_flg)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='gd_st'),
              (SELECT v FROM hbh_test.fx WHERE k='child'), 'GUARDIAN', true) $q$, 'HB081');

-- =====================================================================
-- 2. RECORDING A CONSENT
-- =====================================================================
SET hbh.user_id = 'p9.father';

CALL hbh_test.chk('consent', 'the father records his own LIVE_VIEW consent',
  $q$ WITH c AS (SELECT hbh.grant_consent((SELECT v FROM hbh_test.fx WHERE k='gd_fa'),
                                          'LIVE_VIEW',
                                          (SELECT v FROM hbh_test.fx WHERE k='child'),
                                          'v1', 'من البوابة') AS id),
           i AS (INSERT INTO hbh_test.fx (k, v) SELECT 'con_live', id FROM c RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('consent', 'and the flag followed the record',
  $q$ SELECT can_view_live_flg FROM hbh.guardian_children
      WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='gd_fa')
        AND child_id = (SELECT v FROM hbh_test.fx WHERE k='child') $q$);

CALL hbh_test.chk('consent', 'the record names who agreed, when, and to which wording',
  $q$ SELECT granted_flg AND granted_at IS NOT NULL
             AND recorded_by = (SELECT v FROM hbh_test.fx WHERE k='user_fa')
             AND text_version = 'v1'
      FROM hbh.consents WHERE consent_id = (SELECT v FROM hbh_test.fx WHERE k='con_live') $q$);

CALL hbh_test.chk('consent', 'and an append-only event was written',
  $q$ SELECT count(*) = 1 FROM hbh.consent_events
      WHERE consent_id = (SELECT v FROM hbh_test.fx WHERE k='con_live') AND action = 'GRANTED' $q$);

CALL hbh_test.chk_raises('consent', 'the event log cannot be rewritten',
  $q$ UPDATE hbh.consent_events SET action = 'WITHDRAWN'
      WHERE consent_id = (SELECT v FROM hbh_test.fx WHERE k='con_live') $q$, 'HB001');

CALL hbh_test.chk_raises('consent', 'nor deleted',
  $q$ DELETE FROM hbh.consent_events
      WHERE consent_id = (SELECT v FROM hbh_test.fx WHERE k='con_live') $q$, 'HB001');

-- The mother is a guardian of the SAME child and may not record for the
-- father. Being family is not being the other person.
CALL hbh_test.chk_raises('consent', 'one guardian cannot record for the other - HB082',
  $q$ SELECT hbh.grant_consent((SELECT v FROM hbh_test.fx WHERE k='gd_mo'), 'SMS_NOTIFY') $q$, 'HB082');

CALL hbh_test.chk_raises('consent', 'and a stranger cannot record for this family either',
  $q$ SELECT hbh.grant_consent((SELECT v FROM hbh_test.fx WHERE k='gd_st'), 'SMS_NOTIFY') $q$, 'HB082');

-- Scope.
CALL hbh_test.chk_raises('consent', 'LIVE_VIEW without a child is refused - HB080',
  $q$ SELECT hbh.grant_consent((SELECT v FROM hbh_test.fx WHERE k='gd_fa'), 'LIVE_VIEW') $q$, 'HB080');

CALL hbh_test.chk_raises('consent', 'SMS_NOTIFY with a child is refused - HB080',
  $q$ SELECT hbh.grant_consent((SELECT v FROM hbh_test.fx WHERE k='gd_fa'), 'SMS_NOTIFY',
                               (SELECT v FROM hbh_test.fx WHERE k='child')) $q$, 'HB080');

-- A consent about a child the guardian is not linked to would be a
-- permission granted over somebody else's family.
CALL hbh_test.chk_raises('consent', 'a consent about an unlinked child is refused - HB082',
  $q$ SELECT hbh.grant_consent((SELECT v FROM hbh_test.fx WHERE k='gd_fa'), 'PHOTO_USE',
                               (SELECT v FROM hbh_test.fx WHERE k='child_b')) $q$, 'HB082');

CALL hbh_test.chk('consent', 'the father also agrees to text messages',
  $q$ WITH c AS (SELECT hbh.grant_consent((SELECT v FROM hbh_test.fx WHERE k='gd_fa'),
                                          'SMS_NOTIFY') AS id)
      SELECT count(*) = 1 FROM c $q$);

CALL hbh_test.chk('consent', 'and to the use of activity photographs',
  $q$ WITH c AS (SELECT hbh.grant_consent((SELECT v FROM hbh_test.fx WHERE k='gd_fa'),
                                          'PHOTO_USE',
                                          (SELECT v FROM hbh_test.fx WHERE k='child')) AS id)
      SELECT count(*) = 1 FROM c $q$);

CALL hbh_test.chk('consent', 'has_consent answers for each type separately',
  $q$ SELECT hbh.has_consent((SELECT v FROM hbh_test.fx WHERE k='gd_fa'), 'SMS_NOTIFY')
         AND hbh.has_consent((SELECT v FROM hbh_test.fx WHERE k='gd_fa'), 'PHOTO_USE',
                             (SELECT v FROM hbh_test.fx WHERE k='child'))
         AND NOT hbh.has_consent((SELECT v FROM hbh_test.fx WHERE k='gd_mo'), 'SMS_NOTIFY') $q$);

-- Staff recording a signed paper form.
SET hbh.user_id = 'admin';
CALL hbh_test.chk('consent', 'an administrator with GUARDIAN.MANAGE records a paper form',
  $q$ WITH c AS (SELECT hbh.grant_consent((SELECT v FROM hbh_test.fx WHERE k='gd_mo'),
                                          'LIVE_VIEW',
                                          (SELECT v FROM hbh_test.fx WHERE k='child'),
                                          'v1', 'نموذج ورقي موقّع') AS id)
      SELECT count(*) = 1 FROM c $q$);

CALL hbh_test.chk('consent', 'and the record names the administrator, not the mother',
  $q$ SELECT recorded_by = (SELECT u.user_id FROM hbh.users u WHERE u.username = 'admin')
      FROM hbh.consents
      WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='gd_mo')
        AND consent_type = 'LIVE_VIEW' $q$);

-- =====================================================================
-- 3. WITHDRAWING ONE
-- =====================================================================
SET hbh.user_id = 'p9.father';

CALL hbh_test.chk('withdraw', 'the father withdraws his live consent',
  $q$ SELECT hbh.withdraw_consent((SELECT v FROM hbh_test.fx WHERE k='gd_fa'), 'LIVE_VIEW',
                                  (SELECT v FROM hbh_test.fx WHERE k='child'), 'تراجعت') $q$);

CALL hbh_test.chk('withdraw', 'and the flag went down with it',
  $q$ SELECT NOT can_view_live_flg FROM hbh.guardian_children
      WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='gd_fa')
        AND child_id = (SELECT v FROM hbh_test.fx WHERE k='child') $q$);

CALL hbh_test.chk('withdraw', 'the record says withdrawn, and keeps the date',
  $q$ SELECT NOT granted_flg AND withdrawn_at IS NOT NULL
      FROM hbh.consents WHERE consent_id = (SELECT v FROM hbh_test.fx WHERE k='con_live') $q$);

CALL hbh_test.chk('withdraw', 'and a second event records the withdrawal',
  $q$ SELECT count(*) = 2 FROM hbh.consent_events
      WHERE consent_id = (SELECT v FROM hbh_test.fx WHERE k='con_live') $q$);

CALL hbh_test.chk('withdraw', 'withdrawing twice reports nothing to do',
  $q$ SELECT NOT hbh.withdraw_consent((SELECT v FROM hbh_test.fx WHERE k='gd_fa'), 'LIVE_VIEW',
                                      (SELECT v FROM hbh_test.fx WHERE k='child')) $q$);

CALL hbh_test.chk('withdraw', 'and it can be granted again',
  $q$ WITH c AS (SELECT hbh.grant_consent((SELECT v FROM hbh_test.fx WHERE k='gd_fa'),
                                          'LIVE_VIEW',
                                          (SELECT v FROM hbh_test.fx WHERE k='child')) AS id)
      SELECT count(*) = 1 FROM c $q$);

CALL hbh_test.chk('withdraw', 'the history now holds three events, not one row rewritten',
  $q$ SELECT count(*) = 3 FROM hbh.consent_events
      WHERE consent_id = (SELECT v FROM hbh_test.fx WHERE k='con_live') $q$);

CALL hbh_test.chk('withdraw', 'and there is still exactly ONE current answer',
  $q$ SELECT count(*) = 1 FROM hbh.consents
      WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='gd_fa')
        AND child_id = (SELECT v FROM hbh_test.fx WHERE k='child')
        AND consent_type = 'LIVE_VIEW' $q$);

-- =====================================================================
-- 4. NOTIFICATIONS ARE GENERATED
-- =====================================================================
SET hbh.user_id = 'p9.therapist';

-- A note, published.
CALL hbh_test.chk('notify', 'the therapist writes and publishes a note',
  $q$ WITH n AS (SELECT hbh.write_session_note((SELECT v FROM hbh_test.fx WHERE k='sess'),
                                               'نطق السين في أربع كلمات') AS id),
           i AS (INSERT INTO hbh_test.fx (k, v) SELECT 'note', id FROM n RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('notify', 'publishing it notified BOTH guardians',
  $q$ WITH p AS (SELECT hbh.publish_session_note((SELECT v FROM hbh_test.fx WHERE k='note')))
      SELECT count(*) = 1 FROM p $q$);

CALL hbh_test.chk('notify', 'and there are two notification rows for it',
  $q$ SELECT count(*) = 2 FROM hbh.notifications
      WHERE kind_code = 'NOTE_PUBLISHED'
        AND link_id = (SELECT v FROM hbh_test.fx WHERE k='note') $q$);

-- The join between the two halves of this phase.
CALL hbh_test.chk('notify', 'the father is queued for a text message and the mother is NOT',
  $q$ SELECT count(*) FILTER (WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user_fa')
                                AND sms_pending_flg) = 1
         AND count(*) FILTER (WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user_mo')
                                AND sms_pending_flg) = 0
      FROM hbh.notifications
      WHERE kind_code = 'NOTE_PUBLISHED'
        AND link_id = (SELECT v FROM hbh_test.fx WHERE k='note') $q$);

CALL hbh_test.chk('notify', 'both still get the portal row - only the channel differs',
  $q$ SELECT count(DISTINCT user_id) = 2 FROM hbh.notifications
      WHERE kind_code = 'NOTE_PUBLISHED'
        AND link_id = (SELECT v FROM hbh_test.fx WHERE k='note') $q$);

-- A report, published.
INSERT INTO hbh_test.fx (k, v)
SELECT 'report', report_id FROM (
  SELECT 0 AS report_id) z WHERE false;

-- summary_ar is now filled, and that is not padding. Migration 0091
-- made publish_report refuse a report with no summary - "no summary is
-- a notification pretending to be a report" - and this fixture had been
-- publishing one, which worked only because the rule did not exist yet.
-- The rule is right; the fixture was leaning on its absence.
WITH r AS (
  INSERT INTO hbh.progress_reports (center_id, branch_id, child_id, plan_id, report_no,
                                    title_ar, period_start, period_end, summary_ar)
  SELECT c.center_id, (SELECT v FROM hbh_test.fx WHERE k='branch'),
         (SELECT v FROM hbh_test.fx WHERE k='child'),
         (SELECT v FROM hbh_test.fx WHERE k='plan'),
         hbh.next_number(c.center_id, 'REPORT'),
         'تقرير اختبار ٩', current_date - 30, current_date,
         'تقدّم ملحوظ في المفردات خلال الشهر.'
  FROM hbh.centers c WHERE c.code = 'HBH'
  RETURNING report_id)
INSERT INTO hbh_test.fx (k, v) SELECT 'report', report_id FROM r;

CALL hbh_test.chk('notify', 'publishing a report notifies the family',
  $q$ WITH p AS (SELECT hbh.publish_report((SELECT v FROM hbh_test.fx WHERE k='report')))
      SELECT count(*) = 1 FROM p $q$);

CALL hbh_test.chk('notify', 'two rows, and the title travelled with them',
  $q$ SELECT count(*) = 2 AND bool_and(body_ar = 'تقرير اختبار ٩')
      FROM hbh.notifications
      WHERE kind_code = 'REPORT_PUBLISHED'
        AND link_id = (SELECT v FROM hbh_test.fx WHERE k='report') $q$);

-- A cancelled appointment.
RESET hbh.user_id;
CALL hbh_test.chk('notify', 'cancelling an appointment notifies the family',
  $q$ WITH u AS (UPDATE hbh.appointments
                    SET status = 'CANCELLED', cancel_reason = 'الأخصائي مريض'
                  WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt2') RETURNING 1)
      SELECT count(*) = 1 FROM u $q$);

CALL hbh_test.chk('notify', 'and the reason travelled with it',
  $q$ SELECT count(*) = 2 AND bool_and(body_ar = 'الأخصائي مريض')
      FROM hbh.notifications
      WHERE kind_code = 'APPOINTMENT_CANCELLED'
        AND link_id = (SELECT v FROM hbh_test.fx WHERE k='appt2') $q$);

-- A decided request goes to the ONE guardian who asked.
SET hbh.user_id = 'p9.father';
CALL hbh_test.chk('notify', 'the father submits a callback request',
  $q$ WITH r AS (SELECT hbh.submit_request((SELECT v FROM hbh_test.fx WHERE k='child'),
                                           'CALLBACK', NULL, 'أرجو مكالمة') AS id),
           i AS (INSERT INTO hbh_test.fx (k, v) SELECT 'req', id FROM r RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

SET hbh.user_id = 'admin';
CALL hbh_test.chk('notify', 'and the decision is recorded',
  $q$ WITH d AS (SELECT hbh.decide_request((SELECT v FROM hbh_test.fx WHERE k='req'),
                                           'ACCEPTED', 'هنكلّمك غدًا'))
      SELECT count(*) = 1 FROM d $q$);

-- The mother did not ask and has no decision waiting for her.
CALL hbh_test.chk('notify', 'only the guardian who ASKED was told',
  $q$ SELECT count(*) = 1 AND bool_and(user_id = (SELECT v FROM hbh_test.fx WHERE k='user_fa'))
      FROM hbh.notifications
      WHERE kind_code = 'REQUEST_DECIDED'
        AND link_id = (SELECT v FROM hbh_test.fx WHERE k='req') $q$);

-- =====================================================================
-- 5. A NOTIFICATION IS ADDRESSED TO A PERSON
-- =====================================================================
SET ROLE hbh_app;

SET hbh.user_id = 'p9.father';
CALL hbh_test.chk('inbox', 'the father sees his own notifications',
  $q$ SELECT count(*) >= 4 FROM hbh.notifications $q$);

CALL hbh_test.chk('inbox', 'and every one of them is addressed to him',
  $q$ SELECT bool_and(user_id = (SELECT v FROM hbh_test.fx WHERE k='user_fa'))
      FROM hbh.notifications $q$);

CALL hbh_test.chk('inbox', 'he cannot fetch the mother notification BY ID',
  $q$ SELECT count(*) = 0 FROM hbh.notifications
      WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user_mo') $q$);

SET hbh.user_id = 'p9.mother';
CALL hbh_test.chk('inbox', 'the mother sees hers, and one fewer - she was not told about the request',
  $q$ SELECT count(*) >= 3 AND count(*) FILTER (WHERE kind_code = 'REQUEST_DECIDED') = 0
      FROM hbh.notifications $q$);

SET hbh.user_id = 'p9.stranger';
CALL hbh_test.chk('inbox', 'the other family sees none of it',
  $q$ SELECT count(*) = 0 FROM hbh.notifications $q$);

-- Even a member of staff who can see the child cannot read a message
-- addressed to a parent.
--
-- NARROWED, because 0089 changed the truth and this check was written
-- against the old one. Notifications used to be family-only, so
-- "the therapist has no notifications" and "the therapist cannot read
-- the family's notifications" were the same sentence. Now that staff
-- have kinds of their own - STAFF_CHILD_ASSIGNED and the rest - they
-- are two sentences, and only the second one is the guarantee. Left as
-- it was, this check would have gone red for a feature working exactly
-- as designed.
SET hbh.user_id = 'p9.therapist';
CALL hbh_test.chk('inbox', 'and neither does the therapist, who CAN see the child',
  $q$ SELECT count(*) = 0 FROM hbh.notifications
      WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child')
        AND kind_code NOT LIKE 'STAFF\_%' $q$);

-- And the other half, which the old check was accidentally also making
-- and which now has to be made on purpose: a staff notification about
-- this child IS reachable by the clinician who carries them. Without
-- this, narrowing the check above would have quietly removed the only
-- assertion that 0089's new kinds arrive at all.
CALL hbh_test.chk('inbox', 'but a STAFF notification about that child does reach them',
  $q$ SELECT count(*) >= 1 FROM hbh.notifications
      WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child')
        AND kind_code LIKE 'STAFF\_%' $q$);

RESET hbh.user_id;
CALL hbh_test.chk('inbox', 'no identity sees no notifications',
  $q$ SELECT count(*) = 0 FROM hbh.notifications $q$);

-- Marking read is scoped by the WHERE clause, not by a check a caller
-- could forget.
SET hbh.user_id = 'p9.father';
CALL hbh_test.chk('inbox', 'the father marks one of his own read',
  $q$ SELECT hbh.mark_notification_read(
        (SELECT min(notification_id) FROM hbh.notifications)) $q$);

RESET ROLE;
CALL hbh_test.chk('inbox', 'marking somebody else notification read does nothing',
  $q$ SELECT NOT hbh.mark_notification_read(
        (SELECT min(notification_id) FROM hbh.notifications
         WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user_mo'))) $q$);

CALL hbh_test.chk('inbox', 'and that mother notification is still unread',
  $q$ SELECT count(*) = 0 FROM hbh.notifications
      WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user_mo') AND read_at IS NOT NULL $q$);

RESET hbh.user_id;

-- =====================================================================
-- 6. WHO SEES A CONSENT
-- =====================================================================
SET ROLE hbh_app;

SET hbh.user_id = 'p9.father';
CALL hbh_test.chk('visible', 'the father sees his own three consents',
  $q$ SELECT count(*) = 3 FROM hbh.consents $q$);

CALL hbh_test.chk('visible', 'and not the mother consent',
  $q$ SELECT count(*) = 0 FROM hbh.consents
      WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='gd_mo') $q$);

CALL hbh_test.chk('visible', 'he sees his own consent history',
  $q$ SELECT count(*) >= 3 FROM hbh.consent_events $q$);

SET hbh.user_id = 'p9.therapist';
CALL hbh_test.chk('visible', 'staff who can see every child see the centre consents',
  $q$ SELECT count(*) >= 4 FROM hbh.consents $q$);

SET hbh.user_id = 'p9.stranger';
CALL hbh_test.chk('visible', 'and another family sees none of them',
  $q$ SELECT count(*) = 0 FROM hbh.consents WHERE guardian_id IN
      (SELECT v FROM hbh_test.fx WHERE k IN ('gd_fa','gd_mo')) $q$);

RESET hbh.user_id;
CALL hbh_test.chk('visible', 'no identity sees no consents',
  $q$ SELECT count(*) = 0 FROM hbh.consents $q$);

RESET ROLE;

-- =====================================================================
-- CLEANUP
-- =====================================================================
ALTER TABLE hbh.consent_events DISABLE TRIGGER trg_cev_append_only;
CALL hbh_test.chk('cleanup', 'notifications, consents and their events removed',
  $q$ WITH n AS (DELETE FROM hbh.notifications WHERE user_id IN
                   (SELECT user_id FROM hbh.users WHERE username LIKE 'p9.%') RETURNING 1),
           e AS (DELETE FROM hbh.consent_events WHERE guardian_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('gd_fa','gd_mo','gd_st')) RETURNING 1),
           c AS (DELETE FROM hbh.consents WHERE guardian_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('gd_fa','gd_mo','gd_st')) RETURNING 1)
      SELECT (SELECT count(*) FROM c) = 4 AND (SELECT count(*) FROM n) >= 7 $q$);
ALTER TABLE hbh.consent_events ENABLE TRIGGER trg_cev_append_only;

CALL hbh_test.chk('cleanup', 'reports, notes, plans and requests removed',
  $q$ WITH r AS (DELETE FROM hbh.progress_reports WHERE child_id =
                   (SELECT v FROM hbh_test.fx WHERE k='child') RETURNING 1),
           n AS (DELETE FROM hbh.session_notes WHERE child_id =
                   (SELECT v FROM hbh_test.fx WHERE k='child') RETURNING 1),
           q AS (DELETE FROM hbh.parent_requests WHERE child_id =
                   (SELECT v FROM hbh_test.fx WHERE k='child') RETURNING 1),
           p AS (DELETE FROM hbh.treatment_plans WHERE child_id =
                   (SELECT v FROM hbh_test.fx WHERE k='child') RETURNING 1)
      SELECT (SELECT count(*) FROM r) = 1 AND (SELECT count(*) FROM n) = 1
         AND (SELECT count(*) FROM q) = 1 AND (SELECT count(*) FROM p) = 1 $q$);

ALTER TABLE hbh.session_status_history     DISABLE TRIGGER trg_ssh_append_only;
ALTER TABLE hbh.appointment_status_history DISABLE TRIGGER trg_ash_append_only;
CALL hbh_test.chk('cleanup', 'sessions, appointments and their history removed',
  $q$ WITH sh AS (DELETE FROM hbh.session_status_history WHERE session_id =
                    (SELECT v FROM hbh_test.fx WHERE k='sess') RETURNING 1),
           s AS (DELETE FROM hbh.therapy_sessions WHERE session_id =
                    (SELECT v FROM hbh_test.fx WHERE k='sess') RETURNING 1),
           ah AS (DELETE FROM hbh.appointment_status_history WHERE appointment_id IN
                    (SELECT v FROM hbh_test.fx WHERE k IN ('appt','appt2')) RETURNING 1),
           a AS (DELETE FROM hbh.appointments WHERE appointment_id IN
                    (SELECT v FROM hbh_test.fx WHERE k IN ('appt','appt2')) RETURNING 1)
      SELECT (SELECT count(*) FROM s) = 1 AND (SELECT count(*) FROM a) = 2 $q$);
ALTER TABLE hbh.session_status_history     ENABLE TRIGGER trg_ssh_append_only;
ALTER TABLE hbh.appointment_status_history ENABLE TRIGGER trg_ash_append_only;

CALL hbh_test.chk('cleanup', 'the rest removed',
  $q$ WITH cl AS (DELETE FROM hbh.caseload WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child','child_b')) RETURNING 1),
           g AS (DELETE FROM hbh.guardian_children WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child','child_b')) RETURNING 1),
           k AS (DELETE FROM hbh.children WHERE child_no LIKE 'P9-%' RETURNING 1),
           q AS (DELETE FROM hbh.guardians WHERE mobile LIKE '+2019000000%' AND user_id IN (SELECT user_id FROM hbh.users WHERE username LIKE 'p9.%') RETURNING 1),
           w AS (DELETE FROM hbh.therapist_working_hours WHERE therapist_id =
                   (SELECT v FROM hbh_test.fx WHERE k='th') RETURNING 1),
           ts AS (DELETE FROM hbh.therapist_services WHERE therapist_id =
                   (SELECT v FROM hbh_test.fx WHERE k='th') RETURNING 1),
           t AS (DELETE FROM hbh.therapists WHERE therapist_id =
                   (SELECT v FROM hbh_test.fx WHERE k='th') RETURNING 1),
           rm AS (DELETE FROM hbh.rooms    WHERE code LIKE 'P9-%' RETURNING 1),
           sv AS (DELETE FROM hbh.services WHERE code LIKE 'P9-%' RETURNING 1),
           ur AS (DELETE FROM hbh.user_roles WHERE user_id IN
                   (SELECT user_id FROM hbh.users WHERE username LIKE 'p9.%') RETURNING 1),
           u AS (DELETE FROM hbh.users WHERE username LIKE 'p9.%' RETURNING 1)
      SELECT (SELECT count(*) FROM k) = 2 AND (SELECT count(*) FROM u) = 4 $q$);

CALL hbh_test.chk('cleanup', 'every append-only trigger is enabled again',
  $q$ SELECT count(*) = 3 FROM pg_trigger
      WHERE tgname IN ('trg_cev_append_only','trg_ssh_append_only','trg_ash_append_only')
        AND tgenabled = 'O' $q$);

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
  IF v_fail = 0 AND v_total > 0 THEN RAISE NOTICE '  PHASE 9 ACCEPTED';
  ELSE RAISE NOTICE '  *** PHASE 9 NOT ACCEPTED'; END IF;
  RAISE NOTICE '--------------------------------------------------';
END
$verdict$;

DO $exit$
BEGIN
  IF (SELECT count(*) FROM hbh_test.results WHERE NOT ok) > 0
     OR (SELECT count(*) FROM hbh_test.results) = 0 THEN
    RAISE EXCEPTION 'acceptance suite failed';
  END IF;
END
$exit$;
