-- =====================================================================
-- Hand By Hand (new) - API phase 2 fixture
--
-- A complete clinical history for one child, and a second child in
-- another family who must stay invisible.
--
-- The fixture is built through the DATABASE FUNCTIONS - book_appointment,
-- start_session, close_session, write_session_note, publish_session_note,
-- publish_report - and not by inserting the end state directly. That is
-- the whole point: a row hand-written into session_notes with
-- visibility='PARENT' would prove that the API can read such a row, and
-- nothing about whether the publishing path produces one. The suite has
-- to test the states the system actually reaches.
--
-- Two pairs exist so the visibility ladder has something to fail on:
--   * one note published to the family, one left INTERNAL
--   * one report published, one left DRAFT
-- A guardian must see exactly the first of each.
--
-- Run as hbh_owner. The owner bypasses row level security - which is why
-- the API does not connect as the owner (D-2), and why a fixture can be
-- built at all. But the FUNCTIONS still read hbh.current_user_id(), so
-- the therapist's identity is set at session level before the calls that
-- need it, and cleared afterwards.
--
-- Everything is named a2_ or A2- so the teardown can find it.
-- =====================================================================

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS a2_fx;
CREATE TEMP TABLE a2_fx (k text PRIMARY KEY, v integer);
DROP TABLE IF EXISTS a2_fxt;
CREATE TEMP TABLE a2_fxt (k text PRIMARY KEY, v timestamptz);

INSERT INTO a2_fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO a2_fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

-- Next Monday, 10:00 and 11:00 Cairo time.
--
-- date_trunc('week') lands on Monday, so +7 days is always a Monday and
-- never Friday or Saturday - Egypt's weekend, which validate_slot
-- refuses. Two slots rather than one so the from/to window has something
-- to exclude.
INSERT INTO a2_fxt (k, v) VALUES
  ('slot1_start', (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                   + interval '7 days' + interval '10 hours') AT TIME ZONE 'Africa/Cairo'),
  ('slot1_end',   (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                   + interval '7 days' + interval '10 hours 45 minutes') AT TIME ZONE 'Africa/Cairo'),
  ('slot2_start', (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                   + interval '7 days' + interval '12 hours') AT TIME ZONE 'Africa/Cairo'),
  ('slot2_end',   (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                   + interval '7 days' + interval '12 hours 45 minutes') AT TIME ZONE 'Africa/Cairo');

-- ---------------------------------------------------------------------
-- Service, room, therapist
-- ---------------------------------------------------------------------
INSERT INTO hbh.services (center_id, branch_id, code, name_ar, kind_code, color_hex)
VALUES ((SELECT v FROM a2_fx WHERE k='center'), (SELECT v FROM a2_fx WHERE k='branch'),
        'A2-SPEECH', 'تخاطب — اختبار الـ API', 'SPEECH', '#3B7A9E');
INSERT INTO a2_fx (k, v) SELECT 'svc', service_id FROM hbh.services WHERE code='A2-SPEECH';

INSERT INTO hbh.rooms (center_id, branch_id, code, name_ar)
VALUES ((SELECT v FROM a2_fx WHERE k='center'), (SELECT v FROM a2_fx WHERE k='branch'),
        'A2-R1', 'غرفة اختبار الـ API');
INSERT INTO a2_fx (k, v) SELECT 'room', room_id FROM hbh.rooms WHERE code='A2-R1';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile, status)
SELECT (SELECT v FROM a2_fx WHERE k='center'), (SELECT v FROM a2_fx WHERE k='branch'),
       u.username, u.name, u.utype, u.mobile, 'ACTIVE'
FROM (VALUES
       ('a2_therapist', 'أخصائية التخاطب', 'THERAPIST', '+201500000010'),
       ('a2_parent_a',  'والد الطفل الأول', 'GUARDIAN',  '+201500000011'),
       ('a2_parent_b',  'والد الطفل الثاني', 'GUARDIAN',  '+201500000012')
     ) AS u(username, name, utype, mobile);

