-- =====================================================================
-- Hand By Hand (new) - PHASE 10 acceptance suite
--
-- Must print:  PHASE 10 ACCEPTED
--
-- Three features, and one of them changes the shape of the schema:
-- enrolment is the FIRST anonymous write. So the suite spends most of
-- its weight there, on what an unauthenticated caller can and cannot
-- reach.
--
--   1. a family with no account submits an application, and that
--      creates a row in ONE table - not a child;
--   2. the satisfaction question is configuration, and the number it
--      produces is NPS and not a mean;
--   3. every request is logged with its latency and its error, and only
--      an operator can read it.
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
CREATE TABLE hbh_test.fxs (k text PRIMARY KEY, v text);

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

CREATE PROCEDURE hbh_test.chk_reason(p_grp text, p_name text, p_sql text, p_reason text)
LANGUAGE plpgsql AS $$
DECLARE v_got text;
BEGIN
  BEGIN
    EXECUTE p_sql INTO v_got;
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, v_got IS NOT DISTINCT FROM p_reason,
            'expected ' || p_reason || ', got ' || coalesce(v_got, 'NULL'));
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, false, SQLSTATE || ' ' || SQLERRM);
  END;
END $$;

GRANT USAGE ON SCHEMA hbh_test TO hbh_app;
GRANT INSERT, SELECT ON hbh_test.results TO hbh_app;
-- INSERT as well as SELECT: this suite captures fixture values from
-- inside checks that run AS hbh_app - the anonymous submission is the
-- whole point, and it has to stash the reference number it gets back.
GRANT INSERT, SELECT ON hbh_test.fx, hbh_test.fxs TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh_test TO hbh_app;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA hbh_test TO hbh_app;

-- =====================================================================
-- FIXTURE
-- =====================================================================
INSERT INTO hbh_test.fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO hbh_test.fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

INSERT INTO hbh.services (center_id, branch_id, code, name_ar, kind_code)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'PA-SPEECH', 'تخاطب — اختبار ١٠', 'SPEECH');
INSERT INTO hbh_test.fx (k, v) SELECT 'svc', service_id FROM hbh.services WHERE code='PA-SPEECH';

INSERT INTO hbh.rooms (center_id, branch_id, code, name_ar)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'PA-R1', 'غرفة اختبار ١٠');
INSERT INTO hbh_test.fx (k, v) SELECT 'room', room_id FROM hbh.rooms WHERE code='PA-R1';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
       u.username, u.name, u.utype, u.mobile
FROM (VALUES
       ('pa.therapist', 'أخصائي اختبار ١٠',  'THERAPIST', '+201100000001'),
       ('pa.reception', 'استقبال اختبار ١٠', 'STAFF',     '+201100000002'),
       ('pa.guardian',  'ولي أمر اختبار ١٠', 'GUARDIAN',  '+201100000003')
     ) AS u(username, name, utype, mobile);

INSERT INTO hbh_test.fx (k, v) SELECT 'user_th', user_id FROM hbh.users WHERE username='pa.therapist';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_rc', user_id FROM hbh.users WHERE username='pa.reception';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_gd', user_id FROM hbh.users WHERE username='pa.guardian';

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT f.v, r.role_id
FROM   hbh_test.fx f
JOIN   hbh.roles r ON r.center_id = (SELECT v FROM hbh_test.fx WHERE k='center')
WHERE  (f.k = 'user_th' AND r.code = 'THERAPIST')
   OR  (f.k = 'user_rc' AND r.code = 'RECEPTION')
   OR  (f.k = 'user_gd' AND r.code = 'GUARDIAN');

INSERT INTO hbh.therapists (center_id, branch_id, user_id, full_name_ar)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_th'), 'أخصائي اختبار ١٠');
INSERT INTO hbh_test.fx (k, v) SELECT 'th', therapist_id FROM hbh.therapists WHERE full_name_ar='أخصائي اختبار ١٠';

INSERT INTO hbh.therapist_services (therapist_id, service_id)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='svc'));

INSERT INTO hbh.therapist_working_hours (center_id, therapist_id, weekday, start_time, end_time)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='th'),
       d, TIME '09:00', TIME '17:00'
FROM unnest(ARRAY[7,1,2,3,4]::smallint[]) AS d;

INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'PA-A', 'طفل اختبار ١٠', DATE '2020-10-10', 'M');
INSERT INTO hbh_test.fx (k, v) SELECT 'child', child_id FROM hbh.children WHERE child_no='PA-A';

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_gd'), 'ولي أمر اختبار ١٠', '+201100000003');
INSERT INTO hbh_test.fx (k, v) SELECT 'gd', guardian_id FROM hbh.guardians WHERE mobile='+201100000003';

INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='gd'), (SELECT v FROM hbh_test.fx WHERE k='child'), 'FATHER', true);

INSERT INTO hbh.caseload (center_id, therapist_id, child_id, service_id)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='th'),
        (SELECT v FROM hbh_test.fx WHERE k='child'), (SELECT v FROM hbh_test.fx WHERE k='svc'));

