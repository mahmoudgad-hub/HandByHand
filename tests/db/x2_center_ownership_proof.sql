-- =====================================================================
-- Hand By Hand (new) - CROSS-CENTRE PROOF HARNESS
--
--   bash scripts/db.sh psql < tests/db/x2_center_ownership_proof.sql
--
-- Builds a complete SECOND CENTRE inside one transaction, attempts every
-- mutation from a FIRST-CENTRE staff account, records what happened, and
-- ROLLS THE WHOLE THING BACK. Nothing it creates survives, and nothing
-- it proves depends on leftovers.
--
-- WHY EVERY ATTEMPT SITS IN ITS OWN SAVEPOINT. The first version of this
-- did not, and the first refusal aborted the transaction - so attempt
-- two onwards reported "current transaction is aborted" and the run
-- proved exactly one thing. A savepoint per attempt is what makes seven
-- independent questions answerable in one pass.
--
-- WHY IT IS run TWICE - before the fix and after. Before, it prints
-- ALLOWED for the defects. After, DENIED. The file is the evidence in
-- both directions, which is worth more than two different scripts that
-- can drift apart.
--
-- IT IS NOT AN ACCEPTANCE SUITE. It has no verdict and no exit code: it
-- is an instrument. The acceptance checks live in p14_verify.sql, which
-- asserts the same things and fails the build.
-- =====================================================================

\set ON_ERROR_STOP off
\pset pager off

BEGIN;

CREATE TEMP TABLE proof (seq serial, what text, outcome text, detail text);
-- hbh_app must be able to record its own results. The same trap the C2
-- fixture hit: a temp table belongs to its creator, and the attacks run
-- as hbh_app.
GRANT ALL ON proof TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA pg_temp TO hbh_app;

-- ---------------------------------------------------------------------
-- THE SECOND CENTRE, complete enough to attack
-- ---------------------------------------------------------------------
INSERT INTO hbh.centers (code, name_ar) VALUES ('XPROOF', 'مركز الإثبات');
INSERT INTO hbh.branches (center_id, code, name_ar)
 SELECT center_id, 'XPROOFB', 'فرع الإثبات' FROM hbh.centers WHERE code = 'XPROOF';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile)
SELECT c.center_id, b.branch_id, u.un, u.nm, u.ut, u.mb
FROM   hbh.centers c JOIN hbh.branches b ON b.center_id = c.center_id,
       (VALUES ('xproof.parent','ولي أمر الإثبات','GUARDIAN','+201988000001'),
               ('xproof.staff', 'موظّف الإثبات','STAFF',   '+201988000002')) AS u(un,nm,ut,mb)
WHERE  c.code = 'XPROOF';

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
SELECT u.center_id, u.branch_id, u.user_id, u.full_name_ar, u.mobile
FROM   hbh.users u WHERE u.username = 'xproof.parent';

INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
SELECT c.center_id, b.branch_id, 'XPROOF-1', 'طفل الإثبات', DATE '2020-06-06', 'M'
FROM   hbh.centers c JOIN hbh.branches b ON b.center_id = c.center_id WHERE c.code = 'XPROOF';

INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
SELECT g.guardian_id, ch.child_id, 'FATHER', true
FROM   hbh.guardians g JOIN hbh.children ch ON ch.center_id = g.center_id
WHERE  ch.child_no = 'XPROOF-1';

-- An enrolment application. application_no comes from the series, which
-- is per centre - so this also proves the series is reachable.
INSERT INTO hbh.enrolment_applications
  (center_id, branch_id, application_no, parent_name_ar, parent_mobile,
   child_name_ar, child_birth_date, child_gender, status)
SELECT c.center_id, b.branch_id, 'XPROOF-APP-1',
       'أب الإثبات', '+201988000003', 'طفل جديد للإثبات', DATE '2021-02-02', 'M', 'NEW'
FROM   hbh.centers c JOIN hbh.branches b ON b.center_id = c.center_id WHERE c.code = 'XPROOF';

-- A clinical note, reached through a session and an appointment.
INSERT INTO hbh.services (center_id, branch_id, code, name_ar, kind_code)
SELECT c.center_id, b.branch_id, 'XPROOF-SVC', 'خدمة الإثبات', 'SPEECH'
FROM   hbh.centers c JOIN hbh.branches b ON b.center_id = c.center_id WHERE c.code = 'XPROOF';
INSERT INTO hbh.rooms (center_id, branch_id, code, name_ar)
SELECT c.center_id, b.branch_id, 'XPROOF-RM', 'غرفة الإثبات'
FROM   hbh.centers c JOIN hbh.branches b ON b.center_id = c.center_id WHERE c.code = 'XPROOF';
INSERT INTO hbh.therapists (center_id, branch_id, full_name_ar)
SELECT c.center_id, b.branch_id, 'أخصائي الإثبات'
FROM   hbh.centers c JOIN hbh.branches b ON b.center_id = c.center_id WHERE c.code = 'XPROOF';

INSERT INTO hbh.appointments
  (center_id, branch_id, appointment_no, child_id, therapist_id, room_id, service_id,
   starts_at, ends_at, status)
SELECT c.center_id, b.branch_id, 'XPROOF-APT-1', ch.child_id,
       t.therapist_id, r.room_id, s.service_id,
       now() - interval '2 hours', now() - interval '1 hour', 'BOOKED'
FROM   hbh.centers c JOIN hbh.branches b ON b.center_id = c.center_id
JOIN   hbh.children ch ON ch.center_id = c.center_id
JOIN   hbh.therapists t ON t.center_id = c.center_id
JOIN   hbh.rooms r ON r.center_id = c.center_id
JOIN   hbh.services s ON s.center_id = c.center_id
WHERE  c.code = 'XPROOF';

