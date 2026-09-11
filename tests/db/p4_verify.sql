-- =====================================================================
-- Hand By Hand (new) - PHASE 4 acceptance suite
--
-- Must print:  PHASE 4 ACCEPTED
--
-- The centre of gravity is one sentence: a clinical note must not reach
-- a family before the clinician decided it should. Everything else here
-- supports that, or protects a published report from changing after the
-- family has read it.
-- =====================================================================

\set ON_ERROR_STOP off
\pset pager off

-- ---------------------------------------------------------------------
-- Harness
-- ---------------------------------------------------------------------
DROP SCHEMA IF EXISTS hbh_test CASCADE;
CREATE SCHEMA hbh_test;

CREATE TABLE hbh_test.run (started timestamptz NOT NULL DEFAULT now());
INSERT INTO hbh_test.run DEFAULT VALUES;

CREATE TABLE hbh_test.results (
  seq    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  grp    text    NOT NULL,
  name   text    NOT NULL,
  ok     boolean NOT NULL,
  detail text
);

CREATE TABLE hbh_test.fx  (k text PRIMARY KEY, v integer);
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
                 WHEN v_ok IS NULL THEN 'returned NULL'
                 ELSE 'returned false' END);
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
GRANT SELECT ON hbh_test.fx, hbh_test.fxt TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh_test TO hbh_app;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA hbh_test TO hbh_app;

-- =====================================================================
-- FIXTURE
--
-- A full path: centre, service, room, therapist, two children, one
-- guardian linked to the first, caseload, a booked appointment walked
-- to CHECKED_IN, and a live session. Notes need all of it, which is why
-- the last fixture check exercises the whole chain instead of trusting
-- it.
-- =====================================================================
INSERT INTO hbh_test.fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO hbh_test.fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

INSERT INTO hbh_test.fxt (k, v) VALUES
  ('slot_start', (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '7 days' + interval '10 hours') AT TIME ZONE 'Africa/Cairo'),
  ('slot_end',   (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '7 days' + interval '10 hours 45 minutes') AT TIME ZONE 'Africa/Cairo');

INSERT INTO hbh.services (center_id, branch_id, code, name_ar, kind_code)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P4-SPEECH', 'تخاطب — اختبار ٤', 'SPEECH');
INSERT INTO hbh_test.fx (k, v) SELECT 'svc', service_id FROM hbh.services WHERE code='P4-SPEECH';

INSERT INTO hbh.rooms (center_id, branch_id, code, name_ar)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P4-R1', 'غرفة اختبار ٤');
INSERT INTO hbh_test.fx (k, v) SELECT 'room', room_id FROM hbh.rooms WHERE code='P4-R1';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
       u.username, u.name, u.utype, u.mobile
FROM (VALUES
       ('p4.therapist', 'أخصائي اختبار ٤',  'THERAPIST', '+201400000001'),
       ('p4.other',     'أخصائي آخر ٤',     'THERAPIST', '+201400000002'),
       ('p4.guardian',  'ولي أمر اختبار ٤', 'GUARDIAN',  '+201400000003')
     ) AS u(username, name, utype, mobile);

INSERT INTO hbh_test.fx (k, v) SELECT 'user_th',  user_id FROM hbh.users WHERE username='p4.therapist';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_oth', user_id FROM hbh.users WHERE username='p4.other';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_gd',  user_id FROM hbh.users WHERE username='p4.guardian';

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT f.v, r.role_id
FROM   hbh_test.fx f
JOIN   hbh.roles r ON r.center_id = (SELECT v FROM hbh_test.fx WHERE k='center')
WHERE  (f.k IN ('user_th','user_oth') AND r.code = 'THERAPIST')
   OR  (f.k = 'user_gd'               AND r.code = 'GUARDIAN');

INSERT INTO hbh.therapists (center_id, branch_id, user_id, full_name_ar)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_th'), 'أخصائي اختبار ٤');
INSERT INTO hbh_test.fx (k, v) SELECT 'th', therapist_id FROM hbh.therapists WHERE full_name_ar='أخصائي اختبار ٤';

INSERT INTO hbh.therapist_services (therapist_id, service_id)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='svc'));

INSERT INTO hbh.therapist_working_hours (center_id, therapist_id, weekday, start_time, end_time)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='th'),
       d, TIME '09:00', TIME '17:00'
FROM unnest(ARRAY[7,1,2,3,4]::smallint[]) AS d;

INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P4-A', 'طفل اختبار ٤ أ', DATE '2020-02-02', 'M'),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P4-B', 'طفل اختبار ٤ ب', DATE '2021-06-06', 'F');
INSERT INTO hbh_test.fx (k, v) SELECT 'child_a', child_id FROM hbh.children WHERE child_no='P4-A';
INSERT INTO hbh_test.fx (k, v) SELECT 'child_b', child_id FROM hbh.children WHERE child_no='P4-B';

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_gd'), 'ولي أمر اختبار ٤', '+201400000003');
INSERT INTO hbh_test.fx (k, v) SELECT 'gd', guardian_id FROM hbh.guardians WHERE mobile='+201400000003';

INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='gd'), (SELECT v FROM hbh_test.fx WHERE k='child_a'), 'FATHER', true);

INSERT INTO hbh.caseload (center_id, therapist_id, child_id, service_id, is_primary_flg)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='th'),
        (SELECT v FROM hbh_test.fx WHERE k='child_a'), (SELECT v FROM hbh_test.fx WHERE k='svc'), true);

-- appointment -> CHECKED_IN -> session, each step its own statement
INSERT INTO hbh_test.fx (k, v)
SELECT 'appt', hbh.book_appointment(
  (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
  (SELECT v FROM hbh_test.fx WHERE k='child_a'), (SELECT v FROM hbh_test.fx WHERE k='th'),
  (SELECT v FROM hbh_test.fx WHERE k='room'),    (SELECT v FROM hbh_test.fx WHERE k='svc'),
  (SELECT v FROM hbh_test.fxt WHERE k='slot_start'), (SELECT v FROM hbh_test.fxt WHERE k='slot_end'));

UPDATE hbh.appointments SET status = 'CONFIRMED'  WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt');
UPDATE hbh.appointments SET status = 'CHECKED_IN' WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt');

-- As the therapist who owns it. Migration 0087 gave hbh.start_session
-- the authorization it shipped without - SESSION.START, and whose
-- appointment this is - so a call with no identity now fails closed with
-- HB028 and this fixture would build no session at all.
SET hbh.user_id = 'p4.therapist';

INSERT INTO hbh_test.fx (k, v)
SELECT 'sess', hbh.start_session((SELECT v FROM hbh_test.fx WHERE k='appt'));

RESET hbh.user_id;

-- plan and goals
INSERT INTO hbh.treatment_plans (center_id, branch_id, child_id, service_id, therapist_id, title_ar)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='child_a'), (SELECT v FROM hbh_test.fx WHERE k='svc'),
        (SELECT v FROM hbh_test.fx WHERE k='th'), 'خطة الربع الثالث — اختبار');