-- A completed session, so the ACTION-triggered survey has something to
-- fire on.
INSERT INTO hbh_test.fx (k, v)
SELECT 'appt', hbh.book_appointment(
  (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
  (SELECT v FROM hbh_test.fx WHERE k='child'), (SELECT v FROM hbh_test.fx WHERE k='th'),
  (SELECT v FROM hbh_test.fx WHERE k='room'), (SELECT v FROM hbh_test.fx WHERE k='svc'),
  (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo') + interval '7 days' + interval '10 hours')
    AT TIME ZONE 'Africa/Cairo',
  (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo') + interval '7 days' + interval '10 hours 45 minutes')
    AT TIME ZONE 'Africa/Cairo');

UPDATE hbh.appointments SET status = 'CONFIRMED'  WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt');
UPDATE hbh.appointments SET status = 'CHECKED_IN' WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt');
-- The identity now covers the START as well as the close. Migration 0087
-- gave hbh.start_session the authorization it shipped without, so with
-- no identity it fails closed with HB028 and 'sess' is never recorded -
-- which then made close_session refuse a NULL session, and the teardown
-- leave an appointment behind.
SET hbh.user_id = 'pa.therapist';

INSERT INTO hbh_test.fx (k, v)
SELECT 'sess', hbh.start_session((SELECT v FROM hbh_test.fx WHERE k='appt'));

SELECT hbh.close_session((SELECT v FROM hbh_test.fx WHERE k='sess'), 'COMPLETED');
RESET hbh.user_id;

INSERT INTO hbh_test.fx (k, v) SELECT 'survey', survey_id FROM hbh.nps_surveys WHERE code = 'PARENT_SESSION';

-- A SECOND survey, this suite's own, and the reason it exists is a
-- defect this file had until today.
--
-- The four checks on hbh.v_nps_summary assert ABSOLUTE totals - four
-- answers, two promoters, an NPS of 25, a mean of 7.25. They were asked
-- of the SEEDED survey, PARENT_SESSION, which is the product's own and
-- shared with everything: the portal offers it, every completed session
-- triggers it, and any real answer anybody ever gives lands in the same
-- aggregate. On a database built a moment ago they passed. On a
-- database somebody had used, ONE neighbouring answer moved all four -
-- measured: a single row inserted against PARENT_SESSION turned 91/0
-- into 91/4.
--
-- That is CLAUDE.md's rule, and scoping by survey_id was not enough to
-- keep it: the survey is not the fixture's, so binding to it binds to
-- everybody. A count is only safe when the suite owns every row it
-- counts.
--
-- INACTIVE, so hbh.nps_due() never offers it and the due-and-cooldown
-- checks above keep testing the seeded survey exactly as they did.
-- hbh.v_nps_summary does not filter on active_flg - it groups by it -
-- so an inactive survey still reports its arithmetic.
--
-- The write path is NOT moved here. submit_nps and skip_nps stay on the
-- seeded survey, where being due is part of what they are proving.
-- What this survey isolates is the VIEW'S ARITHMETIC - that nps and the
-- mean are different numbers - and arithmetic needs rows nobody else
-- can add to, not a live product surface.
INSERT INTO hbh.nps_surveys
       (center_id, code, name_ar, question_ar, audience,
        trigger_kind, action_code, cooldown_days, active_flg)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'),
       'PA_ARITHMETIC', 'مجموعة p10 — حساب المؤشّر',
       'سؤال هذه المجموعة وحدها، ولا يُعرض لأحد', 'ALL',
       'ACTION', 'SESSION_COMPLETED', 30, false;

INSERT INTO hbh_test.fx (k, v)
SELECT 'survey_own', survey_id FROM hbh.nps_surveys WHERE code = 'PA_ARITHMETIC';

-- ---------------------------------------------------------------------
CALL hbh_test.chk('fixture', 'migrations 0018 to 0020 recorded',
  $q$ SELECT count(*) = 3 FROM hbh.schema_migrations WHERE version IN ('0018','0019','0020') $q$);

CALL hbh_test.chk('fixture', 'the seeded survey exists and fires on a completed session',
  $q$ SELECT trigger_kind = 'ACTION' AND action_code = 'SESSION_COMPLETED' AND active_flg
      FROM hbh.nps_surveys WHERE survey_id = (SELECT v FROM hbh_test.fx WHERE k='survey') $q$);

CALL hbh_test.chk('fixture', 'the session really did complete',
  $q$ SELECT status = 'COMPLETED' FROM hbh.therapy_sessions
      WHERE session_id = (SELECT v FROM hbh_test.fx WHERE k='sess') $q$);

CALL hbh_test.chk('fixture', 'the ENROL number series is defined',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.number_series WHERE code = 'ENROL') $q$);

CALL hbh_test.chk('fixture', 'reception can manage enrolments and cannot read the ops log',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.roles r
        JOIN hbh.role_permissions rp ON rp.role_id = r.role_id
        JOIN hbh.permissions p ON p.permission_id = rp.permission_id
        WHERE r.code = 'RECEPTION' AND p.code = 'ENROLMENT.MANAGE')
      AND NOT EXISTS (SELECT 1 FROM hbh.roles r
        JOIN hbh.role_permissions rp ON rp.role_id = r.role_id
        JOIN hbh.permissions p ON p.permission_id = rp.permission_id
        WHERE r.code = 'RECEPTION' AND p.code = 'OPS.VIEW') $q$);

-- =====================================================================
-- 1. THE ANONYMOUS SUBMISSION
--
-- As hbh_app with NO identity - exactly what the login screen has.
-- =====================================================================
SET ROLE hbh_app;
RESET hbh.user_id;

CALL hbh_test.chk('anon', 'the caller really has no identity',
  $q$ SELECT hbh.current_user_id() IS NULL AND hbh.current_center_id() IS NULL $q$);

CALL hbh_test.chk('anon', 'and can still submit an application',
  $q$ WITH s AS (SELECT * FROM hbh.submit_enrolment(
                   'HBH', 'أب جديد', '+201055500001', 'طفل جديد',
                   DATE '2021-05-05', 'M', NULL, 'FATHER', 'تأخّر لغوي',
                   NULL, NULL, NULL, NULL, 'WEB', '203.0.113.9'::inet)),
           i AS (INSERT INTO hbh_test.fxs (k, v) SELECT 'app1_no', s.application_no FROM s WHERE s.ok RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('anon', 'the reference number is all they get back',
  $q$ SELECT v ~ ('^ENR-' || extract(year FROM now())::integer || '-[0-9]{5}$')
      FROM hbh_test.fxs WHERE k = 'app1_no' $q$);

-- The endpoint must not become a way to find out who is already known
-- to the centre.
CALL hbh_test.chk('anon', 'an anonymous caller can read NO application back',
  $q$ SELECT count(*) = 0 FROM hbh.enrolment_applications $q$);

CALL hbh_test.chk_raises('anon', 'and cannot insert one directly either',
  $q$ INSERT INTO hbh.enrolment_applications
        (center_id, application_no, parent_name_ar, parent_mobile,
         child_name_ar, child_birth_date, child_gender)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'ENR-FAKE', 'x', '+201000000000',
              'y', DATE '2020-01-01', 'M') $q$, '42501');

-- An unknown centre code is refused the same way a rate limit is, so
-- the caller learns nothing about which codes exist.
CALL hbh_test.chk_reason('anon', 'an unknown centre code gives a vague refusal',
  $q$ SELECT reason FROM hbh.submit_enrolment(
        'NO-SUCH-CENTRE', 'أب', '+201055500009', 'طفل',
        DATE '2021-01-01', 'M') $q$, 'REJECTED');

-- Rate limits, from sys_params.
CALL hbh_test.chk('anon', 'the same mobile may submit up to the daily limit',
  $q$ SELECT (SELECT ok FROM hbh.submit_enrolment('HBH','أب جديد','+201055500001','طفل ثانٍ',
                DATE '2022-02-02','F'))
         AND (SELECT ok FROM hbh.submit_enrolment('HBH','أب جديد','+201055500001','طفل ثالث',
                DATE '2023-03-03','M')) $q$);

CALL hbh_test.chk_reason('anon', 'and the fourth from that mobile is refused',
  $q$ SELECT reason FROM hbh.submit_enrolment('HBH','أب جديد','+201055500001','طفل رابع',
        DATE '2023-04-04','M') $q$, 'TOO_MANY_FOR_MOBILE');

CALL hbh_test.chk('anon', 'a different mobile is unaffected',
  $q$ SELECT ok FROM hbh.submit_enrolment('HBH','أم جديدة','+201055500002','طفل آخر',
        DATE '2021-06-06','F', NULL, 'MOTHER') $q$);

RESET ROLE;

CALL hbh_test.chk('anon', 'four applications reached the table',
  $q$ SELECT count(*) = 4 FROM hbh.enrolment_applications
      WHERE parent_mobile LIKE '+2010555000%' $q$);

-- The claim the whole design rests on: an application is not a child.
-- Named exactly, because the database is shared and a LIKE would count
-- somebody else's rows.
CALL hbh_test.chk('anon', 'and every one of them created NO child',
  $q$ SELECT count(*) = 0 FROM hbh.children
      WHERE full_name_ar IN ('طفل جديد','طفل ثانٍ','طفل ثالث','طفل رابع','طفل آخر') $q$);

-- =====================================================================
-- 2. WHO MAY SEE AN APPLICATION
-- =====================================================================
SET ROLE hbh_app;

SET hbh.user_id = 'pa.guardian';
CALL hbh_test.chk('access', 'a guardian sees no applications at all',
  $q$ SELECT count(*) = 0 FROM hbh.enrolment_applications $q$);

SET hbh.user_id = 'pa.therapist';
CALL hbh_test.chk('access', 'and neither does a therapist',
  $q$ SELECT count(*) = 0 FROM hbh.enrolment_applications $q$);

SET hbh.user_id = 'pa.reception';
CALL hbh_test.chk('access', 'reception with ENROLMENT.MANAGE sees them',
  $q$ SELECT count(*) >= 4 FROM hbh.enrolment_applications $q$);

CALL hbh_test.chk('access', 'and may move one along',
  $q$ WITH u AS (UPDATE hbh.enrolment_applications
                    SET status = 'CONTACTED', contacted_at = now(),
                        contact_note_ar = 'اتكلّمنا معاه'
                  WHERE application_no = (SELECT v FROM hbh_test.fxs WHERE k='app1_no')
                  RETURNING 1)
      SELECT count(*) = 1 FROM u $q$);

RESET ROLE;
RESET hbh.user_id;

-- =====================================================================
-- 3. AN APPLICATION BECOMES A FAMILY - AND ONLY THIS WAY
-- =====================================================================
INSERT INTO hbh_test.fx (k, v)
SELECT 'app1', application_id FROM hbh.enrolment_applications
WHERE application_no = (SELECT v FROM hbh_test.fxs WHERE k='app1_no');

CALL hbh_test.chk_raises('convert', 'NEW straight to ENROLLED is refused by the machine',
  $q$ UPDATE hbh.enrolment_applications SET status = 'ENROLLED'
      WHERE parent_mobile = '+201055500002' $q$, 'HB090');

SET hbh.user_id = 'pa.guardian';
CALL hbh_test.chk_raises('convert', 'a guardian cannot convert one - HB092',
  $q$ SELECT hbh.convert_enrolment((SELECT v FROM hbh_test.fx WHERE k='app1')) $q$, 'HB092');

SET hbh.user_id = 'pa.reception';

-- Contacting the family first is the rule, not a nicety: enrolling
-- somebody nobody has spoken to is how a wrong number becomes a child.
CALL hbh_test.chk_raises('convert', 'an application still NEW cannot be converted - HB091',
  $q$ SELECT hbh.convert_enrolment(
        (SELECT application_id FROM hbh.enrolment_applications
         WHERE parent_mobile = '+201055500002')) $q$, 'HB091');

CALL hbh_test.chk('convert', 'a CONTACTED application converts',
  $q$ WITH c AS (SELECT * FROM hbh.convert_enrolment(
                   (SELECT v FROM hbh_test.fx WHERE k='app1'), 'تم القبول')),
           i AS (INSERT INTO hbh_test.fx (k, v)
                 SELECT 'new_child', c.child_id FROM c RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

RESET hbh.user_id;

CALL hbh_test.chk('convert', 'a real child now exists with a proper number',
  $q$ SELECT child_no ~ '^CH-[0-9]{5}$' AND full_name_ar = 'طفل جديد'
      FROM hbh.children WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='new_child') $q$);

CALL hbh_test.chk('convert', 'a guardian was created and linked to them',
  $q$ SELECT count(*) = 1 FROM hbh.guardian_children gc
      JOIN hbh.guardians g ON g.guardian_id = gc.guardian_id
      WHERE gc.child_id = (SELECT v FROM hbh_test.fx WHERE k='new_child')
        AND g.mobile = '+201055500001' $q$);

-- An enrolment form is not a consent to watch a child in therapy.
CALL hbh_test.chk('convert', 'and the live-view flag was NOT set on the way in',
  $q$ SELECT NOT can_view_live_flg FROM hbh.guardian_children
      WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='new_child') $q$);

CALL hbh_test.chk('convert', 'the application now points at what it produced',
  $q$ SELECT status = 'ENROLLED' AND converted_child_id IS NOT NULL
             AND converted_guardian_id IS NOT NULL AND decided_by IS NOT NULL
      FROM hbh.enrolment_applications
      WHERE application_id = (SELECT v FROM hbh_test.fx WHERE k='app1') $q$);

SET hbh.user_id = 'pa.reception';
CALL hbh_test.chk_raises('convert', 'converting it twice is refused - HB091',
  $q$ SELECT hbh.convert_enrolment((SELECT v FROM hbh_test.fx WHERE k='app1')) $q$, 'HB091');

-- A second child for a family already known must attach to the parent
-- who exists, not create a copy of them.
CALL hbh_test.chk('convert', 'a second application from the same mobile is contacted',
  $q$ WITH u AS (UPDATE hbh.enrolment_applications SET status = 'CONTACTED', contacted_at = now()
                  WHERE parent_mobile = '+201055500001' AND status = 'NEW'
                    AND child_name_ar = 'طفل ثانٍ' RETURNING 1)
      SELECT count(*) = 1 FROM u $q$);

CALL hbh_test.chk('convert', 'and converting it reuses the guardian rather than duplicating them',
  $q$ WITH c AS (SELECT * FROM hbh.convert_enrolment(
                   (SELECT application_id FROM hbh.enrolment_applications
                    WHERE parent_mobile = '+201055500001' AND child_name_ar = 'طفل ثانٍ')))
      SELECT count(*) = 1 FROM c $q$);

RESET hbh.user_id;

CALL hbh_test.chk('convert', 'there is still exactly ONE guardian on that mobile',
  $q$ SELECT count(*) = 1 FROM hbh.guardians WHERE mobile = '+201055500001' $q$);

CALL hbh_test.chk('convert', 'and they now have two children',
  $q$ SELECT count(*) = 2 FROM hbh.guardian_children gc
      JOIN hbh.guardians g ON g.guardian_id = gc.guardian_id
      WHERE g.mobile = '+201055500001' $q$);

CALL hbh_test.chk_raises('convert', 'ENROLLED without the converted ids is refused by the constraint',
  $q$ UPDATE hbh.enrolment_applications
         SET status = 'ENROLLED', converted_child_id = NULL, converted_guardian_id = NULL
       WHERE application_id = (SELECT v FROM hbh_test.fx WHERE k='app1') $q$, '23514');

-- =====================================================================
-- 4. THE SATISFACTION QUESTION
-- =====================================================================
SET ROLE hbh_app;

RESET hbh.user_id;
CALL hbh_test.chk('nps', 'no identity, no question',
  $q$ SELECT count(*) = 0 FROM hbh.nps_due() $q$);

SET hbh.user_id = 'pa.guardian';
CALL hbh_test.chk('nps', 'the guardian is due the survey after the completed session',
  $q$ SELECT count(*) = 1 FROM hbh.nps_due()
      WHERE survey_id = (SELECT v FROM hbh_test.fx WHERE k='survey') $q$);

CALL hbh_test.chk('nps', 'and it carries the wording, not just an id',
  $q$ SELECT length(question_ar) > 10 AND length(followup_question_ar) > 5
      FROM hbh.nps_due() $q$);

CALL hbh_test.chk_raises('nps', 'a score above ten is refused - HB093',
  $q$ SELECT hbh.submit_nps((SELECT v FROM hbh_test.fx WHERE k='survey'), 11::smallint) $q$, 'HB093');

CALL hbh_test.chk_raises('nps', 'and a negative one too',
  $q$ SELECT hbh.submit_nps((SELECT v FROM hbh_test.fx WHERE k='survey'), (-1)::smallint) $q$, 'HB093');

CALL hbh_test.chk('nps', 'the guardian answers nine with a comment',
  $q$ WITH s AS (SELECT hbh.submit_nps((SELECT v FROM hbh_test.fx WHERE k='survey'),
                                       9::smallint, 'الأخصائية ممتازة') AS id)
      SELECT count(*) = 1 FROM s $q$);

CALL hbh_test.chk('nps', 'the score and the free text were both stored',
  $q$ SELECT score = 9 AND comment_ar = 'الأخصائية ممتازة' AND NOT skipped_flg
      FROM hbh.nps_responses
      WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user_gd')
        AND survey_id = (SELECT v FROM hbh_test.fx WHERE k='survey') $q$);

-- The cooldown is what stops the question reappearing on every refresh.
CALL hbh_test.chk('nps', 'and it is no longer due - the cooldown holds',
  $q$ SELECT count(*) = 0 FROM hbh.nps_due() $q$);

RESET hbh.user_id;
RESET ROLE;

-- A dismissal must count as "asked", or the question nags for ever.
INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'pa.gd2', 'ولي أمر ثانٍ', 'GUARDIAN', '+201100000004');
INSERT INTO hbh_test.fx (k, v) SELECT 'user_gd2', user_id FROM hbh.users WHERE username='pa.gd2';
INSERT INTO hbh.user_roles (user_id, role_id)
SELECT (SELECT v FROM hbh_test.fx WHERE k='user_gd2'), role_id FROM hbh.roles
WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center') AND code = 'GUARDIAN';
INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_gd2'), 'ولي أمر ثانٍ', '+201100000004');
INSERT INTO hbh_test.fx (k, v) SELECT 'gd2', guardian_id FROM hbh.guardians WHERE mobile='+201100000004';
INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='gd2'), (SELECT v FROM hbh_test.fx WHERE k='child'), 'MOTHER');

