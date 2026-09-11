-- =====================================================================
-- Hand By Hand (new) - PHASE 2 acceptance suite
--
-- Must print:  PHASE 2 ACCEPTED
--
-- This is a SECURITY GATE. Its centre of gravity is one question:
-- can a guardian reach a child who is not theirs, by any route?
-- It is answered with real refusals against real rows, as the role the
-- API actually connects as - never by reading the policy text.
-- =====================================================================

\set ON_ERROR_STOP off
\pset pager off

-- ---------------------------------------------------------------------
-- Harness - standalone, so this suite can run on its own
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

-- Identifiers created by this suite, so a test can ask for a specific
-- row by id - which is the whole point of a URL-editing test.
CREATE TABLE hbh_test.fx (k text PRIMARY KEY, v integer);
CREATE TABLE hbh_test.otp_probe (who text PRIMARY KEY, code text, expires_at timestamptz);
CREATE TABLE hbh_test.tok (who text PRIMARY KEY, token text);

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
GRANT SELECT ON hbh_test.fx, hbh_test.otp_probe, hbh_test.tok TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh_test TO hbh_app;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA hbh_test TO hbh_app;

-- =====================================================================
-- FIXTURE
--
-- Built here as the owner, so RLS does not stand in the way of setting
-- it up. Every assertion below then runs as hbh_app, where it does.
--
-- Two guardians with one child each is the minimum shape that can prove
-- the gate: with a single guardian there is nothing to be refused.
-- =====================================================================
INSERT INTO hbh_test.fx (k, v)
SELECT 'center', center_id FROM hbh.centers WHERE code = 'HBH';
INSERT INTO hbh_test.fx (k, v)
SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile)
SELECT (SELECT v FROM hbh_test.fx WHERE k = 'center'),
       (SELECT v FROM hbh_test.fx WHERE k = 'branch'),
       u.username, u.name, u.utype, u.mobile
FROM (VALUES
       ('p2.guardian.a', 'ولي أمر الاختبار أ', 'GUARDIAN',  '+201000000001'),
       ('p2.guardian.b', 'ولي أمر الاختبار ب', 'GUARDIAN',  '+201000000002'),
       ('p2.therapist',  'أخصائي الاختبار',    'THERAPIST', '+201000000003')
     ) AS u(username, name, utype, mobile);

INSERT INTO hbh_test.fx (k, v) SELECT 'user_a', user_id FROM hbh.users WHERE username = 'p2.guardian.a';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_b', user_id FROM hbh.users WHERE username = 'p2.guardian.b';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_t', user_id FROM hbh.users WHERE username = 'p2.therapist';

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT f.v, r.role_id
FROM   hbh_test.fx f
JOIN   hbh.roles r ON r.center_id = (SELECT v FROM hbh_test.fx WHERE k = 'center')
WHERE  (f.k IN ('user_a','user_b') AND r.code = 'GUARDIAN')
   OR  (f.k = 'user_t'             AND r.code = 'THERAPIST');

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
SELECT (SELECT v FROM hbh_test.fx WHERE k = 'center'),
       (SELECT v FROM hbh_test.fx WHERE k = 'branch'),
       u.user_id, u.full_name_ar, u.mobile
FROM   hbh.users u WHERE u.username IN ('p2.guardian.a','p2.guardian.b');

INSERT INTO hbh_test.fx (k, v)
SELECT 'guardian_a', guardian_id FROM hbh.guardians WHERE mobile = '+201000000001';
INSERT INTO hbh_test.fx (k, v)
SELECT 'guardian_b', guardian_id FROM hbh.guardians WHERE mobile = '+201000000002';

-- Children A and B carry NO national id, on purpose: many small
-- children in Egypt have none yet, and two of them must not collide.
-- Child C has one, so the rule can be shown to still bite.
INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender, national_id)
VALUES
  ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
   'P2-A', 'طفل الاختبار أ', DATE '2020-03-11', 'M', NULL),
  ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
   'P2-B', 'طفل الاختبار ب', DATE '2021-07-02', 'F', NULL),
  ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
   'P2-C', 'طفل الاختبار ج', DATE '2019-11-20', 'M', '29911200101234');

INSERT INTO hbh_test.fx (k, v) SELECT 'child_a', child_id FROM hbh.children WHERE child_no = 'P2-A';
INSERT INTO hbh_test.fx (k, v) SELECT 'child_b', child_id FROM hbh.children WHERE child_no = 'P2-B';
INSERT INTO hbh_test.fx (k, v) SELECT 'child_c', child_id FROM hbh.children WHERE child_no = 'P2-C';