INSERT INTO hbh_test.fx (k, v) SELECT 'plan', plan_id FROM hbh.treatment_plans WHERE title_ar='خطة الربع الثالث — اختبار';

INSERT INTO hbh.plan_goals (center_id, plan_id, title_ar, baseline_pct, target_pct, sort_order)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='plan'),
        'نطق صوت السين في وسط الكلمة', 30, 80, 10),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='plan'),
        'تكوين جملة من أربع كلمات', 20, 70, 20);
INSERT INTO hbh_test.fx (k, v) SELECT 'goal1', goal_id FROM hbh.plan_goals WHERE title_ar='نطق صوت السين في وسط الكلمة';
INSERT INTO hbh_test.fx (k, v) SELECT 'goal2', goal_id FROM hbh.plan_goals WHERE title_ar='تكوين جملة من أربع كلمات';

INSERT INTO hbh.goal_measurements (center_id, goal_id, session_id, measured_on, value_pct, trials_cnt)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='goal1'),
        (SELECT v FROM hbh_test.fx WHERE k='sess'), current_date - 30, 41, 20),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='goal1'),
        (SELECT v FROM hbh_test.fx WHERE k='sess'), current_date - 10, 55, 20),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='goal2'),
        (SELECT v FROM hbh_test.fx WHERE k='sess'), current_date - 10, 34, 20);

-- ---------------------------------------------------------------------
-- Fixture, asserted by name
-- ---------------------------------------------------------------------
CALL hbh_test.chk('fixture', 'migration 0006 recorded',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0006') $q$);

CALL hbh_test.chk('fixture', 'the therapist is linked to an account',
  $q$ SELECT user_id IS NOT NULL FROM hbh.therapists
      WHERE therapist_id = (SELECT v FROM hbh_test.fx WHERE k='th') $q$);

CALL hbh_test.chk('fixture', 'a live session exists',
  $q$ SELECT status = 'IN_PROGRESS' FROM hbh.therapy_sessions
      WHERE session_id = (SELECT v FROM hbh_test.fx WHERE k='sess') $q$);

CALL hbh_test.chk('fixture', 'the plan has two goals',
  $q$ SELECT count(*) = 2 FROM hbh.plan_goals
      WHERE plan_id = (SELECT v FROM hbh_test.fx WHERE k='plan') $q$);

CALL hbh_test.chk('fixture', 'the goals have three measurements between them',
  $q$ SELECT count(*) = 3 FROM hbh.goal_measurements
      WHERE goal_id IN (SELECT v FROM hbh_test.fx WHERE k IN ('goal1','goal2')) $q$);

CALL hbh_test.chk('fixture', 'the therapist role holds SESSION.NOTES.EDIT and NOTE.PUBLISH',
  $q$ SELECT count(*) = 2 FROM hbh.roles r
      JOIN hbh.role_permissions rp ON rp.role_id = r.role_id
      JOIN hbh.permissions p ON p.permission_id = rp.permission_id
      WHERE r.code = 'THERAPIST' AND p.code IN ('SESSION.NOTES.EDIT','NOTE.PUBLISH') $q$);

CALL hbh_test.chk('fixture', 'the administrator role holds NEITHER of them',
  $q$ SELECT count(*) = 0 FROM hbh.roles r
      JOIN hbh.role_permissions rp ON rp.role_id = r.role_id
      JOIN hbh.permissions p ON p.permission_id = rp.permission_id
      WHERE r.code = 'CENTER_ADMIN' AND p.code IN ('SESSION.NOTES.EDIT','NOTE.PUBLISH') $q$);

-- =====================================================================
-- 1. PLANS
-- =====================================================================
CALL hbh_test.chk('plan', 'a plan starts as DRAFT',
  $q$ SELECT status = 'DRAFT' FROM hbh.treatment_plans
      WHERE plan_id = (SELECT v FROM hbh_test.fx WHERE k='plan') $q$);

CALL hbh_test.chk_raises('plan', 'DRAFT straight to COMPLETED raises HB030',
  $q$ UPDATE hbh.treatment_plans SET status = 'COMPLETED'
      WHERE plan_id = (SELECT v FROM hbh_test.fx WHERE k='plan') $q$, 'HB030');

CALL hbh_test.chk('plan', 'DRAFT to ACTIVE is accepted',
  $q$ WITH u AS (UPDATE hbh.treatment_plans SET status = 'ACTIVE'
                 WHERE plan_id = (SELECT v FROM hbh_test.fx WHERE k='plan') RETURNING 1)
      SELECT count(*) = 1 FROM u $q$);

-- Two live plans would be two answers to "what are we working on", and
-- a report that cannot say which one it used.
CALL hbh_test.chk_raises('plan', 'a second ACTIVE plan for the same child and service is refused',
  $q$ INSERT INTO hbh.treatment_plans (center_id, branch_id, child_id, service_id, therapist_id, title_ar, status)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
              (SELECT v FROM hbh_test.fx WHERE k='child_a'), (SELECT v FROM hbh_test.fx WHERE k='svc'),
              (SELECT v FROM hbh_test.fx WHERE k='th'), 'خطة مكرّرة', 'ACTIVE') $q$, '23505');

CALL hbh_test.chk('plan', 'the same child may have an ACTIVE plan for a DIFFERENT service',
  $q$ WITH s AS (INSERT INTO hbh.services (center_id, branch_id, code, name_ar, kind_code)
                 VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
                         'P4-OT', 'علاج وظيفي — اختبار ٤', 'OT') RETURNING service_id),
           p AS (INSERT INTO hbh.treatment_plans (center_id, branch_id, child_id, service_id, therapist_id, title_ar, status)
                 SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
                        (SELECT v FROM hbh_test.fx WHERE k='child_a'), s.service_id,
                        (SELECT v FROM hbh_test.fx WHERE k='th'), 'خطة علاج وظيفي', 'ACTIVE'
                 FROM s RETURNING 1)
      SELECT count(*) = 1 FROM p $q$);

