-- =====================================================================
-- Hand By Hand (new) - PHASE 3 acceptance suite
--
-- Must print:  PHASE 3 ACCEPTED
--
-- Two things this suite exists to prove, and everything else supports
-- them:
--
--   1. Two receptionists pressing save on the same slot at the same
--      instant cannot both succeed. Proven with two real connections
--      and an uncommitted transaction - not by reading the constraint.
--   2. "Did the visit happen" and "did the clinical work finish" are
--      different questions with different answers, and the system can
--      hold both at once.
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

-- validate_slot answers with a reason rather than an error, so its
-- negative tests name the reason the way chk_raises names a SQLSTATE.
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
GRANT SELECT ON hbh_test.fx, hbh_test.fxt TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh_test TO hbh_app;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA hbh_test TO hbh_app;

-- =====================================================================
-- FIXTURE
--
-- Dates are COMPUTED, never written down. A suite with a hardcoded
-- Monday passes until the week it is run in moves, and then fails for a
-- reason that has nothing to do with the code.
-- =====================================================================
INSERT INTO hbh_test.fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO hbh_test.fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

-- Next Monday 10:00 in the centre's own zone, expressed as an instant.
INSERT INTO hbh_test.fxt (k, v) VALUES
  ('slot_start', (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '7 days' + interval '10 hours') AT TIME ZONE 'Africa/Cairo'),
  ('slot_end',   (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '7 days' + interval '10 hours 45 minutes') AT TIME ZONE 'Africa/Cairo'),
  -- the same Monday, but before the therapist starts
  ('early_start',(date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '7 days' + interval '7 hours') AT TIME ZONE 'Africa/Cairo'),
  ('early_end',  (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '7 days' + interval '7 hours 45 minutes') AT TIME ZONE 'Africa/Cairo'),
  -- the Friday of that week: Egypt rests Friday and Saturday
  ('fri_start',  (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '11 days' + interval '10 hours') AT TIME ZONE 'Africa/Cairo'),
  ('fri_end',    (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '11 days' + interval '10 hours 45 minutes') AT TIME ZONE 'Africa/Cairo'),
  -- yesterday, for the backdating rule
  ('past_start', (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  - interval '6 days' + interval '10 hours') AT TIME ZONE 'Africa/Cairo'),
  ('past_end',   (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  - interval '6 days' + interval '10 hours 45 minutes') AT TIME ZONE 'Africa/Cairo'),
  -- a second, non-overlapping slot on the same Monday
  ('slot2_start',(date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '7 days' + interval '12 hours') AT TIME ZONE 'Africa/Cairo'),
  ('slot2_end',  (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '7 days' + interval '12 hours 45 minutes') AT TIME ZONE 'Africa/Cairo');

-- services and rooms
--
-- P3-CONSULT was added for 0118 and it is not decoration. The two flags
-- are what make a consultation a consultation: it opens no therapy
-- session and wants no caseload. Before them, the online booking below
-- used the SPEECH service - a service that DOES open sessions - and the
-- booking guard would now refuse it with HB251, rightly.
INSERT INTO hbh.services (center_id, branch_id, code, name_ar, kind_code, default_duration_min,
                          creates_session_flg, needs_caseload_flg)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P3-SPEECH', 'تخاطب — اختبار', 'SPEECH', 45, true, true),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P3-OT', 'علاج وظيفي — اختبار', 'OT', 45, true, true),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P3-CONSULT', 'استشارة أونلاين — اختبار', 'CONSULT', 30, false, false);
INSERT INTO hbh_test.fx (k, v) SELECT 'svc_speech',  service_id FROM hbh.services WHERE code='P3-SPEECH';
INSERT INTO hbh_test.fx (k, v) SELECT 'svc_ot',      service_id FROM hbh.services WHERE code='P3-OT';
INSERT INTO hbh_test.fx (k, v) SELECT 'svc_consult', service_id FROM hbh.services WHERE code='P3-CONSULT';

INSERT INTO hbh.rooms (center_id, branch_id, code, name_ar)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'), 'P3-R1', 'غرفة اختبار ١'),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'), 'P3-R2', 'غرفة اختبار ٢');
INSERT INTO hbh_test.fx (k, v) SELECT 'room1', room_id FROM hbh.rooms WHERE code='P3-R1';
INSERT INTO hbh_test.fx (k, v) SELECT 'room2', room_id FROM hbh.rooms WHERE code='P3-R2';

-- accounts
INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
       u.username, u.name, u.utype, u.mobile
FROM (VALUES
       ('p3.therapist', 'أخصائي اختبار ٣',  'THERAPIST', '+201300000001'),
       ('p3.other',     'أخصائي آخر',       'THERAPIST', '+201300000002'),
       ('p3.guardian',  'ولي أمر اختبار ٣', 'GUARDIAN',  '+201300000003'),
       -- ADDED FOR 0117. A THIRD therapist, free and on the rota.
       --
       -- The suite had two, and neither could produce the hour this
       -- feature exists for: one is busy with the child, and the other
       -- is ON_LEAVE, so a slot asked against them comes back
       -- THERAPIST_ON_LEAVE. A refusal for the wrong reason proves
       -- nothing, and a fixture that cannot produce a case cannot test
       -- it - which is why this account exists rather than the section
       -- below making do.
       ('p3.consult',   'أخصائي الاستشارات', 'THERAPIST', '+201300000004')
     ) AS u(username, name, utype, mobile);

INSERT INTO hbh_test.fx (k, v) SELECT 'user_th',   user_id FROM hbh.users WHERE username='p3.therapist';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_oth',  user_id FROM hbh.users WHERE username='p3.other';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_gd',   user_id FROM hbh.users WHERE username='p3.guardian';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_cons', user_id FROM hbh.users WHERE username='p3.consult';

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT f.v, r.role_id
FROM   hbh_test.fx f
JOIN   hbh.roles r ON r.center_id = (SELECT v FROM hbh_test.fx WHERE k='center')
WHERE  (f.k IN ('user_th','user_oth','user_cons') AND r.code = 'THERAPIST')
   OR  (f.k = 'user_gd'                           AND r.code = 'GUARDIAN');

-- therapists
INSERT INTO hbh.therapists (center_id, branch_id, user_id, full_name_ar, status)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_th'), 'أخصائي اختبار ٣', 'ACTIVE'),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_oth'), 'أخصائي في إجازة', 'ON_LEAVE'),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_cons'), 'أخصائي الاستشارات', 'ACTIVE');
INSERT INTO hbh_test.fx (k, v) SELECT 'th', therapist_id FROM hbh.therapists WHERE full_name_ar='أخصائي اختبار ٣';
INSERT INTO hbh_test.fx (k, v) SELECT 'th_leave', therapist_id FROM hbh.therapists WHERE full_name_ar='أخصائي في إجازة';
INSERT INTO hbh_test.fx (k, v) SELECT 'th_cons', therapist_id FROM hbh.therapists WHERE full_name_ar='أخصائي الاستشارات';

-- The therapist delivers SPEECH and not OT, so the mismatch has
-- something real to catch. The consultation therapist delivers it too,
-- or every slot asked against them answers THERAPIST_SERVICE_MISMATCH
-- before reaching anything this suite is about.
-- th_cons delivers BOTH: the consultation, which is what they are here
-- for, and speech - so section 3b can ask for a therapy service with no
-- room and be refused for THAT reason rather than for a mismatch.
INSERT INTO hbh.therapist_services (therapist_id, service_id)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='th'),      (SELECT v FROM hbh_test.fx WHERE k='svc_speech')),
       ((SELECT v FROM hbh_test.fx WHERE k='th_cons'), (SELECT v FROM hbh_test.fx WHERE k='svc_speech')),
       ((SELECT v FROM hbh_test.fx WHERE k='th_cons'), (SELECT v FROM hbh_test.fx WHERE k='svc_consult'));

-- Sunday to Thursday, 09:00 to 17:00. Egypt rests Friday and Saturday.
INSERT INTO hbh.therapist_working_hours (center_id, therapist_id, weekday, start_time, end_time)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), f.v,
       d, TIME '09:00', TIME '17:00'
FROM unnest(ARRAY[7,1,2,3,4]::smallint[]) AS d,
     hbh_test.fx f
WHERE f.k IN ('th', 'th_cons');

-- children and a guardian linked to one of them
INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P3-A', 'طفل اختبار ٣ أ', DATE '2020-05-04', 'M'),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P3-B', 'طفل اختبار ٣ ب', DATE '2021-01-19', 'F');
INSERT INTO hbh_test.fx (k, v) SELECT 'child_a', child_id FROM hbh.children WHERE child_no='P3-A';
INSERT INTO hbh_test.fx (k, v) SELECT 'child_b', child_id FROM hbh.children WHERE child_no='P3-B';

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_gd'), 'ولي أمر اختبار ٣', '+201300000003');
INSERT INTO hbh_test.fx (k, v) SELECT 'gd', guardian_id FROM hbh.guardians WHERE mobile='+201300000003';

INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='gd'), (SELECT v FROM hbh_test.fx WHERE k='child_a'), 'FATHER', true);

-- A SECOND FAMILY, ADDED FOR 0121, and it is the point of the door
-- checks rather than scenery.
--
-- The suite had one guardian, on child_a. Every consultation booked here
-- is child_a's, so "somebody else's family cannot get in" had nobody to
-- ask it with - and the first attempt at that check used a guardian who
-- turned out to be the child's OTHER parent, which is a person who
-- SHOULD get in. It passed, and proved nothing.
INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'p3.stranger', 'ولي أمر أسرة أخرى', 'GUARDIAN', '+201300000005');
INSERT INTO hbh_test.fx (k, v) SELECT 'user_str', user_id FROM hbh.users WHERE username='p3.stranger';

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT (SELECT v FROM hbh_test.fx WHERE k='user_str'), r.role_id
FROM hbh.roles r WHERE r.center_id = (SELECT v FROM hbh_test.fx WHERE k='center') AND r.code = 'GUARDIAN';

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_str'), 'ولي أمر أسرة أخرى', '+201300000005');
INSERT INTO hbh_test.fx (k, v) SELECT 'gd_str', guardian_id FROM hbh.guardians WHERE mobile='+201300000005';

INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='gd_str'), (SELECT v FROM hbh_test.fx WHERE k='child_b'), 'FATHER', true);

-- Caseload for child A only. Child B is deliberately left off it, so
-- the caseload refusal has a case to refuse.
INSERT INTO hbh.caseload (center_id, therapist_id, child_id, service_id, is_primary_flg)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='th'),
        (SELECT v FROM hbh_test.fx WHERE k='child_a'), (SELECT v FROM hbh_test.fx WHERE k='svc_speech'), true);

-- ---------------------------------------------------------------------
-- The fixture, asserted BY NAME.
--
-- Three phases running in the Oracle system lost a round trip to one
-- forgotten piece of setup - the caseload once, the working hours
-- twice - each surfacing dozens of tests later as a confusing refusal
-- from correct code. The last check here is the important one: one
-- real validate_slot call, proving the centre can actually take a
-- booking before a single rule is tested.
-- ---------------------------------------------------------------------
CALL hbh_test.chk('fixture', 'migration 0005 recorded',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0005') $q$);

CALL hbh_test.chk('fixture', 'three services exist',
  $q$ SELECT count(*) = 3 FROM hbh.services WHERE code LIKE 'P3-%' $q$);

-- THE FLAGS ARE ASSERTED BY NAME, before anything depends on them. Both
-- default to true, so a consultation row that was inserted without them
-- would look like an ordinary therapy service - and every check in
-- section 3b would then be refused for a reason that had nothing to do
-- with what it was testing.
CALL hbh_test.chk('fixture', 'and the consultation opens no session and wants no caseload',
  $q$ SELECT NOT creates_session_flg AND NOT needs_caseload_flg
      FROM hbh.services WHERE code = 'P3-CONSULT' $q$);

CALL hbh_test.chk('fixture', 'while the therapy services do both',
  $q$ SELECT bool_and(creates_session_flg AND needs_caseload_flg)
      FROM hbh.services WHERE code IN ('P3-SPEECH','P3-OT') $q$);

CALL hbh_test.chk('fixture', 'two rooms exist',
  $q$ SELECT count(*) = 2 FROM hbh.rooms WHERE code LIKE 'P3-%' $q$);

CALL hbh_test.chk('fixture', 'the therapist is ACTIVE and linked to an account',
  $q$ SELECT status = 'ACTIVE' AND user_id IS NOT NULL FROM hbh.therapists
      WHERE therapist_id = (SELECT v FROM hbh_test.fx WHERE k='th') $q$);

CALL hbh_test.chk('fixture', 'the therapist delivers the speech service',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.therapist_services
        WHERE therapist_id = (SELECT v FROM hbh_test.fx WHERE k='th')
          AND service_id   = (SELECT v FROM hbh_test.fx WHERE k='svc_speech')) $q$);

CALL hbh_test.chk('fixture', 'the therapist has five working days',
  $q$ SELECT count(*) = 5 FROM hbh.therapist_working_hours
      WHERE therapist_id = (SELECT v FROM hbh_test.fx WHERE k='th') $q$);