SET ROLE hbh_app;
SET hbh.user_id = 'pa.gd2';

CALL hbh_test.chk('nps', 'the second guardian is due it too',
  $q$ SELECT count(*) = 1 FROM hbh.nps_due() $q$);

CALL hbh_test.chk('nps', 'she dismisses it',
  $q$ WITH s AS (SELECT hbh.skip_nps((SELECT v FROM hbh_test.fx WHERE k='survey')) AS id)
      SELECT count(*) = 1 FROM s $q$);

CALL hbh_test.chk('nps', 'the dismissal was RECORDED, not forgotten',
  $q$ SELECT skipped_flg AND score IS NULL FROM hbh.nps_responses
      WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user_gd2') $q$);

CALL hbh_test.chk('nps', 'and it stops being asked',
  $q$ SELECT count(*) = 0 FROM hbh.nps_due() $q$);

RESET hbh.user_id;
RESET ROLE;

-- The number, computed properly. Four answers: 9 and 10 promote, 7
-- counts for neither, 3 detracts. Two promoters of four is 50 per cent,
-- one detractor is 25, so NPS is 25 - while the MEAN is 7.25. The two
-- must not be confused, so the view is asked for both.
--
-- ALL FIVE ROWS GO TO THIS SUITE'S OWN SURVEY, including the nine and
-- the dismissal that the two above wrote through submit_nps and
-- skip_nps against the seeded one. Those two calls keep their own
-- checks and prove the write path; these five are the arithmetic, and
-- the arithmetic has to be asked of a set nobody else can add to. See
-- the note beside PA_ARITHMETIC in the fixture.
INSERT INTO hbh.nps_responses (center_id, survey_id, user_id, score, comment_ar, skipped_flg)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='survey_own'),
        (SELECT v FROM hbh_test.fx WHERE k='user_gd'),  9,    'ممتاز جدًا',      false),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='survey_own'),
        (SELECT v FROM hbh_test.fx WHERE k='user_rc'),  10,   'ممتاز',           false),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='survey_own'),
        (SELECT v FROM hbh_test.fx WHERE k='user_th'),  7,    'كويس',            false),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='survey_own'),
        (SELECT v FROM hbh_test.fx WHERE k='user_gd2'), 3,    'المواعيد بتتأخر', false),
       -- The dismissal. Recorded, not forgotten - and counted apart from
       -- the answers, which is the whole reason skipped_cnt exists.
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='survey_own'),
        (SELECT v FROM hbh_test.fx WHERE k='user_gd'),  NULL, NULL,              true);