-- can_view_live_flg is left at its default of false: from migration
-- 0015 the flag may only be set through a recorded consent, and this
-- suite is not about live viewing. P7 is, and grants one properly.
INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
VALUES
  ((SELECT v FROM hbh_test.fx WHERE k='guardian_a'), (SELECT v FROM hbh_test.fx WHERE k='child_a'), 'FATHER', true),
  ((SELECT v FROM hbh_test.fx WHERE k='guardian_b'), (SELECT v FROM hbh_test.fx WHERE k='child_b'), 'MOTHER', true);

-- ---------------------------------------------------------------------
-- The fixture is asserted BY NAME before any test runs. A missing piece
-- must fail where it can be read, not fifty tests later as a confusing
-- refusal from correct code.
-- ---------------------------------------------------------------------
CALL hbh_test.chk('fixture', 'migration 0002 recorded',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0002') $q$);

CALL hbh_test.chk('fixture', 'three test users exist and are ACTIVE',
  $q$ SELECT count(*) = 3 FROM hbh.users
      WHERE username LIKE 'p2.%' AND status = 'ACTIVE' AND active_flg $q$);

CALL hbh_test.chk('fixture', 'every test user has a role',
  $q$ SELECT count(*) = 3 FROM hbh.users u
      JOIN hbh.user_roles ur ON ur.user_id = u.user_id
      WHERE u.username LIKE 'p2.%' $q$);

CALL hbh_test.chk('fixture', 'two guardians exist and are linked to accounts',
  $q$ SELECT count(*) = 2 FROM hbh.guardians WHERE user_id IS NOT NULL AND mobile LIKE '+2010000000%' $q$);

CALL hbh_test.chk('fixture', 'three children exist',
  $q$ SELECT count(*) = 3 FROM hbh.children WHERE child_no LIKE 'P2-%' $q$);

CALL hbh_test.chk('fixture', 'each guardian is linked to exactly one child',
  $q$ SELECT count(*) = 2 FROM hbh.guardian_children gc
      JOIN hbh.guardians g ON g.guardian_id = gc.guardian_id
      WHERE g.mobile LIKE '+2010000000%' $q$);

CALL hbh_test.chk('fixture', 'the seed roles carry permissions',
  $q$ SELECT count(*) > 20 FROM hbh.role_permissions $q$);

CALL hbh_test.chk('fixture', 'number series are defined',
  $q$ SELECT count(*) >= 4 FROM hbh.number_series $q$);

-- =====================================================================
-- 1. PERMISSIONS
-- =====================================================================
CALL hbh_test.chk('perm', 'has_permission fails closed with no identity',
  $q$ SELECT NOT hbh.has_permission('PORTAL.VIEW') $q$);

CALL hbh_test.chk('perm', 'an unknown permission code is false, not an error',
  $q$ SELECT set_config('hbh.user_id', 'admin', true) IS NOT NULL
             AND NOT hbh.has_permission('NO.SUCH.PERMISSION') $q$);

CALL hbh_test.chk('perm', 'a guardian holds PORTAL.VIEW',
  $q$ SELECT set_config('hbh.user_id', 'p2.guardian.a', true) IS NOT NULL
             AND hbh.has_permission('PORTAL.VIEW') $q$);

CALL hbh_test.chk('perm', 'a guardian does NOT hold CHILD.VIEW_ALL',
  $q$ SELECT set_config('hbh.user_id', 'p2.guardian.a', true) IS NOT NULL
             AND NOT hbh.has_permission('CHILD.VIEW_ALL') $q$);

CALL hbh_test.chk('perm', 'a therapist holds CHILD.VIEW_ALL',
  $q$ SELECT set_config('hbh.user_id', 'p2.therapist', true) IS NOT NULL
             AND hbh.has_permission('CHILD.VIEW_ALL') $q$);

-- The deliberate withholding. An administrator closes a session; only
-- the clinician who was in the room authors the note. Two rights, two
-- codes, and never one gate serving both.
CALL hbh_test.chk('perm', 'CENTER_ADMIN holds SESSION.COMPLETE',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.roles r
        JOIN hbh.role_permissions rp ON rp.role_id = r.role_id
        JOIN hbh.permissions p ON p.permission_id = rp.permission_id
        WHERE r.code = 'CENTER_ADMIN' AND p.code = 'SESSION.COMPLETE') $q$);