CALL hbh_test.chk('fixture', 'child A is on the caseload and child B is not',
  $q$ SELECT count(*) FILTER (WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child_a')) = 1
         AND count(*) FILTER (WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child_b')) = 0
      FROM hbh.caseload WHERE therapist_id = (SELECT v FROM hbh_test.fx WHERE k='th') $q$);

CALL hbh_test.chk('fixture', 'the base slot falls on a working day',
  $q$ SELECT extract(isodow FROM ((SELECT v FROM hbh_test.fxt WHERE k='slot_start') AT TIME ZONE 'Africa/Cairo')) = 1 $q$);

-- The fixture assertion that matters most.
CALL hbh_test.chk_reason('fixture', 'the centre can actually take a booking',
  $q$ SELECT reason FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'),
        (SELECT v FROM hbh_test.fx WHERE k='child_a'),
        (SELECT v FROM hbh_test.fx WHERE k='th'),
        (SELECT v FROM hbh_test.fx WHERE k='room1'),
        (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_end')) $q$, 'OK');

-- =====================================================================
-- 1. THE STATE MACHINE
-- =====================================================================
CALL hbh_test.chk('machine', 'BOOKED to CONFIRMED is legal',
  $q$ SELECT hbh.legal_appointment_transition('BOOKED','CONFIRMED') $q$);

CALL hbh_test.chk('machine', 'CONFIRMED to CHECKED_IN is legal',
  $q$ SELECT hbh.legal_appointment_transition('CONFIRMED','CHECKED_IN') $q$);

CALL hbh_test.chk('machine', 'BOOKED straight to COMPLETED is not',
  $q$ SELECT NOT hbh.legal_appointment_transition('BOOKED','COMPLETED') $q$);

CALL hbh_test.chk('machine', 'a cancelled appointment cannot be revived',
  $q$ SELECT NOT hbh.legal_appointment_transition('CANCELLED','BOOKED') $q$);

-- The Oracle version answered TRUE here, which was harmless inside the
-- API and a lie on a menu: it offered "confirm" for an already
-- confirmed appointment and the press looked successful.
CALL hbh_test.chk('machine', 'a status to ITSELF is not a legal move',
  $q$ SELECT NOT hbh.legal_appointment_transition('CONFIRMED','CONFIRMED') $q$);

CALL hbh_test.chk('machine', 'a session may only end from IN_PROGRESS',
  $q$ SELECT hbh.legal_session_transition('IN_PROGRESS','COMPLETED')
         AND hbh.legal_session_transition('IN_PROGRESS','ABORTED')
         AND NOT hbh.legal_session_transition('COMPLETED','IN_PROGRESS') $q$);

-- =====================================================================
-- 2. SLOT VALIDATION
-- =====================================================================
CALL hbh_test.chk_reason('slot', 'an end before its start is refused',
  $q$ SELECT reason FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child_a'),
        (SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='room1'),
        (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_end'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_start')) $q$, 'BAD_WINDOW');

CALL hbh_test.chk_reason('slot', 'the weekend is refused',
  $q$ SELECT reason FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child_a'),
        (SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='room1'),
        (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
        (SELECT v FROM hbh_test.fxt WHERE k='fri_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='fri_end')) $q$, 'WEEKEND');

CALL hbh_test.chk_reason('slot', 'a date in the past is refused',
  $q$ SELECT reason FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child_a'),
        (SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='room1'),
        (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
        (SELECT v FROM hbh_test.fxt WHERE k='past_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='past_end')) $q$, 'IN_THE_PAST');

CALL hbh_test.chk_reason('slot', 'a therapist on leave is refused',
  $q$ SELECT reason FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child_a'),
        (SELECT v FROM hbh_test.fx WHERE k='th_leave'), (SELECT v FROM hbh_test.fx WHERE k='room1'),
        (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_end')) $q$, 'THERAPIST_UNAVAILABLE');

CALL hbh_test.chk_reason('slot', 'a service the therapist does not deliver is refused',
  $q$ SELECT reason FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child_a'),
        (SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='room1'),
        (SELECT v FROM hbh_test.fx WHERE k='svc_ot'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_end')) $q$, 'THERAPIST_SERVICE_MISMATCH');

CALL hbh_test.chk_reason('slot', 'before the therapist starts work is refused',
  $q$ SELECT reason FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child_a'),
        (SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='room1'),
        (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
        (SELECT v FROM hbh_test.fxt WHERE k='early_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='early_end')) $q$, 'OUTSIDE_WORKING_HOURS');

-- =====================================================================
-- 3. BOOKING
-- =====================================================================
CALL hbh_test.chk('book', 'the first booking succeeds',
  $q$ WITH b AS (
        SELECT hbh.book_appointment(
          (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
          (SELECT v FROM hbh_test.fx WHERE k='child_a'), (SELECT v FROM hbh_test.fx WHERE k='th'),
          (SELECT v FROM hbh_test.fx WHERE k='room1'),   (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
          (SELECT v FROM hbh_test.fxt WHERE k='slot_start'),
          (SELECT v FROM hbh_test.fxt WHERE k='slot_end')) AS id),
           i AS (INSERT INTO hbh_test.fx (k, v) SELECT 'appt_a', id FROM b RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('book', 'it carries a formatted appointment number',
  $q$ SELECT appointment_no ~ ('^APT-' || extract(year FROM now())::integer || '-[0-9]{5}$')
      FROM hbh.appointments WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_a') $q$);

CALL hbh_test.chk('book', 'it starts life BOOKED',
  $q$ SELECT status = 'BOOKED' FROM hbh.appointments
      WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_a') $q$);

-- The same slot, three different ways, each refused for its own reason.
CALL hbh_test.chk_reason('book', 'the therapist is now busy in that slot',
  $q$ SELECT reason FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child_b'),
        (SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='room2'),
        (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_end')) $q$, 'THERAPIST_BUSY');

CALL hbh_test.chk_reason('book', 'the child is now busy in that slot',
  $q$ SELECT reason FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child_a'),
        (SELECT v FROM hbh_test.fx WHERE k='th_leave'), (SELECT v FROM hbh_test.fx WHERE k='room2'),
        (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_end')) $q$, 'THERAPIST_UNAVAILABLE');

-- An overlap of a single minute is still an overlap.
CALL hbh_test.chk_raises('book', 'booking the same slot again is refused with HB021',
  $q$ SELECT hbh.book_appointment(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='child_b'), (SELECT v FROM hbh_test.fx WHERE k='th'),
        (SELECT v FROM hbh_test.fx WHERE k='room2'),   (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_end')) $q$, 'HB021');

CALL hbh_test.chk('book', 'a later slot on the same day is free',
  $q$ SELECT ok FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child_a'),
        (SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='room1'),
        (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot2_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot2_end')) $q$);

-- The exclusion constraint is the guarantee, so it is tested directly
-- and not only through the function that reports it nicely.
CALL hbh_test.chk_raises('book', 'a direct INSERT of an overlapping row raises 23P01',
  $q$ INSERT INTO hbh.appointments (center_id, branch_id, appointment_no, child_id,
                                    therapist_id, room_id, service_id, starts_at, ends_at)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
              'P3-DIRECT-1', (SELECT v FROM hbh_test.fx WHERE k='child_b'),
              (SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='room2'),
              (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
              (SELECT v FROM hbh_test.fxt WHERE k='slot_start'),
              (SELECT v FROM hbh_test.fxt WHERE k='slot_end')) $q$, '23P01');

-- =====================================================================
-- 3b. AN APPOINTMENT DELIVERED OVER VIDEO - 0117
--
-- The hour this feature exists for, in one sentence from the
-- architect's note:
--
--   "أب يستشير أخصائية التخاطب بينما ابنه في جلسة تكامل حسّي"
--
-- A father on a video call about his son, WHILE the son is in a
-- therapy session with somebody else. Two appointments, one child, one
-- hour - and until 0117 the child exclusion refused the second one.
--
-- WHAT EACH LEVEL IS FOR. The constraint is the guarantee and is tested
-- with a direct INSERT; validate_slot is the explanation and is tested
-- through its reason. They are checked separately because they can
-- drift apart, and a screen that says CHILD_BUSY over a booking the
-- index then accepts is worse than either being wrong alone.
-- =====================================================================

-- The three refusals that are about the shape of the request, before
-- any diary is consulted.
CALL hbh_test.chk_reason('mode', 'an in-person appointment needs a room',
  $q$ SELECT reason FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child_b'),
        (SELECT v FROM hbh_test.fx WHERE k='th_cons'), NULL,
        (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot2_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot2_end'), NULL, 'IN_PERSON') $q$, 'ROOM_REQUIRED');

-- THE ONE THAT KEEPS A TREATMENT ROOM FREE. An online appointment
-- holding a room would occupy it against ex_appointments_room for an
-- hour nobody is in it, and nothing on the screen would explain why
-- reception cannot book it.
CALL hbh_test.chk_reason('mode', 'an online appointment may not hold a room',
  $q$ SELECT reason FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child_b'),
        (SELECT v FROM hbh_test.fx WHERE k='th_cons'), (SELECT v FROM hbh_test.fx WHERE k='room2'),
        (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot2_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot2_end'), NULL, 'ONLINE') $q$, 'ROOM_NOT_ALLOWED');

CALL hbh_test.chk_reason('mode', 'a mode the schema does not know is refused by name',
  $q$ SELECT reason FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child_b'),
        (SELECT v FROM hbh_test.fx WHERE k='th_cons'), NULL,
        (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot2_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot2_end'), NULL, 'ZOOM') $q$, 'BAD_DELIVERY_MODE');

-- A REVERSED WINDOW STILL ANSWERS FIRST. The mode checks were added
-- above the range build, and the range build already had to stay below
-- the BAD_WINDOW guard - a DECLARE initialiser there once raised 22000
-- instead. Asserted so the order cannot be tidied away.
CALL hbh_test.chk_reason('mode', 'and a reversed window is still answered before the mode',
  $q$ SELECT reason FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child_b'),
        (SELECT v FROM hbh_test.fx WHERE k='th_cons'), NULL,
        (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot2_end'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot2_start'), NULL, 'ZOOM') $q$, 'BAD_WINDOW');

-- ---------------------------------------------------------------------
-- THE HOUR ITSELF. child_a is already in an in-person session with
-- 'th' at slot_start - booked at the top of section 3.
-- ---------------------------------------------------------------------
-- A THERAPY SERVICE CANNOT BE BOOKED WITHOUT A ROOM - 0118.
--
-- hbh.therapy_sessions.room_id is NOT NULL, so a service that opens a
-- session needs somewhere for it to happen. 0117 left this to
-- start_session, which is the expensive half of the discovery: at
-- booking it is a typo somebody fixes, and at start it is a family in a
-- room.
CALL hbh_test.chk_reason('mode', 'a service that opens a session cannot be booked with no room',
  $q$ SELECT reason FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child_b'),
        (SELECT v FROM hbh_test.fx WHERE k='th_cons'), NULL,
        (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot2_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot2_end'), NULL, 'ONLINE') $q$, 'SERVICE_NEEDS_ROOM');

-- And the guarantee behind that explanation, asserted on the table.
CALL hbh_test.chk_raises('mode', 'and the schema refuses it too, by name',
  $q$ INSERT INTO hbh.appointments (center_id, branch_id, appointment_no, child_id,
                                    therapist_id, room_id, service_id, starts_at, ends_at,
                                    delivery_mode)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
              'P3-MODE-4', (SELECT v FROM hbh_test.fx WHERE k='child_b'),
              (SELECT v FROM hbh_test.fx WHERE k='th_cons'), NULL,
              (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
              (SELECT v FROM hbh_test.fxt WHERE k='slot2_start'),
              (SELECT v FROM hbh_test.fxt WHERE k='slot2_end'),
              'ONLINE') $q$, 'HB251');

CALL hbh_test.chk('mode', 'the child being in a session does not block a consultation about them',
  $q$ SELECT ok FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child_a'),
        (SELECT v FROM hbh_test.fx WHERE k='th_cons'), NULL,
        (SELECT v FROM hbh_test.fx WHERE k='svc_consult'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_end'), NULL, 'ONLINE') $q$);

CALL hbh_test.chk('mode', 'and it books, with no room and the mode recorded',
  $q$ WITH b AS (
        SELECT hbh.book_appointment(
          (SELECT v FROM hbh_test.fx WHERE k='center'), NULL,
          (SELECT v FROM hbh_test.fx WHERE k='child_a'), (SELECT v FROM hbh_test.fx WHERE k='th_cons'),
          NULL, (SELECT v FROM hbh_test.fx WHERE k='svc_consult'),
          (SELECT v FROM hbh_test.fxt WHERE k='slot_start'),
          (SELECT v FROM hbh_test.fxt WHERE k='slot_end'),
          NULL, 'ONLINE') AS id),
           i AS (INSERT INTO hbh_test.fx (k, v) SELECT 'appt_online', id FROM b RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

-- Read back in a SEPARATE statement: a CTE that modifies data is
-- invisible to the rest of its own statement, so joining to the row the
-- line above inserted would have compared a snapshot with itself.
CALL hbh_test.chk('mode', 'the row says ONLINE and holds no room',
  $q$ SELECT delivery_mode = 'ONLINE' AND room_id IS NULL
      FROM hbh.appointments WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_online') $q$);

-- ---------------------------------------------------------------------
-- AND THE RULE STILL BITES. The exclusion constraint lost ONLINE, not
-- its teeth: a second IN_PERSON appointment for the same child in the
-- same hour is refused exactly as before.
--
-- A FREE THERAPIST AND A FREE ROOM ARE BOTH REQUIRED FOR THIS TO PROVE
-- ANYTHING. Written first with the busy therapist, it was refused by
-- ex_appointments_therapist - a green check that said nothing about the
-- constraint it claimed to be testing.
-- ---------------------------------------------------------------------
CALL hbh_test.chk_raises('mode', 'a second IN-PERSON appointment for that child is still refused',
  $q$ INSERT INTO hbh.appointments (center_id, branch_id, appointment_no, child_id,
                                    therapist_id, room_id, service_id, starts_at, ends_at,
                                    delivery_mode)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
              'P3-MODE-1', (SELECT v FROM hbh_test.fx WHERE k='child_a'),
              (SELECT v FROM hbh_test.fx WHERE k='th_leave'), (SELECT v FROM hbh_test.fx WHERE k='room2'),
              (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
              (SELECT v FROM hbh_test.fxt WHERE k='slot_start'),
              (SELECT v FROM hbh_test.fxt WHERE k='slot_end'),
              'IN_PERSON') $q$, '23P01');

-- The therapist constraint is NOT touched by any of this, and that is
-- the whole reason a consultation lives in this table: it takes an hour
-- of somebody's day exactly as a session does.
CALL hbh_test.chk_reason('mode', 'the consultation now occupies its therapist',
  $q$ SELECT reason FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child_b'),
        (SELECT v FROM hbh_test.fx WHERE k='th_cons'), NULL,
        (SELECT v FROM hbh_test.fx WHERE k='svc_consult'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_end'), NULL, 'ONLINE') $q$, 'THERAPIST_BUSY');

-- The two halves of ck_appointments_room_mode, asserted against the
-- table rather than only through the function that explains them.
CALL hbh_test.chk_raises('mode', 'the schema itself refuses an online row holding a room',
  $q$ INSERT INTO hbh.appointments (center_id, branch_id, appointment_no, child_id,
                                    therapist_id, room_id, service_id, starts_at, ends_at,
                                    delivery_mode)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
              'P3-MODE-2', (SELECT v FROM hbh_test.fx WHERE k='child_b'),
              (SELECT v FROM hbh_test.fx WHERE k='th_cons'), (SELECT v FROM hbh_test.fx WHERE k='room2'),
              (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
              (SELECT v FROM hbh_test.fxt WHERE k='slot2_start'),
              (SELECT v FROM hbh_test.fxt WHERE k='slot2_end'),
              'ONLINE') $q$, '23514');

-- WITH THE CONSULTATION SERVICE, AND THAT IS THE POINT OF THIS LINE.
--
-- Written with the speech service it came back HB251, not 23514 - a
-- BEFORE trigger runs before a CHECK constraint, so the booking guard
-- answered first and hid the constraint entirely. Same family as the
-- lesson in CLAUDE.md about a BEFORE trigger hiding an RLS refusal: the
-- business rule replies, and the check underneath is never reached.
--
-- A service that opens no session lets the trigger return early, so the
-- constraint is the only thing left to refuse it - which is what this
-- check claims to be testing.
CALL hbh_test.chk_raises('mode', 'and an in-person row with none',
  $q$ INSERT INTO hbh.appointments (center_id, branch_id, appointment_no, child_id,
                                    therapist_id, room_id, service_id, starts_at, ends_at,
                                    delivery_mode)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
              'P3-MODE-3', (SELECT v FROM hbh_test.fx WHERE k='child_b'),
              (SELECT v FROM hbh_test.fx WHERE k='th_cons'), NULL,
              (SELECT v FROM hbh_test.fx WHERE k='svc_consult'),
              (SELECT v FROM hbh_test.fxt WHERE k='slot2_start'),
              (SELECT v FROM hbh_test.fxt WHERE k='slot2_end'),
              'IN_PERSON') $q$, '23514');

-- =====================================================================
-- 3c. THE ROOM, AND THE DOOR - 0120, 0121
--
-- appt_online was booked a moment ago, so a room already exists: the
-- trigger opens one for every ONLINE appointment, because there is more
-- than one way an appointment is created and a consultation with no room
-- is a family pressing a button that does nothing.
--
-- WHAT THE DOOR IS FOR. A consultation's video cannot be proxied - the
-- family's browser talks to the provider itself - so the pass reaches
-- the browser and CANNOT BE CALLED BACK once issued. Everything below is
-- what narrows that: the appointment is yours, it is paid, the hour has
-- come, and the pass dies quickly.
-- =====================================================================
CALL hbh_test.chk('door', 'booking an online consultation opened a room',
  $q$ SELECT status = 'READY' AND provider IS NOT NULL FROM hbh.meetings
      WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_online') $q$);

-- NOT THE APPOINTMENT NUMBER, and the constraint says so too. With a
-- provider whose rooms exist by being joined, a name anybody can work
-- out by counting is an open door.
CALL hbh_test.chk('door', 'and its name is a secret, not a number',
  $q$ SELECT room_ref ~ '^[a-z0-9]{24,64}$'
         AND room_ref NOT LIKE '%' || (SELECT appointment_no FROM hbh.appointments
                                        WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_online')) || '%'
      FROM hbh.meetings
      WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_online') $q$);

SET ROLE hbh_app;
SET hbh.user_id = 'p3.guardian';

-- BOOKED means the invoice has not been paid. Asking the status here
-- asks about the money without this function knowing what an invoice is.
CALL hbh_test.chk_raises('door', 'an unpaid consultation does not open - HB253',
  $q$ SELECT * FROM hbh.authorize_meeting_entry(
        (SELECT v FROM hbh_test.fx WHERE k='appt_online')) $q$, 'HB253');

RESET ROLE;
RESET hbh.user_id;

CALL hbh_test.chk('door', 'paying confirms it',
  $q$ WITH u AS (UPDATE hbh.appointments SET status = 'CONFIRMED'
                 WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_online') RETURNING 1)
      SELECT count(*) = 1 FROM u $q$);

SET ROLE hbh_app;
SET hbh.user_id = 'p3.guardian';

-- The slot this suite books is days away, so the door is shut on time
-- rather than on permission - and the code says which.
CALL hbh_test.chk_raises('door', 'but the hour has not come - HB252',
  $q$ SELECT * FROM hbh.authorize_meeting_entry(
        (SELECT v FROM hbh_test.fx WHERE k='appt_online')) $q$, 'HB252');

RESET ROLE;
RESET hbh.user_id;

-- MOVING THE APPOINTMENT MOVES THE DOOR, which is the other half of the
-- trigger and the reason a rescheduled consultation is enterable at all.
-- Done as an UPDATE rather than by editing the meeting directly: the
-- claim is that the door follows the appointment.
-- TWO STATEMENTS, AND THE FIRST DRAFT WAS ONE.
--
-- Written as `WITH u AS (UPDATE appointments ...) SELECT ... FROM
-- meetings`, the room the UPDATE's own trigger had just moved was
-- invisible to the outer SELECT: both halves read the snapshot taken
-- when the statement began. The CTE rule in CLAUDE.md, arriving through
-- a trigger this time instead of a literal INSERT - which is what made
-- it look like the trigger had not fired.
UPDATE hbh.appointments
   SET starts_at = now() + interval '5 minutes',
       ends_at   = now() + interval '35 minutes'
 WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_online');

CALL hbh_test.chk('door', 'moving the appointment moves the door with it',
  $q$ SELECT opens_at <= now() AND expires_at > now() FROM hbh.meetings
       WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_online') $q$);

SET ROLE hbh_app;
SET hbh.user_id = 'p3.guardian';

CALL hbh_test.chk('door', 'now the family is let in, and is NOT a moderator',
  $q$ SELECT NOT moderator_flg AND room_ref ~ '^[a-z0-9]{24,64}$'
      FROM hbh.authorize_meeting_entry((SELECT v FROM hbh_test.fx WHERE k='appt_online')) $q$);

-- Never past the door, whatever MEETING_TOKEN_TTL_MIN says.
CALL hbh_test.chk('door', 'and the pass cannot outlive the consultation',
  $q$ SELECT a.expires_at <= m.expires_at
      FROM hbh.authorize_meeting_entry((SELECT v FROM hbh_test.fx WHERE k='appt_online')) a
      JOIN hbh.meetings m ON m.appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_online') $q$);

-- THE BARRIER, AND IT IS HANDED THE REAL IDENTIFIER.
--
-- Written first with a subquery for the id, the stranger's own RLS hid
-- the appointment, the subquery returned NULL, and the function refused
-- a NULL rather than refusing THEM. Green, and about nothing. The id is
-- read from hbh_test.fx - which every session can see - so the only
-- thing left to refuse is whose appointment it is.
--
-- And it answers HB021, the same as "no such appointment": telling a
-- stranger it exists but is not theirs is telling them it exists.
SET hbh.user_id = 'p3.stranger';

-- HB051 AND NOT HB021, AND THE DIFFERENCE IS THE WHOLE POINT.
--
-- 0121 raised HB021 here, which book_appointment already raises for a
-- refused slot - so the API answered 409 SLOT_UNAVAILABLE to a family
-- asking about somebody else's appointment. Wrong sentence, and it
-- implies a slot exists, which is the one thing this refusal must not
-- do. HB051 is what this schema uses for a row that is not there or not
-- yours, and the API answers it 404. Corrected in 0124, found by calling
-- the endpoint rather than by reading it.
CALL hbh_test.chk_raises('door', 'another family holding the real id is refused as if it did not exist',
  $q$ SELECT * FROM hbh.authorize_meeting_entry(
        (SELECT v FROM hbh_test.fx WHERE k='appt_online')) $q$, 'HB051');

-- The therapist runs the room. A guardian never does.
SET hbh.user_id = 'p3.consult';

CALL hbh_test.chk('door', 'the therapist is the moderator',
  $q$ SELECT moderator_flg FROM hbh.authorize_meeting_entry(
        (SELECT v FROM hbh_test.fx WHERE k='appt_online')) $q$);

-- The evidence row: who took a pass, for which room, and for how long.
CALL hbh_test.chk('door', 'issuing a pass is recorded',
  $q$ WITH r AS (
        SELECT hbh.record_meeting_token(
          (SELECT meeting_id FROM hbh.meetings
            WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_online')),
          public.digest('p3-pass', 'sha256'), true,
          now() + interval '15 minutes', '196.0.0.9'::inet) AS id)
      SELECT (SELECT count(*) FROM r) = 1 $q$);

-- THE CEILING IS ON THE ROW, not in the caller. Nothing can revoke what
-- this issues, so the window is the only control there is.
CALL hbh_test.chk_raises('door', 'and a pass longer than the ceiling is refused by the table itself',
  $q$ SELECT hbh.record_meeting_token(
        (SELECT meeting_id FROM hbh.meetings
          WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_online')),
        public.digest('p3-too-long', 'sha256'), false,
        now() + interval '4 hours', NULL) $q$, '23514');

RESET ROLE;
RESET hbh.user_id;

-- A CLOSED ROOM TURNS PEOPLE AWAY.
--
-- Forced directly, with the appointment left CONFIRMED, and that is the
-- only way to reach this branch. Cancelling closes the room AND changes
-- the status, and the status is asked first - so a cancelled
-- consultation answers HB253, which is true and is a different rule.
-- Asserting HB252 there would have been asserting nothing: the first
-- draft did exactly that and came back HB253.
--
-- The branch still earns its place. The room can be closed while the
-- appointment stands - a provider failure, or an operator shutting one
-- room - and this is what happens then.
UPDATE hbh.meetings
   SET status = 'CLOSED', closed_at = now(), closed_reason = 'اختبار الإغلاق المباشر'
 WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_online');

SET ROLE hbh_app;
SET hbh.user_id = 'p3.guardian';

CALL hbh_test.chk_raises('door', 'a closed room turns away a family whose appointment still stands - HB252',
  $q$ SELECT * FROM hbh.authorize_meeting_entry(
        (SELECT v FROM hbh_test.fx WHERE k='appt_online')) $q$, 'HB252');

RESET ROLE;
RESET hbh.user_id;

-- AND NOW THE ORDINARY PATH: cancelling. Two statements again, because
-- the row the trigger touches is not visible inside the statement that
-- fires it.
UPDATE hbh.meetings SET status = 'READY', closed_at = NULL, closed_reason = NULL
 WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_online');

UPDATE hbh.appointments
   SET status = 'CANCELLED', cancel_reason = 'اختبار الإغلاق'
 WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_online');

-- A pass already in a browser cannot be called back, so closing the row
-- is the only thing that stops the NEXT one being issued.
CALL hbh_test.chk('door', 'cancelling the appointment closes its room, with a reason',
  $q$ SELECT status = 'CLOSED' AND closed_reason = 'APPOINTMENT_CANCELLED'
      FROM hbh.meetings
      WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_online') $q$);

SET ROLE hbh_app;
SET hbh.user_id = 'p3.guardian';

-- The status is asked before the room, so this is HB253 - and saying so
-- here is the difference between a test and a hope.
CALL hbh_test.chk_raises('door', 'and a cancelled consultation is refused on its status - HB253',
  $q$ SELECT * FROM hbh.authorize_meeting_entry(
        (SELECT v FROM hbh_test.fx WHERE k='appt_online')) $q$, 'HB253');

RESET ROLE;
RESET hbh.user_id;

-- =====================================================================
-- 4. TWO RECEPTIONISTS, ONE SLOT
--
-- The test the whole design exists for.
--
-- A second connection books the free slot and does NOT commit. This
-- connection then tries the same slot. If the constraint were advisory,
-- this would succeed. Because it is an index, this transaction WAITS
-- for the other one - and lock_timeout turns that wait into 55P03,
-- which is the proof: it was made to queue, not allowed through.
-- =====================================================================
SELECT public.dblink_connect('hbh_race', 'dbname=' || current_database() || ' user=' || current_user);
SELECT public.dblink_exec('hbh_race', 'BEGIN');
SELECT public.dblink_exec('hbh_race', format(
  $f$INSERT INTO hbh.appointments (center_id, branch_id, appointment_no, child_id,
                                   therapist_id, room_id, service_id, starts_at, ends_at)
     VALUES (%s, %s, 'P3-RACE-1', %s, %s, %s, %s, %L, %L)$f$,
  (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
  (SELECT v FROM hbh_test.fx WHERE k='child_a'), (SELECT v FROM hbh_test.fx WHERE k='th'),
  (SELECT v FROM hbh_test.fx WHERE k='room1'),   (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
  (SELECT v FROM hbh_test.fxt WHERE k='slot2_start'), (SELECT v FROM hbh_test.fxt WHERE k='slot2_end')));

SET lock_timeout = '2s';

CALL hbh_test.chk_raises('race', 'the second booking of a slot held by an open transaction WAITS',
  $q$ INSERT INTO hbh.appointments (center_id, branch_id, appointment_no, child_id,
                                    therapist_id, room_id, service_id, starts_at, ends_at)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
              'P3-RACE-2', (SELECT v FROM hbh_test.fx WHERE k='child_b'),
              (SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='room2'),
              (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
              (SELECT v FROM hbh_test.fxt WHERE k='slot2_start'),
              (SELECT v FROM hbh_test.fxt WHERE k='slot2_end')) $q$, '55P03');

RESET lock_timeout;

-- Let the other transaction commit, then the same attempt is refused
-- outright rather than made to wait.
SELECT public.dblink_exec('hbh_race', 'COMMIT');

CALL hbh_test.chk_raises('race', 'and once that transaction commits, it is refused outright',
  $q$ INSERT INTO hbh.appointments (center_id, branch_id, appointment_no, child_id,
                                    therapist_id, room_id, service_id, starts_at, ends_at)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
              'P3-RACE-3', (SELECT v FROM hbh_test.fx WHERE k='child_b'),
              (SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='room2'),
              (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
              (SELECT v FROM hbh_test.fxt WHERE k='slot2_start'),
              (SELECT v FROM hbh_test.fxt WHERE k='slot2_end')) $q$, '23P01');

CALL hbh_test.chk('race', 'exactly one of the two attempts survived',
  $q$ SELECT count(*) = 1 FROM hbh.appointments WHERE appointment_no LIKE 'P3-RACE-%' $q$);

SELECT public.dblink_disconnect('hbh_race');

-- =====================================================================
-- 5. THE STATUS MACHINE ON REAL ROWS
-- =====================================================================
CALL hbh_test.chk('status', 'BOOKED to CONFIRMED is accepted',
  $q$ WITH u AS (UPDATE hbh.appointments SET status = 'CONFIRMED'
                 WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_a') RETURNING 1)
      SELECT count(*) = 1 FROM u $q$);

CALL hbh_test.chk_raises('status', 'CONFIRMED straight to COMPLETED raises HB020',
  $q$ UPDATE hbh.appointments SET status = 'COMPLETED'
      WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_a') $q$, 'HB020');

CALL hbh_test.chk('status', 'a history row was written for every move so far',
  $q$ SELECT count(*) = 2 FROM hbh.appointment_status_history
      WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_a') $q$);

CALL hbh_test.chk('status', 'the history names both ends of the move',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.appointment_status_history
        WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_a')
          AND from_status = 'BOOKED' AND to_status = 'CONFIRMED') $q$);

CALL hbh_test.chk_raises('status', 'the history cannot be rewritten',
  $q$ UPDATE hbh.appointment_status_history SET to_status = 'CANCELLED'
      WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_a') $q$, 'HB001');

CALL hbh_test.chk_raises('status', 'a cancellation with no reason is refused',
  $q$ UPDATE hbh.appointments SET status = 'CANCELLED'
      WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_a') $q$, '23514');

-- =====================================================================
-- 6. SESSIONS
-- =====================================================================
--
-- AS THE THERAPIST, and not as nobody.
--
-- Migration 0087 gave hbh.start_session the authorization it shipped
-- without: SESSION.START, and whose appointment this is. Every check
-- below is about a BUSINESS rule - HB024 not checked in, HB022 already
-- started, HB023 not on the caseload - and each one is only reached by a
-- caller the function will speak to. Without an identity all four now
-- answer HB028, and a suite that accepted that would be asserting the
-- authorization gate four times and the rules it means to test zero.
--
-- p3.therapist is the user behind fx 'th', which is the therapist named
-- by appt_a AND by appt_b - so the caseload check at the end still fails
-- for the caseload reason and not for an ownership one.
SET hbh.user_id = 'p3.therapist';

CALL hbh_test.chk_raises('session', 'a session cannot start before the child is checked in',
  $q$ SELECT hbh.start_session((SELECT v FROM hbh_test.fx WHERE k='appt_a')) $q$, 'HB024');

CALL hbh_test.chk('session', 'checking in is accepted',
  $q$ WITH u AS (UPDATE hbh.appointments SET status = 'CHECKED_IN'
                 WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_a') RETURNING 1)
      SELECT count(*) = 1 FROM u $q$);

CALL hbh_test.chk('session', 'and then the session starts',
  $q$ WITH s AS (SELECT hbh.start_session((SELECT v FROM hbh_test.fx WHERE k='appt_a')) AS id),
           i AS (INSERT INTO hbh_test.fx (k, v) SELECT 'sess_a', id FROM s RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('session', 'it starts IN_PROGRESS with no end time',
  $q$ SELECT status = 'IN_PROGRESS' AND ended_at IS NULL FROM hbh.therapy_sessions
      WHERE session_id = (SELECT v FROM hbh_test.fx WHERE k='sess_a') $q$);

CALL hbh_test.chk_raises('session', 'a second session on the same appointment raises HB022',
  $q$ SELECT hbh.start_session((SELECT v FROM hbh_test.fx WHERE k='appt_a')) $q$, 'HB022');

-- ---------------------------------------------------------------------
-- A CONSULTATION DOES NOT OPEN A SESSION - 0117, then 0118
--
-- WHY THIS IS HERE AND NOT A NICETY. hbh.therapy_sessions.room_id is
-- NOT NULL. The moment appointments.room_id became nullable, this call
-- stopped being impossible and started being a raw 23502 from inside a
-- SECURITY DEFINER function - "null value in column room_id" shown to a
-- therapist who pressed Start.
--
-- WHAT THE REFUSAL IS ABOUT CHANGED UNDER THIS CHECK, and the check did
-- not. 0117 refused because the appointment was not IN_PERSON; 0118
-- refuses because the SERVICE does not open sessions, which is the rule
-- that was always meant. appt_online now uses svc_consult, so the same
-- HB250 comes back for the right reason - and it would come back for a
-- consultation held in a room, too, which the mode test never could.
--
-- AS ITS OWN THERAPIST. p3.consult is the user behind th_cons, who is
-- named by appt_online, so can_start_session is satisfied and HB028 is
-- not what comes back. Asserting the code rather than "it failed" is
-- the whole difference: an ownership refusal here would look identical
-- and prove nothing.
--
-- AND THE APPOINTMENT IS STILL BOOKED, WHICH IS THE SECOND HALF OF THE
-- CHECK. The status rule would also refuse it, with HB024. Getting
-- HB250 proves the mode is asked FIRST - so a therapist who checked a
-- consultation in is told "this is a consultation" rather than sent to
-- fix a status that was never the problem.
SET hbh.user_id = 'p3.consult';

CALL hbh_test.chk_raises('session', 'an online consultation refuses to become a session',
  $q$ SELECT hbh.start_session((SELECT v FROM hbh_test.fx WHERE k='appt_online')) $q$, 'HB250');

CALL hbh_test.chk('session', 'and no session row was left behind by the attempt',
  $q$ SELECT count(*) = 0 FROM hbh.therapy_sessions
      WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_online') $q$);

SET hbh.user_id = 'p3.therapist';

-- Booking is reception's verb, not a clinician's: the therapist identity
-- set above does not hold APPOINTMENT.BOOK and book_appointment answers
-- HB027. Dropped for the three set-up statements and taken up again for
-- the check that needs it.
RESET hbh.user_id;

-- The caseload gate, on its own appointment so the refusal cannot be
-- confused with any other rule.
CALL hbh_test.chk('session', 'a second appointment is booked for the child NOT on the caseload',
  $q$ WITH b AS (
        SELECT hbh.book_appointment(
          (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
          (SELECT v FROM hbh_test.fx WHERE k='child_b'), (SELECT v FROM hbh_test.fx WHERE k='th'),
          (SELECT v FROM hbh_test.fx WHERE k='room1'),   (SELECT v FROM hbh_test.fx WHERE k='svc_speech'),
          (SELECT v FROM hbh_test.fxt WHERE k='slot_start') + interval '4 hours',
          (SELECT v FROM hbh_test.fxt WHERE k='slot_end')   + interval '4 hours') AS id),
           i AS (INSERT INTO hbh_test.fx (k, v) SELECT 'appt_b', id FROM b RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

-- Two statements, not two CTEs. A row may be updated once per
-- statement: a second UPDATE of the same row in the same statement is
-- discarded, silently, and the row stops one step short of where the
-- test believes it is. Here that left the appointment CONFIRMED, and
-- the caseload test was then refused with HB024 instead of HB023 -
-- a refusal for the wrong reason, which proves nothing.
CALL hbh_test.chk('session', 'it is confirmed',
  $q$ WITH u AS (UPDATE hbh.appointments SET status = 'CONFIRMED'
                 WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_b') RETURNING 1)
      SELECT count(*) = 1 FROM u $q$);

CALL hbh_test.chk('session', 'and then checked in',
  $q$ WITH u AS (UPDATE hbh.appointments SET status = 'CHECKED_IN'
                 WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_b') RETURNING 1)
      SELECT count(*) = 1 FROM u $q$);

CALL hbh_test.chk('session', 'the appointment really is CHECKED_IN before the next test',
  $q$ SELECT status = 'CHECKED_IN' FROM hbh.appointments
      WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_b') $q$);

-- Named precisely. A Phase 5 test in the Oracle system believed it was
-- proving the check-in gate and was in fact being refused for a missing
-- caseload row - a refusal for the wrong reason proves nothing.
-- As the therapist again: this appointment names 'th' too, so the only
-- rule left to refuse it is the caseload one.
SET hbh.user_id = 'p3.therapist';

CALL hbh_test.chk_raises('session', 'a therapist not on the caseload cannot start it - HB023',
  $q$ SELECT hbh.start_session((SELECT v FROM hbh_test.fx WHERE k='appt_b')) $q$, 'HB023');

-- ---------------------------------------------------------------------
-- THE OTHER FLAG - 0118
--
-- needs_caseload_flg is the half that is easy to add and never prove.
-- The line above is the whole test for it: the SAME call, the SAME
-- appointment, the SAME therapist with no caseload row - and the only
-- thing that changed is the service's flag. Anything less would be
-- asserting that the flag exists, not that it does anything.
--
-- WHY THE FLAG IS FLIPPED ON svc_speech RATHER THAN USING svc_consult.
-- A consultation opens no session at all, so it would be refused by
-- HB250 long before the caseload question was reached - green, and
-- about a different rule entirely. What has to be isolated here is one
-- flag, on a service that still opens sessions.
--
-- IT IS PUT BACK IMMEDIATELY, and the restore is a recorded check at the
-- bottom with the others. Left false, every therapy service on this
-- database would stop asking who is answerable for the child - a
-- safeguard switched off by a test, silently, for every session sharing
-- the database.
UPDATE hbh.services SET needs_caseload_flg = false
 WHERE service_id = (SELECT v FROM hbh_test.fx WHERE k='svc_speech');

CALL hbh_test.chk('session', 'with needs_caseload_flg false the same call goes through',
  $q$ WITH s AS (SELECT hbh.start_session((SELECT v FROM hbh_test.fx WHERE k='appt_b')) AS id),
           i AS (INSERT INTO hbh_test.fx (k, v) SELECT 'sess_b', id FROM s RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('session', 'and the session it opened is a real one',
  $q$ SELECT status = 'IN_PROGRESS' FROM hbh.therapy_sessions
      WHERE session_id = (SELECT v FROM hbh_test.fx WHERE k='sess_b') $q$);

UPDATE hbh.services SET needs_caseload_flg = true
 WHERE service_id = (SELECT v FROM hbh_test.fx WHERE k='svc_speech');

RESET hbh.user_id;

-- =====================================================================
-- 7. TWO STATUSES, TWO QUESTIONS
--
-- A child arrives and tires after five minutes. The visit HAPPENED -
-- the slot and the therapist were consumed - and the clinical work did
-- not finish. One row cannot say both, which is why there are two.
-- =====================================================================
SET hbh.user_id = 'p3.therapist';

CALL hbh_test.chk('two', 'the responsible therapist may close the session',
  $q$ SELECT hbh.can_close_session((SELECT v FROM hbh_test.fx WHERE k='sess_a')) $q$);

-- close_session returns void, so the call is wrapped rather than
-- compared: "SELECT void_function() IS NULL" is not the question.
CALL hbh_test.chk('two', 'the session is aborted with a reason',
  $q$ WITH c AS (SELECT hbh.close_session((SELECT v FROM hbh_test.fx WHERE k='sess_a'),
                                          'ABORTED', 'الطفل تعب بعد خمس دقائق'))
      SELECT count(*) = 1 FROM c $q$);

CALL hbh_test.chk('two', 'the SESSION says the work did not finish',
  $q$ SELECT status = 'ABORTED' AND ended_at IS NOT NULL AND abort_reason IS NOT NULL
      FROM hbh.therapy_sessions WHERE session_id = (SELECT v FROM hbh_test.fx WHERE k='sess_a') $q$);

CALL hbh_test.chk('two', 'the APPOINTMENT says the visit happened',
  $q$ SELECT status = 'COMPLETED' FROM hbh.appointments
      WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_a') $q$);

CALL hbh_test.chk('two', 'and billing is a third question, still open',
  $q$ SELECT a.is_billable_flg AND s.is_billable_flg
      FROM hbh.appointments a
      JOIN hbh.therapy_sessions s ON s.appointment_id = a.appointment_id
      WHERE a.appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_a') $q$);

CALL hbh_test.chk('two', 'the session history recorded the abort',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.session_status_history
        WHERE session_id = (SELECT v FROM hbh_test.fx WHERE k='sess_a')
          AND from_status = 'IN_PROGRESS' AND to_status = 'ABORTED' AND reason IS NOT NULL) $q$);

CALL hbh_test.chk_raises('two', 'a closed session cannot reopen - HB025',
  $q$ UPDATE hbh.therapy_sessions SET status = 'IN_PROGRESS', ended_at = NULL
      WHERE session_id = (SELECT v FROM hbh_test.fx WHERE k='sess_a') $q$, 'HB025');

-- ---------------------------------------------------------------------
-- Who may close, and who may not
--
-- Closing a session and authoring its notes are different rights with
-- different codes. One gate serving both is what let reception start a
-- session in the Oracle system that only the assigned therapist could
-- end, while the screen refused a user holding the very permission the
-- action was named after.
-- ---------------------------------------------------------------------
SET hbh.user_id = 'p3.guardian';
CALL hbh_test.chk('two', 'a guardian may NOT close a session',
  $q$ SELECT NOT hbh.can_close_session((SELECT v FROM hbh_test.fx WHERE k='sess_a')) $q$);

SET hbh.user_id = 'p3.other';
CALL hbh_test.chk('two', 'an unrelated therapist may NOT close it either',
  $q$ SELECT NOT hbh.can_close_session((SELECT v FROM hbh_test.fx WHERE k='sess_a')) $q$);

SET hbh.user_id = 'admin';
CALL hbh_test.chk('two', 'an administrator with CHILD.VIEW_ALL and SESSION.COMPLETE may',
  $q$ SELECT hbh.can_close_session((SELECT v FROM hbh_test.fx WHERE k='sess_a')) $q$);

RESET hbh.user_id;
CALL hbh_test.chk('two', 'and with no identity at all, nobody may',
  $q$ SELECT NOT hbh.can_close_session((SELECT v FROM hbh_test.fx WHERE k='sess_a')) $q$);

-- =====================================================================
-- 8. THE GATE STILL HOLDS OVER THE NEW TABLES
-- =====================================================================
SET ROLE hbh_app;

RESET hbh.user_id;
CALL hbh_test.chk('gate', 'no identity sees no appointments',
  $q$ SELECT count(*) = 0 FROM hbh.appointments $q$);

CALL hbh_test.chk('gate', 'no identity sees no sessions',
  $q$ SELECT count(*) = 0 FROM hbh.therapy_sessions $q$);

SET hbh.user_id = 'p3.guardian';

CALL hbh_test.chk('gate', 'the guardian sees only their own child appointments',
  $q$ SELECT count(*) > 0 AND bool_and(child_id = (SELECT v FROM hbh_test.fx WHERE k='child_a'))
      FROM hbh.appointments $q$);

CALL hbh_test.chk('gate', 'and cannot fetch the other child appointment BY ID',
  $q$ SELECT count(*) = 0 FROM hbh.appointments
      WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_b') $q$);

CALL hbh_test.chk('gate', 'the guardian sees their own child session',
  $q$ SELECT count(*) = 1 FROM hbh.therapy_sessions $q$);

CALL hbh_test.chk('gate', 'and the status history follows the same gate',
  $q$ SELECT count(*) > 0 FROM hbh.appointment_status_history $q$);

-- Rota information is not a parent's business.
CALL hbh_test.chk('gate', 'a guardian sees no working hours',
  $q$ SELECT count(*) = 0 FROM hbh.therapist_working_hours $q$);

SET hbh.user_id = 'p3.therapist';
CALL hbh_test.chk('gate', 'a therapist with CHILD.VIEW_ALL sees both appointments',
  $q$ SELECT count(*) >= 2 FROM hbh.appointments WHERE appointment_no LIKE 'APT-%' $q$);

-- Scoped to this suite's own therapist.
--
-- It used to count the whole table, and another session working in the
-- same database left five rows of its own behind - so the check failed
-- on data that had nothing to do with the rule. A count that is not
-- scoped to the fixture measures whoever else was here.
CALL hbh_test.chk('gate', 'and does see the working hours',
  $q$ SELECT count(*) = 5 FROM hbh.therapist_working_hours
      WHERE therapist_id = (SELECT v FROM hbh_test.fx WHERE k='th') $q$);

-- The shape of this refusal CHANGED with migration 0012, when writing
-- was opened and Postgres became the source of truth.
--
-- Before, there was no UPDATE grant at all and the answer was 42501 -
-- a privilege error. Now the grant exists and the POLICY decides, so an
-- update a therapist may not make simply matches no rows and reports
-- success. Both are refusals; only one of them raises.
--
-- The assertion therefore counts rows rather than catching an error. A
-- test that still expected 42501 here would pass on the day somebody
-- widened the policy to let everybody through.
CALL hbh_test.chk('gate', 'a therapist without APPOINTMENT.BOOK changes no appointment',
  $q$ WITH u AS (UPDATE hbh.appointments SET note_ar = 'x' RETURNING 1)
      SELECT count(*) = 0 FROM u $q$);

RESET hbh.user_id;
RESET ROLE;

-- =====================================================================
-- CLEANUP
--
-- The two status-history tables are append-only, and the suite proved
-- it a moment ago by being refused with HB001. That is exactly why the
-- teardown cannot simply delete them - and it is not a flaw in either
-- the rule or the test.
--
-- What is done instead, and why it is not a loophole:
--
--   * The guarantee that matters is that the APPLICATION role cannot
--     rewrite history. hbh_app has no DELETE and no UPDATE grant on
--     these tables at all - the trigger is a second line, against a
--     mistake by the schema owner.
--   * A teardown run by the owner, in a suite that has just asserted
--     the trigger works, is not that mistake.
--   * So the trigger is disabled for the teardown ONLY, by name, and
--     the last check in this file asserts both are enabled again. If
--     the suite dies in between, that check fails on the next run.
--
-- The alternative - leaving the rows behind - means the database fills
-- with test children and every count assertion has to be loosened to
-- ">=", which is how a suite stops being able to tell the difference
-- between right and nearly right.
-- =====================================================================
ALTER TABLE hbh.appointment_status_history DISABLE TRIGGER trg_ash_append_only;
ALTER TABLE hbh.session_status_history     DISABLE TRIGGER trg_ssh_append_only;

CALL hbh_test.chk('cleanup', 'session history removed',
  $q$ WITH d AS (DELETE FROM hbh.session_status_history WHERE session_id IN
                   (SELECT session_id FROM hbh.therapy_sessions WHERE child_id IN
                      (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b'))) RETURNING 1)
      SELECT count(*) >= 2 FROM d $q$);

-- Two since 0118: child_a's, and the one the needs_caseload_flg check
-- opened on child_b.
CALL hbh_test.chk('cleanup', 'sessions removed',
  $q$ WITH d AS (DELETE FROM hbh.therapy_sessions WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) RETURNING 1)
      SELECT count(*) = 2 FROM d $q$);

-- THE FLAG THIS SUITE TURNED OFF IS BACK ON. Left false, hbh.start_session
-- would stop asking which clinician is answerable for which child's work -
-- on every therapy service in this database, for every session sharing
-- it, until somebody went looking for why.
CALL hbh_test.chk('cleanup', 'the caseload requirement was put back',
  $q$ SELECT bool_and(needs_caseload_flg AND creates_session_flg)
      FROM hbh.services WHERE code IN ('P3-SPEECH','P3-OT') $q$);

CALL hbh_test.chk('cleanup', 'appointment history removed',
  $q$ WITH d AS (DELETE FROM hbh.appointment_status_history WHERE appointment_id IN
                   (SELECT appointment_id FROM hbh.appointments WHERE child_id IN
                      (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b'))) RETURNING 1)
      SELECT count(*) >= 3 FROM d $q$);

-- THE ROOM BEFORE THE APPOINTMENT IT BELONGS TO - 0120.
--
-- hbh.meetings has a foreign key to hbh.appointments, so the delete
-- below stopped working the moment an online consultation opened a room:
-- 23503, the whole cleanup statement rolled back, and the NEXT run
-- started dirty and failed eleven checks that had nothing to do with
-- anything. Exactly the shape CLAUDE.md describes for the P5 cleanup
-- that took twenty-one checks down with it.
--
-- Tokens before rooms, rooms before appointments. Children first, every
-- level its own statement.
CALL hbh_test.chk('cleanup', 'meeting passes removed',
  $q$ WITH d AS (DELETE FROM hbh.meeting_tokens WHERE meeting_id IN
                   (SELECT m.meeting_id FROM hbh.meetings m
                     JOIN hbh.appointments a ON a.appointment_id = m.appointment_id
                    WHERE a.child_id IN (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')))
                  RETURNING 1)
      SELECT count(*) >= 0 FROM d $q$);

CALL hbh_test.chk('cleanup', 'meeting rooms removed',
  $q$ WITH d AS (DELETE FROM hbh.meetings WHERE appointment_id IN
                   (SELECT appointment_id FROM hbh.appointments WHERE child_id IN
                      (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')))
                  RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

-- Four since 0117: the three this suite always booked, plus the online
-- consultation in section 3b.
CALL hbh_test.chk('cleanup', 'appointments removed',
  $q$ WITH d AS (DELETE FROM hbh.appointments WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) RETURNING 1)
      SELECT count(*) = 4 FROM d $q$);

ALTER TABLE hbh.appointment_status_history ENABLE TRIGGER trg_ash_append_only;
ALTER TABLE hbh.session_status_history     ENABLE TRIGGER trg_ssh_append_only;

CALL hbh_test.chk('cleanup', 'caseload and guardian links removed',
  $q$ WITH c AS (DELETE FROM hbh.caseload WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) RETURNING 1),
           g AS (DELETE FROM hbh.guardian_children WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) RETURNING 1)
      SELECT (SELECT count(*) FROM c) = 1 AND (SELECT count(*) FROM g) = 2 $q$);

CALL hbh_test.chk('cleanup', 'children removed',
  $q$ WITH d AS (DELETE FROM hbh.children WHERE child_no LIKE 'P3-%' RETURNING 1)
      SELECT count(*) = 2 FROM d $q$);

-- Ten rota rows and three therapists since 0117 added the consultation
-- therapist: five weekdays each for the two who work.
CALL hbh_test.chk('cleanup', 'rota, skills and therapists removed',
  $q$ WITH w AS (DELETE FROM hbh.therapist_working_hours WHERE therapist_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('th','th_leave','th_cons')) RETURNING 1),
           s AS (DELETE FROM hbh.therapist_services WHERE therapist_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('th','th_leave','th_cons')) RETURNING 1),
           t AS (DELETE FROM hbh.therapists WHERE therapist_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('th','th_leave','th_cons')) RETURNING 1)
      SELECT (SELECT count(*) FROM w) = 10 AND (SELECT count(*) FROM t) = 3 $q$);

-- Three services since 0118: speech, OT and the consultation.
CALL hbh_test.chk('cleanup', 'rooms and services removed',
  $q$ WITH r AS (DELETE FROM hbh.rooms    WHERE code LIKE 'P3-%' RETURNING 1),
           s AS (DELETE FROM hbh.services WHERE code LIKE 'P3-%' RETURNING 1)
      SELECT (SELECT count(*) FROM r) = 2 AND (SELECT count(*) FROM s) = 3 $q$);

-- 0089 gave staff notifications of their own, so booking an appointment
-- now writes a row addressed to the therapist. The teardown predates
-- that and deleted the users straight out, hitting fk_ntf_user. A new
-- write path leaves rows the old teardown has never heard of.
CALL hbh_test.chk('cleanup', 'notifications written during the run are removed',
  $q$ WITH d AS (DELETE FROM hbh.notifications WHERE user_id IN
                   (SELECT user_id FROM hbh.users WHERE username LIKE 'p3.%') RETURNING 1)
      SELECT count(*) >= 0 FROM d $q$);

-- THREE STATEMENTS, AND IT USED TO BE ONE.
--
-- The guardian and the roles both reference the user, and all three
-- deletes were CTEs of a single statement - the shape CLAUDE.md names:
-- "several CTEs modifying data have no ordering between them... it
-- succeeds for days and then the plan changes, and the failure looks
-- flaky when it is actually undefined". Children first, parents last,
-- one statement each.
--
-- And each is its own recorded check, because a cleanup that swallows
-- its failure is worse than no cleanup: the rows it leaves become the
-- next run's mysterious failures.
CALL hbh_test.chk('cleanup', 'the guardian is removed',
  $q$ WITH d AS (DELETE FROM hbh.guardians
                  WHERE user_id IN (SELECT user_id FROM hbh.users WHERE username LIKE 'p3.%')
                  RETURNING 1)
      SELECT count(*) = 2 FROM d $q$);

-- Four role rows since 0117: three therapists and one guardian.
CALL hbh_test.chk('cleanup', 'the role grants are removed',
  $q$ WITH d AS (DELETE FROM hbh.user_roles
                  WHERE user_id IN (SELECT user_id FROM hbh.users WHERE username LIKE 'p3.%')
                  RETURNING 1)
      SELECT count(*) = 5 FROM d $q$);

CALL hbh_test.chk('cleanup', 'and the accounts themselves',
  $q$ WITH d AS (DELETE FROM hbh.users WHERE username LIKE 'p3.%' RETURNING 1)
      SELECT count(*) = 5 FROM d $q$);

-- The check that keeps the teardown honest. If the suite ever dies
-- between the DISABLE and the ENABLE above, this fails on the next run
-- and says so, instead of leaving the history quietly writable.
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
    RAISE NOTICE '  PHASE 3 ACCEPTED';
  ELSE
    RAISE NOTICE '  *** PHASE 3 NOT ACCEPTED';
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