INSERT INTO a2_fx (k, v) SELECT 'user_th', user_id FROM hbh.users WHERE username='a2_therapist';
INSERT INTO a2_fx (k, v) SELECT 'user_a',  user_id FROM hbh.users WHERE username='a2_parent_a';
INSERT INTO a2_fx (k, v) SELECT 'user_b',  user_id FROM hbh.users WHERE username='a2_parent_b';

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT u.user_id, r.role_id
FROM   hbh.users u
JOIN   hbh.roles r ON r.center_id = u.center_id
WHERE (u.username = 'a2_therapist' AND r.code = 'THERAPIST')
   OR (u.username IN ('a2_parent_a','a2_parent_b') AND r.code = 'GUARDIAN');

INSERT INTO hbh.therapists (center_id, branch_id, user_id, full_name_ar, title_ar)
VALUES ((SELECT v FROM a2_fx WHERE k='center'), (SELECT v FROM a2_fx WHERE k='branch'),
        (SELECT v FROM a2_fx WHERE k='user_th'), 'أخصائية التخاطب', 'أخصائي أول');
INSERT INTO a2_fx (k, v) SELECT 'th', therapist_id FROM hbh.therapists
 WHERE user_id = (SELECT v FROM a2_fx WHERE k='user_th');

INSERT INTO hbh.therapist_services (therapist_id, service_id)
VALUES ((SELECT v FROM a2_fx WHERE k='th'), (SELECT v FROM a2_fx WHERE k='svc'));

INSERT INTO hbh.therapist_working_hours (center_id, therapist_id, weekday, start_time, end_time)
SELECT (SELECT v FROM a2_fx WHERE k='center'), (SELECT v FROM a2_fx WHERE k='th'),
       d, TIME '09:00', TIME '17:00'
FROM   unnest(ARRAY[7,1,2,3,4]::smallint[]) AS d;

-- ---------------------------------------------------------------------
-- Two families
-- ---------------------------------------------------------------------
INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
VALUES ((SELECT v FROM a2_fx WHERE k='center'), (SELECT v FROM a2_fx WHERE k='branch'),
        'A2-A', 'طفل العائلة الأولى', DATE '2020-03-15', 'M'),
       ((SELECT v FROM a2_fx WHERE k='center'), (SELECT v FROM a2_fx WHERE k='branch'),
        'A2-B', 'طفل العائلة الثانية', DATE '2019-11-02', 'F');
INSERT INTO a2_fx (k, v) SELECT 'child_a', child_id FROM hbh.children WHERE child_no='A2-A';
INSERT INTO a2_fx (k, v) SELECT 'child_b', child_id FROM hbh.children WHERE child_no='A2-B';

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
SELECT u.center_id, u.branch_id, u.user_id, u.full_name_ar, u.mobile
FROM   hbh.users u WHERE u.username IN ('a2_parent_a', 'a2_parent_b');

INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
SELECT g.guardian_id, c.child_id, 'FATHER', true
FROM   hbh.users u
JOIN   hbh.guardians g ON g.user_id = u.user_id
JOIN   hbh.children c  ON c.child_no = CASE u.username WHEN 'a2_parent_a' THEN 'A2-A' ELSE 'A2-B' END
WHERE  u.username IN ('a2_parent_a', 'a2_parent_b');

-- Family A may watch the live stream, family B may not. Since migration
-- 0015 that is a recorded consent rather than a boolean - writing
-- can_view_live_flg directly raises HB081.
SELECT set_config('hbh.user_id', 'admin', false);

SELECT hbh.grant_consent(
  (SELECT g.guardian_id FROM hbh.guardians g
    JOIN hbh.users u ON u.user_id = g.user_id WHERE u.username = 'a2_parent_a'),
  'LIVE_VIEW',
  (SELECT child_id FROM hbh.children WHERE child_no = 'A2-A'));

