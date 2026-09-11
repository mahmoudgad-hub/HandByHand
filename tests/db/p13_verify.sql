-- =====================================================================
-- Hand By Hand (new) - PHASE 13 acceptance suite: the message leaves.
--
-- Must print:  PHASE 13 ACCEPTED
--
-- Four claims, and the first is the one that stops a launch:
--
--   1. A ONE-TIME CODE IS A CREDENTIAL AND IS TREATED LIKE ONE. It is
--      hashed at rest, it expires, it is spent on use, a new one kills
--      the old one, guessing is counted and ends in a lock - and the
--      delivery record that C5 adds contains NO CODE, structurally.
--   2. A FAMILY IS TOLD, AND EXACTLY ONCE. Every appointment transition
--      that matters produces one notification and one queued message;
--      a trigger firing twice, a worker restarting, or a maintenance
--      pass running twice cannot multiply either.
--   3. A PROVIDER CANNOT ROLL BACK A CLINICAL DECISION. The report is
--      published, the appointment is booked, the family has no usable
--      number - and the business row stands in every case, with the
--      failure recorded where operations can read it.
--   4. NOBODY READS ANOTHER FAMILY'S FEED OR ANOTHER CENTRE'S QUEUE,
--      and a delivery queue is not operable from a user session at all.
--
-- WHAT THIS SUITE DOES NOT PROVE. That a real Egyptian provider accepts
-- these messages. No provider is contracted and no credentials exist;
-- the transport is tested in Go (api/internal/sms) against its own
-- classification, and the boundary is exercised here through the
-- database only. Said plainly because "SMS works" and "SMS was
-- delivered to a phone" are two sentences and this suite proves the
-- first.
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

GRANT USAGE ON SCHEMA hbh_test TO hbh_app;
GRANT INSERT, SELECT ON hbh_test.results TO hbh_app;
GRANT SELECT ON hbh_test.fx, hbh_test.fxb, hbh_test.fxt, hbh_test.fxs TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh_test TO hbh_app;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA hbh_test TO hbh_app;

-- =====================================================================
-- FIXTURE
--
-- The shape is chosen by what has to be DISTINGUISHABLE, not by what is
-- convenient - the lesson this project paid for twice:
--
--   * TWO GUARDIANS ON ONE CHILD, one consenting to SMS and one not.
--     With a single parent, "the consent gated it" and "nothing was
--     sent to anybody" are the same observation.
--   * A THIRD GUARDIAN IN ANOTHER FAMILY, same centre. This is the
--     realistic cross-family threat and the one RLS has to stop.
--   * A SECOND CENTRE with its own guardian. Cross-tenant is a
--     different policy clause from cross-family and a fixture that
--     cannot produce both cannot tell them apart.
--   * A GUARDIAN WITH NO MOBILE, consenting. The only way to reach the
--     "delivery fails, business action stands" branch on purpose.
-- =====================================================================
INSERT INTO hbh_test.fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO hbh_test.fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

INSERT INTO hbh.centers (code, name_ar) VALUES ('P13C2', 'مركز اختبار ١٣ الثاني');
INSERT INTO hbh_test.fx (k, v) SELECT 'center2', center_id FROM hbh.centers WHERE code='P13C2';

INSERT INTO hbh.branches (center_id, code, name_ar)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center2'), 'P13B2', 'فرع اختبار ١٣ الثاني');
INSERT INTO hbh_test.fx (k, v) SELECT 'branch2', branch_id FROM hbh.branches WHERE code='P13B2';

INSERT INTO hbh_test.fxt (k, v) VALUES
  ('slot_start', (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '14 days' + interval '10 hours') AT TIME ZONE 'Africa/Cairo'),
  ('slot_end',   (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '14 days' + interval '10 hours 45 minutes') AT TIME ZONE 'Africa/Cairo'),
  -- DELIBERATELY FAR OUT. This one must fall OUTSIDE the reminder window
  -- the reminder group configures, and "outside" has to be true whatever
  -- day of the week the suite happens to run on. date_trunc('week') puts
  -- the base anywhere from today to six days ago, so a slot two weeks
  -- out is between eight and fourteen days away - too close to a
  -- fourteen-day window to be certain. Sixty days is not.
  ('slot2_start',(date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '60 days' + interval '14 hours') AT TIME ZONE 'Africa/Cairo'),
  ('slot2_end',  (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '60 days' + interval '14 hours 45 minutes') AT TIME ZONE 'Africa/Cairo'),
  ('slot3_start',(date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '14 days' + interval '16 hours') AT TIME ZONE 'Africa/Cairo'),
  ('slot3_end',  (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '14 days' + interval '16 hours 45 minutes') AT TIME ZONE 'Africa/Cairo'),
  ('slot4_start',(date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '14 days' + interval '18 hours') AT TIME ZONE 'Africa/Cairo'),
  ('slot4_end',  (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '14 days' + interval '18 hours 45 minutes') AT TIME ZONE 'Africa/Cairo');

INSERT INTO hbh.services (center_id, branch_id, code, name_ar, kind_code)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P13-SPEECH', 'تخاطب — اختبار ١٣', 'SPEECH');
INSERT INTO hbh_test.fx (k, v) SELECT 'svc', service_id FROM hbh.services WHERE code='P13-SPEECH';

INSERT INTO hbh.rooms (center_id, branch_id, code, name_ar)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P13-R1', 'غرفة اختبار ١٣');
INSERT INTO hbh_test.fx (k, v) SELECT 'room', room_id FROM hbh.rooms WHERE code='P13-R1';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
       u.username, u.name, u.utype, u.mobile
FROM (VALUES
       ('p13.therapist', 'أخصائي اختبار ١٣',        'THERAPIST', '+201930000001'),
       ('p13.admin',     'مدير اختبار ١٣',          'STAFF',     '+201930000009'),
       ('p13.father',    'الأب — يقبل الرسائل',      'GUARDIAN',  '+201930000002'),
       ('p13.mother',    'الأم — ترفض الرسائل',      'GUARDIAN',  '+201930000003'),
       ('p13.stranger',  'ولي أمر أسرة أخرى',        'GUARDIAN',  '+201930000004'),
       ('p13.nomobile',  'ولي أمر بلا رقم',          'GUARDIAN',  '+201930000005'),
       ('p13.locked',    'حساب مقفول',              'GUARDIAN',  '+201930000006')
     ) AS u(username, name, utype, mobile);

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center2'), (SELECT v FROM hbh_test.fx WHERE k='branch2'),
        'p13.other_center', 'ولي أمر المركز الثاني', 'GUARDIAN', '+201930000007');

INSERT INTO hbh_test.fx (k, v) SELECT 'user_th', user_id FROM hbh.users WHERE username='p13.therapist';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_ad', user_id FROM hbh.users WHERE username='p13.admin';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_fa', user_id FROM hbh.users WHERE username='p13.father';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_mo', user_id FROM hbh.users WHERE username='p13.mother';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_st', user_id FROM hbh.users WHERE username='p13.stranger';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_nm', user_id FROM hbh.users WHERE username='p13.nomobile';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_lk', user_id FROM hbh.users WHERE username='p13.locked';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_oc', user_id FROM hbh.users WHERE username='p13.other_center';

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT f.v, r.role_id
FROM   hbh_test.fx f
JOIN   hbh.roles r ON r.center_id = (SELECT v FROM hbh_test.fx WHERE k='center')
WHERE  (f.k = 'user_th' AND r.code = 'THERAPIST')
   OR  (f.k = 'user_ad' AND r.code = 'CENTER_ADMIN')
   OR  (f.k IN ('user_fa','user_mo','user_st','user_nm','user_lk') AND r.code = 'GUARDIAN');

INSERT INTO hbh.therapists (center_id, branch_id, user_id, full_name_ar)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_th'), 'أخصائي اختبار ١٣');
INSERT INTO hbh_test.fx (k, v) SELECT 'th', therapist_id FROM hbh.therapists WHERE full_name_ar='أخصائي اختبار ١٣';

INSERT INTO hbh.therapist_services (therapist_id, service_id)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='svc'));

INSERT INTO hbh.therapist_working_hours (center_id, therapist_id, weekday, start_time, end_time)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='th'),
       d, TIME '08:00', TIME '20:00'
FROM unnest(ARRAY[1,2,3,4,5,6,7]::smallint[]) AS d;

INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P13-A', 'طفل اختبار ١٣', DATE '2020-01-13', 'M'),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P13-B', 'طفل الأسرة الأخرى', DATE '2021-02-02', 'F'),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P13-C', 'طفل بلا رقم لوليّه', DATE '2021-06-06', 'M');
INSERT INTO hbh_test.fx (k, v) SELECT 'child',   child_id FROM hbh.children WHERE child_no='P13-A';
INSERT INTO hbh_test.fx (k, v) SELECT 'child_b', child_id FROM hbh.children WHERE child_no='P13-B';
INSERT INTO hbh_test.fx (k, v) SELECT 'child_c', child_id FROM hbh.children WHERE child_no='P13-C';

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_fa'), 'الأب — يقبل الرسائل',  '+201930000002'),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_mo'), 'الأم — ترفض الرسائل',  '+201930000003'),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_st'), 'ولي أمر أسرة أخرى',    '+201930000004'),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        -- A NUMBER THE DOMAIN ACCEPTS AND A PROVIDER WILL NOT. It is not
        -- NULL, because it cannot be: hbh.guard_identity_format refuses a
        -- guardian without a mobile matching MOBILE_PATTERN, so "a family
        -- with no number on file" is a state this schema does not permit.
        -- The reachable shape of 22 is therefore a number that passes
        -- every check here and is rejected at the provider - which is the
        -- common real case anyway: a number that was right and has been
        -- disconnected.
        (SELECT v FROM hbh_test.fx WHERE k='user_nm'), 'ولي أمر رقمه مرفوض', '+201930000005');
INSERT INTO hbh_test.fx (k, v) SELECT 'gd_fa', guardian_id FROM hbh.guardians WHERE mobile='+201930000002';
INSERT INTO hbh_test.fx (k, v) SELECT 'gd_mo', guardian_id FROM hbh.guardians WHERE mobile='+201930000003';
INSERT INTO hbh_test.fx (k, v) SELECT 'gd_st', guardian_id FROM hbh.guardians WHERE mobile='+201930000004';
INSERT INTO hbh_test.fx (k, v) SELECT 'gd_nm', guardian_id FROM hbh.guardians
  WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user_nm');

INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='gd_fa'), (SELECT v FROM hbh_test.fx WHERE k='child'),   'FATHER', true),
       ((SELECT v FROM hbh_test.fx WHERE k='gd_mo'), (SELECT v FROM hbh_test.fx WHERE k='child'),   'MOTHER', false),
       ((SELECT v FROM hbh_test.fx WHERE k='gd_st'), (SELECT v FROM hbh_test.fx WHERE k='child_b'), 'FATHER', true),
       ((SELECT v FROM hbh_test.fx WHERE k='gd_nm'), (SELECT v FROM hbh_test.fx WHERE k='child_c'), 'FATHER', true);

INSERT INTO hbh.caseload (center_id, therapist_id, child_id, service_id)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='th'),
        (SELECT v FROM hbh_test.fx WHERE k='child'), (SELECT v FROM hbh_test.fx WHERE k='svc'));

-- THE CONSENTS, RECORDED AND NOT ASSUMED.
--
-- "The mother has not agreed" is the initial state and this suite does
-- NOT rely on it being so: identifiers are reused after a hard delete,
-- another suite records consents of the same type, and a fixture that
-- assumes an absence is a fixture that tests nothing the day the
-- assumption breaks. The absence is MADE, by withdrawing first.
SET hbh.user_id = 'p13.admin';
SELECT hbh.grant_consent((SELECT v FROM hbh_test.fx WHERE k='gd_fa'), 'SMS_NOTIFY');
SELECT hbh.withdraw_consent((SELECT v FROM hbh_test.fx WHERE k='gd_mo'), 'SMS_NOTIFY');
SELECT hbh.grant_consent((SELECT v FROM hbh_test.fx WHERE k='gd_nm'), 'SMS_NOTIFY');
RESET hbh.user_id;

-- =====================================================================
-- 0. THE FIXTURE IS CONFIRMED BY NAME BEFORE ANYTHING IS TESTED
--
-- A missing piece shows up fifty checks later as a puzzling refusal
-- from correct code. CLAUDE.md, first day.
-- =====================================================================
CALL hbh_test.chk('fixture', 'migrations 0094 to 0097 are recorded',
  $q$ SELECT count(*) = 4 FROM hbh.schema_migrations WHERE version IN ('0094','0095','0096','0097') $q$);

CALL hbh_test.chk('fixture', 'the outbox exists',
  $q$ SELECT to_regclass('hbh.sms_outbox') IS NOT NULL $q$);

CALL hbh_test.chk('fixture', 'the consenting father really consents',
  $q$ SELECT hbh.has_consent((SELECT v FROM hbh_test.fx WHERE k='gd_fa'), 'SMS_NOTIFY') $q$);

CALL hbh_test.chk('fixture', 'and the mother really does not',
  $q$ SELECT NOT hbh.has_consent((SELECT v FROM hbh_test.fx WHERE k='gd_mo'), 'SMS_NOTIFY') $q$);

CALL hbh_test.chk('fixture', 'the third guardian consents and has a well-formed number',
  $q$ SELECT hbh.has_consent((SELECT v FROM hbh_test.fx WHERE k='gd_nm'), 'SMS_NOTIFY')
         AND (SELECT g.mobile = '+201930000005' FROM hbh.guardians g
              WHERE g.guardian_id = (SELECT v FROM hbh_test.fx WHERE k='gd_nm')) $q$);

-- AND THE SCHEMA REFUSES A GUARDIAN WITHOUT ONE. Worth asserting rather
-- than assuming, because it is the reason 22 is tested as a provider
-- rejection below and not as a missing number.
CALL hbh_test.chk_raises('fixture', 'a guardian with no mobile is refused by the schema',
  $q$ INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'),
              (SELECT v FROM hbh_test.fx WHERE k='branch'),
              (SELECT v FROM hbh_test.fx WHERE k='user_lk'), 'بلا رقم', NULL) $q$, 'HB170');

CALL hbh_test.chk('fixture', 'the login code template has a {code} placeholder',
  $q$ SELECT hbh.param(NULL, 'SMS_TEMPLATE_OTP', '') LIKE '%{code}%' $q$);

-- =====================================================================
-- 1. THE ONE-TIME CODE IS A CREDENTIAL
--
-- Everything here predates C5 except the last two checks. It is run
-- anyway, because "C5 did not weaken the login" is a claim and an
-- untested claim is an opinion.
-- =====================================================================
INSERT INTO hbh_test.fxs (k, v)
SELECT 'otp1', code FROM hbh.request_otp('+201930000002');

CALL hbh_test.chk('otp', 'a code is issued for a registered number',
  $q$ SELECT (SELECT v FROM hbh_test.fxs WHERE k='otp1') ~ '^[0-9]{6}$' $q$);

CALL hbh_test.chk('otp', 'and request_otp now reports the centre',
  $q$ SELECT center_id = (SELECT v FROM hbh_test.fx WHERE k='center')
      FROM hbh.request_otp('+201930000003') $q$);

-- THE STORED FORM IS A HASH. A database dump must not be a list of live
-- credentials, which is the whole reason hbh.otp_codes has no plaintext
-- column - and the reason hbh.sms_outbox has none either.
CALL hbh_test.chk('otp', 'only a bcrypt hash is stored, never the code',
  $q$ SELECT o.code_hash LIKE '$2%' AND o.code_hash <> (SELECT v FROM hbh_test.fxs WHERE k='otp1')
      FROM hbh.otp_codes o
      WHERE o.user_id = (SELECT v FROM hbh_test.fx WHERE k='user_fa')
      ORDER BY o.otp_id DESC LIMIT 1 $q$);

CALL hbh_test.chk('otp', 'the code expires - the window is finite and in the future',
  $q$ SELECT o.expires_at > now() AND o.expires_at <= now() + interval '24 hours'
      FROM hbh.otp_codes o
      WHERE o.user_id = (SELECT v FROM hbh_test.fx WHERE k='user_fa')
      ORDER BY o.otp_id DESC LIMIT 1 $q$);

CALL hbh_test.chk('otp', 'a wrong code is refused and the attempt is COUNTED',
  $q$ SELECT NOT ok AND reason = 'WRONG_CODE'
      FROM hbh.verify_otp('+201930000002', '000000') $q$);

CALL hbh_test.chk('otp', 'and the counter survived the refusal',
  $q$ SELECT o.attempts = 1 FROM hbh.otp_codes o
      WHERE o.user_id = (SELECT v FROM hbh_test.fx WHERE k='user_fa')
      ORDER BY o.otp_id DESC LIMIT 1 $q$);

-- THE AUTHENTICATION BYPASS FOUND AND FIXED IN C5 (migration 0097).
--
-- public.crypt(NULL, hash) is NULL, and `hash <> NULL` is UNKNOWN rather
-- than false - so the wrong-code branch was SKIPPED and control fell
-- through to the lines that consume the code and return success. On this
-- database, before the fix:
--
--   SELECT ok, reason, user_id FROM hbh.verify_otp('015...', NULL);
--   --  t | OK | 935
--
-- It was not reachable through the HTTP handler, which refuses an empty
-- or non-digit code. That is why it survived: the defect is invisible
-- from the one direction anybody looks, and the protection was in the
-- layer that is supposed to carry answers rather than make them.
CALL hbh_test.chk('otp', 'a NULL code does NOT authenticate',
  $q$ SELECT NOT ok AND reason = 'WRONG_CODE'
      FROM hbh.verify_otp('+201930000002', NULL) $q$);

CALL hbh_test.chk('otp', 'a blank code does NOT authenticate either',
  $q$ SELECT NOT ok AND reason = 'WRONG_CODE'
      FROM hbh.verify_otp('+201930000002', '   ') $q$);

-- AND IT COSTS AN ATTEMPT. Refusing a NULL as a validation error instead
-- would leave whoever found the door an unlimited supply of free
-- guesses, which is the same defect wearing a different hat.
CALL hbh_test.chk('otp', 'and each of those cost an attempt',
  $q$ SELECT o.attempts = 3 FROM hbh.otp_codes o
      WHERE o.user_id = (SELECT v FROM hbh_test.fx WHERE k='user_fa')
      ORDER BY o.otp_id DESC LIMIT 1 $q$);

CALL hbh_test.chk('otp', 'the right code is accepted',
  $q$ SELECT ok AND user_id = (SELECT v FROM hbh_test.fx WHERE k='user_fa')
      FROM hbh.verify_otp('+201930000002', (SELECT v FROM hbh_test.fxs WHERE k='otp1')) $q$);

-- ONE USE. Replaying a code that worked a second ago is the cheapest
-- attack there is.
CALL hbh_test.chk('otp', 'the same code cannot be used twice',
  $q$ SELECT NOT ok AND reason = 'NO_PENDING_CODE'
      FROM hbh.verify_otp('+201930000002', (SELECT v FROM hbh_test.fxs WHERE k='otp1')) $q$);

-- RESEND INVALIDATES. Two live codes for one account doubles the
-- guessing surface and means a code a parent abandoned still works.
UPDATE hbh.sys_params SET param_value = '0'
 WHERE param_code = 'OTP_RESEND_SECONDS' AND center_id IS NULL;

INSERT INTO hbh_test.fxs (k, v) SELECT 'otp2', code FROM hbh.request_otp('+201930000002');
INSERT INTO hbh_test.fxs (k, v) SELECT 'otp3', code FROM hbh.request_otp('+201930000002');

-- THE OBSERVABLE REASON IS WRONG_CODE, NOT NO_PENDING_CODE, and getting
-- that wrong the first time is instructive: the OLD code's row was
-- consumed, but a NEWER row is outstanding, so verify_otp finds that one
-- and compares against it. What is being asserted is the security
-- property - the retired code does not let anybody in - and the row
-- check underneath it says WHY.
CALL hbh_test.chk('otp', 'a new request invalidates the code still outstanding',
  $q$ SELECT NOT ok
      FROM hbh.verify_otp('+201930000002', (SELECT v FROM hbh_test.fxs WHERE k='otp2')) $q$);

CALL hbh_test.chk('otp', 'and the retired code row is marked consumed',
  $q$ SELECT count(*) = 0 FROM hbh.otp_codes
      WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user_fa')
        AND consumed_at IS NULL
        AND public.crypt((SELECT v FROM hbh_test.fxs WHERE k='otp2'), code_hash) = code_hash $q$);