CALL hbh_test.chk('plan', 'a measurement outside 0-100 is refused',
  $q$ SELECT NOT EXISTS (SELECT 1 FROM hbh.goal_measurements WHERE value_pct > 100) $q$);

CALL hbh_test.chk_raises('plan', 'and the constraint really does refuse it',
  $q$ INSERT INTO hbh.goal_measurements (center_id, goal_id, value_pct)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'),
              (SELECT v FROM hbh_test.fx WHERE k='goal1'), 140) $q$, '23514');

-- =====================================================================
-- 2. THE AUTHORSHIP GATE
-- =====================================================================
SET hbh.user_id = 'p4.therapist';
CALL hbh_test.chk('author', 'the therapist who ran the session may write notes',
  $q$ SELECT hbh.can_edit_session((SELECT v FROM hbh_test.fx WHERE k='sess')) $q$);

SET hbh.user_id = 'p4.other';
CALL hbh_test.chk('author', 'another therapist may NOT',
  $q$ SELECT NOT hbh.can_edit_session((SELECT v FROM hbh_test.fx WHERE k='sess')) $q$);

-- ---------------------------------------------------------------------
-- TWO REFUSALS, TWO ANSWERS (migration 0030)
--
-- p4.other HOLDS Session.NOTES.EDIT - they are a therapist. Answering
-- them with the same refusal as somebody holding nothing made the
-- screen tell a clinician that their permission does not permit the
-- thing it is named after.
-- ---------------------------------------------------------------------
CALL hbh_test.chk('author', 'and the reason is NOT_YOUR_SESSION, not a missing permission',
  $q$ SELECT reason = 'NOT_YOUR_SESSION' FROM
      hbh.check_session_edit((SELECT v FROM hbh_test.fx WHERE k='sess')) $q$);

CALL hbh_test.chk('author', 'they do hold SESSION.NOTES.EDIT - that is the whole point',
  $q$ SELECT hbh.has_permission('SESSION.NOTES.EDIT') $q$);

CALL hbh_test.chk_raises('author', 'so write_session_note refuses THEM with HB035, not HB031',
  $q$ SELECT hbh.write_session_note((SELECT v FROM hbh_test.fx WHERE k='sess'),
        'ملاحظة على جلسة زميل') $q$, 'HB035');

-- The distinction above is only worth anything while write_session_note
-- is the ONLY way in. A grant added later would give the colleague a
-- second path that never consults check_session_edit at all - and after
-- 0012 opened writes elsewhere, a refusal can be "zero rows, success"
-- rather than an error. So the closed door is asserted, not assumed.
CALL hbh_test.chk('author', 'the function is the only write path - no INSERT grant on notes',
  $q$ SELECT count(*) = 0 FROM information_schema.role_table_grants
      WHERE grantee = 'hbh_app' AND table_name = 'session_notes'
        AND privilege_type IN ('INSERT','UPDATE','DELETE') $q$);

-- SET ROLE, and this is not a detail. The suite runs as hbh_owner, and
-- RLS and table grants are both bypassed for the owner - so this check
-- written without it PASSED THE INSERT and then failed two later checks
-- on the row it had left behind. A closed-door test run as the owner
-- proves the owner can walk through it.
SET ROLE hbh_app;
CALL hbh_test.chk_raises('author', 'so a colleague writing straight to the table is refused',
  $q$ INSERT INTO hbh.session_notes (center_id, session_id, child_id, author_user_id, body_ar)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'),
              (SELECT v FROM hbh_test.fx WHERE k='sess'),
              (SELECT v FROM hbh_test.fx WHERE k='child_a'),
              (SELECT v FROM hbh_test.fx WHERE k='user_oth'), 'التفاف على البوّابة') $q$,
  '42501');
RESET ROLE;

SET hbh.user_id = 'p4.therapist';
CALL hbh_test.chk('author', 'the clinician who ran it gets OK',
  $q$ SELECT ok AND reason = 'OK' FROM
      hbh.check_session_edit((SELECT v FROM hbh_test.fx WHERE k='sess')) $q$);

CALL hbh_test.chk('author', 'a session that does not exist is NO_SESSION, not a permission refusal',
  $q$ SELECT reason = 'NO_SESSION' FROM hbh.check_session_edit(-1) $q$);

-- The derivation, not a second copy of the rule.
CALL hbh_test.chk('author', 'can_edit_session agrees with check_session_edit exactly',
  $q$ SELECT hbh.can_edit_session((SELECT v FROM hbh_test.fx WHERE k='sess'))
             = (SELECT ok FROM hbh.check_session_edit((SELECT v FROM hbh_test.fx WHERE k='sess'))) $q$);

-- The distinction the Oracle system got wrong. An administrator may
-- CLOSE the session and may NOT author its notes, and the two gates
-- must disagree here.
SET hbh.user_id = 'admin';
CALL hbh_test.chk('author', 'an administrator may CLOSE the session',
  $q$ SELECT hbh.can_close_session((SELECT v FROM hbh_test.fx WHERE k='sess')) $q$);

CALL hbh_test.chk('author', 'and may NOT author its notes',
  $q$ SELECT NOT hbh.can_edit_session((SELECT v FROM hbh_test.fx WHERE k='sess')) $q$);

CALL hbh_test.chk_raises('author', 'so write_session_note refuses them with HB031',
  $q$ SELECT hbh.write_session_note((SELECT v FROM hbh_test.fx WHERE k='sess'), 'ملاحظة من الإدارة') $q$,
  'HB031');

-- The administrator lacks the permission outright, so they get the
-- permission refusal - NOT "that session is not yours", which would be
-- both wrong and an existence oracle.
CALL hbh_test.chk('author', 'and their reason is NOT_PERMITTED',
  $q$ SELECT reason = 'NOT_PERMITTED' FROM
      hbh.check_session_edit((SELECT v FROM hbh_test.fx WHERE k='sess')) $q$);