CALL hbh_test.chk('perm', 'CENTER_ADMIN does NOT hold SESSION.NOTES.EDIT',
  $q$ SELECT NOT EXISTS (SELECT 1 FROM hbh.roles r
        JOIN hbh.role_permissions rp ON rp.role_id = r.role_id
        JOIN hbh.permissions p ON p.permission_id = rp.permission_id
        WHERE r.code = 'CENTER_ADMIN' AND p.code = 'SESSION.NOTES.EDIT') $q$);

CALL hbh_test.chk('perm', 'THERAPIST does hold SESSION.NOTES.EDIT',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.roles r
        JOIN hbh.role_permissions rp ON rp.role_id = r.role_id
        JOIN hbh.permissions p ON p.permission_id = rp.permission_id
        WHERE r.code = 'THERAPIST' AND p.code = 'SESSION.NOTES.EDIT') $q$);

-- =====================================================================
-- 2. THE GATE
--
-- Run as hbh_app, where the policies actually bind.
-- =====================================================================
SET ROLE hbh_app;

RESET hbh.user_id;
CALL hbh_test.chk('gate', 'no identity sees no children at all',
  $q$ SELECT count(*) = 0 FROM hbh.children $q$);

CALL hbh_test.chk('gate', 'no identity sees no guardians',
  $q$ SELECT count(*) = 0 FROM hbh.guardians $q$);

SET hbh.user_id = 'p2.guardian.a';

CALL hbh_test.chk('gate', 'guardian A sees exactly one child',
  $q$ SELECT count(*) = 1 FROM hbh.children $q$);

CALL hbh_test.chk('gate', 'and it is their own child',
  $q$ SELECT (SELECT child_no FROM hbh.children) = 'P2-A' $q$);

-- The URL-editing attack, stated literally: ask for the other child by
-- primary key. The answer must be nothing, not a permission error and
-- certainly not a row.
CALL hbh_test.chk('gate', 'guardian A cannot fetch child B BY ID',
  $q$ SELECT count(*) = 0 FROM hbh.children
      WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k = 'child_b') $q$);

CALL hbh_test.chk('gate', 'guardian A cannot fetch the unrelated child C BY ID',
  $q$ SELECT count(*) = 0 FROM hbh.children
      WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k = 'child_c') $q$);

CALL hbh_test.chk('gate', 'can_access_child refuses child B for guardian A',
  $q$ SELECT NOT hbh.can_access_child((SELECT v FROM hbh_test.fx WHERE k = 'child_b')) $q$);

CALL hbh_test.chk('gate', 'can_access_child allows child A for guardian A',
  $q$ SELECT hbh.can_access_child((SELECT v FROM hbh_test.fx WHERE k = 'child_a')) $q$);

CALL hbh_test.chk('gate', 'guardian A sees only their own link row',
  $q$ SELECT count(*) = 1 FROM hbh.guardian_children $q$);

CALL hbh_test.chk('gate', 'guardian A sees only their own guardian record',
  $q$ SELECT count(*) = 1 FROM hbh.guardians $q$);

CALL hbh_test.chk('gate', 'guardian A sees only their own role assignment',
  $q$ SELECT count(*) = 1 FROM hbh.user_roles $q$);

-- Symmetry. A gate that only holds in one direction is not a gate.
SET hbh.user_id = 'p2.guardian.b';

CALL hbh_test.chk('gate', 'guardian B sees exactly one child',
  $q$ SELECT count(*) = 1 FROM hbh.children $q$);

CALL hbh_test.chk('gate', 'and it is child B, not child A',
  $q$ SELECT (SELECT child_no FROM hbh.children) = 'P2-B' $q$);

CALL hbh_test.chk('gate', 'guardian B cannot fetch child A BY ID',
  $q$ SELECT count(*) = 0 FROM hbh.children
      WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k = 'child_a') $q$);

-- Staff with CHILD.VIEW_ALL, in the same centre, see all of them.
SET hbh.user_id = 'p2.therapist';

CALL hbh_test.chk('gate', 'a therapist with CHILD.VIEW_ALL sees every child',
  $q$ SELECT count(*) >= 3 FROM hbh.children $q$);

CALL hbh_test.chk('gate', 'the therapist can reach child B',
  $q$ SELECT hbh.can_access_child((SELECT v FROM hbh_test.fx WHERE k = 'child_b')) $q$);