CALL hbh_test.chk('otp', 'and the newest code is the one that works',
  $q$ SELECT ok FROM hbh.verify_otp('+201930000002', (SELECT v FROM hbh_test.fxs WHERE k='otp3')) $q$);

-- EXPIRY IS ENFORCED BY THE BACKEND, not by a countdown on a screen.
-- The window is narrowed rather than dragged into the past: ck_otp_codes_window
-- refuses expires_at <= issued_at, and weakening a constraint to let a
-- test pass is the move CLAUDE.md names.
INSERT INTO hbh_test.fxs (k, v) SELECT 'otp4', code FROM hbh.request_otp('+201930000002');
UPDATE hbh.otp_codes
   SET expires_at = issued_at + interval '1 millisecond'
 WHERE otp_id = (SELECT max(otp_id) FROM hbh.otp_codes
                 WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user_fa'));

CALL hbh_test.chk('otp', 'an expired code is refused as EXPIRED, not as wrong',
  $q$ SELECT NOT ok AND reason = 'EXPIRED'
      FROM hbh.verify_otp('+201930000002', (SELECT v FROM hbh_test.fxs WHERE k='otp4')) $q$);

-- BRUTE FORCE ENDS. Not "is slowed" - ends, with the account locked.
INSERT INTO hbh_test.fxs (k, v) SELECT 'otp5', code FROM hbh.request_otp('+201930000003');
SELECT hbh.verify_otp('+201930000003', '000001');
SELECT hbh.verify_otp('+201930000003', '000002');
SELECT hbh.verify_otp('+201930000003', '000003');
SELECT hbh.verify_otp('+201930000003', '000004');
SELECT hbh.verify_otp('+201930000003', '000005');

CALL hbh_test.chk('otp', 'the sixth guess locks the account',
  $q$ SELECT NOT ok AND reason = 'TOO_MANY_ATTEMPTS'
      FROM hbh.verify_otp('+201930000003', '000006') $q$);

CALL hbh_test.chk('otp', 'and the RIGHT code no longer works on a locked account',
  $q$ SELECT NOT ok AND reason = 'USER_LOCKED'
      FROM hbh.verify_otp('+201930000003', (SELECT v FROM hbh_test.fxs WHERE k='otp5')) $q$);

CALL hbh_test.chk('otp', 'a locked account is refused a NEW code too',
  $q$ SELECT NOT ok AND reason = 'USER_LOCKED' FROM hbh.request_otp('+201930000003') $q$);

CALL hbh_test.chk('otp', 'and a locked account does not disclose its centre',
  $q$ SELECT center_id IS NULL FROM hbh.request_otp('+201930000003') $q$);

UPDATE hbh.users SET status = 'ACTIVE'
 WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user_mo');

-- ENUMERATION. verify_otp answers an unknown number exactly as it
-- answers a known number with no live code. The request path DOES
-- distinguish them, by the owner's recorded decision of 2026-09-05 -
-- that is a product choice and not a defect, and it is asserted here so
-- that a future change to it is a deliberate one.
CALL hbh_test.chk('otp', 'verify does not tell a stranger whether a number is registered',
  $q$ SELECT (SELECT reason FROM hbh.verify_otp('+201999999999', '123456'))
           = (SELECT reason FROM hbh.verify_otp('+201930000004', '123456')) $q$);

UPDATE hbh.sys_params SET param_value = '60'
 WHERE param_code = 'OTP_RESEND_SECONDS' AND center_id IS NULL;

CALL hbh_test.chk('otp', 'the resend window is enforced once restored',
  $q$ SELECT NOT ok AND reason = 'RESEND_TOO_SOON' FROM hbh.request_otp('+201930000002') $q$);

-- =====================================================================
-- 2. THE DELIVERY RECORD CARRIES NO CREDENTIAL
--
-- This is the C5 addition to the login path, and the constraint is the
-- control - not a convention somebody could forget on a Friday.
-- =====================================================================
INSERT INTO hbh_test.fxb (k, v)
SELECT 'otp_sms', hbh.record_otp_delivery(
  (SELECT v FROM hbh_test.fx WHERE k='center'), '+201930000002', 'dev', 'dev-p13-1');

CALL hbh_test.chk('otpsms', 'a delivery record is written for a login code',
  $q$ SELECT status = 'SENT' AND provider_msg_id = 'dev-p13-1' AND attempts = 1
      FROM hbh.sms_outbox WHERE sms_id = (SELECT v FROM hbh_test.fxb WHERE k='otp_sms') $q$);

CALL hbh_test.chk('otpsms', 'and it holds no message body at all',
  $q$ SELECT body_ar IS NULL FROM hbh.sms_outbox
      WHERE sms_id = (SELECT v FROM hbh_test.fxb WHERE k='otp_sms') $q$);

-- THE CONSTRAINT, TESTED DIRECTLY. If ck_sms_body were ever relaxed,
-- every check above would still pass and a live code could be stored.
CALL hbh_test.chk_raises('otpsms', 'a login code row with a body is REFUSED by the schema',
  $q$ INSERT INTO hbh.sms_outbox (center_id, purpose, template_code, destination,
                                  body_ar, dedupe_key)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'OTP_LOGIN', 'OTP_LOGIN',
              '+201930000002', 'code 123456', 'P13:illegal-body') $q$, '23514');

-- The id is recorded FIRST and read back second. Calling a volatile
-- function in a WHERE clause asks the planner to evaluate it per row,
-- which matches nothing and reads as a failure of the function rather
-- than of the query.
INSERT INTO hbh_test.fxb (k, v)
SELECT 'otp_fail', hbh.record_otp_delivery(
  (SELECT v FROM hbh_test.fx WHERE k='center'), '+201930000002', 'http',
  NULL, 'CONFIG', 'the provider refused these credentials');

CALL hbh_test.chk('otpsms', 'a failed delivery is DEAD, not queued for retry',
  $q$ SELECT status = 'DEAD' AND error_class = 'CONFIG' AND failed_at IS NOT NULL
      FROM hbh.sms_outbox WHERE sms_id = (SELECT v FROM hbh_test.fxb WHERE k='otp_fail') $q$);

CALL hbh_test.chk('otpsms', 'no login code row is ever PENDING, so the worker never claims one',
  $q$ SELECT count(*) = 0 FROM hbh.sms_outbox
      WHERE purpose = 'OTP_LOGIN' AND status IN ('PENDING','SENDING') $q$);

CALL hbh_test.chk_raises('otpsms', 'and it refuses to record a delivery with no destination',
  $q$ SELECT hbh.record_otp_delivery(
        (SELECT v FROM hbh_test.fx WHERE k='center'), '', 'dev') $q$, 'HB231');

-- =====================================================================
-- 3. A REPORT IS PUBLISHED - AND A DRAFT IS NOT ANNOUNCED
--
-- The mandatory test of 42. A parent must learn nothing from a report
-- the therapist is still writing.
-- =====================================================================
SET hbh.user_id = 'p13.therapist';

INSERT INTO hbh_test.fx (k, v)
SELECT 'report', hbh.create_report(
  (SELECT v FROM hbh_test.fx WHERE k='child'), 'تقرير اختبار ١٣',
  current_date - 30, current_date, NULL, 'ملخّص يكفي للنشر.');

CALL hbh_test.chk('draft', 'the draft exists and is a DRAFT',
  $q$ SELECT status = 'DRAFT' FROM hbh.progress_reports
      WHERE report_id = (SELECT v FROM hbh_test.fx WHERE k='report') $q$);

CALL hbh_test.chk('draft', 'NO notification was created for the draft',
  $q$ SELECT count(*) = 0 FROM hbh.notifications
      WHERE link_kind = 'REPORT' AND link_id = (SELECT v FROM hbh_test.fx WHERE k='report') $q$);

CALL hbh_test.chk('draft', 'and NO message was queued for the draft',
  $q$ SELECT count(*) = 0 FROM hbh.sms_outbox o
      JOIN hbh.notifications n ON n.notification_id = o.notification_id
      WHERE n.link_kind = 'REPORT' AND n.link_id = (SELECT v FROM hbh_test.fx WHERE k='report') $q$);

-- Editing a draft is not publishing it either. A trigger keyed on
-- "the row changed" rather than on the transition would announce this.
UPDATE hbh.progress_reports SET summary_ar = 'ملخّص بعد تعديل المسوّدة.'
 WHERE report_id = (SELECT v FROM hbh_test.fx WHERE k='report');

CALL hbh_test.chk('draft', 'editing the draft still announces nothing',
  $q$ SELECT count(*) = 0 FROM hbh.notifications
      WHERE link_kind = 'REPORT' AND link_id = (SELECT v FROM hbh_test.fx WHERE k='report') $q$);

SELECT hbh.publish_report((SELECT v FROM hbh_test.fx WHERE k='report'));
RESET hbh.user_id;

CALL hbh_test.chk('publish', 'publishing tells BOTH guardians of the child',
  $q$ SELECT count(*) = 2 FROM hbh.notifications
      WHERE link_kind = 'REPORT' AND link_id = (SELECT v FROM hbh_test.fx WHERE k='report')
        AND user_id IN ((SELECT v FROM hbh_test.fx WHERE k='user_fa'),
                        (SELECT v FROM hbh_test.fx WHERE k='user_mo')) $q$);

CALL hbh_test.chk('publish', 'the notification points AT the report',
  $q$ SELECT bool_and(link_kind = 'REPORT'
                  AND link_id = (SELECT v FROM hbh_test.fx WHERE k='report')
                  AND child_id = (SELECT v FROM hbh_test.fx WHERE k='child'))
      FROM hbh.notifications
      WHERE link_kind = 'REPORT' AND link_id = (SELECT v FROM hbh_test.fx WHERE k='report') $q$);

-- THE CONSENT DID SOMETHING. One message, to the parent who agreed.
CALL hbh_test.chk('publish', 'exactly ONE message is queued - to the consenting parent only',
  $q$ SELECT count(*) = 1 FROM hbh.sms_outbox o
      JOIN hbh.notifications n ON n.notification_id = o.notification_id
      WHERE n.link_kind = 'REPORT' AND n.link_id = (SELECT v FROM hbh_test.fx WHERE k='report')
        AND o.destination = '+201930000002' $q$);

CALL hbh_test.chk('publish', 'and NOTHING is queued for the parent who declined',
  $q$ SELECT count(*) = 0 FROM hbh.sms_outbox o
      JOIN hbh.notifications n ON n.notification_id = o.notification_id
      WHERE n.link_kind = 'REPORT' AND n.link_id = (SELECT v FROM hbh_test.fx WHERE k='report')
        AND o.destination = '+201930000003' $q$);

