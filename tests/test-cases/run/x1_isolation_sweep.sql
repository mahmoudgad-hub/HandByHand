-- =====================================================================
-- Hand By Hand (new) - INDEPENDENT isolation sweep  (test-case set X1)
--
-- Must print:  X1 ACCEPTED
--
-- This suite is NOT a phase gate. The phase suites p1..p5 each prove
-- their own tables. This one asks the three questions no single phase
-- can ask, because each of them spans every phase at once:
--
--   1. closed  - with no identity at all, does EVERY relation in the
--                schema return nothing? One forgotten policy on one
--                new table is a leak, and it will not show up in the
--                phase that owns the other twenty-eight tables.
--   2. sweep   - one guardian, one foreign child, EVERY child-scoped
--                table in a single pass, asked by primary key.
--   3. tenant  - a SECOND centre. Every existing suite runs inside
--                centre 'HBH' alone, so no test in the project has yet
--                seen a cross-centre read refused.
--
-- The `own` group is not decoration. A sweep that returns zero rows
-- because the fixture is empty proves nothing at all, so every refusal
-- below is paired with the same read succeeding for the family that
-- owns the row.
--
-- Run:  bash tests/test-cases/run/x1_run.sh
-- =====================================================================

\set ON_ERROR_STOP off
\pset pager off

-- ---------------------------------------------------------------------
-- Harness - standalone, same shape as the phase suites
-- ---------------------------------------------------------------------
DROP SCHEMA IF EXISTS x1_test CASCADE;
CREATE SCHEMA x1_test;

CREATE TABLE x1_test.run (started timestamptz NOT NULL DEFAULT now());
INSERT INTO x1_test.run DEFAULT VALUES;

CREATE TABLE x1_test.results (
  seq    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  grp    text    NOT NULL,
  name   text    NOT NULL,
  ok     boolean NOT NULL,
  detail text
);

CREATE TABLE x1_test.fx (k text PRIMARY KEY, v integer);

CREATE PROCEDURE x1_test.chk(p_grp text, p_name text, p_sql text)
LANGUAGE plpgsql AS $$
DECLARE v_ok boolean;
BEGIN
  BEGIN
    EXECUTE p_sql INTO v_ok;
    INSERT INTO x1_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, coalesce(v_ok, false),
            CASE WHEN coalesce(v_ok, false) THEN 'ok'
                 WHEN v_ok IS NULL THEN 'returned NULL'
                 ELSE 'returned false' END);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO x1_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, false, SQLSTATE || ' ' || SQLERRM);
  END;
END $$;

-- A refusal is only proof when it is the refusal that was expected.
CREATE PROCEDURE x1_test.chk_raises(p_grp text, p_name text, p_sql text, p_sqlstate text)
LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
    INSERT INTO x1_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, false, 'expected ' || p_sqlstate || ', statement succeeded');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO x1_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, SQLSTATE = p_sqlstate,
            'expected ' || p_sqlstate || ', got ' || SQLSTATE || ' ' || SQLERRM);
  END;
END $$;

GRANT USAGE ON SCHEMA x1_test TO hbh_app;
GRANT INSERT, SELECT ON x1_test.results TO hbh_app;
GRANT SELECT ON x1_test.fx TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA x1_test TO hbh_app;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA x1_test TO hbh_app;

-- =====================================================================
-- FIXTURE - built as the owner, which bypasses RLS on purpose.
--
-- Two families in centre one, one family in centre TWO. Three is the
-- minimum that can tell "you are not this child's parent" apart from
-- "you are not even in this centre".
-- =====================================================================
SELECT set_config('hbh.user_id', 'admin', false);

INSERT INTO x1_test.fx (k, v) SELECT 'c1', center_id FROM hbh.centers WHERE code = 'HBH';
INSERT INTO x1_test.fx (k, v) SELECT 'b1', branch_id  FROM hbh.branches WHERE code = 'MAIN';

-- ---- the second centre ----------------------------------------------
INSERT INTO hbh.centers (code, name_ar) VALUES ('X1C2', 'مركز الاختبار الثاني');
INSERT INTO x1_test.fx (k, v) SELECT 'c2', center_id FROM hbh.centers WHERE code = 'X1C2';

INSERT INTO hbh.branches (center_id, code, name_ar)
SELECT (SELECT v FROM x1_test.fx WHERE k='c2'), 'X1B2', 'فرع الاختبار الثاني';
INSERT INTO x1_test.fx (k, v) SELECT 'b2', branch_id FROM hbh.branches WHERE code = 'X1B2';

-- Roles are centre-scoped, so centre two needs its own GUARDIAN role
-- carrying the same permissions. Reusing centre one's role would be
-- the very defect this group is looking for.
INSERT INTO hbh.roles (center_id, code, name_ar, name_en, is_system_flg)
SELECT (SELECT v FROM x1_test.fx WHERE k='c2'), 'GUARDIAN', 'ولي أمر', 'Guardian', true;

INSERT INTO hbh.role_permissions (role_id, permission_id)
SELECT r2.role_id, rp.permission_id
FROM   hbh.roles r2
JOIN   hbh.roles r1 ON r1.code = 'GUARDIAN' AND r1.center_id = (SELECT v FROM x1_test.fx WHERE k='c1')
JOIN   hbh.role_permissions rp ON rp.role_id = r1.role_id
WHERE  r2.code = 'GUARDIAN' AND r2.center_id = (SELECT v FROM x1_test.fx WHERE k='c2');

-- ---- accounts --------------------------------------------------------
INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile)
SELECT (SELECT v FROM x1_test.fx WHERE k='c1'), (SELECT v FROM x1_test.fx WHERE k='b1'),
       v.username, v.name, v.utype, v.mobile
FROM (VALUES
       ('x1_pa', 'ولي أمر الاختبار أ', 'GUARDIAN',  '01900000001'),
       ('x1_pb', 'ولي أمر الاختبار ب', 'GUARDIAN',  '01900000002'),
       ('x1_th', 'أخصائي الاختبار',    'THERAPIST', '01900000003')
     ) AS v(username, name, utype, mobile);

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile)
SELECT (SELECT v FROM x1_test.fx WHERE k='c2'), (SELECT v FROM x1_test.fx WHERE k='b2'),
       'x1_pc', 'ولي أمر المركز الثاني', 'GUARDIAN', '01900000004';

INSERT INTO x1_test.fx (k, v) SELECT 'u_pa', user_id FROM hbh.users WHERE username='x1_pa';
INSERT INTO x1_test.fx (k, v) SELECT 'u_pb', user_id FROM hbh.users WHERE username='x1_pb';
INSERT INTO x1_test.fx (k, v) SELECT 'u_th', user_id FROM hbh.users WHERE username='x1_th';
INSERT INTO x1_test.fx (k, v) SELECT 'u_pc', user_id FROM hbh.users WHERE username='x1_pc';

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT u.user_id, r.role_id
FROM   hbh.users u
JOIN   hbh.roles r ON r.center_id = u.center_id
WHERE  (u.username IN ('x1_pa','x1_pb','x1_pc') AND r.code = 'GUARDIAN')
   OR  (u.username = 'x1_th' AND r.code = 'THERAPIST');

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
SELECT u.center_id, u.branch_id, u.user_id, u.full_name_ar, u.mobile
FROM   hbh.users u WHERE u.username IN ('x1_pa','x1_pb','x1_pc');

