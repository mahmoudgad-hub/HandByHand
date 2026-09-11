-- =====================================================================
-- Hand By Hand (new) - PHASE 12 acceptance suite
--
-- Must print:  PHASE 12 ACCEPTED
--
-- HBH-010 - the family we enrolled can actually log in.
--
-- The decisive check is not that hbh.grant_portal_access returns a
-- number. It is that the SAME MOBILE is refused by hbh.request_otp
-- before the call and accepted after it - because that is the loop the
-- card exists to close, and a test that only inspects the function's
-- own return value would pass on a function that wrote to nothing the
-- login path reads.
--
-- Migration 0085.
-- =====================================================================

\set ON_ERROR_STOP off
\pset pager off

DROP SCHEMA IF EXISTS hbh_test CASCADE;
CREATE SCHEMA hbh_test;

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
    VALUES (p_grp, p_name, false, 'expected ' || p_sqlstate || ', statement succeeded');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, SQLSTATE = p_sqlstate,
            'expected ' || p_sqlstate || ', got ' || SQLSTATE || ' ' || SQLERRM);
  END;
END $$;

GRANT USAGE ON SCHEMA hbh_test TO hbh_app;
GRANT INSERT, SELECT ON hbh_test.results, hbh_test.fx TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh_test TO hbh_app;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA hbh_test TO hbh_app;

-- =====================================================================
-- FIXTURE
--
-- Deliberately the WHOLE path: an application arrives the way a family
-- sends one, is contacted, and is converted. Building the guardian by
-- hand would test grant_portal_access against a row convert_enrolment
-- never produces, which is exactly the gap that hid this bug.
-- =====================================================================
INSERT INTO hbh_test.fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO hbh_test.fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
       u.username, u.name, u.utype, u.mobile
FROM (VALUES
       ('pc.reception', 'استقبال اختبار ١٢', 'STAFF',     '+201800000001'),
       ('pc.therapist', 'أخصائي اختبار ١٢',  'THERAPIST', '+201800000002')
     ) AS u(username, name, utype, mobile);

INSERT INTO hbh_test.fx (k, v) SELECT 'user_rc', user_id FROM hbh.users WHERE username='pc.reception';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_th', user_id FROM hbh.users WHERE username='pc.therapist';

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT f.v, r.role_id
FROM   hbh_test.fx f
JOIN   hbh.roles r ON r.center_id = (SELECT v FROM hbh_test.fx WHERE k='center')
WHERE  (f.k = 'user_rc' AND r.code = 'RECEPTION')
   OR  (f.k = 'user_th' AND r.code = 'THERAPIST');

-- The application, submitted the anonymous way a real one is.
INSERT INTO hbh.enrolment_applications
  (center_id, branch_id, application_no, parent_name_ar, parent_mobile,
   relationship_code, child_name_ar, child_birth_date, child_gender, source_code, status)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'APP-P12-0001', 'وليّ أمر اختبار ١٢', '+201800009999',
        'FATHER', 'طفل اختبار ١٢', DATE '2021-03-03', 'M', 'WEB', 'CONTACTED');

INSERT INTO hbh_test.fx (k, v) SELECT 'app', application_id
  FROM hbh.enrolment_applications WHERE application_no = 'APP-P12-0001';

-- ---------------------------------------------------------------------
CALL hbh_test.chk('fixture', 'migration 0085 is applied',
  $q$ SELECT count(*) = 1 FROM hbh.schema_migrations WHERE version = '0085' $q$);

CALL hbh_test.chk('fixture', 'reception holds GUARDIAN.MANAGE and NOT USER.MANAGE',
  $q$ SELECT bool_and(has) FROM (
        SELECT p.code = 'GUARDIAN.MANAGE' AS has
        FROM hbh.permissions p
        JOIN hbh.role_permissions rp ON rp.permission_id = p.permission_id
        JOIN hbh.roles r ON r.role_id = rp.role_id AND r.code = 'RECEPTION'
        WHERE p.code IN ('GUARDIAN.MANAGE','USER.MANAGE')) x $q$);

-- =====================================================================
-- 1. THE BROKEN LOOP, REPRODUCED BEFORE IT IS FIXED
-- =====================================================================
SET hbh.user_id = 'pc.reception';

CALL hbh_test.chk('loop', 'while the application is open the family is told ENROLMENT_PENDING',
  $q$ SELECT reason = 'ENROLMENT_PENDING' FROM hbh.request_otp('+201800009999') $q$);

