-- =====================================================================
-- Hand By Hand (new) - API phase 10 fixture: the last uncovered routes
--
-- TWO FAMILIES AND TWO CHILDREN, for the same reason as phase 9: half
-- these routes take an identifier in the path, and a fixture with one
-- family cannot tell "reads their own child" from "reads any child".
--
-- FOUR ACCOUNTS:
--
--   a10_admin      CENTER_ADMIN - USER.MANAGE, STAFF.MANAGE, ATTACHMENT.UPLOAD
--   a10_therapist  THERAPIST    - holds none of those three. Staff, in the
--                                 same centre, so a refusal cannot be read
--                                 as "guardians are refused".
--   a10_parent1    GUARDIAN     - the child under test
--   a10_parent2    GUARDIAN     - the family that must not reach them
--
-- NO PHOTO, NO CONSENT AND NO SETUP CODE ARE CREATED. All three are
-- what the suite writes, and a fixture that pre-made them would let the
-- gate checks pass on rows the product never produced.
-- =====================================================================

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS a10_fx;
CREATE TEMP TABLE a10_fx (k text PRIMARY KEY, v integer);

INSERT INTO a10_fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO a10_fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile, status)
SELECT (SELECT v FROM a10_fx WHERE k='center'), (SELECT v FROM a10_fx WHERE k='branch'),
       u.username, u.name, u.utype, u.mobile, 'ACTIVE'
FROM (VALUES
       ('a10_admin',     'مديرة المركز — عشرة',    'STAFF',     '+201500000290'),
       ('a10_therapist', 'أخصائية — عشرة',         'THERAPIST', '+201500000291'),
       ('a10_parent1',   'وليّ الأمر الأول — عشرة', 'GUARDIAN',  '+201500000292'),
       ('a10_parent2',   'وليّ الأمر الثاني — عشرة','GUARDIAN',  '+201500000293')
     ) AS u(username, name, utype, mobile);

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT u.user_id, r.role_id
FROM   hbh.users u JOIN hbh.roles r ON r.center_id = u.center_id
WHERE (u.username = 'a10_admin'     AND r.code = 'CENTER_ADMIN')
   OR (u.username = 'a10_therapist' AND r.code = 'THERAPIST')
   OR (u.username IN ('a10_parent1','a10_parent2') AND r.code = 'GUARDIAN');

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
SELECT u.center_id, u.branch_id, u.user_id, u.full_name_ar, u.mobile
FROM   hbh.users u WHERE u.username IN ('a10_parent1', 'a10_parent2');

INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
SELECT (SELECT v FROM a10_fx WHERE k='center'), (SELECT v FROM a10_fx WHERE k='branch'),
       c.no, c.name, DATE '2020-07-07', 'M'
FROM (VALUES ('A10-A','طفل الأسرة الأولى'), ('A10-B','طفل الأسرة الثانية')) AS c(no, name);

INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
SELECT g.guardian_id, c.child_id, 'FATHER', true
FROM   hbh.users u
JOIN   hbh.guardians g ON g.user_id = u.user_id
JOIN   hbh.children  c ON c.child_no = CASE u.username WHEN 'a10_parent1' THEN 'A10-A' ELSE 'A10-B' END
WHERE  u.username IN ('a10_parent1', 'a10_parent2');

SELECT set_config('hbh.user_id', 'a10_admin', false);
SELECT hbh.set_password((SELECT user_id FROM hbh.users WHERE username='a10_admin'),     'a10-admin-pw-123456');
SELECT hbh.set_password((SELECT user_id FROM hbh.users WHERE username='a10_therapist'), 'a10-therapist-pw-123456');
SELECT set_config('hbh.user_id', '', false);

DO $assert$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM hbh.users WHERE username LIKE 'a10\_%';
  IF n <> 4 THEN RAISE EXCEPTION 'fixture: expected 4 accounts, found %', n; END IF;

  -- EVERY MOBILE IS THIS FIXTURE'S OWN. Migration 0098 now enforces it
  -- with a unique index, so a collision fails at INSERT rather than
  -- here - but the check stays, because it names the reason. Before the
  -- index, four reused numbers were accepted silently and the login code
  -- for one account signed in as another.
  SELECT count(*) INTO n
  FROM   hbh.users a JOIN hbh.users b ON b.mobile = a.mobile AND b.user_id <> a.user_id
  WHERE  a.username LIKE 'a10\_%' AND b.active_flg;
  IF n <> 0 THEN RAISE EXCEPTION 'fixture: a mobile is held by another account too'; END IF;

  SELECT count(*) INTO n FROM hbh.users
   WHERE username IN ('a10_admin','a10_therapist') AND password_hash IS NOT NULL;
  IF n <> 2 THEN RAISE EXCEPTION 'fixture: a staff password was not set (% of 2)', n; END IF;

  -- The administrator must hold all three gates this suite opens.
  SELECT count(DISTINCT p.code) INTO n
  FROM   hbh.users u
  JOIN   hbh.user_roles ur       ON ur.user_id = u.user_id
  JOIN   hbh.role_permissions rp ON rp.role_id = ur.role_id AND rp.active_flg
  JOIN   hbh.permissions p       ON p.permission_id = rp.permission_id
  WHERE  u.username = 'a10_admin'
    AND  p.code IN ('USER.MANAGE','STAFF.MANAGE','ATTACHMENT.UPLOAD');
  IF n <> 3 THEN RAISE EXCEPTION 'fixture: a10_admin is missing one of the three gates (% of 3)', n; END IF;

  -- And the therapist must hold NEITHER of the two admin ones, or every
  -- refusal below passes for a reason the suite is not testing.
  SELECT count(*) INTO n
  FROM   hbh.users u
  JOIN   hbh.user_roles ur       ON ur.user_id = u.user_id
  JOIN   hbh.role_permissions rp ON rp.role_id = ur.role_id AND rp.active_flg
  JOIN   hbh.permissions p       ON p.permission_id = rp.permission_id
  WHERE  u.username = 'a10_therapist'
    AND  p.code IN ('USER.MANAGE','STAFF.MANAGE');
  IF n <> 0 THEN RAISE EXCEPTION 'fixture: a10_therapist holds an admin right - the refusals prove nothing'; END IF;

  -- Two families, same centre, different children.
  SELECT count(*) INTO n FROM hbh.guardian_children gc
   JOIN hbh.children c ON c.child_id = gc.child_id WHERE c.child_no LIKE 'A10-%';
  IF n <> 2 THEN RAISE EXCEPTION 'fixture: expected 2 guardian links, found %', n; END IF;

  -- Nothing pre-made. All three are what the suite writes.
  SELECT count(*) INTO n FROM hbh.attachments a
   JOIN hbh.children c ON c.child_id = a.child_id WHERE c.child_no LIKE 'A10-%';
  IF n <> 0 THEN RAISE EXCEPTION 'fixture: % attachment(s) already exist', n; END IF;

  SELECT count(*) INTO n FROM hbh.consents c
   JOIN hbh.guardians g ON g.guardian_id = c.guardian_id
   JOIN hbh.users u ON u.user_id = g.user_id WHERE u.username LIKE 'a10\_%';
  IF n <> 0 THEN RAISE EXCEPTION 'fixture: % consent(s) already exist - the photo gate would open on a row the product did not write', n; END IF;

  SELECT count(*) INTO n FROM hbh.password_setups p
   JOIN hbh.users u ON u.user_id = p.user_id WHERE u.username LIKE 'a10\_%';
  IF n <> 0 THEN RAISE EXCEPTION 'fixture: % setup code(s) already exist', n; END IF;
END
$assert$;

\echo 'fixture a10: ready'