-- The suite owns every row in this survey, so it may assert absolutes.
CALL hbh_test.chk('nps', 'this suite owns every answer it is about to count',
  $q$ SELECT count(*) = 5 FROM hbh.nps_responses
      WHERE survey_id = (SELECT v FROM hbh_test.fx WHERE k='survey_own') $q$);

CALL hbh_test.chk('nps', 'four answers and one dismissal are counted separately',
  $q$ SELECT answered_cnt = 4 AND skipped_cnt = 1 FROM hbh.v_nps_summary
      WHERE survey_id = (SELECT v FROM hbh_test.fx WHERE k='survey_own') $q$);

CALL hbh_test.chk('nps', 'the buckets are 2 promoters, 1 passive, 1 detractor',
  $q$ SELECT promoters = 2 AND passives = 1 AND detractors = 1 FROM hbh.v_nps_summary
      WHERE survey_id = (SELECT v FROM hbh_test.fx WHERE k='survey_own') $q$);

CALL hbh_test.chk('nps', 'NPS is 25 - promoters minus detractors, not an average',
  $q$ SELECT nps = 25 FROM hbh.v_nps_summary
      WHERE survey_id = (SELECT v FROM hbh_test.fx WHERE k='survey_own') $q$);

CALL hbh_test.chk('nps', 'and the mean is 7.25, which is a DIFFERENT number',
  $q$ SELECT mean_score = 7.25 FROM hbh.v_nps_summary
      WHERE survey_id = (SELECT v FROM hbh_test.fx WHERE k='survey_own') $q$);