CALL hbh_test.chk('loop', 'converting the application produces a guardian and a child',
  $q$ WITH c AS (SELECT * FROM hbh.convert_enrolment(
                   (SELECT v FROM hbh_test.fx WHERE k='app'), 'اختبار ١٢')),
           i AS (INSERT INTO hbh_test.fx (k, v) SELECT 'gd', guardian_id FROM c RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

INSERT INTO hbh_test.fx (k, v)
SELECT 'child', converted_child_id FROM hbh.enrolment_applications
WHERE application_id = (SELECT v FROM hbh_test.fx WHERE k='app');

-- THE BUG. The family came in through the only official door and the
-- login screen does not know them.
CALL hbh_test.chk('loop', 'and the enrolled family is STILL refused - NOT_REGISTERED',
  $q$ SELECT reason = 'NOT_REGISTERED' FROM hbh.request_otp('+201800009999') $q$);

CALL hbh_test.chk('loop', 'because convert_enrolment linked no account',
  $q$ SELECT user_id IS NULL FROM hbh.guardians
      WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='gd') $q$);

CALL hbh_test.chk('loop', 'and the portal-status view says so plainly',
  $q$ SELECT NOT has_portal_access FROM hbh.v_guardian_portal_status
      WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='gd') $q$);

-- =====================================================================
-- 2. THE GRANT
-- =====================================================================
CALL hbh_test.chk('grant', 'reception grants portal access, and it reports a NEW account',
  $q$ SELECT created AND user_id IS NOT NULL
      FROM hbh.grant_portal_access((SELECT v FROM hbh_test.fx WHERE k='gd')) $q$);

INSERT INTO hbh_test.fx (k, v)
SELECT 'user_gd', user_id FROM hbh.guardians
WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='gd');

-- The check the card is actually about.
CALL hbh_test.chk('grant', 'AND NOW THE SAME MOBILE SIGNS IN - reason OK',
  $q$ SELECT ok AND reason = 'OK' FROM hbh.request_otp('+201800009999') $q$);