INSERT INTO x1_test.fx (k, v) SELECT 'g_a', guardian_id FROM hbh.guardians WHERE mobile='01900000001';
INSERT INTO x1_test.fx (k, v) SELECT 'g_b', guardian_id FROM hbh.guardians WHERE mobile='01900000002';
INSERT INTO x1_test.fx (k, v) SELECT 'g_c', guardian_id FROM hbh.guardians WHERE mobile='01900000004';

-- ---- children --------------------------------------------------------
-- child_no is literal, never next_number(): a fixture that consumed the
-- real series would move the counter and leave a hole in front of the
-- next child reception registers.
INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
SELECT (SELECT v FROM x1_test.fx WHERE k='c1'), (SELECT v FROM x1_test.fx WHERE k='b1'),
       v.no, v.nm, v.bd::date, v.gd
FROM (VALUES ('X1-A','طفل الاختبار أ','2019-03-04','M'),
             ('X1-B','طفل الاختبار ب','2018-07-12','F')) AS v(no, nm, bd, gd);

INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
SELECT (SELECT v FROM x1_test.fx WHERE k='c2'), (SELECT v FROM x1_test.fx WHERE k='b2'),
       'X1-C', 'طفل المركز الثاني', '2020-01-09'::date, 'M';

INSERT INTO x1_test.fx (k, v) SELECT 'ch_a', child_id FROM hbh.children WHERE child_no='X1-A';
INSERT INTO x1_test.fx (k, v) SELECT 'ch_b', child_id FROM hbh.children WHERE child_no='X1-B';
INSERT INTO x1_test.fx (k, v) SELECT 'ch_c', child_id FROM hbh.children WHERE child_no='X1-C';

-- Live viewing may not be switched on without a recorded LIVE_VIEW
-- consent (migration 0015, trg_live_flag_needs_consent). The link rows
-- are created with the flag DOWN, the consent is recorded through the
-- real function, and only then is the flag raised. Setting the flag in
-- the INSERT is what this fixture used to do, and the rule - which
-- arrived later and is a good one - refused the whole statement, so no
-- link row existed and the `own` control group collapsed with it.
INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg,
                                   can_view_live_flg, can_view_reports_flg)
VALUES ((SELECT v FROM x1_test.fx WHERE k='g_a'), (SELECT v FROM x1_test.fx WHERE k='ch_a'), 'FATHER', true, false, true),
       ((SELECT v FROM x1_test.fx WHERE k='g_b'), (SELECT v FROM x1_test.fx WHERE k='ch_b'), 'MOTHER', true, false, true),
       ((SELECT v FROM x1_test.fx WHERE k='g_c'), (SELECT v FROM x1_test.fx WHERE k='ch_c'), 'FATHER', true, false, true);

SELECT hbh.grant_consent((SELECT v FROM x1_test.fx WHERE k='g_a'), 'LIVE_VIEW',
                         (SELECT v FROM x1_test.fx WHERE k='ch_a'));
SELECT hbh.grant_consent((SELECT v FROM x1_test.fx WHERE k='g_c'), 'LIVE_VIEW',
                         (SELECT v FROM x1_test.fx WHERE k='ch_c'));

UPDATE hbh.guardian_children SET can_view_live_flg = true
 WHERE (guardian_id, child_id) IN (
   ((SELECT v FROM x1_test.fx WHERE k='g_a'), (SELECT v FROM x1_test.fx WHERE k='ch_a')),
   ((SELECT v FROM x1_test.fx WHERE k='g_c'), (SELECT v FROM x1_test.fx WHERE k='ch_c')));

-- ---- clinical scaffolding for centre one ----------------------------
INSERT INTO hbh.services (center_id, code, name_ar, kind_code, default_duration_min)
SELECT (SELECT v FROM x1_test.fx WHERE k='c1'), 'X1SVC', 'خدمة الاختبار', 'SPEECH', 45;
INSERT INTO x1_test.fx (k, v) SELECT 'svc', service_id FROM hbh.services WHERE code='X1SVC';

INSERT INTO hbh.rooms (center_id, branch_id, code, name_ar)
SELECT (SELECT v FROM x1_test.fx WHERE k='c1'), (SELECT v FROM x1_test.fx WHERE k='b1'), 'X1RM', 'غرفة الاختبار';
INSERT INTO x1_test.fx (k, v) SELECT 'room', room_id FROM hbh.rooms WHERE code='X1RM';

INSERT INTO hbh.therapists (center_id, branch_id, user_id, full_name_ar)
SELECT (SELECT v FROM x1_test.fx WHERE k='c1'), (SELECT v FROM x1_test.fx WHERE k='b1'),
       (SELECT v FROM x1_test.fx WHERE k='u_th'), 'أخصائي الاختبار';
INSERT INTO x1_test.fx (k, v)
SELECT 'th', therapist_id FROM hbh.therapists WHERE user_id = (SELECT v FROM x1_test.fx WHERE k='u_th');

INSERT INTO hbh.therapist_services (therapist_id, service_id)
VALUES ((SELECT v FROM x1_test.fx WHERE k='th'), (SELECT v FROM x1_test.fx WHERE k='svc'));

INSERT INTO hbh.caseload (center_id, therapist_id, child_id, service_id)
SELECT (SELECT v FROM x1_test.fx WHERE k='c1'), (SELECT v FROM x1_test.fx WHERE k='th'), c.v, (SELECT v FROM x1_test.fx WHERE k='svc')
FROM   x1_test.fx c WHERE c.k IN ('ch_a','ch_b');

-- Appointments are inserted directly rather than through book_appointment:
-- this suite is about who may READ a row, and the booking rules already
-- have a phase of their own. The times are staggered so the exclusion
-- constraints on therapist, room and child are all satisfied.
INSERT INTO hbh.appointments (center_id, appointment_no, child_id, therapist_id, room_id, service_id, starts_at, ends_at)
VALUES ((SELECT v FROM x1_test.fx WHERE k='c1'), 'X1-APT-A', (SELECT v FROM x1_test.fx WHERE k='ch_a'),
        (SELECT v FROM x1_test.fx WHERE k='th'), (SELECT v FROM x1_test.fx WHERE k='room'), (SELECT v FROM x1_test.fx WHERE k='svc'),
        date_trunc('hour', now()) + interval '30 days', date_trunc('hour', now()) + interval '30 days 45 minutes'),
       ((SELECT v FROM x1_test.fx WHERE k='c1'), 'X1-APT-B', (SELECT v FROM x1_test.fx WHERE k='ch_b'),
        (SELECT v FROM x1_test.fx WHERE k='th'), (SELECT v FROM x1_test.fx WHERE k='room'), (SELECT v FROM x1_test.fx WHERE k='svc'),
        date_trunc('hour', now()) + interval '30 days 2 hours', date_trunc('hour', now()) + interval '30 days 2 hours 45 minutes');

INSERT INTO x1_test.fx (k, v) SELECT 'apt_a', appointment_id FROM hbh.appointments WHERE appointment_no='X1-APT-A';
INSERT INTO x1_test.fx (k, v) SELECT 'apt_b', appointment_id FROM hbh.appointments WHERE appointment_no='X1-APT-B';

INSERT INTO hbh.therapy_sessions (center_id, appointment_id, child_id, therapist_id, room_id, service_id)
SELECT (SELECT v FROM x1_test.fx WHERE k='c1'), a.appointment_id, a.child_id, a.therapist_id, a.room_id, a.service_id
FROM   hbh.appointments a WHERE a.appointment_no IN ('X1-APT-A','X1-APT-B');

