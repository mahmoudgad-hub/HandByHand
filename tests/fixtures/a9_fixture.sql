-- =====================================================================
-- Hand By Hand (new) - API phase 9 fixture: the ten uncovered routes
--
-- TWO FAMILIES, and the second is the whole point.
--
-- The routes this suite covers are indexed by GUARDIAN ID, which travels
-- in the path. A fixture with one family cannot tell "a parent reads
-- their own thread" from "a parent reads any thread" - both look green.
-- The second family is what makes the isolation check mean something,
-- and it must be a REAL family of the same centre: a stranger from
-- another centre is refused by the centre check long before the rule
-- under test is reached.
--
-- FOUR ACCOUNTS:
--
--   a9_admin      CENTER_ADMIN - REQUEST.MANAGE, BILLING.VIEW, SITE.EDIT
--   a9_therapist  THERAPIST    - holds NONE of those three. The negative
--                                subject for every gate in the suite,
--                                and staff, so a refusal cannot be
--                                mistaken for "guardians are refused".
--   a9_parent1    GUARDIAN     - the thread under test
--   a9_parent2    GUARDIAN     - the family that must not see it
--
-- NO MESSAGES AND NO CONSENTS ARE CREATED. Sending is under test, and a
-- consent written here would make the grant check pass on a row it did
-- not write. The assertions at the bottom prove both are absent rather
-- than assuming it - a previous run interrupted between its write and
-- its teardown leaves exactly that state behind.
-- =====================================================================

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS a9_fx;
CREATE TEMP TABLE a9_fx (k text PRIMARY KEY, v integer);

INSERT INTO a9_fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO a9_fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile, status)
SELECT (SELECT v FROM a9_fx WHERE k='center'), (SELECT v FROM a9_fx WHERE k='branch'),
       u.username, u.name, u.utype, u.mobile, 'ACTIVE'
FROM (VALUES
       ('a9_admin',     'مديرة المركز — تسعة',   'STAFF',     '+201500000190'),
       ('a9_therapist', 'أخصائية — تسعة',        'THERAPIST', '+201500000191'),
       ('a9_parent1',   'وليّ الأمر الأول — تسعة','GUARDIAN',  '+201500000192'),
       ('a9_parent2',   'وليّ الأمر الثاني — تسعة','GUARDIAN', '+201500000193')
     ) AS u(username, name, utype, mobile);

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT u.user_id, r.role_id
FROM   hbh.users u JOIN hbh.roles r ON r.center_id = u.center_id
WHERE (u.username = 'a9_admin'     AND r.code = 'CENTER_ADMIN')
   OR (u.username = 'a9_therapist' AND r.code = 'THERAPIST')
   OR (u.username IN ('a9_parent1','a9_parent2') AND r.code = 'GUARDIAN');

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
SELECT u.center_id, u.branch_id, u.user_id, u.full_name_ar, u.mobile
FROM   hbh.users u WHERE u.username IN ('a9_parent1', 'a9_parent2');

INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
SELECT (SELECT v FROM a9_fx WHERE k='center'), (SELECT v FROM a9_fx WHERE k='branch'),
       c.no, c.name, DATE '2020-05-05', 'F'
FROM (VALUES ('A9-A','طفلة الأسرة الأولى'), ('A9-B','طفلة الأسرة الثانية')) AS c(no, name);

INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
SELECT g.guardian_id, c.child_id, 'MOTHER', true
FROM   hbh.users u
JOIN   hbh.guardians g ON g.user_id = u.user_id
JOIN   hbh.children  c ON c.child_no = CASE u.username WHEN 'a9_parent1' THEN 'A9-A' ELSE 'A9-B' END
WHERE  u.username IN ('a9_parent1', 'a9_parent2');

SELECT set_config('hbh.user_id', 'a9_admin', false);
SELECT hbh.set_password((SELECT user_id FROM hbh.users WHERE username='a9_admin'),     'a9-admin-pw-123456');
SELECT hbh.set_password((SELECT user_id FROM hbh.users WHERE username='a9_therapist'), 'a9-therapist-pw-123456');
SELECT set_config('hbh.user_id', '', false);