-- A user whose account is gone loses access on the next request, not at
-- the next login.
RESET hbh.user_id;
SET hbh.user_id = 'p2.nobody';
CALL hbh_test.chk('gate', 'an identity that resolves to no user sees nothing',
  $q$ SELECT count(*) = 0 FROM hbh.children $q$);

-- =====================================================================
-- 3. TABLES THE API MUST NOT TOUCH DIRECTLY
--
-- Code hashes, token hashes and the number counter are reachable only
-- through SECURITY DEFINER functions. Not "no rows" - no privilege.
-- =====================================================================
CALL hbh_test.chk_raises('privilege', 'otp_codes are unreadable by the app role',
  $q$ SELECT count(*) FROM hbh.otp_codes $q$, '42501');

CALL hbh_test.chk_raises('privilege', 'auth_sessions are unreadable by the app role',
  $q$ SELECT count(*) FROM hbh.auth_sessions $q$, '42501');

CALL hbh_test.chk_raises('privilege', 'number_series is unreadable by the app role',
  $q$ SELECT count(*) FROM hbh.number_series $q$, '42501');

-- Since D-26 the app role CAN write - but only where a permission
-- allows it, and this caller holds none.
--
-- The evidence had to change with the rule. Row level security FILTERS
-- an UPDATE rather than raising on it, so the proof is that nothing
-- changed, not that 42501 was thrown. The old form passed for years
-- only because no write was possible at all; against the new grants it
-- would have been waiting for the wrong evidence.
CALL hbh_test.chk('privilege', 'a guardian cannot change a child row',
  $q$ WITH u AS (UPDATE hbh.children SET full_name_ar = 'x' RETURNING 1)
      SELECT count(*) = 0 FROM u $q$);

RESET hbh.user_id;
RESET ROLE;

-- =====================================================================
-- 4. ONE-TIME CODES
-- =====================================================================
CALL hbh_test.chk('otp', 'an unregistered mobile gets no code',
  $q$ SELECT reason = 'NOT_REGISTERED' FROM hbh.request_otp('+201099999999') $q$);