INSERT INTO x1_test.fx (k, v)
SELECT 'ses_a', session_id FROM hbh.therapy_sessions WHERE appointment_id = (SELECT v FROM x1_test.fx WHERE k='apt_a');
INSERT INTO x1_test.fx (k, v)
SELECT 'ses_b', session_id FROM hbh.therapy_sessions WHERE appointment_id = (SELECT v FROM x1_test.fx WHERE k='apt_b');

INSERT INTO hbh.treatment_plans (center_id, child_id, service_id, therapist_id, title_ar)
SELECT (SELECT v FROM x1_test.fx WHERE k='c1'), c.v, (SELECT v FROM x1_test.fx WHERE k='svc'),
       (SELECT v FROM x1_test.fx WHERE k='th'),
       'خطة ' || c.k
FROM   x1_test.fx c WHERE c.k IN ('ch_a','ch_b');

INSERT INTO x1_test.fx (k, v)
SELECT 'plan_a', plan_id FROM hbh.treatment_plans WHERE child_id = (SELECT v FROM x1_test.fx WHERE k='ch_a');
INSERT INTO x1_test.fx (k, v)
SELECT 'plan_b', plan_id FROM hbh.treatment_plans WHERE child_id = (SELECT v FROM x1_test.fx WHERE k='ch_b');

INSERT INTO hbh.plan_goals (center_id, plan_id, title_ar)
VALUES ((SELECT v FROM x1_test.fx WHERE k='c1'), (SELECT v FROM x1_test.fx WHERE k='plan_a'), 'هدف أ'),
       ((SELECT v FROM x1_test.fx WHERE k='c1'), (SELECT v FROM x1_test.fx WHERE k='plan_b'), 'هدف ب');

INSERT INTO x1_test.fx (k, v)
SELECT 'goal_a', goal_id FROM hbh.plan_goals WHERE plan_id = (SELECT v FROM x1_test.fx WHERE k='plan_a');
INSERT INTO x1_test.fx (k, v)
SELECT 'goal_b', goal_id FROM hbh.plan_goals WHERE plan_id = (SELECT v FROM x1_test.fx WHERE k='plan_b');

INSERT INTO hbh.goal_measurements (center_id, goal_id, value_pct)
VALUES ((SELECT v FROM x1_test.fx WHERE k='c1'), (SELECT v FROM x1_test.fx WHERE k='goal_a'), 40),
       ((SELECT v FROM x1_test.fx WHERE k='c1'), (SELECT v FROM x1_test.fx WHERE k='goal_b'), 55);

INSERT INTO x1_test.fx (k, v)
SELECT 'meas_a', measurement_id::integer FROM hbh.goal_measurements WHERE goal_id = (SELECT v FROM x1_test.fx WHERE k='goal_a');
INSERT INTO x1_test.fx (k, v)
SELECT 'meas_b', measurement_id::integer FROM hbh.goal_measurements WHERE goal_id = (SELECT v FROM x1_test.fx WHERE k='goal_b');

-- Notes: written and published through the real functions, as the
-- clinician who ran the session. A note inserted straight into the
-- table can never be PARENT-visible - the born-internal trigger sees
-- to that - so a direct insert would test nothing.
SELECT set_config('hbh.user_id', 'x1_th', false);
SELECT hbh.write_session_note((SELECT v FROM x1_test.fx WHERE k='ses_a'), 'ملاحظة داخلية للطفل أ');
SELECT hbh.write_session_note((SELECT v FROM x1_test.fx WHERE k='ses_a'), 'ملاحظة منشورة للطفل أ');
SELECT hbh.write_session_note((SELECT v FROM x1_test.fx WHERE k='ses_b'), 'ملاحظة منشورة للطفل ب');

INSERT INTO x1_test.fx (k, v)
SELECT 'note_a_int', note_id FROM hbh.session_notes WHERE body_ar = 'ملاحظة داخلية للطفل أ';
INSERT INTO x1_test.fx (k, v)
SELECT 'note_a_pub', note_id FROM hbh.session_notes WHERE body_ar = 'ملاحظة منشورة للطفل أ';
INSERT INTO x1_test.fx (k, v)
SELECT 'note_b_pub', note_id FROM hbh.session_notes WHERE body_ar = 'ملاحظة منشورة للطفل ب';

SELECT hbh.publish_session_note((SELECT v FROM x1_test.fx WHERE k='note_a_pub'));
SELECT hbh.publish_session_note((SELECT v FROM x1_test.fx WHERE k='note_b_pub'));

SELECT set_config('hbh.user_id', 'admin', false);

-- ck_reports_published: a PUBLISHED report has to carry its snapshot
-- and its signature. Weakening the constraint so a fixture can get past
-- it is how a suite starts proving something the product does not do.
INSERT INTO hbh.progress_reports (center_id, child_id, report_no, title_ar, period_start, period_end,
                                  status, goals_snapshot, published_by, published_at)
VALUES ((SELECT v FROM x1_test.fx WHERE k='c1'), (SELECT v FROM x1_test.fx WHERE k='ch_a'),
        'X1-RPT-A', 'تقرير الطفل أ', CURRENT_DATE - 30, CURRENT_DATE,
        'PUBLISHED', '[]'::jsonb, (SELECT v FROM x1_test.fx WHERE k='u_th'), now()),
       ((SELECT v FROM x1_test.fx WHERE k='c1'), (SELECT v FROM x1_test.fx WHERE k='ch_b'),
        'X1-RPT-B', 'تقرير الطفل ب', CURRENT_DATE - 30, CURRENT_DATE,
        'PUBLISHED', '[]'::jsonb, (SELECT v FROM x1_test.fx WHERE k='u_th'), now());

INSERT INTO x1_test.fx (k, v) SELECT 'rpt_a', report_id FROM hbh.progress_reports WHERE report_no='X1-RPT-A';
INSERT INTO x1_test.fx (k, v) SELECT 'rpt_b', report_id FROM hbh.progress_reports WHERE report_no='X1-RPT-B';

INSERT INTO hbh.activity_library (center_id, code, title_ar)
SELECT (SELECT v FROM x1_test.fx WHERE k='c1'), 'X1ACT', 'نشاط الاختبار';
INSERT INTO x1_test.fx (k, v) SELECT 'act', activity_id FROM hbh.activity_library WHERE code='X1ACT';

INSERT INTO hbh.child_activities (center_id, child_id, activity_id, assigned_by)
SELECT (SELECT v FROM x1_test.fx WHERE k='c1'), c.v, (SELECT v FROM x1_test.fx WHERE k='act'),
       (SELECT v FROM x1_test.fx WHERE k='u_th')
FROM   x1_test.fx c WHERE c.k IN ('ch_a','ch_b');

INSERT INTO x1_test.fx (k, v)
SELECT 'ca_a', child_activity_id FROM hbh.child_activities WHERE child_id = (SELECT v FROM x1_test.fx WHERE k='ch_a');
INSERT INTO x1_test.fx (k, v)
SELECT 'ca_b', child_activity_id FROM hbh.child_activities WHERE child_id = (SELECT v FROM x1_test.fx WHERE k='ch_b');

INSERT INTO hbh.activity_log (center_id, child_activity_id, child_id, logged_by)
VALUES ((SELECT v FROM x1_test.fx WHERE k='c1'), (SELECT v FROM x1_test.fx WHERE k='ca_a'),
        (SELECT v FROM x1_test.fx WHERE k='ch_a'), (SELECT v FROM x1_test.fx WHERE k='u_pa')),
       ((SELECT v FROM x1_test.fx WHERE k='c1'), (SELECT v FROM x1_test.fx WHERE k='ca_b'),
        (SELECT v FROM x1_test.fx WHERE k='ch_b'), (SELECT v FROM x1_test.fx WHERE k='u_pb'));