DO $assert$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM hbh.users WHERE username LIKE 'a9\_%';
  IF n <> 4 THEN RAISE EXCEPTION 'fixture: expected 4 accounts, found %', n; END IF;

  SELECT count(*) INTO n FROM hbh.guardians g JOIN hbh.users u ON u.user_id = g.user_id
   WHERE u.username LIKE 'a9\_%';
  IF n <> 2 THEN RAISE EXCEPTION 'fixture: expected 2 guardian rows, found %', n; END IF;

  SELECT count(*) INTO n FROM hbh.users
   WHERE username IN ('a9_admin','a9_therapist') AND password_hash IS NOT NULL;
  IF n <> 2 THEN RAISE EXCEPTION 'fixture: a staff password was not set (% of 2)', n; END IF;

  -- The administrator must HOLD all three gates the suite opens.
  SELECT count(DISTINCT p.code) INTO n
  FROM   hbh.users u
  JOIN   hbh.user_roles ur       ON ur.user_id = u.user_id
  JOIN   hbh.role_permissions rp ON rp.role_id = ur.role_id
  JOIN   hbh.permissions p       ON p.permission_id = rp.permission_id
  WHERE  u.username = 'a9_admin'
    AND  p.code IN ('REQUEST.MANAGE','BILLING.VIEW','SITE.EDIT');
  IF n <> 3 THEN RAISE EXCEPTION 'fixture: a9_admin is missing one of the three gates (% of 3)', n; END IF;

  -- And the therapist must hold NONE of them, or every refusal in this
  -- suite passes for a reason the suite is not testing.
  SELECT count(*) INTO n
  FROM   hbh.users u
  JOIN   hbh.user_roles ur       ON ur.user_id = u.user_id
  JOIN   hbh.role_permissions rp ON rp.role_id = ur.role_id
  JOIN   hbh.permissions p       ON p.permission_id = rp.permission_id
  WHERE  u.username = 'a9_therapist'
    AND  p.code IN ('REQUEST.MANAGE','BILLING.VIEW','SITE.EDIT');
  IF n <> 0 THEN RAISE EXCEPTION 'fixture: a9_therapist holds one of the three gates - the refusals prove nothing'; END IF;

  -- EVERY MOBILE THIS FIXTURE WRITES MUST BE ITS OWN, and the check is
  -- here because the first draft of this file failed it.
  --
  -- hbh.users has NO unique index on mobile, and hbh.request_otp resolves
  -- a login by `WHERE mobile = $1 ORDER BY user_id LIMIT 1` - the OLDEST
  -- account wins. So four numbers that were already held by the dev seed
  -- accounts were accepted without a word, and the code sent to
  -- a9_parent1's number logged in as dev_therapist instead: staff, a
  -- different centre role, a different person. Nothing raised, nothing
  -- logged, and the isolation checks below would have been asserting
  -- against the wrong caller entirely.
  SELECT count(*) INTO n
  FROM   hbh.users a
  JOIN   hbh.users b ON b.mobile = a.mobile AND b.user_id <> a.user_id
  WHERE  a.username LIKE 'a9\_%' AND b.active_flg;
  IF n <> 0 THEN RAISE EXCEPTION 'fixture: % of this fixture''s mobiles are already held by another account - OTP would sign in as somebody else', n; END IF;

  -- The two families must be DIFFERENT guardians of the SAME centre.
  SELECT count(DISTINCT g.center_id) INTO n FROM hbh.guardians g
   JOIN hbh.users u ON u.user_id = g.user_id WHERE u.username LIKE 'a9\_parent%';
  IF n <> 1 THEN RAISE EXCEPTION 'fixture: the two families are not in one centre - the isolation check would pass on the centre rule'; END IF;

  -- No thread and no consent yet. Both are what the suite writes.
  SELECT count(*) INTO n FROM hbh.family_messages m
   JOIN hbh.guardians g ON g.guardian_id = m.guardian_id
   JOIN hbh.users u ON u.user_id = g.user_id WHERE u.username LIKE 'a9\_%';
  IF n <> 0 THEN RAISE EXCEPTION 'fixture: % message(s) already exist - the send checks would start mid-thread', n; END IF;

  SELECT count(*) INTO n FROM hbh.consents c
   JOIN hbh.guardians g ON g.guardian_id = c.guardian_id
   JOIN hbh.users u ON u.user_id = g.user_id WHERE u.username LIKE 'a9\_%';
  IF n <> 0 THEN RAISE EXCEPTION 'fixture: % consent(s) already exist', n; END IF;
END
$assert$;

\echo 'fixture a9: ready'