SET hbh.user_id = 'p4.guardian';
CALL hbh_test.chk('author', 'a guardian may not author notes either',
  $q$ SELECT NOT hbh.can_edit_session((SELECT v FROM hbh_test.fx WHERE k='sess')) $q$);

RESET hbh.user_id;
CALL hbh_test.chk('author', 'and with no identity, nobody may',
  $q$ SELECT NOT hbh.can_edit_session((SELECT v FROM hbh_test.fx WHERE k='sess')) $q$);

-- No identity is its own answer. It is not "not permitted" and it is
-- certainly not "not yours".
CALL hbh_test.chk('author', 'and the reason says so: NO_IDENTITY',
  $q$ SELECT reason = 'NO_IDENTITY' FROM
      hbh.check_session_edit((SELECT v FROM hbh_test.fx WHERE k='sess')) $q$);

-- =====================================================================
-- 3. EVERY NOTE IS BORN INTERNAL
--
-- The headline. The insert below ASKS for a published note, naming an
-- approver and clearing the draft flag. It must be ignored - all of it.
-- =====================================================================
SET hbh.user_id = 'p4.therapist';

CALL hbh_test.chk('ladder', 'a note is written through the API',
  $q$ WITH n AS (SELECT hbh.write_session_note(
                   (SELECT v FROM hbh_test.fx WHERE k='sess'),
                   'الطفل نطق السين في ثلاث كلمات من عشر') AS id),
           i AS (INSERT INTO hbh_test.fx (k, v) SELECT 'note1', id FROM n RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('ladder', 'and it is born INTERNAL, draft, unapproved',
  $q$ SELECT visibility = 'INTERNAL' AND is_draft_flg AND approved_by IS NULL
      FROM hbh.session_notes WHERE note_id = (SELECT v FROM hbh_test.fx WHERE k='note1') $q$);

-- A direct INSERT that asks to be published anyway.
CALL hbh_test.chk('ladder', 'a direct INSERT asking for PARENT is inserted anyway',
  $q$ WITH n AS (INSERT INTO hbh.session_notes
                   (center_id, session_id, child_id, author_user_id, body_ar,
                    visibility, is_draft_flg, approved_by, approved_at)
                 VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'),
                         (SELECT v FROM hbh_test.fx WHERE k='sess'),
                         (SELECT v FROM hbh_test.fx WHERE k='child_a'),
                         (SELECT v FROM hbh_test.fx WHERE k='user_th'),
                         'ملاحظة حاولت تنشر نفسها',
                         'PARENT', false,
                         (SELECT v FROM hbh_test.fx WHERE k='user_th'), now())
                 RETURNING note_id),
           i AS (INSERT INTO hbh_test.fx (k, v) SELECT 'note2', note_id FROM n RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('ladder', 'but the trigger forced it back to INTERNAL',
  $q$ SELECT visibility = 'INTERNAL' FROM hbh.session_notes
      WHERE note_id = (SELECT v FROM hbh_test.fx WHERE k='note2') $q$);

CALL hbh_test.chk('ladder', 'and cleared the draft flag it tried to set',
  $q$ SELECT is_draft_flg FROM hbh.session_notes
      WHERE note_id = (SELECT v FROM hbh_test.fx WHERE k='note2') $q$);

CALL hbh_test.chk('ladder', 'and erased the approver it named',
  $q$ SELECT approved_by IS NULL AND approved_at IS NULL FROM hbh.session_notes
      WHERE note_id = (SELECT v FROM hbh_test.fx WHERE k='note2') $q$);

-- Publishing is gated in the trigger, so a direct UPDATE is refused for
-- the same reason the function would refuse it.
SET hbh.user_id = 'p4.guardian';
CALL hbh_test.chk_raises('ladder', 'a user without NOTE.PUBLISH cannot publish by UPDATE - HB032',
  $q$ UPDATE hbh.session_notes
         SET visibility = 'PARENT', is_draft_flg = false,
             approved_by = (SELECT v FROM hbh_test.fx WHERE k='user_gd'), approved_at = now()
       WHERE note_id = (SELECT v FROM hbh_test.fx WHERE k='note1') $q$, 'HB032');

SET hbh.user_id = 'p4.therapist';
CALL hbh_test.chk_raises('ladder', 'even with the permission, publishing without an approver is refused',
  $q$ UPDATE hbh.session_notes SET visibility = 'PARENT', is_draft_flg = false
       WHERE note_id = (SELECT v FROM hbh_test.fx WHERE k='note1') $q$, 'HB032');

CALL hbh_test.chk_raises('ladder', 'a PARENT note that is still a draft breaks the constraint',
  $q$ UPDATE hbh.session_notes
         SET visibility = 'PARENT', is_draft_flg = true,
             approved_by = (SELECT v FROM hbh_test.fx WHERE k='user_th'), approved_at = now()
       WHERE note_id = (SELECT v FROM hbh_test.fx WHERE k='note1') $q$, '23514');

CALL hbh_test.chk('ladder', 'publishing through the API succeeds',
  $q$ WITH p AS (SELECT hbh.publish_session_note((SELECT v FROM hbh_test.fx WHERE k='note1')))
      SELECT count(*) = 1 FROM p $q$);

CALL hbh_test.chk('ladder', 'and all three facts now agree',
  $q$ SELECT visibility = 'PARENT' AND NOT is_draft_flg
             AND approved_by = (SELECT v FROM hbh_test.fx WHERE k='user_th')
             AND approved_at IS NOT NULL
      FROM hbh.session_notes WHERE note_id = (SELECT v FROM hbh_test.fx WHERE k='note1') $q$);

CALL hbh_test.chk('ladder', 'the publication was recorded in the audit log',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.audit_log
        WHERE detail LIKE 'note % published to guardian'
          AND changed_at >= (SELECT started FROM hbh_test.run)) $q$);

-- Withdrawing a note takes the signature with it. A row must never keep
-- an approval for something it no longer says.
--
-- Write and read are separate statements, and the CTE below is
-- REFERENCED by its own outer query. Both matter:
--   * a statement reads the snapshot taken when it began, so a check
--     that reads back a row it just wrote sees the old value;
--   * and a read-only CTE that nothing references is never executed at
--     all - silently. `WITH p AS (SELECT some_function()) SELECT ...`
--     that ignores p does not call the function, and the assertion then
--     fails while reporting nothing about why.
CALL hbh_test.chk('ladder', 'a published note is withdrawn',
  $q$ WITH u AS (UPDATE hbh.session_notes SET visibility = 'INTERNAL'
                  WHERE note_id = (SELECT v FROM hbh_test.fx WHERE k='note1') RETURNING 1)
      SELECT count(*) = 1 FROM u $q$);

CALL hbh_test.chk('ladder', 'and withdrawing cleared its approval stamp',
  $q$ SELECT approved_by IS NULL AND approved_at IS NULL AND is_draft_flg
      FROM hbh.session_notes WHERE note_id = (SELECT v FROM hbh_test.fx WHERE k='note1') $q$);

CALL hbh_test.chk('ladder', 'it can be published again',
  $q$ WITH p AS (SELECT hbh.publish_session_note((SELECT v FROM hbh_test.fx WHERE k='note1')))
      SELECT count(*) = 1 FROM p $q$);

CALL hbh_test.chk('ladder', 'and it is PARENT once more',
  $q$ SELECT visibility = 'PARENT' AND approved_by IS NOT NULL
      FROM hbh.session_notes WHERE note_id = (SELECT v FROM hbh_test.fx WHERE k='note1') $q$);

-- =====================================================================
-- 4. WHAT THE FAMILY ACTUALLY SEES
-- =====================================================================
SET ROLE hbh_app;

SET hbh.user_id = 'p4.guardian';
CALL hbh_test.chk('visible', 'the guardian sees exactly ONE note',
  $q$ SELECT count(*) = 1 FROM hbh.session_notes $q$);

CALL hbh_test.chk('visible', 'and it is the published one',
  $q$ SELECT (SELECT note_id FROM hbh.session_notes) = (SELECT v FROM hbh_test.fx WHERE k='note1') $q$);

CALL hbh_test.chk('visible', 'the internal note is invisible even BY ID',
  $q$ SELECT count(*) = 0 FROM hbh.session_notes
      WHERE note_id = (SELECT v FROM hbh_test.fx WHERE k='note2') $q$);

SET hbh.user_id = 'p4.therapist';
CALL hbh_test.chk('visible', 'the therapist sees both',
  $q$ SELECT count(*) = 2 FROM hbh.session_notes
      WHERE session_id = (SELECT v FROM hbh_test.fx WHERE k='sess') $q$);

RESET hbh.user_id;
CALL hbh_test.chk('visible', 'no identity sees no notes at all',
  $q$ SELECT count(*) = 0 FROM hbh.session_notes $q$);

-- =====================================================================
-- 5. THE VIEW, AND THE OPTION THAT MAKES IT SAFE
--
-- A view in Postgres runs with its OWNER's rights by default. The owner
-- here bypasses row level security on every table, so without
-- security_invoker this view would hand a guardian every child in the
-- centre - silently, and with no error anywhere.
-- =====================================================================
SET hbh.user_id = 'p4.guardian';

CALL hbh_test.chk('view', 'the guardian reads goals through the view',
  $q$ SELECT count(*) = 2 FROM hbh.v_goal_progress $q$);

CALL hbh_test.chk('view', 'and every row belongs to their own child',
  $q$ SELECT bool_and(child_id = (SELECT v FROM hbh_test.fx WHERE k='child_a'))
      FROM hbh.v_goal_progress $q$);

CALL hbh_test.chk('view', 'the latest measurement is the one shown',
  $q$ SELECT latest_pct = 55 AND measurement_cnt = 2 FROM hbh.v_goal_progress
      WHERE goal_id = (SELECT v FROM hbh_test.fx WHERE k='goal1') $q$);

RESET hbh.user_id;
CALL hbh_test.chk('view', 'with no identity the view returns nothing',
  $q$ SELECT count(*) = 0 FROM hbh.v_goal_progress $q$);

RESET ROLE;

CALL hbh_test.chk('view', 'the view really is declared security_invoker',
  $q$ SELECT EXISTS (SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'hbh' AND c.relname = 'v_goal_progress'
          AND 'security_invoker=true' = ANY (c.reloptions)) $q$);

CALL hbh_test.chk('view', 'EVERY view in the schema is declared security_invoker',
  $q$ SELECT count(*) = 0 FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'hbh' AND c.relkind = 'v'
        AND NOT ('security_invoker=true' = ANY (coalesce(c.reloptions, '{}'))) $q$);

-- =====================================================================
-- 6. A PUBLISHED REPORT IS A SNAPSHOT
-- =====================================================================
-- A data-modifying statement is only legal inside a WITH clause, never
-- inside a plain subquery. Written the other way round it is a syntax
-- error - and with ON_ERROR_STOP off the suite sails past it, leaving
-- the fixture key NULL and thirteen later checks failing for a reason
-- none of them names.
WITH r AS (
  INSERT INTO hbh.progress_reports (center_id, branch_id, child_id, plan_id, report_no,
                                    title_ar, period_start, period_end, summary_ar)
  VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
          (SELECT v FROM hbh_test.fx WHERE k='child_a'), (SELECT v FROM hbh_test.fx WHERE k='plan'),
          hbh.next_number((SELECT v FROM hbh_test.fx WHERE k='center'), 'REPORT'),
          'تقرير التقدّم — اختبار', current_date - 60, current_date, 'ملخّص')
  RETURNING report_id)
INSERT INTO hbh_test.fx (k, v) SELECT 'report', report_id FROM r;

CALL hbh_test.chk('report', 'a report starts as DRAFT with no snapshot',
  $q$ SELECT status = 'DRAFT' AND goals_snapshot IS NULL FROM hbh.progress_reports
      WHERE report_id = (SELECT v FROM hbh_test.fx WHERE k='report') $q$);

SET hbh.user_id = 'p4.guardian';
CALL hbh_test.chk_raises('report', 'a guardian cannot publish a report - HB032',
  $q$ SELECT hbh.publish_report((SELECT v FROM hbh_test.fx WHERE k='report')) $q$, 'HB032');

SET hbh.user_id = 'p4.therapist';
CALL hbh_test.chk('report', 'the therapist publishes it',
  $q$ WITH p AS (SELECT hbh.publish_report((SELECT v FROM hbh_test.fx WHERE k='report')))
      SELECT count(*) = 1 FROM p $q$);

CALL hbh_test.chk('report', 'it now carries a snapshot of both goals',
  $q$ SELECT jsonb_array_length(goals_snapshot) = 2 FROM hbh.progress_reports
      WHERE report_id = (SELECT v FROM hbh_test.fx WHERE k='report') $q$);

CALL hbh_test.chk('report', 'and the snapshot recorded the value that was current then',
  $q$ SELECT (g ->> 'latest_pct')::numeric = 55
      FROM hbh.progress_reports r,
           LATERAL jsonb_array_elements(r.goals_snapshot) g
      WHERE r.report_id = (SELECT v FROM hbh_test.fx WHERE k='report')
        AND (g ->> 'goal_id')::integer = (SELECT v FROM hbh_test.fx WHERE k='goal1') $q$);

-- The whole reason the snapshot exists.
CALL hbh_test.chk('report', 'a NEW measurement is recorded after publication',
  $q$ WITH m AS (INSERT INTO hbh.goal_measurements (center_id, goal_id, measured_on, value_pct, trials_cnt)
                 VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'),
                         (SELECT v FROM hbh_test.fx WHERE k='goal1'), current_date, 78, 20)
                 RETURNING 1)
      SELECT count(*) = 1 FROM m $q$);