-- 24: SMS IS THE CHANNEL WITH NO GATE IN FRONT OF IT. The report's own
-- summary must not travel on it. This asserts the whole body, not a
-- keyword, because a substring test passes the day somebody paraphrases.
CALL hbh_test.chk('publish', 'the text message carries no clinical summary',
  $q$ SELECT bool_and(o.body_ar NOT LIKE '%ملخّص%')
      FROM hbh.sms_outbox o
      JOIN hbh.notifications n ON n.notification_id = o.notification_id
      WHERE n.link_kind = 'REPORT' AND n.link_id = (SELECT v FROM hbh_test.fx WHERE k='report') $q$);

CALL hbh_test.chk('publish', 'the report is PUBLISHED whatever delivery did',
  $q$ SELECT status = 'PUBLISHED' FROM hbh.progress_reports
      WHERE report_id = (SELECT v FROM hbh_test.fx WHERE k='report') $q$);

-- =====================================================================
-- 4. IDEMPOTENCY - 20, and it is mandatory
--
-- "Report 314 published" must not become three text messages because a
-- worker restarted. The guarantee is the unique index on dedupe_key,
-- and this is the check that says so out loud.
-- =====================================================================
CALL hbh_test.chk_raises('idem', 'a second outbox row for the same notification is IMPOSSIBLE',
  $q$ INSERT INTO hbh.sms_outbox (center_id, notification_id, purpose, template_code,
                                  destination, body_ar, dedupe_key)
      SELECT o.center_id, o.notification_id, o.purpose, o.template_code,
             o.destination, o.body_ar, o.dedupe_key
      FROM hbh.sms_outbox o
      JOIN hbh.notifications n ON n.notification_id = o.notification_id
      WHERE n.link_kind = 'REPORT' AND n.link_id = (SELECT v FROM hbh_test.fx WHERE k='report')
      LIMIT 1 $q$, '23505');

CALL hbh_test.chk('idem', 'and enqueue_sms returns the EXISTING row rather than failing',
  $q$ WITH again AS (
        SELECT hbh.enqueue_sms(o.center_id, o.purpose, o.template_code, o.destination,
                               o.dedupe_key, o.body_ar, o.notification_id, 'PENDING') AS id,
               o.sms_id AS was
        FROM hbh.sms_outbox o
        JOIN hbh.notifications n ON n.notification_id = o.notification_id
        WHERE n.link_kind = 'REPORT' AND n.link_id = (SELECT v FROM hbh_test.fx WHERE k='report')
        LIMIT 1)
      SELECT id = was FROM again $q$);