SELECT set_config('hbh.user_id', '', false);

INSERT INTO hbh.caseload (center_id, therapist_id, child_id, service_id, is_primary_flg)
VALUES ((SELECT v FROM a2_fx WHERE k='center'), (SELECT v FROM a2_fx WHERE k='th'),
        (SELECT v FROM a2_fx WHERE k='child_a'), (SELECT v FROM a2_fx WHERE k='svc'), true);

-- ---------------------------------------------------------------------
-- Two appointments, one walked all the way to a closed session
--
-- Each status move is its own statement. A row is updated at most once
-- per statement in Postgres, so a second UPDATE inside the same one is
-- silently ignored - which is how a phase-3 test spent a cycle watching
-- an appointment refuse to leave CONFIRMED.
-- ---------------------------------------------------------------------
INSERT INTO a2_fx (k, v)
SELECT 'appt1', hbh.book_appointment(
  (SELECT v FROM a2_fx WHERE k='center'), (SELECT v FROM a2_fx WHERE k='branch'),
  (SELECT v FROM a2_fx WHERE k='child_a'), (SELECT v FROM a2_fx WHERE k='th'),
  (SELECT v FROM a2_fx WHERE k='room'),    (SELECT v FROM a2_fx WHERE k='svc'),
  (SELECT v FROM a2_fxt WHERE k='slot1_start'), (SELECT v FROM a2_fxt WHERE k='slot1_end'));

INSERT INTO a2_fx (k, v)
SELECT 'appt2', hbh.book_appointment(
  (SELECT v FROM a2_fx WHERE k='center'), (SELECT v FROM a2_fx WHERE k='branch'),
  (SELECT v FROM a2_fx WHERE k='child_a'), (SELECT v FROM a2_fx WHERE k='th'),
  (SELECT v FROM a2_fx WHERE k='room'),    (SELECT v FROM a2_fx WHERE k='svc'),
  (SELECT v FROM a2_fxt WHERE k='slot2_start'), (SELECT v FROM a2_fxt WHERE k='slot2_end'));

UPDATE hbh.appointments SET status = 'CONFIRMED'  WHERE appointment_id = (SELECT v FROM a2_fx WHERE k='appt1');
UPDATE hbh.appointments SET status = 'CHECKED_IN' WHERE appointment_id = (SELECT v FROM a2_fx WHERE k='appt1');

-- Started BY the therapist who owns the appointment, not by nobody.
--
-- Migration 0087 gave hbh.start_session the authorization it never had:
-- it now needs SESSION.START and it now asks whose appointment this is.
-- With no identity set the call fails closed with HB028 - correctly, and
-- this fixture used to depend on the absence of that check.
--
-- Setting the identity is not a workaround for the guard, it is what the
-- header of this file already promises: state built through the real
-- functions, reaching the states the system actually reaches. A session
-- that begins with no clinician is not one of them.
SELECT set_config('hbh.user_id', 'a2_therapist', false);

INSERT INTO a2_fx (k, v)
SELECT 'sess', hbh.start_session((SELECT v FROM a2_fx WHERE k='appt1'));

SELECT set_config('hbh.user_id', '', false);

-- ---------------------------------------------------------------------
-- Plan, goals, measurements
-- ---------------------------------------------------------------------
INSERT INTO hbh.treatment_plans (center_id, branch_id, child_id, service_id, therapist_id, title_ar, status)
VALUES ((SELECT v FROM a2_fx WHERE k='center'), (SELECT v FROM a2_fx WHERE k='branch'),
        (SELECT v FROM a2_fx WHERE k='child_a'), (SELECT v FROM a2_fx WHERE k='svc'),
        (SELECT v FROM a2_fx WHERE k='th'), 'خطة الربع الأول — اختبار الـ API', 'ACTIVE');