CALL hbh_test.chk('otp', 'request_otp issues a code for a registered mobile',
  $q$ WITH r AS (SELECT * FROM hbh.request_otp('+201000000001')),
           i AS (INSERT INTO hbh_test.otp_probe (who, code, expires_at)
                 SELECT 'a', r.code, r.expires_at FROM r WHERE r.ok RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('otp', 'the code has the length the parameter says',
  $q$ SELECT length(code) = hbh.param(NULL, 'OTP_LENGTH', '6')::integer
      FROM hbh_test.otp_probe WHERE who = 'a' $q$);

CALL hbh_test.chk('otp', 'the code is stored hashed, never in plaintext',
  $q$ SELECT NOT EXISTS (
        SELECT 1 FROM hbh.otp_codes o JOIN hbh_test.otp_probe p ON p.who = 'a'
        WHERE o.code_hash = p.code) $q$);

CALL hbh_test.chk('otp', 'the stored hash is bcrypt',
  $q$ SELECT code_hash LIKE '$2%' FROM hbh.otp_codes
      WHERE consumed_at IS NULL AND mobile = '+201000000001' $q$);

CALL hbh_test.chk('otp', 'a second request inside the window is refused',
  $q$ SELECT reason = 'RESEND_TOO_SOON' FROM hbh.request_otp('+201000000001') $q$);

-- Shifting every digit by one guarantees a code that is wrong, without
-- relying on a one-in-a-million coincidence.
CALL hbh_test.chk('otp', 'a wrong code is refused',
  $q$ SELECT reason = 'WRONG_CODE' FROM hbh.verify_otp('+201000000001',
        (SELECT translate(code, '0123456789', '1234567890') FROM hbh_test.otp_probe WHERE who = 'a')) $q$);

-- The point of the whole design. If verify_otp had raised instead of
-- returning, this counter would have rolled back with the exception and
-- the code could be guessed without limit.
CALL hbh_test.chk('otp', 'and the attempt counter SURVIVED the refusal',
  $q$ SELECT attempts = 1 FROM hbh.otp_codes
      WHERE mobile = '+201000000001' AND consumed_at IS NULL $q$);

CALL hbh_test.chk('otp', 'the correct code is accepted and names the user',
  $q$ SELECT ok AND user_id = (SELECT v FROM hbh_test.fx WHERE k = 'user_a')
      FROM hbh.verify_otp('+201000000001',
        (SELECT code FROM hbh_test.otp_probe WHERE who = 'a')) $q$);

CALL hbh_test.chk('otp', 'the same code cannot be used twice',
  $q$ SELECT reason = 'NO_PENDING_CODE' FROM hbh.verify_otp('+201000000001',
        (SELECT code FROM hbh_test.otp_probe WHERE who = 'a')) $q$);

-- Lockout, counted one attempt at a time so each step is visible.
CALL hbh_test.chk('otp', 'guardian B is issued a code',
  $q$ WITH r AS (SELECT * FROM hbh.request_otp('+201000000002')),
           i AS (INSERT INTO hbh_test.otp_probe (who, code, expires_at)
                 SELECT 'b', r.code, r.expires_at FROM r WHERE r.ok RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('otp', 'wrong attempt 1 of 5 leaves 4',
  $q$ SELECT reason = 'WRONG_CODE' AND attempts_left = 4 FROM hbh.verify_otp('+201000000002',
        (SELECT translate(code,'0123456789','1234567890') FROM hbh_test.otp_probe WHERE who='b')) $q$);

CALL hbh_test.chk('otp', 'wrong attempt 2 of 5 leaves 3',
  $q$ SELECT reason = 'WRONG_CODE' AND attempts_left = 3 FROM hbh.verify_otp('+201000000002',
        (SELECT translate(code,'0123456789','1234567890') FROM hbh_test.otp_probe WHERE who='b')) $q$);

CALL hbh_test.chk('otp', 'wrong attempt 3 of 5 leaves 2',
  $q$ SELECT reason = 'WRONG_CODE' AND attempts_left = 2 FROM hbh.verify_otp('+201000000002',
        (SELECT translate(code,'0123456789','1234567890') FROM hbh_test.otp_probe WHERE who='b')) $q$);

CALL hbh_test.chk('otp', 'wrong attempt 4 of 5 leaves 1',
  $q$ SELECT reason = 'WRONG_CODE' AND attempts_left = 1 FROM hbh.verify_otp('+201000000002',
        (SELECT translate(code,'0123456789','1234567890') FROM hbh_test.otp_probe WHERE who='b')) $q$);

CALL hbh_test.chk('otp', 'wrong attempt 5 of 5 leaves 0',
  $q$ SELECT reason = 'WRONG_CODE' AND attempts_left = 0 FROM hbh.verify_otp('+201000000002',
        (SELECT translate(code,'0123456789','1234567890') FROM hbh_test.otp_probe WHERE who='b')) $q$);

CALL hbh_test.chk('otp', 'the sixth attempt is refused as TOO_MANY_ATTEMPTS',
  $q$ SELECT reason = 'TOO_MANY_ATTEMPTS' FROM hbh.verify_otp('+201000000002',
        (SELECT translate(code,'0123456789','1234567890') FROM hbh_test.otp_probe WHERE who='b')) $q$);

CALL hbh_test.chk('otp', 'and the account is now LOCKED',
  $q$ SELECT status = 'LOCKED' FROM hbh.users WHERE username = 'p2.guardian.b' $q$);

CALL hbh_test.chk('otp', 'a locked account is refused a new code',
  $q$ SELECT reason = 'USER_LOCKED' FROM hbh.request_otp('+201000000002') $q$);

-- Even the CORRECT code fails once the account is locked. A lock that
-- only stops wrong guesses stops nothing.
CALL hbh_test.chk('otp', 'even the correct code is refused while locked',
  $q$ SELECT reason = 'USER_LOCKED' FROM hbh.verify_otp('+201000000002',
        (SELECT code FROM hbh_test.otp_probe WHERE who = 'b')) $q$);

-- Expiry, forced rather than waited for.
--
-- Three statements, not one. request_otp INSERTs the row; a sibling CTE
-- in the same statement cannot see that insert, because both halves
-- read the snapshot taken when the statement began - so an UPDATE
-- alongside it silently matches nothing and the check fails while the
-- code under test is perfectly correct.
CALL hbh_test.chk('otp', 'a code is issued for the therapist',
  $q$ WITH r AS (SELECT * FROM hbh.request_otp('+201000000003')),
           i AS (INSERT INTO hbh_test.otp_probe (who, code, expires_at)
                 SELECT 't', r.code, r.expires_at FROM r WHERE r.ok RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

-- ck_otp_codes_window insists expires_at > issued_at, so the window is
-- shrunk to a millisecond rather than dragged into the past. The row
-- stays legal and is already stale by the time it is checked, which is
-- what the test needs - the constraint is right and stays.
CALL hbh_test.chk('otp', 'that code can be pushed past its expiry',
  $q$ WITH x AS (UPDATE hbh.otp_codes
                    SET expires_at = issued_at + interval '1 millisecond'
                 WHERE mobile = '+201000000003' AND consumed_at IS NULL RETURNING 1)
      SELECT count(*) = 1 FROM x $q$);

CALL hbh_test.chk('otp', 'and it then reports EXPIRED, not WRONG_CODE',
  $q$ SELECT reason = 'EXPIRED' FROM hbh.verify_otp('+201000000003',
        (SELECT code FROM hbh_test.otp_probe WHERE who = 't')) $q$);

-- =====================================================================
-- 5. LOGIN SESSIONS
-- =====================================================================
INSERT INTO hbh_test.tok (who, token)
VALUES ('a', encode(public.gen_random_bytes(32), 'hex'));

CALL hbh_test.chk('session', 'a session can be opened for an active user',
  $q$ SELECT expires_at > now() FROM hbh.create_auth_session(
        (SELECT v FROM hbh_test.fx WHERE k = 'user_a'),
        (SELECT token FROM hbh_test.tok WHERE who = 'a')) $q$);

CALL hbh_test.chk('session', 'the token is stored hashed, never in plaintext',
  $q$ SELECT NOT EXISTS (SELECT 1 FROM hbh.auth_sessions s, hbh_test.tok t
        WHERE t.who = 'a' AND encode(s.token_hash, 'hex') = t.token) $q$);

CALL hbh_test.chk('session', 'the token resolves to the right user',
  $q$ SELECT ok AND username = 'p2.guardian.a'
      FROM hbh.resolve_auth_session((SELECT token FROM hbh_test.tok WHERE who = 'a')) $q$);

CALL hbh_test.chk('session', 'an unknown token resolves to NO_SESSION',
  $q$ SELECT reason = 'NO_SESSION' FROM hbh.resolve_auth_session('not-a-real-token') $q$);

-- Guardian B was locked by the attempt tests above, so this is a real
-- locked account and not a contrived one.
CALL hbh_test.chk_raises('session', 'opening a session for a LOCKED user raises HB011',
  $q$ SELECT hbh.create_auth_session((SELECT v FROM hbh_test.fx WHERE k = 'user_b'), 'x-token-x') $q$,
  'HB011');

CALL hbh_test.chk('session', 'revoking returns true the first time',
  $q$ SELECT hbh.revoke_auth_session((SELECT token FROM hbh_test.tok WHERE who = 'a'), 'TEST') $q$);

CALL hbh_test.chk('session', 'a revoked token no longer resolves',
  $q$ SELECT reason = 'REVOKED'
      FROM hbh.resolve_auth_session((SELECT token FROM hbh_test.tok WHERE who = 'a')) $q$);

CALL hbh_test.chk('session', 'revoking again returns false',
  $q$ SELECT NOT hbh.revoke_auth_session((SELECT token FROM hbh_test.tok WHERE who = 'a'), 'TEST') $q$);

-- ---------------------------------------------------------------------
-- OFFBOARDING CLOSES THE SESSIONS THAT WERE OPEN (migration 0105)
--
-- The ACCESS was already ended without this: resolve_auth_session checks
-- status and active_flg on every request, so a suspended person's live
-- token stops working on their next call. What 0105 added is that the
-- RECORD says so - the row used to keep revoked_at NULL and an expiry
-- hours out, and so described a suspended employee as signed in.
--
-- A fresh token, because the one above is already revoked by the checks
-- before this and a trigger that did nothing would still look green.
-- ---------------------------------------------------------------------
INSERT INTO hbh_test.tok (who, token)
VALUES ('offboard', encode(public.gen_random_bytes(32), 'hex'));

SELECT hbh.create_auth_session(
  (SELECT v FROM hbh_test.fx WHERE k = 'user_a'),
  (SELECT token FROM hbh_test.tok WHERE who = 'offboard'));

-- The arming check. Without it, a trigger that revoked nothing and a
-- session that was never open both read as a pass below.
CALL hbh_test.chk('session', 'the new session is open before the suspension',
  $q$ SELECT ok FROM hbh.resolve_auth_session(
        (SELECT token FROM hbh_test.tok WHERE who = 'offboard')) $q$);

UPDATE hbh.users SET status = 'SUSPENDED'
 WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k = 'user_a');

CALL hbh_test.chk('session', 'suspending the user marks the open session revoked',
  $q$ SELECT revoked_at IS NOT NULL AND revoked_reason = 'USER_SUSPENDED'
      FROM hbh.auth_sessions
      WHERE token_hash = public.digest(
              (SELECT token FROM hbh_test.tok WHERE who = 'offboard'), 'sha256') $q$);

-- REVOKED, not USER_LOCKED: the row is now genuinely revoked, so the
-- first guard in resolve_auth_session answers before the status test
-- ever runs. Asserting the reason and not merely "not ok" is the
-- difference between proving the trigger fired and proving the account
-- is unusable - which it already was.
CALL hbh_test.chk('session', 'and the token resolves as REVOKED',
  $q$ SELECT NOT ok AND reason = 'REVOKED'
      FROM hbh.resolve_auth_session(
        (SELECT token FROM hbh_test.tok WHERE who = 'offboard')) $q$);

-- Put the account back, and prove the trigger does NOT un-revoke. The
-- token is gone from wherever it was held; a row that went back to
-- reading "open" would describe a session nobody can use.
UPDATE hbh.users SET status = 'ACTIVE'
 WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k = 'user_a');

CALL hbh_test.chk('session', 'reinstating does not reopen the old session',
  $q$ SELECT revoked_at IS NOT NULL
      FROM hbh.auth_sessions
      WHERE token_hash = public.digest(
              (SELECT token FROM hbh_test.tok WHERE who = 'offboard'), 'sha256') $q$);

-- =====================================================================
-- 6. ATTEMPT AUDIT SURVIVES A ROLLBACK
--
-- The direct proof of D-1. The transaction below is thrown away; the
-- record of the attempt must not be.
-- =====================================================================
BEGIN;
SELECT hbh.audit_attempt('DENY', NULL, 'p2-test-actor', 'HBH_P2_ROLLBACK_PROBE');
ROLLBACK;

CALL hbh_test.chk('audit', 'an attempt record survives its rollback',
  $q$ SELECT count(*) = 1 FROM hbh.audit_log
      WHERE detail = 'HBH_P2_ROLLBACK_PROBE' AND action = 'DENY'
        AND changed_at >= (SELECT started FROM hbh_test.run) $q$);

-- And a change record must NOT: the change did not happen.
BEGIN;
INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type)
VALUES (NULL, 'HBH_P2_ROLLBACK_CHANGE', '1', 'NUMBER');
ROLLBACK;

CALL hbh_test.chk('audit', 'a change record does NOT survive its rollback',
  $q$ SELECT count(*) = 0 FROM hbh.audit_log
      WHERE new_data ->> 'param_code' = 'HBH_P2_ROLLBACK_CHANGE' $q$);

CALL hbh_test.chk_raises('audit', 'audit_attempt refuses a change action',
  $q$ SELECT hbh.audit_attempt('UPDATE', NULL, 'x', 'y') $q$, 'HB012');

-- =====================================================================
-- 7. THE NULL-KEY RULE, THE OTHER WAY ROUND
--
-- sys_params uses NULLS NOT DISTINCT because NULL there means "global"
-- - a value. Here NULL means "not known yet", and two unknowns are not
-- a duplicate. The fixture already holds two children with no national
-- id; if the wrong index had been chosen, the fixture itself would have
-- failed to build.
-- =====================================================================
CALL hbh_test.chk('unique', 'two children with NO national id both exist',
  $q$ SELECT count(*) = 2 FROM hbh.children
      WHERE child_no IN ('P2-A','P2-B') AND national_id IS NULL $q$);

CALL hbh_test.chk('unique', 'a third child with no national id is still accepted',
  $q$ WITH ins AS (
        INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
        VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
                'P2-D', 'طفل الاختبار د', DATE '2022-01-05', 'F')
        RETURNING 1)
      SELECT count(*) = 1 FROM ins $q$);

CALL hbh_test.chk_raises('unique', 'two children with the SAME national id are refused',
  $q$ INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender, national_id)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
              'P2-E', 'طفل الاختبار هـ', DATE '2019-11-20', 'M', '29911200101234') $q$,
  '23505');