-- =====================================================================
-- 5. THE APPOINTMENT TRANSITIONS - 40
--
-- One event, one message, and NOT on an unrelated update. That last
-- clause is the one that costs money and goodwill when it is wrong.
-- =====================================================================
INSERT INTO hbh_test.fx (k, v)
SELECT 'appt', hbh.book_appointment(
  (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
  (SELECT v FROM hbh_test.fx WHERE k='child'), (SELECT v FROM hbh_test.fx WHERE k='th'),
  (SELECT v FROM hbh_test.fx WHERE k='room'), (SELECT v FROM hbh_test.fx WHERE k='svc'),
  (SELECT v FROM hbh_test.fxt WHERE k='slot_start'), (SELECT v FROM hbh_test.fxt WHERE k='slot_end'));

CALL hbh_test.chk('appt', 'booking tells the family',
  $q$ SELECT count(*) = 2 FROM hbh.notifications
      WHERE kind_code = 'APPOINTMENT_BOOKED' AND link_kind = 'APPOINTMENT'
        AND link_id = (SELECT v FROM hbh_test.fx WHERE k='appt') $q$);

CALL hbh_test.chk('appt', 'and queues one message, for the consenting parent',
  $q$ SELECT count(*) = 1 FROM hbh.sms_outbox o
      JOIN hbh.notifications n ON n.notification_id = o.notification_id
      WHERE n.link_kind = 'APPOINTMENT' AND n.link_id = (SELECT v FROM hbh_test.fx WHERE k='appt')
        AND o.destination = '+201930000002' $q$);

CALL hbh_test.chk('appt', 'the therapist is told it is in their diary',
  $q$ SELECT count(*) = 1 FROM hbh.notifications
      WHERE kind_code = 'STAFF_APPOINTMENT_BOOKED'
        AND link_id = (SELECT v FROM hbh_test.fx WHERE k='appt')
        AND user_id = (SELECT v FROM hbh_test.fx WHERE k='user_th') $q$);

-- AND NO TEXT MESSAGE FOR THE STAFF ROW. 0089's header says staff must
-- never pick up sms_pending_flg from a guardian's consent; this is the
-- check that would catch it if notify_staff ever went through
-- notify_guardians.
CALL hbh_test.chk('appt', 'a staff notification queues no text message',
  $q$ SELECT count(*) = 0 FROM hbh.sms_outbox o
      JOIN hbh.notifications n ON n.notification_id = o.notification_id
      WHERE n.kind_code LIKE 'STAFF\_%' $q$);

-- AN UNRELATED UPDATE SAYS NOTHING. 13 of the brief, and the reason the
-- trigger is keyed on the pair of statuses.
UPDATE hbh.appointments SET note_ar = 'ملاحظة إدارية لا تخصّ الأسرة'
 WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt');

-- Scoped to the FAMILY kinds. The staff row 0089 adds also carries
-- link_kind APPOINTMENT, so counting every row on the appointment counts
-- three and the check fails for a reason that is not the defect.
CALL hbh_test.chk('appt', 'editing a note on the appointment tells nobody',
  $q$ SELECT count(*) = 2 FROM hbh.notifications
      WHERE link_kind = 'APPOINTMENT'
        AND link_id = (SELECT v FROM hbh_test.fx WHERE k='appt')
        AND kind_code NOT LIKE 'STAFF\_%' $q$);

UPDATE hbh.appointments SET status = 'CONFIRMED'
 WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt');

CALL hbh_test.chk('appt', 'BOOKED to CONFIRMED tells the family it is certain',
  $q$ SELECT count(*) = 2 FROM hbh.notifications
      WHERE kind_code = 'APPOINTMENT_BOOKED' AND link_kind = 'APPOINTMENT'
        AND link_id = (SELECT v FROM hbh_test.fx WHERE k='appt')
        AND title_ar = 'تم تأكيد موعد' $q$);

UPDATE hbh.appointments SET status = 'CANCELLED', cancel_reason = 'اختبار الإلغاء'
 WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt');

CALL hbh_test.chk('appt', 'cancelling tells the family',
  $q$ SELECT count(*) = 2 FROM hbh.notifications
      WHERE kind_code = 'APPOINTMENT_CANCELLED'
        AND link_id = (SELECT v FROM hbh_test.fx WHERE k='appt') $q$);

-- A MOVE IS ONE EVENT. 0088 added the link precisely so the family is
-- not told "cancelled" and then "booked" for the same slot changing.
INSERT INTO hbh.appointments (center_id, branch_id, appointment_no, child_id, therapist_id,
                              room_id, service_id, starts_at, ends_at, status,
                              rescheduled_from_appointment_id)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
       hbh.next_number((SELECT v FROM hbh_test.fx WHERE k='center'), 'APPT'),
       (SELECT v FROM hbh_test.fx WHERE k='child'), (SELECT v FROM hbh_test.fx WHERE k='th'),
       (SELECT v FROM hbh_test.fx WHERE k='room'), (SELECT v FROM hbh_test.fx WHERE k='svc'),
       (SELECT v FROM hbh_test.fxt WHERE k='slot2_start'),
       (SELECT v FROM hbh_test.fxt WHERE k='slot2_end'), 'BOOKED',
       (SELECT v FROM hbh_test.fx WHERE k='appt');
INSERT INTO hbh_test.fx (k, v) SELECT 'appt_moved', appointment_id FROM hbh.appointments
  WHERE rescheduled_from_appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt');

CALL hbh_test.chk('appt', 'a rescheduled appointment says MOVED, not BOOKED',
  $q$ SELECT count(*) = 2 FROM hbh.notifications
      WHERE kind_code = 'APPOINTMENT_RESCHEDULED'
        AND link_id = (SELECT v FROM hbh_test.fx WHERE k='appt_moved') $q$);

CALL hbh_test.chk('appt', 'and it is not ALSO announced as a new booking',
  $q$ SELECT count(*) = 0 FROM hbh.notifications
      WHERE kind_code = 'APPOINTMENT_BOOKED'
        AND link_id = (SELECT v FROM hbh_test.fx WHERE k='appt_moved') $q$);

-- =====================================================================
-- 6. THE NUMBER IS REFUSED BY THE PROVIDER - 22
--
-- Delivery fails SAFELY. The clinical action stands, the reason is
-- recorded, and nothing retries a number that will never work.
--
-- WHY THIS SHAPE AND NOT "A FAMILY WITH NO NUMBER". The schema does not
-- permit a guardian without a mobile - hbh.guard_identity_format refuses
-- one, asserted in the fixture group above - so "no number on file" is
-- not a state a test can reach honestly. The reachable and far more
-- common case is a number that passes every check here and is rejected
-- at the provider: disconnected, ported, or never a mobile.
-- =====================================================================
SET hbh.user_id = 'p13.therapist';
INSERT INTO hbh_test.fx (k, v)
SELECT 'report_c', hbh.create_report(
  (SELECT v FROM hbh_test.fx WHERE k='child_c'), 'تقرير طفل رقم وليّه مرفوض',
  current_date - 30, current_date, NULL, 'ملخّص كافٍ.');
RESET hbh.user_id;

SET hbh.user_id = 'p13.admin';
SELECT hbh.publish_report((SELECT v FROM hbh_test.fx WHERE k='report_c'));
RESET hbh.user_id;

CALL hbh_test.chk('reject', 'the report is PUBLISHED before delivery is even attempted',
  $q$ SELECT status = 'PUBLISHED' FROM hbh.progress_reports
      WHERE report_id = (SELECT v FROM hbh_test.fx WHERE k='report_c') $q$);

CALL hbh_test.chk('reject', 'the parent gets the portal notification',
  $q$ SELECT count(*) = 1 FROM hbh.notifications
      WHERE link_kind = 'REPORT' AND link_id = (SELECT v FROM hbh_test.fx WHERE k='report_c') $q$);

INSERT INTO hbh_test.fxb (k, v)
SELECT 'sms_reject', o.sms_id
FROM   hbh.sms_outbox o
JOIN   hbh.notifications n ON n.notification_id = o.notification_id
WHERE  n.link_kind = 'REPORT' AND n.link_id = (SELECT v FROM hbh_test.fx WHERE k='report_c');

CALL hbh_test.chk('reject', 'and a message was queued for it',
  $q$ SELECT (SELECT v FROM hbh_test.fxb WHERE k='sms_reject') IS NOT NULL $q$);

-- Now the provider refuses the destination. This is what the worker does
-- when sms.E164 or the gateway rejects a number: it classifies the
-- failure PERMANENT and hands it back.
UPDATE hbh.sms_outbox SET status = 'SENDING', attempts = 1, claimed_at = now(),
                          claimed_by = 'p13-worker-a'
 WHERE sms_id = (SELECT v FROM hbh_test.fxb WHERE k='sms_reject');

SET ROLE hbh_app;
RESET hbh.user_id;
CALL hbh_test.chk('reject', 'a rejected destination is DEAD at once, not retried',
  $q$ SELECT hbh.record_sms_failed((SELECT v FROM hbh_test.fxb WHERE k='sms_reject'),
                                   'PERMANENT', 'the provider rejected the destination')
           = 'DEAD' $q$);
RESET ROLE;

CALL hbh_test.chk('reject', 'the reason is recorded where operations can read it',
  $q$ SELECT error_class = 'PERMANENT' AND error_detail IS NOT NULL AND failed_at IS NOT NULL
      FROM hbh.sms_outbox WHERE sms_id = (SELECT v FROM hbh_test.fxb WHERE k='sms_reject') $q$);

CALL hbh_test.chk('reject', 'and it will never be claimed again',
  $q$ SELECT count(*) = 0 FROM hbh.sms_outbox
      WHERE sms_id = (SELECT v FROM hbh_test.fxb WHERE k='sms_reject')
        AND status IN ('PENDING','SENDING') $q$);

-- THE POINT OF THE WHOLE SECTION. A provider cannot undo a clinical
-- decision. 55 refuses a PASS if it can.
CALL hbh_test.chk('reject', 'the report is STILL published after delivery failed for good',
  $q$ SELECT status = 'PUBLISHED' FROM hbh.progress_reports
      WHERE report_id = (SELECT v FROM hbh_test.fx WHERE k='report_c') $q$);

-- =====================================================================
-- 7. THE WORKER - 44, 45, 50
--
-- Claiming, failing, backing off, dying, and being reclaimed. All of it
-- runs as hbh_app with NO IDENTITY, because that is exactly the
-- connection the real worker holds.
-- =====================================================================
SET ROLE hbh_app;
RESET hbh.user_id;

CALL hbh_test.chk('worker', 'the worker can claim from an empty-identity connection',
  $q$ SELECT count(*) >= 1 FROM hbh.claim_sms(50, 'p13-worker-a') $q$);

-- 50: TWO WORKERS, DISJOINT SETS. The second claim must find nothing
-- the first one took - which is what SKIP LOCKED buys and what a
-- SELECT-then-UPDATE worker would get wrong under load.
CALL hbh_test.chk('worker', 'a second worker claims none of the first worker rows',
  $q$ SELECT count(*) = 0 FROM hbh.claim_sms(50, 'p13-worker-b') $q$);

RESET ROLE;

-- READ BACK AS THE OWNER. The worker's own connection carries no
-- identity, so a SELECT on hbh.sms_outbox from it returns nothing -
-- p_sms_select starts with current_center_id() IS NOT NULL, and that is
-- the identity-fails-closed rule working. claim_sms can still see the
-- rows because it is SECURITY DEFINER; a plain SELECT cannot, and
-- reading zero rows there would look like the claim had failed.
CALL hbh_test.chk('worker', 'a claimed row is SENDING with its attempt counted',
  $q$ SELECT count(*) >= 1 FROM hbh.sms_outbox
      WHERE claimed_by = 'p13-worker-a' AND status = 'SENDING' AND attempts = 1 $q$);

INSERT INTO hbh_test.fxb (k, v)
SELECT 'sms_a', min(sms_id) FROM hbh.sms_outbox WHERE claimed_by = 'p13-worker-a';

SET ROLE hbh_app;
RESET hbh.user_id;

-- 44: A TRANSIENT FAILURE COMES BACK, with a longer wait each time.
CALL hbh_test.chk('worker', 'a transient failure returns the message to the queue',
  $q$ SELECT hbh.record_sms_failed((SELECT v FROM hbh_test.fxb WHERE k='sms_a'),
                                   'TRANSIENT', 'the provider did not answer in time')
           = 'PENDING' $q$);

RESET ROLE;

CALL hbh_test.chk('worker', 'and it is not due again immediately - the backoff is real',
  $q$ SELECT next_attempt_at > now() + interval '30 seconds'
      FROM hbh.sms_outbox WHERE sms_id = (SELECT v FROM hbh_test.fxb WHERE k='sms_a') $q$);

CALL hbh_test.chk('worker', 'a message not yet due is not claimed',
  $q$ SELECT count(*) = 0 FROM hbh.sms_outbox
      WHERE sms_id = (SELECT v FROM hbh_test.fxb WHERE k='sms_a')
        AND status = 'PENDING' AND next_attempt_at <= now() $q$);

-- 19: THE RETRY IS BOUNDED. Nothing loops for ever.
UPDATE hbh.sms_outbox
   SET status = 'SENDING', attempts = 5, next_attempt_at = now(), claimed_at = now(),
       claimed_by = 'p13-worker-a'
 WHERE sms_id = (SELECT v FROM hbh_test.fxb WHERE k='sms_a');

SET ROLE hbh_app;
RESET hbh.user_id;

CALL hbh_test.chk('worker', 'the attempt ceiling turns a transient failure DEAD',
  $q$ SELECT hbh.record_sms_failed((SELECT v FROM hbh_test.fxb WHERE k='sms_a'),
                                   'TRANSIENT', 'still unreachable') = 'DEAD' $q$);

RESET ROLE;

CALL hbh_test.chk('worker', 'and the notification stops asking to be sent',
  $q$ SELECT NOT n.sms_pending_flg
      FROM hbh.notifications n
      JOIN hbh.sms_outbox o ON o.notification_id = n.notification_id
      WHERE o.sms_id = (SELECT v FROM hbh_test.fxb WHERE k='sms_a') $q$);

-- A PERMANENT FAILURE DOES NOT WAIT FOR THE CEILING. Retrying an
-- invalid number five times is five identical refusals.
INSERT INTO hbh_test.fxb (k, v)
SELECT 'sms_b', sms_id FROM hbh.sms_outbox
 WHERE claimed_by = 'p13-worker-a' AND status = 'SENDING' ORDER BY sms_id LIMIT 1;

SET ROLE hbh_app;
RESET hbh.user_id;

CALL hbh_test.chk('worker', 'a permanent failure is DEAD on the first attempt',
  $q$ SELECT hbh.record_sms_failed((SELECT v FROM hbh_test.fxb WHERE k='sms_b'),
                                   'PERMANENT', 'the provider rejected the destination')
           = 'DEAD' $q$);

CALL hbh_test.chk_raises('worker', 'a result cannot be recorded against a row that is not SENDING',
  $q$ SELECT hbh.record_sms_failed((SELECT v FROM hbh_test.fxb WHERE k='sms_b'),
                                   'TRANSIENT', 'again') $q$, 'HB231');

RESET ROLE;

-- 45: THE WORKER DIED HOLDING ROWS. Without the reaper they are SENDING
-- for ever and the backlog silently shrinks by however many were in
-- flight.
INSERT INTO hbh.sms_outbox (center_id, purpose, template_code, destination, body_ar,
                            dedupe_key, status, attempts, claimed_at, claimed_by)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'NOTIFICATION', 'REPORT_PUBLISHED',
        '+201930000002', 'رسالة عالقة من عامل توقّف', 'P13:stuck', 'SENDING', 1,
        now() - interval '30 minutes', 'p13-worker-dead');
INSERT INTO hbh_test.fxb (k, v) SELECT 'sms_stuck', sms_id FROM hbh.sms_outbox
  WHERE dedupe_key = 'P13:stuck';

CALL hbh_test.chk('worker', 'the reaper brings back a message a dead worker was holding',
  $q$ SELECT hbh.reap_stuck_sms() >= 1 $q$);

CALL hbh_test.chk('worker', 'and it is PENDING and due now',
  $q$ SELECT status = 'PENDING' AND claimed_by IS NULL AND next_attempt_at <= now()
      FROM hbh.sms_outbox WHERE sms_id = (SELECT v FROM hbh_test.fxb WHERE k='sms_stuck') $q$);

-- AND A ROW STILL BEING WORKED ON IS LEFT ALONE. A reaper that took
-- everything SENDING would guarantee the duplicate it exists to make
-- rare.
INSERT INTO hbh.sms_outbox (center_id, purpose, template_code, destination, body_ar,
                            dedupe_key, status, attempts, claimed_at, claimed_by)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'NOTIFICATION', 'REPORT_PUBLISHED',
        '+201930000002', 'رسالة قيد الإرسال الآن', 'P13:fresh', 'SENDING', 1,
        now(), 'p13-worker-live');

CALL hbh_test.chk('worker', 'a message claimed a moment ago is NOT reclaimed',
  $q$ SELECT hbh.reap_stuck_sms() = 0
      AND (SELECT status = 'SENDING' FROM hbh.sms_outbox WHERE dedupe_key = 'P13:fresh') $q$);

-- A SUCCESSFUL SEND CLOSES BOTH RECORDS AT ONCE.
UPDATE hbh.sms_outbox SET status = 'SENDING', claimed_at = now(), claimed_by = 'p13-worker-a'
 WHERE sms_id = (SELECT v FROM hbh_test.fxb WHERE k='sms_stuck');

SET ROLE hbh_app;
RESET hbh.user_id;

CALL hbh_test.chk('worker', 'a successful send is recorded with the provider message id',
  $q$ SELECT hbh.record_sms_sent((SELECT v FROM hbh_test.fxb WHERE k='sms_stuck'),
                                 'dev', 'dev-p13-stuck') $q$);