INSERT INTO x1_test.fx (k, v)
SELECT 'log_a', log_id::integer FROM hbh.activity_log WHERE child_id = (SELECT v FROM x1_test.fx WHERE k='ch_a');
INSERT INTO x1_test.fx (k, v)
SELECT 'log_b', log_id::integer FROM hbh.activity_log WHERE child_id = (SELECT v FROM x1_test.fx WHERE k='ch_b');

INSERT INTO hbh.parent_requests (center_id, request_no, child_id, guardian_id, kind_code)
VALUES ((SELECT v FROM x1_test.fx WHERE k='c1'), 'X1-REQ-A', (SELECT v FROM x1_test.fx WHERE k='ch_a'),
        (SELECT v FROM x1_test.fx WHERE k='g_a'), 'CALLBACK'),
       ((SELECT v FROM x1_test.fx WHERE k='c1'), 'X1-REQ-B', (SELECT v FROM x1_test.fx WHERE k='ch_b'),
        (SELECT v FROM x1_test.fx WHERE k='g_b'), 'CALLBACK');

INSERT INTO x1_test.fx (k, v) SELECT 'req_a', request_id FROM hbh.parent_requests WHERE request_no='X1-REQ-A';
INSERT INTO x1_test.fx (k, v) SELECT 'req_b', request_id FROM hbh.parent_requests WHERE request_no='X1-REQ-B';

-- =====================================================================
-- FIXTURE ASSERTIONS
--
-- Every precondition by name, BEFORE any test runs. A missing piece
-- found fifty checks later reads as a baffling refusal from sound code.
-- =====================================================================
CALL x1_test.chk('fixture','two centres exist',
  $q$ SELECT count(*) = 2 FROM hbh.centers WHERE code IN ('HBH','X1C2') $q$);
CALL x1_test.chk('fixture','three guardians, two centres',
  $q$ SELECT count(*) = 3 FROM hbh.guardians WHERE mobile LIKE '+2019%' $q$);
CALL x1_test.chk('fixture','three children',
  $q$ SELECT count(*) = 3 FROM hbh.children WHERE child_no LIKE 'X1-%' $q$);
CALL x1_test.chk('fixture','each guardian is linked to exactly one child',
  $q$ SELECT count(*) = 3 FROM hbh.guardian_children gc
      JOIN hbh.children c ON c.child_id = gc.child_id AND c.child_no LIKE 'X1-%' $q$);
CALL x1_test.chk('fixture','centre two has its own GUARDIAN role',
  $q$ SELECT count(*) = 1 FROM hbh.roles r
      JOIN hbh.centers c ON c.center_id = r.center_id
      WHERE c.code = 'X1C2' AND r.code = 'GUARDIAN' $q$);
CALL x1_test.chk('fixture','the centre two guardian carries PORTAL.VIEW',
  $q$ SELECT count(*) = 1 FROM hbh.user_roles ur
      JOIN hbh.roles r ON r.role_id = ur.role_id
      JOIN hbh.role_permissions rp ON rp.role_id = r.role_id
      JOIN hbh.permissions p ON p.permission_id = rp.permission_id AND p.code = 'PORTAL.VIEW'
      WHERE ur.user_id = (SELECT v FROM x1_test.fx WHERE k='u_pc') $q$);
CALL x1_test.chk('fixture','two appointments and two sessions',
  $q$ SELECT count(*) = 2 FROM hbh.therapy_sessions
      WHERE appointment_id IN (SELECT v FROM x1_test.fx WHERE k IN ('apt_a','apt_b')) $q$);
CALL x1_test.chk('fixture','one note stayed internal',
  $q$ SELECT visibility = 'INTERNAL' FROM hbh.session_notes
      WHERE note_id = (SELECT v FROM x1_test.fx WHERE k='note_a_int') $q$);
CALL x1_test.chk('fixture','two notes reached the family',
  $q$ SELECT count(*) = 2 FROM hbh.session_notes
      WHERE note_id IN (SELECT v FROM x1_test.fx WHERE k IN ('note_a_pub','note_b_pub'))
      AND visibility = 'PARENT' AND is_draft_flg = false AND approved_by IS NOT NULL $q$);
CALL x1_test.chk('fixture','every child-scoped table carries a row for both families',
  $q$ SELECT bool_and(n = 2) FROM (
        SELECT count(*) n FROM hbh.appointments      WHERE appointment_no LIKE 'X1-APT-%'
        UNION ALL SELECT count(*) FROM hbh.therapy_sessions  WHERE session_id IN (SELECT v FROM x1_test.fx WHERE k IN ('ses_a','ses_b'))
        UNION ALL SELECT count(*) FROM hbh.treatment_plans   WHERE plan_id    IN (SELECT v FROM x1_test.fx WHERE k IN ('plan_a','plan_b'))
        UNION ALL SELECT count(*) FROM hbh.plan_goals        WHERE goal_id    IN (SELECT v FROM x1_test.fx WHERE k IN ('goal_a','goal_b'))
        UNION ALL SELECT count(*) FROM hbh.goal_measurements WHERE goal_id    IN (SELECT v FROM x1_test.fx WHERE k IN ('goal_a','goal_b'))
        UNION ALL SELECT count(*) FROM hbh.progress_reports  WHERE report_no  LIKE 'X1-RPT-%'
        UNION ALL SELECT count(*) FROM hbh.child_activities  WHERE child_activity_id IN (SELECT v FROM x1_test.fx WHERE k IN ('ca_a','ca_b'))
        UNION ALL SELECT count(*) FROM hbh.activity_log      WHERE child_activity_id IN (SELECT v FROM x1_test.fx WHERE k IN ('ca_a','ca_b'))
        UNION ALL SELECT count(*) FROM hbh.parent_requests   WHERE request_no LIKE 'X1-REQ-%'
        UNION ALL SELECT count(*) FROM hbh.caseload          WHERE child_id   IN (SELECT v FROM x1_test.fx WHERE k IN ('ch_a','ch_b'))
      ) t $q$);

-- =====================================================================
-- Everything from here runs as hbh_app - the role the API connects as.
-- As the owner these tests would all pass and prove nothing, because
-- the owner bypasses row level security.
-- =====================================================================
SET ROLE hbh_app;

CALL x1_test.chk('fixture','the tests are running as hbh_app',
  $q$ SELECT current_user = 'hbh_app' $q$);
CALL x1_test.chk('fixture','hbh_app is not superuser and does not bypass RLS',
  $q$ SELECT NOT rolsuper AND NOT rolbypassrls FROM pg_roles WHERE rolname = 'hbh_app' $q$);

-- =====================================================================
-- GROUP: closed
--
-- No identity at all. Every relation in the schema, in one pass.
-- Zero rows is a pass; so is a hard permission refusal. Anything else
-- is a leak, and this is the only place in the project that asks the
-- question of EVERY table at once - which is exactly how a table added
-- next month without a policy gets caught.
-- =====================================================================
SELECT set_config('hbh.user_id', '', false);