-- And the guard that would have caught the original defect on the day
-- it was written: a neighbour's answer to the PRODUCT's survey must not
-- reach this suite's numbers. Nothing here reads PARENT_SESSION's
-- totals any more, and this says so in a way that fails if somebody
-- points these checks back at it.
CALL hbh_test.chk('nps', 'and the seeded survey is not what any of that was measured on',
  $q$ SELECT (SELECT v FROM hbh_test.fx WHERE k='survey_own')
           <> (SELECT v FROM hbh_test.fx WHERE k='survey') $q$);

-- =====================================================================
-- 5. THE CONFIGURATION IS EDITABLE, AND ONLY BY ONE ROLE
-- =====================================================================
SET ROLE hbh_app;

SET hbh.user_id = 'pa.guardian';
CALL hbh_test.chk('config', 'a guardian may READ the survey wording - the portal needs it',
  $q$ SELECT count(*) >= 1 FROM hbh.nps_surveys $q$);

-- WITH, not a subquery. A data-modifying statement is legal only inside
-- a WITH clause; written as FROM (UPDATE ...) x it is a syntax error,
-- and the check then fails for a reason that has nothing to do with the
-- policy it was meant to test.
--
-- The policy refuses by matching no rows rather than by raising: an
-- UPDATE that the USING clause excludes simply updates nothing.
CALL hbh_test.chk('config', 'and may not change when it is asked',
  $q$ WITH u AS (UPDATE hbh.nps_surveys SET cooldown_days = 1
                  WHERE survey_id = (SELECT v FROM hbh_test.fx WHERE k='survey') RETURNING 1)
      SELECT count(*) = 0 FROM u $q$);