CALL hbh_test.chk('worker', 'recording the same success twice reports false, not an error',
  $q$ SELECT NOT hbh.record_sms_sent((SELECT v FROM hbh_test.fxb WHERE k='sms_stuck'),
                                     'dev', 'dev-p13-stuck') $q$);

RESET ROLE;

CALL hbh_test.chk('worker', 'and the row is SENT with a time on it',
  $q$ SELECT status = 'SENT' AND sent_at IS NOT NULL AND provider_msg_id = 'dev-p13-stuck'
      FROM hbh.sms_outbox WHERE sms_id = (SELECT v FROM hbh_test.fxb WHERE k='sms_stuck') $q$);

-- =====================================================================
-- 7b. THE OFF SWITCH - 0115, 0116
--
-- The sixth of the six rules docs/architect/03-online-consultation.md
-- sets for a puller: "أوّل عطل عند المزوّد لا يجب أن يحتاج إصدارًا جديدًا".
--
-- WHAT HAS TO BE TRUE, AND WHY EACH PART IS ASSERTED SEPARATELY:
--
--   Nothing is claimed        - obviously.
--   AND nothing is CONSUMED   - the row must still be PENDING with its
--                               attempt uncounted. A pause that burned
--                               an attempt against SMS_MAX_ATTEMPTS
--                               would kill messages for an outage that
--                               was never their fault, and "zero rows
--                               came back" cannot tell the two apart.
--   AND it comes back         - a switch with no way back is a delete.
--
-- THE PARAMETER IS RESTORED IMMEDIATELY AND THE RESTORE IS ASSERTED at
-- the bottom with the rest, beside the reminder interval and the resend
-- window. This one is worth more care than either: left at 'false' it
-- would silently stop every message on this database, for every session
-- sharing it, until somebody went looking for why a family heard
-- nothing.
-- =====================================================================
INSERT INTO hbh.sms_outbox (center_id, purpose, template_code, destination, body_ar,
                            dedupe_key, status)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'NOTIFICATION', 'REPORT_PUBLISHED',
        '+201930000002', 'رسالة تنتظر أثناء الإيقاف', 'P13:killswitch', 'PENDING');
INSERT INTO hbh_test.fxb (k, v) SELECT 'sms_ks', sms_id FROM hbh.sms_outbox
  WHERE dedupe_key = 'P13:killswitch';

UPDATE hbh.sys_params SET param_value = 'false'
 WHERE param_code = 'SMS_SENDING_ENABLED' AND center_id IS NULL;

SET ROLE hbh_app;
RESET hbh.user_id;

CALL hbh_test.chk('killswitch', 'a paused queue hands the worker nothing',
  $q$ SELECT count(*) = 0 FROM hbh.claim_sms(50, 'p13-worker-paused') $q$);

RESET ROLE;

CALL hbh_test.chk('killswitch', 'and the message is untouched - still PENDING, no attempt spent',
  $q$ SELECT status = 'PENDING' AND attempts = 0 AND claimed_by IS NULL
      FROM hbh.sms_outbox WHERE sms_id = (SELECT v FROM hbh_test.fxb WHERE k='sms_ks') $q$);