DO $$
DECLARE r record; n bigint;
BEGIN
  FOR r IN
    SELECT c.relname, c.relkind
    FROM   pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace
    WHERE  ns.nspname = 'hbh' AND c.relkind IN ('r','v')
    ORDER  BY c.relname
  LOOP
    BEGIN
      EXECUTE format('SELECT count(*) FROM hbh.%I', r.relname) INTO n;
      INSERT INTO x1_test.results (grp, name, ok, detail)
      VALUES ('closed', 'no identity sees nothing in ' || r.relname, n = 0,
              CASE WHEN n = 0 THEN 'ok' ELSE n || ' rows visible' END);
    EXCEPTION WHEN insufficient_privilege THEN
      INSERT INTO x1_test.results (grp, name, ok, detail)
      VALUES ('closed', 'no identity sees nothing in ' || r.relname, true, 'refused outright (42501)');
    WHEN OTHERS THEN
      INSERT INTO x1_test.results (grp, name, ok, detail)
      VALUES ('closed', 'no identity sees nothing in ' || r.relname, false, SQLSTATE || ' ' || SQLERRM);
    END;
  END LOOP;
END $$;

CALL x1_test.chk('closed','with no identity there is no centre',
  $q$ SELECT hbh.current_center_id() IS NULL $q$);
CALL x1_test.chk('closed','with no identity there is no user',
  $q$ SELECT hbh.current_user_id() IS NULL $q$);
CALL x1_test.chk('closed','with no identity no permission is held',
  $q$ SELECT NOT hbh.has_permission('PORTAL.VIEW') $q$);
CALL x1_test.chk('closed','with no identity no child is reachable',
  $q$ SELECT NOT hbh.can_access_child((SELECT v FROM x1_test.fx WHERE k='ch_a')) $q$);

-- A username that was never issued must behave exactly like no identity
-- at all - not like a user with an empty centre, which is a different
-- and much more dangerous thing.
SELECT set_config('hbh.user_id', 'x1_no_such_person', false);

CALL x1_test.chk('ghost','an unknown username resolves to no centre',
  $q$ SELECT hbh.current_center_id() IS NULL $q$);
CALL x1_test.chk('ghost','an unknown username sees no children',
  $q$ SELECT count(*) = 0 FROM hbh.children $q$);
CALL x1_test.chk('ghost','an unknown username sees no appointments',
  $q$ SELECT count(*) = 0 FROM hbh.appointments $q$);
CALL x1_test.chk('ghost','an unknown username sees no notes',
  $q$ SELECT count(*) = 0 FROM hbh.session_notes $q$);
CALL x1_test.chk('ghost','an unknown username sees no public system parameters either',
  $q$ SELECT count(*) = 0 FROM hbh.sys_params $q$);
CALL x1_test.chk('ghost','an unknown username sees no public lookup values either',
  $q$ SELECT count(*) = 0 FROM hbh.lookup_values $q$);

-- =====================================================================
-- GROUP: own
--
-- The control. Guardian A reads their own child's row on every table.
-- Without this group the sweep below would pass just as well against an
-- empty database, and prove nothing whatsoever.
-- =====================================================================
SELECT set_config('hbh.user_id', 'x1_pa', false);

CALL x1_test.chk('own','guardian A resolves to centre one',
  $q$ SELECT hbh.current_center_id() = (SELECT v FROM x1_test.fx WHERE k='c1') $q$);
CALL x1_test.chk('own','guardian A sees exactly one child',
  $q$ SELECT count(*) = 1 FROM hbh.children $q$);
CALL x1_test.chk('own','and it is their own child',
  $q$ SELECT child_no = 'X1-A' FROM hbh.children $q$);
CALL x1_test.chk('own','guardian A reads their own appointment',
  $q$ SELECT count(*) = 1 FROM hbh.appointments WHERE appointment_id = (SELECT v FROM x1_test.fx WHERE k='apt_a') $q$);
CALL x1_test.chk('own','guardian A reads their own session',
  $q$ SELECT count(*) = 1 FROM hbh.therapy_sessions WHERE session_id = (SELECT v FROM x1_test.fx WHERE k='ses_a') $q$);
CALL x1_test.chk('own','guardian A reads their own caseload row',
  $q$ SELECT count(*) = 1 FROM hbh.caseload WHERE child_id = (SELECT v FROM x1_test.fx WHERE k='ch_a') $q$);
CALL x1_test.chk('own','guardian A reads their own plan',
  $q$ SELECT count(*) = 1 FROM hbh.treatment_plans WHERE plan_id = (SELECT v FROM x1_test.fx WHERE k='plan_a') $q$);
CALL x1_test.chk('own','guardian A reads their own goal',
  $q$ SELECT count(*) = 1 FROM hbh.plan_goals WHERE goal_id = (SELECT v FROM x1_test.fx WHERE k='goal_a') $q$);
CALL x1_test.chk('own','guardian A reads their own measurement',
  $q$ SELECT count(*) = 1 FROM hbh.goal_measurements WHERE goal_id = (SELECT v FROM x1_test.fx WHERE k='goal_a') $q$);
CALL x1_test.chk('own','guardian A reads their own published report',
  $q$ SELECT count(*) = 1 FROM hbh.progress_reports WHERE report_id = (SELECT v FROM x1_test.fx WHERE k='rpt_a') $q$);
CALL x1_test.chk('own','guardian A reads their own assigned activity',
  $q$ SELECT count(*) = 1 FROM hbh.child_activities WHERE child_activity_id = (SELECT v FROM x1_test.fx WHERE k='ca_a') $q$);
CALL x1_test.chk('own','guardian A reads their own activity log',
  $q$ SELECT count(*) = 1 FROM hbh.activity_log WHERE child_id = (SELECT v FROM x1_test.fx WHERE k='ch_a') $q$);
CALL x1_test.chk('own','guardian A reads their own request',
  $q$ SELECT count(*) = 1 FROM hbh.parent_requests WHERE request_id = (SELECT v FROM x1_test.fx WHERE k='req_a') $q$);
CALL x1_test.chk('own','guardian A reads their own guardian row',
  $q$ SELECT count(*) = 1 FROM hbh.guardians $q$);
CALL x1_test.chk('own','guardian A reads the published note on their child',
  $q$ SELECT count(*) = 1 FROM hbh.session_notes WHERE note_id = (SELECT v FROM x1_test.fx WHERE k='note_a_pub') $q$);

-- =====================================================================
-- GROUP: sweep
--
-- The same guardian, the other family's rows, asked for BY PRIMARY KEY.
-- Asking by key is the point: a URL is edited by changing a number, and
-- a filter that only ever ran on a list view would never notice.
-- =====================================================================
CALL x1_test.chk('sweep','child B is not reachable by identifier',
  $q$ SELECT count(*) = 0 FROM hbh.children WHERE child_id = (SELECT v FROM x1_test.fx WHERE k='ch_b') $q$);
CALL x1_test.chk('sweep','child B is not reachable by can_access_child',
  $q$ SELECT NOT hbh.can_access_child((SELECT v FROM x1_test.fx WHERE k='ch_b')) $q$);
CALL x1_test.chk('sweep','appointment B is not reachable by identifier',
  $q$ SELECT count(*) = 0 FROM hbh.appointments WHERE appointment_id = (SELECT v FROM x1_test.fx WHERE k='apt_b') $q$);
CALL x1_test.chk('sweep','session B is not reachable by identifier',
  $q$ SELECT count(*) = 0 FROM hbh.therapy_sessions WHERE session_id = (SELECT v FROM x1_test.fx WHERE k='ses_b') $q$);