INSERT INTO a2_fx (k, v) SELECT 'plan', plan_id FROM hbh.treatment_plans
 WHERE title_ar = 'خطة الربع الأول — اختبار الـ API';

INSERT INTO hbh.plan_goals (center_id, plan_id, title_ar, baseline_pct, target_pct, sort_order)
VALUES ((SELECT v FROM a2_fx WHERE k='center'), (SELECT v FROM a2_fx WHERE k='plan'),
        'نطق صوت السين في وسط الكلمة', 30, 80, 10),
       ((SELECT v FROM a2_fx WHERE k='center'), (SELECT v FROM a2_fx WHERE k='plan'),
        'تكوين جملة من أربع كلمات', 20, 70, 20);
INSERT INTO a2_fx (k, v) SELECT 'goal1', goal_id FROM hbh.plan_goals WHERE title_ar='نطق صوت السين في وسط الكلمة';
INSERT INTO a2_fx (k, v) SELECT 'goal2', goal_id FROM hbh.plan_goals WHERE title_ar='تكوين جملة من أربع كلمات';

-- Two measurements on the first goal so "latest" has to actually choose.
-- A single measurement would let a query that picked any row at all pass.
INSERT INTO hbh.goal_measurements (center_id, goal_id, session_id, measured_on, value_pct, trials_cnt)
VALUES ((SELECT v FROM a2_fx WHERE k='center'), (SELECT v FROM a2_fx WHERE k='goal1'),
        (SELECT v FROM a2_fx WHERE k='sess'), current_date - 30, 41, 20),
       ((SELECT v FROM a2_fx WHERE k='center'), (SELECT v FROM a2_fx WHERE k='goal1'),
        (SELECT v FROM a2_fx WHERE k='sess'), current_date - 10, 62, 20);

-- ---------------------------------------------------------------------
-- The visibility ladder
--
-- From here on the therapist is the acting identity: write_session_note
-- needs can_edit_session, and publishing needs NOTE.PUBLISH, both of
-- which read hbh.current_user_id().
-- ---------------------------------------------------------------------
SELECT set_config('hbh.user_id', 'a2_therapist', false);

INSERT INTO a2_fx (k, v)
SELECT 'note_public', hbh.write_session_note((SELECT v FROM a2_fx WHERE k='sess'),
       'تحسّن ملحوظ في نطق السين. يُنصح بتكرار التمرين خمس دقائق يوميًا.');

INSERT INTO a2_fx (k, v)
SELECT 'note_internal', hbh.write_session_note((SELECT v FROM a2_fx WHERE k='sess'),
       'ملاحظة داخلية للفريق: مراجعة خطة الجلسة القادمة مع الأخصائي المشرف.');

-- Only the first is published. The second stays INTERNAL, which is the
-- state every note is born in.
SELECT hbh.publish_session_note((SELECT v FROM a2_fx WHERE k='note_public'));

SELECT hbh.close_session((SELECT v FROM a2_fx WHERE k='sess'), 'COMPLETED');

INSERT INTO hbh.progress_reports (center_id, branch_id, child_id, plan_id, report_no,
                                  title_ar, period_start, period_end, summary_ar, status)
VALUES ((SELECT v FROM a2_fx WHERE k='center'), (SELECT v FROM a2_fx WHERE k='branch'),
        (SELECT v FROM a2_fx WHERE k='child_a'), (SELECT v FROM a2_fx WHERE k='plan'),
        'A2-RPT-PUB', 'تقرير الربع الأول', current_date - 90, current_date - 1,
        'تقدّم ثابت خلال الفترة، مع استمرار العمل على تكوين الجمل.', 'DRAFT'),
       ((SELECT v FROM a2_fx WHERE k='center'), (SELECT v FROM a2_fx WHERE k='branch'),
        (SELECT v FROM a2_fx WHERE k='child_a'), (SELECT v FROM a2_fx WHERE k='plan'),
        'A2-RPT-DRAFT', 'مسودّة تقرير الربع الثاني', current_date - 30, current_date,
        'مسودّة لم تُراجَع بعد.', 'DRAFT');