CALL hbh_test.chk_raises('unique', 'two children with the same child_no are refused',
  $q$ INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
              'P2-A', 'مكرر', DATE '2020-03-11', 'M') $q$,
  '23505');

-- =====================================================================
-- 8. USER-VISIBLE NUMBERS
-- =====================================================================
CALL hbh_test.chk('number', 'next_number returns the configured shape',
  $q$ SELECT hbh.next_number((SELECT v FROM hbh_test.fx WHERE k='center'), 'CHILD') ~ '^CH-[0-9]{5}$' $q$);

CALL hbh_test.chk('number', 'a year-bearing series carries the year',
  $q$ SELECT hbh.next_number((SELECT v FROM hbh_test.fx WHERE k='center'), 'INVOICE')
             ~ ('^INV-' || extract(year FROM now() AT TIME ZONE 'UTC')::integer || '-[0-9]{5}$') $q$);

CALL hbh_test.chk('number', 'consecutive calls do not repeat',
  $q$ SELECT hbh.next_number((SELECT v FROM hbh_test.fx WHERE k='center'), 'CHILD')
          <> hbh.next_number((SELECT v FROM hbh_test.fx WHERE k='center'), 'CHILD') $q$);

CALL hbh_test.chk_raises('number', 'an undefined series raises HB010',
  $q$ SELECT hbh.next_number((SELECT v FROM hbh_test.fx WHERE k='center'), 'NO_SUCH_SERIES') $q$,
  'HB010');