CALL x1_test.chk('sweep','the status history of appointment B is not reachable',
  $q$ SELECT count(*) = 0 FROM hbh.appointment_status_history WHERE appointment_id = (SELECT v FROM x1_test.fx WHERE k='apt_b') $q$);
CALL x1_test.chk('sweep','the status history of session B is not reachable',
  $q$ SELECT count(*) = 0 FROM hbh.session_status_history WHERE session_id = (SELECT v FROM x1_test.fx WHERE k='ses_b') $q$);
CALL x1_test.chk('sweep','caseload row B is not reachable',
  $q$ SELECT count(*) = 0 FROM hbh.caseload WHERE child_id = (SELECT v FROM x1_test.fx WHERE k='ch_b') $q$);
CALL x1_test.chk('sweep','plan B is not reachable by identifier',
  $q$ SELECT count(*) = 0 FROM hbh.treatment_plans WHERE plan_id = (SELECT v FROM x1_test.fx WHERE k='plan_b') $q$);
CALL x1_test.chk('sweep','goal B is not reachable by identifier',
  $q$ SELECT count(*) = 0 FROM hbh.plan_goals WHERE goal_id = (SELECT v FROM x1_test.fx WHERE k='goal_b') $q$);
CALL x1_test.chk('sweep','measurement B is not reachable by identifier',
  $q$ SELECT count(*) = 0 FROM hbh.goal_measurements WHERE measurement_id = (SELECT v FROM x1_test.fx WHERE k='meas_b') $q$);
CALL x1_test.chk('sweep','report B is not reachable by identifier',
  $q$ SELECT count(*) = 0 FROM hbh.progress_reports WHERE report_id = (SELECT v FROM x1_test.fx WHERE k='rpt_b') $q$);
CALL x1_test.chk('sweep','note B is not reachable by identifier',
  $q$ SELECT count(*) = 0 FROM hbh.session_notes WHERE note_id = (SELECT v FROM x1_test.fx WHERE k='note_b_pub') $q$);
CALL x1_test.chk('sweep','assigned activity B is not reachable',
  $q$ SELECT count(*) = 0 FROM hbh.child_activities WHERE child_activity_id = (SELECT v FROM x1_test.fx WHERE k='ca_b') $q$);
CALL x1_test.chk('sweep','activity log B is not reachable',
  $q$ SELECT count(*) = 0 FROM hbh.activity_log WHERE log_id = (SELECT v FROM x1_test.fx WHERE k='log_b') $q$);
CALL x1_test.chk('sweep','request B is not reachable by identifier',
  $q$ SELECT count(*) = 0 FROM hbh.parent_requests WHERE request_id = (SELECT v FROM x1_test.fx WHERE k='req_b') $q$);
CALL x1_test.chk('sweep','the link row of family B is not reachable',
  $q$ SELECT count(*) = 0 FROM hbh.guardian_children WHERE child_id = (SELECT v FROM x1_test.fx WHERE k='ch_b') $q$);
CALL x1_test.chk('sweep','guardian B is not reachable',
  $q$ SELECT count(*) = 0 FROM hbh.guardians WHERE guardian_id = (SELECT v FROM x1_test.fx WHERE k='g_b') $q$);
CALL x1_test.chk('sweep','the balance view refuses child B',
  $q$ SELECT count(*) = 0 FROM hbh.v_child_balance WHERE child_id = (SELECT v FROM x1_test.fx WHERE k='ch_b') $q$);
CALL x1_test.chk('sweep','the goal progress view refuses child B',
  $q$ SELECT count(*) = 0 FROM hbh.v_goal_progress WHERE child_id = (SELECT v FROM x1_test.fx WHERE k='ch_b') $q$);
CALL x1_test.chk('sweep','the adherence view refuses child B',
  $q$ SELECT count(*) = 0 FROM hbh.v_activity_adherence WHERE child_id = (SELECT v FROM x1_test.fx WHERE k='ch_b') $q$);
CALL x1_test.chk('sweep','a join through a permitted table does not smuggle child B out',
  $q$ SELECT count(*) = 0
      FROM hbh.appointments a JOIN hbh.children c ON c.child_id = a.child_id
      WHERE c.child_no = 'X1-B' $q$);
CALL x1_test.chk('sweep','an aggregate over the whole table still counts one child only',
  $q$ SELECT count(DISTINCT child_id) = 1 FROM hbh.appointments $q$);

-- =====================================================================
-- GROUP: ladder
--
-- A note is only a family's to read once a clinician has published it,
-- and the same guardian must not see the internal one that sits beside
-- it on the very same session.
-- =====================================================================
CALL x1_test.chk('ladder','the internal note on their own session is invisible',
  $q$ SELECT count(*) = 0 FROM hbh.session_notes WHERE note_id = (SELECT v FROM x1_test.fx WHERE k='note_a_int') $q$);
CALL x1_test.chk('ladder','only the published note on that session is visible',
  $q$ SELECT count(*) = 1 FROM hbh.session_notes WHERE session_id = (SELECT v FROM x1_test.fx WHERE k='ses_a') $q$);
CALL x1_test.chk('ladder','the guardian does not hold CHILD.VIEW_ALL',
  $q$ SELECT NOT hbh.has_permission('CHILD.VIEW_ALL') $q$);
CALL x1_test.chk('ladder','the guardian does not hold SESSION.NOTES.EDIT',
  $q$ SELECT NOT hbh.has_permission('SESSION.NOTES.EDIT') $q$);
CALL x1_test.chk('ladder','the guardian does not hold NOTE.PUBLISH',
  $q$ SELECT NOT hbh.has_permission('NOTE.PUBLISH') $q$);

-- CHARACTERISATION, not approval. A note is born INTERNAL and a report
-- is hidden until PUBLISHED, but a treatment_plans row carries a status
-- of DRAFT and no policy looks at it - so a family reads a plan the
-- clinician is still writing. These two checks state today's answer out
-- loud, so that gating plans later shows up here as a change rather than
-- passing unnoticed. Which of the two is right is the team's call.
CALL x1_test.chk('ladder','a DRAFT report is hidden from the family',
  $q$ SELECT count(*) = 0 FROM hbh.progress_reports
      WHERE child_id = (SELECT v FROM x1_test.fx WHERE k='ch_a') AND status = 'DRAFT' $q$);
CALL x1_test.chk('ladder','but a DRAFT plan is NOT - today',
  $q$ SELECT count(*) = 1 FROM hbh.treatment_plans
      WHERE plan_id = (SELECT v FROM x1_test.fx WHERE k='plan_a') AND status = 'DRAFT' $q$);

-- =====================================================================
-- GROUP: tenant
--
-- A second centre. Every other suite in this project runs inside centre
-- HBH alone, so until this group nothing had ever proved that a centre
-- boundary is a boundary. The guardian_children policy in particular
-- carries no centre predicate of its own - it leans entirely on
-- can_access_child - and that is worth an actual refusal, not a reading
-- of the policy text.
-- =====================================================================
CALL x1_test.chk('tenant','centre one guardian cannot see the centre two child',
  $q$ SELECT count(*) = 0 FROM hbh.children WHERE child_id = (SELECT v FROM x1_test.fx WHERE k='ch_c') $q$);
CALL x1_test.chk('tenant','centre one guardian cannot see the centre two guardian',
  $q$ SELECT count(*) = 0 FROM hbh.guardians WHERE guardian_id = (SELECT v FROM x1_test.fx WHERE k='g_c') $q$);