CALL hbh_test.chk('report', 'the live view moves to the new value',
  $q$ SELECT latest_pct = 78 FROM hbh.v_goal_progress
      WHERE goal_id = (SELECT v FROM hbh_test.fx WHERE k='goal1') $q$);

CALL hbh_test.chk('report', 'and the published report does NOT',
  $q$ SELECT (g ->> 'latest_pct')::numeric = 55
      FROM hbh.progress_reports r,
           LATERAL jsonb_array_elements(r.goals_snapshot) g
      WHERE r.report_id = (SELECT v FROM hbh_test.fx WHERE k='report')
        AND (g ->> 'goal_id')::integer = (SELECT v FROM hbh_test.fx WHERE k='goal1') $q$);

CALL hbh_test.chk_raises('report', 'a published report cannot be edited - HB033',
  $q$ UPDATE hbh.progress_reports SET summary_ar = 'تعديل بعد النشر'
      WHERE report_id = (SELECT v FROM hbh_test.fx WHERE k='report') $q$, 'HB033');

CALL hbh_test.chk_raises('report', 'and cannot be published twice - HB033',
  $q$ SELECT hbh.publish_report((SELECT v FROM hbh_test.fx WHERE k='report')) $q$, 'HB033');

-- A guardian sees a published report and not a draft one.
SET ROLE hbh_app;
SET hbh.user_id = 'p4.guardian';
CALL hbh_test.chk('report', 'the guardian sees the published report',
  $q$ SELECT count(*) = 1 FROM hbh.progress_reports $q$);

