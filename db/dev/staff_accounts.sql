-- =====================================================================
-- Hand By Hand (new) - DEVELOPMENT staff accounts
--
-- READ THIS BEFORE MOVING THE FILE.
--
-- It is in db/dev/ and NOT in db/seed/, and that is the whole safety
-- design. scripts/db.sh migrate runs every file in db/seed/ - so a
-- staff account with a password placed there would be created on every
-- database this project is ever installed on, production included, with
-- a password written in a file in the repository. That is not a seed,
-- it is a door.
--
-- Nothing runs this file automatically. It is invoked by hand:
--
--   DEV_STAFF_PASSWORD='something long' bash scripts/db.sh dev-user
--
-- THE PASSWORD IS NOT IN THIS FILE and there is no default. psql
-- refuses to run a script whose variable is unset, so the failure mode
-- of "somebody ran it without thinking" is an error, not an account
-- with a password everybody knows.
--
-- Four accounts, because one proves nothing about the interface:
--
--   dev_admin       CENTER_ADMIN - the catalogue, staff, cameras, billing
--   dev_reception   RECEPTION    - children and appointments, and NOT
--                                 the catalogue
--   dev_therapist   THERAPIST    - owns sessions
--   dev_therapist2  THERAPIST    - owns none, and speaks English
--
-- A console tested only as an administrator hides every permission bug
-- it has. Reception is how the operations app finds out whether it
-- draws its menu from /me or from a map somebody copied.
--
-- THE SECOND THERAPIST IS NOT A SPARE. Two things need her, and neither
-- can be reached with one:
--
--   A colleague who HOLDS a clinical right and does NOT own the session
--   is the only fixture that tells "you may not edit another therapist's
--   note" apart from "you have no such right". With one therapist - who
--   is always the owner - the second case cannot be constructed, so any
--   error code passes and the check stays green the day somebody narrows
--   the THERAPIST role.
--
--   And she is the centre as it really is: the owner describes one
--   specialist who speaks English and therefore takes every
--   international-school child (docs/06). One therapist cannot show a
--   diary where language decides who gets the referral.
--
-- Idempotent: re-running it resets the passwords and changes nothing
-- else.
-- =====================================================================

\set ON_ERROR_STOP on

-- psql does NOT substitute its variables inside a dollar-quoted block,
-- so this guard cannot be a DO block and the length rule lives in
-- scripts/db.sh where the value comes from. What this catches is the
-- other mistake: running the file directly with no variable at all,
-- which would otherwise interpolate an empty password.
\if :{?staff_password}
\else
\echo 'staff_password is not set - run: DEV_STAFF_PASSWORD=... bash scripts/db.sh dev-user'
\quit
\endif

-- user_type IS NOT DECORATION, and giving all four 'STAFF' quietly broke
-- the one rule that separates a clinician from an administrator.
--
-- hbh.can_close_session - and hbh.can_start_session after it - grant an
-- administrative override to `user_type = 'STAFF'` holding both rights.
-- The THERAPIST role holds CHILD.VIEW_ALL (to cover a colleague) and the
-- clinical right, so the ONLY thing keeping one therapist out of another
-- therapist's session is that a clinician is user_type 'THERAPIST' and
-- not 'STAFF'. Created as STAFF, both dev therapists matched the
-- administrative branch and could start and close each other's sessions.
--
-- Caught by the C1 scenario "therapist starts a colleague's session",
-- which is meant to be refused and was not. The rule was right; this
-- fixture was describing a centre that does not exist. The acceptance
-- fixtures had it right all along - tests/fixtures create pa.therapist
-- as user_type 'THERAPIST' - which is why the suite never saw it.
INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile, status)
SELECT c.center_id, b.branch_id, u.username, u.name, u.kind, u.mobile, 'ACTIVE'
FROM   hbh.centers c
JOIN   hbh.branches b ON b.center_id = c.center_id AND b.code = 'MAIN'
CROSS  JOIN (VALUES
        ('dev_admin',      'مديرة المركز — تطوير',      '+201500000090', 'STAFF'),
        ('dev_reception',  'الاستقبال — تطوير',         '+201500000091', 'STAFF'),
        ('dev_therapist',  'الأخصائي — تطوير',           '+201500000092', 'THERAPIST'),
        ('dev_therapist2', 'أخصائية اللغات — تطوير',    '+201500000094', 'THERAPIST')
      ) AS u(username, name, mobile, kind)