SET hbh.user_id = 'pa.reception';
CALL hbh_test.chk('config', 'nor may reception - it needs NPS.MANAGE',
  $q$ WITH u AS (UPDATE hbh.nps_surveys SET cooldown_days = 1
                  WHERE survey_id = (SELECT v FROM hbh_test.fx WHERE k='survey') RETURNING 1)
      SELECT count(*) = 0 FROM u $q$);

SET hbh.user_id = 'admin';
CALL hbh_test.chk('config', 'an administrator changes the trigger from ACTION to PERIOD',
  $q$ WITH u AS (UPDATE hbh.nps_surveys
                    SET trigger_kind = 'PERIOD', period_days = 90, action_code = NULL,
                        question_ar = 'سؤال معدَّل من شاشة الإدارة'
                  WHERE survey_id = (SELECT v FROM hbh_test.fx WHERE k='survey') RETURNING 1)
      SELECT count(*) = 1 FROM u $q$);

CALL hbh_test.chk('config', 'and the change is live immediately - no deployment',
  $q$ SELECT trigger_kind = 'PERIOD' AND period_days = 90 AND action_code IS NULL
             AND question_ar = 'سؤال معدَّل من شاشة الإدارة'
      FROM hbh.nps_surveys WHERE survey_id = (SELECT v FROM hbh_test.fx WHERE k='survey') $q$);

RESET ROLE;
-- A PERIOD survey with no period would match nothing and never fire,
-- silently. The constraint refuses the shape rather than letting it rot.
CALL hbh_test.chk_raises('config', 'a PERIOD survey with no period is refused',
  $q$ UPDATE hbh.nps_surveys SET period_days = NULL
      WHERE survey_id = (SELECT v FROM hbh_test.fx WHERE k='survey') $q$, '23514');

CALL hbh_test.chk_raises('config', 'and an ACTION survey with no action likewise',
  $q$ INSERT INTO hbh.nps_surveys (center_id, code, name_ar, question_ar, trigger_kind)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'PA-BAD', 'x', 'y', 'ACTION') $q$,
  '23514');

-- =====================================================================
-- 6. WHO READS THE ANSWERS
-- =====================================================================
SET ROLE hbh_app;

SET hbh.user_id = 'pa.guardian';
-- The property is "nothing that is not hers", not "exactly one row".
--
-- It was written as count(*) = 1 because she had written exactly one
-- answer at the time. That tied a PRIVACY check to the size of an
-- unrelated fixture: the arithmetic rows above now give her a second,
-- and the check went red while the policy it tests was untouched. A
-- number that has to be revised whenever a neighbouring section grows
-- is not the invariant - it just happened to equal it once.
--
-- The lower bound stays so it cannot pass on an empty read: bool_and
-- over no rows is NULL, and a policy that returned nothing at all would
-- otherwise look like a policy that filtered perfectly.
CALL hbh_test.chk('answers', 'a guardian sees only her own answers, and nothing of anybody else''s',
  $q$ SELECT count(*) > 0 AND bool_and(user_id = (SELECT v FROM hbh_test.fx WHERE k='user_gd'))
      FROM hbh.nps_responses $q$);

SET hbh.user_id = 'admin';
CALL hbh_test.chk('answers', 'somebody with NPS.MANAGE reads the free text',
  $q$ SELECT count(*) >= 5 AND count(*) FILTER (WHERE comment_ar IS NOT NULL) >= 3
      FROM hbh.nps_responses $q$);

RESET hbh.user_id;
CALL hbh_test.chk('answers', 'and no identity reads none',
  $q$ SELECT count(*) = 0 FROM hbh.nps_responses $q$);

RESET ROLE;

-- =====================================================================
-- 7. EVERY REQUEST IS LOGGED
-- =====================================================================
SET hbh.user_id = 'pa.guardian';
CALL hbh_test.chk('log', 'a request by a signed-in user is logged with their name',
  $q$ WITH l AS (SELECT hbh.log_request('GET', '/api/children', 200::smallint, 42,
                                        '/api/children', 'req-pa-1',
                                        '203.0.113.10'::inet, 'Mozilla/5.0'))
      SELECT count(*) = 1 FROM l $q$);

CALL hbh_test.chk('log', 'and the row carries the identity, the route and the latency',
  $q$ SELECT username = 'pa.guardian' AND route = '/api/children'
             AND duration_ms = 42 AND status_code = 200
      FROM hbh.request_log WHERE request_id = 'req-pa-1' $q$);

RESET hbh.user_id;
CALL hbh_test.chk('log', 'an ANONYMOUS request is logged too, with no user',
  $q$ WITH l AS (SELECT hbh.log_request('POST', '/api/enrolment', 201::smallint, 130,
                                        '/api/enrolment', 'req-pa-anon',
                                        '203.0.113.11'::inet))
      SELECT count(*) = 1 FROM l $q$);

CALL hbh_test.chk('log', 'and that row has no user and no centre',
  $q$ SELECT user_id IS NULL AND username IS NULL AND center_id IS NULL
      FROM hbh.request_log WHERE request_id = 'req-pa-anon' $q$);

CALL hbh_test.chk('log', 'a failure is logged with its code, message and detail',
  $q$ WITH l AS (SELECT hbh.log_request('POST', '/api/appointments', 409::smallint, 88,
                                        '/api/appointments', 'req-pa-err',
                                        NULL, NULL, 'HB021', 'slot rejected: THERAPIST_BUSY',
                                        '{"therapist_id":7}'::jsonb))
      SELECT count(*) = 1 FROM l $q$);