INSERT INTO hbh.therapy_sessions
  (center_id, branch_id, appointment_id, child_id, therapist_id, room_id, service_id,
   started_at, ended_at, status)
SELECT a.center_id, a.branch_id, a.appointment_id, a.child_id, a.therapist_id,
       a.room_id, a.service_id, now() - interval '2 hours', now() - interval '1 hour', 'COMPLETED'
FROM   hbh.appointments a
JOIN   hbh.centers c ON c.center_id = a.center_id WHERE c.code = 'XPROOF';

INSERT INTO hbh.session_notes
  (center_id, session_id, child_id, author_user_id, body_ar, visibility, is_draft_flg)
SELECT s.center_id, s.session_id, s.child_id, (SELECT user_id FROM hbh.users WHERE username='xproof.staff'),
       'ملاحظة سريرية خاصّة بالمركز الآخر', 'STAFF', true
FROM   hbh.therapy_sessions s
JOIN   hbh.centers c ON c.center_id = s.center_id WHERE c.code = 'XPROOF';

-- Handles, read once and held.
SELECT child_id       AS fchild FROM hbh.children              WHERE child_no = 'XPROOF-1'          \gset
SELECT guardian_id    AS fguard FROM hbh.guardians g WHERE g.mobile = '+201988000001'                 \gset
SELECT application_id AS fapp   FROM hbh.enrolment_applications WHERE parent_mobile = '+201988000003' \gset
SELECT note_id        AS fnote  FROM hbh.session_notes
  WHERE body_ar = 'ملاحظة سريرية خاصّة بالمركز الآخر'                                               \gset
SELECT user_id        AS fstaff FROM hbh.users WHERE username = 'xproof.staff'                      \gset
SELECT package_id     AS mypkg  FROM hbh.service_packages WHERE active_flg ORDER BY package_id LIMIT 1 \gset

-- The application must be in a convertible state. Leaving it NEW makes
-- convert_enrolment refuse for a BUSINESS reason, and an earlier version
-- of this file recorded that as "denied" - a refusal for the wrong
-- reason proving nothing and looking green. CLAUDE.md, first page of
-- the testing section.
UPDATE hbh.enrolment_applications SET status = 'CONTACTED'
 WHERE application_id = :fapp;

-- =====================================================================
-- THE ATTACKS
--
-- EACH ONE RECORDS ITS SQLSTATE, not merely whether it threw.
--
-- The first version of this harness ran each call in a savepoint and
-- inferred DENIED from the absence of a success row. It reported all six
-- as denied on a database where sell_package was demonstrably open - because
-- a refusal for ANY reason looked identical to the refusal under test.
-- convert_enrolment, in particular, was being turned away by a business
-- rule about application status and counted as a security pass.
--
-- So the question asked here is not "did it fail" but "what refused it":
--
--   HB232                 the centre guard          <- the fix working
--   HB05x / HB10x / HB07x a permission refusal      <- a different gate
--   anything else         a business rule           <- proves nothing
--   no exception          IT SUCCEEDED              <- the defect
-- =====================================================================
CREATE OR REPLACE PROCEDURE pg_temp.attack(p_what text, p_actor text, p_sql text)
LANGUAGE plpgsql AS $proc$
BEGIN
  BEGIN
    EXECUTE format('SET LOCAL hbh.user_id = %L', p_actor);
    EXECUTE p_sql;
    INSERT INTO proof (what, outcome, detail)
    VALUES (p_what, 'ALLOWED', 'no exception - the cross-centre write SUCCEEDED');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO proof (what, outcome, detail)
    VALUES (p_what,
            CASE WHEN SQLSTATE = 'HB232' THEN 'DENIED (centre)'
                 ELSE 'other: ' || SQLSTATE END,
            left(SQLERRM, 70));
  END;
END
$proc$;

SET ROLE hbh_app;

CALL pg_temp.attack('sell_package', 'dev_admin',
  format('SELECT hbh.sell_package(%s, %s)', :fchild, :mypkg));

CALL pg_temp.attack('convert_enrolment', 'dev_reception',
  format('SELECT * FROM hbh.convert_enrolment(%s, NULL)', :fapp));

CALL pg_temp.attack('publish_session_note', 'dev_therapist',
  format('SELECT hbh.publish_session_note(%s)', :fnote));

CALL pg_temp.attack('grant_consent LIVE_VIEW', 'dev_reception',
  format('SELECT hbh.grant_consent(%s, ''LIVE_VIEW'', %s)', :fguard, :fchild));

CALL pg_temp.attack('withdraw_consent', 'dev_reception',
  format('SELECT hbh.withdraw_consent(%s, ''SMS_NOTIFY'')', :fguard));

CALL pg_temp.attack('set_password', 'dev_admin',
  format('SELECT hbh.set_password(%s, ''a-password-only-the-attacker-knows'')', :fstaff));

RESET ROLE;

\echo ''
\echo '================ CROSS-CENTRE ATTACK RESULTS ================'
SELECT what AS "function", outcome AS "verdict", detail FROM proof ORDER BY seq;
\echo ''
SELECT count(*) FILTER (WHERE outcome = 'ALLOWED')          AS "SUCCEEDED (defect)",
       count(*) FILTER (WHERE outcome = 'DENIED (centre)')  AS "denied by centre guard",
       count(*) FILTER (WHERE outcome LIKE 'other:%')       AS "refused for another reason"
FROM proof;

ROLLBACK;