CALL hbh_test.chk('grant', 'the account is a GUARDIAN on this centre, active',
  $q$ SELECT user_type = 'GUARDIAN' AND active_flg AND status = 'ACTIVE'
             AND center_id = (SELECT v FROM hbh_test.fx WHERE k='center')
      FROM hbh.users WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user_gd') $q$);

-- An account with no role signs in and sees nothing, which reads to the
-- family as a broken portal rather than a missing grant.
CALL hbh_test.chk('grant', 'and it carries the GUARDIAN role',
  $q$ SELECT count(*) = 1 FROM hbh.user_roles ur
      JOIN hbh.roles r ON r.role_id = ur.role_id
      WHERE ur.user_id = (SELECT v FROM hbh_test.fx WHERE k='user_gd') AND r.code = 'GUARDIAN' $q$);

CALL hbh_test.chk('grant', 'no password was set - a guardian signs in by OTP',
  $q$ SELECT password_hash IS NULL FROM hbh.users
      WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user_gd') $q$);

-- The grant IS the UPDATE, and trg_guardians_audit already records it.
-- 0085 wrote a second row by hand with action = 'GRANT', which
-- ck_audit_log_action rejects - so every call raised 23514. 0086 dropped
-- the hand-written row; this asserts the trigger's, which was there all
-- along.
CALL hbh_test.chk('grant', 'and who granted it is in the audit log - from the table trigger',
  $q$ SELECT count(*) >= 1 FROM hbh.audit_log
      WHERE table_name = 'guardians' AND action = 'UPDATE'
        AND row_pk = (SELECT v FROM hbh_test.fx WHERE k='gd')::text
        AND changed_by = 'pc.reception'
        AND (old_data->>'user_id') IS NULL
        AND (new_data->>'user_id') = (SELECT v FROM hbh_test.fx WHERE k='user_gd')::text $q$);

-- =====================================================================
-- 3. CALLING IT TWICE
--
-- Reception cannot tell from the screen whether the last click landed.
-- A function that punishes the second click teaches people to avoid the
-- first.
-- =====================================================================
CALL hbh_test.chk('again', 'the second call reports created = false',
  $q$ SELECT NOT created FROM hbh.grant_portal_access((SELECT v FROM hbh_test.fx WHERE k='gd')) $q$);

CALL hbh_test.chk('again', 'and returns the SAME account, not a rival one',
  $q$ SELECT user_id = (SELECT v FROM hbh_test.fx WHERE k='user_gd')
      FROM hbh.grant_portal_access((SELECT v FROM hbh_test.fx WHERE k='gd')) $q$);

-- request_otp looks families up BY MOBILE and takes the lowest user_id,
-- so a second account on one number is a login that silently resolves
-- to the wrong one.
CALL hbh_test.chk('again', 'exactly ONE guardian account exists on that mobile',
  $q$ SELECT count(*) = 1 FROM hbh.users
      WHERE mobile = '+201800009999' AND user_type = 'GUARDIAN' AND active_flg $q$);

CALL hbh_test.chk('again', 'and the partial unique index still holds one guardian per account',
  $q$ SELECT count(*) = 1 FROM pg_indexes
      WHERE schemaname = 'hbh' AND indexname = 'uix_guardians_user' $q$);

-- =====================================================================
-- 4. REFUSALS
-- =====================================================================
SET ROLE hbh_app;

SET hbh.user_id = 'pc.therapist';
CALL hbh_test.chk_raises('deny', 'a therapist has no GUARDIAN.MANAGE - HB200',
  $q$ SELECT * FROM hbh.grant_portal_access((SELECT v FROM hbh_test.fx WHERE k='gd')) $q$, 'HB200');

RESET hbh.user_id;
CALL hbh_test.chk_raises('deny', 'and with no identity at all - HB200',
  $q$ SELECT * FROM hbh.grant_portal_access((SELECT v FROM hbh_test.fx WHERE k='gd')) $q$, 'HB200');

RESET ROLE;

SET hbh.user_id = 'pc.reception';
CALL hbh_test.chk_raises('deny', 'a guardian who does not exist - HB201',
  $q$ SELECT * FROM hbh.grant_portal_access(-1) $q$, 'HB201');

-- 0085 guarded "a guardian with no mobile" and raised HB202. There is
-- no such guardian: mobile is NOT NULL and constrained to
-- '^[0-9+]{6,20}$'. The fixture that tried to build one was rejected by
-- the constraint itself, and the call then failed as HB201 on a NULL
-- id - a test that could only ever have passed by faking its own
-- premise. 0086 retired the branch, so what is asserted here is that
-- the schema forbids the state, not that a function handles it.
CALL hbh_test.chk_raises('deny', 'a guardian with no mobile cannot be created at all',
  $q$ INSERT INTO hbh.guardians (center_id, branch_id, full_name_ar, mobile)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'),
              (SELECT v FROM hbh_test.fx WHERE k='branch'),
              'وليّ أمر بلا رقم ١٢', '') $q$, 'HB170');

CALL hbh_test.chk('deny', 'and none was created',
  $q$ SELECT count(*) = 0 FROM hbh.guardians WHERE full_name_ar = 'وليّ أمر بلا رقم ١٢' $q$);

RESET hbh.user_id;

-- =====================================================================
-- CLEANUP
-- =====================================================================
-- The append-only trigger has to come off for this, and go back on
-- immediately: a teardown that leaves a guarantee disabled is worse
-- than one that leaves rows.
ALTER TABLE hbh.audit_log DISABLE TRIGGER trg_audit_log_append_only;
CALL hbh_test.chk('cleanup', 'the audit rows for this run are removed',
  $q$ WITH d AS (DELETE FROM hbh.audit_log
                  WHERE table_name IN ('guardians','users','user_roles','children',
                                       'guardian_children','enrolment_applications')
                    AND changed_by IN ('pc.reception','pc.therapist')
                  RETURNING 1)
      SELECT count(*) >= 1 FROM d $q$);
ALTER TABLE hbh.audit_log ENABLE TRIGGER trg_audit_log_append_only;

CALL hbh_test.chk('cleanup', 'and the append-only trigger is enabled again',
  $q$ SELECT tgenabled = 'O' FROM pg_trigger WHERE tgname = 'trg_audit_log_append_only' $q$);

-- request_otp issued codes against the new account, and they hold a
-- foreign key to it.
CALL hbh_test.chk('cleanup', 'the OTP codes issued during the run are removed',
  $q$ WITH d AS (DELETE FROM hbh.otp_codes WHERE user_id IN
                   (SELECT user_id FROM hbh.users
                     WHERE mobile LIKE '+2018000%' OR username LIKE 'pc.%') RETURNING 1)
      SELECT count(*) >= 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'guardian links and children removed',
  $q$ WITH gc AS (DELETE FROM hbh.guardian_children WHERE child_id =
                    (SELECT v FROM hbh_test.fx WHERE k='child') RETURNING 1)
      SELECT count(*) = 1 FROM gc $q$);

CALL hbh_test.chk('cleanup', 'the application is removed',
  $q$ WITH d AS (DELETE FROM hbh.enrolment_applications
                  WHERE application_no = 'APP-P12-0001' RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the child is removed',
  $q$ WITH d AS (DELETE FROM hbh.children WHERE child_id =
                   (SELECT v FROM hbh_test.fx WHERE k='child') RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the guardians are removed',
  $q$ WITH d AS (DELETE FROM hbh.guardians WHERE guardian_id IN
                   (SELECT v FROM hbh_test.fx WHERE k = 'gd') RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the accounts are removed',
  $q$ WITH ur AS (DELETE FROM hbh.user_roles WHERE user_id IN
                    (SELECT user_id FROM hbh.users
                     WHERE username LIKE 'pc.%' OR user_id =
                       (SELECT v FROM hbh_test.fx WHERE k='user_gd')) RETURNING 1),
           u AS (DELETE FROM hbh.users
                  WHERE username LIKE 'pc.%' OR user_id =
                    (SELECT v FROM hbh_test.fx WHERE k='user_gd') RETURNING 1)
      SELECT (SELECT count(*) FROM u) = 3 $q$);

-- One at least, then none left. An exact count breaks the day an id is
-- reused after a hard delete and drags rows from a previous life.
CALL hbh_test.chk('cleanup', 'and nothing of this run remains',
  $q$ SELECT count(*) = 0 FROM hbh.users WHERE mobile LIKE '+2018000%' $q$);

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
  IF v_fail = 0 AND v_total > 0 THEN RAISE NOTICE '  PHASE 12 ACCEPTED';
  ELSE RAISE NOTICE '  *** PHASE 12 NOT ACCEPTED'; END IF;
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