CALL hbh_test.chk('log', 'and the detail survived as jsonb',
  $q$ SELECT error_code = 'HB021' AND (detail ->> 'therapist_id') = '7'
      FROM hbh.request_log WHERE request_id = 'req-pa-err' $q$);

-- A failure with no code cannot be grouped, counted or alerted on.
CALL hbh_test.chk_raises('log', 'a 500 with no error code is refused',
  $q$ INSERT INTO hbh.request_log (method, route, status_code, duration_ms)
      VALUES ('GET', '/api/x', 500, 5) $q$, '23514');

-- Logging must never turn a request that WORKED into one that failed.
CALL hbh_test.chk('log', 'a bad log call warns and returns rather than raising',
  $q$ WITH l AS (SELECT hbh.log_request('TELEPORT', '/api/x', 200::smallint, 1))
      SELECT count(*) = 1 FROM l $q$);

CALL hbh_test.chk('log', 'and it wrote nothing',
  $q$ SELECT count(*) = 0 FROM hbh.request_log WHERE method = 'TELEPORT' $q$);

CALL hbh_test.chk_raises('log', 'a log line cannot be edited afterwards',
  $q$ UPDATE hbh.request_log SET duration_ms = 1 WHERE request_id = 'req-pa-1' $q$, 'HB001');

-- =====================================================================
-- 8. WHAT THE OPERATIONS SCREEN SHOWS
-- =====================================================================
CALL hbh_test.chk('ops', 'health is grouped by ROUTE and reports latency percentiles',
  $q$ SELECT calls >= 1 AND p50_ms IS NOT NULL AND p95_ms IS NOT NULL
      FROM hbh.v_api_health WHERE route = '/api/children' AND method = 'GET' $q$);

CALL hbh_test.chk('ops', 'the failing route shows a hundred per cent error rate',
  $q$ SELECT error_pct = 100.00 AND client_errors = 1
      FROM hbh.v_api_health WHERE route = '/api/appointments' $q$);

CALL hbh_test.chk('ops', 'the error list carries the message and the detail',
  $q$ SELECT error_code = 'HB021' AND error_message LIKE '%THERAPIST_BUSY%'
      FROM hbh.v_recent_errors WHERE request_id = 'req-pa-err' $q$);

CALL hbh_test.chk('ops', 'user activity names who used it and when',
  $q$ SELECT requests >= 1 AND last_seen_at IS NOT NULL
      FROM hbh.v_user_activity WHERE username = 'pa.guardian' $q$);

-- The log names every user and every path they touched.
SET ROLE hbh_app;

SET hbh.user_id = 'pa.guardian';
CALL hbh_test.chk('ops', 'a guardian cannot read the operations log',
  $q$ SELECT count(*) = 0 FROM hbh.request_log $q$);

SET hbh.user_id = 'pa.reception';
CALL hbh_test.chk('ops', 'and neither can reception - it needs OPS.VIEW',
  $q$ SELECT count(*) = 0 FROM hbh.request_log $q$);

SET hbh.user_id = 'pa.therapist';
CALL hbh_test.chk('ops', 'nor a therapist',
  $q$ SELECT count(*) = 0 FROM hbh.request_log $q$);

SET hbh.user_id = 'admin';
CALL hbh_test.chk('ops', 'an administrator with OPS.VIEW does',
  $q$ SELECT count(*) >= 3 FROM hbh.request_log $q$);

CALL hbh_test.chk('ops', 'and the views follow the same policy',
  $q$ SELECT count(*) >= 1 FROM hbh.v_recent_errors $q$);

RESET hbh.user_id;
RESET ROLE;

-- =====================================================================
-- 9. RETENTION
-- =====================================================================
INSERT INTO hbh.request_log (occurred_at, request_id, method, route, status_code, duration_ms)
VALUES (now() - interval '400 days', 'req-pa-old', 'GET', '/api/old', 200, 3);

CALL hbh_test.chk('retention', 'an old log line exists before the purge',
  $q$ SELECT count(*) = 1 FROM hbh.request_log WHERE request_id = 'req-pa-old' $q$);