-- =====================================================================
-- 9. STRUCTURE
-- =====================================================================

CALL hbh_test.chk('structure', 'RLS is enabled on every table added by 0002',
  $q$ SELECT count(*) = 0 FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'hbh' AND c.relkind = 'r'
        AND c.relname IN ('children','guardians','guardian_children','roles','permissions',
                          'role_permissions','user_roles','otp_codes','auth_sessions','number_series')
        AND NOT c.relrowsecurity $q$);




-- Watching a child in therapy is the most sensitive act in the system.
-- The flag that allows it must default to deny.
CALL hbh_test.chk('structure', 'can_view_live_flg defaults to FALSE',
  $q$ SELECT column_default = 'false' FROM information_schema.columns
      WHERE table_schema = 'hbh' AND table_name = 'guardian_children'
        AND column_name = 'can_view_live_flg' $q$);

-- =====================================================================
-- CLEANUP - a recorded check, not a silent hope
-- =====================================================================
CALL hbh_test.chk('cleanup', 'guardian links removed',
  $q$ WITH d AS (DELETE FROM hbh.guardian_children gc
                 USING hbh.children c
                 WHERE c.child_id = gc.child_id AND c.child_no LIKE 'P2-%' RETURNING 1)
      SELECT count(*) = 2 FROM d $q$);