CALL x1_test.chk('tenant','centre one guardian cannot see the centre two link row',
  $q$ SELECT count(*) = 0 FROM hbh.guardian_children WHERE child_id = (SELECT v FROM x1_test.fx WHERE k='ch_c') $q$);
CALL x1_test.chk('tenant','centre one guardian cannot see the other centre',
  $q$ SELECT count(*) = 0 FROM hbh.centers WHERE code = 'X1C2' $q$);
CALL x1_test.chk('tenant','centre one guardian cannot see the other centre branch',
  $q$ SELECT count(*) = 0 FROM hbh.branches WHERE code = 'X1B2' $q$);
CALL x1_test.chk('tenant','centre one guardian cannot see centre two users',
  $q$ SELECT count(*) = 0 FROM hbh.users WHERE user_id = (SELECT v FROM x1_test.fx WHERE k='u_pc') $q$);

SELECT set_config('hbh.user_id', 'x1_pc', false);

CALL x1_test.chk('tenant','the centre two guardian resolves to centre two',
  $q$ SELECT hbh.current_center_id() = (SELECT v FROM x1_test.fx WHERE k='c2') $q$);
CALL x1_test.chk('tenant','and sees exactly their own child',
  $q$ SELECT count(*) = 1 AND min(child_no) = 'X1-C' FROM hbh.children $q$);
CALL x1_test.chk('tenant','centre two guardian cannot see child A',
  $q$ SELECT count(*) = 0 FROM hbh.children WHERE child_id = (SELECT v FROM x1_test.fx WHERE k='ch_a') $q$);
CALL x1_test.chk('tenant','centre two guardian cannot see any centre one appointment',
  $q$ SELECT count(*) = 0 FROM hbh.appointments $q$);
CALL x1_test.chk('tenant','centre two guardian cannot see any centre one note',
  $q$ SELECT count(*) = 0 FROM hbh.session_notes $q$);
CALL x1_test.chk('tenant','centre two guardian cannot see centre one services',
  $q$ SELECT count(*) = 0 FROM hbh.services WHERE code = 'X1SVC' $q$);
CALL x1_test.chk('tenant','centre two guardian cannot see centre one rooms',
  $q$ SELECT count(*) = 0 FROM hbh.rooms WHERE code = 'X1RM' $q$);
CALL x1_test.chk('tenant','centre two guardian cannot see centre one therapists',
  $q$ SELECT count(*) = 0 FROM hbh.therapists $q$);
CALL x1_test.chk('tenant','centre two guardian cannot see centre one activity library',
  $q$ SELECT count(*) = 0 FROM hbh.activity_library WHERE code = 'X1ACT' $q$);
CALL x1_test.chk('tenant','a centre-scoped parameter does not cross the boundary',
  $q$ SELECT count(*) = 0 FROM hbh.sys_params WHERE center_id = (SELECT v FROM x1_test.fx WHERE k='c1') $q$);
CALL x1_test.chk('tenant','but the public parameters are still readable',
  $q$ SELECT count(*) > 0 FROM hbh.sys_params WHERE center_id IS NULL $q$);

-- =====================================================================
-- GROUP: write
--
-- Reading is governed by policies; writing has to be refused too. The
-- portal is a read surface with two exceptions - a request and an
-- activity log - and nothing else a family sends may land.
-- =====================================================================
SELECT set_config('hbh.user_id', 'x1_pa', false);

CALL x1_test.chk_raises('write','a guardian cannot insert a treatment plan',
  $q$ INSERT INTO hbh.treatment_plans (center_id, child_id, service_id, therapist_id, title_ar)
      VALUES ((SELECT v FROM x1_test.fx WHERE k='c1'), (SELECT v FROM x1_test.fx WHERE k='ch_a'),
              (SELECT v FROM x1_test.fx WHERE k='svc'), (SELECT v FROM x1_test.fx WHERE k='th'), 'خطة مزوّرة') $q$,
  '42501');
CALL x1_test.chk_raises('write','a guardian cannot insert a session note',
  $q$ INSERT INTO hbh.session_notes (center_id, session_id, child_id, author_user_id, body_ar)
      VALUES ((SELECT v FROM x1_test.fx WHERE k='c1'), (SELECT v FROM x1_test.fx WHERE k='ses_a'),
              (SELECT v FROM x1_test.fx WHERE k='ch_a'), (SELECT v FROM x1_test.fx WHERE k='u_pa'), 'ملاحظة مزوّرة') $q$,
  '42501');
CALL x1_test.chk_raises('write','a guardian cannot record a goal measurement',
  $q$ INSERT INTO hbh.goal_measurements (center_id, goal_id, value_pct)
      VALUES ((SELECT v FROM x1_test.fx WHERE k='c1'), (SELECT v FROM x1_test.fx WHERE k='goal_a'), 99) $q$,
  '42501');
CALL x1_test.chk_raises('write','a guardian cannot publish a note by direct update',
  $q$ UPDATE hbh.session_notes SET visibility = 'PARENT'
      WHERE note_id = (SELECT v FROM x1_test.fx WHERE k='note_a_int') $q$,
  '42501');
CALL x1_test.chk_raises('write','a guardian cannot delete their own child row',
  $q$ DELETE FROM hbh.children WHERE child_id = (SELECT v FROM x1_test.fx WHERE k='ch_a') $q$,
  '42501');
-- Counted, not caught. hbh_app now HOLDS update on appointments - staff
-- booking needs it - so the policy is what refuses a guardian, and a
-- refusal by policy matches ZERO ROWS and reports success. Waiting for
-- 42501 here passed only while the grant was missing, and would go green
-- again the day somebody widens the policy to let everyone through.
CALL x1_test.chk('write','a guardian moving an appointment changes nothing',
  $q$ WITH moved AS (
        UPDATE hbh.appointments SET starts_at = starts_at + interval '1 day'
        WHERE appointment_id = (SELECT v FROM x1_test.fx WHERE k='apt_a')
        RETURNING 1)
      SELECT count(*) = 0 FROM moved $q$);
CALL x1_test.chk_raises('write','a guardian cannot write into the audit trail',
  $q$ INSERT INTO hbh.audit_log (center_id, table_name, row_pk, action, changed_by)
      VALUES ((SELECT v FROM x1_test.fx WHERE k='c1'), 'children', '1', 'UPDATE', 'x1_pa') $q$,
  '42501');
CALL x1_test.chk_raises('write','a guardian cannot grant themselves a role',
  $q$ INSERT INTO hbh.user_roles (user_id, role_id)
      SELECT (SELECT v FROM x1_test.fx WHERE k='u_pa'), role_id FROM hbh.roles LIMIT 1 $q$,
  '42501');
CALL x1_test.chk_raises('write','a guardian cannot read the one time codes table',
  $q$ SELECT count(*) FROM hbh.otp_codes $q$, '42501');
CALL x1_test.chk_raises('write','a guardian cannot read the session tokens table',
  $q$ SELECT count(*) FROM hbh.auth_sessions $q$, '42501');

RESET ROLE;

-- =====================================================================
-- CLEANUP - a recorded check like any other. Cleanup that swallows its
-- own failure is worse than no cleanup at all: the next run starts on
-- rows nobody knows are there.
-- =====================================================================
SELECT set_config('hbh.user_id', 'admin', false);

-- The status history tables are append-only by trigger, so the trigger
-- is disabled BY NAME and put back, and the last check confirms it came
-- back. See D-14.
ALTER TABLE hbh.appointment_status_history DISABLE TRIGGER trg_ash_append_only;
ALTER TABLE hbh.session_status_history     DISABLE TRIGGER trg_ssh_append_only;
ALTER TABLE hbh.consent_events             DISABLE TRIGGER trg_cev_append_only;