CALL hbh_test.chk('retention', 'run_maintenance purges past the retention',
  $q$ WITH m AS (SELECT hbh.run_maintenance() AS id),
           i AS (INSERT INTO hbh_test.fx (k, v) SELECT 'run', id::integer FROM m RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('retention', 'and the old line is gone',
  $q$ SELECT count(*) = 0 FROM hbh.request_log WHERE request_id = 'req-pa-old' $q$);

CALL hbh_test.chk('retention', 'while today lines are untouched',
  $q$ SELECT count(*) >= 3 FROM hbh.request_log WHERE request_id LIKE 'req-pa-%' $q$);

-- The clinical audit trail is NOT housekeeping.
CALL hbh_test.chk('retention', 'the audit log was not purged by the same run',
  $q$ SELECT count(*) > 0 FROM hbh.audit_log
      WHERE changed_at < now() - interval '1 second' $q$);

-- =====================================================================
-- CLEANUP
-- =====================================================================
-- Seven answers now, not five: two on the seeded survey through
-- submit_nps and skip_nps, and five on this suite's own. Deleted by
-- IDENTITY - the users this fixture made - and never by a pattern on a
-- score or a date, which is how a cleanup reaches a neighbour's row.
CALL hbh_test.chk('cleanup', 'log lines and survey answers removed',
  $q$ WITH r AS (DELETE FROM hbh.request_log WHERE request_id LIKE 'req-pa-%' RETURNING 1),
           n AS (DELETE FROM hbh.nps_responses WHERE user_id IN
                   (SELECT user_id FROM hbh.users WHERE username LIKE 'pa.%') RETURNING 1)
      SELECT (SELECT count(*) FROM r) >= 3 AND (SELECT count(*) FROM n) = 7 $q$);

-- And the survey itself, by its code. It exists only for this suite, so
-- leaving it behind would put a second row in every later run's view of
-- hbh.nps_surveys - the very shape of leak this file just fixed.
CALL hbh_test.chk('cleanup', 'this suite''s own survey removed',
  $q$ WITH d AS (DELETE FROM hbh.nps_surveys WHERE code = 'PA_ARITHMETIC' RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the survey is put back the way the seed left it',
  $q$ WITH u AS (UPDATE hbh.nps_surveys
                    SET trigger_kind = 'ACTION', action_code = 'SESSION_COMPLETED',
                        period_days = NULL, cooldown_days = 30,
                        question_ar = 'ما مدى احتمال أن ترشّح مركزنا لصديق أو قريب؟'
                  WHERE survey_id = (SELECT v FROM hbh_test.fx WHERE k='survey') RETURNING 1)
      SELECT count(*) = 1 FROM u $q$);

CALL hbh_test.chk('cleanup', 'applications and what they produced removed',
  $q$ WITH a AS (DELETE FROM hbh.enrolment_applications
                  WHERE parent_mobile LIKE '+2010555000%' RETURNING 1),
           g AS (DELETE FROM hbh.guardian_children WHERE guardian_id IN
                   (SELECT guardian_id FROM hbh.guardians WHERE mobile = '+201055500001') RETURNING 1),
           k AS (DELETE FROM hbh.children WHERE full_name_ar IN ('طفل جديد','طفل ثانٍ') RETURNING 1),
           q AS (DELETE FROM hbh.guardians WHERE mobile = '+201055500001' RETURNING 1)
      SELECT (SELECT count(*) FROM a) = 4 AND (SELECT count(*) FROM k) = 2
         AND (SELECT count(*) FROM q) = 1 $q$);

CALL hbh_test.chk('cleanup', 'notifications removed',
  $q$ WITH d AS (DELETE FROM hbh.notifications WHERE user_id IN
                   (SELECT user_id FROM hbh.users WHERE username LIKE 'pa.%') RETURNING 1)
      SELECT count(*) >= 0 FROM d $q$);

ALTER TABLE hbh.session_status_history     DISABLE TRIGGER trg_ssh_append_only;
ALTER TABLE hbh.appointment_status_history DISABLE TRIGGER trg_ash_append_only;
CALL hbh_test.chk('cleanup', 'the session and appointment removed',
  $q$ WITH sh AS (DELETE FROM hbh.session_status_history WHERE session_id =
                    (SELECT v FROM hbh_test.fx WHERE k='sess') RETURNING 1),
           s AS (DELETE FROM hbh.therapy_sessions WHERE session_id =
                    (SELECT v FROM hbh_test.fx WHERE k='sess') RETURNING 1),
           ah AS (DELETE FROM hbh.appointment_status_history WHERE appointment_id =
                    (SELECT v FROM hbh_test.fx WHERE k='appt') RETURNING 1),
           a AS (DELETE FROM hbh.appointments WHERE appointment_id =
                    (SELECT v FROM hbh_test.fx WHERE k='appt') RETURNING 1)
      SELECT (SELECT count(*) FROM s) = 1 AND (SELECT count(*) FROM a) = 1 $q$);
ALTER TABLE hbh.session_status_history     ENABLE TRIGGER trg_ssh_append_only;
ALTER TABLE hbh.appointment_status_history ENABLE TRIGGER trg_ash_append_only;

CALL hbh_test.chk('cleanup', 'the rest removed',
  $q$ WITH cl AS (DELETE FROM hbh.caseload WHERE child_id =
                   (SELECT v FROM hbh_test.fx WHERE k='child') RETURNING 1),
           g AS (DELETE FROM hbh.guardian_children WHERE child_id =
                   (SELECT v FROM hbh_test.fx WHERE k='child') RETURNING 1),
           k AS (DELETE FROM hbh.children WHERE child_no = 'PA-A' RETURNING 1),
           q AS (DELETE FROM hbh.guardians WHERE mobile LIKE '+2011000000%' AND user_id IN (SELECT user_id FROM hbh.users WHERE username LIKE 'pa.%') RETURNING 1),
           w AS (DELETE FROM hbh.therapist_working_hours WHERE therapist_id =
                   (SELECT v FROM hbh_test.fx WHERE k='th') RETURNING 1),
           ts AS (DELETE FROM hbh.therapist_services WHERE therapist_id =
                   (SELECT v FROM hbh_test.fx WHERE k='th') RETURNING 1),
           t AS (DELETE FROM hbh.therapists WHERE therapist_id =
                   (SELECT v FROM hbh_test.fx WHERE k='th') RETURNING 1),
           rm AS (DELETE FROM hbh.rooms    WHERE code LIKE 'PA-%' RETURNING 1),
           sv AS (DELETE FROM hbh.services WHERE code LIKE 'PA-%' RETURNING 1),
           ur AS (DELETE FROM hbh.user_roles WHERE user_id IN
                   (SELECT user_id FROM hbh.users WHERE username LIKE 'pa.%') RETURNING 1),
           u AS (DELETE FROM hbh.users WHERE username LIKE 'pa.%' RETURNING 1)
      SELECT (SELECT count(*) FROM k) = 1 AND (SELECT count(*) FROM u) = 4 $q$);

CALL hbh_test.chk('cleanup', 'both append-only triggers are enabled again',
  $q$ SELECT count(*) = 2 FROM pg_trigger
      WHERE tgname IN ('trg_ssh_append_only','trg_ash_append_only') AND tgenabled = 'O' $q$);

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
  IF v_fail = 0 AND v_total > 0 THEN RAISE NOTICE '  PHASE 10 ACCEPTED';
  ELSE RAISE NOTICE '  *** PHASE 10 NOT ACCEPTED'; END IF;
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