CALL hbh_test.chk('cleanup', 'test children removed',
  $q$ WITH d AS (DELETE FROM hbh.children WHERE child_no LIKE 'P2-%' RETURNING 1)
      SELECT count(*) = 4 FROM d $q$);

CALL hbh_test.chk('cleanup', 'test guardians removed',
  $q$ WITH d AS (DELETE FROM hbh.guardians WHERE mobile LIKE '+2010000000%' AND user_id IN (SELECT user_id FROM hbh.users WHERE username LIKE 'p2.%') RETURNING 1)
      SELECT count(*) = 2 FROM d $q$);

CALL hbh_test.chk('cleanup', 'test sessions and codes removed',
  $q$ WITH a AS (DELETE FROM hbh.auth_sessions WHERE user_id IN
                   (SELECT user_id FROM hbh.users WHERE username LIKE 'p2.%') RETURNING 1),
           o AS (DELETE FROM hbh.otp_codes WHERE user_id IN
                   (SELECT user_id FROM hbh.users WHERE username LIKE 'p2.%') RETURNING 1)
      SELECT (SELECT count(*) FROM a) >= 1 AND (SELECT count(*) FROM o) >= 3 $q$);

CALL hbh_test.chk('cleanup', 'test roles and users removed',
  $q$ WITH r AS (DELETE FROM hbh.user_roles WHERE user_id IN
                   (SELECT user_id FROM hbh.users WHERE username LIKE 'p2.%') RETURNING 1),
           u AS (DELETE FROM hbh.users WHERE username LIKE 'p2.%' RETURNING 1)
      SELECT (SELECT count(*) FROM r) = 3 AND (SELECT count(*) FROM u) = 3 $q$);

CALL hbh_test.chk('cleanup', 'probe parameters removed',
  $q$ WITH d AS (DELETE FROM hbh.sys_params WHERE param_code LIKE 'HBH_P2_%' RETURNING 1)
      SELECT count(*) = 0 FROM d $q$);

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
    RAISE NOTICE '  PHASE 2 ACCEPTED';
  ELSE
    RAISE NOTICE '  *** PHASE 2 NOT ACCEPTED';
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