INSERT INTO a2_fx (k, v) SELECT 'report_pub',   report_id FROM hbh.progress_reports WHERE report_no='A2-RPT-PUB';
INSERT INTO a2_fx (k, v) SELECT 'report_draft', report_id FROM hbh.progress_reports WHERE report_no='A2-RPT-DRAFT';

SELECT hbh.publish_report((SELECT v FROM a2_fx WHERE k='report_pub'));

-- Identity cleared. Leaving it set would make every later statement in
-- this psql session act as the therapist.
SELECT set_config('hbh.user_id', '', false);

-- ---------------------------------------------------------------------
-- The fixture asserts itself, by name, before any test runs
-- ---------------------------------------------------------------------
DO $assert$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM hbh.children WHERE child_no LIKE 'A2-%';
  IF n <> 2 THEN RAISE EXCEPTION 'fixture: expected 2 children, found %', n; END IF;

  SELECT count(*) INTO n FROM hbh.appointments a
   JOIN hbh.children c ON c.child_id = a.child_id WHERE c.child_no = 'A2-A';
  IF n <> 2 THEN RAISE EXCEPTION 'fixture: expected 2 appointments, found %', n; END IF;

  SELECT count(*) INTO n FROM hbh.therapy_sessions s
   JOIN hbh.children c ON c.child_id = s.child_id
   WHERE c.child_no = 'A2-A' AND s.status = 'COMPLETED';
  IF n <> 1 THEN RAISE EXCEPTION 'fixture: expected 1 completed session, found %', n; END IF;

  SELECT count(*) INTO n FROM hbh.plan_goals g
   JOIN hbh.treatment_plans p ON p.plan_id = g.plan_id
   JOIN hbh.children c ON c.child_id = p.child_id WHERE c.child_no = 'A2-A';
  IF n <> 2 THEN RAISE EXCEPTION 'fixture: expected 2 goals, found %', n; END IF;

  -- The ladder, asserted on both rungs. If the published note were not
  -- actually published, the visibility test below would pass for the
  -- wrong reason - it would be reading an empty list.
  SELECT count(*) INTO n FROM hbh.session_notes n2
   JOIN hbh.children c ON c.child_id = n2.child_id
   WHERE c.child_no = 'A2-A' AND n2.visibility = 'PARENT'
     AND n2.is_draft_flg = false AND n2.approved_by IS NOT NULL;
  IF n <> 1 THEN RAISE EXCEPTION 'fixture: expected 1 published note, found %', n; END IF;

  SELECT count(*) INTO n FROM hbh.session_notes n2
   JOIN hbh.children c ON c.child_id = n2.child_id
   WHERE c.child_no = 'A2-A' AND n2.visibility = 'INTERNAL';
  IF n <> 1 THEN RAISE EXCEPTION 'fixture: expected 1 internal note, found %', n; END IF;

  SELECT count(*) INTO n FROM hbh.progress_reports WHERE report_no = 'A2-RPT-PUB' AND status = 'PUBLISHED';
  IF n <> 1 THEN RAISE EXCEPTION 'fixture: the published report is not published'; END IF;

  SELECT count(*) INTO n FROM hbh.progress_reports WHERE report_no = 'A2-RPT-DRAFT' AND status = 'DRAFT';
  IF n <> 1 THEN RAISE EXCEPTION 'fixture: the draft report is not a draft'; END IF;

  SELECT count(*) INTO n FROM hbh.progress_reports
   WHERE report_no = 'A2-RPT-PUB' AND jsonb_array_length(goals_snapshot) = 2;
  IF n <> 1 THEN RAISE EXCEPTION 'fixture: the published report has no goal snapshot'; END IF;
END
$assert$;

\echo 'fixture a2: ready'