RESET ROLE;
INSERT INTO hbh.progress_reports (center_id, branch_id, child_id, plan_id, report_no,
                                  title_ar, period_start, period_end)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='child_a'), (SELECT v FROM hbh_test.fx WHERE k='plan'),
        hbh.next_number((SELECT v FROM hbh_test.fx WHERE k='center'), 'REPORT'),
        'مسوّدة لا يراها ولي الأمر', current_date - 30, current_date);

SET ROLE hbh_app;
SET hbh.user_id = 'p4.guardian';
CALL hbh_test.chk('report', 'and still sees only ONE - the draft stays hidden',
  $q$ SELECT count(*) = 1 FROM hbh.progress_reports $q$);

SET hbh.user_id = 'p4.therapist';
CALL hbh_test.chk('report', 'the therapist sees both the draft and the published one',
  $q$ SELECT count(*) = 2 FROM hbh.progress_reports
      WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child_a') $q$);

RESET hbh.user_id;
RESET ROLE;



-- ---------------------------------------------------------------------
-- 6b. AUTHORING ONE (migration 0088)
--
-- The row above is inserted by the OWNER, which is how this suite has
-- always built it and is NOT how the application does it: hbh_app holds
-- SELECT on progress_reports and nothing else, so a report can only be
-- written through hbh.create_report. These checks exercise that path -
-- the one the console actually uses - and the rules that guard it.
-- ---------------------------------------------------------------------
SET ROLE hbh_app;

SET hbh.user_id = 'p4.guardian';
CALL hbh_test.chk_raises('author', 'a guardian cannot create a report - HB032',
  $q$ SELECT hbh.create_report((SELECT v FROM hbh_test.fx WHERE k='child_a'),
        'محاولة من ولي أمر', current_date - 30, current_date) $q$, 'HB032');

SET hbh.user_id = 'p4.therapist';
-- The CREATE runs as hbh_app, because that is the question. Recording
-- the id does not: hbh_app holds SELECT on hbh_test.fx and no more, so
-- the bookkeeping is done as the owner two statements below. Writing it
-- the other way round fails with "permission denied for table fx" and
-- reads as though create_report were the thing that was refused.
CALL hbh_test.chk('author', 'the therapist opens a draft',
  $q$ SELECT hbh.create_report((SELECT v FROM hbh_test.fx WHERE k='child_a'),
        'تقرير مكتوب من الواجهة', current_date - 30, current_date) IS NOT NULL $q$);

RESET ROLE;
INSERT INTO hbh_test.fx (k, v)
SELECT 'authored', report_id FROM hbh.progress_reports
WHERE title_ar = 'تقرير مكتوب من الواجهة'
ORDER BY report_id DESC LIMIT 1;
SET ROLE hbh_app;

CALL hbh_test.chk('author', 'it is a DRAFT, numbered, and attributed to its author',
  $q$ SELECT status = 'DRAFT' AND report_no IS NOT NULL AND created_by = 'p4.therapist'
      FROM hbh.progress_reports
      WHERE report_id = (SELECT v FROM hbh_test.fx WHERE k='authored') $q$);

-- A draft may be incomplete. That is what a draft is for.
CALL hbh_test.chk('author', 'a draft may be saved with no summary yet',
  $q$ SELECT summary_ar IS NULL FROM hbh.progress_reports
      WHERE report_id = (SELECT v FROM hbh_test.fx WHERE k='authored') $q$);

CALL hbh_test.chk_raises('author', 'a title is still required - HB029',
  $q$ SELECT hbh.create_report((SELECT v FROM hbh_test.fx WHERE k='child_a'),
        '   ', current_date - 30, current_date) $q$, 'HB029');

CALL hbh_test.chk_raises('author', 'a period that runs backwards is refused - HB029',
  $q$ SELECT hbh.create_report((SELECT v FROM hbh_test.fx WHERE k='child_a'),
        'عنوان', current_date, current_date - 30) $q$, 'HB029');

-- Publishing is the moment a family reads it, so the prose is required
-- THERE and not before.
CALL hbh_test.chk_raises('author', 'a draft with no summary cannot be published - HB029',
  $q$ SELECT hbh.publish_report((SELECT v FROM hbh_test.fx WHERE k='authored')) $q$, 'HB029');

CALL hbh_test.chk('author', 'the author fills the summary in',
  $q$ WITH u AS (SELECT hbh.update_report(
                   (SELECT v FROM hbh_test.fx WHERE k='authored'), NULL, 'ملخّص مكتوب لاحقًا'))
      SELECT count(*) = 1 FROM u $q$);

CALL hbh_test.chk('author', 'and the edit landed',
  $q$ SELECT summary_ar = 'ملخّص مكتوب لاحقًا' FROM hbh.progress_reports
      WHERE report_id = (SELECT v FROM hbh_test.fx WHERE k='authored') $q$);

SET hbh.user_id = 'p4.guardian';
CALL hbh_test.chk_raises('author', 'a guardian cannot edit a draft - HB032',
  $q$ SELECT hbh.update_report((SELECT v FROM hbh_test.fx WHERE k='authored'),
        NULL, 'تعديل من ولي أمر') $q$, 'HB032');

CALL hbh_test.chk('author', 'and a guardian cannot even see the draft',
  $q$ SELECT count(*) = 0 FROM hbh.progress_reports
      WHERE report_id = (SELECT v FROM hbh_test.fx WHERE k='authored') $q$);

SET hbh.user_id = 'p4.therapist';
CALL hbh_test.chk('author', 'the author publishes it once it has a summary',
  $q$ WITH p AS (SELECT hbh.publish_report((SELECT v FROM hbh_test.fx WHERE k='authored')))
      SELECT count(*) = 1 FROM p $q$);

CALL hbh_test.chk_raises('author', 'and it is immutable afterwards - HB033',
  $q$ SELECT hbh.update_report((SELECT v FROM hbh_test.fx WHERE k='authored'),
        NULL, 'تعديل بعد النشر') $q$, 'HB033');

SET hbh.user_id = 'p4.guardian';
CALL hbh_test.chk('author', 'the guardian sees it only now that it is published',
  $q$ SELECT count(*) = 1 FROM hbh.progress_reports
      WHERE report_id = (SELECT v FROM hbh_test.fx WHERE k='authored') $q$);

RESET ROLE;

-- =====================================================================
-- THE CASE TIMELINE (migration 0093)
--
-- This fixture is the right place for it: two children, and a guardian
-- linked to ONE of them. hbh.v_case_timeline reads nine tables guarded
-- by nine different policies, and a view runs as its owner unless told
-- otherwise - an owner who bypasses RLS on every one of them. Without
-- security_invoker it hands a guardian the case history of every child
-- in the centre, silently and with no error anywhere.
--
-- So the decisive check is not that the view returns rows. It is that
-- child_b - who this guardian has nothing to do with - is absent.
-- =====================================================================
SET ROLE hbh_app;

SET hbh.user_id = 'p4.therapist';
CALL hbh_test.chk('timeline', 'the clinician sees this child thread',
  $q$ SELECT count(*) >= 1 FROM hbh.v_case_timeline
      WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child_a') $q$);

CALL hbh_test.chk('timeline', 'and the session and appointment both appear in it',
  $q$ SELECT count(DISTINCT link_kind) >= 2 FROM hbh.v_case_timeline
      WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child_a')
        AND link_kind IN ('APPOINTMENT','SESSION') $q$);

-- No clinical text travels. A timeline says what happened and points at
-- the row; a note's body has its own gate and its own publication
-- ladder, and inlining it here would hand round a draft as a label.
CALL hbh_test.chk('timeline', 'and it carries no note body or report summary',
  $q$ SELECT count(*) = 0 FROM information_schema.columns
      WHERE table_schema = 'hbh' AND table_name = 'v_case_timeline'
        AND column_name IN ('body_ar','summary_ar','recommendation_ar','note_ar') $q$);

SET hbh.user_id = 'p4.guardian';
CALL hbh_test.chk('timeline', 'the family sees their own child thread',
  $q$ SELECT count(*) >= 1 FROM hbh.v_case_timeline
      WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child_a') $q$);

-- The one that matters.
CALL hbh_test.chk('timeline', 'and NOT the other child, who is nothing to them',
  $q$ SELECT count(*) = 0 FROM hbh.v_case_timeline
      WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child_b') $q$);

CALL hbh_test.chk('timeline', 'nor any child outside their own',
  $q$ SELECT count(*) = 0 FROM hbh.v_case_timeline t
      WHERE t.child_id NOT IN (SELECT gc.child_id FROM hbh.guardian_children gc
                               WHERE gc.guardian_id = (SELECT v FROM hbh_test.fx WHERE k='gd')) $q$);

-- Fails closed, like everything else in this schema.
RESET hbh.user_id;
CALL hbh_test.chk('timeline', 'and with no identity the timeline is empty',
  $q$ SELECT count(*) = 0 FROM hbh.v_case_timeline $q$);

RESET ROLE;

-- The setting itself, asserted by name. It is one word, it is invisible
-- when missing, and p00 checks every view for it - but this is the view
-- where its absence costs the most, so it is also checked here.
CALL hbh_test.chk('timeline', 'the view is declared security_invoker',
  $q$ SELECT c.reloptions::text LIKE '%security_invoker=true%'
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'hbh' AND c.relname = 'v_case_timeline' $q$);

-- =====================================================================
-- CLEANUP
-- =====================================================================
CALL hbh_test.chk('cleanup', 'notifications removed',
  $q$ WITH d AS (DELETE FROM hbh.notifications WHERE user_id IN
                   (SELECT user_id FROM hbh.users WHERE username LIKE 'p4.%') RETURNING 1)
      SELECT count(*) >= 0 FROM d $q$);

-- "Some, then none" rather than "exactly two". The count was two because
-- the suite made two; section 6b now authors a third through
-- create_report, and a cleanup that asserts a particular number is a
-- cleanup that fails the day the suite grows - while still having
-- deleted everything correctly. What matters is that nothing survives.
CALL hbh_test.chk('cleanup', 'reports removed',
  $q$ WITH d AS (DELETE FROM hbh.progress_reports WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) RETURNING 1)
      SELECT count(*) > 0 FROM d $q$);

CALL hbh_test.chk('cleanup', 'and no report of theirs survived',
  $q$ SELECT count(*) = 0 FROM hbh.progress_reports WHERE child_id IN
        (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) $q$);

CALL hbh_test.chk('cleanup', 'notes removed',
  $q$ WITH d AS (DELETE FROM hbh.session_notes WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) RETURNING 1)
      SELECT count(*) = 2 FROM d $q$);

CALL hbh_test.chk('cleanup', 'measurements, goals and plans removed',
  $q$ WITH m AS (DELETE FROM hbh.goal_measurements WHERE goal_id IN
                   (SELECT goal_id FROM hbh.plan_goals WHERE plan_id IN
                      (SELECT plan_id FROM hbh.treatment_plans WHERE child_id IN
                         (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')))) RETURNING 1),
           g AS (DELETE FROM hbh.plan_goals WHERE plan_id IN
                   (SELECT plan_id FROM hbh.treatment_plans WHERE child_id IN
                      (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b'))) RETURNING 1),
           p AS (DELETE FROM hbh.treatment_plans WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) RETURNING 1)
      SELECT (SELECT count(*) FROM m) = 4 AND (SELECT count(*) FROM p) = 2 $q$);

ALTER TABLE hbh.appointment_status_history DISABLE TRIGGER trg_ash_append_only;
ALTER TABLE hbh.session_status_history     DISABLE TRIGGER trg_ssh_append_only;

CALL hbh_test.chk('cleanup', 'session and appointment history removed',
  $q$ WITH sh AS (DELETE FROM hbh.session_status_history WHERE session_id IN
                    (SELECT session_id FROM hbh.therapy_sessions WHERE child_id IN
                       (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b'))) RETURNING 1),
           s AS (DELETE FROM hbh.therapy_sessions WHERE child_id IN
                    (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) RETURNING 1),
           ah AS (DELETE FROM hbh.appointment_status_history WHERE appointment_id IN
                    (SELECT appointment_id FROM hbh.appointments WHERE child_id IN
                       (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b'))) RETURNING 1),
           a AS (DELETE FROM hbh.appointments WHERE child_id IN
                    (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) RETURNING 1)
      SELECT (SELECT count(*) FROM s) = 1 AND (SELECT count(*) FROM a) = 1 $q$);

ALTER TABLE hbh.appointment_status_history ENABLE TRIGGER trg_ash_append_only;
ALTER TABLE hbh.session_status_history     ENABLE TRIGGER trg_ssh_append_only;

CALL hbh_test.chk('cleanup', 'caseload, links and children removed',
  $q$ WITH c AS (DELETE FROM hbh.caseload WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) RETURNING 1),
           g AS (DELETE FROM hbh.guardian_children WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) RETURNING 1),
           k AS (DELETE FROM hbh.children WHERE child_no LIKE 'P4-%' RETURNING 1)
      SELECT (SELECT count(*) FROM k) = 2 $q$);

CALL hbh_test.chk('cleanup', 'rota, therapists, rooms and services removed',
  $q$ WITH w AS (DELETE FROM hbh.therapist_working_hours WHERE therapist_id =
                   (SELECT v FROM hbh_test.fx WHERE k='th') RETURNING 1),
           s AS (DELETE FROM hbh.therapist_services WHERE therapist_id =
                   (SELECT v FROM hbh_test.fx WHERE k='th') RETURNING 1),
           t AS (DELETE FROM hbh.therapists WHERE therapist_id =
                   (SELECT v FROM hbh_test.fx WHERE k='th') RETURNING 1),
           r AS (DELETE FROM hbh.rooms    WHERE code LIKE 'P4-%' RETURNING 1),
           v AS (DELETE FROM hbh.services WHERE code LIKE 'P4-%' RETURNING 1)
      SELECT (SELECT count(*) FROM t) = 1 AND (SELECT count(*) FROM v) = 2 $q$);

CALL hbh_test.chk('cleanup', 'guardians, roles and users removed',
  $q$ WITH g AS (DELETE FROM hbh.guardians WHERE mobile LIKE '+2014000000%' AND user_id IN (SELECT user_id FROM hbh.users WHERE username LIKE 'p4.%') RETURNING 1),
           r AS (DELETE FROM hbh.user_roles WHERE user_id IN
                   (SELECT user_id FROM hbh.users WHERE username LIKE 'p4.%') RETURNING 1),
           u AS (DELETE FROM hbh.users WHERE username LIKE 'p4.%' RETURNING 1)
      SELECT (SELECT count(*) FROM u) = 3 $q$);

CALL hbh_test.chk('cleanup', 'both append-only triggers are enabled again',
  $q$ SELECT count(*) = 2 FROM pg_trigger
      WHERE tgname IN ('trg_ash_append_only','trg_ssh_append_only')
        AND tgenabled = 'O' $q$);

-- =====================================================================
-- VERDICT
-- =====================================================================
\echo ''
SELECT grp AS "المجموعة",
       count(*) AS "اختبارات",
       count(*) FILTER (WHERE NOT ok) AS "فشل"
FROM   hbh_test.results
GROUP  BY grp
ORDER  BY min(seq);

\echo ''
SELECT seq, grp, name, detail
FROM   hbh_test.results
WHERE  NOT ok
ORDER  BY seq;

DO $verdict$
DECLARE
  v_total integer;
  v_fail  integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE NOT ok) INTO v_total, v_fail FROM hbh_test.results;
  RAISE NOTICE '';
  RAISE NOTICE '--------------------------------------------------';
  RAISE NOTICE '  % checks, % failed', v_total, v_fail;
  IF v_fail = 0 AND v_total > 0 THEN
    RAISE NOTICE '  PHASE 4 ACCEPTED';
  ELSE
    RAISE NOTICE '  *** PHASE 4 NOT ACCEPTED';
  END IF;
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