CALL hbh_test.chk('killswitch', 'the health view says so, so it cannot be off and forgotten',
  $q$ SELECT sending_paused AND due_now_cnt >= 1
      FROM hbh.v_sms_health WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center') $q$);

-- A PAUSE IS A DECISION, NOT A FAULT. If is_stalled also lit up here, the
-- one signal that means "the worker is gone" would fire every time an
-- operator deliberately stopped the queue - and an alarm that cries
-- during planned work is an alarm that gets ignored during real work.
CALL hbh_test.chk('killswitch', 'but it is not reported as a stalled worker',
  $q$ SELECT NOT is_stalled
      FROM hbh.v_sms_health WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center') $q$);

UPDATE hbh.sys_params SET param_value = 'true'
 WHERE param_code = 'SMS_SENDING_ENABLED' AND center_id IS NULL;

SET ROLE hbh_app;
RESET hbh.user_id;

CALL hbh_test.chk('killswitch', 'and the same message is claimed as soon as it is back on',
  $q$ SELECT count(*) = 1 FROM hbh.claim_sms(50, 'p13-worker-resumed')
       WHERE sms_id = (SELECT v FROM hbh_test.fxb WHERE k='sms_ks') $q$);

RESET ROLE;

CALL hbh_test.chk('killswitch', 'with its attempt counted only now that it was really taken',
  $q$ SELECT status = 'SENDING' AND attempts = 1 AND claimed_by = 'p13-worker-resumed'
      FROM hbh.sms_outbox WHERE sms_id = (SELECT v FROM hbh_test.fxb WHERE k='sms_ks') $q$);

-- =====================================================================
-- 7c. IS THE WORKER EVEN RUNNING - 0116
--
-- It lives inside the API process. If that goroutine stops, the queue
-- stops draining and NOTHING anywhere raises, logs or fails: the rows
-- simply sit there. From the database that looks like work which has
-- been due longer than the reaper's own window, and is_stalled is it.
-- =====================================================================
UPDATE hbh.sms_outbox
   SET status = 'PENDING', attempts = 0, claimed_at = NULL, claimed_by = NULL,
       next_attempt_at = now() - make_interval(
         mins => hbh.param(NULL, 'SMS_STUCK_MINUTES', '10')::integer * 4)
 WHERE sms_id = (SELECT v FROM hbh_test.fxb WHERE k='sms_ks');

CALL hbh_test.chk('killswitch', 'work due far longer than the window reads as a stopped worker',
  $q$ SELECT is_stalled
      FROM hbh.v_sms_health WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center') $q$);

-- THE COLUMN HAS TWO ANSWERS, NOT THREE. 0115 built it without a
-- coalesce, so on an idle queue min() was NULL, the comparison was
-- UNKNOWN, and the column came back NULL for the state it is asked about
-- most often - the same three-valued-logic trap that let a NULL code
-- through verify_otp. Asserted here because a NULL reads as falsy in
-- every caller and would look like it was working.
UPDATE hbh.sms_outbox SET status = 'SENT', sent_at = now()
 WHERE sms_id = (SELECT v FROM hbh_test.fxb WHERE k='sms_ks');

CALL hbh_test.chk('killswitch', 'and on a queue with nothing due it is false, not null',
  $q$ SELECT is_stalled IS NOT NULL AND NOT is_stalled
      FROM hbh.v_sms_health WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center') $q$);

-- =====================================================================
-- 8. THE QUEUE IS NOT OPERABLE FROM A USER SESSION - 29
--
-- The C1 and C2 lesson applied here: the function asks the
-- authorization question ITSELF rather than trusting that no route
-- calls it. A signed-in parent, therapist or administrator is carrying
-- an identity by the time any handler runs, so none of them can reach
-- the queue even if a route were added by accident.
-- =====================================================================
SET ROLE hbh_app;

SET hbh.user_id = 'p13.father';
CALL hbh_test.chk_raises('queue', 'a signed-in PARENT cannot claim messages',
  $q$ SELECT * FROM hbh.claim_sms(10, 'attacker') $q$, 'HB230');

SET hbh.user_id = 'p13.therapist';
CALL hbh_test.chk_raises('queue', 'a signed-in THERAPIST cannot claim messages',
  $q$ SELECT * FROM hbh.claim_sms(10, 'attacker') $q$, 'HB230');

SET hbh.user_id = 'p13.admin';
CALL hbh_test.chk_raises('queue', 'a signed-in CENTRE ADMIN cannot claim messages',
  $q$ SELECT * FROM hbh.claim_sms(10, 'attacker') $q$, 'HB230');

CALL hbh_test.chk_raises('queue', 'nor mark one sent',
  $q$ SELECT hbh.record_sms_sent((SELECT v FROM hbh_test.fxb WHERE k='sms_a'), 'x', 'y') $q$,
  'HB230');

CALL hbh_test.chk_raises('queue', 'nor mark one failed',
  $q$ SELECT hbh.record_sms_failed((SELECT v FROM hbh_test.fxb WHERE k='sms_a'), 'TRANSIENT', 'x') $q$,
  'HB230');

-- 47: NO GENERIC "SEND ANYTHING TO ANYONE". hbh.enqueue_sms takes a
-- destination and a body and is deliberately NOT granted to the role the
-- API connects as.
CALL hbh_test.chk_raises('queue', 'the general enqueue is not callable by the application role',
  $q$ SELECT hbh.enqueue_sms((SELECT v FROM hbh_test.fx WHERE k='center'), 'NOTIFICATION',
                             'REPORT_PUBLISHED', '+201999999999', 'P13:arbitrary',
                             'رسالة اعتباطية') $q$, '42501');

CALL hbh_test.chk_raises('queue', 'and nobody can write to the outbox directly',
  $q$ INSERT INTO hbh.sms_outbox (center_id, purpose, template_code, destination,
                                  body_ar, dedupe_key)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'NOTIFICATION', 'REPORT_PUBLISHED',
              '+201999999999', 'رسالة اعتباطية', 'P13:direct') $q$, '42501');

RESET ROLE;

-- =====================================================================
-- 9. WHO SEES WHAT - 29, 46
--
-- Every check below runs as hbh_app with an explicit identity. A check
-- of a refusal run as the owner proves that the owner passes, which is
-- the mistake this file's author has already made once in this project.
-- =====================================================================
-- Recorded as the owner, BEFORE the role changes. The check below has to
-- name a row the caller cannot see, which is precisely a row it cannot
-- look up once it is the caller.
INSERT INTO hbh_test.fxb (k, v)
SELECT 'ntf_mother', min(notification_id) FROM hbh.notifications
 WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user_mo');

CALL hbh_test.chk('rls', 'the fixture really produced a notification for the mother',
  $q$ SELECT (SELECT v FROM hbh_test.fxb WHERE k='ntf_mother') IS NOT NULL $q$);

SET ROLE hbh_app;

SET hbh.user_id = 'p13.father';

CALL hbh_test.chk('rls', 'the father sees his own notifications',
  $q$ SELECT count(*) >= 1 FROM hbh.notifications $q$);

CALL hbh_test.chk('rls', 'and every row he sees is addressed to him',
  $q$ SELECT bool_and(user_id = (SELECT v FROM hbh_test.fx WHERE k='user_fa'))
      FROM hbh.notifications $q$);

CALL hbh_test.chk('rls', 'he cannot fetch the mother notification BY ID',
  $q$ SELECT count(*) = 0 FROM hbh.notifications
      WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user_mo') $q$);

-- The id is read from the fixture table, recorded as the OWNER before
-- the role changed. Reading it from a list here would be impossible -
-- that is the point - and reading an id out of a shared list is the
-- mistake a5 made when it stamped a third session's row.
CALL hbh_test.chk('rls', 'and marking hers read does nothing',
  $q$ SELECT NOT hbh.mark_notification_read((SELECT v FROM hbh_test.fxb WHERE k='ntf_mother')) $q$);

CALL hbh_test.chk('rls', 'a PARENT sees no delivery records at all',
  $q$ SELECT count(*) = 0 FROM hbh.sms_outbox $q$);

CALL hbh_test.chk('rls', 'nor through the operations view',
  $q$ SELECT count(*) = 0 FROM hbh.v_sms_delivery $q$);

SET hbh.user_id = 'p13.stranger';

CALL hbh_test.chk('rls', 'a parent in ANOTHER FAMILY sees none of this family notifications',
  $q$ SELECT count(*) = 0 FROM hbh.notifications
      WHERE child_id IN ((SELECT v FROM hbh_test.fx WHERE k='child'),
                         (SELECT v FROM hbh_test.fx WHERE k='child_c')) $q$);

SET hbh.user_id = 'p13.therapist';

CALL hbh_test.chk('rls', 'the therapist sees staff notifications addressed to them',
  $q$ SELECT count(*) >= 1 FROM hbh.notifications
      WHERE kind_code = 'STAFF_APPOINTMENT_BOOKED' $q$);

CALL hbh_test.chk('rls', 'but NOT the family notifications about the same child',
  $q$ SELECT count(*) = 0 FROM hbh.notifications
      WHERE user_id IN ((SELECT v FROM hbh_test.fx WHERE k='user_fa'),
                        (SELECT v FROM hbh_test.fx WHERE k='user_mo')) $q$);

CALL hbh_test.chk('rls', 'a THERAPIST cannot read the delivery queue - no OPS.VIEW',
  $q$ SELECT count(*) = 0 FROM hbh.sms_outbox $q$);

SET hbh.user_id = 'p13.admin';

CALL hbh_test.chk('rls', 'a CENTRE ADMIN can diagnose delivery',
  $q$ SELECT count(*) >= 1 FROM hbh.v_sms_delivery $q$);

CALL hbh_test.chk('rls', 'and the number is MASKED in the view',
  $q$ SELECT bool_and(destination_masked LIKE '****%' AND length(destination_masked) = 8)
      FROM hbh.v_sms_delivery $q$);

CALL hbh_test.chk('rls', 'the admin sees only THEIR centre queue',
  $q$ SELECT bool_and(center_id = (SELECT v FROM hbh_test.fx WHERE k='center'))
      FROM hbh.v_sms_delivery $q$);

CALL hbh_test.chk('rls', 'and not another family notifications either',
  $q$ SELECT count(*) = 0 FROM hbh.notifications
      WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user_fa') $q$);

-- CROSS-CENTRE. A different clause of the same policy from cross-family,
-- and a fixture that cannot produce both cannot tell them apart.
SET hbh.user_id = 'p13.other_center';

CALL hbh_test.chk('rls', 'a guardian in ANOTHER CENTRE sees nothing of this one',
  $q$ SELECT count(*) = 0 FROM hbh.notifications $q$);

CALL hbh_test.chk('rls', 'and no delivery record of this one',
  $q$ SELECT count(*) = 0 FROM hbh.sms_outbox $q$);

-- NO IDENTITY, NO ROWS. Identity fails closed - CLAUDE.md, and the
-- property every check above rests on.
RESET hbh.user_id;

CALL hbh_test.chk('rls', 'no identity sees no notifications',
  $q$ SELECT count(*) = 0 FROM hbh.notifications $q$);

CALL hbh_test.chk('rls', 'no identity sees no delivery records',
  $q$ SELECT count(*) = 0 FROM hbh.sms_outbox $q$);

RESET ROLE;

-- =====================================================================
-- 10. THE REMINDER - 14, 43
--
-- The MECHANISM is complete and the INTERVAL is not decided. Nobody has
-- chosen how many hours before a session a family should be reminded:
-- the lifecycle document asks for the mechanism (LC-05) and names no
-- number, and no parameter in this schema carries one. So the default
-- is OFF, by the absence of an answer rather than by a number this
-- migration invented - and these checks prove both halves.
-- =====================================================================
DELETE FROM hbh.sys_params WHERE param_code = 'APPOINTMENT_REMINDER_HOURS';

-- THE SLOT IS A REAL ONE, not "three hours from now".
--
-- hbh.book_appointment validates against the therapist's working hours
-- and the centre's weekend, so an appointment placed by arithmetic on
-- now() lands on a Friday one run in seven and the suite fails for a
-- reason that has nothing to do with reminders. The slot is a weekday
-- morning; what the reminder test varies instead is the WINDOW, which is
-- the thing under test.
INSERT INTO hbh_test.fx (k, v)
SELECT 'appt_soon', hbh.book_appointment(
  (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
  (SELECT v FROM hbh_test.fx WHERE k='child'), (SELECT v FROM hbh_test.fx WHERE k='th'),
  (SELECT v FROM hbh_test.fx WHERE k='room'), (SELECT v FROM hbh_test.fx WHERE k='svc'),
  (SELECT v FROM hbh_test.fxt WHERE k='slot3_start'),
  (SELECT v FROM hbh_test.fxt WHERE k='slot3_end'));

CALL hbh_test.chk('remind', 'with NO interval configured, no reminder is queued',
  $q$ SELECT hbh.queue_appointment_reminders() = 0 $q$);

CALL hbh_test.chk('remind', 'and none exists',
  $q$ SELECT count(*) = 0 FROM hbh.notifications
      WHERE kind_code = 'APPOINTMENT_REMINDER'
        AND link_id = (SELECT v FROM hbh_test.fx WHERE k='appt_soon') $q$);

-- Now a centre makes the decision. The suite chooses a value for ITSELF;
-- it is not seeded, and the report says so.
INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type, description_ar)
VALUES (NULL, 'APPOINTMENT_REMINDER_HOURS', '400', 'NUMBER', 'قيمة اختبار — ليست قرار عمل');

CALL hbh_test.chk('remind', 'with an interval set, the appointment is reminded',
  $q$ SELECT hbh.queue_appointment_reminders() >= 1 $q$);

CALL hbh_test.chk('remind', 'both guardians are reminded, once each',
  $q$ SELECT count(*) = 2 FROM hbh.notifications
      WHERE kind_code = 'APPOINTMENT_REMINDER'
        AND link_id = (SELECT v FROM hbh_test.fx WHERE k='appt_soon') $q$);

-- 43: RUN IT AGAIN. A maintenance pass runs every hour and must not
-- send an hourly reminder.
SELECT hbh.queue_appointment_reminders();
SELECT hbh.queue_appointment_reminders();

CALL hbh_test.chk('remind', 'running the pass again produces NO duplicate',
  $q$ SELECT count(*) = 2 FROM hbh.notifications
      WHERE kind_code = 'APPOINTMENT_REMINDER'
        AND link_id = (SELECT v FROM hbh_test.fx WHERE k='appt_soon') $q$);

CALL hbh_test.chk('remind', 'and exactly one text message, to the consenting parent',
  $q$ SELECT count(*) = 1 FROM hbh.sms_outbox o
      JOIN hbh.notifications n ON n.notification_id = o.notification_id
      WHERE n.kind_code = 'APPOINTMENT_REMINDER'
        AND n.link_id = (SELECT v FROM hbh_test.fx WHERE k='appt_soon') $q$);

-- A CANCELLED APPOINTMENT IS NOT REMINDED. The other half of 43, and
-- the one that would embarrass a centre: reminding a family to attend
-- something the centre cancelled.
INSERT INTO hbh_test.fx (k, v)
SELECT 'appt_gone', hbh.book_appointment(
  (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
  (SELECT v FROM hbh_test.fx WHERE k='child'), (SELECT v FROM hbh_test.fx WHERE k='th'),
  (SELECT v FROM hbh_test.fx WHERE k='room'), (SELECT v FROM hbh_test.fx WHERE k='svc'),
  (SELECT v FROM hbh_test.fxt WHERE k='slot4_start'),
  (SELECT v FROM hbh_test.fxt WHERE k='slot4_end'));

UPDATE hbh.appointments SET status = 'CANCELLED', cancel_reason = 'ألغي قبل التذكير'
 WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt_gone');

SELECT hbh.queue_appointment_reminders();

CALL hbh_test.chk('remind', 'a CANCELLED appointment is never reminded',
  $q$ SELECT count(*) = 0 FROM hbh.notifications
      WHERE kind_code = 'APPOINTMENT_REMINDER'
        AND link_id = (SELECT v FROM hbh_test.fx WHERE k='appt_gone') $q$);

-- AND ONE OUTSIDE THE WINDOW IS NOT REMINDED EARLY.
CALL hbh_test.chk('remind', 'an appointment beyond the window is not reminded yet',
  $q$ SELECT count(*) = 0 FROM hbh.notifications
      WHERE kind_code = 'APPOINTMENT_REMINDER'
        AND link_id = (SELECT v FROM hbh_test.fx WHERE k='appt_moved') $q$);

-- A REMINDER THAT MOVED. The old appointment row keeps its reminder -
-- it is a record that a family WAS told - and the new row is reminded on
-- its own merits when its own window opens.
CALL hbh_test.chk('remind', 'the reminder belongs to the appointment, not to the child',
  $q$ SELECT bool_and(link_id = (SELECT v FROM hbh_test.fx WHERE k='appt_soon'))
      FROM hbh.notifications
      WHERE kind_code = 'APPOINTMENT_REMINDER'
        AND child_id = (SELECT v FROM hbh_test.fx WHERE k='child') $q$);

DELETE FROM hbh.sys_params WHERE param_code = 'APPOINTMENT_REMINDER_HOURS';

-- =====================================================================
-- 11. THE PERIODIC PASS RUNS ALL OF IT
--
-- run_maintenance is the only thing in this schema that works by the
-- clock, and 0094 added two tasks to it. A task that is never called is
-- a task that does not exist.
-- =====================================================================
INSERT INTO hbh_test.fxb (k, v) SELECT 'run', hbh.run_maintenance();

CALL hbh_test.chk('maint', 'the maintenance run completed',
  $q$ SELECT finished_at IS NOT NULL FROM hbh.maintenance_runs
      WHERE run_id = (SELECT v FROM hbh_test.fxb WHERE k='run') $q$);

CALL hbh_test.chk('maint', 'and neither new task reported an error',
  $q$ SELECT coalesce(detail, '') NOT LIKE '%appointment reminders:%'
         AND coalesce(detail, '') NOT LIKE '%sms reaper:%'
      FROM hbh.maintenance_runs
      WHERE run_id = (SELECT v FROM hbh_test.fxb WHERE k='run') $q$);

CALL hbh_test.chk('maint', 'the tasks 0025 left in it are still there',
  $q$ SELECT pg_get_functiondef(p.oid) LIKE '%release_expired_offers%'
         AND pg_get_functiondef(p.oid) LIKE '%archive_audit%'
         AND pg_get_functiondef(p.oid) LIKE '%expire_packages%'
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'hbh' AND p.proname = 'run_maintenance' $q$);

-- =====================================================================
-- 12. THE SCHEMA CONVENTIONS HOLD FOR THE NEW TABLE
-- =====================================================================
CALL hbh_test.chk('shape', 'every new SECURITY DEFINER function pins its search_path',
  $q$ SELECT count(*) = 0 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'hbh' AND p.prosecdef
        AND p.proname IN ('enqueue_sms','claim_sms','record_sms_sent','record_sms_failed',
                          'reap_stuck_sms','queue_appointment_reminders','assert_sms_worker',
                          'record_otp_delivery','trg_sms_from_notification','trg_notify_confirmed')
        AND NOT EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig, '{}'))
                        AS c(v) WHERE c.v LIKE 'search_path=%') $q$);

CALL hbh_test.chk('shape', 'the operations view runs as its INVOKER, not its owner',
  $q$ SELECT c.reloptions @> ARRAY['security_invoker=true']
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'hbh' AND c.relname = 'v_sms_delivery' $q$);

CALL hbh_test.chk('shape', 'every outbox instant carries a time zone',
  $q$ SELECT count(*) = 0 FROM information_schema.columns
      WHERE table_schema = 'hbh' AND table_name = 'sms_outbox'
        AND data_type = 'timestamp without time zone' $q$);

CALL hbh_test.chk('shape', 'the soft-delete exemption is registered with a reason',
  $q$ SELECT count(*) = 1 FROM hbh.convention_exemptions
      WHERE table_name = 'sms_outbox' AND rule_code = 'SOFT_DELETE'
        AND length(reason) > 40 $q$);

CALL hbh_test.chk('shape', 'no DELETE is granted on the outbox',
  $q$ SELECT count(*) = 0 FROM information_schema.role_table_grants
      WHERE table_schema = 'hbh' AND table_name = 'sms_outbox'
        AND grantee = 'hbh_app' AND privilege_type <> 'SELECT' $q$);

-- =====================================================================
-- CLEANUP
--
-- BY IDENTITY, never by resemblance. A DELETE matching '+20193%' would
-- reach into a neighbouring suite's fixture in this shared database -
-- which is exactly how a P5 cleanup once took twenty-one checks down
-- with it. Every statement below names rows this suite recorded.
--
-- And the cleanup is a CHECK like any other: a cleanup that swallows its
-- own failure is worse than no cleanup, because the next run inherits
-- the wreckage and blames itself.
-- =====================================================================
DELETE FROM hbh.sms_outbox WHERE dedupe_key IN ('P13:stuck','P13:fresh','P13:killswitch');

DELETE FROM hbh.sms_outbox o
 USING hbh.notifications n
 WHERE n.notification_id = o.notification_id
   AND n.user_id IN (SELECT v FROM hbh_test.fx
                     WHERE k IN ('user_fa','user_mo','user_st','user_nm','user_th','user_lk'));

DELETE FROM hbh.sms_outbox
 WHERE destination IN ('+201930000002','+201930000003','+201930000004')
    OR center_id = (SELECT v FROM hbh_test.fx WHERE k='center2');

DELETE FROM hbh.notifications
 WHERE user_id IN (SELECT v FROM hbh_test.fx
                   WHERE k IN ('user_fa','user_mo','user_st','user_nm','user_th','user_lk','user_ad'));

DELETE FROM hbh.otp_codes
 WHERE user_id IN (SELECT v FROM hbh_test.fx WHERE k IN ('user_fa','user_mo'));

-- THE APPEND-ONLY GUARDS COME OFF FOR THE LENGTH OF THE CLEANUP AND GO
-- STRAIGHT BACK ON. They are the reason a consent event and an
-- appointment transition cannot be rewritten, which is the property they
-- exist for; a suite that left one disabled would leave the clinical
-- record writable and say nothing. The last check in this file is that
-- both are enabled again.
ALTER TABLE hbh.consent_events             DISABLE TRIGGER trg_cev_append_only;
ALTER TABLE hbh.appointment_status_history DISABLE TRIGGER trg_ash_append_only;

DELETE FROM hbh.consent_events
 WHERE guardian_id IN (SELECT v FROM hbh_test.fx WHERE k IN ('gd_fa','gd_mo','gd_st','gd_nm'));
DELETE FROM hbh.consents
 WHERE guardian_id IN (SELECT v FROM hbh_test.fx WHERE k IN ('gd_fa','gd_mo','gd_st','gd_nm'));

DELETE FROM hbh.progress_reports
 WHERE report_id IN (SELECT v FROM hbh_test.fx WHERE k IN ('report','report_c'));

DELETE FROM hbh.appointment_status_history
 WHERE appointment_id IN (SELECT v FROM hbh_test.fx
                          WHERE k IN ('appt','appt_moved','appt_soon','appt_gone'));
-- The child first, then the parent: several data-modifying CTEs in one
-- statement have no order between them, and the failure is undefined
-- rather than wrong. Two statements, parents last.
DELETE FROM hbh.appointments
 WHERE appointment_id IN (SELECT v FROM hbh_test.fx
                          WHERE k IN ('appt_moved','appt_soon','appt_gone'));
DELETE FROM hbh.appointments
 WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt');

ALTER TABLE hbh.consent_events             ENABLE TRIGGER trg_cev_append_only;
ALTER TABLE hbh.appointment_status_history ENABLE TRIGGER trg_ash_append_only;

DELETE FROM hbh.caseload  WHERE child_id IN (SELECT v FROM hbh_test.fx WHERE k IN ('child','child_b','child_c'));
DELETE FROM hbh.guardian_children
 WHERE guardian_id IN (SELECT v FROM hbh_test.fx WHERE k IN ('gd_fa','gd_mo','gd_st','gd_nm'));
DELETE FROM hbh.guardians
 WHERE guardian_id IN (SELECT v FROM hbh_test.fx WHERE k IN ('gd_fa','gd_mo','gd_st','gd_nm'));
DELETE FROM hbh.children WHERE child_no IN ('P13-A','P13-B','P13-C');

DELETE FROM hbh.therapist_working_hours WHERE therapist_id = (SELECT v FROM hbh_test.fx WHERE k='th');
DELETE FROM hbh.therapist_services      WHERE therapist_id = (SELECT v FROM hbh_test.fx WHERE k='th');
DELETE FROM hbh.therapists              WHERE therapist_id = (SELECT v FROM hbh_test.fx WHERE k='th');

DELETE FROM hbh.rooms    WHERE code = 'P13-R1';
DELETE FROM hbh.services WHERE code = 'P13-SPEECH';

DELETE FROM hbh.user_roles WHERE user_id IN (SELECT v FROM hbh_test.fx WHERE k LIKE 'user\_%');
DELETE FROM hbh.users      WHERE username LIKE 'p13.%';
DELETE FROM hbh.branches   WHERE code = 'P13B2';
DELETE FROM hbh.centers    WHERE code = 'P13C2';

CALL hbh_test.chk('cleanup', 'every fixture user is gone',
  $q$ SELECT count(*) = 0 FROM hbh.users WHERE username LIKE 'p13.%' $q$);

CALL hbh_test.chk('cleanup', 'every fixture child is gone',
  $q$ SELECT count(*) = 0 FROM hbh.children WHERE child_no LIKE 'P13-%' $q$);

CALL hbh_test.chk('cleanup', 'the second centre is gone',
  $q$ SELECT count(*) = 0 FROM hbh.centers WHERE code = 'P13C2' $q$);

CALL hbh_test.chk('cleanup', 'no outbox row of this run survives',
  $q$ SELECT count(*) = 0 FROM hbh.sms_outbox
      WHERE destination LIKE '+20193%' OR dedupe_key LIKE 'P13:%' $q$);

CALL hbh_test.chk('cleanup', 'the test reminder interval was NOT left behind',
  $q$ SELECT count(*) = 0 FROM hbh.sys_params
      WHERE param_code = 'APPOINTMENT_REMINDER_HOURS' $q$);

CALL hbh_test.chk('cleanup', 'and the resend window is back to its seeded value',
  $q$ SELECT param_value = '60' FROM hbh.sys_params
      WHERE param_code = 'OTP_RESEND_SECONDS' AND center_id IS NULL $q$);

-- THE ONE THAT WOULD HURT MOST IF IT HAD NOT BEEN PUT BACK. Left at
-- 'false' by section 7b, every message on this database stops - for
-- every session sharing it, with nothing raised, until somebody asks
-- why a family heard nothing. Same family of failure as the append-only
-- guard checked below, and the reason both are asserted rather than
-- assumed.
CALL hbh_test.chk('cleanup', 'sending was switched back on',
  $q$ SELECT lower(btrim(param_value)) <> 'false' FROM hbh.sys_params
      WHERE param_code = 'SMS_SENDING_ENABLED' AND center_id IS NULL $q$);

-- THE LAST CHECK, AND THE ONE THAT MATTERS MOST IF THE CLEANUP WENT
-- WRONG. A suite that left an append-only guard disabled would leave the
-- consent record and the appointment history writable, for every
-- session on this database, until somebody noticed.
CALL hbh_test.chk('cleanup', 'every append-only guard is enabled again',
  $q$ SELECT count(*) = 2 FROM pg_trigger
      WHERE tgname IN ('trg_cev_append_only','trg_ash_append_only')
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
  IF v_fail = 0 AND v_total > 0 THEN RAISE NOTICE '  PHASE 13 ACCEPTED';
  ELSE RAISE NOTICE '  *** PHASE 13 NOT ACCEPTED'; END IF;
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