DELETE FROM hbh.activity_log      WHERE child_activity_id IN (SELECT v FROM x1_test.fx WHERE k IN ('ca_a','ca_b'));
DELETE FROM hbh.child_activities  WHERE activity_id = (SELECT v FROM x1_test.fx WHERE k='act');
DELETE FROM hbh.activity_library  WHERE code = 'X1ACT';
DELETE FROM hbh.parent_requests   WHERE request_no LIKE 'X1-REQ-%';
DELETE FROM hbh.progress_reports  WHERE report_no LIKE 'X1-RPT-%';
DELETE FROM hbh.goal_measurements WHERE goal_id IN (SELECT v FROM x1_test.fx WHERE k IN ('goal_a','goal_b'));
DELETE FROM hbh.session_notes     WHERE session_id IN (SELECT v FROM x1_test.fx WHERE k IN ('ses_a','ses_b'));
DELETE FROM hbh.plan_goals        WHERE plan_id IN (SELECT v FROM x1_test.fx WHERE k IN ('plan_a','plan_b'));
DELETE FROM hbh.treatment_plans   WHERE plan_id IN (SELECT v FROM x1_test.fx WHERE k IN ('plan_a','plan_b'));
DELETE FROM hbh.session_status_history     WHERE session_id IN (SELECT v FROM x1_test.fx WHERE k IN ('ses_a','ses_b'));
DELETE FROM hbh.therapy_sessions  WHERE session_id IN (SELECT v FROM x1_test.fx WHERE k IN ('ses_a','ses_b'));
DELETE FROM hbh.appointment_status_history WHERE appointment_id IN (SELECT v FROM x1_test.fx WHERE k IN ('apt_a','apt_b'));
DELETE FROM hbh.appointments      WHERE appointment_no LIKE 'X1-APT-%';
DELETE FROM hbh.caseload          WHERE child_id IN (SELECT v FROM x1_test.fx WHERE k IN ('ch_a','ch_b'));
DELETE FROM hbh.therapist_services WHERE therapist_id = (SELECT v FROM x1_test.fx WHERE k='th');
DELETE FROM hbh.therapists        WHERE therapist_id = (SELECT v FROM x1_test.fx WHERE k='th');
DELETE FROM hbh.rooms             WHERE code = 'X1RM';
DELETE FROM hbh.services          WHERE code = 'X1SVC';
-- The consents recorded for the live-view flag reference the guardians,
-- so they go before them - otherwise the delete dies on the foreign key,
-- the whole cleanup statement rolls back, and the NEXT run starts on
-- rows nobody knows are there.
DELETE FROM hbh.consent_events WHERE consent_id IN
  (SELECT consent_id FROM hbh.consents WHERE guardian_id IN
     (SELECT v FROM x1_test.fx WHERE k IN ('g_a','g_b','g_c')));
DELETE FROM hbh.consents WHERE guardian_id IN
  (SELECT v FROM x1_test.fx WHERE k IN ('g_a','g_b','g_c'));
DELETE FROM hbh.guardian_children WHERE child_id IN (SELECT v FROM x1_test.fx WHERE k IN ('ch_a','ch_b','ch_c'));
DELETE FROM hbh.children          WHERE child_no LIKE 'X1-%';
DELETE FROM hbh.guardians         WHERE mobile LIKE '+2019%';
-- Recording a consent raises a notification (migration 0015), and the
-- notification points at the user - so it goes before them, or the
-- users delete dies on the foreign key and takes the rest of the
-- cleanup statement with it.
DELETE FROM hbh.notifications     WHERE user_id IN (SELECT v FROM x1_test.fx WHERE k IN ('u_pa','u_pb','u_th','u_pc'));
DELETE FROM hbh.user_roles        WHERE user_id IN (SELECT v FROM x1_test.fx WHERE k IN ('u_pa','u_pb','u_th','u_pc'));
DELETE FROM hbh.role_permissions  WHERE role_id IN
       (SELECT role_id FROM hbh.roles WHERE center_id = (SELECT v FROM x1_test.fx WHERE k='c2'));
DELETE FROM hbh.roles             WHERE center_id = (SELECT v FROM x1_test.fx WHERE k='c2');
DELETE FROM hbh.users             WHERE username LIKE 'x1\_%';
DELETE FROM hbh.branches          WHERE code = 'X1B2';
DELETE FROM hbh.centers           WHERE code = 'X1C2';

ALTER TABLE hbh.appointment_status_history ENABLE TRIGGER trg_ash_append_only;
ALTER TABLE hbh.session_status_history     ENABLE TRIGGER trg_ssh_append_only;
ALTER TABLE hbh.consent_events             ENABLE TRIGGER trg_cev_append_only;

CALL x1_test.chk('cleanup','no test users are left behind',
  $q$ SELECT count(*) = 0 FROM hbh.users WHERE username LIKE 'x1\_%' $q$);
CALL x1_test.chk('cleanup','no test children are left behind',
  $q$ SELECT count(*) = 0 FROM hbh.children WHERE child_no LIKE 'X1-%' $q$);
CALL x1_test.chk('cleanup','the second centre is gone',
  $q$ SELECT count(*) = 0 FROM hbh.centers WHERE code = 'X1C2' $q$);
CALL x1_test.chk('cleanup','no test appointments or sessions are left behind',
  $q$ SELECT count(*) = 0 FROM hbh.appointments WHERE appointment_no LIKE 'X1-APT-%' $q$);
CALL x1_test.chk('cleanup','no test notes are left behind',
  $q$ SELECT count(*) = 0 FROM hbh.session_notes WHERE body_ar LIKE '%للطفل%' $q$);
CALL x1_test.chk('cleanup','all three append-only triggers are enabled again',
  $q$ SELECT count(*) = 3 FROM pg_trigger
      WHERE tgname IN ('trg_ash_append_only','trg_ssh_append_only','trg_cev_append_only')
      AND tgenabled = 'O' $q$);

-- =====================================================================
-- VERDICT
--
-- Printed first, always - a suite that dies before its verdict reads as
-- a pass. The raise comes after, and only after, so the exit code is
-- non-zero when anything failed.
-- =====================================================================
\echo ''
\echo '--- failures -------------------------------------------------'
SELECT seq, grp, name, detail FROM x1_test.results WHERE NOT ok ORDER BY seq;

\echo ''
\echo '--- by group -------------------------------------------------'
SELECT grp, count(*) AS checks, count(*) FILTER (WHERE NOT ok) AS failed
FROM x1_test.results GROUP BY grp ORDER BY min(seq);

DO $$
DECLARE n integer; f integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE NOT ok) INTO n, f FROM x1_test.results;
  RAISE NOTICE '';
  RAISE NOTICE '--------------------------------------------------';
  RAISE NOTICE '  % checks, % failed', n, f;
  IF f = 0 THEN
    RAISE NOTICE '  X1 ACCEPTED';
  ELSE
    RAISE NOTICE '  *** X1 NOT ACCEPTED';
  END IF;
  RAISE NOTICE '--------------------------------------------------';
END $$;

DO $$
DECLARE f integer;
BEGIN
  SELECT count(*) FILTER (WHERE NOT ok) INTO f FROM x1_test.results;
  IF f > 0 THEN
    RAISE EXCEPTION 'x1: % checks failed', f;
  END IF;
END $$;