WHERE  c.code = 'HBH'
AND NOT EXISTS (SELECT 1 FROM hbh.users x WHERE lower(x.username) = u.username);

-- Idempotent for a database that already has them as STAFF: the insert
-- above skips existing rows, so without this the wrong value survives
-- every re-run of this file.
UPDATE hbh.users SET user_type = 'THERAPIST'
WHERE  username IN ('dev_therapist', 'dev_therapist2')
AND    user_type <> 'THERAPIST';

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT u.user_id, r.role_id
FROM   hbh.users u
JOIN   hbh.roles r ON r.center_id = u.center_id
WHERE (u.username = 'dev_admin'      AND r.code = 'CENTER_ADMIN')
   OR (u.username = 'dev_reception'  AND r.code = 'RECEPTION')
   OR (u.username = 'dev_therapist'  AND r.code = 'THERAPIST')
   OR (u.username = 'dev_therapist2' AND r.code = 'THERAPIST')
ON CONFLICT (user_id, role_id) DO NOTHING;

-- A therapists row for each therapist account, or the account is a role
-- with nobody behind it: caseload, appointments and sessions all point
-- at a therapist_id, not at a user, so without this the account can sign
-- in and then appear in no diary and own no session.
INSERT INTO hbh.therapists (center_id, branch_id, user_id, full_name_ar, title_ar)
SELECT u.center_id, u.branch_id, u.user_id, u.full_name_ar,
       CASE u.username WHEN 'dev_therapist2' THEN 'أخصائية تخاطب وأكاديمي'
                       ELSE 'أخصائي' END
FROM   hbh.users u
WHERE  u.username IN ('dev_therapist', 'dev_therapist2')
AND NOT EXISTS (SELECT 1 FROM hbh.therapists t WHERE t.user_id = u.user_id);

-- hbh.set_password needs USER.MANAGE, so the seeded administrator acts.
-- Writing to password_hash directly would skip the hashing the function
-- exists to perform.
SELECT set_config('hbh.user_id', 'admin', false);

SELECT hbh.set_password(u.user_id, :'staff_password')
FROM   hbh.users u WHERE u.username IN ('dev_admin', 'dev_reception', 'dev_therapist', 'dev_therapist2');

SELECT set_config('hbh.user_id', '', false);

DO $verify$
DECLARE n integer;
BEGIN
  -- count(DISTINCT u.user_id), not count(*): this counts ACCOUNTS and the
  -- join multiplies by role rows. dev_reception carries a spent THERAPIST
  -- assignment alongside its live RECEPTION one, so count(*) returned 5,
  -- the check raised, and the whole file - single-transaction - rolled
  -- back. Four passwords were set and then silently discarded, and the
  -- error blamed the account count rather than the join.
  SELECT count(DISTINCT u.user_id) INTO n
  FROM   hbh.users u
  JOIN   hbh.user_roles ur ON ur.user_id = u.user_id AND ur.active_flg
  WHERE  u.username IN ('dev_admin','dev_reception','dev_therapist','dev_therapist2')
  AND    u.password_hash IS NOT NULL
  AND    u.status = 'ACTIVE';
  IF n <> 4 THEN
    RAISE EXCEPTION 'expected 4 usable development accounts, found %', n;
  END IF;
END
$verify$;

\echo ''
\echo 'development accounts ready:  dev_admin (CENTER_ADMIN)  ·  dev_reception (RECEPTION)  ·  dev_therapist (THERAPIST)  ·  dev_therapist2 (THERAPIST)'
\echo 'sign in at POST /api/v1/auth/staff/login'
\echo ''
\echo 'dev_therapist2 owns no session on purpose.  She is how a refusal for'
\echo '"not your session" is told apart from a refusal for "no such right".'
\echo 'Her languages and her diary are built by:  bash scripts/db.sh dev-family'
